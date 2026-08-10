import Foundation
import SayItCore
import Testing
@testable import SayItBackend

@Suite("OpenAI-compatible speech synthesizer")
struct OpenAICompatibleSpeechSynthesizerTests {
    @Test("Posts speech request with bearer token and yields decoded audio")
    func synthesizesWithMockSession() async throws {
        let wav = try makeSilentWAV(sampleRate: 24_000, frames: 2400)
        nonisolated(unsafe) var capturedRequest: URLRequest?

        let synthesizer = OpenAICompatibleSpeechSynthesizer(
            apiKeyProvider: { "secret-token" },
            session: { request in
                capturedRequest = request
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "audio/wav"]
                )!
                return (wav, response)
            }
        )

        await synthesizer.updateRemoteConfiguration(
            RemoteTTSConfiguration(
                enabled: true,
                baseURL: URL(string: "https://tts.example/v1"),
                model: "remote-model",
                voice: "alloy",
                timeoutSeconds: 45
            )
        )

        let request = SpeechRequest(
            cleanedText: CleanedText(
                text: "Hello from Say It",
                title: "Hello",
                detectedLanguage: "en",
                cleanupSummary: .empty,
                requiresLongTextConfirmation: false
            ),
            model: try sampleModel(),
            voice: "local-voice",
            language: "en",
            source: .frontend
        )

        var events: [SynthesisEvent] = []
        let stream = await synthesizer.synthesize(request)
        for try await event in stream {
            events.append(event)
        }

        let sent = try #require(capturedRequest)
        #expect(sent.httpMethod == "POST")
        #expect(
            sent.url?.absoluteString == "https://tts.example/v1/audio/speech"
        )
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(sent.timeoutInterval == 45)

        let body = try JSONSerialization.jsonObject(
            with: try #require(sent.httpBody)
        ) as? [String: Any]
        #expect(body?["model"] as? String == "remote-model")
        #expect(body?["input"] as? String == "Hello from Say It")
        #expect(body?["voice"] as? String == "local-voice")
        #expect(body?["response_format"] as? String == "wav")
        #expect(body?.keys.contains("format") != true)

        #expect(events.contains { if case .completed = $0 { true } else { false } })
        let audioEvents = events.compactMap { event -> AudioChunk? in
            if case .audio(let chunk) = event { return chunk }
            return nil
        }
        #expect(audioEvents.count == 1)
        #expect(audioEvents[0].samples.isEmpty == false)
        #expect(audioEvents[0].sampleRate == 24_000)
    }

    @Test("Maps unauthorized responses to a clear error")
    func unauthorized() async throws {
        let synthesizer = OpenAICompatibleSpeechSynthesizer(
            apiKeyProvider: { "bad" },
            session: { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data("nope".utf8), response)
            }
        )
        await synthesizer.updateRemoteConfiguration(
            RemoteTTSConfiguration(
                enabled: true,
                baseURL: URL(string: "https://tts.example/v1"),
                model: "m",
                voice: "v",
                timeoutSeconds: 30
            )
        )

        let request = SpeechRequest(
            cleanedText: CleanedText(
                text: "Hi",
                title: "Hi",
                detectedLanguage: nil,
                cleanupSummary: .empty,
                requiresLongTextConfirmation: false
            ),
            model: try sampleModel(),
            voice: nil,
            language: nil,
            source: .frontend
        )

        let stream = await synthesizer.synthesize(request)
        do {
            for try await _ in stream {}
            Issue.record("Expected unauthorized failure")
        } catch let error as SynthesisError {
            guard case .remoteTTSUnauthorized = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
        }
    }

    @Test("Rejects incomplete remote configuration before transport")
    func invalidConfiguration() async throws {
        let synthesizer = OpenAICompatibleSpeechSynthesizer(
            apiKeyProvider: { nil },
            session: { _ in
                Issue.record("Session should not run")
                throw URLError(.badURL)
            }
        )
        await synthesizer.updateRemoteConfiguration(.disabled)

        let request = SpeechRequest(
            cleanedText: CleanedText(
                text: "Hi",
                title: "Hi",
                detectedLanguage: nil,
                cleanupSummary: .empty,
                requiresLongTextConfirmation: false
            ),
            model: try sampleModel(),
            voice: nil,
            language: nil,
            source: .frontend
        )
        let stream = await synthesizer.synthesize(request)
        do {
            for try await _ in stream {}
            Issue.record("Expected configuration failure")
        } catch let error as SynthesisError {
            guard case .remoteTTSInvalidConfiguration = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
        }
    }


    @Test("Prefers request voice and encodes speaking pace")
    func prefersRequestVoiceAndSpeed() async throws {
        let wav = try makeSilentWAV(sampleRate: 24_000, frames: 2_400)
        nonisolated(unsafe) var body: [String: Any]?
        let synthesizer = OpenAICompatibleSpeechSynthesizer(
            apiKeyProvider: { nil },
            session: { request in
                body = try JSONSerialization.jsonObject(
                    with: try #require(request.httpBody)
                ) as? [String: Any]
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "audio/wav"]
                )!
                return (wav, response)
            }
        )
        await synthesizer.updateRemoteConfiguration(
            RemoteTTSConfiguration(
                enabled: true,
                baseURL: URL(string: "https://tts.example/v1"),
                model: "remote-model",
                voice: "default-voice",
                timeoutSeconds: 30
            )
        )
        let request = SpeechRequest(
            cleanedText: CleanedText(
                text: "Hello pace",
                title: "Hello",
                detectedLanguage: "en",
                cleanupSummary: .empty,
                requiresLongTextConfirmation: false
            ),
            model: try sampleModel(),
            voice: "request-voice",
            language: "en",
            speakingPace: .fast,
            source: .frontend
        )
        for try await _ in await synthesizer.synthesize(request) {}
        let sent = try #require(body)
        #expect(sent["voice"] as? String == "request-voice")
        #expect(sent["speed"] as? Double == SpeakingPace.fast.rawValue)
    }

    @Test("Chunks long text into multiple remote requests")
    func chunksLongText() async throws {
        let wav = try makeSilentWAV(sampleRate: 24_000, frames: 2_400)
        nonisolated(unsafe) var inputs: [String] = []
        let synthesizer = OpenAICompatibleSpeechSynthesizer(
            apiKeyProvider: { nil },
            session: { request in
                let body = try JSONSerialization.jsonObject(
                    with: try #require(request.httpBody)
                ) as? [String: Any]
                inputs.append(body?["input"] as? String ?? "")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "audio/wav"]
                )!
                return (wav, response)
            }
        )
        await synthesizer.updateRemoteConfiguration(
            RemoteTTSConfiguration(
                enabled: true,
                baseURL: URL(string: "https://tts.example/v1"),
                model: "remote-model",
                voice: "alloy",
                timeoutSeconds: 30
            )
        )
        await synthesizer.updateConfiguration(
            chunkTarget: 40,
            chunkDelay: 0,
            paragraphPause: 0,
            idleUnloadDelay: 0
        )
        let text = Array(repeating: "This is a sentence about remote speech. ", count: 8)
            .joined()
        let request = SpeechRequest(
            cleanedText: CleanedText(
                text: text,
                title: "Long",
                detectedLanguage: "en",
                cleanupSummary: .empty,
                requiresLongTextConfirmation: false
            ),
            model: try sampleModel(),
            voice: "alloy",
            language: "en",
            source: .frontend
        )
        for try await _ in await synthesizer.synthesize(request) {}
        #expect(inputs.count > 1)
    }

    @Test("Rejects oversized remote responses before decoding")
    func rejectsOversizedResponses() async throws {
        let tooBig = OpenAICompatibleSpeechSynthesizer.maximumResponseBytes + 1
        let synthesizer = OpenAICompatibleSpeechSynthesizer(
            apiKeyProvider: { nil },
            session: { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "audio/wav",
                        "Content-Length": String(tooBig)
                    ]
                )!
                return (Data(count: tooBig), response)
            }
        )
        await synthesizer.updateRemoteConfiguration(
            RemoteTTSConfiguration(
                enabled: true,
                baseURL: URL(string: "https://tts.example/v1"),
                model: "remote-model",
                voice: "alloy",
                timeoutSeconds: 30
            )
        )
        let request = SpeechRequest(
            cleanedText: CleanedText(
                text: "Hi",
                title: "Hi",
                detectedLanguage: nil,
                cleanupSummary: .empty,
                requiresLongTextConfirmation: false
            ),
            model: try sampleModel(),
            voice: nil,
            language: nil,
            source: .frontend
        )
        do {
            for try await _ in await synthesizer.synthesize(request) {}
            Issue.record("Expected oversized response failure")
        } catch let error as SynthesisError {
            guard case .remoteTTSTransport = error else {
                Issue.record("Unexpected oversized-response error")
                return
            }
        }
    }

    private func sampleModel() throws -> ModelDescriptor {
        let catalog = try ModelCatalogLoader().bundledCatalog()
        return try #require(catalog.models.first)
    }

    private func makeSilentWAV(sampleRate: Int, frames: Int) throws -> Data {
        let dataSize = frames * 2
        var data = Data()
        func appendASCII(_ value: String) {
            data.append(contentsOf: value.utf8)
        }
        func appendUInt32(_ value: UInt32) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}

private extension CleanupSummary {
    static var empty: CleanupSummary {
        CleanupSummary(
            sourceFormat: "plain",
            removedCodeBlocks: 0,
            normalizedWhitespace: false
        )
    }
}

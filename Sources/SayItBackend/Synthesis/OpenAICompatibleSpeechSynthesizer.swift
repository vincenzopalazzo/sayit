import Foundation
import SayItCore

/// OpenAI-compatible TTS client (`POST /v1/audio/speech`).
actor OpenAICompatibleSpeechSynthesizer: BackendSpeechSynthesizing {
    typealias APIKeyProvider = @Sendable () async throws -> String?
    typealias DataSession = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Reject oversized remote payloads before they occupy unbounded memory.
    static let maximumResponseBytes = 32 * 1_024 * 1_024

    private var configuration: RemoteTTSConfiguration = .disabled
    private var chunker = TextChunker()
    private let apiKeyProvider: APIKeyProvider
    private let session: DataSession
    private var operationGeneration: UInt64 = 0
    private var activeTask: Task<Void, Never>?

    init(
        apiKeyProvider: @escaping APIKeyProvider,
        session: @escaping DataSession = { request in
            try await OpenAICompatibleSpeechSynthesizer.loadBoundedResponse(
                for: request
            )
        }
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func updateRemoteConfiguration(_ configuration: RemoteTTSConfiguration) {
        self.configuration = configuration
    }

    func updateConfiguration(
        chunkTarget: Int,
        chunkDelay: Double,
        paragraphPause: Double,
        idleUnloadDelay: Double
    ) async {
        _ = chunkDelay
        _ = paragraphPause
        _ = idleUnloadDelay
        let target = max(chunkTarget, 1)
        chunker = TextChunker(
            targetCharacterCount: target,
            hardCharacterLimit: max(target * 2, 1_000)
        )
    }

    func prepareDependencies(for model: ModelDescriptor) async throws {
        _ = model
        try validateConfiguration()
    }

    func cancelCurrentRequest() async {
        operationGeneration &+= 1
        activeTask?.cancel()
        activeTask = nil
    }

    func unloadModel() async {}

    func generateVoiceSample(
        model: ModelDescriptor,
        text: String,
        language: String?,
        tuning: VoiceSynthesisTuning,
        seed: UInt64,
        reference: VoiceReference?
    ) async throws -> GeneratedVoiceSample {
        _ = model
        _ = text
        _ = language
        _ = tuning
        _ = seed
        _ = reference
        throw SynthesisError.remoteTTSUnsupported(
            "Voice Studio is not available with remote OpenAI-compatible TTS."
        )
    }

    func synthesize(
        _ request: SpeechRequest
    ) async -> AsyncThrowingStream<SynthesisEvent, Error> {
        let operationID = beginOperation()
        let (stream, continuation) =
            AsyncThrowingStream<SynthesisEvent, Error>.makeStream()

        let task = Task { [weak self] in
            guard let self else {
                continuation.finish(throwing: CancellationError())
                return
            }
            do {
                try await self.performSynthesis(
                    request,
                    operationID: operationID,
                    continuation: continuation
                )
                continuation.finish()
            } catch is CancellationError {
                continuation.yield(.cancelled)
                continuation.finish(throwing: CancellationError())
            } catch {
                continuation.finish(throwing: error)
            }
            await self.finishOperation(operationID)
        }
        activeTask = task
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return stream
    }

    private func performSynthesis(
        _ request: SpeechRequest,
        operationID: UInt64,
        continuation: AsyncThrowingStream<SynthesisEvent, Error>.Continuation
    ) async throws {
        try checkOperation(operationID)
        try validateConfiguration()

        let modelName = try requiredModelName()
        let modelID = ModelID(modelName)
        continuation.yield(.loadingModel(modelID))
        continuation.yield(.modelLoaded(modelID))

        let text = request.cleanedText.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SynthesisError.remoteTTSInvalidConfiguration("There is no text to speak.")
        }

        // Prefer the per-request voice (CLI/HTTP/submission) over Advanced default.
        let voice = nonEmpty(request.voice) ?? nonEmpty(configuration.voice)
        let chunks = chunker.chunks(for: text)
        guard !chunks.isEmpty else {
            throw SynthesisError.remoteTTSInvalidConfiguration("There is no text to speak.")
        }

        let endpoint = try configuration.speechEndpointURL()
        let startedAt = ContinuousClock.now

        for (index, chunk) in chunks.enumerated() {
            try checkOperation(operationID)
            continuation.yield(.chunkStarted(index: index, chunk: chunk))

            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue(
                "audio/*, application/octet-stream",
                forHTTPHeaderField: "Accept"
            )
            urlRequest.timeoutInterval = max(5, configuration.timeoutSeconds)

            if let apiKey = try await apiKeyProvider() {
                let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty {
                    urlRequest.setValue(
                        "Bearer \(trimmedKey)",
                        forHTTPHeaderField: "Authorization"
                    )
                }
            }

            var body: [String: Any] = [
                "model": modelName,
                "input": chunk.text,
                "response_format": "wav"
            ]
            if let voice {
                body["voice"] = voice
            }
            let speed = request.speakingPace.rawValue
            if abs(speed - 1) > 0.001 {
                body["speed"] = min(max(speed, 0.25), 4)
            }
            urlRequest.httpBody = try JSONSerialization.data(
                withJSONObject: body,
                options: []
            )

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session(urlRequest)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch let error as SynthesisError {
                throw error
            } catch {
                throw SynthesisError.remoteTTSTransport(error.localizedDescription)
            }

            try checkOperation(operationID)
            try validateHTTPResponse(response, data: data)

            let decoded = try await Task.detached(priority: .userInitiated) {
                try RemoteTTSAudioDecoder.decode(data)
            }.value
            try checkOperation(operationID)
            guard decoded.sampleRate > 0, !decoded.samples.isEmpty else {
                throw SynthesisError.remoteTTSInvalidAudio(
                    "The remote audio could not be played."
                )
            }

            let generationDuration = ContinuousClock.now - startedAt
            let audioDuration = Double(decoded.samples.count) / decoded.sampleRate
            continuation.yield(
                .audio(
                    AudioChunk(
                        requestID: request.id,
                        index: index,
                        samples: decoded.samples,
                        sampleRate: decoded.sampleRate,
                        startsParagraph: chunk.startsParagraph
                    )
                )
            )
            continuation.yield(
                .metrics(
                    SynthesisMetrics(
                        chunkIndex: index,
                        generationDuration: generationDuration.timeInterval,
                        audioDuration: audioDuration
                    )
                )
            )
        }

        continuation.yield(.completed)
    }

    private func validateHTTPResponse(
        _ response: URLResponse,
        data: Data
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SynthesisError.remoteTTSTransport(
                "The remote endpoint returned a non-HTTP response."
            )
        }
        let expectedLength = http.expectedContentLength
        if expectedLength >= 0,
           expectedLength > Int64(Self.maximumResponseBytes) {
            throw SynthesisError.remoteTTSTransport(
                "The remote audio response exceeds the supported size limit."
            )
        }
        if data.count > Self.maximumResponseBytes {
            throw SynthesisError.remoteTTSTransport(
                "The remote audio response exceeds the supported size limit."
            )
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = detail.map { String($0.prefix(280)) } ?? ""
            if http.statusCode == 401 || http.statusCode == 403 {
                throw SynthesisError.remoteTTSUnauthorized(
                    summary.isEmpty
                        ? "The remote endpoint rejected the API key."
                        : summary
                )
            }
            throw SynthesisError.remoteTTSHTTPStatus(
                statusCode: http.statusCode,
                detail: summary
            )
        }
    }

    private func requiredModelName() throws -> String {
        guard let model = nonEmpty(configuration.model) else {
            throw SynthesisError.remoteTTSInvalidConfiguration(
                "Enter the remote model id expected by your endpoint."
            )
        }
        return model
    }

    private func validateConfiguration() throws {
        guard configuration.enabled else {
            throw SynthesisError.remoteTTSInvalidConfiguration(
                "Remote TTS is disabled."
            )
        }
        guard configuration.baseURL != nil else {
            throw SynthesisError.remoteTTSInvalidConfiguration(
                "Enter a valid https:// URL, or http:// only for local-network hosts."
            )
        }
        _ = try requiredModelName()
    }

    private func beginOperation() -> UInt64 {
        operationGeneration &+= 1
        activeTask?.cancel()
        activeTask = nil
        return operationGeneration
    }

    private func finishOperation(_ operationID: UInt64) {
        guard operationID == operationGeneration else { return }
        activeTask = nil
    }

    private func checkOperation(_ operationID: UInt64) throws {
        guard operationID == operationGeneration else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func loadBoundedResponse(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            let expectedLength = http.expectedContentLength
            if expectedLength >= 0,
               expectedLength > Int64(maximumResponseBytes) {
                throw SynthesisError.remoteTTSTransport(
                    "The remote audio response exceeds the supported size limit."
                )
            }
        }

        var data = Data()
        data.reserveCapacity(
            min(
                maximumResponseBytes,
                max(0, Int((response as? HTTPURLResponse)?.expectedContentLength ?? 0))
            )
        )
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumResponseBytes {
                throw SynthesisError.remoteTTSTransport(
                    "The remote audio response exceeds the supported size limit."
                )
            }
        }
        return (data, response)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds)
            + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}

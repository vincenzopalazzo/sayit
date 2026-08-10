import Foundation
import SayItCore

/// OpenAI-compatible TTS client (`POST /v1/audio/speech`).
actor OpenAICompatibleSpeechSynthesizer: BackendSpeechSynthesizing {
    typealias APIKeyProvider = @Sendable () async throws -> String?
    typealias DataSession = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private var configuration: RemoteTTSConfiguration = .disabled
    private let apiKeyProvider: APIKeyProvider
    private let session: DataSession
    private var operationGeneration: UInt64 = 0
    private var activeTask: Task<Void, Never>?

    init(
        apiKeyProvider: @escaping APIKeyProvider,
        session: @escaping DataSession = { request in
            try await URLSession.shared.data(for: request)
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
        _ = chunkTarget
        _ = chunkDelay
        _ = paragraphPause
        _ = idleUnloadDelay
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

        let modelName = nonEmpty(configuration.model) ?? request.model.id.rawValue
        let modelID = ModelID(modelName)
        continuation.yield(.loadingModel(modelID))
        continuation.yield(.modelLoaded(modelID))

        let text = request.cleanedText.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SynthesisError.remoteTTSInvalidConfiguration("There is no text to speak.")
        }

        let voice = nonEmpty(configuration.voice) ?? nonEmpty(request.voice)

        let endpoint = try configuration.speechEndpointURL()
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

        // Prefer wav for reliable local decode. Servers that ignore this field
        // and return mp3/other containers are still handled by the decoder.
        var body: [String: Any] = [
            "model": modelName,
            "input": text,
            "response_format": "wav"
        ]
        if let voice {
            body["voice"] = voice
        }
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        try checkOperation(operationID)
        let chunk = SpeechChunk(
            id: 0,
            text: text,
            startsParagraph: true,
            sourceRange: 0..<text.count
        )
        continuation.yield(.chunkStarted(index: 0, chunk: chunk))

        let startedAt = ContinuousClock.now
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session(urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SynthesisError.remoteTTSTransport(error.localizedDescription)
        }

        try checkOperation(operationID)

        guard let http = response as? HTTPURLResponse else {
            throw SynthesisError.remoteTTSTransport(
                "The remote endpoint returned a non-HTTP response."
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

        let decoded = try RemoteTTSAudioDecoder.decode(data)
        try checkOperation(operationID)
        guard decoded.sampleRate > 0, !decoded.samples.isEmpty else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio could not be played."
            )
        }

        let generationDuration = ContinuousClock.now - startedAt
        let audioDuration = Double(decoded.samples.count) / decoded.sampleRate

        let audio = AudioChunk(
            requestID: request.id,
            index: 0,
            samples: decoded.samples,
            sampleRate: decoded.sampleRate,
            startsParagraph: true
        )
        continuation.yield(.audio(audio))
        continuation.yield(
            .metrics(
                SynthesisMetrics(
                    chunkIndex: 0,
                    generationDuration: generationDuration.timeInterval,
                    audioDuration: audioDuration
                )
            )
        )
        continuation.yield(.completed)
    }

    private func validateConfiguration() throws {
        guard configuration.enabled else {
            throw SynthesisError.remoteTTSInvalidConfiguration(
                "Remote TTS is disabled."
            )
        }
        guard configuration.baseURL != nil else {
            throw SynthesisError.remoteTTSInvalidConfiguration(
                "Enter a valid http(s) base URL for the OpenAI-compatible endpoint."
            )
        }
        guard nonEmpty(configuration.model) != nil else {
            throw SynthesisError.remoteTTSInvalidConfiguration(
                "Enter the remote model id expected by your endpoint."
            )
        }
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
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds)
            + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}

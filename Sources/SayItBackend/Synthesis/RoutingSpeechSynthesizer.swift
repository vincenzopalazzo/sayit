import Foundation
import SayItCore

/// Routes synthesis to local MLX or a remote OpenAI-compatible endpoint.
actor RoutingSpeechSynthesizer: BackendSpeechSynthesizing {
    private let local: any BackendSpeechSynthesizing
    private let remote: OpenAICompatibleSpeechSynthesizer
    private var remoteEnabled = false
    /// Serializes configuration updates so remote settings cannot apply out of order.
    private var configurationChain: Task<Void, Never> = Task {}
    private var configurationGeneration: UInt64 = 0

    init(
        local: any BackendSpeechSynthesizing,
        remote: OpenAICompatibleSpeechSynthesizer
    ) {
        self.local = local
        self.remote = remote
    }

    func updateRemoteConfiguration(_ configuration: RemoteTTSConfiguration) async {
        configurationGeneration &+= 1
        let generation = configurationGeneration
        let previous = configurationChain
        let task = Task { [remote] in
            await previous.value
            await remote.updateRemoteConfiguration(configuration)
        }
        configurationChain = task
        await task.value
        guard generation == configurationGeneration else { return }
        remoteEnabled = configuration.enabled
    }

    func updateConfiguration(
        chunkTarget: Int,
        chunkDelay: Double,
        paragraphPause: Double,
        idleUnloadDelay: Double
    ) async {
        await local.updateConfiguration(
            chunkTarget: chunkTarget,
            chunkDelay: chunkDelay,
            paragraphPause: paragraphPause,
            idleUnloadDelay: idleUnloadDelay
        )
        await remote.updateConfiguration(
            chunkTarget: chunkTarget,
            chunkDelay: chunkDelay,
            paragraphPause: paragraphPause,
            idleUnloadDelay: idleUnloadDelay
        )
    }

    func prepareDependencies(for model: ModelDescriptor) async throws {
        await configurationChain.value
        // Local install/import always prepares the MLX model. Remote mode only
        // validates endpoint configuration in addition.
        try await local.prepareDependencies(for: model)
        if remoteEnabled {
            try await remote.prepareDependencies(for: model)
        }
    }

    func synthesize(
        _ request: SpeechRequest
    ) async -> AsyncThrowingStream<SynthesisEvent, Error> {
        await configurationChain.value
        if remoteEnabled {
            return await remote.synthesize(request)
        }
        return await local.synthesize(request)
    }

    func cancelCurrentRequest() async {
        await local.cancelCurrentRequest()
        await remote.cancelCurrentRequest()
    }

    func unloadModel() async {
        await local.unloadModel()
        await remote.unloadModel()
    }

    func generateVoiceSample(
        model: ModelDescriptor,
        text: String,
        language: String?,
        tuning: VoiceSynthesisTuning,
        seed: UInt64,
        reference: VoiceReference?
    ) async throws -> GeneratedVoiceSample {
        await configurationChain.value
        if remoteEnabled {
            return try await remote.generateVoiceSample(
                model: model,
                text: text,
                language: language,
                tuning: tuning,
                seed: seed,
                reference: reference
            )
        }
        return try await local.generateVoiceSample(
            model: model,
            text: text,
            language: language,
            tuning: tuning,
            seed: seed,
            reference: reference
        )
    }
}

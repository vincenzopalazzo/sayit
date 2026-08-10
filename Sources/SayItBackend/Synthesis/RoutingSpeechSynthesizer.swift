import Foundation
import SayItCore

/// Routes synthesis to local MLX or a remote OpenAI-compatible endpoint.
actor RoutingSpeechSynthesizer: BackendSpeechSynthesizing {
    private let local: any BackendSpeechSynthesizing
    private let remote: OpenAICompatibleSpeechSynthesizer
    private var remoteEnabled = false
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

        if configuration.enabled {
            // Apply remote settings before advertising the remote route so a
            // re-entrant synthesize call cannot observe enabled+stale config.
            await remote.updateRemoteConfiguration(configuration)
            guard generation == configurationGeneration else { return }
            remoteEnabled = true
        } else {
            remoteEnabled = false
            await remote.updateRemoteConfiguration(configuration)
            guard generation == configurationGeneration else { return }
        }
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
        if remoteEnabled {
            try await remote.prepareDependencies(for: model)
        } else {
            try await local.prepareDependencies(for: model)
        }
    }

    func synthesize(
        _ request: SpeechRequest
    ) async -> AsyncThrowingStream<SynthesisEvent, Error> {
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

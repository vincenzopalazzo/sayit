import Foundation
import SayItCore
import Testing
@testable import SayItBackend

@MainActor
@Suite("Backend settings storage")
struct BackendSettingsStoreTests {
    @Test("A failed atomic write does not change in-memory settings")
    func failedWritePreservesCurrentValue() {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: UUID().uuidString,
                directoryHint: .isDirectory
            )
        let store = BackendSettingsStore(directory: missingDirectory)
        let original = store.value
        var updated = original
        updated.speakingPace = SpeakingPace.fast.rawValue

        #expect(throws: (any Error).self) {
            try store.update(updated)
        }
        #expect(store.value == original)
    }

    @Test("Remote TTS settings round-trip through disk")
    func remoteTTSSettingsPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: UUID().uuidString,
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = BackendSettingsStore(directory: directory)
        var updated = store.value
        updated.remoteTTSEnabled = true
        updated.remoteTTSBaseURL = "https://gpu.example/v1"
        updated.remoteTTSModel = "tts-1"
        updated.remoteTTSVoice = "alloy"
        updated.remoteTTSTimeoutSeconds = 90
        try store.update(updated)

        let reloaded = BackendSettingsStore(directory: directory)
        #expect(reloaded.value.remoteTTSEnabled == true)
        #expect(reloaded.value.remoteTTSBaseURL == "https://gpu.example/v1")
        #expect(reloaded.value.remoteTTSModel == "tts-1")
        #expect(reloaded.value.remoteTTSVoice == "alloy")
        #expect(reloaded.value.remoteTTSTimeoutSeconds == 90)
    }
}

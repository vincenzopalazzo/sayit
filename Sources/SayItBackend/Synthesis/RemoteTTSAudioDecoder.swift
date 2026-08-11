import AVFoundation
import Foundation

enum RemoteTTSAudioDecoder {
    struct DecodedPCM: Sendable {
        let samples: [Float]
        let sampleRate: Double
    }

    /// Reject multi-hour remote payloads that would force huge buffers.
    private static let maximumFrameCount: AVAudioFrameCount = 48_000 * 60 * 10
    private static let maximumChannelCount: AVAudioChannelCount = 2
    /// Hard memory budget independent of channel count (~10 min mono float32).
    private static let maximumTotalSamples = 48_000 * 60 * 10

    static func decode(_ data: Data) throws -> DecodedPCM {
        guard !data.isEmpty else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote endpoint returned empty audio."
            )
        }

        let decoded = try decodeContainer(data, preferredExtension: "wav")
            ?? decodeContainer(data, preferredExtension: "mp3")
            ?? decodeContainer(data, preferredExtension: "caf")
        guard let decoded else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "Could not decode remote audio. Prefer response_format=wav or mp3."
            )
        }
        guard decoded.sampleRate > 0 else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio reported an invalid sample rate."
            )
        }
        guard !decoded.samples.isEmpty else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio file contained no samples."
            )
        }
        return decoded
    }

    private static func decodeContainer(
        _ data: Data,
        preferredExtension: String
    ) throws -> DecodedPCM? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(
                path: "sayit-remote-tts-\(UUID().uuidString).\(preferredExtension)"
            )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)

        // Force a known non-interleaved float format so channel planes are safe.
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forReading: temporaryURL,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            return nil
        }
        let format = file.processingFormat
        let length = file.length
        guard length > 0 else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio file contained no samples."
            )
        }
        let maxDurationSeconds = 10.0 * 60.0
        let maxFramesForRate = AVAudioFramePosition(
            max(1, format.sampleRate * maxDurationSeconds)
        )
        let frameLimit = min(
            AVAudioFramePosition(maximumFrameCount),
            maxFramesForRate
        )
        guard length <= frameLimit else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio is longer than the supported limit."
            )
        }
        guard format.channelCount > 0,
              format.channelCount <= maximumChannelCount else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio has an unsupported channel layout."
            )
        }
        let totalSamples = Int(length) * Int(format.channelCount)
        guard totalSamples <= maximumTotalSamples else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio is larger than the supported limit."
            )
        }
        guard format.sampleRate > 0 else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio reported an invalid sample rate."
            )
        }

        let frameCount = AVAudioFrameCount(length)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "Could not allocate an audio buffer."
            )
        }
        try file.read(into: buffer)
        guard buffer.frameLength == frameCount else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio was truncated before decoding finished."
            )
        }

        guard let channelData = buffer.floatChannelData else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "Unsupported remote audio sample format."
            )
        }

        let frames = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var samples: [Float] = []
        samples.reserveCapacity(frames)

        if channelCount == 1 {
            samples.append(contentsOf: UnsafeBufferPointer(
                start: channelData[0],
                count: frames
            ))
        } else {
            for frame in 0..<frames {
                var mixed: Float = 0
                for channel in 0..<channelCount {
                    mixed += channelData[channel][frame]
                }
                samples.append(mixed / Float(channelCount))
            }
        }

        return DecodedPCM(samples: samples, sampleRate: format.sampleRate)
    }
}

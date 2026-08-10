import AVFoundation
import Foundation

enum RemoteTTSAudioDecoder {
    struct DecodedPCM: Sendable {
        let samples: [Float]
        let sampleRate: Double
    }

    /// Reject multi-hour remote payloads that would force huge buffers.
    private static let maximumFrameCount: AVAudioFrameCount = 24_000 * 60 * 30

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

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: temporaryURL)
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
        guard length <= AVAudioFramePosition(maximumFrameCount) else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio is longer than the supported limit."
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

        let sampleRate = format.sampleRate
        guard sampleRate > 0 else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio reported an invalid sample rate."
            )
        }
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "The remote audio had no channels."
            )
        }

        var samples: [Float] = []
        samples.reserveCapacity(Int(buffer.frameLength))

        if let channelData = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
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
        } else if let int16Data = buffer.int16ChannelData {
            let frames = Int(buffer.frameLength)
            let scale: Float = 1.0 / Float(Int16.max)
            if channelCount == 1 {
                for frame in 0..<frames {
                    samples.append(Float(int16Data[0][frame]) * scale)
                }
            } else {
                for frame in 0..<frames {
                    var mixed: Float = 0
                    for channel in 0..<channelCount {
                        mixed += Float(int16Data[channel][frame]) * scale
                    }
                    samples.append(mixed / Float(channelCount))
                }
            }
        } else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "Unsupported remote audio sample format."
            )
        }

        return DecodedPCM(samples: samples, sampleRate: sampleRate)
    }
}

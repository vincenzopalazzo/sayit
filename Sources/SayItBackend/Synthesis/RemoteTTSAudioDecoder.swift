import AVFoundation
import Foundation

enum RemoteTTSAudioDecoder {
    struct DecodedPCM: Sendable {
        let samples: [Float]
        let sampleRate: Double
    }

    static func decode(_ data: Data) throws -> DecodedPCM {
        guard !data.isEmpty else {
            throw SynthesisError.remoteTTSInvalidAudio("The remote endpoint returned empty audio.")
        }

        if let pcm = decodeRawPCM16LE(data) {
            return pcm
        }

        let decoded = try decodeContainer(data, preferredExtension: "wav")
            ?? decodeContainer(data, preferredExtension: "mp3")
            ?? decodeContainer(data, preferredExtension: "caf")
        guard let decoded else {
            throw SynthesisError.remoteTTSInvalidAudio(
                "Could not decode remote audio. Prefer response_format=wav or mp3."
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
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else {
            throw SynthesisError.remoteTTSInvalidAudio("The remote audio file contained no samples.")
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw SynthesisError.remoteTTSInvalidAudio("Could not allocate an audio buffer.")
        }
        try file.read(into: buffer)

        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else {
            throw SynthesisError.remoteTTSInvalidAudio("The remote audio had no channels.")
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

    /// Detect bare PCM16 LE mono at 24 kHz when the payload has no container.
    private static func decodeRawPCM16LE(_ data: Data) -> DecodedPCM? {
        // Only treat as raw PCM when it looks like even-length PCM and lacks
        // common container magic headers.
        guard data.count >= 44, data.count % 2 == 0 else { return nil }
        if data.starts(with: Data("RIFF".utf8)) { return nil }
        if data.starts(with: Data("ID3".utf8)) { return nil }
        if data.count >= 2, data[0] == 0xFF, data[1] & 0xE0 == 0xE0 { return nil } // MPEG
        if data.starts(with: Data("OggS".utf8)) { return nil }
        if data.starts(with: Data("fLaC".utf8)) { return nil }
        // Prefer container decode for anything AVFoundation can open; raw path
        // is intentionally unused unless we add an explicit response_format later.
        return nil
    }
}

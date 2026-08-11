import Foundation


enum SynthesisError: LocalizedError {
    case modelNotInstalled
    case generatedNoAudio
    case invalidReferenceAudio
    case speakingPaceUnavailable
    case remoteTTSInvalidConfiguration(String)
    case remoteTTSUnsupported(String)
    case remoteTTSTransport(String)
    case remoteTTSUnauthorized(String)
    case remoteTTSHTTPStatus(statusCode: Int, detail: String)
    case remoteTTSInvalidAudio(String)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            "The selected voice model is not installed."
        case .generatedNoAudio:
            "The voice model did not generate playable audio."
        case .invalidReferenceAudio:
            "The saved voice reference could not be read."
        case .speakingPaceUnavailable:
            "The selected voice model could not apply its speaking pace."
        case .remoteTTSInvalidConfiguration(let message):
            message
        case .remoteTTSUnsupported(let message):
            message
        case .remoteTTSTransport(let message):
            "Remote TTS request failed: \(message)"
        case .remoteTTSUnauthorized(let message):
            message
        case .remoteTTSHTTPStatus(let statusCode, let detail):
            if detail.isEmpty {
                "Remote TTS failed with HTTP \(statusCode)."
            } else {
                "Remote TTS failed with HTTP \(statusCode): \(detail)"
            }
        case .remoteTTSInvalidAudio(let message):
            message
        }
    }
}

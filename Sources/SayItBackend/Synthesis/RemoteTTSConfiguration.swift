import Foundation

struct RemoteTTSConfiguration: Equatable, Sendable {
    var enabled: Bool
    var baseURL: URL?
    var model: String
    var voice: String
    var timeoutSeconds: Double

    static let disabled = RemoteTTSConfiguration(
        enabled: false,
        baseURL: nil,
        model: "",
        voice: "",
        timeoutSeconds: 120
    )

    var isReady: Bool {
        enabled
            && baseURL != nil
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func parseBaseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed
        if candidate.hasSuffix("/") {
            candidate.removeLast()
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    func speechEndpointURL() throws -> URL {
        guard let baseURL else {
            throw SynthesisError.remoteTTSInvalidConfiguration(
                "Set a valid OpenAI-compatible base URL first."
            )
        }
        // Accept either https://host or https://host/v1
        let path = baseURL.path
        if path == "/v1" || path.hasSuffix("/v1") {
            return baseURL.appending(path: "audio/speech")
        }
        if path.hasSuffix("/v1/audio/speech") {
            return baseURL
        }
        return baseURL.appending(path: "v1/audio/speech")
    }
}

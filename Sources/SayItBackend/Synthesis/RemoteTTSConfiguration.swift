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
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        switch scheme {
        case "https":
            return url
        case "http":
            // Cleartext only for loopback / local-network style hosts.
            guard isLocalNetworkHost(host) else { return nil }
            return url
        default:
            return nil
        }
    }

    static func isLocalNetworkHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        if host.hasSuffix(".local") {
            return true
        }
        // Tailscale MagicDNS and similar private mesh names.
        if host.hasSuffix(".ts.net") {
            return true
        }
        // RFC1918 IPv4 prefixes commonly used on LAN.
        if host.hasPrefix("10.")
            || host.hasPrefix("192.168.")
            || host.range(of: #"^172\.(1[6-9]|2[0-9]|3[0-1])\."#, options: .regularExpression) != nil {
            return true
        }
        return false
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

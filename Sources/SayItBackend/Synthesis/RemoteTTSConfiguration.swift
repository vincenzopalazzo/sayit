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
        if host == "localhost" || host == "::1" {
            return true
        }
        if host.hasSuffix(".local") || host.hasSuffix(".ts.net") {
            return true
        }
        if let ipv4 = parseIPv4(host) {
            return isPrivateIPv4(ipv4)
        }
        return false
    }

    private static func parseIPv4(_ host: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        octets.reserveCapacity(4)
        for part in parts {
            guard let value = UInt8(part) else { return nil }
            octets.append(value)
        }
        return (octets[0], octets[1], octets[2], octets[3])
    }

    private static func isPrivateIPv4(
        _ ip: (UInt8, UInt8, UInt8, UInt8)
    ) -> Bool {
        let (a, b, _, _) = ip
        if a == 127 { return true } // loopback
        if a == 10 { return true }
        if a == 192 && b == 168 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 169 && b == 254 { return true } // link-local
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

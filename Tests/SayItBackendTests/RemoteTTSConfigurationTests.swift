import Foundation
import Testing
@testable import SayItBackend

@Suite("Remote TTS configuration")
struct RemoteTTSConfigurationTests {
    @Test("Parses http(s) base URLs and rejects invalid schemes")
    func parsesBaseURL() {
        #expect(
            RemoteTTSConfiguration.parseBaseURL("https://spark.example:8000/v1")?
                .absoluteString == "https://spark.example:8000/v1"
        )
        #expect(
            RemoteTTSConfiguration.parseBaseURL("http://127.0.0.1:8080/")?
                .absoluteString == "http://127.0.0.1:8080"
        )
        #expect(
            RemoteTTSConfiguration.parseBaseURL("http://192.168.1.10:8080/v1")?
                .absoluteString == "http://192.168.1.10:8080/v1"
        )
        #expect(
            RemoteTTSConfiguration.parseBaseURL("http://example.com/v1") == nil
        )
        #expect(
            RemoteTTSConfiguration.parseBaseURL("http://10.example.com/v1") == nil
        )
        #expect(
            RemoteTTSConfiguration.parseBaseURL("http://192.168.attacker.com/v1") == nil
        )
        #expect(
            RemoteTTSConfiguration.parseBaseURL("http://machine.tailnet.ts.net/v1") == nil
        )
        #expect(
            RemoteTTSConfiguration.parseBaseURL("https://machine.tailnet.ts.net/v1")?
                .absoluteString == "https://machine.tailnet.ts.net/v1"
        )
        #expect(RemoteTTSConfiguration.parseBaseURL("") == nil)
        #expect(RemoteTTSConfiguration.parseBaseURL("ftp://nope") == nil)
        #expect(RemoteTTSConfiguration.parseBaseURL("not a url") == nil)
    }

    @Test("Builds /v1/audio/speech from base or versioned roots")
    func speechEndpoint() throws {
        let bare = RemoteTTSConfiguration(
            enabled: true,
            baseURL: RemoteTTSConfiguration.parseBaseURL("https://host:9"),
            model: "tts",
            voice: "alloy",
            timeoutSeconds: 30
        )
        #expect(
            try bare.speechEndpointURL().absoluteString
                == "https://host:9/v1/audio/speech"
        )

        let versioned = RemoteTTSConfiguration(
            enabled: true,
            baseURL: RemoteTTSConfiguration.parseBaseURL("https://host:9/v1"),
            model: "tts",
            voice: "alloy",
            timeoutSeconds: 30
        )
        #expect(
            try versioned.speechEndpointURL().absoluteString
                == "https://host:9/v1/audio/speech"
        )

        let full = RemoteTTSConfiguration(
            enabled: true,
            baseURL: RemoteTTSConfiguration.parseBaseURL(
                "https://host:9/v1/audio/speech"
            ),
            model: "tts",
            voice: "alloy",
            timeoutSeconds: 30
        )
        #expect(
            try full.speechEndpointURL().absoluteString
                == "https://host:9/v1/audio/speech"
        )
    }

    @Test("isReady requires enablement, URL, and model")
    func readiness() {
        #expect(RemoteTTSConfiguration.disabled.isReady == false)
        let partial = RemoteTTSConfiguration(
            enabled: true,
            baseURL: RemoteTTSConfiguration.parseBaseURL("https://h"),
            model: "",
            voice: "",
            timeoutSeconds: 30
        )
        #expect(partial.isReady == false)
        let ready = RemoteTTSConfiguration(
            enabled: true,
            baseURL: RemoteTTSConfiguration.parseBaseURL("https://h"),
            model: "tts-1",
            voice: "alloy",
            timeoutSeconds: 30
        )
        #expect(ready.isReady == true)
    }
}

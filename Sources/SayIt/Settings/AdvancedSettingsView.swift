import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var state

    @State private var remoteTTSEnabled = false
    @State private var baseURL = ""
    @State private var model = ""
    @State private var voice = ""
    @State private var timeoutSeconds = 120.0
    @State private var apiKey = ""

    private var isDirty: Bool {
        let settings = state.backendSettings
        return remoteTTSEnabled != settings.remoteTTSEnabled
            || baseURL != settings.remoteTTSBaseURL
            || model != settings.remoteTTSModel
            || voice != settings.remoteTTSVoice
            || timeoutSeconds != settings.remoteTTSTimeoutSeconds
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use remote OpenAI-compatible TTS", isOn: $remoteTTSEnabled)

                TextField(
                    "Base URL",
                    text: $baseURL,
                    prompt: Text("https://host:port/v1")
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

                TextField("Model id", text: $model, prompt: Text("tts-1"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                TextField("Voice id", text: $voice, prompt: Text("alloy"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                LabeledContent("Timeout") {
                    HStack {
                        Slider(value: $timeoutSeconds, in: 5...600, step: 5)
                        Text("\(Int(timeoutSeconds))s")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                if let message = state.remoteTTSErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } header: {
                Text("Remote TTS")
            } footer: {
                Text(
                    "Optional. When enabled, text you choose to speak is sent to the configured OpenAI-compatible endpoint, along with any API key, and the returned audio plays on this Mac. History stays on this Mac. Local MLX synthesis remains the default when this is off. Prefer https://; http:// is only for trusted local-network hosts."
                )
            }

            Section {
                SecureField(
                    "API key",
                    text: $apiKey,
                    prompt: Text("Optional bearer token")
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save API Key") {
                        state.setRemoteTTSAPIKey(apiKey)
                        apiKey = ""
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear API Key", role: .destructive) {
                        apiKey = ""
                        state.clearRemoteTTSAPIKey()
                    }
                }

                if let message = state.remoteTTSAPIKeyMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text(
                    "Stored in the Keychain on this Mac. Leave empty if your endpoint does not require a bearer token."
                )
            }

            Section {
                Button("Apply Settings") {
                    persistSettings()
                }
                .disabled(!isDirty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: synchronize)
    }

    private func synchronize() {
        let settings = state.backendSettings
        remoteTTSEnabled = settings.remoteTTSEnabled
        baseURL = settings.remoteTTSBaseURL
        model = settings.remoteTTSModel
        voice = settings.remoteTTSVoice
        timeoutSeconds = settings.remoteTTSTimeoutSeconds
    }

    private func persistSettings() {
        state.updateRemoteTTS(
            enabled: remoteTTSEnabled,
            baseURL: baseURL,
            model: model,
            voice: voice,
            timeoutSeconds: timeoutSeconds
        )
    }
}

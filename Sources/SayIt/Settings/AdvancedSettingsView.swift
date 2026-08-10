import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var state

    @State private var remoteTTSEnabled = false
    @State private var baseURL = ""
    @State private var model = ""
    @State private var voice = ""
    @State private var timeoutSeconds = 120.0
    @State private var apiKey = ""
    @State private var isDirty = false
    @State private var isSynchronizing = false

    var body: some View {
        Form {
            Section {
                Toggle("Use remote OpenAI-compatible TTS", isOn: $remoteTTSEnabled)
                    .onChange(of: remoteTTSEnabled) { _, _ in
                        markDirty()
                    }

                TextField(
                    "Base URL",
                    text: $baseURL,
                    prompt: Text("https://host:port/v1")
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: baseURL) { _, _ in
                    markDirty()
                }

                TextField("Model id", text: $model, prompt: Text("tts-1"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: model) { _, _ in
                        markDirty()
                    }

                TextField("Voice id", text: $voice, prompt: Text("alloy"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: voice) { _, _ in
                        markDirty()
                    }

                LabeledContent("Timeout") {
                    HStack {
                        Slider(value: $timeoutSeconds, in: 5...600, step: 5)
                        Text("\(Int(timeoutSeconds))s")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .onChange(of: timeoutSeconds) { _, _ in
                    markDirty()
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

    private func markDirty() {
        guard !isSynchronizing else { return }
        isDirty = true
    }

    private func synchronize() {
        isSynchronizing = true
        let settings = state.backendSettings
        remoteTTSEnabled = settings.remoteTTSEnabled
        baseURL = settings.remoteTTSBaseURL
        model = settings.remoteTTSModel
        voice = settings.remoteTTSVoice
        timeoutSeconds = settings.remoteTTSTimeoutSeconds
        isDirty = false
        isSynchronizing = false
    }

    private func persistSettings() {
        state.updateRemoteTTS(
            enabled: remoteTTSEnabled,
            baseURL: baseURL,
            model: model,
            voice: voice,
            timeoutSeconds: timeoutSeconds
        )
        isDirty = false
    }
}

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var state

    @State private var remoteTTSEnabled = false
    @State private var baseURL = ""
    @State private var model = ""
    @State private var voice = ""
    @State private var timeoutSeconds = 120.0
    @State private var apiKey = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Toggle("Use remote OpenAI-compatible TTS", isOn: $remoteTTSEnabled)
                    .onChange(of: remoteTTSEnabled) { _, _ in
                        persistSettings()
                    }

                TextField("Base URL", text: $baseURL, prompt: Text("https://host:port/v1"))
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .onSubmit(persistSettings)

                TextField("Model id", text: $model, prompt: Text("tts-1"))
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .onSubmit(persistSettings)

                TextField("Voice id", text: $voice, prompt: Text("alloy"))
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .onSubmit(persistSettings)

                LabeledContent("Timeout") {
                    HStack {
                        Slider(value: $timeoutSeconds, in: 5...600, step: 5)
                        Text("\(Int(timeoutSeconds))s")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .onChange(of: timeoutSeconds) { _, _ in
                    persistSettings()
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
                    "Optional. When enabled, Say It sends text you choose to speak to the configured endpoint and plays the returned audio on this Mac. Your text leaves this computer. Local MLX synthesis remains the default when this is off."
                )
            }

            Section {
                SecureField("API key", text: $apiKey, prompt: Text("Optional bearer token"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveAPIKey)

                HStack {
                    Button("Save API Key") {
                        saveAPIKey()
                    }
                    .disabled(isSaving)

                    Button("Clear API Key", role: .destructive) {
                        apiKey = ""
                        state.clearRemoteTTSAPIKey()
                    }
                    .disabled(isSaving)
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
                .disabled(isSaving)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: synchronize)
        .onChange(of: state.backendSettings) { _, _ in
            synchronize()
        }
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
        isSaving = true
        state.updateRemoteTTS(
            enabled: remoteTTSEnabled,
            baseURL: baseURL,
            model: model,
            voice: voice,
            timeoutSeconds: timeoutSeconds
        )
        isSaving = false
    }

    private func saveAPIKey() {
        isSaving = true
        state.setRemoteTTSAPIKey(apiKey)
        isSaving = false
    }
}

import Foundation

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case service
    case speech
    case voices
    case models
    case history
    case advanced
    case diagnostics
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .service: "Service"
        case .speech: "Speech"
        case .voices: "Voices"
        case .models: "Models"
        case .history: "History"
        case .advanced: "Advanced"
        case .diagnostics: "Diagnostics"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .service: "server.rack"
        case .speech: "waveform"
        case .voices: "person.wave.2"
        case .models: "internaldrive"
        case .history: "clock.arrow.circlepath"
        case .advanced: "slider.horizontal.3"
        case .diagnostics: "stethoscope"
        case .about: "info.circle"
        }
    }
}

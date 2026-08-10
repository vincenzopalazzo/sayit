import SwiftUI

struct PrivacyOnboardingView: View {
    var body: some View {
        OnboardingPage(
            symbol: "lock.shield",
            title: "Private by design",
            subtitle: "By default, your text and generated audio stay on this Mac. Say It connects for model downloads, update checks, and only if you opt into Advanced remote TTS."
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.standardSpacing) {
                Label(
                    "Local speech by default; remote TTS is opt-in",
                    systemImage: "icloud.slash"
                )
                Label(
                    "No passive clipboard monitoring",
                    systemImage: "doc.on.clipboard"
                )
                Label(
                    "No analytics or passive microphone listening",
                    systemImage: "mic.slash"
                )
            }
            .labelStyle(.onboardingFeature)
        }
    }
}

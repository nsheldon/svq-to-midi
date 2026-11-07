import SwiftUI

/// The About window, opened from the app menu ("About SVQ to MIDI").
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            Image("AboutArt")
                .resizable()
                .interpolation(.high)
                .aspectRatio(560.0 / 200.0, contentMode: .fit)
                .frame(width: 560)
                .overlay(alignment: .bottom) {
                    // A Platinum-era bevel along the bottom edge of the artwork
                    VStack(spacing: 0) {
                        Color.white.opacity(0.35).frame(height: 1)
                        Color.black.opacity(0.35).frame(height: 1)
                    }
                }

            VStack(spacing: 6) {
                Text("SVQ to MIDI")
                    .font(.system(size: 22, weight: .bold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Converts Roland XP-50, XP-60, XP-80 and Fantom-X sequencer songs (.SVQ) to Standard MIDI Files, with each Part\u{2019}s patch selection from the song\u{2019}s saved Performance.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Text(copyright)
                    .font(.callout)
                    .padding(.top, 8)

                Text("Roland, MC-80, XP-50, XP-60, XP-80 and Fantom are trademarks of Roland Corporation. SVQ to MIDI is not affiliated with or endorsed by Roland Corporation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }
        .frame(width: 560)
    }
}

/// "About SVQ to MIDI" in the app menu, opening the custom About window.
struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About SVQ to MIDI") { openWindow(id: "about") }
    }
}

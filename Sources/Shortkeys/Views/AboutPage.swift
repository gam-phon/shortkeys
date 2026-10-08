import SwiftUI

struct AboutPage: View {
    static let repositoryURL = URL(string: "https://github.com/gam-phon/shortkeys")!

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            VStack(spacing: 4) {
                Text("Shortkeys")
                    .font(.largeTitle.weight(.semibold))
                Text("Version \(Self.version)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("App launch and window management hotkeys for macOS.")
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Made by Yaser Alraddadi")
                Link("github.com/gam-phon/shortkeys", destination: Self.repositoryURL)
            }
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }

    /// "1.2.0 (42)", from the app's Info.plist.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

import SwiftUI

/// iPhone host for the watch app. Xcode has no App Store distribution
/// method for a bare watchOS archive, so the watch app ships embedded in
/// this host; the phone side is just a pointer to the wrist.
@main
struct CubeScrambleApp: App {
    var body: some Scene {
        WindowGroup {
            HostView()
        }
    }
}

struct HostView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "applewatch.watchface")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("CubeScramble")
                .font(.title.bold())

            Text("CubeScramble lives on your Apple Watch. Open the Watch app on this iPhone — or the App Store on the watch itself — to install it, then generate scrambles straight from your wrist.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    HostView()
}

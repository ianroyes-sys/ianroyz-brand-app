import SwiftUI
import AVFoundation
import Combine

@main
struct IanRoyzApp: App {
    // Owns the orientation lock — the film player is the only screen that rotates.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                // Copy that goes stale (rotation, now playing) refreshes from the
                // feed on launch. Failure is silent — the app keeps what shipped.
                .task { await Live.shared.refresh() }
        }
    }
}

struct RootView: View {
    /// The landing is a great door the first time and a wall the tenth. Once
    /// you've been in, the app opens where you left off — the door is still
    /// reachable from the footer.
    @AppStorage("hasEntered") private var hasEntered = false
    /// Bumping this deliberately reopens the cinematic door for people who
    /// update the app. `hasEntered` alone is preserved by TestFlight updates,
    /// which is why the landing film appeared to disappear in the current build.
    @AppStorage("introExperienceVersion") private var introExperienceVersion = 0
    private let currentIntroExperienceVersion = 1
    @State private var entered = ProcessInfo.processInfo.arguments.contains("ENTERED")
    @State private var requestedRoom: Room?

    private var shouldShowIntro: Bool {
        !entered && (!hasEntered || introExperienceVersion < currentIntroExperienceVersion)
    }

    var body: some View {
        ZStack {
            if !shouldShowIntro {
                HomeView(onWatchIntro: replayIntro, requestedRoom: $requestedRoom)
                    .transition(.opacity)
            } else {
                LandingView(onEnter: {
                    withAnimation(.easeInOut(duration: 0.9)) {
                        entered = true
                        hasEntered = true
                        introExperienceVersion = currentIntroExperienceVersion
                    }
                })
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(shouldShowIntro)
        .onOpenURL { openRoute($0) }
        .onReceive(NotificationCenter.default.publisher(for: .ianRoyzRoute)) { notification in
            if let url = notification.object as? URL { openRoute(url) }
        }
    }

    private func replayIntro() {
        withAnimation(.easeInOut(duration: 0.6)) {
            entered = false
            hasEntered = false
        }
    }

    private func openRoute(_ url: URL) {
        guard url.scheme?.lowercased() == "ianroyz" else { return }
        let destination = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        switch destination {
        case "roll": requestedRoom = .roll
        case "community", "wall": requestedRoom = .classRoll
        case "films", "motion": requestedRoom = .motion
        case "saturdays": requestedRoom = .saturdays
        case "lost": requestedRoom = .lost
        case "shoots": requestedRoom = .shoots
        default: break
        }
    }
}

import SwiftUI
import UIKit
@preconcurrency import UserNotifications

extension Notification.Name {
    static let ianRoyzRoute = Notification.Name("ianRoyzRoute")
}

// MARK: - Orientation
//
// The app is portrait everywhere — it's a vertical, editorial layout and it
// breaks sideways. The film player is the single exception: the work is wide,
// and portrait-locking it means watching a 16:9 cut in a strip.
//
// The Info.plist has to *permit* landscape for the delegate to be allowed to
// return it, so the lock below is what actually keeps every other screen
// portrait. Loosen one without the other and the whole app starts rotating.

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Read by UIKit on every rotation. Default is the app-wide rule.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let route = response.notification.request.content.userInfo["route"] as? String else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .ianRoyzRoute, object: URL(string: route))
        }
    }
}

private struct SupportedOrientations: ViewModifier {
    let mask: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppDelegate.orientationLock = mask
                push(mask)
            }
            .onDisappear {
                AppDelegate.orientationLock = .portrait
                push(.portrait)
            }
    }

    private func push(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}

extension View {
    /// Allow this screen — and only this screen — to rotate.
    func supportedInterfaceOrientations(_ mask: UIInterfaceOrientationMask) -> some View {
        modifier(SupportedOrientations(mask: mask))
    }
}

import SwiftUI
import UserNotifications

@main
struct DropFeedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authSession = AuthSessionManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if authSession.isSignedIn {
                    ContentView()
                } else {
                    LoginFlowView()
                }
            }
            .environmentObject(authSession)
            .preferredColorScheme(.light)
            .task { await requestPushPermissionAndRegister() }
        }
    }

    private func requestPushPermissionAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            // Permission denied or error
        }
    }
}

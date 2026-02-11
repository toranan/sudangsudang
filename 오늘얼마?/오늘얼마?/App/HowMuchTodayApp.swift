import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#endif
#if canImport(KakaoSDKAuth)
import KakaoSDKAuth
import KakaoSDKCommon
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #if canImport(FirebaseAnalytics)
        Analytics.setAnalyticsCollectionEnabled(true)
        #endif
        #endif
        return true
    }
}

@main
struct HowMuchTodayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        #if canImport(KakaoSDKCommon)
        let appKey = AppConfig.kakaoNativeAppKey
        if !appKey.isEmpty {
            KakaoSDK.initSDK(appKey: appKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    #if canImport(KakaoSDKAuth)
                    _ = AuthController.handleOpenUrl(url: url)
                    #endif
                    InviteManager.shared.handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    InviteManager.shared.handleIncomingURL(url)
                }
        }
    }
}

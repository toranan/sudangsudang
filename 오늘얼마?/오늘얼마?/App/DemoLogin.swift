#if DEBUG
import Foundation
#if canImport(Supabase)
import Supabase
#endif

// 데모 영상·UI 테스트용. 실행 환경변수 DEMO_EMAIL/DEMO_PASSWORD가 있으면 그 계정으로 로그인한다.
// 시뮬레이터에서는 Apple 로그인을 쓸 수 없어서 만든 개발용 경로라 Release 빌드에는 들어가지 않는다.
enum DemoLogin {
    static func signInIfRequested() async {
        #if canImport(Supabase)
        let env = ProcessInfo.processInfo.environment
        guard let email = env["DEMO_EMAIL"], let password = env["DEMO_PASSWORD"],
              !email.isEmpty, !password.isEmpty else { return }
        let auth = SupabaseManager.shared.client.auth
        if auth.currentUser?.email == email { return }
        do {
            try? await auth.signOut()
            SupabaseManager.shared.clearLastRole()
            try await auth.signIn(email: email, password: password)
        } catch {
            print("DEBUG: DemoLogin failed: \(error)")
        }
        #endif
    }
}
#endif

import SwiftUI
import AuthenticationServices
import CryptoKit
#if canImport(Supabase)
import Supabase
#endif
#if canImport(KakaoSDKAuth)
import KakaoSDKAuth
import KakaoSDKUser
#endif

struct AuthBrandView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("wallet_mascot")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 160)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                .padding(.bottom, 20)

            VStack(spacing: 12) {
                Text("사장님, 알바생 모두")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)

                Text("간편하게 수당수당")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
    }
}

struct AuthView: View {
    enum Step {
        case role
        case apple
    }

    @Binding var isLoggedIn: Bool
    @Binding var userRole: Profile.Role?
    let resumeProfile: ResumeProfile?

    @State private var step: Step = .apple
    @State private var name: String = ""
    @State private var currentNonce: String?
    @State private var authError: String?
    @State private var pendingUserId: UUID?
    @State private var pendingEmail: String?
    @State private var didApplyResume: Bool = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            AuthBrandView()

            switch step {
            case .role:
                roleStep
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .apple:
                // Just spacer to push content up, buttons are in footer
                Spacer()
            }
        }
        .padding(.top, 40)
        .safeAreaInset(edge: .bottom) {
            if step == .apple {
                appleFooter
            }
        }
        .task {
            applyResumeProfileIfNeeded()
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var roleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("어떤 회원으로 가입하시겠어요?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.appTextPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 10)

            Button(action: {
                Task { await completeSignup(selectedRole: .owner) }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("사장님이에요")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        Text("매장 관리와 근무 승인을 해요")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "storefront.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue.opacity(0.8))
                }
                .padding(20)
                .background(Color.appSurface)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())

            Button(action: {
                Task { await completeSignup(selectedRole: .worker) }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("아르바이트생이에요")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        Text("출퇴근 기록과 급여를 확인해요")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green.opacity(0.8))
                }
                .padding(20)
                .background(Color.appSurface)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())

            Button(action: {
                step = .apple
            }) {
                Text("이전으로")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private var appleStep: some View {
        EmptyView()
    }

    private var appleFooter: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task { await signInWithKakao() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 18))
                    Text("카카오톡으로 시작하기")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(red: 254/255, green: 229/255, blue: 0/255))
                .foregroundColor(.black.opacity(0.85))
                .cornerRadius(16)
            }
            .buttonStyle(ScaleButtonStyle())

            SignInWithAppleButton(.continue, onRequest: { request in
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256(nonce)
            }, onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let idTokenData = credential.identityToken,
                          let idToken = String(data: idTokenData, encoding: .utf8),
                          let nonce = currentNonce
                    else {
                        authError = "애플 로그인 정보를 가져오지 못했어요."
                        return
                    }

                    Task {
                        // Apple may only provide fullName/email on first authorization.
                        // Never require users to re-enter them after sign-in.
                        if let fullName = formattedAppleName(credential.fullName),
                           !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            name = fullName
                        }
                        if let email = credential.email, !email.isEmpty {
                            pendingEmail = email
                        }
                        await signInWithApple(idToken: idToken, nonce: nonce)
                    }
                case .failure(let error):
                    authError = AppErrorMessage.userMessage(error)
                }
            })
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.appBackground)
    }

    private func formattedAppleName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let value = formatter.string(from: components)
        return value.isEmpty ? nil : value
    }

    private func signInWithApple(idToken: String, nonce: String) async {
        #if canImport(Supabase)
        do {
            SupabaseManager.shared.clearCustomSession()
            let session = try await SupabaseManager.shared.authClient.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )

            let userId = session.user.id
            if await handleExistingProfile(userId: userId) {
                return
            }
            pendingUserId = userId
            if pendingEmail == nil {
                pendingEmail = session.user.email
            }
            step = .role
        } catch {
            authError = AppErrorMessage.userMessage(error)
        }
        #else
        authError = "Supabase SDK가 설치되지 않았어요."
        #endif
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: Array<Character> =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                let fallback = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                for ch in fallback where remainingLength > 0 {
                    if charset.contains(ch) {
                        result.append(ch)
                        remainingLength -= 1
                    }
                }
                continue
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    #if canImport(KakaoSDKAuth)
    private func loginWithKakao() async throws -> OAuthToken {
        try await withCheckedThrowingContinuation { continuation in
            let handler: (OAuthToken?, Error?) -> Void = { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "KakaoAuth",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "카카오 로그인을 완료하지 못했어요."]
                        )
                    )
                    return
                }
                continuation.resume(returning: token)
            }

            if UserApi.isKakaoTalkLoginAvailable() {
                UserApi.shared.loginWithKakaoTalk(completion: handler)
            } else {
                UserApi.shared.loginWithKakaoAccount(completion: handler)
            }
        }
    }
    #endif

    private func signInWithKakao() async {
        #if canImport(KakaoSDKAuth)
        do {
            let token = try await loginWithKakao()
            let response = try await SupabaseManager.shared.signInWithKakao(accessToken: token.accessToken)
            if await handleExistingProfile(userId: response.userId) {
                return
            }
            pendingUserId = response.userId
            pendingEmail = response.email
            step = .role
        } catch {
            authError = AppErrorMessage.userMessage(error)
        }
        #else
        authError = "카카오 SDK가 설치되지 않았어요."
        #endif
    }

    @MainActor
    private func handleExistingProfile(userId: UUID) async -> Bool {
        #if canImport(Supabase)
        do {
            let snapshot = try await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            if let roleRaw = snapshot.role, let role = Profile.Role(rawValue: roleRaw) {
                if Onboarding.needsOnboarding(role: role, name: snapshot.name, phone: snapshot.phone) {
                    pendingUserId = userId
                    pendingEmail = snapshot.email
                    userRole = role
                    name = snapshot.name ?? ""
                    step = .role
                    return true
                } else {
                    userRole = role
                    SupabaseManager.shared.saveLastRole(role)
                    isLoggedIn = true
                    return true
                }
            }

            pendingUserId = userId
            pendingEmail = snapshot.email
            step = .role
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    private func applyResumeProfileIfNeeded() {
        guard !didApplyResume, let profile = resumeProfile else { return }
        didApplyResume = true
        pendingUserId = profile.id
        pendingEmail = profile.email
        name = profile.name ?? ""
        if let role = profile.role {
            userRole = role
        }
        if Onboarding.needsOnboarding(role: profile.role, name: profile.name, phone: profile.phone) {
            step = .role
        }
    }

    @MainActor
    private func completeSignup(selectedRole: Profile.Role) async {
        userRole = selectedRole

        guard let userId = pendingUserId else {
            await SupabaseManager.shared.signOut()
            isLoggedIn = false
            userRole = nil
            authError = "로그인 정보를 확인하지 못했어요. 다시 로그인해주세요."
            return
        }

        #if canImport(Supabase)
        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = SupabaseManager.ProfilePayload(
                id: userId,
                email: pendingEmail,
                name: trimmedName.isEmpty ? nil : trimmedName,
                phone: nil,
                role: selectedRole.rawValue
            )
            try await SupabaseManager.shared.upsertProfile(payload)
            SupabaseManager.shared.saveLastRole(selectedRole)
            isLoggedIn = true
        } catch {
            authError = AppErrorMessage.userMessage(error)
        }
        #else
        SupabaseManager.shared.saveLastRole(selectedRole)
        isLoggedIn = true
        #endif
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

extension Notification.Name {
    static let didLogout = Notification.Name("didLogout")
    static let payrollSettingsDidChange = Notification.Name("payrollSettingsDidChange")
    static let appDidBecomeActive = Notification.Name("appDidBecomeActive")
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoggedIn: Bool = false
    @State private var userRole: Profile.Role? = nil // .owner or .worker
    @State private var pendingInvite: InviteManager.InvitePreview? = nil
    @State private var pendingInviteToken: String? = nil
    @State private var resumeProfile: ResumeProfile? = nil

    @State private var isPresentingInviteProfileGate: Bool = false
    @State private var inviteProfileGateName: String = ""
    @State private var inviteProfileGatePhone: String = ""
    @State private var inviteProfileGateSaveCompleted: Bool = false

    @State private var activeAlert: ActiveAlert? = nil

    private enum ActiveAlert: Identifiable, Equatable {
        case invitePrompt(token: String)
        case inviteError(message: String)

        var id: String {
            switch self {
            case .invitePrompt(let token):
                // Different token should force a new alert identity.
                return "invite:\(token)"
            case .inviteError(let message):
                return "error:\(message)"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            if isLoggedIn {
                if userRole == .owner {
                    OwnerRootView()
                } else if userRole == .worker {
                    WorkerRootView()
                } else {
                    // Fallback or Role selection if not set
                    Text("Role not found")
                }
            } else {
                AuthView(isLoggedIn: $isLoggedIn, userRole: $userRole, resumeProfile: resumeProfile)
            }
        }
        .task {
            await restoreSessionIfPossible()
            await loadPendingInviteIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            // If the app is opened via a link while already running (background),
            // the invite notification can be missed during the transition.
            if phase == .active {
                Task { await loadPendingInviteIfNeeded() }
                NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
            }
        }
        .onChange(of: isLoggedIn) { _ in
            Task { await loadPendingInviteIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
            isLoggedIn = false
            userRole = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveInvite)) { _ in
            Task { await loadPendingInviteIfNeeded() }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .invitePrompt:
                return Alert(
                    title: Text("초대가 있습니다"),
                    message: Text(pendingInvite.map { "'\($0.storeName)' 매장에 초대되었습니다. 수락하시겠어요?" } ?? "매장 초대가 있습니다. 수락하시겠어요?"),
                    primaryButton: .default(Text("수락"), action: {
                        Task { await beginAcceptInviteFlow() }
                    }),
                    secondaryButton: .cancel(Text("거절"), action: {
                        clearInviteState()
                    })
                )
            case .inviteError(let message):
                return Alert(
                    title: Text("초대 처리 실패"),
                    message: Text(message),
                    dismissButton: .default(Text("확인"), action: {
                        activeAlert = nil
                    })
                )
            }
        }
        .sheet(isPresented: $isPresentingInviteProfileGate, onDismiss: {
            guard inviteProfileGateSaveCompleted else { return }
            inviteProfileGateSaveCompleted = false
            let savedName = inviteProfileGateName
            let savedPhone = inviteProfileGatePhone
            Task {
                #if canImport(Supabase)
                do {
                    let userId = try await SupabaseManager.shared.currentUserId()
                    try await SupabaseManager.shared.patchProfile(
                        id: userId,
                        name: savedName.isEmpty ? nil : savedName,
                        phone: savedPhone.isEmpty ? nil : savedPhone
                    )
                } catch {
                    #if DEBUG
                    print("DEBUG: ContentView patchProfile failed: \(error.localizedDescription)")
                    #endif
                }
                #endif
                await acceptInvite()
            }
        }) {
            ProfileCompletionSheet(
                context: .init(
                    title: "프로필을 설정할까요?",
                    message: "사장님과의 연동을 위해 이름 입력이 필요해요. 전화번호도 입력할 수 있어요.",
                    primaryActionTitle: "저장하고 수락",
                    showsSkip: false,
                    requiresName: true
                ),
                initialName: inviteProfileGateName,
                initialPhone: inviteProfileGatePhone,
                onSave: { name, phone in
                    inviteProfileGateName = name ?? ""
                    inviteProfileGatePhone = phone ?? ""
                    inviteProfileGateSaveCompleted = true
                },
                onSkip: nil
            )
        }
    }

    @MainActor
    private func clearInviteState() {
        InviteManager.shared.clearPendingToken()
        pendingInvite = nil
        pendingInviteToken = nil
        activeAlert = nil
    }

    private func restoreSessionIfPossible() async {
        #if canImport(Supabase)
        do {
            if let snapshot = try await SupabaseManager.shared.restoreProfileSnapshotIfPossible() {
                let role = snapshot.role.flatMap { Profile.Role(rawValue: $0) }
                let resume = ResumeProfile(
                    id: snapshot.id,
                    email: snapshot.email,
                    name: snapshot.name,
                    phone: snapshot.phone,
                    role: role
                )
                if Onboarding.needsOnboarding(role: role, name: resume.name, phone: resume.phone) {
                    resumeProfile = resume
                    userRole = role
                    isLoggedIn = false
                    return
                } else if let role {
                    userRole = role
                    isLoggedIn = true
                    SupabaseManager.shared.saveLastRole(role)
                    return
                }
            }
            if await SupabaseManager.shared.validateStoredSession(),
               let savedRole = SupabaseManager.shared.lastSavedRole() {
                userRole = savedRole
                isLoggedIn = true
            }
        } catch {
            print("DEBUG: restoreSessionIfPossible failed: \(error)")
            // Do not trust cached role if the server session/profile fetch failed.
            // This avoids "deleted account but still logged in" scenarios.
            SupabaseManager.shared.clearLastRole()
            isLoggedIn = false
            userRole = nil
        }
        #endif
    }

    @MainActor
    private func loadPendingInviteIfNeeded() async {
        #if canImport(Supabase)
        guard isLoggedIn else { return }
        guard let token = InviteManager.shared.pendingToken() else { return }

        // If a new invite arrives while we already have a token loaded, refresh to the latest.
        pendingInviteToken = token
        pendingInvite = nil
        #if DEBUG
        print("DEBUG: ContentView.loadPendingInviteIfNeeded found token=\(token)")
        #endif

        // Best effort: show store name if RLS/network allows, but do not block the prompt.
        if let preview = await InviteManager.shared.fetchPendingInvitePreview() {
            pendingInvite = preview
        }

        // Force-refresh the alert identity when token changes while an alert is already visible.
        if activeAlert != nil {
            activeAlert = nil
            await Task.yield()
        }
        activeAlert = .invitePrompt(token: token)
        #if DEBUG
        print("DEBUG: ContentView.loadPendingInviteIfNeeded showInvitePrompt=true storeName=\(pendingInvite?.storeName ?? "nil")")
        #endif
        #endif
    }

    @MainActor
    private func beginAcceptInviteFlow() async {
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            let snapshot: SupabaseManager.ProfileSnapshot
            do {
                snapshot = try await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            } catch {
                if SupabaseManager.isPostgrestSingleObjectCoerceError(error) {
                    let role = userRole ?? SupabaseManager.shared.lastSavedRole() ?? .worker
                    try await SupabaseManager.shared.ensureMinimalProfileRow(
                        id: userId,
                        email: nil,
                        role: role
                    )
                    inviteProfileGateName = ""
                    inviteProfileGatePhone = ""
                    isPresentingInviteProfileGate = true
                    return
                }
                throw error
            }

            inviteProfileGateName = snapshot.name ?? ""
            inviteProfileGatePhone = snapshot.phone ?? ""

            let nameMissing = (snapshot.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Hard gate for name only. Phone remains optional for App Review compliance.
            if nameMissing {
                isPresentingInviteProfileGate = true
                return
            }

            await acceptInvite()
        } catch {
            if SupabaseManager.isProfilesAuthUserForeignKeyError(error) {
                await SupabaseManager.shared.signOut()
                isLoggedIn = false
                userRole = nil
                activeAlert = .inviteError(message: "로그인이 꼬였어요. 다시 로그인해주세요.")
            } else {
                activeAlert = .inviteError(message: AppErrorMessage.userMessage(error))
            }
        }
        #else
        await acceptInvite()
        #endif
    }

    @MainActor
    private func acceptInvite() async {
        #if canImport(Supabase)
        let token = pendingInvite?.token ?? pendingInviteToken ?? InviteManager.shared.pendingToken()
        guard let token else { return }
        do {
            try await InviteManager.shared.acceptPendingInvite(token: token)
            self.pendingInvite = nil
            self.pendingInviteToken = nil
            self.isPresentingInviteProfileGate = false
            self.activeAlert = nil
            NotificationCenter.default.post(name: .didAcceptInvite, object: nil)
        } catch {
            activeAlert = .inviteError(message: AppErrorMessage.userMessage(error))
        }
        #endif
    }
}

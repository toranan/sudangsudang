import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct WorkerProfileView: View {
    @State private var profileName: String = "알바생"
    @State private var profilePhone: String = ""
    @State private var profileEmail: String = ""

    @State private var loadError: String?
    @State private var isUserRefreshing = false
    @State private var isPresentingProfileEdit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "내 프로필")
                        VStack(alignment: .leading, spacing: 10) {
                            Text(profileName)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.appTextPrimary)

                            if !profilePhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(profilePhone)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                            }
                            if !profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(profileEmail)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                            }

                            Button("프로필 수정") {
                                isPresentingProfileEdit = true
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        .appCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "계정")
                        Button("로그아웃") {
                            Task {
                                await SupabaseManager.shared.signOut()
                                NotificationCenter.default.post(name: .didLogout, object: nil)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    if let loadError {
                        Text(loadError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .refreshable {
                await refreshFromUser()
            }
            .refreshStatusOverlay(isVisible: isUserRefreshing)
        }
        .sheet(isPresented: $isPresentingProfileEdit) {
            ProfileCompletionSheet(
                context: .init(
                    title: "프로필 수정",
                    message: "이름/전화번호를 수정할 수 있어요.",
                    primaryActionTitle: "저장",
                    showsSkip: false
                ),
                initialName: profileName,
                initialPhone: profilePhone,
                onSave: { name, phone in
                    Task {
                        #if canImport(Supabase)
                        do {
                            let userId = try await SupabaseManager.shared.currentUserId()
                            try await SupabaseManager.shared.patchProfile(id: userId, name: name, phone: phone)
                        } catch {
                            // ignore
                        }
                        #endif
                        await loadData()
                    }
                },
                onSkip: nil
            )
        }
        .task {
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptInvite)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await loadData() }
        }
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await loadData()
    }

    @MainActor
    private func loadData() async {
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            do {
                try await WorkerAutoRetirement.processForUser(userId: userId)
            } catch {
                if AppErrorMessage.isCancellation(error) {
                    return
                }
                #if DEBUG
                print("DEBUG: auto retirement (worker profile) failed: \(error.localizedDescription)")
                #endif
            }
            let snapshot = try await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            let trimmedName = (snapshot.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            profileName = trimmedName.isEmpty ? "알바생" : trimmedName
            profilePhone = snapshot.phone ?? ""
            profileEmail = snapshot.email ?? ""
            loadError = nil
        } catch {
            if AppErrorMessage.isCancellation(error) { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }
}

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
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("내 정보")
                            .font(.app(.callout, .medium))
                            .foregroundColor(.appTextSecondary)
                        Text("내 프로필")
                            .font(.system(size: 26, weight: .heavy))
                            .tracking(-0.6)
                            .foregroundColor(.appTextPrimary)
                    }
                    .padding(.horizontal, 4)

                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.appAccentSoft)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(String(profileName.prefix(1)))
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundColor(.appAccent)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(profileName)
                                .font(.app(.headline, .bold))
                                .foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            if !profilePhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(profilePhone)
                                    .font(.app(.caption))
                                    .foregroundColor(.appTextSecondary)
                            }
                            if !profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(profileEmail)
                                    .font(.app(.caption))
                                    .foregroundColor(.appTextSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }

                        Spacer(minLength: 8)

                        Button("수정") {
                            isPresentingProfileEdit = true
                        }
                        .font(.app(.caption, .bold))
                        .foregroundColor(.appTextPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.appFill, in: Capsule())
                        .buttonStyle(.plain)
                    }
                    .appCard()

                    NavigationLink {
                        InquiryView(role: "알바생")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appAccent)
                            Text("문의하기")
                                .font(.app(.body, .semibold))
                                .foregroundColor(.appTextPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.appTextSecondary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                    }
                    .buttonStyle(PressableRowStyle())

                    Text("계정")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(.appTextPrimary)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    Button {
                        Task {
                            await SupabaseManager.shared.signOut()
                            NotificationCenter.default.post(name: .didLogout, object: nil)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appWarning)
                            Text("로그아웃")
                                .font(.app(.body, .semibold))
                                .foregroundColor(.appWarning)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                    }
                    .buttonStyle(PressableRowStyle())

                    if let loadError {
                        Text(loadError)
                            .font(.app(.caption, .medium))
                            .foregroundColor(.appWarning)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .appRefreshable {
                await refreshFromUser()
            }
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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

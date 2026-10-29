import SwiftUI

struct OwnerRootView: View {
    private enum Tab: Hashable {
        case home
        case workers
        case schedule
        case approval
        case settings
    }

    @State private var selection: Tab = .home
    @State private var approvalFocus: ApprovalFocus?
    @AppStorage("did_show_profile_welcome_owner") private var didShowProfileWelcome = false
    @State private var isPresentingWelcomeProfileSheet = false
    @State private var welcomeName: String = ""
    @State private var welcomePhone: String = ""

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                StoreHomeView(onNavigateToApproval: { focus in
                    approvalFocus = focus
                    selection = .approval
                })
                    .toolbar(.hidden, for: .navigationBar)
            }
            .hidesSystemTabBar()
            .tag(Tab.home)

            NavigationStack {
                WorkerManagementView()
                    .toolbar(.hidden, for: .navigationBar)
            }
            .hidesSystemTabBar()
            .tag(Tab.workers)

            NavigationStack {
                ScheduleManagementView()
                    .toolbar(.hidden, for: .navigationBar)
            }
            .hidesSystemTabBar()
            .tag(Tab.schedule)

            NavigationStack {
                ApprovalView(focus: $approvalFocus)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .hidesSystemTabBar()
            .tag(Tab.approval)

            NavigationStack {
                OwnerSettingsView()
                    .toolbar(.hidden, for: .navigationBar)
            }
            .hidesSystemTabBar()
            .tag(Tab.settings)
        }
        .appTabBar(selection: $selection, items: [
            AppTabItem(tag: .home, title: "홈", systemImage: "house.fill"),
            AppTabItem(tag: .workers, title: "알바관리", systemImage: "person.2.fill"),
            AppTabItem(tag: .schedule, title: "스케줄", systemImage: "calendar"),
            AppTabItem(tag: .approval, title: "승인", systemImage: "checkmark.circle.fill"),
            AppTabItem(tag: .settings, title: "설정", systemImage: "gearshape.fill")
        ])
        .tint(.appAccent)
        .task {
            await maybeShowProfileWelcome()
        }
        .sheet(isPresented: $isPresentingWelcomeProfileSheet) {
            ProfileCompletionSheet(
                context: .init(
                    title: "환영합니다!",
                    message: "원활한 사용을 위해 프로필을 완성할 수 있어요.",
                    primaryActionTitle: "완성하기",
                    showsSkip: true
                ),
                initialName: welcomeName,
                initialPhone: welcomePhone,
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
                        didShowProfileWelcome = true
                    }
                },
                onSkip: {
                    didShowProfileWelcome = true
                }
            )
        }
    }

    @MainActor
    private func maybeShowProfileWelcome() async {
        if didShowProfileWelcome { return }
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            let snapshot = try await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            welcomeName = snapshot.name ?? ""
            welcomePhone = snapshot.phone ?? ""
            let nameMissing = (snapshot.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let phoneMissing = (snapshot.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if nameMissing || phoneMissing {
                isPresentingWelcomeProfileSheet = true
            } else {
                didShowProfileWelcome = true
            }
        } catch {
            // If network fails, don't block.
        }
        #else
        didShowProfileWelcome = true
        #endif
    }
}

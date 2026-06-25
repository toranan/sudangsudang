import SwiftUI

struct WorkerRootView: View {
    @AppStorage("did_show_profile_welcome_worker") private var didShowProfileWelcome = false
    @State private var isPresentingWelcomeProfileSheet = false
    @State private var welcomeName: String = ""
    @State private var welcomePhone: String = ""

    var body: some View {
        TabView {
            WorkerHomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("출퇴근")
                }

            WorkerCalendarView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("달력")
                }
            
            MyHistoryView()
                .tabItem {
                    Image(systemName: "clock.fill")
                    Text("내 기록")
                }

            WorkerProfileView()
                .tabItem {
                    Image(systemName: "person.crop.circle.fill")
                    Text("내 프로필")
                }
        }
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

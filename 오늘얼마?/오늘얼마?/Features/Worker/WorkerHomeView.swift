import SwiftUI
import Combine
#if canImport(Supabase)
import Supabase
#endif

struct WorkerHomeView: View {
    struct StorePay: Identifiable {
        let id: UUID
        let workerId: UUID
        let name: String
        let isPersonal: Bool
        let hourlyWage: Double
        let applyWeeklyAllowance: Bool
        let deductionType: PayrollDeductionType
        let todayMinutes: Int
        let todayPay: Double
        let monthMinutes: Int
        let monthPay: Double
        let monthNetPay: Double

        var todayWorkedText: String { WorkerHomeView.formatHours(todayMinutes) }
        var monthWorkedText: String { WorkerHomeView.formatHours(monthMinutes) }
        var todayPayText: String { WorkerHomeView.formatWon(todayPay) }
        var monthPayText: String { WorkerHomeView.formatWon(monthPay) }
        var monthNetPayText: String { WorkerHomeView.formatWon(monthNetPay) }
    }

    struct WorkerRow: Decodable {
        let id: UUID
        let store_id: UUID
        let hourly_wage: Double?
        let apply_weekly_allowance: Bool?
        let deduction_type: String?
        let stores: StoreName?
    }

    struct StoreName: Decodable {
        let name: String
        let is_personal: Bool?
    }

    struct LogRow: Decodable {
        let store_id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
    }

    @State private var storePays: [StorePay] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var lastLoadedAt: Date?
    @State private var isPresentingJoinStore = false
    @State private var isPresentingPersonalStore = false
    @State private var isPresentingJoinProfileGate = false
    @State private var joinProfileGateName: String = ""
    @State private var joinProfileGatePhone: String = ""
    @State private var pendingJoinToken: String?
    @State private var profileGateSaveCompleted = false
    @State private var pendingDeleteStore: StorePay?
    @State private var isShowingDeleteConfirm = false
    @State private var deleteError: String?
    @State private var isShowingDeleteAccountConfirm = false
    @State private var isShowingDeleteAccountError = false
    @State private var deleteAccountErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerStrip

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "내 매장별 급여")

                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .appCard()
                        } else if storePays.isEmpty {
                            Text("등록된 매장이 없어요.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                                .appCard()
                            Button(action: { isPresentingJoinStore = true }) {
                                Text("초대코드 입력하기")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            Button(action: { isPresentingPersonalStore = true }) {
                                Text("매장 추가하기")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        } else {
                            VStack(spacing: 10) {
                                ForEach(storePays) { store in
                                    NavigationLink {
                                        WorkerCheckInView(store: store)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                Text(store.name)
                                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                    .foregroundColor(.appTextSecondary)
                                                Spacer()
                                                Menu {
                                                    Button(role: .destructive) {
                                                        pendingDeleteStore = store
                                                        isShowingDeleteConfirm = true
                                                    } label: {
                                                        Text("삭제")
                                                    }
                                                } label: {
                                                    Image(systemName: "ellipsis")
                                                        .foregroundColor(.appLine)
                                                        .padding(.horizontal, 4)
                                                }
                                                Image(systemName: "chevron.right")
                                                    .foregroundColor(.appLine)
                                            }
                                            HStack(alignment: .bottom) {
                                                Text(store.todayPayText)
                                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                                    .foregroundColor(.appTextPrimary)
                                                Spacer()
                                                Text("오늘 \(store.todayWorkedText)")
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .foregroundColor(.appTextSecondary)
                                            }
                                            HStack {
                                                Text("이번 달 \(store.monthWorkedText)")
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .foregroundColor(.appTextSecondary)
                                                Spacer()
                                                Text(store.monthPayText)
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                    .foregroundColor(.appTextSecondary)
                                            }
                                            HStack {
                                                Text("세후 예상")
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .foregroundColor(.appTextSecondary)
                                                Spacer()
                                                Text(store.monthNetPayText)
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                    .foregroundColor(.appTextSecondary)
                                            }
                                        }
                                        .padding(14)
                                        .background(Color.appSurface)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.appLine, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button(action: { isPresentingJoinStore = true }) {
                                    Text("초대코드 입력하기")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                Button(action: { isPresentingPersonalStore = true }) {
                                    Text("매장 추가하기")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }

                        if let loadError {
                            Text(loadError)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appWarning)
                        }
                        if let deleteError {
                            Text(deleteError)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appWarning)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                await loadData(force: true)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadData(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptInvite)) { _ in
            Task { await loadData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .payrollSettingsDidChange)) { _ in
            Task { await loadData(force: true) }
        }
        .alert("매장을 삭제하시겠습니까?", isPresented: $isShowingDeleteConfirm) {
            Button("삭제", role: .destructive) {
                guard let store = pendingDeleteStore else { return }
                Task { await deleteStore(store) }
            }
            Button("취소", role: .cancel) {
                pendingDeleteStore = nil
            }
        }
        .alert("계정을 삭제하시겠습니까?", isPresented: $isShowingDeleteAccountConfirm) {
            Button("삭제", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("모든 데이터가 삭제되며 복구할 수 없습니다.")
        }
        .alert("계정 삭제 실패", isPresented: $isShowingDeleteAccountError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(deleteAccountErrorMessage ?? "잠시 후 다시 시도해주세요.")
        }
        .sheet(isPresented: $isPresentingJoinStore) {
            JoinStoreView { token in
                Task {
                    await beginJoinStoreFlow(token: token)
                }
            }
        }
        .sheet(isPresented: $isPresentingPersonalStore) {
            CreatePersonalStoreView { name, address in
                Task {
                    await createPersonalStore(name: name, address: address)
                }
            }
        }
        .sheet(isPresented: $isPresentingJoinProfileGate, onDismiss: {
            guard profileGateSaveCompleted, let token = pendingJoinToken else { return }
            profileGateSaveCompleted = false
            let savedName = joinProfileGateName
            let savedPhone = joinProfileGatePhone
            Task {
                #if DEBUG
                print("DEBUG: profile gate dismissed. name=\(savedName) phone=\(savedPhone) token=\(token)")
                #endif
                // 1) 프로필 저장
                #if canImport(Supabase)
                do {
                    let userId = try await SupabaseManager.shared.currentUserId()
                    try await SupabaseManager.shared.patchProfile(
                        id: userId,
                        name: savedName.isEmpty ? nil : savedName,
                        phone: savedPhone.isEmpty ? nil : savedPhone
                    )
                    #if DEBUG
                    print("DEBUG: patchProfile succeeded")
                    #endif
                } catch {
                    #if DEBUG
                    print("DEBUG: patchProfile failed: \(error.localizedDescription)")
                    #endif
                }
                #endif
                // 2) 매장 추가
                await joinStore(token: token)
            }
        }) {
            ProfileCompletionSheet(
                context: .init(
                    title: "프로필을 설정할까요?",
                    message: "사장님과의 연동을 위해 이름 입력이 필요해요. 전화번호는 선택입니다.",
                    primaryActionTitle: "저장하고 추가",
                    showsSkip: false,
                    requiresName: true
                ),
                initialName: joinProfileGateName,
                initialPhone: joinProfileGatePhone,
                onSave: { name, phone in
                    // ⚠️ async 작업 금지 — 메모리 충돌 방지
                    // 값만 @State에 저장하고 onDismiss에서 처리
                    joinProfileGateName = name ?? ""
                    joinProfileGatePhone = phone ?? ""
                    profileGateSaveCompleted = true
                },
                onSkip: nil
            )
        }
    }

    private var headerStrip: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("오늘 내 일")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Text("근무 매장 선택")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
            }
            Spacer()
            Menu {
                Button("로그아웃", role: .destructive) {
                    Task {
                        await SupabaseManager.shared.signOut()
                        NotificationCenter.default.post(name: .didLogout, object: nil)
                    }
                }
                Button("계정 삭제", role: .destructive) {
                    isShowingDeleteAccountConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(.horizontal, 4)
    }

    @MainActor
    private func loadData(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        // Cache: avoid re-fetching on every view transition.
        // Pull-to-refresh or explicit events should pass force=true.
        if !force,
           let lastLoadedAt,
           now.timeIntervalSince(lastLoadedAt) < 45 {
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            loadError = nil
            let userId = try await SupabaseManager.shared.currentUserId()
            let workers: [WorkerRow]
            do {
                workers = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .select("id,store_id,hourly_wage,apply_weekly_allowance,deduction_type,stores(name,is_personal)")
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                    .value
            } catch {
                // Backward-compatible fetch if DB migration isn't applied yet.
                let message = error.localizedDescription.lowercased()
                if message.contains("apply_weekly_allowance") || message.contains("deduction_type") {
                    workers = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,store_id,hourly_wage,stores(name,is_personal)")
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                        .value
                } else {
                    throw error
                }
            }

            if workers.isEmpty {
                storePays = []
                lastLoadedAt = now
                return
            }

            let workerIds = workers.map { $0.id.uuidString }
            let calendar = Calendar.current
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let iso = ISO8601DateFormatter()

            let logs: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("store_id,worker_id,check_in_at,check_out_at,status")
                .in("worker_id", values: workerIds)
                .gte("check_in_at", value: iso.string(from: monthStart))
                .lt("check_in_at", value: iso.string(from: monthEnd))
                .execute()
                .value

            let todayStart = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? Date()

            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var result: [StorePay] = []
            for worker in workers {
                let storeId = worker.store_id
                let wage = worker.hourly_wage ?? 0
                let storeName = worker.stores?.name ?? "매장"
                let isPersonal = worker.stores?.is_personal ?? false
                var applyWeeklyAllowance = worker.apply_weekly_allowance ?? false
                var deductionType = PayrollDeductionType(rawValue: worker.deduction_type ?? "") ?? .withholding
                if isPersonal, let local = PayrollLocalSettingsStore.load(workerId: worker.id) {
                    applyWeeklyAllowance = local.applyWeeklyAllowance
                    deductionType = local.deductionType
                }

                let storeLogs = logs.filter { $0.store_id == storeId && $0.worker_id == worker.id }
                let countedLogs = storeLogs.filter { ($0.status ?? "pending") != "rejected" }

                var monthMinutes = 0
                var todayMinutes = 0

                for log in countedLogs {
                    let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                    let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                    let minutes = WorkerHomeView.calcMinutes(checkIn: checkIn, checkOut: checkOut)
                    monthMinutes += minutes
                    if checkIn >= todayStart && checkIn < tomorrow {
                        todayMinutes += minutes
                    }
                }

                let monthGross = Double(monthMinutes) / 60.0 * wage
                let weeklyAllowance = applyWeeklyAllowance
                    ? PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: countedLogs.map { ($0.check_in_at, $0.check_out_at) }, wage: wage)
                    : 0
                let breakdown = PayrollCalculator.deductionBreakdown(gross: monthGross + weeklyAllowance, type: deductionType)
                let monthNet = max(0, monthGross + weeklyAllowance - breakdown.totalDeduction)

                let storePay = StorePay(
                    id: storeId,
                    workerId: worker.id,
                    name: storeName,
                    isPersonal: isPersonal,
                    hourlyWage: wage,
                    applyWeeklyAllowance: applyWeeklyAllowance,
                    deductionType: deductionType,
                    todayMinutes: todayMinutes,
                    todayPay: Double(todayMinutes) / 60.0 * wage,
                    monthMinutes: monthMinutes,
                    monthPay: monthGross,
                    monthNetPay: monthNet
                )
                result.append(storePay)
            }

            storePays = result
            lastLoadedAt = now
        } catch {
            loadError = error.localizedDescription
        }
        #endif
    }

    @MainActor
    private func deleteAccount() async {
        do {
            try await SupabaseManager.shared.deleteAccount()
            await SupabaseManager.shared.signOut()
            NotificationCenter.default.post(name: .didLogout, object: nil)
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
            isShowingDeleteAccountError = true
        }
    }

    @MainActor
    private func deleteStore(_ store: StorePay) async {
        #if canImport(Supabase)
        do {
            if store.isPersonal == true {
                _ = try await SupabaseManager.shared
                    .client
                    .from("stores")
                    .delete()
                    .eq("id", value: store.id.uuidString)
                    .execute()
            } else {
                let userId = try await SupabaseManager.shared.currentUserId()
                _ = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .delete()
                    .eq("store_id", value: store.id.uuidString)
                    .eq("user_id", value: userId.uuidString)
                    .execute()
            }
            pendingDeleteStore = nil
            await loadData(force: true)
        } catch {
            deleteError = error.localizedDescription
        }
        #endif
    }

    @MainActor
    private func beginJoinStoreFlow(token: String) async {
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            pendingJoinToken = token
            #if DEBUG
            print("DEBUG: beginJoinStoreFlow start. userId=\(userId) token=\(token)")
            #endif

            let snapshot: SupabaseManager.ProfileSnapshot
            do {
                snapshot = try await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            } catch {
                // If the profile row doesn't exist yet, create a minimal one and continue with the name gate.
                if SupabaseManager.isPostgrestSingleObjectCoerceError(error) {
                    #if DEBUG
                    print("DEBUG: profile snapshot missing. creating minimal profile row. userId=\(userId)")
                    #endif
                    try await SupabaseManager.shared.ensureMinimalProfileRow(
                        id: userId,
                        email: nil,
                        role: .worker
                    )
                    joinProfileGateName = ""
                    joinProfileGatePhone = ""
                    isPresentingJoinProfileGate = true
                    #if DEBUG
                    print("DEBUG: showing profile gate sheet (name required). userId=\(userId)")
                    #endif
                    return
                }
                throw error
            }

            joinProfileGateName = snapshot.name ?? ""
            joinProfileGatePhone = snapshot.phone ?? ""

            let nameMissing = (snapshot.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            #if DEBUG
            print("DEBUG: profile snapshot loaded. nameMissing=\(nameMissing) name='\(snapshot.name ?? "nil")' phone='\(snapshot.phone ?? "nil")'")
            #endif

            // Hard gate for name only. Phone remains optional for App Review compliance.
            if nameMissing {
                isPresentingJoinProfileGate = true
                #if DEBUG
                print("DEBUG: showing profile gate sheet (name missing). userId=\(userId)")
                #endif
                return
            }

            await joinStore(token: token)
        } catch {
            if SupabaseManager.isProfilesAuthUserForeignKeyError(error) {
                // Local custom session can become inconsistent with Supabase Auth (auth.users).
                // Force a clean logout so the user can log in again.
                await SupabaseManager.shared.signOut()
                NotificationCenter.default.post(name: .didLogout, object: nil)
                loadError = "로그인이 꼬였어요. 다시 로그인해주세요."
            } else {
                loadError = error.localizedDescription
            }
            #if DEBUG
            print("DEBUG: beginJoinStoreFlow failed. error=\(error)")
            #endif
        }
        #else
        await joinStore(token: token)
        #endif
    }

    @MainActor
    private func joinStore(token: String) async {
        #if canImport(Supabase)
        do {
            #if DEBUG
            print("DEBUG: joinStore start. token=\(token)")
            #endif
            try await SupabaseManager.shared.acceptInvite(token: token)
            pendingJoinToken = nil
            isPresentingJoinProfileGate = false
            #if DEBUG
            print("DEBUG: joinStore success. token=\(token). reloading data.")
            #endif
            NotificationCenter.default.post(name: .didAcceptInvite, object: nil)
            await loadData(force: true)
        } catch {
            loadError = "초대코드 추가 실패: \(error.localizedDescription)"
            #if DEBUG
            print("DEBUG: joinStore failed. token=\(token) error=\(error)")
            #endif
        }
        #endif
    }

    @MainActor
    private func createPersonalStore(name: String, address: String) async {
        #if canImport(Supabase)
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            struct StoreInsert: Encodable {
                let name: String
                let address: String?
                let owner_id: UUID
                let is_personal: Bool
            }
            let payload = StoreInsert(
                name: name,
                address: address.isEmpty ? nil : address,
                owner_id: ownerId,
                is_personal: true
            )
            _ = try await SupabaseManager.shared
                .client
                .from("stores")
                .insert(payload)
                .execute()
            await loadData(force: true)
        } catch {
            loadError = error.localizedDescription
        }
        #endif
    }

    private static func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        let end = checkOut ?? Date()
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }

    private static func formatWon(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: Int(value))) ?? "0"
        return "\(number)원"
    }

    private static func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)시간 \(m)분"
    }
}

struct JoinStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token: String = ""
    @State private var error: String?

    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("초대코드 입력하기")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("초대코드")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    TextField("사장님이 보내준 초대코드를 입력", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appLine, lineWidth: 1)
                        )
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appWarning)
                }

                Button("추가하기") {
                    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        error = "초대코드를 입력해주세요."
                        return
                    }
                    onSubmit(trimmed)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("닫기") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())

                Spacer()
            }
            .padding(20)
            .navigationTitle("초대코드 입력하기")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}

struct CreatePersonalStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var searchResults: [KakaoPlace] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isSearchExpanded = true

    let onSubmit: (String, String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .appCard()
                    } else if !searchResults.isEmpty && isSearchExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(searchResults) { place in
                                Button(action: {
                                    name = place.placeName
                                    address = place.displayAddress
                                    isSearchExpanded = false
                                    hideKeyboard()
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.placeName)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.appTextPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(place.displayAddress)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.appTextSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(12)
                                    .background(Color.appSurface)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.appLine, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let searchError {
                        Text(searchError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("매장 이름")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        HStack(spacing: 8) {
                            TextField("강남 1호점", text: $name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { Task { await searchPlaces() } }
                                .padding(12)
                                .background(Color.appSurface)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.appLine, lineWidth: 1)
                                )
                            Button("검색") {
                                Task { await searchPlaces() }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(width: 80)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("주소 (선택)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("서울 강남구 ...", text: $address)
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }

                    Button(action: {
                        onSubmit(name, address)
                        dismiss()
                    }) {
                        Text("등록하기")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                }
                .padding(20)
            }
            .navigationTitle("매장 추가하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var kakaoRestApiKey: String? {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = info["KAKAO_REST_API_KEY"] as? String
        return (key?.isEmpty == false) ? key : nil
    }

    @MainActor
    private func searchPlaces() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = "검색어를 입력해주세요."
            return
        }
        guard let apiKey = kakaoRestApiKey else {
            searchError = "KAKAO_REST_API_KEY가 설정되어 있지 않습니다."
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let results = try await KakaoLocalSearch.search(query: trimmed, apiKey: apiKey)
            searchResults = results
            isSearchExpanded = true
        } catch {
            searchError = error.localizedDescription
        }
    }

    private struct KakaoSearchResponse: Decodable {
        let documents: [KakaoPlace]
    }

    private struct KakaoPlace: Decodable, Identifiable {
        let id: String
        let placeName: String
        let addressName: String?
        let roadAddressName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case placeName = "place_name"
            case addressName = "address_name"
            case roadAddressName = "road_address_name"
        }

        var displayAddress: String {
            if let roadAddressName, !roadAddressName.isEmpty {
                return roadAddressName
            }
            return addressName ?? "-"
        }
    }

    private enum KakaoLocalSearch {
        static func search(query: String, apiKey: String) async throws -> [KakaoPlace] {
            var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")
            components?.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "size", value: "10")
            ]
            guard let url = components?.url else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "KakaoSearch", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "검색 요청에 실패했습니다. (HTTP \(http.statusCode))"
                ])
            }

            let decoded = try JSONDecoder().decode(KakaoSearchResponse.self, from: data)
            return decoded.documents
        }
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

struct WorkerCheckInView: View {
    let store: WorkerHomeView.StorePay
    @State private var isCheckedIn: Bool = false
    @State private var currentLogId: UUID?
    @State private var currentCheckInAt: Date?
    @State private var liveMinutes: Int = 0
    @State private var isLoadingAction: Bool = false
    @State private var actionError: String?
    @State private var logs: [WorkLogRow] = []
    @State private var isLoadingLogs = false
    @State private var monthLogsForNet: [WorkLogRow] = []
    @State private var isLoadingMonthLogsForNet = false
    @State private var manualHours: String = ""
    @State private var manualMinutes: String = ""
    @State private var isSavingManual = false
    @State private var manualError: String?
    @State private var applyWeeklyAllowance: Bool = false
    @State private var deductionType: PayrollDeductionType = .withholding
    private var allowManualAdd: Bool { store.isPersonal }
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                VStack(alignment: .leading, spacing: 10) {
                    Text("오늘 근무")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("근무 시간")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Text(formatHours(displayMinutes))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("예상 급여")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Text(formatWon(displayPay))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                        }
                    }
                    .appCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("이번 달 요약")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("총 근무 시간")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Text(store.monthWorkedText)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("세전 예상")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Text(store.monthPayText)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("세후 예상 \(monthNetPayText())")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                    .appCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "세후 설정")
                    if store.isPersonal {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $applyWeeklyAllowance) {
                                Text("주휴수당 적용")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                            .onChange(of: applyWeeklyAllowance) { _ in
                                persistLocalPayrollSettings()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("공제 방식 (택 1)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Picker("", selection: $deductionType) {
                                    ForEach(PayrollDeductionType.allCases) { option in
                                        Text(option.title).tag(option)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: deductionType) { _ in
                                    persistLocalPayrollSettings()
                                }
                            }

                            Text("개인 매장의 세후 설정은 이 기기에서만 저장돼요.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                        }
                        .appCard()
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("사장님이 설정한 기준이 적용돼요.")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                            Text("공제 방식: \(store.deductionType.title)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Text("주휴수당: \(store.applyWeeklyAllowance ? "적용" : "미적용")")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                        }
                        .appCard()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "출퇴근")
                    VStack(spacing: 12) {
                        Button(action: {
                            Task { await toggleCheckIn() }
                        }) {
                            HStack {
                                Image(systemName: isCheckedIn ? "stop.fill" : "play.fill")
                                Text(isCheckedIn ? "퇴근하기" : "출근하기")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(backgroundColor: isCheckedIn ? .appWarning : .appAccent))
                        .disabled(isLoadingAction)
                        .opacity(isLoadingAction ? 0.6 : 1.0)

                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.appTextSecondary)
                            Text(isCheckedIn ? "\(store.name)에서 근무 중" : "\(store.name) 출근 대기")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                    if let actionError {
                        Text(actionError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "내역")
                    if isLoadingLogs {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .appCard()
                    } else if logs.isEmpty {
                        Text("근무 내역이 없어요.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                            .appCard()
                    } else {
                        VStack(spacing: 10) {
                            ForEach(logs) { log in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(formatDate(log.check_in_at))
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        Spacer()
                                        StatusPill(text: statusLabel(log.status), color: statusColor(log.status))
                                    }
                                    Text(formatTimeRange(log))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text(formatHours(calcMinutes(checkIn: log.check_in_at, checkOut: log.check_out_at)))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                }
                                .padding(12)
                                .background(Color.appSurface)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.appLine, lineWidth: 1)
                                )
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "근무 추가")
                    if allowManualAdd {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("시간")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                TextField("예: 3", text: $manualHours)
                                    .keyboardType(.numberPad)
                                    .padding(10)
                                    .background(Color.appSurface)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.appLine, lineWidth: 1)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("분")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                TextField("예: 30", text: $manualMinutes)
                                    .keyboardType(.numberPad)
                                    .padding(10)
                                    .background(Color.appSurface)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.appLine, lineWidth: 1)
                                    )
                            }
                        }

                        if let manualError {
                            Text(manualError)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appWarning)
                        }

                        Button(action: {
                            Task { await addManualWork() }
                        }) {
                            Text(isSavingManual ? "추가 중..." : "근무 추가")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isSavingManual)
                        .opacity(isSavingManual ? 0.6 : 1.0)
                    } else {
                        Text("사장님과 연동된 근무는 직접 추가할 수 없어요.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                            .appCard()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            applyWeeklyAllowance = store.applyWeeklyAllowance
            deductionType = store.deductionType
            await loadCurrentLog()
            await loadLogs()
            await loadMonthLogsForNet()
        }
        .onReceive(timer) { _ in
            updateLiveMinutes()
        }
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("오늘 내 일")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Text(store.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                StatusPill(text: isCheckedIn ? "근무 중" : "출근 전", color: isCheckedIn ? .appPositive : .appTextSecondary)
            }
            Spacer()
            Circle()
                .fill(Color.appLine)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "clock.fill")
                        .foregroundColor(.appTextSecondary)
                )
        }
        .appCard()
    }
}

private extension WorkerCheckInView {
    var displayMinutes: Int {
        isCheckedIn ? liveMinutes : store.todayMinutes
    }

    var displayPay: Double {
        Double(displayMinutes) / 60.0 * store.hourlyWage
    }

    func updateLiveMinutes() {
        guard isCheckedIn, let checkIn = currentCheckInAt else { return }
        let minutes = floor(Date().timeIntervalSince(checkIn) / 60.0)
        liveMinutes = max(store.todayMinutes, Int(minutes))
    }

    func persistLocalPayrollSettings() {
        guard store.isPersonal else { return }
        PayrollLocalSettingsStore.save(
            workerId: store.workerId,
            settings: PayrollLocalSettings(
                applyWeeklyAllowance: applyWeeklyAllowance,
                deductionType: deductionType
            )
        )
        NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
    }

    func monthNetPayText() -> String {
        formatWon(monthNetPay())
    }

    func monthNetPay() -> Double {
        // If monthly logs are not loaded yet, use the list-computed value.
        if isLoadingMonthLogsForNet || monthLogsForNet.isEmpty {
            return store.monthNetPay
        }

        let counted = monthLogsForNet.filter { $0.status != "rejected" }
        let wage = store.hourlyWage

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        let totalMinutes = counted.reduce(0) { partial, log in
            let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
            let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
            return partial + PayrollCalculator.calcMinutes(checkIn: start, checkOut: end)
        }

        let gross = Double(totalMinutes) / 60.0 * wage
        let weeklyAllowance = applyWeeklyAllowance
            ? PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: counted.map { ($0.check_in_at, $0.check_out_at) }, wage: wage)
            : 0
        let breakdown = PayrollCalculator.deductionBreakdown(gross: gross + weeklyAllowance, type: deductionType)
        return max(0, gross + weeklyAllowance - breakdown.totalDeduction)
    }

    func formatWon(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: Int(value))) ?? "0"
        return "\(number)원"
    }

    func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)시간 \(m)분"
    }

    @MainActor
    func loadCurrentLog() async {
        #if canImport(Supabase)
        do {
            struct LogRow: Decodable { let id: UUID; let check_in_at: String }
            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .is("check_out_at", value: nil)
                .order("check_in_at", ascending: false)
                .limit(1)
                .execute()
                .value
            currentLogId = rows.first?.id
            isCheckedIn = currentLogId != nil
            if let row = rows.first {
                let parser = ISO8601DateFormatter()
                parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                currentCheckInAt = parser.date(from: row.check_in_at) ?? ISO8601DateFormatter().date(from: row.check_in_at)
                updateLiveMinutes()
            } else {
                currentCheckInAt = nil
                liveMinutes = store.todayMinutes
            }
        } catch {
            actionError = error.localizedDescription
        }
        #endif
    }

    @MainActor
    func toggleCheckIn() async {
        #if canImport(Supabase)
        isLoadingAction = true
        actionError = nil
        defer { isLoadingAction = false }
        do {
            if let logId = currentLogId {
                struct UpdatePayload: Encodable { let check_out_at: String }
                let iso = ISO8601DateFormatter()
                let payload = UpdatePayload(check_out_at: iso.string(from: Date()))
                _ = try await SupabaseManager.shared
                    .client
                    .from("work_logs")
                    .update(payload)
                    .eq("id", value: logId.uuidString)
                    .execute()
                currentLogId = nil
                isCheckedIn = false
                currentCheckInAt = nil
                NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
            } else {
                struct InsertPayload: Encodable {
                    let store_id: UUID
                    let worker_id: UUID
                    let check_in_at: String
                }
                let iso = ISO8601DateFormatter()
                let now = Date()
                let payload = InsertPayload(
                    store_id: store.id,
                    worker_id: store.workerId,
                    check_in_at: iso.string(from: now)
                )
                struct InsertedRow: Decodable { let id: UUID }
                let row: InsertedRow = try await SupabaseManager.shared
                    .client
                    .from("work_logs")
                    .insert(payload)
                    .select("id")
                    .single()
                    .execute()
                    .value
                currentLogId = row.id
                isCheckedIn = true
                currentCheckInAt = now
                updateLiveMinutes()
                NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
            }
        } catch {
            actionError = error.localizedDescription
        }
        #endif
    }

    struct WorkLogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String
    }

    @MainActor
    func loadLogs() async {
        #if canImport(Supabase)
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        do {
            let rows: [WorkLogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .order("check_in_at", ascending: false)
                .limit(30)
                .execute()
                .value
            logs = rows
        } catch {
            actionError = error.localizedDescription
        }
        #endif
    }

    @MainActor
    func loadMonthLogsForNet() async {
        #if canImport(Supabase)
        isLoadingMonthLogsForNet = true
        defer { isLoadingMonthLogsForNet = false }
        do {
            let calendar = Calendar.current
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let iso = ISO8601DateFormatter()
            let rows: [WorkLogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .gte("check_in_at", value: iso.string(from: monthStart))
                .lt("check_in_at", value: iso.string(from: monthEnd))
                .limit(500)
                .execute()
                .value
            monthLogsForNet = rows
        } catch {
            // Ignore: we'll keep showing list-computed net.
        }
        #endif
    }

    @MainActor
    func addManualWork() async {
        #if canImport(Supabase)
        isSavingManual = true
        manualError = nil
        defer { isSavingManual = false }

        let h = Int(manualHours.filter { $0.isNumber }) ?? 0
        let m = Int(manualMinutes.filter { $0.isNumber }) ?? 0
        let totalMinutes = h * 60 + m
        guard totalMinutes > 0 else {
            manualError = "근무 시간을 입력해주세요."
            return
        }

        let calendar = Calendar.current
        let today = Date()
        let dayStart = calendar.startOfDay(for: today)
        let endDate = Date()
        var checkIn = endDate.addingTimeInterval(TimeInterval(-totalMinutes * 60))
        if checkIn < dayStart {
            checkIn = dayStart
        }

        struct InsertPayload: Encodable {
            let store_id: UUID
            let worker_id: UUID
            let check_in_at: String
            let check_out_at: String
            let status: String
        }
        let iso = ISO8601DateFormatter()
        let payload = InsertPayload(
            store_id: store.id,
            worker_id: store.workerId,
            check_in_at: iso.string(from: checkIn),
            check_out_at: iso.string(from: endDate),
            status: "pending"
        )
        do {
            _ = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .insert(payload)
                .execute()
            manualHours = ""
            manualMinutes = ""
            await loadLogs()
            await loadMonthLogsForNet()
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
        } catch {
            manualError = error.localizedDescription
        }
        #endif
    }

    func statusLabel(_ status: String) -> String {
        status == "approved" ? "승인" : (status == "rejected" ? "반려" : "대기")
    }

    func statusColor(_ status: String) -> Color {
        status == "approved" ? .appPositive : (status == "rejected" ? .appWarning : .appTextSecondary)
    }

    func formatDate(_ isoString: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let date = parser.date(from: isoString) ?? iso.date(from: isoString) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    func formatTimeRange(_ log: WorkLogRow) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
        let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let startText = formatter.string(from: start)
        let endText = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(startText) - \(endText)"
    }

    func calcMinutes(checkIn: String, checkOut: String?) -> Int {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        let minutes = floor(end.timeIntervalSince(start) / 60.0)
        return max(0, Int(minutes))
    }

    func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

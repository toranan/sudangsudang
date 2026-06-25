import SwiftUI
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(Supabase)
import Supabase
#endif

struct WorkerHomeView: View {
    struct StorePay: Identifiable, Hashable {
        let id: UUID
        let workerId: UUID
        let name: String
        let isPersonal: Bool
        let hourlyWage: Double
        let applyWeeklyAllowance: Bool
        let applyNightAllowance: Bool
        let deductionType: PayrollDeductionType
        let payday: Int
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
        var paydayText: String { "\(payday)일" }
        var nextPaydayDateText: String {
            WorkerHomeView.formatDate(PayrollPayday.nextPaydayDate(payday: payday))
        }
    }

    struct WorkerRow: Decodable {
        let id: UUID
        let store_id: UUID
        let hourly_wage: Double?
        let apply_weekly_allowance: Bool?
        let deduction_type: String?
        let apply_night_allowance: Bool?
        let payday: Int?
        let is_active: Bool?
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
    @State private var isUserRefreshing = false
    @State private var loadError: String?
    @State private var lastLoadedAt: Date?
    @State private var lastLoadedMonthKey: String?
    @State private var didBackfillPersonalLinks = false
    @State private var selectedMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
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
    @State private var deepLinkTargetStore: StorePay?
    @State private var pendingDeepLinkStoreId: UUID?

    var body: some View {
        presentedHomeContent
    }

    private var presentedHomeContent: some View {
        baseHomeContent
            .alert("퇴사처리하시겠습니까?", isPresented: $isShowingDeleteConfirm) {
                Button("퇴사하기", role: .destructive) {
                    guard let store = pendingDeleteStore else { return }
                    Task { await processRetirement(store) }
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
                        message: "사장님과의 연동을 위해 이름 입력이 필요해요. 전화번호도 입력할 수 있어요.",
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

    private var baseHomeContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerStrip
                    storePaySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                await refreshFromUser()
            }
            .refreshStatusOverlay(isVisible: isUserRefreshing)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $deepLinkTargetStore) { store in
                WorkerCheckInView(store: store)
            }
        }
        .task {
            await loadData(force: false)
            await processPendingDeepLink()
        }
        .onChange(of: selectedMonth) { _ in
            Task { await loadData(force: true) }
        }
        .onChange(of: storePays) { _ in
            resolvePendingDeepLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptInvite)) { _ in
            Task { await loadData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .payrollSettingsDidChange)) { _ in
            Task { await loadData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenWorkerCheckIn)) { note in
            guard let storeId = note.object as? UUID else { return }
            Task { await openStoreFromDeepLink(storeId: storeId) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await loadData(force: false) }
        }
    }

    @ViewBuilder
    private var storePaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "내 매장별 급여")

            if isLoading && storePays.isEmpty {
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
                        storePayCard(store)
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

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await loadData(force: true)
    }

    private func storePayCard(_ store: StorePay) -> some View {
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
                            Text("퇴사하기")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.appTextSecondary)
                            .padding(.horizontal, 4)
                    }
                }
                HStack(alignment: .bottom) {
                    Text(store.monthPayText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Text("\(monthTitle(selectedMonth)) \(store.monthWorkedText)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                }
                HStack {
                    Text("오늘 급여")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(store.todayPayText)
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

    @MainActor
    private func processPendingDeepLink() async {
        guard let pendingStoreId = WorkerDeepLinkManager.shared.pendingStoreId() else { return }
        await openStoreFromDeepLink(storeId: pendingStoreId)
    }

    @MainActor
    private func openStoreFromDeepLink(storeId: UUID) async {
        if let store = storePays.first(where: { $0.id == storeId }) {
            deepLinkTargetStore = nil
            await Task.yield()
            deepLinkTargetStore = store
            WorkerDeepLinkManager.shared.clearPendingStoreId()
            pendingDeepLinkStoreId = nil
            return
        }

        pendingDeepLinkStoreId = storeId
        await loadData(force: true)
        resolvePendingDeepLink()
    }

    @MainActor
    private func resolvePendingDeepLink() {
        guard let storeId = pendingDeepLinkStoreId else { return }
        guard let store = storePays.first(where: { $0.id == storeId }) else { return }
        deepLinkTargetStore = nil
        Task { @MainActor in
            await Task.yield()
            deepLinkTargetStore = store
            WorkerDeepLinkManager.shared.clearPendingStoreId()
            pendingDeepLinkStoreId = nil
        }
    }

    private var headerStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(action: moveToPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
                Spacer()
                Text(monthTitle(selectedMonth))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Spacer()
                Button(action: moveToNextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        if value.translation.width <= -30 {
                            moveToNextMonth()
                        } else if value.translation.width >= 30 {
                            moveToPreviousMonth()
                        }
                    }
            )

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("총급여")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Text(totalMonthPayText)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
            }

            HStack {
                Text("\(monthTitle(selectedMonth)) 총급여")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text("세후 예상 \(totalMonthNetPayText)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }
            HStack {
                Text("예상 환급금")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text(totalRefundEstimateText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private var totalMonthPayText: String {
        Self.formatWon(storePays.reduce(0) { $0 + $1.monthPay })
    }

    private var totalMonthNetPayText: String {
        Self.formatWon(storePays.reduce(0) { $0 + $1.monthNetPay })
    }

    private var totalRefundEstimateText: String {
        let total = storePays.reduce(0.0) { partial, store in
            let estimate = PayrollCalculator.estimateAnnualRefund(
                monthlyTaxablePay: store.monthPay,
                deductionType: store.deductionType
            )
            return partial + estimate.expectedRefund
        }
        return Self.formatWon(total)
    }
    @MainActor
    private func loadData(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        let monthKey = Self.monthKey(monthStart)
        // Cache: avoid re-fetching on every view transition.
        // Pull-to-refresh or explicit events should pass force=true.
        if !force,
           lastLoadedMonthKey == monthKey,
           let lastLoadedAt,
           now.timeIntervalSince(lastLoadedAt) < 120 {
            return
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            if !didBackfillPersonalLinks {
                didBackfillPersonalLinks = true
                await backfillPersonalStoreWorkerLinksIfNeeded(userId: userId)
            }
            do {
                try await WorkerAutoRetirement.processForUser(userId: userId)
            } catch {
                if AppErrorMessage.isCancellation(error) {
                    return
                }
                #if DEBUG
                print("DEBUG: auto retirement (worker home) failed: \(error.localizedDescription)")
                #endif
            }
            let workers: [WorkerRow]
            do {
                workers = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .select("id,store_id,hourly_wage,apply_weekly_allowance,deduction_type,apply_night_allowance,payday,is_active,stores(name,is_personal)")
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                    .value
            } catch {
                // Backward-compatible fetch if DB migration isn't applied yet.
                let message = error.localizedDescription.lowercased()
                if message.contains("apply_night_allowance") || message.contains("payday") {
                    workers = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,store_id,hourly_wage,apply_weekly_allowance,deduction_type,is_active,stores(name,is_personal)")
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                        .value
                } else if message.contains("apply_weekly_allowance") || message.contains("deduction_type") {
                    workers = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,store_id,hourly_wage,is_active,stores(name,is_personal)")
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                        .value
                } else {
                    throw error
                }
            }

            let activeWorkers = workers.filter { $0.is_active ?? true }

            if activeWorkers.isEmpty {
                storePays = []
                lastLoadedAt = now
                lastLoadedMonthKey = monthKey
                return
            }

            let workerIds = activeWorkers.map { $0.id.uuidString }
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

            let logsByWorkerId = Dictionary(grouping: logs, by: \.worker_id)
            var result: [StorePay] = []
            for worker in activeWorkers {
                let storeId = worker.store_id
                let wage = worker.hourly_wage ?? 0
                let storeName = worker.stores?.name ?? "매장"
                let isPersonal = worker.stores?.is_personal ?? false
                var applyWeeklyAllowance = worker.apply_weekly_allowance ?? false
                var deductionType = PayrollDeductionType(rawValue: worker.deduction_type ?? "") ?? .withholding
                var applyNightAllowance = worker.apply_night_allowance ?? false
                var payday = min(max(worker.payday ?? PayrollLocalSettings.defaultPayday, 1), 31)

                if isPersonal, let local = PayrollLocalSettingsStore.load(workerId: worker.id) {
                    applyNightAllowance = local.applyNightAllowance
                    payday = local.payday == 0 ? 31 : min(max(local.payday, 1), 31)
                    applyWeeklyAllowance = local.applyWeeklyAllowance
                    deductionType = local.deductionType
                }

                let storeLogs = logsByWorkerId[worker.id, default: []].filter { $0.store_id == storeId }
                let countedLogs = storeLogs.filter { log in
                    let status = log.status ?? "pending"
                    let hasCheckout = !(log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    return status == "approved" && hasCheckout
                }

                var monthMinutes = 0
                var todayMinutes = 0
                var monthNightMinutes = 0
                var todayNightMinutes = 0

                for log in countedLogs {
                    let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                    let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                    let minutes = WorkerHomeView.calcMinutes(checkIn: checkIn, checkOut: checkOut)
                    let nightMinutes = PayrollCalculator.calcNightMinutes(checkIn: checkIn, checkOut: checkOut)
                    monthMinutes += minutes
                    monthNightMinutes += nightMinutes
                    if checkIn >= todayStart && checkIn < tomorrow {
                        todayMinutes += minutes
                        todayNightMinutes += nightMinutes
                    }
                }

                let monthBasePay = Double(monthMinutes) / 60.0 * wage
                let monthNightPremium = applyNightAllowance ? Double(monthNightMinutes) / 60.0 * wage * PayrollCalculator.nightPremiumRate : 0
                let monthGross = monthBasePay + monthNightPremium
                let weeklyAllowance = applyWeeklyAllowance
                    ? PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: countedLogs.map { ($0.check_in_at, $0.check_out_at) }, wage: wage)
                    : 0
                let breakdown = PayrollCalculator.deductionBreakdown(gross: monthGross + weeklyAllowance, type: deductionType)
                let monthNet = max(0, monthGross + weeklyAllowance - breakdown.totalDeduction)
                let todayBasePay = Double(todayMinutes) / 60.0 * wage
                let todayNightPremium = applyNightAllowance ? Double(todayNightMinutes) / 60.0 * wage * PayrollCalculator.nightPremiumRate : 0

                let storePay = StorePay(
                    id: storeId,
                    workerId: worker.id,
                    name: storeName,
                    isPersonal: isPersonal,
                    hourlyWage: wage,
                    applyWeeklyAllowance: applyWeeklyAllowance,
                    applyNightAllowance: applyNightAllowance,
                    deductionType: deductionType,
                    payday: payday,
                    todayMinutes: todayMinutes,
                    todayPay: todayBasePay + todayNightPremium,
                    monthMinutes: monthMinutes,
                    monthPay: monthGross,
                    monthNetPay: monthNet
                )
                result.append(storePay)
            }

            storePays = result
            lastLoadedAt = now
            lastLoadedMonthKey = monthKey
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func backfillPersonalStoreWorkerLinksIfNeeded(userId: UUID) async {
        #if canImport(Supabase)
        struct PersonalStoreRow: Decodable {
            let id: UUID
        }
        struct LinkedWorkerRow: Decodable {
            let store_id: UUID
        }
        struct WorkerInsert: Encodable {
            let user_id: UUID
            let store_id: UUID
            let name: String
            let phone: String?
            let hourly_wage: Double
            let is_active: Bool
        }

        do {
            let personalStores: [PersonalStoreRow] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select("id")
                .eq("owner_id", value: userId.uuidString)
                .eq("is_personal", value: true)
                .execute()
                .value

            if personalStores.isEmpty { return }

            let storeIds = personalStores.map { $0.id.uuidString }
            let linkedWorkers: [LinkedWorkerRow] = try await SupabaseManager.shared
                .client
                .from("workers")
                .select("store_id")
                .eq("user_id", value: userId.uuidString)
                .in("store_id", values: storeIds)
                .execute()
                .value

            let linkedStoreIds = Set(linkedWorkers.map { $0.store_id })
            let missingStoreIds = personalStores
                .map { $0.id }
                .filter { !linkedStoreIds.contains($0) }

            if missingStoreIds.isEmpty { return }

            let snapshot = try? await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            let trimmedProfileName = snapshot?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let workerName = trimmedProfileName.isEmpty ? "나" : trimmedProfileName
            let trimmedPhone = snapshot?.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let workerPhone = trimmedPhone.isEmpty ? nil : trimmedPhone

            let inserts = missingStoreIds.map { storeId in
                WorkerInsert(
                    user_id: userId,
                    store_id: storeId,
                    name: workerName,
                    phone: workerPhone,
                    hourly_wage: AppConfig.defaultHourlyWage,
                    is_active: true
                )
            }

            _ = try await SupabaseManager.shared
                .client
                .from("workers")
                .insert(inserts)
                .execute()
        } catch {
            #if DEBUG
            print("DEBUG: backfillPersonalStoreWorkerLinksIfNeeded failed: \(error.localizedDescription)")
            #endif
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
            deleteAccountErrorMessage = AppErrorMessage.userMessage(error)
            isShowingDeleteAccountError = true
        }
    }

    @MainActor
    private func processRetirement(_ store: StorePay) async {
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
                try await SupabaseManager.shared.retireWorkerLink(workerId: store.workerId)
            }
            pendingDeleteStore = nil
            await loadData(force: true)
        } catch {
            deleteError = AppErrorMessage.userMessage(error)
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
                loadError = AppErrorMessage.userMessage(error)
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
            loadError = "초대코드 추가 실패: \(AppErrorMessage.userMessage(error))"
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
            let userId = try await SupabaseManager.shared.currentUserId()
            struct StoreInsert: Encodable {
                let name: String
                let address: String?
                let owner_id: UUID
                let is_personal: Bool
            }
            struct CreatedStoreRow: Decodable {
                let id: UUID
            }
            struct WorkerInsert: Encodable {
                let user_id: UUID
                let store_id: UUID
                let name: String
                let phone: String?
                let hourly_wage: Double
                let is_active: Bool
            }
            let payload = StoreInsert(
                name: name,
                address: address.isEmpty ? nil : address,
                owner_id: userId,
                is_personal: true
            )

            let createdStore: CreatedStoreRow = try await SupabaseManager.shared
                .client
                .from("stores")
                .insert(payload)
                .select("id")
                .single()
                .execute()
                .value

            let snapshot = try? await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            let trimmedProfileName = snapshot?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let workerName = trimmedProfileName.isEmpty ? "나" : trimmedProfileName
            let trimmedPhone = snapshot?.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let workerPayload = WorkerInsert(
                user_id: userId,
                store_id: createdStore.id,
                name: workerName,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                hourly_wage: AppConfig.defaultHourlyWage,
                is_active: true
            )

            do {
                _ = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .insert(workerPayload)
                    .execute()
            } catch {
                // Keep data consistent: if worker link fails, remove the just-created personal store.
                _ = try? await SupabaseManager.shared
                    .client
                    .from("stores")
                    .delete()
                    .eq("id", value: createdStore.id.uuidString)
                    .execute()
                throw error
            }

            await loadData(force: true)
        } catch {
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private static func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let end = checkOut else { return 0 }
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }

    private func moveToPreviousMonth() {
        let calendar = Calendar.current
        selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
    }

    private func moveToNextMonth() {
        let calendar = Calendar.current
        selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월"
        return formatter.string(from: date)
    }

    private static func monthKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private static func formatWon(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: Int(value))) ?? "0"
        return "\(number)원"
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("매장명")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        HStack(spacing: 8) {
                            TextField("매장명", text: $name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { Task { await searchPlaces(manualTrigger: true) } }
                                .foregroundColor(.appTextPrimary)
                                .padding(12)
                                .background(Color.appSurface)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.appLine, lineWidth: 1)
                                )
                            Button("검색") {
                                Task { await searchPlaces(manualTrigger: true) }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(width: 80)
                        }
                    }

                    if let searchError {
                        Text(searchError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }

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
        .task(id: name) {
            await debouncedAutoSearch()
        }
    }

    private var kakaoRestApiKey: String? {
        let key = AppConfig.kakaoRestApiKey
        return key.isEmpty ? nil : key
    }

    @MainActor
    private func debouncedAutoSearch() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = nil
            return
        }
        isSearchExpanded = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        await searchPlaces(query: trimmed, manualTrigger: false)
    }

    @MainActor
    private func searchPlaces(manualTrigger: Bool) async {
        await searchPlaces(query: name, manualTrigger: manualTrigger)
    }

    @MainActor
    private func searchPlaces(query: String, manualTrigger: Bool) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = manualTrigger ? "검색어를 입력해주세요." : nil
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
            if Task.isCancelled { return }
            searchResults = results
            isSearchExpanded = true
        } catch {
            if Task.isCancelled { return }
            searchError = AppErrorMessage.userMessage(error)
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
    @State private var monthLogsForNet: [WorkLogRow] = []
    @State private var isLoadingMonthLogsForNet = false
    @State private var startHourInput: String = ""
    @State private var startMinuteInput: String = ""
    @State private var endHourInput: String = ""
    @State private var endMinuteInput: String = ""
    @State private var isSavingManual = false
    @State private var manualError: String?
    @State private var applyWeeklyAllowance: Bool = false
    @State private var applyNightAllowance: Bool = false
    @State private var deductionType: PayrollDeductionType = .withholding
    @State private var payday: Int = PayrollLocalSettings.defaultPayday
    @State private var fixedSchedules: [WorkerFixedSchedule] = []
    @State private var fixedWeekday: Int = 1
    @State private var fixedStartHourInput: String = ""
    @State private var fixedStartMinuteInput: String = ""
    @State private var fixedEndHourInput: String = ""
    @State private var fixedEndMinuteInput: String = ""
    @State private var fixedScheduleError: String?
    @State private var isShowingFixedScheduleInput = false
    @State private var isShowingManualAddInput = false
    @State private var isAutoApplyingFixedSchedule = false
    @State private var lastAutoFixedScheduleCheckKey: String?
    @State private var lastAutoFixedScheduleCheckedAt: Date?
    private var allowManualAdd: Bool { store.isPersonal }
    private var shouldAutoApproveLogs: Bool { store.isPersonal }
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let autoFixedScheduleCheckThrottle: TimeInterval = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                                    .foregroundColor(.appTextPrimary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text("세전 예상")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Text(store.monthPayText)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                                Text("세후 예상 \(monthNetPayText())")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                        .appCard()
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

                    if store.isPersonal {
                        fixedScheduleSection
                    }

                    manualAddSection

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "세부 설정")
                        VStack(alignment: .leading, spacing: 10) {
                            if store.isPersonal {
                                Toggle(isOn: $applyWeeklyAllowance) {
                                    Text("주휴수당 적용")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                                .onChange(of: applyWeeklyAllowance) { _ in
                                    persistLocalPayrollSettings()
                                }

                                Toggle(isOn: $applyNightAllowance) {
                                    Text("야간수당 적용 (22:00~06:00 +50%)")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                                .onChange(of: applyNightAllowance) { _ in
                                    persistLocalPayrollSettings()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("공제 방식 (택 1)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    HStack(spacing: 8) {
                                        ForEach(PayrollDeductionType.allCases) { option in
                                            Button(action: {
                                                deductionType = option
                                                persistLocalPayrollSettings()
                                            }) {
                                                Text(option.title)
                                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                    .foregroundColor(deductionType == option ? .white : .appTextPrimary)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                                    .background(deductionType == option ? Color.appAccent : Color.appSurface)
                                                    .cornerRadius(10)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .stroke(deductionType == option ? Color.appAccent : Color.appLine, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("월급일")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Picker("월급일", selection: $payday) {
                                        ForEach(1...31, id: \.self) { day in
                                            Text("\(day)일").tag(day)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .onChange(of: payday) { _ in
                                        persistLocalPayrollSettings()
                                    }
                                }

                                HStack {
                                    Text("정산기간")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Spacer()
                                    Text("매월 1일 ~ 말일")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                }

                                Text("다음 월급일 \(nextPaydayDateText())")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)

                                Text("개인 매장의 세부 설정은 이 기기에서만 저장돼요.")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
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
                                    Text("야간수당: \(store.applyNightAllowance ? "적용" : "미적용")")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text("월급일: 매월 \(store.paydayText)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text("정산기간: 매월 1일 ~ 말일")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text("다음 월급일 \(nextPaydayDateText())")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                }
                            }
                        }
                        .appCard()
                    }

                historyEntryCard

                if store.isPersonal {
                    refundEstimateSection
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
        .refreshable {
            await loadCurrentLog()
            await loadMonthLogsForNet()
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
        }
        .task {
            if store.isPersonal {
                // Personal store defaults: withholding + no night/weekly allowance.
                applyWeeklyAllowance = false
                applyNightAllowance = false
                deductionType = .withholding
                payday = PayrollLocalSettings.defaultPayday
                if let local = PayrollLocalSettingsStore.load(workerId: store.workerId) {
                    applyWeeklyAllowance = local.applyWeeklyAllowance
                    applyNightAllowance = local.applyNightAllowance
                    deductionType = local.deductionType
                    let localPayday = local.payday == 0 ? PayrollLocalSettings.defaultPayday : local.payday
                    payday = min(max(localPayday, 1), 31)
                }
                loadFixedSchedules()
            } else {
                applyWeeklyAllowance = store.applyWeeklyAllowance
                applyNightAllowance = store.applyNightAllowance
                deductionType = store.deductionType
                payday = store.payday
            }
            await loadCurrentLog()
            await autoAddCompletedFixedSchedulesIfNeeded()
            await loadMonthLogsForNet()
        }
        .onReceive(timer) { _ in
            updateLiveMinutes()
            Task { await autoAddCompletedFixedSchedulesIfNeeded() }
        }
    }

    private var historyEntryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "내역")
            NavigationLink {
                WorkerStoreHistoryView(
                    storeName: store.name,
                    storeId: store.id,
                    workerId: store.workerId,
                    hourlyWage: store.hourlyWage
                )
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("내역 보기")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        Text("전체 근무 내역을 화면에서 길게 확인할 수 있어요.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
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
            .buttonStyle(.plain)
        }
        .appCard()
    }

    private var manualAddSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "근무 추가")
            if allowManualAdd {
                VStack(alignment: .leading, spacing: 10) {
                    Button(isShowingManualAddInput ? "입력 닫기" : "추가하기") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingManualAddInput.toggle()
                            if !isShowingManualAddInput {
                                manualError = nil
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .appCard()

                if isShowingManualAddInput {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("출근 시간")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                timeInputRow(hour: $startHourInput, minute: $startMinuteInput)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("퇴근 시간")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                timeInputRow(hour: $endHourInput, minute: $endMinuteInput)
                            }
                        }

                        Text("종료가 출근보다 빠르면 다음날 퇴근으로 계산돼요.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)

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
                    }
                    .appCard()
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                Text("사장님과 연동된 근무는 직접 추가할 수 없어요.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .appCard()
            }
        }
    }

    private var fixedScheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "고정 스케줄")

            VStack(alignment: .leading, spacing: 10) {
                if fixedSchedules.isEmpty {
                    Text("아직 등록된 고정 스케줄이 없어요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedFixedSchedules) { schedule in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(weekdayLabel(schedule.weekday))요일")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                    Text("\(formatHourMinute(schedule.startHour, schedule.startMinute)) - \(formatHourMinute(schedule.endHour, schedule.endMinute))")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                }
                                Spacer()
                                Button("적용") {
                                    applyFixedScheduleToManualInput(schedule)
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.appAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.appAccent.opacity(0.1))
                                .cornerRadius(8)

                                Button(role: .destructive) {
                                    removeFixedSchedule(schedule)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.appWarning)
                                        .padding(6)
                                }
                            }
                            .padding(10)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                        }
                    }
                }

                Button(isShowingFixedScheduleInput ? "입력 닫기" : "추가하기") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingFixedScheduleInput.toggle()
                        if !isShowingFixedScheduleInput {
                            fixedScheduleError = nil
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .appCard()

            if isShowingFixedScheduleInput {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("요일", selection: $fixedWeekday) {
                        Text("일").tag(0)
                        Text("월").tag(1)
                        Text("화").tag(2)
                        Text("수").tag(3)
                        Text("목").tag(4)
                        Text("금").tag(5)
                        Text("토").tag(6)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("출근 시간")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            timeInputRow(hour: $fixedStartHourInput, minute: $fixedStartMinuteInput)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("퇴근 시간")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            timeInputRow(hour: $fixedEndHourInput, minute: $fixedEndMinuteInput)
                        }
                    }

                    if let fixedScheduleError {
                        Text(fixedScheduleError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }

                    Button("등록하기") {
                        addFixedSchedule()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .appCard()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var refundEstimateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "환급금 계산")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("연간 환산 급여")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(formatWon(refundEstimate.annualGross))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                HStack {
                    Text("원천징수 예상")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(formatWon(refundEstimate.annualWithholding))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                HStack {
                    Text("연말정산 예상세액")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(formatWon(refundEstimate.estimatedSettlementTax))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                HStack {
                    Text("예상 환급금")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Text(formatWon(refundEstimate.expectedRefund))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.appAccent)
                }
                Text(refundEstimate.note)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }
            .appCard()
        }
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
        PayrollLocalSettingsStore.save(
            workerId: store.workerId,
            settings: PayrollLocalSettings(
                applyWeeklyAllowance: applyWeeklyAllowance,
                deductionType: deductionType,
                applyNightAllowance: applyNightAllowance,
                payday: payday
            )
        )
        NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
    }

    func monthNetPayText() -> String {
        formatWon(monthNetPay())
    }

    func nextPaydayDateText() -> String {
        let date = PayrollPayday.nextPaydayDate(payday: payday)
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    var refundEstimate: PayrollRefundEstimate {
        PayrollCalculator.estimateAnnualRefund(
            monthlyTaxablePay: monthTaxablePayForEstimate(),
            deductionType: deductionType
        )
    }

    func monthNetPay() -> Double {
        let taxable = monthTaxablePayForEstimate()
        let breakdown = PayrollCalculator.deductionBreakdown(gross: taxable, type: deductionType)
        return max(0, taxable - breakdown.totalDeduction)
    }

    func monthTaxablePayForEstimate() -> Double {
        // If monthly logs are not loaded yet, use the list-computed gross as fallback.
        if isLoadingMonthLogsForNet || monthLogsForNet.isEmpty {
            return max(0, store.monthPay)
        }

        let counted = approvedMonthLogsForNet()
        let wage = store.hourlyWage

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        let totalMinutes = counted.reduce(0) { partial, log in
            let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
            let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
            return partial + PayrollCalculator.calcMinutes(checkIn: start, checkOut: end)
        }
        let totalNightMinutes = counted.reduce(0) { partial, log in
            let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
            let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
            return partial + PayrollCalculator.calcNightMinutes(checkIn: start, checkOut: end)
        }
        let gross = Double(totalMinutes) / 60.0 * wage
        let nightPremium = applyNightAllowance
            ? Double(totalNightMinutes) / 60.0 * wage * PayrollCalculator.nightPremiumRate
            : 0
        let weeklyAllowance = applyWeeklyAllowance
            ? PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: counted.map { ($0.check_in_at, $0.check_out_at) }, wage: wage)
            : 0
        return max(0, gross + nightPremium + weeklyAllowance)
    }

    func approvedMonthLogsForNet() -> [WorkLogRow] {
        monthLogsForNet.filter { log in
            let hasCheckout = !(log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return normalizedStatus(log.status) == "approved" && hasCheckout
        }
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

    var sortedFixedSchedules: [WorkerFixedSchedule] {
        fixedSchedules.sorted { lhs, rhs in
            if lhs.weekday == rhs.weekday {
                if lhs.startHour == rhs.startHour {
                    return lhs.startMinute < rhs.startMinute
                }
                return lhs.startHour < rhs.startHour
            }
            return lhs.weekday < rhs.weekday
        }
    }

    func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 0: return "일"
        case 1: return "월"
        case 2: return "화"
        case 3: return "수"
        case 4: return "목"
        case 5: return "금"
        case 6: return "토"
        default: return "-"
        }
    }

    func formatHourMinute(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    func timeInputRow(hour: Binding<String>, minute: Binding<String>) -> some View {
        HStack(spacing: 8) {
            TextField("시", text: hour)
                .keyboardType(.numberPad)
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(Color.appSurface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appLine, lineWidth: 1)
                )
            Text(":")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.appTextSecondary)
            TextField("분", text: minute)
                .keyboardType(.numberPad)
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(Color.appSurface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appLine, lineWidth: 1)
                )
        }
    }

    func parseHourMinute(hour: String, minute: String) -> (hour: Int, minute: Int)? {
        guard let h = Int(hour.filter { $0.isNumber }),
              let m = Int(minute.filter { $0.isNumber }),
              (0...23).contains(h),
              (0...59).contains(m) else {
            return nil
        }
        return (h, m)
    }

    func loadFixedSchedules() {
        fixedSchedules = WorkerFixedScheduleStore.load(workerId: store.workerId)
    }

    func persistFixedSchedules() {
        WorkerFixedScheduleStore.save(workerId: store.workerId, schedules: fixedSchedules)
    }

    func addFixedSchedule() {
        fixedScheduleError = nil

        guard let start = parseHourMinute(hour: fixedStartHourInput, minute: fixedStartMinuteInput),
              let end = parseHourMinute(hour: fixedEndHourInput, minute: fixedEndMinuteInput) else {
            fixedScheduleError = "고정 스케줄 시간을 올바르게 입력해주세요."
            return
        }

        guard start.hour != end.hour || start.minute != end.minute else {
            fixedScheduleError = "출근/퇴근 시간이 같아요."
            return
        }

        let candidate = WorkerFixedSchedule(
            id: UUID(),
            weekday: fixedWeekday,
            startHour: start.hour,
            startMinute: start.minute,
            endHour: end.hour,
            endMinute: end.minute
        )

        let duplicated = fixedSchedules.contains {
            $0.weekday == candidate.weekday &&
            $0.startHour == candidate.startHour &&
            $0.startMinute == candidate.startMinute &&
            $0.endHour == candidate.endHour &&
            $0.endMinute == candidate.endMinute
        }
        if duplicated {
            fixedScheduleError = "같은 고정 스케줄이 이미 있어요."
            return
        }

        fixedSchedules.append(candidate)
        persistFixedSchedules()
        fixedStartHourInput = ""
        fixedStartMinuteInput = ""
        fixedEndHourInput = ""
        fixedEndMinuteInput = ""
        fixedScheduleError = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingFixedScheduleInput = false
        }
    }

    func removeFixedSchedule(_ schedule: WorkerFixedSchedule) {
        fixedSchedules.removeAll { $0.id == schedule.id }
        persistFixedSchedules()
    }

    func applyFixedScheduleToManualInput(_ schedule: WorkerFixedSchedule) {
        startHourInput = "\(schedule.startHour)"
        startMinuteInput = "\(schedule.startMinute)"
        endHourInput = "\(schedule.endHour)"
        endMinuteInput = "\(schedule.endMinute)"
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingManualAddInput = true
        }
    }

    func isOvernightSchedule(_ schedule: WorkerFixedSchedule) -> Bool {
        if schedule.endHour < schedule.startHour {
            return true
        }
        if schedule.endHour == schedule.startHour && schedule.endMinute < schedule.startMinute {
            return true
        }
        return false
    }

    func fixedScheduleDateRange(_ schedule: WorkerFixedSchedule, dayStart: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        guard let start = calendar.date(bySettingHour: schedule.startHour, minute: schedule.startMinute, second: 0, of: dayStart),
              let sameDayEnd = calendar.date(bySettingHour: schedule.endHour, minute: schedule.endMinute, second: 0, of: dayStart) else {
            return nil
        }
        let end: Date
        if sameDayEnd < start {
            end = calendar.date(byAdding: .day, value: 1, to: sameDayEnd) ?? sameDayEnd
        } else {
            end = sameDayEnd
        }
        return (start, end)
    }

    @MainActor
    func autoAddCompletedFixedSchedulesIfNeeded() async {
        #if canImport(Supabase)
        guard store.isPersonal else { return }
        guard !isCheckedIn else { return }
        guard !isAutoApplyingFixedSchedule else { return }
        guard !fixedSchedules.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let todayWeekday = (calendar.component(.weekday, from: now) + 6) % 7
        let yesterdayWeekday = (todayWeekday + 6) % 7
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        var dueRanges: [(start: Date, end: Date)] = []

        for schedule in fixedSchedules {
            if schedule.weekday == todayWeekday,
               let range = fixedScheduleDateRange(schedule, dayStart: todayStart),
               range.end <= now {
                dueRanges.append(range)
            }
            if schedule.weekday == yesterdayWeekday,
               isOvernightSchedule(schedule),
               let range = fixedScheduleDateRange(schedule, dayStart: yesterdayStart),
               range.end <= now {
                dueRanges.append(range)
            }
        }

        guard !dueRanges.isEmpty else { return }
        let dueKey = dueRanges
            .sorted(by: { $0.start < $1.start })
            .map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" }
            .joined(separator: "|")
        if lastAutoFixedScheduleCheckKey == dueKey,
           let lastAutoFixedScheduleCheckedAt,
           now.timeIntervalSince(lastAutoFixedScheduleCheckedAt) < autoFixedScheduleCheckThrottle {
            return
        }

        isAutoApplyingFixedSchedule = true
        defer { isAutoApplyingFixedSchedule = false }

        do {
            let iso = ISO8601DateFormatter()
            let existing: [WorkLogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .gte("check_in_at", value: iso.string(from: yesterdayStart))
                .lt("check_in_at", value: iso.string(from: tomorrowStart))
                .execute()
                .value

            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()

            func hasMatchingLog(for range: (start: Date, end: Date)) -> Bool {
                existing.contains { log in
                    let start = parser.date(from: log.check_in_at) ?? fallback.date(from: log.check_in_at)
                    let end = log.check_out_at.flatMap { parser.date(from: $0) ?? fallback.date(from: $0) }
                    guard let start, let end else { return false }
                    let startDiff = abs(start.timeIntervalSince(range.start))
                    let endDiff = abs(end.timeIntervalSince(range.end))
                    return startDiff < 60 && endDiff < 60
                }
            }

            struct InsertPayload: Encodable {
                let store_id: UUID
                let worker_id: UUID
                let check_in_at: String
                let check_out_at: String
                let status: String
                let approved_by: UUID?
                let approved_at: String?
            }

            let approverId = try await SupabaseManager.shared.currentUserId()
            var insertedCount = 0

            for range in dueRanges.sorted(by: { $0.start < $1.start }) {
                if hasMatchingLog(for: range) {
                    continue
                }
                let payload = InsertPayload(
                    store_id: store.id,
                    worker_id: store.workerId,
                    check_in_at: iso.string(from: range.start),
                    check_out_at: iso.string(from: range.end),
                    status: "approved",
                    approved_by: approverId,
                    approved_at: iso.string(from: range.end)
                )
                _ = try await SupabaseManager.shared
                    .client
                    .from("work_logs")
                    .insert(payload)
                    .execute()
                insertedCount += 1
            }

            if insertedCount > 0 {
                await loadMonthLogsForNet()
                NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
            }
            lastAutoFixedScheduleCheckKey = dueKey
            lastAutoFixedScheduleCheckedAt = now
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            #if DEBUG
            print("DEBUG: auto fixed schedule apply failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    @MainActor
    func loadCurrentLog() async {
        #if canImport(Supabase)
        do {
            actionError = nil
            struct LogRow: Decodable { let id: UUID; let check_in_at: String }
            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .is("check_out_at", value: nil)
                .order("check_in_at", ascending: false)
                .limit(5)
                .execute()
                .value
            if rows.count > 1 {
                actionError = "열린 근무 기록이 여러 개 감지됐어요. 최신 기록 기준으로 표시합니다."
            }
            currentLogId = rows.first?.id
            isCheckedIn = currentLogId != nil
            if let row = rows.first {
                let parser = ISO8601DateFormatter()
                parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let checkInDate = parser.date(from: row.check_in_at) ?? ISO8601DateFormatter().date(from: row.check_in_at) ?? Date()
                currentCheckInAt = checkInDate
                updateLiveMinutes()
                await WorkerLiveActivityManager.shared.startOrUpdate(
                    storeId: store.id,
                    storeName: store.name,
                    checkInAt: checkInDate
                )
            } else {
                currentCheckInAt = nil
                liveMinutes = store.todayMinutes
                await WorkerLiveActivityManager.shared.end(storeId: store.id)
            }
        } catch {
            actionError = AppErrorMessage.userMessage(error)
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
                let iso = ISO8601DateFormatter()
                let now = Date()
                if shouldAutoApproveLogs {
                    struct UpdatePayload: Encodable {
                        let check_out_at: String
                        let status: String
                        let approved_by: UUID
                        let approved_at: String
                    }
                    let approverId = try await SupabaseManager.shared.currentUserId()
                    let payload = UpdatePayload(
                        check_out_at: iso.string(from: now),
                        status: "approved",
                        approved_by: approverId,
                        approved_at: iso.string(from: now)
                    )
                    _ = try await SupabaseManager.shared
                        .client
                        .from("work_logs")
                        .update(payload)
                        .eq("id", value: logId.uuidString)
                        .execute()
                } else {
                    struct UpdatePayload: Encodable { let check_out_at: String }
                    let payload = UpdatePayload(check_out_at: iso.string(from: now))
                    _ = try await SupabaseManager.shared
                        .client
                        .from("work_logs")
                        .update(payload)
                        .eq("id", value: logId.uuidString)
                        .execute()
                }
                currentLogId = nil
                isCheckedIn = false
                currentCheckInAt = nil
                NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
                await WorkerLiveActivityManager.shared.end(storeId: store.id)
            } else {
                // Guard against duplicate "open" logs from stale UI state or multi-device retries.
                struct OpenLogRow: Decodable { let id: UUID; let check_in_at: String }
                let openRows: [OpenLogRow] = try await SupabaseManager.shared
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
                if let existing = openRows.first {
                    let parser = ISO8601DateFormatter()
                    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    currentLogId = existing.id
                    isCheckedIn = true
                    let checkInDate = parser.date(from: existing.check_in_at) ?? ISO8601DateFormatter().date(from: existing.check_in_at) ?? Date()
                    currentCheckInAt = checkInDate
                    updateLiveMinutes()
                    await WorkerLiveActivityManager.shared.startOrUpdate(
                        storeId: store.id,
                        storeName: store.name,
                        checkInAt: checkInDate
                    )
                    actionError = "이미 출근 상태예요. 현재 근무 기록으로 동기화했습니다."
                    return
                }

                let iso = ISO8601DateFormatter()
                let now = Date()
                struct InsertedRow: Decodable { let id: UUID }
                let row: InsertedRow
                if shouldAutoApproveLogs {
                    struct InsertPayload: Encodable {
                        let store_id: UUID
                        let worker_id: UUID
                        let check_in_at: String
                        let status: String
                        let approved_by: UUID
                        let approved_at: String
                    }
                    let approverId = try await SupabaseManager.shared.currentUserId()
                    let payload = InsertPayload(
                        store_id: store.id,
                        worker_id: store.workerId,
                        check_in_at: iso.string(from: now),
                        status: "approved",
                        approved_by: approverId,
                        approved_at: iso.string(from: now)
                    )
                    row = try await SupabaseManager.shared
                        .client
                        .from("work_logs")
                        .insert(payload)
                        .select("id")
                        .single()
                        .execute()
                        .value
                } else {
                    struct InsertPayload: Encodable {
                        let store_id: UUID
                        let worker_id: UUID
                        let check_in_at: String
                    }
                    let payload = InsertPayload(
                        store_id: store.id,
                        worker_id: store.workerId,
                        check_in_at: iso.string(from: now)
                    )
                    row = try await SupabaseManager.shared
                        .client
                        .from("work_logs")
                        .insert(payload)
                        .select("id")
                        .single()
                        .execute()
                        .value
                }
                currentLogId = row.id
                isCheckedIn = true
                currentCheckInAt = now
                updateLiveMinutes()
                NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
                await WorkerLiveActivityManager.shared.startOrUpdate(
                    storeId: store.id,
                    storeName: store.name,
                    checkInAt: now
                )
            }
        } catch {
            actionError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    struct WorkLogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
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

        let calendar = Calendar.current
        let today = Date()
        let dayStart = calendar.startOfDay(for: today)
        let startHour = Int(startHourInput.filter { $0.isNumber }) ?? -1
        let startMinute = Int(startMinuteInput.filter { $0.isNumber }) ?? -1
        let endHour = Int(endHourInput.filter { $0.isNumber }) ?? -1
        let endMinute = Int(endMinuteInput.filter { $0.isNumber }) ?? -1

        guard (0...23).contains(startHour), (0...59).contains(startMinute),
              (0...23).contains(endHour), (0...59).contains(endMinute) else {
            manualError = "출근/퇴근 시간을 올바르게 입력해주세요. (예: 09시 30분)"
            return
        }

        guard let checkIn = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart),
              let sameDayEnd = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: dayStart) else {
            manualError = "시간 계산에 실패했어요. 다시 입력해주세요."
            return
        }

        guard checkIn != sameDayEnd else {
            manualError = "출근/퇴근 시간이 같아요. 시간을 다시 확인해주세요."
            return
        }

        let endDate: Date
        if sameDayEnd < checkIn {
            endDate = calendar.date(byAdding: .day, value: 1, to: sameDayEnd) ?? sameDayEnd
        } else {
            endDate = sameDayEnd
        }

        struct InsertPayload: Encodable {
            let store_id: UUID
            let worker_id: UUID
            let check_in_at: String
            let check_out_at: String
            let status: String
            let approved_by: UUID?
            let approved_at: String?
        }
        let iso = ISO8601DateFormatter()
        do {
            let approverId = try await SupabaseManager.shared.currentUserId()
            let payload = InsertPayload(
                store_id: store.id,
                worker_id: store.workerId,
                check_in_at: iso.string(from: checkIn),
                check_out_at: iso.string(from: endDate),
                status: "approved",
                approved_by: approverId,
                approved_at: iso.string(from: endDate)
            )
            _ = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .insert(payload)
                .execute()
            startHourInput = ""
            startMinuteInput = ""
            endHourInput = ""
            endMinuteInput = ""
            manualError = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingManualAddInput = false
            }
            await loadMonthLogsForNet()
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
        } catch {
            manualError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    func normalizedStatus(_ status: String?) -> String {
        let value = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "pending" : value
    }

    func statusLabel(_ status: String?) -> String {
        let value = normalizedStatus(status)
        return value == "approved" ? "승인" : (value == "rejected" ? "반려" : "대기")
    }

    func statusColor(_ status: String?) -> Color {
        let value = normalizedStatus(status)
        return value == "approved" ? .appPositive : (value == "rejected" ? .appWarning : .appTextSecondary)
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

private struct WorkerStoreHistoryView: View {
    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
    }

    let storeName: String
    let storeId: UUID
    let workerId: UUID
    let hourlyWage: Double

    @State private var logs: [LogRow] = []
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?
    @State private var applyNightAllowance = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if isLoading {
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
                                        .foregroundColor(.appTextPrimary)
                                    Spacer()
                                    StatusPill(text: statusLabel(log.status), color: statusColor(log.status))
                                }
                                Text(formatTimeRange(log))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                HStack {
                                    Text(formatHours(totalMinutes(log)))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Spacer()
                                    Text(formatWon(totalPay(log)))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                }
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
        .navigationTitle("\(storeName) 내역")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadLocalSettings()
            await loadLogs()
        }
        .refreshable {
            await refreshFromUser()
        }
        .refreshStatusOverlay(isVisible: isUserRefreshing)
    }

    private func loadLocalSettings() {
        if let local = PayrollLocalSettingsStore.load(workerId: workerId) {
            applyNightAllowance = local.applyNightAllowance
        } else {
            applyNightAllowance = false
        }
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await loadLogs()
    }

    @MainActor
    private func loadLogs() async {
        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status")
                .eq("store_id", value: storeId.uuidString)
                .eq("worker_id", value: workerId.uuidString)
                .order("check_in_at", ascending: false)
                .limit(500)
                .execute()
                .value
            logs = rows
            loadError = nil
        } catch {
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func parseDate(_ isoString: String) -> Date {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        return parser.date(from: isoString) ?? iso.date(from: isoString) ?? Date()
    }

    private func totalMinutes(_ log: LogRow) -> Int {
        let start = parseDate(log.check_in_at)
        let end = log.check_out_at.map(parseDate(_:))
        return PayrollCalculator.calcMinutes(checkIn: start, checkOut: end)
    }

    private func totalPay(_ log: LogRow) -> Double {
        let start = parseDate(log.check_in_at)
        let end = log.check_out_at.map(parseDate(_:))
        let minutes = PayrollCalculator.calcMinutes(checkIn: start, checkOut: end)
        let base = Double(minutes) / 60.0 * hourlyWage
        let nightMinutes = PayrollCalculator.calcNightMinutes(checkIn: start, checkOut: end)
        let nightPremium = applyNightAllowance
            ? Double(nightMinutes) / 60.0 * hourlyWage * PayrollCalculator.nightPremiumRate
            : 0
        return base + nightPremium
    }

    private func statusLabel(_ status: String?) -> String {
        let value = normalizedStatus(status)
        return value == "approved" ? "승인" : (value == "rejected" ? "반려" : "대기")
    }

    private func statusColor(_ status: String?) -> Color {
        let value = normalizedStatus(status)
        return value == "approved" ? .appPositive : (value == "rejected" ? .appWarning : .appTextSecondary)
    }

    private func normalizedStatus(_ status: String?) -> String {
        let value = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "pending" : value
    }

    private func formatDate(_ isoString: String) -> String {
        let date = parseDate(isoString)
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    private func formatTimeRange(_ log: LogRow) -> String {
        let start = parseDate(log.check_in_at)
        let end = log.check_out_at.map(parseDate(_:))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let startText = formatter.string(from: start)
        let endText = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(startText) - \(endText)"
    }

    private func formatWon(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: Int(value))) ?? "0"
        return "\(number)원"
    }

    private func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)시간 \(m)분"
    }
}

private struct WorkerFixedSchedule: Identifiable, Codable {
    let id: UUID
    let weekday: Int
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
}

private enum WorkerFixedScheduleStore {
    private static func key(workerId: UUID) -> String {
        "worker_fixed_schedule_v1_\(workerId.uuidString)"
    }

    static func load(workerId: UUID) -> [WorkerFixedSchedule] {
        guard let data = UserDefaults.standard.data(forKey: key(workerId: workerId)) else { return [] }
        return (try? JSONDecoder().decode([WorkerFixedSchedule].self, from: data)) ?? []
    }

    static func save(workerId: UUID, schedules: [WorkerFixedSchedule]) {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: key(workerId: workerId))
    }
}

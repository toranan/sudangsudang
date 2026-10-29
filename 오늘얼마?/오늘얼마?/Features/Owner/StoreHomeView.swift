import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct StoreHomeView: View {
    let onNavigateToApproval: () -> Void

    struct HomeWorkerRow: Decodable {
        let id: UUID
        let name: String
        let hourly_wage: Double?
        let apply_night_allowance: Bool?
        let is_active: Bool?
    }

    struct HomeScheduleEntryRow: Decodable {
        let worker_id: UUID
        let work_date: String
        let check_in_time: String
        let check_out_time: String?
        let template_id: UUID?
    }

    struct HomeScheduleTemplateRow: Decodable {
        let id: UUID
        let worker_id: UUID
        let weekday: Int
        let check_in_time: String
        let check_out_time: String?
    }

    struct PlannedShift {
        let workerId: UUID
        let name: String
        let start: Date
        let end: Date?
    }

    struct TodayShift: Identifiable {
        enum Status {
            case upcoming
            case working(since: Date)
            case done
            case notCheckedIn

            var title: String {
                switch self {
                case .upcoming: return "예정"
                case .working: return "근무 중"
                case .done: return "퇴근"
                case .notCheckedIn: return "출근 전"
                }
            }

            var color: Color {
                switch self {
                case .upcoming: return .appTextSecondary
                case .working: return .appAccent
                case .done: return .appTextSecondary
                case .notCheckedIn: return .appCaution
                }
            }

            var showsDot: Bool {
                switch self {
                case .working, .notCheckedIn: return true
                case .upcoming, .done: return false
                }
            }
        }

        let workerId: UUID
        let name: String
        let start: Date?
        let end: Date?
        let status: Status

        var id: UUID { workerId }

        var timeText: String {
            let formatter = AppTime.displayFormatter("HH:mm")
            if case .working(let since) = status, start == nil {
                return "\(formatter.string(from: since))부터 근무 중"
            }
            guard let start else { return "" }
            let endText = end.map { formatter.string(from: $0) } ?? "--:--"
            return "\(formatter.string(from: start)) – \(endText)"
        }
    }

    @State private var stores: [Store] = []
    @State private var selectedStoreId: UUID?
    @State private var isPresentingCreateStore = false
    @State private var isPresentingCreateWorker = false
    @State private var isPresentingInviteSheet = false
    @State private var isLoadingStores = false
    @State private var isLoadingSummary = false
    @State private var isUserRefreshing = false
    @State private var didLoadSummary = false
    @State private var storeError: String?
    @State private var pendingDeleteStore: Store?
    @State private var isShowingDeleteConfirm = false

    @State private var actualPay: Double = 0
    @State private var projectedPay: Double = 0
    @State private var workedMinutes: Int = 0
    @State private var workerCount: Int = 0
    @State private var pendingCount: Int = 0
    @State private var todayShifts: [TodayShift] = []

    @State private var lastStoresLoadedAt: Date?
    @State private var lastSummaryLoadedAt: Date?
    @State private var lastSummaryStoreId: UUID?
    @State private var latestStoresRequestID: UUID?
    @State private var latestSummaryRequestID: UUID?
    private let cacheTTLSeconds: TimeInterval = 120
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if isLoadingStores && stores.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else if stores.isEmpty {
                    emptyStoreCard
                } else {
                    if pendingCount > 0 {
                        pendingBanner
                    }
                    laborCostCard
                    todaySection
                    addStaffSection
                    storeManagementRow
                }

                if let storeError {
                    Text(storeError)
                        .font(.app(.caption, .medium))
                        .foregroundColor(.appWarning)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 40)
            .animation(.easeOut(duration: 0.2), value: pendingCount)
        }
        .appRefreshable {
            await refreshFromUser()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $isPresentingCreateStore) {
            CreateStoreView { name, address in
                Task {
                    await createStore(name: name, address: address)
                }
            }
        }
        .sheet(isPresented: $isPresentingCreateWorker) {
            if let storeId = selectedStoreId {
                CreateWorkerView(storeId: storeId) { name, phone, wage in
                    Task {
                        await createWorker(storeId: storeId, name: name, phone: phone, hourlyWage: wage)
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingInviteSheet) {
            WorkerManagementView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        .task {
            await refresh(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .payrollSettingsDidChange)) { _ in
            Task { await refresh(force: true) }
        }
    }

    private var selectedStoreName: String {
        stores.first(where: { $0.id == selectedStoreId })?.name ?? "내 매장"
    }

    private var selectedStore: Store? {
        stores.first(where: { $0.id == selectedStoreId }) ?? stores.first
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Menu {
                ForEach(stores) { store in
                    Button {
                        selectStore(store)
                    } label: {
                        if store.id == selectedStore?.id {
                            Label(store.name, systemImage: "checkmark")
                        } else {
                            Text(store.name)
                        }
                    }
                }
                Divider()
                Button {
                    isPresentingCreateStore = true
                } label: {
                    Label("매장 추가", systemImage: "plus")
                }
                if let selectedStore {
                    Button(role: .destructive) {
                        pendingDeleteStore = selectedStore
                        isShowingDeleteConfirm = true
                    } label: {
                        Label("이 매장 삭제", systemImage: "trash")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedStoreName)
                        .font(.app(.callout, .bold))
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.appSurface, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(todayText)
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appTextSecondary)
                Text("오늘도 수고 많으세요")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(.appTextPrimary)
            }
        }
    }

    private var emptyStoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("먼저 매장을 등록해 주세요")
                .font(.app(.headline, .bold))
                .foregroundColor(.appTextPrimary)
            Text("매장을 만들면 직원을 초대하고 출퇴근과 급여를 한곳에서 관리할 수 있어요.")
                .font(.app(.callout))
                .foregroundColor(.appTextSecondary)
            Button("매장 등록하기") {
                isPresentingCreateStore = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .appCard()
    }

    private var pendingBanner: some View {
        Button(action: onNavigateToApproval) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.appCaution)
                    .frame(width: 8, height: 8)
                Text("승인 기다리는 근무 \(pendingCount)건")
                    .font(.app(.callout, .semibold))
                    .foregroundColor(.appOnInk)
                Spacer()
                Text("확인하기")
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appOnInk.opacity(0.7))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.appOnInk.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.appInk)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableRowStyle())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var laborCostCard: some View {
        NavigationLink {
            if let storeId = selectedStoreId {
                OwnerMonthlyDetailView(storeId: storeId)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(currentMonthText) 예상 인건비")
                        .font(.app(.callout, .medium))
                    Spacer()
                    Text("총 \(formatHours(workedMinutes)) · \(workerCount)명")
                        .font(.app(.caption, .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.8))

                if isLoadingSummary && !didLoadSummary {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    Text(formatWon(actualPay + projectedPay))
                        .font(.system(size: 34, weight: .heavy))
                        .tracking(-1)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: proxy.size.width * paidRatio)
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 10)

                    HStack {
                        Text("지금까지 \(formatWon(actualPay))")
                        Spacer()
                        Text("남은 예정 \(formatWon(projectedPay))")
                    }
                    .font(.app(.caption, .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(Color.appAccent)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableRowStyle())
    }

    private var paidRatio: CGFloat {
        let total = actualPay + projectedPay
        guard total > 0 else { return 0 }
        return CGFloat(min(1, max(0, actualPay / total)))
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("오늘 근무")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(.appTextPrimary)
                if !todayShifts.isEmpty {
                    Text("\(todayShifts.count)")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(.appAccent)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            if todayShifts.isEmpty {
                Text(didLoadSummary ? "오늘 예정된 근무가 없어요." : "불러오는 중이에요.")
                    .font(.app(.callout))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todayShifts.enumerated()), id: \.element.id) { index, shift in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.appLine)
                                .frame(height: 1)
                        }
                        todayShiftRow(shift, index: index)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            }
        }
    }

    private static let avatarPalette: [(fill: Color, text: Color)] = [
        (.appAccentSoft, .appAccent),
        (Color.appCaution.opacity(0.14), .appCaution),
        (.appLavenderSoft, .appLavender)
    ]

    private func todayShiftRow(_ shift: TodayShift, index: Int) -> some View {
        let palette = Self.avatarPalette[index % Self.avatarPalette.count]
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.fill)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(shift.name.prefix(1)))
                        .font(.app(.callout, .bold))
                        .foregroundColor(palette.text)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(shift.name)
                    .font(.app(.body, .bold))
                    .foregroundColor(.appTextPrimary)
                Text(shift.timeText)
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                if shift.status.showsDot {
                    Circle()
                        .fill(shift.status.color)
                        .frame(width: 7, height: 7)
                }
                Text(shift.status.title)
                    .font(.app(.caption, .semibold))
                    .foregroundColor(shift.status.showsDot ? shift.status.color : .appTextSecondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var addStaffSection: some View {
        HStack(spacing: 10) {
            actionTile(
                title: "초대 코드 보내기",
                subtitle: "카톡으로 바로 공유",
                systemImage: "paperplane",
                tint: .appAccent,
                fill: .appAccentSoft
            ) {
                isPresentingInviteSheet = true
            }
            actionTile(
                title: "직접 직원 등록",
                subtitle: "이름과 시급만 입력",
                systemImage: "square.and.pencil",
                tint: .appLavender,
                fill: .appLavenderSoft
            ) {
                guard selectedStoreId != nil else { return }
                isPresentingCreateWorker = true
            }
        }
    }

    private func actionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.appTextSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableRowStyle())
    }

    @ViewBuilder
    private var storeManagementRow: some View {
        if let selectedStore {
            NavigationLink {
                StoreKnowledgeManagementView(
                    storeId: selectedStore.id,
                    storeName: selectedStore.name
                )
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.appAccent)
                        .frame(width: 40, height: 40)
                        .background(Color.appAccentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("가게 매뉴얼·공지")
                            .font(.app(.body, .bold))
                            .foregroundColor(.appTextPrimary)
                        Text("올려두면 챗봇이 직원 질문에 대신 답해요")
                            .font(.app(.caption))
                            .foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            }
            .buttonStyle(PressableRowStyle())
        }
    }

    private var todayText: String {
        AppTime.displayFormatter("M월 d일 EEEE").string(from: Date())
    }

    private var currentMonthText: String {
        "\(AppTime.calendar.component(.month, from: Date()))월"
    }

    private func selectStore(_ store: Store) {
        if selectedStoreId != store.id {
            actualPay = 0
            projectedPay = 0
            workedMinutes = 0
            workerCount = 0
            pendingCount = 0
            todayShifts = []
            didLoadSummary = false
        }
        selectedStoreId = store.id
        Task { await loadSummary(force: true) }
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await refresh(force: true)
    }

    @MainActor
    private func loadStores(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastStoresLoadedAt,
           now.timeIntervalSince(lastStoresLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = UUID()
        latestStoresRequestID = requestID
        isLoadingStores = true
        defer {
            if latestStoresRequestID == requestID {
                isLoadingStores = false
            }
        }
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let result: [Store] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select()
                .eq("owner_id", value: ownerId.uuidString)
                .execute()
                .value
            guard latestStoresRequestID == requestID else { return }
            stores = result
            if selectedStoreId == nil || !stores.contains(where: { $0.id == selectedStoreId }) {
                selectedStoreId = stores.first?.id
            }
            self.lastStoresLoadedAt = now
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard latestStoresRequestID == requestID else { return }
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    struct LogRow: Decodable {
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let workers: WorkerInfo?
        let applied_hourly_wage: Double?
        let applied_night_allowance: Bool?
    }

    struct WorkerInfo: Decodable {
        let name: String
        let hourly_wage: Double?
        let apply_night_allowance: Bool?
    }

    @MainActor
    private func loadSummary(force: Bool) async {
        guard let storeId = selectedStoreId else { return }
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastSummaryLoadedAt,
           let lastSummaryStoreId,
           lastSummaryStoreId == storeId,
           now.timeIntervalSince(lastSummaryLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = UUID()
        latestSummaryRequestID = requestID
        isLoadingSummary = true
        defer {
            if latestSummaryRequestID == requestID {
                isLoadingSummary = false
            }
        }
        do {
            let calendar = AppTime.calendar
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
            let todayStart = calendar.startOfDay(for: now)
            let iso = AppTime.iso
            let dayFormatter = AppTime.displayFormatter("yyyy-MM-dd")
            let client = SupabaseManager.shared.client

            // 이번 달 근무 기록, 직원, 남은 날짜 일정, 고정 스케줄을 동시에 받는다.
            async let logRows: [LogRow] = client
                .from("work_logs")
                .select("worker_id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance,workers(name,hourly_wage,apply_night_allowance)")
                .eq("store_id", value: storeId.uuidString)
                .gte("check_in_at", value: iso.string(from: monthStart))
                .lt("check_in_at", value: iso.string(from: monthEnd))
                .execute()
                .value
            async let workerRows: [HomeWorkerRow] = client
                .from("workers")
                .select("id,name,hourly_wage,apply_night_allowance,is_active")
                .eq("store_id", value: storeId.uuidString)
                .execute()
                .value
            async let entryRows: [HomeScheduleEntryRow] = client
                .from("schedule_entries")
                .select("worker_id,work_date,check_in_time,check_out_time,template_id")
                .eq("store_id", value: storeId.uuidString)
                .gte("work_date", value: dayFormatter.string(from: todayStart))
                .lt("work_date", value: dayFormatter.string(from: monthEnd))
                .execute()
                .value
            async let templateRows: [HomeScheduleTemplateRow] = client
                .from("schedule_templates")
                .select("id,worker_id,weekday,check_in_time,check_out_time,is_active")
                .eq("store_id", value: storeId.uuidString)
                .eq("is_active", value: true)
                .execute()
                .value
            let (rows, workers, entries, templates) = try await (logRows, workerRows, entryRows, templateRows)
            guard latestSummaryRequestID == requestID, selectedStoreId == storeId else { return }

            let activeWorkers = Dictionary(
                uniqueKeysWithValues: workers.filter { $0.is_active ?? true }.map { ($0.id, $0) }
            )
            let dateParser = AppTime.isoWithFractionalSeconds

            var minutes = 0
            var pay: Double = 0
            var pending = 0
            var workedWorkers = Set<UUID>()
            var openSince: [UUID: (date: Date, name: String)] = [:]
            var loggedToday = Set<UUID>()

            for row in rows {
                let status = normalizedStatus(row.status)
                if status == "rejected" { continue }
                let checkIn = dateParser.date(from: row.check_in_at) ?? iso.date(from: row.check_in_at) ?? now
                let checkOut = row.check_out_at.flatMap { dateParser.date(from: $0) ?? iso.date(from: $0) }
                let hasCheckout = !(row.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                if calendar.isDate(checkIn, inSameDayAs: now) {
                    loggedToday.insert(row.worker_id)
                }
                guard hasCheckout else {
                    let name = row.workers?.name ?? activeWorkers[row.worker_id]?.name ?? "직원"
                    if (openSince[row.worker_id]?.date ?? .distantPast) < checkIn {
                        openSince[row.worker_id] = (checkIn, name)
                    }
                    continue
                }
                if status == "pending" { pending += 1 }

                // 승인 대기 건도 예상 인건비에는 포함한다 (반려만 제외).
                let effectiveCheckOut = checkOut ?? checkIn
                minutes += calcMinutes(checkIn: checkIn, checkOut: effectiveCheckOut)
                workedWorkers.insert(row.worker_id)
                pay += PayrollCalculator.grossPay(
                    checkIn: checkIn,
                    checkOut: effectiveCheckOut,
                    appliedHourlyWage: row.applied_hourly_wage,
                    appliedNightAllowance: row.applied_night_allowance,
                    fallbackHourlyWage: row.workers?.hourly_wage ?? 0,
                    fallbackNightAllowance: row.workers?.apply_night_allowance ?? false
                )
            }

            let shifts = Self.plannedShifts(
                from: todayStart,
                to: monthEnd,
                entries: entries,
                templates: templates,
                workers: activeWorkers
            )

            // 남은 예정: 오늘 아직 기록이 없는 근무 + 내일부터 말일까지.
            var projected: Double = 0
            for shift in shifts {
                let isToday = calendar.isDate(shift.start, inSameDayAs: now)
                if isToday && loggedToday.contains(shift.workerId) { continue }
                guard let end = shift.end, let worker = activeWorkers[shift.workerId] else { continue }
                projected += PayrollCalculator.grossPay(
                    checkIn: shift.start,
                    checkOut: end,
                    wage: worker.hourly_wage ?? 0,
                    applyNightAllowance: worker.apply_night_allowance ?? false
                )
            }

            var today: [TodayShift] = shifts
                .filter { calendar.isDate($0.start, inSameDayAs: now) }
                .map { shift in
                    let status: TodayShift.Status
                    if let open = openSince[shift.workerId] {
                        status = .working(since: open.date)
                    } else if loggedToday.contains(shift.workerId) {
                        status = .done
                    } else if now > shift.start.addingTimeInterval(10 * 60) {
                        status = .notCheckedIn
                    } else {
                        status = .upcoming
                    }
                    return TodayShift(workerId: shift.workerId, name: shift.name, start: shift.start, end: shift.end, status: status)
                }
            // 일정 없이 출근한 직원도 보여준다.
            let scheduledToday = Set(today.map(\.workerId))
            for (workerId, open) in openSince where !scheduledToday.contains(workerId) {
                today.append(TodayShift(workerId: workerId, name: open.name, start: nil, end: nil, status: .working(since: open.date)))
            }
            today.sort { ($0.start ?? .distantPast, $0.name) < ($1.start ?? .distantPast, $1.name) }

            withAnimation(.easeOut(duration: 0.25)) {
                actualPay = pay
                projectedPay = projected
                workedMinutes = minutes
                workerCount = workedWorkers.count
                pendingCount = pending
                todayShifts = today
            }
            didLoadSummary = true
            self.lastSummaryLoadedAt = now
            self.lastSummaryStoreId = storeId
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard latestSummaryRequestID == requestID, selectedStoreId == storeId else { return }
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    // 스케줄 화면과 같은 규칙: 날짜별 일정이 있으면 그것을, 고정 스케줄로 아직 만들어지지 않은 날은 템플릿을 쓴다.
    private static func plannedShifts(
        from start: Date,
        to end: Date,
        entries: [HomeScheduleEntryRow],
        templates: [HomeScheduleTemplateRow],
        workers: [UUID: HomeWorkerRow]
    ) -> [PlannedShift] {
        let calendar = AppTime.calendar
        let dayFormatter = AppTime.displayFormatter("yyyy-MM-dd")
        var shifts: [PlannedShift] = []
        var seededTemplateDays = Set<String>()

        for entry in entries {
            if let templateId = entry.template_id {
                seededTemplateDays.insert("\(templateId.uuidString)|\(entry.work_date)")
            }
            guard let worker = workers[entry.worker_id],
                  let day = dayFormatter.date(from: entry.work_date),
                  let shiftStart = combine(day: day, time: entry.check_in_time) else { continue }
            shifts.append(PlannedShift(
                workerId: entry.worker_id,
                name: worker.name,
                start: shiftStart,
                end: entry.check_out_time.flatMap { endTime(day: day, start: shiftStart, time: $0) }
            ))
        }

        var cursor = start
        while cursor < end {
            let weekday = (calendar.component(.weekday, from: cursor) + 6) % 7
            let workDate = dayFormatter.string(from: cursor)
            for template in templates where template.weekday == weekday {
                guard !seededTemplateDays.contains("\(template.id.uuidString)|\(workDate)"),
                      let worker = workers[template.worker_id],
                      let shiftStart = combine(day: cursor, time: template.check_in_time) else { continue }
                shifts.append(PlannedShift(
                    workerId: template.worker_id,
                    name: worker.name,
                    start: shiftStart,
                    end: template.check_out_time.flatMap { endTime(day: cursor, start: shiftStart, time: $0) }
                ))
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return shifts
    }

    private static func combine(day: Date, time: String) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return AppTime.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    // 퇴근 시각이 출근보다 이르면 다음 날 퇴근(야간 근무)으로 본다.
    private static func endTime(day: Date, start: Date, time: String) -> Date? {
        guard let sameDay = combine(day: day, time: time) else { return nil }
        return sameDay > start ? sameDay : AppTime.calendar.date(byAdding: .day, value: 1, to: sameDay)
    }

    private func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let end = checkOut else { return 0 }
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }



    @MainActor
    private func refresh(force: Bool) async {
        await loadStores(force: force)
        await loadSummary(force: force)
    }

    @MainActor
    private func createStore(name: String, address: String) async {
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
                is_personal: false
            )
            let created: Store = try await SupabaseManager.shared
                .client
                .from("stores")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            stores.insert(created, at: 0)
            selectedStoreId = created.id
            lastStoresLoadedAt = Date()
            await loadSummary(force: true)
        } catch {
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func createWorker(storeId: UUID, name: String, phone: String, hourlyWage: Double) async {
        #if canImport(Supabase)
        do {
            struct WorkerInsert: Encodable {
                let store_id: UUID
                let name: String
                let phone: String?
                let hourly_wage: Double
                let is_active: Bool
            }
            let payload = WorkerInsert(
                store_id: storeId,
                name: name,
                phone: phone.isEmpty ? nil : phone,
                hourly_wage: hourlyWage,
                is_active: true
            )
            _ = try await SupabaseManager.shared
                .client
                .from("workers")
                .insert(payload)
                .execute()
        } catch {
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func deleteStore(_ store: Store) async {
        #if canImport(Supabase)
        do {
            _ = try await SupabaseManager.shared
                .client
                .from("stores")
                .delete()
                .eq("id", value: store.id.uuidString)
                .execute()
            stores.removeAll { $0.id == store.id }
            if selectedStoreId == store.id {
                selectedStoreId = stores.first?.id
            }
            lastStoresLoadedAt = Date()
            await loadSummary(force: true)
        } catch {
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
        pendingDeleteStore = nil
    }
}

struct CreateStoreView: View {
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
                    } else if !searchResults.isEmpty {
                        if isSearchExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(searchResults) { place in
                                Button(action: {
                                    hideKeyboard()
                                    applyPlace(place)
                                    isSearchExpanded = false
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.placeName)
                                            .font(.app(.callout, .semibold))
                                            .foregroundColor(.appTextPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(place.displayAddress)
                                            .font(.app(.caption, .medium))
                                            .foregroundColor(.appTextSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .appInputField()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        }
                    }

                    if let searchError {
                        Text(searchError)
                            .font(.app(.caption, .medium))
                            .foregroundColor(.appWarning)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("매장 이름")
                            .font(.app(.caption, .semibold))
                            .foregroundColor(.appTextSecondary)
                        HStack(spacing: 8) {
                            TextField("강남 1호점", text: $name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { Task { await searchPlaces() } }
                                .foregroundColor(.appTextPrimary)
                                .appInputField()
                            Button("검색") {
                                Task { await searchPlaces() }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(width: 80)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("주소 (선택)")
                            .font(.app(.caption, .semibold))
                            .foregroundColor(.appTextSecondary)
                        TextField("서울 강남구 ...", text: $address)
                            .foregroundColor(.appTextPrimary)
                            .appInputField()
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
            .navigationTitle("매장 등록")
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
        return AppConfig.kakaoRestApiKey
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
            searchError = AppErrorMessage.userMessage(error)
        }
    }

    private func applyPlace(_ place: KakaoPlace) {
        name = place.placeName
        address = place.displayAddress
    }

    private struct KakaoSearchResponse: Decodable {
        let documents: [KakaoPlace]
    }

    private struct KakaoPlace: Decodable, Identifiable {
        let id: String
        let placeName: String
        let addressName: String?
        let roadAddressName: String?
        let phone: String
        let categoryName: String
        let x: String
        let y: String

        enum CodingKeys: String, CodingKey {
            case id
            case placeName = "place_name"
            case addressName = "address_name"
            case roadAddressName = "road_address_name"
            case phone
            case categoryName = "category_name"
            case x
            case y
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
}

struct CreateWorkerView: View {
    @Environment(\.dismiss) private var dismiss
    let storeId: UUID
    let onSubmit: (String, String, Double) -> Void

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var wage: String = String(Int(AppConfig.defaultHourlyWage))

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("이름")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    TextField("홍길동", text: $name)
                        .appInputField()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("전화번호 (선택)")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    TextField("010-1234-5678", text: $phone)
                        .keyboardType(.phonePad)
                        .appInputField()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("시급 (원)")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    TextField("예: 10320", text: $wage)
                        .keyboardType(.numberPad)
                        .appInputField()
                    MinimumWageHint(input: wage)
                }

                Button(action: {
                    let digits = wage.filter { $0.isNumber }
                    let amount = Double(digits) ?? AppConfig.defaultHourlyWage
                    onSubmit(name, phone, amount)
                    dismiss()
                }) {
                    Text("등록하기")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

                Spacer()
            }
            .padding(20)
            .navigationTitle("직접 직원 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}

private func hideKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

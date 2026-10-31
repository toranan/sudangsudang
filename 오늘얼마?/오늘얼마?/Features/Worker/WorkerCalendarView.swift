import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct WorkerCalendarView: View {
    struct WorkerStoreRow: Decodable, Identifiable {
        let id: UUID
        let store_id: UUID
        let hourly_wage: Double?
        let apply_night_allowance: Bool?
        let is_active: Bool?
        let stores: StoreInfo?
    }

    struct StoreInfo: Decodable {
        let name: String
        let is_personal: Bool?
    }

    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let applied_hourly_wage: Double?
        let applied_break_policy: String?
        let applied_break_minutes: Int?
        let applied_night_allowance: Bool?
    }

    struct DaySummary: Identifiable {
        var id: Date { date }
        let date: Date
        let totalMinutes: Int
        let totalPay: Double
        let rows: [WorkRow]
    }

    struct WorkRow: Identifiable {
        let id: UUID
        let start: Date
        let end: Date?
        let minutes: Int
        let pay: Double
        let status: String
    }

    @State private var workers: [WorkerStoreRow] = []
    @State private var selectedWorkerId: UUID?
    @State private var currentMonth: Date = Date()
    @State private var summaries: [DaySummary] = []
    // 근무지·월별로 받아 둔 요약. 달을 넘길 때 먼저 보여주고 뒤에서 새로 받는다.
    @State private var monthSummaryCache: [String: [DaySummary]] = [:]
    @State private var selectedDate: Date?
    @State private var isLoadingWorkers = false
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?

    @State private var lastWorkersLoadedAt: Date?
    @State private var lastMonthLoadedAt: Date?
    @State private var lastMonthKey: String?
    @State private var workersRequest = LatestRequest()
    @State private var monthRequest = LatestRequest()
    private let cacheTTLSeconds: TimeInterval = 120

    private let calendar = AppTime.calendar
    private let isoFormatter = AppTime.iso

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                monthHeader

                if !workers.isEmpty {
                    storePicker
                } else if isLoadingWorkers {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else {
                    Text("등록된 매장이 없어요.")
                        .font(.app(.callout))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                }

                if !workers.isEmpty {
                    calendarGrid

                    if let selected = selectedDate,
                       let summary = summaries.first(where: { calendar.isDate($0.date, inSameDayAs: selected) }) {
                        dayDetail(summary: summary)
                    } else {
                        Text("날짜를 선택하면 근무 내역이 보여요.")
                            .font(.app(.callout))
                            .foregroundColor(.appTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard()
                    }
                }

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
        .task {
            await refresh(force: false)
        }
        .onChange(of: selectedWorkerId) { oldValue, _ in
            // 첫 선택(nil → 첫 근무지)은 refresh()가 이어서 로드하므로 중복 요청을 건너뛴다.
            guard oldValue != nil else { return }
            Task { await loadMonth(force: false) }
        }
        .onChange(of: currentMonth) { _ in
            if let workerId = selectedWorkerId,
               let cached = monthSummaryCache["\(workerId.uuidString)|\(monthKey(currentMonth))"] {
                summaries = cached
            }
            Task { await loadMonth(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptInvite)) { _ in
            Task { await refresh(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .payrollSettingsDidChange)) { _ in
            Task { await refresh(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
        }
    }

    private var storePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(workers) { worker in
                    let isSelected = worker.id == selectedWorkerId
                    Button(action: { selectedWorkerId = worker.id }) {
                        Text(worker.stores?.name ?? "매장")
                            .font(.app(.caption, .semibold))
                            .foregroundColor(isSelected ? .appOnInk : .appTextSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(isSelected ? Color.appInk : Color.appSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var monthHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("근무 달력")
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appTextSecondary)
                Text(monthTitle)
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(.appTextPrimary)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if !workers.isEmpty {
                HStack(spacing: 2) {
                    Button(action: { currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                            .frame(width: 36, height: 36)
                    }
                    Button(action: { currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 2)
                .background(Color.appSurface, in: Capsule())
            }
        }
        .padding(.horizontal, 4)
    }

    private var calendarGrid: some View {
        let days = makeMonthDays()
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(["일","월","화","수","목","금","토"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(days) { item in
                    if let date = item.date {
                        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                        let isToday = calendar.isDateInToday(date)
                        let summary = summaries.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
                        Button(action: { selectedDate = date }) {
                            VStack(spacing: 3) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 15, weight: isToday || isSelected ? .heavy : .semibold))
                                    .foregroundColor(isSelected ? .appOnInk : (isToday ? .appAccent : .appTextPrimary))
                                if let summary {
                                    Text(formatWon(summary.totalPay))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(isSelected ? .appOnInk.opacity(0.8) : .appAccent)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                } else {
                                    Text(" ")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .padding(.horizontal, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isSelected ? Color.appInk : (summary != nil ? Color.appAccentSoft : Color.clear))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    private func dayDetail(summary: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle(summary.date))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(.appTextPrimary)
                Spacer()
                Text(formatHours(summary.totalMinutes))
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(summary.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.appLine)
                            .frame(height: 1)
                    }
                    HStack(spacing: 10) {
                        Text(formatRange(start: row.start, end: row.end))
                            .font(.app(.callout, .bold))
                            .foregroundColor(.appTextPrimary)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(row.statusColor)
                                .frame(width: 6, height: 6)
                            Text(row.statusText)
                                .font(.app(.caption, .semibold))
                                .foregroundColor(row.statusColor)
                        }
                        Spacer()
                        Text(row.end != nil ? formatWon(row.pay) : "근무 중")
                            .font(.app(.callout, .bold))
                            .foregroundColor(row.status == "approved" ? .appTextPrimary : .appTextSecondary)
                    }
                    .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .padding(.top, 6)
    }

    private var selectedWorkerHourlyWage: Double {
        workers.first(where: { $0.id == selectedWorkerId })?.hourly_wage ?? 0
    }

    private var selectedWorkerApplyNightAllowance: Bool {
        guard let worker = workers.first(where: { $0.id == selectedWorkerId }) else {
            return false
        }
        if worker.stores?.is_personal == true,
           let local = PayrollLocalSettingsStore.load(workerId: worker.id) {
            return local.applyNightAllowance
        }
        return worker.apply_night_allowance ?? false
    }

    private var monthTitle: String {
        let comps = calendar.dateComponents([.year, .month], from: currentMonth)
        return "\(comps.year ?? 0)년 \(comps.month ?? 0)월"
    }

    private func dayTitle(_ date: Date) -> String {
        let comps = calendar.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 0)월 \(comps.day ?? 0)일"
    }



    private func formatRange(start: Date, end: Date?) -> String {
        let formatter = AppTime.displayFormatter("HH:mm")
        let s = formatter.string(from: start)
        let e = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(s) - \(e)"
    }

    private func monthKey(_ date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    private func makeMonthDays() -> [MonthDay] {
        var items: [MonthDay] = []
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let range = calendar.range(of: .day, in: .month, for: start) ?? 1..<2
        let firstWeekday = calendar.component(.weekday, from: start)
        let leadingEmpty = (firstWeekday + 6) % 7

        for index in 0..<leadingEmpty {
            items.append(MonthDay(id: "leading-\(index)", date: nil))
        }
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: start) {
                items.append(MonthDay(id: "day-\(day)", date: date))
            }
        }
        // 달마다 4~6주로 줄 수가 달라 높이가 흔들리지 않게 항상 6주(42칸)로 채운다.
        while items.count < 42 {
            items.append(MonthDay(id: "trailing-\(items.count)", date: nil))
        }
        return items
    }

    private struct MonthDay: Identifiable {
        let id: String
        let date: Date?
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await refresh(force: true)
    }

    @MainActor
    private func refresh(force: Bool) async {
        await loadWorkers(force: force)
        await loadMonth(force: force)
    }

    @MainActor
    private func loadWorkers(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastWorkersLoadedAt,
           now.timeIntervalSince(lastWorkersLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = workersRequest.begin()
        isLoadingWorkers = true
        defer {
            if workersRequest.isCurrent(requestID) {
                isLoadingWorkers = false
            }
        }
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            do {
                try await WorkerAutoRetirement.processForUser(userId: userId)
            } catch {
                if AppErrorMessage.isCancellation(error) {
                    return
                }
                #if DEBUG
                print("DEBUG: auto retirement (worker calendar) failed: \(error.localizedDescription)")
                #endif
            }
            let rows: [WorkerStoreRow] = try await SupabaseManager.shared
                .client
                .from("workers")
                .select("id,store_id,hourly_wage,apply_night_allowance,is_active,stores(name,is_personal)")
                .eq("user_id", value: userId.uuidString)
                .order("joined_at", ascending: false)
                .execute()
                .value
            guard workersRequest.isCurrent(requestID) else { return }
            let activeRows = rows.filter { $0.is_active ?? true }
            workers = activeRows
            if selectedWorkerId == nil || !activeRows.contains(where: { $0.id == selectedWorkerId }) {
                selectedWorkerId = activeRows.first?.id
            }
            lastWorkersLoadedAt = now
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard workersRequest.isCurrent(requestID) else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadMonth(force: Bool) async {
        guard let workerId = selectedWorkerId else {
            monthRequest.invalidate()
            summaries = []
            selectedDate = nil
            return
        }
        #if canImport(Supabase)
        let now = Date()
        let key = "\(workerId.uuidString)|\(monthKey(currentMonth))"
        if !force,
           lastMonthKey == key,
           let lastMonthLoadedAt,
           now.timeIntervalSince(lastMonthLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = monthRequest.begin()
        isLoading = true
        defer {
            if monthRequest.isCurrent(requestID) {
                isLoading = false
            }
        }
        do {
            loadError = nil
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let startISO = isoFormatter.string(from: start)
            let endISO = isoFormatter.string(from: end)

            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance,applied_break_policy,applied_break_minutes")
                .eq("worker_id", value: workerId.uuidString)
                .gte("check_in_at", value: startISO)
                .lt("check_in_at", value: endISO)
                .order("check_in_at", ascending: true)
                .execute()
                .value

            guard monthRequest.isCurrent(requestID),
                  selectedWorkerId == workerId,
                  "\(workerId.uuidString)|\(monthKey(currentMonth))" == key else { return }
            let built = buildSummaries(from: rows)
            monthSummaryCache[key] = built
            withAnimation(.easeOut(duration: 0.2)) {
                summaries = built
            }
            if selectedDate == nil ||
                selectedDate.map({ !calendar.isDate($0, equalTo: currentMonth, toGranularity: .month) }) == true {
                selectedDate = summaries.first?.date ?? start
            }
            lastMonthLoadedAt = now
            lastMonthKey = key
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard monthRequest.isCurrent(requestID),
                  selectedWorkerId == workerId,
                  "\(workerId.uuidString)|\(monthKey(currentMonth))" == key else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func buildSummaries(from rows: [LogRow]) -> [DaySummary] {
        let parser = AppTime.isoWithFractionalSeconds

        var byDay: [Date: [WorkRow]] = [:]
        for row in rows {
            let status = row.status ?? "pending"
            if status == "rejected" { continue }

            let checkIn = parser.date(from: row.check_in_at) ?? isoFormatter.date(from: row.check_in_at) ?? Date()
            let checkOut = row.check_out_at.flatMap { parser.date(from: $0) ?? isoFormatter.date(from: $0) }
            let minutes = PayrollCalculator.calcPaidMinutes(
                checkIn: checkIn,
                checkOut: checkOut,
                appliedBreakPolicy: row.applied_break_policy,
                appliedBreakMinutes: row.applied_break_minutes
            )
            // 내 기록 탭처럼 승인 대기 근무도 금액을 보여준다(반려는 위에서 뺐다).
            let pay = checkOut != nil
                ? PayrollCalculator.grossPay(
                    checkIn: checkIn,
                    checkOut: checkOut,
                    appliedHourlyWage: row.applied_hourly_wage,
                    appliedNightAllowance: row.applied_night_allowance,
                    fallbackHourlyWage: selectedWorkerHourlyWage,
                    fallbackNightAllowance: selectedWorkerApplyNightAllowance,
                    appliedBreakPolicy: row.applied_break_policy,
                    appliedBreakMinutes: row.applied_break_minutes
                )
                : 0

            let day = calendar.startOfDay(for: checkIn)
            byDay[day, default: []].append(WorkRow(id: row.id, start: checkIn, end: checkOut, minutes: minutes, pay: pay, status: status))
        }

        let summaries = byDay.map { (date, rows) -> DaySummary in
            let totalMinutes = rows.reduce(0) { $0 + $1.minutes }
            let totalPay = rows.reduce(0) { $0 + $1.pay }
            return DaySummary(date: date, totalMinutes: totalMinutes, totalPay: totalPay, rows: rows)
        }

        return summaries.sorted { $0.date < $1.date }
    }
}

private extension WorkerCalendarView.WorkRow {
    var statusText: String {
        switch status {
        case "approved":
            return "승인"
        case "pending":
            return "대기"
        case "rejected":
            return "반려"
        default:
            return status
        }
    }

    var statusColor: Color {
        switch status {
        case "approved":
            return .appPositive
        case "pending":
            return .appCaution
        case "rejected":
            return .appWarning
        default:
            return .appTextSecondary
        }
    }
}

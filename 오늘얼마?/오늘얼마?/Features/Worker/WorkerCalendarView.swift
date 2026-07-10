import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct WorkerCalendarView: View {
    struct WorkerStoreRow: Decodable, Identifiable {
        let id: UUID
        let store_id: UUID
        let hourly_wage: Double?
        let is_active: Bool?
        let stores: StoreInfo?
    }

    struct StoreInfo: Decodable {
        let name: String
    }

    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
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
        let status: String
    }

    @State private var workers: [WorkerStoreRow] = []
    @State private var selectedWorkerId: UUID?
    @State private var currentMonth: Date = Date()
    @State private var summaries: [DaySummary] = []
    @State private var selectedDate: Date?
    @State private var isLoadingWorkers = false
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?

    @State private var lastWorkersLoadedAt: Date?
    @State private var lastMonthLoadedAt: Date?
    @State private var lastMonthKey: String?
    private let cacheTTLSeconds: TimeInterval = 120

    private let calendar = AppTime.calendar
    private let isoFormatter = AppTime.iso

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !workers.isEmpty {
                    storePicker
                } else if isLoadingWorkers {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else {
                    Text("등록된 매장이 없어요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                        .appCard()
                }

                if !workers.isEmpty {
                    monthHeader

                    calendarGrid

                    if let selected = selectedDate,
                       let summary = summaries.first(where: { calendar.isDate($0.date, inSameDayAs: selected) }) {
                        dayDetail(summary: summary)
                    } else {
                        Text("날짜를 선택하면 근무 내역이 보여요.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                            .appCard()
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
        .refreshable {
            await refreshFromUser()
        }
        .refreshStatusOverlay(isVisible: isUserRefreshing)
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            await refresh(force: false)
        }
        .onChange(of: selectedWorkerId) { _ in
            Task { await loadMonth(force: false) }
        }
        .onChange(of: currentMonth) { _ in
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
            HStack(spacing: 8) {
                ForEach(workers) { worker in
                    let isSelected = worker.id == selectedWorkerId
                    Button(action: { selectedWorkerId = worker.id }) {
                        Text(worker.stores?.name ?? "매장")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(isSelected ? .white : .appTextPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.appAccent : Color.appSurface)
                            .cornerRadius(999)
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button(action: { currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(SecondaryButtonStyle())

            Text(monthTitle)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextPrimary)

            Button(action: { currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            if isLoading {
                ProgressView()
            }
        }
    }

    private var calendarGrid: some View {
        let days = makeMonthDays()
        return VStack(spacing: 8) {
            HStack {
                ForEach(["일","월","화","수","목","금","토"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(days) { item in
                    if let date = item.date {
                        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                        let summary = summaries.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
                        Button(action: { selectedDate = date }) {
                            VStack(spacing: 4) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .appTextPrimary)
                                if let summary {
                                    Text(formatWon(summary.totalPay))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundColor(isSelected ? .white.opacity(0.9) : .appTextSecondary)
                                } else {
                                    Text(" ")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.appAccent : Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .appCard()
    }

    private func dayDetail(summary: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: dayTitle(summary.date), trailing: "\(formatHours(summary.totalMinutes))")
            VStack(spacing: 10) {
                ForEach(summary.rows) { row in
                    HStack {
                        Text(formatRange(start: row.start, end: row.end))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Text(row.statusText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(row.statusColor)
                        Text(formatWon(payFor(minutes: row.minutes)))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
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
        .appCard()
    }

    private var selectedWorkerHourlyWage: Double {
        workers.first(where: { $0.id == selectedWorkerId })?.hourly_wage ?? 0
    }

    private func payFor(minutes: Int) -> Double {
        Double(minutes) / 60.0 * selectedWorkerHourlyWage
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
        while items.count % 7 != 0 {
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
        isLoadingWorkers = true
        defer { isLoadingWorkers = false }
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
                .select("id,store_id,hourly_wage,is_active,stores(name)")
                .eq("user_id", value: userId.uuidString)
                .order("joined_at", ascending: false)
                .execute()
                .value
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
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadMonth(force: Bool) async {
        guard let workerId = selectedWorkerId else {
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
        isLoading = true
        defer { isLoading = false }
        do {
            loadError = nil
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let startISO = isoFormatter.string(from: start)
            let endISO = isoFormatter.string(from: end)

            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status")
                .eq("worker_id", value: workerId.uuidString)
                .gte("check_in_at", value: startISO)
                .lt("check_in_at", value: endISO)
                .order("check_in_at", ascending: true)
                .execute()
                .value

            summaries = buildSummaries(from: rows)
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
            let minutes = calcMinutes(checkIn: checkIn, checkOut: checkOut)

            let day = calendar.startOfDay(for: checkIn)
            byDay[day, default: []].append(WorkRow(id: row.id, start: checkIn, end: checkOut, minutes: minutes, status: status))
        }

        let summaries = byDay.map { (date, rows) -> DaySummary in
            let totalMinutes = rows.reduce(0) { $0 + $1.minutes }
            let totalPay = rows.reduce(0) { $0 + payFor(minutes: $1.minutes) }
            return DaySummary(date: date, totalMinutes: totalMinutes, totalPay: totalPay, rows: rows)
        }

        return summaries.sorted { $0.date < $1.date }
    }

    private func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let out = checkOut else { return 0 }
        return max(0, Int(floor(out.timeIntervalSince(checkIn) / 60.0)))
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
            return .appTextSecondary
        case "rejected":
            return .appWarning
        default:
            return .appTextSecondary
        }
    }
}

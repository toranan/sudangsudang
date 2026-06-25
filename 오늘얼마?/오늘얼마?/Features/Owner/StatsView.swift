import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct StatsView: View {
    struct StoreOption: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    struct LogWorker: Decodable {
        let name: String
        let hourly_wage: Double?
    }

    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let worker_id: UUID
        let workers: LogWorker?
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
        let name: String
        let minutes: Int
        let pay: Double
    }

    @State private var stores: [StoreOption] = []
    @State private var selectedStoreId: UUID?
    @State private var currentMonth: Date = Date()
    @State private var summaries: [DaySummary] = []
    @State private var selectedDate: Date?
    @State private var isLoadingStores = false
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?
    @State private var lastStoresLoadedAt: Date?
    @State private var lastMonthLoadedAt: Date?
    @State private var lastMonthKey: String?
    private let cacheTTLSeconds: TimeInterval = 120

    private let calendar = Calendar.current
    private let isoFormatter = ISO8601DateFormatter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !stores.isEmpty {
                    storePicker
                } else if isLoadingStores {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else {
                    Text("등록된 매장이 없어요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                        .appCard()
                }

                if !stores.isEmpty {
                    monthHeader

                    calendarGrid

                    if let selected = selectedDate, let summary = summaries.first(where: { calendar.isDate($0.date, inSameDayAs: selected) }) {
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
        .onChange(of: selectedStoreId) { _ in
            Task { await loadMonth(force: false) }
        }
        .onChange(of: currentMonth) { _ in
            Task { await loadMonth(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
        }
    }

    private var storePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stores) { store in
                    let isSelected = store.id == selectedStoreId
                    Button(action: { selectedStoreId = store.id }) {
                        Text(store.name)
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
                        Button(action: {
                            selectedDate = date
                        }) {
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
            SectionHeader(title: dayTitle(summary.date))
            VStack(spacing: 10) {
                ForEach(summary.rows) { row in
                    HStack {
                        Text(row.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(formatHours(row.minutes))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        Text(formatWon(row.pay))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
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

    private var monthTitle: String {
        let comps = calendar.dateComponents([.year, .month], from: currentMonth)
        return "\(comps.year ?? 0)년 \(comps.month ?? 0)월"
    }

    private func dayTitle(_ date: Date) -> String {
        let comps = calendar.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 0)월 \(comps.day ?? 0)일 근무"
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
    private func loadStores(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastStoresLoadedAt,
           now.timeIntervalSince(lastStoresLoadedAt) < cacheTTLSeconds {
            return
        }
        isLoadingStores = true
        defer { isLoadingStores = false }
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let result: [Store] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select()
                .eq("owner_id", value: ownerId.uuidString)
                .execute()
                .value
            stores = result.map { StoreOption(id: $0.id, name: $0.name) }
            if selectedStoreId == nil {
                selectedStoreId = stores.first?.id
            }
            self.lastStoresLoadedAt = now
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
        guard let storeId = selectedStoreId else { return }
        #if canImport(Supabase)
        let now = Date()
        let key = "\(storeId.uuidString)|\(monthKey(currentMonth))"
        if !force,
           lastMonthKey == key,
           let lastMonthLoadedAt,
           now.timeIntervalSince(lastMonthLoadedAt) < cacheTTLSeconds {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let startISO = isoFormatter.string(from: start)
            let endISO = isoFormatter.string(from: end)

            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status,worker_id,workers(name,hourly_wage)")
                .eq("store_id", value: storeId.uuidString)
                .gte("check_in_at", value: startISO)
                .lt("check_in_at", value: endISO)
                .execute()
                .value

            summaries = buildSummaries(from: rows)
            if selectedDate == nil ||
                selectedDate.map({ !calendar.isDate($0, equalTo: currentMonth, toGranularity: .month) }) == true {
                selectedDate = summaries.first?.date ?? start
            }
            self.lastMonthLoadedAt = now
            self.lastMonthKey = key
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func monthKey(_ date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    @MainActor
    private func refresh(force: Bool) async {
        await loadStores(force: force)
        await loadMonth(force: force)
    }

    private func buildSummaries(from rows: [LogRow]) -> [DaySummary] {
        var byDay: [Date: [WorkRow]] = [:]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for row in rows {
            let status = row.status ?? "pending"
            let hasCheckout = !(row.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            guard status == "approved", hasCheckout else { continue }

            let checkIn = dateFormatter.date(from: row.check_in_at) ?? isoFormatter.date(from: row.check_in_at) ?? Date()
            let checkOut = row.check_out_at.flatMap { dateFormatter.date(from: $0) ?? isoFormatter.date(from: $0) }
            guard let checkOut else { continue }
            let minutes = calcMinutes(checkIn: checkIn, checkOut: checkOut)
            let name = row.workers?.name ?? "알바"
            let wage = row.workers?.hourly_wage ?? 0
            let pay = Double(minutes) / 60.0 * wage

            let day = calendar.startOfDay(for: checkIn)
            byDay[day, default: []].append(WorkRow(id: row.id, name: name, minutes: minutes, pay: pay))
        }

        let summaries = byDay.map { (date, rows) -> DaySummary in
            let totalMinutes = rows.reduce(0) { $0 + $1.minutes }
            let totalPay = rows.reduce(0) { $0 + $1.pay }
            return DaySummary(date: date, totalMinutes: totalMinutes, totalPay: totalPay, rows: rows)
        }

        return summaries.sorted { $0.date < $1.date }
    }

    private func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let out = checkOut else { return 0 }
        return max(0, Int(out.timeIntervalSince(checkIn) / 60))
    }
}

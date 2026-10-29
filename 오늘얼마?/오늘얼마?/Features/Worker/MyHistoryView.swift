import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct MyHistoryView: View {
    struct WorkerRow: Decodable {
        let id: UUID
        let store_id: UUID
        let hourly_wage: Double?
        let apply_weekly_allowance: Bool?
        let deduction_type: String?
        let apply_night_allowance: Bool?
        let stores: StoreName?
    }

    struct StoreName: Decodable {
        let name: String
        let is_personal: Bool?
    }

    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let store_id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let applied_hourly_wage: Double?
        let applied_night_allowance: Bool?
    }

    struct WorkItem: Identifiable {
        let id: UUID
        let startedAt: Date
        let date: String
        let storeName: String
        let time: String
        let hours: String
        let pay: String
        let status: String
        let statusColor: Color
    }

    @State private var monthWorkedText: String = "0시간"
    @State private var monthPayText: String = "0원"
    @State private var monthNetPayText: String = "0원"
    @State private var items: [WorkItem] = []
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?
    @State private var lastLoadedAt: Date?
    @State private var loadRequest = LatestRequest()
    private let cacheTTLSeconds: TimeInterval = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("이번 달")
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                    Text("내 기록")
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(.appTextPrimary)
                }
                .padding(.horizontal, 4)

                summaryCard

                HStack(spacing: 10) {
                    statTile(title: "총 근무 시간", value: monthWorkedText)
                    statTile(title: "세후 예상", value: monthNetPayText, valueColor: .appAccent)
                }

                Text("최근 근무 기록")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(.appTextPrimary)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else if items.isEmpty {
                    Text("근무 기록이 없어요.")
                        .font(.app(.callout))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.appLine)
                                    .frame(height: 1)
                            }
                            workRow(item)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
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
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptInvite)) { _ in
            Task { await loadData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .payrollSettingsDidChange)) { _ in
            Task { await loadData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await loadData() }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("이번 달 예상 급여 (세전)")
                .font(.app(.callout, .medium))
                .foregroundColor(.white.opacity(0.8))
            Text(monthPayText)
                .font(.system(size: 34, weight: .heavy))
                .tracking(-1)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(Color.appAccent)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func statTile(title: String, value: String, valueColor: Color = .appTextPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.appTextSecondary)
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func workRow(_ item: WorkItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.appAccentSoft)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(item.storeName.prefix(1)))
                        .font(.app(.callout, .bold))
                        .foregroundColor(.appAccent)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.storeName)
                        .font(.app(.callout, .bold))
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.statusColor)
                            .frame(width: 6, height: 6)
                        Text(item.status)
                            .font(.app(.caption, .semibold))
                            .foregroundColor(item.statusColor)
                    }
                }
                Text("\(item.date) · \(item.time)")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.pay)
                    .font(.app(.callout, .bold))
                    .foregroundColor(.appTextPrimary)
                Text(item.hours)
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(.vertical, 13)
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await loadData(force: true)
    }

    @MainActor
    private func loadData(force: Bool = false) async {
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastLoadedAt,
           now.timeIntervalSince(lastLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = loadRequest.begin()
        isLoading = true
        defer {
            if loadRequest.isCurrent(requestID) {
                isLoading = false
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
                print("DEBUG: auto retirement (worker history) failed: \(error.localizedDescription)")
                #endif
            }
            let workers: [WorkerRow]
            do {
                workers = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .select("id,store_id,hourly_wage,apply_weekly_allowance,deduction_type,apply_night_allowance,stores(name,is_personal)")
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                    .value
            } catch {
                let message = error.localizedDescription.lowercased()
                if message.contains("apply_night_allowance") {
                    workers = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,store_id,hourly_wage,apply_weekly_allowance,deduction_type,stores(name,is_personal)")
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                        .value
                } else if message.contains("apply_weekly_allowance") || message.contains("deduction_type") {
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

            let workerById = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0) })
            let workerIds = workers.map { $0.id.uuidString }

            if workerIds.isEmpty {
                guard loadRequest.isCurrent(requestID) else { return }
                items = []
                monthWorkedText = "0시간"
                monthPayText = "0원"
                monthNetPayText = "0원"
                lastLoadedAt = now
                return
            }

            let calendar = AppTime.calendar
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let allowanceLogRange = PayrollCalculator.weeklyAllowanceLogRange(forMonth: monthStart)
            let iso = AppTime.iso

            let logs: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,store_id,worker_id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance")
                .in("worker_id", values: workerIds)
                .gte("check_in_at", value: iso.string(from: allowanceLogRange.start))
                .lt("check_in_at", value: iso.string(from: allowanceLogRange.end))
                .order("check_in_at", ascending: false)
                .execute()
                .value

            let parser = AppTime.isoWithFractionalSeconds
            let timeFormatter = AppTime.displayFormatter("HH:mm")
            let dateFormatter = AppTime.displayFormatter("M월 d일")

            var totalMinutes = 0
            var totalPay: Double = 0
            var rendered: [WorkItem] = []

            let monthLogs = logs.filter { log in
                guard let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) else {
                    return false
                }
                return checkIn >= monthStart && checkIn < monthEnd
            }
            let allowanceLogs = logs.filter { log in
                let hasCheckout = !(log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                return normalizedStatus(log.status) == "approved" && hasCheckout
            }
            let countedLogs = allowanceLogs.filter { log in
                guard let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) else {
                    return false
                }
                return checkIn >= monthStart && checkIn < monthEnd
            }

            // Summary totals should include the entire month (not only the first page).
            for log in countedLogs {
                let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                let minutes = Self.calcMinutes(checkIn: checkIn, checkOut: checkOut)
                totalMinutes += minutes

                let worker = workerById[log.worker_id]
                let wage = worker?.hourly_wage ?? 0
                let pay = PayrollCalculator.grossPay(
                    checkIn: checkIn,
                    checkOut: checkOut,
                    appliedHourlyWage: log.applied_hourly_wage,
                    appliedNightAllowance: log.applied_night_allowance,
                    fallbackHourlyWage: wage,
                    fallbackNightAllowance: applyNightAllowance(for: worker)
                )
                totalPay += pay
            }

            // Net pay summary is computed per worker record (store-specific settings).
            var netTotal: Double = 0
            let monthLogsByWorker = Dictionary(grouping: countedLogs, by: { $0.worker_id })
            let allowanceLogsByWorker = Dictionary(grouping: allowanceLogs, by: { $0.worker_id })
            for worker in workers {
                let wLogs = monthLogsByWorker[worker.id, default: []]
                let weeklyLogs = allowanceLogsByWorker[worker.id, default: []]
                let wage = worker.hourly_wage ?? 0
                let gross = wLogs.reduce(0) { partial, log in
                    let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                    let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                    return partial + PayrollCalculator.grossPay(
                        checkIn: checkIn,
                        checkOut: checkOut,
                        appliedHourlyWage: log.applied_hourly_wage,
                        appliedNightAllowance: log.applied_night_allowance,
                        fallbackHourlyWage: wage,
                        fallbackNightAllowance: applyNightAllowance(for: worker)
                    )
                }
                var applyWeekly = worker.apply_weekly_allowance ?? false
                var deductionType = PayrollDeductionType(rawValue: worker.deduction_type ?? "") ?? .withholding
                if worker.stores?.is_personal == true,
                   let local = PayrollLocalSettingsStore.load(workerId: worker.id) {
                    applyWeekly = local.applyWeeklyAllowance
                    deductionType = local.deductionType
                }
                let weeklyAllowance = applyWeekly
                    ? PayrollCalculator.estimateWeeklyAllowancePay(
                        checkInOut: weeklyLogs.map { ($0.check_in_at, $0.check_out_at) },
                        wage: wage,
                        attributedToMonth: monthStart
                    )
                    : 0
                let breakdown = PayrollCalculator.deductionBreakdown(gross: gross + weeklyAllowance, type: deductionType)
                let net = max(0, gross + weeklyAllowance - breakdown.totalDeduction)
                netTotal += net
            }

            // Render list items (first page only)
            for log in monthLogs.prefix(20) {
                let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                let minutes = Self.calcMinutes(checkIn: checkIn, checkOut: checkOut)

                let worker = workerById[log.worker_id]
                let wage = worker?.hourly_wage ?? 0
                let storeName = worker?.stores?.name ?? "매장"
                let pay = PayrollCalculator.grossPay(
                    checkIn: checkIn,
                    checkOut: checkOut,
                    appliedHourlyWage: log.applied_hourly_wage,
                    appliedNightAllowance: log.applied_night_allowance,
                    fallbackHourlyWage: wage,
                    fallbackNightAllowance: applyNightAllowance(for: worker)
                )

                let start = timeFormatter.string(from: checkIn)
                let end = checkOut.map { timeFormatter.string(from: $0) } ?? "--:--"
                let status = normalizedStatus(log.status)
                let statusColor: Color = status == "approved" ? .appPositive : (status == "rejected" ? .appWarning : .appTextSecondary)
                let statusLabel: String = status == "approved" ? "승인" : (status == "rejected" ? "반려" : "대기")

                rendered.append(
                    WorkItem(
                        id: log.id,
                        startedAt: checkIn,
                        date: dateFormatter.string(from: checkIn),
                        storeName: storeName,
                        time: "\(start) - \(end)",
                        hours: formatHours(minutes),
                        pay: formatWon(pay),
                        status: statusLabel,
                        statusColor: statusColor
                    )
                )
            }

            guard loadRequest.isCurrent(requestID) else { return }
            monthWorkedText = formatHours(totalMinutes)
            monthPayText = formatWon(totalPay)
            monthNetPayText = formatWon(netTotal)
            items = rendered.sorted(by: { $0.startedAt > $1.startedAt })
            lastLoadedAt = now
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard loadRequest.isCurrent(requestID) else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private static func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let end = checkOut else { return 0 }
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }

    private func applyNightAllowance(for worker: WorkerRow?) -> Bool {
        guard let worker else { return false }
        if worker.stores?.is_personal == true,
           let local = PayrollLocalSettingsStore.load(workerId: worker.id) {
            return local.applyNightAllowance
        }
        return worker.apply_night_allowance ?? false
    }



}

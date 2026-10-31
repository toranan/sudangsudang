import Foundation
#if canImport(Supabase)
import Supabase
#endif

// 사장님 AI 비서의 조회 도구. Claude가 고른 도구를 앱이 실행하고, 결과를 JSON 문자열로 돌려준다.
// 금액·시간은 화면과 같은 PayrollCalculator로 계산해서, 답과 화면 숫자가 어긋나지 않게 한다.
// DB를 바꾸는 도구는 OwnerAgentActions.swift에 있고, 사장님 확인을 받은 뒤에만 저장한다.
struct OwnerAgentTools {
    let storeId: UUID

    struct ToolError: Error {
        let message: String
    }

    // MARK: - Rows

    struct WorkerRow: Decodable {
        let id: UUID
        let name: String
        let hourly_wage: Double?
        let apply_night_allowance: Bool?
        let apply_weekly_allowance: Bool?
        let break_policy: String?
        let break_minutes: Int?
        let is_active: Bool?
    }

    struct LogRow: Decodable, WeeklyAllowanceLogFields {
        let id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let applied_hourly_wage: Double?
        let applied_night_allowance: Bool?
        let applied_break_policy: String?
        let applied_break_minutes: Int?
        let applied_weekly_allowance: Bool?
    }

    // MARK: - Entry

    func run(name: String, input: [String: AnyJSON]) async -> (text: String, isError: Bool) {
        do {
            let result: Encodable
            switch name {
            case "list_workers":
                result = try await listWorkers()
            case "get_month_payroll":
                result = try await monthPayroll(month: input["month"]?.stringValue, workerName: input["worker_name"]?.stringValue)
            case "get_weekly_allowance_status":
                result = try await weeklyAllowanceStatus(date: input["date"]?.stringValue)
            case "list_pending_approvals":
                result = try await pendingApprovals()
            case "get_work_logs":
                result = try await workLogs(
                    from: input["from"]?.stringValue,
                    to: input["to"]?.stringValue,
                    workerName: input["worker_name"]?.stringValue
                )
            case "get_schedule":
                result = try await schedule(
                    from: input["from"]?.stringValue,
                    to: input["to"]?.stringValue,
                    workerName: input["worker_name"]?.stringValue
                )
            default:
                return ("{\"error\":\"알 수 없는 도구: \(name)\"}", true)
            }
            return (try Self.encode(result), false)
        } catch let error as ToolError {
            return ((try? Self.encode(["error": error.message])) ?? "{}", true)
        } catch {
            return ("{\"error\":\"조회에 실패했어요.\"}", true)
        }
    }

    private static func encode(_ value: Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Tools

    private struct WorkerInfo: Encodable {
        let name: String
        let hourlyWage: Int
        let nightAllowance: Bool
        let weeklyAllowance: Bool
        let breakSetting: String
        let isActive: Bool
    }

    private func listWorkers() async throws -> [WorkerInfo] {
        try await fetchWorkers().map { worker in
            WorkerInfo(
                name: worker.name,
                hourlyWage: Int(worker.hourly_wage ?? 0),
                nightAllowance: worker.apply_night_allowance ?? false,
                weeklyAllowance: worker.apply_weekly_allowance ?? false,
                breakSetting: breakText(policy: worker.break_policy, minutes: worker.break_minutes),
                isActive: worker.is_active ?? true
            )
        }
    }

    private struct MonthPayroll: Encodable {
        struct Worker: Encodable {
            let name: String
            let approvedHours: String
            let workPay: Int
            let weeklyAllowance: Int
            let grossPay: Int
            let pendingCount: Int
            let pendingPay: Int
        }
        let month: String
        let basis: String
        let totalGrossPay: Int
        let totalApprovedHours: String
        let totalPendingCount: Int
        let totalPendingPay: Int
        let workers: [Worker]
    }

    // OwnerMonthlyDetailView와 같은 계산: 승인된 근무 + 주휴수당(일요일이 속한 달에 넣음).
    private func monthPayroll(month: String?, workerName: String?) async throws -> MonthPayroll {
        let monthStart = try parseMonth(month)
        let allWorkers = try await fetchWorkers()
        let workers = try filterWorkers(allWorkers, name: workerName)
        let range = PayrollCalculator.weeklyAllowanceLogRange(forMonth: monthStart)
        let logs = try await fetchLogs(from: range.start, to: range.end, workerIds: workers.map(\.id))
        let logsByWorker = Dictionary(grouping: logs, by: \.worker_id)

        var rows: [MonthPayroll.Worker] = []
        var totalMinutes = 0
        for worker in workers {
            let totals = monthTotals(worker: worker, logs: logsByWorker[worker.id] ?? [], monthStart: monthStart)
            totalMinutes += totals.approvedMinutes
            rows.append(.init(
                name: worker.name,
                approvedHours: formatHours(totals.approvedMinutes),
                workPay: Int(totals.workPay),
                weeklyAllowance: Int(totals.allowance),
                grossPay: Int(totals.workPay + totals.allowance),
                pendingCount: totals.pendingCount,
                pendingPay: Int(totals.pendingPay)
            ))
        }

        return MonthPayroll(
            month: monthFormatter.string(from: monthStart),
            basis: "승인된 근무 기준, 세전, 주휴수당 포함. 대기 중인 근무는 pending에 따로 있음",
            totalGrossPay: rows.reduce(0) { $0 + $1.grossPay },
            totalApprovedHours: formatHours(totalMinutes),
            totalPendingCount: rows.reduce(0) { $0 + $1.pendingCount },
            totalPendingPay: rows.reduce(0) { $0 + $1.pendingPay },
            workers: rows
        )
    }

    struct MonthTotals {
        var approvedMinutes = 0
        var workPay: Double = 0
        var allowance: Double = 0
        var pendingCount = 0
        var pendingPay: Double = 0
    }

    // 한 알바의 한 달 합계. logs는 weeklyAllowanceLogRange(앞뒤 주 포함) 범위로 받은 것.
    // OwnerMonthlyDetailView와 같은 계산: 승인된 근무 + 주휴수당(일요일이 속한 달에 넣음).
    func monthTotals(worker: WorkerRow, logs: [LogRow], monthStart: Date) -> MonthTotals {
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        var totals = MonthTotals()
        var allowanceLogs: [LogRow] = []
        for log in logs {
            guard let start = AppTime.parseISO(log.check_in_at),
                  let end = log.check_out_at.flatMap(AppTime.parseISO) else { continue }
            let status = normalizedStatus(log.status)
            if status == "approved" { allowanceLogs.append(log) }
            guard start >= monthStart, start < monthEnd else { continue }
            if status == "approved" {
                totals.approvedMinutes += paidMinutes(log, start: start, end: end)
                totals.workPay += pay(log, worker: worker, start: start, end: end)
            } else if status == "pending" {
                totals.pendingCount += 1
                totals.pendingPay += pay(log, worker: worker, start: start, end: end)
            }
        }
        totals.allowance = PayrollCalculator.estimateWeeklyAllowancePay(
            logs: allowanceLogs,
            fallbackWage: worker.hourly_wage ?? 0,
            fallbackApply: worker.apply_weekly_allowance ?? false,
            attributedToMonth: monthStart
        )
        return totals
    }

    private struct WeeklyStatus: Encodable {
        struct Worker: Encodable {
            let name: String
            let workedHours: String
            let remainingScheduledHours: String
            let projectedHours: String
            let meets15Hours: Bool
            let projectedWeeklyAllowance: Int
            let hoursShortOf15: String?
        }
        let week: String
        let basis: String
        let workers: [Worker]
    }

    private func weeklyAllowanceStatus(date: String?) async throws -> WeeklyStatus {
        let reference = try date.map(parseDay) ?? Date()
        guard let week = weekCalendar.dateInterval(of: .weekOfYear, for: reference) else {
            throw ToolError(message: "주를 계산하지 못했어요.")
        }
        let now = Date()
        let workers = try await fetchWorkers().filter { $0.apply_weekly_allowance == true && ($0.is_active ?? true) }
        guard !workers.isEmpty else {
            return WeeklyStatus(week: weekText(week), basis: "주휴수당이 켜진 알바가 없음", workers: [])
        }
        let logs = try await fetchLogs(from: week.start, to: week.end, workerIds: workers.map(\.id))
        let shifts = try await plannedShifts(from: max(week.start, calendar.startOfDay(for: now)), to: week.end, workers: workers)
        let absences = try await absenceKeys(from: week.start, to: week.end, workerIds: workers.map(\.id))

        var rows: [WeeklyStatus.Worker] = []
        for worker in workers {
            var workedMinutes = 0
            var loggedDays = Set<Date>()
            for log in logs where log.worker_id == worker.id && normalizedStatus(log.status) != "rejected" {
                guard let start = AppTime.parseISO(log.check_in_at) else { continue }
                loggedDays.insert(calendar.startOfDay(for: start))
                guard let end = log.check_out_at.flatMap(AppTime.parseISO) else { continue }
                workedMinutes += paidMinutes(log, start: start, end: end)
            }
            // 아직 지나지 않았고, 그날 기록이 없는 스케줄만 남은 시간으로 본다.
            var remainingMinutes = 0
            for shift in shifts where shift.workerId == worker.id {
                guard let end = shift.end, end > now,
                      !loggedDays.contains(calendar.startOfDay(for: shift.start)),
                      !absences.contains(absenceKey(worker.id, shift.start)) else { continue }
                remainingMinutes += PayrollCalculator.calcPaidMinutes(
                    checkIn: shift.start,
                    checkOut: end,
                    breakPolicy: PayrollBreakPolicy(rawOrNone: worker.break_policy),
                    customBreakMinutes: worker.break_minutes ?? 0
                )
            }
            let projected = workedMinutes + remainingMinutes
            let allowance = PayrollCalculator.weeklyAllowancePay(weekMinutes: projected, wage: worker.hourly_wage ?? 0)
            rows.append(.init(
                name: worker.name,
                workedHours: formatHours(workedMinutes),
                remainingScheduledHours: formatHours(remainingMinutes),
                projectedHours: formatHours(projected),
                meets15Hours: projected >= 15 * 60,
                projectedWeeklyAllowance: Int(allowance),
                hoursShortOf15: projected >= 15 * 60 ? nil : formatHours(15 * 60 - projected)
            ))
        }
        return WeeklyStatus(
            week: weekText(week),
            basis: "일한 시간은 승인·대기 근무(반려 제외, 휴게 제외), 남은 시간은 스케줄대로 일한다고 본 예상",
            workers: rows
        )
    }

    private struct LogItem: Encodable {
        let id: UUID
        let name: String
        let date: String
        let time: String
        let status: String
        let paidHours: String
        let pay: Int?
    }

    private struct PendingList: Encodable {
        let count: Int
        let totalPay: Int
        let logs: [LogItem]
    }

    private func pendingApprovals() async throws -> PendingList {
        let workers = try await fetchWorkers()
        let byId = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0) })
        #if canImport(Supabase)
        let rows: [LogRow] = try await SupabaseManager.shared.client
            .from("work_logs")
            .select(Self.logColumns)
            .eq("store_id", value: storeId.uuidString)
            .eq("status", value: "pending")
            .not("check_out_at", operator: .is, value: "null")
            .order("check_in_at", ascending: true)
            .limit(50)
            .execute()
            .value
        #else
        let rows: [LogRow] = []
        #endif
        let items = rows.compactMap { logItem($0, worker: byId[$0.worker_id]) }
        return PendingList(count: items.count, totalPay: items.reduce(0) { $0 + ($1.pay ?? 0) }, logs: items)
    }

    private func workLogs(from: String?, to: String?, workerName: String?) async throws -> [LogItem] {
        let (start, end) = try parseRange(from: from, to: to)
        let workers = try filterWorkers(try await fetchWorkers(), name: workerName)
        let byId = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0) })
        let logs = try await fetchLogs(from: start, to: end, workerIds: workers.map(\.id))
            .sorted { $0.check_in_at < $1.check_in_at }
        return logs.prefix(100).compactMap { logItem($0, worker: byId[$0.worker_id]) }
    }

    private struct ScheduleItem: Encodable {
        let name: String
        let date: String
        let time: String
        let absent: Bool
    }

    private func schedule(from: String?, to: String?, workerName: String?) async throws -> [ScheduleItem] {
        let (start, end) = try parseRange(from: from, to: to)
        let workers = try filterWorkers(try await fetchWorkers().filter { $0.is_active ?? true }, name: workerName)
        let shifts = try await plannedShifts(from: start, to: end, workers: workers)
        let absences = try await absenceKeys(from: start, to: end, workerIds: workers.map(\.id))
        let time = AppTime.displayFormatter("HH:mm")
        return shifts
            .sorted { ($0.start, $0.name) < ($1.start, $1.name) }
            .map { shift in
                ScheduleItem(
                    name: shift.name,
                    date: dayLabelFormatter.string(from: shift.start),
                    time: "\(time.string(from: shift.start))–\(shift.end.map { time.string(from: $0) } ?? "미정")",
                    absent: absences.contains(absenceKey(shift.workerId, shift.start))
                )
            }
    }

    // MARK: - Fetch

    private static let logColumns = "id,worker_id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance,applied_break_policy,applied_break_minutes,applied_weekly_allowance"

    func fetchWorkers() async throws -> [WorkerRow] {
        #if canImport(Supabase)
        return try await SupabaseManager.shared.client
            .from("workers")
            .select("id,name,hourly_wage,apply_night_allowance,apply_weekly_allowance,break_policy,break_minutes,is_active")
            .eq("store_id", value: storeId.uuidString)
            .order("joined_at", ascending: true)
            .execute()
            .value
        #else
        return []
        #endif
    }

    func fetchLogs(from start: Date, to end: Date, workerIds: [UUID]) async throws -> [LogRow] {
        guard !workerIds.isEmpty else { return [] }
        #if canImport(Supabase)
        return try await SupabaseManager.shared.client
            .from("work_logs")
            .select(Self.logColumns)
            .eq("store_id", value: storeId.uuidString)
            .in("worker_id", values: workerIds.map(\.uuidString))
            .gte("check_in_at", value: AppTime.isoString(from: start))
            .lt("check_in_at", value: AppTime.isoString(from: end))
            .execute()
            .value
        #else
        return []
        #endif
    }

    // 결근으로 확정된 (알바, 날짜). 키는 absenceKey로 만든다.
    func absenceKeys(from start: Date, to end: Date, workerIds: [UUID]) async throws -> Set<String> {
        guard !workerIds.isEmpty else { return [] }
        #if canImport(Supabase)
        struct Row: Decodable {
            let worker_id: UUID
            let work_date: String
        }
        let rows: [Row] = try await SupabaseManager.shared.client
            .from("work_absences")
            .select("worker_id,work_date")
            .eq("store_id", value: storeId.uuidString)
            .in("worker_id", values: workerIds.map(\.uuidString))
            .gte("work_date", value: dayFormatter.string(from: start))
            .lt("work_date", value: dayFormatter.string(from: end))
            .execute()
            .value
        return Set(rows.map { "\($0.worker_id.uuidString)|\($0.work_date)" })
        #else
        return []
        #endif
    }

    func absenceKey(_ workerId: UUID, _ date: Date) -> String {
        "\(workerId.uuidString)|\(dayFormatter.string(from: date))"
    }

    // 고르기 버튼에 보여 줄 재직 중인 알바 이름(등록 순)
    func activeWorkerNames() async throws -> [String] {
        try await fetchWorkers().filter { $0.is_active ?? true }.map(\.name)
    }

    func fetchLogs(ids: [UUID]) async throws -> [LogRow] {
        guard !ids.isEmpty else { return [] }
        #if canImport(Supabase)
        return try await SupabaseManager.shared.client
            .from("work_logs")
            .select(Self.logColumns)
            .eq("store_id", value: storeId.uuidString)
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value
        #else
        return []
        #endif
    }

    func plannedShifts(from start: Date, to end: Date, workers: [WorkerRow]) async throws -> [StoreHomeView.PlannedShift] {
        guard start < end, !workers.isEmpty else { return [] }
        #if canImport(Supabase)
        let ids = workers.map(\.id.uuidString)
        async let entries: [StoreHomeView.HomeScheduleEntryRow] = SupabaseManager.shared.client
            .from("schedule_entries")
            .select("worker_id,work_date,check_in_time,check_out_time,template_id")
            .eq("store_id", value: storeId.uuidString)
            .in("worker_id", values: ids)
            .gte("work_date", value: dayFormatter.string(from: start))
            .lt("work_date", value: dayFormatter.string(from: end))
            .execute()
            .value
        async let templates: [StoreHomeView.HomeScheduleTemplateRow] = SupabaseManager.shared.client
            .from("schedule_templates")
            .select("id,worker_id,weekday,check_in_time,check_out_time")
            .eq("store_id", value: storeId.uuidString)
            .in("worker_id", values: ids)
            .eq("is_active", value: true)
            .execute()
            .value
        return StoreHomeView.plannedShifts(
            from: calendar.startOfDay(for: start),
            to: end,
            entries: try await entries,
            templates: try await templates,
            workerNames: Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0.name) })
        )
        #else
        return []
        #endif
    }

    // MARK: - Helpers

    var calendar: Calendar { AppTime.calendar }
    var dayFormatter: DateFormatter { AppTime.displayFormatter("yyyy-MM-dd") }
    var monthFormatter: DateFormatter { AppTime.displayFormatter("yyyy-MM") }
    var dayLabelFormatter: DateFormatter { AppTime.displayFormatter("M월 d일 (E)") }

    var weekCalendar: Calendar {
        var cal = AppTime.calendar
        cal.firstWeekday = 2 // 월요일
        return cal
    }

    // 이름 일부로 알바를 찾는다. 정확히 같은 이름이 있으면 그 사람만.
    func filterWorkers(_ workers: [WorkerRow], name: String?) throws -> [WorkerRow] {
        let query = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return workers }
        if let exact = workers.filter({ $0.name == query }).first {
            return [exact]
        }
        let matches = workers.filter { $0.name.contains(query) }
        let names = workers.map(\.name).joined(separator: ", ")
        if matches.isEmpty {
            throw ToolError(message: "'\(query)' 이름의 알바가 없어요. 등록된 알바: \(names)")
        }
        if matches.count > 1 {
            throw ToolError(message: "'\(query)'에 해당하는 알바가 여러 명이에요: \(matches.map(\.name).joined(separator: ", "))")
        }
        return matches
    }

    func paidMinutes(_ log: LogRow, start: Date, end: Date) -> Int {
        PayrollCalculator.calcPaidMinutes(
            checkIn: start,
            checkOut: end,
            appliedBreakPolicy: log.applied_break_policy,
            appliedBreakMinutes: log.applied_break_minutes
        )
    }

    func pay(_ log: LogRow, worker: WorkerRow, start: Date, end: Date) -> Double {
        PayrollCalculator.grossPay(
            checkIn: start,
            checkOut: end,
            appliedHourlyWage: log.applied_hourly_wage,
            appliedNightAllowance: log.applied_night_allowance,
            fallbackHourlyWage: worker.hourly_wage ?? 0,
            fallbackNightAllowance: worker.apply_night_allowance ?? false,
            appliedBreakPolicy: log.applied_break_policy,
            appliedBreakMinutes: log.applied_break_minutes
        )
    }

    private func logItem(_ log: LogRow, worker: WorkerRow?) -> LogItem? {
        guard let worker, let start = AppTime.parseISO(log.check_in_at) else { return nil }
        let time = AppTime.displayFormatter("HH:mm")
        let end = log.check_out_at.flatMap(AppTime.parseISO)
        return LogItem(
            id: log.id,
            name: worker.name,
            date: dayLabelFormatter.string(from: start),
            time: "\(time.string(from: start))–\(end.map { time.string(from: $0) } ?? "근무 중")",
            status: end == nil ? "근무 중" : statusLabel(log.status),
            paidHours: end.map { formatHours(paidMinutes(log, start: start, end: $0)) } ?? "-",
            pay: end.map { Int(pay(log, worker: worker, start: start, end: $0)) }
        )
    }

    func breakText(policy: String?, minutes: Int?) -> String {
        switch PayrollBreakPolicy(rawOrNone: policy) {
        case .none: return "휴게 없음"
        case .statutory: return "법정 기준(4시간 30분, 8시간 1시간)"
        case .custom: return "근무마다 \(minutes ?? 0)분"
        }
    }

    func parseMonth(_ text: String?) throws -> Date {
        guard let text, !text.isEmpty else {
            return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        }
        guard let date = monthFormatter.date(from: text) else {
            throw ToolError(message: "월은 YYYY-MM 형식이어야 해요: \(text)")
        }
        return date
    }

    func parseDay(_ text: String) throws -> Date {
        guard let date = dayFormatter.date(from: text) else {
            throw ToolError(message: "날짜는 YYYY-MM-DD 형식이어야 해요: \(text)")
        }
        return date
    }

    // 종료일을 포함하도록 다음 날 0시까지로 잡는다. 너무 긴 기간은 막는다.
    private func parseRange(from: String?, to: String?) throws -> (Date, Date) {
        guard let from, let to else { throw ToolError(message: "from, to 날짜가 필요해요.") }
        let start = try parseDay(from)
        let lastDay = try parseDay(to)
        guard let end = calendar.date(byAdding: .day, value: 1, to: lastDay), start < end else {
            throw ToolError(message: "기간이 올바르지 않아요.")
        }
        guard end.timeIntervalSince(start) <= 93 * 86_400 else {
            throw ToolError(message: "한 번에 3개월까지만 조회할 수 있어요.")
        }
        return (start, end)
    }

    func weekText(_ week: DateInterval) -> String {
        let last = week.end.addingTimeInterval(-1)
        return "\(dayLabelFormatter.string(from: week.start)) ~ \(dayLabelFormatter.string(from: last))"
    }
}

import Foundation
#if canImport(Supabase)
import Supabase
#endif

// AI 비서가 근무를 바꾸는 도구. Claude가 부르면 바로 저장하지 않고 확인 카드(제안)만 만든다.
// 사장님이 카드에서 확인을 눌러야 execute로 저장한다.
// 여러 명·여러 건을 바꾸는 카드는 항목마다 체크를 두고, 체크된 항목만 저장한다.
struct OwnerAgentProposal {
    enum Kind {
        case add(workerId: UUID, start: Date, end: Date)
        case update(logId: UUID, start: Date, end: Date)
        case setStatus(logIds: [UUID], status: String)
        // workerId가 nil이면 매장 기본값을 바꾸고 모든 알바가 따르게 한다.
        case payrollSettings(workerId: UUID?, changes: PayrollChanges, reapplyThisMonth: Bool)
        case absent(date: Date, entries: [AbsentEntry])
    }

    struct AbsentEntry {
        let workerId: UUID
        // 그날 반려할 근무 기록(반려 제외)
        let logIds: [UUID]
    }

    // 체크할 수 있는 항목. id는 근무 기록 id 또는 알바 id.
    struct Item: Identifiable, Hashable {
        let id: UUID
        let title: String
        let detail: String
    }

    struct PayrollChanges {
        var hourlyWage: Double?
        var nightAllowance: Bool?
        var weeklyAllowance: Bool?
        var breakPolicy: String?
        var breakMinutes: Int?

        var isEmpty: Bool {
            hourlyWage == nil && nightAllowance == nil && weeklyAllowance == nil && breakPolicy == nil
        }
    }

    struct Row: Hashable {
        let label: String
        let value: String
    }

    let kind: Kind
    let title: String
    let rows: [Row]
    let items: [Item]
    let isDestructive: Bool
    // 그 주 근무시간·주휴수당이 어떻게 바뀌는지. 체크한 항목에 따라 달라진다.
    private let effectsFor: (Set<UUID>) -> [String]
    private let confirmTitleFor: (Int) -> String
    // 저장 후 Claude에게 돌려줄 한 줄 요약
    private let summaryFor: (Set<UUID>) -> String

    init(kind: Kind, title: String, rows: [Row], effects: [String], confirmTitle: String, isDestructive: Bool, summary: String) {
        self.kind = kind
        self.title = title
        self.rows = rows
        self.items = []
        self.isDestructive = isDestructive
        self.effectsFor = { _ in effects }
        self.confirmTitleFor = { _ in confirmTitle }
        self.summaryFor = { _ in summary }
    }

    init(
        kind: Kind,
        title: String,
        rows: [Row],
        items: [Item],
        isDestructive: Bool,
        effects: @escaping (Set<UUID>) -> [String],
        confirmTitle: @escaping (Int) -> String,
        summary: @escaping (Set<UUID>) -> String
    ) {
        self.kind = kind
        self.title = title
        self.rows = rows
        self.items = items
        self.isDestructive = isDestructive
        self.effectsFor = effects
        self.confirmTitleFor = confirmTitle
        self.summaryFor = summary
    }

    var allItemIds: Set<UUID> { Set(items.map(\.id)) }
    func effects(selected: Set<UUID>) -> [String] { effectsFor(selected) }
    func confirmTitle(selectedCount: Int) -> String { confirmTitleFor(selectedCount) }
    func summary(selected: Set<UUID>) -> String { summaryFor(selected) }
}

extension OwnerAgentTools {
    static let writeToolNames: Set<String> = ["add_work_log", "update_work_log", "set_work_log_status", "update_payroll_settings", "mark_absent"]

    // 필수 값이 빠졌거나 틀리면 ToolError로 돌려보내, Claude가 사장님께 다시 묻게 한다.
    func propose(name: String, input: [String: AnyJSON]) async throws -> OwnerAgentProposal {
        switch name {
        case "add_work_log":
            return try await proposeAdd(input)
        case "update_work_log":
            return try await proposeUpdate(input)
        case "set_work_log_status":
            return try await proposeStatus(input)
        case "update_payroll_settings":
            return try await proposeSettings(input)
        case "mark_absent":
            return try await proposeAbsent(input)
        default:
            throw ToolError(message: "알 수 없는 도구: \(name)")
        }
    }

    // selected: 체크된 항목 id. 항목이 없는 카드는 무시한다.
    func execute(_ proposal: OwnerAgentProposal, selected: Set<UUID>) async throws {
        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        let ownerId = try await SupabaseManager.shared.currentUserId()
        let now = AppTime.isoString(from: Date())
        switch proposal.kind {
        case let .add(workerId, start, end):
            struct InsertPayload: Encodable {
                let store_id: UUID
                let worker_id: UUID
                let check_in_at: String
                let check_out_at: String
                let status: String
                let approved_by: UUID
                let approved_at: String
            }
            // 사장님이 직접 넣는 근무라 알바관리의 수동 추가처럼 바로 승인 상태로 넣는다.
            _ = try await client.from("work_logs").insert(InsertPayload(
                store_id: storeId,
                worker_id: workerId,
                check_in_at: AppTime.isoString(from: start),
                check_out_at: AppTime.isoString(from: end),
                status: "approved",
                approved_by: ownerId,
                approved_at: now
            )).execute()
        case let .update(logId, start, end):
            struct UpdatePayload: Encodable {
                let check_in_at: String
                let check_out_at: String
                let status: String
                let approved_by: UUID
                let approved_at: String
            }
            _ = try await client.from("work_logs").update(UpdatePayload(
                check_in_at: AppTime.isoString(from: start),
                check_out_at: AppTime.isoString(from: end),
                status: "approved",
                approved_by: ownerId,
                approved_at: now
            ))
            .eq("id", value: logId.uuidString)
            .eq("store_id", value: storeId.uuidString)
            .execute()
        case let .setStatus(allLogIds, status):
            let logIds = allLogIds.filter(selected.contains)
            guard !logIds.isEmpty else { return }
            struct StatusPayload: Encodable {
                let status: String
                let approved_by: UUID
                let approved_at: String
            }
            _ = try await client.from("work_logs").update(StatusPayload(
                status: status,
                approved_by: ownerId,
                approved_at: now
            ))
            .in("id", values: logIds.map(\.uuidString))
            .eq("store_id", value: storeId.uuidString)
            .execute()
        case let .payrollSettings(workerId, changes, reapplyThisMonth):
            // 알바 한 명이면 그 알바의 예외 설정으로, 전체면 매장 기본값을 바꾸고 예외 설정을 지운다.
            // 알바관리 화면과 같은 칸을 쓴다(실제 적용값은 DB 트리거가 맞춘다).
            let customMinutes: AnyJSON = changes.breakPolicy == PayrollBreakPolicy.custom.rawValue
                ? .integer(changes.breakMinutes ?? 0) : .null
            if let workerId {
                var update: [String: AnyJSON] = [:]
                if let wage = changes.hourlyWage { update["hourly_wage_override"] = .double(wage) }
                if let night = changes.nightAllowance { update["apply_night_allowance_override"] = .bool(night) }
                if let weekly = changes.weeklyAllowance { update["apply_weekly_allowance_override"] = .bool(weekly) }
                if let policy = changes.breakPolicy {
                    update["break_policy_override"] = .string(policy)
                    update["break_minutes_override"] = customMinutes
                }
                _ = try await client.from("workers").update(update)
                    .eq("id", value: workerId.uuidString)
                    .eq("store_id", value: storeId.uuidString)
                    .execute()
            } else {
                var defaults: [String: AnyJSON] = [:]
                var clearOverrides: [String: AnyJSON] = [:]
                if let wage = changes.hourlyWage {
                    defaults["default_hourly_wage"] = .double(wage)
                    clearOverrides["hourly_wage_override"] = .null
                }
                if let night = changes.nightAllowance {
                    defaults["default_apply_night_allowance"] = .bool(night)
                    clearOverrides["apply_night_allowance_override"] = .null
                }
                if let weekly = changes.weeklyAllowance {
                    defaults["default_apply_weekly_allowance"] = .bool(weekly)
                    clearOverrides["apply_weekly_allowance_override"] = .null
                }
                if let policy = changes.breakPolicy {
                    defaults["default_break_policy"] = .string(policy)
                    defaults["default_break_minutes"] = .integer(customMinutes.intValue ?? 0)
                    clearOverrides["break_policy_override"] = .null
                    clearOverrides["break_minutes_override"] = .null
                }
                _ = try await client.from("stores").update(defaults)
                    .eq("id", value: storeId.uuidString)
                    .execute()
                _ = try await client.from("workers").update(clearOverrides)
                    .eq("store_id", value: storeId.uuidString)
                    .execute()
            }
            if reapplyThisMonth {
                try await SupabaseManager.shared.reapplyPayrollTermsThisMonth(storeId: storeId, workerId: workerId)
            }
        case let .absent(date, allEntries):
            let entries = allEntries.filter { selected.contains($0.workerId) }
            guard !entries.isEmpty else { return }
            struct AbsenceInsert: Encodable {
                let store_id: UUID
                let worker_id: UUID
                let work_date: String
                let created_by: UUID
            }
            _ = try await client.from("work_absences").upsert(
                entries.map {
                    AbsenceInsert(store_id: storeId, worker_id: $0.workerId, work_date: dayFormatter.string(from: date), created_by: ownerId)
                },
                onConflict: "worker_id,work_date",
                ignoreDuplicates: true
            ).execute()
            // 그날 출근 기록이 있으면 반려한다(지우지 않고 남겨 둔다).
            let logIds = entries.flatMap(\.logIds)
            if !logIds.isEmpty {
                struct RejectPayload: Encodable {
                    let status: String
                    let approved_by: UUID
                    let approved_at: String
                }
                _ = try await client.from("work_logs")
                    .update(RejectPayload(status: "rejected", approved_by: ownerId, approved_at: now))
                    .in("id", values: logIds.map(\.uuidString))
                    .eq("store_id", value: storeId.uuidString)
                    .execute()
            }
        }
        #endif
    }

    // MARK: - Proposals

    private func proposeAdd(_ input: [String: AnyJSON]) async throws -> OwnerAgentProposal {
        let missing = ["worker_name", "date", "start_time", "end_time"].filter {
            (input[$0]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard missing.isEmpty else {
            throw ToolError(message: "필수 값이 빠졌어요: \(missing.joined(separator: ", ")). 추측하지 말고 사장님께 물어보세요.")
        }
        let workers = try await fetchWorkers()
        let worker = try exactlyOneWorker(workers, name: input["worker_name"]?.stringValue)
        let (start, end) = try shiftDates(
            date: input["date"]?.stringValue,
            startTime: input["start_time"]?.stringValue,
            endTime: input["end_time"]?.stringValue
        )
        try await ensureNoOverlap(workerId: worker.id, start: start, end: end, excluding: nil)

        let policy = PayrollBreakPolicy(rawOrNone: worker.break_policy)
        let paid = PayrollCalculator.calcPaidMinutes(checkIn: start, checkOut: end, breakPolicy: policy, customBreakMinutes: worker.break_minutes ?? 0)
        let stay = PayrollCalculator.calcMinutes(checkIn: start, checkOut: end)
        let pay = PayrollCalculator.grossPay(
            checkIn: start,
            checkOut: end,
            wage: worker.hourly_wage ?? 0,
            applyNightAllowance: worker.apply_night_allowance ?? false,
            breakPolicy: policy,
            customBreakMinutes: worker.break_minutes ?? 0
        )
        let effects = try await weeklyEffects([Delta(worker: worker, date: start, minutes: paid)])
        return OwnerAgentProposal(
            kind: .add(workerId: worker.id, start: start, end: end),
            title: "근무 추가",
            rows: [
                .init(label: "알바", value: worker.name),
                .init(label: "날짜", value: dayLabelFormatter.string(from: start)),
                .init(label: "시간", value: timeRangeText(start: start, end: end)),
                .init(label: "근무시간", value: paidText(stay: stay, paid: paid)),
                .init(label: "급여", value: "\(formatWon(pay)) (세전)")
            ],
            effects: effects,
            confirmTitle: "추가하기",
            isDestructive: false,
            summary: "\(worker.name) \(dayLabelFormatter.string(from: start)) \(timeRangeText(start: start, end: end)) 근무를 승인 상태로 추가함"
        )
    }

    private func proposeUpdate(_ input: [String: AnyJSON]) async throws -> OwnerAgentProposal {
        let missing = ["log_id", "start_time", "end_time"].filter {
            (input[$0]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard missing.isEmpty else {
            throw ToolError(message: "필수 값이 빠졌어요: \(missing.joined(separator: ", ")). 근무 기록 id는 get_work_logs로 찾고, 시각은 사장님께 물어보세요.")
        }
        guard let logId = input["log_id"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let log = try await fetchLogs(ids: [logId]).first else {
            throw ToolError(message: "그 근무 기록을 찾지 못했어요. get_work_logs로 id를 다시 확인하세요.")
        }
        let workers = try await fetchWorkers()
        guard let worker = workers.first(where: { $0.id == log.worker_id }),
              let oldStart = AppTime.parseISO(log.check_in_at) else {
            throw ToolError(message: "그 근무 기록의 알바를 찾지 못했어요.")
        }
        let oldEnd = log.check_out_at.flatMap(AppTime.parseISO)
        let date = input["date"]?.stringValue ?? dayFormatter.string(from: oldStart)
        let (start, end) = try shiftDates(date: date, startTime: input["start_time"]?.stringValue, endTime: input["end_time"]?.stringValue)
        try await ensureNoOverlap(workerId: worker.id, start: start, end: end, excluding: log.id)

        // 수정해도 기록에 저장된 시급·휴게 설정은 그대로라, 새 급여도 그 설정으로 계산한다.
        let newPaid = paidMinutes(log, start: start, end: end)
        let newPay = pay(log, worker: worker, start: start, end: end)
        var deltas = [Delta(worker: worker, date: start, minutes: newPaid)]
        var oldPayText = "-"
        if let oldEnd {
            oldPayText = formatWon(pay(log, worker: worker, start: oldStart, end: oldEnd))
            if normalizedStatus(log.status) == "approved" {
                deltas.append(Delta(worker: worker, date: oldStart, minutes: -paidMinutes(log, start: oldStart, end: oldEnd)))
            }
        }
        let oldTime = oldEnd.map { timeRangeText(start: oldStart, end: $0) } ?? "\(AppTime.displayFormatter("HH:mm").string(from: oldStart))– 근무 중"
        let effects = try await weeklyEffects(deltas)
        var rows: [OwnerAgentProposal.Row] = [
            .init(label: "알바", value: worker.name),
            .init(label: "날짜", value: dayLabelFormatter.string(from: start)),
            .init(label: "시간", value: "\(oldTime) → \(timeRangeText(start: start, end: end))"),
            .init(label: "급여", value: "\(oldPayText) → \(formatWon(newPay))")
        ]
        if normalizedStatus(log.status) != "approved" {
            rows.append(.init(label: "상태", value: "\(statusLabel(log.status)) → 승인"))
        }
        return OwnerAgentProposal(
            kind: .update(logId: log.id, start: start, end: end),
            title: "근무 수정",
            rows: rows,
            effects: effects,
            confirmTitle: "수정하기",
            isDestructive: false,
            summary: "\(worker.name) \(dayLabelFormatter.string(from: start)) 근무를 \(timeRangeText(start: start, end: end))로 수정하고 승인함"
        )
    }

    private func proposeStatus(_ input: [String: AnyJSON]) async throws -> OwnerAgentProposal {
        guard let status = input["status"]?.stringValue, ["approved", "rejected"].contains(status) else {
            throw ToolError(message: "status는 approved 또는 rejected여야 해요.")
        }
        let ids = (input["log_ids"]?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
        guard !ids.isEmpty else {
            throw ToolError(message: "log_ids가 비었어요. list_pending_approvals나 get_work_logs로 id를 찾으세요.")
        }
        guard ids.count <= 30 else {
            throw ToolError(message: "한 번에 30건까지만 처리할 수 있어요.")
        }
        let logs = try await fetchLogs(ids: ids)
        guard logs.count == Set(ids).count else {
            throw ToolError(message: "찾지 못한 근무 기록이 있어요. id를 다시 확인하세요.")
        }
        let workers = Dictionary(uniqueKeysWithValues: try await fetchWorkers().map { ($0.id, $0) })
        var items: [OwnerAgentProposal.Item] = []
        var deltasByItem: [UUID: Delta] = [:]
        var payByItem: [UUID: Double] = [:]
        for log in logs.sorted(by: { $0.check_in_at < $1.check_in_at }) {
            guard let worker = workers[log.worker_id],
                  let start = AppTime.parseISO(log.check_in_at),
                  let end = log.check_out_at.flatMap(AppTime.parseISO) else {
                throw ToolError(message: "아직 퇴근하지 않은 근무는 승인·반려할 수 없어요.")
            }
            let amount = pay(log, worker: worker, start: start, end: end)
            payByItem[log.id] = amount
            items.append(.init(
                id: log.id,
                title: "\(worker.name) · \(dayLabelFormatter.string(from: start))",
                detail: "\(timeRangeText(start: start, end: end)) · \(formatWon(amount))"
            ))
            let wasApproved = normalizedStatus(log.status) == "approved"
            let minutes = paidMinutes(log, start: start, end: end)
            if status == "approved" && !wasApproved {
                deltasByItem[log.id] = Delta(worker: worker, date: start, minutes: minutes)
            } else if status == "rejected" && wasApproved {
                deltasByItem[log.id] = Delta(worker: worker, date: start, minutes: -minutes)
            }
        }
        let bases = try await weekBases(Array(deltasByItem.values))
        let isApprove = status == "approved"
        let verb = isApprove ? "승인" : "반려"
        return OwnerAgentProposal(
            kind: .setStatus(logIds: logs.map(\.id), status: status),
            title: "근무 \(verb)",
            rows: [],
            items: items,
            isDestructive: !isApprove,
            effects: { selected in
                let total = selected.reduce(0.0) { $0 + (payByItem[$1] ?? 0) }
                return ["\(selected.count)건 · \(formatWon(total))"]
                    + effectLines(bases, deltas: selected.compactMap { deltasByItem[$0] })
            },
            confirmTitle: { "\($0)건 \(verb)하기" },
            summary: { "근무 \($0.count)건을 \(verb)함" }
        )
    }

    // 결근 처리: 그날 결근을 기록하고, 출근 기록이 있으면 반려한다. 사람마다 체크할 수 있다.
    private func proposeAbsent(_ input: [String: AnyJSON]) async throws -> OwnerAgentProposal {
        guard let dateText = input["date"]?.stringValue, !dateText.isEmpty else {
            throw ToolError(message: "결근한 날짜가 필요해요. 사장님께 물어보세요.")
        }
        let names = (input["worker_names"]?.arrayValue ?? []).compactMap(\.stringValue).filter { !$0.isEmpty }
        guard !names.isEmpty else {
            throw ToolError(message: "worker_names가 비었어요. '다/모두'라고 했으면 get_schedule로 그날 스케줄이 있는 알바를 찾아 이름을 모두 넣으세요.")
        }
        let day = try parseDay(dateText)
        guard day <= Date() else {
            throw ToolError(message: "아직 오지 않은 날은 결근 처리할 수 없어요. 스케줄을 바꾸려면 스케줄 화면을 쓰세요.")
        }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let allWorkers = try await fetchWorkers()
        var targets: [WorkerRow] = []
        for name in names {
            let worker = try exactlyOneWorker(allWorkers, name: name)
            if !targets.contains(where: { $0.id == worker.id }) { targets.append(worker) }
        }

        let shifts = try await plannedShifts(from: day, to: nextDay, workers: targets)
        let logs = try await fetchLogs(from: day, to: nextDay, workerIds: targets.map(\.id))
            .filter { normalizedStatus($0.status) != "rejected" }
        let alreadyAbsent = try await absentWorkerIds(on: day, workerIds: targets.map(\.id))
        let time = AppTime.displayFormatter("HH:mm")

        var items: [OwnerAgentProposal.Item] = []
        var entries: [OwnerAgentProposal.AbsentEntry] = []
        var deltasByItem: [UUID: Delta] = [:]
        var skipped: [String] = []
        for worker in targets {
            guard !alreadyAbsent.contains(worker.id) else {
                skipped.append(worker.name)
                continue
            }
            let workerLogs = logs.filter { $0.worker_id == worker.id }
            var parts: [String] = []
            if let shift = shifts.first(where: { $0.workerId == worker.id }) {
                parts.append("\(time.string(from: shift.start))–\(shift.end.map { time.string(from: $0) } ?? "미정") 스케줄")
            } else {
                parts.append("스케줄 없음")
            }
            var approvedMinutes = 0
            for log in workerLogs {
                guard let start = AppTime.parseISO(log.check_in_at) else { continue }
                let end = log.check_out_at.flatMap(AppTime.parseISO)
                parts.append("출근 기록 \(time.string(from: start))–\(end.map { time.string(from: $0) } ?? "근무 중") → 반려")
                if let end, normalizedStatus(log.status) == "approved" {
                    approvedMinutes += paidMinutes(log, start: start, end: end)
                }
            }
            items.append(.init(id: worker.id, title: worker.name, detail: parts.joined(separator: " · ")))
            entries.append(.init(workerId: worker.id, logIds: workerLogs.map(\.id)))
            if approvedMinutes > 0 {
                deltasByItem[worker.id] = Delta(worker: worker, date: day, minutes: -approvedMinutes)
            }
        }
        guard !items.isEmpty else {
            throw ToolError(message: "\(skipped.joined(separator: ", "))은(는) 그날 이미 결근 처리돼 있어요.")
        }

        let bases = try await weekBases(Array(deltasByItem.values))
        let names_ = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.title) })
        var rows: [OwnerAgentProposal.Row] = [.init(label: "날짜", value: dayLabelFormatter.string(from: day))]
        if !skipped.isEmpty {
            rows.append(.init(label: "이미 결근", value: skipped.joined(separator: ", ")))
        }
        return OwnerAgentProposal(
            kind: .absent(date: day, entries: entries),
            title: "결근 처리",
            rows: rows,
            items: items,
            isDestructive: true,
            effects: { selected in
                effectLines(bases, deltas: selected.compactMap { deltasByItem[$0] })
            },
            confirmTitle: { "\($0)명 결근 처리" },
            summary: { selected in
                let picked = items.filter { selected.contains($0.id) }.compactMap { names_[$0.id] }
                return "\(dayLabelFormatter.string(from: day)) \(picked.joined(separator: ", ")) 결근 처리함(그날 출근 기록은 반려)"
            }
        )
    }

    private func absentWorkerIds(on day: Date, workerIds: [UUID]) async throws -> Set<UUID> {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let keys = try await absenceKeys(from: day, to: nextDay, workerIds: workerIds)
        return Set(workerIds.filter { keys.contains(absenceKey($0, day)) })
    }

    private func proposeSettings(_ input: [String: AnyJSON]) async throws -> OwnerAgentProposal {
        guard let applyTo = input["apply_to"]?.stringValue, ["future", "this_month"].contains(applyTo) else {
            throw ToolError(message: "apply_to(future 또는 this_month)가 필요해요. 이번 달 이미 일한 근무에도 적용할지 사장님께 물어보세요.")
        }
        var changes = OwnerAgentProposal.PayrollChanges()
        if let wage = input["hourly_wage"]?.doubleValue ?? input["hourly_wage"]?.intValue.map(Double.init) {
            guard wage >= AppConfig.minimumHourlyWage else {
                throw ToolError(message: "최저시급(\(formatWon(AppConfig.minimumHourlyWage)))보다 낮은 시급은 저장할 수 없어요.")
            }
            changes.hourlyWage = wage
        }
        changes.nightAllowance = input["night_allowance"]?.boolValue
        changes.weeklyAllowance = input["weekly_allowance"]?.boolValue
        if let policy = input["break_policy"]?.stringValue {
            guard PayrollBreakPolicy(rawValue: policy) != nil else {
                throw ToolError(message: "break_policy는 none, statutory, custom 중 하나여야 해요.")
            }
            changes.breakPolicy = policy
            if policy == PayrollBreakPolicy.custom.rawValue {
                guard let minutes = input["break_minutes"]?.intValue, (0...240).contains(minutes) else {
                    throw ToolError(message: "휴게를 직접 정하려면 break_minutes(0~240분)가 필요해요. 사장님께 물어보세요.")
                }
                changes.breakMinutes = minutes
            }
        }
        guard !changes.isEmpty else {
            throw ToolError(message: "바꿀 설정이 없어요. 시급, 야간수당, 주휴수당, 휴게 중 무엇을 바꿀지 사장님께 물어보세요.")
        }

        let allWorkers = try await fetchWorkers()
        let workerName = input["worker_name"]?.stringValue.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let targets = workerName == nil
            ? allWorkers.filter { $0.is_active ?? true }
            : [try exactlyOneWorker(allWorkers, name: workerName)]
        let reapply = applyTo == "this_month"

        func updated(_ worker: WorkerRow) -> WorkerRow {
            WorkerRow(
                id: worker.id,
                name: worker.name,
                hourly_wage: changes.hourlyWage ?? worker.hourly_wage,
                apply_night_allowance: changes.nightAllowance ?? worker.apply_night_allowance,
                apply_weekly_allowance: changes.weeklyAllowance ?? worker.apply_weekly_allowance,
                break_policy: changes.breakPolicy ?? worker.break_policy,
                break_minutes: changes.breakPolicy.map { _ in changes.breakMinutes ?? 0 } ?? worker.break_minutes,
                is_active: worker.is_active
            )
        }
        let changedTargets = targets.filter { worker in
            let new = updated(worker)
            return new.hourly_wage != worker.hourly_wage
                || new.apply_night_allowance != worker.apply_night_allowance
                || new.apply_weekly_allowance != worker.apply_weekly_allowance
                || new.break_policy != worker.break_policy
                || new.break_minutes != worker.break_minutes
        }
        guard !changedTargets.isEmpty else {
            throw ToolError(message: "이미 그 설정이에요. 바뀌는 알바가 없어요.")
        }

        var rows: [OwnerAgentProposal.Row] = [
            .init(label: "대상", value: workerName == nil ? "매장 전체 (\(changedTargets.map(\.name).joined(separator: ", ")))" : changedTargets[0].name)
        ]
        let single = workerName == nil ? nil : changedTargets[0]
        func change(_ label: String, old: String?, new: String) {
            rows.append(.init(label: label, value: old.map { $0 == new ? new : "\($0) → \(new)" } ?? new))
        }
        if let wage = changes.hourlyWage {
            change("시급", old: single.map { formatWon($0.hourly_wage ?? 0) }, new: formatWon(wage))
        }
        if let night = changes.nightAllowance {
            change("야간수당", old: single.map { ($0.apply_night_allowance ?? false) ? "지급" : "미지급" }, new: night ? "지급" : "미지급")
        }
        if let weekly = changes.weeklyAllowance {
            change("주휴수당", old: single.map { ($0.apply_weekly_allowance ?? false) ? "지급" : "미지급" }, new: weekly ? "지급" : "미지급")
        }
        if let policy = changes.breakPolicy {
            change("휴게", old: single.map { breakText(policy: $0.break_policy, minutes: $0.break_minutes) }, new: breakText(policy: policy, minutes: changes.breakMinutes))
        }
        let monthStart = try parseMonth(nil)
        rows.append(.init(
            label: "적용",
            value: reapply ? "이번 달 근무부터 (\(AppTime.displayFormatter("M월 d일").string(from: monthStart))~)" : "앞으로의 근무부터"
        ))

        var effects: [String] = []
        if reapply {
            // 이번 달 근무에 새 설정을 입혀 다시 계산해 본다(저장 전 미리보기).
            let range = PayrollCalculator.weeklyAllowanceLogRange(forMonth: monthStart)
            let logs = try await fetchLogs(from: range.start, to: range.end, workerIds: changedTargets.map(\.id))
            let logsByWorker = Dictionary(grouping: logs, by: \.worker_id)
            var beforeTotal: Double = 0
            var afterTotal: Double = 0
            for worker in changedTargets {
                let workerLogs = logsByWorker[worker.id] ?? []
                let new = updated(worker)
                let reapplied = workerLogs.map { log -> LogRow in
                    guard let start = AppTime.parseISO(log.check_in_at), start >= monthStart else { return log }
                    return LogRow(
                        id: log.id,
                        worker_id: log.worker_id,
                        check_in_at: log.check_in_at,
                        check_out_at: log.check_out_at,
                        status: log.status,
                        applied_hourly_wage: new.hourly_wage,
                        applied_night_allowance: new.apply_night_allowance,
                        applied_break_policy: new.break_policy,
                        applied_break_minutes: new.break_minutes,
                        applied_weekly_allowance: new.apply_weekly_allowance
                    )
                }
                let before = monthTotals(worker: worker, logs: workerLogs, monthStart: monthStart)
                let after = monthTotals(worker: new, logs: reapplied, monthStart: monthStart)
                let beforePay = before.workPay + before.allowance
                let afterPay = after.workPay + after.allowance
                beforeTotal += beforePay
                afterTotal += afterPay
                effects.append("\(worker.name) 이번 달: \(formatWon(beforePay)) → \(formatWon(afterPay))")
            }
            if changedTargets.count > 1 {
                effects.append("합계: \(formatWon(beforeTotal)) → \(formatWon(afterTotal))")
            }
        } else {
            effects.append("이번 달 이미 기록된 근무 금액은 그대로예요.")
        }

        let target = workerName == nil ? "매장 전체" : changedTargets[0].name
        return OwnerAgentProposal(
            kind: .payrollSettings(workerId: single?.id, changes: changes, reapplyThisMonth: reapply),
            title: "급여 설정 변경",
            rows: rows,
            effects: effects,
            confirmTitle: "바꾸기",
            isDestructive: false,
            summary: "\(target) 급여 설정을 바꿈(\(reapply ? "이번 달 근무부터 다시 적용" : "앞으로의 근무부터"))"
        )
    }

    // MARK: - Weekly effect

    private struct Delta {
        let worker: WorkerRow
        let date: Date
        let minutes: Int
    }

    private struct WeekKey: Hashable {
        let workerId: UUID
        let weekStart: Date
    }

    private struct WeekBase {
        let worker: WorkerRow
        let week: DateInterval
        let approvedMinutes: Int
    }

    // 바뀌는 (알바, 주)마다 지금 승인된 근무시간을 미리 받아 둔다. 체크를 바꿀 때마다 다시 받지 않게.
    private func weekBases(_ deltas: [Delta]) async throws -> [WeekKey: WeekBase] {
        var bases: [WeekKey: WeekBase] = [:]
        for delta in deltas {
            guard let week = weekCalendar.dateInterval(of: .weekOfYear, for: delta.date) else { continue }
            let key = WeekKey(workerId: delta.worker.id, weekStart: week.start)
            guard bases[key] == nil else { continue }
            let logs = try await fetchLogs(from: week.start, to: week.end, workerIds: [delta.worker.id])
            var minutes = 0
            for log in logs where normalizedStatus(log.status) == "approved" {
                guard let start = AppTime.parseISO(log.check_in_at),
                      let end = log.check_out_at.flatMap(AppTime.parseISO) else { continue }
                minutes += paidMinutes(log, start: start, end: end)
            }
            bases[key] = WeekBase(worker: delta.worker, week: week, approvedMinutes: minutes)
        }
        return bases
    }

    // 승인된 근무 기준으로, 바뀌는 주의 근무시간과 주휴수당 전후를 보여 준다.
    private func effectLines(_ bases: [WeekKey: WeekBase], deltas: [Delta]) -> [String] {
        var change: [WeekKey: Int] = [:]
        for delta in deltas {
            guard let week = weekCalendar.dateInterval(of: .weekOfYear, for: delta.date) else { continue }
            change[WeekKey(workerId: delta.worker.id, weekStart: week.start), default: 0] += delta.minutes
        }
        return change
            .sorted { ($0.key.weekStart, $0.key.workerId.uuidString) < ($1.key.weekStart, $1.key.workerId.uuidString) }
            .compactMap { key, minutes -> String? in
                guard minutes != 0, let base = bases[key] else { return nil }
                let before = base.approvedMinutes
                let after = max(0, before + minutes)
                var line = "\(base.worker.name) · \(weekText(base.week)) 주: \(formatHours(before)) → \(formatHours(after))"
                if base.worker.apply_weekly_allowance == true {
                    let wage = base.worker.hourly_wage ?? 0
                    let allowanceBefore = PayrollCalculator.weeklyAllowancePay(weekMinutes: before, wage: wage)
                    let allowanceAfter = PayrollCalculator.weeklyAllowancePay(weekMinutes: after, wage: wage)
                    line += ", 주휴수당 \(formatWon(allowanceBefore)) → \(formatWon(allowanceAfter))"
                }
                return line
            }
    }

    private func weeklyEffects(_ deltas: [Delta]) async throws -> [String] {
        effectLines(try await weekBases(deltas), deltas: deltas)
    }

    // MARK: - Validation

    private func exactlyOneWorker(_ workers: [WorkerRow], name: String?) throws -> WorkerRow {
        let matches = try filterWorkers(workers, name: name)
        guard matches.count == 1, let worker = matches.first else {
            throw ToolError(message: "알바를 한 명으로 정해야 해요. 등록된 알바: \(workers.map(\.name).joined(separator: ", "))")
        }
        return worker
    }

    // 퇴근 시각이 출근보다 이르면 다음 날 퇴근(야간 근무)으로 본다.
    private func shiftDates(date: String?, startTime: String?, endTime: String?) throws -> (Date, Date) {
        guard let date, let startTime, let endTime else {
            throw ToolError(message: "날짜와 출근·퇴근 시각이 모두 필요해요.")
        }
        let day = try parseDay(date)
        guard let start = time(startTime, on: day), let sameDayEnd = time(endTime, on: day) else {
            throw ToolError(message: "시각은 HH:mm 형식이어야 해요: \(startTime), \(endTime)")
        }
        guard start != sameDayEnd else {
            throw ToolError(message: "출근과 퇴근 시각이 같아요. 사장님께 다시 확인하세요.")
        }
        let end = sameDayEnd > start ? sameDayEnd : (calendar.date(byAdding: .day, value: 1, to: sameDayEnd) ?? sameDayEnd)
        guard end <= Date() else {
            throw ToolError(message: "아직 끝나지 않은 근무는 추가하거나 바꿀 수 없어요. 미래 근무는 스케줄 화면에서 정하세요.")
        }
        return (start, end)
    }

    private func time(_ text: String, on day: Date) -> Date? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    // 같은 알바의 다른 근무(반려 제외)와 시간이 겹치면 막는다.
    private func ensureNoOverlap(workerId: UUID, start: Date, end: Date, excluding: UUID?) async throws {
        let from = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let logs = try await fetchLogs(from: from, to: end, workerIds: [workerId])
        for log in logs where log.id != excluding && normalizedStatus(log.status) != "rejected" {
            guard let otherStart = AppTime.parseISO(log.check_in_at) else { continue }
            let otherEnd = log.check_out_at.flatMap(AppTime.parseISO) ?? Date()
            if otherStart < end && start < otherEnd {
                throw ToolError(message: "그 시간에 이미 근무 기록이 있어요: \(dayLabelFormatter.string(from: otherStart)) \(timeRangeText(start: otherStart, end: otherEnd)). 새로 추가하지 말고 그 기록을 수정할지 사장님께 물어보세요.")
            }
        }
    }

    private func timeRangeText(start: Date, end: Date) -> String {
        let formatter = AppTime.displayFormatter("HH:mm")
        let nextDay = calendar.isDate(start, inSameDayAs: end) ? "" : "다음 날 "
        return "\(formatter.string(from: start))–\(nextDay)\(formatter.string(from: end))"
    }

    private func paidText(stay: Int, paid: Int) -> String {
        stay == paid ? formatHours(paid) : "\(formatHours(paid)) (휴게 \(stay - paid)분 제외)"
    }
}

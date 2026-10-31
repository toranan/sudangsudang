import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

// 직원별 급여 설정. 항목마다 "매장 기본"을 따르거나 이 직원만 다르게 정한다.
// DB 마이그레이션 전에는 매장 기본 없이 직원 값만 바로 바꾼다.
struct WorkerPayrollSettingsView: View {
    let workerId: UUID
    let storeId: UUID
    let onSaved: () async -> Void

    private static let storeChoice = "store"

    private struct WorkerTerms: Decodable {
        let hourly_wage: Double?
        let apply_weekly_allowance: Bool?
        let apply_night_allowance: Bool?
        let deduction_type: String?
        let payday: Int?
        let hourly_wage_override: Double?
        let apply_weekly_allowance_override: Bool?
        let apply_night_allowance_override: Bool?
        let deduction_type_override: String?
        let break_policy_override: String?
        let break_minutes_override: Int?
    }

    private struct LegacyWorkerTerms: Decodable {
        let hourly_wage: Double?
        let apply_weekly_allowance: Bool?
        let apply_night_allowance: Bool?
        let deduction_type: String?
        let payday: Int?
    }

    private struct StoreDefaults: Decodable {
        let default_hourly_wage: Double?
        let default_apply_weekly_allowance: Bool?
        let default_apply_night_allowance: Bool?
        let default_deduction_type: String?
        let default_break_policy: String?
        let default_break_minutes: Int?
    }

    // nil도 null로 보내야 "매장 기본"으로 돌아간다.
    private struct OverrideUpdate: Encodable {
        let hourly_wage_override: Double?
        let apply_weekly_allowance_override: Bool?
        let apply_night_allowance_override: Bool?
        let deduction_type_override: String?
        let break_policy_override: String?
        let break_minutes_override: Int?
        let payday: Int

        enum CodingKeys: String, CodingKey {
            case hourly_wage_override, apply_weekly_allowance_override, apply_night_allowance_override
            case deduction_type_override, break_policy_override, break_minutes_override, payday
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(hourly_wage_override, forKey: .hourly_wage_override)
            try c.encode(apply_weekly_allowance_override, forKey: .apply_weekly_allowance_override)
            try c.encode(apply_night_allowance_override, forKey: .apply_night_allowance_override)
            try c.encode(deduction_type_override, forKey: .deduction_type_override)
            try c.encode(break_policy_override, forKey: .break_policy_override)
            try c.encode(break_minutes_override, forKey: .break_minutes_override)
            try c.encode(payday, forKey: .payday)
        }
    }

    private struct LegacyUpdate: Encodable {
        let hourly_wage: Double
        let apply_weekly_allowance: Bool
        let apply_night_allowance: Bool
        let deduction_type: String
        let payday: Int
    }

    @State private var defaults: StoreDefaults?
    @State private var isLegacy = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    @State private var wageChoice = WorkerPayrollSettingsView.storeChoice
    @State private var wageInput = ""
    @State private var breakChoice = WorkerPayrollSettingsView.storeChoice
    @State private var breakMinutesInput = ""
    @State private var weeklyChoice = WorkerPayrollSettingsView.storeChoice
    @State private var nightChoice = WorkerPayrollSettingsView.storeChoice
    @State private var deductionChoice = WorkerPayrollSettingsView.storeChoice
    @State private var payday = PayrollLocalSettings.defaultPayday
    @State private var memo = ""
    @State private var savedMemo = ""
    // 근무 기록에 고정되는 값(시급, 야간수당, 휴게). 저장 전후가 다르면 이번 달 근무에 다시 적용할지 묻는다.
    @State private var snapshotTerms: SnapshotTerms?
    @State private var isAskingReapply = false

    @FocusState private var isWageFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                settingsCard
                WorkerFixedScheduleCard(workerId: workerId, storeId: storeId)
                memoCard
                if let errorMessage {
                    Text(errorMessage)
                        .font(.app(.caption, .medium))
                        .foregroundColor(.appWarning)
                }
                Text("시급·야간수당·주휴수당·휴게를 바꾸면 앞으로의 근무부터 적용돼요.")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
                Button(isSaving ? "저장 중..." : (savedMessage ?? "저장")) {
                    Task { await save() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
                .confirmationDialog("이번 달 근무에도 적용할까요?", isPresented: $isAskingReapply, titleVisibility: .visible) {
                    Button("이번 달 근무에도 적용") { Task { await reapplyThisMonth() } }
                    Button("앞으로의 근무만", role: .cancel) {}
                } message: {
                    Text("이번 달에 이미 기록된 근무는 바꾸기 전 설정으로 계산돼 있어요.")
                }
            }
        }
        .task {
            await load()
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if wageChoice == Self.storeChoice, !isLegacy {
                // 매장 기본을 따를 때는 한 줄로 보여주고, 누르면 이 직원만 다르게 입력한다.
                Button {
                    wageInput = String(Int(defaults?.default_hourly_wage ?? AppConfig.defaultHourlyWage))
                    wageChoice = "custom"
                } label: {
                    row("시급") {
                        HStack(spacing: 6) {
                            Text("매장 기본")
                                .font(.app(.callout))
                                .foregroundColor(.appTextSecondary)
                            Text("\(Int(defaults?.default_hourly_wage ?? AppConfig.defaultHourlyWage).formatted())원")
                                .font(.app(.callout, .bold))
                                .foregroundColor(.appTextPrimary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableRowStyle())
            } else {
                row("시급") {
                    HStack(spacing: 6) {
                        if !isLegacy {
                            Button("매장 기본") { wageChoice = Self.storeChoice }
                                .font(.app(.caption, .semibold))
                                .foregroundColor(.appTextSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.appFill, in: Capsule())
                                .buttonStyle(.plain)
                        }
                        TextField("10320", text: $wageInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.app(.callout, .bold))
                            .frame(minWidth: 80, maxWidth: 120)
                            .focused($isWageFocused)
                        Text("원")
                            .font(.app(.callout))
                            .foregroundColor(.appTextSecondary)
                        // 숫자 키패드에는 완료 키가 없어서, 입력 중에만 닫기 버튼을 보여준다.
                        if isWageFocused {
                            Button("완료") { isWageFocused = false }
                                .font(.app(.caption, .semibold))
                                .foregroundColor(.appAccent)
                                .buttonStyle(.plain)
                        }
                    }
                }
                MinimumWageHint(input: wageInput)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 8)
            }
            divider

            if !isLegacy {
                row("무급 휴게") {
                    ChoiceChips(
                        options: choices(PayrollBreakPolicy.allCases.map { ($0.rawValue, shortBreakTitle($0)) }),
                        selected: breakChoice
                    ) { breakChoice = $0 }
                }
                if breakChoice == PayrollBreakPolicy.custom.rawValue {
                    HStack(spacing: 6) {
                        Spacer()
                        Text("근무마다")
                            .font(.app(.callout))
                            .foregroundColor(.appTextSecondary)
                        TextField("30", text: $breakMinutesInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.app(.body, .bold))
                            .frame(width: 50)
                        Text("분")
                            .font(.app(.callout))
                            .foregroundColor(.appTextSecondary)
                    }
                    .padding(.bottom, 10)
                }
                divider
            }

            row("주휴수당") {
                ChoiceChips(options: choices([("on", "지급"), ("off", "미지급")]), selected: weeklyChoice) { weeklyChoice = $0 }
            }
            divider

            row("야간수당") {
                ChoiceChips(options: choices([("on", "지급"), ("off", "미지급")]), selected: nightChoice) { nightChoice = $0 }
            }
            divider

            row("공제") {
                ChoiceChips(
                    options: choices(PayrollDeductionType.allCases.map { ($0.rawValue, shortDeductionTitle($0)) }),
                    selected: deductionChoice
                ) { deductionChoice = $0 }
            }
            divider

            row("월급일") {
                Menu {
                    Picker("월급일", selection: $payday) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)일").tag(day)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("매월 \(payday)일")
                            .font(.app(.callout, .bold))
                            .foregroundColor(.appTextPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    // MARK: - Pieces

    private var divider: some View {
        Rectangle().fill(Color.appLine).frame(height: 1)
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.app(.callout, .semibold))
                .foregroundColor(.appTextPrimary)
                .fixedSize()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, 12)
    }

    private var memoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("메모")
                    .font(.app(.callout, .semibold))
                    .foregroundColor(.appTextPrimary)
                Spacer()
                Text("사장님만 볼 수 있어요")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
            }
            TextField("메모를 남겨보세요", text: $memo, axis: .vertical)
                .font(.app(.callout))
                .lineLimit(2...6)
        }
        .padding(18)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    private func choices(_ own: [(value: String, title: String)]) -> [(value: String, title: String)] {
        isLegacy ? own : [(Self.storeChoice, "매장 기본")] + own
    }

    private func shortBreakTitle(_ policy: PayrollBreakPolicy) -> String {
        switch policy {
        case .none: return "없음"
        case .statutory: return "법정"
        case .custom: return "직접"
        }
    }

    private func shortDeductionTitle(_ type: PayrollDeductionType) -> String {
        type == .withholding ? "3.3%" : "4대보험"
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        let client = SupabaseManager.shared.client
        await loadMemo()
        do {
            async let termsTask: WorkerTerms = client
                .from("workers")
                .select("hourly_wage,apply_weekly_allowance,apply_night_allowance,deduction_type,payday,hourly_wage_override,apply_weekly_allowance_override,apply_night_allowance_override,deduction_type_override,break_policy_override,break_minutes_override")
                .eq("id", value: workerId.uuidString)
                .single()
                .execute()
                .value
            async let defaultsTask: StoreDefaults = client
                .from("stores")
                .select("default_hourly_wage,default_apply_weekly_allowance,default_apply_night_allowance,default_deduction_type,default_break_policy,default_break_minutes")
                .eq("id", value: storeId.uuidString)
                .single()
                .execute()
                .value
            let (terms, storeDefaults) = try await (termsTask, defaultsTask)
            defaults = storeDefaults
            isLegacy = false
            wageChoice = terms.hourly_wage_override == nil ? Self.storeChoice : "custom"
            wageInput = String(Int(terms.hourly_wage_override ?? terms.hourly_wage ?? AppConfig.defaultHourlyWage))
            breakChoice = terms.break_policy_override ?? Self.storeChoice
            breakMinutesInput = terms.break_minutes_override.map(String.init) ?? ""
            weeklyChoice = terms.apply_weekly_allowance_override.map { $0 ? "on" : "off" } ?? Self.storeChoice
            nightChoice = terms.apply_night_allowance_override.map { $0 ? "on" : "off" } ?? Self.storeChoice
            deductionChoice = terms.deduction_type_override ?? Self.storeChoice
            payday = min(max(terms.payday ?? PayrollLocalSettings.defaultPayday, 1), 31)
            snapshotTerms = await fetchSnapshotTerms()
        } catch {
            guard !AppErrorMessage.isCancellation(error) else { return }
            await loadLegacy()
        }
        #endif
    }

    @MainActor
    private func loadMemo() async {
        #if canImport(Supabase)
        struct NoteRow: Decodable { let body: String }
        let rows: [NoteRow] = (try? await SupabaseManager.shared.client
            .from("worker_notes")
            .select("body")
            .eq("worker_id", value: workerId.uuidString)
            .limit(1)
            .execute()
            .value) ?? []
        memo = rows.first?.body ?? ""
        savedMemo = memo
        #endif
    }

    // 매장 기본값 컬럼이 아직 없을 때: 직원 값만 다룬다.
    @MainActor
    private func loadLegacy() async {
        #if canImport(Supabase)
        do {
            let terms: LegacyWorkerTerms = try await SupabaseManager.shared.client
                .from("workers")
                .select("hourly_wage,apply_weekly_allowance,apply_night_allowance,deduction_type,payday")
                .eq("id", value: workerId.uuidString)
                .single()
                .execute()
                .value
            isLegacy = true
            defaults = nil
            wageChoice = "custom"
            let wage = terms.hourly_wage ?? 0
            wageInput = String(Int(wage > 0 ? wage : AppConfig.defaultHourlyWage))
            weeklyChoice = (terms.apply_weekly_allowance ?? false) ? "on" : "off"
            nightChoice = (terms.apply_night_allowance ?? false) ? "on" : "off"
            deductionChoice = terms.deduction_type ?? PayrollDeductionType.withholding.rawValue
            payday = min(max(terms.payday ?? PayrollLocalSettings.defaultPayday, 1), 31)
        } catch {
            errorMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func save() async {
        #if canImport(Supabase)
        let wage = Double(wageInput.filter(\.isNumber))
        if wageChoice != Self.storeChoice, (wage ?? 0) <= 0 {
            errorMessage = "시급을 입력해주세요."
            return
        }
        if wageChoice != Self.storeChoice, AppConfig.isBelowMinimumWage(wageInput) {
            errorMessage = "최저시급(\(Int(AppConfig.minimumHourlyWage).formatted())원) 아래로는 저장할 수 없어요."
            return
        }
        isSaving = true
        errorMessage = nil
        savedMessage = nil
        defer { isSaving = false }

        func flag(_ choice: String) -> Bool? {
            choice == Self.storeChoice ? nil : choice == "on"
        }
        func value(_ choice: String) -> String? {
            choice == Self.storeChoice ? nil : choice
        }

        do {
            let query = SupabaseManager.shared.client.from("workers")
            if isLegacy {
                try await query
                    .update(LegacyUpdate(
                        hourly_wage: wage ?? AppConfig.defaultHourlyWage,
                        apply_weekly_allowance: weeklyChoice == "on",
                        apply_night_allowance: nightChoice == "on",
                        deduction_type: deductionChoice,
                        payday: payday
                    ))
                    .eq("id", value: workerId.uuidString)
                    .execute()
            } else {
                let breakPolicy = value(breakChoice)
                try await query
                    .update(OverrideUpdate(
                        hourly_wage_override: wageChoice == Self.storeChoice ? nil : wage,
                        apply_weekly_allowance_override: flag(weeklyChoice),
                        apply_night_allowance_override: flag(nightChoice),
                        deduction_type_override: value(deductionChoice),
                        break_policy_override: breakPolicy,
                        break_minutes_override: breakPolicy == PayrollBreakPolicy.custom.rawValue
                            ? min(240, Int(breakMinutesInput.filter(\.isNumber)) ?? 0)
                            : nil,
                        payday: payday
                    ))
                    .eq("id", value: workerId.uuidString)
                    .execute()
            }
            let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedMemo != savedMemo {
                struct NoteUpsert: Encodable {
                    let worker_id: UUID
                    let store_id: UUID
                    let body: String
                    let updated_at: String
                }
                try await SupabaseManager.shared.client
                    .from("worker_notes")
                    .upsert(NoteUpsert(
                        worker_id: workerId,
                        store_id: storeId,
                        body: trimmedMemo,
                        updated_at: AppTime.isoString(from: Date())
                    ))
                    .execute()
                savedMemo = trimmedMemo
            }
            Haptics.success()
            savedMessage = "저장했어요"
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
            let newTerms = await fetchSnapshotTerms()
            if !isLegacy, let before = snapshotTerms, let newTerms, before != newTerms {
                isAskingReapply = true
            }
            snapshotTerms = newTerms ?? snapshotTerms
            await onSaved()
        } catch {
            errorMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private struct SnapshotTerms: Decodable, Equatable {
        let hourly_wage: Double?
        let apply_night_allowance: Bool?
        let apply_weekly_allowance: Bool?
        let break_policy: String?
        let break_minutes: Int?
    }

    private func fetchSnapshotTerms() async -> SnapshotTerms? {
        #if canImport(Supabase)
        return try? await SupabaseManager.shared.client
            .from("workers")
            .select("hourly_wage,apply_night_allowance,apply_weekly_allowance,break_policy,break_minutes")
            .eq("id", value: workerId.uuidString)
            .single()
            .execute()
            .value
        #else
        return nil
        #endif
    }

    @MainActor
    private func reapplyThisMonth() async {
        #if canImport(Supabase)
        isSaving = true
        defer { isSaving = false }
        do {
            try await SupabaseManager.shared.reapplyPayrollTermsThisMonth(storeId: storeId, workerId: workerId)
            Haptics.success()
            savedMessage = "이번 달 근무에도 적용했어요"
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
            await onSaved()
        } catch {
            errorMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                settingsCard
                if !isLegacy {
                    Text("‘매장 기본’은 설정 탭의 매장 기본값을 따라가요.")
                        .font(.app(.caption))
                        .foregroundColor(.appTextSecondary)
                        .padding(.horizontal, 4)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.app(.caption, .medium))
                        .foregroundColor(.appWarning)
                }
                Button(isSaving ? "저장 중..." : (savedMessage ?? "저장")) {
                    Task { await save() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
            }
        }
        .task {
            await load()
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("시급") {
                ChoiceChips(options: choices([("custom", "직접")]), selected: wageChoice) { wageChoice = $0 }
            }
            if wageChoice == Self.storeChoice, let wage = defaults?.default_hourly_wage {
                detailLine("\(Int(wage).formatted())원")
            } else {
                HStack(spacing: 6) {
                    Spacer()
                    TextField("10320", text: $wageInput)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.app(.body, .bold))
                        .frame(width: 110)
                    Text("원")
                        .font(.app(.callout))
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.bottom, 10)
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
                } else if breakChoice == Self.storeChoice {
                    detailLine(storeBreakText)
                }
                divider
            }

            row("주휴수당") {
                ChoiceChips(options: choices([("on", "지급"), ("off", "미지급")]), selected: weeklyChoice) { weeklyChoice = $0 }
            }
            if weeklyChoice == Self.storeChoice {
                detailLine(onOffText(defaults?.default_apply_weekly_allowance))
            }
            divider

            row("야간수당") {
                ChoiceChips(options: choices([("on", "지급"), ("off", "미지급")]), selected: nightChoice) { nightChoice = $0 }
            }
            if nightChoice == Self.storeChoice {
                detailLine(onOffText(defaults?.default_apply_night_allowance))
            }
            divider

            row("공제") {
                ChoiceChips(
                    options: choices(PayrollDeductionType.allCases.map { ($0.rawValue, shortDeductionTitle($0)) }),
                    selected: deductionChoice
                ) { deductionChoice = $0 }
            }
            if deductionChoice == Self.storeChoice {
                detailLine(defaults?.default_deduction_type.flatMap(PayrollDeductionType.init(rawValue:)).map(shortDeductionTitle) ?? "3.3%")
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

    // 매장 기본을 고른 항목 아래에 실제로 적용되는 값을 작게 보여준다.
    private func detailLine(_ text: String) -> some View {
        Text("매장 기본 · \(text)")
            .font(.app(.caption))
            .foregroundColor(.appTextSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.bottom, 10)
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

    private func onOffText(_ value: Bool?) -> String {
        (value ?? false) ? "지급" : "미지급"
    }

    private var storeBreakText: String {
        let policy = PayrollBreakPolicy(rawOrNone: defaults?.default_break_policy)
        if policy == .custom, let minutes = defaults?.default_break_minutes {
            return "근무마다 \(minutes)분"
        }
        return policy.title
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        let client = SupabaseManager.shared.client
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
        } catch {
            guard !AppErrorMessage.isCancellation(error) else { return }
            await loadLegacy()
        }
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
            Haptics.success()
            savedMessage = "저장했어요"
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
            await onSaved()
        } catch {
            errorMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }
}

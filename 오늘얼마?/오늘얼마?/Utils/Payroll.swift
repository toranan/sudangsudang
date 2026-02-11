import Foundation

// Shared payroll math used by both Owner and Worker UIs.
// Notes:
// - "4대보험(예상)" uses employee-share estimates (see docs/korea_four_insurance_rates_2026_02.md).
// - We do not store "net pay" in DB; we store only the settings and compute on-device.

enum PayrollDeductionType: String, CaseIterable, Identifiable, Codable {
    case withholding = "withholding_3_3"
    case fourInsurance = "four_insurance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .withholding: return "원천징수(3.3%)"
        case .fourInsurance: return "4대보험(예상)"
        }
    }
}

struct PayrollDeductionLineItem: Identifiable {
    let id: String
    let title: String
    let rate: Double
    let amount: Double

    init(title: String, rate: Double, amount: Double) {
        self.id = title
        self.title = title
        self.rate = rate
        self.amount = amount
    }
}

struct PayrollDeductionBreakdown {
    let items: [PayrollDeductionLineItem]

    var totalRate: Double { items.reduce(0) { $0 + $1.rate } }
    var totalDeduction: Double { items.reduce(0) { $0 + $1.amount } }
}

enum PayrollCalculator {
    // 2026-02 기준 (근로자 부담분, "예상" 계산용)
    // 국민연금 4.75%, 건강보험 3.595%, 장기요양 0.4724% (= 0.9448% * 50%), 고용보험(실업급여) 0.9%
    static let pensionEmployeeRate: Double = 0.0475
    static let healthEmployeeRate: Double = 0.03595
    static let longTermCareEmployeeRate: Double = 0.009448 / 2.0
    static let employmentEmployeeRate: Double = 0.009

    static func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        let end = checkOut ?? Date()
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }

    static func deductionBreakdown(gross: Double, type: PayrollDeductionType) -> PayrollDeductionBreakdown {
        let base = max(0, gross)
        switch type {
        case .withholding:
            let rate = 0.033
            return PayrollDeductionBreakdown(items: [
                PayrollDeductionLineItem(title: "원천징수(3.3%)", rate: rate, amount: base * rate),
            ])
        case .fourInsurance:
            return PayrollDeductionBreakdown(items: [
                PayrollDeductionLineItem(title: "국민연금(근로자)", rate: pensionEmployeeRate, amount: base * pensionEmployeeRate),
                PayrollDeductionLineItem(title: "건강보험(근로자)", rate: healthEmployeeRate, amount: base * healthEmployeeRate),
                PayrollDeductionLineItem(title: "장기요양(근로자)", rate: longTermCareEmployeeRate, amount: base * longTermCareEmployeeRate),
                PayrollDeductionLineItem(title: "고용보험(근로자)", rate: employmentEmployeeRate, amount: base * employmentEmployeeRate),
            ])
        }
    }

    static func estimateWeeklyAllowancePay(checkInOut: [(String, String?)], wage: Double) -> Double {
        // Estimate weekly allowance based on logs in a single month.
        // Rule-of-thumb: if weekly working time >= 15h, add (weeklyHours/40)*8 hours.
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ko_KR")
        cal.firstWeekday = 2 // Monday

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        var minutesByWeek: [String: Int] = [:]
        for (checkInAt, checkOutAt) in checkInOut {
            let start = parser.date(from: checkInAt) ?? iso.date(from: checkInAt) ?? Date()
            let end = checkOutAt.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? start
            let minutes = max(0, Int(floor(end.timeIntervalSince(start) / 60.0)))

            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)
            let key = "\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
            minutesByWeek[key, default: 0] += minutes
        }

        var total: Double = 0
        for (_, weekMinutes) in minutesByWeek {
            if weekMinutes < 15 * 60 { continue }
            let weekHours = Double(weekMinutes) / 60.0
            let allowanceHours = (weekHours / 40.0) * 8.0
            total += allowanceHours * wage
        }
        return total
    }
}

struct PayrollLocalSettings: Codable {
    var applyWeeklyAllowance: Bool
    var deductionType: PayrollDeductionType
}

enum PayrollLocalSettingsStore {
    private static func key(workerId: UUID) -> String {
        "payroll_local_settings_v1_worker_\(workerId.uuidString)"
    }

    static func load(workerId: UUID) -> PayrollLocalSettings? {
        guard let data = UserDefaults.standard.data(forKey: key(workerId: workerId)) else { return nil }
        return try? JSONDecoder().decode(PayrollLocalSettings.self, from: data)
    }

    static func save(workerId: UUID, settings: PayrollLocalSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key(workerId: workerId))
    }
}

import Foundation

// Shared payroll math used by both Owner and Worker UIs.
// Notes:
// - "4대보험(예상)" uses employee-share estimates (see docs/korea_four_insurance_rates_2026_02.md).
// - "환급금 계산(예상)" uses simplified income-tax rules (see docs/korea_refund_tax_reference_2026_02.md).
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

struct PayrollRefundEstimate {
    let annualGross: Double
    let annualWithholding: Double
    let estimatedSettlementTax: Double
    let expectedRefund: Double
    let note: String
}

enum PayrollCalculator {
    // 2026-02 기준 (근로자 부담분, "예상" 계산용)
    // 국민연금 4.75%, 건강보험 3.595%, 장기요양 0.4724% (= 0.9448% * 50%), 고용보험(실업급여) 0.9%
    static let pensionEmployeeRate: Double = 0.0475
    static let healthEmployeeRate: Double = 0.03595
    static let longTermCareEmployeeRate: Double = 0.009448 / 2.0
    static let employmentEmployeeRate: Double = 0.009
    static let nightPremiumRate: Double = 0.5

    static func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let end = checkOut else { return 0 }
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }

    static func calcNightMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let end = checkOut, end > checkIn else { return 0 }

        let calendar = AppTime.calendar
        var dayCursor = calendar.startOfDay(for: checkIn)
        var total: Double = 0

        while dayCursor < end {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayCursor),
                  let sixAM = calendar.date(byAdding: .hour, value: 6, to: dayCursor),
                  let tenPM = calendar.date(byAdding: .hour, value: 22, to: dayCursor) else {
                break
            }

            total += overlapSeconds(startA: checkIn, endA: end, startB: dayCursor, endB: sixAM)
            total += overlapSeconds(startA: checkIn, endA: end, startB: tenPM, endB: dayEnd)
            dayCursor = dayEnd
        }

        return max(0, Int(floor(total / 60.0)))
    }

    private static func overlapSeconds(startA: Date, endA: Date, startB: Date, endB: Date) -> Double {
        let start = max(startA, startB)
        let end = min(endA, endB)
        return max(0, end.timeIntervalSince(start))
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
        cal.timeZone = AppTime.timeZone
        cal.firstWeekday = 2 // Monday

        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso

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

    static func estimateAnnualRefund(monthlyTaxablePay: Double, deductionType: PayrollDeductionType) -> PayrollRefundEstimate {
        let annualGross = max(0, monthlyTaxablePay) * 12.0

        // Refund estimate is meaningful when withholding(3.3%) was used.
        guard deductionType == .withholding else {
            return PayrollRefundEstimate(
                annualGross: annualGross,
                annualWithholding: 0,
                estimatedSettlementTax: 0,
                expectedRefund: 0,
                note: "원천징수(3.3%) 기준에서만 환급을 추정해요."
            )
        }

        let annualWithholding = annualGross * 0.033
        let earnedIncomeDeduction = estimatedEarnedIncomeDeduction(annualGross: annualGross)
        let earnedIncomeAmount = max(0, annualGross - earnedIncomeDeduction)
        let taxBase = max(0, earnedIncomeAmount - 1_500_000) // 기본공제(본인)

        let calculatedIncomeTax = progressiveIncomeTax(taxBase: taxBase)
        let taxCredit = earnedIncomeTaxCredit(calculatedIncomeTax: calculatedIncomeTax, annualGross: annualGross)
        let incomeTaxAfterCredit = max(0, calculatedIncomeTax - taxCredit)
        let localIncomeTax = incomeTaxAfterCredit * 0.1
        let estimatedSettlementTax = incomeTaxAfterCredit + localIncomeTax

        return PayrollRefundEstimate(
            annualGross: annualGross,
            annualWithholding: annualWithholding,
            estimatedSettlementTax: estimatedSettlementTax,
            expectedRefund: max(0, annualWithholding - estimatedSettlementTax),
            note: "2026년 2월 세법 기준 단순 추정치예요(본인 기본공제만 반영, 부양가족/특별공제 미반영)."
        )
    }

    private static func estimatedEarnedIncomeDeduction(annualGross: Double) -> Double {
        let gross = max(0, annualGross)
        if gross <= 5_000_000 {
            return gross * 0.7
        }
        if gross <= 15_000_000 {
            return 3_500_000 + (gross - 5_000_000) * 0.4
        }
        if gross <= 45_000_000 {
            return 7_500_000 + (gross - 15_000_000) * 0.15
        }
        if gross <= 100_000_000 {
            return 12_000_000 + (gross - 45_000_000) * 0.05
        }
        return 14_750_000 + (gross - 100_000_000) * 0.02
    }

    private static func progressiveIncomeTax(taxBase: Double) -> Double {
        let base = max(0, taxBase)
        if base <= 14_000_000 {
            return base * 0.06
        }
        if base <= 50_000_000 {
            return 840_000 + (base - 14_000_000) * 0.15
        }
        if base <= 88_000_000 {
            return 6_240_000 + (base - 50_000_000) * 0.24
        }
        if base <= 150_000_000 {
            return 15_360_000 + (base - 88_000_000) * 0.35
        }
        if base <= 300_000_000 {
            return 37_060_000 + (base - 150_000_000) * 0.38
        }
        if base <= 500_000_000 {
            return 94_060_000 + (base - 300_000_000) * 0.40
        }
        if base <= 1_000_000_000 {
            return 174_060_000 + (base - 500_000_000) * 0.42
        }
        return 384_060_000 + (base - 1_000_000_000) * 0.45
    }

    private static func earnedIncomeTaxCredit(calculatedIncomeTax: Double, annualGross: Double) -> Double {
        let incomeTax = max(0, calculatedIncomeTax)
        let baseCredit: Double
        if incomeTax <= 1_300_000 {
            baseCredit = incomeTax * 0.55
        } else {
            baseCredit = 715_000 + (incomeTax - 1_300_000) * 0.30
        }

        return min(baseCredit, earnedIncomeTaxCreditCap(annualGross: annualGross))
    }

    private static func earnedIncomeTaxCreditCap(annualGross: Double) -> Double {
        let gross = max(0, annualGross)
        if gross <= 33_000_000 {
            return 740_000
        }
        if gross <= 70_000_000 {
            return max(660_000, 740_000 - (gross - 33_000_000) * 0.008)
        }
        if gross <= 120_000_000 {
            return max(500_000, 660_000 - (gross - 70_000_000) * 0.5)
        }
        return max(200_000, 500_000 - (gross - 120_000_000) * 0.5)
    }
}

struct PayrollLocalSettings: Codable {
    var applyWeeklyAllowance: Bool
    var deductionType: PayrollDeductionType
    var applyNightAllowance: Bool
    var payday: Int

    static let defaultPayday = 10

    init(
        applyWeeklyAllowance: Bool,
        deductionType: PayrollDeductionType,
        applyNightAllowance: Bool = false,
        payday: Int = PayrollLocalSettings.defaultPayday
    ) {
        self.applyWeeklyAllowance = applyWeeklyAllowance
        self.deductionType = deductionType
        self.applyNightAllowance = applyNightAllowance
        self.payday = payday
    }

    enum CodingKeys: String, CodingKey {
        case applyWeeklyAllowance
        case deductionType
        case applyNightAllowance
        case payday
        // Backward-compatibility for previously persisted local settings.
        case settlementDay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applyWeeklyAllowance = try container.decodeIfPresent(Bool.self, forKey: .applyWeeklyAllowance) ?? false
        deductionType = try container.decodeIfPresent(PayrollDeductionType.self, forKey: .deductionType) ?? .withholding
        applyNightAllowance = try container.decodeIfPresent(Bool.self, forKey: .applyNightAllowance) ?? false
        payday =
            try container.decodeIfPresent(Int.self, forKey: .payday)
            ?? container.decodeIfPresent(Int.self, forKey: .settlementDay)
            ?? PayrollLocalSettings.defaultPayday
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(applyWeeklyAllowance, forKey: .applyWeeklyAllowance)
        try container.encode(deductionType, forKey: .deductionType)
        try container.encode(applyNightAllowance, forKey: .applyNightAllowance)
        try container.encode(payday, forKey: .payday)
        // Keep writing old key too so older app builds can still read this local setting.
        try container.encode(payday, forKey: .settlementDay)
    }
}

enum PayrollPayday {
    static func normalizedDay(_ day: Int, referenceMonth: Date = Date(), calendar: Calendar = AppTime.calendar) -> Int {
        let range = calendar.range(of: .day, in: .month, for: referenceMonth) ?? 1..<32
        let minDay = range.lowerBound
        let maxDay = range.upperBound - 1
        // Legacy value 0 means month end.
        if day <= 0 { return maxDay }
        return min(max(day, minDay), maxDay)
    }

    static func nextPaydayDate(
        from now: Date = Date(),
        payday: Int,
        calendar: Calendar = AppTime.calendar
    ) -> Date {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let dayThisMonth = normalizedDay(payday, referenceMonth: monthStart, calendar: calendar)
        let thisMonthDate = targetDate(monthStart: monthStart, day: dayThisMonth, calendar: calendar) ?? monthStart
        if thisMonthDate >= calendar.startOfDay(for: now) {
            return thisMonthDate
        }

        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let dayNextMonth = normalizedDay(payday, referenceMonth: nextMonthStart, calendar: calendar)
        return targetDate(monthStart: nextMonthStart, day: dayNextMonth, calendar: calendar) ?? nextMonthStart
    }

    private static func targetDate(monthStart: Date, day: Int, calendar: Calendar) -> Date? {
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart)
    }
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

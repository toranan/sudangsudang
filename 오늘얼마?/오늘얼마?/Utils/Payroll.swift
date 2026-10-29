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

// 무급 휴게 방식. DB의 break_policy / applied_break_policy 값과 같다.
enum PayrollBreakPolicy: String, CaseIterable, Identifiable, Codable {
    case none
    case statutory
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "없음"
        case .statutory: return "법정 기준"
        case .custom: return "직접 입력"
        }
    }

    init(rawOrNone raw: String?) {
        self = raw.flatMap(PayrollBreakPolicy.init(rawValue:)) ?? .none
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

    // 법정 최소 휴게(근로기준법 54조: 4시간 30분, 8시간 1시간)를 체류시간으로 환산한다.
    // 체류 4시간 이상이면 휴게 없이는 실근로가 4시간 이상이 되므로 30분,
    // 체류 8시간 30분 이상이면 30분만 쉬어도 실근로가 8시간 이상이 되므로 60분.
    static func statutoryBreakMinutes(stayMinutes: Int) -> Int {
        if stayMinutes >= 8 * 60 + 30 { return 60 }
        if stayMinutes >= 4 * 60 { return 30 }
        return 0
    }

    static func breakMinutes(stayMinutes: Int, policy: PayrollBreakPolicy, customMinutes: Int) -> Int {
        let stay = max(0, stayMinutes)
        switch policy {
        case .none: return 0
        case .statutory: return min(stay, statutoryBreakMinutes(stayMinutes: stay))
        case .custom: return min(stay, max(0, customMinutes))
        }
    }

    // 휴게를 법정 최소보다 적게 주는 설정인지. 사장님 안내 문구에만 쓴다.
    static func isBreakBelowStatutory(stayMinutes: Int, policy: PayrollBreakPolicy, customMinutes: Int) -> Bool {
        breakMinutes(stayMinutes: stayMinutes, policy: policy, customMinutes: customMinutes)
            < statutoryBreakMinutes(stayMinutes: stayMinutes)
    }

    static func calcPaidMinutes(
        checkIn: Date,
        checkOut: Date?,
        breakPolicy: PayrollBreakPolicy,
        customBreakMinutes: Int
    ) -> Int {
        let stay = calcMinutes(checkIn: checkIn, checkOut: checkOut)
        return stay - breakMinutes(stayMinutes: stay, policy: breakPolicy, customMinutes: customBreakMinutes)
    }

    static func grossPay(
        checkIn: Date,
        checkOut: Date?,
        wage: Double,
        applyNightAllowance: Bool,
        breakPolicy: PayrollBreakPolicy = .none,
        customBreakMinutes: Int = 0
    ) -> Double {
        let paidMinutes = calcPaidMinutes(
            checkIn: checkIn,
            checkOut: checkOut,
            breakPolicy: breakPolicy,
            customBreakMinutes: customBreakMinutes
        )
        let basePay = Double(paidMinutes) / 60.0 * wage
        guard applyNightAllowance else { return basePay }

        // 휴게 시각은 기록하지 않으므로 주간에 쉰 것으로 보고, 야간 가산은 유급 시간을 넘지 않게 한다.
        let nightMinutes = min(paidMinutes, calcNightMinutes(checkIn: checkIn, checkOut: checkOut))
        let nightPremium = Double(nightMinutes) / 60.0 * wage * nightPremiumRate
        return basePay + nightPremium
    }

    static func grossPay(
        checkIn: Date,
        checkOut: Date?,
        appliedHourlyWage: Double?,
        appliedNightAllowance: Bool?,
        fallbackHourlyWage: Double,
        fallbackNightAllowance: Bool,
        appliedBreakPolicy: String? = nil,
        appliedBreakMinutes: Int? = nil
    ) -> Double {
        grossPay(
            checkIn: checkIn,
            checkOut: checkOut,
            wage: appliedHourlyWage ?? fallbackHourlyWage,
            applyNightAllowance: appliedNightAllowance ?? fallbackNightAllowance,
            breakPolicy: PayrollBreakPolicy(rawOrNone: appliedBreakPolicy),
            customBreakMinutes: appliedBreakMinutes ?? 0
        )
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

    static func weeklyAllowanceLogRange(forMonth month: Date) -> DateInterval {
        let cal = weeklyCalendar()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let firstWeekStart = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        let lastMomentOfMonth = monthEnd.addingTimeInterval(-1)
        let lastWeekEnd = cal.dateInterval(of: .weekOfYear, for: lastMomentOfMonth)?.end ?? monthEnd
        return DateInterval(start: firstWeekStart, end: lastWeekEnd)
    }

    static func estimateWeeklyAllowancePay(
        checkInOut: [(String, String?)],
        wage: Double,
        attributedToMonth month: Date? = nil
    ) -> Double {
        // Monday-Sunday estimate. A week is attributed to the month containing Sunday,
        // so a week crossing a month boundary is neither omitted nor counted twice.
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ko_KR")
        cal.timeZone = AppTime.timeZone
        cal.firstWeekday = 2 // Monday

        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso

        var minutesByWeek: [Date: Int] = [:]
        for (checkInAt, checkOutAt) in checkInOut {
            guard let start = parser.date(from: checkInAt) ?? iso.date(from: checkInAt),
                  let end = checkOutAt.flatMap({ parser.date(from: $0) ?? iso.date(from: $0) }),
                  end > start,
                  let weekStart = cal.dateInterval(of: .weekOfYear, for: start)?.start else {
                continue
            }
            let minutes = max(0, Int(floor(end.timeIntervalSince(start) / 60.0)))
            minutesByWeek[weekStart, default: 0] += minutes
        }

        var total: Double = 0
        for (weekStart, weekMinutes) in minutesByWeek {
            if let month {
                guard let weeklyHoliday = cal.date(byAdding: .day, value: 6, to: weekStart),
                      cal.isDate(weeklyHoliday, equalTo: month, toGranularity: .month) else {
                    continue
                }
            }
            if weekMinutes < 15 * 60 { continue }
            let weekHours = Double(weekMinutes) / 60.0
            let allowanceHours = min(8.0, (weekHours / 40.0) * 8.0)
            total += allowanceHours * wage
        }
        return total
    }

    private static func weeklyCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ko_KR")
        cal.timeZone = AppTime.timeZone
        cal.firstWeekday = 2 // Monday
        return cal
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

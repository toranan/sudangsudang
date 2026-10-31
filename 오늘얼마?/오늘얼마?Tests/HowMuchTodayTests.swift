import XCTest
@testable import HowMuchToday

final class HowMuchTodayTests: XCTestCase {
    func testLatestRequestRejectsOlderRequest() {
        var requests = LatestRequest()
        let older = requests.begin()
        let latest = requests.begin()

        XCTAssertFalse(requests.isCurrent(older))
        XCTAssertTrue(requests.isCurrent(latest))
    }

    func testLatestRequestCanBeInvalidated() {
        var requests = LatestRequest()
        let request = requests.begin()

        requests.invalidate()

        XCTAssertFalse(requests.isCurrent(request))
    }

    func testNightPayAcrossMidnight() throws {
        let start = try makeDate("2026-07-15T22:00:00+09:00")
        let end = try makeDate("2026-07-16T06:00:00+09:00")

        let pay = PayrollCalculator.grossPay(
            checkIn: start,
            checkOut: end,
            wage: 10_320,
            applyNightAllowance: true
        )

        XCTAssertEqual(PayrollCalculator.calcNightMinutes(checkIn: start, checkOut: end), 480)
        XCTAssertEqual(pay, 123_840, accuracy: 0.001)
    }

    func testAppliedTermsTakePriorityOverCurrentWorkerSettings() throws {
        let start = try makeDate("2026-07-15T09:00:00+09:00")
        let end = try makeDate("2026-07-15T17:00:00+09:00")

        let pay = PayrollCalculator.grossPay(
            checkIn: start,
            checkOut: end,
            appliedHourlyWage: 10_320,
            appliedNightAllowance: false,
            fallbackHourlyWage: 11_000,
            fallbackNightAllowance: true
        )

        XCTAssertEqual(pay, 82_560, accuracy: 0.001)
    }

    func testCurrentSettingsAreFallbackForLegacyRows() throws {
        let start = try makeDate("2026-07-15T22:00:00+09:00")
        let end = try makeDate("2026-07-15T23:00:00+09:00")

        let pay = PayrollCalculator.grossPay(
            checkIn: start,
            checkOut: end,
            appliedHourlyWage: nil,
            appliedNightAllowance: nil,
            fallbackHourlyWage: 11_000,
            fallbackNightAllowance: true
        )

        XCTAssertEqual(pay, 16_500, accuracy: 0.001)
    }

    // 체류 4시간씩 4일(16시간)이어도 법정 휴게 30분씩을 빼면 14시간이라 주휴수당이 없다.
    func testWeeklyAllowanceUsesHoursAfterBreak() throws {
        let days = ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08"]
        let withoutBreak: [(String, String?, String?, Int?)] = days.map {
            ("\($0)T09:00:00+09:00", "\($0)T13:00:00+09:00", nil, nil)
        }
        let withBreak: [(String, String?, String?, Int?)] = days.map {
            ("\($0)T09:00:00+09:00", "\($0)T13:00:00+09:00", "statutory", nil)
        }

        XCTAssertEqual(PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: withoutBreak, wage: 10_000), 32_000, accuracy: 0.001)
        XCTAssertEqual(PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: withBreak, wage: 10_000), 0, accuracy: 0.001)
    }

    private struct SnapshotLog: WeeklyAllowanceLogFields {
        let check_in_at: String
        let check_out_at: String?
        let applied_hourly_wage: Double?
        let applied_break_policy: String? = nil
        let applied_break_minutes: Int? = nil
        let applied_weekly_allowance: Bool?
    }

    // 주휴 설정을 끄거나 시급을 올려도, 지난 주는 그 주 근무에 남은 설정으로 계산한다.
    func testWeeklyAllowanceUsesSnapshotOfEachWeek() throws {
        // 9월 첫째 주: 주휴 켜짐·시급 10,000원으로 5시간씩 4일(20시간)
        let pastWeek = ["2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10"].map {
            SnapshotLog(check_in_at: "\($0)T09:00:00+09:00", check_out_at: "\($0)T14:00:00+09:00", applied_hourly_wage: 10_000, applied_weekly_allowance: true)
        }
        // 지금 설정은 주휴 꺼짐·시급 12,000원
        XCTAssertEqual(
            PayrollCalculator.estimateWeeklyAllowancePay(logs: pastWeek, fallbackWage: 12_000, fallbackApply: false),
            40_000,
            accuracy: 0.001
        )
        // 스냅샷이 없는 옛 기록은 지금 설정을 쓴다.
        let legacy = pastWeek.map {
            SnapshotLog(check_in_at: $0.check_in_at, check_out_at: $0.check_out_at, applied_hourly_wage: nil, applied_weekly_allowance: nil)
        }
        XCTAssertEqual(
            PayrollCalculator.estimateWeeklyAllowancePay(logs: legacy, fallbackWage: 12_000, fallbackApply: true),
            48_000,
            accuracy: 0.001
        )
        // 주 중간에 바꾸면 그 주 마지막 근무의 설정을 쓴다.
        var changed = pastWeek
        changed[3] = SnapshotLog(check_in_at: changed[3].check_in_at, check_out_at: changed[3].check_out_at, applied_hourly_wage: 12_000, applied_weekly_allowance: false)
        XCTAssertEqual(
            PayrollCalculator.estimateWeeklyAllowancePay(logs: changed, fallbackWage: 12_000, fallbackApply: true),
            0,
            accuracy: 0.001
        )
    }

    func testWeeklyAllowanceCrossingMonthBelongsToSundayMonth() throws {
        let logs: [(String, String?, String?, Int?)] = [
            ("2026-09-28T09:00:00+09:00", "2026-09-28T12:00:00+09:00", nil, nil),
            ("2026-09-29T09:00:00+09:00", "2026-09-29T12:00:00+09:00", nil, nil),
            ("2026-09-30T09:00:00+09:00", "2026-09-30T12:00:00+09:00", nil, nil),
            ("2026-10-01T09:00:00+09:00", "2026-10-01T12:00:00+09:00", nil, nil),
            ("2026-10-02T09:00:00+09:00", "2026-10-02T12:00:00+09:00", nil, nil),
        ]
        let september = try makeDate("2026-09-01T00:00:00+09:00")
        let october = try makeDate("2026-10-01T00:00:00+09:00")

        XCTAssertEqual(
            PayrollCalculator.estimateWeeklyAllowancePay(
                checkInOut: logs,
                wage: 10_000,
                attributedToMonth: september
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PayrollCalculator.estimateWeeklyAllowancePay(
                checkInOut: logs,
                wage: 10_000,
                attributedToMonth: october
            ),
            30_000,
            accuracy: 0.001
        )
    }

    func testWeeklyAllowanceLogRangeIncludesWholeBoundaryWeeks() throws {
        let october = try makeDate("2026-10-15T00:00:00+09:00")
        let range = PayrollCalculator.weeklyAllowanceLogRange(forMonth: october)

        XCTAssertEqual(range.start, try makeDate("2026-09-28T00:00:00+09:00"))
        XCTAssertEqual(range.end, try makeDate("2026-11-02T00:00:00+09:00"))
    }

    func testStatutoryBreakThresholdsUseStayTime() {
        XCTAssertEqual(PayrollCalculator.statutoryBreakMinutes(stayMinutes: 239), 0)
        XCTAssertEqual(PayrollCalculator.statutoryBreakMinutes(stayMinutes: 240), 30)
        XCTAssertEqual(PayrollCalculator.statutoryBreakMinutes(stayMinutes: 509), 30)
        XCTAssertEqual(PayrollCalculator.statutoryBreakMinutes(stayMinutes: 510), 60)
    }

    func testNoBreakPolicyPaysWholeStay() throws {
        let checkIn = try makeDate("2026-10-05T09:00:00+09:00")
        let checkOut = try makeDate("2026-10-05T15:00:00+09:00")

        let pay = PayrollCalculator.grossPay(
            checkIn: checkIn,
            checkOut: checkOut,
            wage: 10_000,
            applyNightAllowance: false,
            breakPolicy: .none
        )

        XCTAssertEqual(pay, 60_000, accuracy: 0.001)
    }

    func testStatutoryBreakIsUnpaid() throws {
        let checkIn = try makeDate("2026-10-05T09:00:00+09:00")
        let checkOut = try makeDate("2026-10-05T18:00:00+09:00")

        let pay = PayrollCalculator.grossPay(
            checkIn: checkIn,
            checkOut: checkOut,
            wage: 10_000,
            applyNightAllowance: false,
            breakPolicy: .statutory
        )

        XCTAssertEqual(pay, 80_000, accuracy: 0.001)
    }

    func testCustomBreakNeverExceedsStay() throws {
        let checkIn = try makeDate("2026-10-05T09:00:00+09:00")
        let checkOut = try makeDate("2026-10-05T09:20:00+09:00")

        let paid = PayrollCalculator.calcPaidMinutes(
            checkIn: checkIn,
            checkOut: checkOut,
            breakPolicy: .custom,
            customBreakMinutes: 30
        )

        XCTAssertEqual(paid, 0)
    }

    func testNightPremiumIsCappedByPaidMinutes() throws {
        let checkIn = try makeDate("2026-10-05T22:00:00+09:00")
        let checkOut = try makeDate("2026-10-06T02:30:00+09:00")

        let pay = PayrollCalculator.grossPay(
            checkIn: checkIn,
            checkOut: checkOut,
            wage: 10_000,
            applyNightAllowance: true,
            breakPolicy: .statutory
        )

        // 270분 체류 - 30분 휴게 = 240분 유급, 야간 가산도 240분까지만.
        XCTAssertEqual(pay, 40_000 + 20_000, accuracy: 0.001)
    }

    func testBreakBelowStatutoryIsFlagged() {
        XCTAssertTrue(PayrollCalculator.isBreakBelowStatutory(stayMinutes: 300, policy: .none, customMinutes: 0))
        XCTAssertTrue(PayrollCalculator.isBreakBelowStatutory(stayMinutes: 540, policy: .custom, customMinutes: 30))
        XCTAssertFalse(PayrollCalculator.isBreakBelowStatutory(stayMinutes: 540, policy: .statutory, customMinutes: 0))
        XCTAssertFalse(PayrollCalculator.isBreakBelowStatutory(stayMinutes: 180, policy: .none, customMinutes: 0))
    }

    func testAppliedBreakSnapshotIsUsed() throws {
        let checkIn = try makeDate("2026-10-05T09:00:00+09:00")
        let checkOut = try makeDate("2026-10-05T14:00:00+09:00")

        let pay = PayrollCalculator.grossPay(
            checkIn: checkIn,
            checkOut: checkOut,
            appliedHourlyWage: 10_000,
            appliedNightAllowance: false,
            fallbackHourlyWage: 20_000,
            fallbackNightAllowance: true,
            appliedBreakPolicy: "custom",
            appliedBreakMinutes: 60
        )

        XCTAssertEqual(pay, 40_000, accuracy: 0.001)
    }

    private func makeDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "HowMuchTodayTests", code: 1)
        }
        return date
    }
}

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

    func testWeeklyAllowanceCrossingMonthBelongsToSundayMonth() throws {
        let logs: [(String, String?)] = [
            ("2026-09-28T09:00:00+09:00", "2026-09-28T12:00:00+09:00"),
            ("2026-09-29T09:00:00+09:00", "2026-09-29T12:00:00+09:00"),
            ("2026-09-30T09:00:00+09:00", "2026-09-30T12:00:00+09:00"),
            ("2026-10-01T09:00:00+09:00", "2026-10-01T12:00:00+09:00"),
            ("2026-10-02T09:00:00+09:00", "2026-10-02T12:00:00+09:00"),
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

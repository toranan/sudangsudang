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

    private func makeDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "HowMuchTodayTests", code: 1)
        }
        return date
    }
}

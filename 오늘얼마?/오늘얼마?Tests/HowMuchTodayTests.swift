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

    private func makeDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "HowMuchTodayTests", code: 1)
        }
        return date
    }
}

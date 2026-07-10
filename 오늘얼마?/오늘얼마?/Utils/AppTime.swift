import Foundation

/// 앱 전역 시간 기준.
/// 급여/근태의 일·주·월 경계 계산은 기기 시간대와 무관하게 한국 시간(KST)으로 고정한다.
/// (예: 야간수당 22:00~06:00 경계, 주휴수당 주 단위 합산, 월별 정산 범위)
enum AppTime {
    static let timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current

    /// KST 고정 그레고리력. 일/주/월 경계 계산에 사용.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "ko_KR")
        return cal
    }()

    // ISO8601DateFormatter는 스레드 안전하므로 공유 인스턴스로 재사용한다.
    // (생성 비용이 커서 호출부마다 새로 만들면 리스트 렌더링 시 낭비가 큼)

    /// 서버 타임스탬프(소수점 초 포함) 파서.
    static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 소수점 초 없는 기본 ISO8601 포매터. 문자열 생성에도 사용.
    static let iso = ISO8601DateFormatter()

    /// 소수점 초 유무를 모두 허용하는 파싱.
    static func parseISO(_ value: String) -> Date? {
        isoWithFractionalSeconds.date(from: value) ?? iso.date(from: value)
    }

    static func isoString(from date: Date) -> String {
        iso.string(from: date)
    }

    /// 화면 표시용 DateFormatter (KST/ko_KR 고정). 포맷 문자열별로 캐시한다.
    static func displayFormatter(_ format: String) -> DateFormatter {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = formatterCache[format] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatterCache[format] = formatter
        return formatter
    }

    private static var formatterCache: [String: DateFormatter] = [:]
    private static let cacheLock = NSLock()
}

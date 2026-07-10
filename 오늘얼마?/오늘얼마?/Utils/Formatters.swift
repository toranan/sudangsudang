import SwiftUI

// 앱 공통 표시 포맷터.
// 이전에는 화면마다 같은 함수가 복사되어 있었는데(9개 파일), 표기 기준이 화면별로
// 어긋날 수 있어 한 곳으로 통합했다. 급여/시간/승인 상태 표기는 반드시 여기를 거친다.

private let wonNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
}()

/// 분 → "H시간 M분"
func formatHours(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    return "\(h)시간 \(m)분"
}

/// 금액 → "1,234,567원"
func formatWon(_ value: Double) -> String {
    let number = wonNumberFormatter.string(from: NSNumber(value: Int(value))) ?? "0"
    return "\(number)원"
}

/// 서버 status 값 정규화. 비어 있으면 "pending" 취급.
func normalizedStatus(_ status: String?) -> String {
    let value = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? "pending" : value
}

/// 근무 기록 승인 상태 한글 라벨.
func statusLabel(_ status: String?) -> String {
    let value = normalizedStatus(status)
    return value == "approved" ? "승인" : (value == "rejected" ? "반려" : "대기")
}

/// 근무 기록 승인 상태 색상.
func statusColor(_ status: String?) -> Color {
    let value = normalizedStatus(status)
    return value == "approved" ? .appPositive : (value == "rejected" ? .appWarning : .appTextSecondary)
}

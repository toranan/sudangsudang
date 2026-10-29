import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// 주요 액션(출근/퇴근, 승인 등)의 성공/실패를 촉각으로 알려주는 햅틱 헬퍼.
enum Haptics {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// 글자 크기 단계. 화면에서는 .font(.app(.body, .semibold))처럼 쓴다.
enum AppTextStyle {
    case caption     // 13 보조 설명, 라벨
    case callout     // 15 본문 보조, 목록 값
    case body        // 17 본문, 버튼
    case headline    // 20 섹션 제목
    case title       // 24 화면 제목
    case largeTitle  // 28 강조 숫자
    case display     // 34 대표 숫자 (급여 등)

    var size: CGFloat {
        switch self {
        case .caption: return 13
        case .callout: return 15
        case .body: return 17
        case .headline: return 20
        case .title: return 24
        case .largeTitle: return 28
        case .display: return 34
        }
    }
}

extension Font {
    static func app(_ style: AppTextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(size: style.size, weight: weight)
    }
}

// 모서리 단계: 작은 칩 10, 입력칸 14, 버튼 18, 카드 24.
enum AppRadius {
    static let chip: CGFloat = 10
    static let field: CGFloat = 14
    static let button: CGFloat = 18
    static let card: CGFloat = 24
}

// 미니멀 그린: 따뜻한 회백색 바탕, 흰 카드, 초록 포인트, 검정 주요 버튼.
extension Color {
    #if canImport(UIKit)
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }

    static let appAccent = dynamic(
        light: UIColor(red: 10/255, green: 155/255, blue: 99/255, alpha: 1),
        dark: UIColor(red: 43/255, green: 196/255, blue: 136/255, alpha: 1)
    )
    // 초록 포인트의 옅은 바탕 (타일, 아바타, 칩).
    static let appAccentSoft = dynamic(
        light: UIColor(red: 231/255, green: 246/255, blue: 239/255, alpha: 1),
        dark: UIColor(red: 18/255, green: 52/255, blue: 39/255, alpha: 1)
    )
    // 두 번째 포인트 (보라). 타일을 구분할 때만 쓴다.
    static let appLavender = dynamic(
        light: UIColor(red: 110/255, green: 86/255, blue: 207/255, alpha: 1),
        dark: UIColor(red: 167/255, green: 148/255, blue: 240/255, alpha: 1)
    )
    static let appLavenderSoft = dynamic(
        light: UIColor(red: 241/255, green: 238/255, blue: 255/255, alpha: 1),
        dark: UIColor(red: 40/255, green: 34/255, blue: 66/255, alpha: 1)
    )
    // 주요 버튼, 탭바, 알림 배너의 진한 면과 그 위 글자색.
    static let appInk = dynamic(
        light: UIColor(red: 22/255, green: 24/255, blue: 29/255, alpha: 1),
        dark: UIColor(red: 242/255, green: 244/255, blue: 247/255, alpha: 1)
    )
    static let appOnInk = dynamic(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 22/255, green: 24/255, blue: 29/255, alpha: 1)
    )
    static let appBackground = dynamic(
        light: UIColor(red: 247/255, green: 247/255, blue: 245/255, alpha: 1),
        dark: UIColor(red: 16/255, green: 17/255, blue: 20/255, alpha: 1)
    )
    // 입력칸, 칩 같은 채움 면. 흰 카드와 바탕 어디에 놓여도 보이도록 바탕보다 한 단계 진하다.
    static let appFill = dynamic(
        light: UIColor(red: 239/255, green: 240/255, blue: 242/255, alpha: 1),
        dark: UIColor(red: 52/255, green: 56/255, blue: 63/255, alpha: 1)
    )
    static let appSurface = dynamic(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 28/255, green: 31/255, blue: 36/255, alpha: 1)
    )
    static let appTextPrimary = dynamic(
        light: UIColor(red: 22/255, green: 24/255, blue: 29/255, alpha: 1),
        dark: UIColor(red: 242/255, green: 244/255, blue: 247/255, alpha: 1)
    )
    static let appTextSecondary = dynamic(
        light: UIColor(red: 107/255, green: 112/255, blue: 121/255, alpha: 1),
        dark: UIColor(red: 155/255, green: 163/255, blue: 176/255, alpha: 1)
    )
    static let appLine = dynamic(
        light: UIColor(red: 240/255, green: 241/255, blue: 243/255, alpha: 1),
        dark: UIColor(red: 62/255, green: 67/255, blue: 76/255, alpha: 1)
    )
    static let appPositive = dynamic(
        light: UIColor(red: 18/255, green: 183/255, blue: 106/255, alpha: 1),
        dark: UIColor(red: 86/255, green: 214/255, blue: 171/255, alpha: 1)
    )
    static let appWarning = dynamic(
        light: UIColor(red: 240/255, green: 82/255, blue: 82/255, alpha: 1),
        dark: UIColor(red: 255/255, green: 132/255, blue: 132/255, alpha: 1)
    )
    // 출근 전, 승인 대기처럼 주의를 끄는 상태.
    static let appCaution = dynamic(
        light: UIColor(red: 247/255, green: 144/255, blue: 9/255, alpha: 1),
        dark: UIColor(red: 255/255, green: 170/255, blue: 70/255, alpha: 1)
    )
    #else
    static let appAccent = Color(red: 10/255, green: 155/255, blue: 99/255)
    static let appAccentSoft = Color(red: 231/255, green: 246/255, blue: 239/255)
    static let appLavender = Color(red: 110/255, green: 86/255, blue: 207/255)
    static let appLavenderSoft = Color(red: 241/255, green: 238/255, blue: 255/255)
    static let appInk = Color(red: 22/255, green: 24/255, blue: 29/255)
    static let appOnInk = Color.white
    static let appCaution = Color(red: 247/255, green: 144/255, blue: 9/255)
    static let appBackground = Color(red: 247/255, green: 247/255, blue: 245/255)
    static let appFill = Color(red: 239/255, green: 240/255, blue: 242/255)
    static let appSurface = Color.white
    static let appTextPrimary = Color(red: 27/255, green: 29/255, blue: 33/255)
    static let appTextSecondary = Color(red: 107/255, green: 114/255, blue: 128/255)
    static let appLine = Color(red: 236/255, green: 239/255, blue: 243/255)
    static let appPositive = Color(red: 30/255, green: 200/255, blue: 140/255)
    static let appWarning = Color(red: 255/255, green: 107/255, blue: 107/255)
    #endif

    // Legacy aliases for existing views
    static let tossBlue = appAccent
    static let tossBackground = appBackground
    static let tossTextPrimary = appTextPrimary
    static let tossTextSecondary = appTextSecondary
    static let tossGrey = appBackground
}

// 기본은 검정(appInk) 버튼. 색을 지정하면 그 위 글자는 흰색.
struct PrimaryButtonStyle: ButtonStyle {
    var backgroundColor: Color?
    var foregroundColor: Color?

    init(backgroundColor: Color? = nil, foregroundColor: Color? = nil) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .labelStyle(AppButtonLabelStyle())
                .font(.app(.body, .bold))
                .foregroundColor(foregroundColor ?? (backgroundColor == nil ? .appOnInk : .white))
                .padding(.vertical, 17)
                .frame(maxWidth: .infinity)
                .background(backgroundColor ?? .appInk)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
        }
    }
}

// 눌렀을 때 살짝 작아지고 옅어지는 공통 피드백. 비활성 상태는 흐리게.
private struct PressableLabel<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder let content: Content
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// 버튼 안 아이콘은 글자보다 작게 둔다.
struct AppButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 14, weight: .semibold))
            configuration.title
        }
    }
}

// 카드나 목록 행처럼 큰 영역을 누를 때 쓰는 피드백 (.plain 대신).
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// Legacy alias for existing views
struct TossButtonStyle: ButtonStyle {
    var backgroundColor: Color?
    var foregroundColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle(backgroundColor: backgroundColor, foregroundColor: foregroundColor)
            .makeBody(configuration: configuration)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var foregroundColor: Color = .appAccent

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .labelStyle(AppButtonLabelStyle())
                .font(.app(.body, .semibold))
                .foregroundColor(foregroundColor)
                .padding(.vertical, 17)
                .frame(maxWidth: .infinity)
                .background(foregroundColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
        }
    }
}

struct AppCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}

extension View {
    func appCard() -> some View {
        self.modifier(AppCardStyle())
    }

    // 테두리 없이 회색으로 채운 입력칸.
    func appInputField() -> some View {
        self
            .font(.app(.body))
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.appFill)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.field, style: .continuous))
    }

    // 살짝(60pt) 당기면 바로 새로고침. ScrollView에 직접 붙인다.
    func appRefreshable(_ action: @escaping @MainActor () async -> Void) -> some View {
        self.modifier(PullToRefreshModifier(action: action))
    }
}

private struct PullToRefreshModifier: ViewModifier {
    let action: @MainActor () async -> Void

    @State private var pullDistance: CGFloat = 0
    @State private var isRefreshing = false
    @State private var isArmed = true
    private let threshold: CGFloat = 60

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, distance in
                pullDistance = max(0, distance)
                // 손을 떼고 제자리로 돌아와야 다음 새로고침을 받는다.
                if distance <= 4 { isArmed = true }
                guard isArmed, !isRefreshing, distance >= threshold else { return }
                isArmed = false
                isRefreshing = true
                Haptics.tap()
                Task { @MainActor in
                    await action()
                    isRefreshing = false
                }
            }
            .overlay(alignment: .top) {
                if isRefreshing || pullDistance > 8 {
                    RefreshIndicator(
                        progress: min(1, pullDistance / threshold),
                        isRefreshing: isRefreshing
                    )
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isRefreshing)
    }
}

private struct RefreshIndicator: View {
    let progress: CGFloat
    let isRefreshing: Bool

    var body: some View {
        Group {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.appAccent)
            } else {
                Circle()
                    .trim(from: 0, to: progress * 0.85)
                    .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 20, height: 20)
        .padding(9)
        .background(.regularMaterial, in: Circle())
    }
}

// 아이콘과 두 줄 글자를 가로로 놓은 옅은 색 타일 (직원 초대, 직접 등록 등).
struct ActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .appAccent
    var fill: Color = .appAccentSoft
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.appTextSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableRowStyle())
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.app(.headline, .bold))
                .foregroundColor(.appTextPrimary)
            Spacer()
            if let trailing = trailing {
                Button(action: { action?() }) {
                    Text(trailing)
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

// 입력한 시급이 최저시급보다 낮을 때만 보이는 안내. 저장은 막지 않는다.
struct MinimumWageHint: View {
    let input: String

    private var wage: Double? {
        Double(input.filter { $0.isNumber })
    }

    var body: some View {
        if let wage, wage > 0, wage < AppConfig.minimumHourlyWage {
            Text("2026년 최저시급(\(Int(AppConfig.minimumHourlyWage).formatted())원)보다 낮아요")
                .font(.app(.caption, .medium))
                .foregroundColor(.appWarning)
        }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.app(.caption, .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

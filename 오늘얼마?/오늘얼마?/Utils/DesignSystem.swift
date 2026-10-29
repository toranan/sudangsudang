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

// 모서리 단계: 작은 칩 10, 입력칸·작은 카드 12, 버튼 16, 카드 20.
enum AppRadius {
    static let chip: CGFloat = 10
    static let field: CGFloat = 12
    static let button: CGFloat = 16
    static let card: CGFloat = 20
}

// Toss-like Color System (clean + friendly)
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
        light: UIColor(red: 30/255, green: 104/255, blue: 255/255, alpha: 1),
        dark: UIColor(red: 78/255, green: 139/255, blue: 255/255, alpha: 1)
    )
    static let appBackground = dynamic(
        light: UIColor(red: 242/255, green: 244/255, blue: 246/255, alpha: 1),
        dark: UIColor(red: 16/255, green: 17/255, blue: 20/255, alpha: 1)
    )
    // 입력칸, 칩 같은 채움 면. 흰 카드와 회색 배경 어디에 놓여도 보이도록 배경보다 한 단계 진하다.
    static let appFill = dynamic(
        light: UIColor(red: 230/255, green: 233/255, blue: 237/255, alpha: 1),
        dark: UIColor(red: 52/255, green: 56/255, blue: 63/255, alpha: 1)
    )
    static let appSurface = dynamic(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 28/255, green: 31/255, blue: 36/255, alpha: 1)
    )
    static let appTextPrimary = dynamic(
        light: UIColor(red: 25/255, green: 31/255, blue: 40/255, alpha: 1),
        dark: UIColor(red: 242/255, green: 244/255, blue: 247/255, alpha: 1)
    )
    static let appTextSecondary = dynamic(
        light: UIColor(red: 107/255, green: 118/255, blue: 132/255, alpha: 1),
        dark: UIColor(red: 155/255, green: 163/255, blue: 176/255, alpha: 1)
    )
    static let appLine = dynamic(
        light: UIColor(red: 236/255, green: 239/255, blue: 243/255, alpha: 1),
        dark: UIColor(red: 62/255, green: 67/255, blue: 76/255, alpha: 1)
    )
    static let appPositive = dynamic(
        light: UIColor(red: 30/255, green: 200/255, blue: 140/255, alpha: 1),
        dark: UIColor(red: 86/255, green: 214/255, blue: 171/255, alpha: 1)
    )
    static let appWarning = dynamic(
        light: UIColor(red: 255/255, green: 107/255, blue: 107/255, alpha: 1),
        dark: UIColor(red: 255/255, green: 132/255, blue: 132/255, alpha: 1)
    )
    #else
    static let appAccent = Color(red: 30/255, green: 104/255, blue: 255/255)
    static let appBackground = Color(red: 242/255, green: 244/255, blue: 246/255)
    static let appFill = Color(red: 230/255, green: 233/255, blue: 237/255)
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

struct PrimaryButtonStyle: ButtonStyle {
    var backgroundColor: Color = .appAccent
    var foregroundColor: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .font(.app(.body, .semibold))
                .foregroundColor(foregroundColor)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
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
    var backgroundColor: Color = .appAccent
    var foregroundColor: Color = .white

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
                .font(.app(.body, .semibold))
                .foregroundColor(foregroundColor)
                .padding(.vertical, 16)
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

    func refreshStatusOverlay(isVisible: Bool, text: String = "새로고침 중") -> some View {
        self.modifier(RefreshStatusOverlayModifier(isVisible: isVisible, text: text))
    }
}

private struct RefreshStatusOverlayModifier: ViewModifier {
    let isVisible: Bool
    let text: String

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isVisible {
                    RefreshStatusBadge(text: text)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isVisible)
    }
}

private struct RefreshStatusBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.app(.caption, .semibold))
                .foregroundColor(.appTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(Capsule())
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

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
        light: UIColor(red: 247/255, green: 248/255, blue: 250/255, alpha: 1),
        dark: UIColor(red: 18/255, green: 20/255, blue: 24/255, alpha: 1)
    )
    static let appSurface = dynamic(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 28/255, green: 31/255, blue: 36/255, alpha: 1)
    )
    static let appTextPrimary = dynamic(
        light: UIColor(red: 27/255, green: 29/255, blue: 33/255, alpha: 1),
        dark: UIColor(red: 242/255, green: 244/255, blue: 247/255, alpha: 1)
    )
    static let appTextSecondary = dynamic(
        light: UIColor(red: 107/255, green: 114/255, blue: 128/255, alpha: 1),
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
    static let appBackground = Color(red: 247/255, green: 248/255, blue: 250/255)
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
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(foregroundColor)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
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
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(foregroundColor)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appLine, lineWidth: 1)
            )
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AppCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Color.appSurface)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
    }
}

extension View {
    func appCard() -> some View {
        self.modifier(AppCardStyle())
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
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appSurface.opacity(0.96))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.appLine, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.appTextPrimary)
            Spacer()
            if let trailing = trailing {
                Button(action: { action?() }) {
                    Text(trailing)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(.bottom, 4)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .cornerRadius(8)
    }
}

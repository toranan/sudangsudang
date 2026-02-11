import SwiftUI

// Toss-like Color System (clean + friendly)
extension Color {
    static let appAccent = Color(red: 30/255, green: 104/255, blue: 255/255)
    static let appBackground = Color(red: 247/255, green: 248/255, blue: 250/255)
    static let appSurface = Color.white
    static let appTextPrimary = Color(red: 27/255, green: 29/255, blue: 33/255)
    static let appTextSecondary = Color(red: 107/255, green: 114/255, blue: 128/255)
    static let appLine = Color(red: 236/255, green: 239/255, blue: 243/255)
    static let appPositive = Color(red: 30/255, green: 200/255, blue: 140/255)
    static let appWarning = Color(red: 255/255, green: 107/255, blue: 107/255)

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

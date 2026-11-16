import SwiftUI

/// One place for the visual language: colors, gradients, type and card chrome.
enum Theme {
    static let violet = Color(red: 0.388, green: 0.357, blue: 1.0)      // brand
    static let deepViolet = Color(red: 0.20, green: 0.14, blue: 0.62)
    static let lilac = Color(red: 0.66, green: 0.55, blue: 1.0)
    static let forms = Color(red: 0.388, green: 0.357, blue: 1.0)
    static let calls = Color(red: 0.10, green: 0.74, blue: 0.56)
    static let missed = Color(red: 1.0, green: 0.33, blue: 0.40)
    static let money = Color(red: 0.10, green: 0.74, blue: 0.56)
    static let warn = Color(red: 1.0, green: 0.62, blue: 0.10)
    static let bad = Color(red: 1.0, green: 0.33, blue: 0.40)
    static let info = Color(red: 0.16, green: 0.56, blue: 1.0)

    static let corner: CGFloat = 22

    static var hero: LinearGradient {
        LinearGradient(colors: [Color(red: 0.17, green: 0.11, blue: 0.55),
                                Color(red: 0.35, green: 0.27, blue: 0.95),
                                Color(red: 0.60, green: 0.45, blue: 1.0)],
                       startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    static var moneyHero: LinearGradient {
        LinearGradient(colors: [Color(red: 0.02, green: 0.30, blue: 0.27),
                                Color(red: 0.04, green: 0.55, blue: 0.45),
                                Color(red: 0.25, green: 0.80, blue: 0.62)],
                       startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    static var siteHero: LinearGradient {
        LinearGradient(colors: [Color(red: 0.05, green: 0.20, blue: 0.50),
                                Color(red: 0.10, green: 0.42, blue: 0.90),
                                Color(red: 0.35, green: 0.70, blue: 1.0)],
                       startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    private static let avatarPalette: [[Color]] = [
        [Color(red: 0.39, green: 0.36, blue: 1.0), Color(red: 0.62, green: 0.47, blue: 1.0)],
        [Color(red: 0.05, green: 0.62, blue: 0.52), Color(red: 0.30, green: 0.85, blue: 0.62)],
        [Color(red: 0.95, green: 0.35, blue: 0.45), Color(red: 1.0, green: 0.55, blue: 0.45)],
        [Color(red: 0.10, green: 0.50, blue: 0.95), Color(red: 0.35, green: 0.75, blue: 1.0)],
        [Color(red: 0.95, green: 0.55, blue: 0.10), Color(red: 1.0, green: 0.75, blue: 0.25)],
        [Color(red: 0.70, green: 0.30, blue: 0.85), Color(red: 0.90, green: 0.45, blue: 0.85)],
        [Color(red: 0.20, green: 0.30, blue: 0.55), Color(red: 0.40, green: 0.52, blue: 0.75)],
        [Color(red: 0.00, green: 0.60, blue: 0.75), Color(red: 0.25, green: 0.82, blue: 0.88)],
    ]

    static func avatarColors(_ key: String) -> [Color] {
        let h = key.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7fffffff }
        return avatarPalette[h % avatarPalette.count]
    }

    static func tint(for kind: LeadKind) -> Color {
        switch kind {
        case .form: return forms
        case .call: return calls
        case .missed: return missed
        case .phone: return info
        }
    }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: Card chrome

struct CardChrome: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.corner

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = Theme.corner) -> some View {
        modifier(CardChrome(padding: padding, radius: radius))
    }

    /// A soft brand wash at the top of a screen, like Fitness and Wallet.
    func screenBackground(_ tint: Color = Theme.violet) -> some View {
        background {
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 380)
            }
            .ignoresSafeArea()
        }
    }
}

/// Springy press feedback for card buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: Zoom transitions (iOS 18)

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID? = nil
}

extension View {
    @ViewBuilder
    func zoomSource(_ id: String, _ ns: Namespace.ID?) -> some View {
        if let ns {
            self.matchedTransitionSource(id: id, in: ns) { src in
                src.clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomDestination(_ id: String, _ ns: Namespace.ID?) -> some View {
        if let ns {
            self.navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }
}

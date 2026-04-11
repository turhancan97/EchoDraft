import SwiftUI

/// Central tokens and styles for EchoDraft’s visual language (light/dark, materials, accent).
public enum DesignSystem {
    // MARK: - Accent & base colors

    /// Fixed electric blue primary accent (not system accent).
    public static let accentElectricBlue = Color(
        red: 0.15,
        green: 0.45,
        blue: 1.0
    )

    public static let accentElectricBlueBright = Color(
        red: 0.35,
        green: 0.55,
        blue: 1.0
    )

    /// Speaker stripe / tint cycle: green, purple, teal, orange (subtle).
    public static let speakerStripeColors: [Color] = [
        Color(red: 0.2, green: 0.72, blue: 0.45),
        Color(red: 0.58, green: 0.38, blue: 0.95),
        Color(red: 0.2, green: 0.65, blue: 0.78),
        Color(red: 0.95, green: 0.45, blue: 0.35),
        Color(red: 0.45, green: 0.55, blue: 0.98),
        Color(red: 0.85, green: 0.55, blue: 0.25),
    ]

    public static func speakerIndex(from label: String) -> Int {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: #"Speaker\s+(\d+)"#, options: .caseInsensitive),
            let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            match.numberOfRanges > 1,
            let r = Range(match.range(at: 1), in: trimmed),
            let n = Int(trimmed[r])
        {
            return max(0, n - 1)
        }
        return abs(trimmed.hashValue) % speakerStripeColors.count
    }

    public static func speakerStripeColor(for label: String) -> Color {
        let i = speakerIndex(from: label) % speakerStripeColors.count
        return speakerStripeColors[i]
    }

    public static func speakerRowTint(for label: String, colorScheme: ColorScheme) -> Color {
        let base = speakerStripeColor(for: label)
        return colorScheme == .dark ? base.opacity(0.14) : base.opacity(0.10)
    }

    // MARK: - Spacing

    public static let outerPadding: CGFloat = 22
    public static let sectionSpacing: CGFloat = 16
    public static let listRowPadding: CGFloat = 12
    public static let stripeWidth: CGFloat = 4
    public static let panelCornerRadius: CGFloat = 14

    // MARK: - Typography

    public static func titleRounded() -> Font {
        .system(.title2, design: .rounded).weight(.bold)
    }

    public static func headlineRounded() -> Font {
        .system(.title3, design: .rounded).weight(.semibold)
    }

    public static func bodyReadable() -> Font {
        .system(.body, design: .default)
    }

    public static func captionMuted() -> Font {
        .system(.caption, design: .default)
    }

    // MARK: - Motion

    public static func preferredAnimation(reduceMotion: Bool, value: some Equatable) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.15)
        }
        return .spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - Materials & panels

public struct EchoFrostedPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .padding(DesignSystem.outerPadding)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                lineWidth: 1
                            )
                    }
            }
    }
}

extension View {
    public func echoFrostedPanel() -> some View {
        modifier(EchoFrostedPanelModifier())
    }
}

// MARK: - Banners (processing / error)

public struct EchoBannerModifier: ViewModifier {
    let isError: Bool
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .padding(DesignSystem.listRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius, style: .continuous)
                            .strokeBorder(
                                isError ? Color.red.opacity(0.45) : DesignSystem.accentElectricBlue.opacity(0.35),
                                lineWidth: 1.5
                            )
                    }
            }
    }
}

// MARK: - Buttons

public struct EchoBorderedButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(prominent: Bool = false) {
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(prominent ? .semibold : .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        prominent
                            ? DesignSystem.accentElectricBlue
                            : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        prominent
                            ? DesignSystem.accentElectricBlue.opacity(0.9)
                            : DesignSystem.accentElectricBlue.opacity(0.45),
                        lineWidth: 1.5
                    )
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(
                DesignSystem.preferredAnimation(reduceMotion: reduceMotion, value: configuration.isPressed),
                value: configuration.isPressed
            )
    }
}

/// Compact bordered control for timestamps (not a plain link).
public struct EchoTimestampButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.monospaced().weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(DesignSystem.accentElectricBlue.opacity(0.55), lineWidth: 1)
            }
            .foregroundStyle(DesignSystem.accentElectricBlue)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                DesignSystem.preferredAnimation(reduceMotion: reduceMotion, value: configuration.isPressed),
                value: configuration.isPressed
            )
    }
}

// MARK: - Toolbar gradient icons

public struct EchoGradientSymbolIcon: View {
    let systemName: String
    var size: CGFloat = 18

    public init(systemName: String, size: CGFloat = 18) {
        self.systemName = systemName
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        DesignSystem.accentElectricBlueBright,
                        DesignSystem.accentElectricBlue,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: DesignSystem.accentElectricBlue.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Hover scale

public struct EchoHoverScaleModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    public init() {}

    public func body(content: Content) -> some View {
        content
            .scaleEffect((!reduceMotion && hovered) ? 1.02 : 1.0)
            .animation(
                DesignSystem.preferredAnimation(reduceMotion: reduceMotion, value: hovered),
                value: hovered
            )
            .onHover { hovered = $0 }
    }
}

extension View {
    public func echoHoverScale() -> some View {
        modifier(EchoHoverScaleModifier())
    }
}

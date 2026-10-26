import SwiftUI

// The look shared by Quarry and its tools, after ferriteworks.com: black fading to graphite,
// hairline borders, a faint dot grid, heavy headings and no color.

/// Monochrome palette taken from ferriteworks.com.
public enum Brand {
    public static let black = Color(red: 0, green: 0, blue: 0)
    public static let ink = Color(red: 0.024, green: 0.020, blue: 0.016)  // #060504
    public static let graphite = Color(red: 0.086, green: 0.086, blue: 0.086)  // #161616
    public static let hairline = Color.white.opacity(0.08)
    public static let primary = Color.white.opacity(0.92)
    public static let secondary = Color.white.opacity(0.55)
    public static let tertiary = Color.white.opacity(0.38)
    /// Accent for controls such as switches and sliders.
    public static let tint = Color(white: 0.42)
}

/// Black fading to graphite, a faint dot grid, and soft grey glows for the glass to refract.
public struct Backdrop: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.graphite, Brand.black], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.07), .clear], center: UnitPoint(x: 0.7, y: 0.3), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [.white.opacity(0.04), .clear], center: UnitPoint(x: 0.25, y: 0.8), startRadius: 0, endRadius: 420)
            DotGrid()
        }
        .ignoresSafeArea()
    }
}

public struct DotGrid: View {
    var spacing: CGFloat
    var opacity: Double

    public init(spacing: CGFloat = 22, opacity: Double = 0.07) {
        self.spacing = spacing
        self.opacity = opacity
    }

    public var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                }
            }
            context.fill(dots, with: .color(.white.opacity(opacity)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Liquid Glass with a material fallback before macOS 26

extension EnvironmentValues {
    /// Draws glass cards as plain graphite. Glass smears when cards are rotated, as they are
    /// while an easter egg plays.
    @Entry public var solidGlass = false
}

extension View {
    public func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    public func glassButton(prominent: Bool = false) -> some View {
        buttonStyle(FerriteButtonStyle(prominent: prominent))
    }

    @ViewBuilder
    public func glassCircle() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.regularMaterial, in: Circle())
        }
    }

    /// Text and control colors for a Quarry page or window.
    public func ferriteStyle() -> some View {
        tint(Brand.tint).foregroundStyle(Brand.primary)
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @Environment(\.solidGlass) private var solidGlass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let card = content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(shape.strokeBorder(Brand.hairline))
        if solidGlass {
            card.background(Brand.graphite, in: shape)
        } else if #available(macOS 26, *) {
            card.glassEffect(.regular.tint(.white.opacity(0.02)), in: .rect(cornerRadius: cornerRadius))
        } else {
            card.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// Dark, hairline-bordered buttons. The system glass buttons take the window tint and come out
/// light grey on black.
public struct FerriteButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(prominent: Bool = false) {
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        let fill = configuration.isPressed ? 0.16 : prominent ? 0.11 : 0.05
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Brand.primary : Brand.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(fill)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(prominent ? 0.18 : 0.11)))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

import SwiftUI

/// Liquid Glass on iOS 26 and later, a frosted blur before that.
extension View {
    /// A glass panel in the given shape, optionally tinted, optionally
    /// reacting to touch (for things you press).
    @ViewBuilder
    func glassPanel<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint) }
                    shape.strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                }
            }
        }
    }

    /// The main action on a screen: tinted glass, or a filled button before iOS 26.
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// A secondary action: clear glass, or a bordered button before iOS 26.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Groups glass shapes so they blend and morph together on iOS 26.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 12) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    @available(iOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// The table under everything: a soft wash with a hint of each team's
/// colour, so the glass above it has something to bend.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: dark
                           ? [Color(red: 0.06, green: 0.08, blue: 0.12), Color(red: 0.09, green: 0.08, blue: 0.08)]
                           : [Color(red: 0.93, green: 0.95, blue: 0.98), Color(red: 0.97, green: 0.95, blue: 0.92)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.us.opacity(dark ? 0.22 : 0.16), .clear],
                           center: UnitPoint(x: 0.1, y: 0.05), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.them.opacity(dark ? 0.16 : 0.12), .clear],
                           center: UnitPoint(x: 0.95, y: 0.95), startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

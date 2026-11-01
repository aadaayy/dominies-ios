import SwiftUI

/// One domino drawn at any size: ivory face, a thin centre line and black pips.
/// `first` is the left half (lying down) or the top half (standing up).
struct DominoView: View {
    let first: Int
    let second: Int
    let isVertical: Bool
    var dimmed = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let short = min(size.width, size.height)
            let corner = short * 0.16
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.tileFace)
                    .shadow(color: Theme.tileShadow, radius: short * 0.06, y: short * 0.03)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.tileEdge, lineWidth: max(0.5, short * 0.02))
                Canvas { context, canvasSize in
                    draw(in: &context, size: canvasSize)
                }
            }
            .opacity(dimmed ? 0.4 : 1)
        }
        .accessibilityElement()
        .accessibilityLabel("\(first) \(second)")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let short = min(size.width, size.height)
        // Centre line, inset from the edges.
        var line = Path()
        if isVertical {
            line.move(to: CGPoint(x: short * 0.2, y: size.height / 2))
            line.addLine(to: CGPoint(x: size.width - short * 0.2, y: size.height / 2))
        } else {
            line.move(to: CGPoint(x: size.width / 2, y: short * 0.2))
            line.addLine(to: CGPoint(x: size.width / 2, y: size.height - short * 0.2))
        }
        context.stroke(line, with: .color(Theme.pip.opacity(0.28)), lineWidth: max(0.5, short * 0.025))

        let halves: [(value: Int, origin: CGPoint)] = isVertical
            ? [(first, .zero), (second, CGPoint(x: 0, y: short))]
            : [(first, .zero), (second, CGPoint(x: short, y: 0))]
        let radius = short * 0.085
        for half in halves {
            for spot in DominoView.spots(for: half.value) {
                // Lying down, the pattern turns with the tile.
                let unit = isVertical ? spot : CGPoint(x: spot.y, y: spot.x)
                let inset = short * 0.24
                let center = CGPoint(x: half.origin.x + inset + unit.x * (short - inset * 2),
                                     y: half.origin.y + inset + unit.y * (short - inset * 2))
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(Theme.pip))
            }
        }
    }

    /// Pip positions in a unit square, for a half standing upright.
    static func spots(for value: Int) -> [CGPoint] {
        let l = 0.0, m = 0.5, r = 1.0
        let tl = CGPoint(x: l, y: l), tc = CGPoint(x: m, y: l), tr = CGPoint(x: r, y: l)
        let ml = CGPoint(x: l, y: m), c = CGPoint(x: m, y: m), mr = CGPoint(x: r, y: m)
        let bl = CGPoint(x: l, y: r), bc = CGPoint(x: m, y: r), br = CGPoint(x: r, y: r)
        switch value {
        case 1: return [c]
        case 2: return [tr, bl]
        case 3: return [tr, c, bl]
        case 4: return [tl, tr, bl, br]
        case 5: return [tl, tr, c, bl, br]
        case 6: return [tl, tr, ml, mr, bl, br]
        case 7: return [tl, tr, ml, c, mr, bl, br]
        case 8: return [tl, tc, tr, ml, mr, bl, bc, br]
        case 9: return [tl, tc, tr, ml, c, mr, bl, bc, br]
        default: return []
        }
    }
}

import SwiftUI

/// How the game screen shows who sits where. Two designs to compare; the
/// one Alberto picks stays and the other goes.
enum TableStyle: String, CaseIterable {
    /// The other players sit at the screen's edges, where they'd sit at a
    /// real table: Left on the left, Partner across the top, Right on the right.
    case around
    /// A small drawing of the table, with everyone in their seat.
    case map
}

/// One player as the screen shows them.
struct SeatInfo: Identifiable {
    let seat: Int
    let name: String
    let team: Team
    let tiles: Int
    let isTurn: Bool
    /// What they did last this game.
    let last: Action?

    var id: Int { seat }
    var color: Color { Theme.color(for: team) }
}

/// Where a seat sits relative to you, as an arrow.
private func arrow(for seat: Int) -> String {
    switch seat {
    case 1: return "arrow.left"
    case 2: return "arrow.up"
    case 3: return "arrow.right"
    default: return "arrow.down"
    }
}

/// The tile a player played last, drawn small, or "Knocked".
struct LastPlay: View {
    let last: Action?
    var height: CGFloat = 14

    var body: some View {
        switch last {
        case .play(_, let tile, _)?:
            DominoView(first: tile.low, second: tile.high, isVertical: false)
                .frame(width: height * 2, height: height)
                .accessibilityLabel("Played \(tile.low) and \(tile.high)")
        case .knock?:
            Text("Knocked")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: height)
        case nil:
            Color.clear.frame(width: height * 2, height: height)
        }
    }
}

/// Tiles left, as a number with a small tile shape.
struct TilesLeft: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .strokeBorder(Color.secondary, lineWidth: 1)
                .frame(width: 6, height: 11)
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) tiles left")
    }
}

// MARK: - Around the table

/// A player at the edge of the screen. Upright (Left and Right, on the sides)
/// or lying along the top (Partner).
struct EdgeSeat: View {
    let info: SeatInfo
    var lying = false

    var body: some View {
        Group {
            if lying {
                HStack(spacing: 8) {
                    nameLabel
                    LastPlay(last: info.last)
                    TilesLeft(count: info.tiles)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
            } else {
                VStack(spacing: 5) {
                    nameLabel
                    LastPlay(last: info.last)
                    TilesLeft(count: info.tiles)
                }
                .padding(.vertical, 10)
                .frame(width: 68)
            }
        }
        .glassPanel(shape, tint: info.isTurn ? info.color.opacity(0.28) : nil)
        .overlay {
            shape.strokeBorder(info.color.opacity(info.isTurn ? 1 : 0), lineWidth: 2)
        }
        .animation(.easeInOut(duration: 0.2), value: info.isTurn)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("seat-\(info.name)")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: lying ? 18 : 20, style: .continuous)
    }

    private var nameLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: arrow(for: info.seat))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(info.color)
            Text(info.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Table map

/// A small drawing of the table seen from above: you at the bottom, your
/// partner across, Left and Right on the sides, with play going round the
/// way the arrow shows. Whoever is playing is filled in their team colour.
struct SeatMap: View {
    let seats: [SeatInfo]
    /// Narrow, for the folded Duo's side bar.
    var compact = false

    var body: some View {
        let side: CGFloat = compact ? 104 : 184
        let bubble = CGSize(width: compact ? 40 : 62, height: compact ? 34 : 40)
        ZStack {
            // The table top.
            RoundedRectangle(cornerRadius: compact ? 14 : 20, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 14 : 20, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                }
                .frame(width: side - bubble.width * 0.9, height: side - bubble.height * 1.3)
            // Play goes round this way: you, then Left, Partner, Right.
            Image(systemName: "arrow.clockwise")
                .font(.system(size: compact ? 14 : 20, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Play goes to your left, round the table")
            ForEach(seats) { info in
                bubbleView(info, size: bubble)
                    .position(position(of: info.seat, side: side, bubble: bubble))
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("seat-map")
    }

    private func position(of seat: Int, side: CGFloat, bubble: CGSize) -> CGPoint {
        switch seat {
        case 1: return CGPoint(x: bubble.width / 2, y: side / 2)
        case 2: return CGPoint(x: side / 2, y: bubble.height / 2)
        case 3: return CGPoint(x: side - bubble.width / 2, y: side / 2)
        default: return CGPoint(x: side / 2, y: side - bubble.height / 2)
        }
    }

    private func bubbleView(_ info: SeatInfo, size: CGSize) -> some View {
        VStack(spacing: 1) {
            Text(info.name)
                .font((compact ? Font.caption2 : .caption).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(info.isTurn ? Color.white : Color.primary)
            if info.seat != 0 {
                Text("\(info.tiles)")
                    .font((compact ? Font.caption2 : .caption).monospacedDigit())
                    .foregroundStyle(info.isTurn ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, 3)
        .frame(minWidth: size.width, minHeight: size.height)
        .fixedSize()
        .glassPanel(Capsule(), tint: info.isTurn ? info.color : nil)
        .overlay {
            Capsule().strokeBorder(info.color.opacity(info.isTurn ? 0 : 0.7), lineWidth: 1.5)
        }
        .animation(.easeInOut(duration: 0.2), value: info.isTurn)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("seat-\(info.name)")
    }
}

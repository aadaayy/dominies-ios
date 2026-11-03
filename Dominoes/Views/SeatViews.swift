import SwiftUI

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
                .frame(width: 76)
            }
        }
        .glassPanel(shape, tint: info.isTurn ? info.color.opacity(0.28) : nil)
        .overlay {
            shape.strokeBorder(info.color.opacity(info.isTurn ? 1 : 0), lineWidth: 2)
        }
        .animation(.easeInOut(duration: 0.2), value: info.isTurn)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("seat-\(GameController.names[info.seat])")
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

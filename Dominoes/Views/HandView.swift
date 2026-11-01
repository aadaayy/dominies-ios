import SwiftUI

/// Your tiles, standing up along the bottom, in one row or two (five and
/// five, so a full hand of ten always shows on a narrow screen). Tiles you
/// can play sit a little higher; the rest are dimmed while it's your turn.
struct HandView: View {
    let tiles: [Tile]
    let playable: Set<Tile>
    let isYourTurn: Bool
    var selected: Tile?
    /// 1 for a single row, 2 for five and five.
    var rows = 1
    var onTap: (Tile) -> Void

    static let spacing: CGFloat = 6
    static let lift: CGFloat = 8
    static let rowGap: CGFloat = 10

    /// The height a hand needs for tiles of the given width.
    static func height(rows: Int, tileWidth: CGFloat) -> CGFloat {
        CGFloat(rows) * (tileWidth * 2 + lift) + CGFloat(rows - 1) * rowGap
    }

    var body: some View {
        GeometryReader { geometry in
            // Size the tiles for a full hand so they keep their size as you play.
            let perRow = rows > 1 ? Int((Double(max(tiles.count, 10)) / Double(rows)).rounded(.up)) : max(tiles.count, 7)
            let byWidth = (geometry.size.width - Self.spacing * CGFloat(perRow - 1)) / CGFloat(perRow)
            let byHeight = (geometry.size.height - Self.lift * CGFloat(rows) - Self.rowGap * CGFloat(rows - 1)) / CGFloat(rows) / 2
            let width: CGFloat = max(18, min(rows > 1 ? 52 : 46, byWidth, byHeight))
            let lines = stride(from: 0, to: tiles.count, by: perRow).map { Array(tiles[$0..<min($0 + perRow, tiles.count)]) }
            VStack(spacing: Self.rowGap) {
                ForEach(lines.indices, id: \.self) { index in
                    HStack(spacing: Self.spacing) {
                        ForEach(lines[index]) { tile in
                            button(for: tile, width: width)
                        }
                    }
                }
            }
            .padding(.top, Self.lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(duration: 0.3), value: tiles)
            .animation(.spring(duration: 0.3), value: isYourTurn)
        }
    }

    private func button(for tile: Tile, width: CGFloat) -> some View {
        let canPlay = playable.contains(tile)
        return Button {
            onTap(tile)
        } label: {
            DominoView(first: tile.low, second: tile.high, isVertical: true,
                       dimmed: isYourTurn && !canPlay)
                .frame(width: width, height: width * 2)
                .overlay {
                    if tile == selected {
                        RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .offset(y: isYourTurn && canPlay ? -Self.lift : 0)
        }
        .buttonStyle(.plain)
        .disabled(!isYourTurn || !canPlay)
        .accessibilityIdentifier("hand-tile-\(tile.id)")
        .transition(.scale.combined(with: .opacity))
    }
}

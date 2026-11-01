import SwiftUI

/// Your tiles, standing up in a row along the bottom. Tiles you can play sit
/// a little higher; the rest are dimmed while it's your turn.
struct HandView: View {
    let tiles: [Tile]
    let playable: Set<Tile>
    let isYourTurn: Bool
    var selected: Tile?
    var onTap: (Tile) -> Void

    var body: some View {
        GeometryReader { geometry in
            let count = CGFloat(max(tiles.count, 7))
            let spacing: CGFloat = 6
            let byWidth = (geometry.size.width - spacing * (count - 1)) / count
            let byHeight = (geometry.size.height - 12) / 2
            let width: CGFloat = max(18, min(46, byWidth, byHeight))
            HStack(spacing: spacing) {
                ForEach(tiles) { tile in
                    let canPlay = playable.contains(tile)
                    Button {
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
                            .offset(y: isYourTurn && canPlay ? -8 : 0)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isYourTurn || !canPlay)
                    .accessibilityIdentifier("hand-tile-\(tile.id)")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(duration: 0.3), value: tiles)
            .animation(.spring(duration: 0.3), value: isYourTurn)
        }
    }
}

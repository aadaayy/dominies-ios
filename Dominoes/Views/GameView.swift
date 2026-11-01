import SwiftUI

/// The table: scores and the three other players at the top, the line of
/// tiles in the middle and your hand at the bottom. On a short, wide screen
/// (a phone on its side) the scores and players move to a column on the left.
struct GameView: View {
    @Bindable var controller: GameController
    var onExit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            // Sideways phones and the open Duo get the wide layout; upright
            // phones and the folded Duo stack everything.
            let size = geometry.size
            let wide = size.width > size.height * 1.2
            ZStack {
                Backdrop()
                if wide { sideways(size) } else { upright(size) }
                overlays
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: controller.playCount)
        .onDisappear { controller.stop() }
    }

    // MARK: - Layouts

    /// Hand tray padding: above the tiles and below them.
    private static let trayPadding: (top: CGFloat, bottom: CGFloat) = (14, 6)

    private func upright(_ size: CGSize) -> some View {
        // On a narrow screen the hand is two rows of five, so all ten show.
        let rows = size.width < 600 ? 2 : 1
        let perRow: CGFloat = rows == 2 ? 5 : 10
        let byWidth = (size.width - 24 - HandView.spacing * (perRow - 1)) / perRow
        let tileWidth = min(rows == 2 ? 40 : 44, byWidth, size.height * 0.055)
        let handHeight = HandView.height(rows: rows, tileWidth: tileWidth) + Self.trayPadding.top + Self.trayPadding.bottom
        return VStack(spacing: 10) {
            topBar
            seats(axis: .horizontal)
                .glassGroup()
                .padding(.horizontal)
            table
            statusLine
            hand(rows: rows).frame(height: handHeight)
        }
    }

    private func sideways(_ size: CGSize) -> some View {
        let handHeight = min(140, max(96, size.height * 0.26))
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    closeButton
                    Spacer()
                }
                ScoreView(match: controller.match)
                seats(axis: .vertical)
                    .glassGroup()
                Spacer(minLength: 0)
                statusLine
            }
            .frame(width: 200)
            .padding(.leading, 8)
            VStack(spacing: 6) {
                table
                hand(rows: 1).frame(height: handHeight)
            }
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            closeButton
            Spacer()
            ScoreView(match: controller.match)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .glassPanel(Capsule())
            Spacer()
            Text("Game \(controller.match.gameNumber)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var closeButton: some View {
        Button(action: onExit) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .glassPanel(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("close-game")
        .accessibilityLabel("Leave game")
        .frame(width: 64, alignment: .leading)
    }

    private func seats(axis: Axis) -> some View {
        let order = [1, 2, 3]
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return layout {
            ForEach(order, id: \.self) { seat in
                SeatChip(name: GameController.names[seat],
                         team: Team.of(seat: seat),
                         tiles: controller.game.hands[seat].count,
                         isTurn: controller.phase == .playing && !controller.game.isOver && controller.game.current == seat,
                         note: note(for: seat))
            }
        }
    }

    private var table: some View {
        TableView(board: controller.game.board,
                  lastTile: lastPlayedTile,
                  endChoice: endChoice,
                  onChooseEnd: { controller.play(pendingOn: $0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusLine: some View {
        HStack(spacing: 12) {
            if controller.isYourTurn {
                Circle().fill(Theme.us).frame(width: 8, height: 8)
            }
            Text(controller.pendingTile == nil ? controller.status : "Tap the end to play on")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(controller.isYourTurn ? .primary : .secondary)
                .accessibilityIdentifier("status")
            if controller.isYourTurn && controller.yourMoves.isEmpty {
                Button("Knock") { controller.knock() }
                    .prominentGlassButton()
                    .controlSize(.small)
                    .accessibilityIdentifier("knock")
            }
            if controller.pendingTile != nil {
                Button("Cancel") { controller.cancelPending() }
                    .glassButton()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .glassPanel(Capsule())
    }

    private func hand(rows: Int) -> some View {
        HandView(tiles: controller.yourHand,
                 playable: Set(controller.yourMoves.map(\.tile)),
                 isYourTurn: controller.isYourTurn,
                 selected: controller.pendingTile,
                 rows: rows,
                 onTap: { controller.tap($0) })
            .padding(.horizontal, 12)
            .padding(.top, Self.trayPadding.top)
            .padding(.bottom, Self.trayPadding.bottom)
            .background {
                Color.clear
                    .glassPanel(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
                    .ignoresSafeArea(edges: .bottom)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hand")
    }

    @ViewBuilder
    private var overlays: some View {
        switch controller.phase {
        case .choosingStarter:
            Dimmed(dims: false) {
                StarterCard(onChoose: { controller.lead(withPartner: $0) })
            }
        case .gameOver, .matchOver:
            if let result = controller.game.result {
                Dimmed {
                    ResultCard(result: result,
                               game: controller.game,
                               match: controller.match,
                               isMatchOver: controller.phase == .matchOver,
                               onNext: { controller.nextGame() },
                               onDone: onExit)
                }
            }
        case .playing:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var lastPlayedTile: Tile? {
        for action in controller.game.log.reversed() {
            if case .play(_, let tile, _) = action { return tile }
        }
        return nil
    }

    private var endChoice: (left: Int, right: Int)? {
        guard controller.pendingTile != nil,
              let left = controller.game.board.leftOpen,
              let right = controller.game.board.rightOpen else { return nil }
        return (left, right)
    }

    private func note(for seat: Int) -> String? {
        switch controller.lastAction(of: seat) {
        case .knock?: return "Knocked"
        case .play(_, let tile, _)?: return "Played \(tile.low)·\(tile.high)"
        case nil: return nil
        }
    }
}

/// Us and Them, with the target underneath.
struct ScoreView: View {
    let match: Match

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 14) {
                score("Us", match.score(of: .us), Theme.us)
                Text("–").foregroundStyle(.tertiary)
                score("Them", match.score(of: .them), Theme.them)
            }
            .font(.headline)
            Text("to \(match.target)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("score")
    }

    private func score(_ name: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).foregroundStyle(.secondary).fontWeight(.regular)
            Text("\(value)").monospacedDigit()
        }
    }
}

/// One of the other players: name, team colour, tiles left and what they did last.
struct SeatChip: View {
    let name: String
    let team: Team
    let tiles: Int
    let isTurn: Bool
    let note: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.color(for: team))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle().strokeBorder(Theme.color(for: team).opacity(0.35), lineWidth: isTurn ? 6 : 0)
                        .frame(width: 16, height: 16)
                }
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            Text("\(tiles)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .frame(minHeight: 28)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .glassPanel(RoundedRectangle(cornerRadius: 16, style: .continuous),
                    tint: isTurn ? Theme.color(for: team).opacity(0.25) : nil)
        .animation(.easeInOut(duration: 0.2), value: isTurn)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("seat-\(name)")
    }
}

/// A soft dimmed backdrop with a card in the middle.
struct Dimmed<Content: View>: View {
    /// False to leave the screen undimmed (so you can still see your tiles).
    var dims = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(dims ? 0.25 : 0).ignoresSafeArea()
            content
                .padding(24)
                .frame(maxWidth: 380)
                .glassPanel(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(24)
                // Undimmed cards sit above the hand so your tiles stay in view.
                .padding(.bottom, dims ? 0 : 120)
        }
        .transition(.opacity)
    }
}

/// Your team leads: choose who plays the first tile.
struct StarterCard: View {
    var onChoose: (Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Your team leads")
                .font(.title3.weight(.semibold))
            Text("Look at your tiles, then choose who plays first. Your partner's tiles stay hidden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button { onChoose(false) } label: {
                    Text("I'll lead").frame(maxWidth: .infinity)
                }
                .prominentGlassButton()
                .accessibilityIdentifier("lead-me")
                Button { onChoose(true) } label: {
                    Text("Partner leads").frame(maxWidth: .infinity)
                }
                .glassButton()
                .accessibilityIdentifier("lead-partner")
            }
            .controlSize(.large)
        }
    }
}

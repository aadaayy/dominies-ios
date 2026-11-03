import SwiftUI

/// The game screen. Phones play sideways; the Duo plays either way.
/// Every layout shows the line of tiles in the middle, your hand along the
/// bottom (your seat), and the other three players placed where they sit:
/// Left on your left, Partner across from you, Right on your right. Each
/// open end of the line shows where the next tile goes and the number it
/// needs, and the last tile played is outlined in its team's colour.
struct GameView: View {
    @Bindable var controller: GameController
    var onExit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            // Sideways phones and the open Duo get the wide layout; upright
            // phones and the folded Duo stack everything.
            let size = geometry.size
            let wide = size.width > size.height * 1.2
            // The folded Duo's screen is much squarer than other iPhones'.
            let screenWidth = size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
            let screenHeight = size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let folded = !wide && screenHeight / max(screenWidth, 1) < 1.6
            ZStack {
                Backdrop()
                if wide {
                    aroundWide(size)
                } else if folded {
                    aroundFolded(size)
                } else {
                    upright(size)
                }
            }
            .frame(width: size.width, height: size.height)
            // Cards float over the table without pushing it around.
            .overlay { overlays(insets: overlayInsets(wide: wide, folded: folded)) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: controller.playCount)
        .onDisappear { controller.stop() }
    }

    private func overlayInsets(wide: Bool, folded: Bool) -> EdgeInsets {
        if wide { return EdgeInsets(top: 0, leading: Self.railWidth, bottom: 0, trailing: Self.railWidth) }
        if folded { return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: Self.sideBarWidth) }
        return EdgeInsets()
    }

    // MARK: - Layouts

    /// Hand tray padding: above the tiles and below them.
    private static let trayPadding: (top: CGFloat, bottom: CGFloat) = (14, 6)
    static let sideBarWidth: CGFloat = 112
    static let railWidth: CGFloat = 80

    /// Upright on a narrow screen (not used on phones, which play sideways,
    /// but kept so the game still works if the screen turns anyway).
    private func upright(_ size: CGSize) -> some View {
        let rows = size.width < 600 ? 2 : 1
        let perRow: CGFloat = rows == 2 ? 5 : 10
        let byWidth = (size.width - 24 - HandView.spacing * (perRow - 1)) / perRow
        let tileWidth = min(rows == 2 ? 40 : 44, byWidth, size.height * 0.055)
        let handHeight = HandView.height(rows: rows, tileWidth: tileWidth) + Self.trayPadding.top + Self.trayPadding.bottom
        return VStack(spacing: 10) {
            topBar
            HStack(spacing: 8) {
                ForEach(others) { EdgeSeat(info: $0, lying: true) }
            }
            .glassGroup()
            table
            statusLine
            hand(rows: rows).frame(height: handHeight)
        }
    }

    /// Sideways: the score and leaving along the top with your partner in
    /// the middle (across from you), Left and Right on the screen's edges
    /// beside the table, and your hand along the bottom, nearest you.
    private func aroundWide(_ size: CGSize) -> some View {
        let handHeight = min(132, max(92, size.height * 0.25))
        return VStack(spacing: 4) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    closeButton
                    ScoreView(match: controller.match, compactRow: true)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .glassPanel(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Your partner sits across from you: top middle.
                EdgeSeat(info: seat(2), lying: true)
                    .fixedSize()
                statusLine
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 40)
            .padding(.horizontal, 8)
            HStack(spacing: 0) {
                EdgeSeat(info: seat(1))
                    .frame(width: Self.railWidth)
                table
                EdgeSeat(info: seat(3))
                    .frame(width: Self.railWidth)
            }
            hand(rows: 1)
                .frame(height: handHeight)
                .padding(.horizontal, Self.railWidth - 12)
        }
    }

    /// The folded Duo: the three other players in a row across the top, in
    /// the order they sit (Left, Partner across, Right), the table and your
    /// hand below, and a bar on the right with leaving, the score and the
    /// game number.
    private func aroundFolded(_ size: CGSize) -> some View {
        let tableWidth = size.width - Self.sideBarWidth
        let handHeight = foldedHandHeight(tableWidth: tableWidth, height: size.height)
        return HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    EdgeSeat(info: seat(1))
                    Spacer(minLength: 0)
                    EdgeSeat(info: seat(2))
                    Spacer(minLength: 0)
                    EdgeSeat(info: seat(3))
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                table
                statusLine
                hand(rows: 2).frame(height: handHeight)
            }
            .frame(width: tableWidth)
            sideBar
                .frame(width: Self.sideBarWidth)
        }
    }

    private func foldedHandHeight(tableWidth: CGFloat, height: CGFloat) -> CGFloat {
        let byWidth = (tableWidth - 24 - HandView.spacing * 4) / 5
        let tileWidth = min(40, byWidth, height * 0.055)
        return HandView.height(rows: 2, tileWidth: tileWidth) + Self.trayPadding.top + Self.trayPadding.bottom
    }

    private var sideBar: some View {
        VStack(spacing: 12) {
            HStack { closeButton; Spacer(minLength: 0) }
            ScoreView(match: controller.match, stacked: true)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .glassPanel(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Game \(controller.match.gameNumber)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
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

    /// The three other players, in seat order: Left, Partner, Right.
    private var others: [SeatInfo] { [1, 2, 3].map(seat) }

    private func seat(_ seat: Int) -> SeatInfo {
        SeatInfo(seat: seat,
                 name: controller.names[seat],
                 team: Team.of(seat: seat),
                 tiles: controller.game.hands[seat].count,
                 isTurn: controller.phase == .playing && !controller.game.isOver && controller.game.current == seat,
                 last: controller.lastAction(of: seat))
    }

    private var table: some View {
        TableView(board: controller.game.board,
                  lastTile: lastPlay?.tile,
                  lastColor: lastPlay.map { Theme.color(for: Team.of(seat: $0.seat)) } ?? .accentColor,
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                let tray = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                Color.clear
                    .glassPanel(tray, tint: controller.isYourTurn ? Theme.us.opacity(0.12) : nil)
                    .overlay {
                        // Your turn: the tray, which is your seat, lights up in your team's colour.
                        tray.strokeBorder(Theme.us.opacity(controller.isYourTurn ? 0.8 : 0), lineWidth: 2)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .animation(.easeInOut(duration: 0.2), value: controller.isYourTurn)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hand")
    }

    @ViewBuilder
    private func overlays(insets: EdgeInsets) -> some View {
        switch controller.phase {
        case .choosingStarter:
            // Sideways, the card sits over the table, clear of the players.
            Dimmed(dims: false, insets: insets) {
                StarterCard(onChoose: { controller.lead(withPartner: $0) })
            }
        case .gameOver, .matchOver:
            if let result = controller.game.result {
                Dimmed {
                    ResultCard(result: result,
                               game: controller.game,
                               match: controller.match,
                               names: controller.names,
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

    /// The tile played last and who played it.
    private var lastPlay: (tile: Tile, seat: Int)? {
        for action in controller.game.log.reversed() {
            if case .play(let seat, let tile, _) = action { return (tile, seat) }
        }
        return nil
    }

    private var endChoice: (left: Int, right: Int)? {
        guard controller.pendingTile != nil,
              let left = controller.game.board.leftOpen,
              let right = controller.game.board.rightOpen else { return nil }
        return (left, right)
    }
}

/// Us and Them, with the target underneath.
struct ScoreView: View {
    let match: Match
    /// Us over Them, for the folded Duo's side bar.
    var stacked = false
    /// One short line, for the sideways top bar.
    var compactRow = false

    var body: some View {
        if compactRow {
            // On a small phone, the target and then the team names step
            // aside (the colours still say which is which).
            ViewThatFits(in: .horizontal) {
                compactLine(names: true, target: true)
                compactLine(names: true, target: false)
                compactLine(names: false, target: false)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("score")
        } else if stacked {
            VStack(alignment: .leading, spacing: 4) {
                score("Us", match.score(of: .us), Theme.us)
                score("Them", match.score(of: .them), Theme.them)
                Text("to \(match.target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("score")
        } else {
            row
        }
    }

    private var row: some View {
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

    private func compactLine(names: Bool, target: Bool) -> some View {
        HStack(spacing: 10) {
            score(names ? "Us" : nil, match.score(of: .us), Theme.us)
            score(names ? "Them" : nil, match.score(of: .them), Theme.them)
            if target {
                Text("to \(match.target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
    }

    private func score(_ name: String?, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            if let name { Text(name).foregroundStyle(.secondary).fontWeight(.regular) }
            Text("\(value)").monospacedDigit()
        }
    }
}

/// A soft dimmed backdrop with a card in the middle.
struct Dimmed<Content: View>: View {
    /// False to leave the screen undimmed (so you can still see your tiles).
    var dims = true
    /// Room to leave for the players' column or side bar.
    var insets = EdgeInsets()
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
                .padding(insets)
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

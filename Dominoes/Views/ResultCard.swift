import SwiftUI

/// The end of a game: who won, why, the points, and everyone's leftover tiles.
struct ResultCard: View {
    let result: GameResult
    let game: Game
    let match: Match
    /// Who sits where, by seat: "You" first. Online, friends' first names.
    var names: [String] = GameController.names
    let isMatchOver: Bool
    var onNext: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("result-title")
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                ForEach([2, 1, 3, 0], id: \.self) { seat in
                    leftovers(seat)
                }
            }

            ScoreView(match: match)

            if isMatchOver {
                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .prominentGlassButton()
                .controlSize(.large)
                .accessibilityIdentifier("done")
            } else {
                Button(action: onNext) {
                    Text("Next game").frame(maxWidth: .infinity)
                }
                .prominentGlassButton()
                .controlSize(.large)
                .accessibilityIdentifier("next-game")
            }
        }
    }

    private var title: String {
        if isMatchOver {
            return match.winner == .us ? "You won the match" : "They won the match"
        }
        switch result.winner {
        case .us?: return "You won the game"
        case .them?: return "They won the game"
        case nil: return "Blocked, it's a tie"
        }
    }

    private var detail: String {
        switch result.kind {
        case .domino(let seat):
            let who = seat == 0 ? "You" : names[seat]
            return "\(who) went out. \(points)"
        case .blocked:
            return "Nobody could play. Us \(result.usPips), Them \(result.themPips) left. \(points)"
        case .tie:
            return "Nobody could play and both teams held \(result.usPips). No points; play again."
        }
    }

    private var points: String {
        guard let winner = result.winner else { return "" }
        return "\(winner == .us ? "Us" : "Them") +\(result.points)"
    }

    private func leftovers(_ seat: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.color(for: Team.of(seat: seat))).frame(width: 6, height: 6)
            Text(names[seat])
                .font(.footnote.weight(.medium))
                .frame(width: 58, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(game.hands[seat]) { tile in
                    DominoView(first: tile.low, second: tile.high, isVertical: false)
                        .frame(width: 30, height: 15)
                }
            }
            Spacer(minLength: 0)
            Text("\(game.pips(of: seat))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

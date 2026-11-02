import SwiftUI

/// The first screen: the name, two settings and a big Play button, with the
/// account badge in the corner.
struct HomeView: View {
    @AppStorage("target") private var target = 100
    @AppStorage("level") private var levelName = BotLevel.normal.rawValue
    var onPlay: (Int, BotLevel) -> Void
    var onAccount: () -> Void = {}

    private var level: BotLevel { BotLevel(rawValue: levelName) ?? .normal }

    var body: some View {
        GeometryReader { geometry in
            // Sideways phones and the open Duo: the name on the left, the
            // settings and Play on the right, so it all fits without scrolling.
            let wide = geometry.size.width > geometry.size.height * 1.2
            ZStack {
                Backdrop()
                if wide {
                    HStack(spacing: 48) {
                        title
                            .frame(maxWidth: .infinity)
                        controls
                            .frame(maxWidth: 420)
                    }
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 32) {
                        Spacer(minLength: 0)
                        title
                        controls
                            .frame(maxWidth: 440)
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .topTrailing) {
                AccountBadge(action: onAccount)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
    }

    private var title: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                DominoView(first: 6, second: 3, isVertical: true)
                    .frame(width: 34, height: 68)
                    .rotationEffect(.degrees(-8))
                DominoView(first: 9, second: 9, isVertical: true)
                    .frame(width: 34, height: 68)
                    .rotationEffect(.degrees(6))
            }
            VStack(spacing: 4) {
                Text("Dominoes")
                    .font(.largeTitle.weight(.bold))
                Text("Double Nine · Partners")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 24) {
            VStack(spacing: 0) {
                row("Play to") {
                    Picker("Play to", selection: $target) {
                        ForEach(Match.targets, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
                Divider().padding(.leading, 16)
                row("Opponents") {
                    Picker("Opponents", selection: $levelName) {
                        ForEach(BotLevel.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
            .glassPanel(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button {
                onPlay(target, level)
            } label: {
                Text("Play")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .prominentGlassButton()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityIdentifier("play")

            Text("You and your partner against two computer players.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

import SwiftUI

/// The first screen: the name, two settings and a big Play button.
struct HomeView: View {
    @AppStorage("target") private var target = 100
    @AppStorage("level") private var levelName = BotLevel.normal.rawValue
    var onPlay: (Int, BotLevel) -> Void

    private var level: BotLevel { BotLevel(rawValue: levelName) ?? .normal }

    var body: some View {
        ZStack {
            Theme.table.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer(minLength: 0)
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
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 440)

                Button {
                    onPlay(target, level)
                } label: {
                    Text("Play")
                        .font(.headline)
                        .frame(maxWidth: 440)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityIdentifier("play")

                Text("You and your partner against two computer players.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(24)
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

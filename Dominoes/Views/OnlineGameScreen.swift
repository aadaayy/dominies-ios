import SwiftUI

/// A game with friends: the same table as against the computer, plus what
/// only happens online: a friend who stopped answering, a lost connection,
/// and a room that was ended while you were in it.
struct OnlineGameScreen: View {
    let controller: GameController
    /// Back to Play with Friends.
    var onExit: () -> Void

    @State private var askingToLeave = false

    var body: some View {
        GameView(controller: controller, onExit: exit)
            .overlay(alignment: .top) {
                // Below the row of seats and scores along the top, so the
                // banner never hides who's playing. On the folded Duo it stays
                // over the table, clear of the score column on the right.
                GeometryReader { geometry in
                    let wide = geometry.size.width > geometry.size.height * 1.2
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        banners
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, wide ? 60 : 92)
                    .padding(.horizontal, 12)
                    .padding(.trailing, wide ? 0 : GameView.sideBarWidth)
                }
            }
            .overlay {
                if controller.isClosed {
                    Dimmed {
                        ClosedRoomCard(onDone: onExit)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: controller.isClosed)
            .confirmationDialog("Leave this game?", isPresented: $askingToLeave, titleVisibility: .visible) {
                Button("Come back later") { onExit() }
                    .accessibilityIdentifier("leave-later")
                Button("Leave for good", role: .destructive) {
                    Task { await controller.leave(); onExit() }
                }
                if controller.isHost {
                    Button("End it for everyone", role: .destructive) {
                        Task { await controller.disband(); onExit() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Coming back later keeps your seat; the game waits for you on your turn. Leaving for good gives your tiles to a computer.")
            }
            .onDisappear { controller.stop() }
    }

    private func exit() {
        // A finished match: nothing to keep, so just go (the room is deleted
        // once the last person leaves).
        if controller.phase == .matchOver || controller.isClosed {
            Task { await controller.leave() }
            onExit()
        } else {
            askingToLeave = true
        }
    }

    @ViewBuilder
    private var banners: some View {
        if controller.isClosed {
            EmptyView()
        } else if let problem = controller.problem {
            banner {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                Text(problem)
                    .font(.subheadline)
                Button {
                    controller.dismissProblem()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        } else if let seat = controller.stalledSeat {
            banner {
                Text("\(controller.names[seat]) hasn't played for a minute")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Let a computer play") { controller.replaceStalledPlayer() }
                    .prominentGlassButton()
                    .controlSize(.small)
                    .accessibilityIdentifier("replace-stalled")
            }
        }
    }

    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(minHeight: 40)
            .glassPanel(Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

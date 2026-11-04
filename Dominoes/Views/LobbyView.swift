import SwiftUI

/// A game waiting to start: its code to share, the four seats around the
/// table (you at the bottom, your partner across, the other team at your
/// left and right), invites, and the host's options and Start button. Empty
/// seats get a computer player when the game starts.
struct LobbyView: View {
    let model: LobbyModel
    let friends: FriendsModel?
    /// Back to Play with Friends; the room stays and shows under Your games.
    var onBack: () -> Void
    /// You left (or ended) the room.
    var onLeft: () -> Void

    @State private var inviting = false
    @State private var confirmingLeave = false

    private var state: OnlineState { model.state }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height * 1.2
            ZStack(alignment: .top) {
                Backdrop()
                VStack(spacing: 0) {
                    TopBar(title: state.isHost ? "Your game" : "\(state.hostName.map(OnlineJSON.firstName) ?? "A friend")'s game",
                           onBack: onBack) {
                        Button(state.isHost ? "End game" : "Leave", role: .destructive) { confirmingLeave = true }
                            .glassButton()
                            .accessibilityIdentifier(state.isHost ? "disband-room" : "leave-room")
                    }
                    if wide {
                        HStack(alignment: .top, spacing: 28) {
                            ScrollView {
                                VStack(spacing: 14) {
                                    controls(start: false)
                                    if state.isHost { noteText }
                                }
                                .padding(.bottom, 12)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .frame(maxWidth: 330)
                            // Start sits under the seats and the note beside
                            // them, so both columns fit a sideways Pro.
                            VStack(spacing: 14) {
                                seatsTable(cardWidth: 136)
                                startArea(note: false)
                                    .frame(maxWidth: 330)
                            }
                            .frame(maxWidth: 520, maxHeight: .infinity)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        .frame(maxWidth: 920)
                    } else {
                        ScrollView {
                            VStack(spacing: 20) {
                                // Narrow screens (the folded Duo) shrink the side seats so the
                                // table never runs off the right edge.
                                seatsTable(cardWidth: max(84, min(136, (min(geometry.size.width, 520) - 40 - 96 - 24) / 2)))
                                controls(start: true)
                            }
                            .frame(maxWidth: 520)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                if model.closed {
                    Dimmed {
                        ClosedRoomCard(onDone: onLeft)
                    }
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: $inviting) {
            InviteSheet(model: model, friends: friends)
        }
        .confirmationDialog(state.isHost ? "End this game for everyone?" : "Leave this game?",
                            isPresented: $confirmingLeave, titleVisibility: .visible) {
            if state.isHost {
                Button("End game", role: .destructive) {
                    Task { await model.disband(); onLeft() }
                }
            } else {
                Button("Leave", role: .destructive) {
                    Task { await model.leave(); onLeft() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(state.isHost ? "The room is deleted and everyone in it goes back to their games."
                              : "You can join again with the code while it hasn't started.")
        }
    }

    // MARK: - Code, options, Start

    /// The game code and options, and Start too when `start` (otherwise
    /// it goes under the seats).
    private func controls(start: Bool) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Game code")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(state.code)
                    .font(.largeTitle.weight(.semibold).monospaced())
                    .kerning(3)
                    .accessibilityIdentifier("lobby-code")
                HStack(spacing: 10) {
                    Button {
                        inviting = true
                    } label: {
                        Label("Invite", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton()
                    .accessibilityIdentifier("invite-friends")
                    ShareLink(item: "Play dominoes with me. Open Dominoes, tap Play with Friends and join with the code \(state.code).") {
                        Label("Share code", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton()
                    .accessibilityIdentifier("share-code")
                }
                .font(.subheadline.weight(.medium))
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassPanel(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if state.isHost {
                VStack(spacing: 0) {
                    optionRow("Play to") {
                        Picker("Play to", selection: Binding(
                            get: { state.target },
                            set: { model.setOptions(target: $0, level: BotLevel(rawValue: state.level) ?? .normal) })) {
                            ForEach(Match.targets, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                    }
                    Divider().padding(.leading, 16)
                    optionRow("Computers") {
                        Picker("Computers", selection: Binding(
                            get: { BotLevel(rawValue: state.level) ?? .normal },
                            set: { model.setOptions(target: state.target, level: $0) })) {
                            ForEach(BotLevel.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                    }
                }
                .glassPanel(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .disabled(model.busy)
            } else {
                Text("Play to \(state.target) · \((BotLevel(rawValue: state.level) ?? .normal).title) computers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("lobby-options")
            }

            if let problem = model.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if start { startArea(note: true) }
        }
    }

    /// Start and the computer-seat note for the host; for a guest, who
    /// they're waiting on.
    @ViewBuilder
    private func startArea(note: Bool) -> some View {
        if state.isHost {
            Button {
                model.startGame()
            } label: {
                Text("Start game")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .prominentGlassButton()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(model.busy)
            .accessibilityIdentifier("start-game")
            if note { noteText }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                Text("Waiting for \(state.hostName.map(OnlineJSON.firstName) ?? "the host") to start")
                    .accessibilityIdentifier("lobby-waiting")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private var noteText: some View {
        Text(computerNote)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var computerNote: String {
        let empty = state.computerSeats.count
        switch empty {
        case 0: return "Everyone's here."
        case 1: return "A computer plays the empty seat."
        default: return "Computers play the \(empty) empty seats."
        }
    }

    private func optionRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - The table

    /// You at the bottom, your partner at the top, the other team on your
    /// left and right, the way they'll sit in the game.
    private func seatsTable(cardWidth: CGFloat) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                seatCard(2, width: cardWidth)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                seatCard(1, width: cardWidth)
                tableMiddle
                seatCard(3, width: cardWidth)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                seatCard(0, width: cardWidth)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tableMiddle: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                DominoView(first: 9, second: 9, isVertical: true)
                    .frame(width: 16, height: 32)
                DominoView(first: 6, second: 3, isVertical: true)
                    .frame(width: 16, height: 32)
            }
            Text("Play to \(state.target)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 96, height: 72)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.secondary.opacity(0.25), lineWidth: 0.5))
    }

    private func seatCard(_ local: Int, width: CGFloat) -> some View {
        let seat = model.seat(local)
        let team = Team.of(seat: local)
        let person = seat?.person == true
        let name = local == 0 ? "You" : (person ? seat?.name.map(OnlineJSON.firstName) ?? "Player" : "Open seat")
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(Theme.color(for: team)).frame(width: 7, height: 7)
                Text(Seat.names[local] == "You" ? "Your seat" : Seat.names[local])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.color(for: team))
            }
            HStack(spacing: 5) {
                // Their picture (or initials), as on their account.
                if person {
                    AvatarView(player: Player(id: seat?.name ?? "", name: seat?.name ?? "Player", email: nil,
                                              avatarURL: seat?.picture), size: 20)
                }
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(person || local == 0 ? .primary : .secondary)
            }
            .padding(.horizontal, 6)
            if person {
                Text(seat?.host == true ? "Host" : (team == .us ? "Your partner" : "Other team"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(local == 0 ? 0 : 1)
            } else if local != 0 {
                Button("Sit here") { model.sit(atLocal: local) }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                    .disabled(model.busy)
                    .accessibilityIdentifier("sit-\(Seat.names[local].lowercased())")
            }
        }
        .frame(width: width, height: 72)
        .glassPanel(RoundedRectangle(cornerRadius: 18, style: .continuous),
                    tint: person || local == 0 ? Theme.color(for: team).opacity(0.10) : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lobby-seat-\(Seat.names[local].lowercased())")
    }
}

/// Pick friends to invite to the game; they see it on their Play with
/// Friends page.
struct InviteSheet: View {
    let model: LobbyModel
    let friends: FriendsModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let list = friends?.home?.friends ?? []
                if list.isEmpty {
                    Text("Add friends with their friend code on the Play with Friends page, or share the game code.")
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { friend in
                    HStack(spacing: 12) {
                        AvatarView(player: Player(id: friend.id, name: friend.name, email: nil, avatarURL: friend.picture), size: 32)
                        Text(friend.name)
                        Spacer()
                        if inGame(friend) {
                            Text("Here")
                                .foregroundStyle(.secondary)
                        } else if model.invited.contains(friend.id) {
                            Label("Invited", systemImage: "checkmark")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Invite") { model.invite(friend) }
                                .buttonStyle(.borderless)
                                .disabled(model.busy)
                                .accessibilityIdentifier("invite-\(OnlineJSON.firstName(friend.name))")
                        }
                    }
                }
                Section {
                    ShareLink(item: "Play dominoes with me. Open Dominoes, tap Play with Friends and join with the code \(model.state.code).") {
                        Label("Share the game code \(model.state.code)", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("invite-done")
                }
            }
        }
        .task { await friends?.load() }
    }

    private func inGame(_ friend: OnlineFriend) -> Bool {
        model.state.seats.contains { $0.person && !$0.you && $0.name == friend.name }
    }
}

/// The room is gone: the host ended it, or everyone left.
struct ClosedRoomCard: View {
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("This game was ended")
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("room-closed")
            Text("The host ended it for everyone, or everyone else left.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onDone) {
                Text("Back to your games").frame(maxWidth: .infinity)
            }
            .prominentGlassButton()
            .controlSize(.large)
            .accessibilityIdentifier("room-closed-ok")
        }
    }
}

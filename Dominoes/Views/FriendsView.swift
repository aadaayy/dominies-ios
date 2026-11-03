import SwiftUI

/// Play with Friends: start a game, join one with its code, answer invites,
/// go back to games you're in, and keep a list of friends added by their
/// friend codes. Signed out, it asks you to sign in first.
struct FriendsView: View {
    /// Nil when this copy of the app has no game server set up.
    let model: FriendsModel?
    var onBack: () -> Void
    var onAccount: () -> Void
    /// A game to show: its lobby before the start, the table after.
    var onOpenGame: (OnlineState) -> Void

    @Environment(AccountSession.self) private var account
    @AppStorage("target") private var target = 100
    @AppStorage("level") private var levelName = BotLevel.normal.rawValue
    @State private var joinCode = ""
    @State private var friendCode = ""
    @State private var name = ""
    @State private var added: String?
    @FocusState private var focus: Field?

    private enum Field { case join, friend, name }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height * 1.2
            ZStack(alignment: .top) {
                Backdrop()
                VStack(spacing: 0) {
                    TopBar(title: "Play with Friends", onBack: onBack) {
                        if model != nil && account.player != nil && model?.loading == true {
                            ProgressView().controlSize(.small)
                        }
                    }
                    content(wide: wide)
                }
            }
        }
        .task(id: "\(account.player?.id ?? "")-\(model != nil)") {
            guard account.player != nil else { return }
            await model?.watch()
        }
        .onChange(of: model?.home?.name) { _, newValue in
            if name.isEmpty, let newValue { name = newValue }
        }
    }

    @ViewBuilder
    private func content(wide: Bool) -> some View {
        if account.player == nil && account.isSetUp {
            message(title: "Sign in to play with friends",
                    detail: "Friends find you by your friend code and invite you to their games. Playing the computer never needs an account.") {
                Button(action: onAccount) {
                    Text("Sign in").frame(maxWidth: 240)
                }
                .prominentGlassButton()
                .controlSize(.large)
                .accessibilityIdentifier("friends-sign-in")
            }
        } else if let model, account.player != nil {
            if let home = model.home {
                signedIn(model: model, home: home, wide: wide)
            } else if let problem = model.problem {
                message(title: "Couldn't load your games", detail: problem) {
                    Button("Try again") { Task { await model.load() } }
                        .prominentGlassButton()
                        .controlSize(.large)
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else {
            message(title: "Not set up yet",
                    detail: "Games with friends need the game server, which isn't set up in this copy of the app.") {
                EmptyView()
            }
        }
    }

    private func message<Actions: View>(title: String, detail: String,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "person.2.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.us)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            actions()
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Signed in

    @ViewBuilder
    private func signedIn(model: FriendsModel, home: OnlineHome, wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    startColumn(model: model, home: home)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: 340)
                ScrollView {
                    listColumn(model: model, home: home)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: 520)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .padding(.horizontal, 24)
            .frame(maxWidth: 920)
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    startColumn(model: model, home: home)
                    listColumn(model: model, home: home)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// New game, join with a code, and your own friend code.
    private func startColumn(model: FriendsModel, home: OnlineHome) -> some View {
        VStack(spacing: 14) {
            if model.needsName {
                nameCard(model: model)
            }
            if let problem = model.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("friends-problem")
            }

            Button {
                Task {
                    let level = BotLevel(rawValue: levelName) ?? .normal
                    if let state = await model.run({ try await $0.createGame(target: target, level: level) }) {
                        onOpenGame(state)
                    }
                }
            } label: {
                Label("New game", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .prominentGlassButton()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(model.busy || model.needsName)
            .accessibilityIdentifier("new-game")

            HStack(spacing: 10) {
                TextField("Game code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .focused($focus, equals: .join)
                    .submitLabel(.join)
                    .onSubmit { join(model: model) }
                    .onChange(of: joinCode) { _, value in
                        let clean = OnlineJSON.cleanCode(value)
                        if clean != value { joinCode = clean }
                    }
                    .accessibilityIdentifier("join-code")
                Button("Join") { join(model: model) }
                    .glassButton()
                    .disabled(joinCode.count < 6 || model.busy || model.needsName)
                    .accessibilityIdentifier("join")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassPanel(Capsule())

            VStack(spacing: 6) {
                Text("Your friend code")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(home.friendCode)
                    .font(.title.weight(.semibold).monospaced())
                    .kerning(2)
                    .accessibilityIdentifier("my-friend-code")
                Text("Friends add you with it, then invite you to games.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(item: "Add me on Dominoes. My friend code is \(home.friendCode).") {
                    Label("Share my code", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                }
                .glassButton()
                .padding(.top, 4)
                .accessibilityIdentifier("share-friend-code")
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassPanel(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.top, 4)
    }

    private func nameCard(model: FriendsModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose your name")
                .font(.headline)
            Text("Friends see it at the table and on your invites.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("Your name", text: $name)
                    .textContentType(.givenName)
                    .focused($focus, equals: .name)
                    .submitLabel(.done)
                    .onSubmit { saveName(model: model) }
                    .accessibilityIdentifier("name-field")
                Button("Save") { saveName(model: model) }
                    .prominentGlassButton()
                    .disabled(OnlineJSON.nameProblem(name) != nil || model.busy)
                    .accessibilityIdentifier("save-name")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.surface))
        }
        .padding(16)
        .glassPanel(RoundedRectangle(cornerRadius: 24, style: .continuous), tint: Theme.us.opacity(0.12))
    }

    /// Invites, games you're in, and friends.
    private func listColumn(model: FriendsModel, home: OnlineHome) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !home.invites.isEmpty {
                section("Invites") {
                    ForEach(home.invites) { invite in
                        inviteRow(invite, model: model)
                        if invite != home.invites.last { Divider().padding(.leading, 16) }
                    }
                }
            }
            if !home.games.isEmpty {
                section("Your games") {
                    ForEach(home.games) { game in
                        gameRow(game, model: model)
                        if game != home.games.last { Divider().padding(.leading, 16) }
                    }
                }
            }
            section("Friends") {
                addFriendRow(model: model)
                if let added {
                    Text("Added \(added).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                if home.friends.isEmpty {
                    Divider().padding(.leading, 16)
                    Text("No friends yet. Add one with their friend code, or share yours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
                ForEach(home.friends) { friend in
                    Divider().padding(.leading, 16)
                    friendRow(friend, model: model)
                }
            }
        }
        .padding(.top, 4)
    }

    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            VStack(spacing: 0) { rows() }
                .glassPanel(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func inviteRow(_ invite: OnlineInvite, model: FriendsModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(invite.from) invited you")
                    .font(.body.weight(.medium))
                Text(Self.list(invite.players.map(OnlineJSON.firstName), prefix: "With "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("No thanks") {
                Task { await model.run { try await $0.declineInvite(gameID: invite.gameId) } }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("decline-\(invite.code)")
            Button("Join") {
                Task {
                    if let state = await model.run({ try await $0.joinGame(code: invite.code) }) {
                        onOpenGame(state)
                    }
                }
            }
            .prominentGlassButton()
            .disabled(model.busy || model.needsName)
            .accessibilityIdentifier("join-\(invite.code)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func gameRow(_ game: OnlineGameSummary, model: FriendsModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.players.isEmpty ? "You and computers" : Self.list(game.players.map(OnlineJSON.firstName), prefix: "With "))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(Self.detail(game))
                    .font(.footnote)
                    .foregroundStyle(game.yourTurn ? AnyShapeStyle(Theme.us) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 8)
            Button(game.phase == .lobby ? "Open" : "Play") {
                Task {
                    if let state = await model.run({ try await $0.state(gameID: game.id) }) {
                        onOpenGame(state)
                    }
                }
            }
            .glassButton()
            .disabled(model.busy)
            .accessibilityIdentifier("open-\(game.code)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func addFriendRow(model: FriendsModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .foregroundStyle(Theme.us)
            TextField("Friend code", text: $friendCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .focused($focus, equals: .friend)
                .submitLabel(.done)
                .onSubmit { addFriend(model: model) }
                .onChange(of: friendCode) { _, value in
                    let clean = OnlineJSON.cleanCode(value)
                    if clean != value { friendCode = clean }
                }
                .accessibilityIdentifier("friend-code")
            Button("Add") { addFriend(model: model) }
                .glassButton()
                .disabled(friendCode.count < 6 || model.busy)
                .accessibilityIdentifier("add-friend")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func friendRow(_ friend: OnlineFriend, model: FriendsModel) -> some View {
        HStack(spacing: 12) {
            AvatarView(player: Player(id: friend.id, name: friend.name, email: nil, avatarURL: friend.picture), size: 32)
            Text(friend.name)
            Spacer()
            Menu {
                Button("Remove \(OnlineJSON.firstName(friend.name))", role: .destructive) {
                    Task { await model.run { try await $0.removeFriend(id: friend.id) } }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(friend.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("friend-\(friend.name)")
    }

    // MARK: - Actions

    private func join(model: FriendsModel) {
        guard joinCode.count == 6 else { return }
        let code = joinCode
        focus = nil
        Task {
            if let state = await model.run({ try await $0.joinGame(code: code) }) {
                joinCode = ""
                onOpenGame(state)
            }
        }
    }

    private func addFriend(model: FriendsModel) {
        guard friendCode.count == 6 else { return }
        let code = friendCode
        focus = nil
        Task {
            if let friend = await model.run({ try await $0.addFriend(code: code) }) {
                friendCode = ""
                added = friend.name
            }
        }
    }

    private func saveName(model: FriendsModel) {
        guard OnlineJSON.nameProblem(name) == nil else { return }
        let chosen = name
        focus = nil
        Task { await model.run { try await $0.setName(chosen) } }
    }

    // MARK: - Words

    /// "With Sam and Jordan", "With Sam, Jordan and Taylor".
    static func list(_ names: [String], prefix: String = "") -> String {
        switch names.count {
        case 0: return ""
        case 1: return prefix + names[0]
        default: return prefix + names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    static func detail(_ game: OnlineGameSummary) -> String {
        switch game.phase {
        case .lobby:
            return game.isHost ? "Waiting for you to start" : "Waiting for the host to start"
        case .choosing, .playing:
            let score = "Us \(game.usScore), Them \(game.themScore)"
            return game.yourTurn ? "Your turn · \(score)" : "Game \(game.gameNumber) · \(score)"
        case .over:
            return "Game \(game.gameNumber) ended · Us \(game.usScore), Them \(game.themScore)"
        case .matchOver, .closed:
            return "Finished"
        }
    }
}

/// A back button and a title along the top of a page.
struct TopBar<Trailing: View>: View {
    let title: String
    var onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .glassPanel(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("back")
            .accessibilityLabel("Back")
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}


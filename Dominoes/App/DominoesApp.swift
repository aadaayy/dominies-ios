import SwiftUI

@main
struct DominoesApp: App {
    @State private var account = AccountSession.make()

    var body: some Scene {
        WindowGroup {
            Group {
                if let size = LaunchOptions.current.previewSize {
                    ScreenPreview(screen: size) { RootView() }
                } else {
                    RootView()
                }
            }
            .environment(account)
            .task { await account.refresh() }
        }
    }
}

/// Home, the account page, Play with Friends, a game's lobby, or a match
/// in progress (against the computer or with friends).
struct RootView: View {
    @Environment(AccountSession.self) private var account
    @State private var controller: GameController?
    @State private var lobby: LobbyModel?
    @State private var friends: FriendsModel?
    @State private var showingAccount = false
    @State private var showingFriends = false
    private let options = LaunchOptions.current

    private enum Screen: Equatable { case home, account, friends, lobby, game }

    private var screen: Screen {
        if controller != nil { return .game }
        if lobby != nil { return .lobby }
        if showingAccount { return .account }
        if showingFriends { return .friends }
        return .home
    }

    var body: some View {
        ZStack {
            switch screen {
            case .game:
                if let controller {
                    if controller.isOnline {
                        OnlineGameScreen(controller: controller, onExit: closeGame)
                            .transition(.opacity)
                    } else {
                        GameView(controller: controller, onExit: closeGame)
                            .transition(.opacity)
                    }
                }
            case .lobby:
                if let lobby {
                    LobbyView(model: lobby, friends: friends,
                              onBack: closeLobby, onLeft: closeLobby)
                        .transition(.opacity)
                }
            case .account:
                AccountView(onClose: { showingAccount = false })
                    .transition(.opacity)
            case .friends:
                FriendsView(model: friends,
                            onBack: { showingFriends = false },
                            onAccount: { showingAccount = true },
                            onOpenGame: open)
                    .transition(.opacity)
            case .home:
                HomeView(onPlay: start,
                         onFriends: { showingFriends = true },
                         onAccount: { showingAccount = true },
                         invites: account.player == nil ? 0 : friends?.invites.count ?? 0)
                    .transition(.opacity)
                    .task(id: "\(account.player?.id ?? "")-\(friends != nil)") {
                        guard account.player != nil else { return }
                        await friends?.watch()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .onAppear {
            if friends == nil, let online = account.online { friends = FriendsModel(service: online) }
            if options.startGame && controller == nil {
                start(target: 100, level: .normal)
            }
            if options.openFriends { showingFriends = true }
        }
    }

    private func start(target: Int, level: BotLevel) {
        controller = GameController(target: target, level: level, options: options)
    }

    /// A game with friends: the lobby until the host starts it, then the table.
    private func open(_ state: OnlineState) {
        guard let service = account.online else { return }
        if state.phase == .lobby {
            let model = LobbyModel(state: state, service: service)
            model.onStarted = { started in
                controller = GameController(online: started, service: service, options: options)
                lobby = nil
            }
            lobby = model
        } else {
            controller = GameController(online: state, service: service, options: options)
        }
    }

    private func closeGame() {
        controller?.stop()
        withAnimation { controller = nil }
        if let friends { Task { await friends.load() } }
    }

    private func closeLobby() {
        lobby?.stop()
        lobby = nil
        if let friends { Task { await friends.load() } }
    }
}

/// The app drawn at another phone's screen size, shrunk to fit whatever
/// simulator runs it. The automatic checks can't unfold the Duo simulator,
/// so they use this to show the open Duo (about 951 by 669 points) and the
/// smallest iPhone. Used only with -openDuoPreview or -previewSize.
struct ScreenPreview<Content: View>: View {
    let screen: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / screen.width, geometry.size.height / screen.height)
            content
                .padding(.top, 8)
                .frame(width: screen.width, height: screen.height)
                .clipped()
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

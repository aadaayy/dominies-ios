import SwiftUI
import UIKit

@main
struct DominoesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

/// Home, the account page, or a match in progress.
struct RootView: View {
    @State private var controller: GameController?
    @State private var showingAccount = false
    private let options = LaunchOptions.current

    var body: some View {
        ZStack {
            if let controller {
                GameView(controller: controller, onExit: { withAnimation { self.controller = nil } })
                    .transition(.opacity)
            } else if showingAccount {
                AccountView(onClose: { showingAccount = false })
                    .transition(.opacity)
            } else {
                HomeView(onPlay: start, onAccount: { showingAccount = true })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller == nil)
        .animation(.easeInOut(duration: 0.25), value: showingAccount)
        .onAppear {
            if options.startGame && controller == nil {
                start(target: 100, level: .normal)
            }
        }
    }

    private func start(target: Int, level: BotLevel) {
        controller = GameController(target: target, level: level, options: options)
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

/// Regular iPhones play sideways only: there isn't room upright to show who
/// sits where around the table. The iPhone Duo turns freely (folded it's
/// nearly square, and open it's already wide).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.isRegularPhone ? .landscape : .allButUpsideDown
    }

    /// A long, narrow screen (about 2 to 1): every iPhone but the Duo.
    static let isRegularPhone: Bool = {
        let bounds = UIScreen.main.bounds
        let long = max(bounds.width, bounds.height), short = min(bounds.width, bounds.height)
        return long / max(short, 1) > 1.7
    }()
}

import SwiftUI

@main
struct DominoesApp: App {
    var body: some Scene {
        WindowGroup {
            if LaunchOptions.current.openDuoPreview {
                OpenDuoPreview { RootView() }
            } else {
                RootView()
            }
        }
    }
}

/// Home, or a match in progress.
struct RootView: View {
    @State private var controller: GameController?
    private let options = LaunchOptions.current

    var body: some View {
        ZStack {
            if let controller {
                GameView(controller: controller, onExit: { withAnimation { self.controller = nil } })
                    .transition(.opacity)
            } else {
                HomeView(onPlay: start)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller == nil)
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

/// The app drawn at the size of the open iPhone Duo's screen (about 951 by 669
/// points), shrunk to fit whatever simulator runs it. The automatic checks
/// can't unfold the Duo simulator, so they screenshot this to show the open
/// layout. Used only when the app is launched with -openDuoPreview.
struct OpenDuoPreview<Content: View>: View {
    static var openScreen: CGSize { CGSize(width: 951, height: 669) }
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Self.openScreen.width, geometry.size.height / Self.openScreen.height)
            content
                .frame(width: Self.openScreen.width, height: Self.openScreen.height)
                .environment(\.horizontalSizeClass, .regular)
                .environment(\.verticalSizeClass, .regular)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

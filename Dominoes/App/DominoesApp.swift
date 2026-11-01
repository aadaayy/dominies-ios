import SwiftUI

@main
struct DominoesApp: App {
    var body: some Scene {
        WindowGroup {
            if let size = LaunchOptions.current.previewSize {
                ScreenPreview(screen: size) { RootView() }
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

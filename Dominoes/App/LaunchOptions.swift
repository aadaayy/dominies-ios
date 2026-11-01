import Foundation

/// Settings the automatic checks pass when they launch the app, so the
/// screenshots show the same deal every time. Normal launches use none.
struct LaunchOptions {
    /// Same shuffle and same computer moves every time.
    var seed: UInt64?
    /// Let the computer play this many turns for everyone (you included) at
    /// the start, to show a long line straight away.
    var demoMoves = 0
    /// Seconds a computer player waits before playing.
    var botDelay = 0.8
    /// Skip the home screen and start a match.
    var startGame = false
    /// Draw the screen at the open iPhone Duo's size, shrunk to fit.
    var openDuoPreview = false
    /// Which team leads the first game, instead of the draw.
    var firstTeam: Team?

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String] = []) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        seed = value(after: "-seed").flatMap(UInt64.init)
        demoMoves = value(after: "-demoMoves").flatMap(Int.init) ?? 0
        botDelay = value(after: "-botDelay").flatMap(Double.init) ?? 0.8
        startGame = arguments.contains("-startGame")
        openDuoPreview = arguments.contains("-openDuoPreview")
        switch value(after: "-firstTeam") {
        case "us": firstTeam = .us
        case "them": firstTeam = .them
        default: firstTeam = nil
        }
    }
}

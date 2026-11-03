import CoreGraphics
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
    /// Draw the screen at another phone's size (in points), shrunk to fit,
    /// e.g. "-previewSize 951x669" for the open iPhone Duo.
    var previewSize: CGSize?
    /// Which team leads the first game, instead of the draw.
    var firstTeam: Team?
    /// How the game screen shows who sits where, e.g. "-tableStyle map".
    var tableStyle: TableStyle = .around

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
        if arguments.contains("-openDuoPreview") {
            previewSize = CGSize(width: 951, height: 669)
        } else if let text = value(after: "-previewSize") {
            let parts = text.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { previewSize = CGSize(width: parts[0], height: parts[1]) }
        }
        tableStyle = value(after: "-tableStyle").flatMap(TableStyle.init(rawValue:)) ?? .around
        switch value(after: "-firstTeam") {
        case "us": firstTeam = .us
        case "them": firstTeam = .them
        default: firstTeam = nil
        }
    }
}

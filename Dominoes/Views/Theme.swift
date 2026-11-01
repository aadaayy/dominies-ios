import SwiftUI
import UIKit

/// The app's look: quiet greys, ivory tiles, one colour per team.
enum Theme {
    /// The table: the system's grouped background (light grey, near black in dark mode).
    static let table = Color(uiColor: .systemGroupedBackground)
    /// Solid cards (glass is used for panels, see Glass.swift).
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    static let us = Color.blue
    static let them = Color.orange

    static func color(for team: Team) -> Color { team == .us ? us : them }

    /// Ivory tile faces, a touch dimmer in dark mode so they don't glare.
    static let tileFace = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.89, blue: 0.86, alpha: 1)
            : UIColor(red: 0.995, green: 0.99, blue: 0.97, alpha: 1)
    })
    static let pip = Color(white: 0.11)
    static let tileEdge = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.10)
    })
    static let tileShadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.5) : UIColor(white: 0, alpha: 0.14)
    })
}

# Dominoes

Double Nine dominoes for iPhone Duo and regular iPhones: you and your partner against two computer players. A clean, quiet look, with tiles that never overlap however long the line gets.

## What's in it

1. Home: pick the target score (100, 150, 200 or 250) and how good the opponents are (Easy or Normal), then Play.
2. Partner Double Nine rules: 55 tiles, ten each, no drawing. Turns go to the left and alternate between teams. Anyone dealt five or more doubles means a fresh deal.
3. The first game's leading team comes from a fair draw; after that the winners lead. When your team leads you choose who plays first, you or your partner.
4. You must play when you can. With nothing to play you knock (it knocks for you after a moment). Four knocks in a row block the game.
5. Going out wins the opponents' leftover pips. A blocked game goes to the lighter team, which wins the other team's pips. A tie scores nothing and is played again.
6. When a tile fits both ends, the two ends light up and you tap the one you want.
7. Play upright or sideways. Upright (and on the folded Duo) your ten tiles sit in two rows of five; sideways (and on the open Duo) they sit in one row with the players on the left.
8. Pinch the table to zoom in and drag to look around. After every tile played it zooms back out to the whole line.

## How the code is laid out

1. `Dominoes/Core`: the rules (`Game`, `Match`), the computer players (`Bot`) and the table layout (`BoardLayout`). Plain Swift, no screens, so it's tested on a cheap Linux machine with `swift test`.
2. `Dominoes/Views` and `Dominoes/App`: the SwiftUI screens.
3. `Tests/DominoCoreTests`: the logic tests. The layout test plays thousands of real games and checks, after every single play and at every table width, that no two tiles overlap and that each tile touches the one before it with the same number.
4. `DominoesUITests`: the walk-through that plays the app on the simulators, checks tile positions on the real screen, and takes the screenshots.

## Run it on your iPhone Duo (free Apple account)

You need a Mac with Xcode 27.1 or later. No simulator is needed.

### First time

1. In Xcode, choose Integrate > Clone, paste `https://github.com/aadaayy/dominies-ios`, and pick a folder.
2. Open `Dominoes.xcodeproj` if it doesn't open by itself.
3. Xcode Settings > Accounts: sign in with your Apple account. A free account works; Xcode calls it a Personal Team.
4. Click the blue Dominoes project at the top of the file list, open Signing & Capabilities, and pick your Personal Team for the Dominoes target.
5. If Xcode says the bundle identifier is taken, change `com.albertoaday.dominoes` to something unique to you.
6. Plug the Duo into the Mac with a cable and tap Trust on the phone. Developer Mode must be on (Settings > Privacy & Security > Developer Mode).
7. In Xcode, pick your Duo from the device menu at the top and press Run (the play button).
8. The first time, the phone may block the app. On the Duo, open Settings > General > VPN & Device Management, trust your developer certificate, and open the app again.

### Each time there's a new version

1. Integrate > Pull.
2. Press Run.

## Automatic checks

Every push to main runs the logic tests on Linux, then builds the app and runs the walk-through on iPhone Pro Max, iPhone Pro and iPhone Duo simulators. The open Duo is drawn at its real size (about 951 by 669 points) on the Pro Max, since the Duo simulator can't be unfolded there. The newest screenshots land on the `screenshots` branch, named after the device and the step.

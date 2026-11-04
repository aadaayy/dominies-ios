# Dominoes

Double Nine dominoes for iPhone Duo and regular iPhones, mainly with friends online (you and a partner against two others), and against the computer to try it out. A clean, quiet look, with tiles that never overlap however long the line gets.

## What's in it

1. Home: Play with Friends, or Play with Computer after picking the target score (100, 150, 200 or 250) and how good the computers are (Easy or Normal).
2. Partner Double Nine rules: 55 tiles, ten each, no drawing. Turns go to the left and alternate between teams. Anyone dealt five or more doubles means a fresh deal.
3. The first game's leading team comes from a fair draw; after that the winners lead. When your team leads you choose who plays first, you or your partner.
4. You must play when you can. With nothing to play you knock (it knocks for you after a moment). Four knocks in a row block the game.
5. Going out wins the opponents' leftover pips. A blocked game goes to the lighter team, which wins the other team's pips. A tie scores nothing and is played again.
6. When a tile fits both ends, the two ends light up and you tap the one you want.
7. Play upright or sideways. Upright (and on the folded Duo) your ten tiles sit in two rows of five; sideways (and on the open Duo) they sit in one row with the players on the left.
8. Pinch the table to zoom in and drag to look around. After every tile played it zooms back out to the whole line.
9. Accounts: the badge in Home's top corner opens Sign in, with Continue with Google, or an email and password for people without Google (Create Account, or Sign In to one made before). Signed in, the badge shows your Google picture (or initials), and the account page has Change Name, Change Picture (choose a photo and frame it in a circle, go back to the Google photo, or remove it), Sign Out and Delete Account. Friends see the same name and picture in lobbies and games. Signing in is optional for playing the computer; playing with friends needs it.
10. Play with Friends (see Online games below): New game, Join with a six-letter game code, invites from friends, your games in progress, and friends added by their friend codes.

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

## Accounts setup

Accounts run on the Supabase project called **Dominoes** (free plan), kept apart from the golf app's project so the two apps never share players. The app already points at it in `Dominoes/Account/Accounts.plist` (the project URL and its publishable key, both safe in the app and on GitHub). The `profiles` table is made by `supabase/migrations/20261102201913_profiles.sql`, already applied: one row per player (Google or email) with their name and picture, which only they can see or change, plus Delete Account. Pictures players choose are saved in a public storage bucket, `avatars`, made by `supabase/migrations/20261104020000_profile_pictures.sql`: 256 by 256 JPEGs, one folder per player, which only that player can add to or remove from.

Google sign-in needs these clicks once:

1. In Supabase, open the Dominoes project > Authentication > Sign In / Providers > Google, and copy the Callback URL it shows: `https://chgnvqvkcifbjtgbboqa.supabase.co/auth/v1/callback`. Leave the page open.
2. Go to [console.cloud.google.com](https://console.cloud.google.com) and create a project named `Dominoes`.
3. Open Google Auth Platform. Fill in Branding with the app name Dominoes and your email, and pick External under Audience.
4. Audience > Test users: add your own Google address.
5. Clients > Create client. Type: Web application. Under Authorized redirect URIs, paste the Callback URL from step 1. Create, then copy the Client ID and Client secret.
6. Back in Supabase's Google page: turn Google on, paste the Client ID and Client secret, and save.
7. Authentication > URL Configuration > Redirect URLs: add `dominoes://login-callback`.
8. Leave Authentication > Sign In / Providers > Email turned on, for people without a Google account.

### Email and password

Players without Google type an email and a password (at least 8 characters). Create Account makes the account and signs in straight away; Sign In opens one made before. No email is sent either way, because Authentication > Sign In / Providers > Email has Confirm email turned off. Leave it off: with it on, new players would need a confirmation email, which Supabase's own sender only delivers to your Supabase team.

The app shows plain messages for a wrong password, an email that already has an account, and a password that's too short. There's no "forgot password" yet, since a reset needs an email sent to the player.

While Google's Audience says Testing, only the test users you list (up to 100) can sign in. To open it to everyone, press Publish app; the app only asks for name, email and picture, which normally doesn't need Google's review.

Later, Sign in with Apple needs the paid Apple Developer Program. Apple's review rules expect it (or a similar private sign-in) next to Google before the app goes on the App Store.

The automatic checks never reach Supabase: they use a pretend account server on the phone (`-mockAccount`, `Dominoes/Account/MockAccountService.swift`), where Google signs in as Alex Rivera, new email accounts last until the app quits, and jordan@example.com with the password dominoes1 is there to sign in to.

## Online games

Games with friends run on the same Supabase project. The server deals, keeps everyone's tiles hidden from the others, checks every move, plays the computer seats and knocks for anyone with nothing to play, so no phone can cheat. Phones see changes live (Supabase Realtime) and also check every few seconds.

1. Friends: everyone has a six-letter friend code on the Play with Friends page. Type a friend's code to add them; adding goes both ways.
2. New game opens the lobby: the game code to share, the four seats as they sit at the table (you at the bottom, your partner across, the other team on your left and right), Invite to send an invite to a friend, Sit here to change seats, and the host's Play to, Computers and Start game. Empty seats get a computer player.
3. Invites show up on the friend's Play with Friends page (and as a count on Home) while the app is open. There are no push notifications yet: those need the paid Apple Developer Program. Sharing the game code by message works for anyone.
4. Leaving the table asks: Come back later keeps your seat, Leave for good gives your tiles to a computer, and the host can End it for everyone. If a friend hasn't played for a minute, anyone can let a computer play for them.
5. Rooms don't pile up: a room is deleted when the host ends it, when the host leaves before the start, or when the last person leaves. Rooms left alone are cleaned up after a day (finished or never started) or two weeks (anything), whenever someone makes a new game.

The server side is `supabase/migrations/20261103200000_online_games.sql` and `supabase/migrations/20261103210000_delete_empty_rooms.sql`, both already applied (pasted into the SQL Editor). The checks use a pretend server on the phone instead (`-mockOnline`, `Dominoes/Online/MockOnlineService.swift`) with pretend friends Sam Lee and Jordan Park, who join when invited and play their turns.

## Automatic checks

Every push to main (and to Claude's working branches) runs the logic tests on Linux, then builds the app and runs the walk-through on iPhone Pro Max, iPhone Pro and iPhone Duo simulators. The open Duo is drawn at its real size (about 951 by 669 points) on the Pro Max, since the Duo simulator can't be unfolded there. The newest screenshots land on the `screenshots` branch (or `screenshots-<branch name>` for a working branch), named after the device and the step.

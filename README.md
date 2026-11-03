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
9. Accounts: the badge in Home's top corner opens Sign in, with Continue with Google, or an email address and a six-digit code sent to it, for people without Google. Signed in, the badge shows your Google picture (or initials), and the account page has Sign Out and Delete Account. Signing in is optional; the game plays the same without it.

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

Accounts run on the Supabase project called **Dominoes** (free plan), kept apart from the golf app's project so the two apps never share players. The app already points at it in `Dominoes/Account/Accounts.plist` (the project URL and its publishable key, both safe in the app and on GitHub). The `profiles` table is made by `supabase/migrations/20261102201913_profiles.sql`, already applied: one row per player (Google or email) with their name and picture, which only they can see or change, plus Delete Account.

Google sign-in needs these clicks once:

1. In Supabase, open the Dominoes project > Authentication > Sign In / Providers > Google, and copy the Callback URL it shows: `https://chgnvqvkcifbjtgbboqa.supabase.co/auth/v1/callback`. Leave the page open.
2. Go to [console.cloud.google.com](https://console.cloud.google.com) and create a project named `Dominoes`.
3. Open Google Auth Platform. Fill in Branding with the app name Dominoes and your email, and pick External under Audience.
4. Audience > Test users: add your own Google address.
5. Clients > Create client. Type: Web application. Under Authorized redirect URIs, paste the Callback URL from step 1. Create, then copy the Client ID and Client secret.
6. Back in Supabase's Google page: turn Google on, paste the Client ID and Client secret, and save.
7. Authentication > URL Configuration > Redirect URLs: add `dominoes://login-callback`.
8. Leave Authentication > Sign In / Providers > Email turned on, for people without a Google account.

### Email sign-in (no password)

Players type their email and get a sign-in email. New addresses get an account the first time. Nothing to set up for this.

With Supabase's default emails (what you have now), the email has a link. Tapping it on the same phone opens the app signed in. It goes through `dominoes://login-callback`, the same Redirect URL as Google (step 7). A link opened on another device, or an old one, doesn't sign in, and the app says to send a new one.

Later, to send a six-digit code instead: Supabase only lets you edit the emails once your own email sender is connected (below). Then:

1. Authentication > Emails > Templates > Magic link or OTP: replace the body with:
   ```html
   <h2>Your Dominoes code</h2>
   <p>Enter this code in the app: <strong>{{ .Token }}</strong></p>
   <p>It works once and expires soon. If you didn't ask for it, ignore this email.</p>
   ```
2. Do the same for Confirm sign up (new players get that one first).
3. In `Dominoes/Account/Accounts.plist`, add `<key>EmailCodes</key><true/>`, so the app asks for the code.

Supabase's own email sender is only for trying things out: it only sends to the email addresses of your Supabase organization's members, and only a few emails an hour. Before other people sign in with email, connect an email service under Authentication > Emails > SMTP Settings (for example Resend, which has a free plan), then raise the email limit under Authentication > Rate Limits. Until then, other people's email sign-ins fail with "Email sign-in isn't open to everyone yet. Use Google for now." Google sign-in has no such limit.

While Google's Audience says Testing, only the test users you list (up to 100) can sign in. To open it to everyone, press Publish app; the app only asks for name, email and picture, which normally doesn't need Google's review.

Later, Sign in with Apple needs the paid Apple Developer Program. Apple's review rules expect it (or a similar private sign-in) next to Google before the app goes on the App Store.

The automatic checks never reach Supabase: they use a pretend account server on the phone (`-mockAccount`, `Dominoes/Account/MockAccountService.swift`), where any sign-in link works and the email code is always 123456 (with `-mockEmailCodes`).

## Automatic checks

Every push to main (and to Claude's working branches) runs the logic tests on Linux, then builds the app and runs the walk-through on iPhone Pro Max, iPhone Pro and iPhone Duo simulators. The open Duo is drawn at its real size (about 951 by 669 points) on the Pro Max, since the Duo simulator can't be unfolded there. The newest screenshots land on the `screenshots` branch (or `screenshots-<branch name>` for a working branch), named after the device and the step.

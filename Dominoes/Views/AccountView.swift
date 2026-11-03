import SwiftUI

/// The account page, opened from the badge on Home. Signed out it offers
/// Continue with Google, or a one-time code by email for people without a
/// Google account; signed in it shows the player and lets them sign out or
/// delete the account. Playing never needs an account.
struct AccountView: View {
    var onClose: () -> Void

    @Environment(AccountSession.self) private var account
    @State private var working = false
    @State private var problem: String?
    @State private var confirmingDelete = false
    @State private var email = ""
    /// Where the code went, once it's sent.
    @State private var codeSentTo: String?
    @State private var code = ""
    @FocusState private var focus: Field?

    private enum Field { case email, code }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height * 1.2
            ZStack(alignment: .topLeading) {
                Backdrop()
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .center, spacing: 40) {
                                header
                                    .frame(maxWidth: .infinity)
                                actions
                                    .frame(maxWidth: 380)
                            }
                            .frame(maxWidth: 820)
                        } else {
                            VStack(spacing: 28) {
                                header
                                actions
                                    .frame(maxWidth: 440)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, wide ? 32 : 56)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    // Tapping anywhere off the fields puts the keyboard away.
                    .contentShape(Rectangle())
                    .onTapGesture { focus = nil }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                closeButton
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: account.player)
        .alert("Delete your account?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { run { try await account.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Dominoes account and profile are removed for good. You can still play, and you can make a new account any time.")
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var header: some View {
        if let player = account.player {
            VStack(spacing: 12) {
                AvatarView(player: player, size: 84)
                VStack(spacing: 4) {
                    Text(player.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("account-name")
                    if let email = player.email, email != player.name {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Label(player.signInMethod == "email" ? "Signed in with email" : "Signed in with Google",
                      systemImage: "checkmark.seal.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        } else {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    DominoView(first: 6, second: 3, isVertical: true)
                        .frame(width: 30, height: 60)
                        .rotationEffect(.degrees(-8))
                    DominoView(first: 9, second: 9, isVertical: true)
                        .frame(width: 30, height: 60)
                        .rotationEffect(.degrees(6))
                }
                VStack(spacing: 8) {
                    Text("Sign in to Dominoes")
                        .font(.title2.weight(.bold))
                    Text("Make an account with Google or your email so your name comes with you. You can keep playing without one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if account.player != nil {
                VStack(spacing: 0) {
                    row("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", id: "sign-out") {
                        run { await account.signOut() }
                    }
                    Divider().padding(.leading, 52)
                    row("Delete Account", systemImage: "trash", id: "delete-account", destructive: true) {
                        confirmingDelete = true
                    }
                }
                .glassPanel(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else if let sentTo = codeSentTo {
                codeEntry(sentTo)
            } else {
                Button {
                    run { try await account.signInWithGoogle() }
                } label: {
                    HStack(spacing: 12) {
                        Image("GoogleG")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Continue with Google")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .glassButton()
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(working)
                .accessibilityIdentifier("sign-in-google")

                orDivider

                emailEntry

                Button("Not now", action: onClose)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityIdentifier("not-now")
            }

            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("account-problem")
            }
        }
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.secondary.opacity(0.3)).frame(height: 0.5)
            Text("or")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle().fill(.secondary.opacity(0.3)).frame(height: 0.5)
        }
        .padding(.horizontal, 8)
    }

    /// Step one of email sign-in: the address, then a code is emailed to it.
    private var emailEntry: some View {
        let ready = Player.looksLikeEmail(email)
        return VStack(spacing: 10) {
            TextField("Email address", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($focus, equals: .email)
                .onSubmit { if ready { sendCode() } }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .glassPanel(Capsule())
                .accessibilityIdentifier("email-field")
            Button(action: sendCode) {
                Text("Email Me a Code")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .opacity(working ? 0 : 1)
                    .overlay { if working { ProgressView() } }
            }
            .glassButton()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!ready || working)
            .accessibilityIdentifier("send-code")
        }
    }

    /// Step two: the code from the email.
    private func codeEntry(_ sentTo: String) -> some View {
        let ready = Player.cleanCode(code).count >= 6
        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Check your email")
                    .font(.headline)
                Text("Enter the code sent to \(sentTo).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("code-sent-to")
            }
            TextField("Code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($focus, equals: .code)
                .onChange(of: code) { _, new in
                    let clean = Player.cleanCode(new)
                    if clean != new { code = clean }
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
                .glassPanel(Capsule())
                .accessibilityIdentifier("code-field")
            Button(action: verifyCode) {
                Text("Sign In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .opacity(working ? 0 : 1)
                    .overlay { if working { ProgressView() } }
            }
            .prominentGlassButton()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!ready || working)
            .accessibilityIdentifier("verify-code")
            HStack(spacing: 20) {
                Button("Send a New Code", action: sendCode)
                    .accessibilityIdentifier("resend-code")
                Button("Use Another Email") {
                    codeSentTo = nil
                    code = ""
                    problem = nil
                    focus = .email
                }
                .accessibilityIdentifier("change-email")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .disabled(working)
        }
    }

    private func sendCode() {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard Player.looksLikeEmail(address) else { return }
        focus = nil
        run {
            try await account.sendEmailCode(to: address)
            code = ""
            codeSentTo = address
            focus = .code
        }
    }

    private func verifyCode() {
        guard let address = codeSentTo else { return }
        focus = nil
        run {
            try await account.verifyEmailCode(email: address, code: code)
            codeSentTo = nil
            code = ""
            email = ""
        }
    }

    private func row(_ title: String, systemImage: String, id: String, destructive: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working)
        .accessibilityIdentifier(id)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .glassPanel(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account-close")
        .accessibilityLabel("Close")
    }

    /// Runs an account action, showing a spinner and any problem in plain words.
    private func run(_ action: @escaping () async throws -> Void) {
        problem = nil
        working = true
        Task {
            defer { working = false }
            do {
                try await action()
            } catch AccountError.cancelled {
                // They closed Google's page: nothing to say.
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

/// The badge in Home's corner: "Sign in" when signed out, the player's
/// picture (or initials) when signed in.
struct AccountBadge: View {
    var action: () -> Void
    @Environment(AccountSession.self) private var account

    var body: some View {
        Button(action: action) {
            if let player = account.player {
                AvatarView(player: player, size: 40)
                    .padding(2)
                    .glassPanel(Circle(), interactive: true)
            } else {
                Label("Sign in", systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassPanel(Capsule(), interactive: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account")
        .accessibilityLabel(account.player.map { "Account, signed in as \($0.name)" } ?? "Sign in")
    }
}

/// A round picture: the player's Google photo, or their initials on a soft
/// blue disc while it loads or when there's none.
struct AvatarView: View {
    let player: Player
    var size: CGFloat

    var body: some View {
        ZStack {
            initials
            if let url = player.avatarURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.us.opacity(0.85), Theme.us.opacity(0.55)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(player.initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}

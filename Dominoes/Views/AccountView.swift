import SwiftUI

/// The account page, opened from the badge on Home. Signed out it offers
/// Continue with Google, or an email and password for people without a
/// Google account (make one, or sign in to one); signed in it shows the
/// player and lets them sign out or delete the account. Playing never needs
/// an account.
struct AccountView: View {
    var onClose: () -> Void

    @Environment(AccountSession.self) private var account
    @State private var working = false
    @State private var problem: String?
    @State private var confirmingDelete = false
    @State private var mode = Mode.create
    @State private var email = ""
    @State private var password = ""
    @State private var showingPassword = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    /// Make a new account, or sign in to one made before.
    private enum Mode: Hashable { case create, signIn }

    /// While typing, only the title and the email form show, so the fields
    /// and the button fit above the keyboard on the folded Duo.
    private var typing: Bool { focus != nil }

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
                    .padding(.vertical, wide ? 20 : (typing ? 16 : 56))
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
        .animation(.easeInOut(duration: 0.25), value: typing)
        // Signed in or out: start the form fresh.
        .onChange(of: account.player) {
            email = ""
            password = ""
            showingPassword = false
            mode = .create
        }
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
                if !typing {
                    HStack(spacing: 10) {
                        DominoView(first: 6, second: 3, isVertical: true)
                            .frame(width: 30, height: 60)
                            .rotationEffect(.degrees(-8))
                        DominoView(first: 9, second: 9, isVertical: true)
                            .frame(width: 30, height: 60)
                            .rotationEffect(.degrees(6))
                    }
                }
                VStack(spacing: 8) {
                    Text("Sign in to Dominoes")
                        .font(.title2.weight(.bold))
                    if !typing {
                        Text("Make an account with Google or your email so your name comes with you. You can keep playing without one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
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
                problemText
            } else {
                if !typing {
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
                }

                emailForm
                problemText

                if !typing {
                    Button("Not now", action: onClose)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .accessibilityIdentifier("not-now")
                }
            }
        }
    }

    /// What went wrong, in plain words, right under the button that tried.
    @ViewBuilder
    private var problemText: some View {
        if let problem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-problem")
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

    /// For people without Google: an email and a password, to make an
    /// account or to sign in to one. No email is sent either way.
    private var emailForm: some View {
        let ready = Player.looksLikeEmail(email) && !password.isEmpty
        return VStack(spacing: 10) {
            Picker("Account", selection: Binding(get: { mode }, set: { new in
                mode = new
                problem = nil
            })) {
                Text("Create Account").tag(Mode.create)
                Text("Sign In").tag(Mode.signIn)
            }
            .pickerStyle(.segmented)
            .disabled(working)
            .padding(.bottom, 2)
            .accessibilityIdentifier("email-mode")

            TextField("Email address", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .glassPanel(Capsule())
                .accessibilityIdentifier("email-field")

            HStack(spacing: 8) {
                Group {
                    if showingPassword {
                        TextField(passwordPrompt, text: $password)
                    } else {
                        SecureField(passwordPrompt, text: $password)
                    }
                }
                .textContentType(mode == .create ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit { if ready { submit() } }
                .accessibilityIdentifier("password-field")
                Button {
                    let wasTyping = focus == .password
                    showingPassword.toggle()
                    if wasTyping { focus = .password }
                } label: {
                    Image(systemName: showingPassword ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("show-password")
                .accessibilityLabel(showingPassword ? "Hide password" : "Show password")
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(height: 50)
            .glassPanel(Capsule())

            Button(action: submit) {
                Text(mode == .create ? "Create Account" : "Sign In")
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
            .accessibilityIdentifier("email-submit")
        }
    }

    /// New passwords say how long they must be, right in the empty field.
    private var passwordPrompt: String {
        mode == .create ? "Password, at least \(Player.passwordRange.lowerBound) characters" : "Password"
    }

    private func submit() {
        let address = email
        let secret = password
        guard Player.looksLikeEmail(address), !secret.isEmpty else { return }
        focus = nil
        let creating = mode == .create
        run {
            do {
                if creating {
                    try await account.signUp(email: address, password: secret)
                } else {
                    try await account.signIn(email: address, password: secret)
                }
            } catch AccountError.accountExists {
                // They have one already: switch to signing in, keeping what they typed.
                mode = .signIn
                throw AccountError.accountExists
            }
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

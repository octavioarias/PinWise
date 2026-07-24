import SwiftUI

/// Passwordless email sign-in: enter email → receive a one-time code → enter it → signed in.
/// Backed by Supabase email OTP via `AuthManager`. Functional/minimal by design — restyle freely.
/// On success, `AuthManager` flips the session to `.email`, which unmounts the welcome screen.
struct EmailSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthManager.shared
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isWorking = false
    @FocusState private var focused: Bool

    private var emailLooksValid: Bool { email.contains("@") && email.contains(".") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text(codeSent ? "Enter your code" : "Sign in with email")
                        .font(Typo.title).foregroundStyle(BrandColor.textPrimary)
                    Text(codeSent
                         ? "We emailed a 6-digit code to \(email). Enter it below — it can take a moment to arrive."
                         : "We'll email you a one-time code. No password needed.")
                        .font(.callout).foregroundStyle(BrandColor.textSecondary)

                    if !codeSent {
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .pinwiseField()
                        PrimaryButton(title: "Send code", systemImage: "paperplane") {
                            Task { await sendCode() }
                        }
                        .disabled(isWorking || !emailLooksValid)
                        .opacity(isWorking || !emailLooksValid ? 0.5 : 1)
                    } else {
                        TextField("123456", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .pinwiseField()
                        PrimaryButton(title: "Verify & sign in", systemImage: "checkmark") {
                            Task { await verify() }
                        }
                        .disabled(isWorking || code.count < 6)
                        .opacity(isWorking || code.count < 6 ? 0.5 : 1)
                        Button("Change email") {
                            codeSent = false; code = ""; auth.notice = nil
                        }
                        .font(.footnote).foregroundStyle(BrandColor.accentText)
                        .buttonStyle(.plain)
                    }

                    if isWorking {
                        HStack(spacing: Space.sm) { ProgressView(); Text(codeSent ? "Signing you in…" : "Sending code…").font(.caption).foregroundStyle(BrandColor.textSecondary) }
                    }
                    if let notice = auth.notice, !notice.isEmpty {
                        Text(notice).font(.footnote).foregroundStyle(BrandColor.warning)
                    }
                }
                .padding(Space.lg)
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { auth.notice = nil; dismiss() } } }
            .onAppear { focused = true }
        }
    }

    private func sendCode() async {
        isWorking = true; defer { isWorking = false }
        if await auth.requestEmailCode(email) {
            codeSent = true; code = ""; focused = true
        }
    }

    private func verify() async {
        isWorking = true; defer { isWorking = false }
        if await auth.verifyEmailCode(email, code) { dismiss() }
    }
}

import SwiftUI

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var failCount = 0
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                VStack(spacing: 14) {
                    AppMark(size: 88)
                    Text("Lead Gen")
                        .font(.largeTitle.bold())
                    Text("Sign in with your admin password.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit(submit)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let message = error ?? store.loginMessage {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }

                    Button(action: submit) {
                        ZStack {
                            Text("Sign In").opacity(isWorking ? 0 : 1)
                            if isWorking { ProgressView().tint(.white) }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(password.isEmpty || isWorking)
                }
                .padding(.horizontal, 24)

                Label("After you sign in, \(store.biometryName) keeps the app locked.", systemImage: store.biometrySymbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 20)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sensoryFeedback(.error, trigger: failCount)
        .animation(.default, value: error)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !password.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            do {
                try await store.signIn(password: password)
                password = ""
            } catch {
                self.error = error.localizedDescription
                failCount += 1
            }
            isWorking = false
        }
    }
}

struct LockView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                AppMark(size: 80)
                Text("Lead Gen is locked")
                    .font(.title2.bold())
                Button {
                    Task { await store.unlock() }
                } label: {
                    Label("Unlock with \(store.biometryName)", systemImage: store.biometrySymbol)
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .task { store.autoUnlockIfNeeded() }
    }
}

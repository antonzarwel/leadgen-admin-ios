import SwiftUI

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var failCount = 0
    @State private var appeared = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            BrandBackdrop()
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 70)
                    VStack(spacing: 16) {
                        AppMark(size: 96)
                            .scaleEffect(appeared ? 1 : 0.8)
                            .opacity(appeared ? 1 : 0)
                        Text("Lead Gen")
                            .font(.rounded(38, .heavy))
                            .foregroundStyle(.white)
                        Text("Leads, clients and money,\nall in one place.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.white.opacity(0.6))
                            SecureField("", text: $password, prompt: Text("Admin password").foregroundStyle(.white.opacity(0.5)))
                                .textContentType(.password)
                                .submitLabel(.go)
                                .focused($focused)
                                .onSubmit(submit)
                                .foregroundStyle(.white)
                                .tint(.white)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 54)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(error == nil ? 0.18 : 0.6), lineWidth: 1)
                        }
                        .modifier(ShakeEffect(shakes: CGFloat(failCount)))
                        .animation(.default, value: failCount)

                        if let message = error ?? store.loginMessage {
                            Label(message, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.78))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }

                        Button(action: submit) {
                            ZStack {
                                Text("Sign In").opacity(isWorking ? 0 : 1)
                                if isWorking { ProgressView().tint(Theme.deepViolet) }
                            }
                            .font(.headline)
                            .foregroundStyle(Theme.deepViolet)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .opacity(password.isEmpty ? 0.6 : 1)
                        }
                        .buttonStyle(.pressable)
                        .disabled(password.isEmpty || isWorking)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .padding(.horizontal, 20)
                    .offset(y: appeared ? 0 : 30)
                    .opacity(appeared ? 1 : 0)

                    Label("After you sign in, \(store.biometryName) keeps it locked.", systemImage: store.biometrySymbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 32)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 20)
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.error, trigger: failCount)
        .animation(.default, value: error)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { appeared = true }
            focused = true
        }
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

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}

struct LockView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            BrandBackdrop()
            VStack(spacing: 22) {
                AppMark(size: 88)
                VStack(spacing: 6) {
                    Text("Lead Gen")
                        .font(.rounded(30, .heavy))
                        .foregroundStyle(.white)
                    Text("Locked to keep your numbers private")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Button {
                    Task { await store.unlock() }
                } label: {
                    Label("Unlock with \(store.biometryName)", systemImage: store.biometrySymbol)
                        .font(.headline)
                        .foregroundStyle(Theme.deepViolet)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 52)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 8)
            }
            .padding()
        }
        .environment(\.colorScheme, .dark)
        .task { store.autoUnlockIfNeeded() }
    }
}

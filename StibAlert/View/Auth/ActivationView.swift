import SwiftUI

struct ActivationView: View {
    @EnvironmentObject private var session: AuthSession
    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool

    @State private var code = ""
    @State private var isLoading = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var resendCooldown = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isValidCode: Bool {
        code.count == 4
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                PageHeader(
                    title: "",
                    eyebrow: "ACTIVATION"
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroBlock
                        .padding(.bottom, 24)

                    codeSection
                        .padding(.bottom, 20)

                    submitButton
                        .padding(.bottom, 16)

                    resendButton

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .background(DS.Color.paper.ignoresSafeArea())
        .modifier(PaperGrainBackground())
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if session.activationSuccessVisible {
                activationSuccessOverlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            codeFocused = true
        }
        .onReceive(timer) { _ in
            if resendCooldown > 0 {
                resendCooldown -= 1
            }
        }
    }

    private var activationSuccessOverlay: some View {
        ZStack {
            DS.Color.paper.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(DS.Color.primary.opacity(0.14))
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(DS.Color.primary)
                }

                Text("Compte activé")
                    .font(DS.Font.displayH2)
                    .foregroundStyle(DS.Color.ink)

                Text("Session ouverte, synchronisation en cours.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkSoft)
            }
            .padding(28)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .shadow(DS.Shadow.floating)
            .padding(.horizontal, 32)
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dernière étape,")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(DS.Color.ink)
            +
            Text(" validez.")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(DS.Color.primary)

            if let email = session.pendingActivationEmail {
                Text("Entre le code reçu à \(email) pour ouvrir la session et synchroniser ton compte.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkSoft)
                    .frame(maxWidth: 300, alignment: .leading)
                    .padding(.top, 6)
            }
        }
    }

    private var codeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CODE À 4 CHIFFRES")
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundStyle(DS.Color.inkMute)
                .tracking(1.4)

            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Color.ink)
                .frame(height: 86)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(errorMessage == nil ? DS.Color.ink.opacity(0.16) : DS.Color.statusMajor.opacity(0.45), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(4))
                    if filtered != newValue {
                        code = filtered
                    }
                    if errorMessage != nil {
                        errorMessage = nil
                    }
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.statusMajor)
            } else {
                Text("Le code expire rapidement. Tu peux en demander un nouveau si nécessaire.")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(DS.Color.primaryForeground)
                } else {
                    Text("Activer mon compte")
                        .font(.system(size: 14, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(DS.Color.primaryForeground)
            .background(DS.Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.primary, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .shadow(DS.Shadow.floating)
            .opacity(isValidCode ? 1 : 0.6)
        }
        .disabled(isLoading || !isValidCode)
        .opacity(session.activationSuccessVisible ? 0.7 : 1)
        .buttonStyle(PressableScaleStyle())
    }

    private var resendButton: some View {
        Button(action: resend) {
            Text(resendLabel)
                .font(DS.Font.mono.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(isResending || resendCooldown > 0 || isLoading)
        .opacity((isResending || resendCooldown > 0) ? 0.6 : 1)
    }

    private var resendLabel: String {
        if isResending { return "RENVOI…" }
        if resendCooldown > 0 { return "RENVOYER LE CODE (\(resendCooldown)S)" }
        return "RENVOYER LE CODE"
    }

    private func submit() {
        guard isValidCode else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await session.activer(code: code)
            } catch {
                await MainActor.run {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                    isLoading = false
                }
                return
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func resend() {
        isResending = true
        errorMessage = nil

        Task {
            do {
                try await session.renvoyerCode()
                await MainActor.run {
                    resendCooldown = 60
                    isResending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                    isResending = false
                }
            }
        }
    }
}

import SwiftUI

struct STIBAIView: View {
    @StateObject private var viewModel: STIBAIViewModel
    private let locationLabel: String
    private let onClose: () -> Void

    @FocusState private var inputFocused: Bool

    init(
        locationLabel: String,
        contextProvider: @escaping @MainActor (_ userMessage: String) async -> STIBAIContext,
        onClose: @escaping () -> Void
    ) {
        self.locationLabel = locationLabel
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: STIBAIViewModel(contextProvider: contextProvider))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.Color.ink.opacity(0.18))
            transcript
            inputBar
        }
        .background(DS.Color.paper.ignoresSafeArea())
        .onDisappear { viewModel.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Color.accent)
                    .overlay(Circle().stroke(DS.Color.ink, lineWidth: 1.5))
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(DS.Color.accentForeground)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("STIB·AI")
                    .font(DS.Font.monoLarge)
                    .tracking(2.2)
                    .foregroundStyle(DS.Color.ink)
                Text(locationLabel)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 52, height: 52)
                    .background(DS.Color.paper2)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.border, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer l'assistant")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if viewModel.messages.isEmpty {
                        welcomeBlock
                    }

                    ForEach(viewModel.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if let error = viewModel.errorMessage, !error.isEmpty {
                        Text(error)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.statusMajor)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 30)
            }
            .onChange(of: viewModel.messages) { _, messages in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var welcomeBlock: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Salut. Je connais l’état du réseau, les alertes officielles, les signalements et ton trajet actif. Pose-moi une question concrète sur tes déplacements.")
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(7)
                .foregroundStyle(DS.Color.ink)
                .padding(18)
                .background(DS.Color.paper2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.35), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Suggestions")
                    .sectionTitle()

                ForEach(viewModel.quickPrompts, id: \.self) { prompt in
                    Button {
                        viewModel.send(prompt)
                    } label: {
                        HStack {
                            Text(prompt)
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.ink)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(DS.Color.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(DS.Color.border, lineWidth: 1.4)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: STIBAIMessage) -> some View {
        let isUser = message.role == .user
        // Si c'est le DERNIER message assistant ET le stream tourne ET pas
        // encore de texte reçu, on affiche un loading shimmer au lieu d'une
        // bulle vide avec "…" — Gemini SSE peut mettre 3-5 s à émettre son
        // premier token sur cold start ou modèle saturé.
        let showTypingIndicator = !isUser
            && message.content.isEmpty
            && viewModel.isStreaming
            && viewModel.messages.last?.id == message.id

        return HStack(alignment: .top) {
            if isUser { Spacer(minLength: 44) }

            if isUser {
                Text(markdownText(message.content.isEmpty ? "…" : message.content))
                    .font(DS.Font.body)
                    .lineSpacing(5)
                    .foregroundStyle(DS.Color.primaryForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(DS.Color.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Color.ink, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if showTypingIndicator {
                STIBAITypingIndicator()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(DS.Color.paper2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DS.Color.border, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                STIBAIResponseRenderer(text: message.content.isEmpty ? "…" : message.content)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(DS.Color.paper2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DS.Color.border, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !isUser { Spacer(minLength: 44) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            Divider().overlay(DS.Color.ink.opacity(0.16))

            HStack(spacing: 10) {
                TextField("Pose ta question sur le réseau…", text: $viewModel.input, axis: .vertical)
                    .font(DS.Font.body)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DS.Color.border, lineWidth: 1.5)
                    )
                    .submitLabel(.send)
                    .onSubmit {
                        viewModel.send()
                        inputFocused = false
                    }

                Button {
                    viewModel.send()
                    inputFocused = false
                } label: {
                    Image(systemName: viewModel.isStreaming ? "stop.fill" : "paperplane.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Color.primaryForeground)
                        .frame(width: 54, height: 54)
                        .background(viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming ? DS.Color.inkMute : DS.Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
            }
            .padding(.horizontal, 16)

            Text("Réponses basées sur les données disponibles dans l’app.")
                .font(DS.Font.monoSmall)
                .tracking(1.2)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.bottom, 8)
        }
        .background(DS.Color.paper)
    }

    private func markdownText(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

/// 3 dots pulsantes pour l'attente de Gemini SSE — même esprit que
/// ThinkingDotsIndicator de VoiceOverlay mais aux couleurs du chat texte
/// (encre sombre sur fond clair). Affichées dans la bulle assistant tant
/// que le 1er token n'est pas arrivé.
private struct STIBAITypingIndicator: View {
    @State private var step: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(DS.Color.ink.opacity(step == i ? 0.85 : 0.20))
                    .frame(width: 7, height: 7)
                    .scaleEffect(step == i ? 1.15 : 1.0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.35), value: step)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if Task.isCancelled { return }
                step = (step + 1) % 3
            }
        }
    }
}

struct STIBAIFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(DS.Color.accentForeground)
                .frame(width: 46, height: 46)
                .background(Circle().fill(DS.Color.accent))
                .overlay(Circle().stroke(DS.Color.ink, lineWidth: 1.5))
                .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ouvrir l'assistant IA")
    }
}

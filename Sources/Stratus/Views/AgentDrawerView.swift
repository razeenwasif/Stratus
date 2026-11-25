import SwiftUI

struct AgentDrawerView: View {
    @Environment(AppState.self) private var appState
    @State private var draft = ""
    @State private var hoveredMessageId: UUID?
    @FocusState private var inputFocused: Bool

    private let starterPrompts: [String] = [
        "Summarize my GCP spend & top resources",
        "Check recent ERROR logs in this project",
        "List Compute Engine VMs and highlight stopped ones",
        "Check Cloud Run service health & revisions"
    ]

    var body: some View {
        let store = appState.agentChat

        VStack(alignment: .leading, spacing: 0) {
            header(store: store)

            if store.messages.isEmpty {
                emptyState(store: store)
            } else {
                transcript(store: store)
            }

            composer(store: store)
        }
        .frame(maxHeight: .infinity)
        .background(T3.bgInspector)
        .onAppear {
            inputFocused = true
        }
    }

    // MARK: - Header

    private func header(store: AgentChatStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("AGENT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(T3.textTertiary)

                Spacer()

                if !store.messages.isEmpty {
                    Button {
                        store.clear()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(T3.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    appState.showAgentDrawer = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(T3.textSecondary)
                        .padding(6)
                        .background(T3.surfaceHover, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(AgentBackendKind.allCases) { backend in
                    let isSelected = store.selectedBackend == backend
                    let available = store.isBackendAvailable(backend)
                    Button {
                        store.selectedBackend = backend
                    } label: {
                        HStack(spacing: 6) {
                            StatusDot(
                                color: available ? Color(hexString: backend.accentColorHex) : T3.slate,
                                size: 5,
                                pulse: store.isRunning && isSelected
                            )
                            Text(backend.displayName)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? T3.textPrimary : T3.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? T3.surfaceActive : T3.surfaceSubtle,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if let project = appState.selectedProject {
                    TagPill(text: project.projectId, monospaced: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 14)
    }

    // MARK: - Empty State & Starter Prompts

    private func emptyState(store: AgentChatStore) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ask \(store.selectedBackend.displayName)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                    Text("Runs locally via `\(store.selectedBackend.binaryName)` with Stratus MCP tools and active project context.")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("SUGGESTIONS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(T3.textTertiary)

                    ForEach(starterPrompts, id: \.self) { prompt in
                        Button {
                            sendPrompt(prompt)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hexString: store.selectedBackend.accentColorHex))
                                Text(prompt)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(T3.textSecondary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Message Transcript

    private func transcript(store: AgentChatStore) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(store.messages) { msg in
                        messageRow(msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .onChange(of: store.messages.last?.text) { _, _ in
                if let lastId = store.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.messages.count) { _, _ in
                if let lastId = store.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: AgentChatMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 36)
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundStyle(T3.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(T3.surfaceActive, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    StatusDot(
                        color: Color(hexString: msg.backend.accentColorHex),
                        size: 4.5,
                        pulse: msg.isStreaming
                    )
                    Text(msg.backend.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(T3.textTertiary)
                    Spacer()
                    if hoveredMessageId == msg.id && !msg.text.isEmpty {
                        Button {
                            appState.copyToClipboard(msg.text, label: "agent response")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10.5))
                                .foregroundStyle(T3.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if msg.text.isEmpty && msg.isStreaming {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                        Text("Thinking...")
                            .font(.system(size: 12))
                            .foregroundStyle(T3.textTertiary)
                    }
                } else {
                    Text(msg.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(T3.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .onHover { hoveredMessageId = $0 ? msg.id : nil }

        case .error:
            VStack(alignment: .leading, spacing: 4) {
                Text("\(msg.backend.displayName) Error")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(T3.rose)
                Text(msg.text)
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.rose.opacity(0.9))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T3.rose.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Composer

    private func composer(store: AgentChatStore) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "",
                text: $draft,
                prompt: Text("Ask \(store.selectedBackend.displayName) about GCP...").foregroundStyle(T3.textTertiary),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(T3.textPrimary)
            .lineLimit(1...5)
            .focused($inputFocused)
            .onSubmit {
                sendPrompt(draft)
            }

            if store.isRunning {
                ActionPillButton(title: "Stop", systemImage: "stop.fill", tint: T3.rose) {
                    store.stop()
                }
            } else {
                Button {
                    sendPrompt(draft)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? T3.textTertiary : T3.bg)
                        .frame(width: 26, height: 26)
                        .background(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? T3.surfaceActive
                                : Color(hexString: store.selectedBackend.accentColorHex),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func sendPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !appState.agentChat.isRunning else { return }
        draft = ""
        appState.agentChat.send(prompt: trimmed, appState: appState)
    }
}

import Foundation
import Observation

enum AgentBackendKind: String, Sendable, CaseIterable, Identifiable {
    case fairy
    case agy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fairy: return "Fairy"
        case .agy: return "Antigravity"
        }
    }

    var binaryName: String {
        switch self {
        case .fairy: return "fairy"
        case .agy: return "agy"
        }
    }

    var accentColorHex: String {
        switch self {
        case .fairy: return "#E88255"
        case .agy: return "#7A89FF"
        }
    }
}

struct AgentChatMessage: Identifiable, Sendable, Hashable {
    enum Role: String, Sendable, Hashable {
        case user
        case assistant
        case error
    }

    let id: UUID
    let role: Role
    var text: String
    let backend: AgentBackendKind
    let timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        backend: AgentBackendKind,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.backend = backend
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

private final class ProcessStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var stderrBuffer = Data()
    private var didEmitStdout = false

    func appendStderr(_ data: Data) {
        lock.lock()
        stderrBuffer.append(data)
        lock.unlock()
    }

    func markStdoutReceived() {
        lock.lock()
        didEmitStdout = true
        lock.unlock()
    }

    func snapshot() -> (hasStdout: Bool, stderrText: String) {
        lock.lock()
        let text = String(data: stderrBuffer, encoding: .utf8) ?? ""
        let hasOut = didEmitStdout
        lock.unlock()
        return (hasOut, text)
    }
}

@MainActor
@Observable
final class AgentChatStore {
    var selectedBackend: AgentBackendKind = .fairy
    var messages: [AgentChatMessage] = []
    var isRunning = false
    var fairyPath: String?
    var agyPath: String?

    private var activeProcess: Process?
    private var wasStoppedByUser = false

    init() {
        refreshBinaryAvailability()
        if fairyPath == nil && agyPath != nil {
            selectedBackend = .agy
        }
    }

    var fairyAvailable: Bool { fairyPath != nil }
    var agyAvailable: Bool { agyPath != nil }

    func isBackendAvailable(_ backend: AgentBackendKind) -> Bool {
        switch backend {
        case .fairy: return fairyAvailable
        case .agy: return agyAvailable
        }
    }

    func refreshBinaryAvailability() {
        fairyPath = Self.locateBinary("fairy")
        agyPath = Self.locateBinary("agy")
    }

    static func locateBinary(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    func buildContextPrompt(appState: AppState) -> String {
        let projectLabel = appState.selectedProject.map { "\($0.name) (\($0.projectId))" } ?? "none"
        let modeLabel = appState.auth.isDemo ? "Demo Mode (--demo)" : "Live (\(appState.auth.mode.displayName))"
        let inspectorSummary: String
        switch appState.inspector {
        case .vm(let vm):
            inspectorSummary = "Compute VM '\(vm.name)' (\(vm.zone), \(vm.status), \(vm.machineTypeShort))"
        case .cloudRun(let svc):
            inspectorSummary = "Cloud Run service '\(svc.name)' (\(svc.region), \(svc.uri))"
        case .gcsObject(let obj, _):
            inspectorSummary = "GCS object 'gs://\(obj.bucket)/\(obj.name)'"
        case .sql(let sql):
            inspectorSummary = "Cloud SQL '\(sql.name)' (\(sql.databaseVersion), \(sql.state))"
        case .secret(let sec):
            inspectorSummary = "Secret '\(sec.shortName)'"
        case nil:
            inspectorSummary = "none"
        }

        return """
        You are running inside the Stratus macOS Google Cloud Console app.
        Active GCP Project: \(projectLabel)
        Auth Mode: \(modeLabel)
        Active Section: \(appState.selectedSection.title)
        Inspected Resource: \(inspectorSummary)
        Loaded Counts: \(appState.instances.count) VMs, \(appState.cloudRunServices.count) Cloud Run services, \(appState.buckets.count) GCS buckets, \(appState.sqlInstances.count) SQL instances, \(appState.secrets.count) secrets, \(appState.logEntries.count) log entries.
        You can use the `stratus_*` MCP tools or `~/.local/bin/stratus` CLI (add `--demo` if Auth Mode is Demo Mode) to inspect or operate Google Cloud resources on the user's behalf. Keep responses concise and well-structured.
        """
    }

    static func buildArguments(backend: AgentBackendKind, prompt: String, context: String) -> [String] {
        switch backend {
        case .fairy:
            return ["run", "-q", "-y", "--context", context, "-p", prompt]
        case .agy:
            let combined = "\(context)\n\nUser request:\n\(prompt)"
            return ["-p", combined, "--output-format", "text"]
        }
    }

    private func buildPromptWithHistory(latestPrompt: String) -> String {
        let recent = messages.filter { $0.role != .error }.suffix(6)
        guard !recent.isEmpty else { return latestPrompt }
        let history = recent.map { msg in
            let speaker = msg.role == .user ? "User" : "Assistant"
            return "\(speaker): \(msg.text)"
        }.joined(separator: "\n\n")
        return "Recent conversation:\n\(history)\n\nCurrent user message:\n\(latestPrompt)"
    }

    func send(prompt rawPrompt: String, appState: AppState) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning else { return }

        refreshBinaryAvailability()
        let backend = selectedBackend
        guard let binaryPath = (backend == .fairy ? fairyPath : agyPath) else {
            messages.append(AgentChatMessage(
                role: .error,
                text: "\(backend.displayName) CLI (`\(backend.binaryName)`) was not found in ~/.local/bin or Homebrew PATH.",
                backend: backend
            ))
            return
        }

        let promptWithHistory = buildPromptWithHistory(latestPrompt: prompt)
        let context = buildContextPrompt(appState: appState)
        let arguments = Self.buildArguments(backend: backend, prompt: promptWithHistory, context: context)

        messages.append(AgentChatMessage(role: .user, text: prompt, backend: backend))
        let assistantId = UUID()
        messages.append(AgentChatMessage(id: assistantId, role: .assistant, text: "", backend: backend, isStreaming: true))

        isRunning = true
        wasStoppedByUser = false

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let streamState = ProcessStreamState()

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                streamState.markStdoutReceived()
                Task { @MainActor [weak self] in
                    self?.appendChunk(chunk, to: assistantId)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                streamState.appendStderr(data)
            }
        }

        process.terminationHandler = { [weak self] proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            let remainingOut = outPipe.fileHandleForReading.readDataToEndOfFile()
            let remainingErr = errPipe.fileHandleForReading.readDataToEndOfFile()
            if !remainingErr.isEmpty {
                streamState.appendStderr(remainingErr)
            }
            let tailText = String(data: remainingOut, encoding: .utf8) ?? ""
            if !tailText.isEmpty {
                streamState.markStdoutReceived()
            }

            let snap = streamState.snapshot()
            let status = proc.terminationStatus

            Task { @MainActor [weak self] in
                guard let self else { return }
                if !tailText.isEmpty {
                    self.appendChunk(tailText, to: assistantId)
                }
                self.finishTurn(
                    messageId: assistantId,
                    exitStatus: status,
                    hasStdout: snap.hasStdout,
                    stderrText: snap.stderrText,
                    appState: appState
                )
            }
        }

        do {
            activeProcess = process
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil
            isRunning = false
            updateMessage(id: assistantId, role: .error, text: "Failed to launch \(backend.displayName): \(error.localizedDescription)", streaming: false)
        }
    }

    func stop() {
        wasStoppedByUser = true
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
        }
        activeProcess = nil
        isRunning = false
        for idx in messages.indices where messages[idx].isStreaming {
            messages[idx].isStreaming = false
            if messages[idx].text.isEmpty {
                messages[idx].text = "Stopped."
            }
        }
    }

    func clear() {
        if isRunning {
            stop()
        }
        messages.removeAll()
    }

    private func appendChunk(_ chunk: String, to id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += chunk
    }

    private func updateMessage(id: UUID, role: AgentChatMessage.Role, text: String, streaming: Bool) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx] = AgentChatMessage(
            id: id,
            role: role,
            text: text,
            backend: messages[idx].backend,
            timestamp: messages[idx].timestamp,
            isStreaming: streaming
        )
    }

    private func finishTurn(
        messageId: UUID,
        exitStatus: Int32,
        hasStdout: Bool,
        stderrText: String,
        appState: AppState
    ) {
        activeProcess = nil
        isRunning = false

        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].isStreaming = false

        if wasStoppedByUser {
            return
        }

        let trimmedOut = messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedErr = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)

        if exitStatus != 0 && trimmedOut.isEmpty {
            let errMsg = trimmedErr.isEmpty ? "Process exited with status \(exitStatus)." : trimmedErr
            updateMessage(id: messageId, role: .error, text: errMsg, streaming: false)
            return
        }

        if trimmedOut.isEmpty && !hasStdout {
            updateMessage(id: messageId, role: .assistant, text: trimmedErr.isEmpty ? "Done (no output)." : trimmedErr, streaming: false)
            return
        }

        Task {
            await appState.refreshCurrentSection()
        }
    }
}

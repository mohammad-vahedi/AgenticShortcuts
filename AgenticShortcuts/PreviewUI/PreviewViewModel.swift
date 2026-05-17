import Foundation
import SwiftUI

enum PreviewPipelineStage: Int, CaseIterable, Identifiable {
    case extractSchedule, inferName, generateCode, compile, install

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .extractSchedule: return "Extract Schedule"
        case .inferName:       return "Infer Name"
        case .generateCode:    return "Generate Code"
        case .compile:         return "Compile"
        case .install:         return "Install"
        }
    }
}

enum PreviewStageState {
    case pending, active, done, failed, skipped
}

struct PreviewLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let message: String

    enum Kind: Equatable {
        case info, success, warning, error, retry
    }

    static func == (lhs: PreviewLogEntry, rhs: PreviewLogEntry) -> Bool { lhs.id == rhs.id }
}

@MainActor
@Observable
final class PreviewViewModel {
    let generator = ShortcutGenerator()
    private let ollamaService = OllamaService()

    // Persisted projects (in-memory; same as MainView today)
    var projects: [ShortcutProject] = []
    var selectedProjectID: UUID?

    // Composer state
    var prompt: String = ""
    var selectedModel: String =
        UserDefaults.standard.string(forKey: "selectedModel") ?? "qwen2.5-coder:7b"
    let availableModels = ["mistral:7b", "qwen2.5-coder:7b", "qwen3:8b", "qwen3.5:9b"]

    // Pipeline state
    var stageStates: [PreviewPipelineStage: PreviewStageState] = [:]
    var activeStage: PreviewPipelineStage?
    var attemptCount: Int = 0
    var retryUsed: Bool = false
    var compileStartedAt: Date?
    var compileDuration: TimeInterval?

    // Logs + raw model response
    var logs: [PreviewLogEntry] = []
    var firstAttemptError: String?
    var rawModelResponse: String = ""

    // Connection status
    var ollamaConnected: Bool = false

    // Sidebar selection
    var navSelection: NavSection = .create
    enum NavSection: Hashable { case create, history, schedules, settings }

    // Inspector tags / notes (in-memory only — temp UI surface)
    var tagsByProject: [UUID: [String]] = [:]
    var notesByProject: [UUID: String] = [:]

    init() {
        resetStages()
    }

    var selectedProject: ShortcutProject? {
        get { projects.first(where: { $0.id == selectedProjectID }) }
    }

    func bindingForSelectedProject() -> Binding<ShortcutProject>? {
        guard let id = selectedProjectID,
              let idx = projects.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.projects[idx] },
            set: { self.projects[idx] = $0 }
        )
    }

    func tags(for project: ShortcutProject) -> [String] {
        tagsByProject[project.id] ?? []
    }

    func addTag(_ tag: String, to project: ShortcutProject) {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var list = tagsByProject[project.id] ?? []
        guard !list.contains(cleaned) else { return }
        list.append(cleaned)
        tagsByProject[project.id] = list
    }

    func removeTag(_ tag: String, from project: ShortcutProject) {
        tagsByProject[project.id]?.removeAll { $0 == tag }
    }

    func note(for project: ShortcutProject) -> String {
        notesByProject[project.id] ?? ""
    }

    func setNote(_ note: String, for project: ShortcutProject) {
        notesByProject[project.id] = note
    }

    // MARK: - Health

    func checkOllamaHealth() async {
        ollamaConnected = await ollamaService.isAvailable()
    }

    // MARK: - Generation

    func generate() async {
        let description = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        guard !generator.isGenerating else { return }

        UserDefaults.standard.set(selectedModel, forKey: "selectedModel")

        resetStages()
        log(.info, "Starting generation with \(selectedModel)…")

        let monitor = startStatusMonitor()

        var project = ShortcutProject(prompt: description)

        do {
            let result = try await generator.generate(description: description, model: selectedModel)
            monitor.cancel()

            project.cherriCode = result.cherriCode
            project.schedule = result.schedule
            project.name = result.inferredName.isEmpty ? description : result.inferredName
            rawModelResponse = result.cherriCode

            if result.success {
                project.shortcutURL = result.shortcutURL
                project.status = .compiled
                markStage(.compile, .done)
                markStage(.install, .pending) // user-driven; install means "Add to Shortcuts"
                if let started = compileStartedAt {
                    compileDuration = Date().timeIntervalSince(started)
                }
                log(.success, "Compile successful")
            } else {
                project.status = .failed
                project.compilationError = result.error
                markStage(.compile, .failed)
                if let err = result.error {
                    log(.error, "Compilation failed: \(truncate(err))")
                }
            }
        } catch {
            monitor.cancel()
            project.status = .failed
            project.compilationError = error.localizedDescription
            markStage(activeStage ?? .generateCode, .failed)
            log(.error, "Pipeline error: \(error.localizedDescription)")
        }

        projects.insert(project, at: 0)
        selectedProjectID = project.id
        prompt = ""
    }

    // MARK: - Recompile / Sign / Install

    func recompileSelected() async {
        guard let binding = bindingForSelectedProject() else { return }
        log(.info, "Recompiling current code…")
        do {
            let result = try await generator.recompile(
                code: binding.wrappedValue.cherriCode,
                name: binding.wrappedValue.name.isEmpty ? binding.wrappedValue.prompt : binding.wrappedValue.name
            )
            if result.success {
                binding.wrappedValue.shortcutURL = result.shortcutURL
                binding.wrappedValue.status = .compiled
                binding.wrappedValue.compilationError = nil
                markStage(.compile, .done)
                log(.success, "Recompile successful")
            } else {
                binding.wrappedValue.status = .failed
                binding.wrappedValue.compilationError = result.error
                markStage(.compile, .failed)
                log(.error, "Recompile failed: \(truncate(result.error ?? ""))")
            }
        } catch {
            log(.error, "Recompile error: \(error.localizedDescription)")
        }
    }

    func addToShortcuts() async {
        guard let binding = bindingForSelectedProject(),
              binding.wrappedValue.status == .compiled else { return }
        do {
            let signed = try await generator.signAndExport(
                code: binding.wrappedValue.cherriCode,
                name: binding.wrappedValue.name.isEmpty ? binding.wrappedValue.prompt : binding.wrappedValue.name
            )
            let shortcutName = signed.deletingPathExtension().lastPathComponent

            #if canImport(AppKit)
            NSWorkspace.shared.open(signed)
            #endif

            if let schedule = binding.wrappedValue.schedule {
                try await Task.sleep(for: .seconds(1))
                try await generator.installSchedule(schedule, shortcutName: shortcutName)
                binding.wrappedValue.isScheduleInstalled = true
                markStage(.install, .done)
                log(.success, "Schedule installed (\(schedule.displayDescription))")
            } else {
                markStage(.install, .done)
                log(.success, "Opened in Shortcuts")
            }
        } catch {
            log(.error, "Install failed: \(error.localizedDescription)")
        }
    }

    func revealInFinder() {
        guard let url = selectedProject?.shortcutURL else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    func openInShortcuts() {
        guard let url = selectedProject?.shortcutURL else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: - Signing

    var isSigning: Bool = false
    var signMessage: String?

    /// Produce a signed .shortcut from the current project's source.
    /// Returns the URL of the signed file written to ~/Shortcuts.
    @discardableResult
    func signSelected() async -> URL? {
        guard let binding = bindingForSelectedProject(),
              binding.wrappedValue.status == .compiled else { return nil }
        isSigning = true
        signMessage = nil
        defer { isSigning = false }

        let name = binding.wrappedValue.name.isEmpty
            ? binding.wrappedValue.prompt
            : binding.wrappedValue.name

        do {
            let signedURL = try await generator.signAndExport(
                code: binding.wrappedValue.cherriCode,
                name: name
            )
            binding.wrappedValue.shortcutURL = signedURL
            signMessage = "Signed → \(signedURL.lastPathComponent)"
            log(.success, "Signed shortcut written to \(signedURL.path)")
            return signedURL
        } catch {
            signMessage = "Sign failed: \(error.localizedDescription)"
            log(.error, "Signing failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Sign and immediately open in the Shortcuts app. Installs schedule if present.
    func signAndOpen() async {
        guard let signedURL = await signSelected() else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(signedURL)
        #endif

        guard let binding = bindingForSelectedProject(),
              let schedule = binding.wrappedValue.schedule,
              !binding.wrappedValue.isScheduleInstalled else {
            markStage(.install, .done)
            return
        }
        do {
            let shortcutName = signedURL.deletingPathExtension().lastPathComponent
            try await Task.sleep(for: .seconds(1))
            try await generator.installSchedule(schedule, shortcutName: shortcutName)
            binding.wrappedValue.isScheduleInstalled = true
            markStage(.install, .done)
            log(.success, "Schedule installed (\(schedule.displayDescription))")
        } catch {
            log(.error, "Schedule install failed: \(error.localizedDescription)")
        }
    }

    /// Sign and present a save panel so the user can pick where to write the signed file.
    @MainActor
    func signAndSaveAs() async {
        guard let signedURL = await signSelected() else { return }
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.title = "Save Signed Shortcut"
        panel.nameFieldStringValue = signedURL.lastPathComponent
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: signedURL, to: destination)
            signMessage = "Saved → \(destination.lastPathComponent)"
            log(.success, "Saved signed copy to \(destination.path)")
        } catch {
            signMessage = "Save failed: \(error.localizedDescription)"
            log(.error, "Save failed: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Status monitor — translates generator.currentStatus strings into stages + logs

    private func startStatusMonitor() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            var lastStatus = ""
            while !Task.isCancelled {
                let status = await MainActor.run { self.generator.currentStatus }
                if status != lastStatus {
                    await MainActor.run { self.handleStatusChange(from: lastStatus, to: status) }
                    lastStatus = status
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func handleStatusChange(from old: String, to new: String) {
        switch new {
        case "Analyzing schedule...":
            markStage(.extractSchedule, .active)
            log(.info, "Extracting schedule from prompt…")

        case "Generating Cherri code...":
            markStage(.extractSchedule, .done)
            markStage(.inferName, .active)   // runs in parallel with code generation
            markStage(.generateCode, .active)
            log(.info, "Generating code with \(selectedModel)…")
            attemptCount = 1

        case "Wrong language detected — correcting...":
            log(.warning, "Wrong language detected — correcting…")
            retryUsed = true
            attemptCount += 1

        case "Compiling shortcut...":
            markStage(.inferName, .done)
            markStage(.generateCode, .done)
            markStage(.compile, .active)
            compileStartedAt = Date()
            log(.info, "Compiling shortcut…")

        case "Repairing with compiler feedback...":
            // First attempt failed — capture that error if exposed via compilationError on the project (we may not have it yet)
            log(.warning, "First compile attempt failed — retrying with compiler feedback…")
            retryUsed = true
            attemptCount += 1
            if firstAttemptError == nil {
                firstAttemptError = "Compiler rejected the first attempt — see retry log."
            }

        case "":
            break  // done — handled by the outer awaiter
        default:
            log(.info, new)
        }
    }

    // MARK: - State helpers

    func resetStages() {
        for stage in PreviewPipelineStage.allCases {
            stageStates[stage] = .pending
        }
        activeStage = nil
        attemptCount = 0
        retryUsed = false
        compileStartedAt = nil
        compileDuration = nil
        firstAttemptError = nil
        logs = []
        rawModelResponse = ""
    }

    private func markStage(_ stage: PreviewPipelineStage, _ state: PreviewStageState) {
        stageStates[stage] = state
        if state == .active {
            activeStage = stage
        }
    }

    private func log(_ kind: PreviewLogEntry.Kind, _ message: String) {
        logs.append(PreviewLogEntry(timestamp: Date(), kind: kind, message: message))
    }

    private func truncate(_ s: String, max: Int = 220) -> String {
        s.count > max ? String(s.prefix(max)) + "…" : s
    }
}

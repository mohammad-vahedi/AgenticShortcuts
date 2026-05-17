import SwiftUI

struct CodePreviewView: View {
    @Binding var project: ShortcutProject
    var generator: ShortcutGenerator
    var onNewShortcut: () -> Void

    enum EditMode { case none, prompt, code }

    @State private var editMode: EditMode = .none
    @State private var editedPrompt: String = ""
    @State private var editedCode: String = ""
    @State private var isEditingName = false
    @State private var editedName: String = ""
    @State private var isWorking = false
    @State private var isSigning = false
    @State private var errorMessage: String?
    @State private var scheduleMessage: String?
    @AppStorage("selectedModel") private var selectedModel = "qwen2.5-coder:7b"

    private let models = ["mistral:7b", "qwen2.5-coder:7b", "qwen3:8b", "qwen3.5:9b"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let schedule = project.schedule {
                scheduleBar(schedule)
                Divider()
            }
            codeArea
            Divider()
            bottomBar
        }
        .onAppear {
            editedCode = project.cherriCode
            editedPrompt = project.prompt
        }
        .onChange(of: project.id) {
            editedCode = project.cherriCode
            editedPrompt = project.prompt
            editedName = project.name
            editMode = .none
            isEditingName = false
            errorMessage = nil
            scheduleMessage = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // Editable shortcut name
                if isEditingName {
                    HStack(spacing: 6) {
                        TextField("Shortcut name", text: $editedName)
                            .font(.headline)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                            .onSubmit { commitName() }
                        Button("Save") { commitName() }
                            .controlSize(.small)
                        Button("Cancel") {
                            isEditingName = false
                            editedName = project.name
                        }
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(project.name.isEmpty ? project.prompt : project.name)
                            .font(.headline)
                            .lineLimit(1)
                        Button {
                            editedName = project.name.isEmpty ? project.prompt : project.name
                            isEditingName = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !project.prompt.isEmpty {
                    Text(project.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusBadge

            Button {
                onNewShortcut()
            } label: {
                Label("New Shortcut", systemImage: "plus.circle")
            }
        }
        .padding()
    }

    private func commitName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            project.name = trimmed
        }
        isEditingName = false
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch project.status {
        case .generating:
            Label("Generating", systemImage: "ellipsis.circle")
                .foregroundStyle(.orange)
        case .compiled:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Schedule Bar

    @State private var showScheduleDetail = false

    private func scheduleBar(_ schedule: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Summary row
            HStack(alignment: .top) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Schedule")
                            .font(.headline)
                        if project.isScheduleInstalled {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    HStack(spacing: 16) {
                        Label(String(format: "%02d:%02d", schedule.hour, schedule.minute), systemImage: "clock")
                        Label(schedule.recurrence.rawValue.capitalized, systemImage: "repeat")
                        if let days = schedule.durationDays {
                            Label("\(days) days", systemImage: "calendar")
                        } else {
                            Label("Indefinite", systemImage: "infinity")
                        }
                    }
                    .font(.callout)

                    if let expiry = schedule.expiryDate {
                        Text("Until \(expiry.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(spacing: 6) {
                    Button {
                        showScheduleDetail.toggle()
                    } label: {
                        Label(showScheduleDetail ? "Hide Details" : "Show Details", systemImage: showScheduleDetail ? "chevron.up" : "chevron.down")
                    }
                    .controlSize(.small)

                    if project.isScheduleInstalled {
                        Button(role: .destructive) {
                            Task { await removeSchedule(schedule) }
                        } label: {
                            Label("Remove", systemImage: "calendar.badge.minus")
                        }
                        .controlSize(.small)
                    }
                }
            }

            // Explanation
            VStack(alignment: .leading, spacing: 4) {
                Text("Your request produces two things:")
                    .font(.caption)
                    .fontWeight(.medium)
                HStack(alignment: .top, spacing: 8) {
                    Label {
                        Text("Shortcut = the action (Cherri code below)")
                    } icon: {
                        Image(systemName: "1.circle.fill").foregroundStyle(.blue)
                    }
                    .font(.caption)
                    Label {
                        Text("Schedule = a macOS job that runs the shortcut at the set time")
                    } icon: {
                        Image(systemName: "2.circle.fill").foregroundStyle(.blue)
                    }
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            // Expanded detail: show the launchd plist preview
            if showScheduleDetail {
                VStack(alignment: .leading, spacing: 4) {
                    Text("launchd Schedule Config (auto-generated)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        Text(launchdPreview(schedule))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: 140)
                    .background(.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if let msg = scheduleMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(.blue.opacity(0.05))
    }

    private func launchdPreview(_ schedule: Schedule) -> String {
        let name = project.shortcutURL?.deletingPathExtension().lastPathComponent ?? "shortcut"
        var interval = ""
        if let weekday = schedule.weekday, schedule.recurrence == .weekly {
            interval += "        <key>Weekday</key>\n        <integer>\(weekday)</integer>\n"
        }
        interval += "        <key>Hour</key>\n        <integer>\(schedule.hour)</integer>\n"
        interval += "        <key>Minute</key>\n        <integer>\(schedule.minute)</integer>"

        var expiryNote = ""
        if let days = schedule.durationDays, let expiry = schedule.expiryDate {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            expiryNote = "\n<!-- Auto-removes after \(days) days (\(fmt.string(from: expiry))) -->"
        }

        return """
        <!-- \(schedule.plistIdentifier).plist -->\(expiryNote)
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(schedule.plistIdentifier)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/shortcuts</string>
                <string>run</string>
                <string>\(name)</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
        \(interval)
            </dict>
        </dict>
        </plist>
        """
    }

    // MARK: - Code / Prompt Area

    @ViewBuilder
    private var codeArea: some View {
        switch editMode {
        case .prompt:
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit your description and regenerate:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                TextEditor(text: $editedPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)

                HStack {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 200)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(.background.secondary)

        case .code:
            TextEditor(text: $editedCode)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.secondary)

        case .none:
            ScrollView {
                Text(project.cherriCode)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(.background.secondary)
        }
    }

    // MARK: - Bottom Bar

    private var displayError: String? {
        errorMessage ?? (project.status == .failed ? project.compilationError : nil)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let error = displayError {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Error")
                            .font(.callout)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(error, forType: .string)
                        } label: {
                            Label("Copy Error", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                    }
                    ScrollView {
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(.red.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack {
                // Edit Prompt button
                Button {
                    if editMode == .prompt {
                        editMode = .none
                    } else {
                        editedPrompt = project.prompt
                        editMode = .prompt
                    }
                } label: {
                    Label(
                        editMode == .prompt ? "Cancel" : "Edit Prompt",
                        systemImage: editMode == .prompt ? "xmark" : "text.cursor"
                    )
                }

                // Edit Code button
                Button {
                    if editMode == .code {
                        editMode = .none
                    } else {
                        editedCode = project.cherriCode
                        editMode = .code
                    }
                } label: {
                    Label(
                        editMode == .code ? "Cancel" : "Edit Code",
                        systemImage: editMode == .code ? "xmark" : "chevron.left.forwardslash.chevron.right"
                    )
                }

                // Action button based on edit mode
                if editMode == .prompt {
                    Button {
                        Task { await regenerate() }
                    } label: {
                        if isWorking {
                            ProgressView().controlSize(.small).padding(.trailing, 2)
                            Text("Regenerating...")
                        } else {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if editMode == .code {
                    Button {
                        Task { await recompile() }
                    } label: {
                        if isWorking {
                            ProgressView().controlSize(.small).padding(.trailing, 2)
                            Text("Compiling...")
                        } else {
                            Label("Recompile", systemImage: "hammer")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                }

                if editMode == .none, project.status == .compiled {
                    Button {
                        Task { await addToShortcuts() }
                    } label: {
                        if isSigning {
                            ProgressView().controlSize(.small).padding(.trailing, 2)
                            Text(project.schedule != nil ? "Installing..." : "Signing...")
                        } else if project.schedule != nil {
                            Label("Add to Shortcuts & Schedule", systemImage: "calendar.badge.plus")
                        } else {
                            Label("Add to Shortcuts", systemImage: "plus.app")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigning)

                    if let url = project.shortcutURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Finder", systemImage: "folder")
                        }
                    }
                }

                Spacer()

                Button {
                    let text = editMode == .code ? editedCode : project.cherriCode
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                }
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func regenerate() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let description = editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }

        do {
            let result = try await generator.generate(description: description, model: selectedModel)
            project.cherriCode = result.cherriCode
            project.schedule = result.schedule
            project.name = result.inferredName
            editedCode = result.cherriCode
            if result.success {
                project.shortcutURL = result.shortcutURL
                project.status = .compiled
                project.compilationError = nil
                editMode = .none
            } else {
                project.status = .failed
                project.compilationError = result.error
                errorMessage = result.error
            }
        } catch {
            project.status = .failed
            project.compilationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func recompile() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        project.cherriCode = editedCode

        do {
            let result = try await generator.recompile(code: editedCode, name: project.prompt)
            if result.success {
                project.shortcutURL = result.shortcutURL
                project.status = .compiled
                project.compilationError = nil
                editMode = .none
            } else {
                project.status = .failed
                project.compilationError = result.error
                errorMessage = result.error
            }
        } catch {
            project.status = .failed
            project.compilationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func addToShortcuts() async {
        isSigning = true
        defer { isSigning = false }

        do {
            let signedURL = try await generator.signAndExport(
                code: project.cherriCode,
                name: project.prompt
            )
            let shortcutName = signedURL.deletingPathExtension().lastPathComponent

            NSWorkspace.shared.open(signedURL)

            if let schedule = project.schedule {
                try await Task.sleep(for: .seconds(2))
                try await generator.installSchedule(schedule, shortcutName: shortcutName)
                project.isScheduleInstalled = true
                scheduleMessage = "Shortcut added + schedule installed (\(schedule.displayDescription))"
            }
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func installSchedule(_ schedule: Schedule) async {
        let name = project.shortcutURL?
            .deletingPathExtension()
            .lastPathComponent ?? "shortcut"

        do {
            try await generator.installSchedule(schedule, shortcutName: name)
            project.isScheduleInstalled = true
            scheduleMessage = "Scheduled!"
        } catch {
            scheduleMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func removeSchedule(_ schedule: Schedule) async {
        do {
            try await generator.uninstallSchedule(schedule)
            project.isScheduleInstalled = false
            scheduleMessage = "Removed"
        } catch {
            scheduleMessage = "Failed: \(error.localizedDescription)"
        }
    }
}

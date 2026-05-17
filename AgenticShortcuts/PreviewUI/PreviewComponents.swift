import SwiftUI

// MARK: - Card chrome

struct PreviewCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(.tint)
                    }
                    Text(title).font(.headline)
                }
            }
            content
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Prompt composer card

struct PreviewPromptCard: View {
    @Bindable var vm: PreviewViewModel

    var body: some View {
        PreviewCard(title: "Describe the shortcut you want to create", systemImage: nil) {
            ZStack(alignment: .topTrailing) {
                TextEditor(text: $vm.prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 84)
                    .padding(10)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    )

                Button {
                    // mic placeholder — speech-to-text isn't wired in this preview
                } label: {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(10)
                .help("Voice input (coming soon)")
            }

            HStack(spacing: 10) {
                Button {
                    Task { await vm.generate() }
                } label: {
                    HStack(spacing: 6) {
                        if vm.generator.isGenerating {
                            ProgressView().controlSize(.small)
                            Text(vm.generator.currentStatus.isEmpty ? "Working…" : vm.generator.currentStatus)
                        } else {
                            Image(systemName: "play.fill")
                            Text("Generate")
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(vm.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.generator.isGenerating)

                Button(role: .cancel) {
                    // Stop placeholder — generator doesn't expose cancellation today
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                }
                .disabled(!vm.generator.isGenerating)

                Spacer()

                HStack(spacing: 4) {
                    Text("Model:").foregroundStyle(.secondary)
                    Picker("Model", selection: $vm.selectedModel) {
                        ForEach(vm.availableModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }
        }
    }
}

// MARK: - Detected schedule card

struct PreviewDetectedScheduleCard: View {
    let schedule: Schedule

    var body: some View {
        PreviewCard(title: "Detected Schedule", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 6) {
                Text(humanTime)
                    .font(.title3.weight(.semibold))
                if let days = schedule.durationDays {
                    Text("for \(days) days")
                        .foregroundStyle(.secondary)
                }
                Text(startsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var humanTime: String {
        let timeStr = String(format: "%02d:%02d", schedule.hour, schedule.minute)
        switch schedule.recurrence {
        case .once: return "Once at \(timeStr)"
        case .daily: return "Every day at \(timeStr)"
        case .weekly: return "Weekly at \(timeStr)"
        }
    }

    private var startsLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(schedule.startDate) { return "Starts: Today" }
        if cal.isDateInTomorrow(schedule.startDate) { return "Starts: Tomorrow" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return "Starts: \(fmt.string(from: schedule.startDate))"
    }
}

// MARK: - Pipeline stepper

struct PreviewPipelineStepper: View {
    let stageStates: [PreviewPipelineStage: PreviewStageState]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PreviewPipelineStage.allCases.enumerated()), id: \.element.id) { index, stage in
                stepView(index: index + 1, stage: stage, state: stageStates[stage] ?? .pending)
                if index < PreviewPipelineStage.allCases.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: 30)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stepView(index: Int, stage: PreviewPipelineStage, state: PreviewStageState) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(circleFill(state))
                    .frame(width: 22, height: 22)
                circleContent(index: index, state: state)
            }
            Text(stage.title)
                .font(.callout)
                .foregroundStyle(state == .pending ? .secondary : .primary)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func circleContent(index: Int, state: PreviewStageState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        case .active:
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        case .failed:
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        case .pending, .skipped:
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func circleFill(_ state: PreviewStageState) -> Color {
        switch state {
        case .done: return .green
        case .active: return .blue
        case .failed: return .red
        case .pending, .skipped: return Color.secondary.opacity(0.15)
        }
    }
}

// MARK: - Code block (dark themed)

struct PreviewCodeBlock: View {
    let filename: String
    let code: String
    var onCopy: () -> Void = {}
    var onEdit: () -> Void = {}
    var onExpand: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filename)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                toolbarButton("doc.on.doc", "Copy", onCopy)
                toolbarButton("pencil", "Edit", onEdit)
                toolbarButton("arrow.up.left.and.arrow.down.right", "Expand", onExpand)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.13, green: 0.14, blue: 0.18))

            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 12) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(lines.indices), id: \.self) { i in
                            Text("\(i + 1)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            highlightedLine(line)
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                .padding(12)
            }
            .background(Color(red: 0.10, green: 0.11, blue: 0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
        )
    }

    private var lines: [String] {
        code.components(separatedBy: "\n")
    }

    @ViewBuilder
    private func highlightedLine(_ line: String) -> some View {
        // Very light syntax coloring — string literals + @variables + keywords
        Text(attributed(line))
    }

    private func attributed(_ line: String) -> AttributedString {
        var out = AttributedString(line.isEmpty ? " " : line)
        out.foregroundColor = Color.white.opacity(0.92)

        // strings
        applyRegex(&out, in: line, pattern: #""[^"]*""#, color: Color(red: 0.95, green: 0.74, blue: 0.45))
        // @variables
        applyRegex(&out, in: line, pattern: #"@[A-Za-z_][\w]*"#, color: Color(red: 0.55, green: 0.82, blue: 1.0))
        // keywords
        applyRegex(&out, in: line, pattern: #"\b(const|if|else|for|repeat|menu|item|return|in)\b"#,
                   color: Color(red: 0.85, green: 0.55, blue: 0.95))
        // comments
        if let r = line.range(of: #"//.*"#, options: .regularExpression) {
            let ns = NSRange(r, in: line)
            if let attrRange = Range(ns, in: out) {
                out[attrRange].foregroundColor = Color.white.opacity(0.4)
            }
        }
        return out
    }

    private func applyRegex(_ out: inout AttributedString, in source: String, pattern: String, color: Color) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = NSRange(source.startIndex..., in: source)
        regex.enumerateMatches(in: source, range: ns) { match, _, _ in
            guard let match, let r = Range(match.range, in: source),
                  let attrRange = Range(NSRange(r, in: source), in: out) else { return }
            out[attrRange].foregroundColor = color
        }
    }

    private func toolbarButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compile result card

struct PreviewCompileResultCard: View {
    let project: ShortcutProject
    let durationSeconds: TimeInterval?
    let isSigning: Bool
    let signMessage: String?
    var onSignAndOpen: () -> Void
    var onSignAndSaveAs: () -> Void
    var onReveal: () -> Void

    var body: some View {
        PreviewCard(title: "Compile Result", systemImage: project.status == .compiled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") {
            VStack(spacing: 14) {
                if project.status == .compiled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Success!").font(.title3.weight(.semibold))
                    if let durationSeconds {
                        Text(String(format: "Compiled in %.1fs", durationSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(project.shortcutURL?.lastPathComponent ?? "\(project.name).shortcut")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Button(action: onSignAndOpen) {
                        HStack(spacing: 6) {
                            if isSigning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                            }
                            Text(isSigning ? "Signing…" : "Sign & Open in Shortcuts")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigning)

                    Button(action: onSignAndSaveAs) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save Signed File…")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isSigning)

                    Button(action: onReveal) {
                        Text("Reveal in Finder")
                            .frame(maxWidth: .infinity)
                    }

                    if let signMessage {
                        Text(signMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.red)
                    Text("Failed").font(.title3.weight(.semibold))
                    if let err = project.compilationError {
                        ScrollView {
                            Text(err)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 100)
                        .padding(8)
                        .background(.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Schedule (installed) card

struct PreviewScheduleCard: View {
    let schedule: Schedule
    let isInstalled: Bool
    var onManage: () -> Void

    var body: some View {
        PreviewCard(title: "Schedule", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(humanTime).font(.callout.weight(.medium))
                    Spacer()
                    if isInstalled {
                        Label("Installed", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.green.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Text("Pending install")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                if let days = schedule.durationDays {
                    Text("for \(days) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Starts: \(formatted(schedule.startDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let expiry = schedule.expiryDate {
                    Text("Ends:   \(formatted(expiry))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: onManage) {
                    Text("Manage Schedule…")
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
        }
    }

    private var humanTime: String {
        let timeStr = String(format: "%02d:%02d", schedule.hour, schedule.minute)
        switch schedule.recurrence {
        case .once: return "Once at \(timeStr)"
        case .daily: return "Every day at \(timeStr)"
        case .weekly: return "Weekly at \(timeStr)"
        }
    }

    private func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}

// MARK: - RAG examples disclosure

struct PreviewExamplesDisclosure: View {
    let count: Int
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "books.vertical")
                    .foregroundStyle(.tint)
                Text("Using \(count) relevant examples from the Cherri library")
                    .font(.callout)
                Spacer()
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Hide" : "Show")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if expanded {
                Text("Examples are chosen from CherriExamples.swift by keyword overlap with your prompt. They guide the model toward correct patterns and are not copied verbatim.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

import SwiftUI

struct PreviewInspector: View {
    @Bindable var vm: PreviewViewModel
    @State private var tab: Tab = .details
    @State private var newTag: String = ""
    @State private var noteDraft: String = ""

    enum Tab { case details, logs }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("Details", .details)
                tabButton("Logs", .logs)
            }
            .padding(.top, 8)
            .background(.background.secondary)

            Divider()

            ScrollView {
                if let project = vm.selectedProject {
                    if tab == .details {
                        detailsView(project: project)
                    } else {
                        logsView(project: project)
                    }
                } else {
                    emptyState
                }
            }
        }
        .frame(minWidth: 260)
        .background(.background)
    }

    private func tabButton(_ title: String, _ value: Tab) -> some View {
        Button {
            tab = value
        } label: {
            Text(title)
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(tab == value ? .primary : .secondary)
                .overlay(
                    Rectangle()
                        .fill(tab == value ? Color.accentColor : Color.clear)
                        .frame(height: 2),
                    alignment: .bottom
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Select a shortcut to see details")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Details

    @ViewBuilder
    private func detailsView(project: ShortcutProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Name
            field(label: "Name") {
                HStack {
                    Text(project.name.isEmpty ? "Untitled" : project.name)
                        .font(.callout.weight(.medium))
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Status
            field(label: "Status") {
                statusBadge(project.status)
            }

            field(label: "Created") {
                Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
            }

            field(label: "Model") {
                Text(vm.selectedModel).font(.caption.monospaced())
            }

            field(label: "Attempts") {
                Text(attemptsText)
                    .font(.caption)
            }

            field(label: "Location") {
                Text(project.shortcutURL?.path ?? "—")
                    .font(.caption2.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            // Tags
            field(label: "Tags") {
                FlowLayout(spacing: 6) {
                    ForEach(vm.tags(for: project), id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag).font(.caption)
                            Button {
                                vm.removeTag(tag, from: project)
                            } label: {
                                Image(systemName: "xmark").font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    HStack(spacing: 4) {
                        TextField("add tag", text: $newTag)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .onSubmit {
                                vm.addTag(newTag, to: project)
                                newTag = ""
                            }
                            .frame(maxWidth: 80)
                        Image(systemName: "plus.circle").foregroundStyle(.secondary).font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Capsule())
                }
            }

            // Actions
            let actions = extractActions(from: project.cherriCode)
            field(label: "Actions (\(actions.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(actions, id: \.self) { action in
                        HStack(spacing: 8) {
                            Image(systemName: actionIcon(for: action))
                                .foregroundStyle(.tint)
                                .frame(width: 18)
                            Text(prettyActionName(action))
                                .font(.caption)
                        }
                    }
                    if actions.isEmpty {
                        Text("No actions detected yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Notes
            field(label: "Notes") {
                TextEditor(text: Binding(
                    get: { vm.note(for: project) },
                    set: { vm.setNote($0, for: project) }
                ))
                .font(.caption)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 100)
                .padding(8)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
    }

    private var attemptsText: String {
        if vm.attemptCount == 0 { return "—" }
        if vm.retryUsed { return "\(vm.attemptCount) (\(vm.attemptCount - 1) retry)" }
        return "\(vm.attemptCount)"
    }

    @ViewBuilder
    private func statusBadge(_ status: ShortcutProject.Status) -> some View {
        switch status {
        case .compiled:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Completed").font(.caption.weight(.medium))
            }
        case .failed:
            HStack(spacing: 5) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text("Failed").font(.caption.weight(.medium))
            }
        case .generating:
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("Working").font(.caption.weight(.medium))
            }
        }
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func logsView(project: ShortcutProject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if vm.logs.isEmpty {
                Text("No log entries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ForEach(vm.logs) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Text(timestampShort(entry.timestamp))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func timestampShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    // MARK: - Action extraction

    private func extractActions(from code: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b([a-z][a-zA-Z0-9]+)\s*\("#) else { return [] }
        let ns = NSRange(code.startIndex..., in: code)
        var seen = Set<String>()
        var ordered: [String] = []
        regex.enumerateMatches(in: code, range: ns) { match, _, _ in
            guard let match,
                  let r = Range(match.range(at: 1), in: code) else { return }
            let name = String(code[r])
            // skip keywords / control-flow / built-ins we don't want to show
            let skip: Set<String> = ["if", "else", "for", "repeat", "in", "menu", "item",
                                      "return", "const", "true", "false"]
            if skip.contains(name) { return }
            if !seen.contains(name) {
                seen.insert(name)
                ordered.append(name)
            }
        }
        return ordered
    }

    private func actionIcon(for action: String) -> String {
        let lower = action.lowercased()
        if lower.contains("weather") { return "cloud.sun" }
        if lower.contains("clipboard") { return "doc.on.clipboard" }
        if lower.contains("webpage") || lower.contains("url") || lower.contains("fetch") { return "globe" }
        if lower.contains("show") || lower.contains("alert") { return "bubble.left" }
        if lower.contains("battery") { return "battery.100" }
        if lower.contains("dictionary") || lower.contains("json") { return "list.bullet.indent" }
        if lower.contains("shell") || lower.contains("run") { return "terminal" }
        if lower.contains("match") || lower.contains("regex") { return "magnifyingglass" }
        if lower.contains("send") || lower.contains("message") { return "paperplane" }
        if lower.contains("open") { return "arrow.up.right.square" }
        if lower.contains("dark") || lower.contains("setting") { return "moon" }
        return "circle.hexagongrid"
    }

    private func prettyActionName(_ camel: String) -> String {
        var out = ""
        for ch in camel {
            if ch.isUppercase && !out.isEmpty {
                out.append(" ")
            }
            out.append(ch)
        }
        return out.capitalized
    }
}

// MARK: - Simple flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

import SwiftUI

struct PreviewSidebar: View {
    @Bindable var vm: PreviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("Agentic Shortcuts")
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            // Nav
            VStack(spacing: 2) {
                navRow(.create, icon: "wand.and.stars", title: "Create")
                navRow(.history, icon: "clock.arrow.circlepath", title: "History")
                navRow(.schedules, icon: "calendar", title: "Schedules")
                navRow(.settings, icon: "gearshape", title: "Settings")
            }
            .padding(.horizontal, 8)

            // Recent projects
            Text("RECENT PROJECTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(vm.projects.prefix(10)) { project in
                        projectRow(project)
                    }
                    if vm.projects.count > 10 {
                        Button("Show All…") { vm.navSelection = .history }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .padding(.top, 6)
                    }
                    if vm.projects.isEmpty {
                        Text("No projects yet.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            // Footer status
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                HStack(spacing: 8) {
                    Circle()
                        .fill(vm.ollamaConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.ollamaConnected ? "Ollama: Connected" : "Ollama: Offline")
                            .font(.caption.weight(.medium))
                        Text("Model: \(vm.selectedModel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)

                Text("v0.1.0 — Preview UI")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .frame(minWidth: 220)
        .background(.background.secondary)
        .task { await vm.checkOllamaHealth() }
    }

    @ViewBuilder
    private func navRow(_ section: PreviewViewModel.NavSection, icon: String, title: String) -> some View {
        let isSelected = vm.navSelection == section
        Button {
            vm.navSelection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func projectRow(_ project: ShortcutProject) -> some View {
        let isSelected = vm.selectedProjectID == project.id
        Button {
            vm.selectedProjectID = project.id
            vm.navSelection = .create
        } label: {
            HStack(spacing: 10) {
                projectIcon(for: project)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name.isEmpty ? project.prompt : project.name)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .primary)
                    Text(relativeTime(project.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func projectIcon(for project: ShortcutProject) -> some View {
        switch project.status {
        case .compiled:  Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .generating: Image(systemName: "ellipsis.circle").foregroundStyle(.orange)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

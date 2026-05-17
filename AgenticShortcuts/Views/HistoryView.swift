import SwiftUI

struct HistoryView: View {
    let projects: [ShortcutProject]
    @Binding var selection: UUID?

    var body: some View {
        List(projects, selection: $selection) { project in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    statusIcon(for: project.status)
                    Text(project.prompt)
                        .lineLimit(1)
                        .font(.callout)
                }
                Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .tag(project.id)
        }
        .listStyle(.sidebar)
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView(
                    "No Shortcuts Yet",
                    systemImage: "wand.and.stars",
                    description: Text("Describe a shortcut to get started.")
                )
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ShortcutProject.Status) -> some View {
        switch status {
        case .generating:
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.orange)
        case .compiled:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

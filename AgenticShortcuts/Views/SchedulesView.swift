import SwiftUI

struct SchedulesView: View {
    @State private var activeSchedules: [String] = []
    @State private var isLoading = true
    @State private var removeMessage: String?

    private let scheduler = ScheduleService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            scheduleList
        }
    }

    private var header: some View {
        HStack {
            Label("Active Schedules", systemImage: "clock.badge.checkmark")
                .font(.headline)
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding()
    }

    private var scheduleList: some View {
        Group {
            if isLoading {
                ProgressView("Loading schedules...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if activeSchedules.isEmpty {
                ContentUnavailableView(
                    "No Active Schedules",
                    systemImage: "calendar.badge.clock",
                    description: Text("Schedules you install will appear here.")
                )
            } else {
                List {
                    ForEach(activeSchedules, id: \.self) { identifier in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayName(for: identifier))
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Text(identifier)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fontDesign(.monospaced)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                Task { await remove(identifier: identifier) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }

                    if let msg = removeMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        activeSchedules = await scheduler.listActive()
        isLoading = false
    }

    private func remove(identifier: String) async {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(identifier).plist")
        let scriptURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agenticshortcuts/scripts/\(identifier).sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]
        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: plistURL)
        try? FileManager.default.removeItem(at: scriptURL)

        removeMessage = "Removed \(displayName(for: identifier))"
        await refresh()
    }

    private func displayName(for identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "com.agenticshortcuts.", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

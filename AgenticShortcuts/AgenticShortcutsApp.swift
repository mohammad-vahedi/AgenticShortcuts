import SwiftUI

@main
struct AgenticShortcutsApp: App {
    var body: some Scene {
        WindowGroup {
            PreviewMainView()
        }
        .commands {
            CommandMenu("View") {
                OpenLegacyUIButton()
            }
        }

        Window("Schedules", id: "schedules") {
            SchedulesView()
                .frame(minWidth: 500, minHeight: 400)
        }

        Window("Legacy UI", id: "legacy-ui") {
            MainView()
        }

        Settings {
            SettingsView()
        }
    }
}

private struct OpenLegacyUIButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Legacy UI") {
            openWindow(id: "legacy-ui")
        }
        .keyboardShortcut("l", modifiers: [.command, .option])
    }
}

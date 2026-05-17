import AppIntents

struct AgenticShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateShortcutIntent(),
            phrases: [
                "Create a shortcut with \(.applicationName)",
                "Make a shortcut using \(.applicationName)",
                "Build a shortcut in \(.applicationName)",
                "Generate a shortcut with \(.applicationName)"
            ],
            shortTitle: "Create Shortcut",
            systemImageName: "wand.and.stars"
        )
    }
}

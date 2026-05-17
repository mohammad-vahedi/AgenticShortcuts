import AppIntents
import AppKit
import Foundation

struct CreateShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Create a Shortcut"
    static var description = IntentDescription("Generate an Apple Shortcut from a natural language description.")
    static var openAppWhenRun = false

    @Parameter(title: "Description", description: "Describe the shortcut you want to create",
               requestValueDialog: "What should the shortcut do?")
    var shortcutDescription: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let generator = ShortcutGenerator()
        let result = try await generator.generate(description: shortcutDescription)

        if result.success, let url = result.shortcutURL {
            let _ = await MainActor.run {
                NSWorkspace.shared.open(url)
            }
            return .result(dialog: "Your shortcut is ready and opening in Shortcuts!")
        } else {
            let errorMsg = result.error ?? "Unknown error"
            return .result(dialog: "Couldn't create that shortcut: \(errorMsg)")
        }
    }
}

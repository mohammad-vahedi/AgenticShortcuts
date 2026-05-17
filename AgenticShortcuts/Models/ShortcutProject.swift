import Foundation

struct ShortcutProject: Identifiable, Codable {
    let id: UUID
    let prompt: String
    var name: String          // user-visible shortcut name (editable, AI-inferred)
    var cherriCode: String
    var shortcutURL: URL?
    var status: Status
    var schedule: Schedule?
    var isScheduleInstalled: Bool
    var compilationError: String?
    let createdAt: Date

    enum Status: String, Codable {
        case generating
        case compiled
        case failed
    }

    init(prompt: String, name: String = "") {
        self.id = UUID()
        self.prompt = prompt
        self.name = name
        self.cherriCode = ""
        self.shortcutURL = nil
        self.status = .generating
        self.schedule = nil
        self.isScheduleInstalled = false
        self.compilationError = nil
        self.createdAt = Date()
    }
}

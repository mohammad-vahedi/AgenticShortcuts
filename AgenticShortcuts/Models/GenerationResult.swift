import Foundation

struct GenerationResult {
    let success: Bool
    let cherriCode: String
    let shortcutURL: URL?
    let schedule: Schedule?
    let error: String?
    let inferredName: String   // AI-inferred shortcut name
}

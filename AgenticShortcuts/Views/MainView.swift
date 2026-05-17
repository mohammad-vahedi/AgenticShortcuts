import SwiftUI

struct MainView: View {
    @State private var projects: [ShortcutProject] = []
    @State private var selectedProjectID: UUID?
    @State private var generator = ShortcutGenerator()
    @State private var showingPrompt = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            HistoryView(projects: projects, selection: $selectedProjectID)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            selectedProjectID = nil
                            showingPrompt = true
                        } label: {
                            Label("New Shortcut", systemImage: "plus")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            openWindow(id: "schedules")
                        } label: {
                            Label("Schedules", systemImage: "clock.badge.checkmark")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            openWindow(id: "preview-ui")
                        } label: {
                            Label("Preview UI", systemImage: "sparkles.rectangle.stack")
                        }
                        .help("Open the new three-column UI (⌥⌘U)")
                    }
                }
        } detail: {
            if showingPrompt || selectedProjectID == nil {
                PromptView(generator: generator) { project in
                    projects.insert(project, at: 0)
                    selectedProjectID = project.id
                    showingPrompt = false
                }
            } else if let idx = projects.firstIndex(where: { $0.id == selectedProjectID }) {
                CodePreviewView(project: $projects[idx], generator: generator) {
                    selectedProjectID = nil
                    showingPrompt = true
                }
            }
        }
        .navigationTitle("Agentic Shortcuts")
        .frame(minWidth: 800, minHeight: 500)
        .onChange(of: selectedProjectID) {
            if selectedProjectID != nil {
                showingPrompt = false
            }
        }
    }
}

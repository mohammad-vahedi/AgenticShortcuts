import SwiftUI

struct PromptView: View {
    @Bindable var generator: ShortcutGenerator
    var onGenerated: (ShortcutProject) -> Void

    @AppStorage("selectedModel") private var selectedModel = "qwen2.5-coder:7b"

    @State private var prompt = ""
    @State private var errorMessage: String?
    @State private var rewriteMessage: String?

    private let models = ["mistral:7b", "qwen2.5-coder:7b", "qwen3:8b", "qwen3.5:9b"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Describe your Shortcut")
                    .font(.title2)
                    .fontWeight(.medium)

                VStack(spacing: 12) {
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(maxWidth: 560, minHeight: 100, maxHeight: 160)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.quaternary, lineWidth: 1)
                        )

                    HStack {
                        Picker("Model", selection: $selectedModel) {
                            ForEach(models, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .frame(width: 220)

                        Button {
                            Task { await rewritePrompt() }
                        } label: {
                            if generator.isGenerating && generator.currentStatus == "Rewriting prompt..." {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("AI Prompt")
                            } else {
                                Image(systemName: "sparkles.rectangle.stack")
                                Text("AI Prompt")
                            }
                        }
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || generator.isGenerating)

                        Spacer()

                        Button {
                            Task { await generate() }
                        } label: {
                            if generator.isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text(generator.currentStatus)
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Generate")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || generator.isGenerating)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    .frame(maxWidth: 560)
                }

                if let rewriteMessage {
                    Text(rewriteMessage)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(maxWidth: 560, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            .padding(40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rewritePrompt() async {
        errorMessage = nil
        rewriteMessage = nil
        let description = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        do {
            let rewritten = try await generator.rewritePrompt(from: description, model: selectedModel)
            guard !rewritten.isEmpty else {
                rewriteMessage = "Rewrite returned empty — try a different model."
                return
            }
            prompt = rewritten
            rewriteMessage = "Prompt rewritten. Review it, then press Generate."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generate() async {
        errorMessage = nil
        rewriteMessage = nil
        let description = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }

        var project = ShortcutProject(prompt: description)

        do {
            let result = try await generator.generate(description: description, model: selectedModel)
            project.cherriCode = result.cherriCode
            project.schedule = result.schedule
            project.name = result.inferredName
            if result.success {
                project.shortcutURL = result.shortcutURL
                project.status = .compiled
            } else {
                project.status = .failed
                project.compilationError = result.error
                errorMessage = result.error
            }
        } catch {
            project.status = .failed
            project.compilationError = error.localizedDescription
            errorMessage = error.localizedDescription
        }

        onGenerated(project)
        prompt = ""
    }

}

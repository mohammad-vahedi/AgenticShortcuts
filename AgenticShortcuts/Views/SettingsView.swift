import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel = "qwen2.5-coder:7b"
    @AppStorage("cherriPath") private var cherriPath = "/opt/homebrew/bin/cherri"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("skipSigning") private var skipSigning = true
    @AppStorage("useAppleIntelligence") private var useAppleIntelligence = false

    @State private var ollamaStatus: ConnectionStatus = .unknown
    @State private var cherriVersion: String?

    private let models = ["mistral:7b", "qwen2.5-coder:7b", "qwen3:8b", "qwen3.5:9b"]

    var body: some View {
        Form {
            Section("AI Processing") {
                Toggle("Use Apple Intelligence to refine prompts", isOn: $useAppleIntelligence)
                    .font(.caption)

                Text("When enabled, your prompt will be refined using Apple Intelligence before sending to Ollama. Requires macOS Sequoia+ with Apple Intelligence enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("LLM") {
                Picker("Default Model", selection: $selectedModel) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                TextField("Ollama URL", text: $ollamaURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    connectionBadge
                    Spacer()
                    Button("Test Connection") {
                        Task { await checkOllama() }
                    }
                }
            }

            Section("Compiler") {
                TextField("Cherri Path", text: $cherriPath)
                    .textFieldStyle(.roundedBorder)
                Toggle("Skip signing (faster compilation)", isOn: $skipSigning)
                if let version = cherriVersion {
                    Text("Cherri \(version)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .task {
            await checkOllama()
            await checkCherri()
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch ollamaStatus {
        case .unknown:
            Label("Not checked", systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .disconnected:
            Label("Offline", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func checkOllama() async {
        let service = OllamaService(baseURL: URL(string: ollamaURL)!)
        ollamaStatus = await service.isAvailable() ? .connected : .disconnected
    }

    private func checkCherri() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cherriPath)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            cherriVersion = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            cherriVersion = nil
        }
    }

    enum ConnectionStatus {
        case unknown, connected, disconnected
    }
}

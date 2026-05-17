import Foundation

struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
}

struct OllamaChatResponseMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatResponse: Codable {
    let message: OllamaChatResponseMessage
    let done: Bool
}

actor OllamaService {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    func generate(prompt: String, systemPrompt: String, model: String = "qwen2.5-coder:7b") async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body = OllamaChatRequest(
            model: model,
            messages: [
                OllamaChatMessage(role: "system", content: systemPrompt),
                OllamaChatMessage(role: "user", content: prompt)
            ],
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw OllamaError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let chatResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return chatResponse.message.content
    }

    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

enum OllamaError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Ollama"
        case .httpError(let code, let body):
            return "Ollama returned HTTP \(code): \(body)"
        }
    }
}

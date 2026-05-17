import Foundation

struct CompilationResult {
    let shortcutURL: URL
    let output: String
}

actor CherriCompiler {
    private let cherriPath: String

    init(cherriPath: String = "/opt/homebrew/bin/cherri") {
        self.cherriPath = cherriPath
    }

    func compile(source: String, name: String, skipSign: Bool = false) async throws -> CompilationResult {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgenticShortcuts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let sanitizedName = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let sourceFile = tempDir.appendingPathComponent("\(sanitizedName).cherri")
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cherriPath)
        var arguments = [sourceFile.path]
        if skipSign {
            arguments.append("--skip-sign")
        }
        process.arguments = arguments
        process.currentDirectoryURL = tempDir

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errData, encoding: .utf8) ?? ""
        let combinedOutput = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            throw CherriError.compilationFailed(output: combinedOutput)
        }

        let signedFile = tempDir.appendingPathComponent("\(sanitizedName).shortcut")
        let unsignedFile = tempDir.appendingPathComponent("\(sanitizedName)_unsigned.shortcut")
        let shortcutFile: URL
        if FileManager.default.fileExists(atPath: signedFile.path) {
            shortcutFile = signedFile
        } else if FileManager.default.fileExists(atPath: unsignedFile.path) {
            shortcutFile = unsignedFile
        } else {
            throw CherriError.outputNotFound(expected: signedFile.path, compilerOutput: combinedOutput)
        }

        let outputDir = try shortcutsOutputDirectory()
        let destination = outputDir.appendingPathComponent("\(sanitizedName).shortcut")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: shortcutFile, to: destination)

        try? FileManager.default.removeItem(at: tempDir)

        return CompilationResult(shortcutURL: destination, output: combinedOutput)
    }

    private func shortcutsOutputDirectory() throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Shortcuts")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

enum CherriError: LocalizedError {
    case compilationFailed(output: String)
    case outputNotFound(expected: String, compilerOutput: String)

    var errorDescription: String? {
        switch self {
        case .compilationFailed(let output):
            return "Cherri compilation failed:\n\(output)"
        case .outputNotFound(let path, let output):
            return "Expected .shortcut file at \(path) not found.\nCompiler output: \(output)"
        }
    }
}

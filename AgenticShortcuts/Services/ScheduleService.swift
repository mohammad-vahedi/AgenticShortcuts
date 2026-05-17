import Foundation

actor ScheduleService {
    private let launchAgentsDir: URL
    private let scriptsDir: URL

    init() {
        self.launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        self.scriptsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agenticshortcuts/scripts")
    }

    func install(schedule: Schedule, shortcutName: String) async throws {
        try ensureDirectories()

        if let expiryDate = schedule.expiryDate {
            let scriptPath = try createWrapperScript(
                schedule: schedule,
                shortcutName: shortcutName,
                expiryDate: expiryDate
            )
            try createPlist(schedule: schedule, programPath: scriptPath)
        } else {
            try createPlist(schedule: schedule, shortcutName: shortcutName)
        }

        try loadAgent(identifier: schedule.plistIdentifier)
    }

    func uninstall(schedule: Schedule) async throws {
        let plistPath = launchAgentsDir.appendingPathComponent("\(schedule.plistIdentifier).plist")
        let scriptPath = scriptsDir.appendingPathComponent("\(schedule.plistIdentifier).sh")

        try? unloadAgent(identifier: schedule.plistIdentifier)

        try? FileManager.default.removeItem(at: plistPath)
        try? FileManager.default.removeItem(at: scriptPath)
    }

    func listActive() async -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: launchAgentsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("com.agenticshortcuts.") }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    private func ensureDirectories() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: launchAgentsDir.path) {
            try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: scriptsDir.path) {
            try fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        }
    }

    private func createWrapperScript(schedule: Schedule, shortcutName: String, expiryDate: Date) throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let expiryStr = formatter.string(from: expiryDate)
        let identifier = schedule.plistIdentifier
        let plistPath = launchAgentsDir.appendingPathComponent("\(identifier).plist").path
        let scriptPath = scriptsDir.appendingPathComponent("\(identifier).sh")

        let script = """
        #!/bin/bash
        EXPIRY_DATE="\(expiryStr)"
        TODAY=$(date +%Y-%m-%d)
        if [[ "$TODAY" > "$EXPIRY_DATE" ]]; then
            launchctl bootout gui/$(id -u) "\(plistPath)" 2>/dev/null
            rm -f "\(plistPath)"
            rm -f "\(scriptPath.path)"
            exit 0
        fi
        /usr/bin/shortcuts run "\(shortcutName)"
        """

        try script.write(to: scriptPath, atomically: true, encoding: .utf8)

        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath.path)

        return scriptPath.path
    }

    private func createPlist(schedule: Schedule, shortcutName: String) throws {
        let plistPath = launchAgentsDir.appendingPathComponent("\(schedule.plistIdentifier).plist")
        let content = buildPlistXML(
            identifier: schedule.plistIdentifier,
            programArguments: ["/usr/bin/shortcuts", "run", shortcutName],
            schedule: schedule
        )
        try content.write(to: plistPath, atomically: true, encoding: .utf8)
    }

    private func createPlist(schedule: Schedule, programPath: String) throws {
        let plistPath = launchAgentsDir.appendingPathComponent("\(schedule.plistIdentifier).plist")
        let content = buildPlistXML(
            identifier: schedule.plistIdentifier,
            programArguments: ["/bin/bash", programPath],
            schedule: schedule
        )
        try content.write(to: plistPath, atomically: true, encoding: .utf8)
    }

    private func buildPlistXML(identifier: String, programArguments: [String], schedule: Schedule) -> String {
        let argsXML = programArguments.map { "        <string>\($0)</string>" }.joined(separator: "\n")

        var calendarInterval = ""
        if let weekday = schedule.weekday, schedule.recurrence == .weekly {
            calendarInterval += "            <key>Weekday</key>\n            <integer>\(weekday)</integer>\n"
        }
        calendarInterval += "            <key>Hour</key>\n            <integer>\(schedule.hour)</integer>\n"
        calendarInterval += "            <key>Minute</key>\n            <integer>\(schedule.minute)</integer>"

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(identifier)</string>
            <key>ProgramArguments</key>
            <array>
        \(argsXML)
            </array>
            <key>StartCalendarInterval</key>
            <dict>
        \(calendarInterval)
            </dict>
            <key>StandardOutPath</key>
            <string>/tmp/\(identifier).log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/\(identifier).err</string>
        </dict>
        </plist>
        """
    }

    private func loadAgent(identifier: String) throws {
        let plistPath = launchAgentsDir.appendingPathComponent("\(identifier).plist").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath]
        try process.run()
        process.waitUntilExit()
    }

    private func unloadAgent(identifier: String) throws {
        let plistPath = launchAgentsDir.appendingPathComponent("\(identifier).plist").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistPath]
        try process.run()
        process.waitUntilExit()
    }
}

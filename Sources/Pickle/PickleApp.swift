import ArgumentParser
import Foundation
import CiderCore

@main
struct PickleApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pickle",
        abstract: "Keep your notes in a pickle (the good kind) - Apple Notes Version History",
        version: "1.0.0",
        subcommands: [
            InstallCommand.self,
            UninstallCommand.self,
            StartCommand.self,
            StopCommand.self,
            StatusCommand.self,
            HistoryCommand.self,
            DiffCommand.self,
            RestoreCommand.self,
            ExportCommand.self,
            ExportToNotesCommand.self,
            DaemonCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )
}

// MARK: - Shared Options

struct PickleGlobalOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
}

// MARK: - Utility Functions

func pickleSuccess(_ message: String) {
    print("✓ \(message)")
}

func pickleError(_ message: String) {
    print("✗ \(message)")
}

func pickleWarning(_ message: String) {
    print("⚠ \(message)")
}

func pickleInfo(_ message: String) {
    print("ℹ \(message)")
}

func pickleVerbose(_ message: String, verbose: Bool) {
    if verbose {
        print("  \(message)")
    }
}

// MARK: - launchd Helpers

struct LaunchdHelper {
    static let plistLabel = "com.pickle.daemon"

    static var plistPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(plistLabel).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath.path)
    }

    static var isRunning: Bool {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", plistLabel]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func generatePlist(picklePath: String, interval: Int) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(plistLabel)</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(picklePath)</string>
                <string>daemon</string>
                <string>--interval</string>
                <string>\(interval)</string>
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>

            <key>StandardOutPath</key>
            <string>\(home)/.pickle/logs/stdout.log</string>

            <key>StandardErrorPath</key>
            <string>\(home)/.pickle/logs/stderr.log</string>

            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/usr/local/bin:/usr/bin:/bin</string>
                <key>HOME</key>
                <string>\(home)</string>
            </dict>

            <key>ThrottleInterval</key>
            <integer>10</integer>

            <key>ProcessType</key>
            <string>Background</string>

            <key>LowPriorityBackgroundIO</key>
            <true/>

            <key>Nice</key>
            <integer>10</integer>
        </dict>
        </plist>
        """
    }

    static func launchctlLoad() throws {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", plistPath.path]
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw PickleError.launchctlFailed("load failed with status \(task.terminationStatus)")
        }
    }

    static func launchctlUnload() throws {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistPath.path]
        try task.run()
        task.waitUntilExit()

        // Don't throw on unload - it may not be loaded
    }

    static func launchctlStart() throws {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["start", plistLabel]
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw PickleError.launchctlFailed("start failed")
        }
    }

    static func launchctlStop() throws {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["stop", plistLabel]
        try task.run()
        task.waitUntilExit()
    }
}

// MARK: - Errors

enum PickleError: Error, LocalizedError {
    case notInstalled
    case alreadyInstalled
    case launchctlFailed(String)
    case noteNotFound(String)
    case versionNotFound(Int64)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Pickle daemon is not installed. Run 'pickle install' first."
        case .alreadyInstalled:
            return "Pickle daemon is already installed."
        case .launchctlFailed(let message):
            return "launchctl operation failed: \(message)"
        case .noteNotFound(let identifier):
            return "Note not found: \(identifier)"
        case .versionNotFound(let id):
            return "Version not found: \(id)"
        }
    }
}

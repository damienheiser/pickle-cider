import ArgumentParser
import Foundation
import CiderCore

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the Pickle daemon as a launchd service"
    )

    @Option(name: .long, help: "Check interval in seconds")
    var interval: Int = 30

    @Flag(name: .long, help: "Reinstall even if already installed")
    var force: Bool = false

    @OptionGroup var options: PickleGlobalOptions

    func run() throws {
        print("Pickle - Installing Daemon")
        print("")

        // Check if already installed
        if LaunchdHelper.isInstalled && !force {
            pickleWarning("Daemon is already installed")
            pickleInfo("Use --force to reinstall")
            return
        }

        // Find pickle executable path
        let picklePath = findExecutablePath()
        pickleVerbose("Executable path: \(picklePath)", verbose: options.verbose)

        // Create directories
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logDir = home.appendingPathComponent(".pickle/logs")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        pickleVerbose("Created log directory: \(logDir.path)", verbose: options.verbose)

        // Initialize database
        let _ = try VersionDatabase()
        pickleSuccess("Initialized version database")

        // Create plist
        let plistContent = LaunchdHelper.generatePlist(picklePath: picklePath, interval: interval)

        // Ensure LaunchAgents directory exists
        let launchAgentsDir = LaunchdHelper.plistPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        // Unload existing if reinstalling
        if LaunchdHelper.isInstalled {
            try? LaunchdHelper.launchctlUnload()
        }

        // Write plist
        try plistContent.write(to: LaunchdHelper.plistPath, atomically: true, encoding: .utf8)
        pickleSuccess("Created launchd plist: \(LaunchdHelper.plistPath.path)")

        // Load the service
        try LaunchdHelper.launchctlLoad()
        pickleSuccess("Loaded daemon service")

        print("")
        print("Pickle daemon installed successfully!")
        print("")
        print("Configuration:")
        print("  Check interval: \(interval) seconds")
        print("  Log files:      ~/.pickle/logs/")
        print("  Version DB:     ~/.pickle/versions.db")
        print("")
        print("Commands:")
        print("  pickle status   - Check daemon status")
        print("  pickle stop     - Stop the daemon")
        print("  pickle start    - Start the daemon")
        print("  pickle history  - View version history")
    }

    private func findExecutablePath() -> String {
        // Try to find the pickle executable
        // Prefer app bundle path for Full Disk Access inheritance
        let possiblePaths = [
            "/Applications/Pickle Cider.app/Contents/MacOS/pickle",  // Preferred: inherits app's FDA
            "/usr/local/bin/pickle",
            "/opt/homebrew/bin/pickle",
            Bundle.main.executablePath,
            ProcessInfo.processInfo.arguments.first,
        ].compactMap { $0 }

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback to current executable
        return ProcessInfo.processInfo.arguments.first ?? "/usr/local/bin/pickle"
    }
}

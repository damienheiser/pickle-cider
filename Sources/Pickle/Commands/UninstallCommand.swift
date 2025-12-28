import ArgumentParser
import Foundation
import CiderCore

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove the Pickle daemon service"
    )

    @Flag(name: .long, help: "Also delete version history database")
    var purge: Bool = false

    @OptionGroup var options: PickleGlobalOptions

    func run() throws {
        print("Pickle - Uninstalling Daemon")
        print("")

        if !LaunchdHelper.isInstalled {
            pickleWarning("Daemon is not installed")
            return
        }

        // Stop and unload the service
        try? LaunchdHelper.launchctlUnload()
        pickleSuccess("Unloaded daemon service")

        // Remove plist
        try FileManager.default.removeItem(at: LaunchdHelper.plistPath)
        pickleSuccess("Removed launchd plist")

        if purge {
            // Remove all pickle data
            let home = FileManager.default.homeDirectoryForCurrentUser
            let pickleDir = home.appendingPathComponent(".pickle")

            if FileManager.default.fileExists(atPath: pickleDir.path) {
                try FileManager.default.removeItem(at: pickleDir)
                pickleSuccess("Removed all Pickle data (~/.pickle)")
            }
        }

        print("")
        print("Pickle daemon uninstalled successfully!")

        if !purge {
            print("")
            pickleInfo("Version history preserved in ~/.pickle/")
            pickleInfo("Use --purge to delete all data")
        }
    }
}

struct StartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the Pickle daemon"
    )

    func run() throws {
        guard LaunchdHelper.isInstalled else {
            throw PickleError.notInstalled
        }

        if LaunchdHelper.isRunning {
            pickleWarning("Daemon is already running")
            return
        }

        try LaunchdHelper.launchctlStart()
        pickleSuccess("Daemon started")
    }
}

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the Pickle daemon"
    )

    func run() throws {
        guard LaunchdHelper.isInstalled else {
            throw PickleError.notInstalled
        }

        if !LaunchdHelper.isRunning {
            pickleWarning("Daemon is not running")
            return
        }

        try LaunchdHelper.launchctlStop()
        pickleSuccess("Daemon stopped")
    }
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Pickle daemon status and statistics"
    )

    @OptionGroup var options: PickleGlobalOptions

    func run() throws {
        print("Pickle - Status")
        print("═══════════════\n")

        // Daemon status
        print("Daemon:")
        if LaunchdHelper.isInstalled {
            pickleSuccess("Installed")
            if LaunchdHelper.isRunning {
                pickleSuccess("Running")
            } else {
                pickleWarning("Stopped")
            }
        } else {
            pickleWarning("Not installed (run 'pickle install')")
        }
        print("")

        // Version database stats
        do {
            let versionDB = try VersionDatabase()
            let stats = try versionDB.getStatistics()

            print("Version History:")
            print("  Tracked notes: \(stats.trackedNotes)")
            print("  Total versions: \(stats.totalVersions)")

            if let oldest = stats.oldestVersion {
                print("  Oldest version: \(formatDate(oldest))")
            }
            if let newest = stats.newestVersion {
                print("  Latest version: \(formatDate(newest))")
            }
            print("")

            // Storage info
            let storageSize = try getStorageSize()
            print("Storage:")
            print("  Database: ~/.pickle/versions.db")
            print("  Versions: ~/.pickle/versions/")
            print("  Size: \(formatBytes(storageSize))")
            print("")

        } catch {
            pickleWarning("Could not read version database: \(error.localizedDescription)")
        }

        // Log info
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pickle/logs")
        if FileManager.default.fileExists(atPath: logPath.path) {
            print("Logs:")
            print("  \(logPath.path)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func getStorageSize() throws -> Int64 {
        let pickleDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pickle")

        var totalSize: Int64 = 0

        let enumerator = FileManager.default.enumerator(
            at: pickleDir,
            includingPropertiesForKeys: [.fileSizeKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }

        return totalSize
    }
}

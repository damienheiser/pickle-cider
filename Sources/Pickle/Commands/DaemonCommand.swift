import ArgumentParser
import Foundation
import CiderCore
import Darwin

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the monitoring daemon (usually started by launchd)"
    )

    @Option(name: .long, help: "Check interval in seconds")
    var interval: Int = 30

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    func run() throws {
        // Set up signal handlers
        signal(SIGINT) { _ in
            print("\n[Daemon] Received SIGINT, shutting down...")
            Darwin.exit(0)
        }

        signal(SIGTERM) { _ in
            print("\n[Daemon] Received SIGTERM, shutting down...")
            Darwin.exit(0)
        }

        // Create and start monitor
        let monitor = try PickleMonitor(interval: TimeInterval(interval), verbose: verbose)

        // Run forever (or until signal)
        monitor.start()
    }
}

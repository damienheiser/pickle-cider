import ArgumentParser
import Foundation
import CiderCore

@main
struct CiderApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cider",
        abstract: "Press your notes into something useful - Bidirectional Apple Notes sync",
        version: "1.0.0",
        subcommands: [
            PullCommand.self,
            PushCommand.self,
            SyncCommand.self,
            StatusCommand.self,
            InitCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )
}

// MARK: - Shared Options

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Target Apple Notes folder")
    var folder: String = "Cider Sync"

    @Option(name: .long, help: "Output format (md, txt, html)")
    var format: OutputFormat = .md

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Preview changes without making them")
    var dryRun: Bool = false
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case md, txt, html

    var fileExtension: String {
        rawValue
    }
}

// MARK: - Utility Functions

func printVerbose(_ message: String, verbose: Bool) {
    if verbose {
        print("  \(message)")
    }
}

func printSuccess(_ message: String) {
    print("✓ \(message)")
}

func printError(_ message: String) {
    print("✗ \(message)")
}

func printWarning(_ message: String) {
    print("⚠ \(message)")
}

func printInfo(_ message: String) {
    print("ℹ \(message)")
}

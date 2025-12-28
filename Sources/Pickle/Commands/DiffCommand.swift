import ArgumentParser
import Foundation
import CiderCore

struct DiffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Compare two versions of a note"
    )

    @Argument(help: "First version ID")
    var version1: Int64

    @Argument(help: "Second version ID")
    var version2: Int64

    @Flag(name: .long, help: "Show unified diff format")
    var unified: Bool = false

    @OptionGroup var options: PickleGlobalOptions

    func run() throws {
        let versionDB = try VersionDatabase()

        // Load versions
        guard let v1 = try versionDB.getVersion(id: version1) else {
            throw PickleError.versionNotFound(version1)
        }
        guard let v2 = try versionDB.getVersion(id: version2) else {
            throw PickleError.versionNotFound(version2)
        }

        // Load content
        let content1 = try versionDB.loadVersionContent(storagePath: v1.storagePath)
        let content2 = try versionDB.loadVersionContent(storagePath: v2.storagePath)

        print("Comparing versions:")
        print("  Version \(v1.versionNumber) (ID: \(version1)) - \(formatDate(v1.capturedAt))")
        print("  Version \(v2.versionNumber) (ID: \(version2)) - \(formatDate(v2.capturedAt))")
        print("")

        let text1 = content1.content.plaintext
        let text2 = content2.content.plaintext

        if text1 == text2 {
            pickleSuccess("No differences found")
            return
        }

        // Calculate simple diff
        let diff = calculateDiff(old: text1, new: text2)

        print("Changes:")
        print("  \(diff.addedLines) lines added")
        print("  \(diff.removedLines) lines removed")
        print("  \(diff.addedChars) characters added")
        print("  \(diff.removedChars) characters removed")
        print("")

        if unified {
            // Show unified diff
            print("Unified Diff:")
            print("─────────────────────────────────────────────────────")
            let unifiedDiff = generateUnifiedDiff(old: text1, new: text2, oldLabel: "v\(v1.versionNumber)", newLabel: "v\(v2.versionNumber)")
            print(unifiedDiff)
        } else {
            // Show side-by-side changes
            print("Changes (first 20 differences):")
            print("─────────────────────────────────────────────────────")

            let changes = findChanges(old: text1, new: text2)
            for (i, change) in changes.prefix(20).enumerated() {
                switch change {
                case .unchanged(let line):
                    if options.verbose {
                        print("  \(line)")
                    }
                case .added(let line):
                    print("+ \(line)")
                case .removed(let line):
                    print("- \(line)")
                }
            }

            if changes.count > 20 {
                print("... and \(changes.count - 20) more changes")
            }
        }
    }

    private func formatDate(_ timestamp: Int64?) -> String {
        guard let ts = timestamp else { return "unknown" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    struct DiffStats {
        let addedLines: Int
        let removedLines: Int
        let addedChars: Int
        let removedChars: Int
    }

    private func calculateDiff(old: String, new: String) -> DiffStats {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        let oldSet = Set(oldLines)
        let newSet = Set(newLines)

        let added = newSet.subtracting(oldSet)
        let removed = oldSet.subtracting(newSet)

        let addedChars = new.count - old.count
        let removedChars = addedChars < 0 ? -addedChars : 0

        return DiffStats(
            addedLines: added.count,
            removedLines: removed.count,
            addedChars: max(0, addedChars),
            removedChars: removedChars
        )
    }

    enum Change {
        case unchanged(String)
        case added(String)
        case removed(String)
    }

    private func findChanges(old: String, new: String) -> [Change] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        var changes: [Change] = []

        // Simple LCS-based diff
        let oldSet = Set(oldLines)
        let newSet = Set(newLines)

        let removed = oldSet.subtracting(newSet)
        let added = newSet.subtracting(oldSet)

        for line in oldLines {
            if removed.contains(line) {
                changes.append(.removed(line))
            } else {
                changes.append(.unchanged(line))
            }
        }

        for line in newLines where added.contains(line) {
            changes.append(.added(line))
        }

        return changes
    }

    private func generateUnifiedDiff(old: String, new: String, oldLabel: String, newLabel: String) -> String {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        var result = ""
        result += "--- \(oldLabel)\n"
        result += "+++ \(newLabel)\n"

        // Simple unified diff generation
        let oldSet = Set(oldLines)
        let newSet = Set(newLines)

        for (i, line) in oldLines.enumerated() {
            if !newSet.contains(line) {
                result += "@@ -\(i+1) @@\n"
                result += "-\(line)\n"
            }
        }

        for (i, line) in newLines.enumerated() {
            if !oldSet.contains(line) {
                result += "@@ +\(i+1) @@\n"
                result += "+\(line)\n"
            }
        }

        return result
    }
}

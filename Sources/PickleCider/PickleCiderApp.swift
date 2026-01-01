import SwiftUI
import CiderCore
import AppKit
import Carbon.HIToolbox

@main
struct PickleCiderApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Menu Bar Extra - Always visible
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.inAppMonitoringActive ? "leaf.fill" : "leaf")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        // Main Window - Opens on demand
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                    // Window is now open, just bring to front
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Version Picker Window - Opens via ⌘⇧V hotkey
        WindowGroup(id: "version-picker") {
            VersionPickerView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App Delegate for Global Hotkey

class AppDelegate: NSObject, NSApplicationDelegate {
    var hotKeyRef: EventHotKeyRef?
    private var versionPickerObserver: Any?
    private var mainWindowObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register global hotkey: ⌘⇧V for version picker
        registerGlobalHotkey()

        // Hide dock icon - we're a menu bar app now
        NSApp.setActivationPolicy(.accessory)

        // Observe version picker notification
        versionPickerObserver = NotificationCenter.default.addObserver(
            forName: .showVersionPicker,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openVersionPicker()
        }

        // Observe main window notification
        mainWindowObserver = NotificationCenter.default.addObserver(
            forName: .openMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let observer = versionPickerObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = mainWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func registerGlobalHotkey() {
        // ⌘⇧V = Command + Shift + V
        let hotKeyID = EventHotKeyID(signature: OSType(0x5049434B), id: 1) // "PICK"
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 0x09 // 'V' key

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            // Post notification when hotkey pressed
            NotificationCenter.default.post(name: .showVersionPicker, object: nil)
            return noErr
        }, 1, &eventType, nil, nil)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func openVersionPicker() {
        // Bring app to front and open version picker window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find or create the version picker window
        if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "version-picker" }) {
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            // Open via environment - need to use a workaround since we can't access @Environment here
            // Post a notification that the SwiftUI view can observe
            NotificationCenter.default.post(name: .openVersionPickerWindow, object: nil)
        }
    }

    private func openMainWindow() {
        // Show dock icon and bring app to front
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find existing main window or create new one
        // Main windows have the ContentView content size (480x640)
        if let existingWindow = NSApp.windows.first(where: {
            $0.contentView?.frame.size.width == 480 ||
            $0.identifier?.rawValue.contains("main") == true
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            // Need to create window - use AppleScript to open new window
            // This is a workaround for SwiftUI's limited window management in menu bar apps
            let script = NSAppleScript(source: """
                tell application "System Events"
                    tell process "PickleCider"
                        click menu item "New Window" of menu "File" of menu bar 1
                    end tell
                end tell
            """)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)

            // If that didn't work, activate and the window should appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

extension Notification.Name {
    static let showVersionPicker = Notification.Name("showVersionPicker")
    static let openVersionPickerWindow = Notification.Name("openVersionPickerWindow")
    static let openMainWindow = Notification.Name("openMainWindow")
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "leaf.fill")
                    .foregroundColor(.green)
                Text("Pickle Cider")
                    .font(.headline)
                Spacer()
                if appState.inAppMonitoringActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 4)

            Divider()

            // Status
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "doc.text")
                    Text("\(appState.noteCount) notes")
                    Spacer()
                }

                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("\(appState.versionCount) versions saved")
                    Spacer()
                }

                if let lastCheck = appState.lastMonitorCheck {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Last check: \(lastCheck, formatter: timeFormatter)")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .font(.system(size: 12))

            Divider()

            // Actions
            Button(action: { openMainWindow() }) {
                Label("Open Pickle Cider", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Button(action: { appState.refresh() }) {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            Divider()

            // Monitoring toggle
            Toggle(isOn: Binding(
                get: { appState.inAppMonitoringActive },
                set: { newValue in
                    if newValue {
                        appState.startInAppMonitoring()
                    } else {
                        appState.stopInAppMonitoring()
                    }
                }
            )) {
                Label("Background Monitoring", systemImage: "eye")
            }
            .toggleStyle(.switch)

            // Start at login toggle
            Toggle(isOn: Binding(
                get: { LoginItemHelper.shared.isEnabled },
                set: { LoginItemHelper.shared.isEnabled = $0 }
            )) {
                Label("Start at Login", systemImage: "power")
            }
            .toggleStyle(.switch)

            Divider()

            // Hotkey hint
            HStack {
                Text("⌘⇧V")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                Text("Version Picker")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding()
        .frame(width: 260)
    }

    private func openMainWindow() {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }
}

// MARK: - Login Item Helper

import ServiceManagement

class LoginItemHelper {
    static let shared = LoginItemHelper()

    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to \(newValue ? "enable" : "disable") login item: \(error)")
                }
            }
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var noteCount: Int = 0
    @Published var versionCount: Int = 0
    @Published var syncedFileCount: Int = 0
    @Published var trackedNotes: [TrackedNote] = []
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var daemonRunning: Bool = false
    @Published var hasFullDiskAccess: Bool = true
    @Published var needsOnboarding: Bool = false
    @Published var inAppMonitoringActive: Bool = false
    @Published var lastMonitorCheck: Date?

    private var notesReader: NotesReader?
    private var versionDB: VersionDatabase?
    private var stateDB: StateDatabase?
    private var monitorTimer: Timer?
    private let monitorInterval: TimeInterval = 30

    init() {
        checkPermissionsAndRefresh()
        startInAppMonitoring()
    }

    deinit {
        stopInAppMonitoring()
    }

    /// Start in-app background monitoring (inherits app's FDA)
    func startInAppMonitoring() {
        guard monitorTimer == nil else { return }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            self?.performMonitorCheck()
        }

        // Initial check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.performMonitorCheck()
        }

        DispatchQueue.main.async {
            self.inAppMonitoringActive = true
        }
    }

    func stopInAppMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        inAppMonitoringActive = false
    }

    private func performMonitorCheck() {
        guard hasFullDiskAccess else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            do {
                let reader = try NotesReader()
                let versionDB = try VersionDatabase()
                let parser = ProtobufParser()

                let notes = try reader.getAllNotes()
                let knownStates = try versionDB.getAllMonitorStates()
                let knownMap = Dictionary(uniqueKeysWithValues: knownStates.map { ($0.noteUUID, $0) })

                var savedCount = 0

                print("Monitor: Starting check of \(notes.count) notes, known states: \(knownStates.count)")

                for note in notes {
                    if note.isPasswordProtected { continue }

                    var plaintext = ""
                    if let rawData = note.rawData {
                        if let parsed = try? parser.parseNoteData(rawData) {
                            plaintext = parsed.plaintext
                        }
                    }

                    let currentHash = plaintext.sha256Hash
                    let modTime = note.modificationDate ?? Date()

                    let needsSave: Bool
                    if let known = knownMap[note.uuid] {
                        needsSave = currentHash != known.lastHash
                    } else {
                        needsSave = true
                    }

                    if needsSave {
                        do {
                            let noteRecord = try versionDB.getOrCreateNote(
                                uuid: note.uuid,
                                title: note.displayTitle,
                                folderPath: note.folderName
                            )

                            if let noteID = noteRecord.id {
                                // Check if content actually changed
                                var shouldSave = true
                                if let lastVersion = try? versionDB.getLatestVersion(noteID: noteID),
                                   let lastContent = try? versionDB.loadVersionContent(storagePath: lastVersion.storagePath) {
                                    shouldSave = lastContent.content.plaintext != plaintext
                                }

                                if shouldSave {
                                    let content = VersionContent(
                                        noteUUID: note.uuid,
                                        appleNoteID: nil,
                                        title: note.displayTitle,
                                        folderPath: note.folderName,
                                        capturedAt: Date(),
                                        appleModificationDate: note.modificationDate,
                                        plaintext: plaintext,
                                        html: nil,
                                        rawProtobuf: note.rawData
                                    )
                                    _ = try versionDB.saveVersion(noteID: noteID, content: content)
                                    savedCount += 1
                                }
                            }

                            try versionDB.updateMonitorState(uuid: note.uuid, hash: currentHash, mtime: modTime)
                        } catch {
                            print("Monitor: Error processing note \(note.uuid): \(error)")
                        }
                    }
                }

                print("Monitor: Saved \(savedCount) versions")

                DispatchQueue.main.async {
                    self.lastMonitorCheck = Date()
                    if savedCount > 0 {
                        self.refresh() // Refresh UI if versions were saved
                    }
                }
            } catch {
                // Log errors to help debugging
                print("Monitor check error: \(error)")
            }
        }
    }

    /// Check if we have Full Disk Access by attempting to read a protected file
    func checkFullDiskAccess() -> Bool {
        let notesDBPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")

        // Try to open the file for reading
        if FileManager.default.isReadableFile(atPath: notesDBPath.path) {
            // File exists and is readable, but we need to actually try to open it
            // because isReadableFile doesn't check Full Disk Access
            do {
                let handle = try FileHandle(forReadingFrom: notesDBPath)
                handle.closeFile()
                return true
            } catch {
                return false
            }
        }

        // If file doesn't exist, user might not have Notes set up - that's okay
        return !FileManager.default.fileExists(atPath: notesDBPath.path)
    }

    func checkPermissionsAndRefresh() {
        let hasAccess = checkFullDiskAccess()

        DispatchQueue.main.async {
            self.hasFullDiskAccess = hasAccess
            self.needsOnboarding = !hasAccess
        }

        if hasAccess {
            refresh()
        } else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }

    func openSystemPreferences() {
        // Open System Settings > Privacy & Security > Full Disk Access
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                // Initialize readers
                let reader = try NotesReader()
                self?.notesReader = reader

                let noteCount = try reader.getNoteCount()

                // Version database
                let versionDB = try VersionDatabase()
                self?.versionDB = versionDB
                let stats = try versionDB.getStatistics()

                // State database
                let stateDB = try StateDatabase()
                self?.stateDB = stateDB
                let syncStats = try stateDB.getStatistics()

                // Get tracked notes
                let notes = try versionDB.getAllNotes()
                let trackedNotes: [TrackedNote] = try notes.compactMap { noteRecord in
                    let versions = try versionDB.getVersions(noteID: noteRecord.id ?? 0)
                    return TrackedNote(
                        id: noteRecord.uuid,
                        title: noteRecord.title ?? "Untitled",
                        versionCount: versions.count,
                        lastBackup: versions.first?.capturedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    )
                }

                // Check daemon status
                let daemonRunning = LaunchDaemonHelper.isRunning

                DispatchQueue.main.async {
                    self?.noteCount = noteCount
                    self?.versionCount = stats.totalVersions
                    self?.syncedFileCount = syncStats.syncedFiles
                    self?.trackedNotes = trackedNotes
                    self?.daemonRunning = daemonRunning
                    self?.isLoading = false
                    self?.lastError = nil
                    self?.hasFullDiskAccess = true
                    self?.needsOnboarding = false
                }
            } catch {
                let errorMessage = error.localizedDescription
                let isPermissionError = errorMessage.contains("authorization denied") ||
                                        errorMessage.contains("not permitted") ||
                                        errorMessage.contains("SQLite error 23")

                DispatchQueue.main.async {
                    if isPermissionError {
                        self?.hasFullDiskAccess = false
                        self?.needsOnboarding = true
                        self?.lastError = nil
                    } else {
                        self?.lastError = errorMessage
                    }
                    self?.isLoading = false
                }
            }
        }
    }

    func exportNote(_ note: TrackedNote, to url: URL) {
        guard let versionDB = versionDB else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let noteRecord = try versionDB.getNote(uuid: note.id),
                      let noteID = noteRecord.id else { return }

                let versions = try versionDB.getVersions(noteID: noteID)

                for version in versions {
                    let content = try versionDB.loadVersionContent(storagePath: version.storagePath)

                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
                    let filename = "v\(String(format: "%03d", version.versionNumber))_\(dateFormatter.string(from: content.capturedAt)).md"

                    let filePath = url.appendingPathComponent(filename)

                    var md = "---\ntitle: \"\(content.title)\"\nversion: \(version.versionNumber)\n---\n\n"
                    md += content.content.plaintext

                    try md.write(to: filePath, atomically: true, encoding: .utf8)
                }

                DispatchQueue.main.async {
                    self?.lastError = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Export all Apple Notes to markdown files with attachments
    func exportAllAppleNotes(to baseURL: URL) {
        guard let reader = notesReader else {
            lastError = "Notes reader not available"
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let notes = try reader.getAllNotes()
                let accountUUID = try reader.getAccountUUID()
                var exportedCount = 0
                var skippedCount = 0
                var attachmentCount = 0

                for note in notes {
                    // Skip password protected notes
                    if note.isPasswordProtected {
                        skippedCount += 1
                        continue
                    }

                    // Create folder path based on note's folder
                    let folderName = (note.folderName ?? "Notes").sanitizedForFilename
                    let folderPath = baseURL.appendingPathComponent(folderName)
                    try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true)

                    // Create filename from title
                    let noteSafeFilename = note.safeFilename
                    let filename = noteSafeFilename + ".md"
                    let filePath = folderPath.appendingPathComponent(filename)

                    // Get attachments for this note
                    let attachments = try reader.getAttachments(noteID: note.id)
                    var attachmentMarkdown: [String: String] = [:] // uuid -> markdown

                    // Create attachments folder if needed
                    let attachmentsDir = folderPath.appendingPathComponent("_attachments").appendingPathComponent(noteSafeFilename)
                    if !attachments.isEmpty {
                        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
                    }

                    // Process attachments
                    for attachment in attachments {
                        switch attachment.attachmentType {
                        case .image, .video, .audio, .file:
                            // Copy media file
                            if let accountUUID = accountUUID,
                               let sourcePath = attachment.mediaFilePath(accountUUID: accountUUID, baseDir: NotesReader.notesBaseDir) {
                                let destFilename = attachment.filename ?? "\(attachment.uuid).\(sourcePath.pathExtension)"
                                let destPath = attachmentsDir.appendingPathComponent(destFilename)
                                try? FileManager.default.copyItem(at: sourcePath, to: destPath)

                                let relativePath = "_attachments/\(noteSafeFilename)/\(destFilename)"
                                if attachment.attachmentType == .image {
                                    attachmentMarkdown[attachment.uuid] = "![\(destFilename)](\(relativePath))"
                                } else {
                                    attachmentMarkdown[attachment.uuid] = "[\(destFilename)](\(relativePath))"
                                }
                                attachmentCount += 1
                            }

                        case .table:
                            // Get table content
                            if let tableContent = try? reader.getTableContent(attachmentID: attachment.id),
                               !tableContent.isEmpty {
                                // Convert table summary to markdown table format
                                let tableMarkdown = self?.formatTableAsMarkdown(tableContent) ?? tableContent
                                attachmentMarkdown[attachment.uuid] = "\n\n" + tableMarkdown + "\n\n"
                            }

                        case .drawing:
                            attachmentMarkdown[attachment.uuid] = "[Drawing]"

                        case .link:
                            attachmentMarkdown[attachment.uuid] = "[Link]"
                        }
                    }

                    // Get note content with formatting
                    var noteContent: String
                    if let data = note.rawData {
                        do {
                            let parser = ProtobufParser()
                            let content = try parser.parseNoteData(data)
                            // Use markdown for formatted output (includes bold, italic, headings)
                            noteContent = content.markdown.isEmpty ? content.plaintext : content.markdown
                        } catch {
                            skippedCount += 1
                            continue
                        }
                    } else if let text = note.plaintext, !text.isEmpty {
                        noteContent = text
                    } else {
                        skippedCount += 1
                        continue
                    }

                    // Replace attachment placeholders (U+FFFC) with markdown
                    // The object replacement character marks where attachments go
                    var index = 0
                    var processedText = ""
                    for char in noteContent {
                        if char == "\u{FFFC}" && index < attachments.count {
                            let attachment = attachments[index]
                            if let md = attachmentMarkdown[attachment.uuid] {
                                processedText += md
                            } else {
                                processedText += "[attachment]"
                            }
                            index += 1
                        } else {
                            processedText.append(char)
                        }
                    }

                    var md = "---\n"
                    md += "title: \"\(note.displayTitle.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
                    if let folder = note.folderName {
                        md += "folder: \"\(folder)\"\n"
                    }
                    if let created = note.creationDate {
                        md += "created: \(ISO8601DateFormatter().string(from: created))\n"
                    }
                    if let modified = note.modificationDate {
                        md += "modified: \(ISO8601DateFormatter().string(from: modified))\n"
                    }
                    if !attachments.isEmpty {
                        md += "attachments: \(attachments.count)\n"
                    }
                    md += "---\n\n"
                    md += processedText

                    try md.write(to: filePath, atomically: true, encoding: .utf8)
                    exportedCount += 1
                }

                DispatchQueue.main.async {
                    self?.isLoading = false
                    var message = "Exported \(exportedCount) notes"
                    if attachmentCount > 0 {
                        message += ", \(attachmentCount) attachments"
                    }
                    if skippedCount > 0 {
                        message += ", skipped \(skippedCount) (locked/empty)"
                    }
                    self?.lastError = message
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.lastError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Import markdown files into Apple Notes
    func importMarkdownFiles(_ urls: [URL]) {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let writer = NotesWriter()
            var importedCount = 0
            var failedCount = 0
            var errors: [String] = []

            for url in urls {
                do {
                    if url.hasDirectoryPath {
                        // Import all markdown files from directory
                        let contents = try FileManager.default.contentsOfDirectory(
                            at: url,
                            includingPropertiesForKeys: [.isRegularFileKey],
                            options: [.skipsHiddenFiles]
                        )

                        for file in contents where file.pathExtension == "md" || file.pathExtension == "txt" {
                            do {
                                try self?.importSingleFile(file, writer: writer)
                                importedCount += 1
                            } catch {
                                failedCount += 1
                                errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
                            }
                        }
                    } else {
                        // Import single file
                        try self?.importSingleFile(url, writer: writer)
                        importedCount += 1
                    }
                } catch {
                    failedCount += 1
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                self?.isLoading = false
                var message = "Imported \(importedCount) notes"
                if failedCount > 0 {
                    message += ", \(failedCount) failed"
                }
                self?.lastError = message
                self?.refresh()
            }
        }
    }

    private func importSingleFile(_ url: URL, writer: NotesWriter) throws {
        let content = try String(contentsOf: url, encoding: .utf8)

        // Parse YAML frontmatter if present
        var title = url.deletingPathExtension().lastPathComponent
        var folder = "Notes"
        var body = content

        if content.hasPrefix("---\n") {
            // Parse frontmatter
            if let endRange = content.range(of: "\n---\n", range: content.index(content.startIndex, offsetBy: 4)..<content.endIndex) {
                let frontmatter = String(content[content.index(content.startIndex, offsetBy: 4)..<endRange.lowerBound])
                body = String(content[endRange.upperBound...])

                // Parse YAML-ish frontmatter
                for line in frontmatter.components(separatedBy: "\n") {
                    if line.hasPrefix("title:") {
                        title = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    } else if line.hasPrefix("folder:") {
                        folder = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                }
            }
        }

        // Convert markdown to HTML for Apple Notes
        let converter = MarkdownConverter()
        let html = converter.markdownToHTML(body)

        // Create or update the note
        if try writer.noteExists(title: title, folder: folder) {
            try writer.updateNote(title: title, body: html, folder: folder)
        } else {
            try writer.createNote(title: title, body: html, folder: folder)
        }
    }

    /// Format table summary text as a markdown table
    private func formatTableAsMarkdown(_ summary: String) -> String {
        // Table summaries come as "Header:\nValue\nHeader:\nValue" format
        let lines = summary.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Try to detect if it's a key-value table
        var rows: [[String]] = []
        var currentRow: [String] = []
        var isKeyValue = false

        for line in lines {
            if line.hasSuffix(":") {
                // This looks like a header/key
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                    currentRow = []
                }
                currentRow.append(String(line.dropLast()))
                isKeyValue = true
            } else {
                currentRow.append(line)
                if isKeyValue && currentRow.count >= 2 {
                    rows.append(currentRow)
                    currentRow = []
                }
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        guard !rows.isEmpty else { return summary }

        // Determine column count
        let maxCols = rows.map { $0.count }.max() ?? 1

        // Build markdown table
        var md = "| " + (0..<maxCols).map { "Column \($0 + 1)" }.joined(separator: " | ") + " |\n"
        md += "| " + (0..<maxCols).map { _ in "---" }.joined(separator: " | ") + " |\n"

        for row in rows {
            let cells = (0..<maxCols).map { i in
                i < row.count ? row[i].replacingOccurrences(of: "|", with: "\\|") : ""
            }
            md += "| " + cells.joined(separator: " | ") + " |\n"
        }

        return md
    }

    /// Export all Apple Notes to beautiful PDF documents
    func exportAllNotesToPDF(to baseURL: URL) {
        guard let reader = notesReader else {
            lastError = "Notes reader not available"
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let notes = try reader.getAllNotes()
                var exportedCount = 0
                var skippedCount = 0

                // Create output directory
                try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

                for note in notes {
                    // Skip password protected notes
                    if note.isPasswordProtected {
                        skippedCount += 1
                        continue
                    }

                    // Get note content
                    var noteContent: String
                    if let data = note.rawData {
                        do {
                            let parser = ProtobufParser()
                            let content = try parser.parseNoteData(data)
                            noteContent = content.markdown.isEmpty ? content.plaintext : content.markdown
                        } catch {
                            skippedCount += 1
                            continue
                        }
                    } else if let text = note.plaintext, !text.isEmpty {
                        noteContent = text
                    } else {
                        skippedCount += 1
                        continue
                    }

                    // Create folder structure
                    let folderName = (note.folderName ?? "Notes").sanitizedForFilename
                    let folderPath = baseURL.appendingPathComponent(folderName)
                    try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true)

                    // Generate PDF
                    let pdfPath = folderPath.appendingPathComponent(note.safeFilename + ".pdf")
                    try self?.generatePDF(
                        title: note.displayTitle,
                        folder: note.folderName ?? "Notes",
                        created: note.creationDate,
                        modified: note.modificationDate,
                        content: noteContent,
                        outputURL: pdfPath
                    )

                    exportedCount += 1
                }

                DispatchQueue.main.async {
                    self?.isLoading = false
                    var message = "Exported \(exportedCount) notes to PDF"
                    if skippedCount > 0 {
                        message += ", skipped \(skippedCount) (locked/empty)"
                    }
                    self?.lastError = message
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.lastError = "PDF Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func generatePDF(title: String, folder: String, created: Date?, modified: Date?, content: String, outputURL: URL) throws {
        // Create HTML for PDF rendering
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        let createdStr = created.map { dateFormatter.string(from: $0) } ?? "Unknown"
        let modifiedStr = modified.map { dateFormatter.string(from: $0) } ?? "Unknown"

        // Convert markdown-like content to HTML
        let htmlContent = content
            .components(separatedBy: "\n")
            .map { line -> String in
                var processedLine = line
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")

                // Handle markdown headers
                if processedLine.hasPrefix("# ") {
                    return "<h1>\(String(processedLine.dropFirst(2)))</h1>"
                } else if processedLine.hasPrefix("## ") {
                    return "<h2>\(String(processedLine.dropFirst(3)))</h2>"
                } else if processedLine.hasPrefix("### ") {
                    return "<h3>\(String(processedLine.dropFirst(4)))</h3>"
                }

                // Handle bold and italic
                processedLine = processedLine.replacingOccurrences(
                    of: "\\*\\*(.+?)\\*\\*",
                    with: "<strong>$1</strong>",
                    options: .regularExpression
                )
                processedLine = processedLine.replacingOccurrences(
                    of: "\\*(.+?)\\*",
                    with: "<em>$1</em>",
                    options: .regularExpression
                )

                // Handle bullet points
                if processedLine.hasPrefix("- ") || processedLine.hasPrefix("• ") {
                    return "<li>\(String(processedLine.dropFirst(2)))</li>"
                }

                return processedLine.isEmpty ? "<br>" : "<p>\(processedLine)</p>"
            }
            .joined(separator: "\n")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                @page {
                    margin: 1in;
                    size: letter;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    font-size: 12pt;
                    line-height: 1.6;
                    color: #333;
                    max-width: 100%;
                }
                .header {
                    border-bottom: 2px solid #4A90D9;
                    padding-bottom: 20px;
                    margin-bottom: 30px;
                }
                .title {
                    font-size: 24pt;
                    font-weight: bold;
                    color: #2c3e50;
                    margin: 0 0 10px 0;
                }
                .metadata {
                    font-size: 10pt;
                    color: #7f8c8d;
                }
                .metadata span {
                    margin-right: 20px;
                }
                .folder {
                    display: inline-block;
                    background: #e8f4f8;
                    color: #4A90D9;
                    padding: 2px 8px;
                    border-radius: 4px;
                    font-size: 9pt;
                    margin-bottom: 10px;
                }
                .content {
                    margin-top: 20px;
                }
                h1, h2, h3 {
                    color: #2c3e50;
                    margin-top: 1.5em;
                    margin-bottom: 0.5em;
                }
                h1 { font-size: 18pt; border-bottom: 1px solid #eee; padding-bottom: 5px; }
                h2 { font-size: 16pt; }
                h3 { font-size: 14pt; }
                p { margin: 0.5em 0; }
                li { margin: 0.3em 0; margin-left: 20px; }
                strong { font-weight: 600; }
                em { font-style: italic; }
                .footer {
                    margin-top: 40px;
                    padding-top: 20px;
                    border-top: 1px solid #eee;
                    font-size: 9pt;
                    color: #999;
                    text-align: center;
                }
            </style>
        </head>
        <body>
            <div class="header">
                <div class="folder">📁 \(folder.replacingOccurrences(of: "<", with: "&lt;"))</div>
                <h1 class="title">\(title.replacingOccurrences(of: "<", with: "&lt;"))</h1>
                <div class="metadata">
                    <span>📅 Created: \(createdStr)</span>
                    <span>✏️ Modified: \(modifiedStr)</span>
                </div>
            </div>
            <div class="content">
                \(htmlContent)
            </div>
            <div class="footer">
                Exported from Apple Notes by Pickle Cider
            </div>
        </body>
        </html>
        """

        // Use WebKit to render HTML to PDF
        try renderHTMLToPDF(html: html, outputURL: outputURL)
    }

    private func renderHTMLToPDF(html: String, outputURL: URL) throws {
        // Create PDF using NSAttributedString for simplicity
        // (Full WebKit rendering would require main thread and async handling)
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792) // Letter size
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72

        // Convert HTML to attributed string
        guard let data = html.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            throw NSError(domain: "PDFExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse HTML"])
        }

        // Create text view for rendering
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648)) // Letter minus margins
        textView.textStorage?.setAttributedString(attributedString)

        // Generate PDF data
        let pdfData = textView.dataWithPDF(inside: textView.bounds)
        try pdfData.write(to: outputURL)
    }
}

struct TrackedNote: Identifiable {
    let id: String
    let title: String
    let versionCount: Int
    let lastBackup: Date?
}

// MARK: - Launch Daemon Helper

struct LaunchDaemonHelper {
    static let plistLabel = "com.pickle.daemon"
    static let plistPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.pickle.daemon.plist")

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath.path)
    }

    static var isRunning: Bool {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", plistLabel]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    static var picklePath: String {
        // Prefer app bundle path for Full Disk Access inheritance
        let appBundlePath = "/Applications/Pickle Cider.app/Contents/MacOS/pickle"
        if FileManager.default.isExecutableFile(atPath: appBundlePath) {
            return appBundlePath
        }
        return "/usr/local/bin/pickle"
    }

    static func install() {
        // Use pickle CLI to install the daemon
        let task = Process()
        task.launchPath = picklePath
        task.arguments = ["install", "--force"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    static func start() {
        // Auto-install if not installed
        if !isInstalled {
            install()
        }

        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", plistPath.path]
        try? task.run()
        task.waitUntilExit()
    }

    static func stop() {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistPath.path]
        try? task.run()
        task.waitUntilExit()
    }
}

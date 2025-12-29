import SwiftUI
import CiderCore

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedNote: TrackedNote?
    @State private var showingExportPanel = false
    @State private var showingImportPanel = false
    @State private var dragOver = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "2D5016"), Color(hex: "1A3009")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if appState.needsOnboarding {
                // Show onboarding/permission request
                OnboardingView()
            } else {
                VStack(spacing: 0) {
                    // Header with logo
                    HeaderView()
                        .padding()

                    // Stats cards
                    StatsCardsView()
                        .padding(.horizontal)

                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.vertical)

                    // Notes list
                    NotesListView(selectedNote: $selectedNote)
                        .padding(.horizontal)

                    Spacer()

                    // Action buttons
                    ActionButtonsView(
                        showingExportPanel: $showingExportPanel,
                        showingImportPanel: $showingImportPanel
                    )
                    .padding()
                }
            }

            // Drop overlay
            if dragOver {
                DropOverlayView()
            }

            // Loading overlay
            if appState.isLoading {
                LoadingOverlayView()
            }
        }
        .frame(width: 480, height: 640)
        .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .fileExporter(
            isPresented: $showingExportPanel,
            document: ExportDocument(),
            contentType: .folder,
            defaultFilename: "PickleCider Export"
        ) { result in
            if case .success(let url) = result {
                exportAllNotes(to: url)
            }
        }
        .fileImporter(
            isPresented: $showingImportPanel,
            allowedContentTypes: [.folder, .plainText, .text],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importFiles(urls)
            }
        }
        .alert("Error", isPresented: .constant(appState.lastError != nil)) {
            Button("OK") {
                appState.lastError = nil
            }
        } message: {
            Text(appState.lastError ?? "")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    importFiles([url])
                }
            }
        }
    }

    private func exportAllNotes(to url: URL) {
        for note in appState.trackedNotes {
            let noteDir = url.appendingPathComponent(note.title.sanitizedForFilename)
            try? FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
            appState.exportNote(note, to: noteDir)
        }
    }

    private func importFiles(_ urls: [URL]) {
        // Import logic would go here - push to Apple Notes
        appState.refresh()
    }
}

// MARK: - Header View

struct HeaderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            // Pickle jar icon
            PickleJarIcon()
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pickle Cider")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Apple Notes Backup & Sync")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                // Daemon status
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.daemonRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(appState.daemonRunning ? "Daemon Running" : "Daemon Stopped")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    Button(appState.daemonRunning ? "Stop" : "Start") {
                        if appState.daemonRunning {
                            LaunchDaemonHelper.stop()
                        } else {
                            LaunchDaemonHelper.start()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            appState.refresh()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                }
            }

            Spacer()

            Button {
                appState.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
    }
}

// MARK: - Pickle Jar Icon

struct PickleJarIcon: View {
    var body: some View {
        ZStack {
            // Jar body
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "A8D08D"), Color(hex: "6B8E23")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 70)
                .offset(y: 5)

            // Jar lid
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "8B4513"))
                .frame(width: 50, height: 12)
                .offset(y: -32)

            // Spigot
            HStack(spacing: 0) {
                Circle()
                    .fill(Color(hex: "CD853F"))
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(Color(hex: "8B4513"))
                    .frame(width: 15, height: 6)
            }
            .offset(x: 30, y: 15)

            // Pickles inside
            VStack(spacing: 2) {
                Capsule()
                    .fill(Color(hex: "556B2F"))
                    .frame(width: 35, height: 10)
                    .rotationEffect(.degrees(-15))
                Capsule()
                    .fill(Color(hex: "6B8E23"))
                    .frame(width: 30, height: 8)
                    .rotationEffect(.degrees(10))
                Capsule()
                    .fill(Color(hex: "556B2F"))
                    .frame(width: 32, height: 9)
                    .rotationEffect(.degrees(-5))
            }
            .offset(y: 10)

            // Liquid effect
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "9ACD32").opacity(0.3))
                .frame(width: 54, height: 60)
                .offset(y: 8)

            // Glass shine
            Ellipse()
                .fill(Color.white.opacity(0.3))
                .frame(width: 15, height: 40)
                .offset(x: -15, y: 5)
        }
    }
}

// MARK: - Stats Cards

struct StatsCardsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            StatCard(
                icon: "doc.text.fill",
                value: "\(appState.noteCount)",
                label: "Apple Notes"
            )

            StatCard(
                icon: "clock.arrow.circlepath",
                value: "\(appState.versionCount)",
                label: "Versions Saved"
            )

            StatCard(
                icon: "checkmark.circle.fill",
                value: "\(appState.syncedFileCount)",
                label: "Files Synced"
            )
        }
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Color(hex: "9ACD32"))

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Notes List

struct NotesListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedNote: TrackedNote?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tracked Notes")
                .font(.headline)
                .foregroundColor(.white)

            if appState.trackedNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No notes tracked yet")
                        .foregroundColor(.white.opacity(0.5))
                    Text("Install the daemon to start tracking")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.trackedNotes) { note in
                            NoteRow(note: note, isSelected: selectedNote?.id == note.id)
                                .onTapGesture {
                                    selectedNote = note
                                }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 300)
    }
}

struct NoteRow: View {
    let note: TrackedNote
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(note.versionCount) versions", systemImage: "clock")
                    if let lastBackup = note.lastBackup {
                        Label(lastBackup.timeAgo, systemImage: "checkmark.circle")
                    }
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.3))
        }
        .padding()
        .background(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Action Buttons

struct ActionButtonsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showingExportPanel: Bool
    @Binding var showingImportPanel: Bool

    var body: some View {
        HStack(spacing: 16) {
            ActionButton(
                title: "Import",
                icon: "square.and.arrow.down",
                color: Color(hex: "4A90D9")
            ) {
                showingImportPanel = true
            }

            ActionButton(
                title: "Export All",
                icon: "square.and.arrow.up",
                color: Color(hex: "9ACD32")
            ) {
                showingExportPanel = true
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overlays

struct DropOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)

            VStack(spacing: 16) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Color(hex: "9ACD32"))

                Text("Drop files to import")
                    .font(.title2)
                    .foregroundColor(.white)

                Text("Markdown and text files will be pushed to Apple Notes")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .ignoresSafeArea()
    }
}

struct LoadingOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Loading...")
                    .foregroundColor(.white)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Pickle jar icon
            PickleJarIcon()
                .frame(width: 120, height: 120)

            Text("Welcome to Pickle Cider")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Apple Notes Backup & Sync")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            // Permission request card
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44))
                    .foregroundColor(Color(hex: "9ACD32"))

                Text("Full Disk Access Required")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Pickle Cider needs Full Disk Access to read your Apple Notes database. Your notes never leave your Mac.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("1.")
                            .font(.headline)
                            .foregroundColor(Color(hex: "9ACD32"))
                        Text("Click \"Open System Settings\" below")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Text("2.")
                            .font(.headline)
                            .foregroundColor(Color(hex: "9ACD32"))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Click the + button and add:")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            Text("• Pickle Cider (from Applications)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Text("• Terminal (if using CLI tools)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Text("3.")
                            .font(.headline)
                            .foregroundColor(Color(hex: "9ACD32"))
                        Text("Quit and reopen Pickle Cider")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Text("Note: You must quit and reopen after granting access")
                    .font(.caption)
                    .foregroundColor(Color(hex: "9ACD32"))
                    .padding(.top, 8)
            }
            .padding(24)
            .background(Color.white.opacity(0.1))
            .cornerRadius(16)
            .padding(.horizontal, 32)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    appState.openSystemPreferences()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open System Settings")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "9ACD32"))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button {
                    appState.checkPermissionsAndRefresh()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("I've Granted Access - Retry")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("checkInterval") private var checkInterval = 30
    @AppStorage("maxVersions") private var maxVersions = 100

    var body: some View {
        Form {
            Section("Daemon Settings") {
                Stepper("Check interval: \(checkInterval) seconds", value: $checkInterval, in: 10...300, step: 10)
                Stepper("Max versions per note: \(maxVersions)", value: $maxVersions, in: 10...1000, step: 10)
            }

            Section("Storage") {
                LabeledContent("Version Database") {
                    Text("~/.pickle/versions.db")
                        .foregroundColor(.secondary)
                }
                LabeledContent("Sync State") {
                    Text("~/.cider/state.db")
                        .foregroundColor(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("1.0.0")
                }
                Link("View on GitHub", destination: URL(string: "https://github.com")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}

// MARK: - Export Document

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: [:])
    }
}

// MARK: - Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Date {
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension String {
    var sanitizedForFilename: String {
        self.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import UniformTypeIdentifiers

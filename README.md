# Cider, Pickle & Pickle Cider - Apple Notes Tools

Three powerful native macOS tools for Apple Notes: two CLI tools and a beautiful SwiftUI GUI app.

## Cider - "Press your notes into something useful"

Bidirectional sync between Apple Notes and markdown files.

### Features

- **Pull**: Export all your Apple Notes to markdown files
- **Push**: Upload markdown files to Apple Notes
- **Sync**: Bidirectional sync with conflict detection
- **Recursive**: Process entire directory trees with folder structure

### Installation

```bash
# Build from source
git clone https://github.com/yourusername/apple-notes-tools
cd apple-notes-tools
swift build -c release

# Install
cp .build/release/cider /usr/local/bin/
```

### Usage

```bash
# Initialize sync state
cider init

# Export all notes to a directory
cider pull ~/Documents/notes --recursive

# Upload a file to Apple Notes
cider push ~/Documents/notes/my-note.md

# Bidirectional sync
cider sync ~/Documents/notes --folder "My Synced Notes"

# Check status
cider status --detailed
```

### Commands

| Command | Description |
|---------|-------------|
| `cider init` | Initialize sync state database |
| `cider pull <dir>` | Export Apple Notes to markdown files |
| `cider push <path>` | Upload files to Apple Notes |
| `cider sync <dir>` | Bidirectional sync |
| `cider status` | Show sync status |

### Options

```
--folder <name>    Target Apple Notes folder (default: "Cider Sync")
--format <md|txt|html>  Output format (default: md)
--recursive        Process subdirectories
--dry-run          Preview without making changes
--force            Overwrite conflicts
--verbose          Verbose output
```

---

## Pickle - "Keep your notes in a pickle (the good kind)"

Automatic version history for Apple Notes with a launchd daemon.

### Features

- **Automatic versioning**: Every change is captured automatically
- **Background daemon**: Runs silently via launchd
- **Version history**: Browse all versions of any note
- **Diff**: Compare any two versions
- **Restore**: Revert notes to previous versions
- **Export**: Export versions to files or back to Apple Notes

### Installation

```bash
# Build from source
swift build -c release

# Install
cp .build/release/pickle /usr/local/bin/

# Install the daemon
pickle install
```

### Usage

```bash
# Install the background daemon
pickle install --interval 30

# Check daemon status
pickle status

# View version history for a note
pickle history "My Important Note"

# Compare two versions
pickle diff 1 2

# Restore to a previous version
pickle restore 5

# Export all versions of a note
pickle export "My Note" ~/exports --format md

# Export versions to Apple Notes folders
pickle export-to-notes "My Note" --folder "Version History"

# Stop the daemon
pickle stop

# Uninstall
pickle uninstall
```

### Commands

| Command | Description |
|---------|-------------|
| `pickle install` | Install launchd daemon |
| `pickle uninstall` | Remove daemon |
| `pickle start` | Start daemon |
| `pickle stop` | Stop daemon |
| `pickle status` | Show daemon status and statistics |
| `pickle history <note>` | Show version history |
| `pickle diff <v1> <v2>` | Compare versions |
| `pickle restore <id>` | Restore to version |
| `pickle export <note> <dir>` | Export versions to files |
| `pickle export-to-notes` | Export to Apple Notes folders |

### Options

```
--interval <seconds>  Check interval for daemon (default: 30)
--max-versions <n>    Max versions per note (default: 100)
--limit <n>           Limit results
--format <md|txt|json>  Export format
--verbose             Verbose output
```

---

## Requirements

- **macOS 12.0** (Monterey) or later
- **Full Disk Access** permission for your terminal app
- **Automation** permission for Notes.app

### Granting Permissions

1. Open **System Preferences > Security & Privacy > Privacy**
2. Select **Full Disk Access**
3. Add your terminal app (Terminal.app, iTerm, etc.)
4. On first run, allow automation access to Notes.app when prompted

---

## Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/apple-notes-tools
cd apple-notes-tools

# Build debug
swift build

# Build release
swift build -c release

# Run tests
swift test

# Build universal binary (Intel + Apple Silicon)
./Scripts/build-release.sh
```

---

## Data Storage

### Cider
- State database: `~/.cider/state.db`

### Pickle
- Version database: `~/.pickle/versions.db`
- Version files: `~/.pickle/versions/YYYY/MM/DD/*.json.gz`
- Logs: `~/.pickle/logs/`

---

## Technical Details

### Apple Notes Access

- **Reading**: Direct SQLite access to `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`
- **Writing**: AppleScript via NSAppleScript (required to preserve iCloud sync)
- **Content format**: Notes are stored as gzip-compressed protobuf

### Limitations

- Password-protected notes cannot be accessed (skipped with warning)
- Attachments are referenced but not synced
- Apple Notes has no official API - these tools use reverse-engineered access

---

## License

MIT License - see [LICENSE](LICENSE)

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

---

## Credits

Built with:
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [Swift Protobuf](https://github.com/apple/swift-protobuf)
- [SwiftSoup](https://github.com/scinfu/SwiftSoup)

---

## Pickle Cider - The GUI App

A beautiful SwiftUI app that combines both Cider and Pickle in an easy-to-use interface.

### Features

- **Dashboard**: See all your Apple Notes stats at a glance
- **Tracked Notes**: Browse all notes being versioned
- **Drag & Drop**: Import files by dropping them onto the window
- **Export**: One-click export of all versions
- **Daemon Control**: Start/stop the Pickle daemon from the app
- **Cute Pickle Jar Icon**: With a spigot!

### Installation

```bash
# Build
swift build -c release

# The app is at:
.build/release/PickleCider

# Or create an .app bundle manually
```

### Screenshot Description

The app features:
- A dark green gradient background (pickle-themed!)
- A cute pickle jar icon with pickles inside and a spigot
- Stats cards showing notes, versions, and synced files
- A list of tracked notes with version counts
- Import/Export buttons
- Daemon status indicator

---

Inspired by:
- [apple_cloud_notes_parser](https://github.com/threeplanetssoftware/apple_cloud_notes_parser)
- [Apple Notes Liberator](https://github.com/HamburgChimps/apple-notes-liberator)

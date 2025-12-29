# Pickle Cider

Native macOS tools for working with Apple Notes - sync, backup, and version history.

**Build from source required** - macOS Full Disk Access requires apps to be signed with a developer certificate. Building locally with Xcode automatically signs the app with your personal development certificate.

## What's Included

### 🫙 Pickle Cider - GUI App
A beautiful SwiftUI app combining sync and version history.
- Dashboard with stats at a glance
- Browse all tracked notes
- Drag & drop import/export
- Control the Pickle daemon
- Full Disk Access onboarding

### 🍺 Cider - CLI Sync Tool
Bidirectional sync between Apple Notes and markdown files.
```bash
cider pull ~/notes --recursive    # Export notes to markdown
cider push ~/notes/doc.md         # Upload to Apple Notes
cider sync ~/notes                # Bidirectional sync
```

### 🥒 Pickle - CLI Version History
Automatic version history with background daemon.
```bash
pickle install                    # Install background daemon
pickle history "My Note"          # View version history
pickle diff 1 2                   # Compare versions
pickle restore 5                  # Restore to version
```

---

## Installation (Build from Source)

### Requirements
- macOS 13.0 (Ventura) or later
- Xcode 15+ (for building)
- Full Disk Access permission

### Option 1: Build with Xcode (Recommended)

This method automatically signs the app with your personal development certificate.

```bash
# Clone the repository
git clone https://github.com/damienheiser/pickle-cider
cd pickle-cider

# Generate Xcode project
swift package generate-xcodeproj

# Open in Xcode
open PickleCider.xcodeproj
```

In Xcode:
1. Select **PickleCider** scheme
2. Set signing team to your Personal Team
3. Build and Run (⌘R)
4. Find the app in Products folder, drag to Applications

### Option 2: Build with Swift + Manual Signing

```bash
# Clone and build
git clone https://github.com/damienheiser/pickle-cider
cd pickle-cider
swift build -c release

# Find your signing identity
security find-identity -v -p codesigning

# Sign with your certificate (replace YOUR_IDENTITY)
codesign --force --deep --sign "YOUR_IDENTITY" .build/release/PickleCider
codesign --force --sign "YOUR_IDENTITY" .build/release/cider
codesign --force --sign "YOUR_IDENTITY" .build/release/pickle

# Create app bundle
./Scripts/build-app-bundle.sh

# Install
cp -r .build/release/PickleCider.app /Applications/
sudo cp .build/release/cider .build/release/pickle /usr/local/bin/
```

### Option 3: Quick Build Script

```bash
git clone https://github.com/damienheiser/pickle-cider
cd pickle-cider
./Scripts/install.sh
```

---

## Granting Full Disk Access

After installation, you must grant Full Disk Access:

1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Add **Pickle Cider.app** (from Applications)
4. Also add **Terminal.app** if using CLI tools
5. **Quit and reopen** the app (required for changes to take effect)

---

## Usage

### GUI App (Pickle Cider)

Launch from Applications. The app will guide you through granting permissions on first launch.

### CLI Tools

```bash
# Initialize Cider sync
cider init

# Export all notes to markdown
cider pull ~/Documents/notes --recursive

# Upload files to Apple Notes
cider push ~/Documents/notes/my-note.md

# Bidirectional sync
cider sync ~/Documents/notes --folder "My Synced Notes"

# Install Pickle daemon for automatic versioning
pickle install --interval 30

# Check status
pickle status

# View version history
pickle history "My Important Note"

# Compare versions
pickle diff 1 2

# Restore to previous version
pickle restore 5

# Export versions
pickle export "My Note" ~/exports --format md
```

---

## Commands Reference

### Cider Commands

| Command | Description |
|---------|-------------|
| `cider init` | Initialize sync state database |
| `cider pull <dir>` | Export Apple Notes to markdown files |
| `cider push <path>` | Upload files to Apple Notes |
| `cider sync <dir>` | Bidirectional sync |
| `cider status` | Show sync status |

### Cider Options

```
--folder <name>       Target Apple Notes folder (default: "Cider Sync")
--format <md|txt>     Output format (default: md)
--recursive           Process subdirectories
--dry-run             Preview without making changes
--force               Overwrite conflicts
--verbose             Verbose output
```

### Pickle Commands

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

### Pickle Options

```
--interval <seconds>  Check interval for daemon (default: 30)
--max-versions <n>    Max versions per note (default: 100)
--limit <n>           Limit results
--format <md|txt|json>  Export format
--verbose             Verbose output
```

---

## Data Storage

| Tool | Location | Purpose |
|------|----------|---------|
| Cider | `~/.cider/state.db` | Sync state tracking |
| Pickle | `~/.pickle/versions.db` | Version metadata |
| Pickle | `~/.pickle/versions/` | Version content (gzipped JSON) |
| Pickle | `~/.pickle/logs/` | Daemon logs |

---

## Technical Details

### How It Works
- **Reading Notes**: Direct SQLite access to Apple Notes database
- **Writing Notes**: AppleScript via NSAppleScript (preserves iCloud sync)
- **Content Format**: Notes are stored as gzip-compressed protobuf
- **Change Detection**: Polling-based (SQLite WAL makes file watching unreliable)

### Limitations
- Password-protected notes cannot be accessed (skipped with warning)
- Attachments are referenced but not synced
- Requires Full Disk Access for database read access

---

## Troubleshooting

### "SQLite error 23: authorization denied"
Full Disk Access not granted or not applied yet.
1. Check System Settings → Privacy & Security → Full Disk Access
2. Ensure Pickle Cider and/or Terminal are listed and enabled
3. **Quit and reopen** the app (macOS caches permissions)

### App doesn't appear in Full Disk Access list
The app must be properly signed. Build with Xcode or sign manually with your development certificate.

### Daemon not starting
```bash
# Check if daemon is installed
launchctl list | grep pickle

# View daemon logs
cat ~/.pickle/logs/stdout.log
cat ~/.pickle/logs/stderr.log

# Reinstall daemon
pickle uninstall
pickle install
```

---

## License

MIT License - see [LICENSE](LICENSE)

---

## Credits

Built with:
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [Swift Protobuf](https://github.com/apple/swift-protobuf)
- [SwiftSoup](https://github.com/scinfu/SwiftSoup)

Inspired by:
- [apple_cloud_notes_parser](https://github.com/threeplanetssoftware/apple_cloud_notes_parser)
- [Apple Notes Liberator](https://github.com/HamburgChimps/apple-notes-liberator)

# TODO

Ideas that are not in v0.1. Roughly grouped; nothing here is committed to.

## Rules and actions

- Content-based conditions (text inside PDFs, EXIF data, image dimensions)
- Tag and colour-label conditions
- "Expire only if never opened" (`kMDItemLastUsedDate`)
- Auto-sort into folders by type, date or source
- Rename patterns on arrival (date prefix, strip junk like `(1)`)
- Auto-unzip archives, then trash the archive
- Duplicate detection (same hash, or `name (1).ext` pattern)
- Run a shell script, Shortcut or AppleScript as a rule action
- Move to a holding folder instead of trashing, then wipe later
- Preview a rule against existing files (dry run)
- Rule import/export and iCloud sync
- Rule groups and per-folder rules

## Folders

- Watch more than one folder (Desktop, Documents, a project inbox)
- Optional recursive tracking
- Auto-empty Trash items older than N days
- App uninstall leftovers cleanup

## Toast and menu

- Quick Look preview from the toast and menu rows
- A persistent shelf: a drop zone to park files temporarily
- Global hotkey for a recent-downloads popup
- Batch toast ("12 files will be trashed") with a review list
- Undo the last expiry
- Warn shortly before expiry as well as on arrival
- Drag files out of the menu list
- Menu bar icon that reflects state (paused, files expiring soon)

## Polish and distribution

- Proper app icon
- Stats: space reclaimed, files expired per week
- AppleScript / Shortcuts support
- Sparkle updates
- Developer ID signing and notarisation
- Homebrew cask
- Localisation

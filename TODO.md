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

## Screenshot toast: true preview at capture time

Today the toast shows a camera emoji, then swaps in the real preview about 5 s
later when macOS writes the file. To show the actual image the moment the
thumbnail appears, test a Screen Recording re-grab:

- On the logged capture event, call `SCScreenshotManager.captureImage(in:)`
  (macOS 15.2+) with the `captureRect` that `screencapture` logs, and use a
  filter that excludes the screenshot UI and Burndown so the sliding thumbnail
  and the toast are not in the image
- Plan a small spike: grab on a real capture, time it, check memory and CPU

Pros

- The preview appears with the toast instead of 5 s later
- Reuses the capture event Burndown already gets from the log

Cons

- Needs Screen Recording permission: a one-time prompt, the toggle in System
  Settings, then a relaunch
- Sequoia re-asks for approval about monthly; not confirmed whether Tahoe still
  does
- Burndown is ad-hoc signed, so every rebuild loses the grant. It needs a stable
  signing certificate first
- It is a re-grab tens of milliseconds after the capture, so moving content may
  differ from the real shot
- `CGWindowListCreateImage` and `CGDisplayCreateImage` are obsoleted in macOS
  15, so ScreenCaptureKit is the only route

Ruled out (checked, not worth revisiting)

- No staging file, pasteboard write or readable temp folder holds the image
  before the thumbnail times out
- Accessibility does not expose the thumbnail's pixels
- Turning off the macOS floating thumbnail makes the file land instantly (no
  permission needed), but loses the thumbnail's markup and drag features

## Polish and distribution

- Proper app icon
- Stats: space reclaimed, files expired per week
- AppleScript / Shortcuts support
- Sparkle updates
- Developer ID signing and notarisation
- Homebrew cask
- Localisation

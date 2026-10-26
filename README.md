# Burndown

A small macOS menu bar app that stops your Downloads folder silting up. Every new download gets a
lifetime; when it runs out the file is moved to the Trash (or wiped). The menu bar icon is a trash can on fire.

- Watches `~/Downloads` for new files from any source (browsers, AirDrop, curl, Mail...)
- A toast shows `<icon> <name> will be trashed after 14 days` with **Keep** and **Expire now** buttons,
  and the file can be dragged straight out of it
- Optionally tracks macOS screenshots wherever they are saved
- Ordered rules: ignore by extension/name/size, per-type lifetimes, lifetimes by source site
- Trash is recoverable; Wipe is a permanent delete (no Trash)
- Native Swift, event-driven (FSEvents, no polling), one timer armed for the next due date

Requires macOS 26.

## Build and run

```sh
make test      # unit tests
make run       # build, ad-hoc sign, launch build/Burndown.app
make install   # copy to /Applications
```

## Behaviour

- **Keep** adds a Finder tag called `Keep` to the file and stops tracking it. Remove the tag in Finder to
  un-keep it (it will be picked up again only if it is re-downloaded or adopted).
- Files already in Downloads when you first launch are left alone. Use **Adopt existing files** in the menu to
  start their countdown.
- A file moved out of Downloads is untracked (you have filed it), and a file with the `Keep` tag is never
  removed.
- Screenshot tracking is off by default and only picks up screenshots taken after it is enabled.
- Defaults: downloads 14 days then Trash; screenshots untracked.

State lives in `~/Library/Application Support/Burndown/state.json`.

## Debugging

`BURNDOWN_TIME_SCALE=3600 build/Burndown.app/Contents/MacOS/Burndown` makes hours pass as seconds so you can
watch real expiry.

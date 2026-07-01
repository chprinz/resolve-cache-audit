# DaVinci Resolve Cache Audit

Resolve's cache lives in folders named after opaque UUIDs, scattered
across every drive you've ever pointed it at. There's no built-in way to
see which project owns how much, especially once you've deleted the
project itself.

This tool scans everything and answers that: project name, drive, size,
sorted by size. Render cache, Optimized Media, and audio cache together,
including cache left behind by projects you've already deleted.

![Cache Audit dashboard, showing a sample scan grouped by disk database](CacheAudit/screenshot.png)

Download the app, open the DMG, drag it into Applications. First launch
needs one extra click, see below.

**Requirements:** macOS 14 or later, DaVinci Resolve with a Disk Database
project library (for the configured-cache-path lookup; the scan itself
works with any library type).

## Why not just use Resolve's own Cache Manager?

Since 18.5, `Playback → Delete Render Cache → Manage Cache Data` gives you
a cross-project view of **render cache**. This tool covers what that
doesn't:

- **Optimized Media and audio cache.** Deletable from Resolve, but it
  won't tell you which project they belong to. This tool maps all three
  cache types back to project names the same way.
- **Orphaned cache** from projects you've deleted. Invisible to Resolve's
  manager, since there's no project left to attach it to. Still found
  here.
- **Deletion goes to Trash**, not straight to disk. Resolve's own manager
  has no undo.
- Works without opening Resolve at all.

## How it works

Every UUID-named cache folder (for example `eee02c2c-...`) contains a
plain-text `Info.txt` that Resolve writes itself, mapping it back to a
project name. No SQLite parsing needed. The tool scans every mounted drive
automatically, reads those files, measures actual disk usage, and sorts
everything by size, grouped by disk database when you have more than one.

## First launch (unsigned build)

This build isn't notarized by Apple (that needs a paid Developer account).
It's ad-hoc signed instead, which is normal for a small free tool outside
the App Store. One-time step: right-click `Cache Audit.app` in
Applications, choose **Open**, then **Open** again in the dialog. After
that it opens normally.

## Build from source

Open `CacheAudit/CacheAudit.xcodeproj` in Xcode and run, or run
`xcodegen generate` in `CacheAudit/` first if the `.xcodeproj` is missing
(`brew install xcodegen`).

## Also included: a read-only shell script

`DaVinci Cache Audit.command` runs the same scan in Terminal, no app
needed, just double-click it. It's strictly read-only (`find`, `du`,
`SELECT` only) and safe to run anytime, even with Resolve open.

## License

MIT, see [LICENSE](LICENSE).

# DaVinci Resolve — Cache Audit

See which project's cache is eating up which drive — render cache,
Optimized Media, and audio cache together, including cache left behind by
projects you've already deleted.

![Cache Audit dashboard, showing a sample scan grouped by disk database](CacheAudit/screenshot.png)

**[Download the app](../../releases)** — open the DMG, drag into
Applications. First launch needs one extra click, see below.

## Why not just use Resolve's own Cache Manager?

Since 18.5, `Playback → Delete Render Cache → Manage Cache Data` gives you
a cross-project view of **render cache**. This tool covers what that
doesn't:

- **Optimized Media & audio cache** — deletable from Resolve, but without
  showing which project owns them. This tool maps all three cache types
  back to project names the same way.
- **Orphaned cache** from projects you've deleted — invisible to Resolve's
  manager since there's no project left to attach it to. Still found here.
- **Deletion goes to Trash**, not straight to disk — Resolve's own manager
  has no undo.
- Works without opening Resolve at all.

## How it works

Every UUID-named cache folder (e.g. `eee02c2c-...`) contains a plain-text
`Info.txt` that Resolve itself writes, mapping it back to a project name —
no SQLite parsing needed. The tool scans every mounted drive automatically,
reads those files, measures actual disk usage, and sorts everything by
size, grouped by disk database when you have more than one.

## First launch (unsigned build)

This build isn't notarized by Apple (that needs a paid Developer account)
— it's ad-hoc signed instead, normal for a small free tool outside the App
Store. One-time step: right-click `Cache Audit.app` in Applications →
**Open** → **Open** again in the dialog. After that it opens normally.

## Build from source

Open `CacheAudit/CacheAudit.xcodeproj` in Xcode and run, or
`xcodegen generate` in `CacheAudit/` first if the `.xcodeproj` is missing
(`brew install xcodegen`).

## Also included: a read-only shell script

`DaVinci Cache Audit.command` does the same scan in Terminal, no app
needed — just double-click it. It's strictly read-only (`find`, `du`,
`SELECT` only) and safe to run anytime, even with Resolve open. The
configured-cache-path part needs a **Disk Database** project library (not
Resolve's default cloud/Postgres library); the cache scan itself works
either way.

## License

MIT — see [LICENSE](LICENSE).

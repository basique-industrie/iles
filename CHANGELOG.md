# Changelog

Notable user-facing changes are documented here. Versions follow Semantic
Versioning in the same published shapes as `jean-humann/gwnative`: `X.Y.Z` or
`X.Y.Z-(alpha|beta|rc).N`. The About pane and GitHub release title show that
string with no leading `v`. Tags add the `v`.

## Unreleased

### Changed

- A new install starts with an empty workspace. The edge plus opens Settings,
  or brings the existing Settings window forward if it is already open.

### Fixed

- ⌘-drag now moves the empty-workspace plus pill, and the first added island
  keeps that placement.

## 0.1.0-beta.2 - 2026-09-03

### Fixed

- Packaged builds no longer crash on launch when loading provider marks.
  SPM's `Bundle.module` looks next to the `.app`, so the packaged resource
  bundle is now resolved from `Contents/Resources`.

## 0.1.0-beta.1 - 2026-09-02

### Added

- Local-first complication workspace with multiple edge islands and more than
  135 source-aware recipes.
- Per-element data, used/remaining, and color configuration for multi-ring
  complications.
- Fingerprint-bound local extension trust and authenticated loopback Claude Code
  hooks.
- Redacted support-log export, durable settings recovery, release automation,
  privacy manifest, and open-source project governance.

### Changed

- Refined the settings hierarchy and watch-style visual language throughout the
  source, island, and complication workflows.
- Coalesced concurrent provider refreshes and paused background refresh while
  the display sleeps.

### Removed

- First-version quota notifications and unused monitoring infrastructure.

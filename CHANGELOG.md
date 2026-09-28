# Changelog

Notable user-facing changes are documented here. Versions follow Semantic
Versioning in the same published shapes as `jean-humann/gwnative`: `X.Y.Z` or
`X.Y.Z-(alpha|beta|rc).N`. The About pane and GitHub release title show that
string with no leading `v`. Tags add the `v`.

## Unreleased

### Added

- Native Harnais integration for configured Claude, Codex and Cursor accounts.
  Iles refreshes usage through the local account helper on its own schedule.
- Overview with island readings and direct editing, persistent sidebar
  navigation, and System, Light and Dark appearances.
- Account-following Harnais starter collection and independent used/remaining
  modes for each metric slot.

### Changed

- Compact islands keep their 48-point width. Paired usage values use two lines;
  storage readings separate the amount and unit.
- Widget creation uses a compact preview, full-width metric and color controls,
  account-grouped menus, and readable gallery cards. Search matches each recipe's
  metrics rather than every metric supplied by its source.
- Hover details show selected readings first, additional account usage, refresh
  time and an Edit widget action. Finite transitions respect Reduce Motion.
- AI catalogs show sources used in saved islands and configured Harnais accounts.
  General can hide standalone providers duplicated by Harnais.
- Removed the unavailable automatic Alibaba cookie importer and the battery
  source from new catalogs. Saved battery widgets retain their source and recipes.

### Fixed

- Missing account data no longer causes widgets to switch to another account.
  Missing slots retain their positions in paired readings.
- Manually removing a Harnais widget stops automatic additions for that island.
  Undo restores both the widget and its account-following preference.
- Harnais stays in the catalog after its last widget is removed. Adding a widget
  from Sources creates a destination island when needed.
- Island names save on commit; placement sliders no longer draw hundreds of
  ticks below the track. Fable labels use an uppercase F.
- Codex numeric parsing rejects nonfinite readings and out-of-range reset dates.
- Failed refreshes retain the last successful sample and timestamp. Malformed
  visibility preferences fail the refresh rather than enabling hidden widgets.

## 0.1.0 - 2026-09-03

### Added

- A one-shot callout on the empty-workspace plus points new installs at Settings.
  The empty Islands canvas can open starter collections in one step.
- GitHub repository setup lists repositories from the existing `gh` login so a
  repo can be selected instead of typed.

### Changed

- The README leads with the product instead of a badge-and-icon banner.
- A new install starts with an empty workspace. The edge plus opens Settings,
  or brings the existing Settings window forward if it is already open.
- Local `scripts/package.sh` and `scripts/run.sh` now produce **Iles Dev**
  (`com.jean.iles.dev`, `~/.iles-dev/`) so it can run next to the notarized
  **Iles** app without sharing settings, Keychain items, or Claude hooks.
- The Iles Dev menu extra uses an orange mark so it is distinct from shipped
  Iles. That extra is an AppKit status item, so the tint no longer depends on
  a private status-bar getter.
- Iles Dev General diagnostics use Iles Dev log names for the log path,
  delete prompt, and support-log export.
- Third-party notices name SwiftTerm without a second version pin. The
  linked version is the `exact:` pin in `Package.swift`.
- Docs and the pull-request template run `./scripts/test.sh`. `swift test`
  does not see the custom suite.
- The README recipe count matches the first-party launch catalog.

### Removed

- The menu extra no longer shows a disabled Demo/Live row. Demo data is still
  `./scripts/run.sh --demo`.

### Fixed

- ⌘-drag now moves the empty-workspace plus pill, and the first added island
  keeps that placement.
- GitHub repository listing no longer fails when `gh` is already logged in.
  Iles was reading `gh` through a terminal session, which opened a pager and
  hid the repository JSON.
- Fork pull requests no longer run CI on the shared org Mini. That runner
  also signs releases, so untrusted fork workflows stay off it.

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

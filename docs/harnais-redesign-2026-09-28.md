# Iles redesign and pre-commit review

## Current design

Settings uses Harnais's adaptive surfaces, blue controls, typography and spacing.
The floating islands retain Iles's black silhouette and provider colors. Islands
are 48 points wide, with 24-point rings and two lines for paired usage readings.

Overview provides readings and direct editing. Islands contains placement,
ordering and widget configuration. Sources owns setup and refresh controls.
Settings contains appearance, startup and refresh settings. The widget inspector
separates Appearance, Data and Behavior, with a compact preview and an explicit
notice that changes apply immediately.

The settings window now matches Harnais's 52-point titlebar, native traffic-light
placement and 260-point sidebar. Navigation uses 32-point rows, 15-point icons,
13-point labels and the same subtle selection fill. The island list stays visible
across pages. Shared controls use Harnais's hover colors, 20-point page titles,
and 16/24/32-point top/horizontal/bottom page padding. Floating islands keep their
existing geometry and colors. Overview, Settings, About and source details fill
the available content width with consistent page insets. Settings actions use one
row on wider windows and wrap into two rows when space is limited.
The alignment pass was checked live in Overview, the island editor and dark
Settings. System appearance was restored after inspection. All 694 checks and
the public-release checks passed before packaging.

The gallery shows readable account titles, window names and values beside compact
thumbnails. Data selectors group metrics by account. Each slot has separate
value-mode and color controls. The shared slot renderer is used by floating
islands, editor previews and gallery thumbnails.

## Harnais integration

Harnais owns account configuration, credentials and ring visibility. Iles invokes
the installed account helper to fetch usage, schedules its own refreshes and
uses the successful sample's timestamp. It does not use the freshness of the
Harnais GUI or its cached quotas file. Startup, manual and scheduled requests
share the registry's single-flight refresh gate.

Visibility preferences come from the sibling islands.json configuration. Hiding
a quota preserves its widget, position and settings. A paired widget containing
a hidden quota is hidden as a whole. Malformed preferences fail the refresh
rather than silently enabling hidden widgets. Failed refreshes preserve the last
successful readings and timestamp.

Saved islands opt into new-account additions explicitly. Manual removal of a
Harnais widget turns that island into a custom collection; Undo restores the
previous following preference. Missing or renamed account windows retain their
saved configuration. They are never reassigned by matching only a provider and
time window. Exact recipe matches can repair drifted metric keys.

The AI catalog contains sources referenced by saved islands, including hidden
ones, and Harnais accounts with fetched usage. Saved battery widgets retain their
legacy source and recipes; new workspaces do not advertise that source.

## Review findings and fixes

- Removed provider/window-based account reassignment. It could display another
  account's usage when a saved account temporarily disappeared.
- Preserved missing metric positions. An unavailable outer-ring reading now
  shows a placeholder instead of taking the inner ring's reading and label.
  Partially resolved widgets report unavailable data.
- Kept Harnais available after removing its last widget. Adding from Sources
  creates a destination island when none exists.
- Prevented account-following reconciliation from immediately recreating a
  deleted widget. Undo restores the widget, order and following preference.
- Restored legacy battery compatibility so saved widgets remain resolvable.
- Rejected nonfinite Codex readings and out-of-range reset timestamps before
  formatting. Integer, decimal and numeric-string inputs remain supported.
- Restricted gallery searches to each recipe's metrics instead of matching every
  recipe whenever any metric in its source matched.
- Replaced duplicated source/gallery cards with ComplicationRecipeCard. Both
  views now put readable values beside compact previews. Sources uses two wider
  columns and opens the editor after adding a widget.
- Preserved distinct accessibility labels for Used and Remaining. Placement and
  Focus sliders now describe their own units.
- Removed unused design tokens, an unused popup-style parameter and obsolete
  reconciliation helpers. Corrected documentation that described cached-feed
  refresh and automatic removal as current behavior.

## Runtime and performance review

Refresh tasks are deduplicated per source. Local sources keep their existing fast
or slow schedule; network sources use the user-selected interval and battery
cadence. Placement previews move panels without rebuilding their content.
Snapshot observation is isolated per source.

Ring changes interpolate for 180 ms. Detail-card entry lasts 140 ms and movement
between rows lasts 120 ms. These transitions are finite and cancellable, and
respect Reduce Motion. No new idle animation loop or polling timer was added.

A pre-restart process sample with Settings open measured 0.6% CPU and about
153 MiB resident memory. After the final rebuild, five samples taken three
seconds apart while closing Settings ranged from 0–9.5% CPU and 129–130 MiB
resident memory; the last two CPU readings were 0%. These are spot checks, not
evidence of a performance improvement or a long-duration memory benchmark.

## Verification

The subsequent [view-by-view UI review](ui-review-2026-09-28.md) records the source,
gallery, inspector and resize checks from the latest design-system pass.

Automated tests cover refresh coalescing, independent freshness, failed and
malformed responses, visibility preservation, slot ordering, account identity,
removal/undo, legacy source compatibility, geometry, persistence, quota
transforms and parser bounds. The development bundle is built with the release
configuration and packaged separately from the shipped app.

- All 694 checks passed. Release packaging, public-release checks and
  git diff --check passed.
- Live review covered Overview, the island editor, the Data inspector, grouped
  selectors, Sources, gallery search and General in light and dark appearance.
  Searching Codex returned only its three configured account recipes.
- Accessibility inspection confirmed separate Used and Remaining buttons.
- The final Sources view showed readable values in two columns using the same
  recipe cards as the gallery. The packaged Iles Dev bundle was relaunched and
  its new process verified.
- The saved workspace hash matched before and after restarting. Appearance was
  restored to System. Account values refreshed through Iles after launch.
- External login changes and destructive edits were not performed on the user's
  workspace. Removal/Undo and compatibility behavior used isolated fixtures.

## Remaining limits

- Account renames need stable account and window IDs in the Harnais contract for
  automatic migration. Until then, a renamed widget may need its data selected
  again. The app preserves the old configuration.
- Typed per-account failure and first-use metadata is not fully represented in
  the native quota model. An absent metric is reported as missing. Reset-credit
  counts and next-expiry dates now pass through to hover cards.
- Multiple displays, display scaling changes, macOS Reduce Motion enabled and
  long-duration memory growth need dedicated live coverage. The corresponding
  code paths were reviewed, but those scenarios were not reproduced here.
- This review does not authenticate every standalone provider or exercise every
  external service. Parser fixtures and local runtime checks do not replace
  end-to-end service coverage.

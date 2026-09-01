# Architecture

Iles is a Swift Package split into four production targets:

- `Domain` owns models, policies, catalog validation, and I/O protocols. It has
  no UI or provider implementation dependencies.
- `Infrastructure` implements network, credential, storage, hook, subprocess,
  extension, and provider adapters.
- `IslandGeometry` contains reusable placement and panel geometry.
- `IlesCore` composes application state and SwiftUI. The small
  `Iles` executable target starts the app.

`IslandRuntime` is the application composition root. A
`ComplicationSourceRegistry` owns source instances and coalesces concurrent
refreshes. `IslandWorkspaceStore` persists user configuration through the
versioned, atomic `JSONSettingsStore`. UI views consume domain values and do not
perform provider I/O directly.

## Reliability boundaries

- Network sessions are ephemeral and response bodies are bounded by each
  adapter's parser contract.
- External processes drain stdout and stderr concurrently, enforce a deadline,
  cap captured output, and are terminated as a process group when possible.
- Persistence uses owner-only files, atomic replacement, a last-known-good
  backup, schema migration, and corrupt-file quarantine.
- Provider credentials use Keychain where the app owns them. Existing vendor
  CLI credentials are read only when their source is enabled.
- Extension trust covers hidden files as well as visible files and is invalidated
  by any content change.

The standalone test executable combines focused security-boundary checks with
the application regression harness, without requiring XCTest to be installed.

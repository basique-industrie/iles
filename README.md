# Iles

Iles is a local-first, watch-style complication workspace for macOS.
Build compact edge islands from AI usage, coding activity, time and calendar,
Mac health, focus, repositories, shipping status, service health, and trusted
local extensions.

Requires **macOS 26 or newer**.

## Status

The project is preparing its first public release. Provider integrations are
community-maintained and are not affiliated with their respective vendors.
Some AI usage sources read an installed vendor CLI's local state or use an
undocumented endpoint; those sources can change or stop working without notice.

## Build and install locally

```bash
./scripts/package.sh
cp -R dist/Iles.app /Applications/
open /Applications/Iles.app
```

The local packaging script uses an ad-hoc signature. Public artifacts must use
the signed and notarized workflow in [docs/RELEASE.md](docs/RELEASE.md).

Iles has no Dock icon. **Settings…** opens the island editor,
searchable complication catalog, source setup, general settings, and About.

## Develop and test

```bash
./scripts/run.sh          # live probes
./scripts/run.sh --demo   # deterministic demo values
swift test               # regression and security suites
./scripts/check-public-release.sh
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for module boundaries and reliability
controls, and [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a change.

## Catalog

The launch catalog contains more than 135 curated recipes in seven areas:

- **AI** — quota used or remaining per ring, quota health, reset countdowns,
  burn pace, and cost or budget values for supported providers.
- **Sessions** — Claude Code state, project, duration, tasks, agents, and recent
  sessions.
- **Time** — clock and period progress, Calendar events, meeting progress, free
  time, and Reminders.
- **Mac** — battery, CPU, memory, storage, network, thermal state, low-power mode,
  and uptime.
- **Focus** — an app-owned focus and break timer, daily goal, sessions, and
  streak.
- **Developer** — local Git state plus GitHub Actions, pull requests, reviews,
  and deployments through an existing `gh` login.
- **Services** — configurable HTTP endpoint status, latency, availability, and
  failure count.

AI sources include Claude, Codex, Gemini, Antigravity, Z.ai, Copilot, Amp, Kimi,
Kiro, Cursor, MiniMax, DeepSeek, Vercel, Alibaba, Mistral, OpenCode, OpenCode
Mobile, and Grok. Recipes appear only when their source exposes the required
metrics; setup-dependent sources never display invented values.

The default workspace contains one right-edge island with Claude, Codex, and
Cursor rings. Starter collections add coherent stacks for AI, Mac health,
coding focus, day planning, shipping, or service monitoring.

## Features

- Multiple independent islands on either screen edge and any connected display
- Nine visual families: ring, dual ring, value, status, activity, countdown,
  trend, summary, and trio ring
- Independent data, used/remaining presentation, tint, label, and click action
  for every complication element
- Search, readiness filters, starter collections, live previews, drag ordering,
  duplication, swipe deletion, and contextual actions
- Explicit setup for Calendar, Reminders, Git, GitHub, services, Claude hooks,
  and extensions
- Typed metric policies, transformations, bounded history, stale-data treatment,
  and coalesced refresh
- Local extension schema v2 with fingerprint-bound trust, direct executable
  review, deadlines, output limits, and no automatic download or update

See [Extension manifest v2](docs/extension-manifest-v2.md) to build a local
source. There is intentionally no public extension marketplace.

## Local data

| Data | Location |
|---|---|
| Settings | `~/.iles/settings.json` |
| Extensions | `~/.iles/extensions/` |
| Redacted logs | `~/Library/Logs/Iles/` |
| App credentials | Keychain service `com.jean.iles.credentials` |
| Claude hook | marked entry in `~/.claude/settings.json` |

Network activity is limited to enabled provider and service sources. There is
no analytics, telemetry, or tracking. Read [PRIVACY.md](PRIVACY.md) and
[SECURITY.md](SECURITY.md) for exact boundaries and removal instructions.

## License and trademarks

Code is available under the [MIT License](LICENSE). Third-party library notices
and provider-mark information are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Provider names and logos
belong to their respective owners and identify compatibility only.

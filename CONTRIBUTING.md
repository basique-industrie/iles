# Contributing

Thanks for helping improve Iles.

## Before opening a change

- Search existing issues and keep each pull request focused.
- Discuss large behavior, persistence-schema, security-boundary, or visual-
  language changes before implementation.
- Never commit provider credentials, cookies, user paths, account data, build
  products, or unredacted diagnostic logs.
- Confirm that any new asset can be redistributed and document its source and
  license in `THIRD_PARTY_NOTICES.md`.

## Development

Iles requires macOS 26 and the matching Swift toolchain.

```bash
swift build --product Iles
swift test
./scripts/check-public-release.sh
```

Keep domain policy in `Sources/Domain`, OS and provider adapters in
`Sources/Infrastructure`, and SwiftUI/runtime composition in
`Sources/Iles`. Prefer small focused types, dependency injection at I/O
boundaries, structured concurrency, bounded external processes, and tests for
failure paths as well as successful responses.

## Pull requests

Describe the user-visible outcome, security/privacy impact, verification, and
screenshots for UI changes. Update `CHANGELOG.md` under **Unreleased**. By
submitting a contribution, you agree that it is licensed under the MIT License.

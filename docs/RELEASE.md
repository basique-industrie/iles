# Release process

## One-time setup

1. Install the macOS 26 SDK and a Swift 6.2 toolchain.
2. Install a Developer ID Application certificate.
3. Store App Store Connect notarization credentials in a keychain profile:

   ```bash
   xcrun notarytool store-credentials Iles-notary
   ```

4. Rewrite any private `.local` author email addresses before the repository's
   first public push. Do not rewrite shared public history afterward.

## Prepare

1. Move entries from `CHANGELOG.md`'s Unreleased section into the release
   version and date.
2. Keep `CFBundleShortVersionString`, `CFBundleVersion`, and the Git tag aligned.
3. Review every provider endpoint and brand asset against current vendor terms.
4. Run:

   ```bash
   swift test
   ./scripts/check-public-release.sh
   CHECK_HISTORY=1 ./scripts/check-public-release.sh
   ```

5. Commit the release, then create and check out the annotated tag matching the
   app version (for example `v1.0.0`). The release script refuses an untagged or
   mismatched commit.

## Build, sign, and notarize

```bash
SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
NOTARY_PROFILE="Iles-notary" \
./scripts/release.sh
```

The script creates a universal, hardened-runtime app, verifies its signature,
submits it to Apple, staples the ticket, archives the app, and writes a SHA-256
checksum. Test the stapled app on a clean macOS user account before publishing.

The ordinary `scripts/package.sh` command makes an ad-hoc-signed local build; it
is intentionally not suitable for public distribution.

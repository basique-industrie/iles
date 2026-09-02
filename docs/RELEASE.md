# Release process

## One-time setup

1. Install the macOS 26 SDK and a Swift 6.2 toolchain.
2. Install a Developer ID Application certificate.
3. Store App Store Connect notarization credentials in a keychain profile:

   ```bash
   xcrun notarytool store-credentials iles \
     --key AuthKey_XXXX.p8 --key-id KEY_ID --issuer ISSUER
   ```

   CI uses the same App Store Connect key and Developer ID certificate as
   `jean-humann/gwnative`, under the `release` environment secrets:

   - `APPLE_DEVELOPER_ID_APPLICATION_P12`
   - `APPLE_DEVELOPER_ID_PASSWORD`
   - `APPLE_NOTARY_KEY_ID`
   - `APPLE_NOTARY_KEY_ISSUER`
   - `APPLE_NOTARY_KEY_P8`

   GitHub never returns secret values. Copy them once from the gwnative
   `release` environment into `basique-industrie/iles` → Environments →
   `release`. The names must match exactly.

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
./scripts/release.sh
```

The script discovers the Developer ID identity, uses the `iles` notary
profile, builds a universal hardened-runtime app, notarizes it, staples the
ticket, and writes a SHA-256 checksum. Override with `ILES_SIGN_IDENTITY` or
`NOTARY_PROFILE` if more than one identity is installed.

Pushing tag `v1.0.0` runs the same script on GitHub Actions after the `release`
environment is approved. `workflow_dispatch` with `dry_run` notarizes without
publishing.

Test the stapled app on a clean macOS user account before publishing.

The ordinary `scripts/package.sh` command makes an ad-hoc-signed local build; it
is intentionally not suitable for public distribution.

# Security policy

## Supported versions

Security fixes are applied to the latest release and the `main` branch. Older
builds are not supported.

## Reporting a vulnerability

Do not open a public issue for a vulnerability. Use GitHub's private
**Security advisories → Report a vulnerability** flow for this repository.
Include the affected version, reproduction steps, impact, and any suggested
mitigation. Please avoid including real access tokens, cookies, account data,
or unredacted logs.

You should receive an acknowledgement within seven days. A coordinated fix and
disclosure timeline will be proposed after the report is reproduced.

## Security model

Iles is a local menu-bar utility, but it is intentionally not sandboxed:
it reads supported CLI configuration, invokes installed local tools, and can run
extensions that the user explicitly trusts. The app:

- stores app-managed secrets in the macOS Keychain;
- binds its Claude hook receiver to loopback with a per-launch authentication
  token and strict request limits;
- fingerprints every file in a script extension before trust is granted;
- executes only the reviewed relative executable, with a timeout and bounded
  output;
- redacts diagnostic logs and gives their directory and files owner-only
  permissions;
- does not provide automatic extension download or update behavior.

Trust an extension only if you have reviewed all of its files. A trusted script
runs with the same user permissions as Iles. Provider integrations may
depend on vendor CLI files or undocumented endpoints and can stop working when
vendors change them.

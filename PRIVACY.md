# Privacy

Iles is local-first. It contains no analytics SDK, advertising SDK,
tracking, crash-upload service, or telemetry endpoint.

## Data processed on your Mac

Depending on the sources you enable, the app can read local CLI credentials and
state, Calendar events, Reminders, Git repositories, GitHub CLI output, Mac
health information, focus-timer state, and responses from provider or service
endpoints you configure. Data is used to render the islands and source detail
views. It is not sent to the Iles project or its maintainers.

App-managed credentials are stored in macOS Keychain with accessibility limited
to an unlocked device. Non-secret preferences are stored in
`~/.iles/settings.json`. The local **Iles Dev** build uses
`~/.iles-dev/settings.json` instead. Redacted, size-limited diagnostics are
stored in `~/Library/Logs/Iles/` or `~/Library/Logs/Iles-Dev/`; support logs
leave the Mac only when you export and share one yourself.

## Network requests

Network requests go directly from your Mac to the provider, GitHub, or health
endpoint represented by an enabled source. Sessions use ephemeral URLSession
configuration without a shared credential store, cookies, or URL cache.

Some usage integrations rely on vendor CLI credentials or endpoints that are
not public supported APIs. Enabling one may be subject to the provider's terms
and can expose account usage metadata to that provider in the same way as its
own client. Review the source code and your provider terms before enabling it.

## Permissions

Calendar and Reminders permission is requested only from the corresponding
source setup view. Launch at Login is opt-in. Local script extensions are never
run until their exact content fingerprint has been reviewed and trusted.

The bundled privacy manifest declares Disk Space, System Boot Time, and File
Timestamp required-reason APIs used for storage, uptime, and local file-change
detection.

## Removing local data

Quit Iles, remove `~/.iles/`, remove
`~/Library/Logs/Iles/`, and delete entries for the Keychain service
`com.jean.iles.credentials`. For Iles Dev, use `~/.iles-dev/`,
`~/Library/Logs/Iles-Dev/`, and `com.jean.iles.dev.credentials`. If the Claude
Code hook was enabled, disable it in that app first so only its marked hook
entry is removed cleanly.

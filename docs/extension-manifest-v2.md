# Extension manifest v2

Iles loads local extensions from `~/.iles/extensions/<name>/`. Iles Dev uses
`~/.iles-dev/extensions/<name>/` instead.
Each extension needs a `manifest.json` and may include relative probe scripts.
Schema v2 is the only accepted schema; pre-launch manifests are not migrated.

## Minimal typed source

```json
{
  "schemaVersion": 2,
  "id": "example-service",
  "name": "Example Service",
  "version": "1.0.0",
  "description": "Local metrics for an example service.",
  "category": "services",
  "metrics": [
    {
      "id": "latency",
      "name": "Latency",
      "kind": "gauge",
      "unit": "ms"
    }
  ],
  "sections": [
    {
      "id": "service",
      "type": "metricsRow",
      "probe": {
        "command": "probe.sh",
        "interval": 60,
        "timeout": 10
      }
    }
  ],
  "complications": [
    {
      "id": "example-service.latency",
      "name": "Service Latency",
      "shortName": "Latency",
      "summary": "Current response latency for the example service.",
      "question": "How quickly is the service responding?",
      "tags": ["service", "latency"],
      "family": "ring",
      "compatibleFamilies": ["ring", "value"],
      "slots": [{ "metricID": "latency", "transforms": [] }],
      "labelStyle": "value",
      "tint": "source",
      "tapAction": "showDetails",
      "rank": 50,
      "isFeatured": false,
      "isNew": false,
      "fixtures": []
    }
  ]
}
```

The script prints a JSON object matching its section type. A `metricsRow`
section uses stable metric IDs and can supply typed values:

```json
{
  "metrics": [
    {
      "id": "latency",
      "label": "Latency",
      "value": "184",
      "unit": "ms",
      "kind": "gauge",
      "numericValue": 184,
      "rangeLower": 0,
      "rangeUpper": 3000
    }
  ]
}
```

Metric kinds are `gauge`, `value`, `status`, `duration`, and `date`.
Complication families are `ring`, `dualRing`, `value`, `status`, `activity`,
`countdown`, `trend`, and `cluster`. A ring uses one metric, a dual ring uses
two, and a cluster uses at most three.

## Trust and execution

Probe commands must be relative file paths without whitespace or parent (`..`)
components. Iles shows every command and a fingerprint before the user
can trust an extension. Trust applies only to that exact fingerprint, so editing
any extension file requires another review. The user can revoke trust at any
time.

The reviewed script file must be executable. It runs directly from its extension
directory—never through a shell—with its manifest timeout and a bounded output
limit. Configuration values are passed only through generated
`ILES_*` environment variables, so secrets do not appear in process
arguments. Secret fields are kept in Keychain; other extension settings remain
in the local settings file.

The fingerprint includes hidden files. Do not put unrelated files, credentials,
or editor state inside an extension directory: every change invalidates trust
and every file becomes part of the security review.

Built-in `healthCheck` probes do not execute a script and therefore do not need
script trust. Health checks make a direct request to the configured URL; use
HTTPS for non-loopback services and do not place credentials in the URL. Usage
Island does not download or update extensions and does not ship a public
marketplace.

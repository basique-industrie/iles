#!/usr/bin/env python3
"""Encrypt only for GitHub's fixed Harnais release environment recipient."""
import base64
import json
import os
from pathlib import Path
from nacl.public import PublicKey, SealedBox

# Obtained with: gh api repos/basique-industrie/harnais/environments/release/secrets/public-key
# Update these public values if GitHub rotates the environment encryption key.
RECIPIENT = {'key_id': '3380204578043523366', 'key': 'tYHM2BnSn3zzvLntqn8OuMlh+EEr/oH8kNjEHUMSYmA='}
NAMES = (
    "APPLE_DEVELOPER_ID_APPLICATION_P12", "APPLE_DEVELOPER_ID_PASSWORD",
    "APPLE_NOTARY_KEY_ID", "APPLE_NOTARY_KEY_ISSUER", "APPLE_NOTARY_KEY_P8",
    "HARNAIS_NATIVE_OAUTH_CATALOG",
)


def encrypt(values, recipient=RECIPIENT):
    missing = [name for name in NAMES if not values.get(name)]
    if missing:
        raise ValueError("Missing environment secrets: " + ", ".join(missing))
    box = SealedBox(PublicKey(base64.b64decode(recipient["key"], validate=True)))
    return {
        "repository": "basique-industrie/harnais", "environment": "release",
        "key_id": recipient["key_id"], "key": recipient["key"],
        "secrets": {name: base64.b64encode(box.encrypt(values[name].encode())).decode() for name in NAMES},
    }


if __name__ == "__main__":
    os.umask(0o077)
    target = Path(os.environ["RUNNER_TEMP"]) / "harnais-encrypted-secrets.json"
    target.write_text(json.dumps(encrypt(os.environ)))
    print("Encrypted six credentials for Harnais's release environment.")

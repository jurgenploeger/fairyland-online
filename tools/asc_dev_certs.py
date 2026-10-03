#!/usr/bin/env python3
"""Removes the Apple Development certificates that CI's cloud signing leaves behind.

Every TestFlight run starts on a fresh Mac, and cloud signing makes a new development
certificate there for the archive. Apple caps how many an account may have, so after a dozen
builds signing fails with "maximum number of certificates". This revokes only certificates the
API key itself made ("Created via API"), never the ones from your own Macs, and lists them all.

    python3 tools/asc_dev_certs.py <AuthKey.p8> <key id> <issuer id> [--dry-run]

Needs PyJWT and cryptography (pip install pyjwt cryptography).
"""

import json
import sys
import time
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"


def token(key_path, key_id, issuer):
    now = int(time.time())
    payload = {"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, open(key_path).read(), algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})


def call(method, url, auth):
    request = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {auth}"})
    with urllib.request.urlopen(request) as response:
        body = response.read()
        return json.loads(body) if body else None


def main(argv):
    dry_run = "--dry-run" in argv
    key_path, key_id, issuer = [a for a in argv if a != "--dry-run"][:3]
    auth = token(key_path, key_id, issuer)
    certs = call("GET", f"{API}/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200", auth)["data"]
    print(f"{len(certs)} development certificate(s):")
    stale = []
    for cert in certs:
        attributes = cert["attributes"]
        label = f"{attributes.get('name')} / {attributes.get('displayName')}"
        made_by_ci = "Created via API" in label
        print(f"  {'revoke' if made_by_ci else 'keep  '}  {label}  (expires {attributes.get('expirationDate', '?')[:10]})")
        if made_by_ci:
            stale.append(cert["id"])
    if dry_run:
        print(f"dry run: would revoke {len(stale)}")
        return
    for cert_id in stale:
        call("DELETE", f"{API}/certificates/{cert_id}", auth)
    print(f"revoked {len(stale)}")


if __name__ == "__main__":
    main(sys.argv[1:])

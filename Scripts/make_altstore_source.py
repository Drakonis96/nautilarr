#!/usr/bin/env python3
"""Generate (or update) an AltStore Source JSON for Nautilarr.

The source lists each released version with its IPA download URL so users can
add the source to AltStore and install/update over the air. AltStore signs the
IPA on-device with the user's free Apple ID.

Usage:
  make_altstore_source.py --version 0.1.0 --ipa dist/Nautilarr-0.1.0.ipa \
      --download-url https://github.com/<owner>/<repo>/releases/download/v0.1.0/Nautilarr-0.1.0.ipa \
      --icon-url https://<owner>.github.io/<repo>/icon.png \
      --date 2026-06-01 --notes "First release" --output docs/apps.json
"""
import argparse
import json
import os
import sys

BUNDLE_ID = "com.drakonis96.nautilarr"
SOURCE_ID = "com.drakonis96.nautilarr.source"
DEVELOPER = "drakonis96"
TINT = "19C3E6"
MIN_OS = "16.0"
DESCRIPTION = (
    "Nautilarr is an open-source client for managing self-hosted media "
    "services through their public REST APIs. Browse libraries, search and add "
    "titles, monitor download queues and server health — all from a native, "
    "adaptive interface for iPhone, iPad and Mac."
)

# Permissions the IPA actually requests. AltStore 2.0+ verifies these against
# the downloaded .ipa and warns the user if the source under-declares them, so
# this MUST mirror the app's Info.plist usage descriptions (and any custom
# entitlements — there are none beyond the defaults AltStore exempts).
# Keep in sync with project.yml `info.properties`.
APP_PERMISSIONS = {
    "entitlements": [],
    "privacy": {
        "NSLocalNetworkUsageDescription":
            "Nautilarr connects to your self-hosted services on your local network.",
        "NSFaceIDUsageDescription":
            "Nautilarr uses Face ID to protect SSH access and settings.",
    },
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--icon-url", default="")
    parser.add_argument("--date", required=True)  # YYYY-MM-DD
    parser.add_argument("--notes", default="")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    size = os.path.getsize(args.ipa) if os.path.exists(args.ipa) else 0

    version_entry = {
        "version": args.version,
        "date": args.date,
        "localizedDescription": args.notes or f"Nautilarr {args.version}",
        "downloadURL": args.download_url,
        "size": size,
        "minOSVersion": MIN_OS,
        "appPermissions": APP_PERMISSIONS,
    }

    # Preserve prior versions if the source already exists.
    versions = [version_entry]
    if os.path.exists(args.output):
        try:
            with open(args.output) as f:
                existing = json.load(f)
            prior = existing["apps"][0].get("versions", [])
            prior = [v for v in prior if v.get("version") != args.version]
            versions = [version_entry] + prior
        except (KeyError, IndexError, json.JSONDecodeError):
            pass

    source = {
        "name": "Nautilarr",
        "identifier": SOURCE_ID,
        "apps": [
            {
                "name": "Nautilarr",
                "bundleIdentifier": BUNDLE_ID,
                "developerName": DEVELOPER,
                "subtitle": "Self-hosted media services client",
                "localizedDescription": DESCRIPTION,
                "iconURL": args.icon_url,
                "tintColor": TINT,
                "category": "utilities",
                "screenshotURLs": [],
                "appPermissions": APP_PERMISSIONS,
                "versions": versions,
                # Legacy top-level fields for older AltStore versions:
                "version": version_entry["version"],
                "versionDate": version_entry["date"],
                "versionDescription": version_entry["localizedDescription"],
                "downloadURL": version_entry["downloadURL"],
                "size": version_entry["size"],
            }
        ],
        "news": [],
    }

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(source, f, indent=2)
    print(f"✓ Wrote AltStore source to {args.output} ({size} bytes IPA)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

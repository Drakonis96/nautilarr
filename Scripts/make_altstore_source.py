#!/usr/bin/env python3
"""Generate (or update) an AltStore Source JSON for Nautilarr.

The source lists each released version with its IPA download URL so users can
add the source to AltStore and install/update over the air. AltStore signs the
IPA on-device with the user's free Apple ID.

The output follows the AltStore source spec documented at
https://faq.altstore.io/developers/make-a-source — it populates the source
About page (name/subtitle/description/icon/website/tint), the app store page
(subtitle, screenshots, permissions, category) and a per-release News feed that
notifies users when a new version ships. Legacy top-level/per-version fields are
kept so older AltStore builds still parse the source.

Usage:
  make_altstore_source.py --version 0.1.0 --ipa dist/Nautilarr-0.1.0.ipa \
      --download-url https://github.com/<owner>/<repo>/releases/download/v0.1.0/Nautilarr-0.1.0.ipa \
      --icon-url https://<owner>.github.io/<repo>/icon.png \
      --website https://github.com/<owner>/<repo> \
      --date 2026-06-01 --notes "First release" --output docs/apps.json

Screenshots are auto-discovered from "<output dir>/screenshots/ios/*.png" and
mapped to their published GitHub Pages URLs, so committing a new screenshot is
enough to list it.
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
CATEGORY = "utilities"

SOURCE_SUBTITLE = "Your whole self-hosted media stack — in one native app."
SOURCE_DESCRIPTION = (
    "The official source for Nautilarr, an open-source client for your "
    "self-hosted media stack. Add it to AltStore to install Nautilarr and "
    "receive over-the-air updates, signed on-device with your free Apple ID."
)

APP_SUBTITLE = "Self-hosted media services client"
DESCRIPTION = (
    "Nautilarr is an open-source client for managing self-hosted media "
    "services through their public REST APIs. Browse libraries, search and add "
    "titles, monitor download queues and server health — all from a native, "
    "adaptive interface for iPhone, iPad and Mac.\n\n"
    "Supported services include Sonarr, Radarr, Lidarr, Overseerr/Jellyseerr, "
    "qBittorrent, Transmission, Deluge, SABnzbd, NZBGet, Prowlarr, Bazarr, "
    "Tautulli, Jellystat, Unraid and SSH/SFTP.\n\n"
    "API keys and passwords live in the system Keychain — no analytics, no "
    "telemetry. Nautilarr only talks to the services you configure."
)

# Image filename extensions treated as screenshots when auto-discovering.
SCREENSHOT_EXTS = (".png", ".jpg", ".jpeg")

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


def pages_base(icon_url: str) -> str:
    """Derive the GitHub Pages base URL from the icon URL (strip the filename)."""
    return icon_url.rsplit("/", 1)[0] if "/" in icon_url else ""


def discover_screenshots(output_path: str, base_url: str) -> list:
    """Map committed iOS screenshots to their published Pages URLs.

    AltStore only shows iOS/iPadOS screenshots, so we list the files under
    `<output dir>/screenshots/ios` in sorted order. macOS shots are ignored.
    """
    if not base_url:
        return []
    shots_dir = os.path.join(os.path.dirname(output_path) or ".", "screenshots", "ios")
    if not os.path.isdir(shots_dir):
        return []
    return [
        f"{base_url}/screenshots/ios/{name}"
        for name in sorted(os.listdir(shots_dir))
        if name.lower().endswith(SCREENSHOT_EXTS)
    ]


def load_existing(output_path: str):
    """Read the previously published source so version/news history survives."""
    if not os.path.exists(output_path):
        return None
    try:
        with open(output_path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--icon-url", default="")
    parser.add_argument("--website", default="")
    parser.add_argument("--date", required=True)  # YYYY-MM-DD (ISO 8601)
    parser.add_argument("--notes", default="")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    size = os.path.getsize(args.ipa) if os.path.exists(args.ipa) else 0
    base_url = pages_base(args.icon_url)
    website = args.website or base_url or args.icon_url
    screenshots = discover_screenshots(args.output, base_url)
    notes = args.notes or f"Nautilarr {args.version}"

    version_entry = {
        "version": args.version,
        "date": args.date,
        "localizedDescription": notes,
        "downloadURL": args.download_url,
        "size": size,
        "minOSVersion": MIN_OS,
        # appPermissions is per-app in modern AltStore but per-version in 1.x;
        # keep it here too so older clients still validate the download.
        "appPermissions": APP_PERMISSIONS,
    }

    news_entry = {
        "title": f"Nautilarr {args.version} is out",
        "identifier": f"{SOURCE_ID}.news.{args.version}",
        "caption": notes,
        "date": args.date,
        "tintColor": TINT,
        "notify": True,        # push an update notification on next refresh
        "appID": BUNDLE_ID,
    }

    # Preserve prior versions and news if the source already exists, de-duping
    # the entry for this version/identifier so a re-run replaces rather than
    # duplicates it.
    versions = [version_entry]
    news = [news_entry]
    existing = load_existing(args.output)
    if existing:
        try:
            prior_versions = existing["apps"][0].get("versions", [])
            versions += [v for v in prior_versions if v.get("version") != args.version]
        except (KeyError, IndexError, TypeError):
            pass
        prior_news = existing.get("news", []) if isinstance(existing, dict) else []
        news += [n for n in prior_news if n.get("identifier") != news_entry["identifier"]]

    source = {
        "name": "Nautilarr",
        "identifier": SOURCE_ID,
        "subtitle": SOURCE_SUBTITLE,
        "description": SOURCE_DESCRIPTION,
        "iconURL": args.icon_url,
        "website": website,
        "tintColor": TINT,
        "featuredApps": [BUNDLE_ID],
        "apps": [
            {
                "name": "Nautilarr",
                "bundleIdentifier": BUNDLE_ID,
                "developerName": DEVELOPER,
                "subtitle": APP_SUBTITLE,
                "localizedDescription": DESCRIPTION,
                "iconURL": args.icon_url,
                "tintColor": TINT,
                "category": CATEGORY,
                "screenshots": screenshots,      # modern AltStore key
                "screenshotURLs": screenshots,   # legacy key for older AltStore
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
        "news": news,
    }

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(source, f, indent=2)
    print(
        f"✓ Wrote AltStore source to {args.output} "
        f"({size} bytes IPA, {len(screenshots)} screenshots, "
        f"{len(versions)} versions, {len(news)} news items)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

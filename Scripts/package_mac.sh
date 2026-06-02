#!/usr/bin/env bash
# Builds the Mac Catalyst .app, signs it ad-hoc (free, no Developer ID), and
# zips it for the GitHub release. Users authorise it via System Settings >
# Privacy & Security (Gatekeeper) — documented in the README.
set -euo pipefail

SCHEME="Nautilarr"
PROJECT="Nautilarr.xcodeproj"
BUILD_DIR="build/mac"
OUT_DIR="dist"

mkdir -p "${OUT_DIR}"

echo "▸ Building for Mac Catalyst…"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "${BUILD_DIR}" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO

APP_PATH="$(ls -d "${BUILD_DIR}/Build/Products/Release-maccatalyst/"*.app | head -n1)"
echo "▸ Ad-hoc signing ${APP_PATH}…"
codesign --force --deep --sign - "${APP_PATH}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Info.plist")"

ZIP="${OUT_DIR}/Nautilarr-macOS-${VERSION}.zip"
echo "▸ Zipping to ${ZIP}…"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP}"

echo "✓ Wrote ${ZIP}"

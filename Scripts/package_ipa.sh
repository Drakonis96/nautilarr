#!/usr/bin/env bash
# Builds an UNSIGNED .ipa for AltStore distribution.
#
# AltStore re-signs the app on-device with the user's free Apple ID, so the IPA
# we ship does not need a paid signing identity. We archive without signing and
# repackage the resulting .app into the standard Payload/ layout.
set -euo pipefail

SCHEME="Nautilarr"
PROJECT="Nautilarr.xcodeproj"
BUILD_DIR="build"
ARCHIVE="${BUILD_DIR}/Nautilarr.xcarchive"
OUT_DIR="dist"

mkdir -p "${OUT_DIR}"

echo "▸ Archiving (unsigned) for iOS device…"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -sdk iphoneos \
  -archivePath "${ARCHIVE}" \
  archive \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES

APP_PATH="$(ls -d "${ARCHIVE}/Products/Applications/"*.app | head -n1)"
echo "▸ Packaging ${APP_PATH} into an .ipa…"

rm -rf "${BUILD_DIR}/Payload"
mkdir -p "${BUILD_DIR}/Payload"
cp -R "${APP_PATH}" "${BUILD_DIR}/Payload/"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Info.plist")"
( cd "${BUILD_DIR}" && zip -qry "../${OUT_DIR}/Nautilarr-${VERSION}.ipa" Payload )

echo "✓ Wrote ${OUT_DIR}/Nautilarr-${VERSION}.ipa"
echo "IPA_VERSION=${VERSION}" >> "${GITHUB_ENV:-/dev/null}"

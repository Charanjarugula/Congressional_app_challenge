#!/bin/bash
# Archives the Release app, signs it with the team's distribution certificate and uploads it to
# TestFlight. Nobody has to be signed in to Xcode: an App Store Connect API key does the signing
# (Xcode cloud signing) and the upload.
#
#   scripts/testflight.sh                      # archive, sign and upload
#   scripts/testflight.sh --archive-only       # stop after the archive, nothing leaves the Mac
#
# Needs, in the environment:
#   ASC_KEY_ID      the key's ID (10 characters)
#   ASC_ISSUER_ID   the issuer ID shown above the keys list in App Store Connect
#   ASC_KEY_PATH    the downloaded AuthKey_<ID>.p8 (default: ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8)
#
# The build number is the UTC timestamp, so every upload is newer than the last; the marketing
# version comes from the project (MARKETING_VERSION).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ASC_KEY_ID:?set ASC_KEY_ID}"; : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
[ -f "$ASC_KEY_PATH" ] || { echo "no key at $ASC_KEY_PATH" >&2; exit 1; }
OUT="${OUT:-build/testflight}"; rm -rf "$OUT"; mkdir -p "$OUT"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "== archive (build $BUILD_NUMBER)"
xcodebuild archive -project ios/Courtly.xcodeproj -scheme Courtly -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Courtly.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${AUTH[@]}" \
  | grep -E '^(\*\*|error:|.*: error:|ARCHIVE)' || true
[ -d "$OUT/Courtly.xcarchive" ] || { echo "archive failed" >&2; exit 1; }
if [ "${1:-}" = "--archive-only" ]; then echo "archive at $OUT/Courtly.xcarchive"; exit 0; fi

echo "== export and upload"
xcodebuild -exportArchive -archivePath "$OUT/Courtly.xcarchive" -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath "$OUT/export" "${AUTH[@]}" | grep -E '^(\*\*|error:|.*: error:|EXPORT|Upload)' || true
echo "uploaded build $BUILD_NUMBER; it shows under TestFlight in App Store Connect once Apple has processed it (a few minutes)."

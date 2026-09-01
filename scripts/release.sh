#!/bin/bash
# Builds, signs, notarizes and staples a distributable TimeTurner DMG.
#
#   ./scripts/release.sh 1.0
#
# Uses the same notary keychain profile as Redline by default; the stored
# credential is account-level, the profile name is just a label.
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="TimeTurner"
NOTARY_PROFILE="${NOTARY_PROFILE:-redline-notary}"
VERSION="${1:-}"
DIST="build/dist"
DMG="$DIST/$NAME-$VERSION.dmg"

if [[ -z "$VERSION" ]]; then
  echo "usage: ./scripts/release.sh <version>    e.g. ./scripts/release.sh 1.0" >&2
  exit 2
fi

# --- Preflight ---------------------------------------------------------------

fail() { echo; echo "FAILED: $1" >&2; echo; shift; printf '%s\n' "$@" >&2; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/') || true

if [[ -z "${IDENTITY:-}" ]]; then
  fail "no Developer ID Application certificate in the keychain" \
    "developer.apple.com/account -> Certificates -> + -> Developer ID Application"
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  fail "no stored notary credentials under profile '$NOTARY_PROFILE'" \
    "Store an app-specific password once:" \
    "  xcrun notarytool store-credentials $NOTARY_PROFILE \\" \
    "    --apple-id <email> --team-id <TEAM> --password <app-specific-password>"
fi

echo "Signing identity: $IDENTITY"
echo "Notary profile:   $NOTARY_PROFILE"
echo

# --- Build -------------------------------------------------------------------

./build.sh

APP="build/$NAME.app"
rm -rf "$DIST" build/dmg
mkdir -p "$DIST" build/dmg

# --- Sign --------------------------------------------------------------------

# The hardened runtime is required for notarization.
echo "==> Signing the app"
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

# --- Package -----------------------------------------------------------------

echo "==> Building the disk image"
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "$NAME" -srcfolder build/dmg -ov -format UDZO "$DMG"

echo "==> Signing the disk image"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# --- Notarize ----------------------------------------------------------------

# --wait blocks until Apple returns a verdict, usually a couple of minutes.
echo "==> Submitting to Apple for notarization"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# --- Verify ------------------------------------------------------------------

# This is the check that matters: it is what Gatekeeper will do on a machine
# that has never seen this app before.
echo "==> Verifying as Gatekeeper would"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo
echo "Done: $DMG"
echo
echo "Attach it to the release:"
echo "  gh release upload v$VERSION \"$DMG\" --clobber"

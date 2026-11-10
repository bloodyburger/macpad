#!/usr/bin/env bash
#
# Build a Release MacPad.app and package it as a disk image.
#
#   ./Tools/package.sh
#
# Produces dist/MacPad-<version>.dmg, where <version> is the app's
# CFBundleShortVersionString from project.yml. The image holds MacPad.app, a
# link to /Applications to drag it onto, and "FIRST RUN - read me.txt", which
# explains the one-time approval macOS demands of an app that is signed but
# not notarised. The mounted image is named "MacPad <version>". This is the
# same layout CI's build-dmg.yml produces.
#
# Requirements: the same as Tools/build.sh (Xcode command line tools, XcodeGen).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

"${ROOT}/Tools/build.sh" release

APP="${ROOT}/build/Build/Products/Release/MacPad.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
DIST="${ROOT}/dist"
DMG="${DIST}/MacPad-${VERSION}.dmg"
README="${ROOT}/Resources/dmg/FIRST RUN - read me.txt"

echo
echo "==> Packaging MacPad ${VERSION}"
echo "    architectures: $(lipo -archs "${APP}/Contents/MacOS/MacPad")"

# Stage in the system temp folder, which no sync service touches. The copy is
# made without extended attributes, stripped again to be sure, and signed
# here: when the checkout sits in a cloud-synced folder the sync service puts
# Finder metadata back on the built app within seconds of build.sh removing
# it, and codesign's strict check (which Gatekeeper also applies) rejects a
# bundle carrying it. The copy is what people install, so the copy is what
# gets signed and verified.
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/MacPad"
STAGED_APP="${STAGE}/MacPad/MacPad.app"
ditto --norsrc --noextattr --noqtn --noacl "${APP}" "${STAGED_APP}"
xattr -cr "${STAGED_APP}"
codesign --force --deep --sign - --timestamp=none "${STAGED_APP}"
codesign --verify --deep --strict --verbose=2 "${STAGED_APP}"
ln -s /Applications "${STAGE}/MacPad/Applications"
cp "${README}" "${STAGE}/MacPad/"

mkdir -p "${DIST}"
rm -f "${DMG}"
hdiutil create \
  -volname "MacPad ${VERSION}" \
  -srcfolder "${STAGE}/MacPad" \
  -ov -format UDZO \
  -quiet \
  "${DMG}"

echo
echo "Packaged: ${DMG}"
ls -lh "${DMG}" | awk '{print "    size: " $5}'
echo
echo "To install: open the image and drag MacPad.app onto Applications. On the"
echo "first launch macOS asks for approval: System Settings > Privacy & Security >"
echo "Open Anyway (macOS 13 and 14: right-click MacPad.app and choose Open)."

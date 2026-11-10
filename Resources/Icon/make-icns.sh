#!/usr/bin/env bash
#
# Regenerates MacPad's app icon and logo files from artwork.png.
#
#   ./Resources/Icon/make-icns.sh
#
# Writes, next to this script:
#   MacPad.png              the 1024x1024 master icon
#   MacPad.icns             the icon file the app bundle ships
#   MacPad-logo-light.png   icon plus wordmark for light pages
#   MacPad-logo-dark.png    the same for dark pages
#
# All of them are committed, so a normal build never needs to run this. Run it
# after replacing artwork.png or changing compose-icon.swift. Needs Xcode's
# command line tools (swift, iconutil).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

swift "${HERE}/compose-icon.swift" "${HERE}/artwork.png" "${WORK}"
cp "${WORK}/MacPad-1024.png" "${HERE}/MacPad.png"
cp "${WORK}/MacPad-logo-light.png" "${WORK}/MacPad-logo-dark.png" "${HERE}/"
iconutil --convert icns --output "${HERE}/MacPad.icns" "${WORK}/MacPad.iconset"

echo "Wrote MacPad.png, MacPad.icns and the two logo files in ${HERE}"

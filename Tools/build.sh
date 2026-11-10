#!/usr/bin/env bash
#
# Build MacPad.app. Run from anywhere.
#
#   ./Tools/build.sh              debug build
#   ./Tools/build.sh release      release build, ready to copy to /Applications
#   ./Tools/build.sh test         run the test suite
#
# Both app builds come out ad-hoc signed, which is what Apple silicon needs
# before it will launch a binary at all. To make a DMG as well, run
# ./Tools/package.sh, which calls this script in release mode.
#
# Everything is built into build.noindex/. The ".noindex" ending makes
# Spotlight skip the folder, and the built app is unregistered from macOS
# afterwards. Without both, a development build named "MacPad" turned up as
# Spotlight's top result and was opened in place of the installed app. A
# local build also reports its build number as "dev" in the About box, so it
# cannot be mistaken for a release.
#
# Requirements (macOS only):
#   Xcode command line tools   xcode-select --install
#   XcodeGen                   brew install xcodegen

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

MODE="${1:-debug}"
BUILD_DIR="${ROOT}/build.noindex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Take a development build back out of macOS's list of installed apps.
unregister() {
  if [[ -x "${LSREGISTER}" && -d "$1" ]]; then
    "${LSREGISTER}" -u "$1" >/dev/null 2>&1 || true
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "MacPad builds a macOS app bundle and needs Xcode; this is $(uname -s)." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install it with:" >&2
  echo "    brew install xcodegen" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install the Xcode command line tools with:" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi

echo "==> Fetching dependencies"
"${ROOT}/Tools/fetch-deps.sh"

echo
echo "==> Generating MacPad.xcodeproj"
xcodegen generate --quiet

echo
case "${MODE}" in
  release)
    CONFIG=Release
    ;;
  debug)
    CONFIG=Debug
    ;;
  test)
    echo "==> Testing"
    xcodebuild test \
      -project MacPad.xcodeproj \
      -scheme MacPadTests \
      -destination 'platform=macOS' \
      -derivedDataPath "${BUILD_DIR}" \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
      | tail -40
    STATUS="${PIPESTATUS[0]}"
    unregister "${BUILD_DIR}/Build/Products/Debug/MacPad.app"
    exit "${STATUS}"
    ;;
  *)
    echo "Unknown mode “${MODE}”. Use debug, release or test." >&2
    exit 1
    ;;
esac

APP="${BUILD_DIR}/Build/Products/${CONFIG}/MacPad.app"
LOG="${BUILD_DIR}/xcodebuild-${CONFIG}.log"
mkdir -p "${BUILD_DIR}"

# Xcode's own signing step is turned off (CODE_SIGNING_ALLOWED=NO) and the app
# is signed below instead. Signing inside xcodebuild fails whenever the checkout
# sits in a cloud-synced folder (iCloud Drive, Dropbox, OneDrive): the file
# provider stamps Finder metadata on the build output and codesign refuses it
# with "resource fork, Finder information, or similar detritus not allowed".
# Signing afterwards lets us strip that metadata first.
#
# The generic destination builds every architecture in ARCHS (arm64 and
# x86_64). Naming this Mac as the destination would build only its own.
echo "==> Building MacPad (${CONFIG})"
echo "    full compiler output: ${LOG}"
set +e
xcodebuild build \
  -project MacPad.xcodeproj \
  -scheme MacPad \
  -configuration "${CONFIG}" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "${LOG}" | grep -E '(error|warning): |\*\* BUILD'
# The filter keeps compiler diagnostics ("file.swift:3:1: error: ...") and the
# final verdict, and drops the command lines. PIPESTATUS[0] is xcodebuild's own
# exit status; grep exits 1 when nothing matched, which is not a failure.
STATUS="${PIPESTATUS[0]}"
set -e

if [[ "${STATUS}" != "0" ]]; then
  echo >&2
  echo "xcodebuild failed with status ${STATUS}. Last lines of ${LOG}:" >&2
  tail -40 "${LOG}" >&2
  exit "${STATUS}"
fi

if [[ ! -d "${APP}" ]]; then
  echo >&2
  echo "xcodebuild reported success but ${APP} does not exist. See ${LOG}." >&2
  exit 1
fi

echo
echo "==> Signing MacPad.app (ad-hoc)"
# Strip Finder metadata and resource forks, then sign every binary in the
# bundle with the ad-hoc identity ("-"). This is not notarisation: macOS still
# asks for approval on the first launch of a downloaded copy.
xattr -cr "${APP}"
codesign --force --deep --sign - --timestamp=none "${APP}"
codesign --verify --verbose=2 "${APP}"

# xcodebuild registers what it builds as an installed app. Undo that, so
# macOS keeps opening the copy in /Applications.
unregister "${APP}"

echo
echo "Built: ${APP}"
echo "Run it with:"
echo "    open \"${APP}\""

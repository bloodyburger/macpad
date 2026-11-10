#!/usr/bin/env bash
#
# Build and run the regex conformance harness.
#
# Links only Scintilla's platform-independent core, so this works on Linux and
# macOS alike and needs no Xcode. Run it in CI to guard the regex dialect.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

if [ ! -d Vendor/scintilla ] || [ ! -d Vendor/boost-regex ]; then
  echo "Dependencies missing; running Tools/fetch-deps.sh"
  ./Tools/fetch-deps.sh
fi

CXX="${CXX:-clang++}"
OUT="$(mktemp -d)"
trap 'rm -rf "${OUT}"' EXIT

# Only the files Document actually needs. Linking all of src/ would drag in
# Editor, ViewStyle and ScintillaBase, which reference the platform layer
# (Window, Surface, Font, Menu) that exists only in the Cocoa/GTK/Win32
# backends -- and none of which the regex engine touches.
CORE_SOURCES=(
  Document CellBuffer CharClassify CharacterCategoryMap CharacterType
  CaseFolder CaseConvert Decoration PerLine RunStyles RESearch
  UniConversion UndoHistory ChangeHistory DBCS UniqueString
)
CORE_PATHS=()
for name in "${CORE_SOURCES[@]}"; do
  CORE_PATHS+=("Vendor/scintilla/src/${name}.cxx")
done

echo "==> Compiling Scintilla core + MacPad regex engine"
# SCI_OWNREGEX suppresses Scintilla's built-in factory so ours is linked.
"${CXX}" -std=c++17 -O1 -DSCI_OWNREGEX \
  -I Vendor/scintilla/include \
  -I Vendor/scintilla/src \
  -I Vendor/boost-regex/include \
  -o "${OUT}/regex_conformance" \
  Tests/Integration/regex_conformance.cxx \
  Sources/SearchEngine/MPRegexSearch.cxx \
  "${CORE_PATHS[@]}"

echo "==> Running"
echo
"${OUT}/regex_conformance"

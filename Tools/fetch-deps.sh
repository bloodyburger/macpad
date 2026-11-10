#!/usr/bin/env bash
#
# Fetch and verify MacPad's vendored C++ dependencies into Vendor/.
# Idempotent: re-running with everything present does nothing.
#
# Scintilla has no official git repository (upstream is Mercurial on
# SourceForge), so it is pinned as a release tarball verified by SHA-256.
# Lexilla has an official git mirror and is pinned to a release tag by
# commit SHA.

set -euo pipefail

SCINTILLA_VERSION="5.6.9"
SCINTILLA_ARCHIVE="scintilla569.tgz"
SCINTILLA_URL="https://www.scintilla.org/${SCINTILLA_ARCHIVE}"
SCINTILLA_SHA256="1622546ce1d3804b589292f1adae98ad1d87fa8c43bb401edc098adae12dcacb"

LEXILLA_VERSION="5.5.5"
LEXILLA_TAG="rel-5-5-5"
LEXILLA_COMMIT="e67537693bfb1ae4e6f643dcab725a38ffeac3e3"
LEXILLA_URL="https://github.com/ScintillaOrg/lexilla.git"

# Boost.Regex is the engine behind Find/Replace: a full Perl-syntax dialect
# with case-converting replacements. Pinned to one version so the dialect
# cannot shift under the conformance suite.
#
# Only the include tree is needed: since Boost 1.75 Boost.Regex builds
# header-only in BOOST_REGEX_STANDALONE mode, which activates automatically
# when <boost/version.hpp> is absent. That means no library to build and no
# other Boost libraries to vendor -- verified by compiling against the include
# directory alone.
BOOST_REGEX_VERSION="1.90.0"
BOOST_REGEX_TAG="boost-1.90.0"
BOOST_REGEX_COMMIT="f439e22ae41fa647bd7de16c2d92deb232593985"
BOOST_REGEX_URL="https://github.com/boostorg/regex.git"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT}/Vendor"
mkdir -p "${VENDOR}"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

# ---------------------------------------------------------------- Scintilla
if [ -f "${VENDOR}/scintilla/version.txt" ]; then
  echo "==> Scintilla ${SCINTILLA_VERSION} already present"
else
  echo "==> Fetching Scintilla ${SCINTILLA_VERSION}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  curl -fsSL -o "${tmp}/${SCINTILLA_ARCHIVE}" "${SCINTILLA_URL}"

  actual="$(sha256_of "${tmp}/${SCINTILLA_ARCHIVE}")"
  if [ "${actual}" != "${SCINTILLA_SHA256}" ]; then
    echo "ERROR: Scintilla checksum mismatch." >&2
    echo "  expected ${SCINTILLA_SHA256}" >&2
    echo "  actual   ${actual}" >&2
    exit 1
  fi
  echo "    checksum verified"

  # The tarball unpacks to a top-level scintilla/ directory.
  rm -rf "${VENDOR}/scintilla"
  tar xzf "${tmp}/${SCINTILLA_ARCHIVE}" -C "${VENDOR}"
  [ -f "${VENDOR}/scintilla/version.txt" ] || { echo "ERROR: unexpected archive layout" >&2; exit 1; }
  rm -rf "${tmp}"; trap - EXIT
  echo "    -> Vendor/scintilla"
fi

# ------------------------------------------------------------------ Lexilla
if [ -d "${VENDOR}/lexilla/.git" ] \
   && [ "$(git -C "${VENDOR}/lexilla" rev-parse HEAD 2>/dev/null)" = "${LEXILLA_COMMIT}" ]; then
  echo "==> Lexilla ${LEXILLA_VERSION} already present"
else
  echo "==> Fetching Lexilla ${LEXILLA_VERSION} (${LEXILLA_TAG})"
  rm -rf "${VENDOR}/lexilla"
  git -c advice.detachedHead=false clone --quiet --depth 1 \
      --branch "${LEXILLA_TAG}" "${LEXILLA_URL}" "${VENDOR}/lexilla"

  actual="$(git -C "${VENDOR}/lexilla" rev-parse HEAD)"
  if [ "${actual}" != "${LEXILLA_COMMIT}" ]; then
    echo "ERROR: Lexilla commit mismatch." >&2
    echo "  expected ${LEXILLA_COMMIT}" >&2
    echo "  actual   ${actual}" >&2
    exit 1
  fi
  echo "    commit verified"
  echo "    -> Vendor/lexilla"
fi

# -------------------------------------------------------------- Boost.Regex
if [ -d "${VENDOR}/boost-regex/.git" ] \
   && [ "$(git -C "${VENDOR}/boost-regex" rev-parse HEAD 2>/dev/null)" = "${BOOST_REGEX_COMMIT}" ]; then
  echo "==> Boost.Regex ${BOOST_REGEX_VERSION} already present"
else
  echo "==> Fetching Boost.Regex ${BOOST_REGEX_VERSION} (${BOOST_REGEX_TAG})"
  rm -rf "${VENDOR}/boost-regex"
  git -c advice.detachedHead=false clone --quiet --depth 1 \
      --branch "${BOOST_REGEX_TAG}" "${BOOST_REGEX_URL}" "${VENDOR}/boost-regex"

  actual="$(git -C "${VENDOR}/boost-regex" rev-parse HEAD)"
  if [ "${actual}" != "${BOOST_REGEX_COMMIT}" ]; then
    echo "ERROR: Boost.Regex commit mismatch." >&2
    echo "  expected ${BOOST_REGEX_COMMIT}" >&2
    echo "  actual   ${actual}" >&2
    exit 1
  fi
  echo "    commit verified"

  # Guard the header-only assumption: if a future bump reintroduces a compiled
  # core, the build would fail at link time with a confusing error. Fail here
  # with a clear one instead. (src/ holds only the POSIX C API wrappers, which
  # MacPad does not use.)
  unexpected="$(find "${VENDOR}/boost-regex/src" -name '*.cpp' 2>/dev/null \
                 | grep -v -E 'posix_api\.cpp|wide_posix_api\.cpp' || true)"
  if [ -n "${unexpected}" ]; then
    echo "ERROR: Boost.Regex has compiled sources beyond the POSIX wrappers:" >&2
    echo "${unexpected}" >&2
    echo "  MacPad builds it header-only; see Sources/SearchEngine/." >&2
    exit 1
  fi
  echo "    -> Vendor/boost-regex (header-only)"
fi

echo
echo "Dependencies ready:"
echo "  Scintilla $(cat "${VENDOR}/scintilla/version.txt")  ($(ls "${VENDOR}"/scintilla/src/*.cxx | wc -l | tr -d ' ') core sources)"
echo "  Lexilla   ${LEXILLA_VERSION}  ($(ls "${VENDOR}"/lexilla/lexers/*.cxx | wc -l | tr -d ' ') lexers)"
echo "  Boost.Regex ${BOOST_REGEX_VERSION}  (header-only, standalone)"

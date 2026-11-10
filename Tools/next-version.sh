#!/usr/bin/env bash
#
# Prints the version number the next release should carry.
#
#   ./Tools/next-version.sh
#
# The rule, which is the whole of MacPad's versioning:
#
#   base   = CFBundleShortVersionString in project.yml        (e.g. 0.1.0)
#   latest = the highest released version, from the v* tags   (e.g. 0.1.4)
#
#   base is higher than latest  ->  release base              (0.2.0 after you raise it)
#   otherwise                   ->  latest with its last number raised by one (0.1.5)
#   no release yet              ->  release base
#
# So ordinary releases number themselves, and a bigger step (0.1.x to 0.2.0,
# or to 1.0.0) is made by editing the one version line in project.yml.
#
# CI calls this to decide the version before it builds; see the plan job in
# .github/workflows/build-dmg.yml. For testing the rule without a repository:
#
#   ./Tools/next-version.sh --base 0.2.0 --latest 0.1.7     prints 0.2.0
#   ./Tools/next-version.sh --base 0.1.0 --latest 0.1.7     prints 0.1.8
#   ./Tools/next-version.sh --base 0.1.0 --latest ""        prints 0.1.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE=""
LATEST=""
LATEST_GIVEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base)   BASE="$2"; shift 2 ;;
    --latest) LATEST="$2"; LATEST_GIVEN=1; shift 2 ;;
    *) echo "usage: next-version.sh [--base X.Y.Z] [--latest X.Y.Z]" >&2; exit 64 ;;
  esac
done

if [ -z "${BASE}" ]; then
  BASE="$(sed -n -E 's/^[[:space:]]*CFBundleShortVersionString:[[:space:]]*"([^"]+)".*/\1/p' \
            "${ROOT}/project.yml" | head -1)"
fi
if ! printf '%s' "${BASE}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "next-version.sh: the version in project.yml must look like 1.2.3, found \"${BASE}\"" >&2
  exit 1
fi

if [ "${LATEST_GIVEN}" = "0" ]; then
  LATEST="$(git -C "${ROOT}" tag -l 'v[0-9]*' | sed 's/^v//' \
              | grep -E '^[0-9]+(\.[0-9]+){0,2}$' | sort -V | tail -1 || true)"
fi

if [ -z "${LATEST}" ]; then
  echo "${BASE}"
  exit 0
fi

HIGHEST="$(printf '%s\n%s\n' "${BASE}" "${LATEST}" | sort -V | tail -1)"
if [ "${HIGHEST}" = "${BASE}" ] && [ "${BASE}" != "${LATEST}" ]; then
  echo "${BASE}"
else
  IFS=. read -r MAJOR MINOR PATCH <<< "${LATEST}"
  echo "${MAJOR}.${MINOR:-0}.$(( ${PATCH:-0} + 1 ))"
fi

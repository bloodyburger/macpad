#!/usr/bin/env bash
# Print current or obsolete. Remote/ref errors are failures, never permission
# to publish. Called again after uploading the draft to catch superseded runs.
set -euo pipefail

EXPECTED_SHA="${1:?expected commit SHA is required}"
DEFAULT_BRANCH="${2:?default branch is required}"
if [[ ! "${EXPECTED_SHA}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "release-guard: expected a full commit SHA" >&2
  exit 1
fi
git check-ref-format "refs/heads/${DEFAULT_BRANCH}" >/dev/null
REMOTE_REF="$(git ls-remote --exit-code origin "refs/heads/${DEFAULT_BRANCH}")"
read -r REMOTE_SHA REMOTE_NAME <<< "${REMOTE_REF}"
if [[ ! "${REMOTE_SHA}" =~ ^[0-9a-f]{40}$ ]] || [ "${REMOTE_NAME}" != "refs/heads/${DEFAULT_BRANCH}" ]; then
  echo "release-guard: could not verify the current default-branch head" >&2
  exit 1
fi
if [ "${EXPECTED_SHA}" = "${REMOTE_SHA}" ]; then
  echo current
else
  echo obsolete
fi

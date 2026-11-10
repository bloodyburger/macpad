#!/usr/bin/env bash
# Publish the exact checked build. Drafts remain unpublished if the branch
# advances, asset verification fails, or GitHub cannot be reached.
set -euo pipefail

: "${GITHUB_SHA:?}"
: "${GITHUB_REPOSITORY:?}"
: "${DEFAULT_BRANCH:?}"
: "${VERSION:?}"
: "${ARTIFACT_NAME:?}"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release version: ${VERSION}" >&2
  exit 1
fi

HEAD_STATUS="$(./Tools/release-guard.sh "${GITHUB_SHA}" "${DEFAULT_BRANCH}")"
if [ "${HEAD_STATUS}" = obsolete ]; then
  echo "Not published: this build has been superseded on ${DEFAULT_BRANCH}."
  exit 0
fi

TAG="v${VERSION}"
git fetch --tags --force origin
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "${TAG} already exists; refusing to replace a release." >&2
  exit 1
fi

# A workflow rerun can retain artifacts from its earlier attempt. Accept only
# the artifact named by this attempt's build, carrying its version and commit.
case "${ARTIFACT_NAME}" in
  "MacPad-${VERSION}-"*) ;;
  *) echo "Artifact does not match the planned version: ${ARTIFACT_NAME}" >&2; exit 1 ;;
esac
SHORT_SHA="${ARTIFACT_NAME#MacPad-${VERSION}-}"
if [[ ! "${SHORT_SHA}" =~ ^[0-9a-f]{7,40}$ ]] || [[ "${GITHUB_SHA}" != "${SHORT_SHA}"* ]]; then
  echo "Artifact does not match the planned version and commit: ${ARTIFACT_NAME}" >&2
  exit 1
fi
SRC="dist/${ARTIFACT_NAME}.dmg"
shopt -s nullglob
DMGS=(dist/*.dmg)
if [ "${#DMGS[@]}" -ne 1 ] || [ "${DMGS[0]}" != "${SRC}" ]; then
  echo "Expected exactly the checked build artifact: ${SRC}" >&2
  exit 1
fi

DMG="dist/MacPad-${VERSION}.dmg"
mv "${SRC}" "${DMG}"
(cd dist && shasum -a 256 "MacPad-${VERSION}.dmg" > "MacPad-${VERSION}.dmg.sha256")
cp "${DMG}" dist/MacPad.dmg
(cd dist && shasum -a 256 MacPad.dmg > MacPad.dmg.sha256)
cmp "${DMG}" dist/MacPad.dmg
(cd dist && shasum -a 256 -c "MacPad-${VERSION}.dmg.sha256" MacPad.dmg.sha256)

if [ -f "docs/releases/${TAG}.md" ]; then
  cp "docs/releases/${TAG}.md" notes.md
else
  PREVIOUS="$(git tag -l 'v[0-9]*' | sort -V | tail -1)"
  {
    echo "What changed in MacPad ${VERSION}:"
    echo
    git log -40 --no-merges --format='- %s' ${PREVIOUS:+"${PREVIOUS}..HEAD"}
  } > notes.md
fi

# Only unpublished drafts may be replaced after a cancelled earlier attempt.
if gh release list --limit 30 --json tagName,isDraft \
     --jq ".[] | select(.isDraft and .tagName == \"${TAG}\") | .tagName" | grep -q .; then
  gh release delete "${TAG}" --yes
fi
gh release create "${TAG}" "${DMG}" "${DMG}.sha256" \
  dist/MacPad.dmg dist/MacPad.dmg.sha256 \
  --target "${GITHUB_SHA}" --title "MacPad ${VERSION}" --draft --notes-file notes.md

# Verify GitHub received the four exact assets before making /latest public.
RELEASE_JSON="$(mktemp)"
trap 'rm -f "${RELEASE_JSON}"' EXIT
RELEASE_ID="$(gh release view "${TAG}" --json databaseId --jq .databaseId)"
if [[ ! "${RELEASE_ID}" =~ ^[0-9]+$ ]]; then
  echo "Could not identify the uploaded draft release" >&2
  exit 1
fi
gh api "repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}" > "${RELEASE_JSON}"
python3 - "${RELEASE_JSON}" "${VERSION}" <<'PY'
import hashlib, json, pathlib, sys
release = json.loads(pathlib.Path(sys.argv[1]).read_text())
version = sys.argv[2]
if release.get('draft') is not True or release.get('tag_name') != f'v{version}':
    raise SystemExit('Expected the unpublished draft for this version')
assets = release.get('assets', [])
names = [f'MacPad-{version}.dmg', f'MacPad-{version}.dmg.sha256', 'MacPad.dmg', 'MacPad.dmg.sha256']
for name in names:
    matches = [a for a in assets if a.get('name') == name]
    data = (pathlib.Path('dist') / name).read_bytes()
    if len(matches) != 1 or matches[0].get('state') != 'uploaded' or matches[0].get('size') != len(data):
        raise SystemExit(f'Missing or incomplete uploaded asset: {name}')
    if matches[0].get('digest') != 'sha256:' + hashlib.sha256(data).hexdigest():
        raise SystemExit(f'Uploaded asset checksum mismatch: {name}')
PY

HEAD_STATUS="$(./Tools/release-guard.sh "${GITHUB_SHA}" "${DEFAULT_BRANCH}")"
if [ "${HEAD_STATUS}" = obsolete ]; then
  echo "Not published: ${DEFAULT_BRANCH} advanced while uploading. Left ${TAG} as a draft."
  exit 0
fi
gh release edit "${TAG}" --draft=false --latest
for ATTEMPT in 1 2 3; do
  LATEST_TAG="$(gh api "repos/${GITHUB_REPOSITORY}/releases/latest" --jq .tag_name)"
  if [ "${LATEST_TAG}" = "${TAG}" ]; then break; fi
  if [ "${ATTEMPT}" -lt 3 ]; then sleep 2; fi
done
if [ "${LATEST_TAG}" != "${TAG}" ]; then
  echo "Published ${TAG}, but GitHub's latest release is ${LATEST_TAG}; verification failed." >&2
  exit 1
fi
echo "Published https://github.com/${GITHUB_REPOSITORY}/releases/tag/${TAG}"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "Published [MacPad ${VERSION}](https://github.com/${GITHUB_REPOSITORY}/releases/tag/${TAG})" >> "${GITHUB_STEP_SUMMARY}"
fi

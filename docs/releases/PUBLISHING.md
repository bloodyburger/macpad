# Publishing MacPad releases

Releases publish themselves. Push to the default branch; if the build passes
its checks, a new release appears on GitHub a few minutes later with the next
version number. Nothing is tagged, bumped or uploaded by hand.

## What happens on a push

1. **Plan.** The workflow works out the version this build will carry and
   whether it will be published (rules below).
2. **Build.** The app is built with that version written into it, packaged as
   a disk image, launched to prove it starts and draws, and the tests run.
3. **Publish.** If everything passed, the disk image is attached to a draft
   GitHub release, and the draft is then made public. Making it public creates
   the `v<version>` tag on that commit.

A build that fails any check publishes nothing, and the previous release stays
the latest.

Only the current default-branch commit may publish. The workflow checks the
remote branch head while planning and again immediately before publication.
Re-running an older failed or cancelled build skips publication; it cannot
relabel older code as the newest release. If the remote cannot be verified, the
check fails closed.

## How the version is chosen

`Tools/next-version.sh` decides, from two numbers:

- **base**: the version line in `project.yml` (`CFBundleShortVersionString`)
- **latest**: the highest version already released

| Situation | Next release |
|---|---|
| base is not higher than latest (the normal case) | latest with its last number raised by one: 0.1.4 becomes 0.1.5 |
| base has been raised past latest | base itself: set it to 0.2.0 and the next release is 0.2.0, then 0.2.1 |
| nothing released yet | base |

So to start a new series (0.2.0, 1.0.0), change that one line in `project.yml`
and push. Otherwise leave it alone.

The app always carries the version it is released as: the workflow writes the
number into the build, and refuses to publish if the built app reports a
different one. A mismatch would make every installed copy offer itself an
update forever.

## When a push does not publish

- **Another branch.** Only the default branch publishes. Other branches build
  and test, and keep their disk image as a build artifact for 30 days.
- **`[skip release]` in the commit message.** The build and tests run; nothing
  is published. Use it for work in progress that should not reach users.
- **Only docs changed.** Pushes that touch nothing but `docs/`, `README.md`
  or `LICENSE` do not run the workflow at all.
- **The commit is already released.** Re-running the workflow on a released
  commit does not publish it twice.

To publish the current state without a new commit, run the workflow by hand
from the Actions tab (Build DMG, Run workflow) on the default branch.

## Release notes

If `docs/releases/v<version>.md` exists, it is the release text. Otherwise the
notes are the subject lines of the commits since the previous release, so
commit subjects are worth writing for readers. The first 600 characters also
appear in the app's "update available" alert.

## What a release contains

- `MacPad-<version>.dmg` and `MacPad-<version>.dmg.sha256`: the versioned download.
- `MacPad.dmg` and `MacPad.dmg.sha256`: exact copies under a name that never
  changes, so a website can link to the newest build without being updated.

The release job downloads the exact artifact named by its build job, not every
artifact retained by a workflow rerun. It checks the expected version and commit
in the artifact name, verifies the two disk images are identical and their
checksums pass, then uploads all four assets to a draft. Before publishing,
`Tools/publish-release.sh` checks GitHub's uploaded asset names, sizes and SHA-256
digests against the local files. Only then does it explicitly mark the release
as latest and confirm that GitHub's latest-release endpoint points to its tag.

Stable links:

- `https://github.com/bloodyburger/macpad/releases/latest/download/MacPad.dmg`
- `https://github.com/bloodyburger/macpad/releases/latest/download/MacPad.dmg.sha256`

Check a download from its folder with `shasum -a 256 -c MacPad.dmg.sha256`.
GitHub's "latest" is the newest published release; drafts never are. No
website rebuild is needed when a release is published.

## How installed copies find out

MacPad's Check for Updates reads this repository's latest release, compares
its tag with the app's own version, and offers the `.dmg` asset. It runs once
a day after launch and on demand from the MacPad menu.

## If publishing fails part-way

A failed or cancelled run can leave a draft release behind. The next run
removes a leftover draft for the same version before creating its own. Do not
replace the files of a release that is already public; push a fix and let the
next version go out.

A draft is also left unpublished if the default branch advances during its
upload. This is expected: the newer branch build is responsible for the next
release. A failed latest-pointer verification is reported as a failure even if
the release was published; inspect GitHub's designated latest release before
retrying or making any manual change.

Run the release regression checks without building the app:

```sh
python3 -m unittest discover -s Tests/Release -v
```

These use temporary local Git remotes and a mock GitHub CLI. They check current
and obsolete commits, remote failures, stale artifacts, failed uploads, missing
assets, digest mismatches and publication ordering.

## Building locally

`./Tools/package.sh` builds a disk image on your Mac and publishes nothing. A
local build carries the base version from `project.yml`, so it may offer the
newest release as an update.

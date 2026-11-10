<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Resources/Icon/MacPad-logo-dark.png">
    <img alt="MacPad" src="Resources/Icon/MacPad-logo-light.png" width="420">
  </picture>
</p>

# MacPad

A native text and code editor for macOS: fast with large files, many tabs in
one window, syntax highlighting for 31 languages, and find and replace with
full Perl-syntax regular expressions.

**Status: early and usable.** Tabs, highlighting, search, encodings, line
endings, drag and drop, session restore with autosave, and update checks work
and are covered by 71 unit tests plus a 38-check regex conformance suite.
Preferences, Find in Files, split view, macros and plugins are still to come;
[`docs/FEATURES.md`](docs/FEATURES.md) lists every feature and its state.

## Download

The latest build is on the [Releases page](https://github.com/bloodyburger/macpad/releases/latest)
as a universal disk image for macOS 13 and later. Open it, drag MacPad to
Applications, then right-click MacPad and choose Open the first time; the build
is signed but not notarised, so macOS asks once. The app offers newer versions
itself through **MacPad → Check for Updates…**.

## What it does

- **Tabs** in a compact tab bar: drag to reorder, close buttons, a marker on
  unsaved tabs, double-click the empty bar for a new one.
- **Syntax highlighting** for 31 languages, with code folding, line numbers,
  bookmarks and indent guides.
- **Find and replace** in three modes: plain text, extended escapes (`\n`,
  `\t`, `\xHH`) and regular expressions. Matches highlight as you type.
  Replacements support groups and case conversion (`\1`, `$1`, `\U`, `\L`).
- **Files** open from the Finder, the File menu or by dragging them onto the
  window. Encodings (UTF-8, UTF-16, 8-bit code pages) and line endings are
  detected on open and can be changed.
- **Sessions**: your tabs come back on the next launch, and unsaved text is
  backed up every 7 seconds, so quitting never loses work.
- **Light and dark themes** that follow macOS.
- **Updates**: the app checks for a newer version once a day and on demand.

## How it is built

MacPad is a Swift and AppKit application around three mature C++ libraries,
joined by a small Objective-C++ bridge:

- **Scintilla 5.6.9** — the text editing engine, using its Cocoa back end
- **Lexilla 5.5.5** — the syntax lexers
- **Boost.Regex 1.90** — the regular-expression engine, installed through
  Scintilla's `SCI_OWNREGEX` hook

[`docs/PLAN.md`](docs/PLAN.md) explains the choices.

## Building

macOS 13 or later, with Xcode command line tools.

```bash
brew install xcodegen
```

```bash
./Tools/build.sh
```

That fetches and verifies the vendored dependencies, generates the Xcode
project from `project.yml`, builds `MacPad.app` and signs it with the ad-hoc
identity, which Apple silicon needs before it will launch any binary. The
script prints where the app is and how to open it. A failed compile stops the
script and points at the full compiler log under `build/`.

To build a Release app and a disk image you can hand to someone:

```bash
./Tools/package.sh
```

That writes `dist/MacPad-<version>.dmg`. Opening the image shows `MacPad.app`,
a link to `/Applications` to drag it onto, and a short read-me. The app is
signed but not notarised with Apple, so macOS blocks the first launch of a
copy that came from a download. Right-click `MacPad.app` in `/Applications`,
choose **Open**, and confirm. Only the first launch needs this. If that is
refused too, clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/MacPad.app
```

Both builds work from a checkout inside a cloud-synced folder such as iCloud
Drive or Dropbox. Xcode's own signing step cannot (the sync service marks the
build output with Finder metadata that `codesign` rejects), so the scripts
turn it off, strip that metadata and sign afterwards.

The app icon is composed by a script and committed as `Resources/Icon/MacPad.icns`;
see [`Resources/Icon/README.md`](Resources/Icon/README.md) to change it.

To run the tests:

```bash
./Tools/build.sh test
```

The regex conformance harness needs no Mac — it links only Scintilla's
platform-independent core, so it runs anywhere with a C++17 compiler:

```bash
./Tests/Integration/run.sh
```

## Releases

Releases publish themselves. Every push to the main branch that builds and
passes its checks becomes a GitHub release with the next version number, the
disk image attached, and a `v` tag. Nothing is tagged or bumped by hand.
[`docs/releases/PUBLISHING.md`](docs/releases/PUBLISHING.md) has the rules:
how the version is chosen, how to skip a release, and the stable download
links a website can point at.

## Updates

MacPad checks for a newer version once a day, a few seconds after launch, and
offers to download it; **MacPad → Check for Updates…** does the same on demand.
It reads one small JSON file, named by `MacPadUpdateFeedURL` in `project.yml`.
Two ways to serve it:

- **GitHub Releases** (the default): the latest release of this repository,
  which the release automation keeps current. The repository must be public.
- **Your own site**: host a file like this and point `MacPadUpdateFeedURL` at it.

  ```json
  {
    "version": "0.2.0",
    "url": "https://example.com/macpad",
    "download": "https://example.com/downloads/MacPad-0.2.0.dmg",
    "notes": "What changed in this release."
  }
  ```

Turn the launch check off with `defaults write com.macpad.MacPad
AutomaticUpdateChecks -bool NO`, or with `MACPAD_NO_UPDATE_CHECK=1` in the
environment.

## Documents

- [`docs/PLAN.md`](docs/PLAN.md) — architecture, platform decisions, milestones, risks
- [`docs/FEATURES.md`](docs/FEATURES.md) — every feature, done or planned, by menu
- [`docs/releases/PUBLISHING.md`](docs/releases/PUBLISHING.md) — how releases are published

## Licence

MacPad is free software under the **GNU General Public License v3 or later**.
See [`LICENSE`](LICENSE).

MacPad builds on these libraries, under their own licences:

- Scintilla, Lexilla — © Neil Hodgson — https://www.scintilla.org/
- Boost.Regex — © John Maddock — https://www.boost.org/

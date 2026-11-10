# MacPad — architecture and roadmap

**MacPad is a native text and code editor for macOS:** fast with large files,
many tabs in one window, syntax highlighting, and a find-and-replace with real
regular expressions. This document records how it is built, what is decided,
and what comes next. What works today is listed feature by feature in
[`FEATURES.md`](FEATURES.md).

---

## 1. Foundations

MacPad does not write its own text engine. It builds a native Swift and AppKit
application around three mature, permissively licensed C++ libraries.

| Component | Version | Licence | What it does here |
|---|---|---|---|
| Scintilla | 5.6.9 | Permissive (HPND-style, Neil Hodgson) | The editing engine: documents, undo, selections, folding, margins, drawing. Its maintained Cocoa back end is used |
| Lexilla | 5.5.5 | Same as Scintilla | Syntax lexers, 125 of them |
| Boost.Regex | 1.90 | Boost Software License | The regular-expression engine behind Find and Replace. Header-only in `BOOST_REGEX_STANDALONE` mode, so there is no library to build |

Scintilla's author ships a macOS editor built on the same Cocoa back end, so
the foundation is proven in production. It is less exercised than the Windows
and GTK back ends; time is budgeted for input-method, accessibility and
scrolling defects.

### Alternatives considered

| Approach | Verdict |
|---|---|
| **Scintilla (Cocoa) + Lexilla + Swift/AppKit** | **Chosen.** A proven engine with native feel and performance and no runtime. The cost: AppKit gives no tab bar or docking system, so those are built by hand |
| Electron or Tauri with a web editor | Quick to a demo, then a wall on large files, column mode and native behaviour. Not a Mac app. Rejected |
| Qt with its Scintilla binding | Docking and tabs come free, but it looks and behaves like a ported app: wrong menus, scrolling, text input and accessibility. Rejected; the fallback if the AppKit panels overrun |
| SwiftUI with TextKit 2 | Years of work to approach what Scintilla already does. Rejected |

**Language split:** Swift for the application, user interface and settings;
Objective-C++ for the bridge to Scintilla; C++ for the regex adapter. The Xcode
project is generated from `project.yml` by XcodeGen.

---

## 2. Platform decisions

- **Keyboard.** Command is the modifier throughout, and the menus follow
  Apple's conventions: an app menu with Settings, Services, a standard Window
  menu. Toggle Line Comment is `⌘/`; next and previous tab are `⌘⌥→` and `⌘⌥←`,
  as in Safari and Xcode, because macOS reserves `⌃Tab`; Replace is `⌘⌥H`
  because `⌘H` hides the app. A second profile with Ctrl bindings, for people
  arriving from Windows editors, comes with the shortcut editor in M7.
- **Line endings.** New files use LF. Existing files keep whatever they have:
  the line ending is detected on load and preserved on save.
- **Encodings.** A byte order mark is trusted; otherwise valid UTF-8 is UTF-8;
  otherwise the file is read with an 8-bit code page, Windows-1252 by default,
  shown in the Encoding menu by name. A file saved in another 8-bit code page
  opens as wrong characters until that page is chosen. M2 adds the full
  code-page menu and a round-trip corpus.
- **Sessions.** Tabs and unsaved text come back on launch. Unsaved text is
  written to a backup folder every 7 seconds, so quitting never asks and a
  crash loses seconds, not work.
- **Files on disk.** Settings, the session and backups live in
  `~/Library/Application Support/MacPad`.
- **Distribution.** A disk image published on GitHub Releases, outside the Mac
  App Store: the sandbox would block running external commands, plugins and
  opening arbitrary folders as workspaces. Notarisation and a Homebrew cask are
  planned.
- **Installing.** A disk image runs no code, so the app does the tidying:
  opened from an image, it offers to move itself to Applications; opened from
  Applications, it ejects MacPad images left mounted. Images are named after
  their version.
- **Updates.** The app checks GitHub Releases once a day and on demand. Every
  build of the main branch publishes a release; see
  [`releases/PUBLISHING.md`](releases/PUBLISHING.md).
- **Minimum system.** macOS 13, universal for Apple silicon and Intel.

---

## 3. Scope

The first complete version is M1 through M5: documents and tabs, file
handling, search, highlighting and themes, and the full set of editing
commands. That is what people touch every day. Panels, automation, plugins and
localisation follow.

---

## 4. Milestones

Each milestone ends with a measurable exit criterion.

| # | Milestone | Exit criterion |
|---|---|---|
| **M0** | **Skeleton.** Vendored Scintilla and Lexilla, the Objective-C++ bridge, one window, open and save, universal binary, CI producing a signed app. *Done* | Open a large file, type without lag, save byte-identically |
| **M1** | **Documents, tabs, views.** One Scintilla document per tab, swapped under a single view; the tab bar; session restore and backup; recent files; drag and drop. *Largely done.* Remaining: split view, tab colours and pinning, Document List | 100 files open; quit and relaunch restores tabs, carets and scroll positions |
| **M2** | **File handling.** Full code-page menu and encoding conversion; statistical detection; reload prompt when a file changes on disk; follow mode; backup on save; Save a Copy, Rename, Move to Trash | A corpus covering every supported encoding round-trips byte for byte |
| **M3** | **Search.** *Engine and find bar done.* Remaining: In Selection, Find All, Find in Files with filters, the results panel, mark styles, smart highlighting, brace navigation | Find in Files across a large folder returns grouped, clickable results |
| **M4** | **Highlighting, styles, themes.** The ~90-language catalogue from a definitions file; per-language settings; user-defined languages; a style editor and themes loaded from files; all margin and marker options; brace and tag matching; clickable URLs | Every bundled theme renders correctly across a per-language sample corpus |
| **M5** | **Editing commands.** Case conversion, line operations and sorting, blank operations, block comments, column mode and the column editor, multi-select, auto-completion, auto-pairing, indentation | Every Edit command is ticked in `FEATURES.md` |
| **M6** | **Panels.** A docking framework (float, dock on four edges, tabbed groups, persistence), then Function List, Document Map, Folder as Workspace, Projects. *Largest user-interface risk: AppKit has nothing for this* | Panels dock, float, tab and persist across restart |
| **M7** | **Automation.** Macro recording and playback, the Run menu with variables, the shortcut editor and keyboard profiles, command-line arguments and a `macpad` command, Finder Services | A recorded macro replays identically after a restart |
| **M8** | **Plugins.** A native plugin interface, a plugin manager over a signed catalogue, a scripting bridge for small extensions, bundled plugins for compare, export, JSON, XML and hex | Three bundled plugins working; a plugin guide published |
| **M9** | **Polish.** The Settings window, printing, localisation, hashing tools, distraction-free mode, VoiceOver, notarised disk image, Homebrew cask | `FEATURES.md` audited end to end |

---

## 5. Repository layout

```
macpad/
├─ Sources/
│  ├─ MacPadApp/          Swift — app delegate, menus, update controller
│  ├─ MacPadUI/           Swift — window controller, tab bar, find bar, file drops
│  ├─ MacPadCore/         Swift — buffers, sessions, encodings, languages, themes, updates
│  ├─ ScintillaBridge/    Objective-C++ — the ScintillaView wrapper Swift talks to
│  └─ SearchEngine/       C++ — the Boost.Regex adapter for Scintilla
├─ Vendor/                fetched by Tools/fetch-deps.sh, never committed
├─ Resources/             icon, logo, disk-image read-me
├─ Tests/
│  ├─ Unit/               XCTest, hosted in the app
│  └─ Integration/        regex conformance, runs on any platform
├─ Tools/                 build, package, dependency and version scripts
└─ docs/                  this plan, the feature list, release notes
```

---

## 6. How quality is proven

1. **Regex conformance.** `Tests/Integration/run.sh` drives the engine through
   a real Scintilla document, the same path the app uses, and checks 38
   behaviours: patterns, `\K`, multi-line matching, anchors, the replacement
   syntax, case sensitivity, direction, range bounds and malformed input. It
   links only Scintilla's platform-independent core, so it runs on Linux in CI.
2. **Unit tests.** Encodings, languages, sessions, the find engine with every
   option, the tab bar, file drops, drawing bounds and the update checker.
3. **Smoke launch.** CI runs the built app and fails if it exits early, then
   renders the editor and the tab bar offscreen and fails if either is blank.
4. **Constants pinned to headers.** Message numbers and search flags the Swift
   layer hard-codes are checked against the vendored Scintilla header, so a
   dependency bump cannot silently renumber one.
5. **Planned:** golden-file lexer tests per language, XCUITest for dialogs and
   panels, and a capture of the real composited window in CI.

**Performance budgets**, to be asserted in CI: a 100 MB file opens in under
2 seconds; keystroke-to-glyph latency under 16 ms on a 10 MB file; Find All
across 100 open documents in under 1 second; cold launch under 500 ms.

---

## 7. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **Docking panel framework**: AppKit provides nothing | High; the most under-estimated item | Timebox a spike before M6. If it overruns, reconsider Qt while switching is still cheap |
| **Scintilla's Cocoa back end is less exercised** | Medium: input methods, accessibility, scrolling | Budget engine time for upstream patches |
| **AppKit changes between macOS versions** | Medium; already bitten once (§9, drawing on macOS 26) | Test on the newest macOS as well as CI's; capture the real window, not only offscreen renders |
| **8-bit encoding mismatches** | Medium, and very visible | Settle the policy in M2 and cover it with the round-trip corpus |
| **Scope exhaustion**: hundreds of commands | High; this is how such projects die | Ship at the M5 line, iterate in public; `FEATURES.md` keeps progress visible |
| **No plugin ecosystem** | Medium | Bundle the most useful plugins; the scripting bridge covers the long tail |

---

## 8. Decisions

| # | Decision | Consequence |
|---|---|---|
| 1 | **Licence: GPL-3.0-or-later** | `LICENSE` is the verbatim GPL. The three libraries are permissive and impose nothing |
| 2 | **Distribution: direct**, on GitHub Releases | Not the Mac App Store; see §2 |
| 3 | **Keyboard: Mac conventions by default** | A Ctrl-based profile ships later as an option |
| 4 | **First complete version is M1–M5** | Panels, plugins and localisation come after |
| 5 | **Minimum macOS 13** | Modern AppKit and Swift are worth more than reach into old systems |
| 6 | **Releases are automatic** | Every build of the main branch that passes its checks is published with the next version number |

---

## 9. Build state and lessons

MacPad builds as a universal app, launches, renders, and passes its unit tests
and the regex conformance suite, on CI (macOS 15) and on macOS 26. Version
0.1.0 was the first public release.

Lessons worth keeping, each invisible to static checking:

1. **A failing build can mask its successors.** Xcode compiles in parallel; one
   target failing fast cancelled another before it reported its own error.
2. **Read the exit status, not the output.** A test step piped `xcodebuild`
   through `grep ... || true` and reported a real failure as success. The same
   pattern in the local build script printed "Built" for an app that would not
   launch. Both now capture the status directly.
3. **Scintilla document lifetimes.** `SCI_SETDOCPOINTER` releases the document
   the view holds and deletes it if that was the last reference. Switching away
   from a document nothing else owned, then back, used freed memory and crashed
   at launch. The buffer store now holds its own reference for the duration.
4. **ScintillaView lays itself out only in `-setFrame:`.** Auto Layout resizes
   views through `-setFrameSize:`, so constraints alone left it at its
   placeholder size. The bridge forwards the size change explicitly.
5. **Never fill the dirty rect.** On macOS 26, `draw(_:)` receives a rect the
   size of the whole window for a view that does not clip to its bounds, and
   drawing outside the bounds is honoured. The status bar filled that rect and
   covered the tab bar and the editor: a blank window with everything laid out
   correctly underneath. Hand-drawn views fill `bounds`, and a test feeds each
   an oversized rect.
6. **Liveness and offscreen renders cannot see emptiness.** The smoke launch
   passed blank builds, and so did an offscreen render check, because it hands
   each view its own bounds. Only a capture of the real window showed the fault.
7. **Pin constants to the header.** The bridge once numbered Scintilla's search
   flags 1, 2, 4, 8. Whole word happened to coincide and worked; match case and
   regular expressions were silently ignored. A test now reads the header.
8. **The inactive selection has its own colour.** After Find Next the find
   field keeps keyboard focus, and Scintilla drew the selected match in a faint
   inactive grey. Selection colours are set for both states.
9. **Cloud-synced checkouts break code signing.** The sync service marks build
   output with Finder metadata that `codesign` rejects. The build scripts turn
   Xcode's signing off, strip the metadata and sign afterwards.

---

## 10. Search engine: why Boost.Regex and not the macOS options

**`NSTextFinder`**, the stock macOS find bar, has no regular-expression support
at all: literal, case-insensitive, whole-word and diacritic-insensitive only.
For an editor whose headline search feature is regex it cannot work.

**`NSRegularExpression`** is ICU. It has no `\K` match reset, and its
replacement template supports only `$0`–`$n`: no `\U \L \u \l \E` case
conversion, no `$&`, `` $` ``, `$'`, `$+`, no conditionals. `\U$1\E` is an
everyday idiom, so ICU would be a visible downgrade.

**Boost.Regex is nearly free to adopt.** Two findings:

1. Scintilla has a documented hook for exactly this. Define `SCI_OWNREGEX` and
   supply `Scintilla::Internal::CreateRegexSearch`, and the engine is replaced
   wholesale, with Scintilla still handling byte offsets, target ranges and
   `SCI_REPLACETARGETRE`. No text marshalling and no UTF-8 to UTF-16 index
   mapping in the app layer.
2. Since Boost 1.75, Boost.Regex compiles header-only in standalone mode,
   which turns itself on when `<boost/version.hpp>` is absent: one include
   directory and a 350-line adapter.

Scintilla's built-in engine is line-oriented and cannot match across a line
end at all. MacPad's searches are always multi-line, `\R` matches any line
ending, and that gap is closed.

Behaviours established by experiment:

- Boost's plain Perl mode makes `.` cross line ends. MacPad compiles with
  `no_mod_s`, so `.` stops at a line end by default, and the find bar's
  ". matches newline" option is an inline `(?s)` on the pattern.
- Replacements need `format_all`; that is what enables `\U` and the
  conditional forms.
- Variable-length lookbehind is rejected by Boost too.
- `Document::FindText` takes `*length` as an in/out parameter: on entry it must
  hold the pattern length, or it returns without searching.
- Replace All must advance by the replacement length, plus one when the match
  consumed no source character, or a zero-width match such as `x*` never ends.

---

## Credits

MacPad is built on Scintilla and Lexilla, © Neil Hodgson, and Boost.Regex,
© John Maddock, under their respective licences.

## Sources

- Scintilla — https://www.scintilla.org/
- Scintilla and Lexilla licence — https://www.scintilla.org/License.txt
- Boost.Regex — https://www.boost.org/doc/libs/release/libs/regex/

# MacPad features

What MacPad does today and what is planned, organised by menu. This file is
the project's definition of done: an item is ticked only when it works and an
automated test covers it.

Legend: `[x]` works and is covered by automated tests · `[~]` works, or partly
works, but has no automated test yet · `[ ]` planned · `[-]` deliberately not
planned

Milestone tags (`M1`–`M9`) refer to [`PLAN.md`](PLAN.md) §4.

---

## File `M1` `M2`

- [~] New · [~] Open… · [~] Open Recent
- [x] Open by dragging files onto the window, the tab bar or the editor
- [x] Opening a file that is already open selects its tab instead of opening it twice
- [~] Reload from Disk
- [~] Save · Save As… · Save All
- [~] Close Tab · Close All but This (tab context menu)
- [x] Session: tabs, carets and scroll positions restored on launch
- [x] Unsaved text backed up every 7 seconds and restored after a quit or a crash
- [ ] Restore Recently Closed File
- [ ] Show in Finder · Open in Terminal · Open in Default Viewer
- [ ] Open Folder as Workspace (security-scoped bookmarks)
- [ ] Save a Copy As… · Rename… · Move to Trash
- [ ] Close All · Close All to the Left / Right · Close All Unchanged
- [ ] Reload prompt when a file changes on disk (FSEvents)
- [ ] Print… (`M9`)
- [ ] File type declarations so MacPad appears in Open With; Finder Services (`M7`)

## Edit `M5`

### Core
- [x] Undo · Redo · Cut · Copy · Paste · Delete · Select All
- [x] The same commands act on the find and replace fields when the cursor is in them
- [x] Commands that would do nothing are greyed out; Line Endings, Language and
      Encoding menus tick the current choice
- [x] Right-click menu in the editor: clipboard, case, comments, find, web search, bookmark
- [~] Multiple selections, typing into all of them, multi-paste
- [ ] Copy Full Path / File Name / Folder Path
- [ ] Set / Clear Read-Only
- [ ] Increase / Decrease Indent

### Convert case
- [x] UPPERCASE · lowercase
- [ ] Proper Case · Sentence case · iNVERT cASE · rANdOM cAsE

### Line operations
- [ ] Duplicate Line · Remove Duplicate Lines · Remove Consecutive Duplicate Lines
- [ ] Split Lines · Join Lines · Move Line Up / Down
- [ ] Remove Empty Lines (with or without blank characters)
- [ ] Insert Blank Line Above / Below
- [ ] Reverse Line Order · Randomize Line Order
- [ ] Sort Lines: lexicographic, case-insensitive, integer, decimal (comma or dot), natural; ascending and descending

### Comments
- [x] Toggle Line Comment, per-language marker, one undo step
- [x] Block Comment · Block Uncomment, for languages that have block markers

### Auto-completion
- [ ] Word completion · Function completion · Parameter hints · Path completion
- [ ] Auto-insert matching brackets, quotes and HTML/XML close tags

### Line endings
- [x] Convert to Windows (CR LF) · Unix (LF) · classic Mac (CR)
- [x] Detected on open, preserved on save; new files use LF

### Blank operations
- [ ] Trim Trailing / Leading / Both
- [ ] EOL to Space · Remove Unnecessary Blanks and EOL
- [ ] Tab to Space · Space to Tab (all / leading)

### Paste special and selection actions
- [ ] Paste HTML / RTF content · Copy / Cut / Paste binary content
- [x] Find Selection · Search the web for the selection
- [ ] Open selected File / Folder

### Multi-editing and column mode
- [ ] Multi-Select All (with match case / whole word variants)
- [ ] Column mode: begin/end select, `Option`+drag rectangular selection, virtual space
- [ ] Column Editor: insert numbers (start, step, repeat, padding; dec/oct/hex/bin) or text

## Search `M3`

### Find bar
- [x] Find · Find Next · Find Previous (also Return and Shift-Return in the field)
- [x] Search as you type: first match selected, every match highlighted, match count shown
- [x] Modes: Normal · Extended (`\n \r \t \0 \xHH \uXXXX \dDDD \oOOOO`) · Regular expression
- [x] Regular expressions in full Perl syntax through Boost.Regex 1.90: multi-line
      matching, `\K`, lookaround, named groups; 38-check conformance suite
- [x] Replacement syntax: `\1` `$1` `${1}` `$&` `\U \L \u \l \E`, conditionals
- [x] Match case · Whole word · Wrap around · `. matches newline`
- [x] Count · Mark All · Replace · Replace All (safe on zero-width matches)
- [ ] In selection · Find All in Current Document · Find All in All Open Documents
- [ ] Replace All in All Open Documents
- [ ] Find and replace history

### Find in Files
- [ ] Find in Files · Replace in Files
- [ ] Filters, folder choice, subfolders, hidden folders

### Results and navigation
- [ ] Search Results panel, grouped by file, with click-through
- [~] Go to Line… · [ ] Go to offset
- [ ] Go to Matching Brace · Select Between Matching Braces
- [ ] Find Characters in Range

### Mark and highlight
- [ ] Mark styles (5) · Clear marks · Jump between marked lines
- [ ] Smart highlighting: every occurrence of the selected word
- [ ] Copy Styled Text

### Bookmarks
- [~] Toggle · Next · Previous (also by clicking the bookmark margin)
- [ ] Clear All · Inverse
- [ ] Cut / Copy / Paste / Replace / Remove bookmarked lines

## View `M1` `M4` `M6`

- [x] Tab bar: many compact tabs, close buttons, unsaved marker, double-click the
      empty bar for a new tab, drawing confined to its own area
- [~] Tab bar: drag to reorder, middle-click to close, scroll when tabs overflow
- [ ] Tab bar: multi-row, vertical, colours, pinning, tab preview
- [~] Show All Characters (spaces, tabs, line ends) · Show Indent Guides
- [~] Zoom In / Out / Restore Default
- [~] Word Wrap · [ ] wrap indent modes
- [~] Fold All · Unfold All · click the fold margin · [ ] fold by level
- [~] Margins: line numbers (width follows the line count) · bookmarks · folding
- [~] Caret line highlight
- [~] Light and dark themes that follow the system appearance
- [~] Status bar: line, column, line count, length, language, encoding, line ending
- [~] Enter Full Screen · [ ] Distraction Free mode · [ ] Always on Top (`M9`)
- [ ] Split view: two panes, move or clone a document between them
- [ ] Synchronised scrolling between panes
- [ ] Hide Lines · Text direction RTL / LTR
- [ ] Follow a growing file (`tail -f`) (`M2`)
- [ ] Panels: Document Map · Document List · Function List · Folder as Workspace · Projects
- [ ] Edge / column markers · clickable URLs · change history margin

## Encoding `M2`

- [x] UTF-8 · UTF-8 with BOM · UTF-16 LE · UTF-16 BE: detected on open, kept on save
- [x] 8-bit code pages as a fallback for files that are not valid UTF-8 (default Windows-1252)
- [~] Change a file's encoding from the Encoding menu
- [ ] Full code-page menu: Arabic, Baltic, Central European, Chinese, Cyrillic, Greek,
      Hebrew, Japanese, Korean, Thai, Turkish, Vietnamese, Western European
- [ ] Convert between encodings (re-encode the text, not just relabel it)
- [ ] Statistical encoding detection for files without a byte order mark
- [ ] Byte-for-byte round-trip corpus

## Language `M4`

- [x] 31 languages on Lexilla's lexers, each backed by a lexer that exists in the build
- [~] Chosen from the file name or extension; changeable from the Language menu
- [ ] The full ~90-language catalogue, grouped A–Z, loaded from a definitions file
- [ ] Per-language tab settings (size, tabs or spaces)
- [ ] User-defined languages: keywords, comments, numbers, operators, delimiters, folding

## Settings `M4` `M7` `M9`

- [ ] Settings window: General · Editing · Appearance · Tab Bar · Margins · New Document ·
      Recent Files · Languages · Highlighting · Print · Search · Backup · Auto-Completion · Performance
- [ ] Style editor: global and per-language styles, themes loaded from files
- [ ] Shortcut editor: menu commands, macros, run commands, editor commands
- [ ] Keyboard profiles: Mac native (default) and a Windows-style profile with Ctrl bindings
- [ ] Editable context menus
- [x] Session snapshot and periodic backup (on by default; `SessionSnapshotEnabled`)
- [ ] Backup on save

## Tools `M9`

- [ ] MD5 / SHA-1 / SHA-256 / SHA-512 of text, selection or files

## Macro `M7`

- [ ] Start / Stop Recording · Playback · Save Recorded Macro
- [ ] Run a Macro Multiple Times (N times or to the end of the file)
- [ ] Assign shortcuts to macros

## Run `M7`

- [ ] Run… dialog · save a command with a shortcut
- [ ] Variables: `$(FULL_CURRENT_PATH)` `$(CURRENT_DIRECTORY)` `$(FILE_NAME)` `$(NAME_PART)`
      `$(EXT_PART)` `$(CURRENT_WORD)` `$(CURRENT_LINE)` `$(CURRENT_COLUMN)` `$(SYS.<name>)`
- [ ] Default entries: open in Safari / Chrome / Firefox, Terminal, Mail

## Plugins `M8`

- [ ] Native plugin interface: commands, notifications, access to the editor
- [ ] Plugins loaded from `~/Library/Application Support/MacPad/plugins`
- [ ] Plugin manager over a signed catalogue: install, update, remove
- [ ] Scripting bridge (Lua or JavaScriptCore) for small extensions
- [ ] Bundled plugins: Compare · Export · MIME tools · Converter · JSON viewer · XML tools · Hex editor

## Window `M1`

- [~] Next Tab · Previous Tab · Tab 1–9
- [~] Standard macOS Window menu: Minimize, Zoom, Bring All to Front
- [ ] Window list · sort tabs

## App and help `M9`

- [x] Check for Updates: on demand and once a day at launch, from GitHub Releases or a hosted feed
- [~] About panel · app icon and logo
- [x] Universal binary (arm64 + x86_64), ad-hoc signed DMG
- [x] A release published automatically for every build of the main branch
- [ ] Notarised DMG (opens without the right-click step) · Homebrew cask
- [ ] Command-line arguments and a `macpad` command
- [ ] Debug Info

## Cross-cutting

- [ ] Localisation, including right-to-left languages (`M9`)
- [ ] Printing: syntax colours, header and footer variables, preview, line numbers (`M9`)
- [ ] Accessibility: VoiceOver in the editor (`M9`)
- [ ] Performance budgets enforced in CI ([`PLAN.md`](PLAN.md) §6)

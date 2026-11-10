//
//  EditorWindowController.swift
//  MacPad
//
//  One window: a tab bar, an optional find bar, the editor, and a status bar.
//  Owns the BufferStore and wires menu commands to it.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

final class EditorWindowController: NSWindowController {

    private let editor = MPEditorView(frame: .zero)
    private let tabBar = TabBarView(frame: .zero)
    private let findBar = FindBarView(frame: .zero)
    private let statusBar = StatusBarView(frame: .zero)

    private var findBarHeightConstraint: NSLayoutConstraint!
    private var store: BufferStore!
    private var session: SessionCoordinator!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            // No .fullSizeContentView: it extends the content view under the
            // title bar, and with an opaque title bar that hides the tab bar
            // pinned to contentView.top entirely.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "MacPad"
        window.titlebarAppearsTransparent = false
        window.tabbingMode = .disallowed   // MacPad has its own tabs
        window.setFrameAutosaveName("MacPadMainWindow")
        window.minSize = NSSize(width: 520, height: 320)
        window.contentView = AppearanceObservingView(frame: window.contentLayoutRect)
        self.init(window: window)
        (window.contentView as? AppearanceObservingView)?.onAppearanceChange = { [weak self] in
            self?.systemAppearanceDidChange()
        }
        (window.contentView as? AppearanceObservingView)?.onFileDrop = { [weak self] urls in
            self?.open(urls: urls)
        }
        buildInterface()
    }

    // MARK: - Interface

    private func buildInterface() {
        guard let window, let contentView = window.contentView else { return }

        for view in [tabBar, findBar, editor, statusBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        tabBar.delegate = self
        findBar.delegate = self
        editor.delegate = self
        tabBar.onFileDrop = { [weak self] urls in self?.open(urls: urls) }

        findBarHeightConstraint = findBar.heightAnchor.constraint(equalToConstant: 0)
        findBar.isHidden = true

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 26),

            findBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            findBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            findBarHeightConstraint,

            editor.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            editor.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            statusBar.topAnchor.constraint(equalTo: editor.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),
        ])

        store = BufferStore(editor: editor, theme: Theme.matchingSystemAppearance())
        store.delegate = self
        session = SessionCoordinator(store: store, files: SessionStore.standard())
        store.sessionObserver = session

        editor.showFoldMargin(true)
        editor.showBookmarkMargin(true)
        editor.showIndentGuides = true

        // Last run's tabs come back, unsaved text included; a first run gets
        // "new 1". From here on, every edit is backed up within seconds.
        session.restoreAtLaunch()
        session.start()
        window.makeFirstResponder(editor)
    }

    /// Write every unsaved tab to the backup folder and the tab list to disk.
    /// Called by the app delegate as the app quits.
    func snapshotSession() {
        session.snapshot()
    }

    /// Scintilla cannot measure text until it has a drawing surface, so the
    /// margin width and style metrics computed during setup are unreliable.
    /// Re-apply them once the window is actually on screen.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshEditorPresentation()
        dumpLayoutIfRequested()
    }

    /// Print every view's real frame, once the layout pass has settled.
    /// Enabled by MACPAD_DUMP_LAYOUT=1 so CI can read it from a headless run;
    /// this is how a blank editor gets diagnosed without a Mac to click on.
    private func dumpLayoutIfRequested() {
        guard ProcessInfo.processInfo.environment["MACPAD_DUMP_LAYOUT"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, let window = self.window else { return }
            window.contentView?.layoutSubtreeIfNeeded()

            var report = "\n===== MACPAD LAYOUT DUMP =====\n"
            report += "window        frame=\(window.frame) visible=\(window.isVisible)\n"
            report += "contentView   frame=\(window.contentView?.frame ?? .zero)"
                    + " subviews=\(window.contentView?.subviews.count ?? -1)\n"
            report += "tabBar        frame=\(self.tabBar.frame) hidden=\(self.tabBar.isHidden)"
                    + " items=\(self.tabBar.items.count) selected=\(self.tabBar.selectedIndex)\n"
            report += "findBar       frame=\(self.findBar.frame) hidden=\(self.findBar.isHidden)\n"
            report += "statusBar     frame=\(self.statusBar.frame)\n"
            report += "buffers       count=\(self.store?.buffers.count ?? -1)\n"
            report += self.editor.layoutDescription()

            // Geometry being right is not the same as pixels being drawn, and
            // the smoke launch cannot tell a blank window from a working one.
            // Render the views offscreen and count distinct colours: a view
            // that draws nothing yields exactly one.
            self.editor.replaceSelection(with: "let answer = 42  // render check\n")
            self.editor.needsDisplay = true
            window.contentView?.displayIfNeeded()

            report += self.renderCheck(self.editor, label: "editor")
            report += self.renderCheck(self.tabBar, label: "tabBar")
            report += "==============================\n"
            FileHandle.standardError.write(Data(report.utf8))
            print(report)
        }
    }

    /// Snapshot a view offscreen and report how many distinct colours it
    /// contains. Works without a window server, so CI can check it.
    /// One colour means the view drew nothing but its background.
    private func renderCheck(_ view: NSView, label: String) -> String {
        guard view.bounds.width > 1, view.bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return "  render \(label): cannot snapshot (bounds=\(view.bounds))\n"
        }
        view.cacheDisplay(in: view.bounds, to: rep)

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        var colours = Set<UInt32>()
        var sampled = 0
        let xStep = max(1, width / 250)
        let yStep = max(1, height / 250)
        for y in stride(from: 0, to: height, by: yStep) {
            for x in stride(from: 0, to: width, by: xStep) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                let r = UInt32((colour.redComponent * 255).rounded())
                let g = UInt32((colour.greenComponent * 255).rounded())
                let b = UInt32((colour.blueComponent * 255).rounded())
                colours.insert((r << 16) | (g << 8) | b)
                sampled += 1
            }
        }
        let verdict = colours.count <= 1 ? "BLANK" : "drew content"
        return "  render \(label): \(width)x\(height), \(sampled) px sampled, "
             + "\(colours.count) distinct colours -> \(verdict)\n"
    }

    private func refreshEditorPresentation() {
        guard let store = store, let buffer = store.activeBuffer else { return }
        editor.applyTheme(store.currentTheme, for: buffer.language)
        editor.showLineNumbers(true)
        editor.needsLayout = true
        editor.needsDisplay = true
    }

    /// Follow the system appearance.
    /// NSApplication.effectiveAppearance is not reliably KVO-observable, so
    /// this hangs off AppKit's supported hook instead: a content view that
    /// overrides viewDidChangeEffectiveAppearance().
    fileprivate func systemAppearanceDidChange() {
        store?.setTheme(Theme.matchingSystemAppearance())
        tabBar.needsDisplay = true
    }

    // MARK: - Buffer access

    private var activeBuffer: Buffer? { store.activeBuffer }

    // MARK: - File commands

    @objc func newDocument(_ sender: Any?) {
        do { try store.newUntitledBuffer() } catch { presentError(error) }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.open(url: url)
            }
        }
    }

    func open(url: URL) {
        do {
            try store.openFile(at: url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            presentError(error)
        }
    }

    /// Open several files, each in its own tab, and bring the window forward,
    /// which is what a drop from the Finder expects.
    func open(urls: [URL]) {
        for url in urls {
            open(url: url)
        }
        if !urls.isEmpty {
            window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let buffer = activeBuffer else { return }
        if buffer.isUntitled {
            saveDocumentAs(sender)
            return
        }
        do { try store.save(buffer) } catch { presentError(error) }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let buffer = activeBuffer, let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = buffer.displayName
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.store.saveAs(buffer, to: url)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                self.presentError(error)
            }
        }
    }

    @objc func saveAllDocuments(_ sender: Any?) {
        let failures = store.saveAllDirtyBuffers()
        if let (buffer, error) = failures.first {
            presentError(error, context: buffer.displayName)
        }
    }

    @objc func revertDocumentToSaved(_ sender: Any?) {
        guard let buffer = activeBuffer, let url = buffer.url else { return }
        let alert = NSAlert()
        alert.messageText = "Reload “\(buffer.displayName)” from disk?"
        alert.informativeText = "Any unsaved changes will be lost."
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store.close(buffer)
        open(url: url)
    }

    @objc func printDocument(_ sender: Any?) {
        // Printing with syntax colours, header/footer variables and a preview
        // is M9; NSPrintOperation needs a paginating view over Scintilla.
        let alert = NSAlert()
        alert.messageText = "Printing is not implemented yet."
        alert.informativeText = """
            Printing arrives in milestone M9, with syntax colours, \
            header and footer variables and a print preview. \
            See docs/PLAN.md.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func closeActiveBuffer(_ sender: Any?) {
        guard let buffer = activeBuffer else { return }
        closeBuffer(buffer)
    }

    private func closeBuffer(_ buffer: Buffer) {
        guard buffer.isDirty else {
            store.close(buffer)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(buffer.displayName)” before closing?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if buffer.isUntitled {
                saveDocumentAs(nil)   // sheet; leave the buffer open
            } else {
                do {
                    try store.save(buffer)
                    store.close(buffer)
                } catch {
                    presentError(error)
                }
            }
        case .alertSecondButtonReturn:
            store.close(buffer)
        default:
            break
        }
    }

    /// True when the app may quit. With session snapshots on (the default)
    /// unsaved tabs are backed up and come back next launch,
    /// so there is nothing to ask. With them off, every buffer must be clean
    /// or the user must agree to discard it.
    func prepareToTerminate() -> Bool {
        if session.isEnabled {
            session.snapshot()
            return true
        }
        let dirty = store.buffers.filter(\.isDirty)
        guard !dirty.isEmpty else { return true }

        let alert = NSAlert()
        alert.messageText = dirty.count == 1
            ? "“\(dirty[0].displayName)” has unsaved changes."
            : "\(dirty.count) documents have unsaved changes."
        alert.informativeText = "Do you want to save before quitting?"
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let failures = store.saveAllDirtyBuffers()
            if let (buffer, error) = failures.first {
                presentError(error, context: buffer.displayName)
                return false
            }
            // Untitled buffers have nowhere to go; keep the app open for them.
            return !store.buffers.contains { $0.isDirty }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: - Edit commands

    @objc func undoEdit(_ sender: Any?) { editor.undo() }
    @objc func redoEdit(_ sender: Any?) { editor.redo() }
    @objc func cutText(_ sender: Any?) { editor.cutSelection() }
    @objc func copyText(_ sender: Any?) { editor.copySelection() }
    @objc func pasteText(_ sender: Any?) { editor.pasteFromClipboard() }
    @objc func selectAllText(_ sender: Any?) { editor.selectAllText() }

    @objc func toggleLineComment(_ sender: Any?) {
        guard let language = activeBuffer?.language else { return }
        editor.toggleLineComment(for: language)
    }

    @objc func toggleWordWrap(_ sender: Any?) {
        editor.wordWrap = !editor.wordWrap
    }

    @objc func toggleInvisibleCharacters(_ sender: Any?) {
        let shouldShow = !editor.showWhitespace
        editor.showWhitespace = shouldShow
        editor.showEndOfLine = shouldShow
    }

    @objc func toggleIndentGuides(_ sender: Any?) {
        editor.showIndentGuides = !editor.showIndentGuides
    }

    @objc func zoomIn(_ sender: Any?)  { editor.zoomLevel = min(20, editor.zoomLevel + 1) }
    @objc func zoomOut(_ sender: Any?) { editor.zoomLevel = max(-10, editor.zoomLevel - 1) }
    @objc func zoomReset(_ sender: Any?) { editor.zoomLevel = 0 }

    @objc func foldAll(_ sender: Any?)   { editor.foldAll() }
    @objc func unfoldAll(_ sender: Any?) { editor.unfoldAll() }

    @objc func toggleBookmark(_ sender: Any?) {
        editor.toggleBookmark(atLine: editor.currentLine)
    }

    @objc func nextBookmark(_ sender: Any?) {
        let line = editor.nextBookmark(afterLine: editor.currentLine)
        if line >= 0 { editor.goToLine(line) }
    }

    @objc func previousBookmark(_ sender: Any?) {
        let line = editor.previousBookmark(beforeLine: editor.currentLine)
        if line >= 0 { editor.goToLine(line) }
    }

    @objc func goToLine(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Go to line"
        alert.informativeText = "Line number (1–\(editor.lineCount)):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              let requested = Int(field.stringValue) else { return }
        editor.goToLine(max(0, requested - 1))
        editor.scrollCaretIntoView()
    }

    // MARK: - Tab navigation

    @objc func selectNextTab(_ sender: Any?)     { store.activateNextBuffer() }
    @objc func selectPreviousTab(_ sender: Any?) { store.activatePreviousBuffer() }

    @objc func selectTabByNumber(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        store.activateBuffer(at: item.tag - 1)
    }

    // MARK: - Language menu

    @objc func setLanguageFromMenu(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let languageID = item.representedObject as? String,
              let language = LanguageCatalog.language(withID: languageID),
              let buffer = activeBuffer else { return }
        store.setLanguage(language, for: buffer)
    }

    @objc func setLineEndingFromMenu(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let lineEnding = LineEnding(rawValue: item.tag),
              let buffer = activeBuffer else { return }
        store.setLineEnding(lineEnding, for: buffer)
    }

    @objc func setEncodingFromMenu(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let buffer = activeBuffer else { return }
        let encoding: FileEncoding
        switch item.tag {
        case 0: encoding = .utf8
        case 1: encoding = .utf8WithBOM
        case 2: encoding = .utf16LittleEndianWithBOM
        case 3: encoding = .utf16BigEndianWithBOM
        default: encoding = .ansiDefault
        }
        store.setEncoding(encoding, for: buffer)
    }

    // MARK: - Find

    @objc func showFindBar(_ sender: Any?) {
        presentFindBar(withReplace: false)
    }

    @objc func showReplaceBar(_ sender: Any?) {
        presentFindBar(withReplace: true)
    }

    private func presentFindBar(withReplace: Bool) {
        findBar.isHidden = false
        findBar.isReplaceVisible = withReplace
        findBarHeightConstraint.animator().constant = withReplace ? 76 : 40
        let selection = editor.selectedText
        findBar.focusFindField(withSelection: selection)
        findBar.setStatus("")
        highlightAllMatches()
    }

    @objc func hideFindBar(_ sender: Any?) {
        findBarHeightConstraint.animator().constant = 0
        findBar.isHidden = true
        editor.clearIndicator(SearchIndicator.markAll)
        editor.clearIndicator(SearchIndicator.incremental)
        window?.makeFirstResponder(editor)
    }

    @objc func findNext(_ sender: Any?) {
        if findBar.isHidden { presentFindBar(withReplace: false); return }
        performFind(backwards: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        if findBar.isHidden { presentFindBar(withReplace: false); return }
        performFind(backwards: true)
    }

    private enum SearchIndicator {
        /// Mark All: stays until the bar closes.
        static let markAll: Int = 8
        /// Every match of the current search text, refreshed as it is typed.
        static let incremental: Int = 9
    }

    /// Search as you type: from where the
    /// current selection starts, select the first match of what is in the
    /// field and highlight every other one. Typing more letters extends the
    /// same match rather than jumping past it; that is why the search starts
    /// at the selection's start and not its end.
    private func incrementalSearch() {
        let options = findBar.options
        let needle = options.effectiveSearchText
        guard !needle.isEmpty else {
            editor.clearIndicator(SearchIndicator.incremental)
            findBar.setStatus("")
            return
        }
        let flags = options.scintillaFlags.rawValue
        let documentLength = editor.length
        var match = editor.findText(needle, from: editor.selectionStart, to: documentLength, flags: flags)
        if match < 0 && options.wrapAround {
            match = editor.findText(needle, from: 0, to: documentLength, flags: flags)
        }
        if match >= 0 {
            editor.setSelection(from: editor.targetStart, to: editor.targetEnd)
            editor.scrollCaretIntoView()
        }
        highlightAllMatches()
    }

    /// Light up every match of the current search text and report how many.
    private func highlightAllMatches() {
        let options = findBar.options
        let needle = options.effectiveSearchText
        guard !needle.isEmpty else {
            editor.clearIndicator(SearchIndicator.incremental)
            return
        }
        let count = editor.markAllOccurrences(
            of: needle,
            flags: options.scintillaFlags.rawValue,
            indicator: SearchIndicator.incremental,
            color: store.currentTheme.findHighlight)
        if count == 0 {
            findBar.setStatus("Not found", isError: true)
        } else {
            findBar.setStatus(count == 1 ? "1 match" : "\(count) matches")
        }
    }

    @discardableResult
    private func performFind(backwards: Bool) -> Bool {
        let options = findBar.options
        let needle = options.effectiveSearchText
        guard !needle.isEmpty else { return false }

        let flags = options.scintillaFlags.rawValue
        let documentLength = editor.length

        // Scintilla signals a backwards search by passing the range reversed,
        // and MacPad's engine honours that by returning the last match in the
        // range. So no manual scan is needed in either direction.
        var match: Int
        if backwards {
            match = editor.findText(needle, from: editor.selectionStart, to: 0, flags: flags)
            if match < 0 && options.wrapAround {
                match = editor.findText(needle, from: documentLength, to: 0, flags: flags)
            }
        } else {
            match = editor.findText(needle, from: editor.selectionEnd, to: documentLength,
                                    flags: flags)
            if match < 0 && options.wrapAround {
                match = editor.findText(needle, from: 0, to: documentLength, flags: flags)
            }
        }

        guard match >= 0 else {
            findBar.setStatus("Not found", isError: true)
            editor.clearIndicator(SearchIndicator.incremental)
            NSSound.beep()
            return false
        }

        editor.setSelection(from: editor.targetStart, to: editor.targetEnd)
        editor.scrollCaretIntoView()
        highlightAllMatches()
        return true
    }

    private func countOccurrences() -> Int {
        let options = findBar.options
        let needle = options.effectiveSearchText
        guard !needle.isEmpty else { return 0 }
        let flags = options.scintillaFlags.rawValue
        let documentLength = editor.length

        var count = 0
        var cursor = 0
        while cursor < documentLength {
            let found = editor.findText(needle, from: cursor, to: documentLength, flags: flags)
            guard found >= 0 else { break }
            count += 1
            let end = editor.targetEnd
            let start = editor.targetStart
            cursor = end > start ? end : start + 1
        }
        return count
    }

    // MARK: - Status and errors

    private func refreshStatusBar() {
        guard let buffer = activeBuffer else {
            statusBar.update(text: "")
            return
        }
        let line = editor.currentLine + 1
        let column = editor.currentColumn + 1
        let lines = editor.lineCount
        let bytes = editor.length
        statusBar.update(
            text: "Ln \(line)   Col \(column)   \(lines) lines   \(bytes) bytes"
                + "      \(buffer.language.displayName)"
                + "      \(buffer.encoding.displayName)"
                + "      \(buffer.lineEnding.displayName)")
    }

    private func refreshWindowTitle() {
        guard let buffer = activeBuffer else {
            window?.title = "MacPad"
            return
        }
        window?.title = buffer.isDirty ? "\(buffer.displayName) — Edited" : buffer.displayName
        window?.representedURL = buffer.url
    }

    private func presentError(_ error: Error, context: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = context.map { "Could not complete the operation on “\($0)”." }
            ?? "Could not complete the operation."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

// MARK: - BufferStoreDelegate

extension EditorWindowController: BufferStoreDelegate {

    func bufferStoreDidChangeBuffers(_ store: BufferStore) {
        refreshTabBar()
        session.sessionDidChange()
    }

    func bufferStore(_ store: BufferStore, didActivate buffer: Buffer?) {
        refreshTabBar()
        refreshWindowTitle()
        refreshStatusBar()
        session.sessionDidChange()
    }

    private func refreshTabBar() {
        let items = store.buffers.map {
            TabItem(title: $0.displayName,
                    tooltip: $0.fullDescription,
                    isDirty: $0.isDirty,
                    isReadOnly: $0.isReadOnly)
        }
        let selection = store.activeBuffer.flatMap { active in
            store.buffers.firstIndex { $0 === active }
        } ?? -1
        tabBar.setItems(items, selectedIndex: selection)
    }
}

// MARK: - TabBarViewDelegate

extension EditorWindowController: TabBarViewDelegate {

    func tabBar(_ tabBar: TabBarView, didSelectIndex index: Int) {
        store.activateBuffer(at: index)
    }

    func tabBarDidRequestNewTab(_ tabBar: TabBarView) {
        newDocument(nil)
    }

    func tabBar(_ tabBar: TabBarView, didRequestCloseAtIndex index: Int) {
        guard store.buffers.indices.contains(index) else { return }
        closeBuffer(store.buffers[index])
    }

    func tabBar(_ tabBar: TabBarView,
                didMoveTabFrom sourceIndex: Int,
                to destinationIndex: Int) {
        store.moveBuffer(from: sourceIndex, to: destinationIndex)
    }

    func tabBar(_ tabBar: TabBarView,
                didRequestContextMenuAtIndex index: Int,
                event: NSEvent) {
        guard store.buffers.indices.contains(index) else { return }
        let buffer = store.buffers[index]

        let menu = NSMenu()
        menu.addItem(withTitle: "Close", action: #selector(closeActiveBuffer(_:)), keyEquivalent: "")
        let closeOthers = menu.addItem(withTitle: "Close All but This",
                                       action: #selector(closeAllButBuffer(_:)),
                                       keyEquivalent: "")
        closeOthers.representedObject = buffer
        menu.addItem(.separator())
        if let url = buffer.url {
            let reveal = menu.addItem(withTitle: "Show in Finder",
                                      action: #selector(revealBufferInFinder(_:)),
                                      keyEquivalent: "")
            reveal.representedObject = url
            let copyPath = menu.addItem(withTitle: "Copy Full Path",
                                        action: #selector(copyBufferPath(_:)),
                                        keyEquivalent: "")
            copyPath.representedObject = url
        }
        for item in menu.items where item.target == nil {
            item.target = self
        }
        NSMenu.popUpContextMenu(menu, with: event, for: tabBar)
    }

    @objc private func closeAllButBuffer(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let keep = item.representedObject as? Buffer else { return }
        for buffer in store.buffers where buffer !== keep {
            closeBuffer(buffer)
        }
    }

    @objc private func revealBufferInFinder(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let url = item.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyBufferPath(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let url = item.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}

// MARK: - FindBarViewDelegate

extension EditorWindowController: FindBarViewDelegate {

    func findBarDidRequestFindNext(_ bar: FindBarView) {
        performFind(backwards: false)
    }

    func findBarDidRequestFindPrevious(_ bar: FindBarView) {
        performFind(backwards: true)
    }

    func findBarDidRequestReplace(_ bar: FindBarView) {
        let options = bar.options
        let needle = options.effectiveSearchText
        guard !needle.isEmpty else { return }

        // Replace only if the current selection is itself a match;
        // otherwise just advance to the next match.
        let selected = editor.selectedText
        let selectionIsMatch = options.mode == .regularExpression
            ? false
            : (options.matchCase ? selected == needle
                                 : selected.caseInsensitiveCompare(needle) == .orderedSame)

        if selectionIsMatch || options.mode == .regularExpression {
            let start = editor.selectionStart
            let end = editor.selectionEnd
            if editor.findText(needle, from: start, to: end, flags: options.scintillaFlags.rawValue) >= 0 {
                if options.mode == .regularExpression {
                    editor.replaceTarget(withExpanded: options.replacementText)
                } else {
                    editor.replaceTarget(with: options.effectiveReplacementText)
                }
            }
        }
        performFind(backwards: false)
    }

    func findBarDidRequestReplaceAll(_ bar: FindBarView) {
        let options = bar.options
        let needle = options.effectiveSearchText
        guard !needle.isEmpty else { return }
        let flags = options.scintillaFlags.rawValue

        editor.beginUndoAction()
        var replacements = 0
        var cursor = 0
        while cursor <= editor.length {
            let found = editor.findText(needle, from: cursor, to: editor.length, flags: flags)
            guard found >= 0 else { break }
            let start = editor.targetStart
            let matchedLength = editor.targetEnd - start
            let replacedLength: Int
            if options.mode == .regularExpression {
                replacedLength = editor.replaceTarget(withExpanded: options.replacementText)
            } else {
                replacedLength = editor.replaceTarget(with: options.effectiveReplacementText)
            }
            replacements += 1
            // Advance past the replacement, and one further for a zero-width
            // match, which consumed no source character. Advancing only by the
            // replacement length re-examines the text just inserted and, for a
            // pattern like `x*`, never terminates.
            cursor = start + replacedLength + (matchedLength == 0 ? 1 : 0)
        }
        editor.endUndoAction()

        // The matches are gone; drop their highlights before reporting.
        highlightAllMatches()
        bar.setStatus(replacements == 1 ? "1 replacement" : "\(replacements) replacements")
    }

    func findBarDidRequestCount(_ bar: FindBarView) {
        let count = countOccurrences()
        bar.setStatus(count == 1 ? "1 match" : "\(count) matches")
    }

    func findBarDidRequestMarkAll(_ bar: FindBarView) {
        let options = bar.options
        let needle = options.effectiveSearchText
        guard !needle.isEmpty else { return }
        let marked = editor.markAllOccurrences(
            of: needle,
            flags: options.scintillaFlags.rawValue,
            indicator: SearchIndicator.markAll,
            color: store.currentTheme.markAllHighlight)
        bar.setStatus(marked == 1 ? "1 marked" : "\(marked) marked")
    }

    func findBarDidRequestClose(_ bar: FindBarView) {
        hideFindBar(nil)
    }

    func findBarOptionsDidChange(_ bar: FindBarView) {
        // Case, whole word or mode changed: the current match may no longer
        // be one. Search again from where it starts.
        incrementalSearch()
    }

    func findBarSearchTextDidChange(_ bar: FindBarView) {
        incrementalSearch()
    }
}

// MARK: - MPEditorViewDelegate

extension EditorWindowController: MPEditorViewDelegate {

    func editorTextDidChange(_ editor: MPEditorView) {
        store.noteActiveBufferDirtyState(editor.isDirty)
        session.noteActiveBufferEdited()
        refreshStatusBar()
    }

    func editorSelectionDidChange(_ editor: MPEditorView) {
        refreshStatusBar()
    }

    func editorDidReachSavePoint(_ editor: MPEditorView) {
        store.noteActiveBufferDirtyState(false)
    }

    func editorDidLeaveSavePoint(_ editor: MPEditorView) {
        store.noteActiveBufferDirtyState(true)
    }

    func editorDidClickMargin(_ margin: Int, atPosition position: Int, editor: MPEditorView) {
        // Margin 1 is the bookmark margin.
        guard margin == 1 else { return }
        editor.toggleBookmark(atLine: editor.line(forPosition: position))
    }

    func editorDidRequestFoldToggle(atLine line: Int, editor: MPEditorView) {
        // MPEditorView already toggled the fold; nothing more to do yet.
    }

    func editor(_ editor: MPEditorView, didDropFileAtPath path: String) {
        open(urls: [URL(fileURLWithPath: path)])
    }
}

// MARK: - Status bar

final class StatusBarView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    func update(text: String) {
        label.stringValue = text
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        // bounds, not dirtyRect: see ViewDrawingBoundsTests.
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}


// MARK: - Appearance observation

/// The window's content view. It reports system appearance changes
/// (viewDidChangeEffectiveAppearance() is AppKit's documented hook for this;
/// observing NSApp.effectiveAppearance with KVO is not supported) and accepts
/// file drops on any part of the window the editor and tab bar do not cover,
/// such as the status bar and find bar.
final class AppearanceObservingView: NSView, FileDropReceiving {
    var onAppearanceChange: (() -> Void)?
    var onFileDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(FileDrop.acceptedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(FileDrop.acceptedTypes)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileDropEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performFileDrop(sender)
    }
}

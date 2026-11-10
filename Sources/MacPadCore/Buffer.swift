//
//  Buffer.swift
//  MacPad
//
//  A Buffer is one open document — one tab. Text lives in a Scintilla
//  document; the editor view displays whichever document is active. This is
//  why switching tabs is instant regardless of file size: nothing is copied,
//  a pointer is swapped.
//
//  What survives a document switch, established by reading Scintilla 5.6.9:
//
//    Per DOCUMENT (persists automatically, set once at creation):
//      - text
//      - the lexer, its keyword lists and its properties
//        (ScintillaBase::DocumentLexState() calls pdoc->SetLexInterface)
//      - EOL mode, tab width, use-tabs, read-only
//      - undo history, save point
//
//  Reference counting: SCI_SETDOCPOINTER releases the document the view holds
//  and deletes it when that was the last reference. A Buffer owns one
//  reference from createDocument, and the view holds its own while displaying
//  it. Switching away from a document nothing else owns therefore destroys it
//  — see withDocument(of:_:), where getting this wrong crashed on launch.
//
//    Per VIEW (does NOT follow the document, must be handled on switch):
//      - the style table: colours and fonts live in ViewStyle, and style
//        *numbers* mean different things to different lexers, so the theme has
//        to be re-applied for the incoming buffer's language
//      - selection and caret position      -> saved on and restored from Buffer
//      - scroll position                   -> saved on and restored from Buffer
//      - word wrap, zoom                   -> intentionally global
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

final class Buffer {
    let id = UUID()

    /// nil for a document that has never been saved.
    var url: URL?
    /// Sequence number behind the "new 1", "new 2" names of untitled tabs.
    let untitledNumber: Int

    /// Opaque Scintilla document pointer. The Buffer owns exactly one
    /// reference to it, acquired at creation and released on close.
    fileprivate(set) var documentPointer: Int

    var language: Language
    var encoding: FileEncoding
    var lineEnding: LineEnding
    var isDirty: Bool = false
    var isReadOnly: Bool = false

    /// View state parked here while another buffer is on screen.
    var savedAnchor: Int = 0
    var savedCaret: Int = 0
    var savedFirstVisibleLine: Int = 0

    /// Modification date at the time of the last load or save, for detecting
    /// changes made by other applications (M2 adds the FSEvents watcher).
    var lastKnownModificationDate: Date?

    /// Session backup bookkeeping (see SessionCoordinator): where this tab's
    /// unsaved text was last written, and whether it has changed since.
    var backupURL: URL?
    var needsBackup: Bool = false

    init(documentPointer: Int,
         url: URL?,
         untitledNumber: Int,
         language: Language,
         encoding: FileEncoding,
         lineEnding: LineEnding) {
        self.documentPointer = documentPointer
        self.url = url
        self.untitledNumber = untitledNumber
        self.language = language
        self.encoding = encoding
        self.lineEnding = lineEnding
    }

    var displayName: String {
        url?.lastPathComponent ?? "new \(untitledNumber)"
    }

    var isUntitled: Bool { url == nil }

    /// Tooltip and title-bar text.
    var fullDescription: String {
        url?.path ?? displayName
    }
}

enum BufferError: LocalizedError {
    case couldNotCreateDocument
    case couldNotDecode(URL, FileEncoding)
    case couldNotEncode(FileEncoding)
    case noDestination

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDocument:
            return "Scintilla could not allocate a new document."
        case .couldNotDecode(let url, let encoding):
            return "“\(url.lastPathComponent)” could not be read as \(encoding.displayName)."
        case .couldNotEncode(let encoding):
            return "This text cannot be saved as \(encoding.displayName) without losing characters."
        case .noDestination:
            return "This document has no file to save to."
        }
    }
}

/// Told when a buffer's backup copy can go: it was saved for real, or closed.
protocol BufferStoreSessionObserver: AnyObject {
    func bufferWasSaved(_ buffer: Buffer)
    func bufferWasClosed(_ buffer: Buffer)
}

protocol BufferStoreDelegate: AnyObject {
    /// The set of buffers changed: one was opened, closed or renamed.
    func bufferStoreDidChangeBuffers(_ store: BufferStore)
    /// A different buffer became active, or its dirty state changed.
    func bufferStore(_ store: BufferStore, didActivate buffer: Buffer?)
}

/// Owns the open buffers and the Scintilla document lifecycle behind them.
final class BufferStore {

    weak var delegate: BufferStoreDelegate?
    weak var sessionObserver: BufferStoreSessionObserver?

    private(set) var buffers: [Buffer] = []
    private(set) var activeBuffer: Buffer?

    private let editor: MPEditorView
    private var theme: Theme
    private var nextUntitledNumber = 1

    init(editor: MPEditorView, theme: Theme) {
        self.editor = editor
        self.theme = theme
    }

    // MARK: - Theme

    func setTheme(_ newTheme: Theme) {
        theme = newTheme
        if let active = activeBuffer {
            editor.applyTheme(theme, for: active.language)
        }
    }

    var currentTheme: Theme { theme }

    // MARK: - Creating buffers

    @discardableResult
    func newUntitledBuffer() throws -> Buffer {
        let doc = editor.createDocument()
        guard doc != 0 else { throw BufferError.couldNotCreateDocument }

        let buffer = Buffer(documentPointer: doc,
                            url: nil,
                            untitledNumber: nextUntitledNumber,
                            language: LanguageCatalog.plainText,
                            encoding: .utf8,
                            lineEnding: .platformDefault)
        nextUntitledNumber += 1
        buffers.append(buffer)

        configureNewlyCreated(buffer, initialText: nil)
        delegate?.bufferStoreDidChangeBuffers(self)
        activate(buffer)
        return buffer
    }

    /// Open a file, or focus the tab that already has it open, so the same
    /// file is never open in two tabs.
    @discardableResult
    func openFile(at url: URL) throws -> Buffer {
        let standardized = url.standardizedFileURL
        if let existing = buffers.first(where: { $0.url?.standardizedFileURL == standardized }) {
            activate(existing)
            return existing
        }

        let data = try Data(contentsOf: standardized)
        let encoding = FileEncoding.detect(in: data)
        guard let text = encoding.decode(data) else {
            throw BufferError.couldNotDecode(standardized, encoding)
        }

        let doc = editor.createDocument()
        guard doc != 0 else { throw BufferError.couldNotCreateDocument }

        let buffer = Buffer(documentPointer: doc,
                            url: standardized,
                            untitledNumber: 0,
                            language: LanguageCatalog.language(for: standardized),
                            encoding: encoding,
                            lineEnding: LineEnding.detect(in: text))
        buffer.lastKnownModificationDate = try? standardized
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        buffers.append(buffer)

        configureNewlyCreated(buffer, initialText: text)
        delegate?.bufferStoreDidChangeBuffers(self)
        activate(buffer)
        return buffer
    }

    /// Recreate a tab from the previous session. Does not activate it or tell
    /// the delegate; finishRestoring(activeIndex:) does that once for the lot.
    ///
    /// `isDirty` means `text` is unsaved work from a backup: the document is
    /// then built so Scintilla itself reports it modified, which is what the
    /// dirty marker and the save prompt key off.
    @discardableResult
    func restoreBuffer(url: URL?,
                       untitledNumber: Int,
                       text: String?,
                       language: Language,
                       encoding: FileEncoding,
                       lineEnding: LineEnding,
                       isDirty: Bool,
                       isReadOnly: Bool,
                       anchor: Int,
                       caret: Int,
                       firstVisibleLine: Int,
                       backupURL: URL?,
                       modificationDate: Date?) throws -> Buffer {
        let doc = editor.createDocument()
        guard doc != 0 else { throw BufferError.couldNotCreateDocument }

        var number = 0
        if url == nil {
            number = untitledNumber > 0 ? untitledNumber : nextUntitledNumber
            nextUntitledNumber = max(nextUntitledNumber, number + 1)
        }
        let buffer = Buffer(documentPointer: doc,
                            url: url?.standardizedFileURL,
                            untitledNumber: number,
                            language: language,
                            encoding: encoding,
                            lineEnding: lineEnding)
        buffer.isReadOnly = isReadOnly
        buffer.lastKnownModificationDate = modificationDate
        buffer.backupURL = backupURL
        buffer.savedAnchor = anchor
        buffer.savedCaret = caret
        buffer.savedFirstVisibleLine = firstVisibleLine
        buffers.append(buffer)

        configureNewlyCreated(buffer, initialText: text, restoredDirty: isDirty)
        return buffer
    }

    /// After restoreBuffer calls: show the tab that was showing last time.
    func finishRestoring(activeIndex: Int) {
        delegate?.bufferStoreDidChangeBuffers(self)
        guard !buffers.isEmpty else { return }
        let index = buffers.indices.contains(activeIndex) ? activeIndex : buffers.count - 1
        activate(buffers[index])
    }

    /// Apply the document-scoped settings that then persist for this buffer's
    /// lifetime: lexer, keywords, EOL mode, indentation.
    private func configureNewlyCreated(_ buffer: Buffer, initialText: String?, restoredDirty: Bool = false) {
        withDocument(of: buffer) {
            if restoredDirty {
                // Make the empty document the save point, then put the
                // unsaved text in on top of it, so SCI_GETMODIFY says
                // modified. Scintilla has no message that marks a document
                // dirty directly. The one side effect: Undo empties the tab.
                editor.text = ""
                editor.send(ScintillaMessage.emptyUndoBuffer)
                editor.markSavePoint()
                editor.text = initialText ?? ""
            } else if let initialText {
                editor.text = initialText
            }
            editor.eolMode = buffer.lineEnding.rawValue
            editor.tabWidth = buffer.language.defaultTabWidth
            editor.useTabs = buffer.language.defaultUsesTabs

            editor.applyLanguage(buffer.language)

            if !restoredDirty {
                // A freshly loaded document is clean and has no undo history
                // worth keeping — SCI_SETSAVEPOINT makes this the baseline
                // for dirtiness.
                editor.send(ScintillaMessage.emptyUndoBuffer)
                editor.markSavePoint()
            }
            buffer.isDirty = restoredDirty
        }
    }

    // MARK: - Activation

    func activate(_ buffer: Buffer?) {
        guard activeBuffer !== buffer else {
            delegate?.bufferStore(self, didActivate: buffer)
            return
        }

        // Park the outgoing buffer's view state.
        if let outgoing = activeBuffer {
            captureViewState(into: outgoing)
        }

        activeBuffer = buffer

        guard let buffer else {
            delegate?.bufferStore(self, didActivate: nil)
            return
        }

        editor.documentPointer = buffer.documentPointer

        // Styles are per-view and style numbers are per-lexer, so the theme
        // must be re-applied for the incoming language.
        editor.applyTheme(theme, for: buffer.language)
        editor.showLineNumbers(true)

        restoreViewState(from: buffer)
        buffer.isDirty = editor.isDirty
        delegate?.bufferStore(self, didActivate: buffer)
    }

    func activateBuffer(at index: Int) {
        guard buffers.indices.contains(index) else { return }
        activate(buffers[index])
    }

    func activateNextBuffer() {
        guard let active = activeBuffer,
              let index = buffers.firstIndex(where: { $0 === active }),
              !buffers.isEmpty else { return }
        activate(buffers[(index + 1) % buffers.count])
    }

    func activatePreviousBuffer() {
        guard let active = activeBuffer,
              let index = buffers.firstIndex(where: { $0 === active }),
              !buffers.isEmpty else { return }
        activate(buffers[(index - 1 + buffers.count) % buffers.count])
    }

    /// Caret, anchor and scroll position: live from the editor for the active
    /// buffer, parked values for the others.
    func viewState(of buffer: Buffer) -> (anchor: Int, caret: Int, firstVisibleLine: Int) {
        if activeBuffer === buffer {
            return (editor.send(ScintillaMessage.getAnchor),
                    editor.currentPosition,
                    editor.send(ScintillaMessage.getFirstVisibleLine))
        }
        return (buffer.savedAnchor, buffer.savedCaret, buffer.savedFirstVisibleLine)
    }

    /// The buffer's whole text, whether or not it is on screen.
    func text(of buffer: Buffer) -> String {
        withDocument(of: buffer) { editor.text }
    }

    private func captureViewState(into buffer: Buffer) {
        buffer.savedCaret = editor.currentPosition
        buffer.savedAnchor = editor.send(ScintillaMessage.getAnchor)
        buffer.savedFirstVisibleLine = editor.send(ScintillaMessage.getFirstVisibleLine)
        buffer.isDirty = editor.isDirty
    }

    private func restoreViewState(from buffer: Buffer) {
        let limit = editor.length
        let anchor = min(max(0, buffer.savedAnchor), limit)
        let caret = min(max(0, buffer.savedCaret), limit)
        editor.setSelection(from: anchor, to: caret)
        editor.send(ScintillaMessage.setFirstVisibleLine, wparam: buffer.savedFirstVisibleLine)
        editor.scrollCaretIntoView()
    }

    /// Run `body` with `buffer`'s document temporarily selected into the view,
    /// then put the previously active document back. Needed for operations on
    /// buffers that are not on screen, such as Save All.
    ///
    /// The reference counting here is the whole difficulty, and getting it
    /// wrong crashes at launch. SCI_SETDOCPOINTER releases the document the
    /// view currently holds and *deletes it* if that was the last reference.
    /// So switching away from a document the view solely owns destroys it, and
    /// switching back afterwards dereferences freed memory — which is exactly
    /// what happened: a SIGBUS inside ScintillaCocoa::SetDocPointer on the
    /// very first newUntitledBuffer(), because the view's initial document had
    /// no other owner.
    ///
    /// Taking our own reference for the duration keeps the outgoing document
    /// alive while we are away from it.
    func withDocument<T>(of buffer: Buffer, _ body: () throws -> T) rethrows -> T {
        let previousDocument = editor.documentPointer
        let isAlreadyActive = previousDocument == buffer.documentPointer
        if isAlreadyActive {
            return try body()
        }

        var parkedState: (anchor: Int, caret: Int, firstLine: Int)?
        if let active = activeBuffer, active.documentPointer == previousDocument {
            captureViewState(into: active)
        } else {
            parkedState = (editor.send(ScintillaMessage.getAnchor), editor.currentPosition, editor.send(ScintillaMessage.getFirstVisibleLine))
        }

        // Hold the outgoing document ourselves so the switch below cannot be
        // its last reference. Released once we are back on it.
        let needsTemporaryReference = previousDocument != 0
        if needsTemporaryReference {
            editor.addRefDocument(previousDocument)
        }

        editor.documentPointer = buffer.documentPointer
        defer {
            editor.documentPointer = previousDocument
            if needsTemporaryReference {
                // The line above gave the view its own reference again, so
                // dropping ours leaves the count where it started.
                editor.releaseDocument(previousDocument)
            }
            if let parked = parkedState {
                editor.setSelection(from: parked.anchor, to: parked.caret)
                editor.send(ScintillaMessage.setFirstVisibleLine, wparam: parked.firstLine)
            } else if let active = activeBuffer {
                editor.applyTheme(theme, for: active.language)
                restoreViewState(from: active)
            }
        }
        return try body()
    }

    // MARK: - Saving

    func save(_ buffer: Buffer) throws {
        guard let url = buffer.url else { throw BufferError.noDestination }
        try write(buffer, to: url)
    }

    func saveAs(_ buffer: Buffer, to url: URL) throws {
        try write(buffer, to: url)
        buffer.url = url.standardizedFileURL

        // Re-detect the language from the new name.
        let detected = LanguageCatalog.language(for: buffer.url)
        if detected.id != buffer.language.id {
            setLanguage(detected, for: buffer)
        }
        delegate?.bufferStoreDidChangeBuffers(self)
        delegate?.bufferStore(self, didActivate: activeBuffer)
    }

    private func write(_ buffer: Buffer, to url: URL) throws {
        let text: String = withDocument(of: buffer) { editor.text }
        guard let data = buffer.encoding.encode(text) else {
            throw BufferError.couldNotEncode(buffer.encoding)
        }
        try data.write(to: url, options: .atomic)

        buffer.lastKnownModificationDate = try? url
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        withDocument(of: buffer) {
            editor.markSavePoint()
        }
        buffer.isDirty = false
        sessionObserver?.bufferWasSaved(buffer)
        delegate?.bufferStore(self, didActivate: activeBuffer)
    }

    func saveAllDirtyBuffers() -> [(Buffer, Error)] {
        var failures: [(Buffer, Error)] = []
        for buffer in buffers where buffer.isDirty && buffer.url != nil {
            do { try save(buffer) } catch { failures.append((buffer, error)) }
        }
        return failures
    }

    // MARK: - Closing

    /// Close a buffer and release its Scintilla document. The caller is
    /// responsible for having asked about unsaved changes first.
    func close(_ buffer: Buffer) {
        guard let index = buffers.firstIndex(where: { $0 === buffer }) else { return }

        let wasActive = activeBuffer === buffer
        buffers.remove(at: index)

        if wasActive {
            // The view must stop displaying the document before we drop our
            // reference, otherwise the release below is not the last one and
            // the document leaks until the view moves on.
            let replacement = buffers.indices.contains(index)
                ? buffers[index]
                : buffers.last
            activeBuffer = nil
            if let replacement {
                activate(replacement)
            } else {
                // Keep the view on a throwaway empty document rather than a
                // dangling pointer; a fresh untitled buffer follows.
                editor.documentPointer = 0
            }
        }

        editor.releaseDocument(buffer.documentPointer)
        buffer.documentPointer = 0

        sessionObserver?.bufferWasClosed(buffer)
        delegate?.bufferStoreDidChangeBuffers(self)

        if buffers.isEmpty {
            // The window always keeps at least one tab open.
            _ = try? newUntitledBuffer()
        }
    }

    func moveBuffer(from sourceIndex: Int, to destinationIndex: Int) {
        guard buffers.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= buffers.count,
              sourceIndex != destinationIndex else { return }
        let buffer = buffers.remove(at: sourceIndex)
        let adjusted = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        buffers.insert(buffer, at: min(adjusted, buffers.count))
        delegate?.bufferStoreDidChangeBuffers(self)
    }

    // MARK: - Language

    func setLanguage(_ language: Language, for buffer: Buffer) {
        buffer.language = language
        withDocument(of: buffer) {
            editor.applyLanguage(language)
        }
        if activeBuffer === buffer {
            editor.applyTheme(theme, for: language)
        }
        delegate?.bufferStore(self, didActivate: activeBuffer)
    }

    func setLineEnding(_ lineEnding: LineEnding, for buffer: Buffer) {
        buffer.lineEnding = lineEnding
        withDocument(of: buffer) {
            editor.convertAllLineEnds(to: lineEnding.rawValue)
        }
        delegate?.bufferStore(self, didActivate: activeBuffer)
    }

    func setEncoding(_ encoding: FileEncoding, for buffer: Buffer) {
        buffer.encoding = encoding
        delegate?.bufferStore(self, didActivate: activeBuffer)
    }

    /// Called from the editor delegate when Scintilla reports a change.
    func noteActiveBufferDirtyState(_ isDirty: Bool) {
        guard let active = activeBuffer, active.isDirty != isDirty else { return }
        active.isDirty = isDirty
        delegate?.bufferStore(self, didActivate: active)
    }
}

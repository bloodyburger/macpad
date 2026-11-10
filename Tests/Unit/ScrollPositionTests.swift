//
//  ScrollPositionTests.swift
//  MacPadTests
//
//  Where a tab was scrolled to is where it must still be when you come back
//  to it. The caret is often somewhere else: after typing or pasting it sits
//  at the end of the text while you scroll back up to read.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class ScrollPositionTests: XCTestCase {

    private let getXOffset = ScintillaMessage.getXOffset
    private let setXOffset = ScintillaMessage.setXOffset

    private func makeStore() -> (BufferStore, MPEditorView) {
        let editor = MPEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        return (BufferStore(editor: editor, theme: .light), editor)
    }

    private func firstVisibleLine(_ editor: MPEditorView) -> Int {
        editor.send(ScintillaMessage.getFirstVisibleLine)
    }

    func testComingBackToATabKeepsItsVerticalScrollPosition() throws {
        let (store, editor) = makeStore()
        let long = try store.newUntitledBuffer()
        editor.text = (1...400).map { "line \($0)" }.joined(separator: "\n")
        editor.setSelection(from: editor.length, to: editor.length)       // caret at the end
        editor.send(ScintillaMessage.setFirstVisibleLine, wparam: 0)      // scrolled back to the top
        XCTAssertEqual(firstVisibleLine(editor), 0)

        try store.newUntitledBuffer()   // go to another tab
        store.activate(long)            // and come back
        XCTAssertEqual(firstVisibleLine(editor), 0, "the view jumped to the caret at the end of the text")
    }

    func testComingBackToATabKeepsItsHorizontalScrollPosition() throws {
        let (store, editor) = makeStore()
        let long = try store.newUntitledBuffer()
        editor.text = String(repeating: "abcdefghij", count: 300)         // one 3,000-character line
        editor.setSelection(from: editor.length, to: editor.length)       // caret at its end
        editor.send(setXOffset, wparam: 0)                                // scrolled back to its start
        XCTAssertEqual(editor.send(getXOffset), 0)

        try store.newUntitledBuffer()
        store.activate(long)
        XCTAssertEqual(editor.send(getXOffset), 0, "the view jumped sideways to the caret at the end of the line")
    }

    /// A tab brought back from the last session opens where it was scrolled
    /// to, not at its caret.
    func testATabRestoredFromTheSessionOpensAtItsSavedScrollPosition() throws {
        let (store, editor) = makeStore()
        let text = (1...400).map { "line \($0) " + String(repeating: "x", count: 400) }.joined(separator: "\n")
        try store.restoreBuffer(url: nil, untitledNumber: 1, text: text,
                                language: LanguageCatalog.plainText, encoding: .utf8, lineEnding: .lf,
                                isDirty: true, isReadOnly: false,
                                anchor: text.utf8.count, caret: text.utf8.count,
                                firstVisibleLine: 120, xOffset: 300,
                                backupURL: nil, modificationDate: nil)
        store.finishRestoring(activeIndex: 0)
        XCTAssertEqual(firstVisibleLine(editor), 120)
        XCTAssertEqual(editor.send(getXOffset), 300)
    }

    /// The periodic backup reads the text of tabs that are not on screen. Doing
    /// so must not move the tab that is.
    func testReadingAnotherTabsTextDoesNotMoveTheTabOnScreen() throws {
        let (store, editor) = makeStore()
        let other = try store.newUntitledBuffer()
        editor.text = "other tab"
        try store.newUntitledBuffer()
        editor.text = (1...400).map { "line \($0)" }.joined(separator: "\n")
        editor.setSelection(from: editor.length, to: editor.length)
        editor.send(ScintillaMessage.setFirstVisibleLine, wparam: 0)

        XCTAssertEqual(store.text(of: other), "other tab")
        XCTAssertEqual(firstVisibleLine(editor), 0, "backing up another tab scrolled this one to its caret")
    }
}

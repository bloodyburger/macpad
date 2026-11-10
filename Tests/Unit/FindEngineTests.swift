//
//  FindEngineTests.swift
//  MacPadTests
//
//  The find bar's engine, driven headlessly through MPEditorView: every
//  search option the bar offers, checked against the text it actually
//  selects, counts, marks or replaces. SearchOptions is the real type the
//  bar fills in, so the flag translation is covered too.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class FindEngineTests: XCTestCase {

    private func makeEditor(_ text: String) -> MPEditorView {
        let editor = MPEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.text = text
        return editor
    }

    /// The text of the current target range, i.e. the last match.
    private func matched(_ editor: MPEditorView) -> String {
        let data = Data(editor.text.utf8)
        return String(decoding: data[editor.targetStart..<editor.targetEnd], as: UTF8.self)
    }

    private func find(_ editor: MPEditorView, _ options: SearchOptions,
                      from: Int = 0, to: Int? = nil) -> Int {
        editor.findText(options.effectiveSearchText, from: from, to: to ?? editor.length,
                        flags: options.scintillaFlags.rawValue)
    }

    private func count(_ editor: MPEditorView, _ options: SearchOptions) -> Int {
        editor.markAllOccurrences(of: options.effectiveSearchText,
                                  flags: options.scintillaFlags.rawValue,
                                  indicator: 9, color: .yellow)
    }

    // MARK: Normal mode

    func testPlainSearchIgnoresCaseByDefault() {
        let editor = makeEditor("Alpha beta ALPHA alpha\n")
        var options = SearchOptions()
        options.searchText = "alpha"
        XCTAssertEqual(find(editor, options), 0)
        XCTAssertEqual(matched(editor), "Alpha")
        XCTAssertEqual(count(editor, options), 3)
    }

    func testMatchCase() {
        let editor = makeEditor("Alpha beta ALPHA alpha\n")
        var options = SearchOptions()
        options.searchText = "alpha"
        options.matchCase = true
        XCTAssertEqual(find(editor, options), 17)
        XCTAssertEqual(count(editor, options), 1)
    }

    func testWholeWord() {
        let editor = makeEditor("cat concatenate cat_ cat\n")
        var options = SearchOptions()
        options.searchText = "cat"
        XCTAssertEqual(count(editor, options), 4, "without whole word, every substring counts")
        options.wholeWord = true
        XCTAssertEqual(count(editor, options), 2)
        XCTAssertEqual(find(editor, options, from: 1), 21, "skips the one inside concatenate and cat_")
    }

    func testSearchingBackwardsReturnsTheLastMatchBeforeTheCaret() {
        let editor = makeEditor("x1 x2 x3 x4\n")
        var options = SearchOptions()
        options.searchText = "x"
        // A reversed range means "search backwards" to Scintilla.
        XCTAssertEqual(find(editor, options, from: 8, to: 0), 6, "x3 is the last x before position 8")
        XCTAssertEqual(find(editor, options, from: editor.length, to: 0), 9, "wrap-around: last x in the document")
    }

    func testNoMatchReturnsMinusOneAndEmptyNeedleIsRejected() {
        let editor = makeEditor("nothing here\n")
        var options = SearchOptions()
        options.searchText = "zebra"
        XCTAssertEqual(find(editor, options), -1)
        options.searchText = ""
        XCTAssertEqual(find(editor, options), -1)
        XCTAssertEqual(count(editor, options), 0)
    }

    // MARK: Extended mode

    func testExtendedModeFindsTabsAndNewlines() {
        let editor = makeEditor("a\tb\nc\td\n")
        var options = SearchOptions()
        options.mode = .extended
        options.searchText = "\\tb\\nc"
        XCTAssertEqual(find(editor, options), 1)
        XCTAssertEqual(matched(editor), "\tb\nc")
        options.searchText = "\\x63\\t"   // "c" followed by a tab
        XCTAssertEqual(find(editor, options), 4)
    }

    // MARK: Regular expressions

    func testRegexFindsAndCapturesAcrossTheDocument() {
        let editor = makeEditor("var a=5\nvar _b=15\nlet c=7\n")
        var options = SearchOptions()
        options.mode = .regularExpression
        options.searchText = "var (\\w+)=(\\d+)"
        XCTAssertEqual(find(editor, options), 0)
        XCTAssertEqual(matched(editor), "var a=5")
        XCTAssertEqual(find(editor, options, from: 1), 8)
        XCTAssertEqual(matched(editor), "var _b=15")
        XCTAssertEqual(count(editor, options), 2)
    }

    func testRegexReplaceExpandsGroupReferences() {
        let editor = makeEditor("var a=5\n")
        var options = SearchOptions()
        options.mode = .regularExpression
        options.searchText = "var (\\w+)=(\\d+)"
        XCTAssertEqual(find(editor, options), 0)
        _ = editor.replaceTarget(withExpanded: "let $1 := \\2")
        XCTAssertEqual(editor.text, "let a := 5\n")
    }

    func testRegexDotStopsAtLineEndUnlessAsked() {
        let editor = makeEditor("start\nend\n")
        var options = SearchOptions()
        options.mode = .regularExpression
        options.searchText = "start.end"
        XCTAssertEqual(find(editor, options), -1, "dot does not match a newline by default")
        options.dotMatchesNewline = true
        XCTAssertEqual(find(editor, options), 0)
        XCTAssertEqual(matched(editor), "start\nend")
    }

    func testRegexMatchCaseIsHonoured() {
        let editor = makeEditor("Foo foo FOO\n")
        var options = SearchOptions()
        options.mode = .regularExpression
        options.searchText = "f[o]+"
        XCTAssertEqual(count(editor, options), 3)
        options.matchCase = true
        XCTAssertEqual(count(editor, options), 1)
    }

    func testBrokenRegexDoesNotCrashAndFindsNothing() {
        let editor = makeEditor("(unbalanced\n")
        var options = SearchOptions()
        options.mode = .regularExpression
        options.searchText = "("
        XCTAssertEqual(find(editor, options), -1)
        XCTAssertEqual(count(editor, options), 0)
    }

    func testZeroWidthRegexMatchesAreCountedOncePerPosition() {
        let editor = makeEditor("ab\n")
        var options = SearchOptions()
        options.mode = .regularExpression
        options.searchText = "x*"
        // Must terminate, and must count each position once: a, b, newline, end.
        XCTAssertEqual(count(editor, options), 3)
    }

    // MARK: Plain replace

    func testPlainReplaceOfTheTarget() {
        let editor = makeEditor("one two one\n")
        var options = SearchOptions()
        options.searchText = "one"
        XCTAssertEqual(find(editor, options, from: 1), 8)
        XCTAssertEqual(editor.replaceTarget(with: "1"), 1)
        XCTAssertEqual(editor.text, "one two 1\n")
    }
}

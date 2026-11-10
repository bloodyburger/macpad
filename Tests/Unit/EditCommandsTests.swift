//
//  EditCommandsTests.swift
//  MacPadTests
//
//  Every command in the Edit menu and the editor's right-click menu, driven
//  through the window controller exactly as a menu item drives it, and checked
//  against what ends up in the document, the find field and the clipboard.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class EditCommandsTests: XCTestCase {

    private var controller: EditorWindowController!
    private var sessionDirectory: URL!
    private var savedClipboard: String?

    private var editor: MPEditorView { controller.editor }

    override func setUpWithError() throws {
        // A controller reads and writes a session; keep it away from the real one.
        sessionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPadEditCommandsTests-\(UUID().uuidString)", isDirectory: true)
        setenv("MACPAD_SESSION_DIR", sessionDirectory.path, 1)
        savedClipboard = NSPasteboard.general.string(forType: .string)
        controller = EditorWindowController()
    }

    override func tearDownWithError() throws {
        controller = nil
        unsetenv("MACPAD_SESSION_DIR")
        try? FileManager.default.removeItem(at: sessionDirectory)
        NSPasteboard.general.clearContents()
        if let savedClipboard {
            NSPasteboard.general.setString(savedClipboard, forType: .string)
        }
    }

    private func setClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func chooseLanguage(_ id: String) {
        let item = NSMenuItem(title: id, action: nil, keyEquivalent: "")
        item.representedObject = id
        controller.setLanguageFromMenu(item)
    }

    private func type(_ text: String) {
        editor.insertTextAtCaret(text)
    }

    // MARK: Undo, redo

    func testUndoAndRedo() {
        type("first")
        type(" second")
        controller.undoEdit(nil)
        XCTAssertEqual(editor.text, "first")
        controller.redoEdit(nil)
        XCTAssertEqual(editor.text, "first second")
    }

    // MARK: Clipboard

    func testSelectAllCopyAndPaste() {
        type("hello")
        controller.selectAllText(nil)
        controller.copyText(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")
        editor.setSelection(from: editor.length, to: editor.length)
        controller.pasteText(nil)
        XCTAssertEqual(editor.text, "hellohello")
    }

    func testCut() {
        type("cut me")
        controller.selectAllText(nil)
        controller.cutText(nil)
        XCTAssertEqual(editor.text, "")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "cut me")
    }

    /// With the cursor in the find field, Paste, Select All and Copy belong
    /// to that field, not to the document behind it.
    func testClipboardCommandsGoToTheFindFieldWhenItHasFocus() {
        type("document text")
        controller.showFindBar(nil)   // puts the keyboard in the find field
        setClipboard("needle")
        controller.selectAllText(nil)
        controller.pasteText(nil)
        XCTAssertEqual(editor.text, "document text", "the document must not change")
        XCTAssertEqual(controller.findBar.options.searchText, "needle", "the paste belongs in the find field")

        setClipboard("something else")
        controller.selectAllText(nil)
        controller.copyText(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "needle")
    }

    // MARK: Comments

    func testToggleLineCommentCommentsThenUncomments() {
        chooseLanguage("swift")
        type("let a = 1\nlet b = 2")
        controller.selectAllText(nil)
        controller.toggleLineComment(nil)
        XCTAssertEqual(editor.text, "// let a = 1\n// let b = 2")
        controller.selectAllText(nil)
        controller.toggleLineComment(nil)
        XCTAssertEqual(editor.text, "let a = 1\nlet b = 2")
    }

    func testToggleLineCommentUsesTheLanguagesOwnMarker() {
        chooseLanguage("python")
        type("x = 1")
        controller.toggleLineComment(nil)
        XCTAssertEqual(editor.text, "# x = 1")
    }

    func testBlockCommentWrapsTheSelectionAndUncommentRemovesIt() {
        chooseLanguage("swift")
        type("let a = 1")
        controller.selectAllText(nil)
        controller.blockComment(nil)
        XCTAssertEqual(editor.text, "/*let a = 1*/")
        XCTAssertEqual(editor.selectedText, "/*let a = 1*/", "the comment stays selected")

        controller.blockUncomment(nil)
        XCTAssertEqual(editor.text, "let a = 1")

        // One undo step each.
        controller.undoEdit(nil)
        XCTAssertEqual(editor.text, "/*let a = 1*/")
    }

    func testBlockUncommentWorksWithOnlyTheInsideSelected() {
        chooseLanguage("c")
        type("/*x = 1;*/")
        editor.setSelection(from: 2, to: 8)   // just "x = 1;"
        controller.blockUncomment(nil)
        XCTAssertEqual(editor.text, "x = 1;")
    }

    func testBlockUncommentLeavesOrdinaryTextAlone() {
        chooseLanguage("c")
        type("x = 1;")
        controller.selectAllText(nil)
        controller.blockUncomment(nil)
        XCTAssertEqual(editor.text, "x = 1;")
    }

    // MARK: Delete and case

    func testDeleteRemovesTheSelectionWithoutTouchingTheClipboard() {
        setClipboard("keep me")
        type("one two")
        editor.setSelection(from: 3, to: 7)
        controller.deleteText(nil)
        XCTAssertEqual(editor.text, "one")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "keep me")
    }

    func testConvertCase() {
        type("Mixed Case")
        controller.selectAllText(nil)
        controller.convertToUppercase(nil)
        XCTAssertEqual(editor.text, "MIXED CASE")
        controller.convertToLowercase(nil)
        XCTAssertEqual(editor.text, "mixed case")
    }

    // MARK: Menu state

    private func isEnabled(_ action: Selector) -> Bool {
        controller.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
    }

    func testCommentCommandsAreGreyedOutWhereTheyWouldDoNothing() {
        // A new tab is plain text, which has no comment marker.
        type("just words")
        XCTAssertFalse(isEnabled(#selector(EditorWindowController.toggleLineComment(_:))))

        chooseLanguage("python")   // line comments only
        controller.selectAllText(nil)
        XCTAssertTrue(isEnabled(#selector(EditorWindowController.toggleLineComment(_:))))
        XCTAssertFalse(isEnabled(#selector(EditorWindowController.blockComment(_:))))

        chooseLanguage("swift")    // both kinds
        XCTAssertTrue(isEnabled(#selector(EditorWindowController.blockComment(_:))))
        editor.setSelection(from: 0, to: 0)
        XCTAssertFalse(isEnabled(#selector(EditorWindowController.blockComment(_:))),
                       "a block comment needs a selection")
    }

    func testSelectionCommandsNeedASelectionAndUndoNeedsHistory() {
        XCTAssertFalse(isEnabled(#selector(EditorWindowController.undoEdit(_:))))
        XCTAssertFalse(isEnabled(#selector(EditorWindowController.copyText(_:))))
        type("text")
        XCTAssertTrue(isEnabled(#selector(EditorWindowController.undoEdit(_:))))
        XCTAssertFalse(isEnabled(#selector(EditorWindowController.redoEdit(_:))))
        XCTAssertFalse(isEnabled(#selector(EditorWindowController.cutText(_:))))
        controller.selectAllText(nil)
        XCTAssertTrue(isEnabled(#selector(EditorWindowController.cutText(_:))))
        XCTAssertTrue(isEnabled(#selector(EditorWindowController.convertToUppercase(_:))))
        controller.undoEdit(nil)
        XCTAssertTrue(isEnabled(#selector(EditorWindowController.redoEdit(_:))))
    }

    func testLineEndingAndLanguageMenusTickTheCurrentChoice() {
        let lf = NSMenuItem(title: "Unix", action: #selector(EditorWindowController.setLineEndingFromMenu(_:)), keyEquivalent: "")
        lf.tag = LineEnding.lf.rawValue
        let crlf = NSMenuItem(title: "Windows", action: #selector(EditorWindowController.setLineEndingFromMenu(_:)), keyEquivalent: "")
        crlf.tag = LineEnding.crlf.rawValue
        _ = controller.validateMenuItem(lf); _ = controller.validateMenuItem(crlf)
        XCTAssertEqual(lf.state, .on, "new documents use LF")
        XCTAssertEqual(crlf.state, .off)
        controller.setLineEndingFromMenu(crlf)
        _ = controller.validateMenuItem(lf); _ = controller.validateMenuItem(crlf)
        XCTAssertEqual(crlf.state, .on)
        XCTAssertEqual(lf.state, .off)

        chooseLanguage("swift")
        let swift = NSMenuItem(title: "Swift", action: #selector(EditorWindowController.setLanguageFromMenu(_:)), keyEquivalent: "")
        swift.representedObject = "swift"
        _ = controller.validateMenuItem(swift)
        XCTAssertEqual(swift.state, .on)
    }

    // MARK: Right-click menu

    func testRightClickMenuOffersTheEditingCommandsAndTheControllerHandlesEachOne() throws {
        let menu = try XCTUnwrap(editor.contextMenu, "the editor has no right-click menu")
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, ["Cut", "Copy", "Paste", "Delete", "Select All",
                                "UPPERCASE", "lowercase",
                                "Toggle Line Comment", "Block Comment", "Block Uncomment",
                                "Find Selection", "Search with Google",
                                "Toggle Bookmark"])
        for item in menu.items where !item.isSeparatorItem {
            let action = try XCTUnwrap(item.action, "\(item.title) has no action")
            XCTAssertTrue(controller.responds(to: action), "nothing handles \(item.title)")
            XCTAssertNil(item.target, "\(item.title) should travel the responder chain")
        }
    }

    /// Ask the view that actually receives the click, the way AppKit does on
    /// a right-click, and check it hands back MacPad's menu, not Scintilla's.
    func testRightClickInTheTextShowsThisMenu() throws {
        func descendants(of view: NSView) -> [NSView] {
            view.subviews + view.subviews.flatMap(descendants(of:))
        }
        let textView = try XCTUnwrap(descendants(of: editor).first {
            $0.className == "SCIContentView"
        }, "could not find the view that draws the text")
        let window = try XCTUnwrap(controller.window)
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: NSPoint(x: 200, y: 200), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let shown = try XCTUnwrap(textView.menu(for: click))
        XCTAssertTrue(shown === editor.contextMenu)
    }

    func testFindSelectionPutsTheSelectedTextInTheFindField() {
        type("alpha beta alpha")
        editor.setSelection(from: 0, to: 5)
        controller.findSelection(nil)
        XCTAssertEqual(controller.findBar.options.searchText, "alpha")
    }

    func testWebSearchAddressUsesTheFirstLineOfTheSelection() throws {
        let url = try XCTUnwrap(EditorWindowController.webSearchURL(for: "  swift & regex\nsecond line"))
        XCTAssertEqual(url.host, "www.google.com")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                       "swift & regex")
        XCTAssertTrue(url.absoluteString.contains("swift%20%26%20regex"), "the text must be escaped: \(url)")
        XCTAssertNil(EditorWindowController.webSearchURL(for: "   \n"))
    }

    // MARK: Line endings

    func testLineEndingsMenuConvertsTheDocument() {
        type("one\ntwo\n")
        let item = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        item.tag = LineEnding.crlf.rawValue
        controller.setLineEndingFromMenu(item)
        XCTAssertEqual(editor.text, "one\r\ntwo\r\n")
        item.tag = LineEnding.lf.rawValue
        controller.setLineEndingFromMenu(item)
        XCTAssertEqual(editor.text, "one\ntwo\n")
    }
}

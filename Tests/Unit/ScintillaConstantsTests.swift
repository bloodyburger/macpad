//
//  ScintillaConstantsTests.swift
//  MacPadTests
//
//  The Swift layer hard-codes a few Scintilla message numbers because the
//  bridge has no typed method for them. A dependency bump could in principle
//  renumber one, which would fail silently and strangely at runtime — the
//  wrong message is still a valid message. These tests read the vendored
//  header and check the values, so the build catches it instead.
//
//  Writing this test is what caught SCI_EMPTYUNDOBUFFER being 2175 rather than
//  the 2043 originally written by hand.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class ScintillaConstantsTests: XCTestCase {

    /// Parse `#define NAME VALUE` lines out of the vendored Scintilla header.
    private static func headerConstants() throws -> [String: Int] {
        // SRCROOT is passed through as an environment variable by the test
        // target so the test can find the vendored sources.
        guard let root = ProcessInfo.processInfo.environment["MACPAD_SRCROOT"] else {
            throw XCTSkip("MACPAD_SRCROOT not set; run via Tools/build.sh test")
        }
        let header = URL(fileURLWithPath: root)
            .appendingPathComponent("Vendor/scintilla/include/Scintilla.h")

        // Reading a checkout that lives under ~/Documents can block inside
        // open(): macOS asks the test host for Documents-folder permission,
        // and every ad-hoc re-sign makes it ask again. Nobody can answer that
        // in a headless run or behind a locked screen, and the whole suite
        // hung on it. Read on another thread and skip rather than hang; CI,
        // where no such prompt exists, still performs the real check.
        let finished = DispatchGroup()
        var contents: String?
        finished.enter()
        DispatchQueue.global().async {
            contents = try? String(contentsOf: header, encoding: .utf8)
            finished.leave()
        }
        guard finished.wait(timeout: .now() + 5) == .success else {
            throw XCTSkip("Scintilla.h was not readable within 5 seconds; the test host is "
                          + "probably waiting on a Documents-folder permission prompt")
        }
        let text = try XCTUnwrap(contents, "Scintilla.h could not be read at \(header.path)")

        var constants: [String: Int] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, parts[0] == "#define" else { continue }
            let literal = String(parts[2])
            if literal.hasPrefix("0x"), let value = Int(literal.dropFirst(2), radix: 16) {
                constants[String(parts[1])] = value
            } else if let value = Int(literal) {
                constants[String(parts[1])] = value
            }
        }
        return constants
    }

    func testRawMessageNumbersMatchVendoredHeader() throws {
        let constants = try Self.headerConstants()
        XCTAssertFalse(constants.isEmpty, "parsed no constants from Scintilla.h")

        let expected: [(String, Int)] = [
            ("SCI_GETANCHOR",            ScintillaMessage.getAnchor),
            ("SCI_SETANCHOR",            ScintillaMessage.setAnchor),
            ("SCI_GETFIRSTVISIBLELINE",  ScintillaMessage.getFirstVisibleLine),
            ("SCI_EMPTYUNDOBUFFER",      ScintillaMessage.emptyUndoBuffer),
            ("SCI_SETFIRSTVISIBLELINE",  ScintillaMessage.setFirstVisibleLine),
            ("SCI_SETXOFFSET",           ScintillaMessage.setXOffset),
            ("SCI_GETXOFFSET",           ScintillaMessage.getXOffset),
        ]

        for (name, ours) in expected {
            let theirs = try XCTUnwrap(constants[name], "\(name) is missing from Scintilla.h")
            XCTAssertEqual(ours, theirs,
                           "\(name): MacPad uses \(ours), Scintilla.h says \(theirs)")
        }
    }

    /// The bridge re-exports SCFIND_* as MPSearchFlags and passes the values
    /// straight to SCI_SETSEARCHFLAGS. They were once 1, 2, 4, 8...; whole word
    /// coincided with Scintilla's 0x2 and worked, while Match Case and regular
    /// expressions were silently ignored. This pins them to the header.
    func testSearchFlagsMatchVendoredHeader() throws {
        let constants = try Self.headerConstants()
        let expected: [(String, MPSearchFlags)] = [
            ("SCFIND_WHOLEWORD",  .wholeWord),
            ("SCFIND_MATCHCASE",  .matchCase),
            ("SCFIND_WORDSTART",  .wordStart),
            ("SCFIND_REGEXP",     .regExp),
            ("SCFIND_POSIX",      .posix),
            ("SCFIND_CXX11REGEX", .cxx11RegEx),
        ]
        for (name, ours) in expected {
            let theirs = try XCTUnwrap(constants[name], "\(name) is missing from Scintilla.h")
            XCTAssertEqual(ours.rawValue, theirs,
                           "\(name): MacPad uses \(ours.rawValue), Scintilla.h says \(theirs)")
        }
    }

    func testPredefinedStyleNumbersMatchVendoredHeader() throws {
        let constants = try Self.headerConstants()
        let expected: [(String, Int)] = [
            ("STYLE_DEFAULT",         ScintillaStyle.default),
            ("STYLE_LINENUMBER",      ScintillaStyle.lineNumber),
            ("STYLE_BRACELIGHT",      ScintillaStyle.braceLight),
            ("STYLE_BRACEBAD",        ScintillaStyle.braceBad),
            ("STYLE_CONTROLCHAR",     ScintillaStyle.controlChar),
            ("STYLE_INDENTGUIDE",     ScintillaStyle.indentGuide),
            ("STYLE_CALLTIP",         ScintillaStyle.callTip),
            ("STYLE_FOLDDISPLAYTEXT", ScintillaStyle.foldDisplayText),
        ]
        for (name, ours) in expected {
            let theirs = try XCTUnwrap(constants[name], "\(name) is missing from Scintilla.h")
            XCTAssertEqual(ours, theirs,
                           "\(name): MacPad uses \(ours), Scintilla.h says \(theirs)")
        }
    }

    /// Every lexer a Language declares must actually exist in the Lexilla build.
    /// Lexilla has no java/javascript/go/swift lexer — the C family all runs
    /// through `cpp` — so this guards against a plausible mistake.
    func testEveryDeclaredLexerExists() {
        let available = Set(MPEditorView.availableLexerNames())
        XCTAssertFalse(available.isEmpty, "Lexilla reported no lexers")

        for language in LanguageCatalog.all {
            XCTAssertTrue(available.contains(language.lexer),
                          "Language “\(language.displayName)” wants lexer "
                          + "“\(language.lexer)”, which Lexilla does not provide")
        }
    }
}

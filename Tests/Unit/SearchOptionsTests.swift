//
//  SearchOptionsTests.swift
//  MacPadTests
//
//  Extended search mode escape expansion. These are pure-function tests, so
//  they pin down this part of search behaviour without an editor view.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class SearchOptionsTests: XCTestCase {

    private func expand(_ input: String) -> String {
        SearchOptions.expandExtendedEscapes(in: input)
    }

    func testSimpleEscapes() {
        XCTAssertEqual(expand("\\n"), "\n")
        XCTAssertEqual(expand("\\r"), "\r")
        XCTAssertEqual(expand("\\t"), "\t")
        XCTAssertEqual(expand("\\\\"), "\\")
        XCTAssertEqual(expand("a\\nb"), "a\nb")
        XCTAssertEqual(expand("\\r\\n"), "\r\n")
    }

    func testHexEscapes() {
        XCTAssertEqual(expand("\\x41"), "A")
        XCTAssertEqual(expand("\\x41\\x42"), "AB")
        XCTAssertEqual(expand("x\\x20y"), "x y")
    }

    func testUnicodeEscapes() {
        XCTAssertEqual(expand("\\u0041"), "A")
        XCTAssertEqual(expand("\\u00e9"), "é")
    }

    func testDecimalAndOctalEscapes() {
        XCTAssertEqual(expand("\\d065"), "A")
        XCTAssertEqual(expand("\\o0101"), "A")
    }

    /// An incomplete escape is left as literal text rather than swallowed.
    func testIncompleteEscapesArePreserved() {
        XCTAssertEqual(expand("\\x4"), "\\x4")
        XCTAssertEqual(expand("\\u00"), "\\u00")
        XCTAssertEqual(expand("\\"), "\\")
        XCTAssertEqual(expand("\\q"), "\\q")
    }

    func testTextWithoutEscapesIsUnchanged() {
        XCTAssertEqual(expand("plain text"), "plain text")
        XCTAssertEqual(expand(""), "")
    }

    /// Only Extended mode expands escapes; Normal mode must search literally.
    func testModeGatesExpansion() {
        var options = SearchOptions()
        options.searchText = "\\n"

        options.mode = .normal
        XCTAssertEqual(options.effectiveSearchText, "\\n")

        options.mode = .extended
        XCTAssertEqual(options.effectiveSearchText, "\n")

        options.mode = .regularExpression
        XCTAssertEqual(options.effectiveSearchText, "\\n",
                       "regex mode must pass the pattern through untouched")
    }

    func testFlagMapping() {
        var options = SearchOptions()
        XCTAssertTrue(options.scintillaFlags.isEmpty)

        options.matchCase = true
        XCTAssertTrue(options.scintillaFlags.contains(.matchCase))

        options.wholeWord = true
        XCTAssertTrue(options.scintillaFlags.contains(.wholeWord))

        options.mode = .regularExpression
        XCTAssertTrue(options.scintillaFlags.contains(.regExp))
    }
}

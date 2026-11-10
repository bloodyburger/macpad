//
//  LanguageCatalogTests.swift
//  MacPadTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class LanguageCatalogTests: XCTestCase {

    func testExtensionLookup() {
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "main.swift").id, "swift")
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "a.cpp").id, "cpp")
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "script.py").id, "python")
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "page.html").id, "html")
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "data.json").id, "json")
    }

    func testExtensionLookupIsCaseInsensitive() {
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "README.MD").id, "markdown")
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "Main.PY").id, "python")
    }

    /// Exact filenames must win over extensions, so that Makefile and
    /// CMakeLists.txt resolve correctly — the latter would otherwise be
    /// detected as plain text by its .txt extension.
    func testExactFileNameBeatsExtension() {
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "Makefile").id, "makefile")
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "CMakeLists.txt").id, "cmake")
    }

    func testUnknownFilesFallBackToPlainText() {
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "mystery.zzz").id, "normal")
        XCTAssertEqual(LanguageCatalog.language(forFileNamed: "noextension").id, "normal")
    }

    func testIdentifiersAreUnique() {
        let ids = LanguageCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate language id")
    }

    func testNoExtensionIsClaimedTwice() {
        var seen: [String: String] = [:]
        for language in LanguageCatalog.all {
            for ext in language.fileExtensions {
                let key = ext.lowercased()
                if let owner = seen[key] {
                    XCTFail("extension “\(key)” claimed by both \(owner) and \(language.id)")
                }
                seen[key] = language.id
            }
        }
    }

    /// The C family shares the `cpp` lexer, differing only in keyword lists.
    /// Each must actually supply keywords, or it would highlight as bare C++.
    func testCFamilyLanguagesSupplyTheirOwnKeywords() {
        let cFamily = ["c", "cpp", "csharp", "java", "javascript", "typescript", "swift", "go"]
        for id in cFamily {
            let language = LanguageCatalog.language(withID: id)
            XCTAssertNotNil(language, "missing language \(id)")
            XCTAssertEqual(language?.lexer, "cpp", "\(id) should use the cpp lexer")
            XCTAssertFalse(language?.keywordSets[0]?.isEmpty ?? true,
                           "\(id) supplies no keyword list")
        }
    }

    func testLanguagesWithCommentMarkersCanToggleComments() {
        for language in LanguageCatalog.all where language.id != "normal" {
            if language.styleRoles.isEmpty { continue }
            // Every language we style should know how to comment, block or line.
            let canComment = language.lineComment != nil || language.blockComment != nil
            if ["markdown", "diff", "json"].contains(language.id) { continue }
            XCTAssertTrue(canComment, "\(language.id) has no comment markers")
        }
    }
}

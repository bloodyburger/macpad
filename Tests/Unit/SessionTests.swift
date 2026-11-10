//
//  SessionTests.swift
//  MacPadTests
//
//  The session file and backup folder behind "quit and relaunch shows the
//  same tabs". Pure Foundation; no Scintilla involved.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class SessionTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPadSessionTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var sample: SessionFile {
        SessionFile(entries: [
            SessionEntry(filePath: "/tmp/notes/todo.md", displayName: "todo.md", untitledNumber: 0,
                         backupPath: nil, languageID: "markdown", encodingName: "UTF-8",
                         lineEnding: 2, isReadOnly: false, anchor: 10, caret: 14,
                         firstVisibleLine: 3, xOffset: 240, originalModificationTime: 1_700_000_000),
            SessionEntry(filePath: nil, displayName: "new 2", untitledNumber: 2,
                         backupPath: "/tmp/backup/new 2@ABCDEF12", languageID: "plain",
                         encodingName: "UTF-8-BOM", lineEnding: 0, isReadOnly: true,
                         anchor: 0, caret: 5, firstVisibleLine: 0, originalModificationTime: 0),
        ], activeIndex: 1)
    }

    func testSessionRoundTripsThroughXML() throws {
        let data = SessionXML.data(for: sample)
        let parsed = try XCTUnwrap(SessionXML.session(from: data))
        XCTAssertEqual(parsed, sample)
    }

    func testWritesTheDocumentedLayout() throws {
        let xml = try XCTUnwrap(String(data: SessionXML.data(for: sample), encoding: .utf8))
        XCTAssertTrue(xml.contains("<MacPad>"))
        XCTAssertTrue(xml.contains("<Session activeView=\"0\">"))
        XCTAssertTrue(xml.contains("<mainView activeIndex=\"1\">"))
        XCTAssertTrue(xml.contains("filename=\"/tmp/notes/todo.md\""))
        XCTAssertTrue(xml.contains("backupFilePath=\"/tmp/backup/new 2@ABCDEF12\""))
        XCTAssertTrue(xml.contains("startPos=\"10\" endPos=\"14\""))
    }

    /// A session file from another version: a different root element name,
    /// attributes MacPad does not know, and none of its own extra attributes.
    /// The root's name is not checked, unknown attributes are skipped, and an
    /// untitled tab's number comes from its "new N" name. This is what keeps
    /// session files written by MacPad 0.1.0 loading.
    func testReadsASessionWithAnotherRootNameAndUnknownAttributes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <OlderFormat>
            <Session activeView="0">
                <mainView activeIndex="1">
                    <File firstVisibleLine="0" xOffset="0" scrollWidth="64" startPos="3" endPos="3" selMode="0" offset="0" wrapCount="1" lang="Normal Text" encoding="-1" userReadOnly="no" filename="new 4" backupFilePath="/Users/x/Library/Application Support/MacPad/backup/new 4@2026-11-09" originalFileLastModifTimestamp="0" originalFileLastModifTimestampHigh="0" tabColourId="-1" RTL="no" mapFirstVisibleDisplayLine="-1" />
                    <File firstVisibleLine="12" xOffset="0" startPos="100" endPos="120" lang="Python" encoding="-1" userReadOnly="no" filename="/Users/x/code/app.py" backupFilePath="" originalFileLastModifTimestamp="1700000000" />
                </mainView>
                <subView activeIndex="0" />
            </Session>
        </OlderFormat>
        """
        let session = try XCTUnwrap(SessionXML.session(from: Data(xml.utf8)))
        XCTAssertEqual(session.activeIndex, 1)
        XCTAssertEqual(session.entries.count, 2)

        let untitled = session.entries[0]
        XCTAssertNil(untitled.filePath)
        XCTAssertEqual(untitled.displayName, "new 4")
        XCTAssertEqual(untitled.untitledNumber, 4)
        XCTAssertEqual(untitled.backupPath, "/Users/x/Library/Application Support/MacPad/backup/new 4@2026-11-09")
        XCTAssertEqual(untitled.caret, 3)

        let file = session.entries[1]
        XCTAssertEqual(file.filePath, "/Users/x/code/app.py")
        XCTAssertEqual(file.displayName, "app.py")
        XCTAssertNil(file.backupPath, "an empty backupFilePath means no backup")
        XCTAssertEqual(file.anchor, 100)
        XCTAssertEqual(file.caret, 120)
        XCTAssertEqual(file.firstVisibleLine, 12)
        XCTAssertEqual(file.originalModificationTime, 1_700_000_000)
    }

    func testRejectsSomethingThatIsNotASession() {
        XCTAssertNil(SessionXML.session(from: Data("<html/>".utf8)))
        XCTAssertNil(SessionXML.session(from: Data("not xml".utf8)))
    }

    func testStoreSavesAndLoads() throws {
        let store = SessionStore(directory: directory)
        XCTAssertNil(store.load(), "nothing saved yet")
        try store.save(sample)
        XCTAssertEqual(store.load(), sample)
    }

    func testBackupsAreWrittenReadAndRemoved() throws {
        let store = SessionStore(directory: directory)
        let id = UUID()
        let url = try store.writeBackup(text: "unsaved ☃ text\n", displayName: "a/b.txt", id: id)
        XCTAssertTrue(url.path.hasPrefix(store.backupDirectory.path))
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertEqual(store.readBackup(at: url.path), "unsaved ☃ text\n")

        // Writing again for the same tab replaces the same file.
        let again = try store.writeBackup(text: "newer", displayName: "a/b.txt", id: id)
        XCTAssertEqual(again, url)
        XCTAssertEqual(store.readBackup(at: url.path), "newer")

        store.removeBackup(at: url)
        XCTAssertNil(store.readBackup(at: url.path))
        store.removeBackup(at: nil)   // harmless
    }

    func testEncodingStorageNamesRoundTrip() {
        let encodings: [FileEncoding] = [.utf8, .utf8WithBOM, .utf16LittleEndianWithBOM,
                                         .utf16BigEndianWithBOM, .singleByte(.windowsCP1252),
                                         .singleByte(.isoLatin1), .singleByte(.macOSRoman)]
        for encoding in encodings {
            XCTAssertEqual(FileEncoding(storageName: encoding.storageName), encoding,
                           "\(encoding.storageName) did not round-trip")
        }
        XCTAssertNil(FileEncoding(storageName: "no-such-charset"))
    }
}

//
//  FileDropTests.swift
//  MacPadTests
//
//  Dropping files on the window opens them. Covers the pasteboard reading the
//  tab bar and content view share, and the editor's own drop path, which
//  arrives from Scintilla as an SCN_URIDROPPED notification.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class FileDropTests: XCTestCase {

    private var directory: URL!
    private var file: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPadFileDropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("dropped.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func pasteboard(with urls: [URL]) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("MacPadFileDropTests-\(UUID().uuidString)"))
        board.clearContents()
        board.writeObjects(urls as [NSURL])
        return board
    }

    func testReadsFileURLsAndSkipsFolders() {
        let board = pasteboard(with: [file, directory])
        XCTAssertEqual(FileDrop.fileURLs(on: board).map(\.standardizedFileURL),
                       [file.standardizedFileURL])
        XCTAssertEqual(FileDrop.operation(for: board), .copy)
    }

    func testRefusesADragWithNoFiles() {
        let board = NSPasteboard(name: NSPasteboard.Name("MacPadFileDropTests-text"))
        board.clearContents()
        board.setString("just text", forType: .string)
        XCTAssertTrue(FileDrop.fileURLs(on: board).isEmpty)
        XCTAssertEqual(FileDrop.operation(for: board), [])
    }

    func testTabBarForwardsDroppedFiles() {
        let bar = TabBarView(frame: .zero)
        var received: [URL] = []
        bar.onFileDrop = { received = $0 }
        XCTAssertTrue(bar.performFileDrop(from: pasteboard(with: [file])))
        XCTAssertEqual(received.map(\.standardizedFileURL), [file.standardizedFileURL])
        XCTAssertFalse(bar.performFileDrop(from: pasteboard(with: [directory])), "a folder alone is refused")
    }

    func testContentViewForwardsDroppedFiles() {
        let view = AppearanceObservingView(frame: .zero)
        var received: [URL] = []
        view.onFileDrop = { received = $0 }
        XCTAssertTrue(view.performFileDrop(from: pasteboard(with: [file])))
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(view.registeredDraggedTypes.contains(.fileURL))
    }

    /// Scintilla reports a drop on the editor itself as SCN_URIDROPPED with
    /// the path in `text`; the bridge must turn that into a delegate call.
    func testEditorReportsScintillaFileDrop() {
        final class Recorder: NSObject, MPEditorViewDelegate {
            var paths: [String] = []
            func editor(_ editor: MPEditorView, didDropFileAtPath path: String) { paths.append(path) }
        }
        let editor = MPEditorView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let recorder = Recorder()
        editor.delegate = recorder

        editor.deliverDroppedFileNotification(forTesting: file.path)
        XCTAssertEqual(recorder.paths, [file.path])
    }
}

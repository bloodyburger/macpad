//
//  InstallGuardTests.swift
//  MacPadTests
//
//  The decisions behind "you are running from a disk image" and "eject the
//  leftover images", on made-up folders so no real volume or Applications
//  folder is touched.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class InstallGuardTests: XCTestCase {

    private var root: URL!
    private let files = FileManager.default

    override func setUpWithError() throws {
        root = files.temporaryDirectory.appendingPathComponent("MacPadInstallGuardTests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? files.removeItem(at: root)
    }

    /// Make a folder that looks like a mounted image: an app and, when asked,
    /// the Applications shortcut MacPad's images carry.
    @discardableResult
    private func makeVolume(_ name: String, app: String = "MacPad.app", shortcut: Bool = true) throws -> URL {
        let volume = root.appendingPathComponent("Volumes/\(name)", isDirectory: true)
        try files.createDirectory(at: volume.appendingPathComponent("\(app)/Contents"), withIntermediateDirectories: true)
        if shortcut {
            try files.createSymbolicLink(at: volume.appendingPathComponent("Applications"),
                                         withDestinationURL: URL(fileURLWithPath: "/Applications"))
        }
        return volume
    }

    // MARK: Where is this copy running from?

    func testRecognisesACopyRunningFromADiskImage() {
        XCTAssertTrue(InstallGuard.isOnDiskImage(bundlePath: "/Volumes/MacPad 0.1.3/MacPad.app", volumeIsReadOnly: true))
        XCTAssertTrue(InstallGuard.isOnDiskImage(
            bundlePath: "/private/var/folders/ab/T/AppTranslocation/1234-ABCD/d/MacPad.app", volumeIsReadOnly: true),
            "a freshly downloaded app runs from a private copy of its image")
    }

    func testDoesNotMistakeOrdinaryPlacesForADiskImage() {
        XCTAssertFalse(InstallGuard.isOnDiskImage(bundlePath: "/Applications/MacPad.app", volumeIsReadOnly: false))
        XCTAssertFalse(InstallGuard.isOnDiskImage(bundlePath: "/Users/me/Applications/MacPad.app", volumeIsReadOnly: false))
        XCTAssertFalse(InstallGuard.isOnDiskImage(bundlePath: "/Volumes/External SSD/Apps/MacPad.app", volumeIsReadOnly: false),
                       "a writable external drive is a fine place to keep an app")
    }

    func testKnowsWhenItIsInstalled() {
        let home = URL(fileURLWithPath: "/Users/me")
        let folders = InstallGuard.applicationsDirectories(environment: [:], homeDirectory: home)
        XCTAssertEqual(folders.map(\.path), ["/Applications", "/Users/me/Applications"])
        XCTAssertTrue(InstallGuard.isInstalled(bundlePath: "/Applications/MacPad.app", applicationsDirectories: folders))
        XCTAssertTrue(InstallGuard.isInstalled(bundlePath: "/Users/me/Applications/MacPad.app", applicationsDirectories: folders))
        XCTAssertFalse(InstallGuard.isInstalled(bundlePath: "/Users/me/code/build/Debug/MacPad.app", applicationsDirectories: folders),
                       "a development build must not eject anyone's images")
        XCTAssertFalse(InstallGuard.isInstalled(bundlePath: "/Volumes/MacPad/MacPad.app", applicationsDirectories: folders))

        let overridden = InstallGuard.applicationsDirectories(
            environment: [InstallGuard.applicationsOverrideKey: "/tmp/sandbox"], homeDirectory: home)
        XCTAssertEqual(overridden.map(\.path), ["/tmp/sandbox"])
    }

    // MARK: Which mounted images are MacPad's?

    func testFindsOnlyMacPadsOwnImages() throws {
        try makeVolume("MacPad")
        try makeVolume("MacPad 0.1.3")
        try makeVolume("MacPad 2")
        try makeVolume("MacPadding", shortcut: true)             // another product
        try makeVolume("MacPad Backups", app: "Notes.app")        // no MacPad.app inside
        try makeVolume("MacPad Drive", shortcut: false)           // no Applications shortcut: not an installer image
        try makeVolume("Macintosh HD")

        let found = InstallGuard.installerVolumes(in: root.appendingPathComponent("Volumes"),
                                                  excludingBundlePath: "/Applications/MacPad.app")
        XCTAssertEqual(found.map(\.lastPathComponent), ["MacPad", "MacPad 0.1.3", "MacPad 2"])
    }

    func testNeverListsTheImageThisCopyIsRunningFrom() throws {
        let own = try makeVolume("MacPad 0.1.3")
        try makeVolume("MacPad")
        let found = InstallGuard.installerVolumes(in: root.appendingPathComponent("Volumes"),
                                                  excludingBundlePath: own.appendingPathComponent("MacPad.app").path)
        XCTAssertEqual(found.map(\.lastPathComponent), ["MacPad"])
    }

    // MARK: Installing

    func testInstallCopiesTheAppAndReplacesAnOlderCopy() throws {
        let source = try makeVolume("MacPad 0.1.3").appendingPathComponent("MacPad.app")
        try "new".write(to: source.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)

        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let existing = applications.appendingPathComponent("MacPad.app/Contents", isDirectory: true)
        try files.createDirectory(at: existing, withIntermediateDirectories: true)
        try "old".write(to: existing.appendingPathComponent("marker"), atomically: true, encoding: .utf8)

        var replaced: [String] = []
        let destination = try InstallGuard.install(bundle: source, into: applications) { old in
            replaced.append(old.lastPathComponent)
            try self.files.removeItem(at: old)
        }
        XCTAssertEqual(destination.path, applications.appendingPathComponent("MacPad.app").path)
        XCTAssertEqual(replaced, ["MacPad.app"])
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Contents/marker"), encoding: .utf8), "new")
        XCTAssertTrue(files.fileExists(atPath: source.path), "the copy on the image is left alone")
    }

    func testInstallIntoAnEmptyFolderDoesNotAskToReplaceAnything() throws {
        let source = try makeVolume("MacPad").appendingPathComponent("MacPad.app")
        let applications = root.appendingPathComponent("Fresh/Applications", isDirectory: true)
        try InstallGuard.install(bundle: source, into: applications) { _ in
            XCTFail("there was nothing to replace")
        }
        XCTAssertTrue(files.fileExists(atPath: applications.appendingPathComponent("MacPad.app").path))
    }
}

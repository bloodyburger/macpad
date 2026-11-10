//
//  UpdateCheckerTests.swift
//  MacPadTests
//
//  Check for Updates without a network: version comparison, both feed
//  formats, the once-a-day rule, skipping a version, and the outcomes.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class UpdateCheckerTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "MacPadUpdateCheckerTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private struct CannedFetcher: UpdateFeedFetching {
        let result: Result<Data, UpdateCheckError>
        func fetch(_ url: URL, completion: @escaping (Result<Data, UpdateCheckError>) -> Void) {
            completion(result)
        }
    }

    private func checker(current: String, feed: Result<Data, UpdateCheckError>) -> UpdateChecker {
        UpdateChecker(feedURL: URL(string: "https://example.test/feed.json")!,
                      currentVersion: AppVersion(current)!,
                      defaults: defaults,
                      fetcher: CannedFetcher(result: feed))
    }

    private func run(_ checker: UpdateChecker) throws -> Result<UpdateCheckOutcome, UpdateCheckError> {
        let done = expectation(description: "check")
        var outcome: Result<UpdateCheckOutcome, UpdateCheckError>?
        checker.check { outcome = $0; done.fulfill() }
        wait(for: [done], timeout: 2)
        return try XCTUnwrap(outcome)
    }

    // MARK: Versions

    func testVersionsCompareNumerically() {
        XCTAssertLessThan(AppVersion("0.1.0")!, AppVersion("0.2.0")!)
        XCTAssertLessThan(AppVersion("0.9")!, AppVersion("0.10")!, "10 is more than 9, not less")
        XCTAssertLessThan(AppVersion("1.2.3")!, AppVersion("v1.3")!)
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertEqual(AppVersion("v2.1.0-beta.1")!, AppVersion("2.1.0")!, "pre-release tags are ignored")
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
    }

    // MARK: Feeds

    func testReadsMacPadsOwnAppcast() throws {
        let json = """
        {"version": "0.2.0", "url": "https://example.test/macpad",
         "download": "https://example.test/MacPad-0.2.0.dmg", "notes": "Faster search."}
        """
        let release = try XCTUnwrap(UpdateFeed.release(from: Data(json.utf8)))
        XCTAssertEqual(release.version, AppVersion("0.2.0"))
        XCTAssertEqual(release.pageURL.absoluteString, "https://example.test/macpad")
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://example.test/MacPad-0.2.0.dmg")
        XCTAssertEqual(release.notes, "Faster search.")
    }

    func testReadsAGitHubLatestRelease() throws {
        let json = """
        {"tag_name": "v0.3.1", "name": "MacPad 0.3.1",
         "html_url": "https://github.com/example/macpad/releases/tag/v0.3.1",
         "body": "Bug fixes.",
         "assets": [
           {"name": "checksums.txt", "browser_download_url": "https://github.com/example/macpad/releases/download/v0.3.1/checksums.txt"},
           {"name": "MacPad-0.3.1.dmg", "browser_download_url": "https://github.com/example/macpad/releases/download/v0.3.1/MacPad-0.3.1.dmg"}
         ]}
        """
        let release = try XCTUnwrap(UpdateFeed.release(from: Data(json.utf8)))
        XCTAssertEqual(release.version, AppVersion("0.3.1"))
        XCTAssertTrue(release.pageURL.absoluteString.hasSuffix("/releases/tag/v0.3.1"))
        XCTAssertTrue(release.downloadURL?.absoluteString.hasSuffix("MacPad-0.3.1.dmg") == true,
                      "the .dmg asset is chosen, not the first asset")
        XCTAssertEqual(release.notes, "Bug fixes.")
    }

    func testRejectsThingsThatAreNotAFeed() {
        XCTAssertNil(UpdateFeed.release(from: Data("<html/>".utf8)))
        XCTAssertNil(UpdateFeed.release(from: Data("{\"message\": \"Not Found\"}".utf8)))
        XCTAssertNil(UpdateFeed.release(from: Data("{\"version\": \"abc\", \"url\": \"https://x.test\"}".utf8)))
    }

    // MARK: Outcomes

    private var newer: Data {
        Data("""
        {"version": "0.2.0", "url": "https://example.test/macpad", "notes": ""}
        """.utf8)
    }

    func testNewerReleaseIsAvailable() throws {
        let result = try run(checker(current: "0.1.0", feed: .success(newer)))
        guard case .success(.available(let release)) = result else {
            return XCTFail("expected an available update, got \(result)")
        }
        XCTAssertEqual(release.version, AppVersion("0.2.0"))
    }

    func testSameOrOlderReleaseMeansUpToDate() throws {
        XCTAssertEqual(try run(checker(current: "0.2.0", feed: .success(newer))), .success(.upToDate))
        XCTAssertEqual(try run(checker(current: "1.0", feed: .success(newer))), .success(.upToDate))
    }

    func testSkippedVersionIsReportedAsSkipped() throws {
        let checker = checker(current: "0.1.0", feed: .success(newer))
        let first = try run(checker)
        guard case .success(.available(let release)) = first else { return XCTFail("\(first)") }
        checker.skip(release)
        guard case .success(.skipped(let again)) = try run(checker) else { return XCTFail("expected skipped") }
        XCTAssertEqual(again.version, release.version)
    }

    func testErrorsAreReported() throws {
        XCTAssertEqual(try run(checker(current: "0.1.0", feed: .failure(.httpStatus(404)))),
                       .failure(.httpStatus(404)))
        XCTAssertEqual(try run(checker(current: "0.1.0", feed: .success(Data("nope".utf8)))),
                       .failure(.unreadableFeed))
        XCTAssertEqual(UpdateCheckError.httpStatus(404).errorDescription, "No release has been published yet.")
    }

    // MARK: Once a day

    func testAutomaticCheckIsDueOncePerDayAndCanBeTurnedOff() throws {
        let checker = checker(current: "0.1.0", feed: .success(newer))
        XCTAssertTrue(checker.isAutomaticCheckDue(), "never checked: due")
        _ = try run(checker)
        XCTAssertNotNil(checker.lastCheck)
        XCTAssertFalse(checker.isAutomaticCheckDue(), "just checked: not due")
        XCTAssertTrue(checker.isAutomaticCheckDue(now: Date().addingTimeInterval(25 * 60 * 60)), "a day later: due")

        checker.automaticChecksEnabled = false
        XCTAssertFalse(checker.isAutomaticCheckDue(now: Date().addingTimeInterval(48 * 60 * 60)))
    }
}

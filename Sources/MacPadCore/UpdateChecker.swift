//
//  UpdateChecker.swift
//  MacPad
//
//  Finds out whether a newer MacPad has been released.
//
//  The checker downloads one small JSON document, the "feed", reads the
//  newest version from it and compares it with the running app. The feed is
//  either GitHub's "latest release" API answer or MacPad's own appcast, a
//  file with "version", "url", "download" and "notes" fields that can be
//  hosted on any website. Which one is used comes from the bundle's
//  MacPadUpdateFeedURL setting.
//
//  This file has no user interface; UpdateController in MacPadApp shows the
//  alerts. Keeping the logic here lets the tests cover version comparison,
//  feed parsing and the once-a-day rule without a network.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// MARK: - Versions

/// A release version such as "0.1.0" or "v1.2", compared number by number.
/// Anything after a "-" or "+" (a pre-release or build tag) is ignored.
struct AppVersion: Equatable, Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        var core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if core.hasPrefix("v") || core.hasPrefix("V") { core.removeFirst() }
        if let cut = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = String(core[..<cut])
        }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.map { $0! }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

// MARK: - The feed

/// What the feed says about the newest release.
struct UpdateRelease: Equatable {
    let version: AppVersion
    /// Where a person can read about it: the release page.
    let pageURL: URL
    /// The disk image itself, when the feed names one.
    let downloadURL: URL?
    /// Release notes, plain text or Markdown; may be empty.
    let notes: String
}

enum UpdateFeed {

    /// Read a release out of either feed format. Nil when the data is not a
    /// feed MacPad understands.
    static func release(from data: Data) -> UpdateRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else { return nil }
        return ownAppcast(json) ?? gitHubRelease(json)
    }

    /// MacPad's own format:
    /// {"version": "0.2.0", "url": "https://…/macpad", "download": "https://…/MacPad-0.2.0.dmg", "notes": "…"}
    private static func ownAppcast(_ json: [String: Any]) -> UpdateRelease? {
        guard let versionText = json["version"] as? String,
              let version = AppVersion(versionText),
              let page = (json["url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let download = (json["download"] as? String).flatMap(URL.init(string:))
        return UpdateRelease(version: version, pageURL: page, downloadURL: download,
                             notes: json["notes"] as? String ?? "")
    }

    /// GitHub's /repos/{owner}/{repo}/releases/latest answer. The version is
    /// the tag; the download is the first .dmg among the assets.
    private static func gitHubRelease(_ json: [String: Any]) -> UpdateRelease? {
        guard let tag = json["tag_name"] as? String,
              let version = AppVersion(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let download = assets
            .compactMap { $0["browser_download_url"] as? String }
            .first { $0.lowercased().hasSuffix(".dmg") }
            .flatMap(URL.init(string:))
        return UpdateRelease(version: version, pageURL: page, downloadURL: download,
                             notes: json["body"] as? String ?? "")
    }
}

// MARK: - Fetching

enum UpdateCheckError: LocalizedError, Equatable {
    case network(String)
    /// The server answered, but not with a release: 404 when nothing has been
    /// published yet, or any other non-success status.
    case httpStatus(Int)
    case unreadableFeed

    var errorDescription: String? {
        switch self {
        case .network(let message): return "MacPad could not reach the update server. \(message)"
        case .httpStatus(404):      return "No release has been published yet."
        case .httpStatus(let code): return "The update server answered with status \(code)."
        case .unreadableFeed:       return "The update information could not be read."
        }
    }

    static func == (lhs: UpdateCheckError, rhs: UpdateCheckError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

/// Fetches the feed. A protocol so tests can hand in canned answers.
protocol UpdateFeedFetching {
    func fetch(_ url: URL, completion: @escaping (Result<Data, UpdateCheckError>) -> Void)
}

struct URLSessionFeedFetcher: UpdateFeedFetching {
    func fetch(_ url: URL, completion: @escaping (Result<Data, UpdateCheckError>) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json, application/json", forHTTPHeaderField: "Accept")
        request.setValue("MacPad/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(.httpStatus(http.statusCode)))
                return
            }
            completion(.success(data ?? Data()))
        }.resume()
    }
}

// MARK: - The check

enum UpdateCheckOutcome: Equatable {
    /// The running version is the newest, or newer than the feed's.
    case upToDate
    /// A newer release exists.
    case available(UpdateRelease)
    /// A newer release exists but the user asked not to be told about it.
    case skipped(UpdateRelease)
}

final class UpdateChecker {

    static let automaticChecksKey = "AutomaticUpdateChecks"
    static let lastCheckKey = "LastUpdateCheck"
    static let skippedVersionKey = "SkippedUpdateVersion"
    /// Automatic checks happen at most this often.
    static let automaticInterval: TimeInterval = 24 * 60 * 60

    let feedURL: URL
    let currentVersion: AppVersion
    private let defaults: UserDefaults
    private let fetcher: UpdateFeedFetching

    init(feedURL: URL,
         currentVersion: AppVersion,
         defaults: UserDefaults = .standard,
         fetcher: UpdateFeedFetching = URLSessionFeedFetcher()) {
        self.feedURL = feedURL
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.fetcher = fetcher
    }

    /// On unless the user turned it off. MACPAD_NO_UPDATE_CHECK=1 also turns
    /// it off, for test runs and CI.
    var automaticChecksEnabled: Bool {
        get {
            if ProcessInfo.processInfo.environment["MACPAD_NO_UPDATE_CHECK"] == "1" { return false }
            return defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: Self.automaticChecksKey) }
    }

    var lastCheck: Date? { defaults.object(forKey: Self.lastCheckKey) as? Date }

    var skippedVersion: AppVersion? {
        (defaults.string(forKey: Self.skippedVersionKey)).flatMap(AppVersion.init)
    }

    /// Remember not to mention this release again at launch. A manual check
    /// still reports it.
    func skip(_ release: UpdateRelease) {
        defaults.set(release.version.description, forKey: Self.skippedVersionKey)
    }

    /// Whether a launch-time check is due: automatic checks are on and the
    /// last one is older than a day.
    func isAutomaticCheckDue(now: Date = Date()) -> Bool {
        guard automaticChecksEnabled else { return false }
        guard let last = lastCheck else { return true }
        return now.timeIntervalSince(last) >= Self.automaticInterval
    }

    /// Compare what the feed says with what is running.
    static func outcome(current: AppVersion, release: UpdateRelease, skipped: AppVersion?) -> UpdateCheckOutcome {
        guard current < release.version else { return .upToDate }
        if let skipped, skipped == release.version { return .skipped(release) }
        return .available(release)
    }

    /// Fetch the feed and report. The completion runs on the main thread.
    func check(completion: @escaping (Result<UpdateCheckOutcome, UpdateCheckError>) -> Void) {
        fetcher.fetch(feedURL) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let data):
                    guard let release = UpdateFeed.release(from: data) else {
                        completion(.failure(.unreadableFeed))
                        return
                    }
                    self.defaults.set(Date(), forKey: Self.lastCheckKey)
                    completion(.success(Self.outcome(current: self.currentVersion,
                                                     release: release,
                                                     skipped: self.skippedVersion)))
                }
            }
        }
    }
}

//
//  UpdateController.swift
//  MacPad
//
//  The user-facing side of update checking: the menu command, the quiet
//  check at launch, and the alerts. The decisions live in UpdateChecker.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

final class UpdateController {

    /// Info.plist key naming the feed. Defaults to this project's GitHub
    /// releases; point it at your own appcast JSON to host updates yourself.
    static let feedURLInfoKey = "MacPadUpdateFeedURL"
    static let fallbackFeed = URL(string: "https://api.github.com/repos/bloodyburger/macpad/releases/latest")!

    private let checker: UpdateChecker
    private var isChecking = false

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = ProcessInfo.processInfo.environment["MACPAD_UPDATE_FEED"].flatMap(URL.init(string:))
            ?? (info[Self.feedURLInfoKey] as? String).flatMap(URL.init(string:))
            ?? Self.fallbackFeed
        let version = AppVersion(info["CFBundleShortVersionString"] as? String ?? "0") ?? AppVersion("0")!
        checker = UpdateChecker(feedURL: feed, currentVersion: version)
    }

    /// Check once a day, a few seconds after launch so the window is up first.
    /// Only a newer, unskipped release produces any alert.
    func scheduleLaunchCheck() {
        // Never while the unit tests are hosted in the app: a modal alert on
        // the main thread would stall the whole test run.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard checker.isAutomaticCheckDue() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.check(userInitiated: false)
        }
    }

    /// The menu command: always reports, including "up to date" and errors.
    func checkForUpdates() {
        check(userInitiated: true)
    }

    private func check(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true
        checker.check { [weak self] result in
            guard let self else { return }
            self.isChecking = false
            switch result {
            case .success(.available(let release)):
                self.offer(release)
            case .success(.skipped(let release)):
                if userInitiated { self.offer(release) }
            case .success(.upToDate):
                if userInitiated { self.reportUpToDate() }
            case .failure(let error):
                if userInitiated { self.report(error) }
            }
        }
    }

    // MARK: - Alerts

    private func offer(_ release: UpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "MacPad \(release.version) is available."
        var details = "You have MacPad \(checker.currentVersion)."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            details += "\n\n" + String(notes.prefix(600))
        }
        alert.informativeText = details
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
        case .alertThirdButtonReturn:
            checker.skip(release)
        default:
            break
        }
    }

    private func reportUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You’re up to date."
        alert.informativeText = "MacPad \(checker.currentVersion) is the newest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func report(_ error: UpdateCheckError) {
        let alert = NSAlert()
        alert.messageText = "Could not check for updates."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

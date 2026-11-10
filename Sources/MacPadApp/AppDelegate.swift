//
//  AppDelegate.swift
//  MacPad
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: EditorWindowController?
    private let updates = UpdateController()

    /// Files handed to us before the app finished launching, e.g. by opening
    /// MacPad via a double-clicked file.
    private var pendingURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = EditorWindowController()
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        for url in pendingURLs {
            controller.open(url: url)
        }
        pendingURLs.removeAll()

        updates.scheduleLaunchCheck()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updates.checkForUpdates()
    }

    // MARK: - Opening files

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller = windowController else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls {
            controller.open(url: url)
        }
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openRecentDocument(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let url = item.representedObject as? URL else { return }
        windowController?.open(url: url)
    }

    @objc func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    // MARK: - Lifecycle

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = windowController else { return .terminateNow }
        return controller.prepareToTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Last chance to record the tabs and their unsaved text.
        windowController?.snapshotSession()
    }

    /// A text editor with no window open is not useful; reopen one.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
            windowController?.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu actions owned by the app

    @objc func showSettings(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Settings are not implemented yet."
        alert.informativeText = """
            Preferences arrive in a later milestone, with panels for \
            editing, appearance, languages, search and backup. See \
            docs/PLAN.md.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "MacPad \(Self.versionString)"
        alert.informativeText = """
            A native text and code editor for macOS, built on Scintilla and \
            Lexilla.

            This is an early build covering the M0–M1 ground: tabs, syntax \
            highlighting, find and replace, encodings and line endings. \
            docs/FEATURES.md tracks what is done and what is planned, \
            feature by feature.

            MacPad is free software under the GNU GPL v3 or later.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

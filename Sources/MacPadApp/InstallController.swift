//
//  InstallController.swift
//  MacPad
//
//  The launch-time side of InstallGuard: the "you are running from a disk
//  image" alert, the move to Applications, and ejecting leftover images.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

final class InstallController {

    private let environment = ProcessInfo.processInfo.environment
    private let bundleURL = Bundle.main.bundleURL

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var applicationsDirectories: [URL] {
        InstallGuard.applicationsDirectories(environment: environment,
                                             homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    private var isOnDiskImage: Bool {
        let readOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return InstallGuard.isOnDiskImage(bundlePath: bundleURL.path, volumeIsReadOnly: readOnly)
    }

    /// Run once the window is up. `saveSession` writes the open tabs and
    /// unsaved text to disk, so a moved copy picks up exactly where this one
    /// left off.
    func runLaunchChecks(saveSession: @escaping () -> Void) {
        // Never while the unit tests are hosted in the app.
        guard environment["XCTestConfigurationFilePath"] == nil else { return }

        if isOnDiskImage {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.offerToMove(saveSession: saveSession)
            }
        } else if InstallGuard.isInstalled(bundlePath: bundleURL.path,
                                           applicationsDirectories: applicationsDirectories) {
            // Twice: the copy that was just moved out of an image may still be
            // quitting on the first pass, which keeps its image busy.
            for delay in [2.0, 8.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.ejectInstallerImages()
                }
            }
        }
    }

    // MARK: - Leftover images

    private func ejectInstallerImages() {
        let volumes = InstallGuard.installerVolumes(in: URL(fileURLWithPath: "/Volumes", isDirectory: true),
                                                    excludingBundlePath: bundleURL.path)
        for volume in volumes {
            // A busy image simply stays mounted; there is nothing to report.
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }
    }

    // MARK: - Moving to Applications

    private func offerToMove(saveSession: @escaping () -> Void) {
        // MACPAD_INSTALL_CHOICE=move or skip answers for the alert, so an
        // automated check can run this path without a person to click.
        let scripted = environment["MACPAD_INSTALL_CHOICE"]
        let wantsMove: Bool
        if let scripted {
            wantsMove = scripted == "move"
        } else {
            let alert = NSAlert()
            alert.messageText = "MacPad is running from its disk image."
            alert.informativeText = """
                This is MacPad \(version). To install it, move it to your Applications \
                folder. If an older MacPad is already there, it goes to the Trash.

                Until you do, this copy only works while the disk image is open.
                """
            alert.addButton(withTitle: "Move to Applications")
            alert.addButton(withTitle: "Not Now")
            wantsMove = alert.runModal() == .alertFirstButtonReturn
        }
        guard wantsMove else { return }
        moveToApplications(saveSession: saveSession)
    }

    private func moveToApplications(saveSession: @escaping () -> Void) {
        // Two copies running at once would both write the same session files.
        let identifier = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard others.isEmpty else {
            report("Another copy of MacPad is open.",
                   "Quit the other MacPad, then open this one again and choose Move to Applications.")
            return
        }

        let destination: URL
        do {
            destination = try InstallGuard.install(bundle: bundleURL, into: applicationsDirectories[0]) { old in
                try FileManager.default.trashItem(at: old, resultingItemURL: nil)
            }
        } catch {
            report("MacPad could not be moved to Applications.",
                   "\(error.localizedDescription)\n\nYou can drag MacPad from the disk image to Applications yourself.")
            return
        }

        // The copy carries the "downloaded from the internet" mark of the
        // image it came from. This copy has already been approved to run, so
        // clear the mark; otherwise macOS would block the moved copy and ask
        // for the same approval a second time.
        let clear = Process()
        clear.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        clear.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? clear.run()
        clear.waitUntilExit()

        saveSession()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        // Pass MacPad's own switches on, so a scripted check stays in its sandbox.
        configuration.environment = environment.filter { $0.key.hasPrefix("MACPAD_") && $0.key != "MACPAD_INSTALL_CHOICE" }
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.report("MacPad was copied to Applications but could not be opened from there.",
                                 error.localizedDescription)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func report(_ message: String, _ details: String) {
        guard environment["MACPAD_INSTALL_CHOICE"] == nil else {
            FileHandle.standardError.write(Data("MacPad install: \(message) \(details)\n".utf8))
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

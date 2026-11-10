//
//  InstallGuard.swift
//  MacPad
//
//  Keeps people out of a trap that a drag-to-Applications disk image sets.
//
//  A disk image runs no code when it is opened, so nothing can tidy up at
//  install time. Old images stay mounted, every one of them shows as "MacPad"
//  in the Finder, and it is easy to open a stale copy straight from an old
//  image and wonder why the version is wrong. The app is the only thing that
//  can help, so it does two things at launch:
//
//    * Running from a disk image: it says so, names its version, and offers
//      to move itself to Applications.
//    * Running from Applications: it ejects any MacPad disk images that are
//      still mounted.
//
//  This file holds the decisions, with no user interface, so they can be
//  tested. InstallController in MacPadApp shows the alert and does the move.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum InstallGuard {

    /// Environment override for the folder MacPad installs into. Used by
    /// automated checks so they never touch the real Applications folder.
    static let applicationsOverrideKey = "MACPAD_APPLICATIONS_DIR"

    /// Whether an app at this path is running from a disk image rather than
    /// from where it was installed.
    ///
    /// Two shapes: macOS runs a freshly downloaded app from a private,
    /// randomised copy of its disk image (the path then contains
    /// "AppTranslocation"); otherwise the app sits on a read-only volume under
    /// /Volumes. A writable volume there is an ordinary external drive, where
    /// keeping apps is legitimate.
    static func isOnDiskImage(bundlePath: String, volumeIsReadOnly: Bool) -> Bool {
        if bundlePath.contains("/AppTranslocation/") { return true }
        return bundlePath.hasPrefix("/Volumes/") && volumeIsReadOnly
    }

    /// The folders that count as installed locations: the override alone when
    /// set, otherwise the system and the per-user Applications folders.
    static func applicationsDirectories(environment: [String: String],
                                        homeDirectory: URL) -> [URL] {
        if let override = environment[applicationsOverrideKey], !override.isEmpty {
            return [URL(fileURLWithPath: override, isDirectory: true)]
        }
        return [URL(fileURLWithPath: "/Applications", isDirectory: true),
                homeDirectory.appendingPathComponent("Applications", isDirectory: true)]
    }

    /// Whether the app at this path sits directly in one of those folders.
    static func isInstalled(bundlePath: String, applicationsDirectories: [URL]) -> Bool {
        let parent = URL(fileURLWithPath: bundlePath).deletingLastPathComponent().standardizedFileURL.path
        return applicationsDirectories.contains { $0.standardizedFileURL.path == parent }
    }

    /// Mounted MacPad disk images: volumes named "MacPad" or "MacPad <anything>"
    /// that hold MacPad.app beside an Applications shortcut, which is the
    /// layout of MacPad's own images and nothing else's. The volume this copy
    /// of the app is itself running from is left out.
    static func installerVolumes(in volumesDirectory: URL,
                                 excludingBundlePath bundlePath: String,
                                 fileManager: FileManager = .default) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: volumesDirectory.path)) ?? []
        return names.sorted().compactMap { name in
            guard name == "MacPad" || name.hasPrefix("MacPad ") else { return nil }
            let volume = volumesDirectory.appendingPathComponent(name, isDirectory: true)
            let app = volume.appendingPathComponent("MacPad.app").path
            let shortcut = volume.appendingPathComponent("Applications").path
            guard fileManager.fileExists(atPath: app),
                  (try? fileManager.attributesOfItem(atPath: shortcut)) != nil else { return nil }
            guard !bundlePath.hasPrefix(volume.path + "/") else { return nil }
            return volume
        }
    }

    /// Copy the app into an Applications folder, replacing a copy already
    /// there. `replaceExisting` disposes of the old copy; the app passes one
    /// that moves it to the Trash, so nothing is destroyed. Returns where the
    /// new copy is.
    @discardableResult
    static func install(bundle: URL,
                        into applicationsDirectory: URL,
                        fileManager: FileManager = .default,
                        replaceExisting: (URL) throws -> Void) throws -> URL {
        try fileManager.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
        let destination = applicationsDirectory.appendingPathComponent(bundle.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try replaceExisting(destination)
        }
        try fileManager.copyItem(at: bundle, to: destination)
        return destination
    }
}

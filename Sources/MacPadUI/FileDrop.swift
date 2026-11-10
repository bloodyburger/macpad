//
//  FileDrop.swift
//  MacPad
//
//  Dropping files anywhere on the window opens them in tabs.
//
//  Three surfaces take drops. The editor's own Scintilla view accepts file
//  drags already and reports each file through SCN_URIDROPPED, which
//  MPEditorView turns into editor(_:didDropFileAtPath:). The tab bar and the
//  window's content view are plain NSViews, so they use the helper below and
//  hand the URLs to the same place.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

enum FileDrop {

    static let acceptedTypes: [NSPasteboard.PasteboardType] = [.fileURL]

    /// The regular files on the pasteboard, in drop order. Folders and
    /// anything that is not a file URL are left out.
    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return []
        }
        return urls.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
    }

    /// The operation to offer while a drag hovers: copy when it carries at
    /// least one file, nothing otherwise so the cursor shows it is refused.
    static func operation(for pasteboard: NSPasteboard) -> NSDragOperation {
        fileURLs(on: pasteboard).isEmpty ? [] : .copy
    }
}

/// Dragging-destination behaviour shared by the views that accept file drops.
/// Each view registers FileDrop.acceptedTypes and forwards here.
protocol FileDropReceiving: NSView {
    var onFileDrop: (([URL]) -> Void)? { get }
}

extension FileDropReceiving {
    func fileDropEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onFileDrop == nil ? [] : FileDrop.operation(for: sender.draggingPasteboard)
    }

    func performFileDrop(_ sender: NSDraggingInfo) -> Bool {
        performFileDrop(from: sender.draggingPasteboard)
    }

    /// Split out from the NSDraggingInfo path so a test can drive it with a
    /// pasteboard alone.
    func performFileDrop(from pasteboard: NSPasteboard) -> Bool {
        let urls = FileDrop.fileURLs(on: pasteboard)
        guard !urls.isEmpty, let onFileDrop else { return false }
        onFileDrop(urls)
        return true
    }
}

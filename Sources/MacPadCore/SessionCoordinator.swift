//
//  SessionCoordinator.swift
//  MacPad
//
//  Keeps the session file and the backup folder in step with the open tabs,
//  and rebuilds the tabs from them at launch. See Session.swift for the files.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

final class SessionCoordinator {

    /// Seconds between backups of unsaved text.
    static let snapshotInterval: TimeInterval = 7

    /// UserDefaults key; absent means on.
    static let enabledDefaultsKey = "SessionSnapshotEnabled"

    /// Off when the user turned it off in defaults, or when MACPAD_NO_SESSION=1
    /// (for a launch that should neither read nor write the session).
    static var isEnabledByConfiguration: Bool {
        if ProcessInfo.processInfo.environment["MACPAD_NO_SESSION"] == "1" { return false }
        return UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    let isEnabled: Bool
    private let store: BufferStore
    private let files: SessionStore
    private var timer: Timer?
    private var isRestoring = false

    init(store: BufferStore, files: SessionStore, enabled: Bool = SessionCoordinator.isEnabledByConfiguration) {
        self.store = store
        self.files = files
        self.isEnabled = enabled
    }

    deinit { timer?.invalidate() }

    // MARK: - Launch

    /// Bring back the tabs from the last run. Returns how many came back.
    /// Always leaves at least one tab open.
    @discardableResult
    func restoreAtLaunch() -> Int {
        defer { ensureAtLeastOneBuffer() }
        guard isEnabled, let session = files.load(), !session.entries.isEmpty else { return 0 }

        isRestoring = true
        defer { isRestoring = false }

        var restored = 0
        for entry in session.entries {
            if restore(entry) { restored += 1 }
        }
        store.finishRestoring(activeIndex: session.activeIndex)
        return restored
    }

    private func restore(_ entry: SessionEntry) -> Bool {
        let url = entry.filePath.map { URL(fileURLWithPath: $0) }
        var text: String?
        var isDirty = false
        var backupURL: URL?
        var encoding = FileEncoding(storageName: entry.encodingName)

        if let backupPath = entry.backupPath, let saved = files.readBackup(at: backupPath) {
            // Unsaved work from last time, whether the tab had a file or not.
            text = saved
            isDirty = true
            backupURL = URL(fileURLWithPath: backupPath)
        } else if let url {
            // A clean file: read it again from disk. If it is gone, so is the tab.
            guard let data = try? Data(contentsOf: url) else { return false }
            let detected = FileEncoding.detect(in: data)
            if let decoded = encoding?.decode(data) {
                text = decoded
            } else if let decoded = detected.decode(data) {
                text = decoded
                encoding = detected
            } else {
                return false
            }
        }
        // An untitled tab with no backup comes back empty.

        let language = LanguageCatalog.language(withID: entry.languageID)
            ?? LanguageCatalog.language(for: url)
        let lineEnding = LineEnding(rawValue: entry.lineEnding)
            ?? text.map(LineEnding.detect) ?? .platformDefault

        do {
            try store.restoreBuffer(url: url,
                                    untitledNumber: entry.untitledNumber,
                                    text: text,
                                    language: language,
                                    encoding: encoding ?? .utf8,
                                    lineEnding: lineEnding,
                                    isDirty: isDirty,
                                    isReadOnly: entry.isReadOnly,
                                    anchor: entry.anchor,
                                    caret: entry.caret,
                                    firstVisibleLine: entry.firstVisibleLine,
                                    xOffset: entry.xOffset,
                                    backupURL: backupURL,
                                    modificationDate: entry.originalModificationTime > 0
                                        ? Date(timeIntervalSince1970: TimeInterval(entry.originalModificationTime))
                                        : nil)
            return true
        } catch {
            NSLog("MacPad: could not restore “%@”: %@", entry.displayName, "\(error)")
            return false
        }
    }

    private func ensureAtLeastOneBuffer() {
        if store.buffers.isEmpty {
            _ = try? store.newUntitledBuffer()
        }
    }

    // MARK: - While running

    /// Start the periodic backup.
    func start() {
        guard isEnabled, timer == nil else { return }
        let timer = Timer(timeInterval: Self.snapshotInterval, repeats: true) { [weak self] _ in
            self?.snapshot()
        }
        // .common so it also fires while a menu is open or a sheet is up.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The active tab's text changed; its backup is stale.
    func noteActiveBufferEdited() {
        store.activeBuffer?.needsBackup = true
    }

    /// Tabs were opened, closed, reordered or switched: rewrite the tab list.
    /// Cheap, so it runs on every such change.
    func sessionDidChange() {
        writeSessionFile()
    }

    /// Write every dirty tab's text to the backup folder and rewrite the tab
    /// list. Runs on the timer and at quit.
    func snapshot() {
        guard isEnabled, !isRestoring else { return }
        for buffer in store.buffers {
            if buffer.isDirty {
                guard buffer.needsBackup || buffer.backupURL == nil else { continue }
                let text = store.text(of: buffer)
                do {
                    let url = try files.writeBackup(text: text, displayName: buffer.displayName, id: buffer.id)
                    if let old = buffer.backupURL, old != url {
                        files.removeBackup(at: old)   // renamed by Save As
                    }
                    buffer.backupURL = url
                    buffer.needsBackup = false
                } catch {
                    NSLog("MacPad: backup of “%@” failed: %@", buffer.displayName, "\(error)")
                }
            } else if buffer.backupURL != nil {
                files.removeBackup(at: buffer.backupURL)
                buffer.backupURL = nil
            }
        }
        writeSessionFile()
    }

    private func writeSessionFile() {
        guard isEnabled, !isRestoring else { return }
        var session = SessionFile()
        session.entries = store.buffers.map(entry(for:))
        session.activeIndex = store.activeBuffer.flatMap { active in
            store.buffers.firstIndex { $0 === active }
        } ?? 0
        do {
            try files.save(session)
        } catch {
            NSLog("MacPad: could not write session.xml: %@", "\(error)")
        }
    }

    private func entry(for buffer: Buffer) -> SessionEntry {
        let state = store.viewState(of: buffer)
        return SessionEntry(
            filePath: buffer.url?.path,
            displayName: buffer.displayName,
            untitledNumber: buffer.untitledNumber,
            backupPath: buffer.isDirty ? buffer.backupURL?.path : nil,
            languageID: buffer.language.id,
            encodingName: buffer.encoding.storageName,
            lineEnding: buffer.lineEnding.rawValue,
            isReadOnly: buffer.isReadOnly,
            anchor: state.anchor,
            caret: state.caret,
            firstVisibleLine: state.firstVisibleLine,
            xOffset: state.xOffset,
            originalModificationTime: Int(buffer.lastKnownModificationDate?.timeIntervalSince1970 ?? 0))
    }
}

extension SessionCoordinator: BufferStoreSessionObserver {
    func bufferWasSaved(_ buffer: Buffer) {
        // Saved to its real file: the backup copy is no longer needed.
        files.removeBackup(at: buffer.backupURL)
        buffer.backupURL = nil
        buffer.needsBackup = false
        writeSessionFile()
    }

    func bufferWasClosed(_ buffer: Buffer) {
        files.removeBackup(at: buffer.backupURL)
        buffer.backupURL = nil
    }
}

//
//  Session.swift
//  MacPad
//
//  Remembering what was open, and bringing it back.
//
//  MacPad keeps two things between launches: a session file listing the
//  open tabs, and a backup folder holding the unsaved text of every dirty tab,
//  refreshed every few seconds. With
//  both on, quitting does not ask about unsaved changes: the next launch shows
//  the same tabs, with the same unsaved text, marked dirty. A crash loses at
//  most a few seconds of typing. MacPad does the same.
//
//  Files:
//    ~/Library/Application Support/MacPad/session.xml   the tab list
//    ~/Library/Application Support/MacPad/backup/        one file per dirty tab
//
//  session.xml is a small XML file: <MacPad> <Session> <mainView> with one
//  <File filename= backupFilePath= startPos= …/> per tab. The reader does not
//  care what the root element is called, so session files written by MacPad
//  0.1.0, which used a different root name, still load.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// MARK: - Model

/// One tab as recorded in the session file.
struct SessionEntry: Equatable {
    /// nil for an untitled document.
    var filePath: String?
    /// "new 3" for untitled documents; the file name otherwise.
    var displayName: String
    var untitledNumber: Int
    /// Where the unsaved text was written, if the tab was dirty.
    var backupPath: String?
    var languageID: String
    var encodingName: String
    var lineEnding: Int
    var isReadOnly: Bool
    var anchor: Int
    var caret: Int
    var firstVisibleLine: Int
    /// Sideways scroll, in pixels.
    var xOffset: Int = 0
    /// Modification time of the file on disk when it was last loaded or saved,
    /// in seconds since 1970; 0 when unknown or untitled.
    var originalModificationTime: Int

    var isUntitled: Bool { filePath == nil }
    var hasBackup: Bool { backupPath != nil }
}

/// The whole session: tabs in order, and which one was showing.
struct SessionFile: Equatable {
    var entries: [SessionEntry] = []
    var activeIndex: Int = 0
}

// MARK: - XML

enum SessionXML {

    /// Serialise to the session.xml layout described at the top of this file.
    static func data(for session: SessionFile) -> Data {
        let root = XMLElement(name: "MacPad")
        let sessionElement = XMLElement(name: "Session")
        sessionElement.set("activeView", "0")
        let mainView = XMLElement(name: "mainView")
        mainView.set("activeIndex", String(session.activeIndex))

        for entry in session.entries {
            let file = XMLElement(name: "File")
            file.set("firstVisibleLine", String(entry.firstVisibleLine))
            file.set("xOffset", String(entry.xOffset))
            file.set("startPos", String(entry.anchor))
            file.set("endPos", String(entry.caret))
            file.set("selMode", "0")
            file.set("lang", entry.languageID)
            file.set("encoding", "-1")
            file.set("userReadOnly", entry.isReadOnly ? "yes" : "no")
            file.set("filename", entry.filePath ?? entry.displayName)
            if let backup = entry.backupPath {
                file.set("backupFilePath", backup)
            }
            file.set("originalFileLastModifTimestamp", String(entry.originalModificationTime))
            // Details beyond position and path.
            file.set("macpadUntitledNumber", String(entry.untitledNumber))
            file.set("macpadEncoding", entry.encodingName)
            file.set("macpadLineEnding", String(entry.lineEnding))
            mainView.addChild(file)
        }

        sessionElement.addChild(mainView)
        let subView = XMLElement(name: "subView")
        subView.set("activeIndex", "0")
        sessionElement.addChild(subView)
        root.addChild(sessionElement)

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        return document.xmlData(options: [.nodePrettyPrint])
    }

    /// Parse a session.xml. The root element's name is not checked, so files
    /// from older MacPad versions load too. Returns nil if the data is not a
    /// session file at all; a session with no tabs is valid.
    static func session(from data: Data) -> SessionFile? {
        guard let document = try? XMLDocument(data: data),
              let root = document.rootElement(),
              let sessionElement = root.elements(forName: "Session").first,
              let mainView = sessionElement.elements(forName: "mainView").first else {
            return nil
        }

        var session = SessionFile()
        session.activeIndex = Int(mainView.get("activeIndex") ?? "0") ?? 0

        for file in mainView.elements(forName: "File") {
            let name = file.get("filename") ?? ""
            guard !name.isEmpty else { continue }
            // An absolute path names a file on disk; anything else, such as
            // "new 3", is the display name of an untitled tab.
            let isPath = name.hasPrefix("/")
            let displayName = isPath ? (name as NSString).lastPathComponent : name
            var untitledNumber = Int(file.get("macpadUntitledNumber") ?? "") ?? 0
            if untitledNumber == 0, !isPath {
                untitledNumber = Self.untitledNumber(in: displayName) ?? 0
            }
            var backupPath = file.get("backupFilePath")
            if backupPath?.isEmpty == true { backupPath = nil }

            session.entries.append(SessionEntry(
                filePath: isPath ? name : nil,
                displayName: displayName,
                untitledNumber: untitledNumber,
                backupPath: backupPath,
                languageID: file.get("lang") ?? "",
                encodingName: file.get("macpadEncoding") ?? "",
                lineEnding: Int(file.get("macpadLineEnding") ?? "") ?? -1,
                isReadOnly: file.get("userReadOnly") == "yes",
                anchor: Int(file.get("startPos") ?? "0") ?? 0,
                caret: Int(file.get("endPos") ?? "0") ?? 0,
                firstVisibleLine: Int(file.get("firstVisibleLine") ?? "0") ?? 0,
                xOffset: Int(file.get("xOffset") ?? "0") ?? 0,
                originalModificationTime: Int(file.get("originalFileLastModifTimestamp") ?? "0") ?? 0))
        }
        return session
    }

    /// "new 7" -> 7
    static func untitledNumber(in displayName: String) -> Int? {
        let parts = displayName.split(separator: " ")
        guard parts.count == 2, parts[0] == "new" else { return nil }
        return Int(parts[1])
    }
}

private extension XMLElement {
    func set(_ name: String, _ value: String) {
        if let attribute = XMLNode.attribute(withName: name, stringValue: value) as? XMLNode {
            addAttribute(attribute)
        }
    }
    func get(_ name: String) -> String? {
        attribute(forName: name)?.stringValue
    }
}

// MARK: - Files on disk

/// Reads and writes the session file and the backup folder.
final class SessionStore {

    let directory: URL
    var sessionFileURL: URL { directory.appendingPathComponent("session.xml") }
    var backupDirectory: URL { directory.appendingPathComponent("backup", isDirectory: true) }

    init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/MacPad, or the folder named by the
    /// MACPAD_SESSION_DIR environment variable (used by tests and smoke runs
    /// so they never touch the real session).
    static func standard() -> SessionStore {
        if let override = ProcessInfo.processInfo.environment["MACPAD_SESSION_DIR"], !override.isEmpty {
            return SessionStore(directory: URL(fileURLWithPath: override, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return SessionStore(directory: base.appendingPathComponent("MacPad", isDirectory: true))
    }

    func load() -> SessionFile? {
        guard let data = try? Data(contentsOf: sessionFileURL) else { return nil }
        return SessionXML.session(from: data)
    }

    func save(_ session: SessionFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try SessionXML.data(for: session).write(to: sessionFileURL, options: .atomic)
    }

    /// Write a dirty tab's text to the backup folder. The name carries the
    /// tab's display name so the folder is readable by a person, and a short
    /// unique suffix so two "new 1" tabs cannot collide.
    func writeBackup(text: String, displayName: String, id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let safeName = displayName.replacingOccurrences(of: "/", with: ":")
        let url = backupDirectory.appendingPathComponent("\(safeName)@\(id.uuidString.prefix(8))")
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    func readBackup(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func removeBackup(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

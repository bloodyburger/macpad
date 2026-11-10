//
//  MainMenu.swift
//  MacPad
//
//  The menu bar, built in code.
//
//  Keybindings follow the `Mac native` profile: Command replaces Control
//  throughout, and the menu structure follows Apple's conventions (an app menu
//  with Settings, a standard Window menu, Services). A second profile with
//  literal Ctrl bindings and Windows-style navigation, for people carrying
//  over muscle memory from Windows editors, arrives with the Shortcut Mapper
//  in M7, which is also what makes these user-editable.
//
//  Where the usual Windows binding is Ctrl+<key>, the Mac binding is the same
//  key with Command, so almost everything transfers. The exceptions are noted
//  inline.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

enum MainMenu {

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(searchMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(languageMenuItem())
        mainMenu.addItem(encodingMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        return mainMenu
    }

    // MARK: - Helpers

    private static func submenu(_ title: String) -> (NSMenuItem, NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return (item, menu)
    }

    @discardableResult
    private static func add(_ menu: NSMenu,
                            _ title: String,
                            _ action: Selector?,
                            _ key: String = "",
                            _ modifiers: NSEvent.ModifierFlags = .command,
                            tag: Int = 0,
                            represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        item.representedObject = represented
        menu.addItem(item)
        return item
    }

    // MARK: - Application menu

    private static func appMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("MacPad")
        add(menu, "About MacPad", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        add(menu, "Check for Updates…", #selector(AppDelegate.checkForUpdates(_:)))
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(AppDelegate.showSettings(_:)), ",")
        menu.addItem(.separator())

        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())

        add(menu, "Hide MacPad", #selector(NSApplication.hide(_:)), "h")
        add(menu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
            [.command, .option])
        add(menu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        add(menu, "Quit MacPad", #selector(NSApplication.terminate(_:)), "q")
        return item
    }

    // MARK: - File

    private static func fileMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("File")
        add(menu, "New", #selector(EditorWindowController.newDocument(_:)), "n")
        add(menu, "Open…", #selector(EditorWindowController.openDocument(_:)), "o")

        // NSDocumentController populates a Recent Documents menu automatically
        // only for NSDocument-based apps. MacPad manages its own buffers, so
        // the menu is filled on demand by RecentDocumentsMenuDelegate rather
        // than by poking at the private _setMenuName: selector.
        let (recentItem, recentMenu) = submenu("Open Recent")
        recentMenu.delegate = RecentDocumentsMenuDelegate.shared
        menu.addItem(recentItem)

        menu.addItem(.separator())
        add(menu, "Close Tab", #selector(EditorWindowController.closeActiveBuffer(_:)), "w")
        add(menu, "Save", #selector(EditorWindowController.saveDocument(_:)), "s")
        add(menu, "Save As…", #selector(EditorWindowController.saveDocumentAs(_:)), "s",
            [.command, .shift])
        add(menu, "Save All", #selector(EditorWindowController.saveAllDocuments(_:)), "s",
            [.command, .option])
        add(menu, "Reload from Disk", #selector(EditorWindowController.revertDocumentToSaved(_:)))
        menu.addItem(.separator())
        add(menu, "Print…", #selector(EditorWindowController.printDocument(_:)), "p")
        return item
    }

    // MARK: - Edit

    private static func editMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("Edit")
        add(menu, "Undo", #selector(EditorWindowController.undoEdit(_:)), "z")
        add(menu, "Redo", #selector(EditorWindowController.redoEdit(_:)), "z", [.command, .shift])
        menu.addItem(.separator())
        add(menu, "Cut", #selector(EditorWindowController.cutText(_:)), "x")
        add(menu, "Copy", #selector(EditorWindowController.copyText(_:)), "c")
        add(menu, "Paste", #selector(EditorWindowController.pasteText(_:)), "v")
        add(menu, "Delete", #selector(EditorWindowController.deleteText(_:)))
        add(menu, "Select All", #selector(EditorWindowController.selectAllText(_:)), "a")
        menu.addItem(.separator())

        let (caseItem, caseMenu) = submenu("Convert Case")
        add(caseMenu, "UPPERCASE", #selector(EditorWindowController.convertToUppercase(_:)), "u",
            [.command, .shift])
        add(caseMenu, "lowercase", #selector(EditorWindowController.convertToLowercase(_:)), "u")
        menu.addItem(caseItem)
        menu.addItem(.separator())

        // ⌘/ is the comment binding every Mac editor uses.
        add(menu, "Toggle Line Comment",
            #selector(EditorWindowController.toggleLineComment(_:)), "/")
        add(menu, "Block Comment", #selector(EditorWindowController.blockComment(_:)), "/",
            [.command, .option])
        add(menu, "Block Uncomment", #selector(EditorWindowController.blockUncomment(_:)))
        menu.addItem(.separator())

        let (lineEndingsItem, lineEndingsMenu) = submenu("Line Endings")
        for ending in LineEnding.allCases {
            add(lineEndingsMenu, ending.displayName,
                #selector(EditorWindowController.setLineEndingFromMenu(_:)),
                tag: ending.rawValue)
        }
        menu.addItem(lineEndingsItem)
        return item
    }

    // MARK: - Search

    private static func searchMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("Search")
        add(menu, "Find…", #selector(EditorWindowController.showFindBar(_:)), "f")
        add(menu, "Find Next", #selector(EditorWindowController.findNext(_:)), "g")
        add(menu, "Find Previous", #selector(EditorWindowController.findPrevious(_:)), "g",
            [.command, .shift])
        add(menu, "Replace…", #selector(EditorWindowController.showReplaceBar(_:)), "h",
            [.command, .option])
        menu.addItem(.separator())
        add(menu, "Go to Line…", #selector(EditorWindowController.goToLine(_:)), "l")
        menu.addItem(.separator())
        add(menu, "Toggle Bookmark", #selector(EditorWindowController.toggleBookmark(_:)), "b",
            [.command, .shift])
        add(menu, "Next Bookmark", #selector(EditorWindowController.nextBookmark(_:)), "b",
            [.command, .option])
        add(menu, "Previous Bookmark", #selector(EditorWindowController.previousBookmark(_:)), "b",
            [.command, .option, .shift])
        return item
    }

    // MARK: - View

    private static func viewMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("View")
        add(menu, "Zoom In", #selector(EditorWindowController.zoomIn(_:)), "+")
        add(menu, "Zoom Out", #selector(EditorWindowController.zoomOut(_:)), "-")
        add(menu, "Restore Default Zoom", #selector(EditorWindowController.zoomReset(_:)), "0")
        menu.addItem(.separator())
        add(menu, "Word Wrap", #selector(EditorWindowController.toggleWordWrap(_:)))
        add(menu, "Show All Characters",
            #selector(EditorWindowController.toggleInvisibleCharacters(_:)))
        add(menu, "Show Indent Guides", #selector(EditorWindowController.toggleIndentGuides(_:)))
        menu.addItem(.separator())
        add(menu, "Fold All", #selector(EditorWindowController.foldAll(_:)), "0",
            [.command, .option])
        add(menu, "Unfold All", #selector(EditorWindowController.unfoldAll(_:)), "9",
            [.command, .option])
        menu.addItem(.separator())
        add(menu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
            [.command, .control])
        return item
    }

    // MARK: - Language

    private static func languageMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("Language")
        // A-Z submenus only pay off at ~90 languages; with this starter set
        // a flat alphabetical list is easier to use. M4's larger language
        // catalogue brings the grouped structure with it.
        for language in LanguageCatalog.all.sorted(by: { $0.displayName < $1.displayName }) {
            add(menu, language.displayName,
                #selector(EditorWindowController.setLanguageFromMenu(_:)),
                represented: language.id)
        }
        return item
    }

    // MARK: - Encoding

    private static func encodingMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("Encoding")
        let encodings: [(String, Int)] = [
            ("UTF-8", 0),
            ("UTF-8-BOM", 1),
            ("UTF-16 LE BOM", 2),
            ("UTF-16 BE BOM", 3),
            ("ANSI (Windows-1252)", 4),
        ]
        for (title, tag) in encodings {
            add(menu, title, #selector(EditorWindowController.setEncodingFromMenu(_:)), tag: tag)
        }
        return item
    }

    // MARK: - Window

    private static func windowMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("Window")
        add(menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(menu, "Zoom", #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        // ⌃Tab is reserved by macOS for window switching, so these use
        // ⌘⌥← / ⌘⌥→ as Safari and Xcode do.
        add(menu, "Next Tab", #selector(EditorWindowController.selectNextTab(_:)), "\u{F703}",
            [.command, .option])
        add(menu, "Previous Tab", #selector(EditorWindowController.selectPreviousTab(_:)),
            "\u{F702}", [.command, .option])
        menu.addItem(.separator())
        for number in 1...9 {
            let tabItem = add(menu, "Tab \(number)",
                              #selector(EditorWindowController.selectTabByNumber(_:)),
                              "\(number)", tag: number)
            tabItem.isHidden = number > 9
        }
        menu.addItem(.separator())
        add(menu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = menu
        return item
    }

    // MARK: - Help

    private static func helpMenuItem() -> NSMenuItem {
        let (item, menu) = submenu("Help")
        add(menu, "MacPad Help", #selector(AppDelegate.showHelp(_:)), "?")
        NSApp.helpMenu = menu
        return item
    }
}


// MARK: - Recent documents

/// Fills the Open Recent menu from NSDocumentController's recent URLs each
/// time it is opened.
final class RecentDocumentsMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        guard !urls.isEmpty else {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent,
                                  action: #selector(AppDelegate.openRecentDocument(_:)),
                                  keyEquivalent: "")
            item.representedObject = url
            item.toolTip = url.path
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Clear Menu",
                                action: #selector(AppDelegate.clearRecentDocuments(_:)),
                                keyEquivalent: ""))
    }
}

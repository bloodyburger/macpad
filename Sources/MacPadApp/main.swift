//
//  main.swift
//  MacPad
//
//  Programmatic entry point: no storyboard, no nib. The menu bar is built in
//  MainMenu.swift and the window in EditorWindowController.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()

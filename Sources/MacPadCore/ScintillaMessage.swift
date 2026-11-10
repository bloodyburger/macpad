//
//  ScintillaMessage.swift
//  MacPad
//
//  The handful of Scintilla messages the Swift layer sends directly, for which
//  MPEditorView has no typed method. Values are copied from
//  Vendor/scintilla/include/Scintilla.h and verified against it; the test in
//  Tests/Unit/ScintillaMessageTests re-checks them against the vendored header
//  so a dependency bump cannot silently shift one.
//
//  Prefer adding a typed method to MPEditorView over adding entries here.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum ScintillaMessage {
    static let getAnchor: Int            = 2009
    static let setAnchor: Int            = 2026
    static let getFirstVisibleLine: Int  = 2152
    static let emptyUndoBuffer: Int      = 2175
    static let setFirstVisibleLine: Int  = 2613
}

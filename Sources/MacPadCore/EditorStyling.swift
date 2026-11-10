//
//  EditorStyling.swift
//  MacPad
//
//  Applies a Language and a Theme to the editor view.
//
//  Ordering matters and is easy to get wrong: Scintilla's SCI_STYLECLEARALL
//  copies STYLE_DEFAULT over every other style, so the default must be set
//  first, then cleared to all, and only then may per-style colours be applied.
//  Doing it in any other order silently wipes the syntax colours.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

extension MPEditorView {

    /// Document-scoped: attach the lexer and feed it its keyword lists. Safe to
    /// call once per buffer, since the lexer travels with the document.
    func applyLanguage(_ language: Language) {
        if !setLexerNamed(language.lexer) {
            // A missing lexer must not leave the previous language's lexer
            // attached to this document; fall back to no highlighting.
            NSLog("MacPad: Lexilla has no lexer named “%@”; falling back to plain text.",
                  language.lexer)
            _ = setLexerNamed(LanguageCatalog.plainText.lexer)
        }
        for (index, words) in language.keywordSets.sorted(by: { $0.key < $1.key }) {
            setKeywords(words, forSet: index)
        }
        colourise(from: 0, to: -1)
    }

    /// View-scoped: colours and fonts. Must be re-applied whenever the active
    /// document's language changes, because style numbers are per-lexer.
    func applyTheme(_ theme: Theme, for language: Language) {
        // 1. STYLE_DEFAULT first.
        setStyle(ScintillaStyle.default, fontName: theme.fontName, size: theme.fontSize)
        setStyle(ScintillaStyle.default, foreground: theme.foreground)
        setStyle(ScintillaStyle.default, background: theme.background)
        setStyle(ScintillaStyle.default, bold: false)
        setStyle(ScintillaStyle.default, italic: false)

        // 2. Propagate it to every style.
        applyDefaultStyleToAll()

        // 3. Now the per-role colours for this language's lexer.
        for (sceStyleNumber, role) in language.styleRoles {
            // SCE_* constants arrive from C as Int32; the bridge takes NSInteger.
            let styleNumber = Int(sceStyleNumber)
            setStyle(styleNumber, foreground: theme.color(for: role))
            setStyle(styleNumber, background: theme.background)
            if theme.isBold(role)   { setStyle(styleNumber, bold: true) }
            if theme.isItalic(role) { setStyle(styleNumber, italic: true) }
        }

        // 4. Scintilla's predefined styles and view colours.
        setStyle(ScintillaStyle.lineNumber, foreground: theme.lineNumberForeground)
        setStyle(ScintillaStyle.lineNumber, background: theme.lineNumberBackground)
        setStyle(ScintillaStyle.braceLight, foreground: theme.braceMatch)
        setStyle(ScintillaStyle.braceLight, bold: true)
        setStyle(ScintillaStyle.braceBad, foreground: theme.braceMismatch)
        setStyle(ScintillaStyle.braceBad, bold: true)
        setStyle(ScintillaStyle.indentGuide, foreground: theme.indentGuide)

        setCaretForeground(theme.caret)
        setCaretLineBackground(theme.caretLineBackground, visible: true)
        setSelectionBackground(theme.selectionBackground)
        setFoldMarginBackground(theme.lineNumberBackground)

        colourise(from: 0, to: -1)
    }

    /// Wrap the selection in the language's block comment markers, such as
    /// /* and */. Returns false when the language has none or nothing is
    /// selected. One undo step; the commented text stays selected.
    @discardableResult
    func blockComment(for language: Language) -> Bool {
        guard let markers = language.blockComment else { return false }
        let start = selectionStart
        let end = selectionEnd
        guard end > start else { return false }

        beginUndoAction()
        defer { endUndoAction() }
        // Close first, so inserting it does not shift the start position.
        insertText(markers.close, atPosition: end)
        insertText(markers.open, atPosition: start)
        setSelection(from: start, to: end + markers.open.utf8.count + markers.close.utf8.count)
        return true
    }

    /// Remove block comment markers from around the selection. Works whether
    /// the selection includes the markers or sits just inside them. Returns
    /// false when there are none to remove.
    @discardableResult
    func blockUncomment(for language: Language) -> Bool {
        guard let markers = language.blockComment else { return false }
        let openLength = markers.open.utf8.count
        let closeLength = markers.close.utf8.count
        var start = selectionStart
        var end = selectionEnd

        func isOpen(at position: Int) -> Bool {
            position >= 0 && text(inByteRange: NSRange(location: position, length: openLength)) == markers.open
        }
        func isClose(at position: Int) -> Bool {
            position >= 0 && text(inByteRange: NSRange(location: position, length: closeLength)) == markers.close
        }

        if end - start >= openLength + closeLength, isOpen(at: start), isClose(at: end - closeLength) {
            // The selection includes both markers.
        } else if isOpen(at: start - openLength), isClose(at: end) {
            // The markers sit just outside the selection.
            start -= openLength
            end += closeLength
        } else {
            return false
        }

        beginUndoAction()
        defer { endUndoAction() }
        // Close first, so removing it does not shift the start position.
        deleteByteRange(NSRange(location: end - closeLength, length: closeLength))
        deleteByteRange(NSRange(location: start, length: openLength))
        setSelection(from: start, to: end - openLength - closeLength)
        return true
    }

    /// Toggle a line comment on every line the selection touches, using the
    /// language's marker: if every affected line already starts with the
    /// marker, uncomment them all; otherwise comment them all.
    func toggleLineComment(for language: Language) {
        guard let marker = language.lineComment else { return }

        let start = selectionStart
        let end = selectionEnd
        let firstLine = line(forPosition: start)
        var lastLine = line(forPosition: end)

        // A selection ending exactly at a line start does not include that line.
        if lastLine > firstLine, end == position(forLine: lastLine) {
            lastLine -= 1
        }
        guard firstLine <= lastLine else { return }

        struct LineInfo {
            let number: Int
            let text: String
            let isBlank: Bool
            let indentByteCount: Int
        }

        let lines: [LineInfo] = (firstLine...lastLine).map { line in
            let raw = text(ofLine: line)
            let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Byte offset of the first non-whitespace character on the line.
            var indentBytes = 0
            for character in raw {
                if character == " " || character == "\t" {
                    indentBytes += String(character).utf8.count
                } else {
                    break
                }
            }
            return LineInfo(number: line,
                            text: raw,
                            isBlank: body.isEmpty,
                            indentByteCount: indentBytes)
        }

        let meaningful = lines.filter { !$0.isBlank }
        guard !meaningful.isEmpty else { return }

        let allCommented = meaningful.allSatisfy {
            $0.text.trimmingCharacters(in: .whitespaces).hasPrefix(marker)
        }

        // One undo step for the whole toggle.
        beginUndoAction()
        defer { endUndoAction() }

        // Edit from the last line backwards so earlier positions stay valid.
        for info in meaningful.reversed() {
            let lineStart = position(forLine: info.number)
            if allCommented {
                let markerStart = lineStart + info.indentByteCount
                // Remove the marker, and the single space after it that the
                // comment path inserts, in one deletion. Deciding the length
                // from the original line text avoids re-reading the line and
                // mixing byte offsets with character offsets.
                let afterIndent = info.text.dropFirst(
                    info.text.prefix(while: { $0 == " " || $0 == "\t" }).count)
                let hasSpaceAfterMarker = afterIndent.dropFirst(marker.count).hasPrefix(" ")
                let removalLength = marker.utf8.count + (hasSpaceAfterMarker ? 1 : 0)
                deleteByteRange(NSRange(location: markerStart, length: removalLength))
            } else {
                insertText(marker + " ", atPosition: lineStart + info.indentByteCount)
            }
        }
    }
}

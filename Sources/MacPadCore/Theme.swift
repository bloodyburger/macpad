//
//  Theme.swift
//  MacPad
//
//  Maps semantic style roles to colours. Milestone M4 replaces this with
//  themes loaded from files; the role indirection is what makes that swap
//  possible without touching any language definition.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

struct Theme {
    let name: String
    let isDark: Bool

    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let caretLineBackground: NSColor
    let selectionBackground: NSColor
    let lineNumberForeground: NSColor
    let lineNumberBackground: NSColor
    let indentGuide: NSColor
    let braceMatch: NSColor
    let braceMismatch: NSColor
    let markAllHighlight: NSColor
    /// Every match of what is typed in the find bar, highlighted while
    /// searching.
    let findHighlight: NSColor

    let fontName: String
    let fontSize: CGFloat

    private let roleColors: [StyleRole: NSColor]
    private let boldRoles: Set<StyleRole>
    private let italicRoles: Set<StyleRole>

    func color(for role: StyleRole) -> NSColor {
        roleColors[role] ?? foreground
    }

    func isBold(_ role: StyleRole) -> Bool { boldRoles.contains(role) }
    func isItalic(_ role: StyleRole) -> Bool { italicRoles.contains(role) }

    // MARK: - Built-in themes

    /// The stock light theme: black on white with conventional syntax
    /// colours. Themes loaded from files arrive in M4.
    static let light = Theme(
        name: "Default (light)",
        isDark: false,
        background: NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        foreground: NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1),
        caret: NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1),
        caretLineBackground: NSColor(srgbRed: 0.91, green: 0.94, blue: 0.99, alpha: 1),
        selectionBackground: NSColor(srgbRed: 0.75, green: 0.82, blue: 0.94, alpha: 1),
        lineNumberForeground: NSColor(srgbRed: 0.50, green: 0.50, blue: 0.50, alpha: 1),
        lineNumberBackground: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1),
        indentGuide: NSColor(srgbRed: 0.80, green: 0.80, blue: 0.80, alpha: 1),
        braceMatch: NSColor(srgbRed: 0.00, green: 0.50, blue: 0.00, alpha: 1),
        braceMismatch: NSColor(srgbRed: 0.80, green: 0.00, blue: 0.00, alpha: 1),
        markAllHighlight: NSColor(srgbRed: 0.00, green: 0.60, blue: 0.40, alpha: 1),
        findHighlight: NSColor(srgbRed: 1.00, green: 0.75, blue: 0.10, alpha: 1),
        fontName: "Menlo",
        fontSize: 13,
        roleColors: [
            .normal:               NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1),
            .comment:              NSColor(srgbRed: 0.00, green: 0.50, blue: 0.00, alpha: 1),
            .documentationComment: NSColor(srgbRed: 0.00, green: 0.45, blue: 0.35, alpha: 1),
            .keyword:              NSColor(srgbRed: 0.00, green: 0.00, blue: 0.80, alpha: 1),
            .secondaryKeyword:     NSColor(srgbRed: 0.40, green: 0.00, blue: 0.70, alpha: 1),
            .type:                 NSColor(srgbRed: 0.17, green: 0.35, blue: 0.62, alpha: 1),
            .string:               NSColor(srgbRed: 0.50, green: 0.13, blue: 0.13, alpha: 1),
            .character:            NSColor(srgbRed: 0.50, green: 0.13, blue: 0.13, alpha: 1),
            .escapeSequence:       NSColor(srgbRed: 0.70, green: 0.30, blue: 0.00, alpha: 1),
            .number:               NSColor(srgbRed: 0.90, green: 0.40, blue: 0.00, alpha: 1),
            .`operator`:             NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1),
            .preprocessor:         NSColor(srgbRed: 0.50, green: 0.25, blue: 0.60, alpha: 1),
            .identifier:           NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1),
            .functionName:         NSColor(srgbRed: 0.00, green: 0.25, blue: 0.70, alpha: 1),
            .className:           NSColor(srgbRed: 0.00, green: 0.35, blue: 0.60, alpha: 1),
            .tag:                  NSColor(srgbRed: 0.00, green: 0.00, blue: 0.80, alpha: 1),
            .unknownTag:           NSColor(srgbRed: 0.80, green: 0.00, blue: 0.00, alpha: 1),
            .attribute:            NSColor(srgbRed: 0.60, green: 0.00, blue: 0.40, alpha: 1),
            .unknownAttribute:     NSColor(srgbRed: 0.80, green: 0.00, blue: 0.00, alpha: 1),
            .entity:               NSColor(srgbRed: 0.55, green: 0.35, blue: 0.00, alpha: 1),
            .propertyName:         NSColor(srgbRed: 0.30, green: 0.20, blue: 0.70, alpha: 1),
            .heading:              NSColor(srgbRed: 0.00, green: 0.20, blue: 0.70, alpha: 1),
            .link:                 NSColor(srgbRed: 0.00, green: 0.35, blue: 0.80, alpha: 1),
            .emphasis:             NSColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1),
            .strong:               NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1),
            .codeSpan:             NSColor(srgbRed: 0.45, green: 0.25, blue: 0.10, alpha: 1),
            .variable:             NSColor(srgbRed: 0.55, green: 0.20, blue: 0.40, alpha: 1),
            .regex:                NSColor(srgbRed: 0.00, green: 0.45, blue: 0.45, alpha: 1),
            .error:                NSColor(srgbRed: 0.85, green: 0.00, blue: 0.00, alpha: 1),
            .added:                NSColor(srgbRed: 0.00, green: 0.50, blue: 0.00, alpha: 1),
            .deleted:              NSColor(srgbRed: 0.70, green: 0.00, blue: 0.00, alpha: 1),
            .changed:              NSColor(srgbRed: 0.00, green: 0.30, blue: 0.70, alpha: 1),
        ],
        boldRoles: [.keyword, .heading, .strong, .tag],
        italicRoles: [.comment, .documentationComment, .emphasis]
    )

    /// The stock dark theme: a soft charcoal palette.
    static let dark = Theme(
        name: "Default (dark)",
        isDark: true,
        background: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1),
        foreground: NSColor(srgbRed: 0.87, green: 0.88, blue: 0.88, alpha: 1),
        caret: NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        caretLineBackground: NSColor(srgbRed: 0.22, green: 0.23, blue: 0.26, alpha: 1),
        selectionBackground: NSColor(srgbRed: 0.27, green: 0.33, blue: 0.40, alpha: 1),
        lineNumberForeground: NSColor(srgbRed: 0.52, green: 0.55, blue: 0.58, alpha: 1),
        lineNumberBackground: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.24, alpha: 1),
        indentGuide: NSColor(srgbRed: 0.33, green: 0.34, blue: 0.37, alpha: 1),
        braceMatch: NSColor(srgbRed: 0.44, green: 0.80, blue: 0.44, alpha: 1),
        braceMismatch: NSColor(srgbRed: 0.90, green: 0.35, blue: 0.35, alpha: 1),
        markAllHighlight: NSColor(srgbRed: 0.30, green: 0.75, blue: 0.60, alpha: 1),
        findHighlight: NSColor(srgbRed: 0.95, green: 0.70, blue: 0.15, alpha: 1),
        fontName: "Menlo",
        fontSize: 13,
        roleColors: [
            .normal:               NSColor(srgbRed: 0.87, green: 0.88, blue: 0.88, alpha: 1),
            .comment:              NSColor(srgbRed: 0.49, green: 0.56, blue: 0.60, alpha: 1),
            .documentationComment: NSColor(srgbRed: 0.55, green: 0.65, blue: 0.65, alpha: 1),
            .keyword:              NSColor(srgbRed: 0.57, green: 0.72, blue: 0.85, alpha: 1),
            .secondaryKeyword:     NSColor(srgbRed: 0.76, green: 0.62, blue: 0.86, alpha: 1),
            .type:                 NSColor(srgbRed: 0.60, green: 0.80, blue: 0.86, alpha: 1),
            .string:               NSColor(srgbRed: 0.93, green: 0.73, blue: 0.53, alpha: 1),
            .character:            NSColor(srgbRed: 0.93, green: 0.73, blue: 0.53, alpha: 1),
            .escapeSequence:       NSColor(srgbRed: 0.95, green: 0.60, blue: 0.40, alpha: 1),
            .number:               NSColor(srgbRed: 0.90, green: 0.62, blue: 0.45, alpha: 1),
            .`operator`:             NSColor(srgbRed: 0.80, green: 0.82, blue: 0.82, alpha: 1),
            .preprocessor:         NSColor(srgbRed: 0.65, green: 0.80, blue: 0.55, alpha: 1),
            .identifier:           NSColor(srgbRed: 0.87, green: 0.88, blue: 0.88, alpha: 1),
            .functionName:         NSColor(srgbRed: 0.60, green: 0.80, blue: 0.95, alpha: 1),
            .className:           NSColor(srgbRed: 0.55, green: 0.85, blue: 0.90, alpha: 1),
            .tag:                  NSColor(srgbRed: 0.57, green: 0.72, blue: 0.85, alpha: 1),
            .unknownTag:           NSColor(srgbRed: 0.90, green: 0.40, blue: 0.40, alpha: 1),
            .attribute:            NSColor(srgbRed: 0.85, green: 0.65, blue: 0.85, alpha: 1),
            .unknownAttribute:     NSColor(srgbRed: 0.90, green: 0.40, blue: 0.40, alpha: 1),
            .entity:               NSColor(srgbRed: 0.85, green: 0.75, blue: 0.50, alpha: 1),
            .propertyName:         NSColor(srgbRed: 0.72, green: 0.78, blue: 0.95, alpha: 1),
            .heading:              NSColor(srgbRed: 0.60, green: 0.80, blue: 0.95, alpha: 1),
            .link:                 NSColor(srgbRed: 0.50, green: 0.75, blue: 0.95, alpha: 1),
            .emphasis:             NSColor(srgbRed: 0.85, green: 0.86, blue: 0.86, alpha: 1),
            .strong:               NSColor(srgbRed: 0.95, green: 0.96, blue: 0.96, alpha: 1),
            .codeSpan:             NSColor(srgbRed: 0.90, green: 0.78, blue: 0.60, alpha: 1),
            .variable:             NSColor(srgbRed: 0.90, green: 0.65, blue: 0.75, alpha: 1),
            .regex:                NSColor(srgbRed: 0.55, green: 0.85, blue: 0.80, alpha: 1),
            .error:                NSColor(srgbRed: 0.95, green: 0.40, blue: 0.40, alpha: 1),
            .added:                NSColor(srgbRed: 0.50, green: 0.82, blue: 0.50, alpha: 1),
            .deleted:              NSColor(srgbRed: 0.92, green: 0.45, blue: 0.45, alpha: 1),
            .changed:              NSColor(srgbRed: 0.50, green: 0.72, blue: 0.95, alpha: 1),
        ],
        boldRoles: [.keyword, .heading, .strong, .tag],
        italicRoles: [.comment, .documentationComment, .emphasis]
    )

    /// Follows the system appearance.
    static func matchingSystemAppearance() -> Theme {
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return appearance == .darkAqua ? .dark : .light
    }
}

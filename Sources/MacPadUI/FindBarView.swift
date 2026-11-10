//
//  FindBarView.swift
//  MacPad
//
//  Find and replace, presented as a bar docked under the tab bar, which is
//  the shape that fits macOS.
//
//  Scope: this covers the options people use constantly — the three search
//  modes, case and whole-word, wrap-around, backwards, Count, Find All and
//  Replace All. Milestone M3 adds the rest (Find in Files, In Selection, the
//  Search Results panel, the 5 mark styles, transparency) and swaps the regex
//  engine for Boost.Regex so the dialect matches Windows exactly.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

/// The three search modes.
enum SearchMode: Int, CaseIterable {
    case normal = 0
    case extended = 1
    case regularExpression = 2

    var displayName: String {
        switch self {
        case .normal:            return "Normal"
        case .extended:          return "Extended (\\n, \\r, \\t, \\0, \\x…)"
        case .regularExpression: return "Regular expression"
        }
    }

    var shortName: String {
        switch self {
        case .normal:            return "Normal"
        case .extended:          return "Extended"
        case .regularExpression: return "Regex"
        }
    }
}

struct SearchOptions {
    var searchText: String = ""
    var replacementText: String = ""
    var mode: SearchMode = .normal
    var matchCase: Bool = false
    var wholeWord: Bool = false
    var wrapAround: Bool = true
    var searchBackwards: Bool = false
    /// ". matches newline". Expressed as an inline (?s) on the pattern,
    /// which is the equivalent Perl-syntax switch.
    var dotMatchesNewline: Bool = false

    /// Translate to Scintilla's search flag bitmask.
    ///
    /// `.regExp` alone is correct here: the Scintilla target is built with
    /// SCI_OWNREGEX, so regex searches reach MacPad's own Boost.Regex engine
    /// (Sources/SearchEngine/MPRegexSearch.cxx), a full Perl-syntax dialect.
    /// `.cxx11RegEx` must NOT be set; it selected the built-in
    /// std::regex path, a different dialect that is also line-oriented and so
    /// cannot match across line ends at all.
    var scintillaFlags: MPSearchFlags {
        var flags: MPSearchFlags = []
        if matchCase { flags.insert(.matchCase) }
        // Whole-word is not combined with regex, where \b does the job.
        if wholeWord && mode != .regularExpression { flags.insert(.wholeWord) }
        if mode == .regularExpression { flags.insert(.regExp) }
        return flags
    }

    /// Expand Extended-mode escapes (\n, \t, \xHH and the rest) to the
    /// bytes they stand for.
    static func expandExtendedEscapes(in input: String) -> String {
        var output = String()
        let characters = Array(input)
        var index = 0

        func hexValue(_ characters: ArraySlice<Character>) -> UInt32? {
            let text = String(characters)
            guard text.count == characters.count, !text.isEmpty else { return nil }
            return UInt32(text, radix: 16)
        }

        while index < characters.count {
            let character = characters[index]
            guard character == "\\", index + 1 < characters.count else {
                output.append(character)
                index += 1
                continue
            }

            let escape = characters[index + 1]
            switch escape {
            case "n": output.append("\n"); index += 2
            case "r": output.append("\r"); index += 2
            case "t": output.append("\t"); index += 2
            case "0": output.append("\0"); index += 2
            case "a": output.append("\u{07}"); index += 2
            case "b": output.append("\u{08}"); index += 2
            case "f": output.append("\u{0C}"); index += 2
            case "v": output.append("\u{0B}"); index += 2
            case "e": output.append("\u{1B}"); index += 2
            case "\\": output.append("\\"); index += 2
            case "x", "X":
                // \xHH — exactly two hex digits.
                let start = index + 2
                if start + 2 <= characters.count,
                   let value = hexValue(characters[start..<(start + 2)]),
                   let scalar = Unicode.Scalar(value) {
                    output.append(Character(scalar))
                    index += 4
                } else {
                    output.append(character); index += 1
                }
            case "u", "U":
                // \uHHHH — exactly four hex digits.
                let start = index + 2
                if start + 4 <= characters.count,
                   let value = hexValue(characters[start..<(start + 4)]),
                   let scalar = Unicode.Scalar(value) {
                    output.append(Character(scalar))
                    index += 6
                } else {
                    output.append(character); index += 1
                }
            case "d":
                // \ddd — exactly three decimal digits.
                let start = index + 2
                if start + 3 <= characters.count,
                   let value = UInt32(String(characters[start..<(start + 3)]), radix: 10),
                   let scalar = Unicode.Scalar(value) {
                    output.append(Character(scalar))
                    index += 5
                } else {
                    output.append(character); index += 1
                }
            case "o":
                // \oooo — exactly four octal digits.
                let start = index + 2
                if start + 4 <= characters.count,
                   let value = UInt32(String(characters[start..<(start + 4)]), radix: 8),
                   let scalar = Unicode.Scalar(value) {
                    output.append(Character(scalar))
                    index += 6
                } else {
                    output.append(character); index += 1
                }
            default:
                output.append(character)
                index += 1
            }
        }
        return output
    }

    /// The needle as it should be handed to the search engine.
    var effectiveSearchText: String {
        switch mode {
        case .normal:
            return searchText
        case .extended:
            return Self.expandExtendedEscapes(in: searchText)
        case .regularExpression:
            // The engine compiles with Boost's no_mod_s, so `.` stops at a
            // line end by default. An inline (?s) opts in.
            return dotMatchesNewline ? "(?s)" + searchText : searchText
        }
    }

    var effectiveReplacementText: String {
        mode == .extended ? Self.expandExtendedEscapes(in: replacementText) : replacementText
    }
}

protocol FindBarViewDelegate: AnyObject {
    func findBarDidRequestFindNext(_ bar: FindBarView)
    func findBarDidRequestFindPrevious(_ bar: FindBarView)
    func findBarDidRequestReplace(_ bar: FindBarView)
    func findBarDidRequestReplaceAll(_ bar: FindBarView)
    func findBarDidRequestCount(_ bar: FindBarView)
    func findBarDidRequestMarkAll(_ bar: FindBarView)
    func findBarDidRequestClose(_ bar: FindBarView)
    func findBarOptionsDidChange(_ bar: FindBarView)
    /// The search text changed as the user typed.
    func findBarSearchTextDidChange(_ bar: FindBarView)
}

final class FindBarView: NSView {

    weak var delegate: FindBarViewDelegate?

    private let findField = NSSearchField()
    private let replaceField = NSTextField()
    private let modePopUp = NSPopUpButton()
    private let matchCaseButton = NSButton()
    private let wholeWordButton = NSButton()
    private let wrapAroundButton = NSButton()
    private let dotMatchesNewlineButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let replaceRow = NSStackView()

    private(set) var options = SearchOptions()

    /// Replace controls are hidden until Replace is explicitly invoked, so
    /// plain Find stays a one-line bar.
    var isReplaceVisible: Bool = false {
        didSet { replaceRow.isHidden = !isReplaceVisible }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    override var isFlipped: Bool { true }

    private func build() {
        wantsLayer = true

        findField.placeholderString = "Find"
        findField.target = self
        findField.action = #selector(findFieldAction)
        findField.sendsWholeSearchString = true
        findField.sendsSearchStringImmediately = false
        // Keystrokes arrive through controlTextDidChange(_:) for the
        // search-as-you-type behaviour; Return still goes through the action.
        findField.delegate = self

        replaceField.placeholderString = "Replace with"
        replaceField.target = self
        replaceField.action = #selector(replaceFieldAction)

        for mode in SearchMode.allCases {
            modePopUp.addItem(withTitle: mode.shortName)
            modePopUp.lastItem?.toolTip = mode.displayName
            modePopUp.lastItem?.tag = mode.rawValue
        }
        modePopUp.target = self
        modePopUp.action = #selector(optionChanged)

        configureCheckbox(matchCaseButton, title: "Aa", tooltip: "Match case")
        configureCheckbox(wholeWordButton, title: "⊏⊐", tooltip: "Match whole word only")
        configureCheckbox(wrapAroundButton, title: "↻", tooltip: "Wrap around")
        wrapAroundButton.state = .on
        configureCheckbox(dotMatchesNewlineButton, title: ".⏎",
                          tooltip: ". matches newline (regex only)")

        let findNext = makeButton("Next", #selector(findNextAction), tooltip: "Find next (⌘G)")
        let findPrevious = makeButton("Previous", #selector(findPreviousAction),
                                      tooltip: "Find previous (⇧⌘G)")
        let count = makeButton("Count", #selector(countAction),
                               tooltip: "Count occurrences")
        let markAll = makeButton("Mark All", #selector(markAllAction),
                                 tooltip: "Highlight every occurrence")
        let close = NSButton()
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark.circle.fill",
                              accessibilityDescription: "Close find bar")
        close.target = self
        close.action = #selector(closeAction)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let findRow = NSStackView(views: [
            findField, modePopUp, matchCaseButton, wholeWordButton, wrapAroundButton,
            dotMatchesNewlineButton,
            findPrevious, findNext, count, markAll, statusLabel, close,
        ])
        findRow.orientation = .horizontal
        findRow.spacing = 6
        findRow.alignment = .centerY
        findField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let replaceButton = makeButton("Replace", #selector(replaceAction),
                                       tooltip: "Replace this occurrence")
        let replaceAllButton = makeButton("Replace All", #selector(replaceAllAction),
                                          tooltip: "Replace every occurrence")
        replaceRow.setViews([replaceField, replaceButton, replaceAllButton], in: .leading)
        replaceRow.orientation = .horizontal
        replaceRow.spacing = 6
        replaceRow.alignment = .centerY
        replaceRow.isHidden = true

        let container = NSStackView(views: [findRow, replaceRow])
        container.orientation = .vertical
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureCheckbox(_ button: NSButton, title: String, tooltip: String) {
        button.setButtonType(.pushOnPushOff)
        button.title = title
        button.toolTip = tooltip
        button.target = self
        button.action = #selector(optionChanged)
        button.setAccessibilityLabel(tooltip)
    }

    private func makeButton(_ title: String, _ action: Selector, tooltip: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.toolTip = tooltip
        return button
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        // bounds, not dirtyRect: see ViewDrawingBoundsTests.
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    // MARK: - State

    func focusFindField(withSelection selection: String?) {
        if let selection, !selection.isEmpty, !selection.contains("\n") {
            findField.stringValue = selection
            syncOptionsFromControls()
        }
        window?.makeFirstResponder(findField)
        findField.selectText(nil)
    }

    func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func syncOptionsFromControls() {
        options.searchText = findField.stringValue
        options.replacementText = replaceField.stringValue
        options.mode = SearchMode(rawValue: modePopUp.selectedTag()) ?? .normal
        options.matchCase = matchCaseButton.state == .on
        options.wholeWord = wholeWordButton.state == .on
        options.wrapAround = wrapAroundButton.state == .on
        options.dotMatchesNewline = dotMatchesNewlineButton.state == .on

        // ". matches newline" and "whole word" only mean something in their
        // respective modes; grey them out elsewhere.
        dotMatchesNewlineButton.isEnabled = options.mode == .regularExpression
        wholeWordButton.isEnabled = options.mode != .regularExpression
    }

    // MARK: - Actions

    @objc private func findFieldAction() {
        syncOptionsFromControls()
        // Return finds the next match; Shift-Return the previous.
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            options.searchBackwards = true
            delegate?.findBarDidRequestFindPrevious(self)
        } else {
            options.searchBackwards = false
            delegate?.findBarDidRequestFindNext(self)
        }
    }

    @objc private func replaceFieldAction() {
        syncOptionsFromControls()
        delegate?.findBarDidRequestReplace(self)
    }

    @objc private func optionChanged() {
        syncOptionsFromControls()
        delegate?.findBarOptionsDidChange(self)
    }

    @objc private func findNextAction() {
        syncOptionsFromControls()
        options.searchBackwards = false
        delegate?.findBarDidRequestFindNext(self)
    }

    @objc private func findPreviousAction() {
        syncOptionsFromControls()
        options.searchBackwards = true
        delegate?.findBarDidRequestFindPrevious(self)
    }

    @objc private func replaceAction() {
        syncOptionsFromControls()
        delegate?.findBarDidRequestReplace(self)
    }

    @objc private func replaceAllAction() {
        syncOptionsFromControls()
        delegate?.findBarDidRequestReplaceAll(self)
    }

    @objc private func countAction() {
        syncOptionsFromControls()
        delegate?.findBarDidRequestCount(self)
    }

    @objc private func markAllAction() {
        syncOptionsFromControls()
        delegate?.findBarDidRequestMarkAll(self)
    }

    @objc private func closeAction() {
        delegate?.findBarDidRequestClose(self)
    }

    override func cancelOperation(_ sender: Any?) {
        delegate?.findBarDidRequestClose(self)
    }
}

// MARK: - Search as you type

extension FindBarView: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSSearchField) === findField else { return }
        syncOptionsFromControls()
        delegate?.findBarSearchTextDidChange(self)
    }
}

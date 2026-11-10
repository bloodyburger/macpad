//
//  TabBarView.swift
//  MacPad
//
//  The document tab bar. AppKit has no control that does this, so it is
//  drawn and hit-tested by hand: many narrow tabs in one row, each with a
//  dirty marker and a close button, reorderable by dragging.
//
//  Deliberately not NSTabView: it centres a small number of wide tabs and has
//  no reordering, no dirty state and no close buttons. People who edit code
//  keep dozens of tabs open, which is the case this has to handle well.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ tabBar: TabBarView, didSelectIndex index: Int)
    func tabBar(_ tabBar: TabBarView, didRequestCloseAtIndex index: Int)
    func tabBar(_ tabBar: TabBarView, didMoveTabFrom sourceIndex: Int, to destinationIndex: Int)
    func tabBar(_ tabBar: TabBarView, didRequestContextMenuAtIndex index: Int, event: NSEvent)
    /// The empty part of the bar was double-clicked, which opens a new
    /// document.
    func tabBarDidRequestNewTab(_ tabBar: TabBarView)
}

struct TabItem {
    let title: String
    let tooltip: String
    let isDirty: Bool
    let isReadOnly: Bool
}

final class TabBarView: NSView, FileDropReceiving {

    weak var delegate: TabBarViewDelegate?

    /// Files dropped on the bar; the window opens them as tabs.
    var onFileDrop: (([URL]) -> Void)?

    private(set) var items: [TabItem] = []
    private(set) var selectedIndex: Int = -1

    // Layout metrics: compact, so many tabs fit.
    private let tabHeight: CGFloat = 26
    private let minTabWidth: CGFloat = 70
    private let maxTabWidth: CGFloat = 220
    private let tabPadding: CGFloat = 10
    private let closeButtonSize: CGFloat = 12
    private let dirtyMarkerSize: CGFloat = 7

    private var hoveredIndex: Int = -1
    private var hoveredCloseIndex: Int = -1

    /// Drag-to-reorder state.
    private var dragSourceIndex: Int = -1
    private var dragCurrentX: CGFloat = 0
    private var isDragging = false

    private var scrollOffset: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: tabHeight)
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpTracking()
    }

    private func setUpTracking() {
        registerForDraggedTypes(FileDrop.acceptedTypes)
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved,
                                            .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
    }

    // MARK: - Content

    func setItems(_ newItems: [TabItem], selectedIndex newSelection: Int) {
        items = newItems
        selectedIndex = newSelection
        invalidateIntrinsicContentSize()
        scrollSelectedTabIntoView()
        needsDisplay = true
    }

    // MARK: - Layout

    private var tabWidth: CGFloat {
        guard !items.isEmpty else { return minTabWidth }
        let available = bounds.width
        let ideal = available / CGFloat(items.count)
        return min(maxTabWidth, max(minTabWidth, ideal))
    }

    private var totalContentWidth: CGFloat {
        tabWidth * CGFloat(items.count)
    }

    private func rect(forTabAt index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * tabWidth - scrollOffset,
               y: 0,
               width: tabWidth,
               height: tabHeight)
    }

    private func closeButtonRect(inTab tabRect: NSRect) -> NSRect {
        NSRect(x: tabRect.maxX - tabPadding - closeButtonSize,
               y: tabRect.midY - closeButtonSize / 2,
               width: closeButtonSize,
               height: closeButtonSize)
    }

    private func tabIndex(at point: NSPoint) -> Int {
        guard !items.isEmpty, tabWidth > 0 else { return -1 }
        let index = Int((point.x + scrollOffset) / tabWidth)
        return items.indices.contains(index) ? index : -1
    }

    private func scrollSelectedTabIntoView() {
        guard items.indices.contains(selectedIndex) else { return }
        let overflow = max(0, totalContentWidth - bounds.width)
        guard overflow > 0 else { scrollOffset = 0; return }

        let tabLeft = CGFloat(selectedIndex) * tabWidth
        let tabRight = tabLeft + tabWidth
        if tabLeft < scrollOffset {
            scrollOffset = tabLeft
        } else if tabRight > scrollOffset + bounds.width {
            scrollOffset = tabRight - bounds.width
        }
        scrollOffset = min(max(0, scrollOffset), overflow)
    }

    override func layout() {
        super.layout()
        scrollSelectedTabIntoView()
    }

    override func scrollWheel(with event: NSEvent) {
        let overflow = max(0, totalContentWidth - bounds.width)
        guard overflow > 0 else { return }
        // Horizontal scrolling through an overflowing tab row.
        let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        scrollOffset = min(max(0, scrollOffset - delta), overflow)
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        let barBackground = isDark
            ? NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1)
            : NSColor(srgbRed: 0.87, green: 0.87, blue: 0.88, alpha: 1)
        barBackground.setFill()
        // bounds, not dirtyRect. On macOS 26 the rect handed to draw(_:) can be
        // the whole window, and painting it covers every neighbouring view.
        bounds.fill()

        for index in items.indices {
            // The tab being dragged is drawn last, on top.
            if isDragging && index == dragSourceIndex { continue }
            drawTab(at: index, rect: rect(forTabAt: index), isDark: isDark)
        }

        if isDragging, items.indices.contains(dragSourceIndex) {
            var floating = rect(forTabAt: dragSourceIndex)
            floating.origin.x = dragCurrentX
            drawTab(at: dragSourceIndex, rect: floating, isDark: isDark, isFloating: true)
        }

        // Bottom separator, except under the selected tab, so the selected tab
        // reads as joined to the editor below it.
        let separator = isDark
            ? NSColor(srgbRed: 0.28, green: 0.29, blue: 0.31, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.72, blue: 0.74, alpha: 1)
        separator.setFill()
        NSRect(x: 0, y: tabHeight - 1, width: bounds.width, height: 1).fill()
        if items.indices.contains(selectedIndex) {
            let selected = rect(forTabAt: selectedIndex)
            selectedTabBackground(isDark: isDark).setFill()
            NSRect(x: selected.minX + 1, y: tabHeight - 1,
                   width: selected.width - 2, height: 1).fill()
        }
    }

    private func selectedTabBackground(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1)
            : NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)
    }

    private func drawTab(at index: Int, rect tabRect: NSRect, isDark: Bool, isFloating: Bool = false) {
        guard items.indices.contains(index) else { return }
        guard tabRect.intersects(bounds) || isFloating else { return }
        let item = items[index]
        let isSelected = index == selectedIndex
        let isHovered = index == hoveredIndex

        let background: NSColor
        if isSelected {
            background = selectedTabBackground(isDark: isDark)
        } else if isHovered {
            background = isDark
                ? NSColor(srgbRed: 0.21, green: 0.22, blue: 0.25, alpha: 1)
                : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        } else {
            background = isDark
                ? NSColor(srgbRed: 0.17, green: 0.18, blue: 0.20, alpha: 1)
                : NSColor(srgbRed: 0.82, green: 0.82, blue: 0.83, alpha: 1)
        }

        let inset = tabRect.insetBy(dx: 0.5, dy: 0)
        if isFloating {
            NSColor.black.withAlphaComponent(0.2).setFill()
            inset.offsetBy(dx: 0, dy: 1).fill()
        }
        background.setFill()
        inset.fill()

        let border = isDark
            ? NSColor(srgbRed: 0.28, green: 0.29, blue: 0.31, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.72, blue: 0.74, alpha: 1)
        border.setFill()
        NSRect(x: inset.maxX - 1, y: 3, width: 1, height: tabHeight - 6).fill()

        // The active tab carries a coloured top edge.
        if isSelected {
            NSColor.controlAccentColor.setFill()
            NSRect(x: inset.minX, y: 0, width: inset.width, height: 2).fill()
        }

        var textRect = tabRect.insetBy(dx: tabPadding, dy: 0)
        textRect.size.width -= closeButtonSize + 4

        // Dirty marker, ahead of the title.
        if item.isDirty {
            let marker = NSRect(x: textRect.minX,
                                y: tabRect.midY - dirtyMarkerSize / 2,
                                width: dirtyMarkerSize,
                                height: dirtyMarkerSize)
            (isDark ? NSColor.systemOrange : NSColor.systemRed).setFill()
            NSBezierPath(ovalIn: marker).fill()
            textRect.origin.x += dirtyMarkerSize + 4
            textRect.size.width -= dirtyMarkerSize + 4
        }

        let titleColor: NSColor = isSelected
            ? (isDark ? .white : .labelColor)
            : (isDark ? NSColor.white.withAlphaComponent(0.65) : .secondaryLabelColor)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11,
                                     weight: isSelected ? .semibold : .regular),
            .foregroundColor: titleColor,
            .paragraphStyle: paragraph,
        ]
        let title = item.isReadOnly ? "\(item.title) 🔒" : item.title
        let size = (title as NSString).size(withAttributes: attributes)
        var drawRect = textRect
        drawRect.origin.y = tabRect.midY - size.height / 2
        drawRect.size.height = size.height
        if drawRect.width > 0 {
            (title as NSString).draw(in: drawRect, withAttributes: attributes)
        }

        // Close button: shown on the selected tab, or on hover.
        if isSelected || isHovered {
            let closeRect = closeButtonRect(inTab: tabRect)
            if index == hoveredCloseIndex {
                (isDark ? NSColor.white.withAlphaComponent(0.2)
                        : NSColor.black.withAlphaComponent(0.12)).setFill()
                NSBezierPath(roundedRect: closeRect.insetBy(dx: -2, dy: -2),
                             xRadius: 3, yRadius: 3).fill()
            }
            let glyph = NSBezierPath()
            let g = closeRect.insetBy(dx: 3, dy: 3)
            glyph.move(to: NSPoint(x: g.minX, y: g.minY))
            glyph.line(to: NSPoint(x: g.maxX, y: g.maxY))
            glyph.move(to: NSPoint(x: g.maxX, y: g.minY))
            glyph.line(to: NSPoint(x: g.minX, y: g.maxY))
            glyph.lineWidth = 1.4
            glyph.lineCapStyle = .round
            titleColor.setStroke()
            glyph.stroke()
        }
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = -1
        hoveredCloseIndex = -1
        needsDisplay = true
    }

    private func updateHover(at point: NSPoint) {
        let index = tabIndex(at: point)
        var closeIndex = -1
        if index >= 0, closeButtonRect(inTab: rect(forTabAt: index)).contains(point) {
            closeIndex = index
        }
        if index != hoveredIndex || closeIndex != hoveredCloseIndex {
            hoveredIndex = index
            hoveredCloseIndex = closeIndex
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = tabIndex(at: point)
        guard index >= 0 else {
            // Double-clicking the empty part of the bar opens a new document.
            if event.clickCount == 2 {
                delegate?.tabBarDidRequestNewTab(self)
            }
            return
        }

        if closeButtonRect(inTab: rect(forTabAt: index)).contains(point) {
            delegate?.tabBar(self, didRequestCloseAtIndex: index)
            return
        }

        if index != selectedIndex {
            delegate?.tabBar(self, didSelectIndex: index)
        }

        // Middle-click-to-close is handled in otherMouseDown; here, begin a
        // potential drag-to-reorder.
        dragSourceIndex = index
        dragCurrentX = rect(forTabAt: index).minX
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard items.indices.contains(dragSourceIndex), items.count > 1 else { return }
        let point = convert(event.locationInWindow, from: nil)

        if !isDragging {
            // Require a small movement before committing to a drag, so a sloppy
            // click does not reorder tabs.
            let origin = rect(forTabAt: dragSourceIndex)
            guard abs(point.x - origin.midX) > 6 else { return }
            isDragging = true
        }

        dragCurrentX = point.x - tabWidth / 2
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isDragging = false
            dragSourceIndex = -1
            needsDisplay = true
        }
        guard isDragging, items.indices.contains(dragSourceIndex) else { return }

        let centre = dragCurrentX + tabWidth / 2 + scrollOffset
        var destination = Int((centre / tabWidth).rounded(.down))
        destination = min(max(0, destination), items.count - 1)
        guard destination != dragSourceIndex else { return }

        delegate?.tabBar(self, didMoveTabFrom: dragSourceIndex, to: destination)
    }

    override func otherMouseDown(with event: NSEvent) {
        // Middle click closes a tab.
        guard event.buttonNumber == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let index = tabIndex(at: point)
        guard index >= 0 else { return }
        delegate?.tabBar(self, didRequestCloseAtIndex: index)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = tabIndex(at: point)
        guard index >= 0 else { return }
        if index != selectedIndex {
            delegate?.tabBar(self, didSelectIndex: index)
        }
        delegate?.tabBar(self, didRequestContextMenuAtIndex: index, event: event)
    }

    // MARK: - File drops

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileDropEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performFileDrop(sender)
    }

    // MARK: - Tooltips

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        removeAllToolTips()
        for index in items.indices {
            let tabRect = rect(forTabAt: index)
            guard tabRect.intersects(bounds) else { continue }
            addToolTip(tabRect, owner: self, userData: nil)
        }
    }

}

// MARK: - Tooltip owner

// NSViewToolTipOwner, not an NSView override: NSView does not declare this.
extension TabBarView: NSViewToolTipOwner {
    func view(_ view: NSView,
              stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        let index = tabIndex(at: point)
        guard items.indices.contains(index) else { return "" }
        return items[index].tooltip
    }
}

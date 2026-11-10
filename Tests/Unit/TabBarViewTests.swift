//
//  TabBarViewTests.swift
//  MacPadTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class TabBarViewTests: XCTestCase {

    private final class RecordingDelegate: TabBarViewDelegate {
        var newTabRequests = 0
        var selections: [Int] = []
        func tabBar(_ tabBar: TabBarView, didSelectIndex index: Int) { selections.append(index) }
        func tabBar(_ tabBar: TabBarView, didRequestCloseAtIndex index: Int) {}
        func tabBar(_ tabBar: TabBarView, didMoveTabFrom sourceIndex: Int, to destinationIndex: Int) {}
        func tabBar(_ tabBar: TabBarView, didRequestContextMenuAtIndex index: Int, event: NSEvent) {}
        func tabBarDidRequestNewTab(_ tabBar: TabBarView) { newTabRequests += 1 }
    }

    private func click(_ view: NSView, at point: NSPoint, count: Int) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 74, width: 600, height: 26)
        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                       location: view.convert(point, to: nil),
                                       modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: count, pressure: 1)!
        view.mouseDown(with: event)
    }

    /// Double-clicking the empty part of the tab bar opens a new document.
    func testDoubleClickOnEmptySpaceRequestsNewTab() {
        let bar = TabBarView(frame: .zero)
        let delegate = RecordingDelegate()
        bar.delegate = delegate
        bar.setItems([TabItem(title: "new 1", tooltip: "", isDirty: false, isReadOnly: false)],
                     selectedIndex: 0)
        // One tab is at most 220 points wide; x = 500 is empty bar.
        click(bar, at: NSPoint(x: 500, y: 13), count: 2)
        XCTAssertEqual(delegate.newTabRequests, 1)
        XCTAssertTrue(delegate.selections.isEmpty)
    }

    func testSingleClickOnEmptySpaceDoesNothing() {
        let bar = TabBarView(frame: .zero)
        let delegate = RecordingDelegate()
        bar.delegate = delegate
        bar.setItems([TabItem(title: "new 1", tooltip: "", isDirty: false, isReadOnly: false)],
                     selectedIndex: 0)
        click(bar, at: NSPoint(x: 500, y: 13), count: 1)
        XCTAssertEqual(delegate.newTabRequests, 0)
    }

    func testDoubleClickOnATabDoesNotOpenANewOne() {
        let bar = TabBarView(frame: .zero)
        let delegate = RecordingDelegate()
        bar.delegate = delegate
        bar.setItems([TabItem(title: "a", tooltip: "", isDirty: false, isReadOnly: false),
                      TabItem(title: "b", tooltip: "", isDirty: false, isReadOnly: false)],
                     selectedIndex: 0)
        // Second tab starts at x = 220.
        click(bar, at: NSPoint(x: 250, y: 13), count: 2)
        XCTAssertEqual(delegate.newTabRequests, 0)
        XCTAssertEqual(delegate.selections, [1])
    }
}

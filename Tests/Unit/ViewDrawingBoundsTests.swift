//
//  ViewDrawingBoundsTests.swift
//  MacPadTests
//
//  Regression test for the blank window on macOS 26.
//
//  AppKit on macOS 26 can hand draw(_:) a dirty rect far larger than the
//  view's bounds -- the whole window, for a view that does not clip to its
//  bounds -- and it honours drawing outside the bounds. A view that fills the
//  dirty rect therefore paints over its neighbours. The status bar, drawn
//  last, covered the editor and the tab bar completely, and nothing but its
//  own label showed. Every hand-drawn view must stay inside its bounds
//  whatever rect it is asked to draw.
//
//  The offscreen render check in EditorWindowController cannot catch this: it
//  passes the view's own bounds as the rect, so there is nothing to overpaint.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class ViewDrawingBoundsTests: XCTestCase {

    private struct Paint {
        let inside: Bool
        let outside: Bool
    }

    /// Draw `view` into a canvas larger than itself, asking it to draw a rect
    /// that covers the whole canvas, and report where paint landed.
    private func paint(_ view: NSView) throws -> Paint {
        let canvasSize = (width: 300, height: 120)
        let viewFrame = NSRect(x: 50, y: 40, width: 200, height: 26)
        view.frame = viewFrame

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: canvasSize.width, pixelsHigh: canvasSize.height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.clear(CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))
        // Put the view's origin where its frame says, as AppKit would.
        cg.translateBy(x: viewFrame.minX, y: viewFrame.minY)
        if view.isFlipped {
            cg.translateBy(x: 0, y: viewFrame.height)
            cg.scaleBy(x: 1, y: -1)
        }
        // An oversized dirty rect, as macOS 26 passes it.
        view.draw(NSRect(x: -1000, y: -1000, width: 3000, height: 3000))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        // NSBitmapImageRep rows run top-down; the view occupies canvas rows
        // 120-66 = 54 through 120-40 = 80.
        func painted(_ x: Int, _ y: Int) -> Bool {
            (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01
        }
        let inside = painted(150, 67)
        let outsidePoints = [(10, 10), (290, 10), (10, 110), (290, 110), (150, 5), (150, 115),
                             (10, 67), (290, 67), (150, 30), (150, 100)]
        let outside = outsidePoints.contains { painted($0.0, $0.1) }
        return Paint(inside: inside, outside: outside)
    }

    func testTabBarDrawsOnlyInsideItsBounds() throws {
        let result = try paint(TabBarView(frame: .zero))
        XCTAssertTrue(result.inside, "the tab bar should paint its own area")
        XCTAssertFalse(result.outside, "the tab bar painted outside its bounds")
    }

    func testStatusBarDrawsOnlyInsideItsBounds() throws {
        let result = try paint(StatusBarView(frame: .zero))
        XCTAssertTrue(result.inside, "the status bar should paint its own area")
        XCTAssertFalse(result.outside, "the status bar painted outside its bounds")
    }

    func testFindBarDrawsOnlyInsideItsBounds() throws {
        let result = try paint(FindBarView(frame: .zero))
        XCTAssertTrue(result.inside, "the find bar should paint its own area")
        XCTAssertFalse(result.outside, "the find bar painted outside its bounds")
    }
}

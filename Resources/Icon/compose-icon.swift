// Turns a square piece of artwork into MacPad's app icon and logo files.
//
// Usage:   swift compose-icon.swift <artwork.png> <output-directory>
//
// The artwork is painted edge to edge (see README.md for how it was made).
// This script gives it Apple's icon shape: the tile occupies 824 of a 1024
// point canvas, with corners rounded at Apple's proportion and a soft shadow
// beneath, transparent outside. It writes:
//
//   MacPad-1024.png         the finished master icon
//   MacPad.iconset/         every size macOS wants, for iconutil
//   MacPad-logo-light.png   icon plus "MacPad" wordmark, dark text, for light pages
//   MacPad-logo-dark.png    the same with white text, for dark pages
//
// make-icns.sh runs this and packs the iconset into MacPad.icns.

import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift compose-icon.swift <artwork.png> <output-directory>\n".utf8))
    exit(64)
}
let artworkURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let artworkImage = NSImage(contentsOf: artworkURL),
      let artwork = artworkImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("could not read \(artworkURL.path)\n".utf8))
    exit(66)
}

// Apple's macOS icon grid, in a 1024 canvas: an 824 tile inset by 100, with
// corners at roughly 22.4 percent of the tile, and a shadow that sits below it.
let canvasSize: CGFloat = 1024
let tileSize: CGFloat = 824
let tileInset: CGFloat = 100
let cornerRatio: CGFloat = 0.2237

func makeContext(width: Int, height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    return context
}

/// Draw the icon at `pixels` square. Everything scales from the 1024 design.
func drawIcon(in context: CGContext, pixels: CGFloat, originX: CGFloat = 0, originY: CGFloat = 0) {
    let scale = pixels / canvasSize
    let tile = CGRect(x: originX + tileInset * scale, y: originY + tileInset * scale,
                      width: tileSize * scale, height: tileSize * scale)
    let radius = tileSize * scale * cornerRatio
    let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Shadow: drawn as a filled shape under the tile so it is clipped by nothing.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.32))
    context.addPath(path)
    context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.3, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // The artwork, clipped to the tile.
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.draw(artwork, in: tile)
    // A faint top highlight and bottom shade give the flat artwork a little
    // glass, the way Apple's own icons sit on screen.
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
                                       CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
                                       CGColor(red: 0, green: 0, blue: 0, alpha: 0.08)] as CFArray,
                              locations: [0, 0.45, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY),
                               end: CGPoint(x: tile.midX, y: tile.minY), options: [])
    context.restoreGState()
}

func writePNG(_ context: CGContext, to url: URL) {
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let iconset = outputDirectory.appendingPathComponent("MacPad.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (file name, pixel size)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    let context = makeContext(width: pixels, height: pixels)
    drawIcon(in: context, pixels: CGFloat(pixels))
    writePNG(context, to: iconset.appendingPathComponent("\(name).png"))
}

let master = makeContext(width: 1024, height: 1024)
drawIcon(in: master, pixels: 1024)
writePNG(master, to: outputDirectory.appendingPathComponent("MacPad-1024.png"))

// Logo: icon on the left, wordmark on the right, transparent background.
func drawLogo(textColor: NSColor, to url: URL) {
    let width = 1700, height = 520
    let context = makeContext(width: width, height: height)
    drawIcon(in: context, pixels: 520, originX: 0, originY: 0)

    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let font = NSFont.systemFont(ofSize: 230, weight: .semibold)
    let rounded = NSFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 230) ?? font
    let attributes: [NSAttributedString.Key: Any] = [
        .font: rounded,
        .foregroundColor: textColor,
        .kern: -4,
    ]
    let text = NSAttributedString(string: "MacPad", attributes: attributes)
    let size = text.size()
    text.draw(at: NSPoint(x: 540, y: (CGFloat(height) - size.height) / 2 + 8))
    NSGraphicsContext.restoreGraphicsState()
    writePNG(context, to: url)
}
drawLogo(textColor: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.18, alpha: 1),
         to: outputDirectory.appendingPathComponent("MacPad-logo-light.png"))
drawLogo(textColor: .white,
         to: outputDirectory.appendingPathComponent("MacPad-logo-dark.png"))

print("wrote icon sizes, master and logos to \(outputDirectory.path)")

#!/usr/bin/env swift

import AppKit
import Foundation

private let paper = NSColor(calibratedRed: 0xF7 / 255, green: 0xF2 / 255, blue: 0xE6 / 255, alpha: 1)
private let surface = NSColor(calibratedRed: 0xFC / 255, green: 0xF8 / 255, blue: 0xEF / 255, alpha: 1)
private let ink = NSColor(calibratedRed: 0x1E / 255, green: 0x1A / 255, blue: 0x13 / 255, alpha: 1)
private let hairline = NSColor(calibratedRed: 0xD9 / 255, green: 0xCF / 255, blue: 0xBB / 255, alpha: 1)
private let terracotta = NSColor(calibratedRed: 0xC2 / 255, green: 0x54 / 255, blue: 0x2B / 255, alpha: 1)

private func line(_ from: NSPoint, _ to: NSPoint, width: CGFloat, color: NSColor) {
    color.setStroke()
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width
    path.move(to: from)
    path.line(to: to)
    path.stroke()
}

private func drawIcon(size: Int, includesWaveform: Bool) -> NSBitmapImageRep {
    let dimension = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    paper.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: dimension, height: dimension)).fill()

    let inset = dimension * 0.065
    let card = NSRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    surface.setFill()
    NSBezierPath(roundedRect: card, xRadius: dimension * 0.05, yRadius: dimension * 0.05).fill()
    hairline.setStroke()
    let border = NSBezierPath(roundedRect: card.insetBy(dx: dimension * 0.018, dy: dimension * 0.018), xRadius: dimension * 0.035, yRadius: dimension * 0.035)
    border.lineWidth = max(1, dimension * 0.006)
    border.stroke()

    let holeRadius = dimension * 0.014
    let pitch = dimension * 0.061
    var position = inset + pitch
    paper.setFill()
    while position < dimension - inset - pitch / 2 {
        for center in [
            NSPoint(x: position, y: inset),
            NSPoint(x: position, y: dimension - inset),
            NSPoint(x: inset, y: position),
            NSPoint(x: dimension - inset, y: position)
        ] {
            NSBezierPath(ovalIn: NSRect(x: center.x - holeRadius, y: center.y - holeRadius, width: holeRadius * 2, height: holeRadius * 2)).fill()
        }
        position += pitch
    }

    let scale = dimension / 1024
    line(NSPoint(x: 238 * scale, y: 304 * scale), NSPoint(x: 782 * scale, y: 304 * scale), width: 13 * scale, color: ink)

    if includesWaveform {
        let heights: [CGFloat] = [36, 72, 112, 160, 104, 58, 92, 138, 78, 44]
        for (index, height) in heights.enumerated() {
            let x = (534 + CGFloat(index) * 27) * scale
            line(NSPoint(x: x, y: (304 - height / 2) * scale), NSPoint(x: x, y: (304 + height / 2) * scale), width: 9 * scale, color: ink)
        }
    }

    terracotta.setStroke()
    let scissors = NSBezierPath()
    scissors.lineWidth = 28 * scale
    scissors.lineCapStyle = .round
    scissors.lineJoinStyle = .round
    scissors.move(to: NSPoint(x: 426 * scale, y: 529 * scale))
    scissors.line(to: NSPoint(x: 690 * scale, y: 742 * scale))
    scissors.move(to: NSPoint(x: 438 * scale, y: 530 * scale))
    scissors.line(to: NSPoint(x: 713 * scale, y: 430 * scale))
    scissors.stroke()

    let ringSize = 174 * scale
    for center in [NSPoint(x: 330 * scale, y: 452 * scale), NSPoint(x: 344 * scale, y: 604 * scale)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - ringSize / 2, y: center.y - ringSize / 2, width: ringSize, height: ringSize))
        ring.lineWidth = 30 * scale
        ring.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let iosDirectory = root.appendingPathComponent("Clip/Resources/Assets.xcassets/AppIcon.appiconset")
private let macDirectory = root.appendingPathComponent("ClipMac/Resources/Assets.xcassets/AppIcon.appiconset")

try writePNG(drawIcon(size: 1024, includesWaveform: false), to: iosDirectory.appendingPathComponent("AppIcon-1024.png"))
let iosContents = """
{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try iosContents.write(to: iosDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let macSizes = [16, 32, 64, 128, 256, 512, 1024]
for size in macSizes {
    try writePNG(drawIcon(size: size, includesWaveform: true), to: macDirectory.appendingPathComponent("AppIcon-\(size).png"))
}
let macContents = """
{
  "images" : [
    { "filename" : "AppIcon-16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "AppIcon-32.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "AppIcon-32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "AppIcon-64.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "AppIcon-128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "AppIcon-256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "AppIcon-256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "AppIcon-512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "AppIcon-512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "AppIcon-1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try macContents.write(to: macDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("Generated Clip app icons.")


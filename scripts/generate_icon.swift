#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

func renderIcon(size: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
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
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }

    let s = CGFloat(size)
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = rect.width * 0.225

    // 1. Rounded squircle background with deep navy-blue gradient
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.08, green: 0.34, blue: 0.82, alpha: 1.0),
        CGColor(red: 0.03, green: 0.14, blue: 0.42, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Subtle inner border
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(max(1, s * 0.012))
    ctx.strokePath()
    ctx.restoreGState()

    // 2. Timer ring in center
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    let radius = s * 0.26

    // Track circle
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.20))
    ctx.setLineWidth(s * 0.055)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Active progress arc
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.88, blue: 1.0, alpha: 1.0))
    ctx.setLineWidth(s * 0.055)
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: radius, startAngle: .pi * 0.5, endAngle: -.pi * 0.85, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // Top stopwatch crown
    let crownWidth = s * 0.11
    let crownHeight = s * 0.045
    let crownRect = CGRect(
        x: center.x - crownWidth / 2,
        y: center.y + radius + s * 0.035,
        width: crownWidth,
        height: crownHeight
    )
    let crownPath = CGPath(roundedRect: crownRect, cornerWidth: crownHeight * 0.4, cornerHeight: crownHeight * 0.4, transform: nil)
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.addPath(crownPath)
    ctx.fillPath()
    ctx.restoreGState()

    // 3. Checkmark inside timer ring
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.98))
    ctx.setLineWidth(s * 0.055)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y - radius * 0.04))
    ctx.addLine(to: CGPoint(x: center.x - radius * 0.10, y: center.y - radius * 0.36))
    ctx.addLine(to: CGPoint(x: center.x + radius * 0.46, y: center.y + radius * 0.30))
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let rootDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputIcnsURL = rootDir.appendingPathComponent("Resources/AppIcon.icns")
let outputPngURL = rootDir.appendingPathComponent("Resources/AppIcon.png")

if let previewRep = renderIcon(size: 256),
   let previewPng = previewRep.representation(using: .png, properties: [:]) {
    try previewPng.write(to: outputPngURL, options: .atomic)
}

let chunkSpecs: [(type: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024)
]

var chunksData = Data()
for spec in chunkSpecs {
    guard let rep = renderIcon(size: spec.pixels),
          let pngData = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    var chunkLen = UInt32(8 + pngData.count).bigEndian
    chunksData.append(contentsOf: spec.type.utf8)
    chunksData.append(Data(bytes: &chunkLen, count: 4))
    chunksData.append(pngData)
}

var icnsData = Data()
icnsData.append(contentsOf: "icns".utf8)
var totalLen = UInt32(8 + chunksData.count).bigEndian
icnsData.append(Data(bytes: &totalLen, count: 4))
icnsData.append(chunksData)

try icnsData.write(to: outputIcnsURL, options: .atomic)
print("Generated icon at \(outputIcnsURL.path) (\(icnsData.count) bytes)")

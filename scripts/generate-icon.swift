import Foundation
import AppKit
import CoreGraphics

// Generates Assets/AppIcon.png (1024x1024) and compiles Assets/AppIcon.icns
let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsDir = rootURL.appendingPathComponent("Assets")
let pngURL = assetsDir.appendingPathComponent("AppIcon.png")
let iconsetURL = assetsDir.appendingPathComponent("AppIcon.iconset")
let icnsURL = assetsDir.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsCtx
let ctx = nsCtx.cgContext
ctx.setShouldAntialias(true)
ctx.setAllowsAntialiasing(true)

// Clear canvas
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// macOS squircle inset (standard optical padding ~100px each side on 1024 canvas -> 824x824 icon body)
let inset: CGFloat = 96
let bodyRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let cornerRadius: CGFloat = 186
let squirclePath = CGPath(
    roundedRect: bodyRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

// Drop shadow behind icon tile
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: NSColor.black.withAlphaComponent(0.55).cgColor)
ctx.addPath(squirclePath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Clip inside squircle
ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()

// Pitch-black gradient background (#0B0B10 top-left -> #000000 bottom-right)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bgColors = [
    CGColor(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x10 / 255.0, alpha: 1.0),
    CGColor(red: 0x03 / 255.0, green: 0x03 / 255.0, blue: 0x05 / 255.0, alpha: 1.0),
    CGColor(red: 0x00 / 255.0, green: 0x00 / 255.0, blue: 0x00 / 255.0, alpha: 1.0)
] as CFArray
let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
    end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
    options: []
)

// Subtle ambient indigo glow (top-right / center-upper)
let indigoGlow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0x7A / 255.0, green: 0x89 / 255.0, blue: 0xFF / 255.0, alpha: 0.24),
        CGColor(red: 0x7A / 255.0, green: 0x89 / 255.0, blue: 0xFF / 255.0, alpha: 0.0)
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawRadialGradient(
    indigoGlow,
    startCenter: CGPoint(x: 590, y: 615),
    startRadius: 10,
    endCenter: CGPoint(x: 590, y: 615),
    endRadius: 340,
    options: []
)

// Subtle ambient coral glow (lower-left)
let coralGlow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0xE8 / 255.0, green: 0x82 / 255.0, blue: 0x55 / 255.0, alpha: 0.20),
        CGColor(red: 0xE8 / 255.0, green: 0x82 / 255.0, blue: 0x55 / 255.0, alpha: 0.0)
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawRadialGradient(
    coralGlow,
    startCenter: CGPoint(x: 410, y: 425),
    startRadius: 10,
    endCenter: CGPoint(x: 410, y: 425),
    endRadius: 310,
    options: []
)

// Minimalist geometric Stratus emblem:
// 1) Crisp layered cloud-strata silhouette in luminous white/silver
let cloudPath = CGMutablePath()
// Base pill + two soft geometric domes forming a clean cloud silhouette
cloudPath.addRoundedRect(
    in: CGRect(x: 274, y: 410, width: 476, height: 156),
    cornerWidth: 78,
    cornerHeight: 78
)
cloudPath.addEllipse(in: CGRect(x: 344, y: 468, width: 236, height: 228))
cloudPath.addEllipse(in: CGRect(x: 516, y: 454, width: 176, height: 176))

ctx.saveGState()
ctx.addPath(cloudPath)
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 28, color: CGColor(red: 0x7A / 255.0, green: 0x89 / 255.0, blue: 0xFF / 255.0, alpha: 0.28))
ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0))
ctx.fillPath()
ctx.restoreGState()

// Soft translucent inner stratum bar carved visually via gradient overlay inside lower cloud band
let lowerStratum = CGPath(
    roundedRect: CGRect(x: 318, y: 438, width: 388, height: 42),
    cornerWidth: 21,
    cornerHeight: 21,
    transform: nil
)
ctx.saveGState()
ctx.addPath(lowerStratum)
ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 0.92))
ctx.fillPath()
ctx.restoreGState()

// T3-inspired 3-segment telemetry accent bar nestled cleanly below the cloud
let barY: CGFloat = 330
let barH: CGFloat = 24
let seg1 = CGRect(x: 300, y: barY, width: 190, height: barH)
let seg2 = CGRect(x: 504, y: barY, width: 134, height: barH)
let seg3 = CGRect(x: 652, y: barY, width: 72, height: barH)

let segments: [(CGRect, CGColor)] = [
    (seg1, CGColor(red: 0xE8 / 255.0, green: 0x82 / 255.0, blue: 0x55 / 255.0, alpha: 1.0)), // Coral
    (seg2, CGColor(red: 0x7A / 255.0, green: 0x89 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)), // Indigo
    (seg3, CGColor(red: 0x4B / 255.0, green: 0xC3 / 255.0, blue: 0xF7 / 255.0, alpha: 1.0))  // Sky
]

for (rect, color) in segments {
    let pill = CGPath(roundedRect: rect, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 14, color: color.copy(alpha: 0.45))
    ctx.addPath(pill)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

// Subtle 2pt inner rim highlight inside the squircle
ctx.saveGState()
let rimRect = bodyRect.insetBy(dx: 1, dy: 1)
let rimPath = CGPath(roundedRect: rimRect, cornerWidth: cornerRadius - 1, cornerHeight: cornerRadius - 1, transform: nil)
ctx.addPath(rimPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
ctx.setLineWidth(2.0)
ctx.strokePath()
ctx.restoreGState()

ctx.restoreGState() // end squircle clip
NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}
try pngData.write(to: pngURL)
print("Wrote \(pngURL.path)")

// Generate required .iconset PNGs using sips
let iconEntries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func runTool(_ path: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        fatalError("\(path) failed with code \(p.terminationStatus)")
    }
}

for (filename, px) in iconEntries {
    let outURL = iconsetURL.appendingPathComponent(filename)
    try runTool("/usr/bin/sips", ["-z", "\(px)", "\(px)", pngURL.path, "--out", outURL.path])
}

try? FileManager.default.removeItem(at: icnsURL)
try runTool("/usr/bin/iconutil", ["-c", "icns", iconsetURL.path, "-o", icnsURL.path])
try? FileManager.default.removeItem(at: iconsetURL)
print("Compiled \(icnsURL.path)")

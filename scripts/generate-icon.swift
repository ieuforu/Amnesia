#!/usr/bin/env swift
// Draws the app icon, a speech bubble dissolving into particles, as a 1024x1024
// PNG at the path given as the first argument.
import AppKit

let size: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func linearGradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

let tilePath = CGPath(roundedRect: tile, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Drop shadow.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0, 0, 0, 0.32))
context.addPath(tilePath)
context.setFillColor(color(0.1, 0.1, 0.2))
context.fillPath()
context.restoreGState()

// Background.
context.saveGState()
context.addPath(tilePath)
context.clip()
context.drawLinearGradient(
    linearGradient([color(0.36, 0.35, 0.93), color(0.11, 0.10, 0.33)]),
    start: CGPoint(x: tile.minX, y: tile.maxY),
    end: CGPoint(x: tile.maxX, y: tile.minY),
    options: []
)
context.drawRadialGradient(
    linearGradient([color(1, 1, 1, 0.20), color(1, 1, 1, 0)]),
    startCenter: CGPoint(x: 360, y: 760),
    startRadius: 0,
    endCenter: CGPoint(x: 360, y: 760),
    endRadius: 560,
    options: []
)
context.restoreGState()

// A deterministic generator, so regenerating gives the same icon.
struct Generator {
    var state: UInt64 = 2026

    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat((state >> 33) % 100_000) / 100_000
    }
}

let bubble = CGRect(x: 214, y: 378, width: 560, height: 392)
let bubblePath = CGMutablePath()
bubblePath.addRoundedRect(in: bubble, cornerWidth: 128, cornerHeight: 128)
bubblePath.move(to: CGPoint(x: 300, y: bubble.minY + 30))
bubblePath.addQuadCurve(to: CGPoint(x: 262, y: 262), control: CGPoint(x: 316, y: 310))
bubblePath.addQuadCurve(to: CGPoint(x: 452, y: bubble.minY + 2), control: CGPoint(x: 380, y: 280))
bubblePath.closeSubpath()

let cell: CGFloat = 20
let dissolveStart: CGFloat = 500
let dissolveEnd: CGFloat = 800
var generator = Generator()

context.saveGState()
context.addPath(tilePath)
context.clip()

// Each row of the bubble ends at a different point, so the break is uneven.
var rows: [(y: CGFloat, end: CGFloat)] = []
var rowY = CGFloat(240)
while rowY < bubble.maxY + cell {
    rows.append((rowY, dissolveStart + generator.next() * 110 - 55))
    rowY += cell
}

context.saveGState()
context.addPath(bubblePath)
context.clip()
context.setFillColor(color(1, 1, 1))
for row in rows {
    let rect = CGRect(x: 0, y: row.y - 0.5, width: row.end, height: cell + 1)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: cell / 2, cornerHeight: cell / 2, transform: nil))
    context.fillPath()
}
context.restoreGState()

// Past each row's end, particles thin out, shrink and drift to the right.
for row in rows {
    var x = row.end + cell / 2
    while x < bubble.maxX + 10 {
        let center = CGPoint(x: x, y: row.y + cell / 2)
        let roll = generator.next()
        let driftRoll = generator.next()
        let scaleRoll = generator.next()
        x += cell

        guard bubblePath.contains(center, using: .winding) else { continue }

        let progress = min(max((center.x - dissolveStart + 55) / (dissolveEnd - dissolveStart + 55), 0), 1)
        guard roll > pow(progress, 0.75) * 0.92 else { continue }

        let dotSize = cell * (1 - progress * 0.68) * (0.78 + scaleRoll * 0.3)
        let drift = progress * progress * 96
        let origin = CGPoint(
            x: center.x + drift * (0.4 + driftRoll) - dotSize / 2,
            y: center.y + drift * (driftRoll - 0.3) - dotSize / 2
        )
        context.setFillColor(color(1, 1, 1, 1 - progress * 0.5))
        context.fillEllipse(in: CGRect(origin: origin, size: CGSize(width: dotSize, height: dotSize)))
    }
}
context.restoreGState()

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try image.representation(using: .png, properties: [:])!.write(to: output)

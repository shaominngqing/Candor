#!/usr/bin/swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: render-dmg-background.swift <output.png>\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = NSSize(width: 660, height: 420)
let canvasRect = NSRect(origin: .zero, size: canvasSize)

func drawText(
    _ value: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .center
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail

    value.draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    )
}

let image = NSImage(size: canvasSize)
image.lockFocus()

let background = NSGradient(
    starting: NSColor(calibratedRed: 0.985, green: 0.987, blue: 0.991, alpha: 1),
    ending: NSColor(calibratedRed: 0.946, green: 0.952, blue: 0.962, alpha: 1)
)
background?.draw(in: canvasRect, angle: -90)

let glow = NSGradient(
    colorsAndLocations: (NSColor(calibratedRed: 0.30, green: 0.64, blue: 0.94, alpha: 0.10), 0),
    (NSColor(calibratedRed: 0.30, green: 0.64, blue: 0.94, alpha: 0), 1)
)
glow?.draw(
    in: NSBezierPath(ovalIn: NSRect(x: 195, y: 52, width: 270, height: 270)),
    relativeCenterPosition: .zero
)

drawText(
    "安装 Candor",
    in: NSRect(x: 40, y: 350, width: 580, height: 30),
    font: .systemFont(ofSize: 23, weight: .semibold),
    color: NSColor(calibratedWhite: 0.12, alpha: 1)
)
drawText(
    "将 Candor 拖到右侧的“应用程序”",
    in: NSRect(x: 40, y: 322, width: 580, height: 22),
    font: .systemFont(ofSize: 13, weight: .regular),
    color: NSColor(calibratedWhite: 0.40, alpha: 1)
)

let arrowColor = NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.84, alpha: 0.82)
let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 270, y: 205))
arrow.line(to: NSPoint(x: 390, y: 205))
arrow.move(to: NSPoint(x: 376, y: 219))
arrow.line(to: NSPoint(x: 390, y: 205))
arrow.line(to: NSPoint(x: 376, y: 191))
arrowColor.setStroke()
arrow.stroke()

let divider = NSBezierPath()
divider.lineWidth = 1
divider.move(to: NSPoint(x: 52, y: 58))
divider.line(to: NSPoint(x: 608, y: 58))
NSColor(calibratedWhite: 0.45, alpha: 0.16).setStroke()
divider.stroke()

drawText(
    "拖放完成后，即可从“应用程序”打开",
    in: NSRect(x: 40, y: 27, width: 580, height: 20),
    font: .systemFont(ofSize: 11.5, weight: .regular),
    color: NSColor(calibratedWhite: 0.48, alpha: 1)
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("Unable to render DMG background\n".utf8))
    exit(70)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)

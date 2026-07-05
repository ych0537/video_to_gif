#!/usr/bin/env swift
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: generate-icon.swift <output.icns>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let fileManager = FileManager.default
let iconsetURL = fileManager.temporaryDirectory
    .appendingPathComponent("Video2GIF-\(UUID().uuidString).iconset")

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer {
    try? fileManager.removeItem(at: iconsetURL)
}

let iconEntries: [(String, CGFloat)] = [
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

for (filename, size) in iconEntries {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = max(3, size * 0.18)
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.05, dy: size * 0.05), xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.50, blue: 0.88, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.74, blue: 0.56, alpha: 1)
    ])
    gradient?.draw(in: background, angle: 135)

    NSColor.white.withAlphaComponent(0.22).setStroke()
    background.lineWidth = max(1, size * 0.025)
    background.stroke()

    let playPath = NSBezierPath()
    playPath.move(to: NSPoint(x: size * 0.31, y: size * 0.59))
    playPath.line(to: NSPoint(x: size * 0.31, y: size * 0.39))
    playPath.line(to: NSPoint(x: size * 0.50, y: size * 0.49))
    playPath.close()
    NSColor.white.setFill()
    playPath.fill()

    let text = "GIF" as NSString
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: max(7, size * 0.18), weight: .black),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    let textRect = NSRect(x: size * 0.16, y: size * 0.17, width: size * 0.68, height: size * 0.24)
    text.draw(in: textRect, withAttributes: attributes)

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(filename)\n", stderr)
        exit(1)
    }
    try png.write(to: iconsetURL.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(process.terminationStatus)
}

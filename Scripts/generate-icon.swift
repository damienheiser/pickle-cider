#!/usr/bin/env swift

import AppKit
import Foundation

// Generate pickle jar icon for PickleCider app
func createPickleJarIcon(size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    let context = NSGraphicsContext.current!.cgContext

    // Background - rounded square
    let bgRect = NSRect(x: size.width * 0.05, y: size.width * 0.05,
                        width: size.width * 0.9, height: size.height * 0.9)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size.width * 0.2, yRadius: size.height * 0.2)

    // Gradient background
    let gradient = NSGradient(colors: [
        NSColor(red: 0.18, green: 0.31, blue: 0.09, alpha: 1.0),  // Dark green
        NSColor(red: 0.10, green: 0.19, blue: 0.04, alpha: 1.0)   // Darker green
    ])!
    gradient.draw(in: bgPath, angle: -45)

    // Jar body
    let jarWidth = size.width * 0.55
    let jarHeight = size.height * 0.6
    let jarX = (size.width - jarWidth) / 2
    let jarY = size.height * 0.15

    let jarRect = NSRect(x: jarX, y: jarY, width: jarWidth, height: jarHeight)
    let jarPath = NSBezierPath(roundedRect: jarRect, xRadius: jarWidth * 0.15, yRadius: jarHeight * 0.1)

    // Jar gradient (glass effect)
    let jarGradient = NSGradient(colors: [
        NSColor(red: 0.66, green: 0.82, blue: 0.55, alpha: 0.9),  // Light green
        NSColor(red: 0.42, green: 0.56, blue: 0.14, alpha: 0.9)   // Medium green
    ])!
    jarGradient.draw(in: jarPath, angle: 0)

    // Jar outline
    NSColor(red: 0.3, green: 0.4, blue: 0.2, alpha: 0.5).setStroke()
    jarPath.lineWidth = size.width * 0.01
    jarPath.stroke()

    // Lid
    let lidWidth = jarWidth * 0.85
    let lidHeight = size.height * 0.08
    let lidX = (size.width - lidWidth) / 2
    let lidY = jarY + jarHeight - lidHeight * 0.3

    let lidRect = NSRect(x: lidX, y: lidY, width: lidWidth, height: lidHeight)
    let lidPath = NSBezierPath(roundedRect: lidRect, xRadius: lidWidth * 0.1, yRadius: lidHeight * 0.3)

    NSColor(red: 0.55, green: 0.27, blue: 0.07, alpha: 1.0).setFill()  // Brown
    lidPath.fill()

    // Pickles inside jar
    let pickleColor1 = NSColor(red: 0.33, green: 0.42, blue: 0.18, alpha: 1.0)  // Dark olive
    let pickleColor2 = NSColor(red: 0.42, green: 0.56, blue: 0.14, alpha: 1.0)  // Olive

    // Pickle 1
    let pickle1 = NSBezierPath()
    pickle1.appendRoundedRect(
        NSRect(x: jarX + jarWidth * 0.15, y: jarY + jarHeight * 0.15,
               width: jarWidth * 0.65, height: jarHeight * 0.12),
        xRadius: jarWidth * 0.1, yRadius: jarHeight * 0.06
    )
    context.saveGState()
    context.translateBy(x: size.width / 2, y: jarY + jarHeight * 0.21)
    context.rotate(by: -0.15)
    context.translateBy(x: -size.width / 2, y: -(jarY + jarHeight * 0.21))
    pickleColor1.setFill()
    pickle1.fill()
    context.restoreGState()

    // Pickle 2
    let pickle2 = NSBezierPath()
    pickle2.appendRoundedRect(
        NSRect(x: jarX + jarWidth * 0.2, y: jarY + jarHeight * 0.32,
               width: jarWidth * 0.55, height: jarHeight * 0.10),
        xRadius: jarWidth * 0.08, yRadius: jarHeight * 0.05
    )
    context.saveGState()
    context.translateBy(x: size.width / 2, y: jarY + jarHeight * 0.37)
    context.rotate(by: 0.1)
    context.translateBy(x: -size.width / 2, y: -(jarY + jarHeight * 0.37))
    pickleColor2.setFill()
    pickle2.fill()
    context.restoreGState()

    // Pickle 3
    let pickle3 = NSBezierPath()
    pickle3.appendRoundedRect(
        NSRect(x: jarX + jarWidth * 0.18, y: jarY + jarHeight * 0.47,
               width: jarWidth * 0.6, height: jarHeight * 0.11),
        xRadius: jarWidth * 0.09, yRadius: jarHeight * 0.055
    )
    context.saveGState()
    context.translateBy(x: size.width / 2, y: jarY + jarHeight * 0.52)
    context.rotate(by: -0.08)
    context.translateBy(x: -size.width / 2, y: -(jarY + jarHeight * 0.52))
    pickleColor1.setFill()
    pickle3.fill()
    context.restoreGState()

    // Liquid overlay
    let liquidRect = NSRect(x: jarX + jarWidth * 0.05, y: jarY + jarHeight * 0.05,
                            width: jarWidth * 0.9, height: jarHeight * 0.75)
    let liquidPath = NSBezierPath(roundedRect: liquidRect, xRadius: jarWidth * 0.12, yRadius: jarHeight * 0.08)
    NSColor(red: 0.6, green: 0.8, blue: 0.2, alpha: 0.2).setFill()
    liquidPath.fill()

    // Glass shine
    let shineRect = NSRect(x: jarX + jarWidth * 0.1, y: jarY + jarHeight * 0.2,
                           width: jarWidth * 0.15, height: jarHeight * 0.5)
    let shinePath = NSBezierPath(ovalIn: shineRect)
    NSColor.white.withAlphaComponent(0.25).setFill()
    shinePath.fill()

    // Spigot
    let spigotX = jarX + jarWidth
    let spigotY = jarY + jarHeight * 0.35

    // Spigot knob
    let knobPath = NSBezierPath(ovalIn: NSRect(x: spigotX - size.width * 0.02, y: spigotY - size.width * 0.04,
                                               width: size.width * 0.08, height: size.width * 0.08))
    NSColor(red: 0.8, green: 0.52, blue: 0.25, alpha: 1.0).setFill()  // Light brown
    knobPath.fill()

    // Spigot pipe
    let pipeRect = NSRect(x: spigotX + size.width * 0.04, y: spigotY - size.width * 0.02,
                          width: size.width * 0.1, height: size.width * 0.04)
    let pipePath = NSBezierPath(rect: pipeRect)
    NSColor(red: 0.55, green: 0.27, blue: 0.07, alpha: 1.0).setFill()  // Brown
    pipePath.fill()

    image.unlockFocus()
    return image
}

func saveIcon(image: NSImage, size: Int, to directory: URL, name: String) {
    let resizedImage = NSImage(size: NSSize(width: size, height: size))
    resizedImage.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
               operation: .copy, fraction: 1.0)
    resizedImage.unlockFocus()

    guard let tiffData = resizedImage.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for size \(size)")
        return
    }

    let filePath = directory.appendingPathComponent(name)
    do {
        try pngData.write(to: filePath)
        print("Created: \(name)")
    } catch {
        print("Failed to write \(name): \(error)")
    }
}

// Main
let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: generate-icon.swift <output-directory>")
    exit(1)
}

let outputDir = URL(fileURLWithPath: args[1])
let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")

// Create iconset directory
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Generate base icon at high resolution
let baseIcon = createPickleJarIcon(size: NSSize(width: 1024, height: 1024))

// Generate all required sizes
let sizes: [(size: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

for (size, scale, name) in sizes {
    saveIcon(image: baseIcon, size: size * scale, to: iconsetDir, name: name)
}

print("\nIconset created at: \(iconsetDir.path)")
print("Run: iconutil -c icns \(iconsetDir.path)")

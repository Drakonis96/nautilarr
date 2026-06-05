#!/usr/bin/env swift
// Builds the 1024×1024 dark-mode / "Midnight" app icon: the same submarine logo
// composited WHOLE (no crop), centred on an opaque near-black background. Used for
// the system dark-appearance variant of AppIcon and the in-app "Midnight"
// alternate icon. Run from repo root:
//   swift Scripts/make_dark_icon.swift
import AppKit
import CoreGraphics
import Foundation

let root = FileManager.default.currentDirectoryPath
let logoURL = URL(fileURLWithPath: root + "/logo.png")
guard let nsLogo = NSImage(contentsOf: logoURL),
      let logo = nsLogo.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not load logo.png")
}

let side: CGFloat = 1024
let out = NSImage(size: NSSize(width: side, height: side))
out.lockFocus()

// Opaque near-black background (iOS icons may not contain alpha). A hair above
// pure black so it doesn't merge into a black home screen but still reads "dark".
NSColor(srgbRed: 0.04, green: 0.05, blue: 0.07, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()

// Draw the full (square) logo centred at ~84% of the canvas.
let cw = CGFloat(logo.width), ch = CGFloat(logo.height)
let target = side * 0.84
let scale = min(target / cw, target / ch)
let dw = cw * scale, dh = ch * scale
let rect = NSRect(x: (side - dw) / 2, y: (side - dh) / 2, width: dw, height: dh)
NSImage(cgImage: logo, size: NSSize(width: cw, height: ch)).draw(in: rect)

out.unlockFocus()

guard let tiff = out.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}

// Primary AppIcon dark-appearance variant.
let dest = root + "/App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024-dark.png"
try! png.write(to: URL(fileURLWithPath: dest))
print("✓ Wrote \(dest) — artwork \(Int(dw))×\(Int(dh)) on 1024 canvas")

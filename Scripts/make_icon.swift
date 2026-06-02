#!/usr/bin/env swift
// Builds the 1024×1024 app icon from logo.png. The artwork is already a square,
// centred composition, so it's drawn WHOLE (no cropping — which previously
// mis-framed the conning tower) and centred on an opaque ocean gradient with a
// uniform margin (iOS icons may not contain alpha). Run from repo root:
//   swift Scripts/make_icon.swift
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

let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.80, green: 0.92, blue: 0.97, alpha: 1),   // foam (top)
    ending:   NSColor(srgbRed: 0.09, green: 0.64, blue: 0.78, alpha: 1)    // teal (bottom)
)!
gradient.draw(in: NSRect(x: 0, y: 0, width: side, height: side), angle: -90)

// Draw the full (square) logo centred, fitting it to ~84% of the canvas so it
// reads large but keeps an even margin on every side.
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
let dest = root + "/App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
try! png.write(to: URL(fileURLWithPath: dest))
print("✓ Wrote \(dest) — artwork \(Int(dw))×\(Int(dh)) on 1024 canvas")

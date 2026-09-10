#!/usr/bin/env swift
//
//  Renders the SelahBeat app icon at every size Xcode needs.
//
//  Generated rather than hand-drawn so it stays in step with Theme.swift — if
//  the palette changes again, edit the constants below and re-run:
//
//      swift Scripts/GenerateAppIcon.swift
//
//  The mark is a metronome: a tapered body with the pendulum and its weight
//  knocked out of it. Solid shapes and one strong contrast pair, because an
//  icon has to survive being drawn at 16 points in a Finder list.
//

import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// MARK: - Palette (matches Theme.swift "Midnight Blue + Sky")

let skyLight: UInt32 = 0x7DD3FC
let sky: UInt32 = 0x38BDF8
let backdropTop: UInt32 = 0x16202E
let backdropBottom: UInt32 = 0x070B12
let cutout: UInt32 = 0x070B12

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: - Shapes

/// A rounded trapezoid — the metronome body.
func metronomeBody(cx: CGFloat, topY: CGFloat, botY: CGFloat,
                   topHalf: CGFloat, botHalf: CGFloat, radius: CGFloat) -> CGPath {
    let a = CGPoint(x: cx - topHalf, y: topY)
    let b = CGPoint(x: cx + topHalf, y: topY)
    let c = CGPoint(x: cx + botHalf, y: botY)
    let d = CGPoint(x: cx - botHalf, y: botY)

    let path = CGMutablePath()
    path.move(to: CGPoint(x: (a.x + b.x) / 2, y: topY))
    path.addArc(tangent1End: b, tangent2End: c, radius: radius)
    path.addArc(tangent1End: c, tangent2End: d, radius: radius)
    path.addArc(tangent1End: d, tangent2End: a, radius: radius)
    path.addArc(tangent1End: a, tangent2End: b, radius: radius)
    path.closeSubpath()
    return path
}

func roundedRect(center: CGPoint, width: CGFloat, height: CGFloat,
                 radius: CGFloat, rotation: CGFloat) -> CGPath {
    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: rotation)
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: &transform)
}

// MARK: - Drawing

func drawIcon(into ctx: CGContext, size S: CGFloat, macOSStyle: Bool) {
    // Work top-left down, which is easier to reason about for layout.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icons sit inside the standard squircle with breathing room; iOS
    // icons are full-bleed and the system applies its own mask.
    let inset: CGFloat = macOSStyle ? S * 0.096 : 0
    let side = S - inset * 2
    let ox = inset, oy = inset
    let contentRect = CGRect(x: ox, y: oy, width: side, height: side)
    let contentPath: CGPath = macOSStyle
        ? CGPath(roundedRect: contentRect, cornerWidth: side * 0.2255,
                 cornerHeight: side * 0.2255, transform: nil)
        : CGPath(rect: contentRect, transform: nil)

    if macOSStyle {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.014),
                      blur: side * 0.035, color: color(0x000000, 0.45))
        ctx.addPath(contentPath)
        ctx.setFillColor(color(backdropBottom))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(contentPath)
    ctx.clip()

    // Backdrop
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [color(backdropTop), color(backdropBottom)] as CFArray,
                                 locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: ox, y: oy),
                               end: CGPoint(x: ox + side, y: oy + side),
                               options: [])
    }

    // A soft glow behind the mark, so the body doesn't sit on a flat field.
    if let glow = CGGradient(colorsSpace: space,
                             colors: [color(sky, 0.22), color(sky, 0)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawRadialGradient(glow,
                               startCenter: CGPoint(x: ox + side * 0.5, y: oy + side * 0.30),
                               startRadius: 0,
                               endCenter: CGPoint(x: ox + side * 0.5, y: oy + side * 0.30),
                               endRadius: side * 0.58,
                               options: [])
    }

    // Metronome body.
    //
    // Small renders use a larger, wider mark inside the same canvas. Keeping
    // the large-size proportions would leave a 16px icon as an unreadable
    // speck floating in the middle of its inset.
    let bold = S <= 64
    let cx = ox + side * 0.5
    let topY = oy + side * (bold ? 0.125 : 0.185)
    let botY = oy + side * (bold ? 0.790 : 0.775)
    let body = metronomeBody(cx: cx, topY: topY, botY: botY,
                             topHalf: side * (bold ? 0.120 : 0.105),
                             botHalf: side * (bold ? 0.330 : 0.295),
                             radius: side * (bold ? 0.030 : 0.038))

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    if let bodyGradient = CGGradient(colorsSpace: space,
                                     colors: [color(skyLight), color(sky)] as CFArray,
                                     locations: [0, 1]) {
        ctx.drawLinearGradient(bodyGradient,
                               start: CGPoint(x: cx, y: topY),
                               end: CGPoint(x: cx, y: botY),
                               options: [])
    }

    // Pendulum and weight, knocked out of the body.
    //
    // The lean is kept shallow enough that the rounded tip stays inside the
    // tapering sides — a tip clipped by the body edge reads as a mistake.
    // Below 64px the rod and weight are drawn proportionally bolder, because
    // at 16px the display proportions would land under one pixel and vanish.
    let angle: CGFloat = 0.22                      // ~12.5 degrees, leaning right
    let pivot = CGPoint(x: cx, y: botY - side * 0.06)
    let tipY = topY + side * (bold ? 0.13 : 0.10)
    let rodLength = (pivot.y - tipY) / cos(angle)
    let tip = CGPoint(x: pivot.x + sin(angle) * rodLength, y: tipY)

    ctx.setStrokeColor(color(cutout))
    ctx.setLineWidth(side * (bold ? 0.105 : 0.052))
    ctx.setLineCap(.round)
    ctx.move(to: pivot)
    ctx.addLine(to: tip)
    ctx.strokePath()

    let weightCenter = CGPoint(x: pivot.x + (tip.x - pivot.x) * 0.44,
                               y: pivot.y + (tip.y - pivot.y) * 0.44)
    ctx.addPath(roundedRect(center: weightCenter,
                            width: side * (bold ? 0.235 : 0.160),
                            height: side * (bold ? 0.130 : 0.090),
                            radius: side * 0.022, rotation: angle))
    ctx.setFillColor(color(cutout))
    ctx.fillPath()
    ctx.restoreGState()

    // Base plate, overlapping the body slightly so the rounded bottom corners
    // don't leave notches where the two meet.
    ctx.addPath(roundedRect(center: CGPoint(x: cx, y: botY + side * (bold ? 0.020 : 0.014)),
                            width: side * (bold ? 0.800 : 0.720),
                            height: side * (bold ? 0.085 : 0.064),
                            radius: side * 0.028, rotation: 0))
    ctx.setFillColor(color(sky))
    ctx.fillPath()

    ctx.restoreGState()
}

func renderPNG(pixels: Int, macOSStyle: Bool, to url: URL) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "icon", code: 1)
    }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    drawIcon(into: ctx, size: CGFloat(pixels), macOSStyle: macOSStyle)

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 2)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 3) }
}

// MARK: - Emit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let macSet = root.appendingPathComponent("Apps/macOS/Assets.xcassets/AppIcon.appiconset")
let iosSet = root.appendingPathComponent("Apps/iOS/Assets.xcassets/AppIcon.appiconset")
for dir in [macSet, iosSet] {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

let macSizes = [16, 32, 64, 128, 256, 512, 1024]
for px in macSizes {
    try renderPNG(pixels: px, macOSStyle: true, to: macSet.appendingPathComponent("icon_\(px).png"))
}
try renderPNG(pixels: 1024, macOSStyle: false, to: iosSet.appendingPathComponent("icon_1024.png"))

print("Wrote \(macSizes.count) macOS icons and 1 iOS icon")

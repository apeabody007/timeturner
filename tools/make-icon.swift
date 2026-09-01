// Draws TimeTurner's app icon: the hourglass mid-drain, warm sand on the
// same dark plate as Redline, so the two apps read as a family.
//
// Every size is drawn natively rather than downsampled from one master, so
// the strokes stay crisp at 16pt where a scaled-down 1024 would turn to mush.
//
//   swift tools/make-icon.swift            writes Resources/TimeTurner.icns
//
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func drawIcon(size: Double) -> CGImage? {
    guard let context = CGContext(data: nil, width: Int(size), height: Int(size),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // macOS leaves a margin around the artwork and rounds it into a squircle.
    let inset = size * 0.098
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plate.width * 0.225
    let plateShape = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius,
                            transform: nil)

    context.saveGState()
    context.addPath(plateShape)
    context.clip()
    let backdrop = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1),
                                       CGColor(red: 0.05, green: 0.06, blue: 0.07, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(backdrop,
                               start: CGPoint(x: plate.midX, y: plate.maxY),
                               end: CGPoint(x: plate.midX, y: plate.minY),
                               options: [])
    context.restoreGState()

    // The glass. Two triangular bulbs meeting at a narrow neck, capped by
    // bars, the same geometry the menu bar icon draws at 18 points.
    let cx = plate.midX
    let capHalf = plate.width * 0.30
    let glassHalf = plate.width * 0.255
    let capTopY = plate.maxY - plate.height * 0.185
    let capBotY = plate.minY + plate.height * 0.185
    let bulbTopY = capTopY - plate.height * 0.035
    let bulbBotY = capBotY + plate.height * 0.035
    let waistY = (capTopY + capBotY) / 2
    let neckHalf = plate.width * 0.028
    let stroke = max(size * 0.026, 1)

    let topBulb = CGMutablePath()
    topBulb.move(to: CGPoint(x: cx - glassHalf, y: bulbTopY))
    topBulb.addLine(to: CGPoint(x: cx + glassHalf, y: bulbTopY))
    topBulb.addLine(to: CGPoint(x: cx + neckHalf, y: waistY))
    topBulb.addLine(to: CGPoint(x: cx - neckHalf, y: waistY))
    topBulb.closeSubpath()

    let bottomBulb = CGMutablePath()
    bottomBulb.move(to: CGPoint(x: cx - neckHalf, y: waistY))
    bottomBulb.addLine(to: CGPoint(x: cx + neckHalf, y: waistY))
    bottomBulb.addLine(to: CGPoint(x: cx + glassHalf, y: bulbBotY))
    bottomBulb.addLine(to: CGPoint(x: cx - glassHalf, y: bulbBotY))
    bottomBulb.closeSubpath()

    // Sand, mid-drain: the surface has fallen in the top bulb, the pile has
    // built in the bottom, and a thread of it is falling through the neck.
    let sand = CGColor(red: 0.89, green: 0.75, blue: 0.50, alpha: 1)
    let fraction = 0.62
    context.setFillColor(sand)

    context.saveGState()
    context.addPath(topBulb)
    context.clip()
    context.fill(CGRect(x: cx - glassHalf, y: waistY,
                        width: glassHalf * 2,
                        height: (bulbTopY - waistY) * (1 - fraction)))
    context.restoreGState()

    let pile = (waistY - bulbBotY) * fraction
    context.saveGState()
    context.addPath(bottomBulb)
    context.clip()
    context.fill(CGRect(x: cx - glassHalf, y: bulbBotY,
                        width: glassHalf * 2, height: pile))
    context.restoreGState()

    let streamWidth = max(stroke * 0.8, 1)
    context.fill(CGRect(x: cx - streamWidth / 2, y: bulbBotY + pile,
                        width: streamWidth, height: waistY - (bulbBotY + pile)))

    // Glass and caps, stroked over the sand.
    let glassInk = CGColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 0.92)
    context.setStrokeColor(glassInk)
    context.setLineWidth(stroke)
    context.setLineJoin(.round)
    context.addPath(topBulb)
    context.addPath(bottomBulb)
    context.strokePath()

    context.setLineCap(.round)
    context.setLineWidth(stroke * 1.7)
    context.move(to: CGPoint(x: cx - capHalf, y: capTopY))
    context.addLine(to: CGPoint(x: cx + capHalf, y: capTopY))
    context.move(to: CGPoint(x: cx - capHalf, y: capBotY))
    context.addLine(to: CGPoint(x: cx + capHalf, y: capBotY))
    context.strokePath()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not create \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/TimeTurner.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The ten entries iconutil expects.
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        guard let image = drawIcon(size: Double(pixels)) else { continue }
        let suffix = scale == 2 ? "@2x" : ""
        write(image, to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}

let resources = root.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path,
                     "-o", resources.appendingPathComponent("TimeTurner.icns").path]
try convert.run()
convert.waitUntilExit()
guard convert.terminationStatus == 0 else { exit(convert.terminationStatus) }
print("Wrote Resources/TimeTurner.icns")

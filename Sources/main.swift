import AppKit
import ServiceManagement

// TimeTurner, a menu bar hourglass. The sand drains over the current clock
// hour, and at the top of every hour the glass turns itself over.

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first != "--render",
   let unknown = arguments.first(where: { !["--demo"].contains($0) }) {
    let usage = """
        TimeTurner, a menu bar hourglass that turns over on the hour.

          TimeTurner                show the hourglass (default)
          TimeTurner --demo         thirty-second hours, to preview the turn
          TimeTurner --render DIR   write sample icon frames to DIR and exit
          TimeTurner --help         show this
        """
    if unknown == "--help" || unknown == "-h" {
        print(usage)
        exit(0)
    }
    FileHandle.standardError.write(Data("unknown option: \(unknown)\n\n\(usage)\n".utf8))
    exit(2)
}

let demo = CommandLine.arguments.contains("--demo")
let period: TimeInterval = demo ? 30 : 3600

// Measured against local clock hours, so the glass turns at 4:00 sharp even in
// a half-hour-offset timezone.
func secondsIntoCycle(_ date: Date = Date()) -> TimeInterval {
    let local = date.timeIntervalSince1970
        + TimeInterval(TimeZone.current.secondsFromGMT(for: date))
    return local.truncatingRemainder(dividingBy: period)
}

func cycleIndex(_ date: Date = Date()) -> Int {
    let local = date.timeIntervalSince1970
        + TimeInterval(TimeZone.current.secondsFromGMT(for: date))
    return Int(local / period)
}

// MARK: - Drawing

// The glass, drawn fresh for every frame. `fraction` is how much of the hour
// has drained into the bottom bulb, `angle` rotates the whole glass for the
// turn. Drawn in black and marked as a template image so the menu bar tints
// it correctly for light and dark appearances.
func hourglassImage(fraction: Double, angle: Double) -> NSImage {
    let side: CGFloat = 18
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        ctx.translateBy(x: side / 2, y: side / 2)
        ctx.rotate(by: CGFloat(angle) * .pi / 180)
        ctx.translateBy(x: -side / 2, y: -side / 2)

        let left: CGFloat = 4.0
        let right: CGFloat = 14.0
        let capTop: CGFloat = 15.75
        let capBottom: CGFloat = 2.25
        let bulbTop = capTop - 1.0
        let bulbBottom = capBottom + 1.0
        let waist = side / 2
        let cx = side / 2
        let neck: CGFloat = 1.0 // half-width of the opening between the bulbs

        let topBulb = NSBezierPath()
        topBulb.move(to: NSPoint(x: left, y: bulbTop))
        topBulb.line(to: NSPoint(x: right, y: bulbTop))
        topBulb.line(to: NSPoint(x: cx + neck, y: waist))
        topBulb.line(to: NSPoint(x: cx - neck, y: waist))
        topBulb.close()

        let bottomBulb = NSBezierPath()
        bottomBulb.move(to: NSPoint(x: cx - neck, y: waist))
        bottomBulb.line(to: NSPoint(x: cx + neck, y: waist))
        bottomBulb.line(to: NSPoint(x: right, y: bulbBottom))
        bottomBulb.line(to: NSPoint(x: left, y: bulbBottom))
        bottomBulb.close()

        NSColor.black.setFill()
        NSColor.black.setStroke()

        // Sand. The top surface falls as the hour passes, the bottom pile rises.
        let f = CGFloat(min(max(fraction, 0), 1))
        ctx.saveGState()
        topBulb.addClip()
        ctx.fill(CGRect(x: left, y: waist,
                        width: right - left, height: (bulbTop - waist) * (1 - f)))
        ctx.restoreGState()

        let pile = (waist - bulbBottom) * f
        ctx.saveGState()
        bottomBulb.addClip()
        ctx.fill(CGRect(x: left, y: bulbBottom, width: right - left, height: pile))
        ctx.restoreGState()

        // The falling stream, while there is still sand to fall.
        if f > 0 && f < 1 {
            ctx.fill(CGRect(x: cx - 0.35, y: bulbBottom + pile,
                            width: 0.7, height: waist - (bulbBottom + pile)))
        }

        // Glass and caps, stroked over the sand.
        topBulb.lineWidth = 1.0
        topBulb.stroke()
        bottomBulb.lineWidth = 1.0
        bottomBulb.stroke()
        let caps = NSBezierPath()
        caps.move(to: NSPoint(x: left - 1, y: capTop))
        caps.line(to: NSPoint(x: right + 1, y: capTop))
        caps.move(to: NSPoint(x: left - 1, y: capBottom))
        caps.line(to: NSPoint(x: right + 1, y: capBottom))
        caps.lineWidth = 1.5
        caps.stroke()

        return true
    }
    image.isTemplate = true
    return image
}

// `TimeTurner --render DIR` writes sample frames of the icon as PNGs on a
// white background, so a drawing change can be eyeballed without waiting for
// the top of the hour.
if arguments.first == "--render" {
    let dir = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : ".")
    let frames: [(String, Double, Double)] = [
        ("f000", 0.00, 0), ("f025", 0.25, 0), ("f050", 0.50, 0),
        ("f075", 0.75, 0), ("f100", 1.00, 0),
        ("turn045", 1.00, 45), ("turn090", 1.00, 90), ("turn135", 1.00, 135),
    ]
    let pixels = 108 // 18 points at 6x, big enough to inspect
    for (name, fraction, angle) in frames {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        hourglassImage(fraction: fraction, angle: angle)
            .draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }
    exit(0)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var tick: Timer?
    private var turning: Timer?
    private var lastCycle = cycleIndex()
    private var lastDrawnFraction = -1.0
    private var glassWindow: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        draw(fraction: secondsIntoCycle() / period, angle: 0)
        showGlass()

        tick = Timer.scheduledTimer(withTimeInterval: demo ? 0.25 : 1.0,
                                    repeats: true) { [weak self] _ in
            self?.tock()
        }
        tick?.tolerance = demo ? 0.05 : 0.3
    }

    private func tock() {
        guard turning == nil else { return } // the turn animation owns the icon
        let cycle = cycleIndex()
        if cycle != lastCycle {
            lastCycle = cycle
            startTurn()
            return
        }
        // Redraw only when the sand has visibly moved, about 1% of the bulb.
        let fraction = secondsIntoCycle() / period
        if abs(fraction - lastDrawnFraction) > 0.01 {
            draw(fraction: fraction, angle: 0)
        }
    }

    private func startTurn() {
        let start = Date()
        let duration = 0.9
        turning = Timer.scheduledTimer(withTimeInterval: 1.0 / 30,
                                       repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let p = min(1, Date().timeIntervalSince(start) / duration)
            let eased = p * p * (3 - 2 * p)
            // The bottom bulb is full; rotating it 180 degrees lands it as a
            // full top bulb, which is exactly the new hour's starting state.
            self.draw(fraction: 1, angle: eased * 180)
            if p >= 1 {
                timer.invalidate()
                self.turning = nil
                self.draw(fraction: secondsIntoCycle() / period, angle: 0)
            }
        }
    }

    private func draw(fraction: Double, angle: Double) {
        lastDrawnFraction = fraction
        statusItem.button?.image = hourglassImage(fraction: fraction, angle: angle)
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show the Hourglass",
                              action: #selector(showGlass), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        loginItem = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit TimeTurner",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let remaining = period - secondsIntoCycle()
        if demo {
            statusLine.title = "Turns in \(Int(remaining.rounded())) seconds"
        } else {
            let minutes = Int((remaining / 60).rounded(.up))
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            statusLine.title = minutes <= 1
                ? "Turns in under a minute"
                : "Turns in \(minutes) minutes, at \(formatter.string(from: Date().addingTimeInterval(remaining)))"
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showGlass() {
        if glassWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "TimeTurner"
            w.minSize = NSSize(width: 220, height: 300)
            w.isReleasedWhenClosed = false
            w.contentView = GlassView()
            w.setFrameAutosaveName("TimeTurnerGlass")
            if w.frame.origin == .zero { w.center() }
            glassWindow = w
        }
        glassWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSSound.beep()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

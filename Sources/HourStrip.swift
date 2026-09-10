import AppKit

// The hour laid out as sixty characters, one a minute, shown when the pointer
// rests on the menu bar icon. The menu already says how long until the turn in
// words; this says where in the hour you are, which is the part a sentence is
// bad at. It reuses the vocabulary the glass established: done *, running o,
// still to come ., and break sand ~.

/// Sits invisibly over the status item's button and reports the pointer
/// crossing it. `.activeAlways` is the part that matters: without it the
/// tracking area only fires while TimeTurner is frontmost, which it never is.
/// Hit testing returns nil so the click still reaches the button, which owns
/// the menu.
final class StatusHoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    private var isInside = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { report(true) }
    override func mouseExited(with event: NSEvent) { report(false) }

    private func report(_ inside: Bool) {
        guard inside != isInside else { return }
        isInside = inside
        onHover?(inside)
    }
}

/// The panel itself: tick marks, the strip, and one line saying which slot you
/// are in and how long is left of it.
final class HourStripView: NSView {
    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let tickFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
    private static let inset: CGFloat = 13
    private static let gap: CGFloat = 7

    /// Every glyph is the same width, which is what lets a tick label be
    /// parked over the exact minute it names.
    private static var glyphWidth: CGFloat {
        "0".size(withAttributes: [.font: font]).width
    }

    static func idealSize() -> NSSize {
        let lineHeight = "0".size(withAttributes: [.font: font]).height
        let tickHeight = "0".size(withAttributes: [.font: tickFont]).height
        return NSSize(width: glyphWidth * 60 + inset * 2,
                      height: inset * 2 + tickHeight + lineHeight * 2 + gap * 2)
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let phase = currentPhase()
        let width = Self.glyphWidth
        let lineHeight = "0".size(withAttributes: [.font: Self.font]).height

        let strip = NSMutableAttributedString()
        let now = currentMinute()
        for (minute, glyph) in hourGlyphs().enumerated() {
            let color: NSColor
            if minute == now {
                color = .labelColor
            } else if minute < now {
                color = .secondaryLabelColor
            } else {
                color = .tertiaryLabelColor
            }
            strip.append(NSAttributedString(string: String(glyph),
                                            attributes: [.font: Self.font,
                                                         .foregroundColor: color]))
        }

        // Bottom up: status line, strip, ticks.
        let statusY = Self.inset
        let stripY = statusY + lineHeight + Self.gap
        let tickY = stripY + lineHeight + 2

        strip.draw(at: NSPoint(x: Self.inset, y: stripY))

        // Ticks name the boundaries of the grid, or the quarters when the grid
        // is off, so a glyph can be read back as a time.
        let ticks = pomodoro ? [0, 25, 30, 55] : [0, 15, 30, 45]
        let tickAttrs: [NSAttributedString.Key: Any] =
            [.font: Self.tickFont, .foregroundColor: NSColor.tertiaryLabelColor]
        for minute in ticks {
            let label = String(format: ":%02d", minute)
            label.draw(at: NSPoint(x: Self.inset + CGFloat(minute) * width, y: tickY),
                       withAttributes: tickAttrs)
        }

        let remaining = max(0, phase.remaining)
        let clock = String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)
        let left = pomodoro ? slotLabel(phase) : "the hour"
        let right = pomodoro
            ? (phase.isBreak ? "\(clock) back to work" : "\(clock) to the break")
            : "\(clock) to the turn"

        let leftAttrs: [NSAttributedString.Key: Any] =
            [.font: Self.font,
             .foregroundColor: phase.isBreak ? NSColor.secondaryLabelColor : NSColor.labelColor]
        let rightAttrs: [NSAttributedString.Key: Any] =
            [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]

        left.draw(at: NSPoint(x: Self.inset, y: statusY), withAttributes: leftAttrs)
        let rightWidth = right.size(withAttributes: rightAttrs).width
        right.draw(at: NSPoint(x: bounds.width - Self.inset - rightWidth, y: statusY),
                   withAttributes: rightAttrs)
    }
}

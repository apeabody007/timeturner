import AppKit

// The glass window: a resizable pane holding an hourglass built entirely out
// of keyboard characters. The frame is = / \ ( ), the sand is . : ; , * o.
// Grains fall through the neck on the same clock as the menu bar icon, so a
// full hour really takes an hour to drain. Everything is a plain falling-sand
// simulation over a character grid sized to the window.

final class GlassView: NSView {
    private enum Cell {
        case empty
        case wall(Character)
        case sand(Character)
    }

    private var grid: [[Cell]] = []
    private var rows = 0
    private var cols = 0
    private var interior: [Range<Int>] = [] // open columns per row, inside the glass
    private var waistRow = 0
    private var neckCol = 0
    private var total = 0   // grains in play this glass
    private var passed = 0  // grains that have gone through the neck
    private var cycle = currentPhase().cycle
    private var timer: Timer?

    private static let gridFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let font = GlassView.gridFont
    private var cellSize = CGSize(width: 8, height: 16)

    // The countdown under the glass: how much of the hour is left before the
    // turn, in thin monospaced digits so the ticking doesn't jitter.
    private static let timeStrip: CGFloat = 56
    private let timeStrip = GlassView.timeStrip
    private let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 27, weight: .ultraLight)

    // The turn: the whole glass rotates, frozen, then the sand is handed to
    // the new orientation and left to collapse.
    private var turnAngle: Double = 0
    private var turnTimer: Timer?
    private var ticks = 0
    private var lastSecond = -1

    // The joining toast: shown when pomodoro mode comes on, so it is obvious
    // you just stepped into a slot that was already running on the clock.
    private var toast: String?
    private var toastBorn = Date.distantPast

    func announceJoin() {
        toast = "joined \(slotLabel(currentPhase()))"
        toastBorn = Date()
        needsDisplay = true
    }

    // Work sand and break sand are different materials.
    private static let workGrains: [Character] = [".", ".", ".", ":", ":", ";", ",", "*", "o"]
    private static let breakGrains: [Character] = ["~", "~", "~", "-", "-", ","]
    private var grainSet: [Character] {
        currentPhase().isBreak ? Self.breakGrains : Self.workGrains
    }

    // The row pitch is tightened below the font's natural line height so the
    // ink of consecutive \ and / wall glyphs actually meets; at full leading
    // the diagonals read as disconnected dashes.
    private static func cellMetrics() -> CGSize {
        let probe = "0".size(withAttributes: [.font: gridFont])
        return CGSize(width: probe.width, height: ceil(probe.height * 0.68))
    }

    // The glass looks best when the funnel walls step exactly one column per
    // row: solid unbroken \ and / diagonals, no ledges. That happens when the
    // grid is rows + 2 columns wide, so the default window size is derived
    // from the font to land precisely on that geometry.
    static func idealContentSize(rows: Int = 29) -> NSSize {
        let cell = cellMetrics()
        return NSSize(width: CGFloat(rows + 2) * cell.width + 1,
                      height: CGFloat(rows) * cell.height + timeStrip + 1)
    }

    // TIMETURNER_TRACE=1 in the environment logs what the view is doing to
    // stderr, for chasing a repaint that only misbehaves on one screen.
    private static let tracing = ProcessInfo.processInfo.environment["TIMETURNER_TRACE"] != nil
    private static var traceStart = Date()
    static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        let t = String(format: "%7.3f", Date().timeIntervalSince(traceStart))
        FileHandle.standardError.write(Data("[\(t)] \(message())\n".utf8))
    }
    static func brief(_ r: NSRect) -> String {
        String(format: "%.1fx%.1f@%.1f,%.1f", r.width, r.height, r.origin.x, r.origin.y)
    }

    override var isFlipped: Bool { true }

    // draw() fills every pixel of the view before anything else, so AppKit
    // has no reason to clear the window background underneath first. Saying
    // so is what stops that clear showing through as a flash between frames.
    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Layer backing double buffers the view. Without it a redraw this
        // frequent, with this many glyphs, can be shown half finished.
        wantsLayer = true
        // AppKit's default policy regenerates a layer-backed view's contents
        // on its own schedule, including mid-resize and when the view moves
        // between screens, and each regeneration starts from a cleared layer.
        // Redrawing only when asked is what keeps that clear off the screen.
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.isOpaque = true
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        // Core Animation cross fades a layer's contents by default. On a view
        // that repaints itself all day that fade is the blink: every repaint
        // dissolves the old glass into the new one. The sand should move,
        // not the picture.
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(),
                          "position": NSNull(), "onOrderIn": NSNull(),
                          "onOrderOut": NSNull(), "sublayers": NSNull()]
        guard timer == nil else { return }
        cellSize = Self.cellMetrics()
        rebuild()
        timer = Timer.scheduledTimer(withTimeInterval: demo ? 0.05 : 0.1,
                                     repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.step()
        }
    }

    // Moving to another screen can change the backing scale. A layer keeps
    // rendering at its old scale until it is told, and repaints itself to
    // catch up, which reads as a flash.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        Self.trace("backingPropertiesChanged scale=\(window?.backingScaleFactor ?? 0)"
                   + " screen=\(window?.screen?.localizedName ?? "none")")
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard cellSize.width > 1 else { return }
        if grid.isEmpty { rebuild(); return }
        // A move between screens can hand back the size we already have. The
        // glass is only rebuilt when the grid it implies actually differs,
        // so a no-op resize cannot churn the sand.
        let (c, r) = Self.gridSize(for: bounds, cell: cellSize, strip: timeStrip)
        Self.trace("setFrameSize \(Self.brief(NSRect(origin: .zero, size: newSize)))"
                   + " grid \(cols)x\(rows) -> \(c)x\(r)"
                   + (c != cols || r != rows ? " RESHAPE" : " (no-op)"))
        guard c != cols || r != rows else { return }
        reshape()
    }

    // The grid the given bounds imply. Kept in one place so setFrameSize can
    // ask the question without building anything.
    static func gridSize(for bounds: NSRect, cell: CGSize, strip: CGFloat) -> (Int, Int) {
        var c = max(Int(bounds.width / cell.width), 15)
        let r = max(Int((bounds.height - strip) / cell.height), 11)
        if c % 2 == 0 { c -= 1 }
        return (c, r)
    }

    // MARK: - Building the glass

    // Rebuilds the walls for the current window size and reseats the sand to
    // match the current point in the hour. The hourly turn and a wake from
    // sleep both come through here; a live resize goes through reshape()
    // instead, so the sand tumbles rather than teleporting.
    private func rebuild() {
        buildWalls()
        seed()
        needsDisplay = true
    }

    private func buildWalls() {
        (cols, rows) = Self.gridSize(for: bounds, cell: cellSize, strip: timeStrip)
        waistRow = rows / 2
        neckCol = cols / 2

        grid = Array(repeating: Array(repeating: Cell.empty, count: cols), count: rows)
        interior = Array(repeating: 0..<0, count: rows)

        let capL = 1
        let capR = cols - 2
        for c in capL...capR {
            grid[0][c] = .wall("=")
            grid[rows - 1][c] = .wall("=")
        }

        // Top funnel, narrowing to a one-cell gap at the waist.
        for r in 1..<waistRow {
            let t = waistRow > 2 ? Double(r - 1) / Double(waistRow - 1) : 1
            let lw = capL + Int((t * Double(neckCol - 1 - capL)).rounded())
            let rw = capR - Int((t * Double(capR - neckCol - 1)).rounded())
            grid[r][lw] = .wall("\\")
            grid[r][rw] = .wall("/")
            interior[r] = (lw + 1)..<rw
        }
        // The waist itself: a one-cell gate between parentheses.
        grid[waistRow][neckCol - 1] = .wall("(")
        grid[waistRow][neckCol + 1] = .wall(")")
        interior[waistRow] = neckCol..<(neckCol + 1)
        // Bottom funnel, widening back out.
        for r in (waistRow + 1)...(rows - 2) {
            let span = rows - 2 - waistRow
            let t = span > 0 ? Double(r - waistRow) / Double(span) : 1
            let lw = neckCol - 1 - Int((t * Double(neckCol - 1 - capL)).rounded())
            let rw = neckCol + 1 + Int((t * Double(capR - neckCol - 1)).rounded())
            grid[r][lw] = .wall("/")
            grid[r][rw] = .wall("\\")
            interior[r] = (lw + 1)..<rw
        }
    }

    // Seats the sand for this point in the hour. The top chamber fills from
    // the neck up, the bottom pile grows as a cone from the floor.
    private func seed() {
        var topCells: [(Int, Int)] = []
        for r in 1..<waistRow { for c in interior[r] { topCells.append((r, c)) } }
        topCells.sort {
            $0.0 != $1.0 ? $0.0 > $1.0 : abs($0.1 - neckCol) < abs($1.1 - neckCol)
        }
        var bottomCells: [(Int, Int)] = []
        for r in (waistRow + 1)...(rows - 2) { for c in interior[r] { bottomCells.append((r, c)) } }
        bottomCells.sort {
            ((rows - 2 - $0.0) + abs($0.1 - neckCol)) < ((rows - 2 - $1.0) + abs($1.1 - neckCol))
        }

        total = topCells.count
        passed = min(total, Int(currentPhase().fraction * Double(total)))
        for (r, c) in topCells.prefix(total - passed) { grid[r][c] = .sand(grainSet.randomElement()!) }
        for (r, c) in bottomCells.prefix(passed) { grid[r][c] = .sand(grainSet.randomElement()!) }
    }

    // MARK: - Resizing with the sand in place

    // Carries the grains through a resize. Each grain remembers where it sat
    // as a fraction of its chamber; after the walls are rebuilt it is put back
    // down at the nearest open cell to that spot, and the simulation tumbles
    // everything into the new shape. Grain counts rescale with the new
    // capacity so the hour keeps its meaning.
    private func reshape() {
        let oldWaist = waistRow, oldRows = rows, oldCols = cols, oldNeck = neckCol
        let oldHalfW = max(Double(oldCols - 3) / 2, 1)
        var tops: [(ny: Double, nx: Double)] = []
        var bots: [(ny: Double, nx: Double)] = []
        for r in 0..<oldRows {
            for c in 0..<oldCols {
                guard case .sand = grid[r][c] else { continue }
                let nx = Double(c - oldNeck) / oldHalfW
                if r < oldWaist {
                    tops.append((Double(r - 1) / Double(max(oldWaist - 2, 1)), nx))
                } else {
                    bots.append((Double(r - oldWaist - 1) / Double(max(oldRows - 3 - oldWaist, 1)), nx))
                }
            }
        }

        buildWalls()

        total = (1..<waistRow).reduce(0) { $0 + interior[$1].count }
        passed = min(total, Int(currentPhase().fraction * Double(total)))

        // Trim or pad each chamber's grains to the new capacity's share.
        func fit(_ grains: [(ny: Double, nx: Double)], to n: Int) -> [(ny: Double, nx: Double)] {
            var out = Array(grains.shuffled().prefix(n))
            while out.count < n { out.append(grains.randomElement() ?? (0, 0)) }
            return out
        }

        func place(_ grains: [(ny: Double, nx: Double)], rowRange: Range<Int>) {
            let newHalfW = max(Double(cols - 3) / 2, 1)
            var homeless = 0
            for g in grains {
                let span = max(rowRange.count - 1, 1)
                let r0 = rowRange.lowerBound
                    + min(span, max(0, Int((g.ny * Double(span)).rounded())))
                let c0 = neckCol + Int((g.nx * newHalfW).rounded())
                var placed = false
                // The spot itself, else straight up from it: sand stacks, then
                // the simulation topples it.
                for r in stride(from: r0, through: rowRange.lowerBound, by: -1) {
                    guard !interior[r].isEmpty else { continue }
                    let c = min(max(c0, interior[r].lowerBound), interior[r].upperBound - 1)
                    if case .empty = grid[r][c] {
                        grid[r][c] = .sand(grainSet.randomElement()!)
                        placed = true
                        break
                    }
                }
                if !placed { homeless += 1 }
            }
            if homeless > 0 {
                var free: [(Int, Int)] = []
                for r in rowRange {
                    for c in interior[r] {
                        if case .empty = grid[r][c] { free.append((r, c)) }
                    }
                }
                for (r, c) in free.shuffled().prefix(homeless) {
                    grid[r][c] = .sand(grainSet.randomElement()!)
                }
            }
        }

        place(fit(tops, to: total - passed), rowRange: 1..<waistRow)
        place(fit(bots, to: passed), rowRange: (waistRow + 1)..<(rows - 1))
        needsDisplay = true
    }

    // MARK: - Turning the glass over

    // The glass rotates as one piece, frozen, the way a real one does in your
    // hand: the sand is held by friction while it swings, not poured.
    private func startTurn() {
        turnTimer?.invalidate()
        let start = Date()
        let duration = demo ? 0.6 : 0.9
        turnTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30,
                                         repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, Date().timeIntervalSince(start) / duration)
            self.turnAngle = (t * t * (3 - 2 * t)) * 180
            self.needsDisplay = true
            if t >= 1 {
                timer.invalidate()
                self.turnTimer = nil
                self.turnAngle = 0
                self.invert()
                self.needsDisplay = true
            }
        }
    }

    // Hands the sand to the new orientation. A 180 degree turn maps every
    // cell to its opposite, row r to rows - 1 - r and column c to
    // cols - 1 - c, and the glass is built symmetrically, so walls land on
    // walls. What lands in the top chamber is the bottom pile upside down: a
    // cone balanced on its point, which is exactly as unstable as it sounds.
    // The simulation collapses and levels it over the next second, which is
    // what real sand does the moment you set a flipped hourglass down.
    private func invert() {
        var carried: [(Int, Int)] = []
        for r in 0..<rows {
            for c in 0..<cols {
                if case .sand = grid[r][c] {
                    carried.append((rows - 1 - r, cols - 1 - c))
                }
            }
        }

        buildWalls()

        var homeless = 0
        for (r, c) in carried {
            guard r >= 0, r < rows, interior[r].contains(c),
                  case .empty = grid[r][c] else { homeless += 1; continue }
            grid[r][c] = .sand(grainSet.randomElement()!)
        }
        // Rounding at the walls can strand a grain or two; drop them in the
        // top chamber rather than losing sand across the turn.
        if homeless > 0 {
            var free: [(Int, Int)] = []
            for r in 1..<waistRow {
                for c in interior[r] {
                    if case .empty = grid[r][c] { free.append((r, c)) }
                }
            }
            for (r, c) in free.shuffled().prefix(homeless) {
                grid[r][c] = .sand(grainSet.randomElement()!)
            }
        }

        total = (1..<waistRow).reduce(0) { $0 + interior[$1].count }
        passed = min(total, Int(currentPhase().fraction * Double(total)))
    }

    // MARK: - The simulation

    private func open(_ r: Int, _ c: Int) -> Bool {
        guard r >= 0, r < rows, interior[r].contains(c) else { return false }
        if case .empty = grid[r][c] { return true }
        return false
    }

    func step() {
        let cyc = currentPhase().cycle
        if cyc != cycle {
            // One boundary crossed while watching earns the animation. A
            // bigger jump means the window was closed or the Mac asleep
            // through it, so there is nothing to animate: just be right.
            let jumped = cyc - cycle != 1
            cycle = cyc
            if jumped { rebuild() } else { startTurn() }
            return
        }
        if turnTimer != nil { return } // the turn owns the glass while it runs
        let expected = min(total, Int(currentPhase().fraction * Double(total)))
        if expected - passed > 30 {
            rebuild() // slept through a stretch; reseat rather than fast-forward
            return
        }

        // One falling-sand sweep, bottom-up so a grain moves once per tick.
        // The neck is a gate: it only opens while the hour says a grain is due.
        var released = 0
        var moved = false
        var moveCount = 0
        var diagonalCount = 0
        let gateCap = demo ? 3 : 2
        for r in stride(from: rows - 2, through: 1, by: -1) {
            for c in interior[r].shuffled() {
                guard case .sand = grid[r][c] else { continue }
                var target: (Int, Int)? = nil
                let sides = Bool.random() ? [c - 1, c + 1] : [c + 1, c - 1]
                if open(r + 1, c) {
                    target = (r + 1, c)
                } else if let s = sides.first(where: { open(r + 1, $0) && open(r, $0) }) {
                    // A grain can only roll into a column it could actually
                    // reach: the cell beside it has to be free too. Without
                    // that it squeezes diagonally between two packed
                    // neighbours, and a finished pile never stops repacking
                    // itself, one grain a tick, forever.
                    target = (r + 1, s)
                }
                if let (tr, tc) = target {
                    if tr == waistRow && tc == neckCol {
                        guard passed < expected, released < gateCap else { continue }
                        released += 1
                        passed += 1
                    }
                    grid[tr][tc] = grid[r][c]
                    grid[r][c] = .empty
                    moved = true
                    moveCount += 1
                    if tr != r + 1 || tc != c { diagonalCount += 1 }
                }
            }
        }

        let sandMoved = moved
        let levelled = levelTopChamber()
        if levelled { moved = true }

        // A little shimmer in the resting piles, so the sand reads as alive.
        // An hour glass drops a grain every ten seconds or so, so this is
        // most of what there is to see; once a second is plenty, and it
        // keeps a resting glass from repainting itself ten times a second.
        ticks += 1
        var shimmered = false
        if ticks % (demo ? 4 : 10) == 0 {
            for _ in 0..<2 {
                let r = Int.random(in: 1..<rows - 1)
                guard let c = interior[r].randomElement(), case .sand = grid[r][c] else { continue }
                grid[r][c] = .sand(grainSet.randomElement()!)
                shimmered = true
                moved = true
            }
        }

        // The digits tick over once a second and the toast fades on its own,
        // so both ask for their own repaints. Everything else waits for the
        // sand to actually move.
        let secondsLeft = Int(max(0, currentPhase().remaining))
        if secondsLeft != lastSecond {
            lastSecond = secondsLeft
            moved = true
        }
        if toast != nil { moved = true }

        Self.trace("step moves=\(moveCount) diag=\(diagonalCount)"
                   + " level=\(levelled) shimmer=\(shimmered)"
                   + " released=\(released) sec=\(secondsLeft) toast=\(toast != nil)"
                   + " -> repaint=\(moved)")
        if moved { needsDisplay = true }
    }

    // Real sand keeps a level surface. In a wide window the funnel walls
    // slope shallower than the grains' 45 degree tumble, so sand would sit on
    // the corner ledges forever; this pass lets the high spots flow sideways,
    // a few grains a tick, until no column in the top chamber stands more
    // than a grain above its neighbor.
    private func levelTopChamber() -> Bool {
        guard waistRow > 2 else { return false }
        var surface = [Int?](repeating: nil, count: cols) // topmost sand row
        var landing = [Int?](repeating: nil, count: cols) // where a grain would rest
        for r in 1..<waistRow {
            for c in interior[r] {
                if case .sand = grid[r][c] {
                    if surface[c] == nil { surface[c] = r }
                } else if case .empty = grid[r][c], surface[c] == nil {
                    landing[c] = r // deepest open cell above the column's sand
                }
            }
        }

        // Move the highest peak's top grain to the lowest hollow, a few
        // grains a tick, until the whole surface is within a grain of flat.
        var moves = 6
        while moves > 0 {
            var peak: Int? = nil
            var hollow: Int? = nil
            for c in (0..<cols).shuffled() {
                if let s = surface[c], peak == nil || s < surface[peak!]! { peak = c }
                if let l = landing[c], hollow == nil || l > landing[hollow!]! { hollow = c }
            }
            // Any strictly lower hollow is fair game: every move descends, so
            // this terminates, and the surface settles truly flat.
            guard let p = peak, let h = hollow, p != h,
                  let s = surface[p], let land = landing[h], land >= s + 1 else { break }
            grid[land][h] = grid[s][p]
            grid[s][p] = .empty
            surface[h] = land
            landing[h] = land - 1 >= 1 && interior[land - 1].contains(h) ? land - 1 : nil
            landing[p] = s
            if s + 1 < waistRow, interior[s + 1].contains(p),
               case .sand = grid[s + 1][p] {
                surface[p] = s + 1
            } else {
                surface[p] = nil
            }
            moves -= 1
        }
        return moves < 6
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        Self.trace("draw dirty=\(Self.brief(dirtyRect)) bounds=\(Self.brief(bounds))"
                   + " grid=\(cols)x\(rows) scale=\(window?.backingScaleFactor ?? 0)"
                   + " screen=\(window?.screen?.localizedName ?? "none")")
        NSColor.textBackgroundColor.setFill()
        // The invalidated area can reach past the view's own bounds; an
        // opaque view has to leave none of it unpainted.
        dirtyRect.union(bounds).fill()
        guard rows > 0 else { return }

        let wallAttrs: [NSAttributedString.Key: Any] =
            [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let sandAttrs: [NSAttributedString.Key: Any] =
            [.font: font, .foregroundColor: NSColor.labelColor]

        let x0 = (bounds.width - CGFloat(cols) * cellSize.width) / 2
        let y0 = (bounds.height - timeStrip - CGFloat(rows) * cellSize.height) / 2

        // Mid-turn the whole glass is drawn rotated about its own center. The
        // characters are centrally symmetric, so a rotated glass is still a
        // glass: \ stays \, / stays /, = stays =, and ( becomes the ) that
        // belongs on the far side of the neck.
        let ctx = NSGraphicsContext.current?.cgContext
        if turnAngle != 0 {
            let w = CGFloat(cols) * cellSize.width
            let h = CGFloat(rows) * cellSize.height
            let gx = x0 + w / 2
            let gy = y0 + h / 2
            // A rotating rectangle sweeps a bigger box than it occupies at
            // rest, so the glass is scaled to whatever still fits and grows
            // back to full size as it lands. It reads as the glass receding
            // a little while it turns, the way one does in your hand.
            let radians = CGFloat(turnAngle) * .pi / 180
            let sweptW = abs(w * cos(radians)) + abs(h * sin(radians))
            let sweptH = abs(w * sin(radians)) + abs(h * cos(radians))
            let fit = min(bounds.width / sweptW,
                          (bounds.height - timeStrip) / sweptH, 1)
            ctx?.saveGState()
            ctx?.translateBy(x: gx, y: gy)
            ctx?.rotate(by: radians)
            ctx?.scaleBy(x: fit, y: fit)
            ctx?.translateBy(x: -gx, y: -gy)
        }

        for r in 0..<rows {
            let line = NSMutableAttributedString()
            for c in 0..<cols {
                switch grid[r][c] {
                case .empty: line.append(NSAttributedString(string: " ", attributes: wallAttrs))
                case .wall(let ch): line.append(NSAttributedString(string: String(ch), attributes: wallAttrs))
                case .sand(let ch): line.append(NSAttributedString(string: String(ch), attributes: sandAttrs))
                }
            }
            line.draw(at: NSPoint(x: x0, y: y0 + CGFloat(r) * cellSize.height))
        }

        if turnAngle != 0 { ctx?.restoreGState() } // the countdown stays upright

        // The countdown, centered in the strip under the glass. Break time
        // draws dimmer, so the color of the number is the color of the hour.
        let p = currentPhase()
        let remaining = max(0, p.remaining)
        let text = String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)
        let attrs: [NSAttributedString.Key: Any] =
            [.font: timeFont,
             .foregroundColor: p.isBreak ? NSColor.secondaryLabelColor : NSColor.labelColor]
        let size = text.size(withAttributes: attrs)
        let stripTop = y0 + CGFloat(rows) * cellSize.height
        let lift: CGFloat = pomodoro ? 7 : 0
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: stripTop + (timeStrip - size.height) / 2 - lift),
                  withAttributes: attrs)

        // The joining toast, floating in the bottom bulb's airspace: holds
        // for a moment, then dissolves.
        if let message = toast {
            let age = Date().timeIntervalSince(toastBorn)
            let alpha = age < 2.5 ? 1.0 : max(0, 1 - (age - 2.5) / 1.5)
            if alpha <= 0 {
                toast = nil
            } else {
                let toastAttrs: [NSAttributedString.Key: Any] =
                    [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                     .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha)]
                let mSize = message.size(withAttributes: toastAttrs)
                message.draw(at: NSPoint(x: (bounds.width - mSize.width) / 2,
                                         y: y0 + CGFloat(waistRow + 3) * cellSize.height),
                             withAttributes: toastAttrs)
            }
        }

        // In pomodoro mode, the hour's two pomodoros as grains under the
        // digits: done *, running o, still to come .
        if pomodoro {
            let states = [p.segment < 2 ? (p.isBreak ? "*" : "o") : "*",
                          p.segment < 2 ? "." : (p.isBreak ? "*" : "o")]
            let dotAttrs: [NSAttributedString.Key: Any] =
                [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                 .foregroundColor: NSColor.secondaryLabelColor]
            let dots = states.joined(separator: "  ")
            let dotSize = dots.size(withAttributes: dotAttrs)
            dots.draw(at: NSPoint(x: (bounds.width - dotSize.width) / 2,
                                  y: stripTop + (timeStrip - size.height) / 2 - lift
                                     + size.height + 1),
                      withAttributes: dotAttrs)
        }
    }
}

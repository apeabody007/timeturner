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
    private var total = 0   // grains in play this hour
    private var passed = 0  // grains that have gone through the neck
    private var cycle = cycleIndex()
    private var timer: Timer?

    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private var cellSize = CGSize(width: 8, height: 16)

    // The countdown under the glass: how much of the hour is left before the
    // turn, in thin monospaced digits so the ticking doesn't jitter.
    private let timeStrip: CGFloat = 44
    private let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 27, weight: .ultraLight)

    private static let grains: [Character] = [".", ".", ".", ":", ":", ";", ",", "*", "o"]

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard timer == nil else { return }
        let probe = "0".size(withAttributes: [.font: font])
        cellSize = CGSize(width: probe.width, height: ceil(probe.height))
        rebuild()
        timer = Timer.scheduledTimer(withTimeInterval: demo ? 0.05 : 0.1,
                                     repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.step()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard cellSize.width > 1 else { return }
        if grid.isEmpty { rebuild() } else { reshape() }
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
        cols = max(Int(bounds.width / cellSize.width), 15)
        rows = max(Int((bounds.height - timeStrip) / cellSize.height), 11)
        if cols % 2 == 0 { cols -= 1 } // odd width keeps the neck centered
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
        passed = min(total, Int(secondsIntoCycle() / period * Double(total)))
        for (r, c) in topCells.prefix(total - passed) { grid[r][c] = .sand(Self.grains.randomElement()!) }
        for (r, c) in bottomCells.prefix(passed) { grid[r][c] = .sand(Self.grains.randomElement()!) }
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
        passed = min(total, Int(secondsIntoCycle() / period * Double(total)))

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
                        grid[r][c] = .sand(Self.grains.randomElement()!)
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
                    grid[r][c] = .sand(Self.grains.randomElement()!)
                }
            }
        }

        place(fit(tops, to: total - passed), rowRange: 1..<waistRow)
        place(fit(bots, to: passed), rowRange: (waistRow + 1)..<(rows - 1))
        needsDisplay = true
    }

    // MARK: - The simulation

    private func open(_ r: Int, _ c: Int) -> Bool {
        guard r >= 0, r < rows, interior[r].contains(c) else { return false }
        if case .empty = grid[r][c] { return true }
        return false
    }

    func step() {
        let cyc = cycleIndex()
        if cyc != cycle {
            cycle = cyc
            rebuild() // the turn: a fresh hour, top bulb full again
            return
        }
        let expected = min(total, Int(secondsIntoCycle() / period * Double(total)))
        if expected - passed > 30 {
            rebuild() // slept through a stretch; reseat rather than fast-forward
            return
        }

        // One falling-sand sweep, bottom-up so a grain moves once per tick.
        // The neck is a gate: it only opens while the hour says a grain is due.
        var released = 0
        let gateCap = demo ? 3 : 2
        for r in stride(from: rows - 2, through: 1, by: -1) {
            for c in interior[r].shuffled() {
                guard case .sand = grid[r][c] else { continue }
                var target: (Int, Int)? = nil
                let sides = Bool.random() ? [c - 1, c + 1] : [c + 1, c - 1]
                if open(r + 1, c) {
                    target = (r + 1, c)
                } else if let s = sides.first(where: { open(r + 1, $0) }) {
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
                }
            }
        }

        levelTopChamber()

        // A little shimmer in the resting piles, so the sand reads as alive.
        for _ in 0..<2 {
            let r = Int.random(in: 1..<rows - 1)
            guard let c = interior[r].randomElement(), case .sand = grid[r][c] else { continue }
            grid[r][c] = .sand(Self.grains.randomElement()!)
        }
        needsDisplay = true
    }

    // Real sand keeps a level surface. In a wide window the funnel walls
    // slope shallower than the grains' 45 degree tumble, so sand would sit on
    // the corner ledges forever; this pass lets the high spots flow sideways,
    // a few grains a tick, until no column in the top chamber stands more
    // than a grain above its neighbor.
    private func levelTopChamber() {
        guard waistRow > 2 else { return }
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
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        guard rows > 0 else { return }

        let wallAttrs: [NSAttributedString.Key: Any] =
            [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let sandAttrs: [NSAttributedString.Key: Any] =
            [.font: font, .foregroundColor: NSColor.labelColor]

        let x0 = (bounds.width - CGFloat(cols) * cellSize.width) / 2
        let y0 = (bounds.height - timeStrip - CGFloat(rows) * cellSize.height) / 2
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

        // The countdown, centered in the strip under the glass.
        let remaining = max(0, period - secondsIntoCycle())
        let text = String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)
        let attrs: [NSAttributedString.Key: Any] =
            [.font: timeFont, .foregroundColor: NSColor.labelColor]
        let size = text.size(withAttributes: attrs)
        let stripTop = y0 + CGFloat(rows) * cellSize.height
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: stripTop + (timeStrip - size.height) / 2),
                  withAttributes: attrs)
    }
}

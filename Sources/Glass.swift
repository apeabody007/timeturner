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
            self?.tick()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if cellSize.width > 1 { rebuild() }
    }

    // MARK: - Building the glass

    // Rebuilds the walls for the current window size and reseats the sand to
    // match the current point in the hour. Because the state is derived from
    // the clock, a resize, a wake from sleep, and the hourly turn are all the
    // same operation.
    private func rebuild() {
        cols = max(Int(bounds.width / cellSize.width), 15)
        rows = max(Int(bounds.height / cellSize.height), 11)
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

        // Seat the sand for this point in the hour. The top chamber fills from
        // the neck up, the bottom pile grows as a cone from the floor.
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
        needsDisplay = true
    }

    // MARK: - The simulation

    private func open(_ r: Int, _ c: Int) -> Bool {
        guard r >= 0, r < rows, interior[r].contains(c) else { return false }
        if case .empty = grid[r][c] { return true }
        return false
    }

    private func tick() {
        guard window?.isVisible == true else { return }

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

        // A little shimmer in the resting piles, so the sand reads as alive.
        for _ in 0..<2 {
            let r = Int.random(in: 1..<rows - 1)
            guard let c = interior[r].randomElement(), case .sand = grid[r][c] else { continue }
            grid[r][c] = .sand(Self.grains.randomElement()!)
        }
        needsDisplay = true
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
        let y0 = (bounds.height - CGFloat(rows) * cellSize.height) / 2
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
    }
}

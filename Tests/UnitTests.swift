import Foundation

// The clock grid, checked at exact minutes instead of whenever the suite
// happens to run. Everything here is pure arithmetic over a date, so a whole
// hour can be walked through in milliseconds.

var failures = 0

/// A date at a given local wall clock time. Local, because the grid is
/// measured against local hours: the glass turns at 4:00 sharp even in a
/// half-hour-offset timezone, and these cases have to hold there too.
func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    var parts = DateComponents()
    parts.year = 2026
    parts.month = 9
    parts.day = 10
    parts.hour = hour
    parts.minute = minute
    parts.second = second
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    return calendar.date(from: parts)!
}

func check(_ name: String, _ got: String, _ expected: String) {
    let ok = got == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name.padding(toLength: 40, withPad: " ", startingAt: 0)) \(got)" +
          (ok ? "" : "  expected \(expected)"))
}

func checkClose(_ name: String, _ got: Double, _ expected: Double, _ tolerance: Double = 0.001) {
    let ok = abs(got - expected) < tolerance
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name.padding(toLength: 40, withPad: " ", startingAt: 0)) " +
          "\(String(format: "%.4f", got))" +
          (ok ? "" : "  expected \(String(format: "%.4f", expected))"))
}

/// The slot a moment falls in, as one string, so a boundary case reads as one
/// line rather than four separate assertions.
func slot(_ date: Date) -> String {
    let phase = currentPhase(date)
    return "seg \(phase.segment) \(phase.isBreak ? "break" : "work ") \(slotLabel(phase))"
}

// MARK: - The pomodoro grid: 25 work, 5 break, 25 work, 5 break

pomodoro = true

check("on the hour",              slot(at(14, 0)),      "seg 0 work  work :00 to :25")
check("last second of the first", slot(at(14, 24, 59)), "seg 0 work  work :00 to :25")
check("the first break opens",    slot(at(14, 25)),     "seg 1 break break :25 to :30")
check("last second of the break", slot(at(14, 29, 59)), "seg 1 break break :25 to :30")
check("back to work at :30",      slot(at(14, 30)),     "seg 2 work  work :30 to :55")
check("last second of the second", slot(at(14, 54, 59)), "seg 2 work  work :30 to :55")
check("the last break opens",     slot(at(14, 55)),     "seg 3 break break :55 to :00")
check("last second of the hour",  slot(at(14, 59, 59)), "seg 3 break break :55 to :00")

// A slot's fraction is how far through that slot you are, not the hour. The
// glass drains once per slot in pomodoro mode, which is the whole point.
checkClose("halfway through the first work", currentPhase(at(14, 12, 30)).fraction, 0.5)
checkClose("halfway through a five minute break", currentPhase(at(14, 27, 30)).fraction, 0.5)
checkClose("halfway through the second work", currentPhase(at(14, 42, 30)).fraction, 0.5)
checkClose("a fresh slot has drained nothing", currentPhase(at(14, 30)).fraction, 0.0)

checkClose("15 minutes to the first break", currentPhase(at(14, 10)).remaining, 15 * 60)
checkClose("a minute to the hour", currentPhase(at(14, 59)).remaining, 60)

// The cycle number is what makes the glass turn. It has to step by exactly one
// at every boundary and never go backwards, or a turn is missed or repeated.
let boundaries = [at(14, 0), at(14, 25), at(14, 30), at(14, 55), at(15, 0)]
let cycles = boundaries.map { currentPhase($0).cycle }
let steps = zip(cycles, cycles.dropFirst()).map { $1 - $0 }
check("four turns an hour, one step each", "\(steps)", "[1, 1, 1, 1]")

// MARK: - Off the grid

pomodoro = false

check("the hour is one work slot", slot(at(14, 30)), "seg 0 work  ")
checkClose("half past is half drained", currentPhase(at(14, 30)).fraction, 0.5)
checkClose("half an hour still to fall", currentPhase(at(14, 30)).remaining, 30 * 60)
check("no breaks exist off the grid",
      "\((0..<60).contains { isBreakMinute($0) })", "false")

let plainCycles = [at(14, 0), at(14, 25), at(14, 59), at(15, 0)].map { currentPhase($0).cycle }
check("one turn an hour", "\(plainCycles[0] == plainCycles[1] && plainCycles[1] == plainCycles[2] && plainCycles[3] == plainCycles[0] + 1)", "true")

// MARK: - The hour as sixty characters

pomodoro = true

check("sixty minutes, sixty glyphs", "\(hourGlyphs(at(14, 30)).count)", "60")
check("the cursor sits on the minute", "\(hourGlyphs(at(14, 50))[50])", "o")
check("the first minute is the cursor", "\(hourGlyphs(at(14, 0))[0])", "o")
check("the last minute is the cursor", "\(hourGlyphs(at(14, 59))[59])", "o")

let atFifty = String(hourGlyphs(at(14, 50)))
check("spent work, spent break, cursor, work to come, break waiting",
      atFifty,
      String(repeating: "*", count: 25) + String(repeating: "-", count: 5)
        + String(repeating: "*", count: 20) + "o" + String(repeating: ".", count: 4)
        + String(repeating: "~", count: 5))

pomodoro = false
let plainFifty = String(hourGlyphs(at(14, 50)))
check("off the grid there is no break sand",
      plainFifty,
      String(repeating: "*", count: 50) + "o" + String(repeating: ".", count: 9))

// MARK: - Which minutes belong to a break

pomodoro = true
let breakMinutes = (0..<60).filter { isBreakMinute($0) }
check("the grid gives ten minutes to breaks", "\(breakMinutes.count)", "10")
check("and they are the right ten",
      "\(breakMinutes.first!)-\(breakMinutes[4]) \(breakMinutes[5])-\(breakMinutes.last!)",
      "25-29 55-59")
check("the minute before a break is work", "\(isBreakMinute(24))", "false")
check("the minute a break ends is work", "\(isBreakMinute(30))", "false")

print(failures == 0 ? "\nall 28 cases pass" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)

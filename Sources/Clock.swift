import Foundation

// The clock the whole app runs on. Every function here is arithmetic over a
// date and nothing else, which is what lets the grid be tested without
// launching an app or waiting out a real hour.

let demo = CommandLine.arguments.contains("--demo")
let period: TimeInterval = demo ? 30 : 3600

// Pomodoro mode carves every hour into the grid 25 work, 5 break, 25 work,
// 5 break. It is anchored to the clock like everything else here, so there is
// no start button: you join the pomodoro already in progress, and the glass
// turns itself at every boundary.
var pomodoro = UserDefaults.standard.bool(forKey: "pomodoro")
let segmentEnds = [25.0 / 60, 30.0 / 60, 55.0 / 60, 1.0]

// Measured against local clock hours, so the glass turns at 4:00 sharp even in
// a half-hour-offset timezone.
func localSeconds(_ date: Date = Date()) -> TimeInterval {
    date.timeIntervalSince1970
        + TimeInterval(TimeZone.current.secondsFromGMT(for: date))
}

// One draining glass: an hour, or one work or break segment of it.
struct Phase {
    let isBreak: Bool
    let fraction: Double        // how much of this glass has drained
    let remaining: TimeInterval // until the next turn
    let cycle: Int              // increments at every turn
    let segment: Int            // 0-3 within the hour in pomodoro mode
}

// The slot's place on the clock, e.g. "work :30 to :55". The grid is the
// same for everyone; this is what makes joining it visible.
let slotStarts = [":00", ":25", ":30", ":55"]
let slotEnds = [":25", ":30", ":55", ":00"]
func slotLabel(_ p: Phase) -> String {
    guard pomodoro else { return "" }
    return "\(p.isBreak ? "break" : "work") \(slotStarts[p.segment]) to \(slotEnds[p.segment])"
}

func currentPhase(_ date: Date = Date()) -> Phase {
    let local = localSeconds(date)
    let hour = Int(local / period)
    let intoHour = local.truncatingRemainder(dividingBy: period) / period
    guard pomodoro else {
        return Phase(isBreak: false, fraction: intoHour,
                     remaining: (1 - intoHour) * period, cycle: hour, segment: 0)
    }
    var start = 0.0
    for (i, end) in segmentEnds.enumerated() {
        if intoHour < end {
            return Phase(isBreak: i % 2 == 1,
                         fraction: (intoHour - start) / (end - start),
                         remaining: (end - intoHour) * period,
                         cycle: hour * 4 + i, segment: i)
        }
        start = end
    }
    return Phase(isBreak: true, fraction: 1, remaining: 0,
                 cycle: hour * 4 + 3, segment: 3)
}

/// True for the minutes the pomodoro grid gives to a break, :25 to :30 and
/// :55 to :00. Off the grid there are no breaks, so the whole hour is work.
func isBreakMinute(_ minute: Int) -> Bool {
    guard pomodoro else { return false }
    return (25..<30).contains(minute) || minute >= 55
}

/// Which minute of the hour we are in, 0 through 59. Demo mode squeezes the
/// hour into thirty seconds, and this rides along with it because it measures
/// the same fraction the glass drains by.
func currentMinute(_ date: Date = Date()) -> Int {
    let intoHour = localSeconds(date).truncatingRemainder(dividingBy: period) / period
    return min(59, max(0, Int(intoHour * 60)))
}

/// One character per minute of the hour.
func hourGlyphs(_ date: Date = Date()) -> [Character] {
    let now = currentMinute(date)
    return (0..<60).map { minute in
        if minute == now { return "o" }
        if minute < now { return isBreakMinute(minute) ? "-" : "*" }
        return isBreakMinute(minute) ? "~" : "."
    }
}

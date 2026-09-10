---
description: 'Swift conventions for TimeTurner’s AppKit sources and clock tests'
applyTo: '**/*.swift'
---

# Swift in this repo

This is not a package. There is no `Package.swift`. Files under `Sources/` are compiled together by `swiftc` in `build.sh`. Tests compile `Sources/Clock.swift` plus a copy of `Tests/UnitTests.swift` renamed to `main.swift`.

- Target is macOS 13, AppKit + Foundation. Do not introduce SwiftUI, Combine publishers for the tick, or Swift Concurrency just to look modern. The tick is a `Timer`.
- Keep types small and local. `Phase` lives in `Clock.swift`. The glass view owns grains. Do not invent a third model layer.
- Prefer clear names already in the file (`currentPhase`, `fraction`, `cycle`, `announceJoin`) over new synonyms.
- The test file is top-level script code with `check` / `checkClose`. New clock tests follow that pattern. Do not introduce XCTest.
- `pomodoro` is a mutable global in `Clock.swift` because the tests flip it. Do not hide it behind a singleton.
- Icon drawing in `main.swift` produces a template `NSImage`. Keep it black; the menu bar tints it.
- If a function is arithmetic over a `Date`, it belongs in `Clock.swift` so the suite can walk an hour in milliseconds.

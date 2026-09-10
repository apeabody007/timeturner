# TimeTurner, for Copilot

A macOS menu bar hourglass. The sand drains over the current clock hour. At `:00` the glass turns itself over. There is no start button anywhere in this program, and you will not add one.

## What this is

- Menu bar app (`LSUIElement`), no dock icon.
- Two views of the same hour: a tiny template-image hourglass in the status item, and a resizable window whose sand is a real falling-sand simulation drawn from keyboard characters.
- Pomodoro mode carves the hour into `25 work / 5 break / 25 work / 5 break`, anchored to local wall time. Everyone running TimeTurner is in the same slot. You join a pomodoro already in progress.
- Brown noise is generated live. Full volume on work sand, a whisper on breaks.
- About 900 lines of Swift. No packages, no SPM, no storyboards, no SwiftUI, no Xcode project. `./build.sh` is the build.

## Layout

| Path | Job |
| --- | --- |
| `Sources/Clock.swift` | Pure arithmetic over a date. Phase, fraction, remaining, cycle, slot label, hour glyphs. The only file the unit tests compile against. |
| `Sources/Glass.swift` | The window: character grid, falling-sand rules, neck gated by the clock, resize that carries grains as fractions. |
| `Sources/HourStrip.swift` | The sixty-character hover strip under the menu bar icon. |
| `Sources/Noise.swift` | Live brown noise. No audio files. |
| `Sources/main.swift` | AppKit app, menu, icon drawing, `--demo` / `--render` / `--help`. |
| `Tests/UnitTests.swift` | Top-level assertions. Copied to `build/tests/main.swift` and compiled with `Clock.swift` only. |
| `tools/make-icon.swift` | Regenerates `Resources/TimeTurner.icns`. |
| `build.sh` | `./build.sh`, `./build.sh test`, `./build.sh install`, `./build.sh icon`. |

Bundle id: `dev.aaronpeabody.timeturner`. Minimum macOS 13. Arm64 only in `build.sh`.

## Rules you keep

- Clock logic stays in `Clock.swift`. Drawing does not learn what time it is except by calling `currentPhase` / `hourGlyphs` / `slotLabel`.
- State is derived from the current date. Do not persist "how full the glass is." Sleep, resize, and the hourly turn all reseat from now.
- `period` is 3600 seconds, or 30 in `--demo`. Demo mode must keep riding the same fraction math. Do not special-case demo in the grid itself beyond `period`.
- Pomodoro boundaries are `:00`, `:25`, `:30`, `:55`. Cycle increments by exactly one at every turn. A missed or doubled cycle is a missed or doubled animation.
- Glyph vocabulary is fixed: `*` spent work, `-` spent break, `o` now, `.` work still to come, `~` break waiting. Frame characters are `=` `/` `\` `(` `)`. Sand in the window is `.` `:` `;` `,` `*` `o` on work, `~` and `-` on breaks.
- No new dependencies. No SwiftUI. No extra files unless the change truly needs one.
- UserDefaults keys already in use: `pomodoro`, `noise`, `pinned`. Do not rename them.
- Prose matches the README: short sentences, no marketing, no emoji in source comments, no "simply" / "just" / "robust" / "leverage."
- Comments explain why, the way the existing files do.

## How to check a change

```
./build.sh test
./build.sh
./build/TimeTurner.app/Contents/MacOS/TimeTurner --help
```

Headless icon frames (CI does this):

```
./build/TimeTurner.app/Contents/MacOS/TimeTurner --render /tmp/timeturner-frames
```

Expect eight PNGs. To watch a turn without waiting an hour:

```
./build/TimeTurner.app/Contents/MacOS/TimeTurner --demo
```

If you touch the clock grid, add a case to `Tests/UnitTests.swift` at an exact local minute, not "whatever time the suite happens to run." The helper `at(_:_:_:)` already exists.

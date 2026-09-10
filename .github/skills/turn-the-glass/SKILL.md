---
name: turn-the-glass
description: Build, test, demo, and render TimeTurner from the CLI. Use when running the app, checking the clock grid, producing icon frames, or verifying a Copilot change actually turns the glass.
---

# Turn the glass

TimeTurner has no Xcode project. The CLI is `./build.sh`.

## Commands

From the repo root:

```bash
./build.sh test      # 28 clock-grid cases, milliseconds not minutes
./build.sh           # build build/TimeTurner.app (arm64, macOS 13)
./build.sh install   # build, copy to /Applications, launch
./build.sh icon      # regenerate Resources/TimeTurner.icns
```

Once built:

```bash
./build/TimeTurner.app/Contents/MacOS/TimeTurner --help
./build/TimeTurner.app/Contents/MacOS/TimeTurner --demo
./build/TimeTurner.app/Contents/MacOS/TimeTurner --render /tmp/timeturner-frames
```

`--demo` compresses the hour into thirty seconds so the drain and the 180° turn are visible. `--render DIR` writes eight PNGs (`f000`…`f100`, `turn045`…`turn135`). CI expects exactly eight.

Unknown flags must exit 2. `--help` and `-h` exit 0.

## After you change Clock.swift

1. Put new assertions in `Tests/UnitTests.swift` using `at(_:_:_:)` so they pin a local wall-clock minute.
2. Flip `pomodoro = true` or `false` explicitly. The suite does not reset it for you between sections.
3. Run `./build.sh test`. The last line should read `all 28 cases pass` or the new count if you added cases.
4. Do not compile Glass or AppKit into the tests.

## After you change drawing

```bash
./build.sh
./build/TimeTurner.app/Contents/MacOS/TimeTurner --render /tmp/timeturner-frames
ls /tmp/timeturner-frames
```

Inspect the frames. A turn that does not land as a full top bulb is wrong.

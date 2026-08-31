# TimeTurner

**A menu bar hourglass for the Mac. The sand drains over the current clock
hour, and at the top of every hour the glass turns itself over.**

No dock icon, no windows, no settings beyond Launch at Login. One menu bar
item, about 250 lines of Swift. Builds with the Xcode Command Line Tools
alone, so you do not need a 12 GB Xcode install to compile it.

Click the hourglass to see how long until the next turn.

## Install

Build it from a clone:

```
./build.sh install
```

That builds `TimeTurner.app`, copies it to `/Applications`, and launches it.
Turn on **Launch at Login** from the menu if you want it to always be there.
Note that it ad-hoc signs, so macOS may ask you to approve it the first time.

## Watch it turn without waiting an hour

```
./build.sh
./build/TimeTurner.app/Contents/MacOS/TimeTurner --demo
```

Demo mode compresses the hour into thirty seconds, so you can watch the sand
drain and the glass flip.

## License

MIT

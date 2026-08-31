# TimeTurner

**A menu bar hourglass for the Mac. The sand drains over the current clock
hour, and at the top of every hour the glass turns itself over.**

There are two views of the same hour. The menu bar icon is a tiny glass that
drains and does a 180 degree turn on the hour. And there is a resizable
window holding an hourglass built entirely out of keyboard characters: the
frame is `=` `/` `\` `(` `)`, the sand is `.` `:` `;` `,` `*` `o`, and the
grains fall through the neck one at a time on the real clock, piling up in a
cone below. Resize the window and the glass reshapes itself to fit.

No dock icon, no settings beyond Launch at Login. About 600 lines of Swift.
Builds with the Xcode Command Line Tools alone, so you do not need a 12 GB
Xcode install to compile it.

Click the menu bar hourglass to see how long until the next turn, or to
reopen the window.

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

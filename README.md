# NotchPal

Pip, a tiny peach with a sprout, lives in your MacBook's notch. It does nothing useful, on purpose.

- Hover the notch: it grows, Pip pops up and waves hello.
- Move your mouse: Pip's eyes follow you.
- Hover Pip: eyes widen, cheeks blush.
- Click Pip: it squishes, squints and complains.
- Click 3 times fast: spiral eyes and stars for a few seconds.
- Move away: the notch shrinks back and Pip stops animating (no CPU used).

On a Mac without a notch, a small black "fake notch" appears at the top center of the screen.

## Run it

Needs macOS 14 or later and either Xcode or the Command Line Tools (`xcode-select --install`).

```bash
cd NotchPal
swift run
```

Or open `Package.swift` in Xcode and press ⌘R.

Quit from the smiley icon in the menu bar.

## Where to tweak

| What | File |
|---|---|
| Open notch size | `PalModel.openSize` in `PalModel.swift` |
| What Pip says, sounds | `open()` and `hit()` in `PalModel.swift` |
| How many clicks make Pip dizzy, and how fast | `hit()` in `PalModel.swift` |
| Colors, face, arms, sprout | `PipDrawing` in `PipView.swift` |
| Wave, hit, dizzy motion | `Pose.make` in `PipView.swift` |
| Grow/shrink spring, notch corner shape | `NotchRootView` and `NotchShape` in `NotchView.swift` |
| How close you need to be to open it, close delay | `mouseMoved()` and `scheduleClose()` in `NotchController.swift` |

Sounds are built-in macOS sounds (Tink, Pop, Frog), so there are no asset files.

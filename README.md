# NotchPal

Pip, a tiny peach with a sprout, lives in your MacBook's notch. It mostly keeps you company, and it can hold on to a few reminders for you.

<p align="center"><img src="docs/screenshot.png" alt="Pip in the open notch, next to the reminder editor" width="480"></p>

- Hover the notch: it grows, Pip pops up and waves hello.
- Move your mouse: Pip's eyes follow you.
- Hover Pip: eyes widen, cheeks blush.
- Click Pip: it squishes, squints and complains.
- Click 3 times fast: spiral eyes and stars for a few seconds.
- Move away: the notch shrinks back and Pip stops animating (no CPU used).

## Reminders

- Click the bell on the right of the open notch to add one: type a description, then pick **In** (a countdown in h / m / s) or **At** (a clock time with AM/PM) and press **Set**.
- You can also just type the time into the description, like "tea in 5 min" or "standup tomorrow at 9am".
- The next reminder counts down on the left side of the notch. When it's due, the notch pops open and Pip shows it.
- Once you have reminders, the bell opens a list of them. Click the trash icon on a row to delete it, or **+ New** to add another.
- Reminders are saved, so they survive quitting and relaunching.

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
| Open notch size | `PalModel.openSize` / `editSize` in `PalModel.swift` |
| Reminder editor and list | `ReminderEditor` and `ReminderList` in `NotchView.swift` |
| Typed-time parsing ("in 10 min", "at 3pm") | `ReminderParser` in `Reminders.swift` |
| What Pip says, sounds | `open()` and `hit()` in `PalModel.swift` |
| How many clicks make Pip dizzy, and how fast | `hit()` in `PalModel.swift` |
| Colors, face, arms, sprout | `PipDrawing` in `PipView.swift` |
| Wave, hit, dizzy motion | `Pose.make` in `PipView.swift` |
| Grow/shrink spring, notch corner shape | `NotchRootView` and `NotchShape` in `NotchView.swift` |
| How close you need to be to open it, close delay | `mouseMoved()` and `scheduleClose()` in `NotchController.swift` |

Sounds are built-in macOS sounds (Tink, Pop, Frog), so there are no asset files.

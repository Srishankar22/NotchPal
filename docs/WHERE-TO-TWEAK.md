# Where to tweak

Where to find each part of NotchPal in the code, for anyone changing it. All files are in `Sources/NotchPal/` unless a path says otherwise. After a change, rebuild with `./build-app.sh --install`.

| What | File |
|---|---|
| Open notch size (small, with a panel, with a reminder) | `openSize` / `expandedSize` / `reminderSize` in `PalModel.swift` |
| Icons beside the camera (countdown, Shelf, Clipboard, bell) | `NotchEars` in `NotchView.swift` |
| How much the closed notch widens for the music peek and shelf count | `closedWings` in `PalModel.swift` |
| Shelf and Clipboard tabs, closed-notch peek | `PanelViews.swift` |
| Shelf rules (20 items, bookmarks, missing files) | `ShelfStore` in `Shelf.swift` |
| Clipboard rules (30 items, 10 pins, skipped secret types, image budget) | `ClipboardStore` in `Clipboard.swift` |
| Music detection, what counts as "music" vs "video" | `NowPlayingMonitor` in `NowPlaying.swift` |
| Dance moves, catch, shrug, nod | `Pose.make` in `PipView.swift` |
| Settings and their defaults | `Settings.swift` and `MenuContent` in `NotchPalApp.swift` |
| Reminder editor and list | `ReminderEditor` and `ReminderList` in `NotchView.swift` |
| Typed-time parsing ("in 10 min", "at 3pm") | `ReminderParser` in `Reminders.swift` |
| What Pip says | `open()`, `hit()`, `grab()`, `letGo()` and `petted()` in `PalModel.swift` |
| How long Pip holds a grudge after a poke | `upsetUntil` in `hit()` in `PalModel.swift` |
| How many clicks make Pip dizzy, and how fast | `hit()` in `PalModel.swift` |
| Colors, face, arms, sprout | `PipDrawing` in `PipView.swift` |
| Characters: outfits, names, greetings, adding a new one | `Skin` and the outfit views in `PipSkins.swift` |
| Wave, hit, dizzy motion | `Pose.make` in `PipView.swift` |
| Throw physics (bounciness, spring home, bounces to dizzy), petting speed | constants at the top of `PipMotion` in `PipMotion.swift` |
| Grow/shrink spring, notch corner shape | `NotchRootView` and `NotchShape` in `NotchView.swift` |
| How close you need to be to open it, close delay | `mouseMoved()` and `scheduleClose()` in `NotchController.swift` |
| App icon | `scripts/make-icon.swift` |
| App name, bundle ID, version | top of `build-app.sh` |

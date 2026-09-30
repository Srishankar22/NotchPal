# NotchPal

Pip, a tiny peach with a sprout, lives in your MacBook's notch. It mostly keeps you company, and it can hold on to a few reminders for you.

<p align="center"><img src="docs/screenshot.png" alt="Pip waving hello from the open notch" width="480"></p>

## What Pip does

| You do | Pip does |
|---|---|
| Hover the notch | The notch grows, Pip pops up and waves hello |
| Move your mouse | Pip's eyes follow you |
| Hover Pip | Eyes widen, cheeks blush |
| Click Pip | Squishes, squints and complains ("Ow!", "Rude.") |
| Click 3 times fast | Spiral eyes and stars for a few seconds |
| Drag Pip | Dangles and flails ("Hey! Put me down!") |
| Let go while moving | Pip gets thrown, ricochets off the notch walls, then springs back home |
| Throw Pip hard (2+ hard bounces) | Gets dizzy ("Whoa… too fast…") |
| Stroke Pip slowly (no clicking) | Happy eyes and floating hearts |
| Stroke Pip right after poking | Puts up with it: half-closed eyes, flat "—" mouth. When you stop: "Okay… you're forgiven." and no longer dizzy |
| Move away | The notch shrinks back and Pip stops animating (no CPU used) |

## Characters

Pip can dress up as a few characters.

**To change character:** right-click Pip, or click the smiley icon in the menu bar, then choose **Character** and pick one. Your choice is remembered.

<p align="center"><img src="docs/characters.png" alt="Pip, Peaky Blinders, Tanjiro Kamado and Harry Potter versions" width="640"></p>

| Character | Outfit | Says hello with |
|---|---|---|
| Pip | The classic peach with a sprout | "Hi there!", "Psst… hi!" |
| Peaky Blinders | Tweed flat cap with a razor blade in the peak, revolver | "Alright?", "Evening." |
| Tanjiro Kamado | Flame scar on the forehead, black katana | "I'll do my best!" |
| Harry Potter | Round glasses, lightning scar, wand | "Lumos! …oh, hi." |

Outfits are drawn in code on top of Pip, so they squash, tilt, get thrown and go dizzy along with Pip. Held items move with Pip's hand: waving raises the sword or wand.

## Reminders

Click the bell in the open notch, type a description, pick a time and press **Set**. You can also type the time in, like "tea in 5 min".

The next one counts down on the left of the notch, and Pip pops up when it's due. Click the bell again to see your reminders and delete them.

On a Mac without a notch, a small black "fake notch" appears at the top center of the screen.

## Install

Needs macOS 14 or later and either Xcode or the Command Line Tools. If you have neither, install the tools once:

```bash
xcode-select --install
```

Then, in Terminal:

```bash
cd path/to/NotchPal
./build-app.sh --install
```

This builds **NotchPal.app**, copies it to your Applications folder and opens it. From then on, start it like any other app: Spotlight (⌘Space, type "NotchPal"), Launchpad, or double-click it in Applications.

There's no Dock icon and no window. NotchPal lives in the notch and shows a small smiley icon in the menu bar.

**Start automatically:** click the smiley in the menu bar and turn on **Open at Login**.

If you'd rather not install it, `./build-app.sh` on its own just makes `build/NotchPal.app` in the project folder, which you can double-click from there.

The script compiles a release build, draws the app icon from Pip's own drawing code, writes the `Info.plist` (no Dock icon, bundle ID `com.notchpal.NotchPal`) and signs the app locally.

## Quit

Click the smiley icon in the menu bar and choose **Quit NotchPal** (or press ⌘Q while that menu is open).

If the menu bar icon is hidden (for example behind other icons), quit from Terminal instead:

```bash
pkill -x NotchPal
```

or find "NotchPal" in Activity Monitor and click the ✕ button.

## Update after changing the code

```bash
./build-app.sh --install
```

This quits the running copy, replaces the one in Applications and opens the new one. Your reminders and the Open at Login setting are kept.

## Uninstall

1. Click the smiley in the menu bar, turn off **Open at Login**, then **Quit NotchPal**.
2. Drag `NotchPal.app` from Applications to the Trash.
3. Optional, to also delete saved reminders:

   ```bash
   defaults delete com.notchpal.NotchPal
   ```

## Quick run while developing

```bash
swift run
```

Or open `Package.swift` in Xcode and press ⌘R. This runs a bare program rather than the `.app`, so **Open at Login** is hidden, and reminders are saved separately from the app's.

## Where to tweak

| What | File |
|---|---|
| Open notch size | `PalModel.openSize` / `editSize` in `PalModel.swift` |
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

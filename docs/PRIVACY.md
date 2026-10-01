# NotchPal: Privacy and Memory

Last checked: 1 October 2026

## The short version

Nothing NotchPal sees ever leaves your Mac: it has no internet code at all, no analytics and no account. It uses about 25 MB of memory and close to 0% CPU while the notch is closed.

- Your clipboard history lives in memory and is gone when you quit, unless you choose to keep it.
- Anything copied from a password manager is never recorded.
- Song titles, copied text and file names are never written to a log.

## What NotchPal keeps

NotchPal only saves what a feature needs, and keeps it on your Mac, readable by your user account only.

| What | Kept for | Where |
| --- | --- | --- |
| Clipboard history (last 30 copies) | Until you quit, by default | Memory only |
| Clipboard history, with **Remember Clipboard History After Restart** on | Until you clear it | `~/Library/Application Support/NotchPal` |
| Pinned clipboard items (up to 10) | Until you unpin them | `~/Library/Application Support/NotchPal` |
| File Shelf (up to 20 items) | Until you remove them | Same folder; only links to your files, never copies |
| Reminders | Until they go off or you delete them | NotchPal's settings file |
| Settings and chosen character | Until you change them | NotchPal's settings file |
| What's playing (song title, artist) | Only while it plays | Memory only, never saved |

These files are not encrypted by NotchPal itself. Turn on FileVault (System Settings → Privacy & Security) to encrypt your whole disk, including them.

## What NotchPal never does

- **Never goes online.** There is no network code in NotchPal: nothing is uploaded, synced or sent anywhere.
- **Never logs your content.** Its only log messages are "couldn't save shelf.json" and login-item errors. No copied text, file names or song titles.
- **Never reads your keystrokes.** It watches only where the mouse is, to know when to open the notch.
- **Never looks inside things you drag.** When a file is dragged across the screen, NotchPal checks only what kind of thing it is, so it can open the shelf. It reads nothing until you drop it on the notch.
- **Never copies your files.** The shelf keeps a link to each file; dragging one out copies it from the original.

## Passwords and sensitive copies

Passwords you copy from a password manager never enter clipboard history. NotchPal uses two checks, so one can catch what the other misses:

1. **Marked as secret.** Password managers tag copied passwords as secret or temporary. NotchPal skips anything with those tags, before it reads the content.
2. **Copied in a password manager.** Anything copied while one of these apps is in front is ignored: 1Password, Bitwarden, Apple Passwords, Keychain Access, LastPass, KeePassXC, Dashlane, Enpass, NordPass, Proton Pass and Strongbox.

For anything else sensitive, such as a bank number or a private message:

- Choose **Pause Clipboard for 1 Hour** in the smiley menu before you copy it, or
- Hover the item in Clipboard History and click × to delete it, or
- Turn **Clipboard History** off. That also forgets everything it already saw, except pinned items.

## Permissions

Only auto-paste truly needs a permission. Saying no to any of these never breaks the other features.

| Permission | What NotchPal uses it for | When macOS asks | If you say no |
| --- | --- | --- | --- |
| Accessibility | Pressing ⌘V for you, once, right after you click a clipboard item | The first time you click a clipboard item | Clicking copies the item, and you press ⌘V yourself |
| Clipboard access | Reading what you copy, for Clipboard History | Newer macOS versions may ask the first time | Clipboard History stays empty |
| Files and folders | Re-opening shelf items in Desktop, Documents or Downloads | May ask once per folder | Those shelf items show as "missing" |

Dancing Pip needs no permission. It reads what's playing through Apple's built-in Perl and the open-source [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), all on your Mac.

## Memory, CPU and battery

NotchPal measured 25 MB of memory and 0% CPU with the notch closed, on a MacBook running macOS 26.6.

| Situation | Memory | CPU |
| --- | --- | --- |
| Notch closed, nothing playing | 18 MB, plus 7 MB for the music helper | 0% |
| Notch closed, music playing (tiny Pip dancing) | About 26 MB, plus 7 MB | Under 1% |
| Notch open, Pip animating | Slightly more | A few percent, only while open |

It stays small because of these limits:

- **Clipboard:** the last 30 items, at most 10 pinned. Text over 200,000 characters is cut short, and formatting over 1 MB is dropped (the text is kept).
- **Images:** 10 MB in total for recent images, 20 MB for pinned ones. A single image over 10 MB isn't kept.
- **Shelf:** 20 links to files, never copies, so it uses no disk space.
- **Animation:** nothing runs while the notch is closed and quiet. The little dancing Pip beside the closed notch is played by macOS itself, so NotchPal does almost no work for it.
- **Saving:** pinned items are written to disk only when your pins change, not on every copy.

To check it yourself, open Activity Monitor and search for "NotchPal". The music helper appears as "perl".

## Pausing, clearing and deleting your data

Everything below is in the smiley icon's menu in the menu bar, unless it says otherwise.

| To | Do this |
| --- | --- |
| Stop recording copies for a while | **Pause Clipboard for 1 Hour** |
| Forget recent copies (pinned stay) | **Clear Clipboard History**, or turn **Clipboard History** off |
| Delete one copied item | Hover it in Clipboard History and click × |
| Empty the shelf | **Clear Shelf** |
| Stop the song title showing | Turn off **Show Song Title** |
| Stop music detection completely | Turn off **Dancing Pip** (the music helper stops) |
| Remove auto-paste access | System Settings → Privacy & Security → Accessibility → turn off NotchPal |

**To delete everything NotchPal has saved**, quit NotchPal and run these two lines in Terminal:

```
defaults delete com.notchpal.NotchPal
rm -r ~/Library/Application\ Support/NotchPal
```

The first removes reminders, settings and your character. The second removes the shelf and pinned clipboard items. Your actual files are never touched.

## How this was checked

On 1 October 2026, NotchPal's code was reviewed for memory and privacy problems, and automated tests were run. All 28 checks passed, and 9 issues were fixed.

- **Clipboard: 18 checks passed.** Password-manager copies skipped, duplicates merged, the 30-item and 10-pin limits held, pinned items survived a restart, and only pinned items were saved by default.
- **Shelf: 10 checks passed.** Files added and removed, renamed files followed, deleted files shown as missing, original files never moved.
- **Stress test.** Copying a large web page 30 times used 14 MB (it was 146 MB before the fix). Memory stayed flat over 200 more copies, so nothing leaks.
- **Tests never touched real data.** They used a private test clipboard and a scratch folder, not your clipboard or files.

| Fixed | Why it mattered |
| --- | --- |
| Formatting from big copies is now capped at 1 MB | One large web page could hold 5 MB per copy |
| A newly copied image is no longer thrown away when pinned images are large | Recent images could silently go missing |
| Pinned images now have their own 20 MB limit | Pinned images could grow without limit |
| The pinned file is saved only when pins change | Every ⌘C rewrote up to 20 MB to disk |
| The music helper no longer spins the CPU if it stops | It could keep a CPU core busy until restarting |
| Copies made in password-manager apps are ignored | A second check beyond the "secret" tag |
| Turning Clipboard History off forgets what it saw | Before, it only stopped new copies |
| The data folder is set to "only you" on every launch | Even if something else created it |
| The test-only data folder option is removed from the real app | Release builds can't be pointed elsewhere |

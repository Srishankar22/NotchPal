import SwiftUI
import Combine

enum Mood { case calm, hit, dizzy }

/// A plain copy of everything the character needs to draw one frame.
struct PalSnapshot {
    var isOpen: Bool
    var mouse: CGPoint
    var mood: Mood
    var openedAt: Date
    var waveStart: Date
    var hitStart: Date
    var dizzyStart: Date
    var upsetUntil: Date
    var dancing: Bool
    var danceStart: Date
    var catchStart: Date
    var shrugStart: Date
    var nodStart: Date
}

@MainActor
final class PalModel: ObservableObject {
    /// Size of the notch when it's open: Pip on the left, the Shelf / Clipboard panel on the right.
    static let openSize = CGSize(width: 400, height: 150)
    /// Bigger only while the Shelf / Clipboard panel is showing.
    static let expandedSize = CGSize(width: 540, height: 200)
    /// Just wide enough for Pip + the reminder editor or list, so they sit balanced.
    static let reminderSize = CGSize(width: 410, height: 196)

    /// The panel (or reminder editor / list) is showing, so the notch is in its big layout.
    var isExpanded: Bool { panel != nil || isEditing || isListing }

    var currentOpenSize: CGSize {
        if isEditing || isListing { return Self.reminderSize }
        return panel != nil ? Self.expandedSize : Self.openSize
    }

    /// Size of the real notch (measured at launch). Set by NotchController.
    @Published var closedSize = CGSize(width: 190, height: 32)

    /// Mouse position in the window, top-left origin. Only updated while open.
    @Published var mouse: CGPoint = .zero

    @Published private(set) var isOpen = false
    @Published private(set) var mood: Mood = .calm
    /// True while you're holding Pip with the mouse.
    @Published private(set) var isHeld = false
    /// What Pip is saying right now. nil = no bubble, Pip sits centered.
    @Published private(set) var line: String?

    // Animation clocks. Pip works out every pose from "how long since X happened".
    @Published private(set) var openedAt = Date.distantPast
    @Published private(set) var waveStart = Date.distantPast
    @Published private(set) var hitStart = Date.distantPast
    /// Pip holds a grudge for a while after being poked, until petted better.
    @Published private(set) var upsetUntil = Date.distantPast
    @Published private(set) var dizzyStart = Date.distantPast

    private var recentHits: [Date] = []
    private var moodTask: Task<Void, Never>?
    private var lineTask: Task<Void, Never>?

    // MARK: Reminders

    /// Pending reminders, soonest first.
    @Published private(set) var reminders: [Reminder] = []
    /// A reminder that went off. Stays on screen until the notch closes.
    @Published private(set) var alert: String?
    /// True while you're typing a reminder into the bubble.
    @Published private(set) var isEditing = false
    /// True while the list of pending reminders is showing.
    @Published private(set) var isListing = false
    /// Shown under the text field when Pip couldn't find a time.
    @Published private(set) var editHint: String?

    /// Called when a reminder goes off, so the controller can pop the notch open.
    var onAttention: (() -> Void)?
    /// Called when typing starts/stops, so the controller can give the window keyboard focus.
    var onEditingChanged: ((Bool) -> Void)?
    private var reminderTask: Task<Void, Never>?

    /// What the bubble shows: Pip's current line, the reminder that went off, or the song.
    var bubbleText: String? { line ?? alert ?? musicLine }

    var snapshot: PalSnapshot {
        PalSnapshot(isOpen: isOpen, mouse: mouse, mood: mood,
                    openedAt: openedAt, waveStart: waveStart,
                    hitStart: hitStart, dizzyStart: dizzyStart, upsetUntil: upsetUntil,
                    dancing: isDancing, danceStart: danceStart,
                    catchStart: catchStart, shrugStart: shrugStart, nodStart: nodStart)
    }

    // MARK: Shelf, clipboard, music

    let shelf = ShelfStore()
    let clipboard = ClipboardStore()
    let nowPlaying = NowPlayingMonitor()

    /// Which panel is showing. nil = the normal compact notch with just Pip.
    /// Opened from the little icons beside the camera, or by dragging a file to the notch.
    @Published var panel: PanelTab?

    /// Click an icon: open that panel, or close it if it's already showing.
    func togglePanel(_ tab: PanelTab) {
        cancelEditing()
        isListing = false
        panel = panel == tab ? nil : tab
    }
    /// A file is being dragged near or over the notch: show the "Drop here" area.
    @Published private(set) var dropTargeting = false
    /// You're dragging an item out of the shelf: keep the notch open until it lands.
    @Published var isDraggingOut = false

    /// Music or video is playing (with a 2 s grace period on pause, so it doesn't flicker).
    @Published private(set) var isDancing = false
    @Published private(set) var danceStart = Date.distantPast
    @Published private(set) var catchStart = Date.distantPast
    @Published private(set) var shrugStart = Date.distantPast
    @Published private(set) var nodStart = Date.distantPast
    /// Briefly true after a copy (with "Pip nods each time you copy"), to show Pip beside the closed notch.
    @Published private(set) var isNodding = false

    /// Called when you click a clipboard item; the controller pastes it.
    var onPaste: ((ClipItem, _ plainOnly: Bool) -> Void)?

    private var bag: Set<AnyCancellable> = []
    private var danceStopTask: Task<Void, Never>?
    private var nodTask: Task<Void, Never>?
    private var lastSettings: [String: Bool] = [:]

    /// "♪ Title, Artist" while dancing, if song titles are on.
    var musicLine: String? {
        guard isDancing, Settings.isOn(Settings.showSongTitle), let t = nowPlaying.track else { return nil }
        return "\u{266A} " + (t.artist.isEmpty ? t.title : "\(t.title), \(t.artist)")
    }

    /// Extra black on each side of the closed notch: Pip's head and music bars while music plays,
    /// and the shelf count. The camera part always stays centered.
    func closedWings(shelfCount: Int) -> (left: CGFloat, right: CGFloat) {
        guard !isOpen else { return (0, 0) }
        let peeking = isDancing || isNodding
        let showCount = shelfCount > 0 && Settings.isOn(Settings.shelf) && Settings.isOn(Settings.shelfCount)
        // Each includes 6 pt for the notch's curved top corner, which eats into the black area.
        return (peeking ? 32 : 0, (isDancing ? 26 : 0) + (showCount ? 32 : 0))
    }

    /// Starts the clipboard watcher and music detection. Call once, after the callbacks are set.
    func startExtras() {
        AppFiles.lockDown()
        clipboard.onCopy = { [weak self] in self?.copied() }
        nowPlaying.$isPlaying.combineLatest(nowPlaying.$track)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.musicChanged() } }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &bag)
        settingsChanged()
    }

    private func settingsChanged() {
        let keys = [Settings.clipboard, Settings.dancing, Settings.rememberHistory, Settings.danceToVideos, Settings.shelf]
        let now = Dictionary(uniqueKeysWithValues: keys.map { ($0, Settings.isOn($0)) })
        guard now != lastSettings else { return }
        let first = lastSettings.isEmpty
        defer { lastSettings = now }

        if first || now[Settings.clipboard] != lastSettings[Settings.clipboard] {
            clipboard.setEnabled(now[Settings.clipboard] == true)
        }
        if first || now[Settings.dancing] != lastSettings[Settings.dancing] {
            if now[Settings.dancing] == true { nowPlaying.start() } else { nowPlaying.stop() }
        }
        if now[Settings.rememberHistory] != lastSettings[Settings.rememberHistory] {
            clipboard.save()   // writes or deletes the history file
        }
        // Make sure the open tab is one that's switched on.
        if now[Settings.shelf] == false, panel == .shelf { panel = nil }
        if now[Settings.clipboard] == false, panel == .clipboard { panel = nil }
        musicChanged()
    }

    private func musicChanged() {
        let allowed = Settings.isOn(Settings.dancing) && nowPlaying.isPlaying
            && (nowPlaying.track?.isMusic == true || Settings.isOn(Settings.danceToVideos))
        if allowed {
            danceStopTask?.cancel()
            danceStopTask = nil
            if !isDancing {
                isDancing = true
                danceStart = Date()
            }
        } else if isDancing, danceStopTask == nil {
            // Wait 2 s so a gap between songs doesn't stop the dance.
            danceStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.isDancing = false
                self.danceStopTask = nil
            }
        }
        objectWillChange.send()   // the song line may have changed
    }

    private func copied() {
        guard Settings.isOn(Settings.nodOnCopy) else { return }
        nodStart = Date()
        guard !isOpen else { return }
        isNodding = true
        nodTask?.cancel()
        nodTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.isNodding = false
        }
    }

    // MARK: Dropping files on the notch

    func beginDropTargeting() {
        dropTargeting = true
        panel = Settings.isOn(Settings.shelf) ? .shelf : .clipboard
        lineTask?.cancel()
        line = nil
        isListing = false
        cancelEditing()
    }

    func endDropTargeting() {
        dropTargeting = false
    }

    /// Files go on the shelf; text and links dragged in (e.g. from a browser) go to the clipboard history.
    func received(files: [URL], texts: [String]) {
        dropTargeting = false
        if !files.isEmpty, Settings.isOn(Settings.shelf) {
            let overflow = shelf.add(files)
            panel = .shelf
            catchStart = Date()
            say(files.count == 1 ? "Got it!" : "Got all \(files.count)!", for: 1.6)
            Sound.play("Pop")
            if overflow > 0 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(0.9))
                    self?.shrugStart = Date()
                    self?.say("No room! Oldest one's gone.", for: 2)
                }
            }
        }
        if !texts.isEmpty, Settings.isOn(Settings.clipboard) {
            texts.forEach { clipboard.addDropped(text: $0) }
            if files.isEmpty {
                panel = .clipboard
                catchStart = Date()
                say("Saved to clipboard!", for: 1.6)
            }
        }
    }

    // MARK: Clipboard

    func paste(_ item: ClipItem, plainOnly: Bool) {
        onPaste?(item, plainOnly)
    }

    /// Without auto-paste: the item is on the clipboard, you press ⌘V.
    func copiedHint() {
        say("Copied! Press \u{2318}V", for: 2.4)
        waveStart = Date()
    }

    func cannotPin(_ why: String) {
        shrugStart = Date()
        say(why, for: 1.8)
    }

    // MARK: - Open / close

    func open(greet: Bool = true) {
        guard !isOpen else { return }
        let now = Date()
        isOpen = true
        mood = .calm
        openedAt = now
        waveStart = now.addingTimeInterval(0.3)   // wave once the notch has grown
        guard greet else { return }
        say(Skin.current.greetings.randomElement()!, for: 1.8)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        moodTask?.cancel()
        lineTask?.cancel()
        mood = .calm
        line = nil
        alert = nil
        recentHits.removeAll()
        isHeld = false
        isListing = false
        dropTargeting = false
        panel = nil
        cancelEditing()
    }

    // MARK: - Typing a reminder

    func startEditing() {
        guard isOpen, !isEditing else { return }
        lineTask?.cancel()
        line = nil
        alert = nil
        editHint = nil
        isListing = false
        panel = nil
        isEditing = true
        onEditingChanged?(true)
    }

    func cancelEditing() {
        guard isEditing else { return }
        isEditing = false
        editHint = nil
        onEditingChanged?(false)
    }

    /// Saves a reminder from the editor. Returns false (and shows a hint) if the time is no good.
    /// If you never touched the time picker, a time typed into the description ("tea in 5 min") wins.
    func submit(description: String, due picked: Date, pickerTouched: Bool) -> Bool {
        var text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var due = picked
        if !pickerTouched, let parsed = ReminderParser.parse(text) {
            text = parsed.text
            due = parsed.due
        }
        guard due > Date() else {
            editHint = "Pick a time first"
            return false
        }
        if let first = text.first { text = first.uppercased() + text.dropFirst() } else { text = "Time's up!" }

        add(Reminder(text: text, due: due))
        say("Got it! " + ReminderParser.describe(due), for: 2.2)
        waveStart = Date()
        cancelEditing()
        return true
    }

    // MARK: - Reminder list

    func showList() {
        guard isOpen, !reminders.isEmpty else { return }
        lineTask?.cancel()
        line = nil
        alert = nil
        cancelEditing()
        panel = nil
        isListing = true
    }

    func hideList() {
        isListing = false
    }

    /// Loads saved reminders and starts the clock. Call after the callbacks are set.
    func startReminders() {
        reminders = ReminderStore.load()
        scheduleNextReminder()
    }

    func remove(_ id: Reminder.ID) {
        reminders.removeAll { $0.id == id }
        remindersChanged()
    }

    func removeAllReminders() {
        reminders.removeAll()
        remindersChanged()
    }

    private func add(_ reminder: Reminder) {
        reminders.append(reminder)
        reminders.sort { $0.due < $1.due }
        remindersChanged()
    }

    private func remindersChanged() {
        if reminders.isEmpty { isListing = false }
        ReminderStore.save(reminders)
        scheduleNextReminder()
    }

    private func scheduleNextReminder() {
        reminderTask?.cancel()
        guard let next = reminders.first else { return }
        reminderTask = Task { @MainActor [weak self] in
            let wait = next.due.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.fireDueReminders()
        }
    }

    private func fireDueReminders() {
        let now = Date().addingTimeInterval(0.5)
        let due = reminders.filter { $0.due <= now }
        reminders.removeAll { $0.due <= now }
        remindersChanged()
        guard !due.isEmpty else { return }

        lineTask?.cancel()
        line = nil
        alert = "\u{23F0} " + due.map(\.text).joined(separator: " \u{00B7} ")
        let wasOpen = isOpen
        onAttention?()
        waveStart = Date().addingTimeInterval(wasOpen ? 0 : 0.3)
    }

    // MARK: - Getting poked

    func hit() {
        let now = Date()
        hitStart = now
        upsetUntil = now.addingTimeInterval(8)

        // Already seeing stars: just wobble again.
        if mood == .dizzy {
            return
        }

        recentHits = recentHits.filter { now.timeIntervalSince($0) < 1.2 } + [now]

        if recentHits.count >= 3 {
            becomeDizzy("Whoa… stars…")
        } else {
            mood = .hit
            say(["Ow!", "Hey!", "Rude.", "Oof!", "Why?!"].randomElement()!, for: 1.4)
            after(0.8) { [weak self] in
                if self?.mood == .hit { self?.mood = .calm }
            }
        }
    }

    private func becomeDizzy(_ text: String) {
        recentHits.removeAll()
        mood = .dizzy
        dizzyStart = Date()
        say(text, for: nil)
        after(3.2) { [weak self] in
            guard let self else { return }
            self.mood = .calm
            self.say("Okay. I'm fine.", for: 1.8)
            self.waveStart = Date()
        }
    }

    // MARK: - Being picked up and thrown

    func grab() {
        isHeld = true
        say(["Hey! Put me down!", "Whoa, heights!", "Where are we going?"].randomElement()!, for: nil)
    }

    func letGo(thrown: Bool) {
        isHeld = false
        if mood == .dizzy { return }
        say(thrown ? ["Wheee!", "Aaaah!", "Yeet!"].randomElement()! : "Phew.", for: 1.2)
    }

    /// Hit a wall mid-flight: squash, but no complaining.
    func bump() {
        hitStart = Date()
    }

    /// Bounced around too much.
    func flungDizzy() {
        guard mood != .dizzy else { return }
        upsetUntil = Date().addingTimeInterval(8)
        becomeDizzy("Whoa… too fast…")
    }

    // MARK: - Being petted

    /// Slow strokes over Pip. Forgives recent pokes and snaps out of dizziness.
    func petted() {
        let upset = mood != .calm || upsetUntil > Date()
        upsetUntil = .distantPast   // forgiven
        moodTask?.cancel()
        recentHits.removeAll()
        mood = .calm
        let lines = upset
            ? ["Okay… you're forgiven.", "Apology accepted \u{2665}", "Fine. I forgive you."]
            : ["Hehe \u{2665}", "Mmm, that's nice.", "Purr…"]
        say(lines.randomElement()!, for: 2)
    }

    /// Shows a bubble, then clears it after `seconds` (nil = keep until replaced).
    private func say(_ text: String, for seconds: Double?) {
        line = text
        lineTask?.cancel()
        guard let seconds else { return }
        lineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.line = nil
        }
    }

    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        moodTask?.cancel()
        moodTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            work()
        }
    }
}

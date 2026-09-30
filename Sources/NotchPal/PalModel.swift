import SwiftUI

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
}

@MainActor
final class PalModel: ObservableObject {
    /// Size of the notch when it's open.
    static let openSize = CGSize(width: 360, height: 150)

    /// Size of the real notch (measured at launch). Set by NotchController.
    @Published var closedSize = CGSize(width: 190, height: 32)

    /// Mouse position in the window, top-left origin. Only updated while open.
    @Published var mouse: CGPoint = .zero

    @Published private(set) var isOpen = false
    @Published private(set) var mood: Mood = .calm
    /// What Pip is saying right now. nil = no bubble, Pip sits centered.
    @Published private(set) var line: String?

    // Animation clocks. Pip works out every pose from "how long since X happened".
    @Published private(set) var openedAt = Date.distantPast
    @Published private(set) var waveStart = Date.distantPast
    @Published private(set) var hitStart = Date.distantPast
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
    /// Shown under the text field when Pip couldn't find a time.
    @Published private(set) var editHint: String?

    /// Called when a reminder goes off, so the controller can pop the notch open.
    var onAttention: (() -> Void)?
    /// Called when typing starts/stops, so the controller can give the window keyboard focus.
    var onEditingChanged: ((Bool) -> Void)?
    private var reminderTask: Task<Void, Never>?

    /// What the bubble shows: Pip's current line, or the reminder that went off.
    var bubbleText: String? { line ?? alert }

    var snapshot: PalSnapshot {
        PalSnapshot(isOpen: isOpen, mouse: mouse, mood: mood,
                    openedAt: openedAt, waveStart: waveStart,
                    hitStart: hitStart, dizzyStart: dizzyStart)
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
        say(["Hi there!", "Oh, hello!", "Hey you!", "Psst… hi!"].randomElement()!, for: 1.8)
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
        cancelEditing()
    }

    // MARK: - Typing a reminder

    func startEditing() {
        guard isOpen, !isEditing else { return }
        lineTask?.cancel()
        line = nil
        alert = nil
        editHint = nil
        isEditing = true
        onEditingChanged?(true)
    }

    func cancelEditing() {
        guard isEditing else { return }
        isEditing = false
        editHint = nil
        onEditingChanged?(false)
    }

    /// Returns false if the text should stay in the field (Pip couldn't find a time).
    func submit(_ input: String) -> Bool {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else {
            cancelEditing()
            return true
        }
        guard let reminder = ReminderParser.parse(input) else {
            editHint = "When? Try \u{201C}in 10 min\u{201D} or \u{201C}at 3pm\u{201D}"
            return false
        }
        add(reminder)
        say("Got it! " + ReminderParser.describe(reminder.due), for: 2.2)
        waveStart = Date()
        cancelEditing()
        return true
    }

    // MARK: - Reminder list

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

        // Already seeing stars: just wobble again.
        if mood == .dizzy {
            return
        }

        recentHits = recentHits.filter { now.timeIntervalSince($0) < 1.2 } + [now]

        if recentHits.count >= 3 {
            recentHits.removeAll()
            mood = .dizzy
            dizzyStart = now
            say("Whoa… stars…", for: nil)
            after(3.2) { [weak self] in
                guard let self else { return }
                self.mood = .calm
                self.say("Okay. I'm fine.", for: 1.8)
                self.waveStart = Date()
            }
        } else {
            mood = .hit
            say(["Ow!", "Hey!", "Rude.", "Oof!", "Why?!"].randomElement()!, for: 1.4)
            after(0.8) { [weak self] in
                if self?.mood == .hit { self?.mood = .calm }
            }
        }
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

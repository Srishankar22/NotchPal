import SwiftUI

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var model: PalModel

    var body: some View {
        let size = model.isOpen ? model.currentOpenSize : model.closedSize
        let shape = NotchShape(topRadius: model.isOpen ? 14 : 6,
                               bottomRadius: model.isOpen ? 30 : 9)

        ZStack(alignment: .top) {
            if model.isOpen {
                OpenContent(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(color: Color.black.opacity(model.isOpen ? 0.4 : 0), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named("root"))
        .animation(.spring(response: 0.42, dampingFraction: 0.7), value: model.isOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.isEditing)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.isListing)
    }
}

// MARK: - What's inside the open notch

struct OpenContent: View {
    @ObservedObject var model: PalModel

    var body: some View {
        // Pip + bubble are centered as one group: equal space left and right.
        // With no bubble Pip sits in the middle; when one appears Pip slides left.
        HStack(spacing: 10) {
            PipView(model: model)
                .zIndex(1)   // fly over the bubble when thrown
            if model.isEditing {
                ReminderEditor(model: model)
                    .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
            } else if model.isListing {
                ReminderList(model: model)
                    .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
            } else if let text = model.bubbleText {
                SpeechBubble(text: text)
            }
        }
        .padding(.top, model.closedSize.height + 2)   // stay below the camera
        .frame(width: model.currentOpenSize.width, height: model.currentOpenSize.height, alignment: .top)
        .coordinateSpace(.named("notch"))
        .overlay(alignment: .top) { NotchEars(model: model) }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: model.bubbleText)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.isEditing)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.isListing)
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.92))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.1)))
            .frame(maxWidth: 190, alignment: .leading)
            .fixedSize()
            .id(text)
            .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
    }
}

// MARK: - Setting a reminder
// A description, then either "In" (a countdown: h / m / s) or "At" (a clock time with AM/PM).

struct ReminderEditor: View {
    enum Mode { case after, at }
    private enum Field: Hashable { case note, hour, minute, second }

    @ObservedObject var model: PalModel
    @State private var note = ""
    @State private var mode = Mode.after
    @State private var hour = 0
    @State private var minute = 10
    @State private var second = 0
    @State private var isPM = false
    @State private var touched = false
    @FocusState private var focus: Field?

    private let width: CGFloat = 232

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $note,
                      prompt: Text("Description").foregroundStyle(Color.white.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .focused($focus, equals: .note)
                .onSubmit(save)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.14)))

            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    Pill("In", selected: mode == .after) { switchMode(.after) }
                    Pill("At", selected: mode == .at) { switchMode(.at) }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                HStack(spacing: 3) {
                    TimeWheel(value: $hour, range: mode == .at ? 1...12 : 0...23, unit: "h",
                              focus: $focus, field: .hour, onSubmit: save)
                    Colon()
                    TimeWheel(value: $minute, range: 0...59, unit: "m",
                              focus: $focus, field: .minute, onSubmit: save)
                    Colon()
                    TimeWheel(value: $second, range: 0...59, unit: "s",
                              focus: $focus, field: .second, onSubmit: save)
                }
                if mode == .at {
                    Button { isPM.toggle() } label: {
                        Text(isPM ? "PM" : "AM")
                            .frame(width: 30, height: 24)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))

            HStack(spacing: 6) {
                Text(model.editHint ?? preview)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(model.editHint == nil ? Color.white.opacity(0.5) : Color.orange.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: save) {
                    Text("Set")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(width: width)
        .onExitCommand { model.cancelEditing() }
        .onChange(of: hour) { touched = true }
        .onChange(of: minute) { touched = true }
        .onChange(of: second) { touched = true }
        .onChange(of: isPM) { touched = true }
        // The window only becomes key a moment after editing starts.
        .onAppear { DispatchQueue.main.async { focus = .note } }
    }

    // MARK: Working out the time

    private var due: Date {
        let now = Date()
        switch mode {
        case .after:
            return now.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60 + second))
        case .at:
            let h24 = hour % 12 + (isPM ? 12 : 0)
            let today = Calendar.current.date(bySettingHour: h24, minute: minute, second: second, of: now) ?? now
            return today > now ? today : today.addingTimeInterval(86_400)
        }
    }

    private var preview: String {
        switch mode {
        case .after:
            let total = hour * 3600 + minute * 60 + second
            return total == 0 ? "Pick a time" : "Rings in " + ReminderParser.duration(total)
        case .at:
            let d = due
            let time = d.formatted(date: .omitted, time: .standard)
            return Calendar.current.isDateInToday(d) ? "Today " + time : "Tomorrow " + time
        }
    }

    private func switchMode(_ new: Mode) {
        guard new != mode else { return }
        mode = new
        touched = true
        switch new {
        case .after:
            (hour, minute, second) = (0, 10, 0)
        case .at:
            // Start at the next whole hour.
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
            let h24 = Calendar.current.component(.hour, from: next)
            (hour, minute, second, isPM) = (h24 % 12 == 0 ? 12 : h24 % 12, 0, 0, h24 >= 12)
        }
    }

    private func save() {
        _ = model.submit(description: note, due: due, pickerTouched: touched)
    }
}

/// One number you can click up/down or type into.
private struct TimeWheel<F: Hashable>: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    var focus: FocusState<F?>.Binding
    let field: F
    let onSubmit: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            StepButton("chevron.up") { step(1) }
            HStack(spacing: 0) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(width: 20)
                    .focused(focus, equals: field)
                    .onSubmit(onSubmit)
                Text(unit)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
            StepButton("chevron.down") { step(-1) }
        }
        .frame(width: 34)
        .onAppear { text = format(value) }
        .onChange(of: value) { text = format(value) }
        .onChange(of: range) { value = min(max(value, range.lowerBound), range.upperBound) }
        .onChange(of: text) {
            let digits = String(text.filter(\.isNumber).suffix(2))
            if digits != text { text = digits }
            if let n = Int(digits), range.contains(n), n != value { value = n }
        }
        .onChange(of: focus.wrappedValue) {
            // Tidy up when you leave the field ("7" -> "07", junk -> last good value).
            if focus.wrappedValue != field { text = format(value) }
        }
    }

    private func step(_ by: Int) {
        let count = range.count
        value = range.lowerBound + ((value - range.lowerBound + by) % count + count) % count
    }

    private func format(_ n: Int) -> String { String(format: "%02d", n) }
}

private struct StepButton: View {
    let symbol: String
    let action: () -> Void
    init(_ symbol: String, action: @escaping () -> Void) { self.symbol = symbol; self.action = action }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 30, height: 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Colon: View {
    var body: some View {
        Text(":")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.4))
    }
}

private struct Pill: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.7))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(selected ? 0.9 : 0.1)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pending reminders, each with a delete button

struct ReminderList: View {
    @ObservedObject var model: PalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reminders")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Button { model.startEditing() } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                }
                .buttonStyle(.plain)
            }

            // Refresh once a second so "in 4 min" keeps counting down.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(model.reminders) { r in
                            ReminderRow(reminder: r, now: context.date) { model.remove(r.id) }
                        }
                    }
                }
            }
            .frame(maxHeight: 112)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(width: 232)
    }
}

private struct ReminderRow: View {
    let reminder: Reminder
    let now: Date
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(ReminderParser.describe(reminder.due, now: now))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Color.red.opacity(0.9) : Color.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Delete reminder")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.1)))
    }
}

// MARK: - The two "ears" either side of the camera

struct NotchEars: View {
    @ObservedObject var model: PalModel

    var body: some View {
        let width = model.currentOpenSize.width
        let earWidth = max(0, (width - model.closedSize.width) / 2)
        HStack(spacing: 0) {
            // Left: when the next reminder goes off.
            Group {
                if let next = model.reminders.first {
                    // Live countdown when it's close, otherwise the clock time.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Label(ReminderParser.countdown(to: next.due, now: context.date), systemImage: "alarm")
                            .labelStyle(.titleAndIcon)
                            .monospacedDigit()
                    }
                    .help(next.text)
                }
            }
            .frame(width: earWidth)

            Spacer(minLength: 0)

            // Right: add a reminder, or see (and delete) the ones you have.
            Button {
                if model.isEditing || model.isListing {
                    model.cancelEditing()
                    model.hideList()
                } else if model.reminders.isEmpty {
                    model.startEditing()
                } else {
                    model.showList()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: model.reminders.isEmpty ? "bell" : "bell.fill")
                    if !model.reminders.isEmpty { Text("\(model.reminders.count)") }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.reminders.isEmpty ? "Add a reminder" : "Your reminders")
            .contextMenu {
                ForEach(model.reminders) { r in
                    Button("Remove \u{201C}\(r.text)\u{201D} \u{00B7} \(ReminderParser.dayAndTime(r.due))") { model.remove(r.id) }
                }
                if !model.reminders.isEmpty {
                    Divider()
                    Button("Clear All Reminders") { model.removeAllReminders() }
                }
            }
            .frame(width: earWidth)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.6))
        .frame(width: width, height: model.closedSize.height)
    }
}

// MARK: - Notch shape
// Flares out at the top corners (like the real notch meets the screen edge)
// and rounds off at the bottom. Both radii animate.

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = max(0, min(bottomRadius, rect.height - top, (rect.width - 2 * top) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                       control: CGPoint(x: rect.minX + top, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                       control: CGPoint(x: rect.minX + top, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                       control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - top, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

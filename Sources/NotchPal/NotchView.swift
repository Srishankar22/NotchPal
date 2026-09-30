import SwiftUI

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var model: PalModel

    var body: some View {
        let size = model.isOpen ? PalModel.openSize : model.closedSize
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
            if model.isEditing {
                ReminderField(model: model)
                    .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
            } else if let text = model.bubbleText {
                SpeechBubble(text: text)
            }
        }
        .padding(.top, model.closedSize.height + 2)   // stay below the camera
        .frame(width: PalModel.openSize.width, height: PalModel.openSize.height, alignment: .top)
        .overlay(alignment: .top) { NotchEars(model: model) }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: model.bubbleText)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.isEditing)
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

// MARK: - Typing a reminder

struct ReminderField: View {
    @ObservedObject var model: PalModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("", text: $draft,
                      prompt: Text("in 10 min, stretch").foregroundStyle(Color.white.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .focused($focused)
                .onSubmit { if model.submit(draft) { draft = "" } }
                .onExitCommand { model.cancelEditing() }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(width: 170)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.14)))

            if let hint = model.editHint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.leading, 6)
            }
        }
        // The window only becomes key a moment after editing starts.
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

// MARK: - The two "ears" either side of the camera

struct NotchEars: View {
    @ObservedObject var model: PalModel

    var body: some View {
        let earWidth = max(0, (PalModel.openSize.width - model.closedSize.width) / 2)
        HStack(spacing: 0) {
            // Left: when the next reminder goes off.
            Group {
                if let next = model.reminders.first {
                    Label(ReminderParser.shortTime(next.due), systemImage: "alarm")
                        .labelStyle(.titleAndIcon)
                        .help(next.text)
                }
            }
            .frame(width: earWidth)

            Spacer(minLength: 0)

            // Right: add a reminder. Right-click to see or delete them.
            Button { model.isEditing ? model.cancelEditing() : model.startEditing() } label: {
                HStack(spacing: 3) {
                    Image(systemName: model.reminders.isEmpty ? "bell" : "bell.fill")
                    if !model.reminders.isEmpty { Text("\(model.reminders.count)") }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a reminder")
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
        .frame(width: PalModel.openSize.width, height: model.closedSize.height)
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

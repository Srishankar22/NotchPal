import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The right side of the open notch: Pip's line, Shelf / Clipboard tabs

struct TabbedPanel: View {
    @ObservedObject var model: PalModel
    @ObservedObject var shelf: ShelfStore
    @AppStorage(Settings.shelf) private var shelfOn = true
    @AppStorage(Settings.clipboard) private var clipboardOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let text = model.bubbleText {
                    SpeechLine(text: text, scrolls: text == model.musicLine)
                }
                Spacer(minLength: 0)
                if shelfOn {
                    TabButton(title: "Shelf", count: shelf.items.count, selected: model.panel == .shelf) {
                        model.panel = .shelf
                    }
                }
                if clipboardOn {
                    TabButton(title: "Clipboard", count: nil, selected: model.panel == .clipboard) {
                        model.panel = .clipboard
                    }
                }
                // Back to the small notch with just Pip.
                Button { model.panel = nil } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Hide")
            }
            .frame(height: 26)

            Group {
                if model.panel == .shelf && shelfOn {
                    ShelfView(model: model, shelf: shelf)
                } else if clipboardOn {
                    ClipboardView(model: model, clipboard: model.clipboard)
                } else if shelfOn {
                    ShelfView(model: model, shelf: shelf)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.panel)
    }
}

private struct TabButton: View {
    let title: String
    let count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)").foregroundStyle(selected ? Color.black.opacity(0.5) : Color.white.opacity(0.45))
                }
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.7))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.9 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Pip's speech bubble, one line, tail pointing left at Pip. Long song titles scroll.
struct SpeechLine: View {
    let text: String
    var scrolls = false
    private let maxWidth: CGFloat = 196

    var body: some View {
        Group {
            if scrolls {
                MarqueeText(text: text, width: maxWidth - 24)
            } else {
                Text(text).lineLimit(1).truncationMode(.tail)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 11)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.12)))
        .frame(maxWidth: maxWidth, alignment: .leading)
        .fixedSize(horizontal: !scrolls, vertical: false)
        .id(text)
        .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
    }
}

/// Scrolls sideways if the text doesn't fit; sits still if it does.
private struct MarqueeText: View {
    let text: String
    let width: CGFloat
    @State private var textWidth: CGFloat = 0

    var body: some View {
        let overflow = textWidth > width
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !overflow)) { context in
            let gap: CGFloat = 36
            let cycle = textWidth + gap
            let t = context.date.timeIntervalSinceReferenceDate
            let x = overflow ? -CGFloat((t * 28).truncatingRemainder(dividingBy: Double(max(cycle, 1)))) : 0
            HStack(spacing: gap) {
                Text(text).fixedSize()
                if overflow { Text(text).fixedSize() }
            }
            .offset(x: x)
            .frame(width: overflow ? width : nil, alignment: .leading)
            .clipped()
        }
        .background(
            Text(text).fixedSize().hidden()
                .background(GeometryReader { g in Color.clear.onAppear { textWidth = g.size.width } })
        )
    }
}

// MARK: - Shelf tab

struct ShelfView: View {
    @ObservedObject var model: PalModel
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        ZStack {
            if shelf.items.isEmpty {
                DropArea(text: "Drag files here to keep them", highlighted: false)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf, model: model)
                        }
                        Button { shelf.clear() } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                                Text("Clear all").font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 50, height: 84)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            if model.dropTargeting {
                DropArea(text: "Drop here", highlighted: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.dropTargeting)
        .onAppear { shelf.refresh() }
    }
}

private struct DropArea: View {
    let text: String
    let highlighted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(Color.white.opacity(highlighted ? 0.8 : 0.3))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(highlighted ? 0.12 : 0.03)))
            .overlay {
                VStack(spacing: 5) {
                    Image(systemName: highlighted ? "arrow.down.to.line" : "tray")
                        .font(.system(size: 16, weight: .semibold))
                    Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.white.opacity(highlighted ? 0.9 : 0.45))
            }
            .frame(height: 88)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var model: PalModel
    @State private var hovering = false

    var body: some View {
        let missing = shelf.missing.contains(item.id)
        let icon = shelf.icon(for: item)
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                Text(item.name)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(width: 52, height: 26, alignment: .top)
                if missing {
                    Text("missing").font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.orange.opacity(0.9))
                }
            }
            .opacity(missing ? 0.4 : 1)
            .frame(width: 56, height: 84, alignment: .top)
            .padding(.top, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.12 : 0)))
            .overlay {
                FileDragSource(
                    url: missing ? nil : shelf.url(for: item),
                    icon: icon,
                    onHover: { hovering = $0 },
                    onDragging: { model.isDraggingOut = $0 },
                    onDoubleClick: { shelf.open(item) },
                    menu: { [
                        ("Open", missing ? nil : { shelf.open(item) }),
                        ("Show in Finder", missing ? nil : { shelf.reveal(item) }),
                        ("Copy Path", { shelf.copyPath(item) }),
                        ("Remove", { shelf.remove(item.id) }),
                    ] }
                )
            }
            .help(missing ? "\(item.name) (missing)" : item.name)

            if hovering {
                Button { shelf.remove(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -1)
            }
        }
    }
}

// MARK: Dragging a shelf item out (AppKit, so copy vs. move can be controlled)

struct FileDragSource: NSViewRepresentable {
    typealias MenuEntry = (title: String, action: (() -> Void)?)

    let url: URL?
    let icon: NSImage
    var onHover: (Bool) -> Void
    var onDragging: (Bool) -> Void
    var onDoubleClick: () -> Void
    var menu: () -> [MenuEntry]

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.url = url
        view.icon = icon
        view.onHover = onHover
        view.onDragging = onDragging
        view.onDoubleClick = onDoubleClick
        view.makeMenu = menu
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var url: URL?
    var icon: NSImage?
    var onHover: ((Bool) -> Void)?
    var onDragging: ((Bool) -> Void)?
    var onDoubleClick: (() -> Void)?
    var makeMenu: (() -> [FileDragSource.MenuEntry])?
    private var mouseDownEvent: NSEvent?
    private var actions: [MenuAction] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let url else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard hypot(dx, dy) > 3 else { return }
        mouseDownEvent = nil

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = icon ?? NSWorkspace.shared.icon(forFile: url.path)
        let p = convert(down.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40), contents: image)
        onDragging?(true)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    /// Copies by default; hold Command to move instead. Nothing happens if dropped back on the notch.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .outsideApplication else { return [] }
        return NSEvent.modifierFlags.contains(.command) ? .move : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragging?(false)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let entries = makeMenu?() else { return }
        let menu = NSMenu()
        actions = entries.map { MenuAction($0.action) }
        for (entry, action) in zip(entries, actions) {
            let mi = NSMenuItem(title: entry.title, action: entry.action == nil ? nil : #selector(MenuAction.run),
                                keyEquivalent: "")
            mi.target = action
            mi.isEnabled = entry.action != nil
            menu.addItem(mi)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

private final class MenuAction: NSObject {
    let action: (() -> Void)?
    init(_ action: (() -> Void)?) { self.action = action }
    @objc func run() { action?() }
}

// MARK: - Clipboard tab

struct ClipboardView: View {
    @ObservedObject var model: PalModel
    @ObservedObject var clipboard: ClipboardStore
    @State private var hovered: ClipItem.ID?

    var body: some View {
        if clipboard.items.isEmpty {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    VStack(spacing: 5) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 16, weight: .semibold))
                        Text(clipboard.isPaused ? "Paused for now" : "Copy something with \u{2318}C and it shows up here")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.white.opacity(0.45))
                }
                .frame(height: 112)
        } else {
            HStack(alignment: .top, spacing: 8) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(clipboard.items) { item in
                            ClipRow(item: item, thumbnail: clipboard.thumbnail(for: item), hovered: hovered == item.id,
                                    paste: { plain in model.paste(item, plainOnly: plain) },
                                    pin: { if let why = clipboard.togglePin(item.id) { model.cannotPin(why) } },
                                    delete: { clipboard.remove(item.id) },
                                    addToShelf: { model.shelf.add((item.files ?? []).map { URL(fileURLWithPath: $0) }) })
                                .onHover { inside in
                                    if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
                                }
                        }
                    }
                }
                .frame(width: 214)

                let shown = clipboard.items.first { $0.id == hovered } ?? clipboard.items.first
                ClipPreview(item: shown, thumbnail: shown.flatMap(clipboard.thumbnail(for:)),
                            paused: clipboard.pausedUntil.flatMap { $0 > Date() ? $0 : nil },
                            clear: { clipboard.clearHistory() })
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let thumbnail: NSImage?
    let hovered: Bool
    let paste: (_ plainOnly: Bool) -> Void
    let pin: () -> Void
    let delete: () -> Void
    let addToShelf: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            ClipIcon(item: item, thumbnail: thumbnail).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .lineLimit(item.kind == .text || item.kind == .rich ? 2 : 1)
                if item.kind == .link {
                    Text(item.plain ?? "").font(.system(size: 9, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if item.kind == .rich {
                Text("Aa").font(.system(size: 8.5, weight: .heavy, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            if hovered || item.pinned {
                Button(action: pin) {
                    Image(systemName: item.pinned ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.pinned ? Color.yellow.opacity(0.9) : Color.white.opacity(0.6))
                        .frame(width: 16, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.pinned ? "Unpin" : "Pin")
            }
            if hovered {
                Button(action: delete) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 16, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(hovered ? 0.14 : 0.06)))
        .contentShape(Rectangle())
        .onTapGesture { paste(NSEvent.modifierFlags.contains(.option)) }
        .contextMenu {
            Button("Paste") { paste(false) }
            if item.kind == .rich { Button("Paste as Plain Text") { paste(true) } }
            Button(item.pinned ? "Unpin" : "Pin", action: pin)
            if item.kind == .files { Button("Add to Shelf", action: addToShelf) }
            Divider()
            Button("Delete", action: delete)
        }
    }
}

private struct ClipIcon: View {
    let item: ClipItem
    let thumbnail: NSImage?

    var body: some View {
        switch item.kind {
        case .image:
            if let image = thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                symbol("photo")
            }
        case .files:
            if let first = item.files?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first)).resizable()
            } else {
                symbol("doc")
            }
        case .link: symbol("link")
        case .rich: symbol("textformat")
        case .text: symbol("text.alignleft")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.6))
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
    }
}

/// A bigger look at the hovered item.
private struct ClipPreview: View {
    let item: ClipItem?
    let thumbnail: NSImage?
    let paused: Date?
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let item {
                    content(item)
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let paused {
                Text("Paused until " + paused.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.orange.opacity(0.85))
            }
            HStack {
                Text(item?.kind == .rich ? "Click to paste \u{00B7} \u{2325} plain" : "Click to paste")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer(minLength: 0)
                Button(action: clear) {
                    Text("Clear history")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Removes everything except pinned items")
            }
        }
        .padding(8)
        .frame(height: 112)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text, .rich:
            Text(item.plain ?? "")
                .font(.system(size: 10, design: .rounded))
                .lineLimit(5)
        case .link:
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(string: item.plain ?? "")?.host ?? "Link")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text(item.plain ?? "").font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6)).lineLimit(4)
            }
        case .image:
            if let image = thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        case .files:
            VStack(alignment: .leading, spacing: 4) {
                ForEach((item.files ?? []).prefix(3), id: \.self) { path in
                    HStack(spacing: 5) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 16, height: 16)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 10, design: .rounded)).lineLimit(1).truncationMode(.middle)
                    }
                }
                if (item.files?.count ?? 0) > 3 {
                    Text("+\((item.files?.count ?? 0) - 3) more")
                        .font(.system(size: 9, design: .rounded)).foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Beside the closed notch: dancing Pip, music bars, shelf count

struct ClosedWings: View {
    @ObservedObject var model: PalModel
    @ObservedObject var shelf: ShelfStore
    let left: CGFloat
    let right: CGFloat
    @AppStorage("skin") private var skin: Skin = .pip

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if model.isDancing || model.isNodding {
                    // Centered in the band, clear of the rounded bottom corner.
                    PeekPip(skin: skin, nodding: model.isNodding && !model.isDancing)
                        .frame(width: PeekPip.box, height: PeekPip.box)
                        .padding(.trailing, 2)
                }
            }
            // Tucked in against the camera rather than out at the edge.
            .frame(width: left, alignment: .trailing)

            Color.clear.frame(width: model.closedSize.width)

            HStack(spacing: 4) {
                if model.isDancing {
                    MusicBars().frame(width: 13, height: 14)
                }
                if right > (model.isDancing ? 26 : 0) {
                    HStack(spacing: 2) {
                        Image(systemName: "tray.full.fill").font(.system(size: 9, weight: .semibold))
                        Text("\(shelf.items.count)").font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.white.opacity(0.65))
                }
            }
            .padding(.leading, 3)
            .frame(width: right, alignment: .leading)
        }
        .frame(height: model.closedSize.height)
    }
}

// The peek runs as Core Animation layer animations, which the window server plays by itself:
// NotchPal does no per-frame work while music plays with the notch closed.

private let beat: CFTimeInterval = 60.0 / 110   // ~110 BPM

/// Tiny happy Pip bopping (or nodding once after a copy).
private struct PeekPip: NSViewRepresentable {
    static let box: CGFloat = 24
    static let pipSize: CGFloat = 14

    let skin: Skin
    let nodding: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        let pip = CALayer()
        pip.name = "pip"
        pip.contentsGravity = .resizeAspect
        view.layer?.addSublayer(pip)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let pip = view.layer?.sublayers?.first(where: { $0.name == "pip" }) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pip.frame = CGRect(x: 0, y: 0, width: Self.box, height: Self.box)
        pip.contentsScale = view.window?.backingScaleFactor ?? 2
        if context.coordinator.skin != skin || pip.contents == nil {
            pip.contents = Self.image(skin: skin, scale: pip.contentsScale)
            context.coordinator.skin = skin
        }
        CATransaction.commit()

        let mode = nodding ? "nod" : "dance"
        guard context.coordinator.mode != mode else { return }
        context.coordinator.mode = mode
        pip.removeAllAnimations()

        if nodding {
            let nod = CAKeyframeAnimation(keyPath: "transform.translation.y")
            nod.values = [0, -2, 0, -2, 0]   // layer y points up; negative = down
            nod.duration = 1.0
            pip.add(nod, forKey: "nod")
        } else {
            let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bob.values = [0, 1.8, 0]
            bob.keyTimes = [0, 0.5, 1]
            bob.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
            bob.duration = beat
            bob.repeatCount = .infinity
            pip.add(bob, forKey: "bob")

            let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            sway.values = [0, 0.12, 0, -0.12, 0]
            sway.duration = beat * 2
            sway.repeatCount = .infinity
            pip.add(sway, forKey: "sway")
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var skin: Skin?
        var mode: String?
    }

    @MainActor
    private static func image(skin: Skin, scale: CGFloat) -> CGImage? {
        var pose = Pose()
        pose.eyeStyle = .happy
        pose.cheekGlow = 0.6
        let renderer = ImageRenderer(content: PipDrawing(pose: pose, size: pipSize, skin: skin)
            .frame(width: box, height: box))
        renderer.scale = scale
        return renderer.cgImage
    }
}

/// Three little bars bouncing at different phases.
private struct MusicBars: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        let color = NSColor(red: 1.0, green: 0.72, blue: 0.5, alpha: 1).cgColor
        for i in 0..<3 {
            let bar = CALayer()
            bar.backgroundColor = color
            bar.cornerRadius = 1.5
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.frame = CGRect(x: CGFloat(i) * 5, y: 0, width: 3, height: 14)

            let grow = CAKeyframeAnimation(keyPath: "bounds.size.height")
            grow.values = [4, 13, 6, 11, 4]
            grow.duration = beat * 2
            grow.repeatCount = .infinity
            grow.timeOffset = beat * 2 * Double(i) / 3   // out of step with each other
            bar.add(grow, forKey: "grow")
            view.layer?.addSublayer(bar)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

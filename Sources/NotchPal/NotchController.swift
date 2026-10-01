import AppKit
import SwiftUI

// MARK: - Window types

/// A borderless panel that floats over the menu bar and never steals focus.
final class NotchPanel: NSPanel {
    /// Only takes keyboard focus while you're typing a reminder.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    // Allow the window to sit on top of the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Lets the very first click reach Pip, even though the app isn't active.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Notch measurement

struct NotchGeometry {
    let screen: NSScreen
    let size: CGSize

    @MainActor
    static func current() -> NotchGeometry? {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main ?? screens.first else { return nil }

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // Real notch: the gap between the two usable menu bar areas.
            return NotchGeometry(screen: screen,
                                 size: CGSize(width: right.minX - left.maxX,
                                              height: screen.safeAreaInsets.top))
        }
        // No notch (external display, older Mac): draw a small fake one.
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(screen: screen, size: CGSize(width: 180, height: menuBar))
    }
}

// MARK: - Controller

@MainActor
final class NotchController {
    /// The window is a little bigger than the open notch so the springy
    /// overshoot and the shadow never get cut off.
    private static let windowSize = CGSize(width: 620, height: 270)

    let model = PalModel()
    private var panel: NotchPanel?
    private var screenFrame: CGRect = .zero
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var closeTask: Task<Void, Never>?
    private var watchTimer: Timer?
    /// Opened by a reminder: stay open until the mouse has visited once.
    private var waitingForHover = false
    /// Stay open (even with the mouse away) until this time, e.g. so "Got it!" can be read.
    private var keepOpenUntil = Date.distantPast
    /// A file (or text) is being dragged somewhere on screen, toward the notch maybe.
    private var fileDragActive = false
    private var dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var askedForAccessibility: Bool {
        get { UserDefaults.standard.bool(forKey: "askedAccessibility") }
        set { UserDefaults.standard.set(newValue, forKey: "askedAccessibility") }
    }

    func start() {
        let panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.windowSize),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let host = FirstClickHostingView(rootView: NotchRootView(model: model, shelf: model.shelf))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel

        layout()
        panel.orderFrontRegardless()
        installMonitors()

        model.onAttention = { [weak self] in self?.openForReminder() }
        model.onEditingChanged = { [weak self] editing in self?.editingChanged(editing) }
        model.onPaste = { [weak self] item, plain in self?.paste(item, plainOnly: plain) }
        model.startReminders()
        model.startExtras()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    // MARK: Layout

    private func layout() {
        guard let notch = NotchGeometry.current(), let panel else { return }
        screenFrame = notch.screen.frame
        model.closedSize = notch.size
        let size = Self.windowSize
        panel.setFrame(NSRect(x: screenFrame.midX - size.width / 2,
                              y: screenFrame.maxY - size.height,
                              width: size.width, height: size.height),
                       display: true)
    }

    /// The closed notch as drawn right now, including any wings beside it (screen coordinates).
    private var closedRect: CGRect {
        let wings = model.closedWings(shelfCount: model.shelf.items.count)
        let size = model.closedSize
        return CGRect(x: screenFrame.midX - size.width / 2 - wings.left, y: screenFrame.maxY - size.height,
                      width: size.width + wings.left + wings.right, height: size.height)
    }

    /// A rect of the given size hugging the top-center of the screen (screen coordinates).
    private func topRect(_ size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
               width: size.width, height: size.height)
    }

    // MARK: Mouse

    private func installMonitors() {
        // Watching mouse movement doesn't need any special permission.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated {
                if dragging { self?.draggedElsewhere() }
                self?.mouseMoved()
            }
        }) { monitors.append(m) }
        // Start / end of a drag in another app (Finder, a browser…).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp], handler: { [weak self] event in
            let down = event.type == .leftMouseDown
            MainActor.assumeIsolated {
                if down { self?.dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount } else { self?.endFileDrag() }
            }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) { monitors.append(m) }
        // A click anywhere else stops typing (clicks on the notch itself never get here).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.model.cancelEditing() }
        }) { monitors.append(m) }
    }

    private func mouseMoved() {
        guard let panel else { return }
        let p = NSEvent.mouseLocation
        let win = panel.frame
        let local = CGPoint(x: p.x - win.minX, y: win.maxY - p.y)

        if model.isOpen {
            model.mouse = local
            // Holding Pip, dragging a shelf item out, or a file on its way in: keep the notch open
            // and keep getting the mouse, wherever it goes.
            if model.isHeld || model.isDraggingOut || fileDragActive {
                panel.ignoresMouseEvents = false
                cancelClose()
                return
            }
            let inside = topRect(model.currentOpenSize).insetBy(dx: -10, dy: -10).contains(p)
            // Only catch clicks where the notch actually is; everywhere else passes through.
            panel.ignoresMouseEvents = !inside
            if inside { waitingForHover = false }
            if inside || model.isEditing || waitingForHover || Date() < keepOpenUntil {
                cancelClose()
            } else {
                scheduleClose()
            }
        } else {
            panel.ignoresMouseEvents = true
            if closedRect.insetBy(dx: -10, dy: -4).contains(p) {
                model.mouse = local
                open()
            }
        }
    }

    // MARK: Files dragged toward the notch

    /// Another app is dragging something. If it's a file (or text) and it comes within ~40 pt,
    /// open on the Shelf with a "Drop here" area, no hover needed.
    private func draggedElsewhere() {
        guard !model.isDraggingOut,
              Settings.isOn(Settings.shelf) || Settings.isOn(Settings.clipboard) else { return }
        if !fileDragActive {
            let pb = NSPasteboard(name: .drag)
            guard pb.changeCount != dragCountAtMouseDown,
                  let types = pb.types,
                  types.contains(.fileURL) || types.contains(.URL) || types.contains(.string) else { return }
            fileDragActive = true
        }
        let p = NSEvent.mouseLocation
        let target = model.isOpen ? topRect(model.currentOpenSize) : closedRect
        guard target.insetBy(dx: -40, dy: -40).contains(p) else { return }
        if !model.isOpen { open(greet: false) }
        if !model.dropTargeting { model.beginDropTargeting() }
        panel?.ignoresMouseEvents = false
    }

    private func endFileDrag() {
        guard fileDragActive else { return }
        fileDragActive = false
        model.endDropTargeting()
    }

    // MARK: Pasting a clipboard item

    /// Puts the item on the clipboard. With auto-paste (and Accessibility allowed) the notch closes
    /// and ⌘V is pressed for you, into the text field you were in: the notch never took focus.
    private func paste(_ item: ClipItem, plainOnly: Bool) {
        model.clipboard.write(item, plainOnly: plainOnly)
        handBackKeyboard()   // ⌘V must land in your app, not the notch
        guard Settings.isOn(Settings.autoPaste) else {
            model.copiedHint()
            keepOpenUntil = Date().addingTimeInterval(2.4)
            return
        }
        if AXIsProcessTrusted() {
            close()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                Self.pressCommandV()
            }
        } else {
            if !askedForAccessibility {
                askedForAccessibility = true
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            }
            model.copiedHint()
            keepOpenUntil = Date().addingTimeInterval(2.4)
        }
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9   // "V"
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: Open / close

    private func open(greet: Bool = true) {
        cancelClose()
        model.open(greet: greet)
        panel?.ignoresMouseEvents = false
        // Backup check in case a mouse event gets missed (e.g. switching Spaces).
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // Backup for a missed mouse-up at the end of a drag.
                if self?.fileDragActive == true, NSEvent.pressedMouseButtons & 1 == 0 { self?.endFileDrag() }
                self?.mouseMoved()
            }
        }
    }

    private func openForReminder() {
        guard !model.isOpen else { return }
        waitingForHover = true
        open(greet: false)
    }

    private func editingChanged(_ editing: Bool) {
        guard let panel else { return }
        if editing {
            panel.allowsKey = true
            panel.makeKey()
        } else {
            panel.allowsKey = false
            // The keyboard goes back to your app later (handBackKeyboard): doing it now means
            // briefly hiding the window, which would cut off the notch's resize animation.
            // Give Pip's "Got it!" a moment on screen even if the mouse has left.
            if model.line != nil { keepOpenUntil = Date().addingTimeInterval(2.2) }
        }
    }

    /// After typing a reminder the notch still holds the keyboard. Give it back to the app you
    /// were using: hiding and re-showing the window is what makes macOS do that.
    private func handBackKeyboard() {
        guard let panel, panel.isKeyWindow, !panel.allowsKey else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func scheduleClose() {
        guard closeTask == nil else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func close() {
        closeTask = nil
        waitingForHover = false
        keepOpenUntil = .distantPast
        watchTimer?.invalidate()
        watchTimer = nil
        panel?.ignoresMouseEvents = true
        model.close()
        // Once the shrink animation has finished, so it isn't cut short.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !self.model.isOpen else { return }
            self.handBackKeyboard()
        }
    }
}

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
    private static let windowSize = CGSize(width: 440, height: 230)

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

        let host = FirstClickHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel

        layout()
        panel.orderFrontRegardless()
        installMonitors()

        model.onAttention = { [weak self] in self?.openForReminder() }
        model.onEditingChanged = { [weak self] editing in self?.editingChanged(editing) }
        model.startReminders()

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

    /// A rect of the given size hugging the top-center of the screen (screen coordinates).
    private func topRect(_ size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
               width: size.width, height: size.height)
    }

    // MARK: Mouse

    private func installMonitors() {
        // Watching mouse movement doesn't need any special permission.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
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
            if topRect(model.closedSize).insetBy(dx: -10, dy: -4).contains(p) {
                model.mouse = local
                open()
            }
        }
    }

    // MARK: Open / close

    private func open(greet: Bool = true) {
        cancelClose()
        model.open(greet: greet)
        panel?.ignoresMouseEvents = false
        // Backup check in case a mouse event gets missed (e.g. switching Spaces).
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
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
            // Hand the keyboard back to whatever app you were using.
            if panel.isKeyWindow {
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
            // Give Pip's "Got it!" a moment on screen even if the mouse has left.
            if model.line != nil { keepOpenUntil = Date().addingTimeInterval(2.2) }
        }
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
    }
}

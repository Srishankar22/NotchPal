import SwiftUI
import AppKit

@main
struct NotchPalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A tiny menu bar icon, mostly so you have a way to quit.
        MenuBarExtra("NotchPal", systemImage: "face.smiling") {
            Button("Quit NotchPal") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = NotchController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon
        controller.start()
    }
}

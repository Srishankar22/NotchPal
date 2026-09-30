import SwiftUI
import AppKit
import ServiceManagement

@main
struct NotchPalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A tiny menu bar icon, mostly so you have a way to quit.
        MenuBarExtra("NotchPal", systemImage: "face.smiling") {
            // Only works when running as NotchPal.app (see build-app.sh).
            if Bundle.main.bundleIdentifier != nil {
                LoginItemToggle()
                Divider()
            }
            Button("Quit NotchPal") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

struct LoginItemToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at Login", isOn: Binding(
            get: { enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("NotchPal: couldn't change login item: \(error)")
                }
                enabled = SMAppService.mainApp.status == .enabled
            }))
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

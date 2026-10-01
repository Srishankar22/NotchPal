import SwiftUI
import AppKit
import ServiceManagement

@main
struct NotchPalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The smiley in the menu bar: every setting lives here as an on/off toggle.
        MenuBarExtra("NotchPal", systemImage: "face.smiling") {
            MenuContent(model: appDelegate.controller.model)
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
    let controller = NotchController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.model.nowPlaying.stop()
        controller.model.clipboard.save()   // flush a batched history save
    }
}

// MARK: - Menu bar menu

struct MenuContent: View {
    @ObservedObject var model: PalModel
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var nowPlaying: NowPlayingMonitor

    // Defaults here must match Settings.defaults.
    @AppStorage(Settings.shelf) private var shelf = true
    @AppStorage(Settings.shelfCount) private var shelfCount = true
    @AppStorage(Settings.clipboard) private var clipboardOn = true
    @AppStorage(Settings.autoPaste) private var autoPaste = true
    @AppStorage(Settings.rememberHistory) private var remember = false
    @AppStorage(Settings.nodOnCopy) private var nod = false
    @AppStorage(Settings.dancing) private var dancing = true
    @AppStorage(Settings.danceToVideos) private var videos = true
    @AppStorage(Settings.showSongTitle) private var songTitle = true
    @AppStorage(Settings.sounds) private var sounds = false

    init(model: PalModel) {
        self.model = model
        self.clipboard = model.clipboard
        self.nowPlaying = model.nowPlaying
    }

    var body: some View {
        CharacterPicker()
        Divider()

        Section("File Shelf") {
            Toggle("File Shelf", isOn: $shelf)
            Toggle("Show Shelf Count Beside the Notch", isOn: $shelfCount)
        }
        Section("Clipboard") {
            Toggle("Clipboard History", isOn: $clipboardOn)
            Toggle("Auto-Paste When Clicking an Item", isOn: $autoPaste)
            Toggle("Remember Clipboard History After Restart", isOn: $remember)
            Toggle("Pip Nods Each Time You Copy", isOn: $nod)
        }
        Section("Music") {
            Toggle("Dancing Pip", isOn: $dancing)
            Toggle("Dance to Videos Too, Not Just Music", isOn: $videos)
            Toggle("Show Song Title", isOn: $songTitle)
            if dancing && !nowPlaying.available {
                Text("Music detection unavailable")
            }
        }
        Toggle("Sounds", isOn: $sounds)
        Divider()

        if clipboard.isPaused {
            Button("Resume Clipboard History") { clipboard.resume() }
        } else {
            Button("Pause Clipboard for 1 Hour") { clipboard.pause(for: 3600) }
                .disabled(!clipboardOn)
        }
        Button("Clear Shelf") { model.shelf.clear() }
        Button("Clear Clipboard History") { clipboard.clearHistory() }
        Divider()

        // Only works when running as NotchPal.app (see build-app.sh).
        if Bundle.main.bundleIdentifier != nil {
            LoginItemToggle()
        }
        Button("Quit NotchPal") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

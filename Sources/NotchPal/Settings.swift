import AppKit
import SwiftUI

// MARK: - Settings
// Every setting is an on/off toggle in the menu bar menu (see MenuContent), stored in
// UserDefaults so views can bind to it with @AppStorage(Settings.key).

enum Settings {
    static let shelf = "shelfEnabled"
    static let shelfCount = "shelfCountBesideNotch"
    static let clipboard = "clipboardEnabled"
    static let autoPaste = "autoPaste"
    static let rememberHistory = "rememberClipboardHistory"
    static let nodOnCopy = "nodOnCopy"
    static let dancing = "dancingPip"
    static let danceToVideos = "danceToVideos"
    static let showSongTitle = "showSongTitle"
    static let sounds = "sounds"

    /// Defaults, used until you change a setting. Keep in step with the @AppStorage defaults in MenuContent.
    static let defaults: [String: Bool] = [
        shelf: true,
        shelfCount: true,
        clipboard: true,
        autoPaste: true,
        rememberHistory: false,
        nodOnCopy: false,
        dancing: true,
        danceToVideos: true,
        showSongTitle: true,
        // Off: Pip was asked to be quiet. Flip it on in the menu bar menu.
        sounds: false,
    ]

    static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaults[key] ?? false
    }
}

enum PanelTab: String, CaseIterable {
    case shelf, clipboard
}

/// Where NotchPal keeps its files: ~/Library/Application Support/NotchPal, readable only by you.
enum AppFiles {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("NotchPal", isDirectory: true)
        #if DEBUG
        // Debug builds only: lets tests use a scratch folder instead of your real data.
        if let custom = ProcessInfo.processInfo.environment["NOTCHPAL_DATA_DIR"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        }
        #endif
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        return dir
    }

    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    /// Makes sure the folder is private (owner only), even if it was made some other way.
    static func lockDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }

    /// Writes atomically and makes the file private (owner read/write only).
    static func write(_ data: Data, to name: String) {
        let file = url(name)
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // Never log contents; just the fact that saving failed.
            NSLog("NotchPal: couldn't save \(name)")
        }
    }

    static func read(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }

    static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }
}

// MARK: - Sounds (built-in macOS sounds, only when the Sounds setting is on)

@MainActor
enum Sound {
    private static var cache: [String: NSSound] = [:]

    static func play(_ name: String, volume: Float = 0.4) {
        guard Settings.isOn(Settings.sounds),
              let sound = cache[name] ?? NSSound(named: NSSound.Name(name)) else { return }
        cache[name] = sound
        sound.stop()
        sound.volume = volume
        sound.play()
    }
}

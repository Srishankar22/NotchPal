import Foundation

// MARK: - What's playing on the Mac
// macOS keeps one "Now Playing" record (what Control Center's player shows). Since macOS 15.4
// only Apple's own programs may read it, so this runs the open-source mediaremote-adapter
// (Vendor/mediaremote-adapter, BSD 3-Clause) through Apple's /usr/bin/perl, which is allowed to.
// It streams one JSON line per change; nothing is polled, and nothing is logged.

@MainActor
final class NowPlayingMonitor: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var bundleID: String
        var isMusic: Bool
    }

    /// Something is playing right now (raw, not debounced).
    @Published private(set) var isPlaying = false
    @Published private(set) var track: Track?
    /// False when the workaround doesn't work (missing files, or Apple closed the loophole).
    @Published private(set) var available = true

    private var process: Process?
    private var buffer = Data()
    private var restarts = 0
    private var stopping = false

    /// Apps whose media counts as music (everything else, like a browser tab, counts as video).
    private static let musicApps: Set<String> = [
        "com.spotify.client", "com.apple.Music", "com.apple.iTunes", "com.apple.podcasts",
        "com.tidal.desktop", "com.amazon.music", "com.deezer.deezer-desktop", "com.soundcloud.desktop",
        "com.apple.Music.MiniPlayer",
    ]

    func start() {
        guard process == nil else { return }
        guard let paths = Self.adapterPaths() else {
            available = false
            return
        }
        stopping = false

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [paths.script.path, paths.framework.path, "stream",
                       "--no-artwork", "--no-diff", "--debounce=200"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice   // song titles must never end up in a log
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            // Empty = the helper closed its output. Stop listening, or this fires in a tight loop.
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in self?.receive(chunk) }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { @MainActor in self?.ended(status: status) }
        }
        do {
            try p.run()
            process = p
        } catch {
            available = false
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
    }

    private func ended(status: Int32) {
        process = nil
        guard !stopping else { return }
        isPlaying = false
        track = nil
        // Crashed or refused: try a couple of times, then give up until next launch.
        restarts += 1
        if restarts > 3 {
            available = false
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.start()
        }
    }

    private func receive(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: Data(line))
        }
        if buffer.count > 1_000_000 { buffer.removeAll() }   // runaway line; drop it
    }

    private func handle(line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return }
        available = true
        restarts = 0

        guard let title = payload["title"] as? String,
              let bundle = payload["bundleIdentifier"] as? String else {
            isPlaying = false
            track = nil
            return
        }
        let parent = payload["parentApplicationBundleIdentifier"] as? String
        let mediaType = (payload["mediaType"] as? String ?? "").lowercased()
        let isMusic = Self.musicApps.contains(bundle) || parent.map(Self.musicApps.contains) == true
            || payload["isMusicApp"] as? Bool == true
            || mediaType.contains("music") || mediaType.contains("audio")

        track = Track(title: title, artist: payload["artist"] as? String ?? "",
                      bundleID: bundle, isMusic: isMusic)
        isPlaying = payload["playing"] as? Bool ?? false
    }

    /// The adapter ships inside NotchPal.app; `swift run` uses the copy built in the project folder.
    private static func adapterPaths() -> (script: URL, framework: URL)? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL, let fw = Bundle.main.privateFrameworksURL {
            let script = res.appendingPathComponent("mediaremote-adapter.pl")
            let framework = fw.appendingPathComponent("MediaRemoteAdapter.framework")
            if fm.fileExists(atPath: script.path), fm.fileExists(atPath: framework.path) {
                return (script, framework)
            }
        }
        // Development fallback: <project>/Vendor/... and <project>/build/.work/...
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = root.appendingPathComponent("Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl")
        let framework = root.appendingPathComponent("build/.work/MediaRemoteAdapter.framework")
        if fm.fileExists(atPath: script.path), fm.fileExists(atPath: framework.path) {
            return (script, framework)
        }
        return nil
    }
}

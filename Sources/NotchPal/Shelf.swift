import AppKit

// MARK: - File shelf
// Holds up to 20 files as bookmarks to the originals: never copies, so no extra disk space.
// Bookmarks follow a file when it's moved or renamed; if it's deleted, the item shows "missing".

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var bookmark: Data
    var name: String
    var path: String
    var added: Date
}

@MainActor
final class ShelfStore: ObservableObject {
    static let limit = 20

    /// Newest first.
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var missing: Set<ShelfItem.ID> = []

    private static let file = "shelf.json"
    private var iconCache: [String: NSImage] = [:]

    init() {
        items = AppFiles.read(Self.file).flatMap { try? JSONDecoder().decode([ShelfItem].self, from: $0) } ?? []
        refresh()
    }

    /// Adds files (newest first). Returns how many old items were pushed off the end.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        for url in urls {
            let path = url.resolvingSymlinksInPath().path   // /tmp and /private/tmp are the same file
            items.removeAll { $0.path == path }   // dropped again: move to the front
            guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil,
                                                        relativeTo: nil) else { continue }
            items.insert(ShelfItem(bookmark: bookmark, name: url.lastPathComponent, path: path, added: Date()), at: 0)
        }
        let overflow = max(0, items.count - Self.limit)
        if overflow > 0 { items.removeLast(overflow) }
        save()
        refresh()
        return overflow
    }

    func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
        save()
        let paths = Set(items.map(\.path))
        iconCache = iconCache.filter { paths.contains($0.key) }
    }

    func clear() {
        items.removeAll()
        missing.removeAll()
        iconCache.removeAll()
        save()
    }

    /// Where the file is now (following moves), or nil if it's gone.
    func url(for item: ShelfItem) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Re-checks every item (moved files get their new name and path).
    func refresh() {
        var gone: Set<ShelfItem.ID> = []
        var changed = false
        for i in items.indices {
            guard let url = url(for: items[i]) else {
                gone.insert(items[i].id)
                continue
            }
            let path = url.resolvingSymlinksInPath().path
            if path != items[i].path {
                items[i].path = path
                items[i].name = url.lastPathComponent
                if let fresh = try? url.bookmarkData() { items[i].bookmark = fresh }
                changed = true
            }
        }
        missing = gone
        if changed { save() }
        let paths = Set(items.map(\.path))
        iconCache = iconCache.filter { paths.contains($0.key) }
    }

    func icon(for item: ShelfItem) -> NSImage {
        if let cached = iconCache[item.path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: item.path)
        iconCache[item.path] = icon
        return icon
    }

    // MARK: Right-click actions

    func open(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ item: ShelfItem) {
        let path = url(for: item)?.path ?? item.path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { AppFiles.write(data, to: Self.file) }
    }
}

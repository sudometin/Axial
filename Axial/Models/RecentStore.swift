import Foundation
import Observation

struct RecentItem: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let isFolder: Bool
    let bookmark: Data
    let date: Date
}

/// Recently opened files and folders, stored as security-scoped bookmarks so the sandboxed
/// app can reopen them after a relaunch.
@MainActor
@Observable
final class RecentStore {
    private(set) var items: [RecentItem] = []
    private let defaultsKey = "AxialRecentItems"
    private let limit = 8

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) {
            items = decoded
        }
    }

    func add(_ urls: [URL]) {
        for url in urls {
            guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { continue }
            items.removeAll { $0.path == url.path }
            items.insert(RecentItem(
                path: url.path,
                name: url.lastPathComponent,
                isFolder: FileEnumerator.isDirectory(url),
                bookmark: bookmark,
                date: Date()
            ), at: 0)
        }
        if items.count > limit { items = Array(items.prefix(limit)) }
        save()
    }

    /// Resolves a bookmark and starts security-scoped access (kept for the rest of the session).
    func resolve(_ item: RecentItem) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            remove(item)
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        if stale { add([url]) }
        return url
    }

    func remove(_ item: RecentItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

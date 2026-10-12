import Foundation

// MARK: - The drop's inbox (0.3.6)
// A file dropped on the island is copied into ~/Library/Application Support/NotchBuddy/inbox, so the
// chat and the mail draft keep it when the original moves. Before 0.3.6 every drop was copied whole,
// whatever its size, and nothing ever removed a copy: the folder only grew. Now a copy goes after
// 24 h (at launch and at each drop), and a file over 200 MB, or anything that is not a plain file
// (a folder, a package), is not copied: the island uses the original where it is.
// Foundation only, tested by scripts/test-drop-inbox.sh; FileDropHandler and AppDelegate call it.

enum DropInbox {
    /// A copy older than this is removed.
    static let maxAge: TimeInterval = 24 * 60 * 60
    /// The largest file copied, 200 MB (in the binary units of the chat's own limits).
    static let maxCopyBytes: Int64 = 200 * 1024 * 1024

    // MARK: Rules

    /// Whether a dropped item is copied into the inbox: a plain file of known size, 200 MB at most.
    static func shouldCopy(isRegularFile: Bool, size: Int64?) -> Bool {
        guard isRegularFile, let size, size >= 0 else { return false }
        return size <= maxCopyBytes
    }

    /// The names of the copies to remove at `now`: those dated more than `maxAge` before it, except
    /// the ones in `keep` (the file the chat holds). A copy whose date could not be read stays.
    static func expired(_ files: [(name: String, date: Date?)], now: Date, keep: Set<String> = []) -> [String] {
        files.compactMap { file in
            guard !keep.contains(file.name), let date = file.date else { return nil }
            return now.timeIntervalSince(date) > maxAge ? file.name : nil
        }
    }

    // MARK: Files (never on the main thread: callers run them in a detached task)

    /// Whether the item at `url` is copied (`shouldCopy`), from what the file system says of it.
    static func shouldCopy(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        return shouldCopy(isRegularFile: values?.isRegularFile ?? false,
                          size: values?.fileSize.map { Int64($0) })
    }

    /// Removes the copies in `directory` older than `maxAge` at `now`, except `keep`. What cannot be
    /// read or removed stays; a missing folder is nothing to do.
    static func removeExpired(in directory: URL, now: Date = Date(), keep: Set<String> = []) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let files = names.map { name -> (name: String, date: Date?) in
            let attributes = try? fm.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            return (name, attributes?[.modificationDate] as? Date)
        }
        for name in expired(files, now: now, keep: keep) {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Dates a fresh copy from its drop: a copy keeps the original's modification date, which may
    /// be months old, and would otherwise go at the next clean-up.
    static func markCopied(_ copy: URL, at now: Date = Date()) {
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: copy.path)
    }
}

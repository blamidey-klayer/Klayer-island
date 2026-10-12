import Foundation

/// The drop's inbox (DropInbox, 0.3.6): a copy goes after 24 h, at launch and at each drop, except
/// the file the chat holds; a file over 200 MB, or anything that is not a plain file, is never
/// copied (the island uses the original). The rules are pure; the clean-up runs here on a real
/// temporary folder.
@main
enum DropInboxTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("a_plain_file_up_to_200_mb_is_copied", aPlainFileUpTo200MBIsCopied),
            ("a_larger_file_a_folder_or_an_unknown_size_is_not", aLargerFileAFolderOrAnUnknownSizeIsNot),
            ("copies_older_than_24_hours_go", copiesOlderThan24HoursGo),
            ("the_file_the_chat_holds_stays", theFileTheChatHoldsStays),
            ("a_copy_without_a_date_stays", aCopyWithoutADateStays),
            ("the_clean_up_removes_only_old_copies_on_disk", theCleanUpRemovesOnlyOldCopiesOnDisk),
            ("a_fresh_copy_is_dated_from_its_drop", aFreshCopyIsDatedFromItsDrop),
            ("a_missing_folder_is_nothing_to_do", aMissingFolderIsNothingToDo),
            ("the_size_rule_reads_the_file_system", theSizeRuleReadsTheFileSystem),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Drop inbox: \(cases.count) cases passed")
    }

    static let mb: Int64 = 1024 * 1024
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let hour: TimeInterval = 3600

    // MARK: - What is copied

    static func aPlainFileUpTo200MBIsCopied() {
        precondition(DropInbox.maxCopyBytes == 200 * mb, "200 MB, in the chat's binary units")
        precondition(DropInbox.shouldCopy(isRegularFile: true, size: 0), "an empty file")
        precondition(DropInbox.shouldCopy(isRegularFile: true, size: 5 * mb), "an image")
        precondition(DropInbox.shouldCopy(isRegularFile: true, size: 200 * mb), "200 MB exactly")
    }

    static func aLargerFileAFolderOrAnUnknownSizeIsNot() {
        precondition(!DropInbox.shouldCopy(isRegularFile: true, size: 200 * mb + 1), "one byte over")
        precondition(!DropInbox.shouldCopy(isRegularFile: true, size: 8 * 1024 * mb), "a film")
        precondition(!DropInbox.shouldCopy(isRegularFile: false, size: 4096), "a folder or a package")
        precondition(!DropInbox.shouldCopy(isRegularFile: true, size: nil), "a size the system did not give")
        precondition(!DropInbox.shouldCopy(isRegularFile: true, size: -1), "a size that makes no sense")
    }

    // MARK: - What goes

    static func copiesOlderThan24HoursGo() {
        precondition(DropInbox.maxAge == 24 * hour, "24 h")
        let files: [(name: String, date: Date?)] = [
            ("hier.pdf", now.addingTimeInterval(-25 * hour)),
            ("semaine.png", now.addingTimeInterval(-7 * 24 * hour)),
            ("matin.txt", now.addingTimeInterval(-3 * hour)),
            ("juste.txt", now.addingTimeInterval(-24 * hour)),
        ]
        precondition(DropInbox.expired(files, now: now) == ["hier.pdf", "semaine.png"],
                     "only past 24 h, 24 h exactly stays: \(DropInbox.expired(files, now: now))")
    }

    static func theFileTheChatHoldsStays() {
        let files: [(name: String, date: Date?)] = [
            ("tenu.pdf", now.addingTimeInterval(-48 * hour)),
            ("libre.pdf", now.addingTimeInterval(-48 * hour)),
        ]
        precondition(DropInbox.expired(files, now: now, keep: ["tenu.pdf"]) == ["libre.pdf"], "kept by the chat")
    }

    static func aCopyWithoutADateStays() {
        precondition(DropInbox.expired([("inconnu", nil)], now: now).isEmpty, "no date, no removal")
    }

    // MARK: - On disk

    static func tempFolder() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("klayer-drop-inbox-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(_ name: String, in dir: URL, dated date: Date) {
        let url = dir.appendingPathComponent(name)
        try! Data("x".utf8).write(to: url)
        try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    static func names(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    static func theCleanUpRemovesOnlyOldCopiesOnDisk() {
        let dir = tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = Date()
        write("vieux.pdf", in: dir, dated: clock.addingTimeInterval(-30 * hour))
        write("tenu.txt", in: dir, dated: clock.addingTimeInterval(-30 * hour))
        write("recent.png", in: dir, dated: clock.addingTimeInterval(-1 * hour))
        // A folder copied by a build before 0.3.6, as old: it goes whole.
        let folder = dir.appendingPathComponent("dossier")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        write("dedans.txt", in: folder, dated: clock)
        try! FileManager.default.setAttributes([.modificationDate: clock.addingTimeInterval(-40 * hour)],
                                               ofItemAtPath: folder.path)
        DropInbox.removeExpired(in: dir, now: clock, keep: ["tenu.txt"])
        precondition(names(in: dir) == ["recent.png", "tenu.txt"], "left: \(names(in: dir))")
    }

    /// A copy keeps its original's date: the drop dates it, or it would go at the next clean-up.
    static func aFreshCopyIsDatedFromItsDrop() {
        let dir = tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = Date()
        write("ancien.pdf", in: dir, dated: clock.addingTimeInterval(-90 * 24 * hour))
        DropInbox.markCopied(dir.appendingPathComponent("ancien.pdf"), at: clock)
        DropInbox.removeExpired(in: dir, now: clock.addingTimeInterval(23 * hour))
        precondition(names(in: dir) == ["ancien.pdf"], "dated from its drop, it stays 24 h")
        DropInbox.removeExpired(in: dir, now: clock.addingTimeInterval(25 * hour))
        precondition(names(in: dir).isEmpty, "then it goes")
    }

    static func aMissingFolderIsNothingToDo() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("klayer-absent-\(UUID().uuidString)")
        DropInbox.removeExpired(in: dir)
        precondition(!FileManager.default.fileExists(atPath: dir.path), "nothing created, nothing thrown")
    }

    static func theSizeRuleReadsTheFileSystem() {
        let dir = tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        write("petit.txt", in: dir, dated: Date())
        precondition(DropInbox.shouldCopy(dir.appendingPathComponent("petit.txt")), "a small plain file is copied")
        precondition(!DropInbox.shouldCopy(dir), "a folder is not")
        precondition(!DropInbox.shouldCopy(dir.appendingPathComponent("absent.txt")), "nothing there, nothing copied")
        // A sparse file of 201 MB takes no room: the rule reads its size, not the disk.
        let big = dir.appendingPathComponent("gros.bin")
        precondition(FileManager.default.createFile(atPath: big.path, contents: nil), "the big file is created")
        let handle = try! FileHandle(forWritingTo: big)
        try! handle.truncate(atOffset: UInt64(201 * mb))
        try! handle.close()
        precondition(!DropInbox.shouldCopy(big), "over 200 MB: the original is used")
    }
}

import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// The diagnostic log (AppLog.swift): one line appended per call, created at mode 0600. 0.3.6, B4: a
/// write that fails (a full disk) no longer raises: the legacy FileHandle API (`seekToEndOfFile`,
/// `write(_:)`) raised an Objective-C exception on a write error, from the main actor, at the next
/// logged hook. A full disk is played here with the file size limit (RLIMIT_FSIZE, SIGXFSZ ignored):
/// any write past it fails with EFBIG, as a full disk fails with ENOSPC.
@main
enum AppLogTests {
    static let fileName = "applog-test-\(getpid()).log"

    /// Where AppLog writes: ~/Library/Logs/NotchBuddy (Linux has no Library folder: the home's).
    static var logFile: URL {
        (FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"))
            .appendingPathComponent("Logs/NotchBuddy").appendingPathComponent(fileName)
    }

    static func main() {
        defer { try? FileManager.default.removeItem(at: logFile) }
        try? FileManager.default.removeItem(at: logFile)

        appendAppLog(fileName, "Stop [agent_claude-desktop] (abcd1234): shown")
        let first = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        precondition(first.hasSuffix(" Stop [agent_claude-desktop] (abcd1234): shown\n"), "one line: « \(first) »")
        appendAppLog(fileName, "SessionEnd [integration_claude] (ef567890)")
        let second = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        precondition(second.hasPrefix(first) && second.split(separator: "\n").count == 2, "appended: « \(second) »")
        print("  ok  a_line_is_appended")

        appendAppLog(fileName, "escape \u{1B}[31m")
        let escaped = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        precondition(escaped.hasSuffix("escape \\u001B[31m\n"), "control characters escaped: « \(escaped) »")
        print("  ok  control_characters_are_escaped")

        // The disk is full: nothing more can be written to the file. The append fails silently.
        let size = (try? FileManager.default.attributesOfItem(atPath: logFile.path)[.size] as? Int) ?? 0
        #if canImport(Glibc)
        let fileSize = Int32(RLIMIT_FSIZE.rawValue)
        #else
        let fileSize = RLIMIT_FSIZE
        #endif
        signal(SIGXFSZ, SIG_IGN)
        var limit = rlimit()
        getrlimit(fileSize, &limit)
        var full = limit
        full.rlim_cur = rlim_t(size)
        precondition(setrlimit(fileSize, &full) == 0, "the file size limit could not be set")
        appendAppLog(fileName, "PreToolUse Bash")
        appendAppLog(fileName, "Notification permission_prompt [claude-desktop] (abcd1234): asks permission")
        setrlimit(fileSize, &limit)
        let after = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        precondition(after == escaped, "nothing written past the limit, the file intact")
        print("  ok  a_full_disk_does_not_raise")

        // Room again: the next line is appended.
        appendAppLog(fileName, "Stop [integration_claude] (12345678): shown")
        let resumed = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        precondition(resumed.hasPrefix(escaped) && resumed.hasSuffix("(12345678): shown\n"), "« \(resumed) »")
        print("  ok  the_log_resumes_once_there_is_room")
        print("App log: 4 cases passed")
    }
}

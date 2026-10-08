import Foundation

@main
enum ClaudeSettingsFileTests {
    static var fm: FileManager { .default }

    static func failure(_ body: () throws -> Void) -> ClaudeSettingsFile.Failure? {
        do { try body() } catch let error as ClaudeSettingsFile.Failure { return error } catch { return nil }
        return nil
    }

    static func contents(_ url: URL?) -> Data? {
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    static func backups(in dir: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("settings.json.bak-") }
    }

    static func mode(_ url: URL) -> Int {
        ((try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    static func setMode(_ value: Int, _ url: URL) throws {
        try fm.setAttributes([.posixPermissions: NSNumber(value: value)], ofItemAtPath: url.path)
    }

    static func main() throws {
        let dir = fm.temporaryDirectory
            .appendingPathComponent("klayer-settings-\(ProcessInfo.processInfo.processIdentifier)")
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        let name = "settings.json"

        // Absent file: start from nothing, with no bytes to compare against.
        let absent = try ClaudeSettingsFile.read(at: url)
        precondition(absent.object.isEmpty && absent.bytes == nil)

        // Empty and whitespace-only files are an empty object too.
        try Data(" \n\t".utf8).write(to: url)
        let blank = try ClaudeSettingsFile.read(at: url)
        precondition(blank.object.isEmpty && blank.bytes != nil)

        // This is the whole bug: content we cannot use came back as an empty
        // object, and the install then wrote nothing but Klayer Island's hooks over it.
        for bad in ["{ not json", "[1,2,3]", "\"a string\""] {
            try Data(bad.utf8).write(to: url)
            let refused = failure { _ = try ClaudeSettingsFile.read(at: url) }
            precondition(refused == .invalid(name), "unusable content must refuse, not come back empty: \(bad)")
            precondition(contents(url) == Data(bad.utf8), "a refused file must stay as it was")
        }

        // A valid file reads back whole.
        let original = Data(#"{"model":"opus","hooks":{"PreToolUse":[{"hooks":[{"command":"other-tool"}]}]}}"#.utf8)
        try original.write(to: url)
        let snapshot = try ClaudeSettingsFile.read(at: url)
        precondition(snapshot.object["model"] as? String == "opus")
        precondition(snapshot.bytes == original)

        // No "hooks" at all: start from nothing, as before.
        let noHooks = try ClaudeSettingsFile.hooks(in: ["model": "opus"], name: name)
        precondition(noHooks.isEmpty)
        let noGroups = try ClaudeSettingsFile.hookGroups(in: [:], event: "PreToolUse", name: name)
        precondition(noGroups.isEmpty)

        // The usual shape comes back as it is, other tools' hooks included.
        let hooks = try ClaudeSettingsFile.hooks(in: snapshot.object, name: name)
        let groups = try ClaudeSettingsFile.hookGroups(in: hooks, event: "PreToolUse", name: name)
        precondition(groups.count == 1)
        let emptyList = try ClaudeSettingsFile.hookGroups(in: ["Stop": [Any]()], event: "Stop", name: name)
        precondition(emptyList.isEmpty)

        // "hooks" in a shape we do not know used to be replaced by an empty
        // object and written back. It is refused, and the file stays as it was.
        for bad in [#"{"model":"opus","hooks":[1,2]}"#, #"{"hooks":"off"}"#, #"{"hooks":null}"#] {
            try Data(bad.utf8).write(to: url)
            let parsed = try ClaudeSettingsFile.read(at: url)
            let refused = failure { _ = try ClaudeSettingsFile.hooks(in: parsed.object, name: name) }
            precondition(refused == .unexpectedHooks(name), "an unknown \"hooks\" must refuse: \(bad)")
            precondition(contents(url) == Data(bad.utf8))
        }
        for bad in [#"{"hooks":{"PreToolUse":"x"}}"#, #"{"hooks":{"PreToolUse":[1]}}"#, #"{"hooks":{"PreToolUse":{}}}"#] {
            try Data(bad.utf8).write(to: url)
            let parsed = try ClaudeSettingsFile.read(at: url)
            let hooks = try ClaudeSettingsFile.hooks(in: parsed.object, name: name)
            let refused = failure { _ = try ClaudeSettingsFile.hookGroups(in: hooks, event: "PreToolUse", name: name) }
            precondition(refused == .unexpectedHooks(name), "an unknown event shape must refuse: \(bad)")
            precondition(contents(url) == Data(bad.utf8))
        }
        precondition(backups(in: dir).isEmpty)

        // A file edited after the preview is refused: nothing written, no backup.
        let edited = Data(#"{"model":"someone-else-edited-this"}"#.utf8)
        try edited.write(to: url)
        let next = Data(#"{"model":"opus","hooks":{}}"#.utf8)
        let stale = failure { _ = try ClaudeSettingsFile.write(next, to: url, expecting: snapshot.bytes) }
        precondition(stale == .changed(name))
        precondition(contents(url) == edited)
        precondition(backups(in: dir).isEmpty)

        // A file that appeared after a preview of "no file" is refused as well.
        let appeared = failure { _ = try ClaudeSettingsFile.write(next, to: url, expecting: nil) }
        precondition(appeared == .changed(name))
        precondition(contents(url) == edited)

        // The matching write backs up the exact bytes, then replaces the file.
        try setMode(0o600, url)
        let backup = try ClaudeSettingsFile.write(next, to: url, expecting: edited)
        precondition(backup != nil)
        precondition(contents(backup) == edited)
        precondition(contents(url) == next)
        precondition(mode(url) == 0o600, "a rewrite must not widen the file's permissions")

        // Two writes in the same second keep two backups.
        let third = Data(#"{"model":"sonnet"}"#.utf8)
        let secondBackup = try ClaudeSettingsFile.write(third, to: url, expecting: next)
        precondition(secondBackup != nil && secondBackup != backup)
        precondition(contents(backup) == edited)
        precondition(contents(secondBackup) == next)
        precondition(backups(in: dir).count == 2)

        // Wider permissions the user chose are kept as they were.
        try setMode(0o644, url)
        _ = try ClaudeSettingsFile.write(next, to: url, expecting: third)
        precondition(mode(url) == 0o644)

        // No leftover temporary file beside the settings.
        let leftovers = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".klayer-") }
        precondition(leftovers.isEmpty)

        // No file at all: created in a missing folder, ours only, nothing to back up.
        let fresh = dir.appendingPathComponent("new/settings.json")
        let freshBackup = try ClaudeSettingsFile.write(next, to: fresh, expecting: nil)
        precondition(freshBackup == nil)
        precondition(contents(fresh) == next)
        precondition(mode(fresh) == 0o600)

        // A symlinked settings.json stays a link; the file it points at is rewritten.
        let real = dir.appendingPathComponent("dotfiles-settings.json")
        try original.write(to: real)
        let linkDir = dir.appendingPathComponent("linked")
        try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let link = linkDir.appendingPathComponent("settings.json")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        let linkBackup = try ClaudeSettingsFile.write(next, to: link, expecting: original)
        let stillALink = (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil
        precondition(stillALink, "the link was replaced by a file")
        precondition(contents(real) == next)
        precondition(contents(linkBackup) == original)

        try hooksMerge()

        print("Claude settings file: all checks passed")
    }

    // MARK: - Klayer Island's hooks in the "hooks" block

    static func object(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    static func commands(_ hooks: [String: Any], _ event: String) -> [String] {
        ((hooks[event] as? [[String: Any]]) ?? []).flatMap { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
        }
    }

    static func hooksMerge() throws {
        let name = "settings.json"
        let ours = KlayerHookCommand(scriptPath: "/Users/me/Library/Application Support/NotchBuddy/nb-hook",
                                     home: "/Users/me")
        // The user's own hooks, one of them under a path that says "klayer", one sharing a group
        // with an entry an earlier Klayer Island wrote, an empty group of their own, an event
        // shape we do not know, and the old 110 s permission hook.
        let before = try ClaudeSettingsFile.hooks(in: object(#"""
        {"hooks":{
          "SessionStart":[
            {"hooks":[{"type":"command","command":"$HOME/tools/klayer-lint.sh"}]},
            {"matcher":"startup","hooks":[
              {"type":"command","command":"/bin/sh \"/Users/me/.claude/klayer/nb-hook\""},
              {"type":"command","command":"~/bin/log-session.sh"}]}],
          "Stop":[{"hooks":[]}],
          "PermissionRequest":[{"hooks":[
            {"type":"command","command":"\"/Users/me/Library/Application Support/NotchBuddy/nb-hook\"","timeout":110}]}],
          "PreCompact":[{"hooks":[{"type":"command","command":"$HOME/.claude/klayer/nb-hook"}]}],
          "CustomEvent":"left as it is"}}
        """#), name: name)

        // Uninstall: only our entries go; a group goes only once it is empty, an event too.
        let removed = try ClaudeSettingsFile.replacingHooks(in: before, with: [], where: ours.isOurs, name: name)
        precondition(commands(removed, "SessionStart") == ["$HOME/tools/klayer-lint.sh", "~/bin/log-session.sh"],
                     "the user's hooks, and only theirs, stay: \(commands(removed, "SessionStart"))")
        let startGroups = removed["SessionStart"] as? [[String: Any]] ?? []
        precondition(startGroups.count == 2 && startGroups[1]["matcher"] as? String == "startup",
                     "a group that still has the user's hook keeps its matcher")
        precondition(removed["PermissionRequest"] == nil && removed["PreCompact"] == nil,
                     "an event left with no group is dropped")
        precondition((removed["Stop"] as? [[String: Any]])?.count == 1, "a group that was already empty is the user's")
        precondition(removed["CustomEvent"] as? String == "left as it is", "an unknown shape is left as it is")

        // The preview of the uninstall lists our three entries, removed, and nothing else.
        let uninstallDiff = ClaudeSettingsFile.hooksDiff(before: before, after: removed)
        precondition(uninstallDiff.added.isEmpty && uninstallDiff.removed.count == 3, "\(uninstallDiff.text)")
        precondition(!uninstallDiff.text.contains("klayer-lint") && !uninstallDiff.text.contains("log-session"),
                     "the user's hooks never show in the diff")
        precondition(uninstallDiff.text.split(separator: "\n").allSatisfy { $0.hasPrefix("- ") })
        precondition(uninstallDiff.text.contains(#"- PermissionRequest  {"command":"\"/Users/me/Library/Application Support/NotchBuddy/nb-hook\"","timeout":110,"type":"command"}"#),
                     "an entry reads as its event and its hook, slashes unescaped: \(uninstallDiff.text)")
        precondition(uninstallDiff.text.contains(#"- SessionStart [startup]  {"command":"/bin/sh \"/Users/me/.claude/klayer/nb-hook\"","type":"command"}"#),
                     "a matcher shows in brackets: \(uninstallDiff.text)")

        // Install: our entries are replaced by today's, the user's hooks stay where they were.
        let installed = try ClaudeSettingsFile.replacingHooks(in: before, with: ours.installGroups,
                                                              where: ours.isOurs, name: name)
        precondition(commands(installed, "SessionStart") == ["$HOME/tools/klayer-lint.sh", "~/bin/log-session.sh", ours.written])
        precondition(commands(installed, "PreToolUse") == [ours.written, ours.written + " --ask"])
        precondition(installed["PreCompact"] == nil, "an entry of an earlier build in an event we no longer use goes")
        precondition(installed["CustomEvent"] as? String == "left as it is")
        let installDiff = ClaudeSettingsFile.hooksDiff(before: before, after: installed)
        precondition(installDiff.removed.count == 3)
        precondition(installDiff.added.count == ours.installGroups.count, "\(installDiff.text)")
        precondition(installDiff.text.contains(#"+ PermissionRequest  {"command":"\"/Users/me/Library/Application Support/NotchBuddy/nb-hook\"","timeout":120,"type":"command"}"#))
        precondition(installDiff.text.contains(#"+ PreToolUse [AskUserQuestion]  {"command":"\"/Users/me/Library/Application Support/NotchBuddy/nb-hook\" --ask","timeout":130,"type":"command"}"#))
        precondition(!installDiff.text.contains("klayer-lint") && !installDiff.text.contains("log-session"))
        // Removed lines of an event come before its added lines, events in alphabetical order.
        let lines = installDiff.text.split(separator: "\n").map(String.init)
        let permissionLines = lines.filter { $0.dropFirst(2).hasPrefix("PermissionRequest ") }
        precondition(permissionLines.count == 2 && permissionLines[0].hasPrefix("- ") && permissionLines[1].hasPrefix("+ "))
        let events = lines.map { String($0.dropFirst(2).prefix { $0 != " " }) }
        precondition(events == events.sorted(), "events in order: \(events)")

        // Installing again changes nothing: the diff is empty and there is nothing to confirm.
        let again = try ClaudeSettingsFile.replacingHooks(in: installed, with: ours.installGroups,
                                                          where: ours.isOurs, name: name)
        let againDiff = ClaudeSettingsFile.hooksDiff(before: installed, after: again)
        precondition(againDiff.isEmpty && againDiff.text.isEmpty, "\(againDiff.text)")

        // Nothing of ours to remove: an empty diff too.
        let clean = ClaudeSettingsFile.hooksDiff(before: removed, after: try ClaudeSettingsFile.replacingHooks(
            in: removed, with: [], where: ours.isOurs, name: name))
        precondition(clean.isEmpty)

        // An event of ours in a shape we do not know is refused on install, never replaced.
        let odd = object(#"{"hooks":{"Stop":"x"}}"#)["hooks"] as? [String: Any] ?? [:]
        var refused: ClaudeSettingsFile.Failure? = nil
        do { _ = try ClaudeSettingsFile.replacingHooks(in: odd, with: ours.installGroups, where: ours.isOurs, name: name) }
        catch let error as ClaudeSettingsFile.Failure { refused = error }
        precondition(refused == .unexpectedHooks(name))
        // ...and kept as it is on uninstall.
        let oddRemoved = try ClaudeSettingsFile.replacingHooks(in: odd, with: [], where: ours.isOurs, name: name)
        precondition(oddRemoved["Stop"] as? String == "x")
    }
}

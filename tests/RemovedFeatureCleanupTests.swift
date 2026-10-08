import Foundation

/// What features removed in 0.1.0 left on the Mac goes once, at launch: their secrets in the
/// Keychain, the weekly recap's history file, their preferences. Never what the app still uses.
/// Tests use a throwaway defaults suite and a temporary folder, never the real ones.
@main
enum RemovedFeatureCleanupTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("removes_what_removed_features_left", removesWhatRemovedFeaturesLeft),
            ("runs_once_per_version", runsOncePerVersion),
            ("never_touches_what_the_app_still_uses", neverTouchesWhatTheAppStillUses),
            ("nothing_to_remove_is_fine", nothingToRemoveIsFine),
        ]
        for (name, run) in cases {
            run()
            print("  ok  \(name)")
        }
        print("Removed feature cleanup: \(cases.count) cases passed")
    }

    /// A fresh defaults suite and support folder, removed afterwards.
    static func sandbox(_ body: (UserDefaults, URL) -> Void) {
        let name = "klayer-cleanup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: dir)
        }
        body(defaults, dir)
    }

    static func removesWhatRemovedFeaturesLeft() {
        sandbox { defaults, dir in
            for key in RemovedFeatureCleanup.defaultsKeys { defaults.set("old", forKey: key) }
            defaults.set(15.0, forKey: "autoCloseInterval")
            let recap = dir.appendingPathComponent("recap.json")
            let choices = dir.appendingPathComponent("choices.json")
            precondition(FileManager.default.createFile(atPath: recap.path, contents: Data("[]".utf8)))
            precondition(FileManager.default.createFile(atPath: choices.path, contents: Data("[]".utf8)))
            var deleted: [String] = []

            let ran = RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: dir) { deleted.append($0) }

            precondition(ran)
            precondition(deleted == RemovedFeatureCleanup.keychainAccounts, "every removed secret is deleted: \(deleted)")
            for key in RemovedFeatureCleanup.defaultsKeys {
                precondition(defaults.object(forKey: key) == nil, "\(key) is still there")
            }
            precondition(!FileManager.default.fileExists(atPath: recap.path), "recap.json is still there")
            precondition(FileManager.default.fileExists(atPath: choices.path), "choices.json is the app's own")
            precondition(defaults.double(forKey: "autoCloseInterval") == 15, "a setting in use stays")
            precondition(defaults.integer(forKey: RemovedFeatureCleanup.versionKey) == RemovedFeatureCleanup.version)
        }
    }

    static func runsOncePerVersion() {
        sandbox { defaults, dir in
            _ = RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: dir) { _ in }
            // Whatever appears later under these names is not touched again by this version.
            defaults.set(true, forKey: "openOnHover")
            let recap = dir.appendingPathComponent("recap.json")
            precondition(FileManager.default.createFile(atPath: recap.path, contents: Data("[]".utf8)))
            var deleted: [String] = []
            let ran = RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: dir) { deleted.append($0) }
            precondition(!ran && deleted.isEmpty, "the cleanup ran twice")
            precondition(defaults.bool(forKey: "openOnHover"))
            precondition(FileManager.default.fileExists(atPath: recap.path))
            // A stored version older than this one runs it again.
            defaults.set(RemovedFeatureCleanup.version - 1, forKey: RemovedFeatureCleanup.versionKey)
            precondition(RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: dir) { _ in })
            precondition(defaults.object(forKey: "openOnHover") == nil)
        }
    }

    static func neverTouchesWhatTheAppStillUses() {
        for account in ["anthropic-api-key", "github-token"] {
            precondition(!RemovedFeatureCleanup.keychainAccounts.contains(account), "\(account) is in use")
        }
        for key in ["autoCloseInterval", "claudeModel", "mainPill", "activeIntegrations", "soundEnabled",
                    "soundVolume", "greetThreshold", "hotkeyEnabled", "hotkeyFlags", "hotkeyCode",
                    "islandDisplay", "claudePlanUsage", "showPlanInNotch", "settingsSection",
                    "klayOnDesktop", "desktopKlayX", "desktopKlayY", "klayer.spotifyAutomationGranted"] {
            precondition(!RemovedFeatureCleanup.defaultsKeys.contains(key), "\(key) is in use")
        }
        precondition(!RemovedFeatureCleanup.supportFiles.contains("choices.json"))
        precondition(!RemovedFeatureCleanup.supportFiles.contains("nb-hook"))
        precondition(Set(RemovedFeatureCleanup.supportFiles).isSubset(of: ["recap.json"]))
    }

    static func nothingToRemoveIsFine() {
        sandbox { defaults, dir in
            let missing = dir.appendingPathComponent("not-created")
            precondition(RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: missing) { _ in })
            precondition(defaults.integer(forKey: RemovedFeatureCleanup.versionKey) == RemovedFeatureCleanup.version)
        }
    }
}

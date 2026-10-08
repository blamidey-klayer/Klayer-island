import Foundation

/// What removed features left on the Mac goes once, at launch, one versioned step at a time:
/// their secrets in the Keychain, the weekly recap's history file, their preferences. A step
/// never runs twice, and never touches what the app still uses. Tests use a throwaway defaults
/// suite and a temporary folder, never the real ones.
@main
enum RemovedFeatureCleanupTests {
    static func main() {
        let cases: [(String, () -> Void)] = [
            ("removes_what_removed_features_left", removesWhatRemovedFeaturesLeft),
            ("runs_once_per_version", runsOncePerVersion),
            ("the_api_key_chat_goes_in_step_2", theAPIKeyChatGoesInStep2),
            ("a_mac_cleaned_by_step_1_runs_only_step_2", aMacCleanedByStep1RunsOnlyStep2),
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
            for key in allDefaultsKeys { defaults.set("old", forKey: key) }
            defaults.set(15.0, forKey: "autoCloseInterval")
            let recap = dir.appendingPathComponent("recap.json")
            let choices = dir.appendingPathComponent("choices.json")
            precondition(FileManager.default.createFile(atPath: recap.path, contents: Data("[]".utf8)))
            precondition(FileManager.default.createFile(atPath: choices.path, contents: Data("[]".utf8)))
            var deleted: [String] = []

            let ran = RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: dir) { deleted.append($0) }

            precondition(ran)
            precondition(deleted == allKeychainAccounts, "every removed secret is deleted, step by step: \(deleted)")
            for key in allDefaultsKeys {
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
            // A stored version older than the first step's runs every step again.
            defaults.set(0, forKey: RemovedFeatureCleanup.versionKey)
            precondition(RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: dir) { _ in })
            precondition(defaults.object(forKey: "openOnHover") == nil)
            precondition(defaults.integer(forKey: RemovedFeatureCleanup.versionKey) == RemovedFeatureCleanup.version)
        }
    }

    static func neverTouchesWhatTheAppStillUses() {
        for account in ["github-token"] {
            precondition(!allKeychainAccounts.contains(account), "\(account) is in use")
        }
        for key in ["autoCloseInterval", "mainPill", "activeIntegrations", "soundEnabled",
                    "soundVolume", "greetThreshold", "hotkeyEnabled", "hotkeyFlags", "hotkeyCode",
                    "islandDisplay", "claudePlanUsage", "showPlanInNotch", "settingsSection",
                    "klayOnDesktop", "desktopKlayX", "desktopKlayY", "klayer.spotifyAutomationGranted"] {
            precondition(!allDefaultsKeys.contains(key), "\(key) is in use")
        }
        let files = RemovedFeatureCleanup.steps.flatMap(\.supportFiles)
        precondition(!files.contains("choices.json"))
        precondition(!files.contains("nb-hook"))
        precondition(Set(files).isSubset(of: ["recap.json"]))
    }

    static func nothingToRemoveIsFine() {
        sandbox { defaults, dir in
            let missing = dir.appendingPathComponent("not-created")
            precondition(RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: missing) { _ in })
            precondition(defaults.integer(forKey: RemovedFeatureCleanup.versionKey) == RemovedFeatureCleanup.version)
        }
    }

    /// Every step's lists, in step order.
    static var allKeychainAccounts: [String] { RemovedFeatureCleanup.steps.flatMap(\.keychainAccounts) }
    static var allDefaultsKeys: [String] { RemovedFeatureCleanup.steps.flatMap(\.defaultsKeys) }

    static func theAPIKeyChatGoesInStep2() {
        // Step 1 is the 0.1.0 cleanup as it shipped: unchanged, so a Mac it ran on is not
        // cleaned again by it.
        precondition(RemovedFeatureCleanup.steps.map(\.version) == [1, 2], "steps are numbered 1, 2")
        precondition(RemovedFeatureCleanup.version == 2, "the stored version is the last step's")
        let first = RemovedFeatureCleanup.steps[0]
        precondition(first.keychainAccounts == [
            "google-api-key", "openai-api-key",
            "resend-api-key", "resend-from",
            "n8n-url", "n8n-api-key",
            "vercel-token", "stripe-api-key", "calcom-api-key", "notion-api-key",
        ])
        precondition(first.supportFiles == ["recap.json"])
        precondition(first.defaultsKeys == [
            "recapEnabled", "recapHideProjects", "recapLastShownWeek",
            "chatProvider", "openAIChatModel", "googleChatModel",
            "ollamaChatModel", "ollamaServerURL", "lmstudioChatModel", "lmstudioServerURL",
            "hermesApprovalsEnabled", "showCodexPlanInNotch", "vercelProjectFilter", "n8nWorkflowFilter",
            "klayer.musicAutomationGranted", "klayerHooksInstalled",
            "openOnHover", "absenceInterval",
        ], "step 1 keeps the list it shipped with")
        // Step 2 (lot 4): the chat runs through Claude Code, the Anthropic key and the model
        // picker are gone.
        let second = RemovedFeatureCleanup.steps[1]
        precondition(second.keychainAccounts == ["anthropic-api-key"])
        precondition(second.defaultsKeys == ["claudeModel"])
        precondition(second.supportFiles.isEmpty)
    }

    static func aMacCleanedByStep1RunsOnlyStep2() {
        sandbox { defaults, dir in
            // A Mac where version 1 already ran, and where the user set openOnHover again since.
            defaults.set(1, forKey: RemovedFeatureCleanup.versionKey)
            defaults.set(true, forKey: "openOnHover")
            defaults.set("claude-sonnet-4-6", forKey: "claudeModel")
            defaults.set(15.0, forKey: "autoCloseInterval")
            let recap = dir.appendingPathComponent("recap.json")
            precondition(FileManager.default.createFile(atPath: recap.path, contents: Data("[]".utf8)))
            var deleted: [String] = []

            let ran = RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: dir) { deleted.append($0) }

            precondition(ran)
            precondition(deleted == ["anthropic-api-key"], "only step 2's secret goes, got \(deleted)")
            precondition(defaults.object(forKey: "claudeModel") == nil, "the model preference goes")
            precondition(defaults.bool(forKey: "openOnHover"), "step 1 is never run again")
            precondition(FileManager.default.fileExists(atPath: recap.path), "step 1 is never run again")
            precondition(defaults.double(forKey: "autoCloseInterval") == 15)
            precondition(defaults.integer(forKey: RemovedFeatureCleanup.versionKey) == 2)

            // And step 2 itself runs once.
            var again: [String] = []
            precondition(!RemovedFeatureCleanup.runIfNeeded(defaults: defaults, supportDir: dir) { again.append($0) })
            precondition(again.isEmpty)
        }
    }
}

import Foundation

/// What removed features left on the Mac, removed once at launch: their secrets in the Keychain
/// (service ai.klayer.island), the weekly recap's history file, and the preferences no code
/// reads any more. The Settings that could clear them are gone, so nothing else would.
///
/// Versioned by steps: each step runs once, when the stored version is below its own, and the
/// stored version then becomes the last step's. A Mac that already ran a step never runs it
/// again: a later removal adds a new step, it never edits a step that shipped.
/// What the app still uses is never listed (github-token, choices.json…).
/// Foundation only, the Keychain is reached through `deleteSecret`; tested by
/// scripts/test-removed-feature-cleanup.sh.
enum RemovedFeatureCleanup {
    static let versionKey = "removedFeatureCleanupVersion"

    struct Step {
        let version: Int
        /// Keychain accounts (service ai.klayer.island).
        let keychainAccounts: [String]
        /// Files in the support folder.
        let supportFiles: [String]
        /// Preferences.
        let defaultsKeys: [String]
    }

    static let steps: [Step] = [
        // 1, version 0.1.0: the chat providers other than Anthropic, the removed integrations,
        // the weekly recap and the removed settings.
        Step(
            version: 1,
            keychainAccounts: [
                "google-api-key", "openai-api-key",
                "resend-api-key", "resend-from",
                "n8n-url", "n8n-api-key",
                "vercel-token", "stripe-api-key", "calcom-api-key", "notion-api-key",
            ],
            // The session history the weekly recap kept.
            supportFiles: ["recap.json"],
            defaultsKeys: [
                // Weekly recap
                "recapEnabled", "recapHideProjects", "recapLastShownWeek",
                // Chat providers other than Anthropic
                "chatProvider", "openAIChatModel", "googleChatModel",
                "ollamaChatModel", "ollamaServerURL", "lmstudioChatModel", "lmstudioServerURL",
                // Removed agents, services and builds (Hermes, Codex, Vercel, n8n, Apple Music, App Store)
                "hermesApprovalsEnabled", "showCodexPlanInNotch", "vercelProjectFilter", "n8nWorkflowFilter",
                "klayer.musicAutomationGranted", "klayerHooksInstalled",
                // Removed settings: open on hover (lot 2), hide after N min without movement
                "openOnHover", "absenceInterval",
            ]),
        // 2, lot 4: the chat runs through the Claude Code of the Mac. The Anthropic API key and
        // the model picker are gone.
        Step(
            version: 2,
            keychainAccounts: ["anthropic-api-key"],
            supportFiles: [],
            defaultsKeys: ["claudeModel"]),
    ]

    /// The version stored once every step has run.
    static var version: Int { steps.last?.version ?? 0 }

    /// Runs the steps this Mac has not run yet, in order. Returns true when one ran.
    @discardableResult
    static func runIfNeeded(defaults: UserDefaults, supportDir: URL, deleteSecret: (String) -> Void) -> Bool {
        let done = defaults.integer(forKey: versionKey)
        let pending = steps.filter { $0.version > done }
        guard !pending.isEmpty else { return false }
        for step in pending {
            for account in step.keychainAccounts { deleteSecret(account) }
            for name in step.supportFiles {
                try? FileManager.default.removeItem(at: supportDir.appendingPathComponent(name))
            }
            for key in step.defaultsKeys { defaults.removeObject(forKey: key) }
        }
        defaults.set(version, forKey: versionKey)
        return true
    }
}

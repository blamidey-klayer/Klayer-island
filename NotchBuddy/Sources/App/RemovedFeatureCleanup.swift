import Foundation

/// What the features removed in 0.1.0 left on the Mac, removed once at launch: their secrets in
/// the Keychain (service ai.klayer.island), the weekly recap's history file, and the preferences
/// no code reads any more. The Settings that could clear them are gone, so nothing else would.
///
/// Versioned: it runs once per `version`, and a later version that adds to the lists bumps it.
/// What the app still uses is never listed (anthropic-api-key, github-token, choices.json…).
/// Foundation only, the Keychain is reached through `deleteSecret`; tested by
/// scripts/test-removed-feature-cleanup.sh.
enum RemovedFeatureCleanup {
    static let version = 1
    static let versionKey = "removedFeatureCleanupVersion"

    /// Keychain accounts of the removed chat providers and integrations.
    static let keychainAccounts = [
        "google-api-key", "openai-api-key",
        "resend-api-key", "resend-from",
        "n8n-url", "n8n-api-key",
        "vercel-token", "stripe-api-key", "calcom-api-key", "notion-api-key",
    ]

    /// Files in the support folder: the session history the weekly recap kept.
    static let supportFiles = ["recap.json"]

    /// Preferences of removed features and settings.
    static let defaultsKeys = [
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
    ]

    /// Removes everything listed above unless this version already did. Returns true when it ran.
    @discardableResult
    static func runIfNeeded(defaults: UserDefaults, supportDir: URL, deleteSecret: (String) -> Void) -> Bool {
        guard defaults.integer(forKey: versionKey) < version else { return false }
        for account in keychainAccounts { deleteSecret(account) }
        for name in supportFiles {
            try? FileManager.default.removeItem(at: supportDir.appendingPathComponent(name))
        }
        for key in defaultsKeys { defaults.removeObject(forKey: key) }
        defaults.set(version, forKey: versionKey)
        return true
    }
}

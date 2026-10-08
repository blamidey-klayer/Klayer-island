import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var apiKey: String = KeychainStore.shared.get("anthropic-api-key") ?? ""

    // Claude model — dynamic list fetched from the API, static fallback if unavailable
    private static let fallbackModels: [(id: String, label: String)] = [
        ("claude-sonnet-4-6",         "Claude Sonnet 4.6"),
        ("claude-sonnet-5-5",         "Claude Sonnet 5.5"),
        ("claude-opus-5-5",           "Claude Opus 5.5"),
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ]
    private static let customModelTag = "__custom__"
    @State private var fetchedModels: [(id: String, label: String)] = []
    @State private var modelChoice: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? m : SettingsView.customModelTag
    }()
    @State private var customModel: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? "" : m
    }()
    private var displayModels: [(id: String, label: String)] {
        fetchedModels.isEmpty ? Self.fallbackModels : fetchedModels
    }
    @State private var launchAtStartup: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var statusMessage: String = ""
    @State private var showDiff: Bool = false
    /// The previewed change to the "hooks" block, one entry per line (- removed, + added).
    @State private var pendingHookJSON: String = ""
    /// What the pending preview does: install (true) or uninstall (false) the hooks.
    @State private var hookPendingInstall: Bool = true
    @State private var hookNeedsUpdate: Bool = HookServer.hooksNeedUpdate()

    @State private var showStatusLineDiff: Bool = false
    @State private var pendingStatusLineJSON: String = ""
    @State private var statusLinePendingInstall: Bool = true
    @State private var planTogglePending: Bool = false

    // Integration keys
    @State private var githubToken: String  = KeychainStore.shared.get("github-token")    ?? ""

    // Hotkey
    @State private var hotkeyFlags: UInt    = AppState.shared.hotkeyFlags
    @State private var hotkeyCode: UInt16   = AppState.shared.hotkeyCode

    // Bindings in minutes for the absence field
    private var absenceMinutes: Binding<Double> {
        Binding(
            get: { state.absenceInterval / 60 },
            set: { state.absenceInterval = max(1, $0) * 60 }
        )
    }

    // Connected screens for the Display picker, refreshed when screens change
    @State private var connectedScreens: [(uuid: String, name: String)] = []

    // Sidebar selection persisted across sessions
    @AppStorage("settingsSection") private var selectedSection: String = "general"
    // Active pills: the pill whose colour palette is open, if any
    @State private var colorPalettePill: String? = nil
    @AppStorage(ClaudeHost.terminalCardsKey) private var terminalCardsEnabled = false
    @State private var customSoundCount = SoundEngine.shared.customized.count

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar — 200 pt, sidebar visual effect background
            ZStack(alignment: .topLeading) {
                SidebarBackground()
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(alignment: .center, spacing: 10) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Klayer Island")
                                .font(.system(size: 13, weight: .semibold))
                            Text(appVersion)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    Divider()
                    List(selection: Binding(
                        get: { Optional(selectedSection) },
                        set: { if let v = $0 { selectedSection = v; statusMessage = "" } }
                    )) {
                        SettingsSidebarRow(title: "General",      icon: "gearshape.fill",                    color: "#8E939C").tag("general")
                        SettingsSidebarRow(title: "Active pills", icon: "square.grid.2x2.fill",              color: "#F5A524").tag("activepills")
                        SettingsSidebarRow(title: "Agents",       icon: "terminal.fill",                     color: "#3B9EFF").tag("agents")
                        SettingsSidebarRow(title: "Chat",         icon: "bubble.left.and.bubble.right.fill", color: "#E07950").tag("chat")
                        SettingsSidebarRow(title: "Integrations", icon: "puzzlepiece.extension.fill",        color: "#7C5CFF").tag("integrations")
                        SettingsSidebarRow(title: "Shortcuts",    icon: "keyboard.fill",                     color: "#6366F1").tag("shortcuts")
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(width: 200)

            Divider()

            // Detail panel
            VStack(alignment: .leading, spacing: 0) {
                Text(sectionTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                if !statusMessage.isEmpty {
                    Divider()
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(statusMessage.hasPrefix("❌") ? .red : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            state.refreshPlanRelayState()
            guard fetchedModels.isEmpty,
                  let key = KeychainStore.shared.get("anthropic-api-key"), !key.isEmpty else { return }
            Task {
                let models = await ClaudeService.fetchModels(apiKey: key)
                guard !models.isEmpty else { return }
                await MainActor.run {
                    fetchedModels = models
                    let m = state.claudeModel
                    if models.contains(where: { $0.id == m }) {
                        modelChoice = m
                        customModel = ""
                    } else if modelChoice != Self.customModelTag {
                        modelChoice = Self.customModelTag
                        customModel = m
                    }
                }
            }
        }
    }

    // MARK: - Section routing

    private var sectionTitle: String {
        switch selectedSection {
        case "general":      return String(localized: "General")
        case "activepills":  return String(localized: "Active pills")
        case "agents":       return String(localized: "Agents")
        case "chat":         return String(localized: "Chat")
        case "integrations": return String(localized: "Integrations")
        case "shortcuts":    return String(localized: "Shortcuts")
        default:             return String(localized: "General")
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch selectedSection {
        case "activepills":  activePillsSection
        case "agents":       agentsSection
        case "chat":         chatSection
        case "integrations": integrationsSection
        case "shortcuts":    ShortcutsSettingsView()
        default:             generalSection
        }
    }

    // MARK: - General section

    @ViewBuilder private var generalSection: some View {
        GroupBox("Sound") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable sounds", isOn: $state.soundEnabled)
                HStack(spacing: 8) {
                    Text("Volume")
                        .frame(width: 56, alignment: .leading)
                    Slider(value: $state.soundVolume, in: 0...0.2)
                        .disabled(!state.soundEnabled)
                    Text("\(Int(state.soundVolume / 0.2 * 100)) %")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    Button("Open sounds folder") { SoundEngine.shared.revealCustomFolder() }
                    Button("Reload sounds") {
                        SoundEngine.shared.reload()
                        customSoundCount = SoundEngine.shared.customized.count
                        SoundEngine.shared.play("pop")
                    }
                    if customSoundCount > 0 {
                        Text(String(format: String(localized: "%lld custom"), Int64(customSoundCount)))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!state.soundEnabled)
                Text("Drop a file named like one of Klay's sounds (finish.wav, approval.mp3, greet.m4a…) in the sounds folder to replace it, then Reload.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
        }

        GroupBox("Behavior") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Close after")
                    TextField("60", value: $state.autoCloseInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("s inactive")
                }
                HStack(spacing: 8) {
                    Text("Hide after")
                    TextField("3", value: absenceMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                    Text("min without movement")
                }
            }
            .padding(6)
        }

        GroupBox("Display") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Show Klay on", selection: $state.islandDisplay) {
                    Text("Screen with the notch").tag(IslandDisplayChoice.notch)
                    Text("Main screen (menu bar)").tag(IslandDisplayChoice.menuBar)
                    Text("Follow the mouse").tag(IslandDisplayChoice.followMouse)
                    Divider()
                    ForEach(connectedScreens, id: \.uuid) { screen in
                        Text(screen.name).tag(IslandDisplayChoice.display(uuid: screen.uuid))
                    }
                    if case .display(let uuid) = state.islandDisplay,
                       !connectedScreens.contains(where: { $0.uuid == uuid }) {
                        Text("Saved screen (not connected)").tag(state.islandDisplay)
                    }
                }
                .frame(maxWidth: 360)
                Text("On a screen without a notch, Klay sits in a small bar at the top. Follow the mouse moves it to your cursor's screen while it is closed.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
            .onAppear { refreshConnectedScreens() }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification)) { _ in
                refreshConnectedScreens()
            }
        }

        GroupBox("Hotkey") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show island with shortcut", isOn: $state.hotkeyEnabled)
                    .onChange(of: state.hotkeyEnabled) { _, _ in
                        HotKeyCenter.shared.reregister(.toggleIsland)
                    }
                if state.hotkeyEnabled {
                    HStack(spacing: 8) {
                        Text("Shortcut")
                            .frame(width: 70, alignment: .leading)
                        ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                            .onChange(of: hotkeyFlags) { _, v in
                                state.hotkeyFlags = v
                                HotKeyCenter.shared.reregister(.toggleIsland)
                            }
                            .onChange(of: hotkeyCode) { _, v in
                                state.hotkeyCode = v
                                HotKeyCenter.shared.reregister(.toggleIsland)
                            }
                        Text("presses this → island opens")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(6)
        }

        GroupBox("Startup") {
            Toggle("Launch at Mac startup", isOn: $launchAtStartup)
                .onChange(of: launchAtStartup) { _, on in toggleStartup(on) }
                .padding(6)
        }

        GroupBox(String(localized: "Language")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $state.appLanguage) {
                    Text(String(localized: "System")).tag("")
                    Text("English").tag("en")
                    Text("简体中文").tag("zh-Hans")
                    Text("हिन्दी").tag("hi")
                    Text("Español").tag("es")
                    Text("العربية").tag("ar")
                    Text("Français").tag("fr")
                    Text("বাংলা").tag("bn")
                    Text("Português (Brasil)").tag("pt-BR")
                    Text("Русский").tag("ru")
                    Text("Bahasa Indonesia").tag("id")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: state.appLanguage) { _, code in
                    if code.isEmpty {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([code], forKey: "AppleLanguages")
                    }
                    UserDefaults.standard.synchronize()
                }
                HStack(spacing: 8) {
                    Button(String(localized: "Restart Klayer Island")) {
                        let appPath = Bundle.main.bundleURL.path
                        let pid = ProcessInfo.processInfo.processIdentifier
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/bin/sh")
                        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$1\"", "--", appPath]
                        try? task.run()
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                    Text(String(localized: "Applies on next launch"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(6)
        }
    }

    private func refreshConnectedScreens() {
        connectedScreens = NSScreen.screens.compactMap { screen in
            guard let uuid = IslandWindowController.displayUUID(screen) else { return nil }
            return (uuid, screen.localizedName)
        }
    }

    // MARK: - Active pills section

    @ViewBuilder private var activePillsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose the tools you use. Klayer Island only shows what you declare here.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(String(format: String(localized: "settings.slots-used %lld"), Int64(state.activeIntegrations.count)))
                    .font(.system(size: 11))
                    .foregroundColor(state.activeIntegrations.count >= 4 ? .orange : .secondary)

                ForEach(PillCategory.allCases, id: \.self) { cat in
                    let catPills = PillCatalog.all.filter { $0.category == cat }
                    if !catPills.isEmpty {
                        Divider()
                        Text(cat.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        ForEach(catPills, id: \.id) { def in
                            pillRow(def)
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - Agents section

    @ViewBuilder private var agentsSection: some View {
        GroupBox(String(localized: "hooks.claude-code.title")) {
            VStack(alignment: .leading, spacing: 10) {
                if hookNeedsUpdate {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(String(localized: "hooks.outdated"))
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    Button(String(localized: "hooks.update")) { installHooks() }
                }
                Text("nb-hook : \(HookServer.hookScriptPath)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button(String(localized: "hooks.install")) { installHooks() }
                        .buttonStyle(.borderedProminent)
                    Button(String(localized: "hooks.uninstall")) { uninstallHooks() }
                        .buttonStyle(.bordered)
                }
                Toggle("Answer questions and permissions from terminal sessions in the notch", isOn: $terminalCardsEnabled)
                Text("Off: sessions in Warp, Terminal, iTerm… show in the notch, but their questions and permission requests are asked in the terminal. On: the notch shows them first, and the terminal waits until you answer there or close the island (up to 2 min).")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showDiff {
                    ScrollView {
                        Text(pendingHookJSON)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)

                    HStack {
                        Button(String(localized: "hooks.confirm-write")) { confirmHooks() }
                            .buttonStyle(.borderedProminent)
                        Button(String(localized: "Cancel")) { showDiff = false; pendingHookJSON = "" }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(6)
        }

        GroupBox(String(localized: "plan.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "plan.description"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(String(localized: "plan.show-in-notch"), isOn: Binding(
                    get: { state.showPlanInNotch || planTogglePending },
                    set: { on in
                        if on {
                            if state.planRelayInstalled {
                                state.showPlanInNotch = true
                            } else {
                                planTogglePending = true
                                installStatusLine()
                            }
                        } else {
                            state.showPlanInNotch = false
                            planTogglePending = false
                        }
                    }
                ))
                HStack(spacing: 10) {
                    if state.planRelayInstalled {
                        Text(String(localized: "plan.relay.installed"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button(String(localized: "plan.relay.uninstall")) { uninstallStatusLine() }
                            .buttonStyle(.bordered)
                    } else {
                        Text(String(localized: "plan.relay.not-installed"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button(String(localized: "plan.relay.install")) { installStatusLine() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if showStatusLineDiff {
                    ScrollView {
                        Text(pendingStatusLineJSON)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    HStack {
                        Button(String(localized: "hooks.confirm-write")) { confirmStatusLine() }
                            .buttonStyle(.borderedProminent)
                        Button(String(localized: "Cancel")) {
                            showStatusLineDiff = false
                            pendingStatusLineJSON = ""
                            planTogglePending = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - Chat section

    @ViewBuilder private var chatSection: some View {
        GroupBox(String(localized: "chat.anthropic-api.title")) {
            VStack(alignment: .leading, spacing: 8) {
                SecureField(String(localized: "chat.api-key.claude"), text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Button(String(localized: "Save")) {
                    KeychainStore.shared.set("anthropic-api-key", value: apiKey)
                    statusMessage = String(localized: "status.key-saved")
                }
                .buttonStyle(.borderedProminent)

                Divider().padding(.vertical, 2)

                Picker(String(localized: "chat.model"), selection: $modelChoice) {
                    ForEach(displayModels, id: \.id) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                    Text(String(localized: "chat.model.custom")).tag(Self.customModelTag)
                }
                .onChange(of: modelChoice) { _, choice in
                    if choice != Self.customModelTag {
                        state.claudeModel = choice
                    } else {
                        applyCustomModel(customModel)
                    }
                }

                if modelChoice == Self.customModelTag {
                    TextField(String(localized: "chat.model.custom-id"), text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customModel) { _, value in applyCustomModel(value) }
                }

                Text(String(localized: "chat.model.description"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(6)
        }
    }

    // MARK: - Integrations section

    @ViewBuilder private var integrationsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {

                // GitHub
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#F4505E")).frame(width: 8, height: 8)
                        Text("GitHub").font(.system(size: 12, weight: .semibold))
                    }
                    SecureField("Personal Access Token", text: $githubToken)
                        .textFieldStyle(.roundedBorder)
                    Text(String(localized: "integrations.github.token-hint"))
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#8E939C"))
                }

                Button(String(localized: "integrations.save")) { saveIntegrations() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(6)
        }
    }

    // MARK: - Actions

    private func applyCustomModel(_ value: String) {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { state.claudeModel = id }
    }

    private func toggleStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            statusMessage = "❌ Startup: \(error.localizedDescription)"
            launchAtStartup = !on
        }
    }

    // MARK: - Hooks and status line

    private func installHooks() { previewHooks(install: true) }

    /// Like the install: the entries that go are shown first, and nothing is written before
    /// « Confirmer et écrire ».
    private func uninstallHooks() { previewHooks(install: false) }

    private func previewHooks(install: Bool) {
        do {
            let diff = try HookServer.shared.previewClaudeHooks(install: install)
            hookPendingInstall = install
            if diff.isEmpty {
                showDiff = false
                pendingHookJSON = ""
                statusMessage = install
                    ? String(localized: "Les hooks sont déjà à jour : rien à écrire.")
                    : String(localized: "Aucun hook de Klayer Island à retirer.")
            } else {
                pendingHookJSON = diff.text
                showDiff = true
                statusMessage = String(localized: "Vérifie les changements ci-dessous (- retiré, + ajouté), puis confirme.")
            }
        } catch {
            showDiff = false
            pendingHookJSON = ""
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmHooks() {
        do {
            try HookServer.shared.writeClaudeHooks()
            showDiff = false
            pendingHookJSON = ""
            statusMessage = hookPendingInstall
                ? String(localized: "status.hooks-installed-settings")
                : String(localized: "status.hooks-removed")
            hookNeedsUpdate = HookServer.hooksNeedUpdate()
        } catch {
            statusMessage = "❌ Write error: \(error.localizedDescription)"
        }
    }

    private func installStatusLine() {
        do {
            pendingStatusLineJSON = try HookServer.shared.previewStatusLine(install: true)
            showStatusLineDiff = true
            statusLinePendingInstall = true
            statusMessage = String(localized: "hooks.review-json")
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func uninstallStatusLine() {
        do {
            pendingStatusLineJSON = try HookServer.shared.previewStatusLine(install: false)
            showStatusLineDiff = true
            statusLinePendingInstall = false
            statusMessage = String(localized: "hooks.review-json")
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmStatusLine() {
        do {
            try HookServer.shared.writeStatusLine()
            showStatusLineDiff = false
            pendingStatusLineJSON = ""
            state.refreshPlanRelayState()
            if planTogglePending {
                state.showPlanInNotch = true
                planTogglePending = false
            }
            if !statusLinePendingInstall {
                state.showPlanInNotch = false
            }
            statusMessage = statusLinePendingInstall
                ? String(localized: "status.statusline-installed")
                : String(localized: "status.statusline-removed")
        } catch {
            planTogglePending = false
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func saveIntegrations() {
        // Detect GitHub token changes before writing
        let prevGithubToken = KeychainStore.shared.get("github-token")
        saveKey("github-token", value: githubToken)
        let nextGithubToken = KeychainStore.shared.get("github-token")
        if nextGithubToken != prevGithubToken {
            AppState.shared.githubPulse = nil
            AppState.shared.githubActivity = nil
            if nextGithubToken == nil { AppState.shared.githubStats = nil }
            if nextGithubToken != nil {
                GithubPoller.shared.triggerPulseNow()
                GithubPoller.shared.refreshActivityIfStale()
            }
        }

        statusMessage = String(localized: "status.integrations-saved")
    }

    private func saveKey(_ key: String, value: String) {
        if value.isEmpty {
            KeychainStore.shared.remove(key)
        } else {
            KeychainStore.shared.set(key, value: value)
        }
    }

    @ViewBuilder
    private func pillRow(_ def: PillDefinition) -> some View {
        let isMain = def.id == state.mainPillId
        let isOn   = state.activeIntegrations.contains(def.id)
        let atMax  = state.activeIntegrations.count >= 4 && !isOn && !isMain
        let hint: String? = {
            if isMain { return nil }
            if def.comingSoon { return String(localized: "Coming soon") }
            if def.id == SpotifyController.pillId && !SpotifyController.shared.isInstalled { return String(localized: "Not installed") }
            return nil
        }()
        HStack(spacing: 8) {
            // The dot is the row's colour control: it looks as it always did,
            // and a click opens the palette.
            Button {
                colorPalettePill = def.id
            } label: {
                Circle()
                    .fill(Color(hex: def.color))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Color"))
            .accessibilityLabel(Text(def.name + " · " + String(localized: "Color")))
            .popover(isPresented: Binding(
                get: { colorPalettePill == def.id },
                set: { open in if !open && colorPalettePill == def.id { colorPalettePill = nil } }
            ), arrowEdge: .bottom) {
                PillColorPalette(
                    current: def.color,
                    isCustom: state.pillColors[def.id] != nil,
                    pick: { hex in
                        state.setPillColor(def.id, hex)
                        colorPalettePill = nil
                    }
                )
            }
            Text(def.name)
                .font(.system(size: 12))
                .foregroundColor(atMax ? .secondary : .primary)
            Spacer()
            if isMain {
                Text("Main")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                if let h = hint {
                    Text(h)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { _ in state.toggleIntegration(def.id) }
                ))
                .labelsHidden()
                .disabled(atMax)
            }
        }
    }
}

// MARK: - Pill colour palette (Active pills, opened from a row's dot)

private struct PillColorPalette: View {
    /// The colour the pill is painted with now.
    let current: String
    /// The user picked it: "Default" is offered, to go back to the catalog's.
    let isCustom: Bool
    /// nil = back to the catalog's colour.
    let pick: (String?) -> Void

    var body: some View {
        let now = PillColors.normalized(current)
        HStack(spacing: 7) {
            ForEach(PillColors.palette, id: \.self) { hex in
                Button {
                    pick(hex)
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: 1.5)
                                .padding(-3)
                                .opacity(hex == now ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(hex))
            }
            if isCustom {
                Button(String(localized: "Default")) {
                    pick(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Sidebar background (NSVisualEffectView .sidebar)

struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Sidebar row (System Settings style icon)

struct SettingsSidebarRow: View {
    let title: String
    let icon: String
    let color: String

    var body: some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: color)))
        }
    }
}

// MARK: - Shortcut recorder button

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    @State private var isRecording = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            var token: Any?
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard !mods.isEmpty else { return event }
                DispatchQueue.main.async {
                    self.flags = mods.rawValue
                    self.code = event.keyCode
                    self.isRecording = false
                    if let t = token { NSEvent.removeMonitor(t) }
                }
                return nil
            }
        } label: {
            Text(isRecording ? "Press keys…" : shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shortcutLabel: String {
        let f = NSEvent.ModifierFlags(rawValue: flags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += keyChar(code)
        return s.isEmpty ? "None" : s
    }

    private func keyChar(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
            34:"I", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Space", 50:"`", 27:"-"
        ]
        return map[c] ?? "·"
    }
}

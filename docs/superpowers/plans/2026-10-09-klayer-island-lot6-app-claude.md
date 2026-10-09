# Klayer Island lot 6 : l'île au service de l'app Claude, plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Maison centrée sur les conversations (3/4 de la largeur, bande d'icônes à gauche), chat sans pastille automatique, zone de dépôt à un seul Klay, renfort de l'onglet Code et suivi expérimental de Chat et Cowork dans l'app Claude.

**Architecture:** Les règles pures (mise en page de la maison, historique du jour, notifications Code, repérage des libellés de l'app Claude) vont dans du code Foundation testé sous Linux ; les vues SwiftUI et la lecture Accessibilité (AppKit) les appliquent.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI + AppKit, ApplicationServices (AXUIElement, AXObserver), tests `swiftc` via `scripts/test-*.sh`, CI macOS `build.yml`.

**Spec:** `docs/superpowers/specs/2026-10-09-klayer-island-lot6-app-claude-design.md`

## Global Constraints

- Mac uniquement, macOS 15+, Swift 6 `-strict-concurrency=complete`, aucune dépendance tierce. `CLAUDE.md` jamais modifié.
- Le terminal ne change pas : cartes terminal toujours désactivées par défaut, routage des sessions terminal inchangé.
- Jamais d'approbation, de réponse ni de clic dans l'app Claude depuis l'île. Jamais d'envoi d'email.
- Aucun texte de message de l'app Claude n'est lu pour le diagnostic ni stocké ; seuls les rôles et libellés des contrôles.
- 0 % CPU île cachée, sauf l'exception écrite au §6 de la spec (lecture tant que l'app Claude est au premier plan ou qu'une réponse repérée est en cours).
- Textes visibles en français (catalogue, clés sources françaises), sans tiret cadratin ; tutoiement dans l'interface, « vous » dans les docs.
- IDs de pastilles conservés ; pas de restyle hors de ce que demande la spec.

## Review Focus

1. L'app Claude au premier plan, l'utilisateur tape puis passe sur une autre app pendant la réponse : la fin de réponse ouvre l'île (test de la machine de repérage).
2. Aucun libellé reconnu dans l'interface de l'app Claude : rien ne se déclenche, aucune lecture continue (test).
3. Plus de 10 sessions finies dans la journée, ou passage de minuit : la liste garde les 10 plus récentes du jour (test du registre).
4. Notification Code d'une session dont la carte est déjà affichée : pas de doublon (test de la règle).
5. Bande d'icônes sans jeton GitHub ni Spotify : seule Granola reste, la liste garde sa largeur (test de mise en page).

---

### Task 17: Maison : bande d'icônes, conversations sur les 3/4, historique du jour

**Files:** Modify `IslandViewContent.swift` (OverviewView, AgentPillsView retirée de la maison), `ConversationsView.swift`, `ChoiceHistoryView.swift`, `SessionRoster.swift` (élagage), `IslandRootView.swift` si la mise en page l'exige ; Create `HomeLayout.swift` (Foundation) ; tests `tests/SessionRosterTests.swift`, `tests/HomeLayoutTests.swift` + script + étape CI.

**Interfaces:**
- `enum HomeRail { static func icons(spotifyActive: Bool, githubConfigured: Bool) -> [RailIcon] }` avec `enum RailIcon: String { case spotify, github, granola }` (ordre : spotify, github, granola).
- `struct HomeLayout { static func widths(islandWidth: CGFloat) -> (rail: CGFloat, klay: CGFloat, list: CGFloat) }` : `list >= 0.75 * islandWidth`.
- `SessionRoster.prune(now:calendar:)` : une ligne `finished` ou `error` reste jusqu'à minuit du jour de sa fin (calendrier de l'utilisateur), 10 lignes finies au plus (les plus récentes) ; règles des lignes actives inchangées. `visible` : actives d'abord (activité récente), puis finies (fin récente).

- [ ] Step 1 : tests (rail : 3 cas d'icônes ; widths : list ≥ 480 sur 640 ; roster : 12 finies → 10, une finie d'hier effacée après minuit, actives avant finies).
- [ ] Step 2 : implémenter ; maison selon la spec §2 ; ligne finie : gris, « Terminé à HH:mm » ; choix : 3 lignes ; clic sur Spotify ou GitHub = leur carte à la place de la liste, maison ou second clic = retour ; Granola = `GranolaLink.newNote`.
- [ ] Step 3 : tests Linux verts, `swiftc -parse`, commit, push.

### Task 18: Chat sans pastille automatique

**Files:** Modify `IslandRootView.swift` (onglet chat), `IslandWindowController.swift` (raccourci du chat), tout appel automatique à `WindowContextCapture.captureActive`.

- [ ] Ouvrir le chat (onglet, ⌃⌥Espace) ne capture plus la fenêtre précédente ; `promptContext` n'est rempli que par un fichier déposé (« Poser une question ») ou Klay glissé sur une fenêtre. Run `grep -rn "captureActive" NotchBuddy/Sources` : seules restent les captures voulues. Commit, push.

### Task 19: Zone de dépôt à un seul Klay

**Files:** Modify `UploadCanvasView.swift`, `UploadSequenceEngine.swift`, `IslandViewContent.swift` (UploadView), `KlayPaint.swift` si besoin (sans toucher au glyphe).

- [ ] Un seul personnage dans l'onglet Déposer et pendant un glissé : Klay animé avec ses yeux (le Klay principal de l'île, à sa place de la vue `.upload`) ; bras ouverts à l'approche d'un fichier, regard qui suit le fichier, avalement (écrasement, yeux fermés) au dépôt. Retirer la figure d'invitation en double et la boîte aux lettres (`drawBoxBody`, `drawSlot` s'ils n'ont plus d'usage). Banc `tools/klay-preview` mis à jour si la pose d'avalement y existe. Commit, push.

### Task 20: Onglet Code : une demande sans carte ouvre l'île

**Files:** Modify `HookServer.swift` (`Notification`), `SessionRoster.swift` ou un fichier Foundation `CodeNotification.swift` ; tests.

**Interfaces:** `enum CodeNotification { static func alert(message: String, notificationType: String?) -> Kind? }` avec `enum Kind { case permission, waiting }` (lit `notification_type` quand Claude Code le fournit : `permission_prompt`, `idle_prompt`, `elicitation_dialog` ; sinon les messages « needs your permission », « waiting for your input ») ; `static func shouldOpen(kind:, sessionHasCard: Bool, agent: String) -> Bool` : vrai seulement pour `claude-desktop` et sans carte de cette session.

- [ ] Tests (types et messages ; doublon avec carte ; terminal jamais), implémenter : l'île s'ouvre en note « Claude attend ta réponse dans l'app Claude » avec « Ouvrir Claude », la ligne de la session passe en `question`/`approval`. Vérifier les champs exacts sur https://code.claude.com/docs/en/hooks (Notification) et les citer dans le rapport. Commit, push.

### Task 21: Suivi expérimental de Chat et Cowork

**Files:** Create `ClaudeAppWatchRules.swift` (Foundation, testé), `ClaudeAppWatcher.swift` (AppKit/AX) ; Modify `AppDelegate.swift`, `SettingsView.swift` (réglage + bouton de diagnostic), `HookServer.swift` ou `AppState.swift` pour ouvrir l'île ; tests + script + étape CI.

**Interfaces:**
- `struct AXNodeSummary: Equatable { let role: String; let label: String }` (label = AXDescription, AXTitle ou AXHelp, jamais AXValue).
- `enum ClaudeAppWatchRules { static let stopLabels: [String]; static let permissionLabels: [String]; static func isStop(_ n: AXNodeSummary) -> Bool; static func hasPermissionPrompt(_ nodes: [AXNodeSummary]) -> Bool }` (comparaison sans casse ; libellés anglais et français de l'interface : « Stop response », « Arrêter la réponse », « Allow », « Autoriser »… à confirmer par le diagnostic).
- `struct ClaudeAppWatchState { mutating func observe(stopVisible: Bool, permissionVisible: Bool, appFrontmost: Bool, now: Date) -> [ClaudeAppEvent] }` avec `enum ClaudeAppEvent: Equatable { case answerFinished, permissionRequested }` : `answerFinished` quand un bouton d'arrêt vu disparaît et que l'app n'est pas au premier plan ; `permissionRequested` une fois par apparition, app en arrière-plan ; `needsPolling` vrai seulement si l'app est au premier plan ou si une réponse est en cours.
- `ClaudeAppWatcher` : quand l'app Claude tourne, pose `AXManualAccessibility = true` sur son élément application, lit l'arbre (profondeur bornée, boutons seulement) toutes les 2 s tant que `needsPolling`, s'arrête sinon ; observe l'activation des apps (`NSWorkspace.didActivateApplicationNotification`) au lieu d'interroger. Diagnostic : liste des `AXNodeSummary` (rôles et libellés des contrôles) copiée dans le presse-papiers.

- [ ] Tests des règles et de l'état (réponse finie au premier plan : rien ; en arrière-plan : `answerFinished` ; aucun libellé : aucun événement et pas de lecture continue ; autorisation une seule fois), implémenter, réglage « Suivre Chat et Cowork dans l'app Claude (expérimental) » activé par défaut, ouverture de l'île en note avec « Ouvrir Claude ». Commit, push.

### Task 22: Docs et liste de contrôle

**Files:** `docs/TEST-MAC.md` (section lot 6 : maison, chat, dépôt, onglet Code, suivi expérimental, diagnostic à copier et renvoyer), `docs/SPEC.md`, `README.md`, `docs/INTEGRATIONS.md`, `CHANGELOG.md`.

- [ ] Écrire, vérifier contre le code, commit, push.

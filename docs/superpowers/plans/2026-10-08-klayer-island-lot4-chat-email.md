# Klayer Island : chat Haiku et brouillon Gmail par Claude Code, plan d'implémentation (lot 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le chat de l'île répond avec Haiku par le Claude Code installé sur le Mac (login claude.ai de l'utilisateur, aucune clé), et la zone de dépôt prépare un brouillon Gmail par le connecteur Gmail du compte Claude, sans jamais l'envoyer.

**Architecture:** Un cœur Foundation pur (`ClaudeCLI`, `ClaudeStream`) décide du binaire, de l'environnement, des arguments et lit le flux `stream-json` : il se teste sous Linux. Deux couches AppKit le pilotent : `ChatSession`, un processus `claude -p` long par conversation, alimenté en messages `stream-json` sur stdin ; `GmailDraftJob`, un processus court par brouillon. Le chemin par clé API (Messages API, sélecteur de modèle, recherche web) disparaît.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, `Foundation.Process`, PDFKit, tests `swiftc` lancés par `scripts/test-*.sh`, CI macOS `build.yml`.

**Spec:** `docs/superpowers/specs/2026-10-08-klayer-island-refonte-design.md` §7 et §8. Faits CLI vérifiés dans la doc Claude Code le 8 octobre 2026 : `.superpowers/sdd/2026-10-08-klayer-island-refonte/lot4-cli-research.md` (non versionné ; l'essentiel est recopié ci-dessous).

## Global Constraints

- Mac uniquement, macOS 15+, Swift 6 `-strict-concurrency=complete`, aucune dépendance tierce.
- Modèle fixe `claude-haiku-5-5`, sans sélecteur. Aucune clé ni jeton stocké par l'île pour le chat.
- Le processus `claude` reçoit un environnement nettoyé : sans `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY`, `ANTHROPIC_PROFILE` (en `-p`, une clé présente l'emporte toujours sur le login claude.ai et masque les connecteurs), avec `KLAYER_ISLAND_INTERNAL=1`.
- Le chat n'a aucun outil : `--tools ""` et `--disallowedTools "mcp__*"`. Le fichier déposé passe dans le message (image en base64, PDF en texte, texte en clair), jamais par un outil de lecture.
- Le brouillon n'a qu'un outil : la création de brouillon Gmail. Rien ne part sans action de l'utilisateur dans Gmail (règle Klayer et `CLAUDE.md` : jamais d'envoi d'email sans clic explicite).
- Les hooks de l'utilisateur ne se déclenchent pas pour ces processus (`--settings '{"disableAllHooks":true}'`, plus la sortie immédiate de `nb-hook` quand `KLAYER_ISLAND_INTERNAL` est défini).
- Textes visibles en français, sans tiret cadratin. Ne pas restyler les vues existantes : le chat garde sa bulle, son champ et sa dictée ; seule la carte email change, à la demande de la spec §8.
- 0 % CPU île cachée : aucun polling ; un processus en attente sur stdin ne consomme rien, et il est arrêté après 10 minutes sans message.

## Review Focus

1. Claude Code absent du Mac, ou installé sans login claude.ai : message clair avec le lien d'installation ou la marche à suivre, aucun blocage, aucun plantage (tests de `ClaudeCLI.locate` et `ClaudeCLI.authIsClaudeAI` dans Task 13).
2. Une `ANTHROPIC_API_KEY` présente dans l'environnement de l'app : retirée, pour que le forfait de l'utilisateur serve et que les connecteurs restent visibles (test de `ClaudeCLI.environment` dans Task 13).
3. Une ligne `stream-json` coupée entre deux lectures, ou une ligne qui n'est pas du JSON (avertissement de la CLI) : le lecteur la met en attente ou l'ignore, sans perdre de texte (tests de `ClaudeStreamParser` dans Task 13).
4. « Nouvelle conversation » ou fermeture pendant une réponse : le processus est arrêté, et un reste de réponse n'arrive jamais dans la conversation suivante (test du jeton de génération `ChatTurnToken` dans Task 13, câblé dans Task 14).
5. Connecteur Gmail absent du compte, ou outil nommé autrement : message explicite qui nomme Gmail, jamais de faux succès (tests de `ClaudeStream.gmailDraftTool(in:)` et `GmailDraft.parse` dans Task 13).

---

### Task 13: Cœur Claude Code pur et testé

**Files:**
- Create: `NotchBuddy/Sources/App/ClaudeCLI.swift`, `NotchBuddy/Sources/App/ClaudeStream.swift`, `tests/ClaudeCLITests.swift`, `scripts/test-claude-cli.sh`
- Modify: `HookServer.swift` (script `nbHookPython` : sortie immédiate, sans rien écrire, quand `KLAYER_ISLAND_INTERNAL` est défini), `.github/workflows/build.yml`

**Interfaces:**
- Produces (Foundation seulement) :
  - `enum ClaudeCLI` : `static let model = "claude-haiku-5-5"` ; `static func candidatePaths(home: String) -> [String]` (dans cet ordre : `~/.local/bin/claude`, `~/.claude/local/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `~/.npm-global/bin/claude`, `~/.bun/bin/claude`) ; `static func locate(home: String, isExecutable: (String) -> Bool) -> String?` ; `static func environment(from base: [String: String], binary: String) -> [String: String]` (retire les 7 clés des Global Constraints, ajoute `KLAYER_ISLAND_INTERNAL=1`, met en tête de `PATH` le dossier du binaire puis `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`, pour qu'une installation npm trouve `node`) ; `static func chatArguments(systemPrompt: String) -> [String]` ; `static func draftArguments(systemPrompt: String) -> [String]` ; `static let gmailDraftTool = "mcp__claude_ai_Gmail__create_draft"` ; `static let gmailDeniedTools: [String]` (`send_message`, `reply`, `forward`, `update_draft`, `delete_draft` sous le préfixe `mcp__claude_ai_Gmail__`) ; `static func authIsClaudeAI(statusJSON: Data) -> Bool` (`authMethod == "claude.ai"`) ; `static let installURL = URL(string: "https://code.claude.com/docs/en/quickstart")!`.
  - `enum ChatAttachmentKind: Equatable { case image(mediaType: String), pdf, text, unsupported }` et `static func ChatAttachmentKind.forExtension(_ ext: String) -> ChatAttachmentKind` (png, jpg/jpeg, gif, webp → image ; pdf ; txt, md, csv, json, swift, py, js, ts, html, css, xml, yaml, yml → text ; le reste → unsupported).
  - `enum ClaudeStream` : `static func userLine(text: String, images: [(mediaType: String, base64: String)]) -> String` (une ligne JSON terminée par `\n`, forme `{"type":"user","message":{"role":"user","content":[…]},"parent_tool_use_id":null}`, images avant le texte) ; `static func gmailDraftTool(in tools: [String]) -> String?` (l'outil dont le nom commence par `mcp__claude_ai_`, contient `gmail` sans casse et finit par `__create_draft`).
  - `enum ClaudeStreamEvent: Equatable { case initialized(tools: [String]), textDelta(String), assistantText(String), toolUse(name: String, inputJSON: String), toolResult(text: String), turnEnded(isError: Bool, message: String?) }` et `struct ClaudeStreamParser { mutating func feed(_ data: Data) -> [ClaudeStreamEvent] }`.
  - `struct GmailDraft: Equatable { let id: String; let viewURL: URL }` et `static func GmailDraft.parse(toolResult: String) -> GmailDraft?` (JSON avec `id` et `viewUrl` ; `viewUrl` accepté seulement en `https://mail.google.com/…`) ; `struct GmailDraftPreview: Equatable { let to: [String]; let subject: String; let body: String }` et `static func GmailDraftPreview.parse(inputJSON: String) -> GmailDraftPreview?` (lit `to`, `subject`, `body` de l'appel à l'outil de brouillon).
  - `struct ChatTurnToken { private(set) var generation: Int; mutating func reset(); func accepts(_ generation: Int) -> Bool }`.
- `chatArguments` contient exactement : `-p`, `--model claude-haiku-5-5`, `--input-format stream-json`, `--output-format stream-json`, `--verbose`, `--include-partial-messages`, `--tools ""` (argument vide), `--disallowedTools mcp__*`, `--permission-mode dontAsk`, `--no-session-persistence`, `--settings {"disableAllHooks":true}`, `--system-prompt <prompt>`.
- `draftArguments` contient exactement : `-p`, `--model claude-haiku-5-5`, `--output-format stream-json`, `--verbose`, `--tools ""`, `--permission-mode dontAsk`, `--setting-sources local`, `--settings {"disableAllHooks":true}`, `--no-session-persistence`, `--max-turns 3`, `--system-prompt <prompt>`, `--allowedTools <gmailDraftTool>`, `--disallowedTools <gmailDeniedTools…>`. Les listes d'outils sont variadiques : elles viennent en dernier, et la demande passe par stdin, jamais en argument.

- [ ] **Step 1: Write the failing tests** (`tests/ClaudeCLITests.swift`, harnais `@main` comme `tests/PendingRequestTests.swift`) :
  - `locate_takes_the_first_executable_candidate` : seul `/opt/homebrew/bin/claude` exécutable → ce chemin ; aucun → `nil`.
  - `environment_scrubs_keys_and_tags_the_process` : base avec les 7 clés, `HOME` et `PATH=/usr/bin` → aucune des 7, `HOME` gardé, `KLAYER_ISLAND_INTERNAL == "1"`, `PATH` commence par le dossier du binaire.
  - `chat_arguments_have_no_tools` : contient `--tools` suivi de `""`, `--disallowedTools` suivi de `mcp__*`, `--model` suivi de `claude-haiku-5-5`, `--no-session-persistence`.
  - `draft_arguments_allow_only_the_draft_tool` : `--allowedTools` suivi de `gmailDraftTool` seul ; chaque outil de `gmailDeniedTools` présent après `--disallowedTools` ; `--setting-sources` suivi de `local` ; aucun argument après la liste refusée qui ne soit un nom d'outil.
  - `auth_status` : `{"loggedIn":true,"authMethod":"claude.ai"}` → vrai ; `"authMethod":"api_key"` → faux ; `oops` → faux.
  - `attachment_kinds` : `PNG` → image `image/png`, `jpeg` → `image/jpeg`, `pdf`, `md` → text, `zip` → unsupported.
  - `user_line_is_one_json_line` : finit par un seul `\n`, se relit en JSON, image avant texte.
  - `parser_joins_split_lines_and_skips_noise` : un événement `text_delta` coupé en deux `feed` → un seul `.textDelta("Bonjour")` ; une ligne `warning: …` → aucun événement ; un `{"type":"result","is_error":true,"result":"x"}` → `.turnEnded(isError: true, message: "x")` ; un `system`/`init` avec `tools` → `.initialized`.
  - `gmail_tool_lookup` : `["mcp__claude_ai_Gmail__create_draft", "mcp__claude_ai_Gmail__send_message"]` → le premier ; `[]` → `nil`.
  - `gmail_draft_parse` : `{"id":"r1","viewUrl":"https://mail.google.com/mail/u/0/#drafts/r1"}` → brouillon ; `viewUrl` en `http://evil.example` → `nil`.
  - `gmail_draft_preview` : un événement `assistant` dont le contenu porte un bloc `tool_use` (`name` = l'outil Gmail, `input` = `{"to":["a@b.fr"],"subject":"Devis","body":"Bonjour"}`) donne `.toolUse` ; `GmailDraftPreview.parse` sur son `inputJSON` rend ces trois valeurs.
  - `turn_token_rejects_stale_generations` : génération lue, `reset()`, l'ancienne n'est plus acceptée, la nouvelle l'est.
- [ ] **Step 2:** Run `bash scripts/test-claude-cli.sh` ; attendu : échec de compilation.
- [ ] **Step 3:** Implémenter `ClaudeCLI.swift` et `ClaudeStream.swift`. Lignes d'événements à lire : `{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":…}}}` → `textDelta` ; `{"type":"assistant","message":{"content":[…]}}` → `assistantText` (texte joint des blocs `text`) et un `toolUse` par bloc `tool_use` (`input` réécrit en JSON) ; `{"type":"user","message":{"content":[{"type":"tool_result","content":…}]}}` → `toolResult` (texte, que `content` soit une chaîne ou une liste de blocs `text`) ; `{"type":"result",…}` → `turnEnded` ; `{"type":"system","subtype":"init","tools":[…]}` → `initialized`. Ajouter la sortie immédiate de `nb-hook.py` et l'étape CI « Test Claude CLI ».
- [ ] **Step 4:** Run le test ; attendu : `Claude CLI: 12 cases passed`.
- [ ] **Step 5:** Commit, push, CI verte.

### Task 14: Chat Haiku par Claude Code, fin du chemin par clé API

**Files:**
- Create: `NotchBuddy/Sources/App/ChatSession.swift`, `NotchBuddy/Sources/App/ChatAttachment.swift`
- Modify: `IslandViewContent.swift` (`PromptView` : envoi, flux, états CLI absente et non connectée ; `ResultView` et la vue `.result` retirées), `ClaudeService.swift` (ne garde que `Keychain` et `KeychainStore`, renommé `Keychain.swift`), `SettingsView.swift` (section clé API Anthropic et sélecteur de modèle retirés), `AppState.swift` (`claudeModel`, `defaultClaudeModel`, `searchResult`, `SearchResult`, `ResultItem` retirés), `IslandTypes.swift` (`ChatProvider`, `.result`), `AppDelegate.swift` (arrêt du processus à la sortie ; nettoyage unique au lancement de l'élément trousseau `anthropic-api-key` et de la préférence `claudeModel`), `ClaudeResponseText.swift`, `tests/ClaudeResponseTextTests.swift`, `scripts/test-claude-response.sh` et son étape CI (supprimés s'ils n'ont plus d'appelant), `Localizable.xcstrings`

**Interfaces:**
- Consumes: tout le cœur de Task 13.
- Produces: `@MainActor final class ChatSession { static let shared; enum Availability: Equatable { case ready, missingCLI, notLoggedIn }; func availability() async -> Availability; func send(_ text: String, attachment: URL?, context: PromptContext?, into state: AppState); func reset(); func stop() }`.

- [ ] **Step 1:** `ChatSession` lance au premier message `claude` (chemin de `ClaudeCLI.locate`, `environment`, `chatArguments`, dossier courant `HookServer.supportDir/chat` créé vide pour ne charger aucun `CLAUDE.md` de projet), garde le processus pour les messages suivants, lit stdout par `readabilityHandler` dans un `ClaudeStreamParser`, et repasse sur le main actor pour écrire dans `state.chatHistory` : une bulle assistant vide créée à l'envoi, complétée par chaque `textDelta`, remplacée par `assistantText` en fin de tour. Chaque tour porte la génération de `ChatTurnToken` ; `reset()` et `stop()` terminent le processus et changent la génération. Arrêt après 10 minutes sans message (`DispatchWorkItem`, pas de minuterie répétée). `availability()` appelle `claude auth status` une fois par lancement de l'app et met le résultat en cache ; un échec de lancement repasse à `missingCLI`.
- [ ] **Step 2:** Prompt système de Klay : reprendre `makeSystemPrompt` (prénom macOS), sans la phrase sur la recherche web, avec : pas d'outils, pas d'accès aux fichiers ni au web, réponses courtes, langue de l'utilisateur, Markdown léger. Contexte de fenêtre (`PromptContext.window`) en texte dans le premier message, comme aujourd'hui.
- [ ] **Step 3:** `ChatAttachment` construit le contenu du fichier déposé selon `ChatAttachmentKind` : image ≤ 5 Mo en base64 ; PDF converti en texte par PDFKit (`PDFDocument(url:)?.string`), tronqué à 200 000 caractères ; texte UTF-8 ≤ 200 Ko ; sinon un message « Ce type de fichier n'est pas pris en charge. » sans lancer Claude.
- [ ] **Step 4:** `PromptView` garde son apparence. Il appelle `ChatSession.shared.send`. État `missingCLI` : texte « Claude Code n'est pas installé sur ce Mac. » et bouton « Installer Claude Code » (`ClaudeCLI.installURL`). État `notLoggedIn` : « Connecte Claude Code : ouvre un terminal, lance claude puis /login. » Une erreur de tour passe par la note d'erreur existante.
- [ ] **Step 5:** Retirer le chemin par clé API (liste des fichiers ci-dessus). Run `grep -rnE "api\.anthropic\.com|anthropic-api-key|ChatProvider|claudeModel|web_search|SearchResult|fetchModels" NotchBuddy/Sources docs README.md` ; attendu : seulement le nettoyage unique de `AppDelegate` et sa doc.
- [ ] **Step 6:** Commit, push, CI verte, artefact téléchargeable.

### Task 15: Brouillon Gmail par le connecteur du compte Claude

**Files:**
- Create: `NotchBuddy/Sources/App/GmailDraftJob.swift`
- Modify: `IslandViewContent.swift` (`ChooseView` : « Préparer un email » ; `MailView` refaite ; `sendViaAppleMail` et l'AppleScript retirés), `Localizable.xcstrings`

**Interfaces:**
- Consumes: `ClaudeCLI.draftArguments`, `ClaudeCLI.gmailDraftTool`, `ClaudeStream.gmailDraftTool(in:)`, `ClaudeStreamParser`, `GmailDraft.parse`, `ChatSession.Availability` (Task 14).
- Produces: `@MainActor final class GmailDraftJob { enum Outcome: Equatable { case ready(GmailDraft, GmailDraftPreview?), gmailMissing, failed(String) }; static func run(to: [String], subject: String, intent: String, fileName: String?) async -> Outcome }`.

- [ ] **Step 1:** `GmailDraftJob.run` lance `claude` avec `draftArguments`, écrit la demande sur stdin puis le ferme, et lit le flux : si l'événement `initialized` ne contient aucun outil reconnu par `gmailDraftTool(in:)` → `gmailMissing` (et il arrête le processus) ; le dernier `toolUse` de l'outil Gmail donne l'aperçu (`GmailDraftPreview`), le premier `toolResult` que `GmailDraft.parse` accepte → `ready` ; un tour terminé sans brouillon → `failed` avec le message du tour. Délai maximal 90 s, puis arrêt et `failed("Délai dépassé.")`. Prompt système : Klay rédige un email court en français au ton de l'utilisateur à partir de son intention, crée exactement un brouillon avec l'outil Gmail, n'envoie jamais rien, mentionne la pièce jointe à ajouter quand `fileName` est fourni.
- [ ] **Step 2:** `MailView` : champs « À » (adresses séparées par des virgules, chacune contrôlée par une forme simple `x@y.z`), « Objet » (facultatif), « Ce que tu veux dire » ; boutons « Préparer le brouillon » et « Annuler ». Pendant le travail : Klay en `.thinking` et « Préparation du brouillon… ». Résultat `ready` : « Brouillon prêt dans Gmail », l'objet et les 3 premières lignes du corps quand l'aperçu existe, boutons « Ouvrir dans Gmail » (`viewURL`) et « Montrer le fichier » (Finder sur le fichier déposé), et la note « Glisse le fichier dans le brouillon pour le joindre. » (le fichier ne peut pas passer par Claude : il faudrait le recopier en base64 dans la réponse du modèle). `gmailMissing` : « Gmail n'est pas connecté à ton compte Claude. Ajoute le connecteur Gmail sur claude.ai, puis réessaie. » États `missingCLI` et `notLoggedIn` : mêmes textes que le chat.
- [ ] **Step 3:** Run `grep -rnE "tell application \"Mail\"|NSAppleScript|send m\b" NotchBuddy/Sources` ; attendu : aucune ligne.
- [ ] **Step 4:** Commit, push, CI verte.

### Task 16: Documentation et liste de contrôle du lot 4

**Files:**
- Modify: `docs/TEST-MAC.md` (section lot 4), `docs/SPEC.md` (chat et email), `README.md` (« Ce que fait l'app », « Configurer »), `docs/INTEGRATIONS.md`

- [ ] **Step 1:** `docs/TEST-MAC.md`, section lot 4 : `claude auth status` affiche `claude.ai` ; une question rapide répond sans rien configurer dans l'île ; une `ANTHROPIC_API_KEY` exportée dans `~/.zshrc` ne change rien ; « Nouvelle conversation » pendant une réponse ; un PDF et une image déposés puis questionnés ; un brouillon Gmail créé, visible dans Gmail, jamais envoyé ; le nom exact de l'outil Gmail lu dans `claude -p --output-format stream-json --verbose "ok"` (événement `system`/`init`, champ `tools`) et comparé à `mcp__claude_ai_Gmail__create_draft` ; Claude Code absent (renommer le binaire) : message d'installation.
- [ ] **Step 2:** README et SPEC : le chat passe par le Claude Code du Mac et le forfait de l'utilisateur, Haiku fixe, sans outils ; l'email devient un brouillon Gmail, la pièce jointe s'ajoute dans Gmail ; la clé API Anthropic disparaît de « Configurer ». Rappeler que la lecture des conditions d'Anthropic (spec §7) attend la validation d'un fondateur avant diffusion à l'équipe.
- [ ] **Step 3:** Commit, push.

### Task 16b: Finitions reportées de la revue des lots 1 à 3

> Ajout du contrôleur : points mineurs relevés par la re-revue finale des lots 1 à 3, regroupés ici pour ne pas rouvrir ce lot.

**Files:**
- Modify: `IslandWindowController.swift` (réouverture sur l'autre demande), `AppState.swift` (`toggleIntegration`), `HookServer.swift` (détection et aperçu de la ligne d'état), `UploadCanvasView.swift`, `Localizable.xcstrings`, les vues qui portent les deux textes à tiret cadratin

- [ ] **Step 1:** Après un repli avec deux demandes en attente, le survol rouvre sur l'autorisation : mettre à jour le focus, la pose de Klay et le badge de la pastille comme le fait l'affichage d'une demande retenue (`showHeldRequest` ou équivalent).
- [ ] **Step 2:** Activer ou retirer une pastille dans Réglages ne fait plus sortir Klay (`syncMode(revealing: false)` depuis `toggleIntegration`).
- [ ] **Step 3:** La détection et l'aperçu de la ligne d'état (`statusLineInstalled()` et son aperçu) ne reconnaissent que la commande de Klayer Island (chemin cité de `HookServer.hookScriptPath`, comme les hooks), jamais une commande de l'utilisateur qui contiendrait « nb-hook ». Test Foundation.
- [ ] **Step 4:** `"%@ is ready."` (zone de dépôt) reçoit son entrée française au catalogue ; les deux textes visibles à tiret cadratin (« Give me a sec — back to work in three seconds. » et le texte de remplacement « Claude — » de la jauge) sont réécrits sans tiret cadratin, en français.
- [ ] **Step 5:** Run les `scripts/test-*.sh` compilables sous Linux ; commit, push, CI verte.

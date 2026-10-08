# Klayer Island : refonte centrée app Claude, plan d'implémentation (lots 1 à 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recentrer l'app Mac sur l'app Claude desktop : nettoyage complet, ouverture au survol seulement, contenu de l'île refait autour des conversations et des choix demandés par Claude.

**Architecture:** On retire d'abord (lot 1) sans changer le comportement, puis on change la machine à états pure `IslandStateMachine` et son câblage AppKit (lot 2), puis le contenu de l'île et le routage des hooks `claude-desktop` (lot 3). Les lots 4 (chat Haiku, email) et 5 (Cowork) auront chacun leur plan après les spikes S3 et S2.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, XcodeGen, tests en exécutables `swiftc` lancés par `scripts/test-*.sh`, CI GitHub Actions macOS (`.github/workflows/build.yml`, déclenchable à la main).

**Spec:** `docs/superpowers/specs/2026-10-08-klayer-island-refonte-design.md`

## Global Constraints

- Mac uniquement, macOS 15+, Swift 6 `-strict-concurrency=complete`, aucune dépendance tierce.
- Bundle `ai.klayer.island` inchangé ; IDs de pastilles conservés pour ceux qui restent (`integration_claude`, `agent_claude-desktop`, Spotify).
- Klay dessiné depuis `KlayGlyph.swift` / `KlayPaint.swift`, glyphe jamais modifié.
- Jamais d'approbation ni d'envoi sans clic explicite ; Claude Code jamais bloqué (le hook sort tout de suite si l'app ne répond pas).
- `~/.claude/settings.json` : sauvegarde datée, fusion, diff, écriture après confirmation.
- Textes visibles en français par défaut dans les nouvelles vues (chaînes ajoutées à `Localizable.xcstrings`), sans tiret cadratin.
- Vérification Swift locale : `export PATH=<scratchpad>/swift/usr/bin:$PATH` permet `swiftc` (Foundation seulement) pour les tests purs ; tout code SwiftUI/AppKit se vérifie par la CI : `mcp__github__actions_run_trigger` (`run_workflow`, `build.yml`, ref de la branche), attendu : job `build` en `success` et artefact `KlayerIsland-macOS`.

## Review Focus

1. Clic hors de l'île alors qu'une autorisation attend : l'île se replie en réduit, la demande reste, le survol la rouvre (test dans Task 5).
2. Souris qui s'approche puis repart sans toucher l'encoche : Klay salue puis se cache, l'île ne s'ouvre jamais (test dans Task 5).
3. Fin de session arrivée pendant une absence : l'île reste ouverte jusqu'à un survol puis une sortie, pas de minuterie (test dans Task 5).
4. Historique des choix absent, vide ou corrompu : liste vide, aucun plantage, et le fichier est réécrit proprement au choix suivant (test dans Task 9).
5. Question d'une session `claude-desktop` à laquelle on répond aussi dans l'app Claude : la connexion du hook se ferme, la carte de l'île doit disparaître (contrôle manuel S1 dans Task 12, la fermeture du descripteur est déjà gérée pour Claude Code et doit l'être à l'identique).

---

## Lot 1 : nettoyage

### Task 1: Retirer Windows et Linux, garder un banc de rendu de Klay

**Files:**
- Create: `tools/klay-preview/` (`package.json`, `tsconfig.json`, `index.html`, `src/engine.ts`, `src/glyph.ts`, `src/anim.ts`, `src/sound.ts`, `src/types.ts`, `greeting.html` facultatif non requis)
- Delete: `windows/`, `linux/`, `.github/workflows/windows.yml`, `.github/workflows/linux.yml`, `.github/workflows/windows-ci.yml`
- Modify: `scripts/render-mac-icons.mjs` (chemin du glyphe), `CLAUDE.md`, `README.md`, `NOTICE.md`, `docs/AGENTS.md`, `docs/SPEC.md`, `.gitignore`

**Interfaces:**
- Produces: `tools/klay-preview/src/engine.ts` exporte `BotEngine`, `hexToRGB`, `KLAY_FIGURE`, `drawKlayGlyph`, `drawKlayArms`, `drawKlayLegs`, `drawKlayEyes` (copie de `windows/src/klay/engine.ts`, imports réécrits vers `./anim`, `./sound` (no-op `Sound.play`), `./types` (`BotStateName`, `BotEmoteName`)).

- [ ] **Step 1:** Copier `windows/src/klay/{engine,glyph}.ts`, `windows/src/core/anim.ts`, `windows/dev/klay-preview.{html,ts}` dans `tools/klay-preview/`, réécrire les imports, ajouter `package.json` (`vite@^6`, `typescript@^5.6`, script `check` = `tsc --noEmit`, `dev` = `vite`).
- [ ] **Step 2:** Run `cd tools/klay-preview && npm install && npm run check` ; attendu : sortie vide, code 0. Puis `npx vite --port 1430` et capture Playwright de `index.html?freeze=1.2` : la planche affiche les 11 états.
- [ ] **Step 3:** Supprimer `windows/`, `linux/` et les trois workflows. `scripts/render-mac-icons.mjs` lit `tools/klay-preview/src/glyph.ts`.
- [ ] **Step 4:** Mettre à jour la doc : plus aucune mention de Windows, Linux, Tauri, `klayer-hook.exe`, AppImage. Run `grep -rniE "windows|linux|tauri|appimage" --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=tools .` ; attendu : seules des occurrences hors sujet (par exemple « window » de fenêtre) ; les relire.
- [ ] **Step 5:** Commit `chore: Mac only, keep Klay preview bench in tools/`.

### Task 2: Retirer les intégrations de services (sauf GitHub) et Apple Music

**Files:**
- Delete: `NotchBuddy/Sources/App/{StripePoller,N8nPoller,ResendPoller,CalcomPoller,NotionPoller,VercelPoller,MusicController,NowPlayingViews}.swift`
- Modify: `NotchBuddy/Sources/App/AppDelegate.swift:189-195` (démarrage des pollers), `AppState.swift:283-349` et `:403`, `:561`, `SettingsView.swift:1114-1215`, `:1681`, `:1709`, `IslandViewContent.swift` (cartes Stripe :3050, Resend :2348, Cal.com :3139-3430, Notion :3433, n8n :3479, Vercel :2179-2332, Music :3902-4100 ; la carte GitHub :2432-3046 reste), `IslandWindowController.swift:690` (`.musicReveal`), `ClaudeService.swift:64-74` (clés), `KlayerIslandKit/PillCatalog.swift` (entrées `integration_*` sauf `integration_claude` et GitHub), `KlayerIslandKit/IslandTypes.swift:69` (`AgentSource.n8n` renommé `AgentSource.integration`).

**Interfaces:**
- Produces: `PillCatalog` ne contient plus que `integration_claude`, `agent_claude-desktop`, la pastille GitHub (ID inchangé), la pastille Spotify et les agents retirés en Task 3. `AgentSource.n8n` devient `AgentSource.integration`, utilisé par GitHub et Spotify seulement.

- [ ] **Step 1:** Supprimer les fichiers et toutes leurs références ; GitHub (poller, carte, alertes CI, `handleGitHubEvents`, tests `test-github-*.sh`) reste intact, tout comme Spotify et la danse de Klay (`BotCanvasView.swift:55-63`, `DesktopKlay.swift:45-48`) restent intactes.
- [ ] **Step 2:** Run `grep -rnE "Stripe|N8n|n8n|Resend|Calcom|Cal\.com|Notion|Vercel|MusicController|NowPlaying|musicReveal|AppleMusic" NotchBuddy tests scripts .github` ; attendu : aucune ligne. Run `bash scripts/test-github-pulse.sh && bash scripts/test-github-activity.sh` ; attendu : succès.
- [ ] **Step 3:** Run les tests purs locaux restants (`for s in scripts/test-*.sh; do bash $s || echo FAIL $s; done` avec le `swiftc` local) ; attendu : aucun `FAIL` hors scripts qui importent AppKit (à relancer en CI).
- [ ] **Step 4:** Commit, push, lancer la CI ; attendu : `build` en `success`.

### Task 3: Retirer les chats non Claude et les agents non Claude

**Files:**
- Delete: `NotchBuddy/Sources/App/{LocalChat,CodexPlanGauge}.swift`, `tests/fake_local_llm.py`
- Modify: `KlayerIslandKit/IslandTypes.swift:75-120` (fournisseurs : ne garder que `anthropic`), `ClaudeService.swift:275+` (chemin compatible OpenAI), `IslandViewContent.swift` (`ModelPickerView` :1377, choix du fournisseur dans `PromptView` :1175), `SettingsView.swift:959` (Chat, autres fournisseurs, modèles locaux), `HookServer.swift` (branches codex, copilot, muse, hermes, gemini, antigravity, cursor, opencode, amp ; scripts de plugins générés), `KlayerIslandKit/PillCatalog.swift` (agents), `IslandRootView.swift` (pastille Codex de l'en-tête), `tests/ClaudeHookDetectionTests.swift`

**Interfaces:**
- Produces: `ChatProvider` réduit à `.anthropic` (le chat reste fonctionnel avec la clé existante jusqu'au lot 4) ; `HookServer` ne reconnaît plus que `klayer_agent` vide (Claude Code) et `claude-desktop`.

- [ ] **Step 1:** Supprimer code et réglages ; les sessions d'un agent inconnu reçoivent `{"permissionDecision":"ask"}` comme aujourd'hui.
- [ ] **Step 2:** Adapter `tests/ClaudeHookDetectionTests.swift` : un cas vérifie que `validateAgent("codex")` ne crée plus de pastille. Run `bash scripts/test-claude-hooks.sh` en local ; attendu : succès.
- [ ] **Step 3:** Run `grep -rniE "codex|copilot|muse|hermes|gemini|antigravity|opencode|ollama|lmstudio|lm studio|openai|google ai" NotchBuddy tests scripts` ; attendu : aucune ligne hors `Localizable.xcstrings` (nettoyé en Task 4).
- [ ] **Step 4:** Commit, push, CI verte.

### Task 4: Retirer le mode démo, le récap hebdomadaire et toute trace iPhone ou App Store

**Files:**
- Delete: `NotchBuddy/Sources/App/{DemoEngine,RecapStore,WeeklyRecapView}.swift`, `scripts/test-weekly-recap.swift`
- Modify: les 91 blocs `#if APPSTORE` / `#if !APPSTORE` (garder la branche `!APPSTORE`, retirer les directives), `KlayerIslandKit/IslandTypes.swift` (vue `.recap`), `HookServer.swift`, `SettingsView.swift`, `AppDelegate.swift`, `IslandViewContent.swift`, `NotchBuddy/Resources/Localizable.xcstrings` (clés `iphone.*`, `live-activity*`, `instruction.*`, iCloud, Dynamic Island, chaînes des intégrations et fournisseurs retirés), `README.md`, `CHANGELOG.md`, `NOTICE.md`, `docs/*.md`, `.gitignore`, `tests/ClaudeHookDetectionTests.swift`

- [ ] **Step 1:** Retirer le code et les chaînes ; dans `Localizable.xcstrings`, supprimer toute clé que plus aucun fichier Swift n'utilise (script Python : clés du catalogue moins clés trouvées par `String(localized:` / `Text("` / `LocalizedStringKey` ; relire la liste avant suppression).
- [ ] **Step 2:** Run `grep -rniE "iphone|icloud|cloudkit|testflight|app ?store|APPSTORE|live ?activit|dynamic island|apns" --exclude-dir=.git --exclude-dir=node_modules .` ; attendu : aucune ligne, sauf la phrase de `NOTICE.md` qui dit que l'app iPhone de Coucou n'a pas été importée.
- [ ] **Step 3:** Commit, push, CI verte. Télécharger l'artefact n'est pas requis à ce stade.

## Lot 2 : comportement

### Task 5: Machine à états : survol seul, proximité, clic ailleurs

**Files:**
- Modify: `NotchBuddy/Sources/App/IslandStateMachine.swift`
- Test: `tests/IslandHoverTests.swift` (réécrit), `tests/IslandAutoCloseTests.swift` (adapté)

**Interfaces:**
- Produces, dans `IslandStateMachine` :
  - `func pointerNear()` : hidden → petit, appelle `onGreet` une fois par approche.
  - `func pointerFar()` : depuis petit sans demande en attente, planifie petit → hidden après `petitToHiddenDelay`.
  - `func mouseEntered()` : depuis hidden ou petit, ouvre (home) après `hoverOpenDelay` si la souris est toujours dessus ; annulé par `mouseLeft()`.
  - `func clickedOutside()` : home → petit si `isHeldOpen?() == true`, sinon home → hidden.
  - `var hoverOpenDelay: TimeInterval = 0.25`, `var onGreet: (() -> Void)?`.
  - Supprimés : `click()`, `openOnHover`, `openedByHover`, `userInteracted()`.
  - Après `openedExternally()`, aucune minuterie ; le premier `mouseLeft()` qui suit un `mouseEntered()` replie après `hoverCloseDelay` (0,6 s), sauf demande en attente.

- [ ] **Step 1: Write the failing tests** dans `tests/IslandHoverTests.swift` :
  - `near_then_far_greets_once_and_never_opens` : `pointerNear()` → `.petit`, `onGreet` appelé 1 fois ; second `pointerNear()` sans `pointerFar()` → toujours 1 ; `pointerFar()` avec `petitToHiddenDelay = 0.05` → `.hidden` ; jamais `.home`.
  - `hover_opens_after_250ms` : `mouseEntered()` → `.petit` immédiat, `.home` après 0,3 s.
  - `leaving_before_250ms_cancels_opening` : `mouseEntered()`, `mouseLeft()` à 0,1 s → pas de `.home` à 0,5 s.
  - `click_outside_closes` : island `.home` → `clickedOutside()` → `.hidden`.
  - `click_outside_with_pending_request_folds_to_petit` : `isHeldOpen = { true }`, `.home`, `clickedOutside()` → `.petit` ; `mouseEntered()` → `.home` après 0,3 s.
  - `finished_stays_until_hover_then_leave` : `openedExternally()` ; attendre 1 s → `.home` ; `mouseEntered()`, `mouseLeft()` → `.home` à 0,3 s, `.petit` à 1 s.
  - `no_click_api` : vérifié à la compilation (le test n'appelle plus `click()`).
- [ ] **Step 2:** Run `bash scripts/test-island-hover.sh` (swiftc local) ; attendu : échec de compilation sur `pointerNear` / `clickedOutside`.
- [ ] **Step 3:** Implémenter l'API ci-dessus ; retirer les entrées supprimées ; `tests/IslandAutoCloseTests.swift` n'utilise plus `click()`.
- [ ] **Step 4:** Run `bash scripts/test-island-hover.sh && bash scripts/test-auto-close.sh` ; attendu : `Island open on hover: 6 cases passed` remplacé par le nouveau total, auto-close OK.
- [ ] **Step 5:** Commit `feat: hover-only island with proximity greet and click-outside close`.

### Task 6: Câblage AppKit : proximité, salut, clic ailleurs, plus d'ouverture au clic

**Files:**
- Modify: `NotchBuddy/Sources/App/IslandWindowController.swift` (`pollFrame` :303-387, souris :710-808, `pinForFinished` :1039-1050 supprimé, `openOnHoverSubscription` :20 et :231 supprimés), `AppState.swift:250-251` et `:467` (`openOnHover` supprimé), `SettingsView.swift:313` (bascule supprimée), `BotCanvasView.swift:124` (`.botGreet`)

**Interfaces:**
- Consumes: Task 5 (`pointerNear`, `pointerFar`, `clickedOutside`, `onGreet`).
- Produces: `fsm.onGreet` poste `.botGreet` (le salut de `BotEngine.greet()` avec son `greet`) ; un moniteur global `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)` appelle `fsm.clickedOutside()` quand l'île est ouverte ; le rayon de 120 pt déjà utilisé par `pollFrame` appelle `pointerNear()` / `pointerFar()`.

- [ ] **Step 1:** Brancher la proximité et le salut ; son `peek` à l'approche, `open` à l'ouverture, `close` à la fermeture (déjà dans `setMode`).
- [ ] **Step 2:** Le mouseUp dans l'île fermée ou réduite ne déclenche plus rien ; dans l'île ouverte, clic sur Klay = émote agacée, glisser de Klay = bureau, boutons inchangés.
- [ ] **Step 3:** Échap appelle `clickedOutside()`.
- [ ] **Step 4:** Commit, push, CI verte ; ajouter les cas à la liste de contrôle (Task 12).

### Task 7: Île réduite : bouton Granola à la place des mini-Klay

**Files:**
- Create: `NotchBuddy/Sources/App/GranolaLink.swift`, `tests/GranolaLinkTests.swift`, `scripts/test-granola-link.sh`
- Modify: `IslandRootView.swift:123-128` et `:655-672` (`CompactMiniGrid` supprimé), `GreetingCanvasView.swift:481-502` (minis supprimés), `IslandWindowController.swift` (le clic sur le bouton ne passe pas par la FSM), `.github/workflows/build.yml` (nouveau script de test)

**Interfaces:**
- Produces: `enum GranolaLink { static let newNote: URL /* granola://new-document */; static func open(using: (URL) -> Bool) -> Bool }` ; vue `GranolaButton` : SF Symbol `mic`, gris 45 %, 14 pt, infobulle « Nouvelle note Granola », placée à x = largeur − 40 (emplacement de l'ancienne grille).

- [ ] **Step 1: Write the failing test** `tests/GranolaLinkTests.swift` : `GranolaLink.newNote.absoluteString == "granola://new-document"` ; `open(using:)` appelle la closure une fois avec cette URL et renvoie sa valeur.
- [ ] **Step 2:** Run `bash scripts/test-granola-link.sh` ; attendu : échec, type inconnu.
- [ ] **Step 3:** Implémenter `GranolaLink` (production : `NSWorkspace.shared.open`) et `GranolaButton`.
- [ ] **Step 4:** Run le test ; attendu : `Granola link: 2 cases passed`.
- [ ] **Step 5:** Commit, push, CI verte.

### Task 8: Zone de dépôt : Klay à la place des pictogrammes

**Files:**
- Modify: `NotchBuddy/Sources/App/UploadCanvasView.swift:160-180` (texte et puces PDF / Images / Code / Docs), `KlayerIslandKit/KlayPaint.swift` (pose « bras ouverts »)

**Interfaces:**
- Produces: `KlayPaint.armsOpenTargets() -> (lh: CGPoint, rh: CGPoint)` = mains à (±200, −40) en unités du glyphe ; la zone de dépôt dessine Klay (glyphe, yeux `wide`, bras ouverts) au centre avec le texte « Dépose ton fichier ».

- [ ] **Step 1:** Remplacer le pictogramme et les puces ; la séquence boîte aux lettres qui suit reste inchangée.
- [ ] **Step 2:** Reproduire la pose dans `tools/klay-preview` (case « dépôt ») et capturer pour contrôle visuel.
- [ ] **Step 3:** Commit, push, CI verte.

### Task 8b: Jumelles en recherche et couleurs d'état de la marque Klayer

Demande de Baptiste (8 octobre) : en recherche, Klay tient des jumelles bien visibles ; les accents d'état (halo, badge) reprennent les couleurs de la marque Klayer.

**Files:**
- Modify: `tools/klay-preview/src/engine.ts` (couleurs `C`, pose `searching`, dessin des jumelles), `NotchBuddy/Sources/KlayerIslandKit/KlayPaint.swift` et `BotEngine.swift` (mêmes couleurs, même pose, même dessin), `docs/SPEC.md` §7 (tableau des états)

**Interfaces:**
- Produces: `drawKlayBinoculars(x, look)` (TS) et `KlayPaint.drawBinoculars(in:look:)` (Swift), dessinés devant les yeux en état `searching` ; les yeux ne sont pas dessinés pendant ce temps.

Couleurs d'état : variantes éclaircies des couleurs de la marque, pour rester lisibles sur l'île noire (les valeurs exactes de la charte sont trop sombres sur du noir).

| État | Couleur | Source dans la charte |
|---|---|---|
| idle | `#3E7280` | teal-light |
| working | `#4FA3B5` | teal éclairci |
| thinking | `#7FB8C4` | teal éclairci |
| searching | `#A8D0D8` | teal éclairci |
| approval | `#D69A3A` | etat-tension éclairci |
| question | `#E2B866` | etat-tension éclairci |
| error | `#D0663F` | brique éclaircie |
| finished | `#6FA35E` | etat-tenu éclairci |
| ratelimit | `#B0761C` | etat-tension |
| sleeping | `#C9CAC3` | filet |
| dizzy | `#E08A6A` | brique éclaircie |

Jumelles, en unités du glyphe (origine au moyeu) : deux fûts arrondis `#071B20` (teal-deep) de 92 × 104 centrés sur (±56, −10), reliés par un pont de 40 × 30 ; lentilles rondes de rayon 36 en `#3E7280` avec un liseré `#ECEDE7` de 8 et un reflet blanc ; les deux mains tiennent les fûts à (±112, 18) ; l'ensemble suit le balayage du regard (décalage x = yaw × 18).

- [ ] **Step 1:** Implémenter dans `tools/klay-preview` ; capture Playwright de la planche (`index.html?freeze=1.2`, tailles 180 et 97) : les jumelles se lisent à 97 px.
- [ ] **Step 2:** Porter à l'identique en Swift ; `swiftc -parse` sur les fichiers touchés.
- [ ] **Step 3:** Mettre à jour `docs/media/klay-sheet.png` avec la nouvelle capture et le tableau §7 de `docs/SPEC.md`.
- [ ] **Step 4:** Commit, push, CI verte.

### Task 8c: Animation de Klay au niveau de Mochi

Demande de Baptiste (8 octobre) : animations fluides et très vivantes, Klay suit ce qu'on fait avec les yeux, au même niveau que le personnage de l'app d'origine.

**Files:**
- Modify: `tools/klay-preview/src/engine.ts`, `NotchBuddy/Sources/KlayerIslandKit/BotEngine.swift`, `KlayPaint.swift`, `NotchBuddy/Sources/App/BotCanvasView.swift` (cadence), `docs/SPEC.md` §7
- Create: `docs/klay-animation-parity.md` (tableau de parité)
- Reference (lecture seule) : le moteur d'origine, `git show a7bd575:NotchBuddy/Sources/App/BotEngine.swift` dans le clone `/home/user/louis-cfm/coucou`, et `windows/src/mochi/engine.ts` du même commit

**Interfaces:**
- Produces: mêmes API publiques de `BotEngine` (TS et Swift) ; nouveaux états internes seulement.

- [ ] **Step 1:** Établir le tableau de parité : chaque comportement animé du moteur d'origine (respiration, clignements simples et doubles, regard qui suit le pointeur avec retard, rotation de tête et perspective, réaction au survol, écrasement et rebond, ressorts des parties souples, roulades, émotes, particules, salut, danse sur la musique, ennui et bâillement, mini-personnages qui regardent ailleurs) avec son équivalent chez Klay : présent, à renforcer, absent.
- [ ] **Step 2:** Combler chaque ligne « à renforcer » ou « absent », sans reprendre le dessin de Mochi : regard plus ample (yeux, pupilles et léger pivot du corps vers le pointeur), ressorts amortis sur mains et pieds (inertie quand le corps bouge, au lieu d'un simple lissage), petites occupations au repos (tapote du pied, regarde autour quand la souris ne bouge plus, s'étire), corps qui se penche vers le pointeur au survol. Tout calcul dépend de `dt` : aucune animation ne dépend de la cadence d'affichage.
- [ ] **Step 3:** Vérifier sur le banc : séquence de captures Playwright (pointeur déplacé de gauche à droite, survol, repos 10 s) ; le regard suit, les mouvements restent continus d'une image à l'autre.
- [ ] **Step 4:** Porter en Swift à l'identique ; `swiftc -parse` ; CI verte.

## Lot 3 : contenu

### Task 9: Historique des choix demandés par Claude

**Files:**
- Create: `NotchBuddy/Sources/App/ChoiceHistory.swift`, `tests/ChoiceHistoryTests.swift`, `scripts/test-choice-history.sh`
- Modify: `HookServer.swift` (au moment où une autorisation ou une question reçoit sa réponse), `.github/workflows/build.yml`

**Interfaces:**
- Produces:
  - `struct ChoiceRecord: Codable, Equatable { let date: Date; let session: String; let kind: Kind /* .permission, .question */; let prompt: String; let answer: String }`
  - `final class ChoiceHistory { init(fileURL: URL); private(set) var records: [ChoiceRecord] /* plus récent d'abord */; func record(_ r: ChoiceRecord); func latest(_ n: Int) -> [ChoiceRecord] }`, limite 20, écriture atomique JSON.
  - Fichier par défaut : `~/Library/Application Support/KlayerIsland/choices.json`.

- [ ] **Step 1: Write the failing tests** :
  - `keeps_20_newest_first` : 25 `record` → `records.count == 20`, `records.first` = le 25e.
  - `latest_5` : `latest(5).count == 5` et dans l'ordre.
  - `persists_round_trip` : nouvel objet sur le même fichier → mêmes `records`.
  - `missing_or_corrupt_file_is_empty` : fichier absent → `[]` ; fichier contenant `{oops` → `[]`, puis un `record` réécrit un JSON valide.
- [ ] **Step 2:** Run `bash scripts/test-choice-history.sh` ; attendu : échec de compilation.
- [ ] **Step 3:** Implémenter ; brancher `HookServer` : autorisation → `answer` = « Autorisé », « Refusé » ou « Toujours » ; question → libellés des options choisies joints par « , ».
- [ ] **Step 4:** Run le test ; attendu : `Choice history: 4 cases passed`.
- [ ] **Step 5:** Commit, push, CI verte.

### Task 10: Répondre aux sessions de l'app Claude depuis l'île

**Files:**
- Create: `NotchBuddy/Sources/App/HookRouting.swift`, `tests/HookRoutingTests.swift`, `scripts/test-hook-routing.sh`
- Modify: `HookServer.swift:655-697` (`processPermissionRequest`), `:872+` (`processQuestionRequest`), `.github/workflows/build.yml`

**Interfaces:**
- Produces: `enum HookRouting { static func handledInIsland(agent: String) -> Bool /* "" et "claude-desktop" → true */; static func pillId(agent: String) -> String /* "claude-desktop" → "agent_claude-desktop", sinon "integration_claude" */ }`.

- [ ] **Step 1: Write the failing tests** : `handledInIsland("")`, `handledInIsland("claude-desktop")` vrais ; `handledInIsland("codex")`, `handledInIsland("x")` faux ; `pillId("claude-desktop") == "agent_claude-desktop"`, `pillId("") == "integration_claude"`.
- [ ] **Step 2:** Run `bash scripts/test-hook-routing.sh` ; attendu : échec de compilation.
- [ ] **Step 3:** Implémenter et remplacer les tests ad hoc de `HookServer` par `HookRouting` ; les cartes d'autorisation et de question s'affichent pour `claude-desktop`.
- [ ] **Step 4:** Run le test ; attendu : `Hook routing: 6 cases passed`.
- [ ] **Step 5:** Commit, push, CI verte.

### Task 11: Île ouverte : conversations en cours et derniers choix

**Files:**
- Create: `NotchBuddy/Sources/App/ConversationsView.swift`, `NotchBuddy/Sources/App/ChoiceHistoryView.swift`
- Modify: `IslandViewContent.swift:35-265` (vue overview), `:186-264` (`openAgentTarget`), `:594`, `:2020-2060` (boutons terminal, VS Code, Cursor), `:645` (`DiffCardView`), `:3547` (`TickerView` réduit à une ligne), `:3779` (`AgentPillsView`), `IslandRootView.swift:487-551` (en-tête), `PillCatalog.swift` (pastilles d'éditeurs), `SettingsView.swift:464-500` (Active pills), `AppState.swift:126`, `:302`, `:604-624`

**Interfaces:**
- Consumes: `ChoiceHistory.latest(5)` (Task 9), tâches de `AppState`.
- Produces: la carte GitHub existante sous les deux listes, inchangée ; `ConversationsView` (une ligne par tâche : mini-Klay couleur de l'état, titre, état en clair, dernière action ; clic → `NSWorkspace.shared.open(URL(string: "claude://")!)`), `ChoiceHistoryView` (5 lignes grises 55 % d'opacité : heure `HH:mm`, session, prompt tronqué à 1 ligne, réponse) ; la carte de demande en attente passe au-dessus des deux.

- [ ] **Step 1:** Construire les deux vues et la nouvelle overview ; retirer pastilles d'éditeurs, boutons terminal et éditeur, cartes de diff, réglages Active pills.
- [ ] **Step 2:** Run `grep -rnE "VS ?Code|vscode|Cursor|DiffCardView|AgentPillsView|jumpToTerminal|TerminalTarget" NotchBuddy/Sources` ; attendu : seules les détections encore utiles au routage des hooks (relire chaque ligne).
- [ ] **Step 3:** Commit, push, CI verte, artefact téléchargeable.

### Task 12: Liste de contrôle Mac et spikes S1, S3, S4

**Files:**
- Create: `docs/TEST-MAC.md`

- [ ] **Step 1:** Écrire la liste : installation de l'artefact, survol et proximité (salut, son), clic sur l'encoche sans effet, clic ailleurs, Échap, demande en attente et clic ailleurs, fin de session, bouton Granola, zone de dépôt, conversations, derniers choix ; puis S1 (une autorisation du mode Code acceptée dans l'île : la fiche de l'app Claude disparaît-elle ?), S3 (`claude -p --model claude-haiku-5-5 "bonjour"` dans un terminal : répond-il sans connexion supplémentaire ? `claude mcp list` montre-t-il Gmail ?), S4 (`open "granola://new-document"` lance-t-il l'enregistrement ?).
- [ ] **Step 2:** Commit, push. Transmettre le lien de l'artefact et la liste à Baptiste.

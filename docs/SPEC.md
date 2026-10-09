# Klayer Island : spécification

Toutes les mesures sont en points macOS. Les valeurs viennent de `reference/notch-buddy.html` (constantes `NW`, `NH`, `EW`, `VIEWS`, `STATES`, `EMOTES`, `PISTES`, `AGENTS`, classe `Bot`). En cas de doute, relire le code du prototype.

---

## 1. Fenêtre et notch

- Une `NSPanel` sans bordure : `styleMask [.borderless, .nonactivatingPanel]`, fond transparent, sans ombre, niveau au-dessus de la barre de menus (`.mainMenu + 3` ou équivalent qui passe au-dessus de la barre et des apps plein écran), `collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- Taille fixe 720 × 320, ancrée en haut au centre de l'écran qui a un notch. L'island est dessinée dedans, collée au bord haut.
- **Choix de l'écran** (`AppState.islandDisplay`, UserDefaults `islandDisplay`, réglage **Display** dans General) :
  - `notch` (défaut) : écran avec notch, sinon écran principal. Comportement historique.
  - `menuBar` : l'écran qui porte la barre de menus (`NSScreen.screens[0]`).
  - `display:<UUID>` : un écran précis, identifié par `CGDisplayCreateUUIDFromDisplayID` (stable après redémarrage, contrairement à `NSScreenNumber`). Écran débranché → repli sur l'écran avec notch, puis l'écran principal ; il revient dès qu'il est rebranché.
  - `followMouse` : l'island passe sur l'écran du curseur, uniquement en `hidden` ou `compact` et hors glisser-déposer de Klay. Ouverte (approbation, chat, salut…), elle ne bouge pas. Vérifié dans la boucle 60 Hz existante, sans timer supplémentaire.
  - Résolution pure dans `IslandDisplayResolver` (`IslandDisplayChoice.swift`, testé par `scripts/test-display-choice.sh`). `IslandWindowController.relocate(to:)` recalcule la géométrie (notch ou barre), déplace la panel et poste `.islandScreenChanged` pour que `IslandContainer` reprenne ses dimensions au repos.
  - Recalcul à chaque `NSApplication.didChangeScreenParametersNotification` (écran branché ou débranché, capot fermé, résolution, disposition). La fenêtre Réglages et les envols de Klay sur le bureau visent l'écran courant de l'island (`IslandWindowController.islandScreen()`).
- **Clics traversants** : la zone transparente ne doit jamais bloquer les clics. Toggle `ignoresMouseEvents` à 60 Hz selon que `NSEvent.mouseLocation` est dans la forme de l'island (plus 6 pt de marge) ou pas.
- La panel peut devenir key uniquement quand un champ texte de l'island a le focus (prompt, mail). Sinon elle ne vole jamais le focus.
- Détection du notch : `NSScreen.safeAreaInsets.top` > 0 et `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Largeur du notch `wN` = largeur écran − les deux zones auxiliaires ; hauteur `hN` = `safeAreaInsets.top`. Le prototype utilise `wN = 184`, `hN = 32` : dans l'app, prendre les vraies valeurs.
- Pas d'écran avec notch (Mac de bureau, écran externe ou capot fermé), ou écran sans notch choisi dans **Display** : afficher sur cet écran une barre noire de 80 pt au repos (`hidden`), avec Klay visible au centre et son animation en pause ; 240 pt en `compact`, en haut au centre. Hauteur plafonnée à 24 pt et à celle de la barre de menus ; personnage et bouton Granola adaptés à cette hauteur. Le salut se replie vers les dimensions réelles de la barre compacte. La zone de survol au repos ne déborde pas sous la barre. Les vues ouvertes gardent leur largeur de 640 pt.
- Suivi de la souris : polling de `NSEvent.mouseLocation` à chaque frame. Aucune permission nécessaire.

### Forme de l'island
- Rectangle noir `#000`, coins hauts carrés (il se fond dans le bord de l'écran), coins bas arrondis : 14 pt en hidden et compact, 22 pt en expanded.
- Deux « oreilles » concaves de 14 pt aux coins hauts, à l'extérieur, pour que la forme coule dans le bord de l'écran (voir `#island::before/::after` du prototype).

## 2. Modes de l'island

| Mode | Largeur | Hauteur | Bonhomme | Agents secondaires |
|---|---|---|---|---|
| `hidden` | wN | hN | invisible | invisibles |
| `compact` | wN + 160 | hN | Ø 20 (hauteur − 6 sur une barre plus basse), centre x = 40 | aucun ; le bouton Granola occupe l'oreille droite |
| `expanded` | 640 | selon la vue (§5) | selon la vue | selon la vue |

(Ø = diamètre du corps. Le canvas du personnage fait Ø / 0,6 de côté : le corps occupe 60 % du canvas, le reste sert aux particules, mains et badge.)

Bouton Granola (île `compact` uniquement, jamais en `hidden` ni en `expanded`) : pictogramme micro (SF Symbol `mic`) de 14 pt, gris `#8E939C` à 45 %, centré sur le point (largeur − 40, hN/2), dans une zone cliquable carrée de 28 pt (moins si la barre est plus basse). Infobulle « Nouvelle note Granola ». Un clic ouvre `granola://new-document` : le lien crée une note, le démarrage automatique de l'enregistrement n'est pas confirmé. Si aucune app ne répond au lien (Granola absent), le clic ne fait rien. C'est le seul clic actif de l'île réduite. Le pictogramme est un micro neutre : le logo Granola n'est pas repris.

## 3. Règles de comportement

1. **Rien ne tourne** → `hidden`. Totalement invisible.
2. **Souris à moins de 120 pt de l'encoche** → Klay sort en `compact` (son `peek`) et fait coucou de la main (`BotEngine.greet()` par la notification `.botGreet`, son `greet`). Il salue une fois par approche, aussi quand il est déjà sorti, et recommence quand la souris s'est éloignée puis revient ; jamais quand l'île est ouverte ni pendant le salut de lancement, ni quand Klay est sur le bureau. L'approche n'ouvre jamais l'île. Tant que la souris reste dans la zone, l'île réduite ne se cache pas ; une fois la souris partie, elle se cache après 60 s. La zone s'arrête au bord haut de l'écran : un écran placé au-dessus ne compte pas. Changer d'écran, passer à une autre app ou à une autre session, ou mettre les écrans en veille compte comme un départ : la prochaine approche salue de nouveau.
3. **Claude travaille** (un événement d'une session arrive, île cachée) → Klay sort en `compact` (son `peek`), sans saluer : très fin, le bonhomme visible, il suit la souris des yeux partout sur l'écran. Il se cache 60 s plus tard si la souris est loin (règle 2).
4. **Souris sur l'encoche** (forme de l'île, plus 6 pt de marge) → l'île s'ouvre après 250 ms si la souris y est toujours (sur l'autorisation en attente, sinon la question en attente, sinon la vue `overview`, ou `empty` s'il n'y a aucune tâche), son `open`. Partir avant annule l'ouverture. Le bouton Granola de l'île réduite ne compte pas comme l'île : la souris posée dessus n'ouvre rien, et la quitter pour le reste de l'île relance les 250 ms.
5. **Clic sur l'île fermée ou réduite** → rien : l'île ne s'ouvre jamais au clic. Seule exception, le bouton Granola de l'île réduite : son clic ouvre Granola sans ouvrir l'île, sans passer par la machine d'états et sans démarrer un glisser de Klay. Dans l'île ouverte, les clics gardent leur rôle (boutons, chat) ; un clic sur Klay le claque (émote agacé), le glisser l'installe sur le bureau ou l'attache à une fenêtre.
6. **Fermeture** : une île ouverte au survol se replie en `compact` 0,6 s après la sortie de la souris ; revenir avant annule. Après un clic dedans, elle se replie une fois la souris sortie, après le délai **Close after** des réglages (15 s par défaut), pour pouvoir écrire dans le chat la souris ailleurs. Une île que l'app ou un raccourci ouvre alors qu'elle était fermée (alerte, fin de session, chat, pastille) n'a aucun minuteur : elle reste ouverte jusqu'au prochain survol suivi d'une sortie, ou jusqu'à un clic ailleurs. Un raccourci sur une île déjà ouverte compte comme un clic dedans. Ce repli après un clic dedans est le seul à minuteur visible : pendant ses 10 dernières secondes (60 % du délai s'il est plus court), un trait de 2 pt en bas au centre (160 pt → 0, blanc 35 %) montre le compte à rebours et l'île se replie quand il atteint zéro. Le trait suit l'échéance que la machine d'états publie (`IslandStateMachine.foldDeadline`) et disparaît dès que le repli est annulé ; il n'existe ni pour le repli au survol, ni pour une île ouverte par l'app, ni quand une demande tient l'île.
7. **Clic hors de l'île ouverte** → l'île se referme (`hidden`), son `close`. Un clic gauche ou droit dans une autre app, ou dans une autre fenêtre de Klayer Island (Réglages, menu), compte ; un clic sur l'île elle-même ou sur Klay posé sur le bureau ne compte pas. Si une autorisation ou une question est en attente, l'île se replie en `compact` : Klay garde son badge et l'île se rouvre au survol sur la demande. Seule une île épinglée avec ⌘P, sans demande en attente, reste ouverte. ⌘P ne protège que des clics ailleurs et d'Échap tapé dans une autre app (règle 8). Il garde aussi la vue à la fin d'une session. La sortie de la souris et le délai **Close after** replient quand même l'île épinglée (règle 6), et ce repli retire l'épingle. Les moniteurs de clic n'existent que tant que l'île est ouverte.
8. **Échap** → comme un clic ailleurs, sauf si la vue qui a le focus le traite d'abord (le détail GitHub, par exemple, se ferme). Tapé dans une autre app, Échap ne ferme pas une île épinglée (autorisation ou question en attente, ⌘P).
9. (Retirée.) Il n'y a plus de masquage après une absence : l'île réduite se cache 60 s après le départ de la souris (règle 2). Le numéro reste pour ne pas casser les renvois.
10. **Alertes** (permission, question, erreur) : l'île s'ouvre seule sur la vue de l'alerte, même sans survol et même cachée. Une autorisation ou une question en attente tient l'île ouverte jusqu'à la réponse, y compris quand elle arrive alors que l'île est déjà ouverte ou pendant le salut de lancement : aucun minuteur ni aucune sortie de la souris ne la replie. Un clic ailleurs, Échap, le raccourci de fermeture ou le saut au terminal la replient seulement en `compact`, avec le badge (règle 7). La demande ne quitte l'île qu'à la réponse, au choix « répondre dans le terminal », ou quand la connexion du hook se ferme ou expire : changer de vue ou replier l'île ne la renvoie jamais au terminal. Tant qu'une demande attend, les autres alertes ne prennent pas sa place dans l'île ouverte ; sinon elles suivent la règle 6 (île ouverte par l'app).
11. **Terminé** : l'île s'ouvre sur la vue `finished` et reste ouverte jusqu'au prochain survol suivi d'une sortie, ou jusqu'à un clic ailleurs.
12. **Plusieurs demandes en même temps** : une carte à la fois. La carte à l'écran ne change jamais pour une demande de l'autre sorte (une question sur une autorisation, ou l'inverse) : celle-ci attend derrière, avec un badge sur sa pastille et le son `approval`. Quand une demande part (réponse, « répondre dans le terminal », traitée ailleurs, expirée), l'île montre l'autre demande en attente, l'autorisation d'abord, sinon la maison (`PendingRequest.after`). Une note « Handled in … » ou « Still waiting in … » reste 3 s, puis laisse la place à la demande en attente, ou replie l'île s'il n'y en a aucune (`PendingRequest.noteEnd`) ; le minuteur d'une note ne touche jamais une note plus récente. Une nouvelle demande de la même sorte remplace la précédente, qui repart dans son terminal ou dans l'app (réponse `ask`). Les boutons d'une carte d'autorisation ou de question restent estompés et inactifs 0,6 s après chaque changement de la demande à l'écran (nouvelle demande, autre carte, ouverture de l'île sur la carte) : un clic visé sur la carte précédente ne répond jamais à la suivante.
13. **Focus** : le gros bonhomme représente la tâche en focus (la dernière alerte, sinon la première qui travaille). Les autres tâches sont les mini-bonhommes. Cliquer un mini-bonhomme le met en focus.

## 4. Animations de l'island

- Ouverture / agrandissement : 520 ms, ressort avec léger dépassement, équivalent `cubic-bezier(.32,1.22,.42,1)`. En SwiftUI, partir de `.spring(response: 0.5, dampingFraction: 0.72)` et ajuster à l'œil contre le prototype.
- Fermeture / rétrécissement : 340 ms, `cubic-bezier(.45,0,.2,1)`, sans dépassement.
- Largeur, hauteur, rayon, position et taille du bonhomme, position et taille des mini-bonhommes animent **ensemble** (effet « élément partagé » : les mini-bonhommes passent des pastilles de la maison à la colonne des autres vues sans disparaître).
- Contenu des vues : sortie 160 ms (opacité 0, flou 8, échelle 0,97) ; entrée 300 ms avec 160 ms de retard (après que le conteneur a commencé à grandir). L'en-tête apparaît avec 300 ms de retard.
- Mini-bonhommes : décalage de 35 ms par index.
- Libellés des pastilles : apparaissent 220 ms après le début du mouvement.
- Au passage en `expanded`, le bonhomme cligne des yeux.
- Sons : `open` à l'ouverture, `close` à la fermeture.

## 5. Vues (mode expanded, largeur 640)

Structure commune : en-tête de 34 pt (onglets à gauche : Vue d'ensemble, Demander, Déposer ; à droite : « N en cours » + bouton son). Contenu inséré de 36 en haut, 10 à gauche, droite, bas. Cartes : rayon 20, fond `#141518`, bord blanc 3,5 %. Dans les vues autres que `overview`, les mini-bonhommes passent en **colonne** à droite (Ø 16, x = largeur − 31, y = 50 + i × 24) et la carte laisse 42 pt à droite.

Voile de couleur des cartes : dégradé radial depuis le bas (120 % × 90 %, centre 50 % / 130 %), couleur de l'état prise dans le même tableau que Klay (`StateColor`, §7) :
`approval` à 42 %, `question` à 38 %, `error` à 55 %, `finished` à 50 %, `dizzy` à 55 % (vue `confused`), `searching` à 50 % (aussi la carte du chat), neutre blanc à 8 %.

| Vue | Hauteur | Bonhomme (x, Ø) | Contenu | Capture |
|---|---|---|---|---|
| `overview` | 220 | 68, 58 | carte gauche 322 de large : maison (conversations en cours, derniers choix), ou carte GitHub ou Spotify ; carte droite : pastilles | 03 |
| `empty` | 160 | 70, 62 | « Rien ne tourne pour l'instant. » + bouton « Demander à Claude » | 16 |
| `approval` | 160 | 62, 56 | projet de la session + « needs permission », bloc code avec la demande (`ApprovalSummary` : la commande d'un Bash ; l'outil et le fichier, relatif au projet, pour Write, Edit, MultiEdit, NotebookEdit, Read ; l'adresse de WebFetch, la requête de WebSearch, le motif et le chemin de Grep et Glob ; « serveur · outil » et un argument court pour un outil MCP ; sinon le JSON compact, coupé à 200 caractères), Refuser, Autoriser, Toujours (estompés 0,6 s, règle 12) | 04 |
| `question` | 160, plus si la question l'exige (`AskQuestion.estimatedIslandHeight`) | 62, 56 | agent + question (1/N) + options en boutons (single-select ou multi-select) + « Reply in terminal » ; bouton Send/Next pour multi-select ou multi-questions ; « Other… » → saisie libre | 05 |
| `error` | 160 | 62, 58 | projet de la session en échec (`failedSession`, comme `finishedSession`) + « Failed », « Claude s'est arrêté sur une erreur », détail en rouge `#FF8D97` sur une ligne : le texte de l'erreur du hook `StopFailure` (`last_assistant_message`, sinon `error_details`, sinon `error`), ou « Aucun détail d'erreur disponible. » ; Ouvrir le terminal (Ouvrir Claude pour une session de l'app Claude) et OK, mêmes règles que la vue `finished` | 06 |
| `finished` | 160 | 62, 58 | agent + résumé, Voir le terminal, OK | 07 |
| `confused` | 160 | 76, 66 | « Trop de claques d'un coup. » | 08 |
| `upload` | 176 | 140, 62 | zone pointillée, Klay les bras ouverts et « Dépose ton fichier » | 09 |
| `uploading` | 176 | sur la barre, Ø 20 | « Envoi de fichier » + %, barre verte, le bonhomme est le curseur de la barre | 10 |
| `choose` | 176 | 60, 52 | « fichier est prêt. », Poser une question, Préparer un email | 11 |
| `mail` | 240 | 56, 46 | brouillon Gmail (§15.2) : champs À, Objet (facultatif) et « Ce que tu veux dire », Préparer le brouillon, Annuler ; puis « Préparation du brouillon… », puis « Brouillon prêt dans Gmail » ou un échec avec Réessayer | 12 |
| `prompt` | 160 | 52, 44 | chat rapide (§15.1) : pastille de contexte, bulles de la conversation, champ + micro + envoyer ; à la place du champ, la marche à suivre quand Claude Code manque ou n'est pas connecté | 13 |
| `note` | 160 | 60, 50 | message court : une erreur du chat, ou « Handled in … » et « Still waiting in … » (3 s, règle 12) | aucune |
| `settings` | 160 | 54, 46 | son et volume, délai **Close after** (10, 15 ou 30 s), état des hooks Claude Code et du chat (Claude Code installé et connecté avec un compte claude.ai ; lu quand la vue s'affiche), « Réglages… » | aucune |

Centre vertical du bonhomme : le centre de la carte de 84 pt sous l'en-tête, soit hauteur / 2 + 21 (101 pour une île de 160, 131 pour la maison), sauf `upload` (104), `uploading` (118) et `choose` (101), fixes.

### Maison (overview)

Carte gauche de 322 pt, Klay à sa gauche, contenu à partir de x = 108 (spec refonte §6) :

1. **Conversations en cours** : une ligne par session (`AppState.sessions`, registre `SessionRoster`), la plus récente activité d'abord, 3 au plus, 26 pt chacune. Mini-Klay de Ø 18 sur un disque de la couleur de son état (`StateColor`, §7), titre (dossier du projet, 12 pt semibold), état en clair (11 pt `#8E939C` : « En attente », « Réfléchit », « Travaille », « Cherche », « Attend ton accord », « Te pose une question », « Limite atteinte », « Erreur », « Terminé »), dernière action sur une ligne (10,5 pt `#6B7079`, tronquée). Sans session : « Aucune conversation en cours. » (12 pt `#8E939C`) ; si les hooks Claude Code manquent dans `~/.claude/settings.json` (`HookServer.claudeHooksInstalled()`, lu quand la maison s'affiche, jamais à chaque rendu), une seconde ligne grise « Hooks Claude Code non installés » (11 pt `#6B7079`) suivie d'un petit bouton « Réglages… » qui ouvre les Réglages sur Agents.
   - Un clic ouvre la session : l'app Claude (`claude://`) pour une session de l'app Claude ; pour une session Claude Code, l'app où elle tourne (terminal ou éditeur, gardée sur sa ligne) si elle est ouverte, sinon l'app Claude.
   - Une ligne finie, en erreur ou au repos part après 30 min sans activité, toute autre après 2 h, jamais une autorisation ni une question en attente. Le ménage se fait à chaque événement et quand la maison s'affiche (ouverture de l'île, retour à la maison), jamais sur minuterie.
2. **Derniers choix** : les 5 dernières autorisations et questions répondues depuis l'île (`AppState.recentChoices`, historique local de 20 entrées), en gris `#9398A1` à 55 % d'opacité, 10 pt, une ligne chacune : « HH:mm · session · demande · réponse ». La demande est coupée en bout de ligne, la réponse reste entière (20 caractères au plus). Sans choix, le bloc n'apparaît pas.
3. **Demande en cours** : une autorisation ou une question en attente a sa vue (`approval`, `question`), qui passe devant la maison.

La maison s'affiche quand la pastille en focus est une pastille Claude (Claude Code, app Claude) ou qu'aucune n'a le focus. Avec GitHub ou Spotify en focus, la carte gauche garde leur carte et son bouton ↗. Hauteur : 220 pt, soit une carte de 168 pt (8 en haut, en-tête de 34, 10 en bas) ; Klay reste centré verticalement sur la carte.

Retirés : pastilles d'éditeurs (VS Code, Cursor), boutons terminal et éditeur, défilé de tâches, cartes de diff et compteurs +N −M. À la fin d'une session (`Stop`), la dernière phrase de l'assistant (`last_assistant_message`, nettoyée du Markdown par `ChatMarkdown.toOneLine`, premier paragraphe utile) devient la dernière action de sa ligne et le texte de la vue `finished`.

### Pastilles (overview)
- 132 × 34, rayon 17, fond couleur de l'agent à 13 %, bord à 32 %, mini-bonhomme Ø 24 centré à 17 pt du bord gauche, libellé 12 pt couleur de l'agent éclaircie de 25 %. Deux colonnes, écart 8, centrées verticalement dans la carte droite (qui commence à x = 342).

### Catalogue de pastilles
Toutes les pastilles déclarées sont définies dans `PillCatalog.all` (source de vérité unique). Trois catégories :

| Catégorie | Titre | Pastilles | Subtitle |
|---|---|---|---|
| `workspace` | Where you code | Claude Code | Integration |
| `agent` | Agents | Claude Desktop | Agent |
| `service` | Services | GitHub, Spotify | Integration |

Couleurs : Claude Desktop `#D97757`. Les éditeurs n'ont plus de pastille : une session Claude Code s'affiche sur la pastille Claude Code, qu'elle tourne dans un terminal ou un éditeur.

Règles :
- **`mainPillId`** vaut `integration_claude` (« Claude Code »), la pastille workspace toujours chargée. Elle ne compte pas dans les 4 places. Le sélecteur Main a disparu avec les pastilles d'éditeurs : une valeur enregistrée qui n'existe plus (`agent_cursor`) revient à Claude Code au lancement, et une pastille retirée sort de `activeIntegrations`.
- Max 4 pastilles autres que `mainPillId` actives à la fois (`activeIntegrations`, persisté).
- `removeTask` sur `mainPillId` ou une pastille déclarée + active → reset à `.idle` + `pillBadge = nil` + nom du catalogue (pas de suppression). Sinon → suppression normale.
- `sortTasksByCatalog` : pastilles du catalogue dans l'ordre du catalogue ; pastilles hors catalogue juste après `integration_claude`.
- Claude Code : ses sessions, lancées dans un éditeur ou un terminal, s'affichent sur cette pastille et dans la maison ; les hooks s'installent dans Réglages → Agents. Claude Desktop : rien à installer. Les pastilles Claude ouvrent la maison, jamais une carte d'état ; seules GitHub et Spotify ont leur carte (`IntegrationCardView`). Les autres agents ne sont plus suivis : leurs événements sont ignorés (pas de pastille) et leurs demandes d'autorisation reçoivent `ask` (voir `docs/AGENTS.md`).

### Carte GitHub (`GitHubPulseCardView`)

Affichée à la place de `GitHubStatsCardView` quand un `GitHubPulse` est disponible (`githubPulse != nil`). Trois lignes `GitHubStatRow` (My PRs, To review, Default branch CI), chacune tappable → ouvre `GitHubDetailView` avec la section correspondante. En-tête : point rouge + « GitHub » + bouton « ★ N.Nk » (étoiles) + rangée de 7 carrés de contribution (7 derniers jours, 7 pt, espacement 2 pt) si `githubActivity != nil` → ouvre la section `.activity`. Sans stats : « Overview ».

### Vue détail GitHub (`GitHubDetailView`)

Remplace la carte principale quand `showingDetail && githubHasPulse`. En-tête : chevron.left (← ferme) + titre de section. Sections **My PRs**, **To review** → `GitHubPRRowView` (point CI + « repo#N » + titre tronqué + badge Draft), ScrollView maxHeight 60 pt (3 lignes × 20 pt), fondu bas si > 3 éléments. Section **Default branch CI** → `GitHubRepoCIRowView` (point CI + nom court + branche + état). Clic sur une PR → ouvre `https://github.com/…` (filtré `host == "github.com"`). Échap ferme.

### Section Activity (`GitHubActivityDetailContent`)

Section `.activity` de `GitHubDetailView`. En-tête : chevron.left + « Activity » à gauche ; à droite (11 pt #8E939C) : « 1,234 past year · N repos » (clic → `github.com/<login>`). Au survol / clic sur un carré : texte remplacé par « Oct 3 · 12 contributions » (ou « 1 contribution », ou « No contributions »). Grille de contributions : colonnes = semaines (la plus ancienne à gauche, carrés de 7 pt, espacement 1,5 pt, nombre de semaines calculé selon la largeur disponible, environ 23), lignes = jours de la semaine (dimanche = ligne 0). Couleurs des niveaux : 0 = blanc 6 %, 1 = `#0E4429`, 2 = `#006D32`, 3 = `#26A641`, 4 = `#39D353`. Pas de ScrollView, `.clipped()`. `refreshActivityIfStale()` à l'apparition.

### Boutons
- Pilule, 12,5 pt medium, fond blanc 9 % (survol 15 %), primaire : fond `#F5F6F8` texte `#0B0C0E`. Appui : échelle 0,94. Aucun raccourci clavier sur les cartes d'autorisation : la réponse se donne au clic (règle 12).

## 6. Couleurs des agents (fixes)

| Agent | Couleur |
|---|---|
| Korus | `#FF6B5B` |
| SBE Hub | `#2DD4A7` |
| klayer.ai | `#3E7280` |
| Autres | prendre dans cet ordre : `#F472B6`, `#34D399`, `#FB923C`, `#60A5FA`, `#E879F9`, puis boucler |

Nom d'une session Claude Code = nom du dossier de travail (`cwd`), avec une table d'alias réglable (ex. `sbe-hub` → « SBE Hub »).

## 7. Le personnage : Klay

Référence de rendu : `tools/klay-preview/src/engine.ts` (portée en Swift dans `KlayerIslandKit`). Unités : unités du glyphe (le glyphe Klayer fait 797 × 512), origine au centre du moyeu (la partie pleine sous les rayons), y vers le bas.

- **Corps** : le glyphe Klayer (`glyph.ts`, généré depuis le SVG du design system), blanc sur l'île sombre, jamais redessiné ni déformé. Il occupe 62 % de la largeur du canvas. Écrasements, inclinaisons, sauts et vrilles s'appliquent au personnage entier.
- **Halo** : dégradé radial de la couleur de l'état derrière les rayons, rayon 380 unités, opacité 0,55 × teinte au centre. Au repos : teal-light Klayer `#3E7280`, teinte 0,35.
- **Couleurs d'état** : variantes éclaircies des couleurs de la marque Klayer, pour rester lisibles sur l'île noire (les valeurs exactes de la charte sont trop sombres sur du noir). Le halo de Klay, son badge, le halo de l'île derrière lui et le voile des cartes d'alerte (§5) prennent la couleur de l'état (tableau ci-dessous, `C` dans `engine.ts`, `StateColor` dans `BotEngine.swift`). Les marques du badge (points, « ! », « ? ») sont teal-deep `#071B20` sur un fond clair (luminance relative au-dessus de 0,2, là où blanc et teal-deep contrastent autant), blanches sinon : tous les états qui ont un badge sont clairs, avec un contraste d'au moins 4,6:1.
- **Yeux** : deux yeux ronds blancs (rayon 52, écart ±56, liseré teal-deep `#071B20` de 9) posés sur le moyeu. La forme d'œil (pilule, arc content, fente, spirale, cœur, étoile…) se dessine dans chaque œil en teal-deep, découpée au bord intérieur du liseré. Le regard (`klayGaze`, `KlayMotion.gaze`, lacet et tangage de −1 à 1, tangage positif vers le haut) décale les blancs de lacet × 48 et tangage × 30, et les pupilles de lacet × 40 et tangage × 32 en plus, bornées dans une ellipse de 26 × 18 pour rester dans le blanc. En tournant, l'œil de ce côté se rétrécit jusqu'à 16 % et l'écart des yeux se resserre jusqu'à 8 % ; les joues suivent les yeux (× 0,8). Les figures scénarisées (accueil, envoi, zone de dépôt) gardent l'ancien décalage (×0,4 et ×0,8 jusqu'à ±14 et ±12).
- **Bras** : nouilles blanches de 26 unités, liseré teal-deep de 7, mains rondes (rayon 26), devant le glyphe pour rester lisibles sur les rayons, sur toutes les surfaces (île, bureau, salut, envoi, zone de dépôt). Épaules à (±82, 50), couvertes d'un disque blanc. La pose des mains dépend de l'état (`limbTargets`) : repos (±168, 150), tape au clavier en `working`, main au menton en `thinking`, les deux mains sur les côtés des jumelles à (±146, −52) en `searching`, qui suivent leur balayage, bras levés en `approval`, grattage de tête en `question`, bras ballants en `error`, `ratelimit` et `sleeping`, V en `finished`, moulinets en `dizzy`. Salut : main droite levée, va-et-vient à 13 rad/s. Zone de dépôt : bras ouverts, mains à (±200, −40) (`armsOpenTargets`).
- **Jumelles** (`searching`, Klay principal seulement : ni mini-Klay ni zone de dépôt), vues un peu d'en haut pour que la longueur des fûts se voie, de 272 de large sur 177 de haut (`BINO`, `KlayPaint.Bino`) :
  - deux fûts teal-deep `#071B20` d'axe x = ±84 : en haut un tube d'oculaire étroit (48 de large, de −142 à −94, rayon d'angle 10) barré d'une bague brume `#ECEDE7` de 8 à y = −128 ; dessous un tube d'objectif plus large (104 de large, de −104 à 0, rayon d'angle 18) terminé par une ellipse de 104 × 44 centrée en y = 0, tournée vers nous ;
  - dans chaque bout d'objectif, un verre teal-light `#3E7280` en ellipse de 80 × 30, liseré brume de 8, et un trait de lumière blanc de 6 (arc d'ellipse de 56 × 18, de 1,08π à 1,42π) ;
  - au centre, une charnière teal-deep de 20 de large (de −138 à −36), un pont de 124 × 18 entre les oculaires (de −124 à −106) et une molette de mise au point de 46 × 26 (rayon 9) centrée en y = −142, barrée de brume ;
  - balayage : décalage x = lacet × 45 et rotation de lacet × 0,13 rad autour de (0, −60), soit ±27 unités et ±0,08 rad pendant la recherche ; les mains tiennent les côtés des tubes d'objectif en (±146, −52) et suivent le même mouvement ;
  - ordre de dessin : jambes, glyphe, jumelles, bras, joues ; les yeux ne sont pas dessinés pendant ce temps. Les jumelles restent quand les membres sont masqués (île compacte).
- **Jambes** : deux jambes blanches derrière le glyphe, hanches à (±17, 104), pieds ovales (32 × 15) à (±36, 212). Piétinement en `working`, tapotement du pied au repos (voir Mouvement).
- **Membres masqués** en dessous de 30 px de largeur de glyphe (île compacte).
- **Boîte aux lettres** (dépôt de fichier) : le glyphe rétrécit et s'efface, une boîte blanche à dégradé brume `#ECEDE7` apparaît avec une fente sombre et les mêmes yeux.
- **Mini-Klay** (pastilles d'agents et de services) : glyphe blanc et yeux sur un disque de la couleur de la pastille, sans membres.
- Regard : suit la souris avec retard. Clignement aléatoire toutes les 2,2 à 5,4 s, double clignement 22 % du temps.

### Mouvement

Constantes partagées par le banc (`motion.ts`, `MOTION`) et le Mac (`KlayMotion.swift`), testées par `scripts/test-klay-motion.sh`. Tableau de parité avec le moteur d'origine : `docs/klay-animation-parity.md`. Tout dépend du temps et de `dt` (secondes), jamais du nombre d'images : les ressorts sont intégrés par tranches de 1/240 s au plus, et `dt` vient de l'horloge du moteur (`CACurrentMediaTime`, plafonné à 0,05 s).

- **Regard** : la cible vient du pointeur, tanh(dx/260) et tanh(dy/200) depuis Klay, passée par la courbe sign(l)·|l|^0,75 puis × 0,62 (lacet) et × 0,5 (tangage). Le regard la rejoint en ressort amorti (réponse 0,2 s, amortissement 0,6).
- **Penché** : toute la figure se tourne vers le regard, plus lentement que les yeux (ressort, réponse 0,6 s, amortissement 0,5). Côté lacet : rotation de 0,06 rad autour des semelles et décalage de 16 unités. Côté tangage : regarder en haut le soulève de 10 unités et l'étire de 2 % depuis les semelles, regarder en bas fait l'inverse. Le glyphe n'est jamais déformé, seule la figure entière bouge.
- **Mains et pieds** : ressorts amortis vers la pose de l'état (mains : réponse 0,22 s, amortissement 0,45 ; pieds : 0,14 s, 0,6). Quand le corps bouge (sauts, secousse, danse, penché, inclinaison), les membres gardent une part de leur place (inertie 0,85 pour les mains, 0,4 pour les pieds) : ils traînent, dépassent puis se posent. Impulsions : écrasement (mains 420 unités/s vers le bas), claque (mains 900 vers le haut et 500 d'un côté, pieds 300), survol (mains 350 vers le haut).
- **Survol** (l'île met `tgEs` à 1,08 quand le pointeur est sur Klay, le bureau aussi) : sursaut (sy 1,07 et sx 0,96 en 110 ms, retour en 280 ms avec rebond), montée de 8 unités vers le pointeur, gain du regard × 2,4.
- **Respiration éveillée** du Klay principal : sy ± 1,2 % à 1,9 rad/s (le sommeil garde ± 3,5 % à 1,8 rad/s).
- **Pointeur immobile** depuis 3,5 à 6 s (`idle`, `working`, `finished`, hors survol) : Klay regarde autour, un coup d'œil toutes les 0,6 à 1,6 s, 30 % vers le pointeur ; le moindre mouvement du pointeur le ramène.
- **Occupations au repos** (`idle` seulement, sans survol, émote, salut, danse ni boîte aux lettres) : toutes les 5 à 12 s, un tapotement du pied (3,3 Hz pendant 0,9 s, pointe levée de 20 unités). Pointeur immobile depuis 25 s : un étirement ou un bâillement en alternance, puis un toutes les 35 à 70 s. Étirement : 1,8 s, mains à (±130, −215), corps étiré de 6 % (sx 0,97), yeux fermés de 0,35 à 1,35 s. Bâillement : l'émote Bâille.
- **Danse** (Spotify) : 112 BPM, saut de 0,2 R, balancement de 0,1 rad et décalage de 0,08 R autour des semelles, écrasement à chaque atterrissage ; montée 0,3 s, descente 0,5 s ; yeux contents en `idle` et `finished`.
- **Cadence** : l'île dessine Klay à la fréquence d'affichage et s'arrête quand elle est cachée ; Klay sur le bureau aussi, 10 images/s endormi, en pause écran éteint ou verrouillé. Toutes les vues de l'île ouverte restent dans l'arbre (opacité 0) : celles qui ne sont pas à l'écran arrêtent leurs animations (mini Klays de la maison, zone de dépôt, barre d'envoi).

### États (`STATES`)

| Clé | Libellé | Couleur | Teinte | Yeux | Badge | Particularité |
|---|---|---|---|---|---|---|
| `idle` | Au repos | `#3E7280` (teal-light) | 0,35 | pilule | aucun | |
| `working` | Travaille | `#4FA3B5` (teal éclairci) | 0,72 | pilule | pilule « ••• » animée | |
| `thinking` | Réfléchit | `#7FB8C4` (teal éclairci) | 0,72 | pilule | « ••• » | regarde en haut à droite |
| `searching` | Cherche | `#A8D0D8` (teal éclairci) | 0,72 | cachés par les jumelles | « ••• » | tient des jumelles à deux mains, qui balaient de gauche à droite (lacet sin(2,6 t) × 0,6), un peu au-dessus de l'horizon (tangage +0,06) ; le corps suit le balayage |
| `approval` | Attend ton feu vert | `#D69A3A` (etat-tension éclairci) | 0,78 | grands | « ! » | petits sauts en boucle |
| `question` | Pose une question | `#E2B866` (etat-tension éclairci) | 0,75 | pilule | « ? » | tête penchée 0,12 rad, se gratte la tête |
| `error` | Erreur | `#D0663F` (brique éclaircie) | 0,78 | plats | point brique | secousse horizontale à l'entrée |
| `finished` | Terminé | `#6FA35E` (etat-tenu éclairci) | 0,5 | contents (arc) | point vert | saut + vrille de 700 ms + écrasement à l'atterrissage + étincelles |
| `ratelimit` | Limite atteinte | `#B0761C` (etat-tension) | 0,72 | fatigués | point ocre | gouttes de sueur |
| `sleeping` | Dort | `#C9CAC3` (filet) | 0,25 | fermés | aucun | respiration, « z » qui montent |
| `dizzy` | Sonné | `#E08A6A` (brique éclaircie) | 0,7 | spirales | aucun | double roulade 1,3 s |

Halo de l'île derrière le bonhomme (`botGlowColor`) : dégradé radial de la couleur de l'état (même tableau), opacité 0,15 au repos et en sommeil, 0 en sonné, 0,65 sinon, flou 6.

Correspondance avec les vrais événements : voir `INTEGRATIONS.md`. `searching` = un `PreToolUse` de Grep, Glob, LS, WebSearch, WebFetch ou d'une commande Bash de recherche (`rg`, `grep`, `find`, `fd`, `ls`, `tree`, `wc` : `BashVerb.searches`) ; le `PostToolUse` qui suit ne baisse pas les jumelles avant 1,5 s (`SessionPhase.searchDwell`, comparaison de dates, sans minuteur), au-delà l'événement suivant décide ; la ligne de la session dit « Cherche ». `sleeping` = aucune tâche depuis 10 min et island ouverte manuellement ; `ratelimit` = limite d'usage signalée par Claude Code.

### Émotes (`EMOTES`) et déclencheurs réels

| Émote | Yeux | Extra | Son | Déclencheur |
|---|---|---|---|---|
| Amour | cœurs `#FF4D6D` | joues à fond, cœurs qui montent | `love` | souris immobile 1,9 s sur le bonhomme |
| Surpris | petits points | saut + yeux agrandis | `pop` | quand vous l'attrapez (glisser) |
| Fier | étoiles `#F7B32B` | étoiles, tête en arrière | `proud` | aucun pour l'instant (la vue de résultat a disparu avec le chat par Claude Code) |
| Clin d'œil | un œil fermé | tête penchée | `wink` | aucun pour l'instant (l'île n'envoie plus de mail) |
| Bâille | fatigués puis fermés | étirement vertical, « z » | `yawn` | juste avant de passer en `sleeping` |
| Content | arcs | joues | aucun | après une décision, un fichier avalé, une réponse du chat finie, un brouillon prêt |
| Agacé | fentes inclinées | halo violet `#A855F7` | `annoyed` | une claque |

## 8. Interactions avec le bonhomme

- **Survol** (expanded) : clignement, yeux ×1,08, son `hover` ; Klay sursaute, lève les mains et se penche vers le pointeur (§7, Mouvement). Immobile 1,9 s → Amour.
- **Clic** en compact ou hidden → rien, l'île ne s'ouvre jamais au clic (§3), sauf le bouton Granola de l'île réduite, qui ouvre Granola. **Clic** en expanded → claque : écrasement (70/130/170 ms), Agacé 800 ms, halo violet, sons `slap` + `annoyed`.
- **3 clics en moins de 1,7 s** → état `dizzy` pendant 3,3 s, vue `confused`, son `dizzy`, puis retour à la vue et à l'état d'avant.
- **Glisser** le bonhomme (> 7 pt) : un bonhomme flottant Ø 54 suit le curseur (Surpris + `pop`), celui du notch disparaît. Lâché sur une fenêtre d'une autre app → **attache** (voir INTEGRATIONS §4). Lâché ailleurs → revient dans le notch en 420 ms en rétrécissant.
- **Glisser un fichier** depuis le Finder vers la zone du notch (±220 pt autour du centre, jusqu'à 26 pt sous l'island) → vue `upload`, le bonhomme se transforme en « bac » (morph 380 ms avec rebond) et regarde le fichier. Contour vert et voile vert quand le fichier est au-dessus.
- **Zone de dépôt** : Klay lui-même, au centre de la carte, remplace le pictogramme et les puces « PDF / Images / Code / Docs ». Il est dessiné de 72 pt de haut, glyphe, yeux `wide`, jambes au repos et bras ouverts, avec « Dépose ton fichier » dessous. Il bouge doucement (va-et-vient vertical de 8 unités, mains qui balancent de 6 unités, clignement toutes les 3,6 s) et regarde le fichier. Il s'efface avec la zone et s'assombrit quand le bac passe devant lui. L'onglet Déposer montre la même figure. Banc : cellule « dépôt » de `tools/klay-preview`.
- **Déposer** : le fichier file dans le bonhomme (360 ms), `gulp` à 330 ms, écrasement + Content, retour à la forme ronde à 950 ms, vue `uploading` (1,2 à 2,1 s, `tick` tous les 10 %, correspond à la copie dans le dossier de travail de l'app), son `approve`, puis vue `choose`.
- Plusieurs fichiers : même flux, libellé « 3 fichiers ».

## 9. Sons

Fichiers `assets/sounds/*.wav` (48 kHz stéréo), rendus depuis le moteur du prototype avec un gain ×6. **Volume par défaut du lecteur : 0,12** pour retrouver le niveau du prototype ; le curseur de volume des réglages va de 0 à 0,2. Jouer avec `AVAudioPlayer` préchargés (latence nulle), plusieurs sons peuvent se superposer. Désactivable dans l'en-tête de l'island et dans les réglages (persisté).

| Événement | Son |
|---|---|
| peek / klayer | `peek` + `greet` |
| ouverture / fermeture | `open` / `close` |
| survol du bonhomme / petit clic UI | `hover` / `blip` |
| claque / agacé / sonné | `slap` / `annoyed` / `dizzy` |
| travaille / réfléchit / cherche | `work` / `think` / `search` |
| permission / question / erreur / limite | `approval` / `question` / `error` / `rate` |
| terminé | `finish` |
| décision validée, upload fini | `approve` |
| fichier avalé / progression | `gulp` / `tick` |
| envoi / attache fenêtre | `send` / `attach` : fichiers gardés parmi les 29, aucun déclencheur dans l'app pour l'instant (l'île n'envoie plus de mail) |
| émotes | `love`, `pop`, `proud`, `wink`, `yawn`, `sleep` |

Pas de son pour les mises à jour silencieuses (lignes des conversations en cours, mini-bonhommes qui changent d'état sauf alerte).

## 10. Barre de menus et réglages

Petit item dans la barre de menus (icône : silhouette du Klay, monochrome). Menu : Ouvrir Klayer Island, Réglages…, Quitter.

Fenêtre Réglages (SwiftUI, simple), sections dans l'ordre d'affichage :
- **Claude Code Hooks** : état des hooks, boutons Installer et Désinstaller. Chacun montre d'abord les entrées du bloc `hooks` qui changent (« - » retirée, « + » ajoutée) et n'écrit qu'après « Confirmer et écrire », avec une sauvegarde datée juste avant. Seules les entrées de Klayer Island sont touchées (INTEGRATIONS §1).
- **Plan usage** : toggle **Show in the notch** + bouton **Install relay** / **Uninstall relay**. Voir INTEGRATIONS §1bis. **Jauge de forfait Claude** : petit pill dans l'en-tête de l'île (vue home uniquement). Activé via `showPlanInNotch` (UserDefaults) + `HookServer.statusLineInstalled()`. Couleur = `ClaudePlanGauge.color(for: dominantPct)`. Clic → `showingPlanDetail` bascule et `ClaudePlanCardView` s'affiche à la place de la carte en cours. `showingPlanDetail` se remet à false au changement de focusId, de vue ou de mode. Grand Klay prend la couleur de l'usage quand `showingPlanDetail == true`.
- **Integrations** : jeton personnel GitHub (Trousseau).
- **Sound** : son on/off, volume.
- **Behavior** : **Close after** N s, le délai du repli après un clic dans l'île (règle 6).
- **Display** : écran de l'island : Screen with the notch (défaut), Main screen (menu bar), Follow the mouse, ou un écran précis par son nom (`NSScreen.localizedName`). Un écran mémorisé mais débranché s'affiche « Saved screen (not connected) ». Voir §1.
- **Active pills** : pastilles actives (Claude Code toujours active + jusqu'à 4 autres), avec pour chacune son interrupteur et sa palette de couleur ; liste par catégorie (voir catalogue §5).
- **Hotkey** : raccourci global pour ouvrir le notch.
- **Startup** : lancer au démarrage (`SMAppService.mainApp`).

### Clic droit sur Klay

Un émote Amour (son `love`). La garde-robe de Coucou n'existe pas dans Klayer Island.

## 11. Jalons

Chaque jalon se termine par build + capture + comparaison aux références + commit (voir CLAUDE.md).

- **M0 Base** : vérifier Xcode (`xcodebuild -version`), XcodeGen, `git init`, `project.yml`, app agent qui se lance et affiche le faux contenu. Menu Debug.
- **M1 Island** : panel, détection du notch, 4 modes, règles §3, clics traversants, animations §4, données factices.
- **M2 Personnage** : port de `Bot` (Klay), tous les états et émotes, mini-bonhommes, halo, badges, particules, mains. Pause quand masqué.
- **M3 Vues** : toutes les vues §5, maison (conversations en cours, derniers choix), pastilles, colonne, élément partagé, voiles. Comparer avec les 16 captures.
- **M4 Sons** : branchement §9, réglages son.
- **M5 Claude Code** : hooks, approbations, questions, saut au terminal (INTEGRATIONS §1).
- **M6 GitHub** : polling, alertes CI, cartes (INTEGRATIONS §1quater).
- **M7 Fichiers** : glisser-déposer, question sur un fichier, brouillon Gmail (INTEGRATIONS §3 et §6).
- **M8 Fenêtres + chat** : attache, titre de la fenêtre, URL, chat par le Claude Code du Mac (INTEGRATIONS §4 et §5).
- **M9 Finition** : réglages complets, lancement au démarrage, écran sans notch, mesure CPU/RAM, passe finale de comparaison visuelle.

## 12. Critères d'acceptation

- Côte à côte avec le prototype, vous ne voyez pas de différence sur le personnage, les couleurs, les timings et les sons.
- Aucun clic perdu à cause de la fenêtre transparente.
- Une session Claude Code n'est jamais bloquée par l'app (app fermée, plantée ou lente → le terminal prend le relais).
- Hidden = 0 % CPU ; compact < 3 % ; mémoire < 100 Mo.

## 13. Klay sur le bureau

Klay peut quitter l'island et vivre comme une icône flottante sur le bureau. Il conserve tout son comportement (émotes, suivi des yeux, danse) et réagit aux alertes.

### Pose et panneau

- **Panneau** : `NSPanel` borderless non-activating, niveau `.floating`, `collectionBehavior [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`, taille 120 × 120 pt.
- **Clics traversants** : `ignoresMouseEvents` activé par défaut ; désactivé à 60 Hz uniquement quand le curseur est sur le corps (rayon ≈ 24 % de la taille du panneau). Position bornée à `screen.visibleFrame` avec une marge de 24 pt.
- Le panneau est toujours au niveau `.floating` : en dessous des panneaux de menu et de l'island, au-dessus des fenêtres normales.

### Installation

- **Depuis le glisser** : quand l'utilisateur lâche Klay hors de la zone notch et hors de toute fenêtre, `IslandWindowController.finishDrag` cède le panneau fantôme au `DesktopKlayController`. Le panneau s'agrandit vers 120 × 120 (animation ressort ~0,25 s), son contenu remplacé par `DesktopBotView`. Son de bienvenue : `pop`. Atterrissage avec émote `happy`.
- **Retour dans la zone notch** : lâcher dans le cadre du panneau island → Klay retourne à la notch sans s'installer sur le bureau.
- **Au démarrage** (si `UserDefaults["klayOnDesktop"] == true`) : le greeting se joue normalement, puis à `greetComplete` un nouveau panneau part de la notch et vole vers la position sauvegardée (animation 0,45 s).

### Interactions

| Geste | Effet |
|---|---|
| Clic simple | Slap (`engine.slap()`), différé de `NSEvent.doubleClickInterval` |
| Double-clic | Annule le slap en attente ; vol vers la notch (`flyHome()`), island réapparaît |
| Clic droit | Émote Amour |
| Survol du corps | Clignement, yeux ×1,08, sursaut, se penche vers le pointeur (§7, Mouvement) |
| Glisser → zone notch | Vol vers la notch (`flyHome()`) |
| Glisser → fenêtre (GitHub) | Attache le contexte, Klay revient à sa position initiale, island ouvre `.prompt` |
| Glisser → ailleurs | Repositionne le panneau (borné au `visibleFrame`) |

### Personnage complet

- Respiration, clignements, suivi des yeux depuis la position du panneau (pas depuis l'island).
- Danse : mêmes règles que le mode compact (Spotify en lecture + pastille active + état autorisé).
- Fréquence d'affichage éveillé, 10 fps endormi (`TimelineView` adapte `minimumInterval` selon `isSleeping`).

### Absences de la notch

Quand `AppState.klayOnDesktop == true`, `BotPlacement` masque le bonhomme de la notch (opacité 0, même règle que `isDraggingBot`).

### Alertes

Détection par `Publishers.CombineLatest($pendingApproval, $pendingQuestion)` : seules les transitions nil↔non-nil déclenchent l'action. La notification `.hookExpand` n'est pas utilisée (elle part aussi pour `.finished`, `.error`, le glisser de fichier, etc.).

1. `pendingApproval` ou `pendingQuestion` passe à non-`nil` → émote `surprised` sur le Klay du bureau.
2. Après 0,45 s, `retractForAlert()` : le panneau vole vers la notch et se ferme ; `klayOnDesktop` passe à `false` (le bonhomme de la notch réapparaît pour l'alerte) ; `UserDefaults["klayOnDesktop"]` reste `true`.
3. Quand `pendingApproval` **et** `pendingQuestion` sont tous deux `nil`, `launchFlyIfNeeded()` renvole Klay vers la position sauvegardée après 0,6 s.
4. Si l'alerte se résout pendant l'animation de retrait, le panneau ne s'ouvre pas sur la notch : Klay repart directement vers le bureau.

### `.finished`

Émote `happy` (saut de joie) sur le Klay du bureau. Détecté par `Publishers.CombineLatest($stateOverride, $tasks)` → `effectiveState` ; ne déclenche pas de retrait vers la notch.

### Sommeil

- 2 min sans activité d'agent ET souris à plus de 150 pt → `engine.setState(.sleeping)`, `TimelineView` passe à 10 fps.
- Réveil à l'approche de la souris ou à la réception d'un événement d'agent.
- Pause complète lors du sommeil écran (`NSWorkspace.screensDidSleepNotification`) ou du verrouillage de session (`com.apple.screenIsLocked`).

### Persistance

- Position et état sauvegardés dans `UserDefaults` (clés : `desktopKlayX`, `desktopKlayY`, `klayOnDesktop`).
- Position bornée au `visibleFrame` du meilleur écran disponible au chargement ; si aucun écran ne convient, coin bas-droit de l'écran principal avec 24 pt de marge.


## 14. Raccourcis clavier

### 14.1 Raccourcis globaux (Carbon `RegisterEventHotKey`)

Ces raccourcis fonctionnent en arrière-plan sans permission Accessibilité.

| Action | Défaut | Clé UserDefaults | Activé par défaut |
|--------|--------|-----------------|-------------------|
| Afficher/masquer l'île (`toggleIsland`) | ⌘⇧N | `hotkeyCode` / `hotkeyFlags` (legacy) | Non |
| Ouvrir le chat (`openChat`) | ⌃⌥Espace | `shortcut.openChat.keyCode` / `.flags` | Oui |
| Aller à l'alerte (`goToAlert`) | ⌃⌥A | `shortcut.goToAlert.keyCode` / `.flags` | Oui |
| Sauter au terminal (`jumpToTerminal`) | ⌃⌥T | `shortcut.jumpToTerminal.keyCode` / `.flags` | Oui |
| Attacher la fenêtre active (`attachFrontWindow`) | ⌃⌥W | `shortcut.attachFrontWindow.keyCode` / `.flags` | Oui |
| Pilule suivante (`nextPill`) | ⌃⌥] | `shortcut.nextPill.keyCode` / `.flags` | Oui |
| Pilule précédente (`prevPill`) | ⌃⌥[ | `shortcut.prevPill.keyCode` / `.flags` | Oui |
| Couper le son (`toggleMute`) | ⌃⌥M | `shortcut.toggleMute.keyCode` / `.flags` | Oui |
| Klay sur le bureau (`toggleDesktopKlay`) | ⌃⌥D | `shortcut.toggleDesktopKlay.keyCode` / `.flags` | Oui |

- Si Carbon ne peut pas enregistrer un raccourci (conflit système), l'action est marquée `.conflict` dans `HotKeyCenter` et un indicateur apparaît dans Réglages → Raccourcis.
- `toggleIsland` conserve les clés UserDefaults historiques (`hotkeyCode`, `hotkeyFlags`, `hotkeyEnabled`) pour ne pas casser les préférences existantes.

### 14.2 Raccourcis locaux (actifs quand l'île a le focus)

Ces raccourcis sont gérés par `NSEvent.addLocalMonitorForEvents`. L'île prend le focus clavier quand elle est ouverte via un raccourci global (jamais au survol ni à l'alerte).

| Raccourci | Action |
|-----------|--------|
| ⌘→ | Pilule suivante |
| ⌘← | Pilule précédente |
| ⌘1…⌘9 | Passe directement à la pilule n° 1–9 |
| ⌘↓ | Descend dans la liste de la carte active |
| ⌘↑ | Monte dans la liste de la carte active |
| ⌘O | Ouvre/développe l'élément sélectionné |
| ⌘↩ | Envoyer le message (vue Prompt) |
| ⌘K | Nouvelle conversation (vue Prompt) |
| ⌘, | Ouvrir les Réglages |
| ⌘P | Épingle ou désépingle l'île ouverte. Épinglée, elle ne résiste qu'aux clics ailleurs et à Échap tapé dans une autre app, et une fin de session garde sa vue ; la sortie de la souris la replie quand même (règles 6 et 7) |

### 14.3 Personnalisation

Réglages → Raccourcis (`ShortcutsSettingsView`) :

- Chaque raccourci global dispose d'un toggle (activer/désactiver) et d'un `ShortcutRecorderButton` pour le reconfigurer.
- Les conflits internes (deux actions avec le même raccourci) sont signalés en rouge.
- Les conflits système (Carbon a refusé l'enregistrement) sont signalés en orange.
- Bouton **Tout réinitialiser** remet les valeurs par défaut sur toutes les actions.
- Les raccourcis locaux sont affichés en lecture seule.


## 15. Chat rapide et brouillon Gmail (lot 4)

Le chat et l'email passent par le Claude Code installé sur le Mac, avec le forfait claude.ai de l'utilisateur. L'île ne stocke ni clé ni jeton pour cela. Détail technique (processus, arguments, environnement) : `INTEGRATIONS.md` §5 et §6. Conception : `docs/superpowers/specs/2026-10-08-klayer-island-refonte-design.md` §7 et §8. Vérification sur Mac : `TEST-MAC.md`, section 4 et spike S3.

**Cadre d'usage.** La lecture des conditions d'Anthropic (spec de conception §7) attend la validation d'un fondateur : l'app ne se diffuse pas à l'équipe avant.

### 15.1 Chat rapide (vue `prompt`)

- **Modèle.** `claude-haiku-5-5`, fixe, sans sélecteur. Pas de recherche web.
- **Aucun outil.** Le chat n'ouvre ni fichier, ni shell, ni page web, ni connecteur : son processus ne charge aucun connecteur et ne démarre aucun serveur MCP, sauf ceux qu'un administrateur impose par `managed-mcp.json`, dont les outils restent retirés. Le seul fichier qu'il lit est celui que l'utilisateur a déposé, dont le contenu est dans le message. Les options de lancement retirent tous les outils ; l'île arrête quand même le processus si un outil apparaît (« Le chat a reçu des outils : arrêt par sécurité. »).
- **Prérequis.** Claude Code installé et connecté avec un compte claude.ai (`claude auth status` affiche `claude.ai`). Sinon, à la place du champ, une phrase grise : « Claude Code n'est pas installé sur ce Mac. » avec « Installer Claude Code » (page d'installation), ou « Connecte Claude Code : ouvre un terminal, lance claude puis /login. ». Le chat reprend dès la réouverture, sans relancer l'île. Le chat ne demande rien à configurer : il n'y a plus de section Chat dans les Réglages.
- **Ce que le message porte.** La question ; avant elle, la fenêtre attachée en texte (app, titre, adresse de l'onglet : jamais une capture) et le fichier déposé :
  - image png, jpg, gif ou webp de 5 Mo au plus ;
  - PDF de 50 Mo au plus, lu en texte et coupé à 200 000 caractères avec une mention ;
  - texte ou code de 200 Ko au plus (txt, md, csv, json, swift, py, js, ts, html, css, xml, yaml, yml) ;
  - tout autre fichier : note « Ce type de fichier n'est pas pris en charge. », le fichier quitte le chat et les questions suivantes partent sans lui. Même sort, avec leur propre phrase, pour un fichier trop gros ou illisible.
- **Réponse.** La bulle se remplit au fil du flux, Klay réfléchit (points de frappe) puis revient au repos avec l'émote Content. Une réponse à la fois : ce qui est tapé pendant une réponse reste dans le champ. ⌘↩ envoie.
- **Conversation.** Un processus `claude` par conversation, arrêté par « Nouvelle conversation » (⌘K, la bulle en cours s'arrête et rien n'arrive ensuite), après 10 minutes sans message, à la fermeture de l'app ou s'il plante. Le message suivant en démarre un autre, qui reçoit les derniers échanges (20 000 caractères au plus) et le contexte : la conversation continue sans trou. L'historique reste en mémoire de l'app.
- **Erreurs.** Une note, Klay en erreur, quand le chat est à l'écran. Si l'utilisateur est passé à une autre vue pendant la réponse, ou si une carte de permission ou de question est arrivée, cette vue reste et Klay cesse seulement de réfléchir ; l'erreur attend dans la conversation, dans la bulle de réponse, et n'est jamais renvoyée à Claude comme une de ses réponses. Les erreurs connues de Claude Code (connexion, limite d'usage, trop de demandes, serveurs surchargés, nombre d'étapes) sont dites en français ; le reste passe tel quel.
- **Invisible des hooks.** Le processus du chat ne crée ni pastille, ni ligne de session, ni carte d'autorisation.

### 15.2 Email : un brouillon Gmail (vue `mail`)

- **Principe.** « Préparer un email » (sur le fichier déposé) ne passe plus par Mail.app. Klay crée un brouillon dans le Gmail de l'utilisateur, par le connecteur Gmail de son compte Claude. **L'île n'envoie jamais rien** : l'utilisateur relit le brouillon dans Gmail, y ajoute la pièce jointe et l'envoie lui-même.
- **Formulaire.** « À » (une ou plusieurs adresses simples, séparées par des virgules ; une ligne rouge nomme celles qui sont invalides), « Objet » (facultatif), « Ce que tu veux dire » (obligatoire). « Préparer le brouillon » est atténué tant que le formulaire ne tient pas. « avec <fichier> » rappelle le fichier déposé. Même carte et mêmes composants que l'ancienne vue d'envoi : seul son contenu change.
- **Préparation.** « Préparation du brouillon… » avec « Annuler », Klay réfléchit. Une carte de permission ou de question qui arrive pendant la préparation reprend la pose de sa demande, comme pendant une réponse du chat. 90 s au plus. Un seul brouillon à la fois. L'île peut se replier pendant la préparation : le résultat attend à sa réouverture.
- **Résultat.**
  - Brouillon prêt (voile vert) : « Brouillon prêt dans Gmail », l'objet et les 3 premières lignes, « Ouvrir dans Gmail » (adresse `https://mail.google.com` seulement), « Montrer le fichier » (le fichier dans le Finder) et la phrase « Glisse le fichier dans le brouillon pour le joindre. ». Klay fait l'émote Content. Le formulaire est vide pour le prochain.
  - Gmail absent : « Gmail n'est pas connecté à ton compte Claude. Ajoute le connecteur Gmail sur claude.ai, puis réessaie. » avec « Réessayer ».
  - Échec (voile rouge) : le message (4 lignes au plus) avec « Réessayer », qui rend le formulaire tel que l'utilisateur l'a laissé.
- **Pièce jointe.** Claude ne joint jamais le fichier et ne le voit pas : seul son nom est dans la demande. L'utilisateur le glisse dans le brouillon.
- **Garde-fous.** Le brouillon n'a qu'un outil : la création de brouillon Gmail. L'envoi, la réponse, le transfert, la modification et la suppression sont refusés par leur nom, et le mode `dontAsk` (refuser ce qui demanderait une autorisation) doit refuser les autres outils. Si le processus appelle un autre outil (seuls `ToolSearch` et `WaitForMcpServers`, qui chargent ou attendent les outils de Claude Code, passent), ou crée un brouillon qui diffère de la demande (autres destinataires, copie, pièce jointe, version HTML), ou plusieurs brouillons, l'île l'arrête et le dit (`INTEGRATIONS.md` §6). Seules les options refusent. L'arrêt par l'île est une seconde barrière, qui arrive après la décision de la CLI ; la consigne ne fait que recommander.
- **Claude Code absent ou non connecté.** La carte reprend les phrases du chat, avec « Installer Claude Code » et « Annuler ».
- **Permission macOS.** Plus d'automatisation de Mail.

### 15.3 Ce que le lot 4 retire

- La clé API Anthropic (Trousseau, `anthropic-api-key`), le sélecteur de modèle (`claudeModel`) et la section Réglages « Anthropic API » ; le fournisseur de chat et son code (`ChatProvider`), la recherche web, les vues `searching` et `result`.
- L'envoi par Mail.app (AppleScript) et la note « Email sent to … ».
- Au premier lancement de cette build, l'app supprime une fois la clé Anthropic du Trousseau et le réglage `claudeModel` (deuxième étape de `RemovedFeatureCleanup`, `removedFeatureCleanupVersion` à 2). Le jeton GitHub reste.

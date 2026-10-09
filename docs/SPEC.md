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
13. **Focus** : le gros bonhomme représente la tâche en focus (la dernière alerte, sinon la première qui travaille). Depuis le lot 6, la maison n'affiche plus de pastilles : les sessions sont des lignes (un clic ouvre la session), et seules les icônes Spotify et GitHub de la bande d'icônes mettent leur pastille en focus (§5, Maison).

## 4. Animations de l'island

- Ouverture / agrandissement : 520 ms, ressort avec léger dépassement, équivalent `cubic-bezier(.32,1.22,.42,1)`. En SwiftUI, partir de `.spring(response: 0.5, dampingFraction: 0.72)` et ajuster à l'œil contre le prototype.
- Fermeture / rétrécissement : 340 ms, `cubic-bezier(.45,0,.2,1)`, sans dépassement.
- Largeur, hauteur, rayon, position et taille du bonhomme animent **ensemble**. Depuis le lot 6, la maison n'a plus de pastilles et aucune vue n'a de colonne de mini-bonhommes : les seuls mini-bonhommes sont ceux des lignes de la maison.
- Contenu des vues : sortie 160 ms (opacité 0, flou 8, échelle 0,97) ; entrée 300 ms avec 160 ms de retard (après que le conteneur a commencé à grandir). L'en-tête apparaît avec 300 ms de retard.
- Au passage en `expanded`, le bonhomme cligne des yeux.
- Sons : `open` à l'ouverture, `close` à la fermeture.

## 5. Vues (mode expanded, largeur 640)

Structure commune : en-tête de 34 pt (onglets à gauche : Vue d'ensemble, Demander, Déposer ; à droite : « N en cours » + bouton son + bouton Quitter, symbole `power`, 14 pt, `#8E939C`, infobulle « Quitter Klayer Island », qui quitte l'app sans confirmation comme le menu de la barre). L'onglet maison porte le badge des alertes de l'app Claude non vues (§5, Bande d'icônes). Contenu inséré de 36 en haut, 10 à gauche, droite, bas. Cartes : rayon 20, fond `#141518`, bord blanc 3,5 %.

Voile de couleur des cartes : dégradé radial depuis le bas (120 % × 90 %, centre 50 % / 130 %), couleur de l'état prise dans le même tableau que Klay (`StateColor`, §7) :
`approval` à 42 %, `question` à 38 %, `error` à 55 %, `finished` à 50 %, `dizzy` à 55 % (vue `confused`), `searching` à 50 % (aussi la carte du chat), neutre blanc à 8 %.

| Vue | Hauteur | Bonhomme (x, Ø) | Contenu | Capture |
|---|---|---|---|---|
| `overview` | 220 | 96, 58 | bande d'icônes (36 pt), puis une carte : Klay dans sa colonne (100 pt) et la liste (484 pt) des sessions en cours, des sessions finies du jour et des 3 derniers choix, ou la carte GitHub ou Spotify à la place de la liste (voir Maison) | 03 |
| `empty` | 160 | 70, 62 | « Rien ne tourne pour l'instant. » + bouton « Demander à Claude » | 16 |
| `approval` | 160 | 62, 56 | projet de la session + « needs permission », bloc code avec la demande (`ApprovalSummary` : la commande d'un Bash ; l'outil et le fichier, relatif au projet, pour Write, Edit, MultiEdit, NotebookEdit, Read ; l'adresse de WebFetch, la requête de WebSearch, le motif et le chemin de Grep et Glob ; « serveur · outil » et un argument court pour un outil MCP ; sinon le JSON compact, coupé à 200 caractères), Refuser, Autoriser, Toujours (estompés 0,6 s, règle 12) | 04 |
| `question` | 160, plus si la question l'exige (`AskQuestion.estimatedIslandHeight`) | 62, 56 | agent + question (1/N) + options en boutons (single-select ou multi-select) + « Reply in terminal » ; bouton Send/Next pour multi-select ou multi-questions ; « Other… » → saisie libre | 05 |
| `error` | 160 | 62, 58 | projet de la session en échec (`failedSession`, comme `finishedSession`) + « Failed », « Claude s'est arrêté sur une erreur », détail en rouge `#FF8D97` sur une ligne : le texte de l'erreur du hook `StopFailure` (`last_assistant_message`, sinon `error_details`, sinon `error`), ou « Aucun détail d'erreur disponible. » ; Ouvrir le terminal (Ouvrir Claude pour une session de l'app Claude) et OK, mêmes règles que la vue `finished` | 06 |
| `finished` | 160 | 62, 58 | agent + résumé, Voir le terminal, OK | 07 |
| `confused` | 160 | 76, 66 | « Trop de claques d'un coup. » | 08 |
| `upload` | 176 | 320, 62 | zone pointillée, Klay au milieu de la carte (y 92) et « Dépose ton fichier » dessous ; un fichier qui approche : la zone de dépôt prend le relais (§8) | 09 |
| `uploading` | 176 | sur la barre, Ø 20 | « Envoi de fichier » + %, barre verte, le bonhomme est le curseur de la barre | 10 |
| `choose` | 176 | 60, 52 | « fichier est prêt. », Poser une question, Préparer un email | 11 |
| `mail` | 240 | 56, 46 | brouillon Gmail (§15.2) : champs À, Objet (facultatif) et « Ce que tu veux dire », Préparer le brouillon, Annuler ; puis « Préparation du brouillon… », puis « Brouillon prêt dans Gmail » ou un échec avec Réessayer | 12 |
| `prompt` | 160 | 52, 44 | chat rapide (§15.1) : pastille de contexte quand un acte explicite en a posé une, bulles de la conversation, champ + micro + envoyer ; à la place du champ, la marche à suivre quand Claude Code manque ou n'est pas connecté | 13 |
| `note` | 160 | 60, 50 | message court : une erreur du chat, ou « Handled in … » et « Still waiting in … » (3 s, règle 12) ; ou une demande de l'app Claude (§16) : titre, ligne, « Ouvrir Claude » et OK | aucune |
| `settings` | 160 | 54, 46 | son et volume, délai **Close after** (10, 15 ou 30 s), état des hooks Claude Code et du chat (Claude Code installé et connecté avec un compte claude.ai ; lu quand la vue s'affiche), « Réglages… » | aucune |

Centre vertical du bonhomme : le centre de la carte de 84 pt sous l'en-tête, soit hauteur / 2 + 21 (101 pour une île de 160, 131 pour la maison), sauf `upload` (92), `uploading` (118) et `choose` (101), fixes.

### Maison (overview)

De gauche à droite, sur 640 pt (`HomeLayout`, testé par `scripts/test-home-layout.sh`) : le bord de 10 pt, la **bande d'icônes** (36 pt) sur le noir de l'île, puis une carte qui porte **Klay** dans sa colonne de 100 pt (centre x = 96, Ø 58 : le cercle de son canvas, où un clic le claque, ne touche ni les icônes ni les lignes) et la **liste** (484 pt à partir de x = 146, au moins les 3/4 de l'île), puis le bord de 10 pt. La bande garde sa largeur quelles que soient ses icônes. Hauteur : 220 pt, soit une carte de 168 pt (8 en haut, en-tête de 34, 10 en bas) ; Klay reste centré verticalement sur la carte.

La liste défile dans la carte, sans barre, et ne la fait jamais grandir : rebond seulement si elle dépasse, et la dernière ligne visible s'estompe tant qu'il en reste dessous. De haut en bas :

1. **Sessions en cours** (`AppState.sessions`, registre `SessionRoster`, ordre `SessionRoster.listed`) : toutes, la plus récente activité d'abord, 26 pt chacune. Mini-Klay de Ø 18 sur un disque de la couleur de son état (`StateColor`, §7), titre (le nom de la session, sinon le dossier du projet, 12 pt semibold, coupé par « … »), état en clair (11 pt `#8E939C` : « En attente », « Réfléchit », « Travaille », « Cherche », « Attend ton accord », « Te pose une question », « Limite atteinte »), dernière action sur une ligne (10,5 pt `#6B7079`, tronquée).
2. **Sessions finies du jour** : les lignes `finished` et `error`, la fin la plus récente d'abord, en gris : titre `#8E939C`, « Terminé à HH:mm » ou « Erreur à HH:mm » en `#6B7079` (l'heure de la fin sur 24 h, dans le fuseau de l'utilisateur), mini-Klay gris (saturation 0, opacité 60 %) dessiné une fois dans la pose de sa fin, sans animation. 10 au plus.
   - Nom d'une session (`SessionName`, règles pures dans `SessionRoster.name`, testées par `scripts/test-session-roster.sh`) : celui de la liste des sessions de VS Code et de l'onglet Code de l'app Claude, pour toute session Claude Code, terminal compris. Deux sources : le titre personnalisé que porte un hook (`session_title` de `SessionStart` et `UserPromptSubmit`, présent quand la session a été nommée par `--name`, `/rename` ou un renommage dans l'app Claude ou VS Code) et le `session_name` de la ligne d'état (le titre personnalisé, sinon celui que Claude a généré ; le relais `nb-hook --statusline` le transmet, coupé à 120 caractères). Le nom le plus récent l'emporte, quelle que soit sa source : la ligne d'état porte le titre personnalisé dès qu'il est donné, elle n'est donc jamais en retard sur le hook. Pour un renommage, l'ordre d'arrivée des deux relais n'est pas garanti : au pis l'ancien nom reste jusqu'à la ligne d'état ou au message suivants, qui portent le même. Sans nom, le dossier ; un nom vide, blanc ou qui n'est pas du texte ne remplace jamais un nom connu. Un nom arrivé avant la ligne de sa session lui est donné quand elle apparaît (gardé 30 min) ; les noms partent avec leur ligne (`end`, `prune`). Le nom ne déplace pas la ligne et ne change ni sa date ni sa dernière action. Il titre aussi, sur une ligne coupée par « … » (`AgentWho`), la vue `finished` ou `error` de la session, la carte d'autorisation, l'entrée des derniers choix et la ligne de la note de l'onglet Code (§16.1). Il reste en mémoire avec la ligne et n'est envoyé nulle part ; `nb.log` dit qu'un nom est arrivé, jamais lequel. Seule l'entrée des derniers choix d'une demande répondue depuis l'île le garde, dans l'historique local `choices.json` (20 entrées), comme elle gardait le dossier. Le transcript de la session n'est jamais lu (format interne). Cowork : rien de documenté ne donne à une app du Mac le nom d'une tâche, l'île ne nomme pas les tâches Cowork.
   - Sans aucune session : « Aucune conversation en cours. » (12 pt `#8E939C`) ; si les hooks Claude Code manquent dans `~/.claude/settings.json` (`HookServer.claudeHooksInstalled()`, lu quand la maison s'affiche, jamais à chaque rendu), une seconde ligne grise « Hooks Claude Code non installés » (11 pt `#6B7079`) suivie d'un petit bouton « Réglages… » qui ouvre les Réglages sur Agents.
   - Un clic ouvre la session : l'app Claude (`claude://`) pour une session de l'app Claude ; pour une session Claude Code, l'app où elle tourne (terminal ou éditeur, gardée sur sa ligne) si elle est ouverte, sinon l'app Claude.
   - Ménage (`SessionRoster.prune`) : une ligne finie ou en erreur reste jusqu'à minuit du jour de sa fin, dans le calendrier de l'utilisateur (changements d'heure compris), et seules les 10 fins les plus récentes restent ; une ligne au repos (`idle`) part après 30 min sans activité, une ligne au travail (`thinking`, `working`, `searching`, `ratelimit`) après 2 h ; jamais une autorisation ni une question en attente. `SessionEnd` retire la ligne, sauf une ligne finie ou en erreur : quitter Claude Code après une réponse est la fin normale d'une session, elle reste dans l'historique du jour. Le ménage se fait à chaque événement, quand la maison s'affiche (ouverture de l'île, retour à la maison) et avant ⌃⌥T, jamais sur minuterie : une île laissée ouverte sur la maison au passage de minuit garde les lignes de la veille jusqu'au prochain événement ou à la prochaine ouverture.
3. **Derniers choix** : les 3 dernières autorisations et questions répondues depuis l'île (`AppState.recentChoices`, `ChoiceHistoryView.limit`, historique local de 20 entrées), en gris `#9398A1` à 55 % d'opacité, 10 pt, une ligne chacune : « HH:mm · session · demande · réponse ». La demande est coupée en bout de ligne, la réponse reste entière (20 caractères au plus). Sans choix, le bloc n'apparaît pas.
4. **Demande en cours** : une autorisation ou une question en attente a sa vue (`approval`, `question`), qui passe devant la maison.

La liste s'affiche sauf quand GitHub ou Spotify a le focus (`HomeRail.showsCard`) : leur carte existante prend alors sa place, dans une bande de 98 pt centrée dans la carte, avec son bouton ↗, décalée de 8 pt à gauche pour que son texte commence là où commencent les lignes (`HomeLayout.serviceCardShift`). Même bande et même décalage pour la carte de forfait.

Retirés : pastilles d'éditeurs (VS Code, Cursor), boutons terminal et éditeur, défilé de tâches, cartes de diff et compteurs +N −M, et depuis le lot 6 les pastilles de la maison. À la fin d'une session (`Stop`), la dernière phrase de l'assistant (`last_assistant_message`, nettoyée du Markdown par `ChatMarkdown.toOneLine`, premier paragraphe utile) devient la dernière action de sa ligne et le texte de la vue `finished`.

### Bande d'icônes (overview)

- Icônes, de haut en bas, une par rangée de 26 pt alignée sur les lignes, sous l'onglet maison (`HomeRail.icons`, `AppState.homeRailIcons`) : Spotify (sa pastille active), GitHub (sa pastille active et un jeton réglé), Granola (toujours). Symboles neutres `music.note`, `arrow.triangle.pull` et `mic` (aucun logo repris), 13 pt, `#8E939C` à 45 % comme le bouton Granola de l'île réduite, `#B0B5BE` au survol, `#F5F6F8` sur une capsule `#1D1F23` pour l'icône dont la carte est à l'écran. Spotify en lecture teinte sa note en vert à 70 %. Le badge d'alerte d'une pastille (CI GitHub en échec ou réussie, revue demandée) passe sur son icône, à 75 %.
- Infobulles : « Spotify », « GitHub », « Nouvelle note Granola », et « Retour aux conversations » sur l'icône dont la carte est affichée.
- Clic (`HomeRail.action`) : Spotify ou GitHub met sa pastille en focus et sa carte à la place de la liste (`AppState.showCard`, qui retient la pastille d'avant) ; un second clic sur la même icône, ou l'onglet maison de l'en-tête, rend la liste et le focus d'avant (`AppState.showHomeList`). Granola ouvre une nouvelle note (`GranolaLink`), la maison reste. Une autorisation ou une question qui part rend la liste, pas la carte (`HomeRail.focusAfterRequest`).
- Les pastilles Claude Code et Claude Desktop n'ont pas d'icône : leurs sessions sont la liste. Leurs identifiants restent pour le routage, la pose de Klay et les cartes. Le badge que la pastille de l'app Claude reçoit quand l'île sert à autre chose (une fin, une erreur, une demande derrière une carte), et celui d'une alerte de l'app Claude retenue (§16.1), passent sur l'onglet maison de l'en-tête : même badge, même taille (75 %) et même place que sur les icônes de la bande, le plus fort des deux (demande, puis erreur, puis fin ; `ClaudeAppAlertHold.houseBadge`). Il part quand la liste est à l'écran ou quand le badge de la pastille de l'app Claude s'efface (badge de la pastille), quand l'alerte retenue s'affiche ou tombe, et quand l'app Claude passe au premier plan. Un clic sur l'onglet maison montre l'alerte retenue à la place de la maison. Le badge de la pastille Claude Code (terminal, éditeur) ne s'affiche nulle part : seuls le son et la ligne de la session le disent.

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
- Claude Code : ses sessions, lancées dans un éditeur ou un terminal, sont routées sur cette pastille et s'affichent dans la maison ; les hooks s'installent dans Réglages → Agents. Claude Desktop : rien à installer. Les pastilles Claude ouvrent la maison, jamais une carte d'état ; seules GitHub et Spotify ont leur carte (`IntegrationCardView`). Les autres agents ne sont plus suivis : leurs événements sont ignorés (pas de pastille) et leurs demandes d'autorisation reçoivent `ask` (voir `docs/AGENTS.md`).

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

Nom d'une session Claude Code = son nom quand l'île le connaît (§5, Maison, « Nom d'une session »), sinon le nom du dossier de travail (`cwd`), avec une table d'alias réglable (ex. `sbe-hub` → « SBE Hub »).

## 7. Le personnage : Klay

Référence de rendu : `tools/klay-preview/src/engine.ts` (portée en Swift dans `KlayerIslandKit`). Unités : unités du glyphe (le glyphe Klayer fait 797 × 512), origine au centre du moyeu (la partie pleine sous les rayons), y vers le bas.

- **Corps** : le glyphe Klayer (`glyph.ts`, généré depuis le SVG du design system), blanc sur l'île sombre, jamais redessiné ni déformé. Il occupe 62 % de la largeur du canvas. Écrasements, inclinaisons, sauts et vrilles s'appliquent au personnage entier.
- **Halo** : dégradé radial de la couleur de l'état derrière les rayons, rayon 380 unités, opacité 0,55 × teinte au centre. Au repos : teal-light Klayer `#3E7280`, teinte 0,35.
- **Couleurs d'état** : variantes éclaircies des couleurs de la marque Klayer, pour rester lisibles sur l'île noire (les valeurs exactes de la charte sont trop sombres sur du noir). Le halo de Klay, son badge, le halo de l'île derrière lui et le voile des cartes d'alerte (§5) prennent la couleur de l'état (tableau ci-dessous, `C` dans `engine.ts`, `StateColor` dans `BotEngine.swift`). Les marques du badge (points, « ! », « ? ») sont teal-deep `#071B20` sur un fond clair (luminance relative au-dessus de 0,2, là où blanc et teal-deep contrastent autant), blanches sinon : tous les états qui ont un badge sont clairs, avec un contraste d'au moins 4,6:1.
- **Yeux** : deux yeux ronds blancs (rayon 52, écart ±56, liseré teal-deep `#071B20` de 9) posés sur le moyeu. La forme d'œil (pilule, arc content, fente, spirale, cœur, étoile…) se dessine dans chaque œil en teal-deep, découpée au bord intérieur du liseré. Le regard (`klayGaze`, `KlayMotion.gaze`, lacet et tangage de −1 à 1, tangage positif vers le haut) décale les blancs de lacet × 48 et tangage × 30, et les pupilles de lacet × 40 et tangage × 32 en plus, bornées dans une ellipse de 26 × 18 pour rester dans le blanc. En tournant, l'œil de ce côté se rétrécit jusqu'à 16 % et l'écart des yeux se resserre jusqu'à 8 % ; les joues suivent les yeux (× 0,8). Le salut de lancement garde l'ancien décalage (×0,4 et ×0,8 jusqu'à ±14 et ±12). Le Klay de la zone de dépôt et de l'envoi suit la règle du regard du Klay de l'île (`KlayMotion.gaze`, sans son ressort), pour que ses yeux ne changent pas quand il prend le relais (§8).
- **Bras** : nouilles blanches de 26 unités, liseré teal-deep de 7, mains rondes (rayon 26), devant le glyphe pour rester lisibles sur les rayons, sur toutes les surfaces (île, bureau, salut, envoi, zone de dépôt). Épaules à (±82, 50), couvertes d'un disque blanc. La pose des mains dépend de l'état (`limbTargets`) : repos (±168, 150), tape au clavier en `working`, main au menton en `thinking`, les deux mains sur les côtés des jumelles à (±146, −6) en `searching`, qui suivent leur balayage, bras levés en `approval`, grattage de tête en `question`, bras ballants en `error`, `ratelimit` et `sleeping`, V en `finished`, moulinets en `dizzy`. Salut : main droite levée, va-et-vient à 13 rad/s. Zone de dépôt : bras ouverts, mains à (±200, −40) (`armsOpenTargets`).
- **Jumelles** (`searching`, Klay principal seulement : ni mini-Klay ni zone de dépôt), vues de face et ajustées autour des yeux, de 278 de large sur 182 de haut (`BINO`, `KlayPaint.Bino`) :
  - sur chaque œil (centre (±56, −6)), un verre rond de rayon 64 où l'œil et son liseré tiennent, un liseré brume `#ECEDE7` de 7, puis un anneau teal-deep `#071B20` de 12 ;
  - les deux anneaux se rejoignent sur l'arête du nez en une seule forme teal-deep : entre les verres, une cloison teal-deep de 12 de large bordée de brume (chaque verre s'arrête à x = ±13) ; au-dessus, un pont court de 56 × 24 (de −84 à −60) et la molette de mise au point de 46 × 26 (rayon 9) centrée en y = −92, barrée de brume ;
  - dans chaque verre, l'œil de Klay grossi : l'œil entier (blanc, liseré, pupille) à l'échelle 1,3 autour du centre du verre, découpé au verre. Les pupilles suivent le regard comme hors des jumelles (décalage des pupilles de `klayGaze` ; les yeux restent au centre des verres) et les clignements se voient. Par-dessus l'œil, un voile teal-light `#3E7280` au bord du verre (dégradé radial, transparent jusqu'à 62 % du rayon, opacité 0,75 au bord) et un trait de lumière blanc de 7 (arc de rayon 52, de 1,1π à 1,4π) ;
  - balayage : décalage x = lacet × 12 et rotation de lacet × 0,08 rad autour de (0, −6), soit ±7 unités et ±0,05 rad pendant la recherche ; les yeux grossis bougent avec les verres ; les mains tiennent les côtés extérieurs des verres en (±146, −6) et suivent le même mouvement ;
  - ordre de dessin : jambes, glyphe, bras, jumelles avec les yeux, puis les mains par-dessus (les bras redessinés dans un disque de rayon 40 autour de chaque main, sans couture au poignet) : les bras passent derrière les jumelles, qui couvrent aussi les joues. Les jumelles restent quand les membres sont masqués (île compacte).
- **Jambes** : deux jambes blanches derrière le glyphe, hanches à (±17, 104), pieds ovales (32 × 15) à (±36, 212). Piétinement en `working`, tapotement du pied au repos (voir Mouvement).
- **Marche** (retour à l'île, §13 ; `KlayWalk.gait` et `KlayPaint.walkLimbs`, `walkGait` et `walkTargets` sur le banc, cellules « marche ») : une démarche vue de face, lisible à la taille du Klay flottant du glisser. Phase de foulée de 0 à 1 (deux pas) : le pied gauche se lève dans la première moitié, le droit dans la seconde, jamais les deux à la fois. Le pied levé monte jusqu'à 72 unités et avance de 20 vers où Klay marche ; l'autre, au sol, recule de 10. Le corps descend de 20 unités à chaque appui (phases 0 et ½) et remonte d'autant à mi-pas (¼ et ¾) ; les pieds au sol restent en place pendant ce mouvement. La main opposée au pied levé vient vers l'avant : 34 unités vers le milieu et 80 vers le haut ; l'autre recule, 14 vers l'extérieur et 20 vers le haut. Klay se penche de 0,08 rad vers où il marche, autour des semelles, et regarde vers l'île. Toute l'amplitude suit la vitesse : à l'arrêt, c'est la pose de repos. Ni coup d'œil ni occupation pendant la marche. Le glyphe n'est ni déformé ni recoloré.
- **Membres masqués** en dessous de 30 px de largeur de glyphe (île compacte).
- **Zone de dépôt** : Klay reste Klay, le glyphe intact (plus de boîte aux lettres depuis le lot 6) ; ses bras s'ouvrent pour le fichier (`KlayPaint.dropLimbs`) et il l'avale (§8).
- **Mini-Klay** (lignes des conversations de la maison) : glyphe blanc et yeux sur un disque de la couleur de l'état de la session, sans membres ; gris et immobile pour une session finie ou en erreur (§5, Maison).
- Regard : suit la souris avec retard. Clignement aléatoire toutes les 2,2 à 5,4 s, double clignement 22 % du temps.

### Mouvement

Constantes partagées par le banc (`motion.ts`, `MOTION`) et le Mac (`KlayMotion.swift`), testées par `scripts/test-klay-motion.sh`. Tableau de parité avec le moteur d'origine : `docs/klay-animation-parity.md`. Tout dépend du temps et de `dt` (secondes), jamais du nombre d'images : les ressorts sont intégrés par tranches de 1/240 s au plus, et `dt` vient de l'horloge du moteur (`CACurrentMediaTime`, plafonné à 0,05 s).

- **Regard** : la cible vient du pointeur, tanh(dx/260) et tanh(dy/200) depuis Klay, passée par la courbe sign(l)·|l|^0,75 puis × 0,62 (lacet) et × 0,5 (tangage). Le regard la rejoint en ressort amorti (réponse 0,2 s, amortissement 0,6).
- **Penché** : toute la figure se tourne vers le regard, plus lentement que les yeux (ressort, réponse 0,6 s, amortissement 0,5). Côté lacet : rotation de 0,06 rad autour des semelles et décalage de 16 unités. Côté tangage : regarder en haut le soulève de 10 unités et l'étire de 2 % depuis les semelles, regarder en bas fait l'inverse. Le glyphe n'est jamais déformé, seule la figure entière bouge.
- **Mains et pieds** : ressorts amortis vers la pose de l'état (mains : réponse 0,22 s, amortissement 0,45 ; pieds : 0,14 s, 0,6). Quand le corps bouge (sauts, secousse, danse, penché, inclinaison), les membres gardent une part de leur place (inertie 0,85 pour les mains, 0,4 pour les pieds) : ils traînent, dépassent puis se posent. Impulsions : écrasement (mains 420 unités/s vers le bas), claque (mains 900 vers le haut et 500 d'un côté, pieds 300), survol (mains 350 vers le haut).
- **Survol** (l'île met `tgEs` à 1,08 quand le pointeur est sur Klay, le bureau aussi) : sursaut (sy 1,07 et sx 0,96 en 110 ms, retour en 280 ms avec rebond), montée de 8 unités vers le pointeur, gain du regard × 2,4.
- **Respiration éveillée** du Klay principal : sy ± 1,2 % à 1,9 rad/s (le sommeil garde ± 3,5 % à 1,8 rad/s).
- **Pointeur immobile** depuis 3,5 à 6 s (`idle`, `working`, `finished`, hors survol) : Klay regarde autour, un coup d'œil toutes les 0,6 à 1,6 s, 30 % vers le pointeur ; le moindre mouvement du pointeur le ramène.
- **Occupations au repos** (`idle` seulement, sans survol, émote, salut ni danse) : toutes les 5 à 12 s, un tapotement du pied (3,3 Hz pendant 0,9 s, pointe levée de 20 unités). Pointeur immobile depuis 25 s : un étirement ou un bâillement en alternance, puis un toutes les 35 à 70 s. Étirement : 1,8 s, mains à (±130, −215), corps étiré de 6 % (sx 0,97), yeux fermés de 0,35 à 1,35 s. Bâillement : l'émote Bâille.
- **Danse** (Spotify) : 112 BPM, saut de 0,2 R, balancement de 0,1 rad et décalage de 0,08 R autour des semelles, écrasement à chaque atterrissage ; montée 0,3 s, descente 0,5 s ; yeux contents en `idle` et `finished`.
- **Cadence** : l'île dessine Klay à la fréquence d'affichage et s'arrête quand elle est cachée ; Klay sur le bureau aussi, 10 images/s endormi, en pause écran éteint ou verrouillé ; le Klay qui rentre à pied seulement pendant sa marche (§13). Toutes les vues de l'île ouverte restent dans l'arbre (opacité 0) : celles qui ne sont pas à l'écran arrêtent leurs animations (mini Klays de la maison, zone de dépôt, barre d'envoi).

### États (`STATES`)

| Clé | Libellé | Couleur | Teinte | Yeux | Badge | Particularité |
|---|---|---|---|---|---|---|
| `idle` | Au repos | `#3E7280` (teal-light) | 0,35 | pilule | aucun | |
| `working` | Travaille | `#4FA3B5` (teal éclairci) | 0,72 | pilule | pilule « ••• » animée | |
| `thinking` | Réfléchit | `#7FB8C4` (teal éclairci) | 0,72 | pilule | « ••• » | regarde en haut à droite |
| `searching` | Cherche | `#A8D0D8` (teal éclairci) | 0,72 | grossis dans les jumelles | « ••• » | tient des jumelles à deux mains, qui balaient de gauche à droite (lacet sin(2,6 t) × 0,6), un peu au-dessus de l'horizon (tangage +0,06) ; le corps suit le balayage |
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
| Amour | cœurs `#FF4D6D` | joues à fond, cœurs qui montent | `love` | souris immobile 1,9 s sur le bonhomme ; sans son, quand vous l'attrapez pour le glisser |
| Surpris | petits points | saut + yeux agrandis | aucun | Klay sur le bureau, quand une demande le rappelle dans l'île (§13) |
| Fier | étoiles `#F7B32B` | étoiles, tête en arrière | `proud` | aucun pour l'instant (la vue de résultat a disparu avec le chat par Claude Code) |
| Clin d'œil | un œil fermé | tête penchée | `wink` | aucun pour l'instant (l'île n'envoie plus de mail) |
| Bâille | fatigués puis fermés | étirement vertical, « z » | `yawn` | juste avant de passer en `sleeping` |
| Content | arcs | joues | aucun | après une décision, un fichier avalé, une réponse du chat finie, un brouillon prêt |
| Agacé | fentes inclinées | halo violet `#A855F7` | `annoyed` | une claque |

## 8. Interactions avec le bonhomme

- **Survol** (expanded) : clignement, yeux ×1,08, son `hover` ; Klay sursaute, lève les mains et se penche vers le pointeur (§7, Mouvement). Immobile 1,9 s → Amour.
- **Clic** en compact ou hidden → rien, l'île ne s'ouvre jamais au clic (§3), sauf le bouton Granola de l'île réduite, qui ouvre Granola. **Clic** en expanded → claque : écrasement (70/130/170 ms), Agacé 800 ms, halo violet, sons `slap` + `annoyed`.
- **3 clics en moins de 1,7 s** → état `dizzy` pendant 3,3 s, vue `confused`, son `dizzy`, puis retour à la vue et à l'état d'avant.
- **Glisser** le bonhomme (plus de 3 pt) : un Klay flottant (toile de 67 pt, Klay de Ø 40) suit le curseur, celui de l'île disparaît. Lâché sur une fenêtre d'une autre app → **attache** (voir INTEGRATIONS §4) et l'île s'ouvre sur le chat. Où que vous le lâchiez (sur une fenêtre, sur le bureau, près de l'encoche), Klay **rentre à pied** dans l'île depuis l'endroit du lâcher (§13, Retour à pied) : il ne reste plus sur le bureau après un glisser. Le Klay de l'île reste caché jusqu'à son arrivée, pour que deux Klay ne se voient jamais.
- **Glisser un fichier** depuis le Finder vers la zone du notch (±220 pt autour du centre, jusqu'à 26 pt sous l'island) → vue `upload`. La zone de dépôt (`UploadCanvasView`, `UploadSequenceEngine`, testée par `scripts/test-upload-sequence.sh`) prend le relais du Klay de l'île à la même place et à la même taille (x 320, y 92, Ø 62, règle de taille `KlaySize`) : le Klay de l'île disparaît aussitôt, sans fondu, pour que deux Klay ne se voient jamais, et revient en fondu de 0,25 s quand la zone part. Contour vert et voile vert quand le fichier est au-dessus.
- **Zone de dépôt** : un seul personnage, Klay, au milieu de la carte pointillée, avec « Dépose ton fichier » dessous (y 133). Dans l'onglet Déposer, c'est le Klay de l'île, au repos (il respire, cligne et suit le pointeur). Quand un fichier approche, il ouvre les bras en 0,38 s avec un léger dépassement (mains vers (±200, −40), `armsOpenTargets`), ouvre grand les yeux, les pose sur le fichier, se déplace pour le suivre et cligne toutes les 3,6 s. Un fichier qui ressort sans être déposé : en 0,3 s les bras retombent et les yeux reviennent au repos, puis Klay retourne au centre ; si le fichier revient, Klay repart de là où il est. Plus de boîte aux lettres ni de seconde figure. Banc : cellules « dépôt : bras ouverts » et « dépôt : avale » de `tools/klay-preview`.
- **Déposer** : le fichier file dans Klay par une ligne au-dessus de ses yeux (aspiration de 0,30 s, 80 ms après le dépôt) ; Klay s'écrase (1,14 × 0,82 au plus profond, 70 ms après l'aspiration), ferme les yeux, baisse les bras, puis se réduit sur la barre : vue `uploading` (barre de 2,4 s, `tick` tous les 10 %, pendant la copie dans le dossier de travail de l'app), son `approve` au dépôt et à la fin, puis vue `choose`.
- Plusieurs fichiers : seul le premier est pris (`FileDropHandler`).

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
| fichier déposé / progression | `approve` / `tick` (`gulp` reste parmi les 29 fichiers, sans déclencheur dans l'app pour l'instant) |
| envoi / attache fenêtre | `send` / `attach` : fichiers gardés parmi les 29, aucun déclencheur dans l'app pour l'instant (l'île n'envoie plus de mail) |
| émotes | `love`, `pop`, `proud`, `wink`, `yawn`, `sleep` |

Pas de son pour les mises à jour silencieuses (lignes des conversations en cours, mini-bonhommes qui changent d'état sauf alerte).

## 10. Barre de menus et réglages

Petit item dans la barre de menus (icône : silhouette du Klay, monochrome). Menu : Ouvrir Klayer Island, Réglages…, Quitter. Sur une barre de menus pleine, l'encoche cache souvent cet item : le bouton Quitter de l'en-tête de l'île fait la même chose (§5).

Fenêtre Réglages (SwiftUI, simple), sections dans l'ordre d'affichage :
- **Claude Code Hooks** : état des hooks, boutons Installer et Désinstaller. Chacun montre d'abord les entrées du bloc `hooks` qui changent (« - » retirée, « + » ajoutée) et n'écrit qu'après « Confirmer et écrire », avec une sauvegarde datée juste avant. Seules les entrées de Klayer Island sont touchées (INTEGRATIONS §1).
- **App Claude : Chat et Cowork** (section Agents, lot 6) : interrupteur « Suivre Chat et Cowork dans l'app Claude (expérimental) », activé par défaut (UserDefaults `claudeAppWatchEnabled`) ; ligne « Accès Accessibilité : autorisé » ou « Accès Accessibilité : non autorisé », avec « Autoriser l'accès » ; bouton « Copier le diagnostic de l'app Claude », puis « Copié » 2 s. Voir §16.2.
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
- Hidden = 0 % CPU ; compact < 3 % ; mémoire < 100 Mo. Seule exception (lot 6, §16.2) : le suivi de Chat et Cowork lit l'app Claude toutes les 2 s tant qu'elle est au premier plan ou qu'une réponse repérée est en cours, et rien sinon.

## 13. Klay sur le bureau

Avec ⌃⌥D, Klay quitte l'island et vit comme une icône flottante sur le bureau. Il conserve tout son comportement (émotes, suivi des yeux, danse) et réagit aux alertes. Il rentre toujours à pied (Retour à pied, ci-dessous).

### Pose et panneau

- **Panneau** : `NSPanel` borderless non-activating, niveau `.floating`, `collectionBehavior [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`, taille 120 × 120 pt.
- **Clics traversants** : `ignoresMouseEvents` activé par défaut ; désactivé à 60 Hz uniquement quand le curseur est sur le corps (rayon ≈ 24 % de la taille du panneau). Position bornée à `screen.visibleFrame` avec une marge de 24 pt.
- Le panneau est toujours au niveau `.floating` : en dessous des panneaux de menu et de l'island, au-dessus des fenêtres normales.

### Installation

- **Par ⌃⌥D** (`flyOutOrHome()`) : un nouveau panneau part de l'encoche et vole vers la position sauvegardée (0,45 s). Rien tant qu'un Klay rentre à pied.
- **Plus par le glisser** : lâché n'importe où, le Klay glissé hors de l'île rentre à pied (`IslandWindowController.finishDrag` cède le panneau flottant à `KlayWalker`) ; il ne s'installe plus sur le bureau.
- **Au démarrage** (si `UserDefaults["klayOnDesktop"] == true`) : le greeting se joue normalement, puis à `greetComplete` un nouveau panneau part de la notch et vole vers la position sauvegardée (animation 0,45 s).

### Interactions

| Geste | Effet |
|---|---|
| Clic simple | Slap (`engine.slap()`), différé de `NSEvent.doubleClickInterval` |
| Double-clic | Annule le slap en attente ; Klay rentre à pied dans l'île (`walkHome()`) et le mode bureau s'arrête |
| ⌃⌥D | Klay rentre à pied dans l'île (`walkHome()`) et le mode bureau s'arrête |
| Clic droit | Émote Amour |
| Survol du corps | Clignement, yeux ×1,08, sursaut, se penche vers le pointeur (§7, Mouvement) |
| Glisser → zone notch | Klay rentre à pied dans l'île (`walkHome()`) |
| Glisser → fenêtre (GitHub) | Attache le contexte, Klay revient à sa position initiale, island ouvre `.prompt` |
| Glisser → ailleurs | Repositionne le panneau (borné au `visibleFrame`) |

### Personnage complet

- Respiration, clignements, suivi des yeux depuis la position du panneau (pas depuis l'island).
- Danse : mêmes règles que le mode compact (Spotify en lecture + pastille active + état autorisé).
- Fréquence d'affichage éveillé, 10 fps endormi (`TimelineView` adapte `minimumInterval` selon `isSleeping`).

### Absences de la notch

Quand `AppState.klayOnDesktop == true`, ou tant qu'un Klay rentre à pied (`AppState.klayWalkingHome`), `BotPlacement` masque le bonhomme de la notch (opacité 0, même règle que `isDraggingBot`).

### Alertes

Détection par `Publishers.CombineLatest($pendingApproval, $pendingQuestion)` : seules les transitions nil↔non-nil déclenchent l'action. La notification `.hookExpand` n'est pas utilisée (elle part aussi pour `.finished`, `.error`, le glisser de fichier, etc.).

1. `pendingApproval` ou `pendingQuestion` passe à non-`nil` → émote `surprised` sur le Klay du bureau.
2. Après 0,45 s, `retractForAlert()` : Klay rentre à pied dans l'île (Retour à pied) ; `klayOnDesktop` passe à `false` au départ et le bonhomme de la notch apparaît à son arrivée, pour l'alerte ; `UserDefaults["klayOnDesktop"]` reste `true`.
3. Quand `pendingApproval` **et** `pendingQuestion` sont tous deux `nil`, `launchFlyIfNeeded()` renvole Klay vers la position sauvegardée après 0,6 s.
4. Si l'alerte se résout avant ou pendant sa marche de retour, Klay repart vers le bureau dès son arrivée.

### Retour à pied (`KlayWalker`)

Un seul marcheur ramène Klay dans l'île : à la fin de tout glisser du Klay de l'île (sur une fenêtre, sur le bureau, près de l'encoche), et depuis le bureau au double-clic, à ⌃⌥D, au lâcher sur la zone de l'encoche et quand une demande arrive (`retractForAlert`). Le plan et la démarche sont purs (`KlayWalk.swift`, miroir de `tools/klay-preview/src/walk.ts`) et testés par `scripts/test-klay-walk.sh`.

- **Trajet** : une ligne droite depuis l'endroit où il est jusque juste sous sa place dans l'île : 0,3 × sa largeur sous le Klay de l'île réduite ou ouverte, sous le centre de l'encoche quand l'île est fermée (`KlayWalk.doorstep`, la place vient de `IslandWindowController.klayHome()`). Lâché sur une fenêtre, l'île est déjà ouverte sur le chat : il marche jusque sous sa place à gauche de la carte.
- **Durée** : distance / 650 pt/s, bornée entre 0,7 s et 2,2 s. À 40 pt ou moins de la fin, pas de marche : il saute aussitôt. Sa vitesse monte en demi-cosinus sur le premier pas (0,4 s, ou la moitié de la marche si elle est plus courte) et redescend de même sur le dernier ; régulière entre les deux.
- **Démarche** : 2,5 pas par seconde, la pose de §7 (Marche), le halo de l'état au repos (teal-light), sans badge, les yeux vers l'île.
- **Arrivée** : un petit saut de 0,34 s, jusqu'à 18 pt au-dessus de la ligne, jusqu'à la place du Klay de l'île, en rétrécissant ou en grandissant jusqu'à sa taille (plus petit dans l'île réduite, plus grand dans les vues ouvertes ; place et taille relues au début du saut, l'île a pu s'ouvrir ou se fermer), avec un écrasement au départ du saut ; son `peek`. À l'arrivée, le panneau du marcheur est masqué et fermé dans le même tour de la boucle principale que le Klay de l'île est montré : jamais deux Klay, au pire une image sans Klay. Île fermée sur l'encoche (ou salut, ou zone de dépôt, qui dessinent leur propre Klay) : il rétrécit dans le centre de l'encoche et s'efface sur les derniers 40 % du saut. Lâché à 40 pt ou moins de la fin, il saute depuis l'endroit du lâcher, sans passer d'abord par la fin de la marche.
- **Taille** : celle de son panneau au départ, toile de 67 pt pour le Klay flottant du glisser, 120 pt pour le Klay du bureau. Le panneau passe au-dessus de l'île (niveau de la barre des menus + 4) et laisse passer les clics.
- **Jamais deux Klay** : `AppState.klayWalkingHome` cache le Klay de l'île du premier pas à l'arrivée, et le halo de l'île ouverte derrière sa place (rien n'attend à une place vide) ; pendant ce temps l'île ne salue pas, vous ne pouvez pas glisser son Klay, et ⌃⌥D ne fait rien. Un retour au bureau demandé pendant la marche (fin d'alerte) attend son arrivée. Un fichier glissé sur l'île pendant la marche ouvre la zone de dépôt, qui dessine son propre Klay : le marcheur s'arrête et disparaît aussitôt, sans son (`KlayWalker.finishNow`).
- **Fluidité et CPU** : le lien d'affichage de la vue du marcheur (`displayLink(target:selector:)`, macOS 14 et plus) déplace le panneau à chaque image de l'écran où il se trouve, 120 fois par seconde sur un écran ProMotion, et sa `TimelineView` le dessine au même rythme ; les deux n'existent que pendant la marche, le lien est invalidé à chaque arrivée (saut fini, fichier glissé, nouvelle marche) ; rien ne tourne une fois Klay arrivé.

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
| Entrée suivante de la maison (`nextPill`) | ⌃⌥] | `shortcut.nextPill.keyCode` / `.flags` | Oui |
| Entrée précédente de la maison (`prevPill`) | ⌃⌥[ | `shortcut.prevPill.keyCode` / `.flags` | Oui |
| Couper le son (`toggleMute`) | ⌃⌥M | `shortcut.toggleMute.keyCode` / `.flags` | Oui |
| Klay sur le bureau (`toggleDesktopKlay`) | ⌃⌥D | `shortcut.toggleDesktopKlay.keyCode` / `.flags` | Oui |

- `nextPill` et `prevPill` (« Onglet suivant » et « Onglet précédent » dans les Réglages) parcourent ce que montre la maison, en boucle : la liste, puis la carte de chaque icône de service de la bande, dans son ordre (Spotify, puis GitHub), par le même chemin qu'un clic (`HomeRail.cycle`). Ils ouvrent l'île sur la maison. Les pastilles Claude ne sont pas parcourues : leurs sessions sont la liste.
- Si Carbon ne peut pas enregistrer un raccourci (conflit système), l'action est marquée `.conflict` dans `HotKeyCenter` et un indicateur apparaît dans Réglages → Raccourcis.
- `toggleIsland` conserve les clés UserDefaults historiques (`hotkeyCode`, `hotkeyFlags`, `hotkeyEnabled`) pour ne pas casser les préférences existantes.

### 14.2 Raccourcis locaux (actifs quand l'île a le focus)

Ces raccourcis sont gérés par `NSEvent.addLocalMonitorForEvents`. L'île prend le focus clavier quand elle est ouverte via un raccourci global (jamais au survol ni à l'alerte).

| Raccourci | Action |
|-----------|--------|
| ⌘→ | Entrée suivante de la maison, comme ⌃⌥] |
| ⌘← | Entrée précédente de la maison, comme ⌃⌥[ |
| ⌘1…⌘9 | ⌘1 la liste, ⌘2 et ⌘3 les cartes de la bande d'icônes, dans son ordre ; un numéro sans entrée ne fait rien (`HomeRail.entry`) |
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
- **Contexte.** Le chat s'ouvre sans contexte (lot 6) : ni son onglet ni ⌃⌥Espace ne capturent la fenêtre de l'app précédente, et un fichier déposé n'y entre qu'avec « Poser une question ». Seuls des actes explicites posent un contexte : « Poser une question » (ou « Poser une question à ce sujet ») sur un fichier déposé, Klay glissé sur une fenêtre, ⌃⌥W (« Attacher la fenêtre de premier plan »). Un contexte reste jusqu'à ce qu'un autre le remplace, ou qu'un fichier refusé le retire. `scripts/test-window-capture-sites.sh` refuse tout autre appel à la capture de fenêtre.
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

## 16. L'app Claude : onglet Code, Chat et Cowork (lot 6)

L'île est la notification de l'app Claude : elle signale chaque fin de réponse ou de session et chaque demande (autorisation, question), même quand l'utilisateur est dans une autre app. Conception : `docs/superpowers/specs/2026-10-09-klayer-island-lot6-app-claude-design.md`. Détail technique : `INTEGRATIONS.md` §1 et §8. Vérification sur Mac : `TEST-MAC.md`, section 5.

| Mode de l'app Claude | Source | Niveau |
|---|---|---|
| Code (onglet Code) | hooks Claude Code (`klayer_agent: claude-desktop`) | mécanisme officiel : fins, autorisations, questions (lot 3), et notifications (§16.1) |
| Chat | lecture des boutons de l'app par l'accessibilité de macOS | expérimental : dépend des libellés de l'interface d'Anthropic |
| Cowork | idem | expérimental ; le spike S2 (Plugin Cowork) reste ouvert |

Le terminal ne change pas. L'île ne clique jamais dans l'app Claude, n'y répond à rien et n'y lit jamais le texte d'un message. Hors périmètre : claude.ai dans un navigateur, et répondre depuis l'île aux autorisations de Chat ou de Cowork.

### 16.1 Onglet Code : une demande sans carte ouvre l'île

- Une notification Claude Code (hook `Notification`) d'une session de l'app Claude qui demande quelque chose ouvre l'île sur cette session, quand aucune carte de cette session n'est tenue (son autorisation ou sa question à l'écran, ou en attente du survol). Règles pures dans `CodeNotification`, testées par `scripts/test-code-notification.sh`.
- Ce qui demande quelque chose (`notification_type`) : `permission_prompt` (une autorisation) ; `elicitation_dialog` et `elicitation_url_dialog` (le formulaire ou l'adresse d'un serveur MCP) ; `idle_prompt` (Claude a fini il y a environ 60 s et rien n'a été tapé depuis). Tout autre type ne demande rien. Sans type (Claude Code ancien) : le texte « needs your permission » ou « waiting for your input ».
- Un `idle_prompt` qui suit une fin déjà montrée (la ligne de la session est finie ou en erreur, et sa vue `finished` ou `error` s'est ouverte) n'ouvre rien : cette vue était la notification. Une fin seulement badgée (une carte attendait, l'île servait à autre chose) n'a rien montré : son `idle_prompt` ouvre la note, c'est sa seconde chance. Une autorisation ou un formulaire ouvre quelle que soit la ligne.
- Vue `note` : titre « Claude attend ta réponse » ; ligne « Une autorisation t'attend dans l'app Claude : <session> » pour une autorisation, « Claude a besoin de toi dans l'app Claude : <session> » sinon (le nom de la session, sinon son dossier, §5) ; boutons « Ouvrir Claude » (ouvre l'app Claude, puis l'île se replie) et OK. Son `approval` pour une autorisation, `question` sinon. La note tient l'île comme une fin de session (règle 6 : jusqu'au survol suivi d'une sortie, un clic ailleurs, Échap, OK ou « Ouvrir Claude ») ; le minuteur de 3 s des notes ne la ferme pas, et une réponse donnée dans l'app ne la replie pas d'elle-même. La même note déjà à l'écran ne rejoue ni son ni ouverture.
- Ouverture (`AppState.showClaudeAppAlert`, la seule entrée des notes de l'app Claude) : même règle qu'une fin (`FinishPresentation`) : jamais par-dessus un brouillon du chat ou d'un email, une carte en attente, les vues de dépôt, les Réglages de l'île ou une île épinglée. Sinon, le son, un badge d'autorisation sur la pastille de l'app Claude, et l'alerte est retenue, la dernière seulement (`ClaudeAppAlertHold`, testé par `scripts/test-code-notification.sh`) : elle s'affiche dans la même note, sous la même règle et avec son son, la prochaine fois que l'île montrerait sa maison (une demande part sans autre en attente, l'île s'ouvre sur sa vue par défaut, un clic sur l'onglet maison). Elle tombe quand l'app Claude passe au premier plan, quand une alerte plus récente la remplace (retenue ou affichée), quand sa session de l'onglet Code reprend (tout autre événement de hook de cette session, ou une nouvelle demande : l'utilisateur a répondu dans l'app Claude), ou après 30 min (un seul réveil à cette heure, pas de minuteur qui tourne). L'onglet maison porte son badge en attendant (§5, Bande d'icônes).
- Sous une carte de la même pastille (deux sessions de l'app Claude) : la notification d'une autre session joue son son et passe par la même entrée, donc retenue, jamais par-dessus la carte ; sa ligne bouge comme ailleurs.
- Ligne de la session : « Attend ton accord » pour une autorisation, « Te pose une question » pour une attente, sauf une ligne finie ou en erreur, qui reste dans l'historique du jour. Un `PostToolUse` de la session la remet sur « Travaille » (l'utilisateur a répondu dans l'app), sauf tant qu'une carte de cette session est tenue.
- Terminal (sans `klayer_agent`) : jamais. Ses notifications gardent leur effet d'avant (limite d'usage, question dans le texte).
- Les champs et les types viennent de la doc des hooks de Claude Code. Que l'app Claude envoie `idle_prompt` et `elicitation_*` dans ses sessions n'y est pas écrit, et `permission_prompt` n'y part qu'à partir de Claude Code 2.1.233 : à confirmer sur Mac.

### 16.2 Chat et Cowork : suivi expérimental

- Réglage « Suivre Chat et Cowork dans l'app Claude (expérimental) », activé par défaut (§10). Coupé : aucun observateur ni minuteur. Ni lecture ni demande d'accès dans un lancement de test (`KLAYER_ISLAND_TEST=1`).
- Accès : la permission Accessibilité de macOS, déjà demandée pour le titre de la fenêtre attachée au chat. La demande de macOS s'affiche d'elle-même une fois par build (la première fois que le suivi est actif et que l'app Claude tourne sans accès ; une build signée ad hoc perd l'accès à chaque mise à jour), ensuite seulement par « Autoriser l'accès », qui ouvre aussi Réglages Système sur Accessibilité quand l'accès manque encore. Sans accès, rien n'est lu ni planifié.
- Lecture (`ClaudeAppWatcher`) : l'app Claude (`com.anthropic.claudefordesktop`, une app Electron) n'expose son interface à l'accessibilité que si son attribut `AXManualAccessibility` est vrai : l'île le met à vrai au début d'une série de lectures et le remet à faux à la fin, seulement si c'est elle qui l'avait mis. Elle parcourt les fenêtres de l'app sur une file à part, hors du fil principal (profondeur 30, 5 000 éléments, 0,5 s au plus par appel, les enfants du dernier au premier pour que la limite coupe les plus anciens messages plutôt que la zone de saisie). Elle lit le rôle de chaque élément parcouru et le libellé des seuls boutons (`AXButton`, `AXMenuButton`, `AXPopUpButton` ; `AXDescription`, sinon `AXTitle`, sinon `AXHelp`, jamais `AXValue`), sans entrer dans les textes, les champs, les liens ni les images. Le titre de la fenêtre principale ne sert qu'à la ligne de la note.
- Libellés (`ClaudeAppWatchRules`, le seul endroit où ils vivent, testé par `scripts/test-claude-app-watch.sh`) : arrêt « Stop response », « Stop », « Arrêter la réponse », « Arrêter » ; autorisation « Allow », « Allow once », « Always allow », « Allow always », « Autoriser », « Autoriser une fois », « Toujours autoriser » ; refus « Deny », « Don't allow », « Refuser », « Ne pas autoriser ». Comparaison exacte, sans casse ni espaces autour, apostrophe typographique lue comme droite ; jamais « contient ». Une autorisation demande un bouton d'autorisation et un bouton de refus visibles ensemble. Aucun libellé reconnu : aucun événement. Ces listes sont des suppositions que le diagnostic corrige.
- Événements (`ClaudeAppWatchState`, pur et testé) :
  - « Claude a fini de répondre », son `finish` : un bouton d'arrêt vu, puis absent à deux lectures de suite, l'app Claude au second plan aux deux lectures et sans autorisation à l'écran. Rien si l'une des deux lectures s'est faite app au premier plan. La note arrive donc 2 à 4 s après la fin.
  - « Claude attend ta réponse », son `approval` : une autorisation apparue, une fois par apparition, l'app au second plan. Une autorisation vue au premier plan ne déclenche rien, même si elle est encore là quand l'app passe derrière. Elle ne compte comme partie qu'après deux lectures sans elle.
  - Ligne de la note : le titre de la fenêtre de l'app Claude, sauf vide ou « Claude », et alors « Dans l'app Claude ». Même note et même règle d'ouverture que §16.1.
  - Onglet Code : dans les 15 s qui suivent un événement de hook d'une session de l'app Claude (`HookServer.lastDesktopHookAt`), un événement du suivi est consommé sans note, pour ne pas doubler les vues que les hooks montrent déjà.
- CPU : aucun minuteur au repos ; les notifications de macOS (activation, lancement et fin d'app) réveillent le suivi. Une lecture toutes les 2 s, seulement tant que l'app Claude est au premier plan ou qu'une réponse repérée est en cours. Quand une autre app passe devant pendant les lectures, une lecture immédiate décide s'il faut continuer : une réponse envoyée juste avant le changement d'app est suivie jusqu'au bout. Une lecture qui ne dit rien (aucune fenêtre, app masquée, délai dépassé) ne conclut rien ; au second plan, 15 lectures de suite de cette sorte (30 s) abandonnent la réponse sans note, et une réponse suivie de derrière plus de 60 min aussi. L'app Claude quitte : tout est oublié. Écrans en veille ou session inactive : ni minuteur ni lecture ; au retour, une lecture, puis l'état décide. Une lecture sans zone web (`AXWebArea`) dans les 3 s qui suivent l'activation de l'arbre par l'île ne dit rien non plus : Chromium construit encore sa page.
- Diagnostic : « Copier le diagnostic de l'app Claude », sur clic seulement, active lui-même l'arbre de l'app Claude et attend qu'il soit construit (une zone web, ou un nombre d'éléments qui a grandi puis s'arrête, 3 s au plus), puis copie dans le presse-papiers la version de l'app Claude, l'accès (oui ou non), comment l'arbre a été activé (déjà actif, ou le résultat de l'activation), la durée de l'attente, les comptes de la lecture (fenêtres, éléments lus, limites atteintes, durée, lecture complète, zones web `AXWebArea`, nombre d'éléments par rôle, boutons), si le bouton d'arrêt et une autorisation sont reconnus, puis une ligne `rôle | libellé` par bouton distinct, 300 lignes au plus. Un libellé de plus de 30 caractères ou de 5 mots s'écrit « (libellé long, N caractères) », un libellé vide « (sans libellé) ». Jamais le texte d'un message, jamais le titre de la fenêtre, rien sur le disque. Un libellé court peut pourtant être le titre d'une conversation : l'utilisateur relit le diagnostic avant de l'envoyer.
- Journal : `~/Library/Logs/NotchBuddy/claude-app.log`, des événements seulement, jamais un libellé, un titre ni un message.

# Klayer Island : liste de contrôle Mac

Cette liste se parcourt de haut en bas : 10 minutes pour l'installation, 40 minutes pour le parcours de test (points facultatifs exclus), puis 10 minutes pour les trois spikes (S1, S3, S4). Elle teste la build des lots 1 à 3. La section du lot 4 (chat Haiku et brouillon Gmail par Claude Code) sera ajoutée ici quand ce lot sera livré.

Ce que contient cette build :

- **Lot 1, nettoyage.** App Mac seule. Plus de Stripe, n8n, Resend, Cal.com, Notion, Vercel, Apple Music, ni d'agents autres que Claude. GitHub et Spotify restent.
- **Lot 2, comportement.** Klay sort et salue quand la souris s'approche de l'encoche. L'île s'ouvre au survol, jamais au clic, et se ferme au clic ailleurs ou à Échap. Le bouton Granola remplace la grille de pastilles de l'île réduite. La zone de dépôt montre Klay les bras ouverts. Klay a des jumelles en recherche, des couleurs d'état de la marque et un mouvement plus vivant.
- **Lot 3, contenu.** La maison montre les conversations en cours et les derniers choix. Les autorisations et questions de l'app Claude s'affichent dans l'île. L'île s'ouvre à chaque fin de session.

Le chat et l'email de cette build utilisent encore l'ancien chemin (clé API, Apple Mail). Ne les envoyez pas : ils changent au lot 4.

## Comment lire cette liste

- Chaque case est un point : une action à faire, puis « Attendu », ce que vous devez voir.
- Les libellés de l'app suivent la langue du Mac. Cette liste donne le français, avec l'anglais entre parenthèses quand il diffère.
- Un point marqué (facultatif) demande un second écran, Spotify, un jeton GitHub ou une longue attente. Sautez-le si vous n'avez pas le matériel.
- « À noter » veut dire qu'aucune bonne réponse n'est connue : décrivez ce que vous voyez.
- Pour chaque point en échec : une capture d'écran, et ce que vous avez vu à la place.

## Avant de commencer

- Un MacBook avec encoche. Sans encoche, dites-le : certains points changent (barre noire à la place).
- Claude Code 2.1.85 ou plus récent (`claude --version`), nécessaire pour les questions. Un terminal reconnu : Terminal, iTerm, Warp, Ghostty, kitty ou autre de la liste de l'app.
- L'app Claude à jour, avec son onglet Code, pour S1 et les points « app Claude ».
- Granola installé et connecté (bouton Granola, S4). Spotify et un jeton GitHub sont facultatifs.
- Deux dossiers d'essai : `mkdir -p ~/essai-a ~/essai-b`.
- Le son activé (haut-parleur dans l'en-tête de l'île).

Raccourcis utiles :

| Raccourci | Effet |
|---|---|
| ⌃⌥Espace | ouvre le chat |
| ⌃⌥A | va à l'alerte en attente |
| ⌃⌥T | amène le terminal ou l'éditeur de la session la plus récente |
| ⌃⌥D | envoie Klay sur le bureau, ou le ramène |
| ⌘P | épingle l'île ouverte (dans l'île) |
| ⌘⇧N | ouvre ou ferme l'île (désactivé par défaut) |

## 1. Installer

- [ ] Téléchargez l'artefact `KlayerIsland-macOS` : GitHub, dépôt `blamidey-klayer/Klayer-notif`, Actions, workflow Build, dernier run vert de la branche `claude/klayer-project-reproduction-92uerq`, section Artifacts. L'artefact expire après 14 jours. Dézippez, puis déplacez `KlayerIsland.app` dans `/Applications`.
- [ ] Premier lancement. L'app est signée ad hoc, pas notariée. Clic droit sur `KlayerIsland.app`, Ouvrir, puis Ouvrir dans la fenêtre. Autre voie : `xattr -dr com.apple.quarantine /Applications/KlayerIsland.app`. Attendu : l'app démarre et une icône Klay apparaît dans la barre de menus, avec Ouvrir Klayer Island, Réglages… et Quitter.
- [ ] Trousseau. Chaque nouvelle build peut redemander l'accès au jeton GitHub, car la signature ad hoc change. Autorisez. À noter : la demande revient-elle à chaque lancement ?
- [ ] Salut de lancement. Attendu : Klay salue (halo doré qui vire au teal, badge d'activité teal), puis le salut se replie dans l'île réduite avec Klay seul, sans disque coloré.
- [ ] Hooks absents, avant toute installation. Survolez l'encoche (ou menu Ouvrir Klayer Island). Attendu : la maison dit « Aucune conversation en cours. », puis en dessous « Hooks Claude Code non installés » et un bouton « Réglages… ». Si des hooks d'un ancien build sont déjà installés, cette ligne manque : Réglages, Agents, Désinstaller (Uninstall). Attendu : les entrées de Klayer Island à retirer s'affichent, une par ligne, précédées de « - », et rien n'est écrit. Cliquez « Confirmer et écrire » (Confirm and write), puis rouvrez l'île.
- [ ] Cliquez « Réglages… ». Attendu : les Réglages s'ouvrent sur la section Agents et l'île se replie. Refaites avec les Réglages déjà ouverts sur une autre section : ils passent sur Agents.
- [ ] Installez les hooks : Réglages, Agents, « Installer les hooks » (Install hooks). Attendu : sous le bouton, les changements du bloc `hooks` de `~/.claude/settings.json`, une entrée par ligne : « + » pour une entrée ajoutée, « - » pour une entrée d'un ancien build retirée. Vos propres hooks n'y figurent pas : ils restent tels quels. Rien n'est écrit à ce stade. Cliquez « Confirmer et écrire » (Confirm and write). Attendu : le message « ✓ Hooks installés dans ~/.claude/settings.json ».
- [ ] Cliquez de nouveau « Installer les hooks ». Attendu : « Les hooks sont déjà à jour : rien à écrire. », sans aperçu ni nouvelle sauvegarde.
- [ ] (facultatif) Ajoutez à la main un hook à vous dont le chemin contient « klayer », par exemple `{"type":"command","command":"$HOME/klayer-essai.sh"}` sous `SessionStart`. Désinstallez puis réinstallez les hooks. Attendu : ce hook n'apparaît dans aucun aperçu et reste dans le fichier.
- [ ] Vérifiez la sauvegarde : `ls ~/.claude/settings.json.bak-*`. Attendu : un fichier daté `settings.json.bak-AAAAMMJJ-HHMMSS`. Il n'existe que si `settings.json` existait déjà.
- [ ] Dans Réglages, Agents, cochez « Answer questions and permissions from terminal sessions in the notch ». Par défaut elle est décochée : les autorisations et questions d'une session de terminal restent alors dans le terminal. Le reste de cette liste suppose qu'elle est cochée.
- [ ] Le relais est réécrit à chaque lancement. Faites `ls -l ~/Library/Application\ Support/NotchBuddy/`. Attendu : `nb-hook` et `nb-hook.py` datés du dernier lancement. Puis `grep -c CLAUDE_CODE_ENTRYPOINT ~/Library/Application\ Support/NotchBuddy/nb-hook.py`. Attendu : 2.
- [ ] Rouvrez l'île. Attendu : la ligne « Hooks Claude Code non installés » a disparu.
- [ ] Pour la suite, lancez des sessions Claude Code neuves : celles ouvertes avant l'installation peuvent ne pas envoyer d'événements.

## 2. Parcours de test

### 2.1 Île réduite et survol (6 min)

Avant de commencer : aucune session Claude Code ouverte. Si l'île réduite est encore visible après le lancement, éloignez la souris et attendez qu'elle se cache.

- [ ] Approchez la souris à moins de 120 pt de l'encoche, sans la toucher. Attendu : Klay sort en île réduite avec le son `peek`, regarde le pointeur et salue de la main (son `greet`). L'île ne s'ouvre pas.
- [ ] Restez dans la zone. Attendu : pas de second salut. Sortez de la zone puis revenez. Attendu : un nouveau salut, aussi quand Klay est déjà sorti.
- [ ] (facultatif) Éloignez la souris et attendez 60 s. Attendu : l'île réduite se cache. Tant que la souris reste dans la zone, elle reste.
- [ ] Posez la souris sur l'encoche. Attendu : l'île s'ouvre après environ 250 ms, avec le son `open`. Retirez la souris avant 250 ms. Attendu : rien ne s'ouvre.
- [ ] Ouverte par le survol, sortez la souris. Attendu : repli en île réduite après environ 0,6 s. Revenez avant la fin. Attendu : elle reste ouverte.
- [ ] Cliquez sur l'encoche fermée, puis sur l'île réduite (hors bouton Granola). Attendu : rien ne s'ouvre. Appuyez sur Klay dans l'île réduite. Attendu : rien non plus. Seul le glisser de Klay reste possible.
- [ ] Île ouverte, cliquez (gauche puis droit) dans une autre app, sur le bureau, puis dans la barre de menus. Attendu : elle se referme à chaque fois, avec le son `close`.
- [ ] Île ouverte, cliquez dans la fenêtre Réglages, puis sur l'icône de la barre de menus. Attendu : elle se referme.
- [ ] Île ouverte, tapez Échap dans l'île. Attendu : elle se ferme.
- [ ] Île ouverte, tapez Échap dans une autre app (le terminal). Attendu : elle se ferme, sauf si une demande attend ou si elle est épinglée. À noter : macOS vous demande-t-il une autorisation (surveillance de l'entrée, accessibilité) pour ce cas ?
- [ ] Île ouverte, épinglez-la (⌘P) puis cliquez dans une autre app. Attendu : elle reste ouverte.
- [ ] (facultatif, 15 s d'attente) Île ouverte par le survol, cliquez dedans (sur le bouton maison de l'en-tête), puis sortez la souris. Attendu : repli après le délai « Close after » des Réglages (15 s par défaut). Dans les 10 dernières secondes, un trait de 2 pt au bas du centre se réduit et l'île se replie quand il atteint zéro. Revenez sur l'île pendant le compte à rebours : le trait disparaît et l'île reste ouverte. Ouverte au survol sans clic, ou ouverte seule sur « terminé » : aucun trait.
- [ ] Île ouverte, cliquez sur Klay. Attendu : émote « agacé ». Glissez Klay hors de l'encoche et lâchez-le sur le bureau. Attendu : Klay se pose sur le bureau. Glissez-le sur la fenêtre d'une autre app. Attendu : le chat s'ouvre avec cette fenêtre en contexte. Les boutons de l'île et le chat fonctionnent.
- [ ] Île fermée, tapez ⌃⌥Espace. Attendu : le chat s'ouvre. Approcher l'encoche ou la survoler ne le replie pas. Un clic dans une autre app le ferme. Même règle pour ⌃⌥], ⌃⌥[ et ⌃⌥W.
- [ ] Klay sur le bureau (⌃⌥D), approchez l'encoche. Attendu : pas de son `greet`. Ouvrez l'île, puis cliquez sur Klay du bureau. Attendu : l'île reste ouverte.
- [ ] (facultatif) Écran externe placé au-dessus du MacBook, souris en bas de cet écran, juste au-dessus de l'encoche. Attendu : pas de salut.
- [ ] (facultatif) Réglages, General, Display : choisissez un autre écran et approchez la souris de sa nouvelle encoche ou barre. Attendu : Klay salue sur le nouvel écran.

### 2.2 Bouton Granola (2 min)

- [ ] Approchez la souris pour sortir Klay en île réduite. Attendu : un micro gris dans l'oreille droite. Il n'y est ni île cachée, ni île ouverte. Aucun mini Klay coloré n'apparaît, ni en île réduite ni à la fin du salut de lancement.
- [ ] Posez la souris sur le bouton plus d'1 s. Attendu : l'île ne s'ouvre pas. Passez sur l'oreille gauche ou l'encoche. Attendu : elle s'ouvre après 250 ms.
- [ ] Mettez une autre app au premier plan, puis cliquez le bouton. Attendu : Granola ouvre une nouvelle note dès le premier clic. L'île reste réduite, Klay ne se détache pas, aucun son `peek` ni `open`. L'enregistrement est l'objet de S4.
- [ ] Survolez le bouton. Attendu : l'infobulle « Nouvelle note Granola ». À noter : n'apparaît-elle pas tant que l'app est inactive ? (facultatif) VoiceOver la lit.
- [ ] Ouvrez puis fermez l'île. Attendu : le bouton s'efface avec le bord de l'île, sans clignoter.
- [ ] (facultatif) Granola fermé ou absent, cliquez le bouton. Attendu : rien ne se passe et l'app ne plante pas.
- [ ] (facultatif) Écran sans encoche (barre de 24 pt de haut). Attendu : l'icône tient dans la barre, la zone cliquable fait 24 pt, la barre reste traversée par les clics hors de l'île. En mode « Follow the mouse », le bouton suit l'île sur l'autre écran.

### 2.3 Demandes (8 min)

Ouvrez un terminal reconnu, `cd ~/essai-a`, lancez `claude` sans l'acceptation automatique des outils.

- [ ] Demandez « crée le fichier essai.txt avec le mot bonjour ». Attendu : l'île s'ouvre seule, même sans survol, sur la carte « essai-a a besoin d'une permission » (needs permission). Elle dit ce qui est demandé : « Write · essai.txt » (l'outil et le fichier, relatif au dossier du projet ; pour une commande du terminal, la commande ; pour une page web, son adresse). Refuser (Deny), Autoriser (Allow) et Toujours (Always) restent estompés 0,6 s, puis s'activent. Son `approval`. Klay lève les bras, badge « ! » ambre.
- [ ] Cliquez Autoriser. Attendu : le fichier est créé, l'île revient à la maison, la ligne de la session repasse à « Travaille ».
- [ ] Redemandez un autre fichier et cliquez Refuser. Attendu : Claude Code ne crée pas le fichier. À noter : si le refus est ignoré, c'est le bug signalé sur `PermissionRequest` (anthropics/claude-code #19298).
- [ ] Redemandez et cliquez Toujours. Attendu : la règle est enregistrée par Claude Code. À noter : la même demande revient-elle ensuite ?
- [ ] Redemandez et répondez dans le terminal avant l'île. Attendu : la carte de l'île se ferme et affiche « Handled in Terminal. » (le nom de votre terminal) pendant 3 s, puis l'île se replie. La ligne de la session repasse aussi à « Travaille ».
- [ ] Demandez « utilise l'outil AskUserQuestion pour me demander rouge ou bleu, puis écris le choix dans couleur.txt ». Attendu : l'île s'ouvre sur la question, avec les options en boutons et un lien « Répondre dans le terminal » (Reply in terminal). Cliquez une option. Attendu : la réponse part tout de suite et Claude continue avec ce choix.
- [ ] Redemandez une question et cliquez « Répondre dans le terminal ». Attendu : la carte se ferme et le terminal pose la question. Redemandez, puis interrompez Claude Code (Échap dans le terminal). Attendu : la carte disparaît.
- [ ] (facultatif) Question à plusieurs réponses ou à plusieurs questions. Attendu : cases à cocher, bouton Envoyer (Send) ou Suivant (Next), compteur 1/N, saisie libre sous « Other… ». Cochez une réponse (ou passez à la question 2), cliquez ailleurs pour replier l'île, puis survolez-la. Attendu : la carte reprend où vous en étiez, cases cochées et texte libre compris.
- [ ] Une demande attend, puis cliquez dans une autre app (ou tapez Échap dans l'île). Attendu : l'île se replie en île réduite et Klay garde son badge. Claude Code attend toujours : le terminal ne repose pas la demande. Survolez l'île. Attendu : elle se rouvre sur la demande. Même chose pour une question.
- [ ] Une demande attend, île ouverte : survolez puis sortez la souris, attendez 2 s. Attendu : la carte reste ouverte. Même résultat quand la demande arrive pendant que l'île est ouverte par le survol.
- [ ] Une question attend. Tapez ⌃⌥T (ou ⌘⇧N si vous l'avez activé). Attendu : repli en île réduite, la question reste en attente, ⌃⌥A la rouvre. Tapez ensuite ⌃⌥Espace. Attendu : le chat prend la place, la demande reste en attente, le survol ou ⌃⌥A la ramène. macOS peut demander l'autorisation Automatisation la première fois : acceptez.
- [ ] (facultatif) Deux sessions (`~/essai-a` et `~/essai-b`) demandent une autorisation en même temps. Attendu : l'île montre la plus récente, l'autre se pose dans son terminal, et la ligne de la première repasse à « Travaille ». Les boutons de la carte s'estompent quand elle change de demande et ne répondent qu'après 0,6 s.
- [ ] (facultatif) Une autorisation de `essai-a` est à l'écran, puis `essai-b` pose une question (AskUserQuestion). Attendu : la carte d'autorisation reste en place, sans changer sous le pointeur ; le son `approval` sonne et la ligne de `essai-b` passe à « Te pose une question ». Cliquez Autoriser. Attendu : la question s'affiche aussitôt, ses boutons estompés 0,6 s, puis actifs. Recommencez en répondant à l'autorisation dans le terminal de `essai-a`. Attendu : pas de note par-dessus la carte à l'écran ; si c'est la question qui est à l'écran, elle reste. Quand la note « Handled in … » s'affiche alors qu'une autre demande attend, elle laisse la place à cette demande après 3 s au lieu de rester affichée.
- [ ] (facultatif) Décochez « Answer questions and permissions from terminal sessions in the notch », puis redemandez une autorisation dans un terminal. Attendu : pas de carte, le terminal demande lui-même. Recochez-la.
- [ ] App Claude, onglet Code, dossier d'essai, mode qui demande les autorisations. Demandez une action qui en exige une. Attendu : la même carte s'ouvre dans l'île, avec le nom du projet. Répondez dans l'app d'abord. Attendu : la carte de l'île se ferme et affiche « Handled in Claude. » pendant 3 s. La décision dans l'île se teste avec S1.
- [ ] App Claude, déclenchez un `AskUserQuestion`. Attendu : la question s'affiche dans l'île. Choisissez une option : Claude continue avec ce choix. Recommencez et cliquez « Répondre dans Claude ». Attendu : la carte se ferme et l'app pose la question elle-même. Recommencez et répondez dans l'app d'abord. Attendu : la carte de l'île se ferme.
- [ ] (facultatif) Claude Code dans VS Code. Attendu : le lien de la question dit « Répondre dans le terminal » (Reply in terminal) et la note dit « Handled in Claude Code. ».
- [ ] (facultatif) Deux sessions de l'app Claude. La session A finit et, dans les 5 s, la session B demande une autorisation. Attendu : la carte nomme le projet de B, Autoriser fonctionne, la pastille reste jusqu'au prochain arrêt de B. Avec une question ouverte pour B, la fin de A laisse la carte en place, avec le nom de B ; le travail de A pendant ce temps (un outil, un nouveau message) ne change ni la pose de Klay ni le nom de la pastille, seule la ligne de A bouge. La réponse inscrit le projet de B dans les derniers choix. Avant la première demande, la pastille de l'app Claude s'appelle « Claude Desktop », pas « claude-desktop ».

### 2.4 Fin de session et erreur (7 min)

Gardez deux terminaux avec une session dans `~/essai-a` et une dans `~/essai-b`.

- [ ] Île fermée ou réduite, la session `essai-a` finit (demandez « réponds ok »). Attendu : l'île s'ouvre seule sur « essai-a a terminé » (Claude Code finished), avec sa dernière phrase, le son `finish`, et Klay qui saute, vrille et retombe avec des étincelles. La pastille repasse au repos 5,2 s plus tard. L'île reste ouverte jusqu'au prochain survol suivi d'une sortie, ou jusqu'à un clic ailleurs. Cela vaut aussi quand la pastille de la session n'a pas le focus.
- [ ] Île ouverte par le survol, pointeur posé en bas de l'île, une session finit. Attendu : l'île passe sur « terminé » (160 pt) et ne se replie pas seule, même si le pointeur se retrouve sous elle. Un survol puis une sortie la replie 0,6 s après.
- [ ] (facultatif) Quittez puis relancez l'app pendant qu'une session tourne, et faites-la finir pendant le salut de lancement (les 4 premières secondes). Attendu : la vue « terminé » remplace le salut ; un clic ailleurs ou Échap la ferme. Si Klay vivait sur le bureau, il y retourne ensuite.
- [ ] Terminez une session avec une réponse en Markdown (titres, listes). Attendu : la vue « terminé » et la ligne de la maison montrent le premier paragraphe en texte simple.
- [ ] Île ouverte sur le chat (⌃⌥Espace) avec un brouillon tapé sans l'envoyer, une session finit. Attendu : le brouillon reste, la vue ne change pas, la pastille reçoit un badge « terminé », le son `finish` est joué. Même résultat sur la vue mail (déposez un fichier, cliquez « Envoyer par email » (Send by email), tapez sans envoyer), sur la vue « … est prêt. », sur un résultat et sur les réglages de l'île. N'envoyez aucun email.
- [ ] Île épinglée (⌘P) sur la maison, une session finit. Attendu : la vue ne change pas, badge seul. Désépinglez puis faites finir une session. Attendu : l'île passe sur « terminé ».
- [ ] Île ouverte sur la maison (non épinglée), une session finit. Attendu : l'île bascule sur « terminé ».
- [ ] L'île est ouverte sur « essai-a a terminé », sans que vous l'ayez survolée. Tapez la demande suivante dans le terminal de `essai-a`. Attendu : la vue se replie en île réduite dès l'envoi. Recommencez la souris posée sur l'île, puis après un clic dans l'île : elle reste ouverte. Une demande tapée dans `essai-b` ne la replie pas.
- [ ] Les deux sessions tournent. `essai-a` finit alors que `essai-b` a travaillé entre-temps. Attendu : la vue « terminé » porte le dossier `essai-a` et sa dernière phrase. « Open terminal » (Ouvrir le terminal) ramène le terminal de `essai-a`, pas celui de `essai-b`.
- [ ] Une autorisation attend pour `essai-a`, et `essai-b` finit. Attendu : l'île ne change pas de vue, la pastille de `essai-b` reçoit un badge « terminé ».
- [ ] (facultatif) Une question attend pour `essai-a`, et une autre session de la même pastille finit. Attendu : la carte reste, la pastille ne passe pas à « terminé », badge seul. Répondez à la carte : la pastille est rétablie. Quand `essai-a` finit pendant sa propre question : badge seul, pas de vue « terminé » par-dessus.
- [ ] Une autorisation attend pour `essai-a`, puis `essai-a` finit. Attendu : la carte se ferme, l'île passe sur « terminé » de `essai-a` (pas sur la pastille qui avait le focus avant) et reste ouverte après 3 s.
- [ ] Session de l'app Claude qui finit. Attendu : la vue montre son projet et le bouton « Ouvrir Claude » (Open Claude). Restez plus de 10 s : la vue ne change ni de pastille ni de bouton à 5,2 s. Fermez-la (OK ou clic ailleurs). Attendu : la pastille de l'app Claude disparaît dans les 5 s. Après un clic ailleurs (île cachée), Klay ne ressort pas quand la pastille disparaît ; s'il ressort pour un autre événement, il se cache 60 s après que la souris est partie. Un nouveau tour lancé pendant que la vue est ouverte, ou dans les 5 s qui suivent sa fermeture, ne retire pas la pastille. De même, une demande tapée dans les 5 s qui suivent la fin d'une session Claude Code ne remet pas la pastille au repos pendant que Claude réfléchit, et une carte arrivée dans ces 5 s garde la pose de Klay.
- [ ] Un échec de fin de tour (par exemple, coupez le Wi-Fi pendant une réponse de Claude). Attendu : l'île s'ouvre sur la vue « Échoué » (Failed), avec le son `error` : le dossier de la session en échec, « Claude s'est arrêté sur une erreur », puis en rouge le texte de l'erreur que Claude affiche (par exemple « API Error: … ») ou, s'il n'y en a pas, « Aucun détail d'erreur disponible. ». « Ouvrir le terminal » (Open terminal) ramène le terminal de cette session, « Ouvrir Claude » pour une session de l'app Claude ; OK replie l'île. Aucun bouton ne reste sans effet. La ligne de la session montre le texte de l'erreur. Même règle que la fin : badge seul si une carte attend, si l'île sert à autre chose ou si elle est épinglée.

### 2.5 Maison (5 min)

- [ ] Sans session, hooks installés. Attendu : la maison fait 220 pt de haut. « Aucune conversation en cours. » en gris, Klay centré à gauche, pastilles à droite, aucune flèche ↗.
- [ ] Lancez trois sessions dans trois dossiers (deux terminaux différents, un VS Code si possible), puis une quatrième. Attendu : trois lignes au plus, la plus récente d'abord. Chaque ligne a un mini Klay de la couleur de l'état, l'état en clair (« Travaille », « Attend ton accord »…) et la dernière action sur une ligne tronquée. Un titre long se coupe, l'état reste entier.
- [ ] Cliquez la ligne d'un terminal. Attendu : ce terminal passe devant, pas un autre, et l'île se replie. Cliquez la ligne VS Code. Attendu : VS Code passe devant. Fermez un terminal puis cliquez sa ligne. Attendu : l'app Claude s'ouvre (`claude://`).
- [ ] Session de l'app Claude (onglet Code). Attendu : elle a sa ligne, et son clic ouvre l'app Claude.
- [ ] Répondez depuis l'île à une autorisation (Autoriser, Refuser, Toujours) et à une question. Attendu : les choix apparaissent sous les conversations, en gris clair : « HH:mm · dossier · demande · Autorisé », la demande étant le texte de la carte (« Write · essai.txt », la commande…). Une commande longue se coupe et la réponse reste visible. Une réponse à plusieurs choix de plus de 20 caractères finit par « … ». Après 6 choix, seuls les 5 derniers s'affichent. Une demande traitée dans le terminal, ou « Répondre dans le terminal », n'ajoute rien. Faites-le aussi pour une session de l'app Claude : le nom du projet apparaît comme session. (facultatif) `~/Library/Application Support/NotchBuddy/choices.json` garde 20 entrées au plus, en local.
- [ ] Une autorisation arrive île ouverte sur la maison. Attendu : la carte passe devant (160 pt), puis l'île revient à la maison après la réponse.
- [ ] Faites une action de plus de 80 caractères dans une session. Attendu : sa ligne finit par « … » (80 caractères en tout). Quittez une session (`/exit`). Attendu : sa ligne disparaît, même si une autorisation attend pour une autre session de la même pastille.
- [ ] Aucun « VS Code » ni « Cursor » dans l'île ni dans les pastilles. Une session VS Code s'affiche sur la pastille « Claude Code ».
- [ ] (facultatif) Libellés d'état en français, que le Mac soit réglé en français ou en anglais.
- [ ] (facultatif) Laissez une session finie 30 min sans événement, puis rouvrez l'île. Attendu : sa ligne a disparu. Une ligne qui attend un accord reste.
- [ ] (facultatif, jeton GitHub dans Réglages, Integrations) Cliquez la pastille GitHub. Attendu : la carte GitHub est inchangée, dans une bande de 98 pt centrée dans la carte. Titre, trois lignes de stats et bouton ↗ (vers github.com/pulls) sont calés en haut de la bande et alignés sur Klay. Cliquez une ligne : le détail s'ouvre, Échap le ferme d'abord. Comparez à une capture de l'ancien build (île de 160 pt) si vous en avez une.
- [ ] (facultatif, Spotify) Cliquez la pastille Spotify, en lecture puis au repos. Attendu : carte inchangée dans la même bande, ↗ vers Spotify. Klay danse quand Spotify joue. Même contrôle pour la carte GitHub non configurée, le détail GitHub (« My PRs »…) et la carte de forfait si le relais de forfait est installé (Réglages, Agents, Plan usage).

### 2.6 Zone de dépôt (3 min)

- [ ] Glissez un fichier du Finder vers l'encoche. Attendu : Klay, les bras ouverts, au centre de la carte, avec « Dépose ton fichier » dessous. Plus de puces PDF, Images, Code, Docs ni de « Drop your files here ». Contour et voile verts quand le fichier est au-dessus.
- [ ] Observez la figure. Attendu : elle bouge doucement (balancement, mains, clignement toutes les 3,6 s) et ses yeux suivent le curseur. Les mains à liseré se lisent sur les rayons. Rien n'est rogné en haut de la carte.
- [ ] Lâchez le fichier. Attendu : le bac se forme à l'entrée, la fente s'ouvre à l'approche, le fichier est aspiré, Klay mâchonne, la barre « Envoi de … en cours » (Uploading …) avance, puis la vue « … est prêt. » s'ouvre avec ses boutons. La figure s'assombrit quand le bac passe devant et disparaît avec la zone. À noter : à 25 %, yeux, moyeu, jambes et liseré des bras forment-ils un seul fantôme uniforme ?
- [ ] À noter : pendant le glissement, la carte montre le bac à gauche et Klay bras ouverts au centre (deux personnages). Cela vous gêne-t-il ?
- [ ] Onglet Déposer (bouton + de l'en-tête). Attendu : même figure et même texte. Le texte devient vert pendant un glissement. Rien n'est rogné en haut de la figure.
- [ ] (facultatif) Déposez trois fichiers. Attendu : le libellé dit « 3 fichiers ».

### 2.7 Animations de Klay (5 min)

Île ouverte sur la maison, pour voir les bras et les jambes.

- [ ] Bougez le pointeur lentement autour de l'île. Attendu : les yeux de Klay suivent (blancs et pupilles), l'œil du côté tourné se rétrécit, puis la figure entière se penche vers le pointeur, avec un léger dépassement.
- [ ] Survolez Klay. Attendu : clignement, yeux plus grands, sursaut avec les mains levées, Klay monte un peu et regarde le curseur. En sortant, tout revient. Immobile 1,9 s sur Klay : émote Amour (cœurs).
- [ ] Laissez le pointeur immobile 4 à 6 s. Attendu : Klay regarde autour de lui, parfois vers le pointeur. Le moindre mouvement le ramène aussitôt.
- [ ] (facultatif, 25 s à 70 s) Laissez le pointeur immobile. Attendu : un tapotement du pied toutes les 5 à 12 s, puis après 25 s un étirement (mains en haut, yeux fermés) et plus tard un bâillement.
- [ ] Cliquez Klay. Attendu : écrasement, mains projetées vers le haut et de côté puis qui se posent, émote « agacé », halo violet. Cliquez trois fois en moins de 1,7 s. Attendu : Klay est sonné (double roulade), la vue « Trop de clics d'un coup. » (Too many hits at once.) s'affiche 3,3 s, puis l'île reprend sa vue d'avant.
- [ ] Trois clics rapides sur Klay posé sur le bureau. Attendu : l'île s'ouvre sur la vue « sonné » puis reste ouverte jusqu'au prochain survol suivi d'une sortie, ou jusqu'à un clic ailleurs.
- [ ] Observez les poses. Attendu : les mains levées se lisent sur les rayons blancs. Bras levés en autorisation, V en fin de session, grattage de tête en question, salut de la main à l'approche. Les épaules ne montrent aucun bord sombre sur le moyeu, y compris pendant le fondu de la boîte aux lettres.
- [ ] Observez les couleurs d'état, sur le halo de Klay, son badge et le halo de l'île derrière lui. Attendu : travaille en teal, réfléchit en teal plus pâle, autorisation en ambre, question en or, erreur en brique, terminé en vert, sonné en brique claire. Les points, le « ! » et le « ? » du badge sont foncés et lisibles.
- [ ] (facultatif) Limite d'usage atteinte : ocre. Île ouverte à la main sans tâche depuis 10 min : gris filet, yeux fermés, « z » qui montent.
- [ ] Voiles des cartes d'alerte. Attendu : autorisation ambre, question or, erreur brique, terminé vert, sonné brique claire. La carte du chat (⌃⌥Espace) a un voile teal pâle : le texte reste lisible dessus.
- [ ] Île réduite (membres masqués). Attendu : les yeux suivent et glissent toujours, rien ne tremble.
- [ ] Mini Klays des pastilles et des lignes de la maison. Attendu : les yeux se promènent, pas de membres, pas de penché.
- [ ] Les particules (cœurs, « z », sueur) montent à vitesse normale, pas trois à six fois trop vite.
- [ ] Klay sur le bureau (⌃⌥D). Attendu : mouvement fluide, clignement et sursaut au survol. Après 2 min sans bouger, il dort.
- [ ] (facultatif) Même vitesse de mouvement sur un écran ProMotion (120 Hz) et un écran externe 60 Hz.
- [ ] (facultatif, Spotify en lecture) Île réduite ou maison sur la pastille Spotify. Attendu : Klay danse, les membres rebondissent avec les sauts.
- [ ] Jumelles de l'état « cherche ». Dans `~/essai-a`, demandez « cherche le mot bonjour dans ce dossier » (Grep ou `grep`), puis « cherche sur le web la date de sortie de macOS 26 » (WebSearch). Île ouverte sur la maison, pastille Claude Code en focus. Attendu : Klay lève les jumelles à chaque recherche, au moins 1,5 s même pour un Grep très court : deux tubes sombres avec verre teal et molette, mains sur les côtés des tubes, balayage gauche et droite avec le corps qui suit, pas d'yeux, badge « ••• » teal pâle. La ligne de la session dit « Cherche ». Une modification de fichier qui suit le remet sur « Travaille ». Dans la ligne de la session et les pastilles, le mini Klay garde ses yeux, sans jumelles. (facultatif, demande Node.js) Même dessin sur le banc de rendu : `cd tools/klay-preview && npm install && npx vite`, cellule de l'état « searching ».

### 2.8 Réglages et raccourcis (2 min)

- [ ] Réglages, General, Behavior. Attendu : les réglages « Open on hover » et « Masquer après … min sans mouvement » (Hide after … min without movement) ont disparu. Seul « Fermer après … s d'inactivité » (Close after) reste.
- [ ] Réglages, Active pills. Attendu : plus de sélecteur Main. « Claude Code » est marqué Main. Claude Desktop, GitHub et Spotify ont un interrupteur et une palette de couleur.
- [ ] ⌘E dans l'île. Attendu : rien. Réglages, Shortcuts : plus de ligne ⌘E.
- [ ] ⌃⌥T avec une session ouverte. Attendu : le terminal ou l'éditeur de la session la plus récente passe devant (l'app Claude si c'est une session de l'app). Sans session ou terminal fermé : le terminal de la pastille en focus, puis Terminal.
- [ ] (facultatif, ancien build avec des intégrations retirées) Après le premier lancement de cette build : `ls ~/Library/Application\ Support/NotchBuddy/recap.json` ne trouve rien, `defaults read ai.klayer.island recapEnabled` dit que la clé n'existe pas, et l'app Trousseau n'a plus d'élément `ai.klayer.island` pour `stripe-api-key` ni `openai-api-key`. La clé Anthropic et le jeton GitHub sont toujours là.
- [ ] (facultatif, ancien build) Quittez l'app, faites `defaults write ai.klayer.island mainPill agent_cursor`, relancez. Attendu : l'app démarre sur Claude Code, la clé `mainPill` disparaît, `activeIntegrations` ne contient plus `agent_cursor`.

### 2.9 Performance (2 min, plus l'attente)

- [ ] Île cachée, souris loin, aucune session ouverte, aucun événement pendant 5 min (par exemple pendant une pause). Ouvrez ensuite le Moniteur d'activité, colonne % CPU de « KlayerIsland ». Attendu : 0 %.
- [ ] Île réduite. Attendu : moins de 3 % de CPU et moins de 100 Mo de mémoire (critères de `docs/SPEC.md`, §12).
- [ ] Île ouverte sur la maison avec trois sessions. À noter : le CPU, trois mini Klays de plus qu'avant. Puis, avec les mêmes sessions, une carte d'autorisation à l'écran. À noter : le CPU, normalement plus bas, car les mini Klays de la maison s'arrêtent derrière la carte.
- [ ] Klay sur le bureau, éveillé puis endormi. À noter : le CPU. Il est affiché à la fréquence de l'écran éveillé (c'était 30 images par seconde avant) et à 10 images par seconde endormi.
- [ ] Onglet Déposer ouvert. Attendu : charge faible (30 images par seconde).

## 3. Spikes

Les trois spikes se font sur votre Mac, avec les vraies apps. S2 (Cowork) est hors périmètre de cette build.

### S1 : l'app Claude retire-t-elle sa fiche quand l'île répond ?

- [ ] Mettez l'app Claude à jour. Notez sa version. Vérifiez que les hooks sont installés et que le relais contient la détection de l'app (`grep -c CLAUDE_CODE_ENTRYPOINT ~/Library/Application\ Support/NotchBuddy/nb-hook.py` affiche 2).
- [ ] Dans l'app Claude, onglet Code, ouvrez un dossier d'essai, en mode qui demande les autorisations. Demandez « crée le fichier essai-s1.txt avec le mot bonjour ».
- [ ] L'île s'ouvre sur la carte de permission. Cliquez Autoriser dans l'île (pas dans l'app). Regardez la fiche de permission de l'app pendant et après le clic.
- [ ] Recommencez en répondant d'abord dans l'app. Attendu : la carte de l'île se ferme et affiche « Handled in Claude. » pendant 3 s.
- [ ] (facultatif, 2 min) Laissez une autorisation sans réponse. Attendu : la note « Still waiting in Claude. » apparaît et la fiche de l'app reste utilisable.

Question : quand l'île répond à une autorisation du mode Code, la fiche de l'app Claude disparaît-elle ?

À noter :

- la fiche disparaît tout de suite, après un délai, ou elle reste ;
- si elle reste, ce qui arrive quand vous cliquez dessus (double exécution, erreur, rien) ;
- le fichier est créé une seule fois ;
- la version de l'app Claude.

Si la réponse est non : la fiche reste dans l'app. L'île affichera alors la demande en lecture seule, avec « Répondre dans Claude » (`docs/superpowers/specs/2026-10-08-klayer-island-refonte-design.md`, §10). Ce mode reste à développer.

Réponse S1 : …

### S3 : `claude -p` fonctionne-t-il sans connexion de plus, et Gmail y est-il disponible ?

- [ ] Dans un terminal, lancez `which claude` et `claude --version`. Si Claude Code n'est pas installé, notez-le, installez-le d'après https://code.claude.com/docs/en/quickstart et ne lancez pas `/login`.
- [ ] Lancez `claude auth status` et notez la sortie (la méthode de connexion). Si l'île réagit à ces commandes (les hooks Klayer sont installés), notez-le.
- [ ] Lancez `[ -n "$ANTHROPIC_API_KEY" ] && echo "clé API définie" || echo "pas de clé API"`. Une clé API définie prend le pas sur la connexion claude.ai : notez-le. Ne copiez jamais la clé.
- [ ] Lancez `claude -p --model claude-haiku-5-5 "bonjour"`. Notez la réponse, ou le message d'erreur mot pour mot.
- [ ] Lancez `claude mcp list`. Notez si une ligne nomme Gmail, et son état.
- [ ] Pour le nom exact de l'outil Gmail, lancez `claude -p --model claude-haiku-5-5 --output-format stream-json --verbose "ok" | grep -o -i 'mcp__[A-Za-z0-9_-]*gmail[A-Za-z0-9_-]*' | sort -u`. Si la commande n'affiche rien, collez les premières lignes de la sortie sans le `grep`.

Questions : `claude -p` répond-il sans connexion supplémentaire ? `claude mcp list` montre-t-il Gmail ?

À noter :

- la réponse de Haiku, ou l'erreur exacte ;
- la sortie de `claude auth status` ;
- si vous vous étiez déjà connecté dans le terminal avec `claude` : dans ce cas la réponse ne dit rien du partage de la connexion avec l'app desktop. Un test propre se fait sur un Mac où seule l'app desktop est connectée ;
- la ligne Gmail de `claude mcp list` et son état ;
- les noms d'outils Gmail trouvés, dont celui qui finit par `create_draft`.

Si la réponse est non : le chat et l'email ne peuvent pas utiliser la connexion de l'app desktop. L'île demandera de connecter Claude Code dans un terminal (`claude`, puis `/login`). Si Gmail manque dans `claude mcp list`, l'île ne pourra pas préparer de brouillon et le dira. Ces messages sont prévus au lot 4.

Réponse S3 : …

### S4 : `granola://new-document` démarre-t-il l'enregistrement ?

- [ ] Quittez Granola. Dans un terminal, lancez `open "granola://new-document"`. Observez Granola.
- [ ] Granola ouvert, relancez la même commande. Observez à nouveau.
- [ ] Cliquez le bouton Granola de l'île réduite (même lien). Comparez avec la commande.

Question : le lien lance-t-il l'enregistrement ?

À noter :

- Granola se lance-t-il, une note vierge s'ouvre-t-elle ;
- l'enregistrement démarre-t-il (indicateur d'enregistrement de Granola, micro actif), tout de suite ou après un délai ;
- Granola demande-t-il une autorisation (micro, autre) ;
- la version de Granola.

Si la réponse est non : l'icône ouvre la note (c'est déjà ce que fait le bouton) et vous lancez l'enregistrement vous-même dans Granola.

Réponse S4 : …

S2 (Cowork) : hors périmètre de cette build, rien à tester.

## 4. Ce qu'il faut me renvoyer

Renvoyez-moi ces éléments dans le fil où vous avez reçu ce lien :

- [ ] Les réponses S1, S3 et S4, avec les notes demandées sous chaque spike.
- [ ] Chaque point en échec avec sa capture d'écran, et ce que vous avez vu à la place.
- [ ] Les points « À noter » : Trousseau, autorisation pour Échap, infobulle Granola, deux Klay pendant le glissement, CPU relevés.
- [ ] Le nom exact de l'outil Gmail, si S3 le montre.
- [ ] Votre contexte : version de l'app (en haut de la barre latérale des Réglages), version de macOS, modèle de Mac (avec ou sans encoche), versions de l'app Claude et de Claude Code.

## 5. Lot 4 (à venir)

Cette section sera ajoutée quand le lot 4 sera livré : chat Haiku par le Claude Code du Mac et brouillon Gmail par le connecteur de votre compte Claude.

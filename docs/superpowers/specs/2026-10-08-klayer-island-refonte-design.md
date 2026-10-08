# Klayer Island : refonte centrée app Claude

Date : 8 octobre 2026. Statut : à valider par Baptiste.

## 1. Objectif

Klayer Island sert aux consultants Klayer qui travaillent dans l'app Claude desktop (mode Code et Cowork). Elle répond à une question : **Claude a-t-il besoin de moi, ou a-t-il fini ?**

Critères de succès :

- Aucune demande de Claude (autorisation, question) ne reste sans réponse faute d'avoir été vue.
- Une fin de session se voit sans aller chercher l'app Claude.
- Une question rapide obtient une réponse dans l'île, sans connexion à configurer.
- L'app ne montre plus rien qui relève du développement (éditeurs, diff, services tiers), à l'exception de GitHub.

## 2. Périmètre

- **Mac uniquement.** `windows/`, `linux/`, les workflows Windows et Linux et leurs docs sont retirés. La référence de dessin de Klay (`engine.ts`, `glyph.ts`, aperçu) passe dans `tools/klay-preview/` pour garder un banc de rendu dans le navigateur.
- **Aucune trace de l'iPhone** : chaînes `iphone.*`, `live-activity`, iCloud et Dynamic Island de `Localizable.xcstrings`, branches `#if APPSTORE` (91 occurrences), mentions dans la doc.
- **Hors périmètre** : les conversations du mode Chat de l'app Claude et les sessions Cowork qui tournent dans le cloud. Aucune source d'événement n'existe pour elles (voir §9).

## 3. Sources d'événements

| Source | Comment | État |
|---|---|---|
| Mode Code de l'app Claude | hooks Claude Code de `~/.claude/settings.json`, partagés avec l'app desktop ([doc hooks](https://code.claude.com/docs/en/hooks), [doc desktop](https://code.claude.com/docs/en/desktop)) | fonctionne déjà pour le suivi ; les autorisations et questions sont aujourd'hui renvoyées à l'app (`HookServer.swift`, `processPermissionRequest`, réponse `ask`) |
| Claude Code en terminal | mêmes hooks | conservé tel quel, sans mise en avant |
| Cowork, mode local | Plugin « Klayer Island » dont les hooks écrivent sur la socket de l'île ([plugins](https://claude.com/docs/plugins/platform-support)) | spike S2 |

Changement : l'exclusion `claude-desktop` est levée. Les autorisations et questions des sessions du mode Code s'affichent dans l'île avec Allow, Deny, Always, et la décision part par le hook. La doc indique que la première réponse (hook ou fiche de l'app) s'applique ; reste à vérifier que la fiche de l'app disparaît (spike S1).

Les agents non Claude (Codex, Gemini CLI, Antigravity, Cursor, Copilot, Muse, OpenCode, Amp, Hermes) sont retirés.

## 4. Comportement de l'île

| Situation | Comportement |
|---|---|
| Souris à moins de 120 pt de l'encoche | Klay sort en mode réduit, regarde le pointeur et fait coucou de la main, avec le son `peek`. L'île ne s'ouvre pas. |
| Souris sur l'encoche | L'île s'ouvre en grand après 250 ms, son `open`, Klay salue (son `greet`, notification `.botGreet` enfin émise). |
| Clic sur l'encoche fermée | Rien. L'île ne s'ouvre jamais au clic. |
| Clic hors de l'île ouverte | L'île se referme, son `close`. Si une demande est en attente, elle se replie en mode réduit : Klay garde son badge et l'île se rouvre au survol. |
| Claude demande une autorisation ou pose une question | L'île s'ouvre seule, même si l'utilisateur est absent, et reste ouverte jusqu'à la réponse. |
| Claude a fini une session | L'île s'ouvre seule sur la fin de session et reste ouverte jusqu'au prochain survol suivi d'une sortie, ou un clic ailleurs. Le code mort `pinForFinished` est supprimé. |
| Échap | Ferme, comme un clic ailleurs. |

Les clics à l'intérieur de l'île ouverte gardent leur rôle (boutons, chat). Un clic sur Klay dans l'île ouverte reste l'émote « agacé ».

## 5. Île réduite

Les 4 pastilles de couleur (grille de mini-Klay) disparaissent, ainsi que les minis de l'animation d'accueil. À leur place : une **icône Granola grisée**. Un clic dessus ouvre `granola://new-document`. C'est le seul clic actif sur l'île réduite.

- Le lien crée une note ; le démarrage automatique de l'enregistrement n'est pas confirmé (spike S4).
- L'icône est un pictogramme micro sobre avec l'infobulle « Nouvelle note Granola ». Le logo Granola est leur marque : on ne le reprend pas sans accord.

## 6. Île ouverte

**En-tête** : maison, chat, réglages, son. La jauge de forfait Claude reste ; celle de Codex part.

**Maison**, de haut en bas :

1. **Conversations en cours** : une ligne par session (titre ou dossier du projet, état, mini-Klay de la couleur de l'état, dernière action en une ligne). Un clic ouvre l'app Claude (`claude://`).
2. **Derniers choix demandés par Claude**, en gris : les 5 dernières autorisations et questions, avec la réponse donnée et l'heure. Historique local, 20 entrées au plus, jamais envoyé ailleurs.
3. **Demande en cours** quand il y en a une : la carte Allow, Deny, Always ou les choix de la question, au-dessus de tout.

Retirés : pastilles d'éditeurs (VS Code, Cursor…), boutons terminal et éditeur, cartes de diff, compteurs +N −M, récap hebdomadaire (statistiques de code).

**GitHub** reste : sa pastille et sa carte (pull requests, revues demandées, CI) s'affichent sous les conversations, comme aujourd'hui.

## 7. Chat rapide

- **Modèle** : `claude-haiku-5-5`, fixé, sans sélecteur ([modèles](https://platform.claude.com/docs/en/models/overview)).
- **Sans connexion dans l'app** : l'île lance le Claude Code installé sur le Mac (`claude -p --model claude-haiku-5-5 --output-format stream-json`), qui utilise le login claude.ai de l'utilisateur. Aucune clé, aucun jeton stocké par l'île.
- **Sans outils** : aucun accès aux fichiers ni au shell depuis le chat, sauf le fichier déposé (§8).
- **Prérequis** : la CLI Claude Code installée et connectée. L'app desktop embarque sa propre CLI ; le partage des identifiants entre les deux n'est pas confirmé (spike S3). Si la CLI manque, l'île affiche « Installer Claude Code » avec le lien d'installation.
- **Cadre d'usage** : les conditions d'Anthropic interdisent à un tiers de proposer le login claude.ai ou de router des requêtes par les identifiants d'un forfait, mais n'empêchent pas un utilisateur de se servir de son Claude Code non modifié ([legal](https://code.claude.com/docs/en/legal-and-compliance)). Lecture à faire valider par un fondateur avant diffusion à l'équipe.

Retirés : Gemini, OpenAI, Ollama, LM Studio, sélecteur de modèle, clés API, `LocalChat.swift`, recherche web.

## 8. Dépôt de fichier et email

- **Zone de dépôt** : le pictogramme et les puces « PDF / Images / Code / Docs » sont remplacés par Klay qui ouvre les bras ; la suite (Klay devient boîte aux lettres et avale le fichier) ne change pas.
- **Poser une question** : chat Haiku avec lecture autorisée sur ce seul fichier.
- **Préparer un email** : `claude -p` avec le seul outil de création de brouillon du connecteur Gmail de l'utilisateur ([MCP](https://code.claude.com/docs/en/mcp)). L'île montre le brouillon et un bouton « Ouvrir dans Gmail ». Rien ne part sans action de l'utilisateur dans Gmail (règle Klayer). Resend et Mail.app sont retirés. Spike S3.

## 9. Suppressions

| Retiré | Fichiers principaux |
|---|---|
| Stripe, n8n, Resend, Cal.com, Notion, Vercel | `*Poller.swift` sauf `GithubPoller.swift`, cartes dans `IslandViewContent.swift`, section Integrations de `SettingsView.swift`, `AppState`, `DemoEngine` |
| Apple Music | `MusicController.swift`, `NowPlayingViews.swift`, `MusicPill`, `.musicReveal` |
| Chats non Claude | `IslandTypes.swift` (fournisseurs), `LocalChat.swift`, `ModelPickerView` |
| Agents non Claude | entrées de `PillCatalog.swift`, branches de `HookServer.swift`, scripts de plugins OpenCode, Amp, Hermes |
| Code iPhone et App Store | `#if APPSTORE`, chaînes et docs |
| Windows et Linux | `windows/`, `linux/`, workflows |
| Mode démo, récap hebdomadaire | `DemoEngine.swift`, `RecapStore.swift`, `WeeklyRecapView.swift` |

**Gardés** : GitHub (pull requests, revues, CI), Spotify (pastille et danse de Klay), Klay sur le bureau, raccourcis clavier, jauge de forfait Claude.

Point dur : `AgentSource.n8n` sert de source à toutes les pastilles de services et d'IA, GitHub compris : il est renommé `AgentSource.integration` et ne sert plus qu'à GitHub et Spotify.

## 10. Spikes avant implémentation

| # | Question | Critère de sortie |
|---|---|---|
| S1 | Quand le hook répond à une autorisation du mode Code, la fiche de l'app Claude disparaît-elle ? | Testé sur un Mac avec l'app Claude à jour. Si non : l'île affiche la demande en lecture seule avec « Répondre dans Claude ». |
| S2 | Un hook de Plugin Cowork (mode local) peut-il joindre la socket de l'île sur l'hôte ? | Un événement Cowork arrive dans l'île. Si non : Cowork hors périmètre. Klayer est-il en Team ou Enterprise ? À confirmer. |
| S3 | `claude -p` fonctionne-t-il avec le login de l'app desktop, et le connecteur Gmail y est-il disponible ? | Une réponse Haiku et un brouillon Gmail obtenus depuis l'île. |
| S4 | `granola://new-document` démarre-t-il l'enregistrement ? | Constaté sur un Mac. Sinon : l'icône ouvre la note et l'utilisateur lance l'enregistrement. |

Les spikes S1, S3 et S4 demandent un vrai Mac : je prépare la build, le test se fait sur ton poste.

## 11. Lots

1. **Nettoyage** (§2, §9) : retraits sans changement de comportement. Build CI verte.
2. **Comportement** (§4, §5) : survol, proximité, salut, clic ailleurs, icône Granola.
3. **Contenu** (§6) : conversations en cours, derniers choix, levée de l'exclusion `claude-desktop`.
4. **Chat et email** (§7, §8), après S3.
5. **Cowork** (§3), après S2.

## 12. Vérification

- Chaque lot : build macOS CI verte, tests `scripts/test-*.sh` adaptés, app téléchargeable.
- Nouveaux tests unitaires : règles d'ouverture de la machine à états (survol, clic, clic ailleurs, demande en attente) et historique des choix (20 entrées, ordre, persistance locale).
- Test manuel sur Mac par lot, avec une liste de contrôle jointe à chaque build.

# Klayer Island

**Klay vit dans l'encoche de votre Mac et suit vos sessions d'agents de code. Vous autorisez, répondez et relancez sans quitter ce que vous faites.**

Outil interne Klayer, fork de [Coucou](https://github.com/Louis-CFM/coucou) (licence MIT). Le nom, le personnage, l'icône et les sons sont propres à Klayer : voir [NOTICE.md](NOTICE.md).

![Klay, état par état](docs/media/klay-sheet.png)

## Klay

Klay est le glyphe Klayer avec deux yeux, des bras et des jambes. Le glyphe est tracé tel quel ; seuls les membres, les yeux et le halo coloré derrière les rayons bougent.

| État de l'agent | Ce que fait Klay |
|---|---|
| Au repos | respire, cligne des yeux, suit la souris du regard |
| Travaille | tape des deux mains et piétine sur place |
| Réfléchit | main au menton, regard en l'air |
| Cherche | lève des jumelles à deux mains, balaie l'horizon |
| Attend une autorisation | lève les deux bras et sautille |
| Pose une question | se gratte la tête, penché |
| Erreur | bras ballants, yeux plissés |
| Terminé | saute, fait un tour sur lui-même, bras en V |
| Limite atteinte | yeux fatigués, transpire |
| Dort | yeux fermés, des « z » s'envolent |

Cliquez-le : il se fâche. Trois clics rapides : il a le tournis. Clic droit : un emote « love ». Déposez un fichier sur l'île : il se change en boîte aux lettres et l'avale.

## Ce que fait l'app

- **Conversations en cours** : la maison de l'île liste vos sessions Claude, celles de l'app de bureau Claude comme celles de Claude Code dans un terminal ou un éditeur. Pour chacune : son dossier, son état en clair (« Travaille », « Attend ton accord »…), un mini Klay de la couleur de cet état et sa dernière action. Un clic ouvre la session : l'app Claude, ou le terminal ou l'éditeur où tourne Claude Code.
- **Derniers choix** : sous les conversations, en gris, les 5 dernières autorisations et questions auxquelles vous avez répondu depuis l'île, avec l'heure et la réponse. L'historique reste sur votre Mac.
- **Autoriser et répondre depuis l'île** : les demandes d'autorisation de Claude Code (Allow, Deny, Always), les questions `AskUserQuestion` à choix simple ou multiple. Une demande en attente passe devant la maison.
- **Fin de session** : l'île s'ouvre sur la session qui vient de finir, avec sa dernière phrase et un bouton qui ramène à son terminal ou à l'app Claude.
- **Chat** : Claude (API Anthropic). La clé reste dans le trousseau du système.
- **Quotas** : limites 5 heures et hebdomadaires de Claude dans l'en-tête de l'île.
- **Dépôt de fichier** sur l'île, puis question à Claude ou envoi par email (Mail.app).
- **Klay sur le bureau** : glissez-le hors de l'île, il flotte sur le bureau et revient quand un agent a besoin de vous.
- **GitHub** : PR, revues et CI dans l'île. Sa pastille a son mini Klay coloré.
- **Spotify** : pastille de lecture (pochette, progression, volume). Klay danse quand Spotify joue.
- **Raccourcis clavier** globaux, modifiables dans Réglages → Raccourcis.
- **10 langues**, dont le français.
- **Aucune télémétrie, aucun compte.** L'app ne parle qu'aux services que vous branchez.

Retirés par rapport à Coucou : widgets, synchronisation entre appareils, versions hors Mac, garde-robe et tenues de Mochi, mode démo, récap hebdomadaire, pastilles d'éditeurs (VS Code, Cursor), boutons terminal et éditeur, cartes de diff et compteurs +N −M.

## Installer

Pas de release publique : la diffusion reste interne. Construisez depuis les sources.

L'app est réservée au Mac (macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)) :

```bash
brew install xcodegen
cd NotchBuddy
xcodegen
open NotchBuddy.xcodeproj   # puis ⌘R
```

Renseignez votre équipe Apple dans `DEVELOPMENT_TEAM` (`NotchBuddy/project.yml`) pour signer.

## Configurer

Icône Klayer Island dans la barre des menus → **Réglages…**

| Quoi | Pourquoi | Où |
|---|---|---|
| Hooks Claude Code | sessions en direct et autorisations | **Install hooks** : l'app sauvegarde `~/.claude/settings.json`, fusionne ses hooks et montre le diff avant d'écrire |
| App de bureau Claude | une pastille pour les sessions de l'onglet Code | rien à installer : le relais des hooks Claude Code la reconnaît ; détail dans [docs/AGENTS.md](docs/AGENTS.md) |
| Clé API Anthropic | chat et questions sur un fichier | Réglages → Anthropic API, rangée dans le trousseau |
| Quotas Claude | jauge dans l'en-tête | Réglages → Agents → Plan usage → **Install relay** |
| GitHub | PR, revues et CI | Réglages → Integrations : jeton personnel rangé dans le trousseau, optionnel |

Si l'app ne tourne pas, le hook rend la main immédiatement : **Claude Code n'est jamais bloqué.**

## Développer

- Le dessin de référence de Klay est `tools/klay-preview/src/engine.ts` (Canvas 2D), que le code Swift de `KlayerIslandKit` reprend. Ce banc de rendu ne fait pas partie de l'app. Pour voir tous les états côte à côte : `cd tools/klay-preview && npm install && npx vite`, puis ouvrez la page affichée ; `?freeze=1.2` fige l'animation pour une capture.
- Le glyphe (`tools/klay-preview/src/glyph.ts`) est généré depuis le SVG officiel du design system Klayer : ne le modifiez pas à la main.
- Sons : `python3 scripts/gen-sounds.py`. Icônes : `node scripts/render-mac-icons.mjs`.
- Tests : scripts `scripts/test-*.sh` (nécessitent macOS). Banc de rendu : `cd tools/klay-preview && npm run check`.
- Règles pour les agents de code : [CLAUDE.md](CLAUDE.md).

## Licence

Code sous [licence MIT](LICENSE), copyright Louis Raillé pour le code d'origine et Klayer pour les modifications. Nom, personnage Klay, icône et sons : Klayer. Détail dans [NOTICE.md](NOTICE.md).

# Klayer Island, lot 6 : l'île au service de l'app Claude

Date : 9 octobre 2026. Retours de Baptiste au premier test Mac, design validé en conversation (« Vas-y »).

## 1. Objectif

L'île est la notification de l'app Claude : elle signale chaque fin de réponse ou de session et chaque demande (question, autorisation), même quand on est ailleurs. Le terminal n'est pas visé : son comportement ne change pas.

| Mode de l'app Claude | Source | Niveau |
|---|---|---|
| Code (onglet Code) | hooks Claude Code (`klayer_agent: claude-desktop`) | garanti par un mécanisme officiel |
| Chat (claude.ai dans l'app) | lecture de l'interface de l'app par l'accessibilité macOS | expérimental : dépend des libellés de l'interface d'Anthropic |
| Cowork | idem | expérimental ; le spike S2 (Plugin Cowork) reste ouvert |

## 2. Maison

De gauche à droite, sur 640 pt :

1. **Bande d'icônes**, très fine (environ 36 pt), verticale : Spotify (si actif), GitHub (si un jeton est réglé), Granola (toujours). Icônes grisées comme le bouton Granola de l'île réduite, infobulle. Un clic sur Spotify ou GitHub affiche leur carte existante à la place de la liste ; maison ou second clic : retour. Granola : nouvelle note (`GranolaLink`).
2. **Klay**, à sa place actuelle de la carte, un peu plus petit si besoin.
3. **Conversations**, au moins les 3/4 de la largeur : sessions en cours en haut, puis sessions finies du jour en gris avec leur heure de fin (10 au plus, effacées à minuit), puis les 3 derniers choix demandés par Claude.

Les pastilles Claude Code et Claude Desktop disparaissent de la maison (leurs sessions sont dans la liste) ; leurs identifiants restent pour le routage et les cartes.

## 3. Chat

Plus aucune pastille d'app ajoutée automatiquement (fenêtre de l'app précédente : Claude, Granola…). Restent seulement les contextes voulus : un fichier déposé puis « Poser une question », ou Klay glissé sur une fenêtre.

## 4. Zone de dépôt

Un seul personnage : Klay animé avec ses yeux. Il ouvre les bras quand un fichier approche, le suit des yeux et l'avale. Plus de boîte aux lettres ni de second Klay.

## 5. Onglet Code de l'app Claude

Une notification Claude Code d'une session de l'app Claude (autorisation demandée, attente d'une réponse) ouvre l'île sur cette session quand aucune carte n'est déjà affichée pour elle : « Claude attend ta réponse dans l'app Claude », bouton « Ouvrir Claude ».

## 6. Chat et Cowork : suivi expérimental

- Réglage « Suivre Chat et Cowork dans l'app Claude (expérimental) », activé par défaut ; demande la permission Accessibilité déjà utilisée par l'app.
- Lecture de l'interface de l'app Claude (`com.anthropic.claudefordesktop`, Electron : attribut `AXManualAccessibility`). Repère une réponse en cours (bouton d'arrêt), sa fin (le bouton disparaît), et des boutons d'autorisation.
- Fin de réponse ou demande alors que l'app Claude n'est pas au premier plan : l'île s'ouvre (« Claude a fini de répondre » ou « Claude attend ta réponse », titre de la conversation si lisible, « Ouvrir Claude »). Jamais de clic dans l'app Claude depuis l'île.
- CPU : lecture seulement quand l'app Claude est au premier plan, ou tant qu'une réponse repérée est en cours ; rien sinon (0 % quand l'app Claude est en arrière-plan sans réponse en cours).
- Diagnostic : bouton « Copier le diagnostic de l'app Claude » qui copie la structure de l'interface (rôles et libellés des boutons, jamais le texte des messages) pour régler les libellés sur ton Mac.
- Libellés repérés rangés à un seul endroit, testés ; si aucun ne correspond, rien ne se déclenche (pas de fausse alerte).

## 7. Hors périmètre

Terminal (inchangé), claude.ai dans un navigateur, réponse aux autorisations de Chat ou Cowork depuis l'île.

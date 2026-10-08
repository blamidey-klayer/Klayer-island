# Changelog

## 0.1.0 (non publiée)

Première version de Klayer Island, à partir de Coucou 0.2.2 (macOS). Voir [NOTICE.md](NOTICE.md).

- **Klay** remplace Mochi : le glyphe Klayer en blanc, deux yeux ronds, des bras et des jambes qui changent de pose selon l'état (travail, réflexion, recherche, demande d'autorisation, question, erreur, fin, limite atteinte, sommeil), et un halo de la couleur de l'état derrière les rayons.
- Nouvelle animation d'accueil, nouvelle icône, nouveaux sons synthétisés.
- Clic droit sur Klay : un emote « love » (la garde-robe et les tenues de saison sont retirées).
- Retirés : les widgets, la synchronisation avec d'autres appareils et toute version hors Mac. L'app est réservée au Mac.
- Retirés : les intégrations Stripe, n8n, Resend, Cal.com, Notion et Vercel, et Apple Music. GitHub et Spotify restent.
- Retirés : le mode démo (Réglages → Général) et le récap hebdomadaire (carte du lundi matin, entrée du menu, historique des sessions, image à partager). L'historique que le récap gardait est dans `~/Library/Application Support/NotchBuddy/recap.json` : vous pouvez supprimer ce fichier.
- Retirés : les agents autres que Claude (Codex, Gemini CLI, Antigravity, Copilot CLI, Muse Code, OpenCode, Amp, Hermes, Cursor en tant qu'agent) avec leurs installateurs de hooks et de plugins, la jauge de quota Codex, les fournisseurs de chat autres qu'Anthropic (Google AI, OpenAI, Ollama, LM Studio) et le sélecteur de modèle du chat. Les sessions Claude Code lancées dans Cursor s'affichent sur la pastille Claude Code. Le chat garde la clé Anthropic existante.
- À supprimer à la main si une version antérieure avait posé des hooks ou des plugins pour un agent retiré : Klayer Island ignore leurs événements et répond « ask » à leurs demandes d'autorisation, et une entrée restante peut gêner les appels d'outil de cet agent. Emplacements : `~/.codex/hooks.json`, `~/.copilot/hooks/klayer.json`, les entrées `nb-hook` de `~/.gemini/settings.json` et de `~/.gemini/config/hooks.json`, `~/.config/opencode/plugins/klayer.js`, `~/.config/amp/plugins/klayer.ts`, `~/.hermes/plugins/klayer` (et les lignes `transport: klayer` de `~/.hermes/config.yaml`), et les entrées `nb-hook` de `~/.config/muse/settings.json` pour Muse Code. Détail dans [docs/AGENTS.md](docs/AGENTS.md).
- Identifiants : bundle `ai.klayer.island`, clé de payload `klayer_agent`, dossier de support `~/Library/Application Support/NotchBuddy`.
- `tools/klay-preview/` garde le banc de rendu de Klay (planche de tous les états, dessin de référence en Canvas 2D).

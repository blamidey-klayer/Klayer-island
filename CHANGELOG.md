# Changelog

## 0.1.0 (non publiée)

Première version de Klayer Island, à partir de Coucou 0.2.2 (macOS). Voir [NOTICE.md](NOTICE.md).

- **Klay** remplace Mochi : le glyphe Klayer en blanc, deux yeux ronds, des bras et des jambes qui changent de pose selon l'état (travail, réflexion, recherche, demande d'autorisation, question, erreur, fin, limite atteinte, sommeil), et un halo de la couleur de l'état derrière les rayons.
- Nouvelle animation d'accueil, nouvelle icône, nouveaux sons synthétisés.
- Clic droit sur Klay : un emote « love » (la garde-robe et les tenues de saison sont retirées).
- Retirés : app iPhone, widgets, Live Activities, synchronisation iCloud et relais APNs, build App Store, versions hors Mac. L'app est réservée au Mac.
- Retirés : les agents autres que Claude (Codex, Gemini CLI, Antigravity, Copilot CLI, Muse Code, OpenCode, Amp, Hermes, Cursor en tant qu'agent) avec leurs installateurs de hooks et de plugins, la jauge de quota Codex, les fournisseurs de chat autres qu'Anthropic (Google AI, OpenAI, Ollama, LM Studio) et le sélecteur de modèle du chat. Les sessions Claude Code lancées dans Cursor s'affichent sur la pastille Claude Code. Le chat garde la clé Anthropic existante.
- Identifiants : bundle `ai.klayer.island`, clé de payload `klayer_agent`, dossier `~/.claude/klayer`.
- `tools/klay-preview/` garde le banc de rendu de Klay (planche de tous les états, dessin de référence en Canvas 2D).

# Origine et licences

Klayer Island est un fork interne de [Coucou](https://github.com/Louis-CFM/coucou), application open source de Louis Raillé, reprise au commit `a7bd575` (Coucou 0.2.2 pour macOS, 0.2.0 pour Windows et Linux).

## Ce qui vient de Coucou

Le **code source** de Coucou est publié sous [licence MIT](LICENSE). Nous le réutilisons et le modifions dans ce cadre : la mention de copyright d'origine est conservée dans `LICENSE`, comme la licence l'exige.

## Ce qui ne vient pas de Coucou

Le fichier `LICENSE-ASSETS.md` de Coucou exclut de la licence MIT le nom « Coucou », le nom et le personnage « Mochi », l'icône de l'app, les sons et les médias. Aucun de ces éléments n'est repris ici :

| Élément réservé dans Coucou | Remplacement dans Klayer Island |
|---|---|
| Nom « Coucou » | Klayer Island |
| Personnage Mochi (forme, look, expressions, animations) | Klay, dessiné à partir du glyphe Klayer, avec ses propres yeux, bras, jambes et poses (`windows/src/klay/engine.ts`, `NotchBuddy/Sources/KlayerIslandKit/`) |
| Garde-robe et tenues de Mochi | Retirées |
| Icône de l'app et de la barre des menus | Tuile teal Klayer et glyphe Klayer (`NotchBuddy/Assets.xcassets/`, `windows/src-tauri/icons/`) |
| 28 sons | Sons synthétisés par `scripts/gen-sounds.py` |
| Médias, captures, prototype de design (`docs/media/`, `design/`) | Non importés ; `docs/media/klay-sheet.png` est un rendu de Klay |
| App iPhone, widgets, relais APNs | Non importés |

## Marque Klayer

Le glyphe Klayer est la propriété de Klayer. Il est tracé tel quel à partir du fichier officiel du design system (`windows/src/klay/glyph.ts`, généré, à ne pas retoucher à la main). Klay ajoute autour du glyphe des yeux, des bras, des jambes et un halo : le glyphe lui-même n'est ni redessiné ni déformé.

## Diffusion

Usage interne Klayer. Toute diffusion hors de Klayer (store, release publique, site) se valide d'abord avec un fondateur.

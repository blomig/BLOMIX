# Blomix — Guide de développement

> **Version de référence** : 5.1  
> **Dernière mise à jour** : juillet 2026

---

## Prérequis

| Outil | Version minimale |
|---|---|
| macOS | Compatible Xcode 16 |
| Xcode | 16+ (Swift 6) |
| iOS (cible) | 18.0 (`IPHONEOS_DEPLOYMENT_TARGET`) |
| Compte Apple Developer | Requis pour Game Center, CloudKit et déploiement |

---

## Ouvrir et compiler

```bash
git clone https://github.com/blomig/BLOMIX.git
cd BLOMIX
open Blomix/Blomix.xcodeproj
```

1. Scheme **Blomix** → destination simulateur ou appareil physique.
2. **Signing & Capabilities** : renseigner votre `DEVELOPMENT_TEAM` (le projet référence `blomig.BLOMIX`).
3. `⌘R` pour build et run.

| Paramètre Xcode | Valeur actuelle |
|---|---|
| `MARKETING_VERSION` | 5.1 |
| `CURRENT_PROJECT_VERSION` | 62 |
| `PRODUCT_BUNDLE_IDENTIFIER` | `blomig.BLOMIX` |
| `SWIFT_VERSION` | 6.0 |
| Orientations | Portrait uniquement |

---

## Capabilities et services

Fichier : `Blomix/Blomix/Blomix.entitlements`

| Capability | Usage |
|---|---|
| **Game Center** | Classements solo/Zen, matchmaking PvP, invitations |
| **CloudKit** | Défis PvP asynchrones (`iCloud.blomig.BLOMIX`) |
| **Push (APS)** | Environnement `development` (à basculer en production pour release) |

### Tester le PvP

- Deux appareils ou simulateurs avec des comptes Game Center **distincts**.
- Connexion Game Center active dans Réglages iOS.
- Le RNG partagé et la synchronisation sont gérés par `BlomixPvPNetworking.swift`.
- Logique d’appariement et check-list de debug : [PVP_MATCHING.md](PVP_MATCHING.md).

### Tester les classements

- Authentification Game Center au lancement (`GameCenterManager.swift`, `ScoreManager.swift`).
- Simulateur : se connecter via Réglages → Game Center.

---

## Architecture (résumé)

La logique gameplay est centralisée dans `GameScene.swift` (~11k lignes) :

```
GameViewController          # Root UIKit, tutoriel, invitations GC
    └── SKView
        └── GameScene       # Grille, placement, Magix, stages, HUD SpriteKit

BlomixMoveAnalyzer          # Évaluation pure Swift (sans SpriteKit)
BlomixPvPNetworking         # GKMatch, état partagé, attaques
BlomixProceduralSFX         # Sons procéduraux Magix / feedback
BlomixL10n                  # Pont typé vers Localizable.strings
```

Détail complet : [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) §16.

---

## Fichiers de configuration importants

| Fichier | Rôle |
|---|---|
| `color_skins.json` | Skins de couleurs (Default + Perso) |
| `en.lproj/` / `fr.lproj/` | Chaînes UI, tips, citations |
| `Assets.xcassets/WebImages/` | Sprites blox, Magix, HUD, écrans |
| `Info.plist` | Polices embarquées, localisations, Game Center |

---

## Ajouter un son

1. Placer le fichier dans `Blomix/Blomix/Sounds/` (formats `.wav` / `.mp3`).
2. Référencer via l'enum `BlomixMatchSFX` dans `GameScene.swift`.
3. Documenter dans [VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md) (déclencheur, timing, volume).

Sons procéduraux : `BlomixProceduralSFX.swift` (pas de fichier audio).

---

## Ajouter une chaîne traduite

Voir [LOCALIZATION.md](LOCALIZATION.md). En bref :

1. Ajouter la propriété dans `BlomixL10n.swift`.
2. Ajouter la clé dans `en.lproj/Localizable.strings` **et** `fr.lproj/Localizable.strings`.
3. Utiliser `BlomixL10n.maCle` dans le code (jamais de chaîne en dur dans l'UI).

---

## Debug et flags utiles

| Flag / constante | Fichier | Effet |
|---|---|---|
| `evalEnabled` | `BlomixMoveAnalyzer.swift` | Active le moteur d'évaluation |
| `realtimeFeedbackEnabled` | `BlomixMoveAnalyzer.swift` | Popups `!!` / `?` en jeu (désactivé en prod) |
| `MagixRules.spawnProbabilityByKind` | `GameScene.swift` | Probabilités de spawn Magix |
| `PriksRules.spawnProbability` | `GameScene.swift` | Probabilité de spawn Brix |

---

## Tests

Aucune cible de tests unitaires n'est configurée actuellement.  
Validation manuelle recommandée :

- [ ] Partie solo complète (6 stages + game over)
- [ ] Mode Zen (pas de timer)
- [ ] Chaque variante Magix (spawn forcé en debug si besoin)
- [ ] Sauvegarde / reprise (`BlomixSoloSaveManager`)
- [ ] PvP invitation + match complet
- [ ] Classements Game Center
- [ ] Changement de langue FR ↔ EN
- [ ] Réglages audio (mix SFX / musique)

---

## Maintenance de la documentation

Lors d'une évolution majeure du gameplay, mettre à jour **en priorité** :

1. `RULES.md` si les règles joueur changent
2. `PROJECT_CONTEXT.md` pour la référence technique
3. `VFX_AND_ANIMATIONS.md` pour tout effet visuel ou sonore
4. `EVAL.md` si la fonction d'évaluation change
5. `GLOSSARY.md` si un terme est ajouté ou renommé
6. `CHANGELOG.md` à chaque release

Voir [CONTRIBUTING.md](CONTRIBUTING.md) pour les conventions de commit et de nommage.

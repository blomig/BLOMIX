# BLOMIX

Puzzle combinatoire **8×8** pour iOS : placez des blox colorés, formez des chaînes de 5+ blocs, gérez les Brix résistants, les blocs Magix et la montée en pression (lignes entrantes, bombes, timer).

| | |
|---|---|
| **Version** | 5.2 (build 64) |
| **Plateforme** | iOS 18+ (portrait) |
| **Stack** | Swift 6, UIKit, SpriteKit, Game Center |
| **Langues** | Français, Anglais, Allemand, Espagnol, Italien |

---

## Démarrage rapide

1. Cloner le dépôt et ouvrir `Blomix/Blomix.xcodeproj` dans **Xcode 16+**.
2. Sélectionner une équipe de signature dans *Signing & Capabilities* (bundle `blomig.BLOMIX`).
3. Lancer sur simulateur ou appareil (Game Center requis pour le PvP et les classements).

Guide détaillé : [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)

---

## Documentation

Toute la documentation est dans le dossier [`docs/`](docs/README.md) :

| Document | Contenu |
|---|---|
| [docs/README.md](docs/README.md) | Index de la documentation |
| [docs/RULES.md](docs/RULES.md) | Règles du jeu (joueurs) |
| [docs/PROJECT_CONTEXT.md](docs/PROJECT_CONTEXT.md) | Référence technique (mécaniques, HUD, sauvegarde) |
| [docs/PVP_MATCHING.md](docs/PVP_MATCHING.md) | Appariement PvP (CloudKit, GameKit, revanche) |
| [docs/VFX_AND_ANIMATIONS.md](docs/VFX_AND_ANIMATIONS.md) | Juice Spec : sons, particules, timings |
| [docs/EVAL.md](docs/EVAL.md) | Moteur d'évaluation des coups et hints |
| [docs/GLOSSARY.md](docs/GLOSSARY.md) | Terminologie canonique (code ↔ joueur) |
| [docs/LOCALIZATION.md](docs/LOCALIZATION.md) | Guide de localisation (FR/EN/DE/ES/IT) |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Build, debug, conventions de code |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | Historique des versions |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Conventions de contribution et maintenance doc |

Politique de confidentialité : [docs/privacy-policy.html](docs/privacy-policy.html)

---

## Structure du dépôt

```
BLOMIX/
├── Blomix/                 # Projet Xcode (app iOS)
│   ├── Blomix.xcodeproj
│   └── Blomix/             # Sources Swift, assets, localisation
├── docs/                   # Documentation
├── icones_app/             # Icônes et visuels marketing
├── Palette couleur/        # Références couleurs
└── old_web_code/           # Ancienne version web (archive)
```

---

## Licence

Projet propriétaire — tous droits réservés. Voir le dépôt pour les conditions d'utilisation.

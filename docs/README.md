# Blomix — Documentation

> **Version de référence** : 4.9  
> **Plateforme** : iOS (UIKit + SpriteKit), Swift  
> **Langues** : Français, Anglais, Allemand, Espagnol, Italien

---

## Contenu

### Joueurs et design

| Fichier | Description |
|---|---|
| [RULES.md](RULES.md) | Règles du jeu (mécaniques, scoring, modes) |
| [VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md) | Juice Spec : animations, particules, sons, timings |
| [GLOSSARY.md](GLOSSARY.md) | Terminologie canonique (code ↔ joueur ↔ UI) |

### Technique

| Fichier | Description |
|---|---|
| [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) | Référence technique (architecture, HUD, sauvegarde, localisation) |
| [EVAL.md](EVAL.md) | Fonction d'évaluation des coups (`BlomixMoveAnalyzer`) et hints |
| [LOCALIZATION.md](LOCALIZATION.md) | Guide de localisation FR/EN/DE/ES/IT (`BlomixL10n`) |

### Projet et maintenance

| Fichier | Description |
|---|---|
| [DEVELOPMENT.md](DEVELOPMENT.md) | Build, debug, tests manuels, conventions |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Conventions de contribution et maintenance doc |
| [CHANGELOG.md](CHANGELOG.md) | Historique des versions |
| [privacy-policy.html](privacy-policy.html) | Politique de confidentialité (FR/EN) |

---

## Résumé rapide

**Blomix** est un puzzle combinatoire 8×8. Le joueur place des **Blox** colorés pour former des chaînes de 5 blocs ou plus (8-connexité). Des **Brix** résistants, des **blocs Magix** aux effets spéciaux, des **bombes** et une **ligne entrante tous les 10 coups** rendent la gestion de l'espace critique.

**Modes principaux :**
- **Solo stagé** — timer par coup, multiplicateur de score progressif (6 stages)
- **Zen** — sans timer ni stages, classement dédié
- **PvP** — 1 vs 1 via Game Center, RNG partagé, attaques par paliers de score
- **Tutoriel** — séquence guidée au premier lancement

---

## Carte de lecture

| Je suis… | Commencer par… |
|---|---|
| Nouveau joueur / game designer | `RULES.md` → `GLOSSARY.md` |
| Développeur rejoignant le projet | `DEVELOPMENT.md` → `PROJECT_CONTEXT.md` |
| Sound / VFX designer | `VFX_AND_ANIMATIONS.md` → `GLOSSARY.md` |
| Traducteur | `LOCALIZATION.md` → `GLOSSARY.md` |
| Mainteneur / release | `CHANGELOG.md` → `CONTRIBUTING.md` |

---

*Maintenir ces fichiers à jour lors des évolutions majeures du jeu.*

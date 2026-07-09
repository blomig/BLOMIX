# Blomix — Documentation

> **Version de référence** : 4.7  
> **Plateforme** : iOS (UIKit + SpriteKit), Swift  
> **Langues** : Français, Anglais

---

## Contenu

| Fichier | Description |
|---|---|
| [RULES.md](RULES.md) | Règles du jeu pour les joueurs (mécaniques, scoring, modes) |
| [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) | Documentation technique du projet (architecture, HUD, sauvegarde, localisation) |
| [VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md) | Spécification VFX : animations, particules, sons, timings par objet/événement |
| [EVAL.md](EVAL.md) | Fonction d'évaluation des coups (`BlomixMoveAnalyzer`) et système de hints |

---

## Résumé rapide

**Blomix** est un puzzle combinatoire 8×8. Le joueur place des **Blox** colorés pour former des chaînes de 5 blocs ou plus (8-connexité). Des **Brix** résistants, des **blocs Magix** aux effets spéciaux, des **bombes** et une **ligne entrante tous les 10 coups** rendent la gestion de l'espace critique.

**Modes principaux :**
- **Solo stagé** — timer par coup, multiplicateur de score progressif (6 stages)
- **Zen** — sans timer ni stages, classement dédié
- **PvP** — 1 vs 1 via Game Center, RNG partagé, attaques par paliers de score
- **Tutoriel** — séquence guidée au premier lancement

---

*Maintenir ces fichiers à jour lors des évolutions majeures du jeu.*

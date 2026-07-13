# Blomix — Glossaire

> Terminologie canonique pour aligner la documentation, le code et l'UI.  
> **Version de référence** : 5.0

---

## Règle d'usage

| Contexte | Convention |
|---|---|
| **Documentation joueur** (`RULES.md`) | Noms d'affichage (Blox, Brix, CHROMAX…) |
| **Documentation technique** | Identifiants code + nom d'affichage entre parenthèses |
| **Code Swift** | Identifiants anglais (`priks`, `MagixKind.chromax`) |
| **UI localisée** | Chaînes `BlomixL10n` / `Localizable.strings` |

---

## Éléments de la grille

| Terme doc | Code | Description |
|---|---|---|
| **Blox** | `BlockType.color(String)` | Bloc coloré standard (6 couleurs) |
| **Brix** | `BlockType.priks(Int)` | Bloc résistant numéroté ; le compteur = coups restants avant disparition |
| **Bloc Magix** | `BlockType.magix(MagixKind)` | Bloc spécial déclenchant un effet à l'atterrissage |
| **Case vide** | `BlockType.empty` | Cellule sans contenu |
| **Grille** | `grid[row][col]` | 8×8 ; `row 0` = haut, `row 7` = bas |
| **Chaîne** | — | Groupe 8-connexe de ≥ 5 blox de même couleur |
| **Cascade** | — | Résolutions en chaîne après gravité (plusieurs vagues) |
| **Gravité inversée** | — | Les blocs remontent vers le haut ; les vides restent en bas |

### Couleurs des blox

| Nom logique (code) | Couleur |
|---|---|
| `red` | Rouge |
| `blue` | Bleu |
| `green` | Vert |
| `yellow` | Jaune |
| `purple` | Violet |
| `orange` | Orange |

---

## Variantes Magix

| Nom UI (RULES) | `MagixKind` | Symbole HUD |
|---|---|---|
| **CHROMAX** | `.chromax` | ? |
| **BRIXED** | `.brixed` | 9 |
| **CROSSX** | `.crosx` | + |
| **SCRUMBLX** | `.scrumblx` | = |
| **COLORX** | `.colorx` | O |
| **SAINTX** | `.cleanx` | ∞ |
| **TWISTX** | `.twistx` | ↻ |

> **Note** : le code utilise `crosx` (pas `crossx`) et `cleanx` (affiché SAINTX en UI).

---

## Mécaniques

| Terme | Description |
|---|---|
| **File d'attente** | 3 prochains blocs jouables : P0 (courant), P1, P2 |
| **Ligne entrante** | Nouvelle rangée injectée en bas tous les 10 coups |
| **Bombe** | Explosion déclenchée après N lignes entrantes ; efface une zone |
| **Placement** | Le joueur choisit une colonne ; le bloc tombe (gravité inversée) |
| **Toucher un Brix** | 8-connexité avec un Brix pendant une vague → compteur −1 (max 1/vague) |
| **Stage** | Palier solo (1–6) avec timer et multiplicateur de score croissant |
| **Multiplicateur** | Bonus de score lié au stage atteint |
| **Hint** | Suggestion de colonne optimale (5 par partie, `BlomixMoveAnalyzer`) |

---

## Modes de jeu

| Mode | Code / flag | Particularités |
|---|---|---|
| **Solo stagé** | Mode par défaut | Timer par coup, 6 stages, lignes entrantes, bombes |
| **Zen** | `isZenMode` | Pas de timer, pas de stages, classement dédié |
| **PvP** | `BlomixPvPMatchCoordinator` | 1 vs 1 Game Center, RNG partagé, attaques |
| **Tutoriel** | `tutorialBlockQueue` | Séquence scriptée au premier lancement |

---

## Scoring (termes)

| Terme | Description |
|---|---|
| **Score de chaîne** | Points pour une chaîne (taille, couleur, multiplicateur) |
| **Bonus Brix** | +20 pts quand un Brix atteint 0 |
| **Bonus SAINTX** | +200 pts en plus du score des cases effacées |
| **Milestone** | Seuils HUD 100 / 1000 (animation score) |
| **Best score** | Record personnel (Game Center + local) |
| **Elo** | Classement compétitif PvP (`BlomixEloManager`) |

---

## Technique et architecture

| Terme | Fichier / type | Rôle |
|---|---|---|
| **SimGrid** | `BlomixMoveAnalyzer` | Copie de grille pour simulation |
| **Lookahead** | `BlomixMoveAnalyzer` | Exploration 3 niveaux (P0→P1→P2) |
| **Solo save v7** | `BlomixSoloSaveManager` | Sauvegarde UserDefaults, reprise partie |
| **Skin** | `BlomixSkinCatalog` / `color_skins.json` | Palette de couleurs joueur |
| **Juice / VFX** | `GameScene.swift` | Particules, animations, sons de feedback |
| **SFX procédural** | `BlomixProceduralSFX` | Sons générés en code (Magix, UI) |
| **L10n** | `BlomixL10n.swift` | Pont typé vers `Localizable.strings` |

---

## Abréviations HUD

| Abrév. | Signification |
|---|---|
| **P0 / P1 / P2** | Positions dans la file de blocs à venir |
| **LIGNE x/10** | Compteur avant prochaine ligne entrante |
| **GC** | Game Center |
| **GK** | GameKit (framework Apple) |

---

## Synonymes historiques (à éviter dans la doc)

| Ancien / alternatif | Terme canonique |
|---|---|
| Priks (seul) | **Brix** (nom joueur) ; `priks` reste l'identifiant code |
| Bloc spécial | **Bloc Magix** |
| Mode classique | **Solo stagé** |
| Multi | **PvP** |

---

*Mettre à jour ce glossaire lors de l'ajout d'un nouveau terme gameplay ou d'une variante Magix.*

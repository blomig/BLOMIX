# Blomix — Documentation du projet

> **Version de référence** : 5.2  
> **Plateforme** : iOS (UIKit + SpriteKit), Swift  
> **Langues** : Français, Anglais, Allemand, Espagnol, Italien

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Grille et types de blocs](#2-grille-et-types-de-blocs)
3. [Génération aléatoire](#3-génération-aléatoire)
4. [Placement et gravité](#4-placement-et-gravité)
5. [Chaînes et cascades](#5-chaînes-et-cascades)
6. [Brix (Priks)](#6-brix-priks)
7. [Blocs Magix](#7-blocs-magix)
8. [Bombe](#8-bombe)
9. [Ligne entrante](#9-ligne-entrante)
10. [Scoring](#10-scoring)
11. [Modes de jeu](#11-modes-de-jeu)
12. [Tutoriel interactif](#12-tutoriel-interactif)
13. [Analyse des coups](#13-analyse-des-coups)
14. [Graphisme et police](#14-graphisme-et-police)
15. [Localisation](#15-localisation)
16. [Architecture des fichiers clés](#16-architecture-des-fichiers-clés)

---

## 1. Vue d'ensemble

Blomix est un jeu de puzzle combinatoire 8×8. Le joueur place des blox colorés pour former des chaînes de 5+ blocs de même couleur (8-connexité). Des Brix résistants, des blocs Magix aux effets variés, des bombes et une ligne entrante tous les 10 coups créent une montée en pression progressive.

Le mode solo principal (**stagé**) impose un timer par coup et un multiplicateur de score croissant. Un mode **Zen** sans contrainte temporelle et un mode **PvP** Game Center complètent l'offre.

---

## 2. Grille et types de blocs

| Paramètre | Valeur |
|---|---|
| Dimensions | 8 lignes × 8 colonnes |
| Taille d'une case | 40 pts (`GridLayout.cellPoints`) |
| Ligne du haut | `topRowIndex = 0` |
| Ligne du bas | `bottomRowIndex = 7` |

**Coordonnées** : `grid[row][col]` — `row = 0` = haut, `row = 7` = bas.

**Types de cellule (`BlockType`)**

| Type | Description |
|---|---|
| `.empty` | Case vide |
| `.color("nom")` | Blox coloré (6 couleurs) |
| `.priks(n)` | Brix, `n` coups restants |
| `.magix(MagixKind)` | Bloc Magix (7 variantes) |

---

## 3. Génération aléatoire

Fonction centrale : `randomNextPlayableBlock()` dans `GameScene.swift`.

Ordre de tirage :
1. **Magix** (~3 % cumulé) — voir `MagixRules.spawnProbabilityByKind`
2. **Brix** (1/8) — `PriksRules.spawnProbability`
3. **Couleur** (reste) — uniforme parmi les 6

**File d'attente** (3 blocs visibles) :

| Variable | Rôle |
|---|---|
| `currentBlock` | P0 — bloc en cours |
| `blockAfterCurrent` | P1 |
| `blockTwoAhead` | P2 |

En PvP : RNG partagé via `BlomixPvPMatchCoordinator`.  
En tutoriel : séquence scriptée (`tutorialBlockQueue`).

**Restrictions lignes entrantes** : pas de Magix ; pas de Brix en tutoriel (remplacés par des couleurs).

---

## 4. Placement et gravité

1. Tap sur colonne → bloc posé dans `highestEmptyRow` (première case vide depuis le haut).
2. Ghost preview après appui ≥ 120 ms.
3. Après toute suppression : `compactGridTowardTop()` — blocs remontent, vides en bas.

**Mode bombe** : tap direct sur une case (`placeBombAtCell`), pas de gravité pour le placement.

---

## 5. Chaînes et cascades

- Détection flood-fill 8-connexe, taille ≥ 5, couleur uniquement.
- Séquence : animation dissolution → décrément Brix adjacents → vidage grille → compactage animé → bonus colonne vidée → re-scan (`resolveChains`).
- `chainSeriesLevel` : 0 pour la première vague, +1 à chaque cascade.
- `chainClearWaveCount` : compteur de vagues avec chaîne (persisté en sauvegarde, historique).

**Score chaîne** (`chainClearScorePoints`) :

| Taille | Base |
|---|---|
| 5 | 5 |
| 6 | 7 |
| 7 | 10 |
| 8 | 13 |
| 9 | 15 |
| 10+ | 20 |

Bonus cascade : `+ chainSeriesLevel × 10`.

---

## 6. Brix (Priks)

| Paramètre | Valeur |
|---|---|
| Compteur initial | `PriksRules.initialHitsRemaining = 5` |
| Probabilité | 1/8 |
| Décrément | −1 par vague si 8-adjacent à une case effacée (max 1/vague) |
| Disparition | +20 pts, son `priksVanish` |
| Bombe | destruction instantanée (+20 pts), pas de décrément |

BRIXED (Magix) : crée un Brix(9), décrémente tous les autres de 2.  
SAINTX : laisse un Brix valant le nombre de cases effacées.

---

## 7. Blocs Magix

Définis dans `MagixKind` et `MagixRules` (`GameScene.swift`).

| Kind | Label popup | Effet principal |
|---|---|---|
| `.chromax` | CHROMAX | Chemin ≤ 15 cases → couleur unique → `resolveChains()` |
| `.brixed` | BRIXED | Devient Priks(9) ; −2 sur tous les Brix |
| `.crosx` | CROSSX | Ligne + colonne → couleur aléatoire → chaînes |
| `.scrumblx` | SCRUMBLX | Décalage horizontal par ligne ; −1 Brix global |
| `.colorx` | COLORX | Roulette → efface une couleur (score chaîne) |
| `.cleanx` | SAINTX | Vide la grille → Brix(N) + 200 pts |
| `.twistx` | TWISTX | Échange couleur ↔ Brix (valeur = min Brix, défaut 3) |

Rendu : shader dégradé animé + halo + particules orbitales (`applyMagixShader`).

Le lookahead (`BlomixMoveAnalyzer`) **ignore** les Magix (effets non simulables).

---

## 8. Bombe

| Paramètre | Solo | PvP |
|---|---|---|
| Stock initial | 5 | 3 |
| Gain en partie | Aucun (stock fixe) | — |

**Flux solo :**
1. Tap icône → `isBombMode = true`, `bombCount -= 1`
2. Tap case → tremblement 0,3 s → explosion 3×3
3. +10 pts, Brix détruits +20 pts chacun
4. `chainSeriesLevel = 1` → cascades
5. Annulation possible (restitue la bombe)

---

## 9. Ligne entrante

- `moveCount` s'incrémente de 1 après chaque pose dont la résolution se termine **sans chaîne en attente** (fin de `resolveChains` sans nouvelle chaîne).
- Injection quand `moveCount % 10 == 0` via `addRandomLinePushingGridUp()`.
- Preview visible quand `moveCount % 10 == 9`.
- 8 tirages indépendants ; animation montée depuis le bas.
- Game Over si colonne pleine avant injection.

**PvP** : `consumeNextIncomingAttackLineIfAny()` pour les attaques (palier score/50).

---

## 10. Scoring

| Action | Points |
|---|---|
| Chaîne | Table base + cascade |
| Brix disparu / bombe | 20 par Brix |
| Bombe utilisée | 10 |
| Colonne vidée | 10 par colonne |
| SAINTX | 200 |

**Multiplicateur stage** : appliqué dans `addScore()` si `isInStagedSoloMode`.

**Game Over** : `finalScore = score` (pas de bonus de fin Brix).

**Leaderboards Game Center** :
- Solo : score principal + moyenne
- Zen : `ZenMode`
- PvP : Elo (`elotype`)

---

## 11. Modes de jeu

### Solo stagé

`isInStagedSoloMode = pvpCoordinator == nil && !isTutorialMode && !isZenMode`

6 stages (`soloStages`) : timer décroissant, multiplicateur croissant.  
Timer relancé après chaque coup stable ; overlay de transition entre stages.

### Mode Zen

`isZenMode = true` : pas de timer, pas de stages, leaderboard Zen séparé.

### Sauvegarde solo

`BlomixSoloGameSave` (version **7**, clé `blomix_solo_save_v2`) :
- Grille, file P0/P1/P2, `moveCount`, `nextBottomLine`
- Bombes, score, `chainSeriesLevel`, `chainClearWaveCount`
- Stage, timer, `moveRecords`, `hintsRemaining`, `isZenMode`
- Auto-save en arrière-plan ; restauration au lancement
- Avant persistance : flush des états transitoires (`pendingGridWrite`, `pendingScoredChainClearCells`) pour éviter une grille incohérente après reprise

### PvP

`BlomixPvPNetworking.swift` + `BlomixPvPUI.swift` :
- Handshake RNG partagé
- Attaque : `score / 50` → ligne chez l'adverse
- Timer tour : 10 s
- Elo : `BlomixEloManager` (défaut 800, K adaptatif)
- Fin : victoire/défaite/déconnexion → retour solo sauvegardé

---

## 12. Tutoriel interactif

Machine à états `TutorialStep` :

| Étape | Déclencheur |
|---|---|
| Intro | Démarrage |
| Chaîne | Après 2 poses |
| Célébration chaîne | Chaîne réalisée (auto 2,8 s) |
| Ligne | 1ère injection |
| Brix | 1er Brix en P0 |
| Célébration Brix | Brix décrémenté (auto 2,8 s) |
| Bombe | Après 2 poses libres |
| Magix | Après bombe posée (auto 3 s) |
| Célébration finale | Auto 3 s → sortie |

Contraintes : bombe verrouillée jusqu'à l'étape ; Brix/Magix absents des lignes ; bouton Passer.

---

## 13. Analyse des coups

`BlomixMoveAnalyzer.swift` — moteur pure Swift, sans SpriteKit.

- Lookahead 3 niveaux (P0, P1, P2) : 512 simulations max
- `evalEnabled = true`, `realtimeFeedbackEnabled = false`
- 5 hints par partie (`hintsRemaining`)
- Stats fin de partie : optimalité %, pire coup (`worstMistakeSnapshot`)

Voir [EVAL.md](EVAL.md).

---

## 14. Graphisme et police

### Thème chrome Sombre / Clair (`BlomixAppearance`)

Orthogonal aux skins de couleurs des blox. Persistance `UserDefaults` (`BlomixAppearanceMode`) ; notification `.blomixAppearanceDidChange`.

| | Sombre *(défaut)* | Clair |
|---|---|---|
| Fond scène | Noir | `#F5EEDF` |
| Textes | Blanc / gris clairs | Gris foncé / moyens |
| Cases vides | `#1F1F1F` approx. | `#EBE3D0` |
| Halos Magix / bombes / disques | Blanc | Noir |
| Ombre chips | Gris clair | Noir |
| Transitions (contour) | Blanc | Gris foncé |
| Game over / pire coup | Voile noir + textes clairs | Voile `#F5EEDF` @ 0,94 + textes foncés |

- Toggle **uniquement sur l’accueil** (icône soleil / lune) ; pas de suivi du mode système iOS
- Splash studio : toujours noir ; thème appliqué après
- Boutons : chips inversés selon le thème (`BlomixSKButtonNode`, `BlomixUIDestinationButtonStyle`)
- Transitions stage / Zen / PvP / tutoriel : fill **orange skin** inchangé ; **contour seul** via `transitionOutlineColor` (pas de halo)

### Police (`BlomixTypography`)

| Nom | PostScript |
|---|---|
| Bitcount *(défaut)* | `BitcountGridSingleInk-Regular` |
| Google Sans | `GoogleSans-Regular` |
| Dyna Puff | `DynaPuff-Regular` |
| Alfa Slab One | `AlfaSlabOne-Regular` |

### Skins couleur

`color_skins.json` — skin Default + Perso (couleurs custom). Indépendant du thème chrome.

### HUD en jeu

- Score animé (rolling counter, milestones 100/1000)
- Best score Game Center
- Compteur LIGNE x/10 (gauche)
- Timer stage ou PvP (droite)
- File P1/P2, icône bombe + compteur
- Bouton hint (?), menu hamburger

### Chips boutons

Tokens `BlomixAppearance` (fill / bordure / titre inversés Sombre ↔ Clair), radius 10 pt (`BlomixSKButtonNode`).

---

## 15. Localisation

| Langue | Dossier |
|---|---|
| Français | `fr.lproj/` |
| Anglais | `en.lproj/` |
| Allemand | `de.lproj/` |
| Espagnol | `es.lproj/` |
| Italien | `it.lproj/` |

| Fichier | Contenu |
|---|---|
| `Localizable.strings` | Clés UI (`BlomixL10n`) |
| `tips_of_day.json` | Conseils du jour |
| `gameover_quotes.json` | Citations fin de partie |
| `InfoPlist.strings` | Chaînes système (`NSGKFriendListUsageDescription`, etc.) |
| `rules.txt` | Anciennes règles statiques (legacy) |
| `credits.txt` | Crédits |

---

## 16. Architecture des fichiers clés

```
Blomix/Blomix/
├── GameScene.swift               # Logique principale, UI SpriteKit, Magix, stages
│   ├── GridLayout                # Constantes grille
│   ├── PriksRules / MagixRules   # Constantes Brix et Magix
│   ├── BlomixSoloSaveManager     # Sauvegarde UserDefaults
│   └── BlomixSkinCatalog         # Skins couleur
├── BlomixMoveAnalyzer.swift      # Évaluation des coups, hints
├── BlomixL10n.swift              # Pont typé localisation
├── BlomixTypography.swift        # Police joueur
├── BlomixAppearance.swift        # Thème chrome Sombre / Clair
├── BlomixPvPNetworking.swift     # GKMatch, RNG, attaques
├── BlomixPvPUI.swift             # Lobby, résultats, adversaires récents
├── BlomixEloManager.swift        # Elo PvP
├── ScoreManager.swift            # Game Center scores
├── GameViewController.swift      # Root VC, overlay tutoriel legacy
├── LeaderboardViewController.swift
├── BlomixProceduralSFX.swift     # Sons procéduraux (Magix, etc.)
├── BlomixMusicPlayer.swift       # Musique par stage
├── color_skins.json
├── en.lproj/ / fr.lproj/ / de.lproj/ / es.lproj/ / it.lproj/
└── Assets.xcassets/WebImages/
```

---

*Document aligné sur le code v5.2 — à maintenir lors des évolutions majeures.*

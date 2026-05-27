# Blomix — Documentation du projet

> **Version de référence** : v1.4  
> **Plateforme** : iOS (UIKit + SpriteKit), Swift  
> **Langues** : Français, Anglais

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Grille](#2-grille)
3. [Blox couleur](#3-blox-couleur)
4. [Placement des blox](#4-placement-des-blox)
5. [Chaînes](#5-chaînes)
6. [Brix](#6-brix)
7. [Bombe](#7-bombe)
8. [Ligne du bas (push)](#8-ligne-du-bas-push)
9. [Game Over](#9-game-over)
10. [Score et multiplicateurs](#10-score-et-multiplicateurs)
11. [Modes de jeu](#11-modes-de-jeu)
12. [Tutoriel interactif](#12-tutoriel-interactif)
13. [Graphisme et police](#13-graphisme-et-police)
14. [Localisation](#14-localisation)
15. [Architecture des fichiers clés](#15-architecture-des-fichiers-clés)

---

## 1. Vue d'ensemble

Blomix est un jeu de puzzle combinatoire. Le joueur place des blox colorés dans une grille 8 × 8 en formant des chaînes de 5 blox ou plus de la même couleur pour les effacer et marquer des points. Des blocs spéciaux (Brix) résistent aux chaînes et demandent plusieurs attaques adjacentes pour disparaître. Une bombe permet de détruire directement une zone 3 × 3. Tous les 10 coups, une nouvelle ligne de blox monte par le bas, rendant la gestion de l'espace de plus en plus critique.

---

## 2. Grille

| Paramètre | Valeur |
|---|---|
| Dimensions | 8 lignes × 8 colonnes |
| Taille d'une case | 40 pts (`GridLayout.cellPoints`) |
| Ligne du haut | `topRowIndex = 0` |
| Ligne du bas | `bottomRowIndex = 7` |

**Système de coordonnées**  
`grid[row][col]` — `row = 0` est le **haut**, `row = 7` est le **bas**.  
En coordonnées locales du nœud SpriteKit :  
- `x = −span/2 + (col + 0.5) × cellPoints`  
- `y = span/2 − (row + 0.5) × cellPoints`

**Types de cellule (`BlockType`)**

| Type | Description |
|---|---|
| `.empty` | Case vide |
| `.color("nom")` | Blox coloré (rouge, bleu, vert, jaune, violet, orange) |
| `.priks(n)` | Brix avec `n` coups restants avant disparition |

---

## 3. Blox couleur

### Palette

6 couleurs normalisées : `red`, `blue`, `green`, `yellow`, `purple`, `orange`.

### Génération aléatoire

Chaque nouveau blox est tiré via `randomNextPlayableBlock()` :
- Probabilité **1/8** → Brix (`.priks(5)`)
- Probabilité **7/8** → couleur aléatoire parmi les 6

### File d'attente

La file contient toujours 3 blox visibles :

| Variable | Rôle |
|---|---|
| `currentBlock` | Blox en cours de placement (grand aperçu) |
| `blockAfterCurrent` | Prochain blox (file) |
| `blockTwoAhead` | Blox suivant (file) |

Après chaque pose, la file avance et un nouveau blox est tiré à la fin.  
En **PvP**, la génération utilise un RNG partagé pour que les deux joueurs reçoivent la même séquence.  
En **mode tutoriel**, la séquence est scriptée (voir §12).

---

## 4. Placement des blox

### Mécanique

1. Le joueur **tape** sur la colonne souhaitée (ou fait glisser son doigt).
2. Le blox est placé dans la **première case vide en partant du haut** de cette colonne (`highestEmptyRow`) — logique d'empilement vers le bas.
3. La colonne sélectionnée est mise en surbrillance ; un **ghost preview** (opacité 55 %) montre la position d'atterrissage après un appui maintenu ≥ 120 ms.

### Cas particuliers

| Situation | Comportement |
|---|---|
| Colonne pleine, d'autres libres | Son d'erreur, pose refusée |
| Toutes les colonnes pleines | Game Over |

### Mode bombe (solo)

En mode bombe, le tap ne cible **pas** une colonne mais **directement une case de la grille**. La bombe se pose à l'endroit exact du tap (pas de gravité). Voir §7.

---

## 5. Chaînes

### Règle

Un groupe de **5 blox ou plus** de la **même couleur** reliés en **8-connexité** (horizontal, vertical, diagonal) est une chaîne gagnante.  
Les Brix ne participent jamais à une chaîne.

### Détection

Algorithme flood-fill (pile) sur la grille : toutes les composantes connexes de même `colorName` sont calculées ; seules celles de taille ≥ 5 sont retenues.

### Séquence après détection

1. Animation de dissolution des blox gagnants
2. `applyPriksAdjacentDecrement` — décrémente les Brix voisins (voir §6)
3. Mise à jour de la grille (cases → `.empty`)
4. Compactage vers le bas (`compactGridTowardTop`)
5. Bonus colonne vide si applicable
6. Nouvelle passe `resolveChains()` (cascade)

### Score des chaînes

| Condition | Points par composante |
|---|---|
| Première vague (`chainSeriesLevel = 0`) | = taille du groupe (ex. 5 → 5 pts) |
| Cascade (`chainSeriesLevel ≥ 1`) | = taille du groupe + 5 pts |

`chainSeriesLevel` s'incrémente de 1 à chaque vague en cascade et revient à 0 quand plus aucune chaîne n'est détectée.

---

## 6. Brix

Les **Brix** (Priks dans le code) sont des blocs résistants affichant un compteur.

| Paramètre | Valeur |
|---|---|
| Compteur initial | `PriksRules.initialHitsRemaining = 5` |
| Probabilité d'apparition | 1/8 (même que `randomNextPlayableBlock`) |

### Décrément

À chaque vague de chaîne, tout Brix **8-adjacent** à au moins une case effacée perd **1 point** (au maximum 1 par vague, quelle que soit la taille de la chaîne).

### Disparition

Quand le compteur atteint **0** :
- La case passe à `.empty`
- **+10 points** par Brix disparu
- Son `priksVanish`

### Interaction avec la bombe

Une bombe détruit instantanément un Brix dans sa zone d'explosion (3 × 3) sans passer par le décrément — la case passe directement à `.empty` sans bonus +10.

---

## 7. Bombe

### Acquisition

| Paramètre | Valeur |
|---|---|
| Stock initial | 1 bombe |
| Gain | +1 bombe tous les 10 vagues de chaîne (`chainClearWaveCount % 10 == 0`) |
| HUD | Barre de 10 segments ; se remplit à chaque vague |

### Utilisation (solo)

1. Taper l'icône bombe → mode bombe actif
2. Taper **directement une case de la grille**
3. L'image de la bombe apparaît sur la case avec un **tremblement marqué (0,3 s)**
4. Explosion 3 × 3 centrée sur la case choisie
5. +10 points, compactage, `resolveChains()`

### Utilisation (PvP / fallback)

La bombe suit la trajectoire d'un blox normal dans la colonne choisie et explose sur la **première case occupée** rencontrée en remontant depuis le bas (ou en haut si colonne vide).

### Zone d'explosion

Carré 3 × 3 centré sur la case d'impact : jusqu'à 9 cases vidées (`.empty`), qu'elles contiennent des blox couleur ou des Brix.

---

## 8. Ligne du bas (push)

Toutes les **10 poses sans chaîne**, une nouvelle ligne de blox monte depuis le bas de la grille.

### Compteur

`moveCount` s'incrémente de 1 uniquement après une pose dont le `resolveChains()` se conclut **sans** chaîne. La progression est visible dans la barre "Next line" (10 segments).

### Contenu

8 blox générés indépendamment comme `randomNextPlayableBlock()` (donc probabilité 1/8 de Brix par case en solo/PvP). **En mode tutoriel**, les Brix sont remplacés par des blox couleur aléatoires afin de réserver la découverte des Brix à la file principale.

### Conséquence grille pleine

Si au moins une colonne est déjà pleine au moment de la poussée → **Game Over**.

### Preview

La ligne suivante est prévisualisée en bas de la grille avant d'être injectée.

---

## 9. Game Over

Déclenché quand :
- La colonne cible d'un blox est pleine **et** toutes les autres le sont aussi
- Une ligne du bas tente de s'injecter alors qu'une colonne est déjà pleine

L'écran Game Over affiche le **score final** (partie + bonus), une citation aléatoire (`gameover_quotes.json`) et des boutons "Rejouer" et "Classement".

---

## 10. Score et multiplicateurs

### Pendant la partie

| Action | Points |
|---|---|
| Chaîne (1ère vague) | = taille du groupe |
| Chaîne (cascade) | = taille + 5 |
| Brix disparu (via chaîne) | +10 par Brix |
| Bombe utilisée | +10 |
| Colonne entièrement vidée | +10 par colonne |

### Bonus de fin de partie (solo uniquement)

Calculé à partir de `bonusTotalBlocks` (total des blocs non vides posés + injectés) et `bonusTotalPriks` (sous-ensemble Brix) :

```
theoretical = bonusTotalBlocks ÷ 8  (division entière)
bonusPoints = max(0, (bonusTotalPriks − theoretical) × 10)
```

Ce bonus récompense les parties où les Brix représentent une proportion plus élevée que prévu.

### Affichage

`displayedScore` monte avec une animation vers `score` ; l'amplitude du pulse du label est proportionnelle au `chainSeriesLevel`.

---

## 11. Modes de jeu

### Solo

Partie infinie, sauvegarde automatique.

**Sauvegarde** (`BlomixSoloGameSave`, clé UserDefaults `blomix_solo_save_v1`) :
- Grille complète, file des 3 blox, `moveCount`, ligne suivante, bombes, score, compteurs de chaîne et de bonus
- Déclenchée automatiquement à la mise en arrière-plan ou à la perte de focus (tutoriel, PvP, appel entrant, etc.)
- Restaurée au lancement suivant via `presentStartScreenOrRestoreSoloSave()`

**Restauration automatique** :
- Après la fin du tutoriel
- Après la fin d'un match PvP (victoire, défaite, déconnexion, erreur réseau)

### PvP (Player vs Player)

Via **Game Center** (`GKMatch`).

| Aspect | Détail |
|---|---|
| Accès | Bouton PvP → recherche automatique ou lobby |
| RNG synchronisé | Graine partagée → mêmes blox pour les deux joueurs |
| Attaque | Chaque palier `score / 50` franchi → envoi d'une ligne chez l'adversaire |
| Elo | Rating par défaut 800, K = 32, formule Elo classique (leaderboard `"elotype"`) |
| Fin | Victoire / défaite / déconnexion → retour à la partie solo sauvegardée |

### Tutoriel interactif

Voir §12.

---

## 12. Tutoriel interactif

### Déclenchement

- **Automatique** au premier lancement d'une partie (si `hasSeenInteractiveTutorial` est `false`)
- **Manuel** via le bouton "Tutoriel" (accueil ou menu en jeu)

### Séquence de blox prédéfinie

`jaune → rouge → 16× bleu → jaune, bleu, vert, rouge, bleu, bleu → Brix(5) → 16× jaune → rouge, vert, bleu, jaune → …`

La file continue en aléatoire après épuisement de la séquence.

### Étapes et overlays

| Étape | Déclencheur | Texte (FR) |
|---|---|---|
| Intro | Démarrage | "Tape sur une colonne pour placer un blox" |
| Chaîne | Après 2 poses | "Fais une chaîne de 5 blox de même couleur" |
| Célébration chaîne | Chaîne réalisée | "Super ! 5 blox = effacés !" (auto-dismiss 2,8 s) |
| Ligne | 1ère injection du bas | "Tous les 10 blox, une ligne vient perturber le jeu !" |
| Brix | 1er Brix en currentBlock | "Les Brix sont plus résistants…" |
| Célébration Brix | Brix décrémenté | "Super ! Le Brix se rapproche de la disparition !" (auto-dismiss 2,8 s) |
| Bombe | Après 2 poses libres | "Tape sur une case pour poser la bombe !" |
| Célébration bombe | Bombe posée | "Super ! Tu sais tout — bonne partie !" (auto-dismiss 3 s → retour accueil) |

### Contraintes tutoriel

- **Bombe verrouillée** jusqu'à l'étape Bombe (`tutorialBombUnlocked`)
- **Brix absents des lignes injectées** (remplacés par des blox couleur)
- Bouton **"Passer"** toujours visible (haut droite) → retour accueil immédiat, tutoriel marqué comme vu
- La partie solo en cours est **sauvegardée** avant le lancement du tutoriel et **restaurée** à la fin

---

## 13. Graphisme et police

### Police

Sélectionnable par le joueur dans les réglages (`BlomixTypography`) :

| Nom affichage | PostScript name |
|---|---|
| Bitcount *(défaut)* | `BitcountGridSingleInk-Regular` |
| Google Sans | `GoogleSans-Regular` |
| Dyna Puff | `DynaPuff-Regular` |
| Alfa Slab One | `AlfaSlabOne-Regular` |

### Palette de couleurs (skin "Default")

Définie dans `color_skins.json`. Les Brix ont une couleur et une couleur de texte dédiées (`priks`, `prikstext`). Skin **Perso** : couleurs entièrement personnalisables par le joueur.

### Style des boutons (chips)

| Propriété | Valeur |
|---|---|
| Fond | `#232323` |
| Bord | `#444444`, 1 px hairline |
| Texte | Blanc |
| Corner radius | 10 pts |

Identique en UIKit (vues UIKit) et en SpriteKit (chips d'accueil via `SKShapeNode`).

### HUD en jeu

- **Score** : label animé (pulse proportionnel au `chainSeriesLevel`)
- **Best score** : via Game Center
- **Bonus** : flottants "+N pts" animés sur la grille
- **Next blox** : file des 3 prochains blox
- **Next line** : barre de progression 10 segments
- **Next bomb** : barre de progression 10 segments + icône bombe + compteur
- **Menu** : icône hamburger → Nouvelle partie, Scores, Tutoriel, Réglages, PvP

### Écran d'accueil

Logo studio, titre Blomix, 5 boutons chips (Jouer, PvP, Scores, Tutoriel, Réglages, Crédits), tip du jour rotatif (toutes les 5 s), bannière de mise à jour App Store si nouvelle version disponible.

### Game Over

Fond noir semi-transparent (72 %), score final, bonus, citation `gameover_quotes.json`, boutons Rejouer / Classement, animation de blocs ambiants.

---

## 14. Localisation

| Langue | Dossier |
|---|---|
| Français | `fr.lproj/` |
| Anglais | `en.lproj/` |

**Fichiers par dossier :**

| Fichier | Contenu |
|---|---|
| `Localizable.strings` | Toutes les clés UI (`BlomixL10n`) |
| `tips_of_day.json` | Conseils du jour (tableau `{ "text": "…" }`) |
| `gameover_quotes.json` | Citations fin de partie (`{ "text", "author" }`) |
| `rules.txt` | Texte des anciennes règles statiques (conservé) |
| `credits.txt` | Texte des crédits |

`color_skins.json` n'est pas localisé (racine du bundle).

---

## 15. Architecture des fichiers clés

```
Blomix/
├── GameScene.swift               # Scène principale : toute la logique de jeu, UI SpriteKit
│   ├── GridLayout                # Constantes grille (rowCount, columnCount, cellPoints…)
│   ├── PriksRules                # Constantes Brix (initialHitsRemaining, spawnProbability)
│   ├── BlomixSoloSaveManager     # Sauvegarde/restauration partie solo (UserDefaults)
│   ├── BlomixSkinCatalog         # Gestion des skins couleur
│   └── (modes tutorial, PvP, bomb, score…)
├── BlomixL10n.swift              # Pont typé vers Localizable.strings
├── BlomixTypography.swift        # Gestion de la police choisie par le joueur
├── BlomixUIButtonStyle.swift     # Constantes visuelles des boutons
├── BlomixPvPNetworking.swift     # Protocole réseau PvP (GKMatch, attaques, handshake)
├── BlomixPvPUI.swift             # UI PvP (lobby, adversaire récent, invitation)
├── BlomixEloManager.swift        # Calcul et persistance Elo
├── ScoreManager.swift            # Soumission scores Game Center
├── GameViewController.swift      # Root view controller, lancement scène, tutorial overlay legacy
├── LeaderboardViewController.swift # Leaderboard Elo, défis
├── BlomixAmbientBlocksView.swift  # Animation blocs de fond
├── UserDefaults+BlomixGameTutorial.swift # Clés UserDefaults tutoriel
├── color_skins.json              # Définition des skins couleur
├── en.lproj/
│   ├── Localizable.strings
│   ├── tips_of_day.json
│   ├── gameover_quotes.json
│   ├── rules.txt
│   └── credits.txt
├── fr.lproj/
│   └── (mêmes fichiers)
└── Assets.xcassets/
    └── WebImages/                # Textures du jeu (bomb, blox, écrans…)
```

---

*Document généré automatiquement — à maintenir à jour lors des évolutions majeures du jeu.*

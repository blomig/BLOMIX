# Blomix — Documentation du projet

> **Version de référence** : 6.4  
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
| `.magix(MagixKind)` | Bloc Magix (8 variantes, dont BOMBX) |

---

## 3. Génération aléatoire

Fonction centrale : `randomNextPlayableBlock()` dans `GameScene.swift`.

Ordre de tirage (`randomNextPlayableBlock`) :
1. **Magix** si `r < MagixRules.spawnProbability` (~**2,9 %** cumulé) — tirage pondéré par variante, voir `MagixRules.spawnProbabilityByKind`
2. **Brix** si `r < spawnMagix + 1/8` — donc **exactement 12,5 %** du tirage total
3. **Couleur** — le reste (~84,6 %), uniforme parmi les 6

Ce n’est **pas** « 7/8 couleur + 1/8 Brix, plus 3 % Magix par-dessus ».

**File d'attente** (3 blocs visibles) :

| Variable | Rôle |
|---|---|
| `currentBlock` | P0 — bloc en cours |
| `blockAfterCurrent` | P1 |
| `blockTwoAhead` | P2 |

En PvP : RNG partagé via `BlomixPvPMatchCoordinator`.  
En tutoriel : séquence scriptée (`tutorialBlockQueue`).

**Restrictions lignes entrantes** (`nextBottomLineRowForSession`) : tirage identique à la file, **puis** tout `.magix` est remplacé par une couleur ; en tutoriel, les `.priks` aussi. En Duel, le RNG partagé **ne tire jamais** de Magix (`BlomixPvPSeededBlockRNG` : 1/8 Brix sinon couleur).

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

BRIXED (Magix) : crée un Brix(9), **détruit** tous les autres Brix (+20 chacun).  
SAINTX : laisse un Brix valant le nombre de cases effacées.

---

## 7. Blocs Magix

Définis dans `MagixKind` et `MagixRules` (`GameScene.swift`).

| Kind | Label popup | Effet principal |
|---|---|---|
| `.chromax` | CHROMAX | Chemin ≤ 15 cases → couleur unique → `resolveChains()` |
| `.brixed` | BRIXED | Devient Priks(9) ; **détruit tous les autres Brix** (+20 chacun). `brixedGlobalDecrement` (ancienne règle −2) n’est plus appliqué |
| `.crosx` | CROSSX | Ligne + colonne → couleur aléatoire → chaînes |
| `.scrumblx` | SCRUMBLX | Décalage horizontal par ligne ; −1 Brix global |
| `.colorx` | COLORX | Roulette → efface une couleur (score chaîne) |
| `.cleanx` | SAINTX | Vide la grille → Brix(N) ; +200 pts **via `addScore`** (donc × stage en Arcade) |
| `.twistx` | TWISTX | Échange **automatique** (pas de tap joueur) : une couleur présente ↔ tous les Brix (valeur = min Brix, défaut 3) |
| `.bombx` | BOMBX | Tâche 3 rangs sur cases occupées → chaînes → **+1 bombe** au stock (`grantBombxStockBonus`). Arcade / Zen uniquement |

Fractions de spawn (`MagixRules.spawnProbabilityByKind`) :

| Kind | p |
|---|---|
| `.twistx` / `.chromax` / `.brixed` | 1/324 chacun |
| `.colorx` / `.scrumblx` | 1/180 chacun |
| `.crosx` | 1/216 |
| `.cleanx` / `.bombx` | 1/500 chacun |

Cumul ≈ **2,9 %**. (Le commentaire code « ≈ 1/30 » est un vestige à 4 variantes.)

Rendu : shader dégradé animé + halo + particules orbitales (`applyMagixShader`).

Le lookahead (`BlomixMoveAnalyzer`) **ignore** les Magix **et les bombes** (effets non simulables).

---

## 8. Bombe

| Paramètre | Arcade / Zen | Duel |
|---|---|---|
| Stock initial | 5 | 3 |
| Gain en partie | **BOMBX** : +1 (garanti) | Pas de Magix |
| Zone | Arcade : 3×3 + croix selon stage ; Zen : 3×3 | Toujours 3×3 |

`bombCrossArmLength` = `currentStageIndex` en solo stagé (0 au L1 … 5 à l’Ultime) ; 0 hors Arcade. Texture HUD `nuke` dès que `arm > 0`.

**Une bombe n’est pas un coup** : `shouldRunPostPlacementHooks` n’est posé que par `dropBlock`. `moveCount` / ligne des 10 n’avancent pas.

**Timer :** `stageTimerTick` et `blomixPvP_shouldRunTurnTimer` **sautent** tant que `isBombMode` (le chrono Duel est gelé pendant la visée).

**Flux :**
1. Tap icône → `isBombMode = true`, `bombCount -= 1`
2. Tap case → tremblement 0,3 s → explosion (`bombAffectedCells`)
3. +10 pts, Brix détruits +20 pts chacun
4. `chainSeriesLevel = 1` → cascades
5. Annulation possible (restitue la bombe)

---

## 9. Ligne entrante

- `moveCount` s'incrémente **une fois**, dans la branche idle de `resolveChains`, si `shouldRunPostPlacementHooks` (après **toutes** les cascades d’une pose). Une bombe ne pose pas ce flag.
- Injection quand `moveCount % 10 == 0` via `addRandomLinePushingGridUp()`.
- Preview visible quand `moveCount % 10 == 9`.
- 8 tirages indépendants via `randomNextPlayableBlock()`, **puis** strip Magix (et Brix en tuto).
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
| SAINTX | 200 (via `addScore` → × stage en Arcade) |
| Grille 100 % vide (Arcade / Zen) | **500** plats (`fullyClearedBoardBonusPoints`, `applyStageMultiplier: false`) — en plus des +10 / colonne |

**Multiplicateur stage** : appliqué dans `addScore()` si `isInStagedSoloMode`, sauf le bonus grille vide.

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
Timer relancé **à fond** après chaque coup stable et après overlay de stage. Timeout → `autoDropPreferredColumn()` : hasard parmi les colonnes dont `grid[0][col] == .empty`, sinon toute colonne jouable.

**Reprise de save :** `resumeStageTimerKeepingRemaining()` avec les secondes persistées, clamp `[1 … durée du stage]`. Un flush mid-anim relance aussi sur le reste.

### Mode Zen

`isZenMode = true` : pas de timer, pas de stages, leaderboard Zen séparé.

### Sauvegarde solo

`BlomixSoloGameSave` (version **7**, clé `blomix_solo_save_v2`) :
- Grille, file P0/P1/P2, `moveCount`, `nextBottomLine`
- Bombes, score, `chainSeriesLevel`, `chainClearWaveCount`
- Stage, timer, `moveRecords`, `hintsRemaining`, `isZenMode`
- Auto-save en arrière-plan ; au lancement, **toujours l’accueil** (6.4) : hero Continuer + mode si save, sinon Découvrir / Arcade
- Avant persistance : flush des états transitoires (`pendingGridWrite`, `pendingScoredChainClearCells`) **puis toujours** `compactGridTowardTop` + resolve synchrone (évite de sauver des trous mid-vague)
- À la reprise : même légalisation gravité / chaînes **avant** `drawGrid()` (répare les anciennes saves illégales)

### PvP

`BlomixPvPNetworking.swift` + `BlomixPvPUI.swift` + `BlomixPvPLocalSession.swift` :
- Canaux : **online** (`GKMatch`) ou **local** Multipeer (`serviceType` `blomix-pvp`) via le même coordinateur
- Handshake RNG partagé (`helloSeed` + `protocolVersion`) ; file d’envoi + ack pour messages critiques
- Heartbeat / grace déco mid-game (online ~4 s ; local ~45 s + rebuild session / re-invite)
- Local : découverte maintenue mid-match, `onTransportRestored`, silence → `forceTransportReset` (voir `PVP_MATCHING.md`)
- **Série de revanches** : compteur session local ; HUD après 1ʳᵉ revanche ; overlay fin si ≥ 1 partie (voir `PVP_MATCHING.md`)
- **H2H** : 0 CloudKit en match / récap ; affichage = historique + Δ ; juge accueil ne descend pas sous le plancher (sauf ±1)
- Attaque : `score / 50` → **une** ligne chez l’adverse par `addScore` (reste `score % 50` ; HUD et pile montrent ce reste)
- Timer tour : 10 s ; **gelé** tant que `isBombMode` (`blomixPvP_shouldRunTurnTimer`)
- Elo : `BlomixEloManager` (défaut 800 local, K adaptatif) — **pas** d’écriture GC 800/0 à l’init ; 1 update **par partie**
- Lobby : Partie rapide (**Local** / **En ligne**), défis CloudKit / récents / classement
- Overlay attente match sur **grille vide** (pas sur l’accueil)
- Dialogs d’erreur / timeout : style in-app BLOMIX (`BlomixInAppDialogView`)
- Fin : victoire/défaite/déconnexion → retour solo sauvegardé

### Classement Elo (UI)

`LeaderboardViewController` — onglet Elo :
- Chargement **multipage** des entrées Game Center (fenêtre top 100 souvent remplie de 800/0)
- Filtre applicatif : conserve les joueurs ayant joué (`context > 0` ou score ≠ 800)
- Snapshots Sendable dans les callbacks GK (pas de `GKLeaderboard.Entry` hors callback)

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
| Bombe | Après 2 poses libres (`tutorialBombUnlocked`) |
| Magix | Après bombe posée — overlay tous les Magix ; tap **ou** 3 s → célébration |
| Célébration finale | « Tu sais tout » auto 3 s → `exitTutorial` (reprise save solo si présente) |

Contraintes : bombe verrouillée jusqu'à l'étape ; Brix/Magix absents des lignes ; bouton Passer.  
L’overlay UIKit paginé (`GameTutorialOverlayView` / `hasSeenGameTutorial`) n’est plus sur le chemin joueur.

---

## 13. Analyse des coups

`BlomixMoveAnalyzer.swift` — moteur pure Swift, sans SpriteKit.

- Lookahead 3 niveaux (P0, P1, P2) : 512 simulations max
- `evalEnabled = true`, `realtimeFeedbackEnabled = false`
- Stats fin de partie : **justesse** % , pire coup (`worstMistakeSnapshot`) — plus de hint en cours de partie (v6.1). Magix / bombes non simulés → le % ne les compte pas.

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

### Accueil — liens utilitaires & crédits

Rangée d’**icônes** sous les disques de rang (`makeStartScreenChromeIcon`) — `makeStartScreenUtilityLinks` (libellés texte) n’est plus branché :

| Icône | Action |
|---|---|
| **Réglages** | `gearshape.fill` → `SettingsViewController` |
| **Tutoriel** | `book.fill` → partie guidée (tuto interactif grille, pas l’overlay paginé UIKit) |
| **Thème** | soleil / lune |
| **Partager** | `paperplane.fill` |
| **Crédits** | `info.circle.fill` → `BlomixCreditsViewController` |

- Rangée d’icônes SF Symbols (`.fill`, teinte `primaryText`), sans libellé sous l’icône
- Arcade **pleine largeur** (hero skin) ; Duel + Zen en paire
- 4 disques de rang : Arc. / Moy. / Zen / Duel
- Modal crédits : fond scène + blox ambiants + **Fermer** ; header BLOMIX + tagline + version marketing/build
- Cartes `panelFill` / bordure chrome ; titres de section en **accent skin** (orange blox)
- Contenu structuré via `BlomixL10n.creditsSections` (FR/EN/DE/ES/IT) ; `credits.txt` legacy non branché UI
- Crédits : bouton chrome **Laisser un avis** → `?action=write-review` (pas de pop-up custom, guideline 5.6.1)
- GO Arcade/Zen : après ≥ 3 parties terminées, 1× par `MARKETING_VERSION`, `AppStore.requestReview` (pause 2,5 s, pas pendant overlay record) ; hors tuto / Duel
- **Conseil du jour** : ancré à 10 % de la hauteur. Si l’iTunes Lookup signale une MAJ, une bannière (lien App Store) **prend ce slot et masque les conseils** ; ✕ rétablit les conseils pour la session.

### Partage (accueil + game over)

`BlomixShareComposer` + share sheet système (`UIActivityViewController` via `GameViewController`).

| Entrée | Contenu |
|---|---|
| Accueil | Icône avion en papier (`paperplane.fill`) → texte challenge + URL App Store `id6762053543` |
| Game over Solo/Zen | 3ᵉ bouton sous Classement → **carte 1:1** (grille finale, skin + thème chrome, score, bandeau record si PB) + texte + URL |
| PvP | Hors scope v1 |

- Score accueil : best Solo, sinon Zen, sinon message sans score ; mention « Zen » seulement si Zen
- Messages localisés FR/EN/DE/ES/IT (`share.*`)
- Icône : dessin vectoriel custom (`BlomixAppearance.shareButtonTexture`), pas le glyphe système `square.and.arrow.up`

### Police (`BlomixTypography`)

Deux visages figés (plus de picker joueur) :

| Rôle | Police | Usage |
|---|---|---|
| Display / grille | Changa One | Titres, gros score, overlays, record, Brix, Magix, COMBO, `+N` |
| Chrome | Nunito Regular / Medium / SemiBold | Micro-captions / corps / chips |

### Skins couleur

`color_skins.json` — skin Default + Perso (couleurs custom). Indépendant du thème chrome.

### HUD en jeu

- Score animé (rolling counter, milestones 100/1000) ; **Duel** : affichage `score % 50` (total inchangé)
- Best score Game Center
- Compteur LIGNE x/10 (gauche)
- Duel : barre continue 0…50 à **droite** du gros score (clipée, même horloge / couleur que le chiffre) ; le chiffre HUD est `score % 50`
- Timer stage ou PvP (droite)
- Arcade : badge LX (bas gauche) visible pendant l’overlay ; grow ×2 / swap / settle calés sur la transition
- File P1/P2, icône bombe + compteur
- Menu hamburger (Accueil / Scores / Réglages) — pause le timer Solo tant qu’il est ouvert

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
| `rules.txt` | Anciennes règles statiques (legacy ; non exposé par l’UI) |
| `credits.txt` | Legacy ; l’UI crédits utilise `BlomixL10n.creditsSections` |

---

## 16. Architecture des fichiers clés

```
Blomix/Blomix/
├── GameScene.swift               # Logique principale, UI SpriteKit, Magix, stages
│   ├── GridLayout                # Constantes grille
│   ├── PriksRules / MagixRules   # Constantes Brix et Magix
│   ├── BlomixSoloSaveManager     # Sauvegarde UserDefaults
│   └── BlomixSkinCatalog         # Skins couleur
├── BlomixMoveAnalyzer.swift      # Évaluation des coups (récap / pire coup)
├── BlomixL10n.swift              # Pont typé localisation
├── BlomixTypography.swift        # Police joueur
├── BlomixAppearance.swift        # Thème chrome Sombre / Clair (+ icône partage custom)
├── BlomixShareComposer.swift     # Messages + carte 1:1 + items share sheet (accueil: texte+URL ; GO: +image)
├── BlomixPvPNetworking.swift     # GKMatch / Multipeer, RNG, attaques
├── BlomixPvPLocalSession.swift   # PvP Local (MultipeerConnectivity)
├── BlomixPvPUI.swift             # Lobby, résultats, dialogues in-app, adversaires récents
├── BlomixEloManager.swift        # Elo PvP + cache identité GC + pending offline
├── ScoreManager.swift            # GC Solo/Zen/moyenne ; sync max(local,pending) + reconcile local>GC
├── BlomixCreditsViewController.swift  # Crédits en cartes (tagline, version, sections)
├── BlomixRulesGuideViewController.swift  # Guide règles + Magix (6.4)
├── BlomixPvPH2HManager.swift     # H2H PvP CloudKit (multi-ID game/team + alias, isolé)
├── BlomixPublicCloudGate.swift   # Robinet Public DB (503 / Retry-After) H2H + lobby
├── BlomixAvailablePlayersManager.swift  # Joueurs dispo + défis `chfrom_*`
├── GameViewController.swift      # Root VC, tutoriel, share sheet UIKit
├── LeaderboardViewController.swift  # Classements Elo H2H + défis ; crédits plain-text legacy
├── BlomixProceduralSFX.swift     # Sons procéduraux (Magix, etc.)
├── BlomixMusicPlayer.swift       # Musique par stage
├── color_skins.json
├── en.lproj/ / fr.lproj/ / de.lproj/ / es.lproj/ / it.lproj/
└── Assets.xcassets/WebImages/
```

---

*Document aligné sur le code v6.4 (build 118) — à maintenir lors des évolutions majeures.*

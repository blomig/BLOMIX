# PLAN 9.0 — Nouveau look « New » (prototype à bascule Old / New)

> À lire en premier par tout agent (Grok Build) qui travaille sur la branche `9.0`.
> Worktree : `~/Developer/BLOMIX-9.0`. Ne jamais toucher `~/Documents/GIT/BLOMIX` (iCloud).
> Le 15/11/2026, la piste Encre **remplace** la gelée comme mode New ([DA_ENCRE_WASHI.md](DA_ENCRE_WASHI.md), `docs/design/9.0/encre-washi-rendu1.png`). E1–E5 : papier washi, taches, pièces fusionnées, pose et chaîne. Les Brix Encre prennent les deux couleurs du skin (fond et chiffre, même mélange qu’en Classique). La feuille de grille Clair est `#F0E6D2` (cases vides Classique), avec un grain très fin. Chelsea Market remplace Changa One en Encre seulement. Pangolin remplace Nunito en Encre seulement. Magix et bombe en Encre : même disque et mêmes effets, matière aquarelle (grain + couronne irrégulière). Classique ne bouge pas, sauf le léger abaissement de la grille (tous modes) qui égalise l’air sous le score et l’air au-dessus du bloc à lancer.

## 1. Objectif

La 9.0 introduit un nouveau rendu visuel, **New**. Depuis le 15/11/2026 la cible est la piste Encre
(`docs/design/9.0/encre-washi-rendu1.png`, [DA_ENCRE_WASHI.md](DA_ENCRE_WASHI.md)).
La géométrie des pièces vient de la gelée (`docs/design/9.0/maquette-new-cible.jpg`).
Le rendu affiché par `.new` est l'Encre. `maquette-1-exploration.jpg` n'est qu'une exploration.

Le rendu actuel s'appelle **Old**. Un réglage dans l'onglet **Réglages** permet de basculer Old ↔ New
pour prototyper et tester sans rien casser.

## 2. Règle d'or (non négociable)

1. **Old reste identique au pixel près.** Aucune modification de comportement, de couleur, de taille,
   d'animation ou de son en mode Old. Si un changement touche du code partagé, il doit être neutre en Old.
2. **Old par défaut.** Un joueur qui ne touche à rien ne voit aucune différence.
3. **Le gameplay ne change pas** : règles, scores, RNG, défi du jour, PvP, sauvegardes, télémétrie,
   trophées. New est une couche de rendu, jamais une couche de logique.
4. **Tout le code New vit dans ses propres fichiers** (préfixe `BlomixNew…`), branché par des points
   d'entrée minimes et clairement commentés (`// 9.0 New:`) dans le code existant.
5. Pas de nouvelle dépendance externe. On reste en **UIKit + SpriteKit** (pas de SceneKit / RealityKit).

## 3. Le réglage Old / New

- `enum BlomixVisualStyle: String { case old, new }` dans `BlomixVisualStyle.swift`,
  sur le modèle de `BlomixAppearance` (UserDefaults, clé `BlomixVisualStyle`, défaut `.old`).
  Depuis E0 (15/11/2026), `.new` est la piste Encre. Pas de troisième cas.
- Notification `blomixVisualStyleDidChange` postée au changement.
- Réglages : une ligne « Apparence », trois boutons Sombre / Clair / Encre. Sombre = Classique sombre,
  Clair = Classique clair, Encre = style `.new` et clair. Pas d’Encre sombre. Le soleil / lune de l’accueil est retiré.
  Chaînes déjà présentes dans les 6 langues (`settings.appearance.dark`, `.light`, `settings.visual_style.new`).
- **Décision V3** : le bouton écrit tout de suite UserDefaults. Il ne reconstruit pas la grille de la partie en cours.
  Le style est lu à la **prochaine partie**. Une partie Encre déjà lancée reste en clair jusqu’au retour accueil,
  même si le joueur choisit Sombre entre-temps.

## 4. Point de branchement du rendu

- Les blocs de grille passent par `GameScene.makeSolidGameplayBlockSprite(block:pixelSize:priksDigitFontSize:)`.
  En New, `.color` et `.priks` délèguent à `BlomixNewBlockRenderer` (sprite de grille `cell − 1`).
  La file et le gros aperçu (couleur / Brix) passent par `applyJelly`, à leur taille d’origine.
  En Old, le carré uni est inchangé. En Encre, Magix et bombe gardent leur shader de palette ; la texture du disque est un masque aquarelle (`BlomixNewInkRenderer.discTexture`).
- Autres fabriques à inventorier avant d'y toucher : `makeBlockCell`, `makeFallingBlockNode`,
  `makeBottomLinePreviewCellNode`, aperçu « prochains blox », Magix (`makeMagixShaderSprite`).
- Grille vide (cellules), cadre de grille, HUD : étapes ultérieures.
- Inventaire complet : §4.1 (relevé du 14/11/2026, `GameScene` non modifié à l’étape 0).

### 4.1 Inventaire des fabriques de nœuds de blocs (14/11/2026)

`makeSolidGameplayBlockSprite` a **11** sites d’appel, pas ~12. Le Magix en chute et les
minis « prochains blox » ne passent pas par elle. Lignes de `Blomix/Blomix/GameScene.swift`
sauf mention contraire. Ne pas brancher New sur un seul de ces points.

**Fabrique principale** — `makeSolidGameplayBlockSprite(block:pixelSize:priksDigitFontSize:)` (l. 15550).
Blox et Brix : `SKSpriteNode` couleur unie. Magix : délègue à `makeMagixShaderSprite` (l. 15577).
`.empty` : sprite transparent (pas une case de grille).

| Lignes | Appelant | Rôle |
|---|---|---|
| 10959, 10962 | `makeBottomLinePreviewCellNode` | Bande sous la grille : couleur, puis Brix et Magix |
| 12550 | effet TWISTX | Remplace la case après le flip |
| 14497, 14500 | `makeFallingBlockNode` | Pièce qui monte : couleur, puis Brix (chiffre 20 pt) |
| 15345 | `presentPaintedBlock` | Peinture Magix, cases qui ne muent pas le sprite d’origine |
| 15985, 15992, 15999 | `drawGrid` | Case de grille : couleur, Brix, Magix |
| 17078 | `showHintGhost` | Fantôme d’indice, alpha 0,60 |
| 17147 | `showGhostPreview` | Fantôme d’appui long, alpha 0,55 |

**Autres fabriques nommées**

| Fonction | Ligne | Produit | Qui l’appelle |
|---|---|---|---|
| `makeFallingBlockNode(for:)` | 14494 | Pièce qui monte. Couleur et Brix → fabrique principale. Magix → `makeMagixShaderSprite` direct (l. 14503). Vide → sprite clair 1×1 | Chute du coup (l. 11382). Montée de la ligne entrante (l. 11170) |
| `makeBottomLinePreviewCellNode(block:)` | 10955 | Bande « demi-case ». Couleur / Brix / Magix → fabrique principale. Vide → `SKSpriteNode` `emptyCell` (l. 10964) | `refreshPendingBottomLinePreview` (l. 11044). Trou SCRUMBLX via `makeScrumblxHolePlaceholderSprite` |
| `makeScrumblxHolePlaceholderSprite()` | 13101 | Trou visuel = case vide de la bande | Décalage SCRUMBLX (l. 13229, 13277) |
| `makeBlockCell(_:size:)` | 7152 | Fonction **locale** de l’overlay pire coup. `SKShapeNode` arrondi, chiffre Brix ou lettre Magix. Ne passe pas par la fabrique principale | Un appel (l. 7188) : les 3 blocs joué / suivant / d’après |
| `makeMagixShaderSprite(size:kind:)` | 11843 | Disque shader + halo + symbole | Fabrique principale (cas Magix), chute Magix, `buildMagixIntroOverlay` (l. 18308) |
| `makeGuideMagixPreviewSprite(size:kind:)` | 11947 | Même shader, symbole `guideMagixSymbol` | `BlomixGuideIllustrationView` (`GuideSpritePreviewScene`) et `BlomixWhatsNew` (`MagixWhatsNewPreviewScene`) |
| `makeBombShaderSprite(size:)` | 11955 | Disque bombe (shader + halo + particules) | Icône HUD (l. 13550), pose (l. 14273), chute (l. 14405), overlay tuto (l. 18211) |
| `makeGuideBombPreviewSprite(size:)` | 11942 | Alias public du sprite bombe | Guide, `GuideSpritePreviewScene` |

**Mutateurs — sprite déjà là, pas une fabrique.** À traiter avec le type, sinon un slot New resterait Old.

| Fonction | Ligne | Rôle |
|---|---|---|
| `applyBlockTypeToQueueSprite(sprite:block:slotCellPoints:)` | 13621 | Les deux minis « prochains blox ». Les slots naissent vides dans `setupBombHUD` (l. 13569 et 13577). Couleur et Brix en aplat. Magix via `applyMagixShader` |
| `updatePreviewSprite()` | 14614 | Gros bloc courant sous la file. Le nœud `previewNodeName` est créé une fois, puis repeint. Bombe : `applyBombShader`. Magix : `applyMagixShader` |
| `applyMagixShader(to:size:kind:symbolLabelName:)` | 11797 | Corps commun Magix (shader, halo, symbole) |
| `applyBombShader(to:size:)` | 11910 | Corps commun bombe |
| `morphMagixSprite(_:into:)` | 15295 | Mue le sprite Magix en Blox ou Brix (SAINTX et cie). Ne respawn pas |
| `drawGrid` cas `.empty` | 15974 | Case vide, inline. Inset Clair : `attachLightEmptyCellInset` (l. 16730) |
| Overlay pire coup, grille miniature | 7021 | `SKShapeNode` inline, même écran que `makeBlockCell` |
| Overlay pire coup, ligne entrante | 7090 | `SKShapeNode` aplati, inline |
| `showGhostPreview`, surbrillance de colonne | 17136 | Cases vides en `ghostColumnHighlight`, pas un bloc |
| COLORX / SAINTX | 12054, 12156, 12372, 12381 | Repeint le sprite existant ou pose un voile blanc. Pas une fabrique de bloc |

**Décor — pas une case de jeu.** Laisser en Old tant que l’habillage n’est pas décidé.

| Fonction | Ligne | Rôle |
|---|---|---|
| `spawnAmbientBlock` | 3379 | Carrés qui montent, accueil et game over |
| `BlomixAmbientBlocksView.spawnBlock` | `BlomixAmbientBlocksView.swift` | Même idée, fond UIKit des modaux |
| `triggerPvPAttackSentVisuals` | 19704 | Mini-blocs qui s’envolent quand une attaque part |
| `buildChainImageNode` | 18334 | Cinq carrés bleus du tutoriel (`SKShapeNode`) |
| `settleBlock` / `rebuildBloxJunctionShapes` | 15637 / 15755 | Barres entre Blox de même couleur. En New, `rebuildBloxJunctionShapes` s’arrête avant et pose une pièce `blomixNewFusion` par groupe. Classique : barres inchangées |
| Grains d’air | ~16719 | Pas des blocs |
| Cadre `gridFrameOutlineName` | 16023, dans `drawGrid` | Étape 3 |

**Hors partie SpriteKit**

| Lieu | Rôle |
|---|---|
| `BlomixShareComposer` (~l. 184) | Carte de partage, Core Graphics, une boucle sur la grille |
| `BlomixGuideIllustrationView.drawRoundedBlock` / `drawBlox` / `drawBrix` / `drawLine` | Pictos UIKit du guide. Bombe et Magix passent par les fabriques `makeGuide…` |
| `Watch/UI/WatchGridCanvas.swift`, `WatchBlockTile` | Grille Watch. **Hors périmètre** (section 5). Ne pas y toucher |

Étape 1 : seulement la fabrique principale, et seulement les Blox couleur, en lisant le style figé au début de partie (V3). Les 11 appels suivront tous. Étape 2 : Brix, Magix, bombe, chute, file, preview, guide, partage, overlay pire coup. Les mutateurs de la même ligne du tableau vont avec.

## 5. Direction visuelle New (gelée encore à l'écran)

> **Cible du mode New : Encre**, en place depuis le 15/11/2026 ([DA_ENCRE_WASHI.md](DA_ENCRE_WASHI.md)).
> Le texte ci-dessous décrit l’ancienne gelée, dont la géométrie (pièces, congés, diagonale) est réutilisée.
> Les étapes 2, 3, 5 et 6 de la gelée restent en pause.

- **Matière gelée / bonbon translucide** : volume doux, reflet spéculaire en haut à gauche,
  ombre portée courte, léger biseau. Lumière venant du haut-gauche, **cohérente partout**.
- **Fusion des blocs de même couleur adjacents** : sur la maquette, des cellules voisines de même
  couleur forment une seule pièce continue (coins intérieurs arrondis). Fait au repos en New (V8) :
  une texture par groupe 8-connexe, sans changer la logique de jeu.
- **Priks** : bloc violet profond avec chiffre blanc en relief, lisible avant tout.
- **Grille** : plateau de verre dépoli, cellules vides en creux légers.
- **Fond** clair crème ; titre BLOMIX et score en relief (étape habillage).
- Rendu par **textures pré-générées** (Core Graphics → `SKTexture`, mises en cache par couleur/taille/
  forme), pas de shader lourd par bloc. Viser 60 i/s sur iPhone 12.

### Points de vigilance

- **Contraste sur fond clair** : ratios calculés sur le crème — violet 1,55, jaune 1,56, bleu 2,11.
  Prévoir contour ou ombre pour que chaque couleur se détache, et vérifier en mode daltonien si existant.
- **Les diagonales font partie de la pièce** (V8, demandé par Lomig, au-delà du « orthogonal seulement ») :
  une diagonale déjà dans le polyomino orthogonal n’est pas redessinée. Deux cases qui ne se touchent
  que par un coin sont reliées par un trait de la même gelée, de la largeur du trait Classique
  (`sqrt(32)`), dans le même contour. Le L de la maquette garde son coin intérieur creux.
- L'habillage complet (titre, HUD, boutons) obligerait à rouvrir la décision D18 : **hors périmètre**
  tant que Lomig ne l'a pas validé.
- Apple Watch : **non concernée**.

## 6. Découpage par étapes

| Étape | Contenu | Critère de sortie |
|---|---|---|
| 0 | **Fait le 14/11/2026.** Réglage Old/New (enum, notification, ligne Réglages, 6 langues). New = Old. Inventaire §4.1. Pas de rebuild en partie (V3). | Bascule visible, aucun changement de plateau, build + tests OK |
| 1 | **Fait le 14/11/2026.** Blox couleur en gelée (`BlomixNewBlockRenderer`), cache par couleur / pixels / Clair-Sombre. Style figé au début de partie (V5). | Grille New : Blox gelée. Old identique. Priks, Magix, bombe, file et aperçu encore Old. |
| 2 | Priks + Magix + bombe + bloc qui tombe + aperçu prochains blox en New | Tous les types de blocs rendus en New |
| 3 | Grille de verre et cellules vides | Plateau conforme à la maquette |
| 4 | **Fait au repos, le 14/11/2026.** Une texture par groupe 8-connexe de même couleur. Orthogonal : une pièce, congés intérieurs. Diagonale interne : englobée, plus de trait. Diagonale seule : trait fin de la même matière, largeur Classique. Pendant une animation la pièce se sépare en cases, puis se reforme. | Grille New au repos : formes continues. Classique inchangé. |
| 5 | Animations (pose, chaîne, cascade) adaptées à la matière | Juice cohérent, perf 60 i/s |
| 6 | (si validé, D18) Habillage : titre, score, HUD, boutons | Décision Lomig |

Chaque étape = un commit local, `CHANGELOG.md` + ce plan mis à jour (cocher, noter les décisions).

La suite du look New est la piste Encre ([DA_ENCRE_WASHI.md](DA_ENCRE_WASHI.md) §5). E0 à E5 sont faites. E6 (habillage pinceau et hanko) attend Lomig.

## 7. Interdits pour les agents

- Pas de `git push`, pas de fastlane, pas d'App Store Connect, pas de TestFlight.
- Pas de changement de version / build (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
- Ne pas modifier le schéma Watch (si Xcode le reformate : `git checkout -- <schéma>`).
- Ne pas toucher au gameplay, au PvP, à CloudKit, à la télémétrie.

## 8. Vérification à chaque étape

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` ; build simulateur iPhone + tests existants.
- Captures simulateur **Classique et Encre** (clair + sombre) jointes au compte rendu.
  Classique doit rester identique. Tant que la matière Encre n'est pas en place, la capture
  Encre doit rester la gelée d'avant l'étape.

## 9. Décisions

| # | Décision | Date |
|---|---|---|
| V1 | Cible = maquette 2 (gelée sur fond crème). Rester en SpriteKit. | 14/11/2026 |
| V2 | Bascule Old/New dans Réglages, Old par défaut et inchangé. | 14/11/2026 |
| V3 | Le segment persiste tout de suite (`UserDefaults` `BlomixVisualStyle`, notification `blomixVisualStyleDidChange`, `object` = le nouveau style). Il ne reconstruit pas la partie, même ouverte depuis le menu en cours. Étape 0 : aucun abonné, New et Old sont le même code de rendu. Étapes 1+ : lire le style **au début de partie** (nouvelle partie ou reprise), pas pendant une résolution. | 14/11/2026 |
| V4 | `makeSolidGameplayBlockSprite` a 11 appels. La file « prochains blox », le gros bloc courant, la chute Magix, la bombe, l’overlay pire coup, le guide, le partage et la Watch sont d’autres points (§4.1). | 14/11/2026 |
| V5 | Le style de la partie est le snapshot statique `GameScene.visualStyleForRun` (la fabrique est `static`). Il est lu dans `BlomixVisualStyle.current` une fois, avant le premier `drawGrid`, pour : Arcade neuve (le tutoriel passe par là), Zen, Five, Défi neuf, reprise (`restoreFromSoloSave`, y compris Défi repris), et chaque manche PvP au handshake. Remis à `.old` au retour accueil (grille masquée). `didChangeSize` et les résolutions ne relisent pas UserDefaults. La texture gelée est un masque d’éclairage multiplié par `sprite.color` (`colorBlendFactor` 1) : dissolution et cycle SAINTX continuent d’écrire la couleur. Le reflet blanc est un sprite enfant. Une partie typique : **6** textures gelée (6 couleurs du skin, taille `cell − 4`, une apparence, une échelle) **+ 1** reflet partagé. Changer Clair/Sombre en cours de partie ajoute jusqu’à 6 entrées, pas un rendu par bloc. `morphMagixSprite` vers un Blox couleur reste un aplat jusqu’au prochain `drawGrid` (mutateur, étape 2). La chute couleur passe déjà par la fabrique : elle est gelée dès cette étape. | 14/11/2026 |
| V6 | Le corps gelée remplit le sprite (`cell − 4`), coins ≈ 0,12 du côté : carré arrondi, presque toute la case. Les jonctions orthogonales New sont des sprites du même dégradé, sur le plat du contact, assez épais pour couvrir le liseré face au voisin. Les diagonales New gardent le trait, en teinte matière, sous les Blox (z 0,55) pour ne rester visibles que dans la fente. Classique : rectangle 4×36 / 36×4 et diagonale inchangés. La fusion en une seule pièce (coins intérieurs) reste l’étape 4. | 14/11/2026 |
| V7 | Le filet de la maquette : en New le sprite de grille passe à `cell − 1` (39 pt) et la marge de texture à ~1 % du côté, soit environ 2 pt entre les corps. Classique reste 36 pt. Les Brix (fabrique, chute, fantômes, SAINTX, mue) sont la même gelée ; le chiffre est au-dessus du reflet (z 3). Les deux minis de la file et le gros aperçu courant (couleur et Brix seulement) aussi, sans changer leur taille — l’alignement de la file reste sur `cell − 4`. La file est repeinte juste après le gel du style (`setupBombHUD` la peint avant). Flash BRIXED et disparition Brix New reviennent à une teinte pleine, pour ne pas laisser le masque gris. Magix, bombe, guide, partage : inchangés. | 14/11/2026 |
| V8 | Au repos, en New, un groupe de Blox de même couleur (8-connexité, comme les chaînes) est une texture : dégradé unique, un reflet, un contour. L’orthogonal a des congés extérieurs et intérieurs. Une barre diagonale dont les deux cases sont déjà dans cette pièce n’est pas dessinée : elle est dans la matière. Une diagonale entre deux pièces qui ne se touchent que par un coin est un trait de la même gelée, unionné au contour (V9). Les sprites `cell_` restent pour les animations ; ils sont cachés au repos. Dès qu’une case bouge, fond ou change d’échelle, son groupe redevient des cases le temps du geste, puis la pièce se reforme. Le coup de voisin (2 pt) ne sépare pas. Classique : barres 4×36 et traits diagonaux inchangés. Le préfixe du nœud est `blomixNewFusion` (la fin de partie retire `junction_`, pas les pièces). | 14/11/2026 |
| V9 | La diagonale seule n’est plus un disque au coin partagé. Même épaisseur que le trait Classique (`sqrt(32)`), même matière. En Encre, seul le tronçon entre les deux contours est dessiné : le trait ne traverse pas les blox. | 15/11/2026 |
| E0 | `.new` est la piste Encre. Pas de `case ink`, pas de segment Gelée. Réglages : « Classique / Encre (bêta) », 6 langues (FR Encre, EN Ink, DE Tinte, ES Tinta, IT Inchiostro, PT Tinta). Classique inchangé. Référence : `docs/design/9.0/encre-washi-rendu1.png`. | 15/11/2026 |
| E1–E5 | Papier washi (fond de partie et grille, Clair et Sombre). Blox en taches d’encre, pièces V8/V9 conservées, Brix indigo chiffre blanc, file et aperçu compris. Pose +4 % / 0,15 s. Chaîne aspirée vers le centre de chaque case, mêmes durées. Chelsea Market à la place de Changa One en Encre seulement (Nunito encore le chrome ce jour-là). Pangolin remplace Nunito plus tard, toujours en Encre seulement. Caveat Brush, puis Rubik Dirt, essayées d’abord, sont retirées. Le grain des Blox et des Brix est un cran plus discret. | 15/11/2026 |
| E5b | Papier clair `#F3E8D4` (plus ocre que `#F6F1E7`). Plus de liseré gris sur les Blox et les Brix : le bord est un léger bassin de pigment. La diagonale est la même encre, pas un trait plus noir. | 15/11/2026 |
| E5c | Les six fibres courbes du papier sont retirées (elles traversaient le filet). Les taches ont des bassins, des flaques et du grain stables, sans trait gris. | 15/11/2026 |
| E5d | La variation n’est plus quelques grosses flaques (elles se répétaient sur une pièce). Granulation en trois octaves, taille fixe en points : grain plus présent, variation lente très légère. | 15/11/2026 |
| E5e | Brix Encre : les deux couleurs du skin (fond `priks`, chiffre `prikstext`, même mélange qu’en Classique). Plus d’indigo, plus de chiffre blanc forcé. Gros score : lavis dans les glyphes seulement, gris au repos, teinté par les paillettes, sans plaque. | 16/11/2026 |
| E5f | Case Encre seule, et case au moment où une chaîne se sépare : tampon de l’adresse, pas le tampon « 0_0 » commun à la couleur (la clé de pièce ignore l’adresse) et pas le tampon de la file (sel 0). 64 masques, peints une fois hors du fil au début de la partie et après une purge. La teinte est celle du skin. Poser le masque ne peint rien. La pièce de plusieurs cases reste un seul lavis. | 18/11/2026 |
| P1 | Prise en main, mesure seulement. `eventsJSON` gagne `tutorial_start`, `tutorial_step`, `tutorial_end` et `is_new_install` sur `first_launch`. Pas de champ CloudKit nouveau. L’accueil ne change pas. Le tuto passe par Découvrir, il n’est pas automatique. | 19/11/2026 |
| P2 | Installation neuve : la popup Nouveautés ne s’affiche pas. La campagne courante est marquée vue. L’accueil ne change pas. | 19/11/2026 |
| P3 | Le tuto dit que 5 blox comptent en ligne, en L ou en diagonale, et montre la chaîne en biais. Une bulle pointe la file des prochains blox. | 19/11/2026 |
| P4 | Fin du tuto : une phrase et l’exemple COLORX, plus « Prêt pour ta première vraie partie ? ». Plus de défilé des 9 Magix, plus de « Tu sais tout ». | 19/11/2026 |
| P5 | Tutoiement des conseils du jour et des phrases FR encore en vous. Le Guide aligne le +500 sur le code : × stage en Arcade, plat en Zen et Five. L’ancien Guide disait l’inverse pour l’Arcade. | 19/11/2026 |

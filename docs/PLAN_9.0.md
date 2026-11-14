# PLAN 9.0 — Nouveau look « New » (prototype à bascule Old / New)

> À lire en premier par tout agent (Grok Build) qui travaille sur la branche `9.0`.
> Worktree : `~/Developer/BLOMIX-9.0`. Ne jamais toucher `~/Documents/GIT/BLOMIX` (iCloud).
> Étape 0 faite le 14/11/2026. Prochaine : étape 1. Le rendu New est encore le rendu Old.

## 1. Objectif

La 9.0 introduit un nouveau rendu visuel, **New**, inspiré de `docs/design/9.0/maquette-new-cible.jpg`
(la maquette 1 `maquette-1-exploration.jpg` n'est qu'une exploration, **pas** la cible).

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
- Notification `blomixVisualStyleDidChange` postée au changement.
- Ligne dans `SettingsViewController` (`LeaderboardViewController.swift`) : libellé « Style visuel »,
  segment « Classique / Nouveau (bêta) ». Chaînes localisées dans les 6 langues (voir `LOCALIZATION.md`).
- Bascule visible dans Réglages (accueil et menu de partie). **Décision V3** : le segment
  écrit tout de suite UserDefaults et poste la notification. Il ne reconstruit pas la grille.
  Le style sera lu à la **prochaine partie** (étape 1+), jamais au milieu d’une résolution.
- Compatible avec Sombre / Clair : New doit fonctionner dans les deux, même si la maquette est en clair.
  Étape 0 : les deux thèmes affichent le segment ; le plateau ne change pas.

## 4. Point de branchement du rendu

- Les blocs de grille passent par `GameScene.makeSolidGameplayBlockSprite(block:pixelSize:priksDigitFontSize:)`
  (≈ 12 appels) : c'est le point d'entrée principal. En New, déléguer à
  `BlomixNewBlockRenderer` ; en Old, code actuel inchangé.
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
| `settleBlock` / `rebuildBloxJunctionShapes` | 15637 / 15755 | Barres entre Blox de même couleur. Étape 4 (fusion) : les remplacer ou les masquer. Pas des blocs |
| Grains d’air | ~16719 | Pas des blocs |
| Cadre `gridFrameOutlineName` | 16023, dans `drawGrid` | Étape 3 |

**Hors partie SpriteKit**

| Lieu | Rôle |
|---|---|
| `BlomixShareComposer` (~l. 184) | Carte de partage, Core Graphics, une boucle sur la grille |
| `BlomixGuideIllustrationView.drawRoundedBlock` / `drawBlox` / `drawBrix` / `drawLine` | Pictos UIKit du guide. Bombe et Magix passent par les fabriques `makeGuide…` |
| `Watch/UI/WatchGridCanvas.swift`, `WatchBlockTile` | Grille Watch. **Hors périmètre** (section 5). Ne pas y toucher |

Étape 1 : seulement la fabrique principale, et seulement les Blox couleur, en lisant le style figé au début de partie (V3). Les 11 appels suivront tous. Étape 2 : Brix, Magix, bombe, chute, file, preview, guide, partage, overlay pire coup. Les mutateurs de la même ligne du tableau vont avec.

## 5. Direction visuelle New (d'après la maquette cible)

- **Matière gelée / bonbon translucide** : volume doux, reflet spéculaire en haut à gauche,
  ombre portée courte, léger biseau. Lumière venant du haut-gauche, **cohérente partout**.
- **Fusion des blocs de même couleur adjacents** : sur la maquette, des cellules voisines de même
  couleur forment une seule pièce continue (coins intérieurs arrondis). C'est un marqueur fort du look,
  mais coûteux : à traiter en étape dédiée (calcul de voisinage, pas de logique de jeu modifiée).
- **Priks** : bloc violet profond avec chiffre blanc en relief, lisible avant tout.
- **Grille** : plateau de verre dépoli, cellules vides en creux légers.
- **Fond** clair crème ; titre BLOMIX et score en relief (étape habillage).
- Rendu par **textures pré-générées** (Core Graphics → `SKTexture`, mises en cache par couleur/taille/
  forme), pas de shader lourd par bloc. Viser 60 i/s sur iPhone 12.

### Points de vigilance

- **Contraste sur fond clair** : ratios calculés sur le crème — violet 1,55, jaune 1,56, bleu 2,11.
  Prévoir contour ou ombre pour que chaque couleur se détache, et vérifier en mode daltonien si existant.
- **Les diagonales doivent rester lisibles** : les chaînes sont en 8-connexité ; la fusion visuelle ne
  doit relier que l'orthogonal, sans faire croire que deux blocs en diagonale ne comptent pas.
- L'habillage complet (titre, HUD, boutons) obligerait à rouvrir la décision D18 : **hors périmètre**
  tant que Lomig ne l'a pas validé.
- Apple Watch : **non concernée**.

## 6. Découpage par étapes

| Étape | Contenu | Critère de sortie |
|---|---|---|
| 0 | **Fait le 14/11/2026.** Réglage Old/New (enum, notification, ligne Réglages, 6 langues). New = Old. Inventaire §4.1. Pas de rebuild en partie (V3). | Bascule visible, aucun changement de plateau, build + tests OK |
| 1 | Bloc gelée unitaire (Blox couleur) en New via `BlomixNewBlockRenderer`, textures en cache | Grille en New avec blocs gelée, Old inchangé |
| 2 | Priks + Magix + bombe + bloc qui tombe + aperçu prochains blox en New | Tous les types de blocs rendus en New |
| 3 | Grille de verre et cellules vides | Plateau conforme à la maquette |
| 4 | Fusion des blocs adjacents de même couleur | Formes continues, diagonales lisibles |
| 5 | Animations (pose, chaîne, cascade) adaptées à la matière | Juice cohérent, perf 60 i/s |
| 6 | (si validé, D18) Habillage : titre, score, HUD, boutons | Décision Lomig |

Chaque étape = un commit local, `CHANGELOG.md` + ce plan mis à jour (cocher, noter les décisions).

## 7. Interdits pour les agents

- Pas de `git push`, pas de fastlane, pas d'App Store Connect, pas de TestFlight.
- Pas de changement de version / build (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
- Ne pas modifier le schéma Watch (si Xcode le reformate : `git checkout -- <schéma>`).
- Ne pas toucher au gameplay, au PvP, à CloudKit, à la télémétrie.

## 8. Vérification à chaque étape

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` ; build simulateur iPhone + tests existants.
- Captures simulateur **Old et New** (clair + sombre) jointes au compte rendu, pour comparer Old
  avant/après (doit être identique).

## 9. Décisions

| # | Décision | Date |
|---|---|---|
| V1 | Cible = maquette 2 (gelée sur fond crème). Rester en SpriteKit. | 14/11/2026 |
| V2 | Bascule Old/New dans Réglages, Old par défaut et inchangé. | 14/11/2026 |
| V3 | Le segment persiste tout de suite (`UserDefaults` `BlomixVisualStyle`, notification `blomixVisualStyleDidChange`, `object` = le nouveau style). Il ne reconstruit pas la partie, même ouverte depuis le menu en cours. Étape 0 : aucun abonné, New et Old sont le même code de rendu. Étapes 1+ : lire le style **au début de partie** (nouvelle partie ou reprise), pas pendant une résolution. | 14/11/2026 |
| V4 | `makeSolidGameplayBlockSprite` a 11 appels. La file « prochains blox », le gros bloc courant, la chute Magix, la bombe, l’overlay pire coup, le guide, le partage et la Watch sont d’autres points (§4.1). | 14/11/2026 |

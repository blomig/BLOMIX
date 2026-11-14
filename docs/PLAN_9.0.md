# PLAN 9.0 — Nouveau look « New » (prototype à bascule Old / New)

> À lire en premier par tout agent (Grok Build) qui travaille sur la branche `9.0`.
> Worktree : `~/Developer/BLOMIX-9.0`. Ne jamais toucher `~/Documents/GIT/BLOMIX` (iCloud).

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
- Bascule **hors partie** au minimum ; en partie, soit rebuild propre de la grille, soit application
  à la partie suivante (choisir le plus sûr et le documenter).
- Compatible avec Sombre / Clair : New doit fonctionner dans les deux, même si la maquette est en clair.

## 4. Point de branchement du rendu

- Les blocs de grille passent par `GameScene.makeSolidGameplayBlockSprite(block:pixelSize:priksDigitFontSize:)`
  (≈ 12 appels) : c'est le point d'entrée principal. En New, déléguer à
  `BlomixNewBlockRenderer` ; en Old, code actuel inchangé.
- Autres fabriques à inventorier avant d'y toucher : `makeBlockCell`, `makeFallingBlockNode`,
  `makeBottomLinePreviewCellNode`, aperçu « prochains blox », Magix (`makeMagixShaderSprite`).
- Grille vide (cellules), cadre de grille, HUD : étapes ultérieures.

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
| 0 | Réglage Old/New + plomberie (enum, notification, ligne Réglages, 6 langues). New = Old pour l'instant. | Bascule visible, aucun changement visuel, build + tests OK |
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

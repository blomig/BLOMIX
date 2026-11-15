# DA « Encre » — encre et aquarelle sur papier washi (piste 1)

> À lire par Grok Build **après** `docs/PLAN_9.0.md`, dont toutes les règles s'appliquent
> (règle d'or §2, interdits §7, vérification §8). Worktree : `~/Developer/BLOMIX-9.0`, branche `9.0`.
> Rédigé le 15/11/2026 à la demande de Lomig, d'après le rendu Grok Imagine de la piste 1, jugé « assez chouette ».
> Référence visuelle : `docs/design/9.0/encre-washi-rendu1.png`.

## 1. Intention

Les blocs deviennent des taches d'encre ou d'aquarelle posées sur un papier japonais texturé.
Deux voisins de même couleur fusionnent comme deux gouttes qui se touchent ; une chaîne de 5
s'efface comme de l'encre bue par le papier. Ambiance : calme, zen, élégante, artisanale,
mais **un écran de jeu net et lisible avant tout**. Rendu 2D plat : pas de 3D, pas de reflet
brillant, pas d'ombre portée (sauf un très léger assombrissement de papier mouillé sous l'encre).

## 2. Place dans le code (ne rien casser)

- **L'Encre remplace la gelée comme mode New.** Décision de Lomig, 15/11/2026 (E0).
  Pas de `case ink` et pas de troisième segment : `BlomixVisualStyle` reste `.old` / `.new`.
  `.new` est la piste Encre. Segment Réglages : « Classique / Encre (bêta) », 6 langues
  (`LOCALIZATION.md`). Classique reste le défaut et reste identique au pixel près.
- **E0** a renommé le segment. **E1 à E5** (15/11/2026) dessinent l'encre.
  Le papier, le masque et le grain vivent dans `BlomixNewInkRenderer.swift`
  (commentaires `// 9.0 Ink:`). La géométrie des pièces reste dans `BlomixNewBlockRenderer`.
  Les points d'entrée sont les mêmes (`makeSolidGameplayBlockSprite`, `applyJelly`, pièces au repos).
  Pas de `switch` supplémentaire : `.new` suffit.
- **Chelsea Market** remplace Changa One (display et grille) quand `BlomixVisualStyle.current` est `.new`.
  Nunito reste le chrome. Classique garde Changa One.
- **Réutiliser la géométrie existante** de `BlomixNewBlockRenderer` : groupes 8-connexes (V8),
  contours orthogonaux avec congés, diagonale seule en capsule (V9), cases séparées pendant les
  animations puis pièce reformée. Factoriser les chemins si besoin. La gelée n'est plus un style
  choisi : sa géométrie sert de base, puis la matière de `.new` devient l'encre.
  **Classique** reste identique au pixel près.
- Style figé au début de partie (V3/V5), comme la gelée.
- Textures pré-cuites en Core Graphics → `SKTexture`, en cache. Pas de shader par bloc. 60 i/s sur iPhone 12.

## 3. Direction visuelle détaillée

### Papier (fond)
- Mode Clair : washi blanc cassé ocre (`#F3E8D4`, un cran plus chaud que le premier `#F6F1E7`), grain fin discret. Pas de fibres courbes : elles se lisaient comme des traits par-dessus le filet.
- Texture générée **une fois** (bruit procédural), à la taille de la grille, mise en cache.
- Mode Sombre : papier sumi anthracite chaud (ordre d'idée `#26231F`), même grain ; l'encre y devient de la gouache
  claire et saturée. Il doit marcher, même si le Clair est la référence.

### Blocs (Blox de couleur)
- Chaque case est une flaque d'aquarelle saturée, bords **légèrement irréguliers** peints à la main.
- Granulation fine, à l'échelle du papier (bruit de valeur en points, pas en fraction de la pièce). Le grain est présent. La variation lente reste très légère, pour que deux cases d'une même pièce ne portent pas le même motif. Le washi transparaît dans les pointes du grain. Pas de liseré gris. Stable : même graine, même tache.
- **Irrégularité stable** : le tremblé du bord est déterministe (graine = couleur + coordonnées des cases du groupe).
  La même pièce doit être dessinée à l'identique à chaque `drawGrid` : aucun scintillement.
- Garder la forme de la case reconnaissable : le tremblé reste faible (≈ 1 pt), jamais au point de mordre sur le filet.
- Couleurs = celles du skin du joueur (comme la gelée, `sprite.color` × masque), mais **vives et franches**,
  jamais boueuses ni grises. Les teintes pâles (violet 1,55, jaune 1,56, bleu 2,11 en ratio,
  voir PLAN §5) ont un bassin de pigment un peu plus marqué, sans trait gris.

### Fusion
- Voisins orthogonaux de même couleur : **une seule tache continue**, les bords se mêlent comme de l'encre mouillée
  (léger fondu au point de contact, pas de ligne). Reprendre les pièces V8.
- Couleurs différentes : toujours séparées par un fin filet de papier nu.
- Diagonale seule (deux cases ne se touchant que par un coin) : un **trait de pinceau fin** de la même encre,
  épaisseur `sqrt(32)` comme le trait Classique (V9), bouts légèrement effilés. Même pigment que les cases,
  sans contour plus sombre qui le délimite.

### Brix (Priks)
- Encre indigo profond, chiffre en lettrage pinceau **blanc net**, parfaitement lisible (lisibilité > style).

### Cases vides
- Lignes de grille au crayon ou à l'encre sumi très diluée, à peine visibles.

### Hors périmètre de cette DA pour l'instant
- Titre, score, boutons, HUD (habillage) : la piste prévoit pinceau sumi noir + petit tampon hanko rouge
  près du titre, mais c'est soumis à la décision D18 de Lomig. Ne pas le faire sans son accord.
- Apple Watch : non concernée.

## 4. Animations (étape tardive)

- Pose d'un bloc : la tache « boit » le papier, petite expansion de 3 à 5 % puis retour (≈ 0,15 s).
- Fusion qui se forme : fondu doux entre les cases et la pièce, pas de pop.
- Chaîne de 5 : le centre de chaque case aspire la tache (×0,55, ×0,16, puis pincement avec le fondu, 0,50 s),
  sans changer la durée logique des résolutions (le gameplay et les timings de cascade ne bougent pas).
- Magix et bombe : les effets, le halo, les orbites et les durées restent ceux du Classique. En Encre, le disque est un masque aquarelle (grain des Blox, couronne d’encre irrégulière) multiplié par la palette animée. Le glyphe reste noir.

## 5. Étapes proposées (un commit local par étape, CHANGELOG + PLAN mis à jour)

| Étape | Contenu | Critère de sortie |
|---|---|---|
| E0 | **Fait le 15/11/2026.** `.new` = piste Encre. Segment « Classique / Encre (bêta) », 6 langues. Pas de troisième cas. Rendu `.new` encore gelée. | Bascule visible, Classique inchangé, rendu Nouveau identique à la gelée d'avant, build + tests OK |
| E1 | **Fait le 15/11/2026.** Papier washi (fond de partie + grille, Clair + Sombre) et cases vides au crayon | Fond conforme, perf OK |
| E2 | **Fait le 15/11/2026.** Blox de couleur en encre, cache, irrégularité stable | Plus aucun aplat dans la grille Encre au repos |
| E3 | **Fait le 15/11/2026.** Fusion en taches continues + diagonale (géométrie V8/V9) | Pièces continues, aucun scintillement entre deux `drawGrid` |
| E4 | **Fait le 15/11/2026.** Brix indigo, chute, file, gros aperçu, fantômes | Tous les blocs couleur/Brix en encre |
| E5 | **Fait le 15/11/2026.** Pose : +4 % puis retour. Chaîne : aspiration vers le centre, mêmes durées | Juice cohérent, 60 i/s |
| E6 | (si validé par Lomig, D18) Habillage pinceau + hanko | Décision Lomig |

Faire **E0 puis s'arrêter** pour le compte rendu ; ensuite une étape à la fois, sur demande de Lomig.

## 6. Vérification

- Build simulateur iPhone + tests existants verts (`BlomixReferenceTests`, `swift test`).
- Captures simulateur Classique / Encre, en Clair et en Sombre, jointes au compte rendu.
  Classique doit être identique à avant. Tant que la matière n'a pas changé (E0), Encre
  doit être identique à la gelée d'avant.
- Lisibilité : chaque couleur doit se distinguer d'un coup d'œil, y compris les diagonales.
- Rappel des interdits (PLAN §7) : pas de push, pas de fastlane, pas d'ASC/TestFlight, pas de changement
  de version/build, pas de modification du schéma Watch, pas de changement de gameplay, PvP, CloudKit, télémétrie.

## 7. Prompt de référence (Grok Imagine, piste 1)

```
Redesign this mobile puzzle game screenshot in a new art direction, keeping the exact same layout,
grid (8x8), block positions, colors, numbers, UI elements and text. Only change the visual style.
Art direction: Japanese ink and watercolor on washi paper.
- Background: warm off-white handmade washi paper with visible soft fibers and subtle grain, very light.
- Blocks: each block is a square pool of saturated watercolor ink with slightly irregular, hand-painted
  edges, pigment pooling darker along the borders and lighter in the center, tiny paper texture showing through.
- Adjacent blocks of the same color merge into one continuous ink shape, their edges bleeding softly
  into each other like wet ink drops touching; different colors stay clearly separated by a thin line of bare paper.
- Numbered blocks: deep indigo ink with the number painted in clean white brush lettering, perfectly legible.
- Empty grid cells: barely visible pencil or faded sumi-e grid lines on the paper.
- UI: thin black sumi ink brush strokes and calligraphic lettering, with one small red hanko seal stamp near the title.
- Colors stay bright, clean and high-contrast against the paper; no muddy or grey tones.
- Flat 2D, no 3D, no glossy highlights, no drop shadows except a faint wet-paper darkening under the ink.
```

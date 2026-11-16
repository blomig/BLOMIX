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
  `.new` est la piste Encre. Réglages : une ligne Apparence, trois boutons Sombre / Clair / Encre
  (`LOCALIZATION.md`). Encre est toujours le clair. Classique reste le défaut et reste identique au pixel près.
- **E0** a renommé le segment. **E1 à E5** (15/11/2026) dessinent l'encre.
  Le papier, le masque et le grain vivent dans `BlomixNewInkRenderer.swift`
  (commentaires `// 9.0 Ink:`). La géométrie des pièces reste dans `BlomixNewBlockRenderer`.
  Les points d'entrée sont les mêmes (`makeSolidGameplayBlockSprite`, `applyJelly`, pièces au repos).
  Pas de `switch` supplémentaire : `.new` suffit.
- **Chelsea Market** remplace Changa One (display et grille) quand `BlomixVisualStyle.current` est `.new`.
  Nunito reste le chrome. Classique garde Changa One.
- **Réutiliser la géométrie existante** de `BlomixNewBlockRenderer` : groupes 8-connexes (V8),
  contours orthogonaux avec congés, diagonale seule limitée à l'écart entre les blox (V9), cases séparées pendant les
  animations puis pièce reformée. Factoriser les chemins si besoin. La gelée n'est plus un style
  choisi : sa géométrie sert de base, puis la matière de `.new` devient l'encre.
  **Classique** reste identique au pixel près.
- Style figé au début de partie (V3/V5), comme la gelée.
- Textures pré-cuites en Core Graphics → `SKTexture`, en cache. Pas de shader par bloc. 60 i/s sur iPhone 12.
- La pièce fusionnée se peint hors du fil du jeu. Tant qu’elle n’est pas prête, les cases restent visibles. Une chaîne n’attend pas la peinture pour disparaître. Au-delà de 64 000 pixels, l’échelle baisse (filtre linéaire) : une grande tache reste souple, le fil du jeu ne s’arrête pas.

## 3. Direction visuelle détaillée

### Papier (fond)
- Mode Clair : le pourtour de la partie reste un washi blanc cassé ocre (`#F3E8D4`, un cran plus chaud que le premier `#F6F1E7`). La feuille de la grille est `#F0E6D2`, la même teinte que les cases vides du Classique clair.
- Cette feuille porte un grain continu très léger (deux octaves, environ ±1,5 %), Clair et Sombre. Pas de points isolés, pas de fibres courbes : elles se lisaient comme des traits par-dessus le filet. Le filet de crayon passe après le grain.
- Texture générée **une fois** (bruit procédural), à la taille de la grille, mise en cache.
- Le joueur ne choisit plus le papier sombre. Encre est toujours ce clair. Le sombre (`#26231F`) reste dans le rendu, mais l’apparence Encre ne l’allume pas.

### Blocs (Blox de couleur)
- Chaque case garde la silhouette arrondie d'avant (rayon ~0,12). Le lavis est le pigment, clippé sur les cases posées : il ne peut pas peindre la case d'à côté.
- Quelques flaques de 9 à 18 pt, en points absolus, laissent voir le washi. L'opacité descend vers 0,58 dans deux ou trois creux, même teinte. Pas de grande fleur répétée d'une case à l'autre.
- Le duvet de 1,55 pt est calmé : il ne fait plus la surface. Pas de liseré gris. Sur une forme épaisse, les 2 pt intérieurs sont un peu plus chargés (même teinte). Le 1 pt extérieur s'efface. Le pont diagonal, hors des cases, s'efface en lentille : pas de bord plus opaque, et le tour des cases n'est pas élargi.
- **Irrégularité stable** : graine = couleur + coordonnées des cases du groupe. La même pièce est identique à chaque `drawGrid` : aucun scintillement.
- Couleurs = celles du skin du joueur (`sprite.color` × masque), **vives et franches**. Les teintes pâles (violet 1,55, jaune 1,56, bleu 2,11 en ratio, voir PLAN §5) ont une cuvette un peu plus marquée, sans trait gris.

### Fusion
- Voisins orthogonaux de même couleur : **une seule tache continue**, les bords se mêlent comme de l'encre mouillée
  (léger fondu au point de contact, pas de ligne). Reprendre les pièces V8.
- Couleurs différentes : toujours séparées par un fin filet de papier nu.
- Diagonale seule (deux cases ne se touchant que par un coin) : un **trait de pinceau** de la même encre,
  épaisseur `sqrt(32)` comme le trait Classique (V9), seulement sur le tronçon entre les deux contours.
  Le trait ne traverse pas les blox. Même pigment. Le bord du pont s'efface en lentille. Le lavis des cases
  ne s'élargit pas. Le groupement ne change pas.

### Brix (Priks)
- Même lavis que les Blox (flaques, charge au bord des formes épaisses). La teinte du fond est `priks` du skin, comme en Classique. Le chiffre est `prikstext`, et il se mélange au fond au fil des coups (5 et 4 = couleur du chiffre, 3 = 80 %, 2 = 60 %, 1 = 40 %). Le plancher d'opacité (0,58) garde un fond sous le chiffre.

### Gros score
- Encre seulement : le même lavis que les pièces, **dans** les chiffres. Pas de plaque, rien qui dépasse l’encre. Les contreformes (0, 4, 6, 8, 9) restent des trous. Au repos le chiffre est gris pour que les flaques se voient : gris foncé (blanc 0,30) sur le papier clair, gris moyen (blanc 0,58) sur le papier sombre. Quand les paillettes arrivent, les glyphes prennent leur couleur le temps du roll, puis le gris revient (0,30 s). Cette couleur est une teinte du sprite, pas une nouvelle peinture. Les dix chiffres (trois variantes chacun) sont peints une fois, hors du fil du jeu ; le roll ne fait que les réassembler. La course suit toujours la couleur du texte. Classique : chiffre plein, couleur du texte, sans lavis. RECORD, LIGNE et TEMPS ne sont pas lavés. Pas de tampon hanko (D18 toujours en attente).

### Cases vides
- Lignes de grille au crayon ou à l'encre sumi très diluée, à peine visibles.

### Hors périmètre de cette DA pour l'instant
- Titre, score, boutons, HUD (habillage) : la piste prévoit pinceau sumi noir + petit tampon hanko rouge
  près du titre, mais c'est soumis à la décision D18 de Lomig. Ne pas le faire sans son accord.
- Apple Watch : non concernée.

## 4. Animations (étape tardive)

- Pose d'un bloc : la tache « boit » le papier, petite expansion de 3 à 5 % puis retour (≈ 0,15 s).
- Fusion qui se forme : fondu doux entre les cases et la pièce, pas de pop.
- Chaîne de 5, Brix à 0, blox effacés par COLORX et blox effacés par SAINTX : le centre de chaque case aspire la tache (×0,55, ×0,16, puis pincement avec le fondu, 0,50 s). Pendant le retrait, le carré devient le cercle inscrit. La chaîne gardait déjà cette attente. Pour les trois autres, le redessin attend la fin du geste. Le pop ×1,25 du Brix déposé par SAINTX reste. Le lavage SAINTX de 2 s ne change pas.
- Paillettes : inchangées, elles lisent comme des gouttes. Les paillettes carrées de la mort d’un Brix deviennent des ronds du même diamètre (aussi au trou SCRUMBLX et dans le blast). Les étoiles de présence restent.
- Magix et bombe : le halo, les orbites, le glyphe et l’explosion (poussée, rotation, effondrement) restent ceux du Classique. En Encre, le disque garde le grain serré (pas le lavis des Blox) et une couronne d’encre irrégulière, multipliés par la palette animée. Le glyphe reste noir. La chute depuis la file (le bloc qui quitte l’aperçu) reste le vol Classique.

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

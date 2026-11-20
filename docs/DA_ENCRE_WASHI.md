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
  **Pangolin** remplace Nunito (chrome) dans le même cas. Classique garde Changa One et Nunito.
- **Réutiliser la géométrie existante** de `BlomixNewBlockRenderer` : groupes 8-connexes (V8),
  contours orthogonaux avec congés, diagonale seule limitée à l'écart entre les blox (V9), cases séparées pendant les
  animations puis pièce reformée. Factoriser les chemins si besoin. La gelée n'est plus un style
  choisi : sa géométrie sert de base, puis la matière de `.new` devient l'encre.
  **Classique** reste identique au pixel près.
- Style figé au début de partie (V3/V5), comme la gelée.
- Textures pré-cuites en Core Graphics → `SKTexture`, en cache. Pas de shader par bloc. 60 i/s sur iPhone 12.
- La pièce fusionnée se peint hors du fil du jeu. Tant qu’elle n’est pas prête, les cases restent visibles. Une chaîne n’attend pas la peinture pour disparaître. Au-delà de 64 000 pixels, l’échelle baisse (filtre linéaire) : une grande tache reste souple, le fil du jeu ne s’arrête pas.
- Ces textures meurent au passage en arrière-plan (swipe vers le haut, l’app reste en mémoire). Au retour, le cache est vidé et la grille est repeinte. Sinon le rectangle de la pièce s’aplatit : blox dans les trous, Brix et blox sur la même case.

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
- **Irrégularité stable** : pour une pièce de plusieurs cases, graine = couleur + coordonnées des cases du groupe. La même pièce est identique à chaque `drawGrid` : aucun scintillement.
- **Case seule** : pas la pièce de forme « 0_0 ». Cette clé ignore l’adresse, donc toutes les cases isolées d’une couleur reprendraient le premier tampon cuit. Chaque case porte le masque de son adresse. Il y en a 64, un par case de la grille, peints une fois hors du fil du jeu au début de la partie et après une purge d’arrière-plan. La teinte est celle du skin (`sprite.color`) : les 64 masques servent toutes les couleurs. Deux cases de même couleur n’ont pas le même motif. Au moment où une chaîne se sépare, chaque case montre ce masque, déjà en cache. Poser la texture ne peint rien, ni à la pose ni à la séparation. Le sel 0 reste le tampon de la file, de l’aperçu, de la chute et des Brix.
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

### Boutons
Encre seulement. Le composant partagé (`BlomixSKButtonNode`, `BlomixUIButton`) : accueil, menus, navigation. Pas un second écran.

- Fond : rectangle arrondi en papier washi, même grain que la feuille de la grille (`#F0E6D2`), sans filet de crayon. Pas de reflet, pas de dégradé de lumière, pas de biseau, pas d’ombre nette.
- La gouttière Classique devient un liseré d’aquarelle. Contour peint (masque pré-rendu), fin (tampon 1,3…2,7 pt, fusé court), épaisseur un peu irrégulière, bords fondus dans le papier. La couleur est le dégradé du skin actif, dans le même ordre que la gouttière Classique, et elle suit le skin en direct (même shader).
- Libellé : Chelsea Market, gris du gros score au repos (blanc 0,30 sur le papier clair).
- Appui : le liseré s’élargit (échelle 1,14, 0,15 s, ease-out) comme une goutte qui s’étale, puis revient (0,16 s, ease-out). Le mot ne s’enfonce pas.
- Pastilles de mode, mot BLOMIX et rangs : pas des boutons. Ils gardent leur dessin.

### Décor de fond
Encre seulement. Les micro-blox deviennent de petits carrés de papier washi aux bords déchirés (quatre silhouettes cuites, teintées ensuite). Tailles, positions et vitesses restent celles du Classique.

- Hors liseré : filigrane, crème sur crème, alpha environ 0,10…0,18. Ils tournent lentement en montant. Réduire les animations coupe cette rotation, pas la montée : le Classique ne l’arrêtait pas non plus.
- Dans le liseré d’un bouton, et dans les gouttières déjà révélatrices (mot BLOMIX, rangs) : la même copie clipée que le Classique, alpha 0,90, teintée par la couleur du skin. Le masque du liseré ne laisse voir le pigment que dans la peinture.
- Grille, en partie Encre : les mêmes confettis, plus petits (4…7 pt) et plus lents (9…16 s), alpha 0,08…0,16, toujours crème. Sous les blox. Réduire les animations : rien, comme l’air Classique.
- Menus UIKit : pas de copie dans une gouttière (le Classique n’en avait pas). Filigrane seulement.

### Hors périmètre de cette DA pour l'instant
- Titre (mot BLOMIX), gros score hors chiffres déjà lavés, HUD hors boutons, tampon hanko : la piste D18 reste en attente. Ne pas le faire sans l’accord de Lomig.
- Apple Watch : non concernée.

## 4. Animations (étape tardive)

- Pose d'un bloc : la tache « boit » le papier, petite expansion de 3 à 5 % puis retour (≈ 0,15 s).
- Fusion qui se forme : fondu doux entre les cases et la pièce, pas de pop.
- Chaîne de 5, Brix à 0, blox effacés par COLORX et blox effacés par SAINTX : le centre de chaque case aspire la tache (×0,55, ×0,16, puis pincement avec le fondu, 0,50 s). Pendant le retrait, le carré devient le cercle inscrit. Une case seule au repos et une case séparée d’une chaîne portent le tampon de leur adresse, pas le tampon partagé de la file et pas le tampon « 0_0 » commun à toutes les cases seules d’une couleur. Ces 64 masques sont peints une fois hors du fil du jeu, au début de la partie (et après une purge d’arrière-plan). La teinte est celle du skin. Poser le tampon ne peint rien. La pièce soudée reste un seul lavis. La chaîne gardait déjà cette attente. Pour les trois autres, le redessin attend la fin du geste. Le pop ×1,25 du Brix déposé par SAINTX reste. Le lavage SAINTX de 2 s ne change pas.
- Paillettes : inchangées, elles lisent comme des gouttes. Les paillettes carrées de la mort d’un Brix deviennent des ronds du même diamètre (aussi au trou SCRUMBLX et dans le blast). Les étoiles de présence gardent leur geste et prennent la couleur de fond du Brix (`priks`).
- Magix et bombe : le centre du disque est le lavis des Blox (flaques, plancher vers 0,58). La couronne d’encre irrégulière reste, multipliée par la palette animée. Le glyphe reste noir. Pas de halo. Les orbites sont celles du Classique : mêmes grains, même trajet jusqu’à 16 pt au-delà du bord. Le pop de peinture et l’explosion (poussée, rotation, effondrement) restent ceux du Classique. Une case ne dépasse pas ce pop (environ ×1,4). La chute depuis la file reste le vol Classique. Seule la disparition des blox et des Brix diffère : aspiration vers le centre de la case. L’aperçu du guide suit l’Encre choisie, ou la partie Encre encore ouverte.

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

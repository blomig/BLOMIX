# BLOMIX — Magix

> **Version de référence** : 6.4  
> Catalogue des blocs Magix **en jeu** et pistes **non implémentées**.  
> Les règles joueur font foi dans [RULES.md](RULES.md) §2c ; constantes et spawn dans [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) §7 ; juice dans [VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md) §6.

Noms Magix **non traduits** (UI, doc, ASC). Code : `MagixKind` / `MagixRules` dans `GameScene.swift` (`crosx` = CROSSX, `cleanx` = SAINTX).

---

## Commun à toutes les variantes

- Effet au **atterrissage** (colonne choisie, première case vide depuis le haut).
- **Jamais** dans les lignes entrantes du bas, **jamais** en **Duel**.
- Cumul de spawn ≈ **2,9 %** du tirage file (pondéré par variante).
- Le lookahead (`BlomixMoveAnalyzer`) **ignore** les Magix.

---

## En jeu (6.4)

| UI | Code | Symbole | Spawn | Effet joueur |
|---|---|---|---|---|
| **CHROMAX** | `.chromax` | ? | 1/324 | Chemin aléatoire ≤ 15 cases occupées → une couleur → chaînes |
| **BRIXED** | `.brixed` | 9 | 1/324 | Devient Brix(9) ; **détruit** tous les autres Brix (+20 chacun). Plus de −2 global |
| **CROSSX** | `.crosx` | + | 1/216 | Ligne + colonne d’atterrissage → couleur aléatoire → chaînes |
| **SCRUMBLX** | `.scrumblx` | = | 1/180 | Chaque ligne occupée se décale (1–7 crans, wrap) ; **−1** tous les Brix |
| **COLORX** | `.colorx` | O | 1/180 | Roulette : **efface** tous les blox d’une couleur (score chaîne) |
| **SAINTX** | `.cleanx` | ∞ | 1/500 | Vide la grille ; laisse un Brix(N = cases enlevées) ; **+200** (× stage en Arcade) |
| **TWISTX** | `.twistx` | X | 1/324 | Échange auto : une couleur **présente** ↔ tous les Brix (valeur = min des Brix, défaut 3) |
| **BOMBX** | `.bombx` | B | 1/500 | Tâche 3 rangs sur cases **occupées** → chaînes → **+1 bombe** (garanti). Arcade / Zen seulement |

### Axes déjà utilisés

| Axe | Variantes |
|---|---|
| Peindre une zone | CHROMAX (chemin), CROSSX (croix +), BOMBX (tache) |
| Effacer | COLORX (une couleur), SAINTX (tout) |
| Brix | BRIXED (wipe), TWISTX (échange couleur↔Brix), SCRUMBLX (−1 global) |
| Ordre / lignes | SCRUMBLX (décalage **horizontal** par ligne) |
| Ressource | BOMBX (+1 bombe) |

---

## Pistes (non codées)

Recueillies en 6.4. Un seul nouveau Magix suffirait : la table a déjà 8 tirages. **Hors Duel / lignes du bas**, comme les autres.

À éviter (trop proches) : autre tache, autre wipe total, autre −1 Brix global, autre décalage horizontal aléatoire de lignes.

### PACKX — tout glisse vers ta colonne

Toutes les pièces occupées glissent **horizontalement** vers la colonne d’atterrissage (gravité **latérale** d’un coup), puis compactage haut.

- **Nouveau :** la gravité n’est aujourd’hui que vers le haut.
- **Joueur :** rassembler une couleur éclatée, coller un 4 à un 3.
- **Risque :** coller un Brix contre une chaîne, boucher le puits visé.

### FLIPX — on retourne les piles

Dans chaque colonne, **inverser l’ordre** des blocs occupés, puis compactage haut.

- **Nouveau :** SCRUMBLX mélange les **lignes** ; ici l’ordre **dans la pile**.
- **Joueur :** déterrer une couleur au plafond, ou envoyer du déchet vers les lignes (le bas).
- **Risque :** un Brix(1) inoffensif se retrouve au contact du vide.

### MERGEX — deux couleurs n’en font plus qu’une

Deux couleurs **présentes** : A est repeint en B. Pas d’effacement. Puis chaînes.

- **Nouveau :** COLORX **enlève** une couleur ; ici on **réduit la palette** sans trous.
- **Joueur :** deux 4-groupes → un 8, mega-cascade, beaucoup de −1 Brix.
- **Risque :** fusionner la mauvaise paire.

### CYCLEX — toute la palette tourne

Chaque blox passe à la couleur suivante du cycle (6 teintes). **Brix inchangés**. Puis chaînes.

- **Nouveau :** TWISTX n’échange qu’**une** couleur avec les Brix.
- **Joueur :** un 4 reste un 4, mais plus la couleur « en tête » vs la file.
- **Risque :** surtout mental ; peu de chaos structurel.

### VOIDX — un trou chirurgical

Vider la **ligne** ou la **colonne** d’atterrissage, puis compactage.

- **Nouveau :** CROSSX **peint** la croix ; ici une **coupe** qui fait de la place.
- **Joueur :** oxygène sans reset SAINTX.
- **Risque :** sacrifier la meilleure colonne.

### SLASHX — la croix qu’on n’a pas

Peindre les **diagonales** passant par l’atterrissage (8-connexité). CROSSX = **+**.

- **Nouveau :** géométrie encore unused.
- **Joueur :** relier des coins, chaînes diagonales.
- **Risque :** plus chaotique que CROSSX. Symbole **X** déjà TWISTX — glyphe à soigner.

### FORGEX — les Brix deviennent du jeu

Tous les Brix → blox de la couleur **la moins présente** (ou une couleur absente). Pas de wipe +20.

- **Nouveau :** BRIXED **détruit** ; TWISTX **échange** une couleur déjà là. Ici les Brix **rejoignent** le puzzle.
- **Joueur :** débloquer un plateau trop pierreux.
- **Risque :** inondation d’une couleur qui ne cascade pas — ou tout faire sauter.

### HALTX — une ligne de moins

Le compteur LIGNE **saute un tour** (prochaine injection annulée). Moins une transformée de grille qu’un **souffle**.

- **Nouveau :** aucun Magix ne touche au rythme des 10 coups.
- **Joueur :** survie lisible.
- **Risque :** trop « gratuit » seul — à coupler (ex. −1 Brix, ou ligne convertie en une couleur et injectée tout de suite).

### Pour en choisir un

| Si on veut… | Piste |
|---|---|
| Identité BLOMIX (gravité / piles) | **PACKX** ou **FLIPX** |
| Jouissance cascade | **MERGEX** ou **FORGEX** |
| Lisibilité / survie | **VOIDX** ou **HALTX** |
| Puzzle pur, peu spectaculaire | **CYCLEX** |

Les plus riches sans recouper l’existant : **PACKX** et **MERGEX**.

---

*Les pistes ne sont pas des règles. Avant implémentation : figer atterrissage, score, Brix, rareté, puis aligner RULES / PROJECT_CONTEXT / GLOSSARY / VFX / l10n.*

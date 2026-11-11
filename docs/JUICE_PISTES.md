# BLOMIX — Pistes juice / physique des objets

> **Version de référence** : 8.8  
> Recueil **2026-09**, complété **2026-11** (matière, cascade, ligne, mort, accueil, modaux, Clair, air — local 8.9). Pistes de **feel**, pas des règles.  
> Spec en jeu : [VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md).  
> Magix (blocs + pistes PACKX…) : [MAGIX.md](MAGIX.md).  
> Modes (4ᵉ mode, Défi Zen du jour…) : [MODE_PISTES.md](MODE_PISTES.md).

Ce fichier fige une **lecture critique** après le lot juice 7.4 local (`+N` shatter, paillettes → HUD, mort Brix, gerbe Magix). Rien ici n’est promis ni cadencé.

---

## La grammaire (ce qui est devenu vrai)

Trois objets, trois **matières** :

| | Corps | Mort / départ | Paillettes |
|---|---|---|---|
| **Blox** | carré, couleur skin | scale-up → poussière **ronde** | vol **vitesse constante** (~824 pt/s) vers le gros score |
| **Brix** | carré + chiffre | pop / torsion / implosion | **carrés**, même vol HUD |
| **Magix** | disque shader + orbite palette | ne reste jamais Magix | gerbe **palette** à l’impact, **pas** vers le score |

Loi du **score** : la matière qui vaut des points **va au chiffre** ; le HUD **roule du premier grain au dernier** ; compactage / pose **n’attendent pas**.

Deux physiques : **transfert** (points → HUD) et **présence** (atterrir, rebondir, être un Magix).

---

## Ce qui tient (ne pas défaire)

- **Pose** : vol commun ; stretch Brix plus sec ; Magix = blox + traîne blanche + gerbe palette. Le type se lit avant le contact. Magix, et l’appui long qui a montré la colonne ghost, ajoutent un tour pile sur la durée de cette montée (sens au hasard, droit à l’arrivée).
- **Chaîne** : dissolution 0,50 s, paillettes au pic, `+N` qui **est** les points. COMBO / CONNECT sont un commentaire plus tard (0,72 s, 40 pt), jamais vers le HUD.
- **Cascade** : vague 1 calme (stagger 0,04 s, grains 2,0–3,5). Vague 2 et 3+ serrent le stagger (0,028 puis 0,020) et grossissent les grains. Le shake (1,4 puis 2,0) part avec la dissolution. Pause 0,07 s et compactage 0,20 s inchangés.
- **Ligne** : dernier cran ±1 pt. La bande tremble plus fort et chaque case respire. Le plateau monte de 2 pt juste avant la poussée.
- **Mort** : pendant les anneaux, le reste de la grille s’assombrit ; la case qui bloque reste en couleur. Voile ordinaire et voile record inchangés.
- **Compactage** : 0,20 s, haut → bas, bounce cosmétique. Le monde respire sans voler la main.
- **Brix vivant** : le bloc ne bounce pas au −1 ; seul le **chiffre** pulse.
- **Constantes HUD** : ~824 pt/s, mix paillettes, shatter `+N`. Bounce Magix = blox. Compactage qui n’attend pas le score.
- **Voisinage** : 8 voisins. Même couleur de Blox attirée (2 pt à la pose, 1 pt au compactage), les autres repoussés. Jamais le sprite qui rebondit.
- **Haptique de matière** : pose, connect 2/3/4, Magix, refus sourd, chaîne en deux coups. Bombe / ligne / game over restent lourds.
- **Accueil** : le mot et le hero d’abord (tenue 0,85 s au cold launch). Disques, icônes et modes arrivent après, plus petits. Aucun mode retiré. Au retour, hero d’abord, disques déjà là.
- **Maisons** : Salon, scores, réglages, guide, crédits, sondage et hub Défi montent avec la gravité (0,25 s) et redescendent. Lobby et feuilles système inchangés.
- **Clair** : la grille est une planche (trou `#F0E6D2`, barre haute 2 pt, ombre de contact 0,11). Sombre reste une grille éclairée par les couleurs. Thème et skins restent séparés.
- **Air** : en partie, jusqu’à 4 grains très lents montent dans les trous, sous les blox. Pas une seconde pluie de score.
- **Toast** : le palier est une mini-cible (anneau, point, Nunito), pas un chip de réglages.
- **Réduire les animations** (réglage iPhone, pas un bouton du jeu) : voisin, jitter et respiration de la ligne, montée de 2 pt, shakes de cascade et de game over, glissés d’accueil, montée des modaux, grains, scale du toast et tour de vol se taisent. La pose, la chaîne, le score, les haptiques, le rouge du compteur, la bande et les anneaux restent. Le commentaire COMBO arrive en fondu, timings de vague 1.

---

## Fractures

### 1. « Mourir » ≠ toujours « aller au score »

| Mort | Paillettes → HUD ? | `+N` shatter ? |
|---|---|---|
| Chaîne blox | oui, ronds | oui |
| Brix → 0 | oui, carrés | oui |
| **COLORX** | **non** (scale → 0,01) | oui, le `+N` seul |
| **SAINTX** | oui (`spawnChainPopDots`) | +200 |
| **Bombe** | **non** (explosion blanche, blocs qui s’envolent) | +10 / +20 Brix |
| Magix peinture | **non** (pop de remplacement) | non (pas un score) |

COLORX est le trou le plus lisible : même événement qu’une chaîne (blox d’une couleur, formule chaîne), **pas la même mort**. Le `+N` arrive orphelin.

La bombe est un **autre verbe** (explosion ≠ dissolution) — légitime, mais les Brix du blast n’ont plus le pop carré + vol HUD.

### 2. Magix : trois destins, une seule arrivée

L’arrivée est unifiée (bounce + gerbe). **Après**, le disque :

- **devient blox** (CHROMAX, CROSSX, SLASHX, BOMBX) — pop de remplacement, le Magix **mue**
- **devient Brix** (BRIXED `drawGrid` sec ; SAINTX mue la peau en place — plus juste)
- **s’évapore** (COLORX roulette, SCRUMBLX fade, TWISTX…)

**TWISTX** : `.empty` tout de suite ; le disque peut rester pendant les flips ; `drawGrid` le vire. Pas de mort.

### 3. Brix : deux langages de particules

- Pose / compactage : paillettes **rondes** (recette blox), couleur Brix
- Mort : **carrés** vers le HUD

Défendable (vivant = impact, mort = fragments du cube). À l’œil, la pose n’annonce pas encore la mort.

### 4. COMBO vs `+N`

**Fait (local 8.9).** Le `+N` reste la monnaie (62 pt, grow 0,58 s, shatter vers le HUD). COMBO / CONNECT arrivent après, en 40 pt, et rétrécissent sur place. Le shake de cascade part avec les cases, pas avec le texte.

### 5. Magix peinture = spawn blox, pas contamination

CHROMAX / CROSSX / SLASHX / BOMBX / TWISTX : `remove` + sprite 0,5→1,35. Ça lit **apparition**. La gerbe d’arrivée dit « énergie palette » ; la peinture dit « téléport blox ».

### 6. Jonctions

**Fait (8.1)** : dissolution de chaîne — la barre fond avec le premier blox du couple. Magix / bombe / compactage restent en retrait immédiat (autre verbe). Compactage en vol : toujours sans barres (hors 8.1).

### 7. Deux easings HUD

Fenêtre paillettes Brix : **linéaire**. Chaîne : ease-out si pas de fenêtre forcée. Deux lois pour le même transfert.

### 8. Preview Magix vs pose

Orbite (vie, enfant du sprite) + traîne blanche (vol) + gerbe (impact). Trois auras, lisibles si on assume ce découpage.

---

## Pistes juice (pas cadencées)

Ordre de **cohérence de lecture**, pas un backlog.

| Id | Piste | Pourquoi | Effort |
|---|---|---|---|
| **A** | COLORX : au pic du scale, `spawnChainPopDots` comme une chaîne / SAINTX | Le `+N` n’est plus orphelin | **Fait** (local 7.4) |
| **A′** | Bombe : paillettes HUD au pic ×1,25 (ronds blox / carrés Brix) + `+N` Brix / +10 au même t ; anim explosion inchangée | Même verbe « matière → score » | **Fait** (local 7.4) |
| **B** | Magix **consommé** (TWISTX, SCRUMBLX, COLORX-disque) : une fin (fade + mini-burst palette, inverse de l’arrivée) | Plus de fantôme d’une frame | **Fait** (local 7.4) |
| **C** | Magix qui **mue** (1ʳᵉ case CHROMAX / anneau 0 CROSSX / rang 0 BOMBX / BRIXED) : le disque se **ferme dans** le nouveau corps (modèle SAINTX) | Peinture = contamination, pas teleport | **Fait** (local 7.4) |
| **D** | Pose Brix : poudre un peu anguleuse, ou 6–8 micro-carrés | Signature, pas une 2ᵉ gerbe de mort | **Fait** (8.1 : 6–8 micro-carrés à l’éjection, pose + compactage) |
| **E** | COMBO plus petit / plus tard ; toujours pas de vol HUD | Moins de bagarre avec le `+N` | **Fait** (local 8.9) |
| **F** | Jonctions : fondre avec la case, pas disparaître avant | Le groupe visé a une mort | **Fait** (8.1 : chaîne / cascade ; immédiat ailleurs) |
| **G** | Une courbe HUD « matière → chiffre » (linéaire ou ease-in léger) dès qu’il y a pluie | Une seule loi | Petit |

**Hors grammaire** (spectacle) : haptique à l’arrivée Magix **fait** (même instant que la gerbe, transient medium — pas un second coup sur la gerbe) ; nom Magix plus proche du `+N` ; traîne Magix teintée 1 frame / 3 en palette.

**Ne pas toucher** : 824 pt/s, mix paillettes, shatter `+N`, bounce Magix = blox, compactage indépendant du HUD, Brix bloc inerte / chiffre vivant.

Plus rentable **lecture** : **A** + **B**. Plus rentable **poésie** : **C**.  
**A / A′ / B / C / D / E / F** faits ; **G** reste ouvert.

---

## Lien avec les autres recueils

Les pistes Magix **blocs** ([MAGIX.md](MAGIX.md) : PACKX, FLIPX, MERGEX, HALTX, VOIDX, CYCLEX, FORGEX) et les pistes **modes** ([MODE_PISTES.md](MODE_PISTES.md)) restent ailleurs.

Si on en code un : **appliquer cette grammaire dès le premier atterrissage** (naissance / vie / mort dans la matière du type ; points → HUD). Un nouveau Magix ou un 4ᵉ mode qui « téléporte » encore des sprites sans fin de disque recréerait la fracture 2.

---

*Pas des règles. Avant d’implémenter une ligne du tableau : figer le verbe (mue / consommation / mort-score), caler le HUD s’il y a des points, aligner [VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md).*

# BLOMIX — Pièce des trophées (piste)

> **Statut** : 1ʳᵉ version testable (store + Salon + cible + hooks). Rangs encore I / II / III. À figer après tests Five + boards GC live.  
> **Version de référence** : 8.6  
> Vocabulaire : [GLOSSARY.md](GLOSSARY.md). Modes : [RULES.md](RULES.md). Magix : [MAGIX.md](MAGIX.md).  
> Nom d’écran : **Salon des trophées** (caption accueil : **Salon**).  
> Noms des **rangs** 1 / 10 / 100 : **à décider** (§2). *Blox / Brix / Magix* comme grades = **écarté** (signe contradictoire avec le plateau).

Un **cabinet personnel** : pastilles-cibles sur un mur. Grises tant que jamais faites ; allumées dès la 1ʳᵉ fois, avec un **rang qui monte** (trois grades, noms ouverts). Le chiffre au centre **est le compte** (0 au départ, et ça continue après 100). Deux **tours** se remplissent l’un après l’autre ; tout plein → paillettes Magix. Pas un classement, pas un 4ᵉ mode, pas des Achievements Game Center (v1).

But : donner une raison de **toucher à tout** le jeu, puis d’y **revenir** — la pièce se relit, elle ne se coche pas.

Dans le reste du doc, les grades s’appellent **I / II / III** (mécanique 1 → 10 → 100). Les mots joueur sont au §2.

---

## 1. Ce que le joueur voit

### Entrée

Rangée d’icônes accueil (aujourd’hui 5) : **6ᵉ** icône, SF Symbol `trophy.fill`, même chrome.

| | Reco |
|---|---|
| Place | Entre **Partager** et **Crédits** |
| Caption | court (ex. **Pièce**) — titre d’écran = nom choisi |
| Badge | point si rang monté / pastille nouvelle non ouverte |

Si 6 icônes serrent le 40 mm : `iconStep` 56 → ~50, pas une 2ᵉ rangée.

### L’écran (modal UIKit, famille Crédits / Score)

Fond scène + blox ambiants. Titre gouttière. Fermer en haut.

1. **Bandeau** : pastilles allumées `28 / 41` · rangs `I 12 · II 11 · III 5` (libellés = noms figés au §2) · dernière montée (nom + palier).
2. **Murs** par catégorie (titres cutout).
3. **Grille** 4 cibles / rangée (~52 pt). Même objet partout ; légendes 1/10/100 **fiche seulement** (§6).

Pas de SpriteKit ici : lecture, pas pose.

### Une pastille : compteur + deux tours

Pas bronze / argent / or Apple. **Une cible.** Noms de grades ouverts (§2). Dessin : §6.

Le **numéro au centre** = le nombre de fois (ou le meilleur, courbe Qualité). Il vaut **0** au départ et **continue** après le plafond (347 CHROMAX, etc.). Ce n’est pas un niveau 1/2/3.

**Deux tours** (courbe Volume 1 / 10 / 100 — CHROMAX, *Super combo*, etc.) :

1. **n = 0** — anneaux vides, centre **0**, pas d’arc.
2. **n ≥ 1** — le disque intérieur (peau) s’allume. Le **premier tour** (anneau **10**) commence à se remplir : remplissage = **n / 10**.
3. **n ≥ 10** — premier tour plein. Le **deuxième tour** (anneau **100**) commence à compter : remplissage = **n / 100** (à 10 l’arc extérieur est déjà à 10 %).
4. **n ≥ 100** — les deux tours sont pleins. Plus rien à remplir. Des **particules type Magix** sortent du **disque intérieur et du disque extérieur**, comme d’un bloc Magix. Le compteur au centre continue.

Le 2ᵉ tour ne part pas de zéro : c’est le même compte, lu sur l’anneau suivant. Tant que n < 10, l’anneau 100 reste vide.

Exemple — *Super combo* (cascade ≥ 2 vagues), courbe Volume :

| Compte | Rang | Centre | Tours |
|---|---|---|---|
| 0 | — | **0** | Rien. Anneaux vides |
| 1 | **I** | **1** | Disque intérieur allumé. 1er tour : 1/10 |
| 7 | I | **7** | 1er tour : 7/10. Anneau 100 vide |
| 10 | **II** | **10** | 1er tour plein. 2ᵉ tour : 10/100 |
| 47 | II | **47** | 2ᵉ tour : 47/100 |
| 100 | **III** | **100** | Tout plein. Paillettes Magix **depuis** les deux disques. Compteur continue (347…) |

Même lecture sur les autres courbes : le 1er tour va de s1 à s2, le 2ᵉ de s2 à s3 (Rare 1 / 3 / 10, Qualité 5 / 8 / 10+, etc.). Unique : pas de tours, 0 ou 1.
NBLOMIG / ok avec toute la logique, simplement ce n'est pas 0/1/10/100, mais 0/Nombre1/Nombre2/Nombre3 (on préciser pour chaque trophées à quoi correspondent les nombre1, nombre2, nombre3 ainsi que les labels / noms pour I, II, et III. 
NBLOMIG / ça serait bien, après avoir rempli le trophée qu'il 1° continue à compter - c'est déjà le cas - et qu'il affiche dessous 3 petites étoiles (vides au début, et remplies gouttières après l'atteinte du III pour la première étoile, puis si le joueur refait le nombre d'évèneemnts/ achevement correspondant au III la deuxiième étoile s'allume, puis pour un nombre encore équivalent la 3ème étoile. 

Verrouillée **cachée** : caption **???**, tap = « Réalisation secrète », anneaux sans fill, **pas** de 0 au centre.

Nouveau palier : souffle 2 cycles (disques accueil), puis calme.

### Fiche (tap)

Panneau bas, chrome capsule :

- Titre Changa + **même cible**, plus grande, anneaux **légendés** 1 / 10 / 100 (ou 1 / 3 / 10, etc.)
- Phrase joueur (ce que c’est)
- **×N** (le centre le dit déjà ; optionnel en gouttière)
- Pas de barre sous le nom : l’arc **est** la jauge
- Première fois · premier II · premier III (dates courtes)
- Fermer : hors panneau

Grise connue (n = 0) : condition lisible, anneaux + légendes, fill vide, centre **0**.
NBLOMIG / très bien pour commencer simplemnt les chiffres 1/10/100 ne s'affichent pas en entier ou pas bien. Ce n'est pas très clair le nombre d'évènementn que l'on doit faire, or dans la fiche, ça doit être limpide.
---

## 2. Langage des rangs (à figer)

Les seuils **1 → 10 → 100** restent (deux tours, §1). Ce qui est ouvert : **comment on les *appelle***, pour que ça dise « trophée » sans piquer le vocabulaire du plateau. Le dessin (cible, tours, paillettes) est au §6.

### Pourquoi pas Blox / Brix / Magix

Sur le plateau :

| Mot | Signe |
|---|---|
| **Blox** | Neutre — la matière du jeu |
| **Brix** | **Négatif** — obstacle, compteur, ça gêne |
| **Magix** | **Très positif** — rare, cadeau, disque |

S’en servir comme grades d’un *même* trophée inverse le Brix (le 10ᵉ super combo deviendrait « plus dur / plus moche ») et use Magix (le 100ᵉ combo n’est pas un bloc Magix). Confusion garantie à la lecture de la pièce : « j’ai un Brix sur Combo » vs un Brix(5) dans la grille.

On peut encore **emprunter des formes** (carré, relief, disque) si les **noms** sont autre chose.

Contraintes pour un bon langage :

1. Trois mots **ordonnés** (on entend que III > II > I).
2. Une **touche trophée** — au moins le grade III doit sonner « vitrine / médaille / honneur », pas « encore un blox ».
3. **Cohérent chrome BLOMIX** : poinçon, gouttière, relief, peau, orbite, CONNECT — pas bronze Apple, pas étoile RPG.
4. Aucun mot déjà chargé **contre** le joueur (Brix, nuke, ligne, game over).
5. Courts : ils tiennent sous une pastille et dans un bandeau.

---

### Piste A — *Poinçon / Relief / Couronne*  ★ reco craft

| I (1) | II (10) | III (100) |
|---|---|---|
| **Poinçon** | **Relief** | **Couronne** |

BLOMIX *frappe* déjà : intro du wordmark (poinçon L→R), boutons en **relief** / puits, Magix et bombe en **disque à couronne** — mais ici la couronne est celle d’une **médaille**, pas d’un Magix.

- **Poinçon** = première marque, tu es inscrit dans le métal.
- **Relief** = le chrome du jeu (on *touche* le trophée comme un bouton).
- **Couronne** = l’objet « médaille de vitrine ». Sparkle à la fiche.

Touche trophée : on **frappe** une médaille. Très atelier BLOMIX.  
Risque : « poinçon » un peu technique ; « couronne » reste cousin du Magix — à tenir par le **nom** + un anneau plus *médaille* (plein, pas halo Magix).

Formes : I = plaque percée d’un point ; II = capsule relief ; III = disque + anneau plein.

---

### Piste B — *Inscrit / Médaille / Trophée*  ★ reco lisible

| I | II | III |
|---|---|---|
| **Inscrit** | **Médaille** | **Trophée** |

Le mot **Trophée** n’apparaît qu’au plafond. I = tu es dans le cabinet. II = ça se porte. III = *ça*, c’est un trophée.

Touche trophée : maximale, honnête.  
Cohérence : les **pastilles** du mur restent le contenant (comme les disques de rang accueil) ; le grade est ce qu’elles *deviennent*.  
Risque : collision **Trophée** (grade) vs **Pièce des trophées** (salle) — tenable si le titre d’écran est *Cabinet* / *Pièce*. Interdit la coupe 3D : III = médaille à couronne cutout, pas une coupe.

Formes : I = pastille peau (disque accueil) ; II = plus de relief, liseré ; III = couronne + cutout.

---

### Piste C — *Plaque / Gouttière / Orbite*

| I | II | III |
|---|---|---|
| **Plaque** | **Gouttière** | **Orbite** |

Le plus **chrome** : plaque de métal → le trou BLOMIX → les grains d’orbite (sillage Magix/bombe, déjà « précieux »).

Touche trophée : l’orbite *est* le glitter de récompense, sans dire Magix.  
Risque : gouttière est un mot d’atelier (joueurs Crédits/doc) ; orbite = juice Magix. Un peu abstrait pour un enfant / un premier run.

---

### Piste D — *Liaison / Chaîne / CONNECT*

| I | II | III |
|---|---|---|
| **Liaison** | **Chaîne** | **CONNECT** |

Le jeu qui parle. I = deux cases se touchent. II = une vraie chaîne (≥ 5). III = le mot **CONNECT** (trait chrome bord à bord sur la pastille).

Touche trophée : CONNECT est déjà le moment *noble* du plateau. En faire le grade ultime est très BLOMIX.  
Risque **fort** : collision avec le trophée *CONNECT* (pont réel). « Chaîne » est le verbe de scoring. À réserver si on assume que le mur *cite* le jeu — ou garder CONNECT **seulement en dessin** (trait) et prendre les noms de A ou B.

---

### Piste E — *Éclat / Halo / Couronne*

| I | II | III |
|---|---|---|
| **Éclat** | **Halo** | **Couronne** |

Lumière de vitrine. Doux, « récompense ». Halo existe déjà sur les Magix.  
Risque : encore le voisinage Magix ; moins de matière chrome (moins « frappé » que A).

---

### Piste F — *Cachet / Sceau / Couronne*

| I | II | III |
|---|---|---|
| **Cachet** | **Sceau** | **Couronne** |

Cabinet, officiel, un peu héraldique. Le meuble *estampille*.  
Risque : trop « institution » pour BLOMIX (qui est puits + peau, pas blason).

---

### Ce qu’on peut mixer

Le **nom** et le **dessin** se séparent :

- Noms **B** (*Inscrit / Médaille / Trophée*) + formes **A** (poinçon → relief → couronne).
- Ou noms **A** + trait **CONNECT** (chrome) seulement au rang III.

Reco **mots** : piste B (*Inscrit / Médaille / Trophée*) ou A (*Poinçon / Relief / Couronne*). Écarter Blox/Brix/Magix. Piste D en joker si tu veux que le plateau *parle*.

**Formes A (plaque / relief / couronne) : remplacées** par la cible à anneaux (§6). Les noms de grades restent à figer ; le dessin, non.

---

## 3. Paliers (le système)

Chaque pastille a **un événement** (ce qu’on compte ou le meilleur) et **deux seuils** après le premier.

### Courbes

| Courbe | I | II | III | Pour |
|---|---|---|---|---|
| **Volume** | 1 | **10** | **100** | Combos, chaînes, parties, Magix (kinds) courants, bombes, partages |
| **Rare** | 1 | **3** | **10** | SAINTX, BOT1, CONNECT, grille vide, rang 1 du jour, secrets |
| **Qualité** | palier 1 | palier 2 | palier 3 | *Meilleur* : taille de chaîne 5 / 8 / 10+ ; stage 2 / 4 / Ultime ; score 1k / 5k / 10k |
| **Unique** | 1 | — | — | Tuto fini, thème Clair : allumé = fait. Un anneau (ou cible plate). Rang I suffit |

Défaut = **Volume 1 / 10 / 100**, comme *Super combo*.  
Pas de 4ᵉ métal. L’échelle II→III **est** la longue (100). Si un trophée est trop grind (victoire BOT1 ×100), courbe **Rare 1 / 3 / 10**.

Les paliers **empilent** : le 100ᵉ combo a déjà donné I et II.

### Deux lectures, une pastille

- **Compte** (la plupart) : chaque événement +1. Centre = total. Tours = n / palier actif (§1).
- **Qualité** (peu) : on mémorise le *max* (plus grande chaîne, plus haut stage, meilleur score). Centre = ce max (8, pas « ×8 chaînes de 8 »). Même deux tours, sur les seuils de max.

Anneaux **relégendés** selon la courbe (Volume 1/10/100, Rare 1/3/10, Qualité 5/8/10+). Légendes **fiche seulement**. **À tester** avec la pureté du mur (§6).

On ne dédouble plus « chaîne 5 », « chaîne 8 », « chaîne 10 » en trois pastilles : **une** pastille *Chaîne*, rang I dès 5, II à 8, III à 10+. Le **volume** de chaînes est une **autre** pastille (*Cent / mille*).

### Règles catalogue

1. Une pastille = une idée qui **vieillit** (sauf Unique).
2. Chaque mode : une porte (l’avoir joué, volume) + au moins une fierté.
3. Les 9 Magix : une pastille chacun, courbe Volume (COLORX/CHROMAX) ou Rare (SAINTX/BOMBX 1/500).
4. Peu de secrets (9). Lisibles une fois ouverts, **même courbe** (Pacifiste 1 / 3 / 10 GO à 5 bombes).
5. Pas de trophée qui force la triche (forfait Duel, score exact).
6. Pas d’Achievements ASC v1. Local, cet iPhone.
7. Pas CloudKit, pas Watch.
8. Peu de rétroactif : hiscores, podium déjà crédité, tuto vu. Le reste au prochain événement.

---

## 4. Catégories (murs)

| Mur | Glyphe | Rôle |
|---|---|---|
| **Seuil** | Porte | Chaque mode, en volume |
| **Chaînes** | 5 | Cœur puzzle + combo + CONNECT |
| **Magix** | Disque | Les 9 + collection |
| **Arcade** | Timer | Stage, nuke, score |
| **Five** | 5 | Sans le diluer dans Zen |
| **Défi** | Jour | Deux graines, podium, ghost |
| **Duel** | ⚔️ | Humain, local, bots |
| **Folie** | Bombe | Style, partage, secrets |

Hors v1 : toutes les skins, avis App Store, Watch.

---

## 5. Catalogue v1

IDs = clés de save. Titres = étiquettes design FR (nom d’écran à part).  
**C** = courbe (V volume, R rare, Q qualité, U unique).

~**41** pastilles visibles + **9** secrets = **50** sur le mur (moins qu’avant : la profondeur est dans les rangs, pas dans 73 cases).

### Seuil (8)

| ID | Titre | Événement | C |
|---|---|---|---|
| `play_arcade` | Arcade | GO Arcade | V |
| `play_zen` | Zen | GO Zen | V |
| `play_five` | Five | GO Five **libre** | V |
| `play_daily_arc` | Défi Arcade | GO classé Défi Arcade | V |
| `play_daily_five` | Défi Five | GO classé Défi Five | V |
| `play_duel` | Duel | Match terminé (G ou P, tous adversaires) | V |
| `play_tutorial` | Tu sais tout | Tuto **au bout** (pas Passer) | U |
| `play_both_dailies` | Double journée | Les deux Défis le même jour UTC | R |

### Chaînes (6)

| ID | Titre | Événement | C |
|---|---|---|---|
| `chain_size` | Chaîne | Plus grande chaîne (5 → 8 → 10+) | Q |
| `chain_count` | Encore | Nombre de chaînes ≥ 5 | V (III à **1000**, II à 100 — exception : trop fréquent en 1/10/100) |
| `combo` | Super combo | Résolution à **≥ 2** vagues | **V 1 / 10 / 100** — *l’exemple* |
| `combo_deep` | Série | Une résolution à **≥ 5** vagues | R |
| `connect` | CONNECT | Pont gauche–droite | R |
| `board_empty` | Vide | Bonus +500 grille vide | R |

`board_empty` hors Duel. CONNECT et chaînes **comptent** en Duel.  
`chain_count` : I = 1, II = **100**, III = **1000** (pas 10/100, trop vite).

### Magix (11)

Effet vu à l’atterrissage. Pas en Duel.

| ID | Titre | C |
|---|---|---|
| `magix_chromax` | CHROMAX | V |
| `magix_brixed` | BRIXED | R |
| `magix_crossx` | CROSSX | V |
| `magix_slashx` | SLASHX | V |
| `magix_scrumblx` | SCRUMBLX | V |
| `magix_colorx` | COLORX | V |
| `magix_saintx` | SAINTX | R |
| `magix_twistx` | TWISTX | V |
| `magix_bombx` | BOMBX | R |
| `magix_all_nine` | Cabinet Magix | U — les 9 au moins ×1. Barre 0–9 kinds distincts (qualité déguisée) |
| `magix_saintx_ultime` | Infini ×6 | R — SAINTX en Ultime |

Glyphe Magix : **pas** sur le fill (la peau est unique). Option fiche : symbole en plus du nom. Rang III = paillettes **issues des deux disques** (comme un bloc Magix), pas une couronne Magix collée sur le fill.

### Arcade (5)

| ID | Titre | Événement | C |
|---|---|---|---|
| `arcade_stage` | Stage | Plus haut stage (2 → 4 → Ultime) | Q |
| `arcade_nuke` | Nuke | Bombe posée stage ≥ 2 | V |
| `arcade_score` | Score | Meilleur score de run (1k → 5k → 10k) | Q |
| `arcade_pb` | Record | Fois où l’overlay RECORD Arcade s’est ouvert | R |
| `arcade_ultime_count` | Une seconde | GO (ou run) ayant **atteint** Ultime | R |

### Five (5)

Libre ou Défi Five, sauf `play_five`.

| ID | Titre | Événement | C |
|---|---|---|---|
| `five_lines` | Marée | Lignes Five injectées **dans une run** (max run : 5 → 20 → 50) | Q |
| `five_score` | Score Five | Meilleur score (500 → 2k → 5k) | Q |
| `five_pb` | Record Five | Overlay RECORD `FiveMode` | R |
| `five_no_bomb` | Mains nues | GO **sans une seule explosion** | R |
| `five_empty` | Five vide | Grille vide en Five | R |

### Défi (5)

| ID | Titre | Événement | C |
|---|---|---|---|
| `daily_ghost_beat` | Référence | Score > Référence BLOMIX | R |
| `daily_rank_1` | Jour 1 | Rang live 1 au GO (n’importe quel défi) | R |
| `daily_podium` | Podium | +5 / +3 / +1 crédité | V — II = 10 podiums, III = 50 |
| `daily_streak` | Semaine | Meilleure série de jours UTC avec ≥ 1 défi fini (3 → 7 → 30) | Q |
| `daily_days` | Habitude | Jours distincts avec ≥ 1 défi classé | V |

Plus de pastilles séparées « 10 Arcade / 10 Five » : c’est `play_daily_*` en Volume.

### Duel (7)

| ID | Titre | Événement | C |
|---|---|---|---|
| `duel_win` | Victoire | Gagner (tous adversaires) | V |
| `duel_win_human` | Face à face | Victoire vs humain (GK ou Local) | R |
| `duel_win_local` | Table | Victoire Local | R |
| `duel_babybot` | BABYBOT | Victoire vs BABYBOT | V |
| `duel_bot1` | BOT1 | Victoire vs BOT1 | R |
| `duel_no_attack` | Pacifique | Victoire score de run < 50 | R |
| `duel_streak` | Série | Meilleure série de victoires (3 → 5 → 10) | Q |

`play_duel` compte les matchs ; `duel_win` les victoires. Pas de 4ᵉ pastille « 10 duels ».

### Folie (7 visibles + 9 secrets)

**Visibles**

| ID | Titre | Événement | C |
|---|---|---|---|
| `share_home` | Avion | Share sheet accueil | V |
| `share_go` | Carte | Share sheet GO | V |
| `theme_light` | Clair | Chrome Clair au moins une fois | U |
| `bomb` | Bombe | Explosions | V |
| `continue_save` | Continuer | Reprises save | V |
| `worst_move` | Pire coup | Ouverture overlay pire coup | V |
| `justesse` | Justesse | Meilleur % GO (≥ 20 coups) : 80 → 90 → 100 | Q |

**Secrets** (??? jusqu’au 1er, puis **Rare 1 / 3 / 10**)

| ID | Titre ouvert | Événement |
|---|---|---|
| `secret_five_bombs` | Pacifiste | GO **avec 5 bombes en stock** (Arcade / Zen / Five) |
| `secret_zero_bombs` | Poudrière | GO à **0** bombe, ≥ 1 explosion dans la run |
| `secret_timeout` | Trop tard | Auto-drop Arcade **sans visée** |
| `secret_bomb_cancel` | Fausse alerte | Armer puis annuler la bombe |
| `secret_duel_bomb_freeze` | Temps mort | Duel : mode bombe ≥ 8 s puis poser |
| `secret_line_go` | Trop plein | GO **par la ligne**, pas par pose |
| `secret_saintx_tiny` | Presque rien | SAINTX sur ≤ 8 cases occupées |
| `secret_brixed_zero` | 9 solitaire | BRIXED sans autre Brix |
| `secret_share_pb` | Vitrine | Share GO **avec** bandeau record |

**50** pastilles. Un rang III sur *Super combo* = 100 cascades ; un rang III sur *Pacifiste* = 10 GO à 5 bombes.

---

## 6. Graphisme

Inspiration : `image_inspi/trophees-chromax-piste-graphique.jpg` (trois plans CHROMAX : anneaux, disque peau, arc, chiffre au centre). **La logique** est §1 (compteur + deux tours) — le mock 02 met l’arc sur le 100 trop tôt (compte 3 = 1er tour, anneau 10). **Décisions Lomig** ci-dessous. Pas de coupes 3D. Pas de plaque / relief / couronne (§2 piste A, dessin écarté).

**Une cible** = trois anneaux concentriques (1 · 10 · 100 ou la courbe) + disque intérieur peau + arc du tour actif + chiffre. Le rang se *lit* à l’occupation, pas à un changement d’espèce.

### Couleur

- Disque : **dégradé aux couleurs de la peau** du joueur, même recette que les **gouttières** (puits / jauge 0→N°1).
- Rien de spécifique **par mur** ni **par Magix**. CHROMAX orange-vert-bleu sur la planche = démo ; en jeu c’est la peau, y compris sur la pastille CHROMAX.
- Arc : **mouvant**, comme les gouttières (shader / dégradé qui glisse), pas un bleu plat.

### Mur vs fiche

| | Mur (pureté) | Fiche (tap) |
|---|---|---|
| Cible | Anneaux + disque + arc + chiffre | **Même objet**, plus grand |
| Légendes **1 / 10 / 100** (ou 1 / 3 / 10, etc.) | **Non** | **Oui** |
| Caption | Nunito sous la cible (un mot, Magix non traduits) | Titre Changa + phrase |
| Paillettes rang III | Issues du disque **intérieur** et du disque **extérieur** | Idem, plus lisibles |

### Occupations (Volume 1 / 10 / 100)

Le remplissage d’un tour = **n / palier**, pas une jauge 0→100 renormalisée sur le segment.

| n | Rang | Disque | Tours / arc | Paillettes |
|---|---|---|---|---|
| **0** | — | Vide. Anneaux gardés. Centre **0** | Aucun | — |
| **1 … 9** | **I** | Intérieur peau allumé (anneau 1) | **1er tour** : arc sur l’anneau **10**, n/10. Anneau 100 vide | — |
| **10 … 99** | **II** | Jusqu’à l’anneau 10 | 1er tour **plein**. **2ᵉ tour** : arc sur l’anneau **100**, n/100 | — |
| **100+** | **III** | Plein (intérieur **et** extérieur) | Les deux tours pleins. Plus d’arc à avancer | **Comme un bloc Magix** : particules (`spawnSpecialOrbitLingerSparks` ou équivalent) **sortent** du disque intérieur **et** du disque extérieur. Compteur continue |

Relégende : remplacer 10 / 100 par s2 / s3 (Rare 1/3/10, Qualité 5/8/10+, podium 1/10/50, `chain_count` 1/100/1000). Unique : un allumage, pas de tours.

### Relégende (courbes) — **à tester**

Les trois anneaux portent les **seuils de la courbe**, pas toujours 1/10/100 :

| Courbe | Anneaux (fiche) |
|---|---|
| Volume | 1 · 10 · 100 |
| Rare | 1 · 3 · 10 |
| Qualité | palier 1 · 2 · 3 (ex. 5 · 8 · 10+) |
| Unique | un anneau, ou cible plate allumée |

**À tester avec la pureté du mur** : sans légendes, une cible Rare (1/3/10) et une Volume (1/10/100) se ressemblent. Si c’est illisible, options à challenger : léger écart d’épaisseur d’anneaux, ou légendes mur au tap-hold — **pas** de teinte par mur.

### Chrome

- Fond scène + blox ambiants plus lents. Cible sur chrome Sombre / Clair.
- Anneaux : `tertiaryText` (état 0) → plus marqués une fois allumés.
- Chiffre central : compteur (ou max qualité), contraste sur le dégradé.
- Bandeau salle : cutout, pas d’XP de RPG.
- Portrait, 4 colonnes.

### Secrets

Même cible. Caption **???** tant que 0. Après le 1er : nom + fill peau, comme les autres.

---

## 7. Technique (plus tard, pas maintenant)

Un hook par famille d’événements. Le store ne connaît que `id → count | best`, le **rang se calcule** (seuils dans le catalogue).

```
rang = III si valeur ≥ s3
     else II si valeur ≥ s2
     else I si valeur ≥ 1 (ou ≥ s1 qualité)
     else gris
```

Store JSON `blomix_trophies_v1` : `{ id: { value, firstAt, iiAt, iiiAt, seen } }`. Monotone. Pas de reset joueur. (`iiAt` / `iiiAt` = dates des paliers ; pas Brix/Magix.)

Toast **au retour accueil** si palier monté pendant la run (pas de popup en partie). Tap → pièce, focus la pastille.

---

## 8. Ce qu’on ne fait pas

- Battle pass, XP global, quêtes du jour (déjà les Défis).
- 4ᵉ métal (platine). Deux tours, stop.
- Légendes 1/10/100 **sur le mur** (fiche seulement).
- Teinte par mur ou par Magix (la peau suffit).
- Popup Magix **en cours de pose**.
- Arc du 2ᵉ tour **avant** n ≥ s2 (le mock 02 à 3 sur l’anneau 100 est faux).
- Révéler les secrets dans le guide.
- Forcer un Duel humain pour « finir » (BOT1 = plafond solo).
- Tuto « Passer » ≠ `play_tutorial`.

---

## 9. Décisions à figer

1. **Nom de la salle** : **Salon des trophées** (figé pour la 1ʳᵉ version). Caption icône : **Salon**.
2. **Noms des rangs** (§2) : A Poinçon/Relief/Couronne · B Inscrit/Médaille/Trophée · D CONNECT · autre. *(Le dessin n’est plus A : c’est la cible §6.)*
3. **6ᵉ icône** accueil vs Crédits.
4. Courbe Volume **1 / 10 / 100** vs **1 / 10 / 50**.
5. `chain_count` à 100 / 1000 : OK comme exception ?
6. Toast accueil vs badge icône seulement.
7. 9 secrets, assez ?
8. Rétroactif minimal (hiscores, podium, tuto) : OK ?

**Dessin (figé, sauf tests)** : cible peau ; centre = compte (0 au départ, continue) ; 1er tour dès n ≥ 1, 2ᵉ tour dès n ≥ s2 ; paillettes Magix **depuis les deux disques** au rang III, comme un bloc Magix. Légendes fiche seulement. **À tester** : relégende Rare/Qualité sans légendes mur (une cible 1/3/10 vs 1/10/100 se ressemble).

---

## 10. Ordre de code (plus tard)

1. Store + rang calculé + écran mur / fiche / **cible** — une pastille témoin (*Super combo* ou CHROMAX).
2. Seuil (modes).
3. Chaînes + Magix.
4. Arcade / Five / Défi / Duel.
5. Folie + secrets.
6. l10n 6 langues, guide, GLOSSARY, CHANGELOG, whats-new au jalon.

**1ʳᵉ version (test)** : store local + cible + Salon modal + 6ᵉ icône + hooks principaux. DEBUG : appui long sur une pastille = +1. Pas de bump marketing. Rangs encore I / II / III.

Rien de plus « produit » avant : Five testé, boards GC live, **cette** spec validée (surtout §2 mots des rangs).

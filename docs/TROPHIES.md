# BLOMIX — Pièce des trophées (piste)

> **Statut** : conception. **Pas de code.** À figer après tests Five + boards GC live.  
> **Version de référence** : 8.6  
> Vocabulaire : [GLOSSARY.md](GLOSSARY.md). Modes : [RULES.md](RULES.md). Magix : [MAGIX.md](MAGIX.md).  
> Nom d’écran : **à décider** (*Pièce des trophées* / *Cabinet* / *Réalisations*).  
> Noms des **rangs** 1 / 10 / 100 : **à décider** (§2). *Blox / Brix / Magix* comme grades = **écarté** (signe contradictoire avec le plateau).

Un **cabinet personnel** : pastilles sur un mur. Grisées tant que jamais faites ; allumées dès la 1ʳᵉ fois, avec un **rang qui monte** (trois grades, noms ouverts) et une **barre gouttière** sous le nom. Pas un classement, pas un 4ᵉ mode, pas des Achievements Game Center (v1).

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
3. **Grille** 4 pastilles / rangée (famille disques de rang, ~52 pt).

Pas de SpriteKit ici : lecture, pas pose.

### Une pastille, trois vies

Pas bronze / argent / or Apple. **Une pastille, trois peaux** — le dessin dit le grade, **sans** reprendre les noms du plateau (voir §2).

Exemple — *Super combo* (cascade ≥ 2 vagues) :

| Compte | Rang | Pastille (forme, à figer avec le nom) | Barre sous le nom |
|---|---|---|---|
| 0 | — | Grise, glyphe silhouette | Vide, ou absente |
| 1 | **I** | Forme 1, chiffre **1** | Gouttière peau **1 / 10** |
| 7 | I | **7** | **7 / 10** |
| 10 | **II** | Forme 2, **10** | Nouvelle échelle **10 / 100** (remplie à 10 %) |
| 47 | II | **47** | **47 / 100** |
| 100 | **III** | Forme 3, **100** | Pleine. Le compteur continue (347…) ; plus de palier |

Le **1** apparaît au premier déblocage. Ensuite le chiffre **est le compteur**, pas un niveau 1/2/3.

**Barre** = même recette que la jauge 0→N°1 (gouttière, fill peau, 3 pt). Sous le **nom** (caption mur + titre de fiche), pas autour du disque.

- Rang I : dénominateur = seuil **II** (souvent 10).
- Rang II : dénominateur = seuil **III** (souvent 100) — nouvelle barre, on « repart » visuellement.
- Rang III : barre pleine, sparkle **seulement à l’ouverture de la fiche** (pas 41 orbites sur le mur).

Verrouillée **cachée** : caption **???**, tap = « Réalisation secrète », pas de barre.

Nouveau palier : souffle 2 cycles (disques accueil), puis calme.

### Fiche (tap)

Panneau bas, chrome capsule :

- Titre Changa + pastille (forme du rang actuel)
- Phrase joueur (ce que c’est)
- **×N** en gouttière
- Barre **n / prochain** (ou pleine si III) + libellé *vers II* / *vers III* (noms joueur du §2)
- Première fois · premier II · premier III (dates courtes)
- Fermer : hors panneau

Grise connue : condition lisible, 0 / 1, pas de date.

---

## 2. Langage des rangs (à figer)

Les seuils **1 → 10 → 100** restent. Ce qui est ouvert : **comment on les *appelle* et on les *dessine***, pour que ça dise « trophée » sans piquer le vocabulaire du plateau.

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

Reco pour amender : **B pour les mots** (ça dit trophée), **A pour les formes** (ça dit BLOMIX). Écarter Blox/Brix/Magix. Piste D en joker si tu veux que le plateau *parle*.

---

## 3. Paliers (le système)

Chaque pastille a **un événement** (ce qu’on compte ou le meilleur) et **deux seuils** après le premier.

### Courbes

| Courbe | I | II | III | Pour |
|---|---|---|---|---|
| **Volume** | 1 | **10** | **100** | Combos, chaînes, parties, Magix (kinds) courants, bombes, partages |
| **Rare** | 1 | **3** | **10** | SAINTX, BOT1, CONNECT, grille vide, rang 1 du jour, secrets |
| **Qualité** | palier 1 | palier 2 | palier 3 | *Meilleur* : taille de chaîne 5 / 8 / 10+ ; stage 2 / 4 / Ultime ; score 1k / 5k / 10k |
| **Unique** | 1 | — | — | Tuto fini, thème Clair : allumé = fait. Pas de barre. Rang I suffit (on n’invente pas 10 tutos) |

Défaut = **Volume 1 / 10 / 100**, comme *Super combo*.  
Pas de 4ᵉ métal. L’échelle II→III **est** la longue (100). Si un trophée est trop grind (victoire BOT1 ×100), courbe **Rare 1 / 3 / 10**.

Les paliers **empilent** : le 100ᵉ combo a déjà donné I et II.

### Deux lectures, une pastille

- **Compte** (la plupart) : chaque événement +1, rang selon le total.
- **Qualité** (peu) : on mémorise le *max* (plus grande chaîne, plus haut stage, meilleur score). La barre va vers le *prochain seuil de max*, le chiffre sur le disque = ce max (8, pas « ×8 chaînes de 8 »).

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

Glyphe = symbole Magix (`?` `9` `+` `X` `=` `O` `∞` `§` `B`). Rang III de la pastille = couronne **en plus** du glyphe (médaille, pas « ce Magix est Magix »).

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

Pas de coupes 3D. Le rang **est** la forme — **provisoire** jusqu’au choix §2 (ci-dessous = piste A, craft).

| Rang | Forme (piste A) | Chiffre | Barre |
|---|---|---|---|
| Gris | Disque chrome α 0,35 | — | 0 |
| **I** | Plaque / poinçon, fill peau | compteur / max qualité | / seuil II |
| **II** | Capsule **relief** (bouton BLOMIX) | idem | / seuil III (nouvelle échelle) |
| **III** | Disque + **couronne de médaille** (anneau plein, pas halo Magix) | idem | pleine ; orbite à la fiche |

- Caption Nunito sous la forme, barre **3 pt** sous la caption (largeur = pastille).
- Mur : blox ambiants plus lents.
- Bandeau : cutout, pas d’XP de RPG.
- Fiche : titre Changa, corps Nunito, ×N gouttière comme +5 du hub.

Portrait. 4 colonnes, caption d’un mot (Magix non traduits).

---

## 7. Technique (plus tard, pas maintenant)

Un hook par famille d’événements. Le store ne connaît que `id → count | best`, le **rang se calcule** (seuils dans le catalogue).

```
rang = III si valeur ≥ s3
     else II si valeur ≥ s2
     else I si valeur ≥ 1 (ou ≥ s1 qualité)
     else gris
```

Store JSON `blomix_trophies_v1` : `{ id: { value, firstAt, brixAt, magixAt, seen } }`. Monotone. Pas de reset joueur.

Toast **au retour accueil** si palier monté pendant la run (pas de popup en partie). Tap → pièce, focus la pastille.

---

## 8. Ce qu’on ne fait pas

- Battle pass, XP global, quêtes du jour (déjà les Défis).
- 4ᵉ métal (platine). Trois formes BLOMIX, stop.
- Barre autour du disque (illisibile en 4 colonnes).
- Popup Magix **en cours de pose**.
- Révéler les secrets dans le guide.
- Forcer un Duel humain pour « finir » (BOT1 = plafond solo).
- Tuto « Passer » ≠ `play_tutorial`.

---

## 9. Décisions à figer

1. **Nom de la salle** : *Pièce des trophées* / *Cabinet* / *Réalisations* / autre.
2. **Langage des rangs** (§2) : A Poinçon/Relief/Couronne · B Inscrit/Médaille/Trophée · mix B mots + A formes (reco) · D CONNECT · autre.
3. **6ᵉ icône** accueil vs Crédits.
4. Courbe Volume **1 / 10 / 100** vs **1 / 10 / 50**.
5. `chain_count` à 100 / 1000 : OK comme exception ?
6. Toast accueil vs badge icône seulement.
7. 9 secrets, assez ?
8. Rétroactif minimal (hiscores, podium, tuto) : OK ?

---

## 10. Ordre de code (plus tard)

1. Store + rang calculé + écran mur / fiche / barre — une pastille témoin (*Super combo*).
2. Seuil (modes).
3. Chaînes + Magix.
4. Arcade / Five / Défi / Duel.
5. Folie + secrets.
6. l10n 6 langues, guide, GLOSSARY, CHANGELOG, whats-new au jalon.

Rien de tout ça avant : Five testé, boards GC live, **cette** spec validée (surtout §2 paliers + nom).

# BLOMIX — Pièce des trophées (piste)

> **Statut** : conception. **Pas de code.** À figer après tests Five + boards GC live.  
> **Version de référence** : 8.6  
> Vocabulaire : [GLOSSARY.md](GLOSSARY.md). Modes : [RULES.md](RULES.md). Magix : [MAGIX.md](MAGIX.md).  
> Nom d’écran : **à décider** (*Pièce des trophées* / *Cabinet* / *Réalisations*).

Un **cabinet personnel** : pastilles sur un mur. Grisées tant que jamais faites ; allumées dès la 1ʳᵉ fois, avec un **rang qui monte** (Blox → Brix → Magix) et une **barre gouttière** sous le nom. Pas un classement, pas un 4ᵉ mode, pas des Achievements Game Center (v1).

But : donner une raison de **toucher à tout** le jeu, puis d’y **revenir** — la pièce se relit, elle ne se coche pas.

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

1. **Bandeau** : pastilles allumées `28 / 41` · rangs `Blox 12 · Brix 11 · Magix 5` · dernière montée (nom + palier).
2. **Murs** par catégorie (titres cutout).
3. **Grille** 4 pastilles / rangée (famille disques de rang, ~52 pt).

Pas de SpriteKit ici : lecture, pas pose.

### Une pastille, trois vies

Pas bronze / argent / or Apple. **Le rang = un objet BLOMIX.** La pastille **change de nature** quand tu insistes.

Exemple — *Super combo* (cascade ≥ 2 vagues) :

| Compte | Rang | Pastille | Barre sous le nom |
|---|---|---|---|
| 0 | — | Grise, glyphe silhouette | Vide, ou absente |
| 1 | **Blox** | Carré peau, **1** | Gouttière peau **1 / 10** |
| 7 | Blox | Carré, **7** | **7 / 10** |
| 10 | **Brix** | Carré Brix + chiffre, **10** | Nouvelle échelle **10 / 100** (remplie à 10 %) |
| 47 | Brix | **47** | **47 / 100** |
| 100 | **Magix** | Disque + couronne, **100** | Pleine. Le compteur continue (347…) ; plus de palier |

Le **1** apparaît au premier déblocage. Ensuite le chiffre **est le compteur**, pas un niveau 1/2/3.

**Barre** = même recette que la jauge 0→N°1 (gouttière, fill peau, 3 pt). Sous le **nom** (caption mur + titre de fiche), pas autour du disque.

- Rang Blox : dénominateur = seuil **Brix** (souvent 10).
- Rang Brix : dénominateur = seuil **Magix** (souvent 100) — nouvelle barre, on « repart » visuellement.
- Rang Magix : barre pleine, halo d’orbite **seulement à l’ouverture de la fiche** (pas 41 orbites sur le mur).

Verrouillée **cachée** : caption **???**, tap = « Réalisation secrète », pas de barre.

Nouveau palier : souffle 2 cycles (disques accueil), puis calme.

### Fiche (tap)

Panneau bas, chrome capsule :

- Titre Changa + pastille (forme du rang actuel)
- Phrase joueur (ce que c’est)
- **×N** en gouttière
- Barre **n / prochain** (ou pleine si Magix) + libellé *vers Brix* / *vers Magix*
- Première fois · premier Brix · premier Magix (dates courtes)
- Fermer : hors panneau

Grise connue : condition lisible, 0 / 1, pas de date.

---

## 2. Paliers (le système)

Chaque pastille a **un événement** (ce qu’on compte ou le meilleur) et **deux seuils** après le premier.

### Courbes

| Courbe | Blox | Brix | Magix | Pour |
|---|---|---|---|---|
| **Volume** | 1 | **10** | **100** | Combos, chaînes, parties, Magix courants, bombes, partages |
| **Rare** | 1 | **3** | **10** | SAINTX, BOT1, CONNECT, grille vide, rang 1 du jour, secrets |
| **Qualité** | palier 1 | palier 2 | palier 3 | *Meilleur* : taille de chaîne 5 / 8 / 10+ ; stage 2 / 4 / Ultime ; score 1k / 5k / 10k |
| **Unique** | 1 | — | — | Tuto fini, thème Clair : allumé = fait. Pas de barre (déjà Magix visuellement ? **non** : Blox suffit, on n’invente pas 10 tutos) |

Défaut = **Volume 1 / 10 / 100**, comme *Super combo*.  
La « barre de 50 » du brief : on **ne** met **pas** un 4ᵉ métal. L’échelle Brix→Magix **est** la longue (100). Si un trophée est trop grind (victoire BOT1 ×100), il passe en **Rare 1 / 3 / 10**.

Les paliers **empilent** : le 100ᵉ combo a déjà donné Blox et Brix.

### Deux lectures, une pastille

- **Compte** (la plupart) : chaque événement +1, rang selon le total.
- **Qualité** (peu) : on mémorise le *max* (plus grande chaîne, plus haut stage, meilleur score). La barre va vers le *prochain seuil de max*, le chiffre sur le disque = ce max (8, pas « ×8 chaînes de 8 »).

On ne dédouble plus « chaîne 5 », « chaîne 8 », « chaîne 10 » en trois pastilles : **une** pastille *Chaîne*, rang Blox dès 5, Brix à 8, Magix à 10+. Le **volume** de chaînes est une **autre** pastille (*Cent / mille*).

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

## 3. Catégories (murs)

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

## 4. Catalogue v1

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
| `chain_count` | Encore | Nombre de chaînes ≥ 5 | V (Magix à **1000**, Brix à 100 — exception : trop fréquent en 1/10/100) |
| `combo` | Super combo | Résolution à **≥ 2** vagues | **V 1 / 10 / 100** — *l’exemple* |
| `combo_deep` | Série | Une résolution à **≥ 5** vagues | R |
| `connect` | CONNECT | Pont gauche–droite | R |
| `board_empty` | Vide | Bonus +500 grille vide | R |

`board_empty` hors Duel. CONNECT et chaînes **comptent** en Duel.  
`chain_count` : Blox 1, Brix **100**, Magix **1000** (pas 10/100, trop vite).

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

Glyphe = symbole Magix (`?` `9` `+` `X` `=` `O` `∞` `§` `B`). Rang Magix de la pastille = couronne **en plus** du glyphe.

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
| `daily_podium` | Podium | +5 / +3 / +1 crédité | V — Brix = 10 podiums, Magix = 50 |
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

**50** pastilles. Un Magix sur *Super combo* = 100 cascades ; un Magix sur *Pacifiste* = 10 GO à 5 bombes.

---

## 5. Graphisme

Pas de coupes 3D. Le rang **est** la forme.

| Rang | Forme | Chiffre | Barre |
|---|---|---|---|
| Gris | Disque chrome α 0,35 | — | 0 |
| **Blox** | Carré peau (blox) | compteur / max qualité | / seuil Brix |
| **Brix** | Carré Brix, digit style HUD | idem | / seuil Magix (nouvelle échelle) |
| **Magix** | Disque + couronne noire | idem | pleine ; orbite à la fiche |

- Caption Nunito sous la forme, barre **3 pt** sous la caption (largeur = pastille).
- Mur : blox ambiants plus lents.
- Bandeau : cutout, pas d’XP de RPG.
- Fiche : titre Changa, corps Nunito, ×N gouttière comme +5 du hub.

Portrait. 4 colonnes, caption d’un mot (Magix non traduits).

---

## 6. Technique (plus tard, pas maintenant)

Un hook par famille d’événements. Le store ne connaît que `id → count | best`, le **rang se calcule** (seuils dans le catalogue).

```
rang = Magix si valeur ≥ sMagix
     else Brix si valeur ≥ sBrix
     else Blox si valeur ≥ 1 (ou ≥ sBlox qualité)
     else gris
```

Store JSON `blomix_trophies_v1` : `{ id: { value, firstAt, brixAt, magixAt, seen } }`. Monotone. Pas de reset joueur.

Toast **au retour accueil** si palier monté pendant la run (pas de popup en partie). Tap → pièce, focus la pastille.

---

## 7. Ce qu’on ne fait pas

- Battle pass, XP global, quêtes du jour (déjà les Défis).
- 4ᵉ métal (platine). Trois formes BLOMIX, stop.
- Barre autour du disque (illisibile en 4 colonnes).
- Popup Magix **en cours de pose**.
- Révéler les secrets dans le guide.
- Forcer un Duel humain pour « finir » (BOT1 = plafond solo).
- Tuto « Passer » ≠ `play_tutorial`.

---

## 8. Décisions à figer

1. **Nom** : *Pièce des trophées* / *Cabinet* / *Réalisations* / autre.
2. **6ᵉ icône** accueil vs Crédits.
3. Courbe Volume **1 / 10 / 100** (reco, ton *Super combo*) vs **1 / 10 / 50** (Or plus tôt).
4. `chain_count` à 100 / 1000 : OK comme exception ?
5. Toast accueil vs badge icône seulement.
6. 9 secrets, assez ?
7. Rétroactif minimal (hiscores, podium, tuto) : OK ?

---

## 9. Ordre de code (plus tard)

1. Store + rang calculé + écran mur / fiche / barre — une pastille témoin (*Super combo*).
2. Seuil (modes).
3. Chaînes + Magix.
4. Arcade / Five / Défi / Duel.
5. Folie + secrets.
6. l10n 6 langues, guide, GLOSSARY, CHANGELOG, whats-new au jalon.

Rien de tout ça avant : Five testé, boards GC live, **cette** spec validée (surtout §2 paliers + nom).

# Blomix — Règles du jeu

> **Version de référence** : 6.4  
> Aligné sur le comportement du binaire (build 118).

## 1. La grille

La grille est de **8 colonnes × 8 rangées**.  
Les rangées sont indexées **de 0 (haut) à 7 (bas)**.  
Les colonnes sont indexées de **0 (gauche) à 7 (droite)**.

La **gravité est inversée** : les blocs se compactent **vers le haut**. Quand des blocs sont supprimés, les blocs restants remontent pour occuper les rangées les plus hautes disponibles dans leur colonne. Les cases vides se retrouvent **en bas** de chaque colonne.

---

## 2. Les blocs jouables

Chaque tirage de la file (P0 / P1 / P2) suit **cet ordre** :

1. **Magix** — ~**3 %** cumulé (voir §2c)  
2. **Brix** — **1/8** du tirage (12,5 %)  
3. **Blox couleur** — le reste (~84,5 %), uniforme parmi les 6 couleurs  

Les Magix sont donc tirés **en premier** : ils ne s’ajoutent pas « par-dessus » un 7/8 couleur + 1/8 Brix.

### 2a. Blox (blocs couleur)

6 couleurs : rouge, bleu, vert, jaune, violet, orange.

### 2b. Brix (Priks)

Blocs numérotés. Compteur initial : **5**.  
À chaque chaîne qui **touche** (8-connexité) un Brix, son compteur décrémente de **1** (maximum 1 par vague de résolution).  
Quand le compteur atteint **0**, le Brix disparaît et rapporte **20 pts**.

Les Brix **ne participent jamais** à la formation des chaînes.

### 2c. Blocs Magix

Blocs spéciaux rares (~**3 %** de probabilité cumulée) déclenchant un effet à l'atterrissage. Ils **n'apparaissent jamais** dans les lignes entrantes du bas, ni en **Duel**.

| Variante | Symbole | Effet |
|---|---|---|
| **CHROMAX** | ? | Chemin aléatoire (≤ 15 cases) transformé en une couleur, puis résolution des chaînes |
| **BRIXED** | 9 | Devient un Brix(9) ; **tous les autres Brix sont détruits** (+20 pts chacun) |
| **CROSSX** | + | Ligne + colonne centrées sur la case deviennent une couleur aléatoire, puis chaînes |
| **SCRUMBLX** | = | Chaque ligne occupée se décale horizontalement (1–7 cases, wrap-around) ; −1 sur tous les Brix |
| **COLORX** | O | Roulette de couleur : efface tous les blocs de la couleur choisie (score chaîne) |
| **SAINTX** (cleanx) | ∞ | Efface toute la grille et laisse un Brix valant le nombre de cases supprimées ; **+200 pts** bonus (en Arcade : × le multiplicateur du stage) |
| **TWISTX** | X | Échange **automatique** : une couleur aléatoire présente sur la grille ↔ tous les Brix (valeur = minimum des Brix existants, défaut 3) |
| **BOMBX** | B | Peint (cases **déjà occupées** seulement) : atterrissage + voisins 8-connexes + 1 hop aléatoire par voisin + **encore 1 hop** (tâche 3 rangs) en une couleur ; chaînes ; puis **+1 bombe** au stock (garanti même sans clear). Rareté ≈ SAINTX. **Arcade / Zen** uniquement |

Les fractions exactes par variante sont dans [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) §7.

---

## 3. Pose d'un bloc

Le joueur choisit une **colonne** (tap ou glissement). Le bloc est posé dans la **première case vide depuis le haut** dans cette colonne.

| Situation | Comportement |
|---|---|
| Colonne pleine, d'autres libres | Son d'erreur, pose refusée |
| Toutes les colonnes pleines | Game Over |

Un **ghost preview** (opacité 55 %) montre la position d'atterrissage après un appui maintenu ≥ 120 ms.

---

## 4. File de blocs

Le joueur voit en permanence :

| Slot | Rôle |
|---|---|
| **P0** | Bloc en cours (grand aperçu) |
| **P1** | Prochain bloc |
| **P2** | Bloc d'encore après |

Après chaque pose : P0 ← P1, P1 ← P2, P2 ← tirage aléatoire.

En **Duel**, la séquence est partagée (RNG synchronisé, **sans Magix**).  
En **tutoriel**, la séquence est scriptée puis repasse en aléatoire.

---

## 5. Détection des chaînes

Une **chaîne** se forme quand **5 blox ou plus de la même couleur** sont **8-connexes** (horizontal, vertical, diagonal).

Dès qu'une telle configuration existe (après pose, compactage ou effet Magix), elle est détectée et déclenchée.

### Cascades

Après suppression + compactage, la grille est re-scannée. Les nouvelles chaînes forment une **cascade** (combo). Le niveau `chainSeriesLevel` s'incrémente à chaque vague :

- Première chaîne d'une résolution → `chainSeriesLevel = 0`
- Deuxième vague (cascade) → `chainSeriesLevel = 1` → popup **COMBO**
- Troisième → `chainSeriesLevel = 2` → popup **SUPER COMBO**, etc.

### Bombe et cascades

Poser une bombe fixe `chainSeriesLevel = 1` pour les cascades qui suivent.

---

## 6. Scoring

### Chaînes (Blox couleur)

| Taille du groupe | Points de base |
|---|---|
| 5 blox | 5 pts |
| 6 blox | 7 pts |
| 7 blox | 10 pts |
| 8 blox | 13 pts |
| 9 blox | 15 pts |
| 10+ blox | 20 pts |

**Bonus cascade** : `+10 × chainSeriesLevel` pts ajoutés au score de base.

Exemples :
- Chaîne de 6 au niveau 0 → 7 pts
- Chaîne de 6 au niveau 1 → 17 pts
- Chaîne de 6 au niveau 2 → 27 pts

Si plusieurs composantes indépendantes existent dans la même vague, elles partagent le même `chainSeriesLevel`.

En **Arcade**, les points passent par le multiplicateur du stage courant (×1 à ×6), **sauf** le bonus grille vide (§ ci-dessous), qui est plat.

### Brix

| Action | Points |
|---|---|
| Brix disparu (compteur → 0 via chaîne, SCRUMBLX, etc.) | **20 pts** par Brix |
| Brix détruit par bombe | **20 pts** par Brix |
| Brix détruit par **BRIXED** | **20 pts** par Brix |

### Bombe

| Action | Points |
|---|---|
| Explosion (usage) | **10 pts** |
| Brix détruits dans le rayon | **20 pts** chacun |

### Colonne entièrement vidée

**+10 pts** par colonne qui contenait au moins un bloc avant la vague et se retrouve entièrement vide après.

### Grille entièrement vide (Arcade / Zen)

Si une vague part d’une grille **non vide** et la laisse **entièrement vide** : **+500 pts** plats (hors ×stage), **en plus** des +10 par colonne. Absent en Duel et en tutoriel.

### SAINTX (cleanx)

**+200 pts** bonus à l'activation (en plus du Brix laissé sur la grille).  
En Arcade, ce bonus **est multiplié** par le ×stage (×1 à ×6). En Zen : +200 plat.

---

## 7. La ligne entrante (tous les 10 coups)

Tous les **10 coups de pose** (`moveCount % 10 == 0`), une rangée de 8 blocs **monte depuis le bas** et occupe la première case vide de chaque colonne.

Un **coup** = une pose de bloc (Blox, Brix ou Magix) dont la résolution est terminée. **Poser une bombe n’est pas un coup** : le compteur LIGNE n’avance pas.

- Le compteur **LIGNE x/10** est visible en permanence dans le HUD.
- La composition est **prévisualisée au coup 9** (demi-cases en bas de grille).
- Chaque case est tirée indépendamment comme un bloc de file, **puis** tout Magix est remplacé par une couleur. En tutoriel, les Brix des lignes sont aussi remplacés par des couleurs.
- Si une colonne est déjà pleine au moment de l'injection → **Game Over**.

En **Duel**, des lignes d'**attaque** supplémentaires peuvent arriver quand un joueur franchit un palier de **50 points** de score. Une **barre continue 0…50** à droite du gros score (le chiffre HUD est le reste `score % 50`) montre l’approche du prochain palier ; c’est un indicateur HUD, l’envoi reste inchangé.

---

## 8. Les bombes

| Paramètre | Arcade / Zen | Duel |
|---|---|---|
| Stock initial | **5** | **3** |

**Utilisation :**
1. Taper l'icône bombe → mode bombe actif (la bombe sort du stock).
2. Taper **directement une case** de la grille (visée : overlay de la zone).
3. Tremblement 0,3 s, puis explosion.
4. Tous les Blox couleur dans le rayon sont supprimés.
5. Les Brix dans le rayon sont **détruits** (pas décrémentés) → 20 pts chacun.
6. Compactage, puis résolution des cascades (niveau 1).

Taper à nouveau l'icône bombe **annule** le mode et restitue la bombe au stock.

**Ce n’est pas un coup** pour la ligne entrante (voir §7).

### Zone d’explosion

| Mode | Zone |
|---|---|
| Zen, Duel, tutoriel | Toujours **3×3** (8-connexité autour de la case) |
| Arcade stage 1 | **3×3** |
| Arcade stage 2 | 3×3 + **1** case par bras cardinal (croix) |
| Arcade stage 3 | 3×3 + **2** cases par bras |
| Arcade stage 4 | 3×3 + **3** cases par bras |
| Arcade stage 5 | 3×3 + **4** cases par bras |
| Arcade Ultime | 3×3 + **5** cases par bras |

À partir du stage 2, l’icône HUD passe à la texture **nuke**. Les cases hors grille sont ignorées.

En **Duel**, tant que le mode bombe est actif (visée), le **timer de tour (10 s) est gelé**. Annuler ou poser la bombe relance le décompte.

---

## 9. Modes de jeu

### Arcade (défaut)

Partie infinie avec **timer par coup** et **multiplicateur de score** progressif :

| Stage | Score min | Timer | Multiplicateur |
|---|---|---|---|
| 1 | 0 | 32 s | ×1 |
| 2 | 250 | 16 s | ×2 |
| 3 | 1 000 | 8 s | ×3 |
| 4 | 2 000 | 4 s | ×4 |
| 5 | 3 000 | 2 s | ×5 |
| Ultime | 5 000 | 1 s | ×6 |

Quand le timer arrive à 0, le bloc courant est **posé automatiquement** : au hasard parmi les colonnes dont **la ligne du haut est encore vide** ; s’il n’y en a aucune, au hasard parmi toutes les colonnes encore jouables. Si plus aucune colonne n’est libre → Game Over.

Sauvegarde automatique à la mise en arrière-plan (reprise : voir [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) §11).

### Mode Zen

Sans timer, sans stages, bombes **3×3** uniquement. Classement Game Center dédié (`ZenMode`). Multiplicateur ×1.

### Duel (1 vs 1)

Via **Game Center** (en ligne) ou **Multipeer** (Local) :
- RNG partagé → mêmes blocs pour les deux joueurs (**pas de Magix**)
- **3 bombes** au départ, zone **3×3**
- Attaque : ligne chez l'adversaire à chaque palier **score / 50**
- Le score affiché est le reste **0–49** avant le prochain palier (le total n’est pas montré)
- Timer de tour : **10 s** par coup ; **geler** tant que le mode bombe est actif
- **Elo** : rating initial 800, K adaptatif selon le nombre de matchs
- Victoire = adversaire en Game Over ; le score le plus élevé l'emporte

Détail appariement / défis : [PVP_MATCHING.md](PVP_MATCHING.md).

### Tutoriel interactif

- Automatique au premier lancement (ou via l’icône Tutoriel de l’accueil)
- Séquence de blocs scriptée, bombe verrouillée jusqu'à l'étape dédiée
- Pas de Brix/Magix dans les lignes injectées
- Bouton **Passer** toujours disponible

---

## 10. Analyse des coups

En fin de partie Arcade / Zen, un récapitulatif indique la **justesse** des placements et permet de revoir le **pire coup**. Il n’y a plus de bouton hint en cours de partie.

Le pourcentage **ne compte pas** les Magix ni les bombes : seuls les placements de Blox / Brix sont évalués, sur un horizon de 3 blocs visibles (P0, P1, P2).

Voir [EVAL.md](EVAL.md) pour l’algorithme.

---

## 11. Game Over

Le jeu se termine quand :
- Le joueur tente de poser un bloc dans une colonne **pleine** alors qu'**aucune autre colonne** n'est disponible
- Une ligne entrante (ou d’attaque) provoque un débordement (colonne pleine)
- En Arcade, le timer expire alors qu’aucune colonne n’est jouable

L'écran affiche le **score final**, une citation aléatoire, le récapitulatif d'optimalité, et les boutons Rejouer / Accueil / Classement (plus Partager et, le cas échéant, le pire coup).

---

## 12. Analyse des coups (feedback interne)

Un moteur interne évalue chaque coup sur un horizon de 3 blocs (P0, P1, P2). En fin de partie, un pourcentage d'**optimalité** résume la qualité globale des choix.

Seuils de feedback (si activé en temps réel — **désactivé** en production) :
- Écart ≤ 50 pts vs optimal → **!!** (excellent, si spread ≥ 900)
- Écart > 900 pts → **?** (mauvais)

Voir [EVAL.md](EVAL.md).

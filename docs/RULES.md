# Blomix — Règles du jeu

## 1. La grille

La grille est de **8 colonnes × 8 rangées**.  
Les rangées sont indexées **de 0 (haut) à 7 (bas)**.  
Les colonnes sont indexées de **0 (gauche) à 7 (droite)**.

La **gravité est inversée** : les blocs se compactent **vers le haut**. Quand des blocs sont supprimés, les blocs restants remontent pour occuper les rangées les plus hautes disponibles dans leur colonne. Les cases vides se retrouvent **en bas** de chaque colonne.

---

## 2. Les blocs jouables

### 2a. Blox (blocs couleur)

6 couleurs : rouge, bleu, vert, jaune, violet, orange.  
Probabilité de tirage : **7/8** (uniforme parmi les 6 couleurs).

### 2b. Brix (Priks)

Blocs numérotés, tirés avec une probabilité de **1/8**.  
Compteur initial : **5**.  
À chaque chaîne qui **touche** (8-connexité) un Brix, son compteur décrémente de **1** (maximum 1 par vague de résolution).  
Quand le compteur atteint **0**, le Brix disparaît et rapporte **20 pts**.

Les Brix **ne participent jamais** à la formation des chaînes.

### 2c. Blocs Magix

Blocs spéciaux rares (~**3 %** de probabilité cumulée) déclenchant un effet à l'atterrissage. Ils **n'apparaissent jamais** dans les lignes entrantes du bas.

| Variante | Symbole | Effet |
|---|---|---|
| **CHROMAX** | ? | Chemin aléatoire (≤ 15 cases) transformé en une couleur, puis résolution des chaînes |
| **BRIXED** | 9 | Devient un Brix(9) ; tous les autres Brix perdent 2 points |
| **CROSSX** | + | Ligne + colonne centrées sur la case deviennent une couleur aléatoire, puis chaînes |
| **SCRUMBLX** | = | Chaque ligne occupée se décale horizontalement (1–7 cases, wrap-around) ; −1 sur tous les Brix |
| **COLORX** | O | Roulette de couleur : efface tous les blocs de la couleur choisie (score chaîne) |
| **SAINTX** (cleanx) | ∞ | Efface toute la grille et laisse un Brix valant le nombre de cases supprimées (+200 pts bonus) |
| **TWISTX** | X | Échange une couleur aléatoire ↔ tous les Brix (valeur = minimum des Brix existants, défaut 3) |

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

En **PvP**, la séquence est partagée (RNG synchronisé).  
En **tutoriel**, la séquence est scriptée puis repasse en aléatoire.

---

## 5. Détection des chaînes

Une **chaîne** se forme quand **5 blox ou plus de la même couleur** sont **8-connexes** (horizontal, vertical, diagonal).

Dès qu'une telle configuration existe (après pose, compactage ou effet Magix), elle est détectée et déclenchée.

### Cascades

Après suppression + compactage, la grille est re-scannée. Les nouvelles chaînes forment une **cascade** (combo). Le niveau `chainSeriesLevel` s'incrémente à chaque vague :

- Première chaîne d'une résolution → `chainSeriesLevel = 0`
- Deuxième vague (cascade) → `chainSeriesLevel = 1`
- Troisième → `chainSeriesLevel = 2`, etc.

Popup **COMBO** / **SUPER COMBO** à partir du niveau 2.

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

En **mode solo stagé**, tous les points sont multipliés par le multiplicateur du stage courant (×1 à ×6).

### Brix

| Action | Points |
|---|---|
| Brix disparu (compteur → 0 via chaîne) | **20 pts** par Brix |
| Brix détruit par bombe | **20 pts** par Brix |

### Bombe

| Action | Points |
|---|---|
| Explosion (usage) | **10 pts** |
| Brix détruits dans le rayon | **20 pts** chacun |

### Colonne entièrement vidée

**+10 pts** par colonne qui contenait au moins un bloc avant la vague et se retrouve entièrement vide après.

### SAINTX (cleanx)

**+200 pts** bonus à l'activation (en plus du Brix laissé sur la grille).

---

## 7. La ligne entrante (tous les 10 coups)

Tous les **10 coups joués** (`moveCount % 10 == 0`), une rangée de 8 blocs **monte depuis le bas** et occupe la première case vide de chaque colonne.

- Le compteur **LIGNE x/10** est visible en permanence dans le HUD.
- La composition est **prévisualisée au coup 9** (demi-cases en bas de grille).
- Chaque case est tirée indépendamment (1/8 Brix, ~3 % Magix, reste couleur).
- Les blocs **Magix n'apparaissent jamais** dans ces lignes.
- Si une colonne est déjà pleine au moment de l'injection → **Game Over**.

En **PvP**, des lignes d'**attaque** supplémentaires peuvent arriver quand un joueur franchit un palier de **50 points** de score.

---

## 8. Les bombes

| Paramètre | Solo | PvP |
|---|---|---|
| Stock initial | **5** | **3** |

**Utilisation :**
1. Taper l'icône bombe → mode bombe actif (la bombe sort du stock).
2. Taper **directement une case** de la grille.
3. Tremblement 0,3 s, puis explosion **3×3** (8-connexité autour de la case ciblée).
4. Tous les Blox couleur dans le rayon sont supprimés.
5. Les Brix dans le rayon sont **détruits** (pas décrémentés) → 20 pts chacun.
6. Compactage, puis résolution des cascades (niveau 1).

Taper à nouveau l'icône bombe **annule** le mode et restitue la bombe au stock.

---

## 9. Modes de jeu

### Solo stagé (défaut)

Partie infinie avec **timer par coup** et **multiplicateur de score** progressif :

| Stage | Score min | Timer | Multiplicateur |
|---|---|---|---|
| 1 | 0 | 32 s | ×1 |
| 2 | 250 | 16 s | ×2 |
| 3 | 1 000 | 8 s | ×3 |
| 4 | 2 000 | 4 s | ×4 |
| 5 | 3 000 | 2 s | ×5 |
| Ultime | 5 000 | 1 s | ×6 |

Sauvegarde automatique à la mise en arrière-plan.

### Mode Zen

Sans timer, sans stages. Classement Game Center dédié (`ZenMode`). Multiplicateur ×1.

### PvP (1 vs 1)

Via **Game Center** :
- RNG partagé → mêmes blocs pour les deux joueurs
- **3 bombes** au départ
- Attaque : ligne chez l'adversaire à chaque palier **score / 50**
- Timer de tour : **10 s** par coup
- **Elo** : rating initial 800, K adaptatif selon le nombre de matchs
- Victoire = adversaire en Game Over ; le score le plus élevé l'emporte

### Tutoriel interactif

- Automatique au premier lancement (ou via le bouton Tutoriel)
- Séquence de blocs scriptée, bombe verrouillée jusqu'à l'étape dédiée
- Pas de Brix/Magix dans les lignes injectées
- Bouton **Passer** toujours disponible

---

## 10. Aide (Hint)

**5 hints** par partie. Le bouton **?** affiche la colonne optimale calculée par le moteur d'analyse (lookahead 3 niveaux). L'indicateur disparaît après 2,5 s.

---

## 11. Game Over

Le jeu se termine quand :
- Le joueur tente de poser un bloc dans une colonne **pleine** alors qu'**aucune autre colonne** n'est disponible
- Une ligne entrante provoque un débordement (colonne pleine)

L'écran affiche le **score final**, une citation aléatoire, le récapitulatif d'optimalité (si activé), et les boutons Rejouer / Classement.

---

## 12. Analyse des coups (feedback)

Un moteur interne évalue chaque coup sur un horizon de 3 blocs (P0, P1, P2). En fin de partie, un pourcentage d'**optimalité** résume la qualité globale des choix.

Seuils de feedback (si activé en temps réel) :
- Écart ≤ 50 pts vs optimal → **!!** (excellent, si spread ≥ 900)
- Écart > 900 pts → **?** (mauvais)

Voir [EVAL.md](EVAL.md) pour le détail de l'algorithme.

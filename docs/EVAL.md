# Blomix — Fonction d'évaluation (`BlomixMoveAnalyzer`)

> **Version implémentée** : v2 (production)  
> Fichier source : `Blomix/Blomix/BlomixMoveAnalyzer.swift`

---

## Vue d'ensemble

La fonction d'évaluation attribue un **score de position** à une grille stable (après résolution de toutes les cascades). Ce score alimente un **lookahead à 3 niveaux** pour choisir la meilleure colonne (hints) et évaluer la qualité des coups du joueur.

Un score **plus élevé** = position **meilleure**.  
La plupart des termes sont des **pénalités** (négatifs) ; les termes positifs récompensent les structures favorables.

---

## Feature flags

| Flag | Valeur | Effet |
|---|---|---|
| `evalEnabled` | `true` | Active le moteur (CPU sur thread dédié) |
| `realtimeFeedbackEnabled` | `false` | Pas de popup `!!` / `?` en cours de partie |

---

## Signature

```swift
static func evaluate(grid: SimGrid, moveCount: Int) -> Int
```

**Retourne :**

```swift
risk + clearing + brixPotential + stability + structure + accessibility + preChainScore
```

---

## Terme 1 — `risk` : pénalité de hauteur

### Calcul des hauteurs

Hauteur d'une colonne = **première rangée vide depuis le haut** (row 0 = sommet).

```
maxH     = max des hauteurs sur 8 colonnes
sumH     = somme des hauteurs
fullCols = colonnes entièrement remplies (hauteur = 8)
```

### Urgence (proximité de la ligne entrante)

```
k = 10 - (moveCount % 10)     // coups restants [1..10]
t = (10 - k) / 9.0            // 0.0 (ligne loin) → 1.0 (imminent)

urgencyH  = 0.80 + 0.20 × t   // [0.80 .. 1.00]
urgencySH = 0.90 + 0.10 × t   // [0.90 .. 1.00]
```

### Facteur dynamique (v2)

Si `maxH ≥ 4` et que la colonne la plus haute contient un groupe ≥ 3 **ou** un landing spot avec `preChainScore > 0` :

```
dynamicFactor = 0.75   // sinon 1.0
```

Atténue la pénalité quand la hauteur a une valeur stratégique.

### Formule

```
risk = -900 × maxH × urgencyH × dynamicFactor
     -  85 × sumH × urgencySH
     - 3000 × fullCols
```

---

## Terme 2 — `clearing` : groupes existants + bonus Brix

Recensement des composantes 8-connexes par taille :

```
clearing = 45 × nGe5 + 30 × nGe4 + 15 × nGe3 + brixTouchBonus
```

**Bonus Brix (v2)** : pour chaque groupe ≥ 5 touchant un Brix en 8-connexité :

```
brixTouchBonus += 8
```

---

## Terme 3 — `structure`

```
structure = 12 × totalInGe3
```

`totalInGe3` = nombre total de blocs dans des composantes de taille ≥ 3.

---

## Terme 4 — `accessibility` : capacité à étendre les groupes

Points d'accès = cases vides 8-adjacentes à un groupe qui sont aussi la **case d'atterrissage** de leur colonne.

**v2 : groupes de taille 2, 3 et 4** (v1 : 3 et 4 seulement).

```
accessibility = 25 × accessPoints4 +  9 × accessPoints3 +  3 × accessPoints2
              - 40 × deadGroups4   - 15 × deadGroups3   -  6 × deadGroups2
```

---

## Terme 5 — `brixPotential` (ex-`brixScore`)

Pour chaque Brix (compteur `n`, position `row`) :

```
base = 40 × (5 - n)
if row >= 5: base -= 30

futureBonus = 0
if 8-adjacent à un groupe couleur ≥ 3: futureBonus += 25
if 8-adjacent à un landing spot avec preChainScore ≥ 45: futureBonus += 35

contribution = base + futureBonus

brixPotential = max(-550, Σ contributions)
```

---

## Terme 6 — `stability`

```
stability = 4 × (10 - moveCount % 10)   // [4 .. 40]
```

Favorise légèrement les positions éloignées de la prochaine injection.

---

## Terme 7 — `preChainScore` : potentiel de fusion

Pour chaque colonne avec landing spot `L`, somme des composantes 8-adjacentes de même couleur (groupes fragmentés fusionnables par un seul bloc) :

| `colorTotals[c] + 1` | Bonus |
|---|---|
| ≥ 5 | **+150** |
| = 4 | **+45** |
| = 3 | **+12** |

**Bonus Brix (v2)** : si `L` est 8-adjacent à un Brix et `cellScore > 0` :

```
bonus += 20
```

---

## Lookahead 3 niveaux (`computeOptimal`)

Explore exactement les 3 blocs visibles :

```
col0 → pose P0 (currentBlock)
col1 → pose P1 (blockAfterCurrent)
col2 → pose P2 (blockTwoAhead)
```

Complexité : **8 × 8 × 8 = 512** simulations (chaque cascade incluse).  
Thread : `DispatchQueue` QoS `.userInitiated`.

### Injection de ligne

Simulée au **niveau 1** si `(moveCount + 1) % 10 == 0` et `pendingLine` connu.  
Niveaux 2 et 3 : `pendingLine = nil`.

### Bonus d'effacement immédiat (`immediateClearing`)

En plus de `evaluate(g3)`, le lookahead ajoute un bonus par niveau pour les blocs **net** effacés :

```
immediateClearing = max(0, cellCount(before) - cellCount(after)) × 65
```

Compense le fait qu'une bonne chaîne appauvrit temporairement la grille aux yeux de `evaluate()`.

### Magix

Si P0 est un Magix → résultat vide (effet non simulable).

---

## Seuils de qualité du coup

```
delta = optimalScore - scorePerColumn[colonneChoisie]
spread = optimalScore - worstScore
```

| Condition | Qualité | Feedback |
|---|---|---|
| `delta ≤ 50` et `spread ≥ 900` | Excellent | `!!` |
| `delta > 900` | Mauvais | `?` |
| Sinon | Neutre | — |

Le spread minimum (900) évite les `!!` quand toutes les colonnes sont équivalentes.

---

## Statistiques de partie

`BlomixGameMoveStats` accumule un `BlomixMoveRecord` par coup analysé.

**Optimalité %** (affichée au Game Over) :

```
Pour chaque coup :
  si spread < 200 → contribution = 1.0 (pas de pénalité)
  sinon → (chosenScore - worstScore) / spread

optimalityPercent = moyenne × 100
```

**Pire coup** : snapshot `BlomixWorstMistakeSnapshot` (grille, file, colonne choisie vs optimales) consultable depuis l'écran Game Over.

---

## Limites connues

1. **Cascades profondes** aux niveaux 2–3 : seule la position finale est scorée (partiellement compensé par `immediateClearing`).
2. **Horizon borné à 3** : setups à 4+ coups sous-évalués.
3. **Magix et bombes** : non simulés dans le lookahead.
4. **Lignes futures** : ignorées au-delà du niveau 1 (compensé partiellement par `urgencyH`).
5. **`risk` dominant** : même avec le facteur dynamique v2.

---

## Historique v1 → v2

| Aspect | v1 | v2 (actuel) |
|---|---|---|
| Coefficient `maxH` | −1200 | −900 + facteur dynamique |
| Accessibilité | groupes 3–4 | groupes 2–4 |
| Brix | `brixScore` réactif | `brixPotential` + bonus futur |
| Clearing | base seule | +8 si chaîne touche Brix |
| preChainScore | base seule | +20 si touche Brix |
| Lookahead | evaluate(g3) seul | + immediateClearing par niveau |

La spécification v2 initiale (`EVAL2.md`) est entièrement implémentée.

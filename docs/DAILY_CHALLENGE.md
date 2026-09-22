# BLOMIX — Défi du jour (graine)

> **Statut** : **7.2 / 136** en review App Store. En vente : 7.1 / 134.  
> **CloudKit** : type Public `DailyScore` déployé en **Production**.  
> **Game Center** : `dailywins_arc` (nom ASC `DailyWin_arc`).  
> **Version de référence** : 7.2  
> **2026-09-21**  
> Voir aussi [MODE_PISTES.md](MODE_PISTES.md) § Graine du jour, [MAGIX.md](MAGIX.md), [RULES.md](RULES.md).

Objectif : **tout le monde joue la même partie** ce jour-là (file, Magix, lignes des 10). UX simple. Classement du **jour** à l’écran Game Over + un classement Game Center des **victoires** cumulées.

---

## 1. Ce que le joueur voit (cible)

**Deux classements distincts** (ne pas les fusionner dans un seul écran) :

| | Aujourd’hui (scores) | Carrière (points podium) |
|---|---|---|
| Contenu | Scores de **ce** jour UTC | Cumul +5/+3/+1 |
| Entrée | Chip accueil → **hub du jour** | 5ᵉ disque **défi** → onglet GC (comme Arc. / Zen / Duel) |

### Hub unique (un seul écran « jour »)

Tap chip accueil → **toujours** le hub (liste CloudKit du jour + un CTA) :

| État | Libellé du chip accueil | CTA du hub |
|---|---|---|
| Pas encore joué | **Défi du jour** | **Défi !** (lance) |
| Run en cours (save) | **Défi du jour** (ou Continuer défi) | **Continuer** |
| GO déjà fait aujourd’hui | **Classement du défi** | **Revenez demain** (grisé, non lancable) |

Tap CTA grisé : rien (déjà sur le classement). Tap chip grisé/renommé : **même hub**.

Dans la liste : noms 1 / 2 / 3 en **Changa One** (1er plus grand) ; à droite, **+5 / +3 / +1** en gouttière (`BlomixCutoutTitleView`) pour les places du jour (égalités = mêmes points, places sautées). Calcul **client**, pas un champ CloudKit. CTA **Revenez demain** : grisé, non cliquable.

**Game Over** (court, après `end.wav`) : **ton score** + rang live + **Accueil** + **Classement** (→ hub, où tu te vois dans la liste). Pas de récap justesse.

**Quitter une run en cours** : Arcade / Duel / Zen → dialogue d’abandon **habituel**. Le hub **Continuer** reprend sans dialogue.

**Disque défi** : rang GC **carrière** (points), pas la liste du jour — comme les 4 autres disques.

### Pourquoi ce chemin

- Un seul endroit pour « les scores d’aujourd’hui ».
- On **voit** le défi (et les scores) **avant** de jouer — c’est un défi, pas une surprise.
- Après la partie, le chip **change de métier** (jouer → consulter) sans nouveau menu.
- On ne mélange pas « qui a gagné aujourd’hui » et « qui a le plus de points depuis toujours ».

Pas de Duel, pas de film, pas de 2 grilles.

---

## 2. « La même partie » — ce que ça impose au hasard

Aujourd’hui le solo tire avec `Double.random` / `randomElement()` (`randomNextPlayableBlock`, lignes, remplacement Magix → couleur). Le Duel a déjà un RNG **seedé** (`BlomixPvPSeededBlockRNG`) mais **sans Magix**.

Pour que deux joueurs qui jouent **les mêmes colonnes** voient **la même chose**, il faut **deux flux** distincts :

| Flux | Contenu | Ne doit PAS dépendre |
|---|---|---|
| **File** (seed du jour uniquement) | Blox / Brix / **kind** Magix de la file à 3 ; chaque ligne des 10 (8 cases, **sans Magix** comme aujourd’hui) | Des colonnes jouées, des bombes, du juice |
| **Effets** (seed + événement) | Chemin CHROMAX, couleur CROSSX/SLASHX/COLORX, décalages SCRUMBLX, hops BOMBX, couleur TWISTX, etc. | De la file (ne pas avancer le flux File) |

Si on mélange les deux dans un seul compteur : un CHROMAX posé plus tôt **décale** toute la file suivante → ce n’est plus la même partie.

Les effets Magix **dépendent de la case d’atterrissage** (CROSSX = cette ligne + colonne). C’est voulu : le skill, c’est *où* tu poses. Deux joueurs identiques jusqu’au Magix → même effet. Deux colonnes différentes → grilles différentes, **file encore identique**.

**Timer Arcade :** ce n’est pas du hasard, c’est du skill (tu poses avant 0). Deux joueurs qui timeout à des moments différents ont **divergé** comme s’ils avaient choisi des colonnes différentes. La **file** reste la même.

**Auto-drop :** la colonne auto **peut différer** d’un joueur à l’autre (décision produit : sans importance). Pas besoin de le seeder. La file, elle, reste identique.

Lignes des 10 : aujourd’hui `generateNextRandomLineRowIndependentCells()` puis on **remplace** les Magix par une couleur **non seedée**. En Défi : tirer la ligne **déjà** sans Magix, tout depuis le flux File (Brix dans la ligne : **oui**, comme Arcade, sauf si on décide le contraire).

Skin Alea / thème chrome : **visuel**, pas dans la graine.

---

## 3. Reco règles de partie (à figer avant code)

| Sujet | Reco | Pourquoi |
|---|---|---|
| Base | **Arcade** (timer, stages 1…Ultime, ×1…×6, bombe qui grandit, auto-drop) | Demandé : même accélération |
| Magix | **Oui**, mêmes raretés | Demandé ; catalogue actuel |
| Lignes | Tous les 10 coups, seedées, pas de Magix | Comme Arcade |
| Bombes | 5 au départ, **zone selon le stage** (comme Arcade) | Pas le 3×3 Zen |
| Grille vide +500 | Oui, **× le stage** | Comme Arcade |
| SAINTX +200 | Oui, **× le stage** | Comme Arcade |
| Auto-drop | Hasard **OK** (comme Arcade) | Colonne différente sans importance |
| Retry | **1 seule partie** / jour UTC | Bouton grisé « revenez demain » après GO |
| Fuseau | **UTC** | Un seul jour mondial |
| Continuer Arcade | Slot save **séparé** ; si défi **en cours**, les autres boutons → dialogue habituel d’abandon | Comme Duel/Zen vs Continuer |

---

## 4. Graine calendaire

- Clé jour : `YYYY-MM-DD` en **UTC** (tranché).
- `seed = hash("blomix-daily-v1" + date)` → `UInt64` (algorithme **documenté**, reproductible).
- La partie **verrouille** la date/seed au **lancement**. Un run commencé à 23:59 UTC se termine sur **cette** graine même après minuit.
- Version de format `v1` dans le hash : si on change le tirage Magix plus tard, les vieux scores ne se mélangent pas.

---

## 5. Points podium et les deux classements

**Tranché.** Podium **UTC, à la clôture du jour** (pas au Game Over) :

| Place du jour (score) | Points GC |
|---|---|
| 1er | **+5** |
| 2e | **+3** |
| 3e | **+1** |
| 4e et plus | **0** |

Moins de 3 joueurs : on attribue quand même 5 / 3 (s’il y a un 2e) / 1.  
Le board GC **`dailywins_arc`** (nom ASC `DailyWin_arc`) est un **cumul** de ces points (on soumet le total).

Le rang affiché **au GO** est le rang **live** (parmi ceux qui ont déjà fini). Il **n’est pas** encore les +5/+3/+1 : quelqu’un peut te passer après.

**Attribution :** pas de serveur BLOMIX, et Game Center **interdit** d’écrire le score d’un autre joueur.

| Surface | Source | Écriture | Doublon |
|---|---|---|---|
| Onglet in-app **Défi** | Recalcul +5/+3/+1 sur `DailyScore` des jours **clos** | **Aucune** (lecture) | Idempotent : 1 record CK / joueur / jour ; 1 podium / joueur / jour |
| Board GC `dailywins_arc` (5ᵉ disque) | `submitScore` **du joueur local** seulement | Local UserDefaults `credited_{day}` + total GC | Pas d’écriture du score d’un pair |

Ouvrir l’app (toi ou un autre) **ne rajoute pas** de points sur l’onglet in-app : chacun recalcule la même somme. Le 2e qui ouvre soumet **son** +3 à Game Center, ça ne touche pas tes +5.

Au lendemain (accueil / foreground / auth GC), le client parcourt les **14** derniers jours clos : s’il est 1/2/3 et n’a pas encore crédité ce `day`, il ajoute 5/3/1 **chez lui** puis `submitScore` du total GC.

| | Classement **du jour** (GO + bouton) | Classement **points défi** (GC, disque accueil) |
|---|---|---|
| Question | Mon **score** aujourd’hui | Mes **points podium** cumulés |
| Reset | Chaque jour UTC | Jamais (sauf board `_v2`) |
| Stockage | CloudKit `DailyScore` | Game Center `dailywins_arc` |

**Égalité de score (tranché) :** même score = même place, **mêmes points** (deux 1ers → +5 chacun ; le suivant est 3e +1, pas de 2e).

---

## 6. Architecture proposée (sans code)

```
Accueil ──Défi du jour──► GameScene (flag daily, RNG seedé)
                              │
                         Game Over daily
                              ├─ score local
                              ├─ Arcade : submitScore + moyenne (comme une partie Arcade)
                              ├─ CloudKit upsert score du jour (best-effort)
                              ├─ fetch rang (query date = jour verrouillé)
                              └─ (points 5/3/1 : au passage du jour UTC, voir §5)
```

- **Pas** de `protocolVersion` Duel.
- CloudKit : nouveau type (ex. `DailyScore`) — **schéma Public DB à créer en prod** (comme `AvailablePlayer`). Champs minimaux : `day` (String queryable), `score`, `displayName`, `won` (0/1), `gamePlayerID` dans le `recordName` (`daily_{day}_{gamePlayerID}`) pour que chacun n’écrive **que son** record.
- Permissions : même leçon PvP — on n’écrit que **son** record.
- Gate 503 (`BlomixPublicCloudGate`) : le GO s’affiche **quand même** (score local) ; rang = « — » si CK ko.
- GC non connecté : on joue, on stocke pending wins/score, flush à l’auth (comme Solo/Zen).

Eval (`BlomixMoveAnalyzer`) : ignore déjà les Magix. Recap GO **off** en Défi (écran simple).

---

## 7. Impact produit / technique

| Zone | Impact |
|---|---|
| `GameScene` | Flag mode daily + **même pipeline stage/timer/bombe qu’Arcade** ; file + lignes seedées ; auto-drop inchangé ; effets Magix hashés ; GO dédié |
| Accueil | Chip **Défi du jour** : sous Arcade, mêmes dimensions / style que le hero Arcade. 5ᵉ disque de rang (sous-titre défi), chiffres/libellés **même taille**, rangée un peu resserrée |
| Save | **Slot dédié** (ne pas écraser `blomix_solo_save_v2` Arcade/Zen) |
| `ScoreManager` / `LeaderboardViewController` | Score de la run → **aussi** Arcade (highscore `BlomixMainScore_v3` + moyenne). Onglet `dailywins_arc` = **uniquement** les points podium |
| CloudKit | Nouveau record type + index `day` ; Dashboard prod **et** dev |
| ASC | Créer le leaderboard victoires ; **pas** une version magasin tant qu’on reste en TF |
| l10n | Bouton, GO, vide, erreur CK, nom d’onglet — **5 langues** |
| Juice | Réutiliser tel quel |
| PvP / pastille Duel | Inchangés |

---

## 8. Décisions

### Figées

1. **Points** : 1er +5, 2e +3, 3e +1, le reste 0 ; égalité = mêmes points ; cumul GC. Crédit **après clôture UTC** (§5).  
2. **Retry** : une seule partie. Hub CTA **Revenez demain** après GO.  
3. **Fuseau** : UTC.  
4. **Layout accueil** : Arcade sous BLOMIX, chip Défi en dessous, style hero Arcade. 5ᵉ disque **défi** (carrière GC).  
5. **Chemin** : chip → **hub** (liste du jour + CTA Défi ! / Continuer / Revenez demain). Après GO, chip = **Classement du défi** → même hub. Disque ≠ hub.

### Figées (suite)

- Brix dans les lignes seedées : **comme Arcade**.  
- Magix effets : **hash d’événement** (ne consomme pas la file).  
- Chip **en cours** : même pattern qu’Arcade — titre + sous-titre **Continuer**.  
- Score de la run : **aussi** une partie Arcade (highscore + moyenne). Les deux classements défi (jour CK / podium GC) restent à part.  
- Look & feel : hub / GO = chrome existant (puits, capsules, cutout, Sombre/Clair). **Grille = `GameScene` habituelle** (pas une mini-grille).  
- ID GC : **`dailywins_arc`** (nom ASC `DailyWin_arc`). Classic, Integer, **Meilleur score**, plus haut = mieux.

---

## 9. Risques

| Risque | Mitigation |
|---|---|
| Un `Double.random` oublié (file, lignes, CHROMAX, remplacement Magix→couleur) | Inventaire unique : **file + effets Magix** seedés ; auto-drop hors de ça |
| Minuit / voyageur | Seed figée au start |
| Triche (rejouer, outil) | 7.1 : best-effort comme le reste ; pas d’anti-cheat serveur |
| GC « victoires » soumis dans le désordre | Toujours envoyer le **max** connu localement |
| Liste du jour vide au GO | Afficher le score + « 1er pour l’instant » / « rang indisponible » |
| Save Arcade écrasée | Clé séparée, Continuer Arcade inchangé |
| Layout accueil | Hero Défi + hero Arcade empilés + 5 disques : à valider visuellement (surtout iPhone mini / largeur) |

---

## 10. Implémentation (7.1)

Fichiers :

| Fichier | Rôle |
|---|---|
| `BlomixDailyRNG.swift` | File LCG + effets hashés (`blomix-daily-v1` FNV-1a 64) |
| `BlomixDailyChallenge.swift` | Slot `blomix_daily_save_v1`, CK `DailyScore`, podium +5/+3/+1, GC `dailywins_arc` |
| `BlomixDailyHubViewController.swift` | Hub du jour (liste + CTA) |

**CloudKit Dashboard (à faire une fois)** — Public DB, type `DailyScore` :

| Champ | Type | Index |
|---|---|---|
| `day` | String | Queryable |
| `score` | Int(64) | Sortable |
| `displayName` | String | — |
| `gamePlayerID` | String | — |

`recordName` = `daily_{YYYY-MM-DD}_{gamePlayerID}`. Déployer le schéma **Development → Production** (comme `AvailablePlayer`). Un run Xcode (Debug) tape **Development** ; TestFlight / App Store tapent **Production**.

**Prochaines étapes magasin** : 7.2 / 136 en review. Après OK Apple : **Release This Version** manuel dans ASC (`automatic_release: false`). Détail : [DEVELOPMENT.md](DEVELOPMENT.md) § Déploiement.

---

## 11. Ordre d’attaque (historique)

1. Figer §8 (surtout victoire + retry + fuseau).  
2. Maquette accueil + GO.  
3. RNG File + lignes + Magix kind ; test déterminisme **sans** UI.  
4. Brancher effets Magix sur hash d’événement ; même test avec CHROMAX/COLORX.  
5. Mode + save dédiée, GO minimal (score + Accueil).  
6. CloudKit rang du jour.  
7. Board GC victoires + onglet.  
8. l10n 5 langues, RULES, CHANGELOG, whats-new, Dashboard CK prod.

Lot 3–4 est le vrai risque « ce n’est pas la même partie ». Le reste est du chrome et de l’infra déjà vue (dispo CloudKit, ScoreManager).

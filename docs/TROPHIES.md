# BLOMIX — Pièce des trophées (piste)

> **Statut** : conception. **Pas de code.** À figer après tests Five + boards GC live.  
> **Version de référence** : 8.6  
> Vocabulaire : [GLOSSARY.md](GLOSSARY.md). Modes : [RULES.md](RULES.md). Magix : [MAGIX.md](MAGIX.md).

Un **cabinet personnel** : pastilles sur un mur, grisées ou allumées. On tape pour lire ce que ça veut dire, combien de fois, depuis quand. Ça n’est **pas** un classement, **pas** un 4ᵉ mode, **pas** des Achievements Game Center (v1).

But : donner une raison de **toucher à tout** le jeu (Arcade, Zen, Five, les deux Défis, Duel, Magix, bombes, partage) sans transformer BLOMIX en liste de quêtes.

---

## 1. Ce que le joueur voit

### Entrée

Rangée d’icônes accueil (aujourd’hui 5) : ajouter **une 6ᵉ**, SF Symbol `trophy.fill`, même chrome que Réglages / Tutoriel / Thème / Partager / Crédits.

| | Reco |
|---|---|
| Place | Entre **Partager** et **Crédits** (le cabinet est une vitrine, pas un réglage) |
| Caption | **Pièce** (court, comme « Thème ») — titre de l’écran = **Pièce des trophées** |
| Badge | Point ou chiffre **nouveau** sur l’icône tant qu’il reste des trophées débloqués non ouverts |

Si 6 icônes serrent trop le 40 mm : reculer `iconStep` (56 → ~50), pas une 2ᵉ rangée.

### L’écran (modal UIKit, famille Crédits / Score)

Fond scène + blox ambiants. Titre gouttière **Pièce des trophées**. Fermer en haut.

1. **Bandeau** : `23 / 64` + dernière pastille débloquée (nom + il y a …).
2. **Murs par catégorie** (titres cutout, comme les cartes Crédits).
3. **Grille de pastilles** 4 par rangée — même famille que les disques de rang accueil (diamètre ~52, trou gouttière, caption sous le disque).

Pas de SpriteKit pour cet écran : c’est de la lecture, pas de la pose.

### Pastille

| État | Visuel |
|---|---|
| **Verrouillée** (connue) | Disque chrome désaturé, α ~0,35, glyphe en silhouette. Caption lisible. |
| **Verrouillée cachée** | Disque vide, caption **???**. Le tap dit seulement « Réalisation secrète ». |
| **Débloquée** | Disque **peau** (comme un rang accueil). Glyphe clair. Halo Magix seulement si rareté **mythe**. |
| **Nouveau** | Souffle 1–2 cycles (même recette que les disques de rang), puis calme. |

Trois raretés, **langage BLOMIX** (pas bronze / argent / or Apple) :

| Rareté | Objet | Usage |
|---|---|---|
| **Blox** | Carré peau | Premier pas, volumes |
| **Brix** | Carré + chiffre | Seuils, séries, stages |
| **Magix** | Disque + couronne | Collection, exploits, secret |

### Fiche (tap)

Panneau bas, chrome capsule :

- Titre (Changa) + rareté
- Phrase **joueur** (ce qu’il a fait), pas le nom de fonction
- **×N** fois atteinte (même si N = 1)
- Première fois : date locale courte
- Si palier : barre `12 / 50` (gouttière peau, comme la jauge 0→N°1)
- Fermer : tap hors panneau ou bouton

Verrouillée connue : on **lit la condition**, compteur à 0, pas de date.  
Cachée : pas de spoiler.

---

## 2. Règles du catalogue

1. **Une pastille = une idée.** Pas « chaîne 5, 6, 7, 8, 9, 10 » en six disques — trois paliers max (5 / 8 / 10+).
2. **Chaque mode a au moins une porte d’entrée** (l’avoir joué) **et** une fierté (l’avoir *bien* joué).
3. **Les Magix ont chacun une pastille** : c’est le catalogue le plus riche et le plus ignoré.
4. **Compteur toujours.** Même « premier Duel » passera à ×2, ×3. La pièce vieillit avec le joueur.
5. **Peu de secrets** (8–10). Le reste est lisible grisé : ça *oriente*. Les secrets *récompensent* le folklore (5 bombes au GO, etc.).
6. **Pas de trophée qui force la triche** (score exact impossible, timer à 0 volontaire, forfait Duel).
7. **Pas d’Achievements App Store Connect en v1.** L’ASC est déjà occupée par `FiveMode` / `dailywins_five`. La pièce est **locale**. Un miroir GC pourra n’exporter que les Magix plus tard.
8. **Pas CloudKit, pas Watch.** Cabinet sur *cet* iPhone. (Plus tard : iCloud KV si on veut le meuble sur un second appareil.)
9. **Peu de rétroactif.** On crédite seulement ce qui est déjà sûr sans rejouer : highscores locaux Arcade / Zen / Five, points podium défi déjà en UserDefaults, tuto vu. Le reste commence au prochain événement. Le Défi Five d’aujourd’hui (avant CK) **ne** débloque **pas** « premier Défi Five » tant qu’on n’a pas un nouveau GO.

---

## 3. Catégories (murs)

Ordre dans la pièce = ordre d’exploration d’un joueur curieux, pas l’ordre technique.

| Mur | Glyphe de section | Pourquoi il est là |
|---|---|---|
| **Seuil** | Porte | Toucher chaque mode une fois |
| **Chaînes** | 5 carrés | Le cœur puzzle |
| **Magix** | Disque | Explorer les 9 kinds |
| **Arcade** | Timer | Stages, nuke, records |
| **Five** | 5 | Le nouveau mode, sans le diluer dans Zen |
| **Défi** | Jour | Les deux graines, podium, ghost |
| **Duel** | ⚔️ | Humain, local, bots |
| **Folie** | Bombe | Secrets, style, partage |

Hors v1 : skins « toutes les palettes » (liste instable), avis App Store (guideline), Watch.

---

## 4. Catalogue v1 (64 + 9 secrets)

IDs stables (`snake_case`) — ce sont les clés de save, pas des libellés joueur. Noms ci-dessous = **étiquette de design FR**.

× = compteur. Les paliers **empilent** (faire 10+ compte aussi pour 8 et pour 5).

### Seuil (8) — rareté Blox

| ID | Titre | Condition | Compte |
|---|---|---|---|
| `play_arcade` | Arcade | Une partie Arcade terminée (GO) | × parties |
| `play_zen` | Zen | Idem Zen | × |
| `play_five` | Five | Idem Five **libre** (pas le Défi) | × |
| `play_daily_arc` | Défi Arcade | GO classé d’un Défi Arcade | × jours |
| `play_daily_five` | Défi Five | GO classé d’un Défi Five | × jours |
| `play_duel` | Duel | Un match Duel **terminé** (victoire ou défaite, humain / local / bot) | × |
| `play_tutorial` | Tu sais tout | Tutoriel **mené au bout** (pas « Passer ») | ×1 suffit, compte les replays |
| `play_both_dailies` | Double journée | GO Défi Arcade **et** Défi Five le **même** jour UTC | × jours |

### Chaînes (9) — Blox / Brix

| ID | Titre | Condition | Rareté |
|---|---|---|---|
| `chain_5` | Cinq | Une chaîne ≥ 5 | Blox |
| `chain_8` | Huit | Une chaîne ≥ 8 | Brix |
| `chain_10` | Dix | Une chaîne ≥ 10 | Magix |
| `combo_2` | Cascade | Deux vagues dans la même résolution | Blox |
| `combo_5` | Série | Cinq vagues d’affilée (`chainSeriesLevel`) | Brix |
| `connect` | CONNECT | Bonus pont gauche–droite | Brix |
| `board_empty` | Vide | Bonus grille 100 % vide (+500) | Magix |
| `chains_100` | Cent | 100 chaînes en carrière (toutes tailles ≥ 5) | Brix |
| `chains_1000` | Mille | 1000 chaînes | Magix |

Hors Duel pour `board_empty` (le bonus n’existe pas). CONNECT et chaînes **comptent** en Duel.

### Magix (12) — une pastille par kind + collection

Poser le Magix **et** voir son effet (atterrissage). Duel : aucun (pas de Magix).

| ID | Titre | Kind |
|---|---|---|
| `magix_chromax` | CHROMAX | `.chromax` |
| `magix_brixed` | BRIXED | `.brixed` |
| `magix_crossx` | CROSSX | `.crosx` |
| `magix_slashx` | SLASHX | `.slashx` |
| `magix_scrumblx` | SCRUMBLX | `.scrumblx` |
| `magix_colorx` | COLORX | `.colorx` |
| `magix_saintx` | SAINTX | `.cleanx` |
| `magix_twistx` | TWISTX | `.twistx` |
| `magix_bombx` | BOMBX | `.bombx` |
| `magix_all_nine` | Cabinet Magix | Les 9 kinds au moins une fois chacun | Magix |
| `magix_saintx_ultime` | Infini ×6 | SAINTX posé en Arcade **Ultime** | Magix |
| `magix_bombx_stock` | Stock | BOMBX alors que le stock bombes était déjà à 5 | Brix |

Glyphe de pastille = **symbole Magix** déjà en jeu (`?` `9` `+` `X` `=` `O` `∞` `§` `B`).

### Arcade (8)

| ID | Titre | Condition | Rareté |
|---|---|---|---|
| `arcade_stage_2` | ×2 | Atteindre le stage 2 | Blox |
| `arcade_stage_4` | ×4 | Stage 4 | Brix |
| `arcade_ultime` | Ultime | Stage Ultime (×6, 1 s) | Magix |
| `arcade_nuke` | Nuke | Poser une bombe à partir du stage 2 (zone croix) | Brix |
| `arcade_score_1k` | Mille points | Score de run Arcade ≥ 1 000 | Blox |
| `arcade_score_5k` | Cinq mille | ≥ 5 000 | Brix |
| `arcade_score_10k` | Dix mille | ≥ 10 000 | Magix |
| `arcade_pb` | Record | Battre son RECORD Arcade (overlay PB) | Brix |

### Five (6)

Libre **ou** Défi Five, sauf mention.

| ID | Titre | Condition | Rareté |
|---|---|---|---|
| `five_lines_20` | Marée | 20 lignes Five injectées dans une run (100 poses) | Brix |
| `five_score_2k` | Five 2k | Score de run ≥ 2 000 | Brix |
| `five_pb` | Record Five | Battre son RECORD `FiveMode` | Brix |
| `five_no_bomb` | Mains nues | GO Five **sans avoir posé** une bombe (stock peut être < 5 si BOMBX / oubli… non : stock final quelconque, **zéro explosion**) | Brix |
| `five_preview` | Coup 4 | Avoir vu l’aperçu LIGNE 4/5 (presque automatique — plutôt : **survivre** 10 aperçus dans une run) | Blox |
| `five_empty` | Five vide | Grille vide en Five | Magix |

`five_preview` est trop gratuit tel quel → le tenir à **10 aperçus dans la même run** (50 poses, encore accessible).

### Défi (6)

| ID | Titre | Condition | Rareté |
|---|---|---|---|
| `daily_ghost_beat` | Référence | Score du jour **> Référence BLOMIX** (hub) | Magix |
| `daily_rank_1` | Jour 1 | Rang live 1 au GO (Arcade ou Five) | Magix |
| `daily_podium` | Podium | +5 / +3 / +1 crédité à la clôture (déjà calculé client) | Brix |
| `daily_streak_7` | Semaine | 7 jours UTC d’affilée avec **au moins un** des deux Défis fini | Magix |
| `daily_arc_10` | Dix Arcades | 10 Défis Arcade classés | Brix |
| `daily_five_10` | Dix Five | 10 Défis Five classés | Brix |

### Duel (8)

| ID | Titre | Condition | Rareté |
|---|---|---|---|
| `duel_win` | Victoire | Gagner un Duel | Blox |
| `duel_win_human` | Face à face | Victoire vs humain (GK ou Local), pas bot | Brix |
| `duel_win_local` | Table | Victoire en Local (Multipeer) | Brix |
| `duel_babybot` | BABYBOT | Victoire vs BABYBOT | Blox |
| `duel_bot1` | BOT1 | Victoire vs BOT1 | Magix |
| `duel_no_attack` | Pacifique | Victoire avec score de run **< 50** (aucune ligne d’attaque envoyée) | Magix |
| `duel_streak_3` | Série | 3 victoires d’affilée (tous adversaires) | Brix |
| `duel_10` | Dix duels | 10 matchs terminés | Blox |

### Folie (7 visibles + 9 secrets)

**Visibles**

| ID | Titre | Condition | Rareté |
|---|---|---|---|
| `share_home` | Avion | Partage depuis l’accueil (sheet présentée, pas forcément « posté ») | Blox |
| `share_go` | Carte | Partage depuis un GO (carte grille) | Blox |
| `theme_light` | Clair | Passer le chrome en Clair | Blox |
| `bomb_first` | Bombe | Première explosion | Blox |
| `continue_save` | Continuer | Reprendre une save (hero Arcade / chip Zen / Five / hub Défi) | Blox |
| `worst_move` | Pire coup | Ouvrir l’overlay « voir le pire coup » | Blox |
| `justesse_80` | Justesse | GO Arcade/Zen/Five avec optimalité ≥ 80 % (≥ 20 coups comptés) | Brix |

**Secrets** (caption ??? tant que verrouillé)

| ID | Titre une fois ouvert | Condition | Rareté |
|---|---|---|---|
| `secret_five_bombs` | Pacifiste | **GO avec 5 bombes encore en stock** (Arcade / Zen / Five). *L’exemple fondateur.* | Magix |
| `secret_zero_bombs` | Poudrière | GO avec **0** bombe et **au moins une** explosion dans la run | Brix |
| `secret_timeout` | Trop tard | Arcade : un auto-drop **sans visée maintenue** (colonne au hasard) | Blox |
| `secret_bomb_cancel` | Fausse alerte | Armer la bombe puis **annuler** (icône à nouveau) | Blox |
| `secret_duel_bomb_freeze` | Temps mort | En Duel, geler le timer en mode bombe **≥ 8 s** puis poser | Brix |
| `secret_line_go` | Trop plein | Game over **par la ligne** (injection / attaque), pas par pose | Brix |
| `secret_saintx_tiny` | Presque rien | SAINTX alors que la grille a **≤ 8** cases occupées | Magix |
| `secret_brixed_zero` | 9 solitaire | BRIXED alors qu’il n’y a **aucun** autre Brix | Brix |
| `secret_share_pb` | Vitrine | Partager un GO **avec bandeau record** | Brix |

Total v1 : **8+9+12+8+6+6+8+7 = 64** visibles, **9** secrets → **73** pastilles.

---

## 5. Graphisme (allure)

Pas des coupes 3D, pas de métal PlayStation. Le meuble **est** BLOMIX : puits, peau, Magix.

- **Mur** : même `sceneBackground` que Crédits ; blox ambiants plus lents, α un peu plus bas (cabinet).
- **Pastille** = `makeRankDiscNode` (ou équivalent UIKit) : cercle peau, chiffre/glyphe en **cutout** blanc, caption Nunito 9 pt sous le disque (comme ARC. / FIVE).
- **Verrou** : même disque, `BlomixAppearance.tertiaryText`, pas de peau.
- **Mythe débloquée** : couronne + 8–10 grains d’orbite **au tap de la fiche** (pas en permanence sur le mur — trop de CPU). Recette `spawnSpecialOrbitLingerSparks`.
- **Nouveau** : souffle des disques accueil, 2 cycles.
- **Bandeau compteur** : cutout `23/64`, pas une barre d’XP de RPG.
- **Fiche** : titre Changa, corps Nunito, ×N en gouttière (comme +5 du hub Défi).

Écran **portrait** uniquement. 4 colonnes tiennent le 40 mm si caption courte (un mot, Magix non traduit).

---

## 6. Technique (quand on coderait — pas maintenant)

Hook **un** point par famille d’événements, pas 73 `if` dans `resolveChains` :

| Hook | Où (existant) | Alimente |
|---|---|---|
| `onChainResolved` | fin de vague `resolveChains` | chaînes, combo, CONNECT, vide |
| `onMagixLanded` | `applyMagixEffect` | 9 kinds + collection + SAINTX Ultime |
| `onBombExploded` / `onBombCancelled` | explosion / annulation | nuke, folie, secrets |
| `onStageEntered` | overlay stage Arcade | ×2 / ×4 / Ultime |
| `onGameOver` | `triggerGameOver` + overlay PB | modes, scores, 5 bombes, justesse, ligne GO |
| `onDailyFinished` | `finishRun` | défis, double journée, rang |
| `onPodiumCredited` | crédit +5/+3/+1 | podium |
| `onPvPSettled` | résultat Duel (humain / local / bot) | mur Duel |
| `onSharePresented` | share sheet accueil / GO | avion, carte, vitrine |
| `onChromeToggled` | toggle Clair | thème |
| `onSaveResumed` | Continuer | continue_save |
| `onTutorialFinished` | dernière étape tuto | play_tutorial |

Store : un JSON UserDefaults `blomix_trophies_v1` `{ id: { count, firstAt, lastAt, seen } }`. Compteur **monotone**. Pas de reset (sauf debug).

UI : `BlomixTrophyRoomViewController` + `BlomixL10n` (6 langues, Magix non traduits). Guide : une carte dans le tutoriel **écrit** (livre), pas le tuto interactif.

Hors scope v1 : Game Center Achievements, CloudKit, Watch, skins, reset joueur, notifications « tu as débloqué » **en cours de partie** (ça casse le flow). Toast **au retour accueil** si déblocage pendant la run : une ligne sous les icônes, tap → pièce, focus la pastille.

---

## 7. Ce qu’on ne fait pas

- Quêtes du jour qui reset (on a déjà les Défis).
- XP / niveaux / battle pass.
- Trophées « joue 7 jours de suite n’importe quoi » (le streak **Défi** suffit).
- Révéler les secrets dans le guide.
- Forcer un Duel humain pour « finir » la pièce (BOT1 est le plafond solo).
- Compter le tutoriel « Passer » comme `play_tutorial`.

---

## 8. Décisions à figer avec toi

1. **Nom d’écran** : *Pièce des trophées* (reco) vs *Réalisations* vs *Cabinet*.
2. **6ᵉ icône accueil** vs entrée depuis Crédits (plus discret, moins exploré).
3. **73 pastilles v1** : trop / trop peu ? On peut shipper Seuil + Magix + Folie d’abord (~30).
4. **Rétroactif** : d’accord pour le peu (hiscores, podium déjà crédité, tuto) ?
5. **Toast accueil** après une run, ou seulement le badge sur l’icône ?
6. **Secrets** : 9, c’est le bon folklore, ou on en cache davantage (GO 5 bombes seulement) ?

---

## 9. Ordre de code (plus tard)

1. Store + hooks GO / modes (Seuil) — on *voit* la pièce.
2. Mur Magix + Chaînes (hooks déjà au bon endroit).
3. Arcade / Five / Défi / Duel.
4. Folie + secrets.
5. l10n 6 langues, guide, GLOSSARY, CHANGELOG, whats-new au jalon.

Aucun de ces points avant : Five testé, `FiveMode` / `dailywins_five` live, pièce **validée** sur cette spec.

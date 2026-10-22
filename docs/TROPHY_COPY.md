# BLOMIX — Copie des trophées (brouillon)

> **Ce fichier n’est pas lu par le jeu.** C’est le bac à sable pour les mots et les chiffres.  
> Quand c’est prêt : *« implémente TROPHY_COPY »* — l’agent recopie vers le catalogue Swift + `BlomixL10n` / `.lproj`.  
> Spec mécanique / dessin : [TROPHIES.md](TROPHIES.md). Ne pas y mélanger la copie.  
> Jalon 8.8 : copie assez bonne (ou décision de reporter) au **4 nov. 2026** — [RELEASE_8.8.md](RELEASE_8.8.md).

**Pourquoi pas un JSON ?** Un JSON irait pour un import automatique. Ici on peaufine des **noms**, des **phrases** et des **notes** en français, souvent sur GitHub : le Markdown se lit, se commente, s’édite. Les `id` restent stables ; le reste est à toi.

---

## Comment remplir

| Champ | Rôle |
|---|---|
| `id` | **Ne pas renommer** (c’est le code). |
| courbe | `volume` 1 / n2 / n3 · `rare` 1 / 3 / 10 · `quality` n1 / n2 / n3 (max, pas un compte) · `unique` 0 ou 1 |
| seuils | **0** = rien fait · **n1** = I · **n2** = II · **n3** = III. Unique : seulement 0 / 1. |
| **nom** | Un seul mot **sous la cible**, du 0 jusqu’à III (et après III tant qu’il n’y a pas 3 étoiles). |
| **maître** | Le mot sous la cible **seulement** quand les **3 étoiles** sont pleines (`n ≥ 3 × n3`). Unique : `—` (pas d’étoiles). |
| aujourd’hui | Libellé mécanique actuel (référence, pas le nom joueur). |
| phrase | Texte de la **fiche** (ce que c’est). Une phrase. |
| notes | Pistes, variantes — l’agent ignore tant que tu n’as pas dit d’implémenter. |

Les I / II / III se lisent sur la **cible** (tours, chiffre). Le nom dessous **ne change pas** à chaque palier.

Magix : le **nom propre** (CHROMAX, …) **ne se traduit pas**. Souvent `nom` = le glyphe ; `maître` = un mot à toi, ou le même.

Les `…` sont vides exprès. Tu peux coller « aujourd’hui » dans `nom`, inventer `maître` ensuite.

---

## Murs (catégories)

Un nom par mur. Cutout au-dessus de la grille.

| id | aujourd’hui | nom |
|---|---|---|
| `seuil` | Seuil | |
| `chaines` | Chaînes | |
| `magix` | Magix | |
| `arcade` | Arcade | |
| `five` | Five | |
| `defi` | Défi | |
| `duel` | Duel | |
| `folie` | Folie | |

---

## Trophées

### Seuil

#### `play_arcade`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Arcade
- nom : …
- maître : …
- phrase : Termine une partie Arcade.
- notes :

#### `play_zen`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Zen
- nom : …
- maître : …
- phrase : Termine une partie Zen.
- notes :

#### `play_five`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Five
- nom : …
- maître : …
- phrase : Termine une partie Five libre.
- notes :

#### `play_daily_arc`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Défi Arcade
- nom : …
- maître : …
- phrase : Classe un Défi Arcade.
- notes :

#### `play_daily_five`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Défi Five
- nom : …
- maître : …
- phrase : Classe un Défi Five.
- notes :

#### `play_duel`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Duel
- nom : …
- maître : …
- phrase : Termine un Duel, gagné ou perdu.
- notes :

#### `play_tutorial`
- courbe : unique
- seuils : 0 · **1**
- aujourd’hui : Tu sais tout
- nom : …
- maître : —
- phrase : Va au bout du tutoriel (sans Passer).
- notes :

#### `play_both_dailies`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Double journée
- nom : …
- maître : …
- phrase : Les deux Défis le même jour.
- notes :

---

### Chaînes

#### `chain_size`
- courbe : quality
- seuils : 0 · **5** · **8** · **10**
- aujourd’hui : Chaîne
- nom : …
- maître : …
- phrase : Plus grande chaîne : 5, puis 8, puis 10+.
- notes : centre = le max, pas un compte.

#### `chain_count`
- courbe : volume
- seuils : 0 · **1** · **100** · **1000**
- aujourd’hui : Encore
- nom : …
- maître : …
- phrase : Chaînes de 5 ou plus.
- notes :

#### `combo`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Super combo
- nom : …
- maître : …
- phrase : Une résolution à au moins 2 vagues.
- notes :

#### `combo_deep`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Série
- nom : …
- maître : …
- phrase : Une résolution à au moins 5 vagues.
- notes :

#### `connect`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : CONNECT
- nom : …
- maître : …
- phrase : Un pont gauche–droite.
- notes : glyphe CONNECT, comme un Magix (non traduit ?).

#### `board_empty`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Vide
- nom : …
- maître : …
- phrase : Vide la grille (+500).
- notes :

---

### Magix

Noms propres **non traduits**. `magix_all_nine` et `magix_saintx_ultime` n’en sont pas.

#### `magix_chromax`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : CHROMAX
- nom : …
- maître : …
- phrase : Pose un CHROMAX.
- notes :

#### `magix_brixed`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : BRIXED
- nom : …
- maître : …
- phrase : Pose un BRIXED.
- notes :

#### `magix_crossx`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : CROSSX
- nom : …
- maître : …
- phrase : Pose un CROSSX.
- notes :

#### `magix_slashx`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : SLASHX
- nom : …
- maître : …
- phrase : Pose un SLASHX.
- notes :

#### `magix_scrumblx`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : SCRUMBLX
- nom : …
- maître : …
- phrase : Pose un SCRUMBLX.
- notes :

#### `magix_colorx`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : COLORX
- nom : …
- maître : …
- phrase : Pose un COLORX.
- notes :

#### `magix_saintx`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : SAINTX
- nom : …
- maître : …
- phrase : Pose un SAINTX.
- notes :

#### `magix_twistx`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : TWISTX
- nom : …
- maître : …
- phrase : Pose un TWISTX.
- notes :

#### `magix_bombx`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : BOMBX
- nom : …
- maître : …
- phrase : Pose un BOMBX.
- notes :

#### `magix_all_nine`
- courbe : quality
- seuils : 0 · **1** · **5** · **9**
- aujourd’hui : Cabinet Magix
- nom : …
- maître : …
- phrase : Les 9 Magix au moins une fois.
- notes : centre = combien de kinds distincts.

#### `magix_saintx_ultime`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Infini ×6
- nom : …
- maître : …
- phrase : SAINTX en Stage Ultime.
- notes :

---

### Arcade

#### `arcade_stage`
- courbe : quality
- seuils : 0 · **2** · **4** · **6**
- aujourd’hui : Stage
- nom : …
- maître : …
- phrase : Atteins le Stage 2, 4, puis Ultime.
- notes : 6 = Ultime (index 5).

#### `arcade_nuke`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Nuke
- nom : …
- maître : …
- phrase : Pose une bombe à partir du Stage 2.
- notes :

#### `arcade_score`
- courbe : quality
- seuils : 0 · **1000** · **5000** · **10000**
- aujourd’hui : Score
- nom : …
- maître : …
- phrase : Meilleur score Arcade : 1k, 5k, 10k.
- notes :

#### `arcade_pb`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Record
- nom : …
- maître : …
- phrase : Ouvre l’overlay RECORD Arcade.
- notes :

#### `arcade_ultime_count`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Une seconde
- nom : …
- maître : …
- phrase : Atteins le Stage Ultime.
- notes :

---

### Five

#### `five_lines`
- courbe : quality
- seuils : 0 · **5** · **20** · **50**
- aujourd’hui : Marée
- nom : …
- maître : …
- phrase : Lignes Five dans une run : 5, 20, 50.
- notes :

#### `five_score`
- courbe : quality
- seuils : 0 · **500** · **2000** · **5000**
- aujourd’hui : Score Five
- nom : …
- maître : …
- phrase : Meilleur score Five : 500, 2k, 5k.
- notes :

#### `five_pb`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Record Five
- nom : …
- maître : …
- phrase : Ouvre l’overlay RECORD Five.
- notes :

#### `five_no_bomb`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Mains nues
- nom : …
- maître : …
- phrase : Termine un Five sans explosion.
- notes :

#### `five_empty`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Five vide
- nom : …
- maître : …
- phrase : Vide la grille en Five.
- notes :

---

### Défi

#### `daily_ghost_beat`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Référence
- nom : …
- maître : …
- phrase : Dépasse la Référence BLOMIX.
- notes :

#### `daily_rank_1`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Jour 1
- nom : …
- maître : …
- phrase : Rang 1 au GO d’un Défi.
- notes :

#### `daily_podium`
- courbe : volume
- seuils : 0 · **1** · **10** · **50**
- aujourd’hui : Podium
- nom : …
- maître : …
- phrase : Podiums Défi crédités.
- notes :

#### `daily_streak`
- courbe : quality
- seuils : 0 · **3** · **7** · **30**
- aujourd’hui : Semaine
- nom : …
- maître : …
- phrase : Jours d’affilée avec un Défi fini.
- notes :

#### `daily_days`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Habitude
- nom : …
- maître : …
- phrase : Jours distincts avec un Défi classé.
- notes :

---

### Duel

#### `duel_win`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Victoire
- nom : …
- maître : …
- phrase : Gagne un Duel.
- notes :

#### `duel_win_human`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Face à face
- nom : …
- maître : …
- phrase : Gagne contre un humain.
- notes :

#### `duel_win_local`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Table
- nom : …
- maître : …
- phrase : Gagne un Duel en local.
- notes :

#### `duel_babybot`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : BABYBOT
- nom : …
- maître : …
- phrase : Gagne contre BABYBOT.
- notes : nom propre bot.

#### `duel_bot1`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : BOT1
- nom : …
- maître : …
- phrase : Gagne contre BOT1.
- notes : nom propre bot.

#### `duel_no_attack`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Pacifique
- nom : …
- maître : …
- phrase : Gagne un Duel avec un score < 50.
- notes :

#### `duel_streak`
- courbe : quality
- seuils : 0 · **3** · **5** · **10**
- aujourd’hui : Série
- nom : …
- maître : …
- phrase : Série de victoires Duel : 3, 5, 10.
- notes :

---

### Folie

#### `share_home`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Avion
- nom : …
- maître : …
- phrase : Partage depuis l’accueil.
- notes :

#### `share_go`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Carte
- nom : …
- maître : …
- phrase : Partage une carte de game over.
- notes :

#### `theme_light`
- courbe : unique
- seuils : 0 · **1**
- aujourd’hui : Clair
- nom : …
- maître : —
- phrase : Passe le chrome en Clair.
- notes :

#### `bomb`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Bombe
- nom : …
- maître : …
- phrase : Fais exploser une bombe.
- notes :

#### `continue_save`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Continuer
- nom : …
- maître : …
- phrase : Reprend une partie sauvegardée.
- notes :

#### `worst_move`
- courbe : volume
- seuils : 0 · **1** · **10** · **100**
- aujourd’hui : Pire coup
- nom : …
- maître : …
- phrase : Ouvre l’overlay du pire coup.
- notes :

#### `justesse`
- courbe : quality
- seuils : 0 · **80** · **90** · **100**
- aujourd’hui : Justesse
- nom : …
- maître : …
- phrase : Justesse de fin de partie : 80, 90, 100 %.
- notes : centre = le %.

---

### Secrets (mur Folie, caption `???` tant que 0)

Une fois ouverts : `nom` sous la cible, `maître` à 3 étoiles, + phrase. Tant que 0 : mur = `???` (ne pas révéler `nom`).

#### `secret_five_bombs`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Pacifiste
- nom : …
- maître : …
- phrase : Termine avec 5 bombes en stock.
- notes :

#### `secret_zero_bombs`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Poudrière
- nom : …
- maître : …
- phrase : Termine à 0 bombe après au moins une explosion.
- notes :

#### `secret_timeout`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Trop tard
- nom : …
- maître : …
- phrase : Auto-drop Arcade sans visée.
- notes :

#### `secret_bomb_cancel`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Fausse alerte
- nom : …
- maître : …
- phrase : Arme puis annule la bombe.
- notes :

#### `secret_duel_bomb_freeze`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Temps mort
- nom : …
- maître : …
- phrase : En Duel, reste en mode bombe 8 s puis pose.
- notes :

#### `secret_line_go`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Trop plein
- nom : …
- maître : …
- phrase : Game over par la ligne, pas par une pose.
- notes :

#### `secret_saintx_tiny`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Presque rien
- nom : …
- maître : …
- phrase : SAINTX sur 8 cases occupées ou moins.
- notes :

#### `secret_brixed_zero`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : 9 solitaire
- nom : …
- maître : …
- phrase : BRIXED sans autre Brix sur la grille.
- notes :

#### `secret_share_pb`
- courbe : rare
- seuils : 0 · **1** · **3** · **10**
- aujourd’hui : Vitrine
- nom : …
- maître : …
- phrase : Partage un GO avec bandeau record.
- notes :

# BLOMIX — 20 réalisations Game Center (9.0, créées dans App Store Connect)

> Statut : **validé par Lomig et créé dans App Store Connect le 20/11/2026** : 20 réalisations, 120 localisations (6 langues), vérifiées par GET.
> Images 1024×1024 ajoutées le 20/11/2026 pour les 120 localisations (section 0 bis).
> Le 20/11/2026 au soir, les 20 versions et la version **9.0** (build **167**) sont dans le brouillon de review iOS `bce8572c-c5f7-4587-a7a8-eeeb56a25afa` (Ready for Review, `submittedDate` vide). Rien n’est parti chez Apple. Elles ne sont pas visibles des joueurs.
> Source analysée : 8.9 publique (`blomig/BLOMIX`, commit c990254), `BlomixTrophyStore.swift`, `GameScene.swift`, `docs/TROPHIES.md`, `docs/RULES.md`, `docs/MAGIX.md`.
> Rédigé le 20/11/2026.

Principe : **chaque réalisation lit un compteur du Salon des trophées** (`BlomixTrophyStore`, clé `blomix_trophies_v1`). Aucune nouvelle logique de jeu : on ajoute seulement une couche qui traduit les valeurs du Salon en `GKAchievement`. Comme ces compteurs sont déjà enregistrés, les joueurs actuels récupèrent automatiquement ce qu'ils ont déjà accompli dès la première synchro (tuto terminé, Stage atteint, série de défis, etc.).

Répartition : 5 faciles · 6 moyennes · 5 difficiles · 3 expertes · 1 légendaire. 2 cachées. **Total : 930 points** (sur 1 000 autorisés ; on garde 70 points pour la suite).

---

## 0. Identifiants App Store Connect

gameCenterDetail : `b4d3ac30-27a9-490d-b6d4-afc3eeb1cbb4` (app 6762053543). Localisations : `fr-FR`, `en-US`, `es-ES`, `it`, `de-DE`, `pt-BR` (alignées sur la fiche App Store).

| # | vendorIdentifier (ID Game Center à utiliser dans le code) | ID ASC | Pts | Visible avant obtention |
|---|---|---|---|---|
| 1 | `blomix.ach.first_chain` | `04acb0a0-03fb-437a-ba8c-7972fc49cbf7` | 10 | oui |
| 2 | `blomix.ach.first_bomb` | `56f4e9fd-5b00-4b8f-8312-5066b5df9dd0` | 10 | oui |
| 3 | `blomix.ach.tutorial` | `37866f2e-a4da-4c60-be10-1ba0121a52d0` | 10 | oui |
| 4 | `blomix.ach.first_magix` | `0ee2db56-d4e4-4847-98b8-2d654e816950` | 15 | oui |
| 5 | `blomix.ach.pacifist` | `8a3a434e-0d88-4f71-b990-691f2549c66d` | 15 | non (cachée) |
| 6 | `blomix.ach.super_combo` | `622efb60-02df-4434-8887-38a8a6a974b0` | 25 | oui |
| 7 | `blomix.ach.stage_3` | `c324b427-2b2b-4250-b64b-22ead37e07a1` | 30 | oui |
| 8 | `blomix.ach.duel_win` | `b91ad582-94b7-4b43-89bf-c718807686a2` | 30 | oui |
| 9 | `blomix.ach.daily_streak_3` | `f38feaab-3847-4036-8ffb-33a2c88e3eaa` | 30 | oui |
| 10 | `blomix.ach.five_tide_20` | `359fe12d-aabd-4e0e-a629-c68bb3fa9fe3` | 35 | oui |
| 11 | `blomix.ach.zen_2000` | `06cfd5d1-3548-434f-acb5-fb0d2381a790` | 30 | oui |
| 12 | `blomix.ach.stage_ultime` | `c38a06d1-4663-4ed1-84b7-1158686341ff` | 60 | oui |
| 13 | `blomix.ach.chain_10` | `70a2cf24-d87a-4915-91bb-60f37d3febe8` | 60 | oui |
| 14 | `blomix.ach.magix_all_nine` | `cbf0f09e-5a6e-4abf-941a-88fcf476e797` | 70 | oui |
| 15 | `blomix.ach.daily_streak_7` | `63d3f274-279e-447a-860c-3bb866094c89` | 60 | oui |
| 16 | `blomix.ach.trophies_30` | `d0074c4a-f4a8-46d0-b393-c491941b122c` | 60 | oui |
| 17 | `blomix.ach.arcade_10k` | `52fe10b8-8c1e-4f74-b061-347cb7e8a54d` | 90 | oui |
| 18 | `blomix.ach.combo_deep` | `e434b854-67be-4c49-9995-222e5d050007` | 90 | oui |
| 19 | `blomix.ach.daily_streak_30` | `6cde7fb8-1ad8-438c-a349-8b6e749cbe82` | 100 | oui |
| 20 | `blomix.ach.saintx_ultime` | `342b76d2-bc29-46d4-8466-c6ba33826a0f` | 100 | non (cachée) |

---
## 0 bis. Images des réalisations

1024×1024, JPEG RGB sans transparence. La même image est utilisée pour les 6 langues de chaque réalisation. Envoyées dans App Store Connect le 20/11/2026.

- Box : `/workspace/blomix/gamecenter/images/`
- Mac : `~/Developer/BLOMIX-9.0/docs/gamecenter/images/`
- Planche récapitulative : `images/planche.jpg`

| # | Réalisation | Fichier |
|---|---|---|
| 1 | Première chaîne (`blomix.ach.first_chain`) | `images/gc_01_first_chain.jpg` |
| 2 | Boum ! (`blomix.ach.first_bomb`) | `images/gc_02_bomb.jpg` |
| 3 | Tu sais tout (`blomix.ach.tutorial`) | `images/gc_03_tutorial.jpg` |
| 4 | Abracadabra (`blomix.ach.first_magix`) | `images/gc_04_magix.jpg` |
| 5 | Pacifiste (`blomix.ach.pacifist`) | `images/gc_05_pacifist.jpg` |
| 6 | Super combo (`blomix.ach.super_combo`) | `images/gc_06_combo.jpg` |
| 7 | Stage 3 (`blomix.ach.stage_3`) | `images/gc_07_stage3.jpg` |
| 8 | Premier duel gagné (`blomix.ach.duel_win`) | `images/gc_08_duel.jpg` |
| 9 | Trois jours de suite (`blomix.ach.daily_streak_3`) | `images/gc_09_streak3.jpg` |
| 10 | Marée haute (`blomix.ach.five_tide_20`) | `images/gc_10_tide.jpg` |
| 11 | Esprit zen (`blomix.ach.zen_2000`) | `images/gc_11_zen.jpg` |
| 12 | Stage Ultime (`blomix.ach.stage_ultime`) | `images/gc_12_ultimate.jpg` |
| 13 | Chaîne de 10 (`blomix.ach.chain_10`) | `images/gc_13_chain10.jpg` |
| 14 | Cabinet Magix (`blomix.ach.magix_all_nine`) | `images/gc_14_magix9.jpg` |
| 15 | Une semaine de défis (`blomix.ach.daily_streak_7`) | `images/gc_15_streak7.jpg` |
| 16 | Salon des trophées (`blomix.ach.trophies_30`) | `images/gc_16_salon.jpg` |
| 17 | 10 000 en Arcade (`blomix.ach.arcade_10k`) | `images/gc_17_arcade10k.jpg` |
| 18 | Cascade infernale (`blomix.ach.combo_deep`) | `images/gc_18_cascade.jpg` |
| 19 | Un mois de défis (`blomix.ach.daily_streak_30`) | `images/gc_19_streak30.jpg` |
| 20 | Infini ×6 (`blomix.ach.saintx_ultime`) | `images/gc_20_infinity.jpg` |

---
## 1. Tableau récapitulatif

| # | Identifiant | Nom FR | Nom EN | Condition | Difficulté | Pts | Cachée | % joueurs attendu |
|---|---|---|---|---|---|---|---|---|
| 1 | `blomix.ach.first_chain` | Première chaîne | First Chain | 1 chaîne de 5 (diagonales comprises) | Facile | 10 | Non | 90 % |
| 2 | `blomix.ach.first_bomb` | Boum ! | Kaboom! | 1 bombe explosée | Facile | 10 | Non | 80 % |
| 3 | `blomix.ach.tutorial` | Tu sais tout | Fully Trained | Tutoriel terminé jusqu'au bout | Facile | 10 | Non | 50 % |
| 4 | `blomix.ach.first_magix` | Abracadabra | Abracadabra | 1 Magix déclenché | Facile | 15 | Non | 60 % |
| 5 | `blomix.ach.pacifist` | Pacifiste | Pacifist | Game over avec ≥ 5 bombes en stock | Facile | 15 | **Oui** | 45 % |
| 6 | `blomix.ach.super_combo` | Super combo | Super Combo | 1 cascade (≥ 2 vagues) | Moyenne | 25 | Non | 50 % |
| 7 | `blomix.ach.stage_3` | Stage 3 | Stage 3 | Stage 3 en Arcade (1 000 pts) | Moyenne | 30 | Non | 35 % |
| 8 | `blomix.ach.duel_win` | Premier duel gagné | First Duel Win | 1 Duel gagné (humain ou bot) | Moyenne | 30 | Non | 25 % |
| 9 | `blomix.ach.daily_streak_3` | Trois jours de suite | Three-Day Streak | Série de 3 jours de défi | Moyenne | 30 | Non | 18 % |
| 10 | `blomix.ach.five_tide_20` | Marée haute | High Tide | 20 lignes encaissées dans 1 partie Five | Moyenne | 35 | Non | 20 % |
| 11 | `blomix.ach.zen_2000` | Esprit zen | Zen Mind | 2 000 pts en Zen | Moyenne | 30 | Non | 20 % |
| 12 | `blomix.ach.stage_ultime` | Stage Ultime | Ultimate Stage | Stage Ultime en Arcade (5 000 pts) | Difficile | 60 | Non | 5 % |
| 13 | `blomix.ach.chain_10` | Chaîne de 10 | Chain of 10 | 1 chaîne d'au moins 10 blox | Difficile | 60 | Non | 8 % |
| 14 | `blomix.ach.magix_all_nine` | Cabinet Magix | Magix Cabinet | Les 9 Magix déclenchés | Difficile | 70 | Non | 5 % |
| 15 | `blomix.ach.daily_streak_7` | Une semaine de défis | Week-Long Streak | Série de 7 jours de défi | Difficile | 60 | Non | 5 % |
| 16 | `blomix.ach.trophies_30` | Salon des trophées | Trophy Lounge | 30 trophées visibles allumés | Difficile | 60 | Non | 7 % |
| 17 | `blomix.ach.arcade_10k` | 10 000 en Arcade | 10,000 in Arcade | Score Arcade ≥ 10 000 | Experte | 90 | Non | 1,5 % |
| 18 | `blomix.ach.combo_deep` | Cascade infernale | Chain Reaction | 1 cascade de ≥ 5 vagues | Experte | 90 | Non | 2 % |
| 19 | `blomix.ach.daily_streak_30` | Un mois de défis | Month-Long Streak | Série de 30 jours de défi | Experte | 100 | Non | 1 % |
| 20 | `blomix.ach.saintx_ultime` | Infini ×6 | Infinity ×6 | SAINTX au Stage Ultime | Légendaire | 100 | **Oui** | < 0,5 % |

**Total : 930 points.** Faciles 60 · Moyennes 180 · Difficiles 310 · Expertes 280 · Légendaire 100.

Couverture : Arcade (7, 12, 17, 20), Zen (11), Five (10), Défi du jour et séries (9, 15, 19), Duel (8), tutoriel (3), bombes (2, 5), Magix (4, 14, 20), chaînes et cascades (1, 6, 13, 18), collection (16).

Les pourcentages sont des **estimations** (aucune donnée par trophée dans la télémétrie). À recalibrer après quelques semaines avec les pourcentages que Game Center affiche lui-même.

---

## 2. Fiches détaillées

Champs communs à toutes : **réalisable plusieurs fois : non**. Le compteur est lu dans `BlomixTrophyStore.shared.progress(for: id).value`, sauf mention contraire. Tous ces compteurs ignorent le tutoriel (`!isTutorialMode`), sauf le n° 3.

### 1. Première chaîne — `blomix.ach.first_chain`
- **EN** : First Chain
- **Avant** FR : « Aligne 5 blox de la même couleur (les diagonales comptent). » / EN : « Line up 5 blox of the same color (diagonals count). »
- **Après** FR : « Ta première chaîne de 5 ! La première d'une longue série. » / EN : « Your first chain of 5! The first of many. »
- **Points** : 10 · **Cachée** : non · **Difficulté** : facile · **Attendu** : 90 %
- **Condition** : trophée `chain_count` ≥ 1. Alimenté par `BlomixTrophyHooks.noteChainWave(sizes:seriesLevel:connectCount:)` (`BlomixTrophyStore.swift`), appelé dans `GameScene.swift` (~l. 8342) à chaque vague de résolution. Compte aussi en Duel.

### 2. Boum ! — `blomix.ach.first_bomb`
- **EN** : Kaboom!
- **Avant** FR : « Fais exploser ta première bombe. » / EN : « Set off your first bomb. »
- **Après** FR : « Première bombe posée. Ça fait du bien, non ? » / EN : « First bomb dropped. Feels good, right? »
- **Points** : 10 · **Cachée** : non · **Difficulté** : facile · **Attendu** : 80 %
- **Condition** : trophée `bomb` ≥ 1. `BlomixTrophyHooks.noteBomb(isNuke:brixBroken:)`, appelé dans `GameScene.swift` (~l. 14319) après `applyBombExplosion3x3`. Hors tutoriel.

### 3. Tu sais tout — `blomix.ach.tutorial`
- **EN** : Fully Trained
- **Avant** FR : « Va jusqu'au bout du tutoriel. » / EN : « Finish the tutorial all the way through. »
- **Après** FR : « Tutoriel terminé : tu connais toutes les règles. » / EN : « Tutorial complete: you know all the rules. »
- **Points** : 10 · **Cachée** : non · **Difficulté** : facile · **Attendu** : 50 %
- **Condition** : trophée `play_tutorial` ≥ 1 (unique). `BlomixTrophyHooks.noteTutorialFinished()`, appelé dans `GameScene.swift` (~l. 18059) à la fin de l'étape `.bombCelebration`. « Passer » ne compte pas.
- **Remarque** : utile pour la v9 et la pédagogie, puisque la réalisation pousse à finir le tuto. La télémétrie ne mesure toujours pas la fin du tuto (le prompt « 7 points » de la v9 le prévoit). La réalisation, elle, s'appuie sur le trophée, qui existe déjà.

### 4. Abracadabra — `blomix.ach.first_magix`
- **EN** : Abracadabra
- **Avant** FR : « Déclenche ton premier Magix. » / EN : « Trigger your first Magix. »
- **Après** FR : « Ton premier Magix ! Il y en a 9 en tout : à toi de tous les trouver. » / EN : « Your first Magix! There are 9 in all. Find them all. »
- **Points** : 15 · **Cachée** : non · **Difficulté** : facile · **Attendu** : 60 %
- **Condition** : trophée `magix_all_nine` ≥ 1 (nombre de types distincts déclenchés, recalculé par `BlomixTrophyStore.refreshDerivedMagixCollection()`). Alimenté par `BlomixTrophyHooks.noteMagix(...)`, appelé dans `GameScene.swift` (~l. 12004). Pas de Magix en Duel. Environ 2,9 % des pièces sont des Magix, donc la plupart des joueurs en voient un en quelques parties.

### 5. Pacifiste — `blomix.ach.pacifist` (cachée)
- **EN** : Pacifist
- **Avant** FR : « Termine une partie avec au moins 5 bombes en stock. » / EN : « End a game with at least 5 bombs in stock. »
- **Après** FR : « Perdu avec 5 bombes en poche… La prochaine fois, fais tout sauter ! » / EN : « Game over with 5 bombs in your pocket… Next time, blow it all up! »
- **Points** : 15 · **Cachée** : **oui** · **Difficulté** : facile (souvent obtenue par accident) · **Attendu** : 45 %
- **Condition** : trophée secret `secret_five_bombs` ≥ 1. `GameScene.noteTrophiesAtGameOver(finalScore:)` (~l. 5729) : `if bombCount >= 5`. En solo, on démarre avec 5 bombes (`bombCount = 5`, ~l. 2144), donc il suffit de n'en poser aucune, ou de les récupérer avec BOMBX. S'applique en Arcade, Zen, Five et Défi.
- **Remarque** : c'est un clin d'œil au joueur qui a perdu « 7 bombes en poche ». C'est aussi pédagogique : la réalisation rappelle que les bombes sont faites pour servir.

### 6. Super combo — `blomix.ach.super_combo`
- **EN** : Super Combo
- **Avant** FR : « Déclenche une cascade : une chaîne qui en provoque une autre. » / EN : « Trigger a cascade: one chain setting off another. »
- **Après** FR : « Ta première cascade ! Les blox tombent, et ça repart. » / EN : « Your first cascade! Blox fall and it all goes again. »
- **Points** : 25 · **Cachée** : non · **Difficulté** : moyenne · **Attendu** : 50 %
- **Condition** : trophée `combo` ≥ 1. `noteChainWave` incrémente `combo` quand `seriesLevel == 1` (2ᵉ vague d'une même résolution).

### 7. Stage 3 — `blomix.ach.stage_3`
- **EN** : Stage 3
- **Avant** FR : « Atteins le Stage 3 en Arcade (1 000 points). » / EN : « Reach Stage 3 in Arcade (1,000 points). »
- **Après** FR : « Stage 3 atteint : 8 secondes par coup, ça s'accélère ! » / EN : « Stage 3 reached: 8 seconds per move, it's speeding up! »
- **Points** : 30 · **Cachée** : non · **Difficulté** : moyenne · **Attendu** : 35 %
- **Condition** : trophée `arcade_stage` ≥ 3 (record `currentStageIndex + 1`, écrit au game over dans `GameScene.noteTrophiesAtGameOver`, ~l. 5701 et 5724). Paliers dans `GameScene.soloStages` (~l. 17218) : S1 0 / S2 250 / S3 1 000 / S4 2 000 / S5 3 000 / Ultime 5 000, avec un chrono de 32 / 16 / 8 / 4 / 2 / 1 s et un multiplicateur de ×1 à ×6. Le Défi Arcade compte aussi.

### 8. Premier duel gagné — `blomix.ach.duel_win`
- **EN** : First Duel Win
- **Avant** FR : « Gagne un Duel, contre un ami ou un bot. » / EN : « Win a Duel, against a friend or a bot. »
- **Après** FR : « Victoire ! Ton adversaire veut déjà sa revanche. » / EN : « Victory! Your opponent already wants a rematch. »
- **Points** : 30 · **Cachée** : non · **Difficulté** : moyenne · **Attendu** : 25 %
- **Condition** : trophée `duel_win` ≥ 1. `BlomixTrophyStore.noteDuelFinished(didWin:)`, appelé dans `GameScene.swift` (~l. 20149). Tous les adversaires comptent, BABYBOT compris.

### 9. Trois jours de suite — `blomix.ach.daily_streak_3`
- **EN** : Three-Day Streak
- **Avant** FR : « Termine le défi du jour 3 jours d'affilée. » / EN : « Finish the daily challenge 3 days in a row. »
- **Après** FR : « 3 jours d'affilée ! Ne casse pas ta série. » / EN : « 3 days in a row! Don't break the streak. »
- **Points** : 30 · **Cachée** : non · **Difficulté** : moyenne · **Attendu** : 18 %
- **Condition** : trophée `daily_streak` ≥ 3 (meilleure série). `BlomixTrophyStore.noteDailyDay(_:)`, appelé au game over d'un défi (Arcade ou Five) dans `noteTrophiesAtGameOver` (~l. 5707). Les jours sont comptés en **UTC** : pour un joueur en France, la journée bascule à 1 h du matin (2 h en été).

### 10. Marée haute — `blomix.ach.five_tide_20`
- **EN** : High Tide
- **Avant** FR : « Encaisse 20 lignes dans une même partie Five. » / EN : « Take 20 incoming lines in a single Five game. »
- **Après** FR : « 20 lignes encaissées en Five. Tu tiens la marée ! » / EN : « 20 lines taken in Five. You held back the tide! »
- **Points** : 35 · **Cachée** : non · **Difficulté** : moyenne · **Attendu** : 20 %
- **Condition** : trophée `five_lines` ≥ 20 (record `moveCount / incomingLinePeriod`, soit 100 coups en Five). Écrit dans `noteTrophiesAtGameOver` (~l. 5696 et 5715). Five libre et Défi Five.

### 11. Esprit zen — `blomix.ach.zen_2000`
- **EN** : Zen Mind
- **Avant** FR : « Marque 2 000 points en Zen. » / EN : « Score 2,000 points in Zen. »
- **Après** FR : « 2 000 points sans chrono. Tu as trouvé ton rythme. » / EN : « 2,000 points, no clock. You found your flow. »
- **Points** : 30 · **Cachée** : non · **Difficulté** : moyenne · **Attendu** : 20 %
- **Condition** : trophée `zen_score` ≥ 2 000 (meilleur score Zen, palier II du trophée). Écrit dans `noteTrophiesAtGameOver` (~l. 5720), avec la reprise de `BlomixLocalZenHighScore` au premier lancement.

### 12. Stage Ultime — `blomix.ach.stage_ultime`
- **EN** : Ultimate Stage
- **Avant** FR : « Atteins le Stage Ultime en Arcade (5 000 points). » / EN : « Reach the Ultimate Stage in Arcade (5,000 points). »
- **Après** FR : « Une seconde par coup. Respect. » / EN : « One second per move. Respect. »
- **Points** : 60 · **Cachée** : non · **Difficulté** : difficile · **Attendu** : 5 %
- **Condition** : trophée `arcade_stage` ≥ 6 (ou `arcade_ultime_count` ≥ 1, équivalent). Même source que le n° 7.

### 13. Chaîne de 10 — `blomix.ach.chain_10`
- **EN** : Chain of 10
- **Avant** FR : « Fais une chaîne d'au moins 10 blox d'un coup. » / EN : « Make a single chain of at least 10 blox. »
- **Après** FR : « 10 blox d'un coup ! Belle construction. » / EN : « 10 blox at once! Nicely built. »
- **Points** : 60 · **Cachée** : non · **Difficulté** : difficile · **Attendu** : 8 %
- **Condition** : trophée `chain_size` ≥ 10 (plus grande composante d'une vague, `recordBest` dans `noteChainWave`).

### 14. Cabinet Magix — `blomix.ach.magix_all_nine`
- **EN** : Magix Cabinet
- **Avant** FR : « Déclenche les 9 Magix au moins une fois. » / EN : « Trigger all 9 Magix at least once. »
- **Après** FR : « Les 9 Magix sont dans ta collection ! » / EN : « All 9 Magix are in your collection! »
- **Points** : 70 · **Cachée** : non · **Difficulté** : difficile · **Attendu** : 5 %
- **Condition** : trophée `magix_all_nine` ≥ 9 (`refreshDerivedMagixCollection`, qui compte les 9 IDs de `BlomixTrophyCatalog.magixKindIDs`). SAINTX et BOMBX (1 chance sur 500 chacun) font l'essentiel de la difficulté.
- **Progression** : à envoyer en `percentComplete = n / 9 × 100`, pour que Game Center affiche l'avancement.

### 15. Une semaine de défis — `blomix.ach.daily_streak_7`
- **EN** : Week-Long Streak
- **Avant** FR : « Termine le défi du jour 7 jours d'affilée. » / EN : « Finish the daily challenge 7 days in a row. »
- **Après** FR : « Une semaine complète de défis. Belle régularité ! » / EN : « A full week of challenges. Impressive consistency! »
- **Points** : 60 · **Cachée** : non · **Difficulté** : difficile · **Attendu** : 5 %
- **Condition** : trophée `daily_streak` ≥ 7. Même source que le n° 9.

### 16. Salon des trophées — `blomix.ach.trophies_30`
- **EN** : Trophy Lounge
- **Avant** FR : « Allume 30 trophées dans le Salon. » / EN : « Light up 30 trophies in the Trophy Lounge. »
- **Après** FR : « 30 trophées allumés. Le Salon prend des couleurs ! » / EN : « 30 trophies lit. Your lounge is filling up! »
- **Points** : 60 · **Cachée** : non · **Difficulté** : difficile · **Attendu** : 7 %
- **Condition** : `BlomixTrophyStore.shared.litVisibleCount` ≥ 30 (trophées non secrets au rang ≥ I ; le catalogue 8.9 en compte 67 visibles et 13 secrets, soit 80). Valeur **dérivée** : pas de nouvel événement de jeu, mais il faut la recalculer à chaque `.blomixTrophiesDidChange`.
- **Progression** : `percentComplete = min(lit, 30) / 30 × 100`.
- **Variante** : si on préfère viser la profondeur plutôt que la largeur, « 10 trophées au rang III » via `rankCounts().iii` ≥ 10.

### 17. 10 000 en Arcade — `blomix.ach.arcade_10k`
- **EN** : 10,000 in Arcade
- **Avant** FR : « Marque 10 000 points dans une partie Arcade. » / EN : « Score 10,000 points in a single Arcade game. »
- **Après** FR : « 10 000 points en Arcade. Peu de joueurs en sont capables. » / EN : « 10,000 points in Arcade. Few players can do that. »
- **Points** : 90 · **Cachée** : non · **Difficulté** : experte · **Attendu** : 1,5 %
- **Condition** : trophée `arcade_score` ≥ 10 000 (meilleur score, Arcade et Défi Arcade). Il faut tenir longtemps au Stage Ultime (1 s par coup, ×6) : on dépasse le seuil de 5 000 de 5 000 points de plus. Le trophée interne place son rang III à 20 000. On garde 20 000 pour le Salon et 10 000 pour Game Center, plus atteignable.
- **À vérifier** : la distribution réelle des meilleurs scores sur le classement `BlomixMainScore_v3` avant de figer ce seuil. Si moins de 0,5 % des joueurs passent 10 000, descendre à 7 500.

### 18. Cascade infernale — `blomix.ach.combo_deep`
- **EN** : Chain Reaction
- **Avant** FR : « Déclenche une cascade de 5 vagues en un seul coup. » / EN : « Trigger a 5-wave cascade with a single move. »
- **Après** FR : « 5 vagues d'un coup ! La grille ne s'en remet pas. » / EN : « 5 waves in one move! The board will never recover. »
- **Points** : 90 · **Cachée** : non · **Difficulté** : experte · **Attendu** : 2 %
- **Condition** : trophée `combo_deep` ≥ 1. `noteChainWave` incrémente `combo_deep` quand `seriesLevel == 4` (5ᵉ vague).

### 19. Un mois de défis — `blomix.ach.daily_streak_30`
- **EN** : Month-Long Streak
- **Avant** FR : « Termine le défi du jour 30 jours d'affilée. » / EN : « Finish the daily challenge 30 days in a row. »
- **Après** FR : « 30 jours sans en rater un. Tu es une légende du défi ! » / EN : « 30 days without missing one. Daily challenge legend! »
- **Points** : 100 · **Cachée** : non · **Difficulté** : experte · **Attendu** : 1 %
- **Condition** : trophée `daily_streak` ≥ 30. Même source que le n° 9.
- **Progression** : `percentComplete = min(streak, 30) / 30 × 100`. Comme c'est une meilleure série, on n'envoie que des valeurs qui montent : `GKAchievement` ne redescend jamais.

### 20. Infini ×6 — `blomix.ach.saintx_ultime` (cachée, légendaire)
- **EN** : Infinity ×6
- **Avant** FR : « Déclenche SAINTX au Stage Ultime. » / EN : « Trigger SAINTX in the Ultimate Stage. »
- **Après** FR : « SAINTX au Stage Ultime : grille vidée, bonus ×6. Légendaire. » / EN : « SAINTX in the Ultimate Stage: board wiped, ×6 bonus. Legendary. »
- **Points** : 100 · **Cachée** : **oui** · **Difficulté** : légendaire · **Attendu** : < 0,5 %
- **Condition** : trophée `magix_saintx_ultime` ≥ 1. Dans `BlomixTrophyHooks.noteMagix`, la condition `kind == .cleanx && isUltime`. SAINTX apparaît 1 fois sur 500, et il faut être au Stage Ultime, à 1 s par coup.

---

## 2 bis. Localisations (6 langues, telles que créées dans ASC)

### 1. `blomix.ach.first_chain`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Première chaîne | Aligne 5 blox de la même couleur (les diagonales comptent). | Ta première chaîne de 5 ! La première d'une longue série. |
| en-US | First Chain | Line up 5 blox of the same color (diagonals count). | Your first chain of 5! The first of many. |
| es-ES | Primera cadena | Alinea 5 blox del mismo color (las diagonales cuentan). | ¡Tu primera cadena de 5! La primera de muchas. |
| it | Prima catena | Allinea 5 blox dello stesso colore (le diagonali contano). | La tua prima catena da 5! La prima di una lunga serie. |
| de-DE | Erste Kette | Reihe 5 Blox derselben Farbe auf (Diagonalen zählen). | Deine erste 5er-Kette! Die erste von vielen. |
| pt-BR | Primeira corrente | Alinhe 5 blox da mesma cor (diagonais contam). | Sua primeira corrente de 5! A primeira de muitas. |

### 2. `blomix.ach.first_bomb`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Boum ! | Fais exploser ta première bombe. | Première bombe posée. Ça fait du bien, non ? |
| en-US | Kaboom! | Set off your first bomb. | First bomb dropped. Feels good, right? |
| es-ES | ¡Bum! | Haz explotar tu primera bomba. | Primera bomba colocada. Sienta bien, ¿eh? |
| it | Bum! | Fai esplodere la tua prima bomba. | Prima bomba piazzata. Che soddisfazione, eh? |
| de-DE | Bumm! | Zünde deine erste Bombe. | Erste Bombe gelegt. Fühlt sich gut an, oder? |
| pt-BR | Bum! | Exploda sua primeira bomba. | Primeira bomba colocada. É bom demais, né? |

### 3. `blomix.ach.tutorial`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Tu sais tout | Va jusqu'au bout du tutoriel. | Tutoriel terminé : tu connais toutes les règles. |
| en-US | Fully Trained | Finish the tutorial all the way through. | Tutorial complete: you know all the rules. |
| es-ES | Lo sabes todo | Completa el tutorial hasta el final. | Tutorial completado: ya conoces todas las reglas. |
| it | Sai tutto | Completa il tutorial fino in fondo. | Tutorial completato: conosci tutte le regole. |
| de-DE | Voll ausgebildet | Spiel das Tutorial bis zum Ende durch. | Tutorial abgeschlossen: Du kennst alle Regeln. |
| pt-BR | Você sabe tudo | Termine o tutorial até o fim. | Tutorial concluído: você conhece todas as regras. |

### 4. `blomix.ach.first_magix`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Abracadabra | Déclenche ton premier Magix. | Ton premier Magix ! Il y en a 9 en tout : à toi de tous les trouver. |
| en-US | Abracadabra | Trigger your first Magix. | Your first Magix! There are 9 in all. Find them all. |
| es-ES | Abracadabra | Activa tu primer Magix. | ¡Tu primer Magix! Hay 9 en total: encuéntralos todos. |
| it | Abracadabra | Attiva il tuo primo Magix. | Il tuo primo Magix! Sono 9 in tutto: trovali tutti. |
| de-DE | Abrakadabra | Löse dein erstes Magix aus. | Dein erstes Magix! Es gibt 9 davon: Finde sie alle. |
| pt-BR | Abracadabra | Ative seu primeiro Magix. | Seu primeiro Magix! São 9 no total: encontre todos. |

### 5. `blomix.ach.pacifist`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Pacifiste | Termine une partie avec au moins 5 bombes en stock. | Perdu avec 5 bombes en poche… La prochaine fois, fais tout sauter ! |
| en-US | Pacifist | End a game with at least 5 bombs in stock. | Game over with 5 bombs in your pocket… Next time, blow it all up! |
| es-ES | Pacifista | Termina una partida con al menos 5 bombas en reserva. | Perdiste con 5 bombas en el bolsillo… ¡La próxima vez, hazlo volar todo! |
| it | Pacifista | Finisci una partita con almeno 5 bombe in riserva. | Hai perso con 5 bombe in tasca… La prossima volta, fai saltare tutto! |
| de-DE | Pazifist | Beende ein Spiel mit mindestens 5 Bomben im Vorrat. | Verloren mit 5 Bomben in der Tasche… Nächstes Mal jag alles in die Luft! |
| pt-BR | Pacifista | Termine uma partida com pelo menos 5 bombas no estoque. | Perdeu com 5 bombas no bolso… Da próxima vez, exploda tudo! |

### 6. `blomix.ach.super_combo`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Super combo | Déclenche une cascade : une chaîne qui en provoque une autre. | Ta première cascade ! Les blox tombent, et ça repart. |
| en-US | Super Combo | Trigger a cascade: one chain setting off another. | Your first cascade! Blox fall and it all goes again. |
| es-ES | Supercombo | Provoca una cascada: una cadena que desata otra. | ¡Tu primera cascada! Los blox caen y vuelta a empezar. |
| it | Super combo | Scatena una cascata: una catena che ne provoca un'altra. | La tua prima cascata! I blox cadono e si riparte. |
| de-DE | Super-Combo | Löse eine Kaskade aus: Eine Kette löst die nächste aus. | Deine erste Kaskade! Die Blox fallen und es geht weiter. |
| pt-BR | Super combo | Provoque uma cascata: uma corrente que dispara outra. | Sua primeira cascata! Os blox caem e tudo recomeça. |

### 7. `blomix.ach.stage_3`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Stage 3 | Atteins le Stage 3 en Arcade (1 000 points). | Stage 3 atteint : 8 secondes par coup, ça s'accélère ! |
| en-US | Stage 3 | Reach Stage 3 in Arcade (1,000 points). | Stage 3 reached: 8 seconds per move, it's speeding up! |
| es-ES | Stage 3 | Llega al Stage 3 en Arcade (1.000 puntos). | Stage 3 alcanzado: 8 segundos por jugada, ¡esto se acelera! |
| it | Stage 3 | Raggiungi lo Stage 3 in Arcade (1.000 punti). | Stage 3 raggiunto: 8 secondi a mossa, si accelera! |
| de-DE | Stage 3 | Erreiche Stage 3 im Arcade-Modus (1.000 Punkte). | Stage 3 erreicht: 8 Sekunden pro Zug, jetzt wird's schnell! |
| pt-BR | Stage 3 | Chegue ao Stage 3 no Arcade (1.000 pontos). | Stage 3 alcançado: 8 segundos por jogada, está acelerando! |

### 8. `blomix.ach.duel_win`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Premier duel gagné | Gagne un Duel, contre un ami ou un bot. | Victoire ! Ton adversaire veut déjà sa revanche. |
| en-US | First Duel Win | Win a Duel, against a friend or a bot. | Victory! Your opponent already wants a rematch. |
| es-ES | Primer duelo ganado | Gana un Duelo, contra un amigo o un bot. | ¡Victoria! Tu rival ya quiere la revancha. |
| it | Primo duello vinto | Vinci un Duello, contro un amico o un bot. | Vittoria! Il tuo avversario vuole già la rivincita. |
| de-DE | Erstes Duell gewonnen | Gewinne ein Duell, gegen Freunde oder einen Bot. | Sieg! Dein Gegner will schon eine Revanche. |
| pt-BR | Primeiro duelo vencido | Vença um Duelo, contra um amigo ou um bot. | Vitória! Seu adversário já quer a revanche. |

### 9. `blomix.ach.daily_streak_3`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Trois jours de suite | Termine le défi du jour 3 jours d'affilée. | 3 jours d'affilée ! Ne casse pas ta série. |
| en-US | Three-Day Streak | Finish the daily challenge 3 days in a row. | 3 days in a row! Don't break the streak. |
| es-ES | Tres días seguidos | Termina el desafío del día 3 días seguidos. | ¡3 días seguidos! No rompas la racha. |
| it | Tre giorni di fila | Completa la sfida del giorno 3 giorni di fila. | 3 giorni di fila! Non spezzare la serie. |
| de-DE | Drei Tage am Stück | Schließ die tägliche Challenge 3 Tage hintereinander ab. | 3 Tage am Stück! Reiß die Serie nicht ab. |
| pt-BR | Três dias seguidos | Termine o desafio do dia 3 dias seguidos. | 3 dias seguidos! Não quebre a sequência. |

### 10. `blomix.ach.five_tide_20`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Marée haute | Encaisse 20 lignes dans une même partie Five. | 20 lignes encaissées en Five. Tu tiens la marée ! |
| en-US | High Tide | Take 20 incoming lines in a single Five game. | 20 lines taken in Five. You held back the tide! |
| es-ES | Marea alta | Aguanta 20 líneas en una misma partida Five. | 20 líneas aguantadas en Five. ¡Frenaste la marea! |
| it | Alta marea | Resisti a 20 linee in una sola partita Five. | 20 linee incassate in Five. Hai fermato la marea! |
| de-DE | Hochwasser | Halte in einer Five-Partie 20 neuen Reihen stand. | 20 Reihen in Five überstanden. Du hältst die Flut auf! |
| pt-BR | Maré alta | Aguente 20 linhas numa mesma partida Five. | 20 linhas aguentadas no Five. Você segurou a maré! |

### 11. `blomix.ach.zen_2000`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Esprit zen | Marque 2 000 points en Zen. | 2 000 points sans chrono. Tu as trouvé ton rythme. |
| en-US | Zen Mind | Score 2,000 points in Zen. | 2,000 points, no clock. You found your flow. |
| es-ES | Mente zen | Consigue 2.000 puntos en Zen. | 2.000 puntos sin reloj. Has encontrado tu ritmo. |
| it | Mente zen | Fai 2.000 punti in Zen. | 2.000 punti senza cronometro. Hai trovato il tuo ritmo. |
| de-DE | Zen-Geist | Hol 2.000 Punkte im Zen-Modus. | 2.000 Punkte ohne Uhr. Du hast deinen Flow gefunden. |
| pt-BR | Mente zen | Faça 2.000 pontos no Zen. | 2.000 pontos sem relógio. Você encontrou seu ritmo. |

### 12. `blomix.ach.stage_ultime`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Stage Ultime | Atteins le Stage Ultime en Arcade (5 000 points). | Une seconde par coup. Respect. |
| en-US | Ultimate Stage | Reach the Ultimate Stage in Arcade (5,000 points). | One second per move. Respect. |
| es-ES | Stage Ultime | Llega al Stage Ultime en Arcade (5.000 puntos). | Un segundo por jugada. Respeto. |
| it | Stage Ultime | Raggiungi lo Stage Ultime in Arcade (5.000 punti). | Un secondo a mossa. Rispetto. |
| de-DE | Ultime-Stage | Erreiche die Ultime-Stage im Arcade-Modus (5.000 Punkte). | Eine Sekunde pro Zug. Respekt. |
| pt-BR | Stage Ultime | Chegue ao Stage Ultime no Arcade (5.000 pontos). | Um segundo por jogada. Respeito. |

### 13. `blomix.ach.chain_10`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Chaîne de 10 | Fais une chaîne d'au moins 10 blox d'un coup. | 10 blox d'un coup ! Belle construction. |
| en-US | Chain of 10 | Make a single chain of at least 10 blox. | 10 blox at once! Nicely built. |
| es-ES | Cadena de 10 | Haz una cadena de al menos 10 blox de una vez. | ¡10 blox de golpe! Buena construcción. |
| it | Catena da 10 | Fai una catena di almeno 10 blox in un colpo. | 10 blox in un colpo! Bella costruzione. |
| de-DE | 10er-Kette | Bilde eine Kette aus mindestens 10 Blox auf einmal. | 10 Blox auf einmal! Stark gebaut. |
| pt-BR | Corrente de 10 | Faça uma corrente de pelo menos 10 blox de uma vez. | 10 blox de uma vez! Bela construção. |

### 14. `blomix.ach.magix_all_nine`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Cabinet Magix | Déclenche les 9 Magix au moins une fois. | Les 9 Magix sont dans ta collection ! |
| en-US | Magix Cabinet | Trigger all 9 Magix at least once. | All 9 Magix are in your collection! |
| es-ES | Gabinete Magix | Activa los 9 Magix al menos una vez. | ¡Los 9 Magix ya están en tu colección! |
| it | Cabinet Magix | Attiva tutti i 9 Magix almeno una volta. | Tutti i 9 Magix sono nella tua collezione! |
| de-DE | Magix-Kabinett | Löse alle 9 Magix mindestens einmal aus. | Alle 9 Magix sind in deiner Sammlung! |
| pt-BR | Gabinete Magix | Ative os 9 Magix pelo menos uma vez. | Os 9 Magix estão na sua coleção! |

### 15. `blomix.ach.daily_streak_7`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Une semaine de défis | Termine le défi du jour 7 jours d'affilée. | Une semaine complète de défis. Belle régularité ! |
| en-US | Week-Long Streak | Finish the daily challenge 7 days in a row. | A full week of challenges. Impressive consistency! |
| es-ES | Una semana de desafíos | Termina el desafío del día 7 días seguidos. | Una semana entera de desafíos. ¡Qué constancia! |
| it | Una settimana di sfide | Completa la sfida del giorno 7 giorni di fila. | Una settimana intera di sfide. Che costanza! |
| de-DE | Eine Woche Challenges | Schließ die tägliche Challenge 7 Tage hintereinander ab. | Eine ganze Woche Challenges. Starke Ausdauer! |
| pt-BR | Uma semana de desafios | Termine o desafio do dia 7 dias seguidos. | Uma semana inteira de desafios. Que constância! |

### 16. `blomix.ach.trophies_30`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Salon des trophées | Allume 30 trophées dans le Salon. | 30 trophées allumés. Le Salon prend des couleurs ! |
| en-US | Trophy Lounge | Light up 30 trophies in the Trophy Lounge. | 30 trophies lit. Your lounge is filling up! |
| es-ES | Salón de trofeos | Enciende 30 trofeos en el Salón. | 30 trofeos encendidos. ¡Tu Salón se llena de color! |
| it | Salone dei trofei | Accendi 30 trofei nel Salone. | 30 trofei accesi. Il tuo Salone si colora! |
| de-DE | Trophäen-Salon | Bring 30 Trophäen im Salon zum Leuchten. | 30 Trophäen leuchten. Dein Salon füllt sich! |
| pt-BR | Salão de troféus | Acenda 30 troféus no Salão. | 30 troféus acesos. Seu Salão está ganhando cor! |

### 17. `blomix.ach.arcade_10k`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | 10 000 en Arcade | Marque 10 000 points dans une partie Arcade. | 10 000 points en Arcade. Peu de joueurs en sont capables. |
| en-US | 10,000 in Arcade | Score 10,000 points in a single Arcade game. | 10,000 points in Arcade. Few players can do that. |
| es-ES | 10.000 en Arcade | Consigue 10.000 puntos en una partida Arcade. | 10.000 puntos en Arcade. Pocos jugadores lo logran. |
| it | 10.000 in Arcade | Fai 10.000 punti in una partita Arcade. | 10.000 punti in Arcade. Ci riescono in pochi. |
| de-DE | 10.000 im Arcade | Hol 10.000 Punkte in einer Arcade-Partie. | 10.000 Punkte im Arcade-Modus. Das schaffen nur wenige. |
| pt-BR | 10.000 no Arcade | Faça 10.000 pontos numa partida Arcade. | 10.000 pontos no Arcade. Poucos jogadores conseguem. |

### 18. `blomix.ach.combo_deep`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Cascade infernale | Déclenche une cascade de 5 vagues en un seul coup. | 5 vagues d'un coup ! La grille ne s'en remet pas. |
| en-US | Chain Reaction | Trigger a 5-wave cascade with a single move. | 5 waves in one move! The board will never recover. |
| es-ES | Cascada infernal | Provoca una cascada de 5 oleadas con una sola jugada. | ¡5 oleadas de golpe! El tablero no se recupera. |
| it | Cascata infernale | Scatena una cascata di 5 ondate con una sola mossa. | 5 ondate in un colpo! La griglia non si riprende più. |
| de-DE | Höllenkaskade | Löse mit einem Zug eine Kaskade aus 5 Wellen aus. | 5 Wellen auf einmal! Davon erholt sich das Feld nie. |
| pt-BR | Cascata infernal | Provoque uma cascata de 5 ondas numa só jogada. | 5 ondas de uma vez! O tabuleiro não se recupera. |

### 19. `blomix.ach.daily_streak_30`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Un mois de défis | Termine le défi du jour 30 jours d'affilée. | 30 jours sans en rater un. Tu es une légende du défi ! |
| en-US | Month-Long Streak | Finish the daily challenge 30 days in a row. | 30 days without missing one. Daily challenge legend! |
| es-ES | Un mes de desafíos | Termina el desafío del día 30 días seguidos. | 30 días sin fallar ni uno. ¡Eres una leyenda del desafío! |
| it | Un mese di sfide | Completa la sfida del giorno 30 giorni di fila. | 30 giorni senza saltarne uno. Sei una leggenda della sfida! |
| de-DE | Ein Monat Challenges | Schließ die tägliche Challenge 30 Tage hintereinander ab. | 30 Tage ohne Pause. Du bist eine Challenge-Legende! |
| pt-BR | Um mês de desafios | Termine o desafio do dia 30 dias seguidos. | 30 dias sem perder nenhum. Você é uma lenda do desafio! |

### 20. `blomix.ach.saintx_ultime`

| Langue | Nom | Avant obtention | Après obtention |
|---|---|---|---|
| fr-FR | Infini ×6 | Déclenche SAINTX au Stage Ultime. | SAINTX au Stage Ultime : grille vidée, bonus ×6. Légendaire. |
| en-US | Infinity ×6 | Trigger SAINTX in the Ultimate Stage. | SAINTX in the Ultimate Stage: board wiped, ×6 bonus. Legendary. |
| es-ES | Infinito ×6 | Activa SAINTX en el Stage Ultime. | SAINTX en el Stage Ultime: tablero vacío, bonus ×6. Legendario. |
| it | Infinito ×6 | Attiva SAINTX nello Stage Ultime. | SAINTX nello Stage Ultime: griglia svuotata, bonus ×6. Leggendario. |
| de-DE | Unendlich ×6 | Löse SAINTX in der Ultime-Stage aus. | SAINTX in der Ultime-Stage: Feld leer, Bonus ×6. Legendär. |
| pt-BR | Infinito ×6 | Ative SAINTX no Stage Ultime. | SAINTX no Stage Ultime: tabuleiro limpo, bônus ×6. Lendário. |

---
## 3. Notes d'intégration

### 3.1 Game Center aujourd'hui (code 8.9)
- **Intégré** : entitlement `com.apple.developer.game-center` (`Blomix.entitlements`, `BlomixRelease.entitlements`, `Watch/BLOMIXWatch.entitlements`).
- **Authentification** : `GameCenterManager.authenticatePlayer(from:)` (`GKLocalPlayer.local.authenticateHandler`), pilotée par `ScoreManager`.
- **Classements** (`GKLeaderboard.submitScore`) : `BlomixMainScore_v3` (Arcade), `BlomixAverageScore_v1` (moyenne), `ZenMode`, `FiveMode`, `dailywins_arc` et `dailywin_five` (points podium des défis), `elotype` (Elo Duel, `BlomixEloManager`). Il reste un ancien ID par défaut, `BlomigMainScore_v2`, dans `GameCenterManager.reportScore` et `showLeaderboard` : à nettoyer.
- **Multijoueur** : `GKMatchmaker` et `GKMatch` pour le Duel en ligne (`BlomixPvPNetworking.swift`, `BlomixAvailablePlayersManager.swift`).
- **Réalisations** : **aucune**. Il n'y a ni `GKAchievement` ni `GKAccessPoint` dans le code. Le Salon des trophées est 100 % local (`blomix_trophies_v1` dans UserDefaults, « Pas Game Center, pas CloudKit »).

### 3.2 Game Center dans App Store Connect

**Mise à jour du 20/11/2026** : les 20 réalisations et leurs 120 localisations ont été créées avec la clé App Manager (`POST /v1/gameCenterAchievements` et `/v1/gameCenterAchievementLocalizations`), puis contrôlées par GET : 930 points, aucun écart avec ce document. Rien n'a été supprimé, archivé ni modifié sur les classements. Les images ont été ajoutées ensuite (section 0 bis).

**Rattachement du 20/11/2026** : chaque réalisation avait déjà sa version 1. Ces 20 versions et la version App Store 9.0 sont dans le même brouillon (`bce8572c-c5f7-4587-a7a8-eeeb56a25afa`, plateforme iOS, état Ready for Review, `submittedDate` vide). Le build 167, Valid, est sélectionné sur la 9.0. La 8.9 reste Ready for Sale. Game Center était déjà activé sur la 9.0, et cette version Game Center reste compatible avec celle de la 8.9 (`b00e61d4-471f-4da8-98a5-37f953a5c041`). `fastlane submit` s’arrête sur ce brouillon : la lane refuse un brouillon qui contient déjà des éléments, et elle enverrait avec `automatic_release`. Les essais sandbox ne sont pas faits.

Premier constat, avec l'ancienne clé Sales and Reports (lecture seule) :
- `GET /v1/apps/6762053543` : OK (app « BLOMIX - Block Puzzle », bundle `blomig.BLOMIX`).
- `GET /v1/apps/6762053543/gameCenterDetail` : **403 FORBIDDEN** (« The API key in use does not allow this request »).
- `GET /v1/apps/6762053543/gameCenterEnabledVersions` : **403**.
- **Conclusion** : la clé actuelle (rôle Sales and Reports) ne peut ni lire ni créer de réalisations. Game Center est forcément activé dans ASC, puisque les classements fonctionnent en production, mais on ne peut pas savoir par l'API s'il existe déjà des réalisations. Pour les créer : soit à la main dans ASC (Fonctionnalités > Game Center > Réalisations), soit avec une clé API **Admin** ou **App Manager**.
- Pour chaque réalisation, ASC demande : Reference Name, Achievement ID, points, Hidden, Achievable More Than Once, puis par langue le nom, les descriptions avant et après obtention, et une **image 512×512 ou 1024×1024** (PNG ou JPEG, sans transparence). Il faut 20 images, à décliner dans le style Encre ou celui des cibles du Salon.
- Les réalisations ne sont visibles des joueurs qu'une fois **attachées à une version soumise** (la 9.0) et approuvées. Une fois en ligne, une réalisation ne peut plus être supprimée et ses points ne peuvent plus changer : d'où l'intérêt de valider la liste avant de créer.
- Langues : les 6 langues de la fiche (fr-FR, en-US, es-ES, it, de-DE, pt-BR) sont créées dans ASC (section 2 bis).

### 3.3 Code à ajouter (pour Grok Build, 9.0)

**Implémenté le 20/11/2026.** `BlomixGameCenterAchievements.swift` lit les 20 compteurs du Salon, calcule le pourcentage (binaire 0 ou 100, progressif arrondi à deux décimales, cachées uniquement à 100) et envoie un seul `GKAchievement.report` pour ce qui a monté. Cache `blomix_gc_achievements_v1`, indexé par `teamPlayerID` (repli `gamePlayerID` s’il est vide). Debounce 1,5 s sur `.blomixTrophiesDidChange`. Au retour d’auth, fusion avec `loadAchievements()` puis rattrapage : si plus de trois réalisations se complètent dans ce lot, seule la plus haute en points affiche une bannière. `start()` est appelé dans `SceneDelegate.scene(_:willConnectTo:)`, `syncIfNeeded()` dans `sceneDidBecomeActive`. `resetAchievements` existe seulement en `#if DEBUG`, sans bouton. Les tests unitaires du calcul et de la table des 20 identifiants passent. Les essais sandbox sur iPhone (bannières en jeu, hors ligne, rattrapage d’un Salon déjà rempli) ne sont pas faits ici : le simulateur n’était pas connecté à Game Center.

1. **Nouveau fichier `BlomixGameCenterAchievements.swift`** (MainActor) : une table `[(gcID, trophyID ou closure, seuil, isProgressive)]`, et une fonction `sync()` qui :
   - lit `BlomixTrophyStore.shared.progress(for:)` ou `litVisibleCount` ;
   - calcule `percentComplete` (100 si le seuil est atteint, sinon la progression pour les n° 14, 16 et 19, par exemple 2/7 pour une série) ;
   - n'envoie que les valeurs **en hausse** par rapport à un cache local (`blomix_gc_ach_v1`), regroupées en un seul `GKAchievement.report([...])`, avec `showsCompletionBanner = true`.
2. **Quand appeler `sync()`** : à l'authentification réussie (`.blomixGameCenterAuthDidChange`), ce qui récupère au passage tout l'historique des joueurs actuels, puis à chaque `.blomixTrophiesDidChange`, avec un délai d'environ 1 s pour ne pas spammer pendant une cascade.
3. **Hors ligne** : le cache local garde les valeurs déjà envoyées. Les autres seront renvoyées au prochain `sync()`. Le Salon reste la source de vérité.
4. **Nouveaux hooks de jeu** : **aucun**. Les 20 réalisations s'appuient sur des compteurs déjà alimentés en 8.9. Une seule est dérivée (n° 16, `litVisibleCount`) : on la recalcule dans `sync()`, sans nouvel événement.
5. **Option skins** (non retenue dans les 20, puisque les skins sont libres et non débloquables) : une réalisation « Styliste » (« Crée ta propre palette Perso ») demanderait un **nouveau hook** dans `BlomixSkinCatalog.applyPersoColorSave(hex:slot:skinId:)` (`GameScene.swift`, ~l. 140), par exemple un trophée `skin_perso` unique. Elle pourrait remplacer n'importe laquelle des faciles.
6. **Réinitialisation** : rien à faire. On ne réinitialise jamais les réalisations côté jeu (`GKAchievement.resetAchievements` uniquement en debug).
7. **Tests** : vérifier en sandbox Game Center (compte de test) avant la soumission, en jouant une partie, puis Réglages > Game Center > BLOMIX.

### 3.4 Points d'attention
- Défi : les séries sont comptées en jours **UTC** (`noteDailyDay`). Le défi bascule à 1 h du matin en France, et la description reste volontairement simple.
- `arcade_stage` et `arcade_score` incluent le Défi Arcade, `five_lines` inclut le Défi Five. C'est voulu, puisque ce sont les mêmes règles.
- Les trophées antérieurs à l'arrivée du Salon ne sont pas tous récupérables : seuls les meilleurs scores sont repris au premier lancement (`retrofitIfNeeded`). Un vieux joueur qui a fini le tuto avant le Salon n'aura le n° 3 qu'en le refaisant jusqu'au bout.
- Total 930 sur 1 000 : il reste 70 points pour une réalisation de saison ou « Styliste » plus tard.

### 3.5 Reste à faire (Lomig)
1. ~~Images~~ : fait le 20/11/2026, 120 images envoyées par l'API (section 0 bis).
2. ~~Rattacher à la 9.0~~ : fait le 20/11/2026, dans le brouillon de review, pas envoyé (section 3.2). Une fois en ligne, une réalisation ne peut plus être supprimée et ses points ne peuvent plus changer.
3. **Code Swift** : fait le 20/11/2026 (section 3.3). Reste le test sandbox Game Center sur iPhone, avant la soumission.

# Prompt Grok Build : réalisations Game Center (BLOMIX 9.0)

> À copier d'un bloc dans Grok Build, dans le projet `~/Developer/BLOMIX-9.0`. Rédigé le 20/11/2026, à partir du code de la branche 9.0 (dernier commit bf271f8) et de `docs/gamecenter/REALISATIONS_GAME_CENTER.md`.

---

Tu travailles dans le projet Xcode BLOMIX (`~/Developer/BLOMIX-9.0`, branche 9.0, Swift 6, iOS 18 minimum). Objectif : brancher les **20 réalisations Game Center** déjà créées dans App Store Connect sur les compteurs du Salon des trophées, qui existent déjà. Aucune règle de jeu ne change.

## 0. Avant toute modification (obligatoire)
1. Lance `git status`. Le dépôt contient probablement des changements non commités (au 20/11 : `Blomix/Blomix/GameScene.swift`, `docs/CHANGELOG.md`, `docs/PLAN_9.0.md`, `docs/RULES.md`, plus les dossiers non suivis `Blomix/Blomix.xcodeproj/xcshareddata/xcodecloud/` et `docs/gamecenter/`).
2. Fais un **commit local de sauvegarde** de cet état (par exemple `chore: sauvegarde avant réalisations Game Center`), pour pouvoir revenir en arrière si une erreur serveur (500) coupe la session. **Aucun push.**
3. Ensuite, un commit local par étape logique (voir § 6). Jamais de push, jamais de `git reset --hard`.
4. Lis `docs/gamecenter/REALISATIONS_GAME_CENTER.md` (sections 0, 1, 2 et 3.3) : c'est la spécification de référence.

## 1. Ce qui existe déjà (vérifié dans le code, ne pas réinventer)
- **Compteurs locaux** : `Blomix/Blomix/BlomixTrophyStore.swift`.
  - `BlomixTrophyCatalog.all` contient 80 trophées (67 visibles et 13 secrets).
  - `BlomixTrophyStore.shared` est `@MainActor` et persiste dans UserDefaults sous `blomix_trophies_v1`.
  - Lecture : `progress(for: id).value` (Int), `rank(for:)`, `litVisibleCount` (trophées non secrets au rang ≥ I).
  - Écriture : `increment`, `recordBest`, `recordUnique`, `noteDailyDay(_:)` (séries de jours UTC) et `noteDuelFinished(didWin:)`.
  - Chaque changement poste `Notification.Name.blomixTrophiesDidChange`.
  - Au premier lancement, `retrofitIfNeeded()` reprend seulement les meilleurs scores.
- **Hooks déjà appelés depuis `GameScene.swift`** (enum `BlomixTrophyHooks`, dans `BlomixTrophyStore.swift`) :
  - `noteChainWave(sizes:seriesLevel:connectCount:)` pour les chaînes et cascades ;
  - `noteBomb(isNuke:brixBroken:)` ;
  - `noteMagix(_:isUltime:occupiedCells:otherBrixCount:consecutiveMagix:)` ;
  - `noteTutorialFinished()` (appelé dans `finishTutorialFromEndButton()` et `beginFirstGuidedArcade()`).
  - Dans `GameScene` : `noteTrophiesAtGameOver(finalScore:)` (fin de partie : `play_*`, `arcade_score`, `arcade_stage`, `five_lines`, `zen_score`, `secret_five_bombs`, `noteDailyDay`…) et l'appel à `BlomixTrophyStore.shared.noteDuelFinished(didWin:)` en fin de Duel.
  - Stages : `GameScene.soloStages` (S1 0, S2 250, S3 1 000, S4 2 000, S5 3 000, Ultime 5 000). `arcade_stage` enregistre `currentStageIndex + 1`, donc 6 = Ultime.
- **Authentification Game Center réelle** : `ScoreManager.authenticateOnLaunch(from:)` (`ScoreManager.swift`, `@MainActor`), appelée depuis `SceneDelegate.swift`.
  - Elle pose `ScoreManager.shared.isAuthenticated` puis poste `.blomixGameCenterAuthDidChange`.
  - En cas de succès, elle appelle `syncScoresWithGameCenterIfPossible(reason: "auth_success")` et la synchro Elo.
  - ⚠️ `GameCenterManager.authenticatePlayer(from:)` (`GameCenterManager.swift`) n'est **appelée nulle part** : ne t'appuie pas dessus, et ne réinstalle **jamais** un second `authenticateHandler`.
- **Game Center déjà utilisé** :
  - classements via `GKLeaderboard.submitScore` (`BlomixMainScore_v3`, `BlomixAverageScore_v1`, `ZenMode`, `FiveMode`, `dailywins_arc`, `dailywin_five`, `elotype`) ;
  - Duel via `GKMatchmaker` et `GKMatch` (`BlomixPvPNetworking.swift`) ;
  - aucun `GKAchievement` pour l'instant.
- **Projet Xcode** : pas de groupes synchronisés. Un nouveau fichier `.swift` doit être **ajouté à la cible de l'app** dans `project.pbxproj`, comme `BlomixTrophyStore.swift`.

## 2. À créer : `Blomix/Blomix/BlomixGameCenterAchievements.swift`
Un type `@MainActor final class BlomixGameCenterAchievements` avec un singleton `shared`, qui centralise **toute** la logique. Tu ne touches à `GameScene.swift` que si c'est indispensable (normalement ce n'est pas nécessaire).

### 2.1 Table des 20 réalisations (identifiants exacts, déjà créés dans ASC : ne pas les modifier)
Chaque entrée contient : `gcID`, une source (une closure `@MainActor () -> Int` qui lit le store), un `target` (seuil), un mode (`progressive` ou `binary`) et un indicateur `hidden`.

| # | gcID | Source (valeur lue) | Seuil | Mode | Cachée |
|---|---|---|---|---|---|
| 1 | `blomix.ach.first_chain` | `progress(for: "chain_count").value` | 1 | binary | non |
| 2 | `blomix.ach.first_bomb` | `progress(for: "bomb").value` | 1 | binary | non |
| 3 | `blomix.ach.tutorial` | `progress(for: "play_tutorial").value` | 1 | binary | non |
| 4 | `blomix.ach.first_magix` | `progress(for: "magix_all_nine").value` | 1 | binary | non |
| 5 | `blomix.ach.pacifist` | `progress(for: "secret_five_bombs").value` | 1 | binary | **oui** |
| 6 | `blomix.ach.super_combo` | `progress(for: "combo").value` | 1 | binary | non |
| 7 | `blomix.ach.stage_3` | `progress(for: "arcade_stage").value` | 3 | progressive | non |
| 8 | `blomix.ach.duel_win` | `progress(for: "duel_win").value` | 1 | binary | non |
| 9 | `blomix.ach.daily_streak_3` | `progress(for: "daily_streak").value` | 3 | progressive | non |
| 10 | `blomix.ach.five_tide_20` | `progress(for: "five_lines").value` | 20 | progressive | non |
| 11 | `blomix.ach.zen_2000` | `progress(for: "zen_score").value` | 2000 | progressive | non |
| 12 | `blomix.ach.stage_ultime` | `progress(for: "arcade_stage").value` | 6 | progressive | non |
| 13 | `blomix.ach.chain_10` | `progress(for: "chain_size").value` | 10 | progressive | non |
| 14 | `blomix.ach.magix_all_nine` | `progress(for: "magix_all_nine").value` | 9 | progressive | non |
| 15 | `blomix.ach.daily_streak_7` | `progress(for: "daily_streak").value` | 7 | progressive | non |
| 16 | `blomix.ach.trophies_30` | `BlomixTrophyStore.shared.litVisibleCount` | 30 | progressive | non |
| 17 | `blomix.ach.arcade_10k` | `progress(for: "arcade_score").value` | 10000 | progressive | non |
| 18 | `blomix.ach.combo_deep` | `progress(for: "combo_deep").value` | 1 | binary | non |
| 19 | `blomix.ach.daily_streak_30` | `progress(for: "daily_streak").value` | 30 | progressive | non |
| 20 | `blomix.ach.saintx_ultime` | `progress(for: "magix_saintx_ultime").value` | 1 | binary | **oui** |

Ces 20 compteurs existent tous et sont déjà alimentés : **aucun nouveau compteur n'est nécessaire**. Si l'un d'eux est introuvable dans `BlomixTrophyCatalog`, arrête-toi et signale-le au lieu d'en inventer un.

### 2.2 Calcul du pourcentage
- `percent = min(100, Double(value) / Double(target) * 100)`, arrondi à 2 décimales.
- `binary` : 0 ou 100.
- `progressive` : la progression partielle est envoyée (par exemple 2/7 jours donne 28,57 %).
- **Cachées (n° 5 et 20)** : n'envoyer **que 100**, jamais de progression partielle, sinon Game Center dévoile la réalisation avant son obtention.
- `chain_size` ne vaut 0 ou ≥ 5 que lorsqu'une chaîne existe : c'est normal, la progression démarre donc à 50 %.

### 2.3 Envoi
- `GKAchievement(identifier:)`, `percentComplete`, `showsCompletionBanner = true`, puis **un seul** `GKAchievement.report([...])` par lot. Utilise la version `async throws`, et reste sur le MainActor (compatible Swift 6 strict).
- **Anti-spam** :
  - garder un cache local `[gcID: Double]` des pourcentages **déjà confirmés** par Game Center (UserDefaults, clé `blomix_gc_achievements_v1`), **indexé par joueur** (`GKLocalPlayer.local.teamPlayerID`) pour qu'un changement de compte ne bloque rien ;
  - n'envoyer une entrée que si le nouveau pourcentage est **strictement supérieur** au cache ;
  - ne mettre le cache à jour qu'**après** un succès du `report`.
- **Regroupement** : `.blomixTrophiesDidChange` est postée très souvent, à chaque vague de cascade. Applique un debounce d'environ 1,5 s, puis un seul `sync()`.
- **Non authentifié** :
  - si `GKLocalPlayer.local.isAuthenticated` (ou `ScoreManager.shared.isAuthenticated`) est faux, **ne rien envoyer** et marquer `needsSync = true` ;
  - la « file d'attente », ce sont les compteurs eux-mêmes : comme le store reste la source de vérité, il suffit de tout recalculer au prochain `sync()` ;
  - en cas d'erreur réseau, garder `needsSync = true` et réessayer à la prochaine occasion (auth, retour au premier plan, prochain changement), sans boucle serrée.
- **Rattrapage des joueurs existants** :
  - à `.blomixGameCenterAuthDidChange` avec auth OK, appeler `GKAchievement.loadAchievements()` pour fusionner l'état serveur dans le cache (on garde le max), puis `sync()` complet ;
  - c'est ce qui accorde d'un coup aux joueurs actuels ce qu'ils ont déjà accompli (tuto, stages, séries…).
  - Au premier rattrapage, si plus de 3 réalisations sont complétées d'un coup, envoie-les avec `showsCompletionBanner = false`, sauf la plus haute, pour éviter une rafale de 15 bannières.
- **Points d'appel** :
  - démarrage : `BlomixGameCenterAchievements.shared.start()` (idempotent), appelé dans `SceneDelegate.scene(_:willConnectTo:options:)` près de l'appel existant à `ScoreManager.shared.authenticateOnLaunch(from:)`. Il s'abonne à `.blomixGameCenterAuthDidChange` et `.blomixTrophiesDidChange` ;
  - `SceneDelegate.sceneDidBecomeActive(_:)` (qui appelle déjà `syncScoresWithGameCenterIfPossible(reason: "scene_did_become_active")`) : ajouter `BlomixGameCenterAchievements.shared.syncIfNeeded()` ;
  - **ne modifie pas** le `authenticateHandler` existant de `ScoreManager`.
- **Jamais** de `GKAchievement.resetAchievements` dans le code de production. Si tu en veux un pour tester, mets-le derrière `#if DEBUG`, sans bouton visible en Release.

## 3. Interdits
- Ne pas toucher aux classements (`ScoreManager`, IDs de leaderboards, `submitScore`), à l'Elo, au matchmaking ni au Duel (`BlomixPvP*`, `BlomixEloManager`, `BlomixAvailablePlayersManager`).
- Ne pas modifier les règles, les compteurs du Salon, leurs seuils, ni la récompense BOMBX liée aux trophées complétés.
- Ne pas renommer les identifiants `blomix.ach.*` : ils sont figés dans App Store Connect.
- Ne pas modifier CloudKit, App Store Connect, fastlane, les entitlements (Game Center est déjà activé) ni le numéro de version.
- Pas de push. Pas de texte de réalisation dans le code : les noms et descriptions sont gérés par Game Center, en 6 langues.
- Vocabulaire dans les commentaires et logs : « complété », jamais « maxé ».

## 4. Tests (sandbox Game Center, sur iPhone, build Debug)
1. Connecte un compte Game Center de test (Réglages > Game Center, ou compte Sandbox des Réglages développeur).
2. **Nouvelle installation** : finis le tutoriel → « Tu sais tout ». Pose une bombe → « Boum ! ». Fais une chaîne de 5 → « Première chaîne ». La bannière Game Center s'affiche à chaque fois.
3. Atteins le Stage 3 en Arcade : la réalisation est à 100 %, et « Stage Ultime » est à 50 % dans l'app Game Center.
4. Termine une partie sans poser de bombe (5 en stock) : « Pacifiste » apparaît à 100 %. Avant ça, elle doit rester cachée, sans aucune progression visible.
5. **Rattrapage** : avec un appareil qui a déjà un Salon bien rempli, installe le build et connecte-toi. Les réalisations correspondant aux compteurs existants arrivent sans jouer, avec une seule bannière.
6. **Hors ligne** : mode avion, réalise une condition, puis reviens en ligne et au premier plan. La réalisation est envoyée.
7. **Anti-spam** : les logs (`print("[GCAch] …")`) montrent qu'aucun `report` ne part quand rien n'augmente, et au plus 1 lot par debounce pendant une cascade.
8. **Non-régression** : envoi des scores Arcade, Zen et Five, classements des défis, Duel en ligne et contre bot, Elo, reprise de partie et Salon des trophées fonctionnent comme avant.

## 5. Critères d'acceptation
- [ ] `BlomixGameCenterAchievements.swift` existe, est ajouté à la cible de l'app, compile sans avertissement Swift 6, et contient la table des 20 identifiants exacts du § 2.1.
- [ ] Aucun envoi quand le joueur n'est pas authentifié. Tout se rattrape après l'auth.
- [ ] Progression partielle envoyée pour les réalisations `progressive`. Les cachées ne reçoivent que 100.
- [ ] Le cache par joueur empêche tout envoi qui n'augmente pas. Un seul `report` par lot.
- [ ] Le rattrapage au lancement fonctionne pour un joueur existant, sans rafale de bannières.
- [ ] Aucun reset en Release. Aucun changement sur les classements, le Duel, l'Elo, les règles ou les compteurs.
- [ ] Les tests du § 4 sont passés en sandbox. Résume-les dans `docs/CHANGELOG.md` (ligne 9.0) et ajoute une note courte dans `docs/gamecenter/REALISATIONS_GAME_CENTER.md` (§ 3.3 « Implémenté »).

## 6. Découpage et commits (locaux uniquement)
1. Commit de sauvegarde de l'état actuel (§ 0).
2. `feat(gc): table des 20 réalisations et calcul des pourcentages` (nouveau fichier, ajouté au projet, pas encore branché).
3. `feat(gc): envoi groupé, cache par joueur, rattrapage après auth` (branchement dans `SceneDelegate.scene(_:willConnectTo:options:)` et `sceneDidBecomeActive(_:)`, abonnements aux notifications).
4. `docs(gc): changelog et note d'implémentation`.

À la fin, donne-moi un résumé : les fichiers touchés, les commits avec leurs hashs, le résultat de chaque test du § 4, et tout point incertain.

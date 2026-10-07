# BLOMIX — Duel vs bots (spec)

> **Statut** : **implémenté** (soumission 8.2 / 153). Schéma CloudKit `BotEloEvent` en Production. `protocolVersion` inchangé.  
> **Version de référence** : 8.2  
> **2026-10-06**  
> Voir [PVP_MATCHING.md](PVP_MATCHING.md), [EVAL.md](EVAL.md), [RULES.md](RULES.md) § Duel.

Objectif : pouvoir lancer un Duel contre **BABYBOT**, **MINIBOT**, **BOBBOT**, **BOT10**, **BOT5** ou **BOTSUPREME** — mêmes règles que le Duel humain, une seule grille (la tienne), les bots **visibles dans le classement Elo in-app** comme des joueurs.

---

## 0. Règle d’or (isolation)

**Au pire, un match contre un bot est lent. Rien d’autre n’est abîmé.**

| Toujours intact | Interdit |
|---|---|
| Duel humain (GK + Local Multipeer) | Faux `GKPlayer`, faux `GKMatch`, invite Game Center vers un bot |
| `protocolVersion`, handshake, keepAlive, grace, `attackId` filaire | Brancher le bot sur le fil GK / Multipeer |
| Classement Game Center **`elotype`** (mécanique : submit = `GKLocalPlayer.local` seulement) | `submitScore` pour une identité bot |
| H2H humain (`PvPH2HEvent`, juge, `pairKey` A:_) | Mélanger `bot:…` dans le juge H2H humain |
| Arcade, Zen, Défi, Référence BLOMIX, tutoriel, Watch | Réutiliser `BlomixDailyGhost` tel quel (Magix, stages, 5 bombes) |
| Justesse Game Over (`computeOptimal` / `evaluate` côté joueur) | Changer les poids d’`evaluate` « pour le bot » |

Si CloudKit bots est KO, si le moteur bot rame, si la fusion Elo rate : **le Duel humain et l’onglet Elo Game Center se comportent comme aujourd’hui.** Le match bot, lui, peut juste être lent ou sans ligne bot au classement.

---

## 1. Ce que le joueur voit

### 1.1 Six adversaires

| Id interne | Nom (non traduit, comme un Magix) | Temps | Cerveau |
|---|---|---|---|
| `bot:baby` | **BABYBOT** | 5 s | **tous** les coups : pire coup |
| `bot:mini` | **MINIBOT** | 5 s | **tous** les coups : colonne légale au hasard |
| `bot:bob` | **BOBBOT** | 5 s | 2 coups sur 5 : pire coup ; sinon `computeOptimal` |
| `bot:10` | **BOT10** | 10 s | 1 coup sur 2 : pire coup ; sinon `computeOptimal` |
| `bot:5` | **BOT5** | 5 s | toujours `computeOptimal` |
| `bot:supreme` | **BOTSUPREME** | 1 s | toujours `computeOptimal` |

Le hasard **ne consomme pas** le RNG des pièces (mélange déterministe `fidgetSeed`). Colonne = atterrissage possible, tirage uniforme. Pire coup = même métrique que le récap. BOBBOT : sur 5 coups, 1er et 3e = pire. BOT10 : 1/2 pire, horloge **10 s**. BOT5 / BOTSUPREME inchangés.

Badge **BOT** sur la ligne (classement / HUD). Pas de prénom Game Center, pas d’avatar GC.

### 1.2 Entrées

Deux chemins, **aucun** n’est un défi CloudKit ni un `GKInvite` :

1. **Liste Duel** (Joueurs disponibles) — section basse **Bots**, 6 rangs toujours visibles, 0 réseau. Tap = lance le match local.
2. **Onglet Elo** — les 6 bots sont **fusionnés** dans la liste (tri par rating, comme un humain). Tap = lance le match local. **Pas** le bouton « Défier » Game Center.

Les bots **n’apparaissent pas** dans le heartbeat `AvailablePlayer`. On ne peut pas les défier « comme un joueur en ligne ».

### 1.3 Pendant le match

Identique à un Duel humain **côté joueur** :

- Une grille SpriteKit, timer **toi** 10 s (gelé en visée bombe).
- HUD Duel : palier 0…50, pile d’attaque, nom de l’adversaire = BABYBOT / … / BOTSUPREME, profondeur de remplissage adverse.
- File **sans Magix**, 3 bombes **3×3**, ligne des 10, attaques à chaque palier 50.
- L’adversaire n’est **pas** animé. Le bot est un moteur en mémoire.
- **Quitter** (☰ Accueil) : overlay de confirmation, comme un Duel humain. Confirmer = défaite + Elo (`elotype` + `BotEloEvent`). Annuler reprend (timer gelé pendant ☰ / overlay).

Revanche / série : compteur **local session** comme aujourd’hui (HUD série). Pas de H2H CloudKit humain.

### 1.4 Fin de manche

Même écran résultat Duel (victoire / défaite, Elo local ±Δ). L’Elo **du joueur** part sur `elotype`. L’Elo **du bot** part sur CloudKit events (best-effort). Si CloudKit rate : le joueur a quand même son Elo GC ; la ligne bot se mettra à jour plus tard (ou restera en retard). Ce n’est pas un échec de manche.

---

## 2. Architecture (une grille, un moteur)

```
┌─────────────────────────────────────────────┐
│ GameScene  (grille joueur, juice, timer 10 s)│
│  pvpCoordinator canal .bot (loopback)        │
└──────────────┬──────────────────────────────┘
               │ attaques / iLost / fillDepth
               │ (appels process, 0 octet réseau)
┌──────────────▼──────────────────────────────┐
│ File `blomix.pvpBot`  QoS .utility           │
│ BlomixPvPBotEngine  (copie RAM, Sendable)    │
│  think 1 / 5 / 10 s  +  computeOptimal / 1/N │
└─────────────────────────────────────────────┘
```

- **Zéro** deuxième `GameScene`.
- **Zéro** `GKMatch` / `MCSession`.
- Seed RNG : tirée **localement** au lancement (même famille que `helloSeed`), copiée dans la scène **et** le moteur. Chaque côté consomme sa file à son rythme — comme deux humains.

### 2.1 Coordinateur

Ne pas refondre `BlomixPvPMatchCoordinator`.

Canal supplémentaire **`.bot`** (à côté de `.gk` et `.local`) :

- Handshake : immédiat, seed locale, **pas** de `helloSeed` filaire, **pas** de `protocolVersion` échangé.
- Toutes les sorties réseau (`sendEnvelope`, keepAlive, grace, ack, H2H snapshot filaire) : `if channel == .bot { return }` **en tête**. Les branches `.gk` / `.local` **byte-identiques**.
- Attaque joueur → `botEngine.injectAttackLine`.
- Attaque bot → même inject scène que `attackLine` reçu aujourd’hui (`consumeNextIncomingAttackLineIfAny` / pile).
- `iLost` bot ou joueur → même UI résultat, **sans** ack filaire.
- `boardFillDepth` : le moteur pousse `maxH` via le setter déjà là (`blomixPvP_setRemoteBoardFillDepth`).

Si le canal `.bot` est buggé, un match **humain** ne l’emprunte jamais.

### 2.2 Moteur (`BlomixPvPBotEngine`)

**Nouveau fichier.** Pas `BlomixDailyGhost` (Arcade, Magix, 5 bombes, croix de stage, pas d’attaques).

| | Duel humain / bot | Fantôme Défi |
|---|---|---|
| Magix | jamais | oui |
| Bombes | 3, blast **3×3** | 5, 3×3 + croix de stage |
| Ligne des 10 | oui | oui |
| Attaques palier 50 | oui | non |
| Stages / × score | non | oui |
| Timer | joueur 10 s ; bot = horloge pensée | ignoré |

Politique de pose (alignée fantôme **engine 5**, sans Magix) :

- Blox / Brix : argmax `computeOptimal` (`pendingLine` = prochaine ligne des 10 si connue), sauf BABYBOT : tous pire coup ; MINIBOT : tous au hasard ; BOBBOT : 2/5 pire ; BOT10 : 1/2 pire.
- Bombes souples : `maxH ≥ 7` et le meilleur drop n’abaisse pas / n’efface pas ; cible Brix puis colonnes hautes. Survie si plus d’atterrissage.
- **Ne pas** modifier `evaluate` / `computeOptimal` pour « aider le bot ».

### 2.3 Horloge bot (fluidité)

1. Sur file `.utility` **dédiée** (`blomix.pvpBot`) — **jamais** `analyzerQueue`, jamais MainActor pour le lookahead.
2. `computeOptimal` (ms) **puis** attendre le reste de 1 / 5 / 10 s, **puis** appliquer le coup au moteur.
3. Si le calcul dépasse le budget (BOTSUPREME 1 s, thermal) : jouer **dès que prêt**. La scène joueur n’attend pas.
4. Menu / overlay qui gèle le Duel humain : même gel pour l’horloge bot.
5. Visée bombe **joueur** : timer joueur gelé ; l’horloge **bot continue** (comme un adversaire humain).

« Lent » = BOT10 qui met 10 s, ou un frame où BOTSUPREME sort à 1,3 s. **Pas** un hitch SpriteKit.

---

## 3. Elo

### 3.1 Intention

Les 6 bots **sont des joueurs du classement Elo dans BLOMIX**. Ton Elo Duel **bouge** après un match bot (même formule, même `elotype` pour **toi**). L’Elo du bot **bouge** pour tout le monde.

### 3.2 Ce que Game Center ne sait pas faire

`GKLeaderboard.submitScore(..., player: GKLocalPlayer.local, leaderboardIDs: ["elotype"])`.

On ne peut **pas** publier BOT10 sur `elotype`. Les bots n’existent pas comme `GKPlayer`.

### 3.3 Deux sources, une liste

| Qui | Vérité | Écriture |
|---|---|---|
| Humain | `elotype` | inchangée : le joueur local soumet **son** rating après **toute** manche Duel (humain **ou** bot) |
| Bot | CloudKit Public `BotEloEvent` | le joueur crée **son** event (créateur = lui, comme `chfrom_*` / H2H) |

Onglet Elo :

1. Charger `elotype` **exactement** comme aujourd’hui (multipage, filtre 800/0, `context`).
2. Charger les ratings bots (réduction des events, cache).
3. Fusionner par rating décroissant, insérer les 6 lignes (badge BOT).
4. Si l’étape 2 échoue : **afficher uniquement l’étape 1** — liste actuelle, zéro ligne bot, zéro régression.

Pastille accueil Duel : **même rang** que l’onglet (`BlomixEloManager.fetchDisplayedLocalDuelRank`) — pas le `GKLeaderboard.Entry.rank` brut (mur des comptes 800 / 0 parties).

Interdit : écrire un score bot sur `elotype` ; changer le filtre humains ; appeler `loadPlayers` / `GKInvite` sur une ligne bot.

### 3.4 Formule

`BlomixEloManager.updatedRatings` **sans copie**. Profil remote = rating + `completedMatchCount` du bot (nombre d’events).

Après la manche :

1. `finalizeFromCacheOnly` / submit local **existant** (ton nouveau rating → `elotype`). Même chemin qu’un Local Multipeer hors ligne.
2. Créer un `BotEloEvent` (best-effort, **hors** chemin UI critique, comme H2H). Échec → log, pas de dialog, pas de rollback de l’Elo joueur.

### 3.5 Schéma CloudKit `BotEloEvent`

**Pas** un record unique `BotElo` world-writable (vandalisme). Un event **par match**, créé par le joueur.

`recordName` (côté code, pas le Dashboard) = `botelo_{clientEventId}`.

Réduction (lecture, pas pendant le match) :

- Query `botId` == X, tri `createdAt` puis `recordName`.
- Départ 800 / 0 matchs.
- Rejouer : chaque event applique la formule avec le rating **courant** du bot et le `outcome` (K = `kFactor(matchCount bot)`).
- Rating affiché = résultat. Best-effort : deux matchs parallèles → ordre imparfait, acceptable (volume Duel actuel).

**Robinet** : passer par `BlomixPublicCloudGate` (503 / Retry-After). Un 503 bots **ne doit pas** élargir le blocage au-delà de la politique actuelle du gate (ne pas inventer un second gate).

### 3.6 CloudKit Dashboard — ce que **toi** fais (une fois)

Conteneur **`iCloud.blomig.BLOMIX`**, base **Public**. Comme `DailyScore` / `PvPH2HEvent`.

L’entitlement `icloud-container-environment` = **Production** : un ⌘R Xcode tape la Public **prod**. Un type créé seulement en Development est **invisible** à l’app. Il faut **Deploy to Production**.

**Ne pas toucher** : `AvailablePlayer`, `DailyScore`, `PvPH2HEvent`, indexes existants, rôles.

#### Étapes

1. [CloudKit Console](https://icloud.developer.apple.com/dashboard) → team BLOMIX → conteneur **`iCloud.blomig.BLOMIX`**.
2. Environnement **Development**. Schema → **Record Types** → **+** (Add Record Type).
3. Nom exact : **`BotEloEvent`** (casse comprise). Créer.
4. Ajouter **uniquement** ces champs :

| Champ | Type Dashboard | Index |
|---|---|---|
| `botId` | `String` | **Queryable** |
| `reporterId` | `String` | — |
| `outcome` | `Int(64)` | — |
| `playerEloBefore` | `Int(64)` | — |
| `botEloBefore` | `Int(64)` | — |
| `matchId` | `String` | **Queryable** |
| `createdAt` | `Date/Time` | **Queryable** + **Sortable** |

5. **Security / Permissions** du type : **laisser le défaut Public**  
   World **read** · Authenticated **create** · **Creator** write.  
   **Ne pas** cocher Authenticated write sur les records des autres.
6. **Deploy Schema Changes…** → **Production**. Vérifier que `BotEloEvent` apparaît en prod avec les **mêmes** indexes.
7. **Aucun record à créer à la main.** Pas de ligne « BOT10 ». Les events naissent en fin de manche (code). Tant que le code n’écrit pas : type vide = OK.

Contrôle : Schema Production → `BotEloEvent` listé ; les trois autres types inchangés.

Si tu ne déploies **pas** en prod : plus tard le match bot marchera quand même (isolation), mais **pas** de lignes bots au classement (query `unknown item type` / silencieux).

### 3.7 Farm

Un BOT10 **mondial** qui perd descend. Le battre à 400 ne rapporte plus. C’est voulu.

Les 2–3 premières semaines à 800, les victoires rapportent (K haut). Documenté, pas un bug. **Pas** d’Elo bot privé par appareil (ça, ce serait un farm infini + 3 BOT10 différents).

---

## 4. H2H, série, déco

| | Match bot | Match humain |
|---|---|---|
| H2H CloudKit | **aucun** event `PvPH2HEvent` | inchangé |
| Juge accueil / Elo | ignore `bot:…` | inchangé |
| Série HUD | compteur session local OK | inchangé |
| Déco / Reconnexion | N/A (pas de transport) | inchangé |
| Quitter ☰ | overlay « tu perds ce match Duel » ; confirmer = défaite + Elo joueur/bot | **même overlay** (humain aussi) |

---

## 5. Fichiers (cible, à la code)

| Fichier | Rôle | Toucher ? |
|---|---|---|
| **Nouveau** `BlomixPvPBotEngine.swift` | Moteur RAM | oui |
| **Nouveau** petit glue bot (horloge, file) | | oui |
| `BlomixPvPNetworking.swift` | Canal `.bot` + early-return réseau | **minimal** |
| `BlomixPvPUI.swift` | Section Bots liste Duel ; résultat déjà OK | oui |
| `LeaderboardViewController.swift` | Fusion 3 lignes ; tap bot ≠ `GKInvite` | oui |
| `BlomixEloManager.swift` | Réutiliser `againstRemoteProfile` ; **pas** de submit bot | oui si helper lecture cache bot, sinon non |
| **Nouveau** writer/lecteur `BotEloEvent` | Best-effort | oui |
| `GameScene.swift` | Lancer canal bot, inject déjà là | **minimal** (même HUD `pvpCoordinator != nil`) |
| `BlomixDailyGhost.swift` | | **non** |
| `BlomixMoveAnalyzer.swift` | | **non** |
| `BlomixPvPH2HManager.swift` | | **non** (filtre `bot:` si un id fuyait, sinon non) |
| Watch / Fastlane / `protocolVersion` | | **non** |

l10n : FR+EN min. (idéalement 5 langues) — titres section Bots, badge, accessibilité. Noms **BABYBOT / MINIBOT / BOBBOT / BOT10 / BOT5 / BOTSUPREME** non traduits.

---

## 6. Ce qu’on ne code pas dans le 1ᵉʳ lot

- Bot plus « fort » qu’`evaluate` (horizon 4, farm Magix — il n’y a pas de Magix en Duel).
- Replay / grille bot visible.
- Bots dans Joueurs disponibles / push / défis `chfrom_*`.
- Compte Game Center studio « BOT10 ».
- Record CloudKit unique world-writable.
- Changement d’Elo Duel humain, du matching, du Watch.

---

## 7. Checklist manuelle (quand ce sera joué)

**Régression (obligatoire, avant de regarder le bot) :**

- [ ] Duel humain GK : handshake, attaques, Elo `elotype`, H2H, revanche
- [ ] Duel Local Multipeer : idem
- [ ] Onglet Elo : liste GC identique si CloudKit bots down (mode avion après cache GC)
- [ ] Arcade / Zen / Défi / hub Référence BLOMIX
- [ ] Watch inchangée

**Bot :**

- [ ] Liste Duel : 6 rangs, tap lance, 0 spinner réseau
- [ ] Elo : 3 lignes badge BOT ; tap ≠ invite GC
- [ ] Une seule grille ; attaques juice = Duel
- [ ] BABYBOT / MINIBOT / BOBBOT / BOT10 / BOT5 / BOTSUPREME : tous pire / tous hasard / 2/5 pire / 1/2 pire 10 s / 5 s / 1 s, scène fluide
- [ ] Bombes bot : stock **3**, jamais plus (comme le joueur Duel ; pas de BOMBX)
- [ ] Fin de manche : ± Elo joueur sur `elotype` ; event CloudKit best-effort
- [ ] CloudKit KO : manche OK, Elo joueur OK, pas de ligne bot ou ligne périmée cache
- [ ] ☰ Accueil / abandon : overlay confirmation ; confirmer = défaite + Elo ; Annuler reprend ; pas de coordinateur GK coincé (`isInActiveMatch`)

---

## 8. Décisions figées

1. Isolation > perf. Lent OK ; coller / casser le Duel humain **non**.
2. Bots = joueurs du classement **in-app**, pas des comptes GC.
3. Ton Elo `elotype` **change** après un match bot.
4. Elo bot = events CloudKit, réduction à la lecture, best-effort.
5. BOT5 / BOTSUPREME : optimal. BOT10 : 1/2 pire (10 s). BABYBOT : tous pire. MINIBOT : tous hasard. BOBBOT : 2/5 pire.
6. `protocolVersion` inchangé.
7. `protocolVersion` inchangé. Pas de faux `GKPlayer`.

---

*Implémenté en 8.2 / 153 (soumission). Checklist §7 à jouer sur device.*

# PvP — Appariement et défis entre joueurs

> **Référence code** : `BlomixAvailablePlayersManager.swift`, `BlomixPvPUI.swift`, `GameViewController.swift`, `LeaderboardViewController.swift`, `BlomixPvPNetworking.swift`  
> **Dernière revue** : juillet 2026

Ce document décrit **précisément** comment deux joueurs BLOMIX peuvent se défier en PvP, quelles conditions doivent être remplies, et où la logique peut échouer silencieusement.

---

## Vue d'ensemble

BLOMIX propose **trois chemins distincts** pour lancer un duel 1 vs 1. Ils n'utilisent **pas** le même mécanisme de « notification » :

| Mode | Entrée UI | Signalisation | Mécanisme d'invitation |
|------|-----------|---------------|------------------------|
| **A. Joueurs disponibles** | Lobby PvP → « Joueurs disponibles » | CloudKit Public DB | Bannière in-app (`BlomixChallengeBannerView`) — **pas** de push Game Center |
| **B. Adversaire récent** | Lobby PvP → « Adversaire récent » | GameKit direct | `GKInvite` → bannière in-app (`BlomixPvPInviteBannerView`) |
| **C. Classement Elo** | Classement → onglet Elo → « Défier » | GameKit direct | Identique au mode B |
| **D. Auto-match** | Code présent, **UI non branchée** | — | `beginMatchSearch()` / `BlomixPvPAutoSearcher` jamais appelés depuis l'UI |

**Point critique pour le bug « on se voit dans la liste mais pas d'invitation »** : le mode A sépare **deux opérations CloudKit indépendantes** :

1. **Visibilité** — record `{gamePlayerID}` (heartbeat toutes les 60 s, TTL 5 min)
2. **Défi** — record `chfrom_{challengerGamePlayerID}` (TTL 90 s, écrit par le challenger sur **son propre** record)

Voir l'autre dans la liste prouve que (1) fonctionne. Cela **ne garantit pas** que (2) a réussi.

**Permissions CloudKit Public DB** : un joueur authentifié ne peut écrire que les records dont il est **créateur**. L'ancien format `chal_{gamePlayerID_du_défié}` provoquait `WRITE operation not permitted` car le challenger tentait d'écrire le « record » d'un autre joueur. Le format `chfrom_{challengerGamePlayerID}` corrige cela.

Il n'existe **aucun contrôle de version d'app** dans le chemin PvP. « Même version » n'est pas un prérequis du code.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS Client                               │
├─────────────────────────────────────────────────────────────────┤
│  BlomixPvPLobbyViewController                                    │
│    ├─ toggle « OK pour être défié »                              │
│    ├─ BlomixPvPAvailablePlayersViewController  (mode A)          │
│    └─ BlomixPvPRecentPlayersViewController     (mode B)          │
│  LeaderboardViewController                     (mode C)          │
│  GameViewController                                              │
│    ├─ handleIncomingChallengeDetected → BlomixChallengeBannerView│
│    └─ player(_:didAccept:) → BlomixPvPInviteBannerView          │
├─────────────────────────────────────────────────────────────────┤
│  BlomixAvailablePlayersManager (@MainActor singleton)            │
│    publishAvailability / createChallenge / pollForIncoming…    │
├─────────────────────────────────────────────────────────────────┤
│  CloudKit Public DB (iCloud.blomig.BLOMIX)                        │
│    Record Type: AvailablePlayer                                  │
│  GameKit GKMatchmaker                                            │
│    findMatch(playerGroup) ou findMatch(recipients)               │
└─────────────────────────────────────────────────────────────────┘
```

### Schéma CloudKit — Record Type `AvailablePlayer`

| Champ | Type | Index | Usage |
|-------|------|-------|-------|
| `teamPlayerID` | String | Queryable | Identifiant d'équipe GC ; pour les défis = `gamePlayerID` du **challenger** |
| `displayName` | String | — | Nom affiché |
| `eloRating` | Int64 | — | Elo réel **ou** `matchPlayerGroup` pour les records `chal_*` |
| `lastHeartbeat` | Date | Queryable, Sortable | Fraîcheur ; filtre requête ≥ now − 5 min |
| `inMatch` | Int (0/1) | — | 1 = joueur en partie PvP (badge « En match », pas de bouton Défier) |

#### Record de disponibilité

```
recordName = {gamePlayerID du joueur local}
teamPlayerID = teamPlayerID Game Center
displayName = displayName GC
eloRating = Elo (ou 0 puis mis à jour)
lastHeartbeat = Date()
inMatch = 0 | 1
```

#### Record de défi sortant (rendez-vous)

```
recordName = "chfrom_" + {gamePlayerID du CHALLENGER}
teamPlayerID = gamePlayerID du joueur DÉFIÉ   ← cible (champ queryable existant)
displayName = displayName du challenger
eloRating = matchPlayerGroup (hash déterministe)
lastHeartbeat = Date()
```

Le challengé détecte les défis en scannant les records `chfrom_*` dont `teamPlayerID == mon gamePlayerID`.

**`matchPlayerGroup`** — hash djb2 sur `"id1|id2"` (ids triés), modulo 10⁹ + 1 (évite 0 = auto-match) :

```swift
static func matchPlayerGroup(id1: String, id2: String) -> Int
```

Les deux joueurs calculent la **même valeur** localement ; elle sert de `GKMatchRequest.playerGroup`.

---

## Mode A — « OK pour être défié » + liste des joueurs disponibles

### Phase 1 — Devenir visible

```
Utilisateur active le toggle
  → isAvailableForChallenge = true (UserDefaults blomixAvailableForChallenge_v1)
  → publishAvailability()     // CKModifyRecordsOperation, savePolicy .allKeys
  → startHeartbeat()            // toutes les 60 s
  → startChallengePolling()     // immédiat puis toutes les 4 s
```

**Garde-fous publish :**
- `GKLocalPlayer.local.isAuthenticated` requis
- Erreur remontée à l'UI via `.blomixAvailabilityPublishResult` (premier passage uniquement)

**Cycle de vie app :**
- `willResignActive` → arrêt heartbeat + polling (**record conservé**)
- `didBecomeActive` → republish + redémarrage timers si toggle actif

### Phase 2 — Voir les autres joueurs

```
BlomixPvPAvailablePlayersViewController.loadAvailablePlayers()
  → fetchAvailablePlayersAndChallenge()
  → CKQuery: lastHeartbeat >= now − 5 min
  → Filtres côté client :
       • exclure soi-même (gamePlayerID)
       • exclure même teamPlayerID (comptes liés)
       • exclure heartbeat périmé
  → Auto-refresh liste toutes les 8 s (phase .loaded ou .empty)
```

Un joueur **en match** (`inMatch == 1`) apparaît dans la liste avec le badge « En match » — le bouton « Défier » est absent.

### Phase 3 — Envoyer un défi (challenger)

```
challengeTapped()
  1. applyPhase(.inviting)           ← UI « Invitation envoyée à %@ » IMMÉDIATEMENT
  2. Task {
       createChallenge(...)          ← CloudKit save (peut échouer silencieusement)
       startChallengeMatchmaking()   ← GKMatchmaker.findMatch(playerGroup)
     }
```

**`createChallenge` — points de fragilité :**
- Utilise `publicDB.save(record)` après un éventuel `record(for:)` — **pas** `CKModifyRecordsOperation` + `.allKeys`
- En cas d'échec : log `[Available] challenge create error:` uniquement, **aucun feedback UI**
- Risque `serverRecordChanged` si record `chal_*` existant avec changeTag différent

**`startChallengeMatchmaking` :**
- Annule `BlomixPvPAutoSearcher` + `GKMatchmaker.shared().cancel()`
- Poste `.blomixPvPOutgoingInviteStateChanged(active: true, targetPlayerID:)`
- Timeout 60 s → cancel + `deleteChallenge` + phase `.failed`
- Attend `expectedPlayerCount == 0` via `GKMatchDelegate` avant `onMatch`

### Phase 4 — Recevoir un défi (challengé)

Le défi **n'est pas** une invitation Game Center. C'est une **bannière in-app** en haut de l'écran.

```
pollForIncomingChallenge() [toutes les 4 s, si available && !inMatch]
  → fetchAvailablePlayersAndChallenge()
  → cherche record chal_{localGamePlayerID}, heartbeat < 90 s
  → si nouveau challenger (≠ lastNotifiedChallengerID) :
       post .blomixIncomingChallengeDetected

GameViewController.handleIncomingChallengeDetected()
  → garde : !isInActiveMatch
  → garde : pas déjà une BlomixChallengeBannerView visible
  → showChallengeBanner() sur view.window
```

**Acceptation :**
```
acceptIncomingChallenge()
  → deleteChallenge(localGamePlayerID)
  → GKMatchmaker.findMatch(playerGroup: challenge.matchPlayerGroup)
  → Attente P2P via ChallengeMatchDelegate (expectedPlayerCount == 0)
  → beginPvPWithMatch()
```

**Refus :**
```
declineIncomingChallenge()
  → suppressChallengeWithDelay()  // delete + verrou 8 s sur lastNotifiedChallengerID
```

### Diagramme de séquence (mode A)

```
Challenger                          CloudKit                         Challengé
    |                                   |                                |
    |-- upsert {gamePlayerID} --------->|                                |
    |                                   |<------- upsert {gamePlayerID} --|
    |                                   |                                |
    |-- query (liste) ----------------->|                                |
    |<-- voit challengé ----------------|                                |
    |                                   |                                |
    |-- save chal_{challengé} --------->|                                |
    |-- findMatch(playerGroup)          |                                |
    |                                   |                                |
    |                                   |<-- poll (4 s) -----------------|
    |                                   |--- chal_{challengé} ----------->|
    |                                   |                                |-- bannière ⚔️
    |                                   |                                |-- findMatch(même group)
    |<=========== GKMatch P2P ==========================================>|
```

---

## Mode B — Adversaire récent (GameKit direct)

```
BlomixPvPRecentPlayersViewController.challengeTapped()
  → GKPlayer.loadPlayers(forIdentifiers:) si cache incomplet
  → sendInvitation(to: GKPlayer)
       request.recipients = [player]
       findMatch(for: request)
```

**Réception côté invité :**
```
GameViewController.player(_:didAccept invite: GKInvite)
  → garde outgoingInviteActive (sauf défi croisé même targetPlayerID)
  → GKMatchmaker.match(for: invite)
  → BlomixPvPInviteBannerView
```

**Limitation GameKit connue :** erreur 5121 / « never played together » — joueurs qui ne se sont jamais affrontés via GC ne peuvent pas s'inviter ainsi. Message : `pvp.leaderboard_invite_not_recent_player`.

---

## Mode C — Classement Elo

Identique au mode B (`LeaderboardViewController.sendInvitation`). Les `GKPlayer` sont mis en cache depuis les entrées du leaderboard Elo — pas d'appel `loadPlayers` au tap.

---

## État et machines à états

### Disponibilité (`BlomixAvailablePlayersManager`)

```
OFF ──toggle ON──► AVAILABLE
                      ├─ heartbeat 60 s
                      ├─ poll défis 4 s
                      └─ record CloudKit actif (TTL 5 min sans heartbeat)

AVAILABLE + partie PvP ──setActiveMatch(true)──► polling STOP, inMatch=1

Fin de partie ──setActiveMatch(false)──► clearLastNotifiedChallenger + reprendre poll
```

### Liste joueurs disponibles (`BlomixPvPAvailablePlayersViewController.Phase`)

```
loading → loaded(items) | empty
loaded → inviting(name) → [match via onMatch] | failed
```

### Lobby (`BlomixPvPLobbyViewController.LobbyPhase`)

```
choosingMode → searching → matchFound → preparingBoards
```
Le chemin `searching` via `beginMatchSearch()` existe mais **n'est relié à aucun bouton UI**.

---

## Notifications internes

| Notification | Émetteur | Récepteur | Rôle |
|--------------|----------|-----------|------|
| `.blomixAvailabilityChanged` | setter `isAvailableForChallenge` | Lobby toggle | Sync UI |
| `.blomixAvailabilityPublishResult` | `publishAvailability` | Lobby status | Succès/erreur CloudKit |
| `.blomixIncomingChallengeDetected` | `pollForIncomingChallenge` | `GameViewController` | Afficher bannière défi CloudKit |
| `.blomixPvPOutgoingInviteStateChanged` | flows d'invitation | `GameViewController` | Verrou `outgoingInviteActive` |
| `.blomixPvPOpponentConnected` | `BlomixPvPMatchCoordinator` | Lobby | Adversaire connecté |
| `.blomixPvPBoardsReady` | `GameScene` | Lobby | Fermeture modals |

---

## Conditions nécessaires — mode A (checklist complète)

### Challenger

| # | Condition | Si faux |
|---|-----------|---------|
| 1 | Game Center authentifié | `challengeTapped` return immédiat |
| 2 | Cible visible (`inMatch == 0`) | Pas de bouton Défier |
| 3 | `createChallenge` CloudKit OK | **Challengé ne voit rien ; challenger voit quand même « Invitation envoyée »** |
| 4 | `findMatch(playerGroup)` OK | Phase `.failed` côté challenger |
| 5 | Challengé rejoint avec même `playerGroup` ≤ ~60 s | Timeout challenger |

### Challengé

| # | Condition | Si faux |
|---|-----------|---------|
| 1 | Toggle « OK pour être défié » actif | Pas de polling |
| 2 | `isInActiveMatch == false` | Poll ignoré, bannière bloquée |
| 3 | Polling actif (app au premier plan) | Délai jusqu'à `didBecomeActive` |
| 4 | Fetch CloudKit réussit | `try?` avale l'erreur — silence total |
| 5 | Record `chal_{localID}` présent, HB < 90 s | Pas de notification |
| 6 | `challengerID ≠ lastNotifiedChallengerID` | Pas de re-notification (verrou anti-rebond) |
| 7 | Pas de bannière déjà affichée | Deuxième défi ignoré |
| 8 | Utilisateur regarde l'écran (bannière in-app) | Confusion avec « pas d'invitation GC » |
| 9 | Accept → `matchPlayerGroup` lu correctement depuis CloudKit | Voir bug Int64 ci-dessous |

---

## Matrice des échecs silencieux

| Symptôme utilisateur | Cause probable | Preuve dans les logs |
|---------------------|----------------|----------------------|
| « Invitation envoyée » mais l'autre ne voit rien | `createChallenge` échoué | `[Available] challenge create error:` |
| Les deux se voient, rien ne se passe | Attente d'une notif **Game Center** (mode A n'en envoie pas) | Pas de log d'erreur |
| Défi manqué pendant quelques secondes | App en arrière-plan (`willResignActive` arrête le poll) | Reprise au retour foreground |
| Re-défi immédiat après refus ignoré | `suppressChallengeWithDelay` 8 s | Normal si < 8 s |
| Re-défi du même adversaire sans refus | `lastNotifiedChallengerID` encore actif | Record `chal_*` non expiré |
| Partie précédente terminée bizarrement | `isInActiveMatch` resté à `true` | Poll jamais relancé |
| Acceptation mais match impossible | `eloRating` lu `as? Int` alors que CloudKit renvoie `Int64` → `playerGroup = 0` | Match échoue **après** bannière |
| Adversaire récent : erreur explicite | GameKit 5121 never played together | Message UI dédié |
| Classement : idem | Même restriction GC | `pvpLeaderboardInviteNotRecentPlayer` |

---

## Scénario rapporté — analyse

> Deux joueurs, même version, tous deux « OK pour être défié », visibles mutuellement dans le lobby, mais pas d'invitation quand l'un défie l'autre.

### Causes classées par probabilité

1. **Attente d'une notification Game Center** (très probable en test utilisateur)  
   Le mode « Joueurs disponibles » affiche « Invitation envoyée » côté challenger mais envoie une **bannière BLOMIX** côté challengé — slide-in vert en haut, texte « %@ vous défie ! », countdown 60 s. Aucun push système.

2. **`createChallenge` échoue silencieusement** (cause code la plus crédible)  
   Asymétrie délibérée : `publishAvailability` utilise une opération robuste avec feedback UI ; `createChallenge` utilise un simple `save()` sans remonter l'erreur. L'UI passe en `.inviting` **avant** l'écriture CloudKit.

3. **Polling suspendu sur l'appareil du challengé**  
   Notification iOS, Centre de contrôle, ou bascule d'app → `willResignActive` stoppe le poll. Le défi peut arriver avec jusqu'à ~4 s de latence au retour (ou plus si l'app reste en arrière-plan).

4. **Verrou `lastNotifiedChallengerID`**  
   Si les joueurs ont testé plusieurs fois (refus, timeout, défi expiré), un re-défi du même challenger dans la fenêtre de suppression peut être filtré.

5. **`isInActiveMatch` bloqué**  
   Si une partie PvP précédente n'a pas appelé `setActiveMatch(false)` (crash, déconnexion brutale), le polling et la bannière sont désactivés.

6. **Latence d'indexation CloudKit**  
   Les records de disponibilité et de défi partagent le même type et la même requête, mais un record `chal_*` fraîchement écrit peut mettre quelques secondes à apparaître dans les résultats de query.

### Ce qui est **peu probable** si « on se voit dans la liste »

- Game Center non authentifié (publish échouerait aussi)
- Même `teamPlayerID` (filtré de la liste)
- Version d'app différente (non vérifiée par le code)
- `inMatch == 1` (badge visible, pas de bouton Défier)

---

## Guide de debug (deux appareils / comptes GC)

### Côté challenger (après tap « Défier »)

1. Console Xcode : chercher `[Available] challenge created →` vs `challenge create error:`
2. Vérifier que l'écran affiche « Invitation envoyée à … » + countdown 60 s
3. CloudKit Dashboard → container `iCloud.blomig.BLOMIX` → record `chal_{gamePlayerID du challengé}`

### Côté challengé

1. Toggle vert « OK pour être défié » actif
2. Console : polling actif ? Pas de `[Available]` fetch errors ?
3. `isInActiveMatch` doit être false (partie solo OK)
4. **Regarder le haut de l'écran** — bannière ⚔️, pas une alerte Game Center
5. Si bannière absente après 10 s : vérifier record `chal_{mon gamePlayerID}` dans CloudKit Dashboard

### Préfixes de log utiles

| Préfixe | Source |
|---------|--------|
| `[Available]` | CloudKit disponibilité + défis |
| `[PvP]` | GameViewController, matchmaking |
| `[PvP AutoSearch]` | Recherche auto (non utilisée en prod UI) |
| `[PvP Lobby]` | Lobby phases |

---

## Bugs / dettes techniques

| ID | Description | Statut |
|----|-------------|--------|
| **PVP-1** | UI `.inviting` avant confirmation `createChallenge` | ✅ Corrigé — `.inviting` après succès CloudKit |
| **PVP-2** | `createChallenge` sans upsert robuste | ✅ Corrigé — `modifyRecords` + `.allKeys` |
| **PVP-3** | `pollForIncomingChallenge` : `try?` avale les erreurs | ✅ Corrigé — log `[Available] poll error:` |
| **PVP-4** | Lecture `eloRating as? Int` (schéma Int64) | ✅ Corrigé — `intFromRecord` + recalcul secours |
| **PVP-5** | Commentaires « ≤ 8 s » vs timer 4 s | ✅ Corrigé |
| **PVP-6** | Pas de `bringSubviewToFront` sur bannière | ✅ Corrigé |
| **PVP-7** | Mode auto-match non branché UI | Ouvert |
| **PVP-8** | Pas de gestion « défi croisé » mode CloudKit | Ouvert |
| **PVP-9** | Format `chal_{défié}` — WRITE not permitted CloudKit | ✅ Corrigé — format `chfrom_{challenger}` |
| **PVP-10** | Overlay déconnexion masqué derrière écran résultat | ✅ Corrigé — dismiss modal résultat d'abord |
| **PVP-11** | Revanche : UI « Lancement » avant sync réseau | ✅ Corrigé — launching via coordinateur uniquement |
| **PVP-12** | Revanche : helloSeed avant P2P prêt | ✅ Corrigé — `expectedPlayerCount == 0` |
| **PVP-13** | Revanche : pas d'overlay attente / timeout | ✅ Corrigé — overlay + retry 2 s + timeout 45 s |
| **PVP-14** | `matchFailed` silencieux | ✅ Corrigé — overlay « Connexion perdue » |

---

## Fichiers source

| Fichier | Responsabilité |
|---------|----------------|
| `BlomixAvailablePlayersManager.swift` | CloudKit, heartbeat, poll, rendez-vous |
| `BlomixPvPUI.swift` | Lobby, liste disponibles, récents, bannières |
| `GameViewController.swift` | Réception défis CloudKit + invites GK |
| `LeaderboardViewController.swift` | Défis depuis classement Elo |
| `BlomixPvPNetworking.swift` | Auto-searcher, coordinateur in-match |
| `GameScene.swift` | `setup()`, `setActiveMatch`, lancement PvP |

---

*Maintenir ce fichier lors de toute modification du flux PvP.*

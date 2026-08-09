//
//  BlomixPvPH2HManager.swift
//  Blomix
//
//  Historique tête-à-tête PvP (1 point = 1 manche gagnée) via CloudKit Public DB.
//
//  Isolation stricte : tout est best-effort / async. Un échec n’affecte que l’affichage
//  du total H2H — jamais le match, l’Elo, la série session ou la reconnexion.
//
//  Schéma CloudKit (Record Type `PvPH2HEvent`, Public DB) — à déployer en prod :
//    pairKey        String   Queryable
//    winnerID       String
//    loserID        String
//    channel        String   ("online" | "local")
//    clientEventId  String
//    createdAt      Date
//  recordName = "h2h_{clientEventId}" (créateur = vainqueur → WRITE OK).
//
//  Identité : GameKit expose parfois des chaînes différentes selon l’API
//  (`GKMatch` vs `GKLeaderboard.Entry`) pour le même joueur (`gamePlayerID` vs
//  `teamPlayerID`, formats `A:_…` vs hex). Le cache est multi-clés + alias ;
//  les queries cloud tentent les combinaisons d’IDs locaux/distants.
//
//  Réconciliation produit (v5.9 build 86+) — **vérité CloudKit** :
//  - Si fetch Public DB **OK** → affichage / cache = **uniquement** le compte cloud
//    (même total pour les deux joueurs, en miroir). Plus de max(cache/plancher).
//  - Pending vainqueur : flush agressif avant lecture ; **non** ajouté à l’affichage.
//  - Si fetch **KO** (réseau) → secours cache / plancher session (offline only).
//
//  Agrégation events (build 87+) — évite 12-10 vs 10-14 :
//  - Dédup par recordName / clientEventId (plus de somme aveugle multi-pairKey).
//  - Queries `winnerID ==` (si index Queryable) + pairKeys (IDs × connus × pending).
//  - Apprend les IDs winner/loser pour classer local vs remote de façon stable.
//  Console : idéalement `winnerID` **Queryable** (en plus de `pairKey`).
//

import CloudKit
import Foundation
import GameKit
import UIKit

// MARK: - Models

struct BlomixPvPH2HTotals: Equatable, Sendable, Codable {
    /// Victoires du joueur local face à cet adversaire.
    var localWins: Int
    /// Victoires de l’adversaire face au local.
    var remoteWins: Int

    static let zero = BlomixPvPH2HTotals(localWins: 0, remoteWins: 0)

    var hasHistory: Bool { localWins + remoteWins > 0 }

    /// Fusion conservative (max par côté) — évite de sous-compter si sources partielles.
    func merging(_ other: BlomixPvPH2HTotals) -> BlomixPvPH2HTotals {
        BlomixPvPH2HTotals(
            localWins: max(localWins, other.localWins),
            remoteWins: max(remoteWins, other.remoteWins)
        )
    }
}

// MARK: - Manager

@MainActor
final class BlomixPvPH2HManager {

    static let shared = BlomixPvPH2HManager()

    private let ckContainer = CKContainer(identifier: "iCloud.blomig.BLOMIX")
    private var publicDB: CKDatabase { ckContainer.publicCloudDatabase }
    private static let recordType = "PvPH2HEvent"

    /// Cache v2 : n’importe quel ID distant connu → totaux (POV local).
    private static let cacheKeyV2 = "blomixPvPH2HCache_v2"
    private static let cacheKeyV1 = "blomixPvPH2HCache_v1"
    private static let pendingKey = "blomixPvPH2HPending_v1"
    /// Alias ID → ID canonique (union-find aplati). Relie gamePlayerID ↔ teamPlayerID, etc.
    private static let aliasKey = "blomixPvPH2HAliases_v1"
    /// Plancher de session : confirmed + deltas tant que le cloud n’a pas rattrapé.
    private static let sessionFloorKey = "blomixPvPH2HSessionFloor_v1"
    /// pairKeys déjà vus (écriture ou lecture) — pour retrouver l’historique multi-ID.
    private static let knownPairKeysKey = "blomixPvPH2HKnownPairKeys_v1"
    /// Expire un plancher non rattrapé (évite inflation éternelle si bug d’enregistrement).
    private static let sessionFloorMaxAge: TimeInterval = 7 * 24 * 3600

    private var isFlushing = false
    private var didRegisterLifecycle = false
    private var didMigrateCache = false
    private var didPruneEmpty = false

    private init() {
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()
        pruneEmptyCacheEntriesIfNeeded()
    }

    private func registerLifecycleIfNeeded() {
        guard !didRegisterLifecycle else { return }
        didRegisterLifecycle = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingEventsBestEffort()
            }
        }
    }

    // MARK: - Pair key (CloudKit)

    /// Clé stable de la paire (ordre lexicographique des IDs).
    static func pairKey(localID: String, remoteID: String) -> String? {
        let a = localID.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = remoteID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty, a != b else { return nil }
        return [a, b].sorted().joined(separator: "|")
    }

    // MARK: - Public API (best-effort)

    /// Enregistre le résultat d’une manche. Fournir **tous** les IDs distants connus
    /// (`gamePlayerID`, `teamPlayerID`) pour que le classement Elo retrouve le cumul.
    /// - Parameter matchEventKey: clé stable optionnelle (ex. seed+index de manche) pour
    ///   idempotence cloud ; si omis → UUID (comportement historique).
    func recordMatchOutcome(
        localWon: Bool,
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil,
        channel: String,
        matchEventKey: String? = nil
    ) {
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()

        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        guard !remoteIDs.isEmpty else {
            print("[H2H] record skip — remote IDs vides")
            return
        }
        registerAliases(remoteIDs)

        let localIDs = resolvedLocalPlayerIDs()
        // IDs d’écriture cloud : priorité match-like (A:_…) pour coller à l’historique prod.
        guard let primaryLocal = Self.preferredCloudID(from: localIDs),
              let primaryRemote = Self.preferredCloudID(from: remoteIDs)
        else {
            print("[H2H] record skip — local ID manquant")
            return
        }

        guard let pair = Self.pairKey(localID: primaryLocal, remoteID: primaryRemote) else {
            print("[H2H] record skip — IDs manquants local=\(debugID(primaryLocal)) remote=\(debugID(primaryRemote))")
            return
        }

        // Cache optimiste + plancher de session (garde-fou cohérence jusqu’au rattrapage cloud).
        let before = cachedTotals(againstRemoteIDs: remoteIDs) ?? .zero
        var next = before
        if localWon {
            next.localWins += 1
        } else {
            next.remoteWins += 1
        }
        noteSessionOutcome(remoteIDs: remoteIDs, localWon: localWon, totalsBefore: before)
        replaceTotals(next, underRemoteIDs: remoteIDs)
        print("[H2H] cache \(localWon ? "win" : "loss") vs \(remoteIDs.map(debugID).joined(separator: ",")) → \(next.localWins)-\(next.remoteWins) \(debugDumpSessionSummary(forRemoteIDs: remoteIDs))")

        guard localWon else { return }

        let clientEventId = Self.stableClientEventId(matchEventKey: matchEventKey, pairKey: pair, winnerID: primaryLocal)
        // Idempotence : déjà en pending ou déjà traité récemment.
        if loadPending().contains(where: { $0.clientEventId == clientEventId }) {
            print("[H2H] win already pending event=\(clientEventId.prefix(12))…")
            flushPendingEventsBestEffort()
            return
        }

        let event = PendingH2HEvent(
            clientEventId: clientEventId,
            pairKey: pair,
            winnerID: primaryLocal,
            loserID: primaryRemote,
            channel: channel,
            createdAt: Date()
        )
        enqueuePending(event)
        print("[H2H] win queued event=\(event.clientEventId.prefix(12))… pair=\(String(pair.prefix(40)))…")
        // Flush immédiat + second essai asynchrone (réduit les Elo ouverts trop tôt).
        flushPendingEventsBestEffort()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.flushPendingEventsAsync()
        }
    }

    /// Totaux en cache pour un ID distant (suit les alias).
    func cachedTotals(against remoteGamePlayerID: String) -> BlomixPvPH2HTotals? {
        cachedTotals(againstRemoteIDs: [remoteGamePlayerID])
    }

    /// Totaux en cache pour un ensemble d’IDs (game + team + alias + pont nom).
    func cachedTotals(againstRemoteIDs remoteIDs: [String], displayName: String? = nil) -> BlomixPvPH2HTotals? {
        migrateCacheV1IfNeeded()
        if let displayName {
            bridgeAliasesUsingDisplayName(displayName, eloIDs: remoteIDs)
        }
        let keys = expandedRemoteIDs(remoteIDs)
        guard !keys.isEmpty else { return nil }
        let cache = loadCacheV2()
        var best: BlomixPvPH2HTotals?
        for key in keys {
            guard let t = cache[key] else { continue }
            best = best.map { $0.merging(t) } ?? t
        }
        return best
    }

    /// Rafraîchit depuis CloudKit (toutes combinaisons d’IDs plausibles). Ne throw pas vers l’UI.
    func refreshTotals(against remoteGamePlayerID: String) async -> BlomixPvPH2HTotals? {
        await refreshTotals(againstRemoteIDs: [remoteGamePlayerID], displayName: nil)
    }

    func refreshTotals(
        againstRemoteIDs remoteIDs: [String],
        displayName: String? = nil
    ) async -> BlomixPvPH2HTotals? {
        migrateCacheV1IfNeeded()
        if let displayName {
            bridgeAliasesUsingDisplayName(displayName, eloIDs: remoteIDs)
        }
        registerAliases(remoteIDs)

        let remotes = expandedRemoteIDs(remoteIDs)
        guard !remotes.isEmpty else {
            print("[H2H] refresh skip — no remote IDs")
            return nil
        }

        let localIDs = resolvedLocalPlayerIDs()
        guard !localIDs.isEmpty else {
            print("[H2H] refresh skip — no local IDs")
            return nil
        }

        let previous = cachedTotals(againstRemoteIDs: remotes)
        let floorState = sessionFloorState(forRemoteIDs: remotes)

        // Flush agressif (2 passes) pour pousser les wins avant lecture vérité cloud.
        await flushPendingEventsAsync()
        var pendingLeft = pendingLocalWins(localIDs: Set(localIDs), remoteIDs: Set(remotes))
        if pendingLeft > 0 {
            print("[H2H] pending after flush#1: \(pendingLeft) — retry")
            try? await Task.sleep(nanoseconds: 500_000_000)
            await flushPendingEventsAsync()
            pendingLeft = pendingLocalWins(localIDs: Set(localIDs), remoteIDs: Set(remotes))
        }
        if pendingLeft > 0 {
            print("[H2H] pending still \(pendingLeft) (affichage cloud sans les ajouter) — \(debugDumpPendingSummary())")
        }

        var cloudBundle = await fetchCloudSum(
            localIDs: localIDs,
            remotes: remotes,
            flushFirst: false
        )
        // Si encore du pending et cloud sous le plancher / cache, 3ᵉ passe flush+query.
        if pendingLeft > 0 || (floorState?.hasOpenSession == true) {
            let cloudL = cloudBundle.sum.localWins
            let cloudR = cloudBundle.sum.remoteWins
            let wantL = max(floorState?.floorLocal ?? 0, previous?.localWins ?? 0)
            let wantR = max(floorState?.floorRemote ?? 0, previous?.remoteWins ?? 0)
            if cloudL < wantL || cloudR < wantR || pendingLeft > 0 {
                print("[H2H] cloud \(cloudL)-\(cloudR) vs want~\(wantL)-\(wantR) — extra flush+query")
                try? await Task.sleep(nanoseconds: 400_000_000)
                await flushPendingEventsAsync()
                cloudBundle = await fetchCloudSum(
                    localIDs: localIDs,
                    remotes: remotes,
                    flushFirst: false
                )
                pendingLeft = pendingLocalWins(localIDs: Set(localIDs), remoteIDs: Set(remotes))
            }
        }

        let reconciled: BlomixPvPH2HTotals?
        if cloudBundle.querySucceeded {
            // ── Vérité CloudKit (identique pour les deux clients) ──
            // Pas de +pending, pas de max(cache), pas de plancher session.
            let total = cloudBundle.sum
            if total.hasHistory {
                replaceTotals(total, underRemoteIDs: remotes)
                print("[H2H] reconcile CLOUD-TRUTH \(total.localWins)-\(total.remoteWins) (raw cloud, pendingLeft=\(pendingLeft)) prev \(previous.map { "\($0.localWins)-\($0.remoteWins)" } ?? "nil")")
            } else {
                clearTotals(underRemoteIDs: remotes)
                print("[H2H] reconcile CLOUD-TRUTH empty (0 events) — cache cleared")
            }
            // Ferme le plancher : le cloud a tranché (même s’il est en retard d’un upload encore pending).
            forceCloseSessionFloor(remoteIDs: remotes, to: total)
            if !total.hasHistory {
                print("[H2H] refresh OK cloud empty remotes=\(remotes.prefix(2).map(debugID).joined(separator: ","))…")
            }
            return total.hasHistory ? total : nil
        }

        // ── Offline / CK down : secours local uniquement ──
        if let previous, previous.hasHistory {
            print("[H2H] refresh OFFLINE keep cache \(previous.localWins)-\(previous.remoteWins)")
            return previous
        }
        if let floor = floorState, floor.hasOpenSession {
            let total = BlomixPvPH2HTotals(localWins: floor.floorLocal, remoteWins: floor.floorRemote)
            replaceTotals(total, underRemoteIDs: remotes)
            print("[H2H] refresh OFFLINE session floor \(total.localWins)-\(total.remoteWins)")
            return total
        }

        print("[H2H] refresh empty remotes=\(remotes.prefix(3).map(debugID).joined(separator: ","))…")
        return previous
    }

    // MARK: - Cloud fetch helper (dédup events)

    private struct CloudSumBundle {
        var sum: BlomixPvPH2HTotals
        var anyHit: Bool
        var querySucceeded: Bool
    }

    private struct H2HCloudEvent {
        var recordName: String
        var winnerID: String
        var loserID: String
        var pairKey: String
        var clientEventId: String
    }

    private func fetchCloudSum(
        localIDs: [String],
        remotes: [String],
        flushFirst: Bool
    ) async -> CloudSumBundle {
        if flushFirst {
            await flushPendingEventsAsync()
        }

        var localSet = Set(localIDs)
        var remoteSet = Set(remotes)
        var unique: [String: H2HCloudEvent] = [:]
        var querySucceeded = false
        var winnerQueryUseful = false

        // 1) Queries par winnerID (même ensemble d’events des deux côtés si index Queryable).
        let winnerIDs = Array(localSet.union(remoteSet)).sorted { Self.idQueryPriority($0) > Self.idQueryPriority($1) }
        for wid in winnerIDs {
            do {
                let recs = try await fetchRecords(predicate: NSPredicate(format: "winnerID == %@", wid))
                querySucceeded = true
                winnerQueryUseful = true
                mergeCloudRecords(recs, into: &unique)
            } catch {
                // Index absent ou erreur : on bascule sur pairKey (pas fatal).
                print("[H2H] winnerID query fail id=\(debugID(wid)): \(error.localizedDescription)")
            }
        }

        // 2) Queries pairKey (IDs live + known + pending) — couvre l’historique même sans index winnerID.
        let pairKeys = candidatePairKeys(localIDs: Array(localSet), remotes: Array(remoteSet))
        for pair in pairKeys {
            do {
                let recs = try await fetchRecords(predicate: NSPredicate(format: "pairKey == %@", pair))
                querySucceeded = true
                mergeCloudRecords(recs, into: &unique)
                if !recs.isEmpty {
                    rememberPairKey(pair)
                    print("[H2H] cloud hit pair=\(String(pair.prefix(36)))… raw=\(recs.count)")
                }
            } catch {
                print("[H2H] pairKey query fail pair=\(String(pair.prefix(24)))…: \(error.localizedDescription)")
            }
        }

        // 3) Filtrer strictement le duo (winnerID renvoie toutes les wins vs tout le monde).
        //    Puis enrichir les sets d’IDs seulement à partir d’events déjà duo-valides.
        func isStrictDuo(_ ev: H2HCloudEvent, loc: Set<String>, rem: Set<String>) -> Bool {
            Self.eventInvolvesDuo(
                winnerID: ev.winnerID,
                loserID: ev.loserID,
                pairKey: ev.pairKey,
                localIDs: loc,
                remoteIDs: rem
            )
        }

        var duoEvents = unique.values.filter { isStrictDuo($0, loc: localSet, rem: remoteSet) }

        // Enrichissement borné : IDs alternatifs sur des events déjà reconnus duo.
        for ev in duoEvents {
            rememberPairKey(ev.pairKey)
            if remoteSet.contains(ev.loserID) || localSet.contains(ev.winnerID) {
                localSet.insert(ev.winnerID)
                remoteSet.insert(ev.loserID)
            }
            if localSet.contains(ev.loserID) || remoteSet.contains(ev.winnerID) {
                remoteSet.insert(ev.winnerID)
                localSet.insert(ev.loserID)
            }
        }
        // Re-filtre avec sets enrichis (récupère d’éventuels events orphelins du même duo).
        duoEvents = unique.values.filter { isStrictDuo($0, loc: localSet, rem: remoteSet) }

        let learnedLocal = localSet.subtracting(Set(localIDs))
        let learnedRemote = remoteSet.subtracting(Set(remotes))
        if !learnedLocal.isEmpty {
            registerAliases(Array(learnedLocal) + localIDs)
            print("[H2H] learned local IDs \(learnedLocal.map(debugID).joined(separator: ","))")
        }
        if !learnedRemote.isEmpty {
            registerAliases(Array(learnedRemote) + remotes)
            print("[H2H] learned remote IDs \(learnedRemote.map(debugID).joined(separator: ","))")
        }

        var localWins = 0
        var remoteWins = 0
        for ev in duoEvents {
            if Self.isLocalWinner(winnerID: ev.winnerID, localIDs: localSet, remoteIDs: remoteSet) {
                localWins += 1
            } else if remoteSet.contains(ev.winnerID) {
                remoteWins += 1
            } else {
                // Winner inconnu mais event duo via pairKey : l’autre côté du pair.
                remoteWins += 1
            }
        }

        let sum = BlomixPvPH2HTotals(localWins: localWins, remoteWins: remoteWins)
        if !duoEvents.isEmpty {
            print("[H2H] cloud unique events=\(duoEvents.count) pairsTried=\(pairKeys.count) winnerQ=\(winnerQueryUseful) → \(localWins)-\(remoteWins)")
        }
        return CloudSumBundle(sum: sum, anyHit: sum.hasHistory, querySucceeded: querySucceeded)
    }

    private func mergeCloudRecords(_ records: [CKRecord], into unique: inout [String: H2HCloudEvent]) {
        for rec in records {
            let name = rec.recordID.recordName
            let winner = (rec["winnerID"] as? String) ?? ""
            let loser = (rec["loserID"] as? String) ?? ""
            let pair = (rec["pairKey"] as? String) ?? ""
            let cid = (rec["clientEventId"] as? String) ?? name
            let key = cid.isEmpty ? name : cid
            guard !winner.isEmpty else { continue }
            unique[key] = H2HCloudEvent(
                recordName: name,
                winnerID: winner,
                loserID: loser,
                pairKey: pair,
                clientEventId: cid
            )
        }
    }

    private static func eventInvolvesDuo(
        winnerID: String,
        loserID: String,
        pairKey: String,
        localIDs: Set<String>,
        remoteIDs: Set<String>
    ) -> Bool {
        let winLocal = localIDs.contains(winnerID)
        let winRemote = remoteIDs.contains(winnerID)
        let loseLocal = localIDs.contains(loserID)
        let loseRemote = remoteIDs.contains(loserID)
        if (winLocal && loseRemote) || (winRemote && loseLocal) { return true }
        // pairKey historique : les deux IDs du duo.
        let parts = pairKey.split(separator: "|").map(String.init)
        if parts.count == 2 {
            let a = parts[0], b = parts[1]
            let aL = localIDs.contains(a), aR = remoteIDs.contains(a)
            let bL = localIDs.contains(b), bR = remoteIDs.contains(b)
            if (aL && bR) || (aR && bL) { return true }
        }
        return false
    }

    private static func isLocalWinner(
        winnerID: String,
        localIDs: Set<String>,
        remoteIDs: Set<String>
    ) -> Bool {
        if localIDs.contains(winnerID) { return true }
        if remoteIDs.contains(winnerID) { return false }
        // Inconnu : ne pas attribuer au local par défaut.
        return false
    }

    private func fetchRecords(predicate: NSPredicate) async throws -> [CKRecord] {
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (batch, next): ([CKRecord], CKQueryOperation.Cursor?) = try await withCheckedThrowingContinuation { cont in
                let op: CKQueryOperation
                if let cursor {
                    op = CKQueryOperation(cursor: cursor)
                } else {
                    op = CKQueryOperation(query: query)
                }
                op.qualityOfService = .userInitiated
                op.resultsLimit = 200
                var page: [CKRecord] = []
                op.recordMatchedBlock = { _, result in
                    if case .success(let rec) = result {
                        page.append(rec)
                    }
                }
                op.queryResultBlock = { result in
                    switch result {
                    case .success(let c):
                        cont.resume(returning: (page, c))
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
                publicDB.add(op)
            }
            all.append(contentsOf: batch)
            cursor = next
        } while cursor != nil

        return all
    }

    /// Enregistre que plusieurs IDs désignent le même joueur (game ↔ team, Elo ↔ match).
    func registerAliases(_ ids: [String]) {
        let clean = Self.normalizedIDList(ids)
        guard clean.count >= 2 else {
            // Même un seul ID : s’assurer qu’il se résout vers lui-même si déjà aliasé autrement — no-op.
            return
        }
        var map = loadAliases()
        let roots = clean.map { Self.aliasRoot($0, map: map) }
        // Canonique = préférence match-like (A:_), sinon le plus petit lexico pour stabilité.
        let canonical = roots.max(by: { Self.idQueryPriority($0) < Self.idQueryPriority($1) })
            ?? roots.sorted()[0]
        for id in clean {
            map[id] = canonical
        }
        // Replier les anciennes racines vers le nouveau canonique.
        for (k, v) in map {
            if roots.contains(v) || roots.contains(k) {
                map[k] = canonical
            }
        }
        for r in roots where r != canonical {
            map[r] = canonical
        }
        saveAliases(map)

        // Répliquer le meilleur cache sous toutes les clés du groupe (même total, pas de max artificiel).
        let group = clean.flatMap { expandedRemoteIDs([$0]) }
        if let best = cachedTotals(againstRemoteIDs: group), best.hasHistory {
            replaceTotals(best, underRemoteIDs: group)
        }
    }

    func flushPendingEventsBestEffort() {
        Task { @MainActor in
            await flushPendingEventsAsync()
        }
    }

    /// Debug / diagnostic cache + pending + session floors (logs Xcode / Console).
    func debugDumpCacheSummary() -> String {
        migrateCacheV1IfNeeded()
        pruneEmptyCacheEntriesIfNeeded()
        let c = loadCacheV2().filter { $0.value.hasHistory }
        let parts = c.map { "\(debugID($0.key)):\($0.value.localWins)-\($0.value.remoteWins)" }
        let aliasCount = loadAliases().count
        let pend = debugDumpPendingSummary()
        let sess = debugDumpSessionSummary()
        return "entries=\(c.count) aliases=\(aliasCount) [\(parts.joined(separator: ", "))] localIDs=\(resolvedLocalPlayerIDs().map(debugID).joined(separator: ",")) \(pend) \(sess)"
    }

    /// Wins locales en attente d’upload CloudKit (ce qui « traîne » sur cet iPhone).
    func debugDumpPendingSummary() -> String {
        let pending = loadPending()
        if pending.isEmpty { return "pending=0" }
        let bits = pending.prefix(12).map { e in
            let age = Int(Date().timeIntervalSince(e.createdAt))
            return "\(e.clientEventId.prefix(8))… ch=\(e.channel) age=\(age)s pair=\(String(e.pairKey.prefix(28)))…"
        }
        let more = pending.count > 12 ? " +\(pending.count - 12) more" : ""
        return "pending=\(pending.count) [\(bits.joined(separator: "; "))]\(more)"
    }

    /// Nombre d’events vainqueur non encore uploadés (diagnostic).
    func pendingUploadCount() -> Int {
        loadPending().count
    }

    func debugDumpSessionSummary(forRemoteIDs remoteIDs: [String] = []) -> String {
        if remoteIDs.isEmpty {
            let all = loadSessionFloors().filter { $0.value.hasOpenSession }
            if all.isEmpty { return "sessionFloors=0" }
            let bits = all.prefix(6).map { "\(debugID($0.key)):\($0.value.floorLocal)-\($0.value.floorRemote)(d\($0.value.deltaLocal)/\($0.value.deltaRemote))" }
            return "sessionFloors=\(all.count) [\(bits.joined(separator: ", "))]"
        }
        guard let s = sessionFloorState(forRemoteIDs: remoteIDs) else { return "session=nil" }
        return "session conf=\(s.confirmedLocal)-\(s.confirmedRemote) Δ=\(s.deltaLocal)/\(s.deltaRemote) floor=\(s.floorLocal)-\(s.floorRemote)"
    }

    // MARK: - Session floor (garde-fou)

    /// État de session pour un adversaire : baseline confirmée + manches locales non encore « rattrapées » par le cloud.
    private struct SessionFloorState: Codable, Equatable {
        var confirmedLocal: Int
        var confirmedRemote: Int
        var deltaLocal: Int
        var deltaRemote: Int
        var updatedAt: Date

        var floorLocal: Int { confirmedLocal + deltaLocal }
        var floorRemote: Int { confirmedRemote + deltaRemote }
        var hasOpenSession: Bool { deltaLocal > 0 || deltaRemote > 0 }
    }

    private func noteSessionOutcome(
        remoteIDs: [String],
        localWon: Bool,
        totalsBefore: BlomixPvPH2HTotals
    ) {
        let key = sessionStorageKey(forRemoteIDs: remoteIDs)
        var all = loadSessionFloors()
        var state = all[key] ?? SessionFloorState(
            confirmedLocal: totalsBefore.localWins,
            confirmedRemote: totalsBefore.remoteWins,
            deltaLocal: 0,
            deltaRemote: 0,
            updatedAt: Date()
        )
        // Première manche de la « session ouverte » : baseline = total avant outcome.
        if !state.hasOpenSession {
            state.confirmedLocal = totalsBefore.localWins
            state.confirmedRemote = totalsBefore.remoteWins
            state.deltaLocal = 0
            state.deltaRemote = 0
        }
        if localWon {
            state.deltaLocal += 1
        } else {
            state.deltaRemote += 1
        }
        state.updatedAt = Date()
        all[key] = state
        // Répliquer sous les alias pour lookup Elo multi-ID.
        for rid in expandedRemoteIDs(remoteIDs) {
            all[rid] = state
        }
        saveSessionFloors(all)
        print("[H2H] session floor note \(localWon ? "W" : "L") → conf \(state.confirmedLocal)-\(state.confirmedRemote) Δ\(state.deltaLocal)/\(state.deltaRemote) floor \(state.floorLocal)-\(state.floorRemote)")
    }

    private func sessionFloorState(forRemoteIDs remoteIDs: [String]) -> SessionFloorState? {
        let all = loadSessionFloors()
        let keys = expandedRemoteIDs(remoteIDs)
        var best: SessionFloorState?
        for k in keys {
            guard var s = all[k] else { continue }
            if Date().timeIntervalSince(s.updatedAt) > Self.sessionFloorMaxAge {
                continue
            }
            if !s.hasOpenSession { continue }
            if let b = best {
                // Garde le plancher le plus haut (sécurité multi-clés).
                if s.floorLocal + s.floorRemote > b.floorLocal + b.floorRemote {
                    best = s
                }
            } else {
                best = s
            }
        }
        return best
    }

    /// Ferme le plancher après un fetch cloud OK (vérité partagée = cloud).
    private func forceCloseSessionFloor(remoteIDs: [String], to displayed: BlomixPvPH2HTotals) {
        var all = loadSessionFloors()
        let cleared = SessionFloorState(
            confirmedLocal: displayed.localWins,
            confirmedRemote: displayed.remoteWins,
            deltaLocal: 0,
            deltaRemote: 0,
            updatedAt: Date()
        )
        let key = sessionStorageKey(forRemoteIDs: remoteIDs)
        all[key] = cleared
        for rid in expandedRemoteIDs(remoteIDs) {
            all[rid] = cleared
        }
        saveSessionFloors(all)
        print("[H2H] session floor closed → conf \(cleared.confirmedLocal)-\(cleared.confirmedRemote) (cloud-truth)")
    }

    private func sessionStorageKey(forRemoteIDs remoteIDs: [String]) -> String {
        let expanded = expandedRemoteIDs(remoteIDs)
        if let pref = Self.preferredCloudID(from: expanded) { return pref }
        return expanded.sorted().first ?? "unknown"
    }

    private func loadSessionFloors() -> [String: SessionFloorState] {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionFloorKey),
              let decoded = try? JSONDecoder().decode([String: SessionFloorState].self, from: data)
        else { return [:] }
        // Purge expirés.
        let now = Date()
        return decoded.filter { now.timeIntervalSince($0.value.updatedAt) <= Self.sessionFloorMaxAge }
    }

    private func saveSessionFloors(_ map: [String: SessionFloorState]) {
        if map.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.sessionFloorKey)
            return
        }
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.sessionFloorKey)
        }
    }

    // MARK: - CloudKit

    private func flushPendingEventsAsync() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let pending = loadPending()
        guard !pending.isEmpty else { return }

        var remaining: [PendingH2HEvent] = []
        for event in pending {
            do {
                try await saveEventToCloud(event)
                print("[H2H] uploaded \(event.clientEventId.prefix(8))…")
            } catch {
                print("[H2H] upload fail (kept pending): \(error.localizedDescription)")
                remaining.append(event)
            }
        }
        savePending(remaining)
    }

    private func saveEventToCloud(_ event: PendingH2HEvent) async throws {
        let recID = CKRecord.ID(recordName: "h2h_\(event.clientEventId)")
        let record = CKRecord(recordType: Self.recordType, recordID: recID)
        record["pairKey"] = event.pairKey as CKRecordValue
        record["winnerID"] = event.winnerID as CKRecordValue
        record["loserID"] = event.loserID as CKRecordValue
        record["channel"] = event.channel as CKRecordValue
        record["clientEventId"] = event.clientEventId as CKRecordValue
        record["createdAt"] = event.createdAt as CKRecordValue

        do {
            _ = try await publicDB.save(record)
            rememberPairKey(event.pairKey)
        } catch {
            if isIdempotentCloudSuccess(error) {
                rememberPairKey(event.pairKey)
                return
            }
            throw error
        }
    }

    private func isIdempotentCloudSuccess(_ error: Error) -> Bool {
        if let ck = error as? CKError {
            switch ck.code {
            case .serverRecordChanged, .batchRequestFailed, .partialFailure:
                // Record déjà présent (re-flush / clientEventId stable) → succès.
                return true
            default:
                break
            }
        }
        let msg = error.localizedDescription.lowercased()
        return msg.contains("already exists")
            || msg.contains("duplicate")
            || msg.contains("unique")
            || msg.contains("server record changed")
    }

    // MARK: - Known pairKeys

    private func rememberPairKey(_ pairKey: String) {
        let p = pairKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.contains("|") else { return }
        var set = loadKnownPairKeys()
        guard set.insert(p).inserted else { return }
        saveKnownPairKeys(set)
    }

    private func loadKnownPairKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: Self.knownPairKeysKey),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    private func saveKnownPairKeys(_ set: Set<String>) {
        let arr = Array(set).sorted()
        if arr.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.knownPairKeysKey)
            return
        }
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: Self.knownPairKeysKey)
        }
    }

    /// pairKeys candidats pour ce duo (IDs live × connus × pending).
    private func candidatePairKeys(localIDs: [String], remotes: [String]) -> [String] {
        var keys = Set<String>()
        for local in localIDs {
            for remote in remotes {
                if let p = Self.pairKey(localID: local, remoteID: remote) {
                    keys.insert(p)
                }
            }
        }
        let localSet = Set(localIDs)
        let remoteSet = Set(remotes)
        for pk in loadKnownPairKeys() {
            let parts = pk.split(separator: "|").map(String.init)
            guard parts.count == 2 else { continue }
            let a = parts[0], b = parts[1]
            let touchesLocal = localSet.contains(a) || localSet.contains(b)
            let touchesRemote = remoteSet.contains(a) || remoteSet.contains(b)
            if touchesLocal && touchesRemote {
                keys.insert(pk)
            }
        }
        for event in loadPending() {
            let parts = event.pairKey.split(separator: "|").map(String.init)
            guard parts.count == 2 else { continue }
            let a = parts[0], b = parts[1]
            if (localSet.contains(a) || localSet.contains(b))
                && (remoteSet.contains(a) || remoteSet.contains(b)
                    || remoteSet.contains(event.loserID) || localSet.contains(event.winnerID)) {
                keys.insert(event.pairKey)
            }
        }
        return keys.sorted()
    }

    // MARK: - Identity

    /// Tous les IDs locaux utiles pour pairKey / winnerID (game puis team).
    private func resolvedLocalPlayerIDs() -> [String] {
        var raw: [String] = []
        let live = GKLocalPlayer.local
        raw.append(live.gamePlayerID)
        raw.append(live.teamPlayerID)
        if let cached = BlomixEloManager.shared.cachedLocalGameIdentity()?.gamePlayerID {
            raw.append(cached)
        }
        return Self.normalizedIDList(raw)
    }

    /// Priorité de tentative query / écriture : IDs style match `A:_…` d’abord (historique cloud).
    private static func idQueryPriority(_ id: String) -> Int {
        if id.hasPrefix("A:_") || id.hasPrefix("G:") || id.hasPrefix("T:") { return 3 }
        if id.contains(":") { return 2 }
        return 1
    }

    /// ID préféré pour pairKey / winnerID / loserID (stable avec l’historique prod).
    private static func preferredCloudID(from ids: [String]) -> String? {
        let clean = normalizedIDList(ids)
        guard !clean.isEmpty else { return nil }
        return clean.max(by: {
            if idQueryPriority($0) != idQueryPriority($1) {
                return idQueryPriority($0) < idQueryPriority($1)
            }
            // À priorité égale : lexico plus petit (déterministe).
            return $0 > $1
        })
    }

    /// `clientEventId` cloud : stable si `matchEventKey` fourni (idempotence), sinon UUID.
    private static func stableClientEventId(
        matchEventKey: String?,
        pairKey: String,
        winnerID: String
    ) -> String {
        let raw = (matchEventKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return UUID().uuidString }
        let material = "\(pairKey)|\(winnerID)|\(raw)"
        // UUID-like déterministe (32 hex) — recordName `h2h_<id>` reste unique par manche.
        let digest = Self.fnv1a64(material)
        let hex = String(digest, radix: 16, uppercase: true)
        return "M" + hex.padding(toLength: 15, withPad: "0", startingAt: 0) + String(material.count, radix: 16)
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for b in string.utf8 {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Nombre de wins locales encore en pending pour ce duo (après flush partiel).
    private func pendingLocalWins(localIDs: Set<String>, remoteIDs: Set<String>) -> Int {
        let pending = loadPending()
        guard !pending.isEmpty else { return 0 }
        var n = 0
        for event in pending {
            guard localIDs.contains(event.winnerID) else { continue }
            // loserID doit être l’adversaire (ou un de ses alias déjà dans remoteIDs).
            if remoteIDs.contains(event.loserID) {
                n += 1
                continue
            }
            // pairKey contient les deux IDs triés.
            let parts = event.pairKey.split(separator: "|").map(String.init)
            if parts.count == 2 {
                let a = parts[0], b = parts[1]
                let touchesLocal = localIDs.contains(a) || localIDs.contains(b)
                let touchesRemote = remoteIDs.contains(a) || remoteIDs.contains(b)
                if touchesLocal && touchesRemote { n += 1 }
            }
        }
        return n
    }

    private static func isUsablePlayerID(_ id: String) -> Bool {
        let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t == "GKPlayerIDUnknown" { return false }
        return true
    }

    private static func normalizedIDList(_ ids: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for id in ids {
            let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsablePlayerID(t), seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return out
    }

    private func expandedRemoteIDs(_ remoteIDs: [String]) -> [String] {
        let map = loadAliases()
        var seen = Set<String>()
        var out: [String] = []
        for id in Self.normalizedIDList(remoteIDs) {
            let root = Self.aliasRoot(id, map: map)
            // Toutes les clés qui partagent cette racine + l’id lui-même.
            let group = map.compactMap { k, v -> String? in
                Self.aliasRoot(k, map: map) == root || Self.aliasRoot(v, map: map) == root ? k : nil
            } + [id, root]
            for g in group where seen.insert(g).inserted {
                out.append(g)
            }
        }
        return out
    }

    /// Pont de secours : même displayName qu’un adversaire récent (ID match `A:_…`).
    private func bridgeAliasesUsingDisplayName(_ displayName: String, eloIDs: [String]) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let recent = BlomixRecentOpponentsCache.shared.all()
        let matches = recent.filter {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame
        }
        guard !matches.isEmpty else { return }
        var ids = eloIDs
        for m in matches {
            ids.append(m.gamePlayerID)
        }
        // Aussi : si le cache a une seule entrée avec historique et le nom matche via recent → déjà couvert.
        registerAliases(ids)
        print("[H2H] alias via displayName «\(name)» → \(Self.normalizedIDList(ids).map(debugID).joined(separator: ","))")
    }

    private func debugID(_ id: String) -> String {
        guard !id.isEmpty else { return "∅" }
        if id.count <= 14 { return id }
        return String(id.prefix(10)) + "…" + String(id.suffix(4))
    }

    private func describeCache(_ remoteID: String) -> String {
        if let t = cachedTotals(againstRemoteIDs: [remoteID]), t.hasHistory {
            return "\(t.localWins)-\(t.remoteWins)"
        }
        return "nil"
    }

    // MARK: - Cache v2 (remoteID → totals)

    private struct PendingH2HEvent: Codable, Equatable {
        var clientEventId: String
        var pairKey: String
        var winnerID: String
        var loserID: String
        var channel: String
        var createdAt: Date
    }

    private func loadCacheV2() -> [String: BlomixPvPH2HTotals] {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKeyV2),
              let decoded = try? JSONDecoder().decode([String: BlomixPvPH2HTotals].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveCacheV2(_ cache: [String: BlomixPvPH2HTotals]) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKeyV2)
        }
    }

    /// Écrit le total **tel quel** sous toutes les clés (réconciliation cloud-first).
    private func replaceTotals(_ totals: BlomixPvPH2HTotals, underRemoteIDs remoteIDs: [String]) {
        var cache = loadCacheV2()
        let keys = expandedRemoteIDs(remoteIDs)
        if totals.hasHistory {
            for rid in keys {
                cache[rid] = totals
            }
        } else {
            for rid in keys {
                cache.removeValue(forKey: rid)
            }
        }
        cache = cache.filter { $0.value.hasHistory }
        saveCacheV2(cache)
    }

    private func clearTotals(underRemoteIDs remoteIDs: [String]) {
        replaceTotals(.zero, underRemoteIDs: remoteIDs)
    }

    private func pruneEmptyCacheEntriesIfNeeded() {
        guard !didPruneEmpty else { return }
        didPruneEmpty = true
        let cache = loadCacheV2()
        let pruned = cache.filter { $0.value.hasHistory }
        if pruned.count != cache.count {
            saveCacheV2(pruned)
            print("[H2H] pruned empty cache entries \(cache.count)→\(pruned.count)")
        }
    }

    /// Migre l’ancien cache pairKey → remoteID (POV local).
    private func migrateCacheV1IfNeeded() {
        guard !didMigrateCache else { return }
        didMigrateCache = true
        guard UserDefaults.standard.data(forKey: Self.cacheKeyV2) == nil,
              let data = UserDefaults.standard.data(forKey: Self.cacheKeyV1),
              let old = try? JSONDecoder().decode([String: BlomixPvPH2HTotals].self, from: data),
              !old.isEmpty
        else { return }

        let localIDs = Set(resolvedLocalPlayerIDs())
        var neu: [String: BlomixPvPH2HTotals] = [:]
        for (pair, totals) in old {
            let parts = pair.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { continue }
            let a = parts[0], b = parts[1]
            let remote: String
            if localIDs.contains(a) {
                remote = b
            } else if localIDs.contains(b) {
                remote = a
            } else {
                continue
            }
            guard !remote.isEmpty else { continue }
            if let existing = neu[remote] {
                neu[remote] = existing.merging(totals)
            } else {
                neu[remote] = totals
            }
        }
        if !neu.isEmpty {
            saveCacheV2(neu)
            print("[H2H] migrated cache v1→v2 entries=\(neu.count)")
        }
    }

    // MARK: - Aliases

    private func loadAliases() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: Self.aliasKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveAliases(_ map: [String: String]) {
        if map.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.aliasKey)
            return
        }
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.aliasKey)
        }
    }

    private static func aliasRoot(_ id: String, map: [String: String]) -> String {
        var current = id
        var guardCounter = 0
        while let next = map[current], next != current, guardCounter < 16 {
            current = next
            guardCounter += 1
        }
        return current
    }

    // MARK: - Pending

    private func loadPending() -> [PendingH2HEvent] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingKey),
              let decoded = try? JSONDecoder().decode([PendingH2HEvent].self, from: data)
        else { return [] }
        return decoded
    }

    private func savePending(_ events: [PendingH2HEvent]) {
        if events.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.pendingKey)
            return
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
    }

    private func enqueuePending(_ event: PendingH2HEvent) {
        var pending = loadPending()
        if pending.contains(where: { $0.clientEventId == event.clientEventId }) { return }
        pending.append(event)
        if pending.count > 100 {
            pending = Array(pending.suffix(100))
        }
        savePending(pending)
    }
}

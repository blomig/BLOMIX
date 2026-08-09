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
    func recordMatchOutcome(
        localWon: Bool,
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil,
        channel: String
    ) {
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()

        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        guard let primaryRemote = remoteIDs.first else {
            print("[H2H] record skip — remote IDs vides")
            return
        }
        registerAliases(remoteIDs)

        let localIDs = resolvedLocalPlayerIDs()
        guard let primaryLocal = localIDs.first else {
            print("[H2H] record skip — local ID manquant")
            return
        }

        // pairKey cloud : préférer gamePlayerID live (historique existant en `A:_…`).
        guard let pair = Self.pairKey(localID: primaryLocal, remoteID: primaryRemote) else {
            print("[H2H] record skip — IDs manquants local=\(debugID(primaryLocal)) remote=\(debugID(primaryRemote))")
            return
        }

        // Une seule incrémentation, puis réplication sous toutes les clés / alias (évite double-count).
        var next = cachedTotals(againstRemoteIDs: remoteIDs) ?? .zero
        if localWon {
            next.localWins += 1
        } else {
            next.remoteWins += 1
        }
        writeTotals(next, underRemoteIDs: remoteIDs)
        print("[H2H] cache \(localWon ? "win" : "loss") vs \(remoteIDs.map(debugID).joined(separator: ",")) → \(next.localWins)-\(next.remoteWins)")

        guard localWon else { return }

        let event = PendingH2HEvent(
            clientEventId: UUID().uuidString,
            pairKey: pair,
            winnerID: primaryLocal,
            loserID: primaryRemote,
            channel: channel,
            createdAt: Date()
        )
        enqueuePending(event)
        print("[H2H] win queued event=\(event.clientEventId.prefix(8))… pair=\(String(pair.prefix(40)))…")
        flushPendingEventsBestEffort()
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
        await flushPendingEventsAsync()

        let localSet = Set(localIDs)
        var cloudBest = BlomixPvPH2HTotals.zero
        var anyCloudHit = false
        var triedPairs = Set<String>()

        // Essayer d’abord les paires « match-like » (préfixe A:_), puis le reste.
        let orderedLocals = localIDs.sorted { Self.idQueryPriority($0) > Self.idQueryPriority($1) }
        let orderedRemotes = remotes.sorted { Self.idQueryPriority($0) > Self.idQueryPriority($1) }

        for local in orderedLocals {
            for remote in orderedRemotes {
                guard let pair = Self.pairKey(localID: local, remoteID: remote) else { continue }
                guard triedPairs.insert(pair).inserted else { continue }
                do {
                    let cloud = try await fetchTotalsFromCloud(pairKey: pair, localIDs: localSet)
                    if cloud.hasHistory {
                        cloudBest = cloudBest.merging(cloud)
                        anyCloudHit = true
                        print("[H2H] cloud hit pair=\(String(pair.prefix(36)))… → \(cloud.localWins)-\(cloud.remoteWins)")
                        // Une paire fertile suffit en pratique (même duo).
                        break
                    }
                } catch {
                    print("[H2H] cloud query fail pair=\(String(pair.prefix(24)))…: \(error.localizedDescription)")
                }
            }
            if anyCloudHit { break }
        }

        let merged: BlomixPvPH2HTotals
        if let previous, previous.hasHistory, !cloudBest.hasHistory {
            merged = previous
            print("[H2H] refresh keep cache (cloud empty) \(previous.localWins)-\(previous.remoteWins)")
        } else if let previous {
            merged = previous.merging(cloudBest)
        } else {
            merged = cloudBest
        }

        // Ne pas polluer le cache avec des 0-0 (c’était la source des 79 clés vides).
        if merged.hasHistory {
            writeTotals(merged, underRemoteIDs: remotes)
            print("[H2H] refresh OK remotes=\(remotes.map(debugID).joined(separator: ",")) → \(merged.localWins)-\(merged.remoteWins) (cloud \(cloudBest.localWins)-\(cloudBest.remoteWins))")
            return merged
        }

        print("[H2H] refresh empty remotes=\(remotes.prefix(3).map(debugID).joined(separator: ","))…")
        return previous
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

        // Répliquer le meilleur cache sous toutes les clés du groupe.
        let group = clean.flatMap { expandedRemoteIDs([$0]) }
        if let best = cachedTotals(againstRemoteIDs: group), best.hasHistory {
            writeTotals(best, underRemoteIDs: group)
        }
    }

    func flushPendingEventsBestEffort() {
        Task { @MainActor in
            await flushPendingEventsAsync()
        }
    }

    /// Debug / diagnostic.
    func debugDumpCacheSummary() -> String {
        migrateCacheV1IfNeeded()
        pruneEmptyCacheEntriesIfNeeded()
        let c = loadCacheV2().filter { $0.value.hasHistory }
        let parts = c.map { "\(debugID($0.key)):\($0.value.localWins)-\($0.value.remoteWins)" }
        let aliasCount = loadAliases().count
        return "entries=\(c.count) aliases=\(aliasCount) [\(parts.joined(separator: ", "))] localIDs=\(resolvedLocalPlayerIDs().map(debugID).joined(separator: ","))"
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
        } catch {
            if isIdempotentCloudSuccess(error) { return }
            throw error
        }
    }

    private func isIdempotentCloudSuccess(_ error: Error) -> Bool {
        if let ck = error as? CKError {
            switch ck.code {
            case .serverRecordChanged, .batchRequestFailed:
                return true
            default:
                break
            }
        }
        let msg = error.localizedDescription.lowercased()
        return msg.contains("already exists") || msg.contains("duplicate") || msg.contains("unique")
    }

    private func fetchTotalsFromCloud(
        pairKey: String,
        localIDs: Set<String>
    ) async throws -> BlomixPvPH2HTotals {
        let predicate = NSPredicate(format: "pairKey == %@", pairKey)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)

        var localWins = 0
        var remoteWins = 0
        var cursor: CKQueryOperation.Cursor?
        var totalRecords = 0

        repeat {
            let (records, next): ([CKRecord], CKQueryOperation.Cursor?) = try await withCheckedThrowingContinuation { cont in
                let op: CKQueryOperation
                if let cursor {
                    op = CKQueryOperation(cursor: cursor)
                } else {
                    op = CKQueryOperation(query: query)
                }
                op.qualityOfService = .userInitiated
                op.resultsLimit = 200
                var batch: [CKRecord] = []
                op.recordMatchedBlock = { _, result in
                    if case .success(let rec) = result {
                        batch.append(rec)
                    }
                }
                op.queryResultBlock = { result in
                    switch result {
                    case .success(let c):
                        cont.resume(returning: (batch, c))
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
                publicDB.add(op)
            }

            totalRecords += records.count
            for rec in records {
                let winner = (rec["winnerID"] as? String) ?? ""
                if localIDs.contains(winner) {
                    localWins += 1
                } else if !winner.isEmpty {
                    remoteWins += 1
                }
            }
            cursor = next
        } while cursor != nil

        if totalRecords > 0 {
            print("[H2H] cloud query pair=\(String(pairKey.prefix(32)))… records=\(totalRecords) → \(localWins)-\(remoteWins)")
        }
        return BlomixPvPH2HTotals(localWins: localWins, remoteWins: remoteWins)
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

    /// Priorité de tentative query : IDs style match `A:_…` d’abord (historique cloud).
    private static func idQueryPriority(_ id: String) -> Int {
        if id.hasPrefix("A:_") || id.hasPrefix("G:") || id.hasPrefix("T:") { return 3 }
        if id.contains(":") { return 2 }
        return 1
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

    private func writeTotals(_ totals: BlomixPvPH2HTotals, underRemoteIDs remoteIDs: [String]) {
        guard totals.hasHistory else { return }
        var cache = loadCacheV2()
        for rid in expandedRemoteIDs(remoteIDs) {
            if let existing = cache[rid] {
                cache[rid] = existing.merging(totals)
            } else {
                cache[rid] = totals
            }
        }
        // Nettoyage opportuniste des 0-0.
        cache = cache.filter { $0.value.hasHistory }
        saveCacheV2(cache)
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

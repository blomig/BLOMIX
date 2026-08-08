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

import CloudKit
import Foundation
import GameKit
import UIKit

// MARK: - Models

struct BlomixPvPH2HTotals: Equatable, Sendable {
    /// Victoires du joueur local face à cet adversaire.
    var localWins: Int
    /// Victoires de l’adversaire face au local.
    var remoteWins: Int

    static let zero = BlomixPvPH2HTotals(localWins: 0, remoteWins: 0)
}

// MARK: - Manager

@MainActor
final class BlomixPvPH2HManager {

    static let shared = BlomixPvPH2HManager()

    private let ckContainer = CKContainer(identifier: "iCloud.blomig.BLOMIX")
    private var publicDB: CKDatabase { ckContainer.publicCloudDatabase }
    private static let recordType = "PvPH2HEvent"

    private static let cacheKey = "blomixPvPH2HCache_v1"
    private static let pendingKey = "blomixPvPH2HPending_v1"

    private var isFlushing = false
    private var didRegisterLifecycle = false

    private init() {
        registerLifecycleIfNeeded()
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

    // MARK: - Pair key

    /// Clé stable de la paire (ordre lexicographique des gamePlayerID).
    static func pairKey(localID: String, remoteID: String) -> String? {
        let a = localID.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = remoteID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty, a != b else { return nil }
        return [a, b].sorted().joined(separator: "|")
    }

    // MARK: - Public API (best-effort)

    /// Appelé après une fin de manche validée. N’throws jamais vers l’appelant.
    /// - localWon: true → le local a gagné (écrit l’event cloud + cache).
    /// - localWon: false → le local a perdu (cache optimiste seulement ; le vainqueur écrit le cloud).
    func recordMatchOutcome(
        localWon: Bool,
        remoteGamePlayerID: String,
        channel: String
    ) {
        registerLifecycleIfNeeded()
        let localID = resolvedLocalGamePlayerID()
        guard let pair = Self.pairKey(localID: localID, remoteID: remoteGamePlayerID) else {
            print("[H2H] record skip — IDs manquants")
            return
        }

        // Cache optimiste immédiat (affichage).
        mutateCache(pairKey: pair, localID: localID) { totals in
            if localWon {
                totals.localWins += 1
            } else {
                totals.remoteWins += 1
            }
        }

        guard localWon else {
            // Le vainqueur distant est responsable de l’event cloud.
            print("[H2H] loss cached optimistically pair=\(String(pair.prefix(24)))…")
            return
        }

        let event = PendingH2HEvent(
            clientEventId: UUID().uuidString,
            pairKey: pair,
            winnerID: localID,
            loserID: remoteGamePlayerID,
            channel: channel,
            createdAt: Date()
        )
        enqueuePending(event)
        print("[H2H] win queued event=\(event.clientEventId.prefix(8))…")
        flushPendingEventsBestEffort()
    }

    /// Totaux en cache local (immédiat, peut être stale).
    func cachedTotals(against remoteGamePlayerID: String) -> BlomixPvPH2HTotals? {
        let localID = resolvedLocalGamePlayerID()
        guard let pair = Self.pairKey(localID: localID, remoteID: remoteGamePlayerID) else { return nil }
        return loadCache()[pair]
    }

    /// Rafraîchit depuis CloudKit puis met à jour le cache. Ne throw pas vers l’UI.
    func refreshTotals(against remoteGamePlayerID: String) async -> BlomixPvPH2HTotals? {
        let localID = resolvedLocalGamePlayerID()
        guard let pair = Self.pairKey(localID: localID, remoteID: remoteGamePlayerID) else { return nil }
        // Flush d’abord pour que nos wins pending comptent dans le fetch.
        await flushPendingEventsAsync()
        do {
            let totals = try await fetchTotalsFromCloud(pairKey: pair, localID: localID)
            var cache = loadCache()
            cache[pair] = totals
            saveCache(cache)
            print("[H2H] refresh OK pair=\(String(pair.prefix(24)))… local=\(totals.localWins) remote=\(totals.remoteWins)")
            return totals
        } catch {
            print("[H2H] refresh failed (non-fatal): \(error.localizedDescription)")
            return loadCache()[pair]
        }
    }

    /// Déclenche un flush pending sans attendre.
    func flushPendingEventsBestEffort() {
        Task { @MainActor in
            await flushPendingEventsAsync()
        }
    }

    // MARK: - CloudKit write / read

    private func flushPendingEventsAsync() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        var pending = loadPending()
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
            // Retry / record déjà présent → succès idempotent (même clientEventId).
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

    private func fetchTotalsFromCloud(pairKey: String, localID: String) async throws -> BlomixPvPH2HTotals {
        let predicate = NSPredicate(format: "pairKey == %@", pairKey)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        // Pas de sort obligatoire.

        var localWins = 0
        var remoteWins = 0
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (records, next): ([CKRecord], CKQueryOperation.Cursor?) = try await withCheckedThrowingContinuation { cont in
                let op: CKQueryOperation
                if let cursor {
                    op = CKQueryOperation(cursor: cursor)
                } else {
                    op = CKQueryOperation(query: query)
                }
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

            for rec in records {
                let winner = rec["winnerID"] as? String ?? ""
                if winner == localID {
                    localWins += 1
                } else if !winner.isEmpty {
                    remoteWins += 1
                }
            }
            cursor = next
        } while cursor != nil

        return BlomixPvPH2HTotals(localWins: localWins, remoteWins: remoteWins)
    }

    // MARK: - Identity

    private func resolvedLocalGamePlayerID() -> String {
        let live = GKLocalPlayer.local.gamePlayerID
        if !live.isEmpty, live != "GKPlayerIDUnknown" { return live }
        // Cache Elo / Multipeer identity
        if let cached = BlomixEloManager.shared.cachedLocalGameIdentity()?.gamePlayerID, !cached.isEmpty {
            return cached
        }
        return live
    }

    // MARK: - Cache / pending persistence

    private struct PendingH2HEvent: Codable, Equatable {
        var clientEventId: String
        var pairKey: String
        var winnerID: String
        var loserID: String
        var channel: String
        var createdAt: Date
    }

    private func loadCache() -> [String: BlomixPvPH2HTotals] {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let decoded = try? JSONDecoder().decode([String: BlomixPvPH2HTotals].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveCache(_ cache: [String: BlomixPvPH2HTotals]) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func mutateCache(pairKey: String, localID: String, _ body: (inout BlomixPvPH2HTotals) -> Void) {
        _ = localID
        var cache = loadCache()
        var totals = cache[pairKey] ?? .zero
        body(&totals)
        // Bornes de sécurité
        totals.localWins = max(0, totals.localWins)
        totals.remoteWins = max(0, totals.remoteWins)
        cache[pairKey] = totals
        saveCache(cache)
    }

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
        // Plafond anti-croissance
        if pending.count > 100 {
            pending = Array(pending.suffix(100))
        }
        savePending(pending)
    }
}

// Codable for totals in cache
extension BlomixPvPH2HTotals: Codable {}

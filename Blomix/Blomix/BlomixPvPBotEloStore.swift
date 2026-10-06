//
//  BlomixPvPBotEloStore.swift
//  Blomix
//
//  Elo des bots : events CloudKit Public `BotEloEvent`, réduction à la lecture.
//  Best-effort. Un 503 passe par `BlomixPublicCloudGate` (même robinet que H2H).
//  Jamais de `submitScore` pour une identité bot.
//

import CloudKit
import Foundation
import GameKit

@MainActor
final class BlomixPvPBotEloStore {

    static let shared = BlomixPvPBotEloStore()

    private let ckContainer = CKContainer(identifier: "iCloud.blomig.BLOMIX")
    private var publicDB: CKDatabase { ckContainer.publicCloudDatabase }
    private static let recordType = "BotEloEvent"
    private static let cacheKey = "BlomixPvPBotElo.v1"

    private struct CachedBot: Codable {
        var rating: Int
        var matchCount: Int
    }

    private var memoryCache: [BlomixPvPBotKind: BlomixEloProfile] = [:]

    private init() {
        loadDiskCacheIntoMemory()
    }

    func cachedProfile(for kind: BlomixPvPBotKind) -> BlomixEloProfile {
        if let p = memoryCache[kind] { return p }
        return BlomixEloProfile(
            rating: BlomixEloManager.shared.defaultRating,
            completedMatchCount: 0
        )
    }

    /// Profils connus en cache local (peut être vide — alors pas de lignes bot).
    func cachedProfilesIfAny() -> [BlomixPvPBotKind: BlomixEloProfile] {
        memoryCache
    }

    /// Query + réduction. `nil` = échec (onglet Elo = humains seulement, sauf cache déjà là).
    @discardableResult
    func refreshFromCloudBestEffort() async -> [BlomixPvPBotKind: BlomixEloProfile]? {
        do {
            try BlomixPublicCloudGate.shared.throwIfBlocked()
            var out: [BlomixPvPBotKind: BlomixEloProfile] = [:]
            for kind in BlomixPvPBotKind.allCases {
                let events = try await fetchEvents(botId: kind.rawValue)
                out[kind] = reduce(events)
            }
            memoryCache = out
            persistDiskCache(out)
            BlomixPublicCloudGate.shared.noteSuccess()
            return out
        } catch {
            BlomixPublicCloudGate.shared.noteError(error)
            print("[BotElo] refresh fail: \(error.localizedDescription)")
            if !memoryCache.isEmpty { return memoryCache }
            return nil
        }
    }

    /// Après une manche : met à jour le cache local + écrit l’event (hors chemin UI critique).
    func recordMatchBestEffort(
        botKind: BlomixPvPBotKind,
        outcome: BlomixPvPMatchOutcome,
        result: BlomixEloResult,
        matchId: String
    ) {
        let updated = BlomixEloProfile(
            rating: result.remoteNewRating,
            completedMatchCount: result.remoteMatchCountAfter
        )
        memoryCache[botKind] = updated
        persistDiskCache(memoryCache)

        let reporter = GKLocalPlayer.local.gamePlayerID
        let outcomeInt: Int64
        switch outcome {
        case .win: outcomeInt = 1
        case .loss: outcomeInt = 0
        case .draw: outcomeInt = 0
        }
        let clientEventId = UUID().uuidString
        Task { @MainActor in
            await self.saveEventBestEffort(
                botId: botKind.rawValue,
                reporterId: reporter,
                outcome: outcomeInt,
                playerEloBefore: Int64(result.localOldRating),
                botEloBefore: Int64(result.remoteOldRating),
                matchId: matchId,
                clientEventId: clientEventId
            )
        }
    }

    // MARK: - Réduction

    private struct BotEloCloudEvent {
        let recordName: String
        let createdAt: Date
        let playerEloBefore: Int
        let outcome: BlomixPvPMatchOutcome
    }

    private func reduce(_ events: [BotEloCloudEvent]) -> BlomixEloProfile {
        var rating = BlomixEloManager.shared.defaultRating
        var matches = 0
        let ordered = events.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.recordName < $1.recordName
        }
        for event in ordered {
            let local = BlomixEloProfile(rating: event.playerEloBefore, completedMatchCount: 0)
            let remote = BlomixEloProfile(rating: rating, completedMatchCount: matches)
            let step = BlomixEloManager.shared.updatedRatings(
                localProfile: local,
                remoteProfile: remote,
                outcome: event.outcome
            )
            rating = step.remoteNewRating
            matches += 1
        }
        return BlomixEloProfile(rating: rating, completedMatchCount: matches)
    }

    // MARK: - CloudKit

    private func fetchEvents(botId: String) async throws -> [BotEloCloudEvent] {
        let predicate = NSPredicate(format: "botId == %@", botId)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
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
                op.qualityOfService = .utility
                op.resultsLimit = 100
                let box = BotEloRecordPage()
                op.recordMatchedBlock = { _, result in
                    if case .success(let rec) = result {
                        box.append(rec)
                    }
                }
                op.queryResultBlock = { result in
                    switch result {
                    case .success(let c):
                        cont.resume(returning: (box.snapshot(), c))
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
                publicDB.add(op)
            }
            all.append(contentsOf: batch)
            cursor = next
        } while cursor != nil

        return all.compactMap { rec in
            let created = rec["createdAt"] as? Date ?? rec.creationDate ?? .distantPast
            let playerBefore = (rec["playerEloBefore"] as? Int64).map(Int.init)
                ?? (rec["playerEloBefore"] as? Int)
                ?? BlomixEloManager.shared.defaultRating
            let raw = (rec["outcome"] as? Int64).map(Int.init) ?? (rec["outcome"] as? Int) ?? 0
            let outcome: BlomixPvPMatchOutcome = raw > 0 ? .win : .loss
            return BotEloCloudEvent(
                recordName: rec.recordID.recordName,
                createdAt: created,
                playerEloBefore: playerBefore,
                outcome: outcome
            )
        }
    }

    private func saveEventBestEffort(
        botId: String,
        reporterId: String,
        outcome: Int64,
        playerEloBefore: Int64,
        botEloBefore: Int64,
        matchId: String,
        clientEventId: String
    ) async {
        do {
            try BlomixPublicCloudGate.shared.throwIfBlocked()
            let recID = CKRecord.ID(recordName: "botelo_\(clientEventId)")
            let record = CKRecord(recordType: Self.recordType, recordID: recID)
            record["botId"] = botId as CKRecordValue
            record["reporterId"] = reporterId as CKRecordValue
            record["outcome"] = outcome as CKRecordValue
            record["playerEloBefore"] = playerEloBefore as CKRecordValue
            record["botEloBefore"] = botEloBefore as CKRecordValue
            record["matchId"] = matchId as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue
            _ = try await publicDB.save(record)
            BlomixPublicCloudGate.shared.noteSuccess()
            print("[BotElo] uploaded \(clientEventId.prefix(8))… \(botId)")
        } catch {
            if isIdempotentCloudSuccess(error) { return }
            BlomixPublicCloudGate.shared.noteError(error)
            print("[BotElo] upload fail: \(error.localizedDescription)")
        }
    }

    private func isIdempotentCloudSuccess(_ error: Error) -> Bool {
        if let ck = error as? CKError {
            switch ck.code {
            case .serverRecordChanged, .batchRequestFailed, .partialFailure:
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

    private final class BotEloRecordPage: @unchecked Sendable {
        private let lock = NSLock()
        private var recs: [CKRecord] = []

        func append(_ rec: CKRecord) {
            lock.lock(); recs.append(rec); lock.unlock()
        }

        func snapshot() -> [CKRecord] {
            lock.lock(); defer { lock.unlock() }
            return recs
        }
    }

    // MARK: - Cache disque

    private func loadDiskCacheIntoMemory() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let raw = try? JSONDecoder().decode([String: CachedBot].self, from: data)
        else { return }
        var out: [BlomixPvPBotKind: BlomixEloProfile] = [:]
        for (key, val) in raw {
            guard let kind = BlomixPvPBotKind(rawValue: key) else { continue }
            out[kind] = BlomixEloProfile(rating: val.rating, completedMatchCount: val.matchCount)
        }
        memoryCache = out
    }

    private func persistDiskCache(_ profiles: [BlomixPvPBotKind: BlomixEloProfile]) {
        var raw: [String: CachedBot] = [:]
        for (kind, p) in profiles {
            raw[kind.rawValue] = CachedBot(rating: p.rating, matchCount: p.completedMatchCount)
        }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}

//
//  BlomixDailyChallenge.swift
//  Blomix
//
//  Défi du jour : slot save dédié, scores CloudKit `DailyScore`, points podium
//  +5/+3/+1 au lendemain UTC, cumul Game Center `dailywins_arc`.
//

import CloudKit
import Foundation
@preconcurrency import GameKit
import UIKit

/// Une ligne du classement CloudKit du jour (ou de la veille).
struct BlomixDailyScoreEntry: Sendable {
    let gamePlayerID: String
    let displayName: String
    let score: Int
}

/// Snapshot persisté (clé séparée de `blomix_solo_save_v2`).
struct BlomixDailyRunSave: Codable {
    static let currentVersion = 1
    let version: Int
    let utcDay: String
    let seed: UInt64
    let fileRNGState: UInt64
    let game: BlomixSoloGameSave
}

enum BlomixDailyHubCTA {
    case play
    case resume
    case finished
}

enum BlomixDailyScoresLoad {
    case loaded([BlomixDailyScoreEntry])
    case unavailable
}

@MainActor
final class BlomixDailyChallenge {

    static let shared = BlomixDailyChallenge()

    nonisolated static let leaderboardID = "dailywins_arc"
    private static let recordType = "DailyScore"
    private static let saveKey = "blomix_daily_save_v1"
    private static let finishedDayKey = "blomix_daily_finished_day"
    private static let finishedScoreKey = "blomix_daily_finished_score"
    private static let careerPointsKey = "blomix_daily_career_points"
    private static let pendingGCKey = "blomix_daily_pending_gc_points"
    private static let creditedPrefix = "blomix_daily_credited_"

    private let ckContainer = CKContainer(identifier: "iCloud.blomig.BLOMIX")
    private var publicDB: CKDatabase { ckContainer.publicCloudDatabase }
    private var didSetup = false
    private var isClaimingPodium = false

    private init() {}

    func setup() {
        guard !didSetup else { return }
        didSetup = true
        NotificationCenter.default.addObserver(
            forName: .blomixGameCenterAuthDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingCareerPoints()
                self?.claimPodiumIfNeeded()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingCareerPoints()
                self?.claimPodiumIfNeeded()
            }
        }
        flushPendingCareerPoints()
        claimPodiumIfNeeded()
    }

    // MARK: - État local

    var utcToday: String { BlomixDailySeed.utcDayString() }

    var hasInProgressRun: Bool { loadRun() != nil }

    func hasFinished(day: String) -> Bool {
        UserDefaults.standard.string(forKey: Self.finishedDayKey) == day
    }

    var hubCTA: BlomixDailyHubCTA {
        if hasInProgressRun { return .resume }
        if hasFinished(day: utcToday) { return .finished }
        return .play
    }

    var careerPoints: Int {
        get { max(0, UserDefaults.standard.integer(forKey: Self.careerPointsKey)) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: Self.careerPointsKey) }
    }

    func seedForNewRun() -> (day: String, seed: UInt64) {
        let day = utcToday
        return (day, BlomixDailySeed.seed(forDay: day))
    }

    func saveRun(_ run: BlomixDailyRunSave) {
        guard let data = try? JSONEncoder().encode(run) else { return }
        UserDefaults.standard.set(data, forKey: Self.saveKey)
    }

    func loadRun() -> BlomixDailyRunSave? {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let run = try? JSONDecoder().decode(BlomixDailyRunSave.self, from: data),
              run.version == BlomixDailyRunSave.currentVersion else {
            clearRun()
            return nil
        }
        return run
    }

    func clearRun() {
        UserDefaults.standard.removeObject(forKey: Self.saveKey)
    }

    /// GO : vide le slot, mémorise le jour/score, pousse CloudKit (best-effort).
    func finishRun(day: String, score: Int) {
        clearRun()
        UserDefaults.standard.set(day, forKey: Self.finishedDayKey)
        UserDefaults.standard.set(max(0, score), forKey: Self.finishedScoreKey)
        Task { await upsertScore(day: day, score: score) }
    }

    // MARK: - Classement du jour (CloudKit)

    func fetchScores(day: String) async -> BlomixDailyScoresLoad {
        var entries: [BlomixDailyScoreEntry] = []
        var cloudFailed = false
        if BlomixPublicCloudGate.shared.isBlocked {
            cloudFailed = true
        } else {
            do {
                try BlomixPublicCloudGate.shared.throwIfBlocked()
                let records = try await queryScores(day: day)
                BlomixPublicCloudGate.shared.noteSuccess()
                entries = records.map { entry(from: $0) }
            } catch {
                cloudFailed = true
                BlomixPublicCloudGate.shared.noteError(error)
                print("[Daily] fetchScores(\(day)) : \(error.localizedDescription)")
            }
        }
        mergeLocalFinishedScore(day: day, into: &entries)
        entries.sort { $0.score > $1.score }
        if entries.isEmpty, cloudFailed { return .unavailable }
        return .loaded(entries)
    }

    /// Si le joueur a fini ce jour (UserDefaults), sa ligne est toujours là — même sans GC / CK.
    private func mergeLocalFinishedScore(day: String, into entries: inout [BlomixDailyScoreEntry]) {
        guard hasFinished(day: day) else { return }
        let rawID = GKLocalPlayer.local.gamePlayerID
        let playerID = (rawID.isEmpty || rawID == "GKPlayerIDUnknown") ? "local" : rawID
        let score = max(0, UserDefaults.standard.integer(forKey: Self.finishedScoreKey))
        let name = GKLocalPlayer.local.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = name.isEmpty ? BlomixL10n.startScreenPlayerUnknown : name
        if let index = entries.firstIndex(where: { $0.gamePlayerID == playerID || $0.gamePlayerID == "local" }) {
            if score > entries[index].score {
                entries[index] = BlomixDailyScoreEntry(
                    gamePlayerID: playerID, displayName: display, score: score
                )
            }
        } else if let index = entries.firstIndex(where: { $0.displayName == display }) {
            if score > entries[index].score {
                entries[index] = BlomixDailyScoreEntry(
                    gamePlayerID: playerID, displayName: display, score: score
                )
            }
        } else {
            entries.append(
                BlomixDailyScoreEntry(gamePlayerID: playerID, displayName: display, score: score)
            )
        }
    }

    /// Rang dense (égalités = même place). `nil` si le joueur n’est pas dans la liste.
    static func denseRank(of gamePlayerID: String, in entries: [BlomixDailyScoreEntry]) -> Int? {
        guard !gamePlayerID.isEmpty else { return nil }
        var place = 1
        var index = 0
        while index < entries.count {
            let score = entries[index].score
            var end = index
            while end < entries.count, entries[end].score == score { end += 1 }
            let group = entries[index..<end]
            if group.contains(where: { $0.gamePlayerID == gamePlayerID }) {
                return place
            }
            place += group.count
            index = end
        }
        return nil
    }

    /// Points podium : 1er +5, 2e +3, 3e +1 ; égalité = mêmes points, places sautées.
    static func podiumPoints(for gamePlayerID: String, in entries: [BlomixDailyScoreEntry]) -> Int {
        guard let rank = denseRank(of: gamePlayerID, in: entries) else { return 0 }
        switch rank {
        case 1: return 5
        case 2: return 3
        case 3: return 1
        default: return 0
        }
    }

    func upsertScore(day: String, score: Int) async {
        let playerID = GKLocalPlayer.local.gamePlayerID
        guard !playerID.isEmpty, playerID != "GKPlayerIDUnknown" else { return }
        if BlomixPublicCloudGate.shared.isBlocked { return }
        let recordName = Self.recordName(day: day, gamePlayerID: playerID)
        let recID = CKRecord.ID(recordName: recordName)
        do {
            try BlomixPublicCloudGate.shared.throwIfBlocked()
            let record: CKRecord
            if let existing = try? await publicDB.record(for: recID) {
                let previous = (existing["score"] as? Int) ?? Int(existing["score"] as? Int64 ?? 0)
                if score < previous { return }
                record = existing
            } else {
                record = CKRecord(recordType: Self.recordType, recordID: recID)
            }
            record["day"] = day as CKRecordValue
            record["score"] = score as CKRecordValue
            record["displayName"] = displayName() as CKRecordValue
            record["gamePlayerID"] = playerID as CKRecordValue
            _ = try await publicDB.save(record)
            BlomixPublicCloudGate.shared.noteSuccess()
        } catch {
            BlomixPublicCloudGate.shared.noteError(error)
            print("[Daily] upsertScore : \(error.localizedDescription)")
        }
    }

    // MARK: - Podium (lendemain UTC)

    func claimPodiumIfNeeded() {
        guard !isClaimingPodium else { return }
        let yesterday = BlomixDailySeed.previousUtcDayString()
        if UserDefaults.standard.bool(forKey: Self.creditedPrefix + yesterday) { return }
        if let run = loadRun(), run.utcDay == yesterday { return }
        isClaimingPodium = true
        Task { @MainActor [weak self] in
            defer { self?.isClaimingPodium = false }
            await self?.claimPodium(for: yesterday)
        }
    }

    private func claimPodium(for day: String) async {
        if UserDefaults.standard.bool(forKey: Self.creditedPrefix + day) { return }
        let playerID = GKLocalPlayer.local.gamePlayerID
        guard !playerID.isEmpty, playerID != "GKPlayerIDUnknown" else { return }
        let entries: [BlomixDailyScoreEntry]
        switch await fetchScores(day: day) {
        case .loaded(let rows):
            entries = rows
        case .unavailable:
            return
        }
        guard !entries.isEmpty else { return }
        guard entries.contains(where: { $0.gamePlayerID == playerID }) else {
            if hasFinished(day: day) { return }
            UserDefaults.standard.set(true, forKey: Self.creditedPrefix + day)
            return
        }
        let gained = Self.podiumPoints(for: playerID, in: entries)
        if gained > 0 {
            careerPoints += gained
            print("[Daily] Podium \(day) : +\(gained) (total \(careerPoints)).")
        }
        UserDefaults.standard.set(true, forKey: Self.creditedPrefix + day)
        submitCareerPoints(careerPoints)
    }

    func submitCareerPoints(_ points: Int) {
        let value = max(0, points)
        careerPoints = max(careerPoints, value)
        UserDefaults.standard.set(max(value, pendingCareerPoints()), forKey: Self.pendingGCKey)
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(
            value,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [Self.leaderboardID]
        ) { [weak self] error in
            Task { @MainActor in
                if let error {
                    print("[Daily] submitCareerPoints : \(error.localizedDescription)")
                } else {
                    print("[Daily] Points \(value) soumis sur \(Self.leaderboardID).")
                    if value >= (self?.pendingCareerPoints() ?? 0) {
                        UserDefaults.standard.set(0, forKey: Self.pendingGCKey)
                    }
                }
            }
        }
    }

    private func flushPendingCareerPoints() {
        let pending = max(careerPoints, pendingCareerPoints())
        guard pending > 0 else { return }
        submitCareerPoints(pending)
    }

    private func pendingCareerPoints() -> Int {
        max(0, UserDefaults.standard.integer(forKey: Self.pendingGCKey))
    }

    // MARK: - CloudKit helpers

    private static func recordName(day: String, gamePlayerID: String) -> String {
        let safeID = gamePlayerID.replacingOccurrences(of: "/", with: "_")
        return "daily_\(day)_\(safeID)"
    }

    private func displayName() -> String {
        let name = GKLocalPlayer.local.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? BlomixL10n.startScreenPlayerUnknown : name
    }

    private func entry(from record: CKRecord) -> BlomixDailyScoreEntry {
        let id = (record["gamePlayerID"] as? String)
            ?? record.recordID.recordName
        let name = (record["displayName"] as? String) ?? BlomixL10n.startScreenPlayerUnknown
        let score: Int
        if let i = record["score"] as? Int {
            score = i
        } else if let i64 = record["score"] as? Int64 {
            score = Int(i64)
        } else {
            score = 0
        }
        return BlomixDailyScoreEntry(gamePlayerID: id, displayName: name, score: score)
    }

    private func queryScores(day: String) async throws -> [CKRecord] {
        let predicate = NSPredicate(format: "day == %@", day)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        // Pas de sort CloudKit : un index `score` sortable combiné à `day` fait souvent
        // échouer la query (liste vide). Le tri est fait en mémoire.
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        let (first, next) = try await publicDB.records(matching: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 200)
        for (_, result) in first {
            if case .success(let rec) = result { all.append(rec) }
        }
        cursor = next
        while let current = cursor {
            let (batch, more) = try await publicDB.records(continuingMatchFrom: current, desiredKeys: nil, resultsLimit: 200)
            for (_, result) in batch {
                if case .success(let rec) = result { all.append(rec) }
            }
            cursor = more
        }
        return all
    }
}

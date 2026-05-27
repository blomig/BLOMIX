//
//  BlomixAvailablePlayersManager.swift
//  Blomix
//
//  Gère la visibilité "OK pour être défié" via CloudKit Public Database.
//
//  Schéma CloudKit (Record Type "AvailablePlayer") — inchangé :
//    teamPlayerID  String   Queryable
//    displayName   String   —
//    eloRating     Int64    —
//    lastHeartbeat Date     Queryable, Sortable
//
//  Stratégie d'invitation : GKPlayer.loadPlayers(forIdentifiers:) ne résout pas
//  des joueurs inconnus (jamais croisés en match). On utilise donc un "rendez-vous
//  CloudKit + playerGroup GKMatchmaker" :
//    • Le challenger écrit un record "chal_{challengedGamePlayerID}" dans CloudKit.
//    • Le challengé détecte ce record à son prochain refresh (≤ 8 s).
//    • Les deux lancent GKMatchmaker.findMatch avec le même playerGroup déterministe.
//    • GKMatchmaker les associe sans avoir besoin de GKPlayer.recipients.
//
//  Record de défi (même Record Type "AvailablePlayer") :
//    recordName    = "chal_{challengedGamePlayerID}"
//    teamPlayerID  = challengerGamePlayerID
//    displayName   = challengerDisplayName
//    eloRating     = matchPlayerGroup (Int)
//    lastHeartbeat = création (pour expiry 5 min)
//

import CloudKit
import GameKit
import UIKit

// MARK: - Models

/// Joueur disponible retourné par CloudKit.
struct BlomixAvailablePlayer {
    /// gamePlayerID = recordName — utilisé comme critère de rendez-vous GKMatchmaker.
    let gamePlayerID: String
    let displayName:  String
    let eloRating:    Int?
}

/// Défi entrant détecté dans CloudKit.
struct BlomixIncomingChallenge {
    let challengerGamePlayerID: String
    let challengerDisplayName:  String
    let matchPlayerGroup:       Int
}

// MARK: - Manager

@MainActor
final class BlomixAvailablePlayersManager {

    static let shared = BlomixAvailablePlayersManager()
    private init() {}

    // MARK: - CloudKit

    private let ckContainer = CKContainer(identifier: "iCloud.blomig.BLOMIX")
    private var publicDB: CKDatabase { ckContainer.publicCloudDatabase }
    private static let recordType = "AvailablePlayer"

    // MARK: - Persistance

    private static let defaultsKey = "blomixAvailableForChallenge_v1"

    var isAvailableForChallenge: Bool {
        get { UserDefaults.standard.bool(forKey: Self.defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: .blomixAvailabilityChanged, object: nil)
            if newValue {
                publishAvailability()
                startHeartbeat()
                startChallengePolling()
            } else {
                stopHeartbeat()
                stopChallengePolling()
                unpublishAvailability()
            }
        }
    }

    private var heartbeatTimer:         Timer?
    private var challengePollTimer:     Timer?
    private var cachedGamePlayerID:     String?
    private var cachedTeamPlayerID:     String?
    /// ID du dernier défi notifié — évite de re-poster la notif pour le même défi.
    private var lastNotifiedChallengerID: String?
    private var isSetup                 = false

    // MARK: - Setup

    func setup() {
        guard !isSetup else { return }
        isSetup = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        if isAvailableForChallenge {
            publishAvailability()
            startHeartbeat()
            startChallengePolling()
        }
    }

    @objc private func handleResignActive() {
        stopHeartbeat()
        stopChallengePolling()
        unpublishAvailability()
    }

    @objc private func handleBecomeActive() {
        guard isAvailableForChallenge else { return }
        publishAvailability()
        startHeartbeat()
        startChallengePolling()
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        let t = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.publishAvailability() }
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeatTimer = t
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Polling défi entrant (global, toutes les 8 s)

    private func startChallengePolling() {
        stopChallengePolling()
        lastNotifiedChallengerID = nil
        // Premier poll immédiat, puis toutes les 8 s.
        Task { @MainActor [weak self] in self?.pollForIncomingChallenge() }
        let t = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollForIncomingChallenge() }
        }
        RunLoop.main.add(t, forMode: .common)
        challengePollTimer = t
    }

    private func stopChallengePolling() {
        challengePollTimer?.invalidate()
        challengePollTimer = nil
        lastNotifiedChallengerID = nil
    }

    private func pollForIncomingChallenge() {
        Task { [weak self] in
            guard let self else { return }
            guard let (_, challenge) = try? await self.fetchAvailablePlayersAndChallenge() else { return }
            if let challenge {
                // Ne notifier que si c'est un nouveau challenger.
                guard challenge.challengerGamePlayerID != self.lastNotifiedChallengerID else { return }
                self.lastNotifiedChallengerID = challenge.challengerGamePlayerID
                NotificationCenter.default.post(
                    name: .blomixIncomingChallengeDetected,
                    object: nil,
                    userInfo: [
                        "challengerGamePlayerID": challenge.challengerGamePlayerID,
                        "challengerDisplayName":  challenge.challengerDisplayName,
                        "matchPlayerGroup":       challenge.matchPlayerGroup,
                    ]
                )
            } else if self.lastNotifiedChallengerID != nil {
                // Le défi a expiré ou a été supprimé — réinitialiser pour le prochain.
                self.lastNotifiedChallengerID = nil
            }
        }
    }

    /// Réinitialise le tracker pour permettre un nouveau défi du même joueur.
    func clearLastNotifiedChallenger() {
        lastNotifiedChallengerID = nil
    }

    // MARK: - Publish / Unpublish

    func publishAvailability() {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return }
        let gameID      = player.gamePlayerID
        let teamID      = player.teamPlayerID
        let displayName = player.displayName
        cachedGamePlayerID = gameID
        cachedTeamPlayerID = teamID

        Task { [weak self] in
            guard let self else { return }
            await self.upsertRecord(recordName: gameID, teamID: teamID,
                                    displayName: displayName, elo: 0, isFirstPass: true)
            if let elo = await self.fetchLocalElo() {
                await self.upsertRecord(recordName: gameID, teamID: teamID,
                                        displayName: displayName, elo: elo)
            }
        }
    }

    private func upsertRecord(recordName: String, teamID: String,
                               displayName: String, elo: Int, isFirstPass: Bool = false) async {
        let recID = CKRecord.ID(recordName: recordName)
        var record: CKRecord
        do {
            record = try await publicDB.record(for: recID)
        } catch {
            record = CKRecord(recordType: Self.recordType, recordID: recID)
        }
        record["teamPlayerID"]  = teamID      as CKRecordValue
        record["displayName"]   = displayName as CKRecordValue
        record["lastHeartbeat"] = Date()       as CKRecordValue
        record["eloRating"]     = elo          as CKRecordValue
        do {
            try await publicDB.save(record)
            print("[Available] upserted OK: \(displayName)")
            if isFirstPass {
                NotificationCenter.default.post(
                    name: .blomixAvailabilityPublishResult, object: nil,
                    userInfo: ["success": true, "message": "✓ \(displayName)"])
            }
        } catch {
            let msg = error.localizedDescription
            print("[Available] upsert error: \(msg)")
            if isFirstPass {
                NotificationCenter.default.post(
                    name: .blomixAvailabilityPublishResult, object: nil,
                    userInfo: ["success": false, "message": "Erreur CloudKit : \(msg)"])
            }
        }
    }

    func unpublishAvailability() {
        let gameID = cachedGamePlayerID
            ?? (GKLocalPlayer.local.isAuthenticated ? GKLocalPlayer.local.gamePlayerID : nil)
        if let gameID {
            publicDB.delete(withRecordID: CKRecord.ID(recordName: gameID)) { _, _ in }
        }
        // Nettoyage de l'ancien format (teamPlayerID comme recordName).
        let teamID = cachedTeamPlayerID
            ?? (GKLocalPlayer.local.isAuthenticated ? GKLocalPlayer.local.teamPlayerID : nil)
        if let teamID, teamID != gameID {
            publicDB.delete(withRecordID: CKRecord.ID(recordName: teamID)) { _, _ in }
        }
    }

    // MARK: - Challenge rendez-vous

    /// Préfixe des records de défi dans CloudKit (même Record Type "AvailablePlayer").
    private static let challengePrefix = "chal_"

    /// Hash déterministe partagé entre les deux joueurs : sert de playerGroup GKMatchmaker.
    /// Même valeur calculée côté challenger et côté challengé.
    static func matchPlayerGroup(id1: String, id2: String) -> Int {
        let combined = [id1, id2].sorted().joined(separator: "|")
        var hash: UInt64 = 5381
        for scalar in combined.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        let group = Int(hash % 1_000_000_000) + 1   // 1-indexed, évite 0 (groupe auto-match)
        return group
    }

    /// Écrit un record de défi dans CloudKit à destination du joueur challengé.
    func createChallenge(challengerGamePlayerID: String,
                         challengerDisplayName: String,
                         challengedGamePlayerID: String,
                         matchPlayerGroup: Int) async {
        let recName = Self.challengePrefix + challengedGamePlayerID
        let recID   = CKRecord.ID(recordName: recName)
        var record: CKRecord
        do {
            record = try await publicDB.record(for: recID)
        } catch {
            record = CKRecord(recordType: Self.recordType, recordID: recID)
        }
        record["teamPlayerID"]  = challengerGamePlayerID as CKRecordValue
        record["displayName"]   = challengerDisplayName  as CKRecordValue
        record["eloRating"]     = matchPlayerGroup       as CKRecordValue
        record["lastHeartbeat"] = Date()                  as CKRecordValue
        do {
            try await publicDB.save(record)
            print("[Available] challenge created → \(challengedGamePlayerID)")
        } catch {
            print("[Available] challenge create error: \(error.localizedDescription)")
        }
    }

    /// Supprime le record de défi dirigé vers le joueur indiqué.
    func deleteChallenge(challengedGamePlayerID: String) {
        let recID = CKRecord.ID(recordName: Self.challengePrefix + challengedGamePlayerID)
        publicDB.delete(withRecordID: recID) { _, _ in }
    }

    // MARK: - Fetch

    /// Retourne les joueurs disponibles ET le défi entrant pour le joueur local.
    func fetchAvailablePlayersAndChallenge() async throws
        -> (players: [BlomixAvailablePlayer], challenge: BlomixIncomingChallenge?) {

        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        let localGameID = GKLocalPlayer.local.isAuthenticated
            ? GKLocalPlayer.local.gamePlayerID : nil
        let localTeamID = GKLocalPlayer.local.isAuthenticated
            ? GKLocalPlayer.local.teamPlayerID : nil
        let cutoff = Date().addingTimeInterval(-5 * 60)

        let (results, _) = try await publicDB.records(
            matching:     query,
            inZoneWith:   nil,
            desiredKeys:  ["teamPlayerID", "displayName", "eloRating", "lastHeartbeat"],
            resultsLimit: 200
        )

        var players:   [BlomixAvailablePlayer]  = []
        var challenge: BlomixIncomingChallenge? = nil

        for (_, result) in results {
            guard case .success(let record) = result else { continue }
            let recName = record.recordID.recordName

            if recName.hasPrefix(Self.challengePrefix) {
                // Record de défi — l'intéresser seulement s'il m'est destiné.
                let challengedID = String(recName.dropFirst(Self.challengePrefix.count))
                guard challengedID == localGameID else { continue }
                // Vérifie la fraîcheur (défi expiré = > 5 min)
                if let hb = record["lastHeartbeat"] as? Date, hb < cutoff { continue }
                let challengerID   = record["teamPlayerID"] as? String ?? ""
                let challengerName = record["displayName"]  as? String ?? "?"
                let matchGroup     = record["eloRating"]    as? Int    ?? 0
                challenge = BlomixIncomingChallenge(
                    challengerGamePlayerID: challengerID,
                    challengerDisplayName:  challengerName,
                    matchPlayerGroup:       matchGroup
                )

            } else {
                // Record de joueur disponible.
                let gameID = recName
                let teamID = record["teamPlayerID"] as? String ?? gameID
                if gameID == localGameID { continue }
                if teamID == localTeamID { continue }
                if let hb = record["lastHeartbeat"] as? Date, hb < cutoff { continue }
                let name = record["displayName"] as? String ?? "?"
                let elo  = record["eloRating"]   as? Int
                players.append(BlomixAvailablePlayer(gamePlayerID: gameID,
                                                     displayName: name,
                                                     eloRating: elo))
            }
        }

        let sorted = players.sorted {
            switch ($0.eloRating, $1.eloRating) {
            case (let a?, let b?): return a > b
            case (nil, _?):        return false
            case (_?, nil):        return true
            case (nil, nil):       return false
            }
        }
        return (sorted, challenge)
    }

    // MARK: - Helpers

    private func fetchLocalElo() async -> Int? {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return nil }
        guard let profile = try? await BlomixEloManager.shared.fetchProfile(for: player),
              profile.completedMatchCount > 0
        else { return nil }
        return profile.rating
    }
}

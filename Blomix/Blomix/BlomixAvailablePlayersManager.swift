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
    /// true si le joueur est en cours de partie PvP au moment du fetch.
    let inMatch:      Bool
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

    private var heartbeatTimer:           Timer?
    private var challengePollTimer:       Timer?
    private var cachedGamePlayerID:       String?
    private var cachedTeamPlayerID:       String?
    /// ID du dernier défi notifié — évite de re-poster la notif pour le même défi.
    private var lastNotifiedChallengerID: String?
    /// Timer différé qui remet lastNotifiedChallengerID à nil après un déclin/expiration.
    /// Laisse passer au moins 2 cycles de poll (8 s) avant de permettre une nouvelle bannière,
    /// le temps que la suppression CloudKit se propage.
    private var challengeSuppressTimer:   Timer?
    private var isSetup                   = false

    /// Positionné à true quand une partie PvP est active — suspend la bannière de défi entrant.
    /// Mis à jour par GameScene via `setActiveMatch(_:)`.
    private(set) var isInActiveMatch: Bool = false

    /// Appelé par GameScene quand une partie PvP démarre ou se termine.
    func setActiveMatch(_ active: Bool) {
        isInActiveMatch = active
        if active {
            // Suspension du polling pendant la partie pour économiser les ressources et
            // éviter les bannières intempestives.
            stopChallengePolling()
        } else {
            // Reprise du polling dès la fin de partie, si le joueur est toujours disponible.
            if isAvailableForChallenge {
                clearLastNotifiedChallenger()
                startChallengePolling()
            }
        }
        // Mettre à jour CloudKit immédiatement avec le nouveau statut inMatch,
        // sans attendre le prochain heartbeat.
        if isAvailableForChallenge {
            publishAvailability()
        }
    }

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
        // On arrête les timers pour ne pas consommer de ressources en arrière-plan,
        // mais on NE supprime PAS le record. La moindre interruption système
        // (notification, bannière, alerte) déclenche willResignActive — supprimer
        // ici rendait le joueur invisible au moindre incident.
        // La visibilité expire naturellement après 5 min via lastHeartbeat >= cutoff
        // si le joueur quitte vraiment l'app sans la rouvrir.
        stopHeartbeat()
        stopChallengePolling()
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
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
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
        let t = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollForIncomingChallenge() }
        }
        RunLoop.main.add(t, forMode: .common)
        challengePollTimer = t
    }

    private func stopChallengePolling() {
        challengePollTimer?.invalidate()
        challengePollTimer = nil
        // Ne pas effacer lastNotifiedChallengerID ici : il sert de verrou anti-rebond
        // même quand le polling est suspendu (ex : pendant une partie PvP).
    }

    private func pollForIncomingChallenge() {
        // Pas de bannière pendant une partie PvP active.
        guard !isInActiveMatch else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let (_, challenge) = try? await self.fetchAvailablePlayersAndChallenge() else { return }
            // Vérification après await : la partie a peut-être démarré pendant le fetch.
            guard !self.isInActiveMatch else { return }
            if let challenge {
                // Ne notifier que si c'est un nouveau challenger (verrou anti-rebond).
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
                self.challengeSuppressTimer?.invalidate()
                self.challengeSuppressTimer = nil
            }
        }
    }

    /// Réinitialise immédiatement le tracker (ex: après succès d'une partie lancée).
    func clearLastNotifiedChallenger() {
        challengeSuppressTimer?.invalidate()
        challengeSuppressTimer = nil
        lastNotifiedChallengerID = nil
    }

    /// Supprime le record de défi puis remet lastNotifiedChallengerID à nil après un délai.
    /// Laisse passer au moins 2 cycles de poll le temps que CloudKit propage la suppression,
    /// évitant la boucle "déclin → poll → nouvelle bannière".
    func suppressChallengeWithDelay(challengedGamePlayerID: String) {
        deleteChallenge(challengedGamePlayerID: challengedGamePlayerID)
        challengeSuppressTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastNotifiedChallengerID = nil
                self?.challengeSuppressTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        challengeSuppressTimer = t
    }

    // MARK: - Publish / Unpublish

    func publishAvailability() {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return }
        let gameID      = player.gamePlayerID
        let teamID      = player.teamPlayerID
        let displayName = player.displayName
        let inMatch     = isInActiveMatch
        cachedGamePlayerID = gameID
        cachedTeamPlayerID = teamID

        Task { [weak self] in
            guard let self else { return }
            await self.upsertRecord(recordName: gameID, teamID: teamID,
                                    displayName: displayName, elo: 0,
                                    inMatch: inMatch, isFirstPass: true)
            if let elo = await self.fetchLocalElo() {
                await self.upsertRecord(recordName: gameID, teamID: teamID,
                                        displayName: displayName, elo: elo,
                                        inMatch: inMatch)
            }
        }
    }

    private func upsertRecord(recordName: String, teamID: String,
                               displayName: String, elo: Int,
                               inMatch: Bool = false, isFirstPass: Bool = false) async {
        // savePolicy = .allKeys : écrase tous les champs directement sur le serveur
        // sans fetch préalable. Évite l'erreur silencieuse serverRecordChanged qui
        // survient quand un record existe déjà avec un changeTag différent.
        let recID  = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: Self.recordType, recordID: recID)
        record["teamPlayerID"]  = teamID                as CKRecordValue
        record["displayName"]   = displayName           as CKRecordValue
        record["lastHeartbeat"] = Date()                as CKRecordValue
        record["eloRating"]     = elo                   as CKRecordValue
        record["inMatch"]       = (inMatch ? 1 : 0)    as CKRecordValue

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy       = .allKeys
        op.qualityOfService = .userInitiated

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                // perRecordSaveBlock : seul moyen fiable de détecter un échec
                // sur un enregistrement individuel dans une op non-atomique
                // (isAtomic = true interdit en Public Database).
                // modifyRecordsResultBlock retourne .success même si le record
                // a échoué → on capture l'erreur individuelle ici.
                var recordError: Error?
                op.perRecordSaveBlock = { (_, result: Result<CKRecord, Error>) in
                    if case .failure(let err) = result { recordError = err }
                }
                op.modifyRecordsResultBlock = { result in
                    if let err = recordError {
                        cont.resume(throwing: err)
                    } else {
                        switch result {
                        case .success:           cont.resume()
                        case .failure(let err):  cont.resume(throwing: err)
                        }
                    }
                }
                self.publicDB.add(op)
            }
            print("[Available] upserted OK: \(displayName)")
            if isFirstPass {
                NotificationCenter.default.post(
                    name: .blomixAvailabilityPublishResult, object: nil,
                    userInfo: ["success": true, "message": BlomixL10n.pvpGcConnected(displayName)])
            }
        } catch {
            let msg = error.localizedDescription
            print("[Available] upsert error: \(msg)")
            if isFirstPass {
                NotificationCenter.default.post(
                    name: .blomixAvailabilityPublishResult, object: nil,
                    userInfo: ["success": false, "message": BlomixL10n.pvpAvailabilityCloudKitError(msg)])
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

        let localGameID = GKLocalPlayer.local.isAuthenticated
            ? GKLocalPlayer.local.gamePlayerID : nil
        let localTeamID = GKLocalPlayer.local.isAuthenticated
            ? GKLocalPlayer.local.teamPlayerID : nil
        let cutoff = Date().addingTimeInterval(-5 * 60)

        // Filtrer côté serveur : seulement les enregistrements des 5 dernières minutes.
        // NSDate explicite requis — CloudKit ne reconnaît pas Date bridgé via CVarArg
        // pour les comparaisons côté serveur (le save réussit mais la requête retourne ∅).
        // sortDescriptors retiré : dépendance à un second index qui ralentit l'indexation
        // des records fraîchement écrits, aggravant la latence de visibilité.
        let predicate = NSPredicate(format: "lastHeartbeat >= %@", cutoff as NSDate)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)

        let (results, _) = try await publicDB.records(
            matching:     query,
            inZoneWith:   nil,
            desiredKeys:  ["teamPlayerID", "displayName", "eloRating", "lastHeartbeat", "inMatch"],
            resultsLimit: 50   // largement suffisant pour des joueurs actifs récents
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
                // Fenêtre de validité d'un défi : 90 s (vs 5 min pour les joueurs disponibles).
                // Couvre le timeout de 60 s du challenger + une marge de 30 s pour la latence
                // CloudKit, sans laisser traîner un défi périmé suite à une déconnexion du challenger.
                let challengeCutoff = Date().addingTimeInterval(-90)
                if let hb = record["lastHeartbeat"] as? Date, hb < challengeCutoff { continue }
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
                let name    = record["displayName"] as? String ?? "?"
                let elo     = record["eloRating"]   as? Int
                let inMatch = (record["inMatch"] as? Int ?? 0) != 0
                players.append(BlomixAvailablePlayer(gamePlayerID: gameID,
                                                     displayName: name,
                                                     eloRating: elo,
                                                     inMatch: inMatch))
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

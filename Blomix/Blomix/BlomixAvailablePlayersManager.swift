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
//    • Le challenger écrit un record "chfrom_{challengerGamePlayerID}" (record qu'il possède).
//    • teamPlayerID porte le gamePlayerID du joueur cible (champ queryable existant).
//    • Le challengé détecte ce record à son prochain poll (≤ 4 s).
//    • Les deux lancent GKMatchmaker.findMatch avec le même playerGroup déterministe.
//    • GKMatchmaker les associe sans avoir besoin de GKPlayer.recipients.
//
//  Important CloudKit Public DB : un joueur ne peut écrire que les records dont il est
//  créateur. L'ancien schéma "chal_{challengedGamePlayerID}" provoquait
//  "WRITE operation not permitted" car le challenger écrivait le record d'un autre joueur.
//
//  Record de défi sortant (même Record Type "AvailablePlayer") :
//    recordName    = "chfrom_{challengerGamePlayerID}"
//    teamPlayerID  = challengedGamePlayerID   (cible du défi — queryable)
//    displayName   = challengerDisplayName
//    eloRating     = matchPlayerGroup (Int)
//    lastHeartbeat = création (TTL 90 s)
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

    /// Cible du défi CloudKit sortant en cours (`chfrom_*`), si connu.
    /// Sert à détecter un défi croisé (A défie B pendant que B défie A).
    private(set) var outgoingChallengeTargetID: String?

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
        BlomixPvPLog.event("active_match", ["active": "\(active)"])
    }

    func setOutgoingChallengeTarget(_ gamePlayerID: String?) {
        outgoingChallengeTargetID = gamePlayerID
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

    // MARK: - Polling défi entrant (global, toutes les 4 s)

    private func startChallengePolling() {
        stopChallengePolling()
        lastNotifiedChallengerID = nil
        // Premier poll immédiat, puis toutes les 4 s.
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
            let challenge: BlomixIncomingChallenge?
            do {
                (_, challenge) = try await self.fetchAvailablePlayersAndChallenge()
            } catch {
                print("[Available] poll error: \(error.localizedDescription)")
                return
            }
            // Vérification après await : la partie a peut-être démarré pendant le fetch.
            guard !self.isInActiveMatch else { return }
            if let challenge {
                // P2.2 — Défi croisé : on défie déjà ce joueur → pas de bannière
                // (les deux matchmakent déjà sur le même playerGroup).
                if let out = self.outgoingChallengeTargetID,
                   out == challenge.challengerGamePlayerID {
                    BlomixPvPLog.event("mutual_challenge_detected", [
                        "peer": challenge.challengerGamePlayerID
                    ])
                    self.lastNotifiedChallengerID = challenge.challengerGamePlayerID
                    return
                }
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

    /// Supprime le record de défi sortant local puis remet lastNotifiedChallengerID à nil après un délai.
    /// Laisse passer au moins 2 cycles de poll le temps que CloudKit propage la suppression,
    /// évitant la boucle "déclin → poll → nouvelle bannière".
    func suppressChallengeWithDelay(challengedGamePlayerID: String) {
        _ = challengedGamePlayerID
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

        do {
            try await modifyRecords([record])
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

    /// Préfixe des records de défi sortant — le challenger écrit **son propre** record.
    private static let outgoingChallengePrefix = "chfrom_"
    /// Ancien format (lecture seule pour compatibilité) — provoquait WRITE not permitted à la création.
    private static let legacyChallengePrefix = "chal_"

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

    /// Écrit le défi sortant dans le record CloudKit **du challenger** (permissions CK Public DB).
    func createChallenge(challengerGamePlayerID: String,
                         challengerDisplayName: String,
                         challengedGamePlayerID: String,
                         matchPlayerGroup: Int) async throws {
        let recID  = CKRecord.ID(recordName: Self.outgoingChallengePrefix + challengerGamePlayerID)
        let record = CKRecord(recordType: Self.recordType, recordID: recID)
        // teamPlayerID = cible du défi (champ queryable) — pas le teamPlayerID Game Center ici.
        record["teamPlayerID"]  = challengedGamePlayerID as CKRecordValue
        record["displayName"]   = challengerDisplayName  as CKRecordValue
        record["eloRating"]     = matchPlayerGroup       as CKRecordValue
        record["lastHeartbeat"] = Date()                  as CKRecordValue
        try await modifyRecords([record])
        outgoingChallengeTargetID = challengedGamePlayerID
        BlomixPvPLog.event("challenge_created", [
            "from": challengerGamePlayerID,
            "to": challengedGamePlayerID,
            "group": "\(matchPlayerGroup)"
        ])
    }

    /// Supprime le record de défi sortant du joueur local (challenger uniquement).
    func clearOutgoingChallenge() {
        outgoingChallengeTargetID = nil
        guard let challengerID = cachedGamePlayerID
            ?? (GKLocalPlayer.local.isAuthenticated ? GKLocalPlayer.local.gamePlayerID : nil)
        else { return }
        let recID = CKRecord.ID(recordName: Self.outgoingChallengePrefix + challengerID)
        publicDB.delete(withRecordID: recID) { _, error in
            if let error {
                BlomixPvPLog.event("challenge_clear_error", ["error": error.localizedDescription])
            }
        }
    }

    /// Sauvegarde un ou plusieurs records via CKModifyRecordsOperation + .allKeys
    /// (évite serverRecordChanged sans fetch préalable ; requis en Public Database).
    private func modifyRecords(_ records: [CKRecord]) async throws {
        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.savePolicy       = .allKeys
        op.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var recordError: Error?
            op.perRecordSaveBlock = { (_, result: Result<CKRecord, Error>) in
                if case .failure(let err) = result { recordError = err }
            }
            op.modifyRecordsResultBlock = { result in
                if let err = recordError {
                    cont.resume(throwing: err)
                } else {
                    switch result {
                    case .success:          cont.resume()
                    case .failure(let err): cont.resume(throwing: err)
                    }
                }
            }
            self.publicDB.add(op)
        }
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
        var challengeHeartbeat: Date? = nil
        let challengeCutoff = Date().addingTimeInterval(-90)

        for (_, result) in results {
            guard case .success(let record) = result else { continue }
            let recName = record.recordID.recordName

            if recName.hasPrefix(Self.outgoingChallengePrefix) {
                // Défi sortant d'un autre joueur — m'intéresse si je suis la cible (teamPlayerID).
                guard let localGameID else { continue }
                let targetID = record["teamPlayerID"] as? String ?? ""
                guard targetID == localGameID else { continue }
                guard let hb = record["lastHeartbeat"] as? Date, hb >= challengeCutoff else { continue }
                let challengerID   = String(recName.dropFirst(Self.outgoingChallengePrefix.count))
                let challengerName = record["displayName"] as? String ?? "?"
                var matchGroup = Self.intFromRecord(record, key: "eloRating") ?? 0
                if matchGroup == 0, !challengerID.isEmpty {
                    matchGroup = Self.matchPlayerGroup(id1: localGameID, id2: challengerID)
                }
                if challengeHeartbeat == nil || hb > challengeHeartbeat! {
                    challengeHeartbeat = hb
                    challenge = BlomixIncomingChallenge(
                        challengerGamePlayerID: challengerID,
                        challengerDisplayName:  challengerName,
                        matchPlayerGroup:       matchGroup
                    )
                }

            } else if recName.hasPrefix(Self.legacyChallengePrefix) {
                // Ancien format chal_{challengedID} — lecture seule pour clients pas encore à jour.
                let challengedID = String(recName.dropFirst(Self.legacyChallengePrefix.count))
                guard challengedID == localGameID else { continue }
                guard let hb = record["lastHeartbeat"] as? Date, hb >= challengeCutoff else { continue }
                let challengerID   = record["teamPlayerID"] as? String ?? ""
                let challengerName = record["displayName"]  as? String ?? "?"
                var matchGroup = Self.intFromRecord(record, key: "eloRating") ?? 0
                if matchGroup == 0,
                   let localGameID,
                   !challengerID.isEmpty {
                    matchGroup = Self.matchPlayerGroup(id1: localGameID, id2: challengerID)
                }
                if challengeHeartbeat == nil || hb > challengeHeartbeat! {
                    challengeHeartbeat = hb
                    challenge = BlomixIncomingChallenge(
                        challengerGamePlayerID: challengerID,
                        challengerDisplayName:  challengerName,
                        matchPlayerGroup:       matchGroup
                    )
                }

            } else {
                // Record de joueur disponible.
                let gameID = recName
                let teamID = record["teamPlayerID"] as? String ?? gameID
                if gameID == localGameID { continue }
                if teamID == localTeamID { continue }
                if let hb = record["lastHeartbeat"] as? Date, hb < cutoff { continue }
                let name    = record["displayName"] as? String ?? "?"
                let elo     = Self.intFromRecord(record, key: "eloRating")
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

    /// Lit un entier depuis un champ CloudKit (Int, Int64 ou NSNumber).
    private static func intFromRecord(_ record: CKRecord, key: String) -> Int? {
        if let v = record[key] as? Int { return v }
        if let v = record[key] as? Int64 { return Int(v) }
        if let v = record[key] as? NSNumber { return v.intValue }
        return nil
    }

    private func fetchLocalElo() async -> Int? {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return nil }
        guard let profile = try? await BlomixEloManager.shared.fetchProfile(for: player),
              profile.completedMatchCount > 0
        else { return nil }
        return profile.rating
    }
}

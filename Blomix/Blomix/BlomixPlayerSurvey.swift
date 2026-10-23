//
//  BlomixPlayerSurvey.swift
//  Blomix
//
//  Sondage 8.8 : 10 parties solo, puis toutes les 10 (Plus tard).
//  Réponses → CloudKit Public `PlayerSurvey`. Pas Duel, pas tuto.
//

import CloudKit
import Foundation
@preconcurrency import GameKit

@MainActor
enum BlomixPlayerSurvey {

    static let campaignID = "8.8"
    static let recordType = "PlayerSurvey"
    static let gamesPerOffer = 10
    static let maxFreeText = 200

    enum Mode: String, CaseIterable, Sendable {
        case arcade
        case zen
        case daily
        case duel
        case five

        var title: String {
            switch self {
            case .arcade: return BlomixL10n.startButton
            case .zen: return BlomixL10n.zenButton
            case .daily: return BlomixL10n.startDaily
            case .duel: return BlomixL10n.startPvPButton
            case .five: return BlomixL10n.fiveButton
            }
        }
    }

    struct Answers: Codable, Sendable {
        var modes: [String]
        var improve: String
        var recommend: Int
        var recommendWhy: String
    }

    private static let gamesKey = "blomix_survey_8_8_games"
    private static let nextAtKey = "blomix_survey_8_8_next_at"
    private static let doneKey = "blomix_survey_8_8_done"
    private static let seededKey = "blomix_survey_8_8_seeded"
    private static let pendingKey = "blomix_survey_8_8_pending"
    private static let anonIDKey = "blomix_survey_8_8_anon_id"

    private static let ckContainer = CKContainer(identifier: "iCloud.blomig.BLOMIX")
    private static var publicDB: CKDatabase { ckContainer.publicCloudDatabase }

    /// Évite deux modales si l’accueil se reconstruit.
    static var isShowing = false

    static var shouldPresent: Bool {
        guard !isShowing else { return false }
        seedFromReviewCountIfNeeded()
        retryPendingUploadIfNeeded()
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return false }
        return completedGames >= nextOfferAt
    }

    static var completedGames: Int {
        max(0, UserDefaults.standard.integer(forKey: gamesKey))
    }

    static var nextOfferAt: Int {
        let stored = UserDefaults.standard.integer(forKey: nextAtKey)
        return stored > 0 ? stored : gamesPerOffer
    }

    static func recordCompletedGame() {
        seedFromReviewCountIfNeeded()
        UserDefaults.standard.set(completedGames + 1, forKey: gamesKey)
    }

    static func markLater() {
        let next = completedGames + gamesPerOffer
        UserDefaults.standard.set(next, forKey: nextAtKey)
        isShowing = false
    }

    static func markNever() {
        UserDefaults.standard.set(true, forKey: doneKey)
        isShowing = false
    }

    static func submit(_ answers: Answers) {
        UserDefaults.standard.set(true, forKey: doneKey)
        persistPending(answers)
        isShowing = false
        Task { await upload(answers) }
    }

    // MARK: - Compteur

    /// Joueurs 8.6 : le compteur avis Arcade/Zen/Five amorce le seuil « régulier ».
    private static func seedFromReviewCountIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)
        if UserDefaults.standard.object(forKey: gamesKey) == nil {
            UserDefaults.standard.set(BlomixReviewPrompt.completedGames, forKey: gamesKey)
        }
        if UserDefaults.standard.integer(forKey: nextAtKey) == 0 {
            UserDefaults.standard.set(gamesPerOffer, forKey: nextAtKey)
        }
    }

    // MARK: - CloudKit

    private static func persistPending(_ answers: Answers) {
        if let data = try? JSONEncoder().encode(answers) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    private static func retryPendingUploadIfNeeded() {
        guard UserDefaults.standard.bool(forKey: doneKey),
              let data = UserDefaults.standard.data(forKey: pendingKey),
              let answers = try? JSONDecoder().decode(Answers.self, from: data) else { return }
        Task { await upload(answers) }
    }

    private static func upload(_ answers: Answers) async {
        if BlomixPublicCloudGate.shared.isBlocked { return }
        let playerID = resolvedPlayerID()
        let recID = CKRecord.ID(recordName: "survey88_\(playerID)")
        do {
            try BlomixPublicCloudGate.shared.throwIfBlocked()
            let record: CKRecord
            if let existing = try? await publicDB.record(for: recID) {
                record = existing
            } else {
                record = CKRecord(recordType: recordType, recordID: recID)
            }
            record["campaign"] = campaignID as CKRecordValue
            record["modes"] = answers.modes.joined(separator: ",") as CKRecordValue
            record["improve"] = answers.improve as CKRecordValue
            record["recommend"] = answers.recommend as CKRecordValue
            record["recommendWhy"] = answers.recommendWhy as CKRecordValue
            record["locale"] = (Locale.current.language.languageCode?.identifier ?? "und") as CKRecordValue
            record["appVersion"] = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") as CKRecordValue
            record["gamePlayerID"] = playerID as CKRecordValue
            _ = try await publicDB.save(record)
            BlomixPublicCloudGate.shared.noteSuccess()
            UserDefaults.standard.removeObject(forKey: pendingKey)
        } catch {
            BlomixPublicCloudGate.shared.noteError(error)
            print("[Survey] upload : \(error.localizedDescription)")
        }
    }

    private static func resolvedPlayerID() -> String {
        let gk = GKLocalPlayer.local.gamePlayerID
        if !gk.isEmpty, gk != "GKPlayerIDUnknown" { return gk }
        if let existing = UserDefaults.standard.string(forKey: anonIDKey), !existing.isEmpty {
            return existing
        }
        let fresh = "anon_\(UUID().uuidString)"
        UserDefaults.standard.set(fresh, forKey: anonIDKey)
        return fresh
    }
}

//
//  BlomixEloManager.swift
//  Blomix
//
//  Gestion Elo dédiée au mode PvP : lecture/soumission Game Center,
//  calcul des ratings et préparation du matchmaking orienté compétence.
//

import Foundation
import GameKit

enum BlomixPvPMatchOutcome: Sendable {
    case win
    case loss
    case draw

    fileprivate var normalizedScore: Double {
        switch self {
        case .win: return 1.0
        case .loss: return 0.0
        case .draw: return 0.5
        }
    }
}

struct BlomixEloProfile: Sendable {
    let rating: Int
    let completedMatchCount: Int
}

struct BlomixEloResult: Sendable {
    let localOldRating: Int
    let remoteOldRating: Int
    let localNewRating: Int
    let remoteNewRating: Int
    let localMatchCountBefore: Int
    let remoteMatchCountBefore: Int
    let localMatchCountAfter: Int
    let remoteMatchCountAfter: Int
    let localKFactor: Double
    let remoteKFactor: Double
    let expectedLocalScore: Double
    let expectedRemoteScore: Double

    var debugSummary: String {
        "local \(localOldRating) -> \(localNewRating) (matches \(localMatchCountBefore) -> \(localMatchCountAfter), K=\(localKFactor)), remote \(remoteOldRating) -> \(remoteNewRating) (matches \(remoteMatchCountBefore) -> \(remoteMatchCountAfter), K=\(remoteKFactor)), expectedLocal=\(expectedLocalScore), expectedRemote=\(expectedRemoteScore)"
    }
}

@MainActor
final class BlomixEloManager {
    static let shared = BlomixEloManager()

    /// Leaderboard Game Center dédié au PvP Elo (Most Recent Score).
    let leaderboardID = "elotype"
    /// Valeur de départ pour tout joueur sans entrée Elo existante.
    let defaultRating = 800
    /// K-factor classique "standard club" : variations lisibles sans être trop brutales.
    let kFactor = 32

    /// Nom exact de la queue de matchmaking rules-based configurée dans App Store Connect.
    /// Laissez `nil` tant que la queue n’existe pas encore côté backend Game Center.
    private let matchmakingQueueName: String? = nil
    private let matchmakingPropertyKey = "elo"

    private enum LocalCache {
        /// Incrémenter cette version si l’on doit invalider d’anciens caches Elo locaux.
        static let keyPrefix = "BlomixPvPEloCache.v2"
    }

    private init() {}

    // MARK: - Elo formula

    /// Score attendu du joueur local face à l’adversaire, selon la formule Elo classique des échecs.
    ///
    /// `expected = 1 / (1 + 10 ^ ((opp - self) / 400))`
    func expectedScore(rating: Int, opponentRating: Int) -> Double {
        let exponent = Double(opponentRating - rating) / 400.0
        return 1.0 / (1.0 + pow(10.0, exponent))
    }

    /// K-factor progressif : démarre à 40 puis diminue avec l’expérience,
    /// avec un plancher à 20 pour garantir au moins ±10 pts entre joueurs de même niveau.
    ///
    /// Décroissance : K = max(20, 40 / (1 + n/80))
    ///   n=0  → K=40   (±20 pts entre égaux)
    ///   n=40 → K≈26.7 (±13 pts entre égaux)
    ///   n=80 → K=20   (±10 pts entre égaux) — plancher
    func kFactor(forCompletedMatchCount matchCount: Int) -> Double {
        let normalizedCount = max(0, matchCount)
        return max(20.0, 40.0 / (1.0 + Double(normalizedCount) / 80.0))
    }

    /// Calcule les nouveaux ratings Elo des deux joueurs après un match.
    ///
    /// La formule appliquée est :
    /// `new = old + K * (scoreRéel - scoreAttendu)`
    ///
    /// - Parameters:
    ///   - localRating: Elo actuel du joueur local.
    ///   - remoteRating: Elo actuel de l’adversaire.
    ///   - outcome: résultat du match vu côté joueur local.
    /// - Returns: les nouveaux ratings des deux joueurs, ainsi que les scores attendus utilisés.
    func updatedRatings(localProfile: BlomixEloProfile, remoteProfile: BlomixEloProfile, outcome: BlomixPvPMatchOutcome) -> BlomixEloResult {
        let expectedLocal = expectedScore(rating: localProfile.rating, opponentRating: remoteProfile.rating)
        let expectedRemote = expectedScore(rating: remoteProfile.rating, opponentRating: localProfile.rating)

        let actualLocal = outcome.normalizedScore
        let actualRemote = 1.0 - actualLocal

        let localK = kFactor(forCompletedMatchCount: localProfile.completedMatchCount)
        let remoteK = kFactor(forCompletedMatchCount: remoteProfile.completedMatchCount)
        let localDelta = localK * (actualLocal - expectedLocal)
        let remoteDelta = remoteK * (actualRemote - expectedRemote)

        let newLocal = max(0, Int((Double(localProfile.rating) + localDelta).rounded()))
        let newRemote = max(0, Int((Double(remoteProfile.rating) + remoteDelta).rounded()))

        return BlomixEloResult(
            localOldRating: localProfile.rating,
            remoteOldRating: remoteProfile.rating,
            localNewRating: newLocal,
            remoteNewRating: newRemote,
            localMatchCountBefore: localProfile.completedMatchCount,
            remoteMatchCountBefore: remoteProfile.completedMatchCount,
            localMatchCountAfter: localProfile.completedMatchCount + 1,
            remoteMatchCountAfter: remoteProfile.completedMatchCount + 1,
            localKFactor: localK,
            remoteKFactor: remoteK,
            expectedLocalScore: expectedLocal,
            expectedRemoteScore: expectedRemote
        )
    }

    // MARK: - Public Elo IO

    func fetchLocalPlayerElo() async throws -> Int {
        try await fetchLocalPlayerProfile().rating
    }

    func fetchLocalPlayerProfile() async throws -> BlomixEloProfile {
        guard GKLocalPlayer.local.isAuthenticated else {
            throw makeError(code: 1, description: "Joueur local non authentifié : Elo indisponible.")
        }

        do {
            let current = try await loadLocalPlayerProfileFromLeaderboard()
            let resolved = current ?? BlomixEloProfile(rating: defaultRating, completedMatchCount: 0)
            persistLocalProfileCache(resolved)
            if current == nil {
                do {
                    try await submitLocalProfile(resolved)
                    print("[PvP Elo] Aucun Elo existant : initialisation du leaderboard « \(leaderboardID) » à \(resolved.rating) (matches=\(resolved.completedMatchCount)).")
                } catch {
                    print("[PvP Elo] Aucun Elo existant et initialisation Game Center impossible pour l’instant. Fallback local conservé à \(resolved.rating) / matches=\(resolved.completedMatchCount). Erreur: \(error.localizedDescription)")
                }
            }
            return resolved
        } catch {
            if let cached = cachedLocalProfile() {
                print("[PvP Elo] Lecture Game Center échouée, fallback sur le cache local: rating=\(cached.rating), matches=\(cached.completedMatchCount). Erreur: \(error.localizedDescription)")
                return cached
            }
            throw error
        }
    }

    func fetchElo(for player: GKPlayer) async throws -> Int {
        try await fetchProfile(for: player).rating
    }

    func fetchProfile(for player: GKPlayer) async throws -> BlomixEloProfile {
        guard GKLocalPlayer.local.isAuthenticated else {
            throw makeError(code: 2, description: "Joueur local non authentifié : impossible de lire l’Elo adverse.")
        }
        let current = try await loadProfileFromLeaderboard(for: player)
        return current ?? BlomixEloProfile(rating: defaultRating, completedMatchCount: 0)
    }

    func submitLocalElo(_ value: Int) async throws {
        try await submitLocalProfile(BlomixEloProfile(
            rating: value,
            completedMatchCount: cachedLocalProfile()?.completedMatchCount ?? 0
        ))
    }

    func submitLocalProfile(_ profile: BlomixEloProfile) async throws {
        guard GKLocalPlayer.local.isAuthenticated else {
            throw makeError(code: 3, description: "Joueur local non authentifié : impossible d’envoyer l’Elo.")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            GKLeaderboard.submitScore(
                profile.rating,
                context: profile.completedMatchCount,
                player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboardID]
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        persistLocalProfileCache(profile)
        print("[PvP Elo] Profil local soumis sur « \(leaderboardID) » : rating=\(profile.rating), matches=\(profile.completedMatchCount).")
    }

    @discardableResult
    func finalizeLocalPlayerRating(
        outcome: BlomixPvPMatchOutcome,
        against remotePlayer: GKPlayer
    ) async throws -> BlomixEloResult {
        let localProfile = try await fetchLocalPlayerProfile()
        let remoteProfile = try await fetchProfile(for: remotePlayer)
        let result = updatedRatings(localProfile: localProfile, remoteProfile: remoteProfile, outcome: outcome)
        try await submitLocalProfile(BlomixEloProfile(
            rating: result.localNewRating,
            completedMatchCount: result.localMatchCountAfter
        ))
        print("[PvP Elo] Résultat finalisé: \(result.debugSummary)")
        return result
    }

    // MARK: - Matchmaking

    /// Prépare une `GKMatchRequest` 1v1 pour le PvP orienté Elo.
    ///
    /// L’Elo source vient toujours du leaderboard `elotype`.
    /// En revanche, GameKit exige une `queueName` non nulle avant d’accepter `properties`.
    /// Tant que la queue App Store Connect n’est pas créée, on retombe donc sur l’automatch standard.
    func makePvPMatchRequest() async -> GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2

        guard let queueName = matchmakingQueueName, !queueName.isEmpty else {
            request.queueName = nil
            request.properties = nil
            print("[PvP Elo] Queue App Store Connect absente : automatch standard sans propriété Elo.")
            return request
        }

        do {
            let localElo = try await fetchLocalPlayerElo()
            request.queueName = queueName
            request.properties = [matchmakingPropertyKey: localElo]
            print("[PvP Elo] Matchmaking préparé depuis « \(leaderboardID) » avec queue « \(queueName) » et propriété \(matchmakingPropertyKey)=\(localElo).")
        } catch {
            request.queueName = nil
            request.properties = nil
            print("[PvP Elo] Impossible de préparer le matchmaking Elo depuis « \(leaderboardID) » : \(error.localizedDescription). Fallback automatch standard.")
        }

        return request
    }

    // MARK: - Private leaderboard access

    private func loadLocalPlayerProfileFromLeaderboard() async throws -> BlomixEloProfile? {
        try await withCheckedThrowingContinuation { continuation in
            GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { leaderboards, loadError in
                if let loadError {
                    continuation.resume(throwing: loadError)
                    return
                }
                guard let leaderboard = leaderboards?.first else {
                    continuation.resume(throwing: self.makeError(
                        code: 4,
                        description: "Leaderboard Elo « \(self.leaderboardID) » introuvable."
                    ))
                    return
                }

                leaderboard.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime) { _, entries, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let profile: BlomixEloProfile? = entries?.first.flatMap { self.normalizedProfile(fromRating: Int($0.score), completedMatchCount: Swift.max(0, $0.context)) }
                    continuation.resume(returning: profile)
                }
            }
        }
    }

    private func loadProfileFromLeaderboard(for player: GKPlayer) async throws -> BlomixEloProfile? {
        try await withCheckedThrowingContinuation { continuation in
            GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { leaderboards, loadError in
                if let loadError {
                    continuation.resume(throwing: loadError)
                    return
                }
                guard let leaderboard = leaderboards?.first else {
                    continuation.resume(throwing: self.makeError(
                        code: 5,
                        description: "Leaderboard Elo « \(self.leaderboardID) » introuvable."
                    ))
                    return
                }

                leaderboard.loadEntries(for: [player], timeScope: .allTime) { _, entries, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let profile: BlomixEloProfile? = entries?.first.flatMap { self.normalizedProfile(fromRating: Int($0.score), completedMatchCount: Swift.max(0, $0.context)) }
                    continuation.resume(returning: profile)
                }
            }
        }
    }

    // MARK: - Private cache

    private func cachedLocalProfile() -> BlomixEloProfile? {
        let ratingKey = localProfileCacheKey(suffix: "rating")
        let matchesKey = localProfileCacheKey(suffix: "matches")
        guard UserDefaults.standard.object(forKey: ratingKey) != nil else { return nil }
        let rating = UserDefaults.standard.integer(forKey: ratingKey)
        let matches = UserDefaults.standard.integer(forKey: matchesKey)
        return BlomixEloProfile(rating: rating, completedMatchCount: max(0, matches))
    }

    private func persistLocalProfileCache(_ profile: BlomixEloProfile) {
        UserDefaults.standard.set(profile.rating, forKey: localProfileCacheKey(suffix: "rating"))
        UserDefaults.standard.set(profile.completedMatchCount, forKey: localProfileCacheKey(suffix: "matches"))
    }

    private func localProfileCacheKey(suffix: String) -> String {
        let local = GKLocalPlayer.local
        let stablePlayerID = local.teamPlayerID.isEmpty ? local.gamePlayerID : local.teamPlayerID
        return "\(LocalCache.keyPrefix).\(stablePlayerID).\(suffix)"
    }

    private func normalizedProfile(fromRating rating: Int, completedMatchCount: Int) -> BlomixEloProfile? {
        let normalizedMatches = max(0, completedMatchCount)

        // Après le reset du leaderboard, ou avec une ancienne build, Game Center peut encore exposer
        // une valeur "vide" / legacy (< 800 avec 0 match). On la traite comme une absence d'entrée.
        guard !(normalizedMatches == 0 && rating < defaultRating) else { return nil }

        return BlomixEloProfile(
            rating: rating,
            completedMatchCount: normalizedMatches
        )
    }

    // MARK: - Errors

    private func makeError(code: Int, description: String) -> NSError {
        NSError(
            domain: "BlomixEloManager",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

//
//  ScoreManager.swift
//  Blomix
//
//  Singleton centralisant l’authentification Game Center, l’envoi des scores
//  et la lecture optionnelle du meilleur score local (leaderboard App Store Connect).
//

import Foundation
@preconcurrency import GameKit
import UIKit

/// Gestion Game Center pour le classement principal **BlomigMainScore_v2**.
///
/// - Appelez **`authenticateOnLaunch(from:)`** une seule fois au démarrage (ex. `SceneDelegate` / `AppDelegate`).
/// - **`submitScore`** met toujours à jour le **backup UserDefaults** si le score bat le record local, puis tente Game Center.
/// - **`fetchLocalPlayerBestScore`** alimente la comparaison pour **`isNewPersonalBest`** (max local + GC si déjà chargé).
@MainActor
final class ScoreManager {
    // MARK: - Singleton

    static let shared = ScoreManager()

    /// Identifiant du leaderboard configuré dans App Store Connect (doit correspondre exactement).
    nonisolated static let mainLeaderboardID    = "BlomixMainScore_v3"
    /// Leaderboard « score moyen » (Most Recent Score dans App Store Connect).
    nonisolated static let averageLeaderboardID = "BlomixAverageScore_v1"
    /// Leaderboard dédié au mode Zen.
    nonisolated static let zenLeaderboardID     = "ZenMode"

    private init() {
        migrateScoreVersionIfNeeded()
    }

    /// Réinitialise le meilleur score local si la version du scoring a changé (nouveau leaderboard, nouveau système de points).
    private func migrateScoreVersionIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: LocalPersistence.scoreVersionKey)
        guard stored < LocalPersistence.currentScoreVersion else { return }
        UserDefaults.standard.set(0, forKey: LocalPersistence.highScoreKey)
        UserDefaults.standard.set(0, forKey: LocalPersistence.pendingGCScoreKey)
        UserDefaults.standard.set(LocalPersistence.currentScoreVersion, forKey: LocalPersistence.scoreVersionKey)
        print("[ScoreManager] Migration v\(LocalPersistence.currentScoreVersion) : meilleur score local remis à zéro.")
    }

    // MARK: - État

    /// Indique si le joueur local est authentifié auprès de Game Center (mis à jour après le flux `authenticateHandler`).
    private(set) var isAuthenticated = false

    /// Évite de réinstaller `GKLocalPlayer.local.authenticateHandler` (une seule configuration au lancement).
    private var didStartAuthentication = false

    // MARK: - High-score local (backup UserDefaults)

    private enum LocalPersistence {
        static let highScoreKey      = "BlomixLocalHighScore"
        /// Meilleur score Zen enregistré localement (indépendant du record Solo).
        static let zenHighScoreKey   = "BlomixLocalZenHighScore"
        /// Meilleur score réalisé hors ligne (GC inaccessible) — soumis automatiquement à la reconnexion.
        static let pendingGCScoreKey = "BlomixPendingGCScore"
        /// Version du système de score. Incrémentée quand les scores ne sont plus comparables (nouveau leaderboard, nouveau système de points…).
        static let scoreVersionKey   = "BlomixScoreVersion"
        static let currentScoreVersion = 3   // v3 : nouveau leaderboard BlomixMainScore_v3 + nouveau système de points

        // ── Statistiques de moyenne (JAMAIS réinitialisées par la migration de version) ──
        /// Somme cumulée de tous les scores de parties solo complètes (de tout temps).
        static let avgTotalScoreKey  = "BlomixAvgTotalScore"
        /// Nombre de parties solo complètes enregistrées dans la moyenne.
        static let avgGameCountKey   = "BlomixAvgGameCount"
    }

    /// Meilleur score enregistré sur l’appareil (synchronisé avec `UserDefaults`, clé **BlomixLocalHighScore**).
    private var localHighScore: Int {
        get { UserDefaults.standard.integer(forKey: LocalPersistence.highScoreKey) }
        set { UserDefaults.standard.set(newValue, forKey: LocalPersistence.highScoreKey) }
    }

    /// Meilleur score Zen enregistré sur l'appareil, indépendant du record Solo.
    private var localZenHighScore: Int {
        get { UserDefaults.standard.integer(forKey: LocalPersistence.zenHighScoreKey) }
        set { UserDefaults.standard.set(newValue, forKey: LocalPersistence.zenHighScoreKey) }
    }

    /// Met à jour le high-score Solo **disque** uniquement si `score` est strictement supérieur à la valeur actuelle.
    @discardableResult
    func updateLocalHighScoreIfBetter(_ score: Int) -> Bool {
        guard score > localHighScore else {
            print("[ScoreManager] Backup local : score \(score) ne dépasse pas le record \(localHighScore) — aucune écriture.")
            return false
        }
        localHighScore = score
        print("[ScoreManager] Backup local (UserDefaults) mis à jour : nouveau record = \(score).")
        return true
    }

    /// Met à jour le high-score Zen **disque** uniquement si `score` est strictement supérieur à la valeur actuelle.
    @discardableResult
    func updateLocalZenHighScoreIfBetter(_ score: Int) -> Bool {
        guard score > localZenHighScore else { return false }
        localZenHighScore = score
        print("[ScoreManager] Backup Zen local mis à jour : nouveau record Zen = \(score).")
        return true
    }

    /// Retourne le meilleur score Solo persisté localement (0 si aucune partie enregistrée).
    func getLocalHighScore() -> Int { localHighScore }

    /// Retourne le meilleur score Zen persisté localement (0 si aucune partie enregistrée).
    func getLocalZenHighScore() -> Int { localZenHighScore }

    // MARK: - Référence Game Center (pour comparaisons « record personnel »)

    /// `true` après au moins un **`fetchLocalPlayerBestScore`** réussi (même si le joueur n’a pas encore d’entrée → score 0 côté GC).
    private var hasFetchedGameCenterPersonalBest = false

    /// Dernier meilleur score **Game Center** connu (0 = fetch OK mais aucune entrée sur le classement).
    private var cachedGameCenterPersonalBest: Int = 0

    /// Mémorise le résultat d’un chargement Game Center pour alimenter **`isNewPersonalBest`**.
    private func recordGameCenterPersonalBestFromFetch(_ best: Int?, leaderboardID: String = ScoreManager.mainLeaderboardID) {
        if leaderboardID == ScoreManager.zenLeaderboardID {
            hasFetchedGameCenterZenPersonalBest = true
            cachedGameCenterZenPersonalBest = best ?? 0
        } else {
            hasFetchedGameCenterPersonalBest = true
            cachedGameCenterPersonalBest = best ?? 0
        }
    }

    /// Indique si `score` bat le **meilleur connu** : max entre le backup local et, si déjà chargé, le meilleur score Game Center.
    func isNewPersonalBest(_ score: Int) -> Bool {
        let local = getLocalHighScore()
        let reference: Int
        if hasFetchedGameCenterPersonalBest {
            reference = max(local, cachedGameCenterPersonalBest)
        } else {
            reference = local
        }
        return score > reference
    }

    // ── Cache Game Center Zen (symétrique du cache Solo) ───────────────────────
    private var hasFetchedGameCenterZenPersonalBest = false
    private var cachedGameCenterZenPersonalBest: Int = 0

    /// Indique si `score` bat le **meilleur Zen connu** : max entre backup local et cache GC Zen (si chargé).
    func isNewZenPersonalBest(_ score: Int) -> Bool {
        let local = getLocalZenHighScore()
        let reference = hasFetchedGameCenterZenPersonalBest
            ? max(local, cachedGameCenterZenPersonalBest)
            : local
        return score > reference
    }

    // MARK: - Authentification

    /// Lance le flux d’authentification Game Center **une seule fois** pour la durée de vie du processus.
    ///
    /// GameKit peut fournir un `UIViewController` à présenter (connexion / création de compte). Les rappels
    /// du handler peuvent arriver hors thread principal : tout est republié sur le **main actor**.
    ///
    /// - Parameter viewController: Contrôleur racine utilisé pour présenter la feuille Game Center si nécessaire.
    func authenticateOnLaunch(from viewController: UIViewController) {
        guard !didStartAuthentication else { return }
        didStartAuthentication = true

        GKLocalPlayer.local.authenticateHandler = { [weak self, weak viewController] gcAuthViewController, error in
            Task { @MainActor in
                guard let self else { return }

                guard let viewController else {
                    print("[ScoreManager] Authentification : UIViewController indisponible (déréférencé).")
                    self.isAuthenticated = false
                    NotificationCenter.default.post(name: .blomixGameCenterAuthDidChange, object: nil)
                    return
                }

                if let gcAuthViewController {
                    print("[ScoreManager] Présentation de l’interface d’authentification Game Center.")
                    viewController.present(gcAuthViewController, animated: true)
                    return
                }

                if let error {
                    print("[ScoreManager] Échec d’authentification Game Center : \(error.localizedDescription)")
                    self.isAuthenticated = false
                    NotificationCenter.default.post(name: .blomixGameCenterAuthDidChange, object: nil)
                    return
                }

                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                let name = GKLocalPlayer.local.displayName
                print("[ScoreManager] Authentification terminée. isAuthenticated=\(self.isAuthenticated), displayName=\(name)")
                NotificationCenter.default.post(name: .blomixGameCenterAuthDidChange, object: nil)
                if self.isAuthenticated {
                    self.flushPendingGCScoreIfNeeded()
                }
            }
        }
    }

    // MARK: - Score en attente (hors ligne → synchro GC à la reconnexion)

    /// Mémorise `score` comme score à soumettre à Game Center dès que la connexion sera rétablie.
    /// Ne conserve que le meilleur score accumulé entre plusieurs parties hors ligne.
    private func savePendingGCScore(_ score: Int) {
        let current = UserDefaults.standard.integer(forKey: LocalPersistence.pendingGCScoreKey)
        guard score > current else { return }
        UserDefaults.standard.set(score, forKey: LocalPersistence.pendingGCScoreKey)
        print("[ScoreManager] Score \(score) mis en attente pour synchronisation Game Center (hors ligne).")
    }

    private func clearPendingGCScore() {
        UserDefaults.standard.removeObject(forKey: LocalPersistence.pendingGCScoreKey)
    }

    /// Appelé dès que Game Center redevient disponible : soumet le meilleur score enregistré hors ligne (s'il existe).
    private func flushPendingGCScoreIfNeeded() {
        let pending = UserDefaults.standard.integer(forKey: LocalPersistence.pendingGCScoreKey)
        guard pending > 0 else { return }
        clearPendingGCScore()
        print("[ScoreManager] Reconnexion Game Center — soumission du score en attente : \(pending).")
        submitScore(pending)
    }

    // MARK: - Moyenne des scores (leaderboard BlomixAverageScore_v1)

    /// Enregistre le score d'une partie solo complète, recalcule la moyenne et la soumet à Game Center.
    ///
    /// Les clés UserDefaults utilisées (`BlomixAvgTotalScore` / `BlomixAvgGameCount`) ne sont jamais
    /// effacées par `migrateScoreVersionIfNeeded()` — elles survivent à toutes les mises à jour de l'app.
    ///
    /// - Parameter score: Score final de la partie (ignoré s'il est ≤ 0).
    func recordGameScore(_ score: Int) {
        guard score > 0 else { return }
        let ud = UserDefaults.standard
        let total = max(0, ud.integer(forKey: LocalPersistence.avgTotalScoreKey)) + score
        let count = max(0, ud.integer(forKey: LocalPersistence.avgGameCountKey)) + 1
        ud.set(total, forKey: LocalPersistence.avgTotalScoreKey)
        ud.set(count, forKey: LocalPersistence.avgGameCountKey)
        let average = total / count   // entier, arrondi vers le bas
        print("[ScoreManager] Moyenne mise à jour : \(total) / \(count) = \(average) pts (après \(count) partie(s)).")
        // Soumission directe vers le leaderboard dédié — on ne passe PAS par submitScore()
        // pour ne pas risquer de modifier le high score local (updateLocalHighScoreIfBetter).
        // Le nombre de parties est stocké dans le champ `context` (Int64) pour être
        // visible sur le classement par tous les joueurs.
        submitAverageScoreToGC(average, gameCount: count)
    }

    private func submitAverageScoreToGC(_ average: Int, gameCount: Int) {
        guard isAuthenticated else {
            print("[ScoreManager] submitAverageScoreToGC(\(average)) : Game Center non disponible — valeur conservée localement.")
            return
        }
        GKLeaderboard.submitScore(
            average,
            context: gameCount,
            player: GKLocalPlayer.local,
            leaderboardIDs: [ScoreManager.averageLeaderboardID]
        ) { error in
            DispatchQueue.main.async {
                if let error {
                    print("[ScoreManager] Erreur soumission moyenne : \(error.localizedDescription)")
                } else {
                    print("[ScoreManager] Moyenne \(average) soumise avec succès sur « \(ScoreManager.averageLeaderboardID) ».")
                }
            }
        }
    }

    /// Retourne la moyenne locale actuelle (0 si aucune partie enregistrée). Lecture seule, sans appel réseau.
    func localAverageScore() -> Int {
        let ud = UserDefaults.standard
        let total = max(0, ud.integer(forKey: LocalPersistence.avgTotalScoreKey))
        let count = max(0, ud.integer(forKey: LocalPersistence.avgGameCountKey))
        guard count > 0 else { return 0 }
        return total / count
    }

    /// Nombre de parties enregistrées dans la moyenne locale (0 si aucune). Utilisé comme fallback
    /// dans le classement quand `entry.context` vaut 0 (entrée soumise avant l'ajout du context).
    func localGameCount() -> Int {
        max(0, UserDefaults.standard.integer(forKey: LocalPersistence.avgGameCountKey))
    }

    // MARK: - Soumission de score

    /// Envoie un score entier au leaderboard **BlomigMainScore_v2** (ou un autre ID si vous le surchargez).
    ///
    /// Utilise l’API moderne `GKLeaderboard.submitScore(_:context:player:leaderboardIDs:completionHandler:)`.
    ///
    /// - Parameters:
    ///   - score: Valeur publiée sur le classement (entier positif attendu par Game Center).
    ///   - leaderboardID: Identifiant App Store Connect du leaderboard.
    ///   - context: Métadonnée entière optionnelle associée au score (0 par défaut).
    ///   - completion: Appelé sur le **main thread** ; `nil` si vous n’avez pas besoin de retour.
    func submitScore(
        _ score: Int,
        leaderboardID: String = ScoreManager.mainLeaderboardID,
        context: Int = 0,
        completion: (@Sendable @MainActor (Result<Void, Error>) -> Void)? = nil
    ) {
        // Backup disque **toujours** tenté en premier (hors ligne, échec réseau Game Center, ou joueur non connecté).
        if leaderboardID == ScoreManager.zenLeaderboardID {
            _ = updateLocalZenHighScoreIfBetter(score)
        } else {
            _ = updateLocalHighScoreIfBetter(score)
        }

        guard isAuthenticated else {
            // GC inaccessible : on mémorise le score pour l'envoyer à la prochaine reconnexion.
            savePendingGCScore(score)
            let error = NSError(
                domain: "ScoreManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Joueur non authentifié : impossible d’envoyer le score."]
            )
            print("[ScoreManager] submitScore(\(score)) : Game Center non disponible (non authentifié). Backup UserDefaults = \(getLocalHighScore()).")
            completion?(.failure(error))
            return
        }

        print("[ScoreManager] Soumission du score \(score) vers « \(leaderboardID) »…")

        GKLeaderboard.submitScore(
            score,
            context: context,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    // Échec réseau alors qu'authentifié : mise en attente pour re-tentative à la prochaine reconnexion GC.
                    self.savePendingGCScore(score)
                    print("[ScoreManager] Erreur Game Center après submitScore : \(error.localizedDescription) — backup local (UserDefaults) = \(self.getLocalHighScore()).")
                    completion?(.failure(error))
                } else {
                    print("[ScoreManager] Score \(score) soumis avec succès sur « \(leaderboardID) ».")
                    completion?(.success(()))
                }
            }
        }
    }

    // MARK: - Lecture du meilleur score local

    /// Charge le classement puis récupère l’entrée **du joueur local** (meilleur score all-time, portée globale).
    ///
    /// - Parameters:
    ///   - leaderboardID: Identifiant du leaderboard.
    ///   - completion: Appelé sur le **main thread** avec `.success(nil)` si le joueur n’a encore aucune entrée.
    func fetchLocalPlayerBestScore(
        leaderboardID: String = ScoreManager.mainLeaderboardID,
        completion: @escaping @Sendable @MainActor (Result<Int?, Error>) -> Void
    ) {
        guard isAuthenticated else {
            let error = NSError(
                domain: "ScoreManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Joueur non authentifié : impossible de charger le classement."]
            )
            print("[ScoreManager] fetchLocalPlayerBestScore annulé : non authentifié.")
            completion(.failure(error))
            return
        }

        print("[ScoreManager] Chargement du leaderboard « \(leaderboardID) » pour le meilleur score local…")

        // Les callbacks GameKit sont `@Sendable` : ne pas faire traverser `GKLeaderboard` / `GKLeaderboard.Entry` vers une autre file ;
        // on extrait des `Int?` / erreurs sur la file du callback, puis on repasse sur le MainActor avec ces types `Sendable`.
        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { leaderboards, loadError in
            if let loadError {
                Task { @MainActor in
                    print("[ScoreManager] Erreur loadLeaderboards : \(loadError.localizedDescription)")
                    completion(.failure(loadError))
                }
                return
            }

            guard let leaderboard = leaderboards?.first else {
                let error = NSError(
                    domain: "ScoreManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Aucun leaderboard retourné pour l’identifiant « \(leaderboardID) »."]
                )
                Task { @MainActor in
                    print("[ScoreManager] Liste de leaderboards vide pour « \(leaderboardID) ».")
                    completion(.failure(error))
                }
                return
            }

            leaderboard.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1)) { localPlayerEntry, _, _, error in
                if let error {
                    Task { @MainActor in
                        print("[ScoreManager] Erreur loadEntries : \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                    return
                }

                let bestScore: Int? = localPlayerEntry.map { Int($0.score) }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let value = bestScore {
                        self.recordGameCenterPersonalBestFromFetch(value, leaderboardID: leaderboardID)
                        print("[ScoreManager] Meilleur score local sur « \(leaderboardID) » : \(value).")
                        completion(.success(value))
                    } else {
                        self.recordGameCenterPersonalBestFromFetch(nil, leaderboardID: leaderboardID)
                        print("[ScoreManager] Aucune entrée locale encore enregistrée sur « \(leaderboardID) ».")
                        completion(.success(nil))
                    }
                }
            }
        }
    }

    /// Fetches the local player's global rank in `mainLeaderboardID` (BlomixMainScore_v3).
    /// Calls `completion` on the **main thread** with the rank (1-based), or `nil` on failure
    /// or if the player has no entry yet.
    func fetchLocalPlayerMainScoreRank(completion: @escaping @Sendable @MainActor (Int?) -> Void) {
        fetchLocalPlayerRank(leaderboardID: ScoreManager.mainLeaderboardID, completion: completion)
    }

    /// Fetches the local player's global rank in any leaderboard.
    /// Calls `completion` on the **main thread** with the rank (1-based), or `nil` on failure
    /// or if the player has no entry yet. Rank is not capped — the player's actual position
    /// in the full global leaderboard is returned regardless of their standing.
    func fetchLocalPlayerRank(leaderboardID: String, completion: @escaping @Sendable @MainActor (Int?) -> Void) {
        guard GKLocalPlayer.local.isAuthenticated else {
            Task { @MainActor in completion(nil) }
            return
        }

        // Box @unchecked : GKLeaderboard n'est pas Sendable, mais l'API GK reste thread-safe ici.
        struct LeaderboardBox: @unchecked Sendable { let board: GKLeaderboard }

        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { leaderboards, error in
            guard let leaderboard = leaderboards?.first, error == nil else {
                Task { @MainActor in completion(nil) }
                return
            }
            let boardBox = LeaderboardBox(board: leaderboard)
            boardBox.board.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1)) { localEntry, _, _, err in
                if err == nil, let rank = localEntry?.rank {
                    Task { @MainActor in completion(rank) }
                    return
                }
                // Secours : entrée explicite du joueur local (comme LeaderboardViewController).
                boardBox.board.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime) { _, entries, err2 in
                    let rank: Int? = (err2 == nil) ? entries?.first?.rank : nil
                    Task { @MainActor in completion(rank) }
                }
            }
        }
    }
}

//
//  ScoreManager.swift
//  Blomix
//
//  Singleton centralisant l’authentification Game Center, l’envoi des scores
//  et la lecture optionnelle du meilleur score local (leaderboard App Store Connect).
//

import Foundation
import GameKit
import UIKit

/// Gestion Game Center pour le classement principal **BlomixMainScore**.
///
/// - Appelez **`authenticateOnLaunch(from:)`** une seule fois au démarrage (ex. `SceneDelegate` / `AppDelegate`).
/// - **`submitScore`** met toujours à jour le **backup UserDefaults** si le score bat le record local, puis tente Game Center.
/// - **`fetchLocalPlayerBestScore`** alimente la comparaison pour **`isNewPersonalBest`** (max local + GC si déjà chargé).
@MainActor
final class ScoreManager {
    // MARK: - Singleton

    static let shared = ScoreManager()

    /// Identifiant du leaderboard configuré dans App Store Connect (doit correspondre exactement).
    static let mainLeaderboardID = "BlomixMainScore"

    private init() {}

    // MARK: - État

    /// Indique si le joueur local est authentifié auprès de Game Center (mis à jour après le flux `authenticateHandler`).
    private(set) var isAuthenticated = false

    /// Évite de réinstaller `GKLocalPlayer.local.authenticateHandler` (une seule configuration au lancement).
    private var didStartAuthentication = false

    // MARK: - High-score local (backup UserDefaults)

    private enum LocalPersistence {
        static let highScoreKey      = "BlomixLocalHighScore"
        /// Meilleur score réalisé hors ligne (GC inaccessible) — soumis automatiquement à la reconnexion.
        static let pendingGCScoreKey = "BlomixPendingGCScore"
    }

    /// Meilleur score enregistré sur l’appareil (synchronisé avec `UserDefaults`, clé **BlomixLocalHighScore**).
    private var localHighScore: Int {
        get { UserDefaults.standard.integer(forKey: LocalPersistence.highScoreKey) }
        set { UserDefaults.standard.set(newValue, forKey: LocalPersistence.highScoreKey) }
    }

    /// Met à jour le high-score **disque** uniquement si `score` est strictement supérieur à la valeur actuelle.
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

    /// Retourne le meilleur score persisté localement (0 si aucune partie enregistrée).
    func getLocalHighScore() -> Int {
        localHighScore
    }

    // MARK: - Référence Game Center (pour comparaisons « record personnel »)

    /// `true` après au moins un **`fetchLocalPlayerBestScore`** réussi (même si le joueur n’a pas encore d’entrée → score 0 côté GC).
    private var hasFetchedGameCenterPersonalBest = false

    /// Dernier meilleur score **Game Center** connu (0 = fetch OK mais aucune entrée sur le classement).
    private var cachedGameCenterPersonalBest: Int = 0

    /// Mémorise le résultat d’un chargement Game Center pour alimenter **`isNewPersonalBest`**.
    private func recordGameCenterPersonalBestFromFetch(_ best: Int?) {
        hasFetchedGameCenterPersonalBest = true
        cachedGameCenterPersonalBest = best ?? 0
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

    // MARK: - Soumission de score

    /// Envoie un score entier au leaderboard **BlomixMainScore** (ou un autre ID si vous le surchargez).
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
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        // Backup disque **toujours** tenté en premier (hors ligne, échec réseau Game Center, ou joueur non connecté).
        _ = updateLocalHighScoreIfBetter(score)

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
            DispatchQueue.main.async {
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
        completion: @escaping (Result<Int?, Error>) -> Void
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
                        self.recordGameCenterPersonalBestFromFetch(value)
                        print("[ScoreManager] Meilleur score local sur « \(leaderboardID) » : \(value).")
                        completion(.success(value))
                    } else {
                        self.recordGameCenterPersonalBestFromFetch(nil)
                        print("[ScoreManager] Aucune entrée locale encore enregistrée sur « \(leaderboardID) ».")
                        completion(.success(nil))
                    }
                }
            }
        }
    }
}

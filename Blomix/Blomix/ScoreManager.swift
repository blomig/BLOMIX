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

/// Gestion Game Center pour les classements Solo / Zen / moyenne.
///
/// - Appelez **`authenticateOnLaunch(from:)`** une seule fois au démarrage (ex. `SceneDelegate` / `AppDelegate`).
/// - **`submitScore`** met toujours à jour le **backup UserDefaults** (Solo ou Zen), puis tente Game Center ;
///   hors ligne ou échec réseau → file d’attente **par leaderboard** (meilleur score Solo et Zen séparés).
/// - **`recordGameScore`** met à jour la moyenne locale ; hors ligne la moyenne est resynchronisée à l’auth GC.
/// - Au succès d’auth / retour foreground : flush `max(local, pending)` Solo + Zen, puis moyenne ;
///   réconciliation **local → GC** si le hiscore appareil dépasse le best GC (sans jamais baisser le local).
/// - **`fetchLocalPlayerBestScore`** alimente la comparaison pour **`isNewPersonalBest`** (max local + GC si déjà chargé)
///   et déclenche un upload local si `local > GC` (throttle).
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
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncScoresWithGameCenterIfPossible(reason: "did_become_active")
            }
        }
    }

    /// Réinitialise le meilleur score local si la version du scoring a changé (nouveau leaderboard, nouveau système de points).
    private func migrateScoreVersionIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: LocalPersistence.scoreVersionKey)
        guard stored < LocalPersistence.currentScoreVersion else { return }
        UserDefaults.standard.set(0, forKey: LocalPersistence.highScoreKey)
        UserDefaults.standard.set(0, forKey: LocalPersistence.pendingGCScoreKey)
        UserDefaults.standard.set(0, forKey: LocalPersistence.pendingZenGCScoreKey)
        UserDefaults.standard.set(LocalPersistence.currentScoreVersion, forKey: LocalPersistence.scoreVersionKey)
        print("[ScoreManager] Migration v\(LocalPersistence.currentScoreVersion) : meilleur score local remis à zéro.")
    }

    // MARK: - État

    /// Indique si le joueur local est authentifié auprès de Game Center (mis à jour après le flux `authenticateHandler`).
    private(set) var isAuthenticated = false

    /// Évite de réinstaller `GKLocalPlayer.local.authenticateHandler` (une seule configuration au lancement).
    private var didStartAuthentication = false

    /// Throttle des réconciliations fetch+upload (auth / foreground / fetch HUD).
    private var lastFullSyncAt: Date?
    private var lastForcedUploadAtByLeaderboard: [String: Date] = [:]
    private let fullSyncMinInterval: TimeInterval = 12
    private let forcedUploadMinInterval: TimeInterval = 45
    private var isSyncingBestScores = false

    // MARK: - High-score local (backup UserDefaults)

    private enum LocalPersistence {
        static let highScoreKey      = "BlomixLocalHighScore"
        /// Meilleur score Zen enregistré localement (indépendant du record Solo).
        static let zenHighScoreKey   = "BlomixLocalZenHighScore"
        /// Meilleur score Solo hors ligne / échec GC — resoumis sur `mainLeaderboardID` à l’auth.
        static let pendingGCScoreKey = "BlomixPendingGCScore"
        /// Meilleur score Zen hors ligne / échec GC — resoumis sur `zenLeaderboardID` à l’auth.
        static let pendingZenGCScoreKey = "BlomixPendingZenGCScore"
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
    /// En cas de nouveau record, aligne aussi le pending GC (évite local haut / pending 0 après migration ou clear anticipé).
    @discardableResult
    func updateLocalHighScoreIfBetter(_ score: Int) -> Bool {
        guard score > localHighScore else {
            print("[ScoreManager] Backup local : score \(score) ne dépasse pas le record \(localHighScore) — aucune écriture.")
            return false
        }
        localHighScore = score
        savePendingGCScore(score, leaderboardID: ScoreManager.mainLeaderboardID)
        print("[ScoreManager] Backup local (UserDefaults) mis à jour : nouveau record = \(score).")
        return true
    }

    /// Met à jour le high-score Zen **disque** uniquement si `score` est strictement supérieur à la valeur actuelle.
    /// En cas de nouveau record, aligne aussi le pending GC Zen.
    @discardableResult
    func updateLocalZenHighScoreIfBetter(_ score: Int) -> Bool {
        guard score > localZenHighScore else { return false }
        localZenHighScore = score
        savePendingGCScore(score, leaderboardID: ScoreManager.zenLeaderboardID)
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
                    self.syncScoresWithGameCenterIfPossible(reason: "auth_success")
                    // Identité + Elo PvP (Local hors ligne).
                    BlomixEloManager.shared.persistLocalGameIdentityFromGameCenter()
                    BlomixEloManager.shared.flushPendingEloIfNeeded()
                    // Rafraîchit aussi le cache Elo local depuis GC quand possible.
                    Task { @MainActor in
                        _ = try? await BlomixEloManager.shared.fetchLocalPlayerProfile()
                    }
                }
            }
        }
    }

    // MARK: - Scores en attente (hors ligne → synchro GC à la reconnexion)

    /// Clé UserDefaults du pending pour un leaderboard best-score (Solo ou Zen).
    private func pendingKey(forLeaderboardID leaderboardID: String) -> String? {
        if leaderboardID == ScoreManager.zenLeaderboardID {
            return LocalPersistence.pendingZenGCScoreKey
        }
        if leaderboardID == ScoreManager.mainLeaderboardID {
            return LocalPersistence.pendingGCScoreKey
        }
        // Autres leaderboards (moyenne, Elo…) : pas de file « best score » ici.
        return nil
    }

    private func localHighScore(forLeaderboardID leaderboardID: String) -> Int {
        if leaderboardID == ScoreManager.zenLeaderboardID { return getLocalZenHighScore() }
        if leaderboardID == ScoreManager.mainLeaderboardID { return getLocalHighScore() }
        return 0
    }

    private func pendingScore(forLeaderboardID leaderboardID: String) -> Int {
        guard let key = pendingKey(forLeaderboardID: leaderboardID) else { return 0 }
        return max(0, UserDefaults.standard.integer(forKey: key))
    }

    /// Score à pousser vers GC : max(hiscore local, pending). Source de vérité appareil = local.
    private func bestScoreToUpload(forLeaderboardID leaderboardID: String) -> Int {
        max(localHighScore(forLeaderboardID: leaderboardID), pendingScore(forLeaderboardID: leaderboardID))
    }

    /// Mémorise `score` pour le leaderboard donné. Ne conserve que le **meilleur** score par file (Solo / Zen séparés).
    private func savePendingGCScore(_ score: Int, leaderboardID: String) {
        guard score > 0, let key = pendingKey(forLeaderboardID: leaderboardID) else { return }
        let current = UserDefaults.standard.integer(forKey: key)
        guard score > current else { return }
        UserDefaults.standard.set(score, forKey: key)
        print("[ScoreManager] Score \(score) mis en attente pour « \(leaderboardID) » (hors ligne / échec GC).")
    }

    private func clearPendingGCScore(leaderboardID: String) {
        guard let key = pendingKey(forLeaderboardID: leaderboardID) else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Après un submit **réussi** sur un leaderboard Best Score : GC a au moins `score`.
    /// On efface le pending s’il est ≤ score (dette couverte). On ne recrée **pas** une dette
    /// juste parce que le local est plus haut — la réconciliation fetch s’en charge si GC < local.
    private func clearPendingAfterSuccessfulSubmit(score: Int, leaderboardID: String) {
        let pending = pendingScore(forLeaderboardID: leaderboardID)
        guard pending > 0 else { return }
        if pending <= score {
            clearPendingGCScore(leaderboardID: leaderboardID)
            print("[ScoreManager] Pending « \(leaderboardID) » effacé après submit OK (\(score) ≥ pending \(pending)).")
        }
    }

    /// Point d’entrée public : auth, foreground, ou appel manuel.
    /// Flush `max(local, pending)` Solo/Zen + moyenne, puis réconciliation fetch si besoin.
    func syncScoresWithGameCenterIfPossible(reason: String) {
        // Aligne l’état app sur GameKit (ex. réseau revenu sans rejouer le handler).
        let gkOK = GKLocalPlayer.local.isAuthenticated
        if gkOK != isAuthenticated {
            isAuthenticated = gkOK
            NotificationCenter.default.post(name: .blomixGameCenterAuthDidChange, object: nil)
        }
        guard isAuthenticated else { return }

        if let last = lastFullSyncAt, Date().timeIntervalSince(last) < fullSyncMinInterval {
            // Toujours tenter un flush « best local » léger (pas de fetch) même sous throttle court.
            flushBestLocalScoresToGCIfNeeded(reason: "\(reason)_throttled_flush")
            return
        }
        lastFullSyncAt = Date()
        flushBestLocalScoresToGCIfNeeded(reason: reason)
        flushLocalAverageToGCIfNeeded()
        reconcileLocalHighScoresWithGameCenter(reason: reason)
    }

    /// Pousse Solo / Zen : `max(hiscore local, pending)` — **sans** clear pending avant succès réseau.
    private func flushBestLocalScoresToGCIfNeeded(reason: String) {
        guard isAuthenticated else { return }
        for leaderboardID in [ScoreManager.mainLeaderboardID, ScoreManager.zenLeaderboardID] {
            let toUpload = bestScoreToUpload(forLeaderboardID: leaderboardID)
            guard toUpload > 0 else { continue }
            // Si GC cache déjà ≥ local et pas de pending, inutile de re-soumettre en boucle.
            let pending = pendingScore(forLeaderboardID: leaderboardID)
            let local = localHighScore(forLeaderboardID: leaderboardID)
            if pending == 0,
               leaderboardID == ScoreManager.zenLeaderboardID,
               hasFetchedGameCenterZenPersonalBest,
               cachedGameCenterZenPersonalBest >= local {
                continue
            }
            if pending == 0,
               leaderboardID == ScoreManager.mainLeaderboardID,
               hasFetchedGameCenterPersonalBest,
               cachedGameCenterPersonalBest >= local {
                continue
            }
            print("[ScoreManager] Sync GC (\(reason)) — upload \(toUpload) → « \(leaderboardID) » (local=\(local), pending=\(pending)).")
            submitScore(toUpload, leaderboardID: leaderboardID, completion: nil)
        }
    }

    /// Si hiscore local > best GC connu / fetché, re-soumet le local (leaderboards Best Score : GC garde le max).
    private func reconcileLocalHighScoresWithGameCenter(reason: String) {
        guard isAuthenticated, !isSyncingBestScores else { return }
        isSyncingBestScores = true
        let group = DispatchGroup()
        for leaderboardID in [ScoreManager.mainLeaderboardID, ScoreManager.zenLeaderboardID] {
            let local = localHighScore(forLeaderboardID: leaderboardID)
            guard local > 0 else { continue }
            group.enter()
            fetchLocalPlayerBestScore(leaderboardID: leaderboardID) { [weak self] result in
                defer { group.leave() }
                guard let self else { return }
                let remote: Int
                switch result {
                case .success(let best): remote = best ?? 0
                case .failure: return
                }
                if local > remote {
                    self.uploadLocalBestIfAhead(
                        leaderboardID: leaderboardID,
                        local: local,
                        remoteBest: remote,
                        reason: reason
                    )
                } else if remote >= self.pendingScore(forLeaderboardID: leaderboardID),
                          remote >= local {
                    // GC déjà ≥ local : plus de dette d’upload.
                    self.clearPendingGCScore(leaderboardID: leaderboardID)
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isSyncingBestScores = false
        }
    }

    private func uploadLocalBestIfAhead(
        leaderboardID: String,
        local: Int,
        remoteBest: Int,
        reason: String
    ) {
        guard local > remoteBest, local > 0 else { return }
        if let last = lastForcedUploadAtByLeaderboard[leaderboardID],
           Date().timeIntervalSince(last) < forcedUploadMinInterval {
            // Sous throttle : s’assurer au moins que le pending porte le local.
            savePendingGCScore(local, leaderboardID: leaderboardID)
            return
        }
        lastForcedUploadAtByLeaderboard[leaderboardID] = Date()
        savePendingGCScore(local, leaderboardID: leaderboardID)
        print("[ScoreManager] Réconciliation (\(reason)) local \(local) > GC \(remoteBest) sur « \(leaderboardID) » — upload.")
        submitScore(local, leaderboardID: leaderboardID, completion: nil)
    }

    /// Resynchronise le leaderboard moyenne depuis les stats locales (toujours exactes hors ligne).
    private func flushLocalAverageToGCIfNeeded() {
        let count = localGameCount()
        guard count > 0 else { return }
        let average = localAverageScore()
        print("[ScoreManager] Reconnexion GC — resync moyenne locale \(average) (\(count) partie(s)).")
        submitAverageScoreToGC(average, gameCount: count)
    }

    // MARK: - Moyenne des scores (leaderboard BlomixAverageScore_v1)

    /// Enregistre le score d'une partie solo complète, recalcule la moyenne et la soumet à Game Center.
    ///
    /// Les clés UserDefaults utilisées (`BlomixAvgTotalScore` / `BlomixAvgGameCount`) ne sont jamais
    /// effacées par `migrateScoreVersionIfNeeded()` — elles survivent à toutes les mises à jour de l'app.
    /// Hors ligne : la moyenne locale est à jour ; le push GC a lieu au prochain succès d’auth (`flushLocalAverageToGCIfNeeded`).
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
        guard gameCount > 0, average >= 0 else { return }
        guard isAuthenticated else {
            // Pas de file séparée : la source de vérité est locale ; flush à l’auth.
            print("[ScoreManager] submitAverageScoreToGC(\(average), games=\(gameCount)) : GC non dispo — moyenne locale conservée, resync à l’auth.")
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
                    // Prochaine auth resoumettra la moyenne locale courante.
                    print("[ScoreManager] Erreur soumission moyenne : \(error.localizedDescription) — retry au prochain auth.")
                } else {
                    print("[ScoreManager] Moyenne \(average) soumise avec succès sur « \(ScoreManager.averageLeaderboardID) » (context=\(gameCount)).")
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
        // Nouveau record local → pending aligné (via updateLocal*).
        let isZen = (leaderboardID == ScoreManager.zenLeaderboardID)
        let isBestScoreBoard = isZen || leaderboardID == ScoreManager.mainLeaderboardID
        if isZen {
            _ = updateLocalZenHighScoreIfBetter(score)
        } else if leaderboardID == ScoreManager.mainLeaderboardID {
            _ = updateLocalHighScoreIfBetter(score)
        }

        guard isAuthenticated else {
            // Hors ligne : dette = max(score de la partie, hiscore local) pour ne jamais perdre un PB local.
            if isBestScoreBoard {
                let localBackup = localHighScore(forLeaderboardID: leaderboardID)
                savePendingGCScore(max(score, localBackup), leaderboardID: leaderboardID)
            }
            let localBackup = isZen ? getLocalZenHighScore() : getLocalHighScore()
            let error = NSError(
                domain: "ScoreManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Joueur non authentifié : impossible d’envoyer le score."]
            )
            print("[ScoreManager] submitScore(\(score), \(leaderboardID)) : GC non dispo. Backup local = \(localBackup).")
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
                    // Échec réseau : pending = max(score tenté, hiscore local) pour le prochain sync.
                    if isBestScoreBoard {
                        let localBackup = self.localHighScore(forLeaderboardID: leaderboardID)
                        self.savePendingGCScore(max(score, localBackup), leaderboardID: leaderboardID)
                    }
                    let localBackup = isZen ? self.getLocalZenHighScore() : self.getLocalHighScore()
                    print("[ScoreManager] Erreur submitScore \(leaderboardID): \(error.localizedDescription) — backup local = \(localBackup).")
                    completion?(.failure(error))
                } else {
                    print("[ScoreManager] Score \(score) soumis avec succès sur « \(leaderboardID) ».")
                    if isBestScoreBoard {
                        self.clearPendingAfterSuccessfulSubmit(score: score, leaderboardID: leaderboardID)
                        // Cache GC : au moins ce score (Best Score GC ne descend pas).
                        let prev: Int = {
                            if isZen {
                                return self.hasFetchedGameCenterZenPersonalBest
                                    ? self.cachedGameCenterZenPersonalBest : 0
                            }
                            return self.hasFetchedGameCenterPersonalBest
                                ? self.cachedGameCenterPersonalBest : 0
                        }()
                        self.recordGameCenterPersonalBestFromFetch(max(prev, score), leaderboardID: leaderboardID)
                    }
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
                        let local = self.localHighScore(forLeaderboardID: leaderboardID)
                        if local > value {
                            self.uploadLocalBestIfAhead(
                                leaderboardID: leaderboardID,
                                local: local,
                                remoteBest: value,
                                reason: "fetch_best"
                            )
                        }
                    } else {
                        self.recordGameCenterPersonalBestFromFetch(nil, leaderboardID: leaderboardID)
                        print("[ScoreManager] Aucune entrée locale encore enregistrée sur « \(leaderboardID) ».")
                        completion(.success(nil))
                        let local = self.localHighScore(forLeaderboardID: leaderboardID)
                        if local > 0 {
                            self.uploadLocalBestIfAhead(
                                leaderboardID: leaderboardID,
                                local: local,
                                remoteBest: 0,
                                reason: "fetch_best_empty"
                            )
                        }
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

    /// Rang global **si** `score` était déjà le best du joueur (overlay record).
    ///
    /// Ne pas lire `localEntry.rank` juste après un submit : Game Center renvoie souvent
    /// l’ancien rang (2ᵉ) alors que le nouveau score prend la 1ʳᵉ place.
    /// Ici : 1 + nombre d’**autres** joueurs (top 100) dont le score est strictement supérieur.
    func fetchGlobalRankInsertingScore(
        _ score: Int,
        leaderboardID: String,
        completion: @escaping @Sendable @MainActor (Int?) -> Void
    ) {
        guard score > 0, GKLocalPlayer.local.isAuthenticated else {
            Task { @MainActor in completion(nil) }
            return
        }

        struct LeaderboardBox: @unchecked Sendable { let board: GKLeaderboard }
        struct EntrySnap: Sendable {
            let score: Int
            let rank: Int
            let gamePlayerID: String
            let teamPlayerID: String
        }

        let localGID = GKLocalPlayer.local.gamePlayerID
        let localTID = GKLocalPlayer.local.teamPlayerID

        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { leaderboards, error in
            guard let leaderboard = leaderboards?.first, error == nil else {
                Task { @MainActor in completion(nil) }
                return
            }
            let boardBox = LeaderboardBox(board: leaderboard)
            boardBox.board.loadEntries(
                for: .global,
                timeScope: .allTime,
                range: NSRange(location: 1, length: 100)
            ) { localEntry, rankedEntries, _, err in
                if let err {
                    print("[ScoreManager] fetchGlobalRankInsertingScore loadEntries: \(err.localizedDescription)")
                    Task { @MainActor in completion(nil) }
                    return
                }
                func snap(_ entry: GKLeaderboard.Entry) -> EntrySnap {
                    EntrySnap(
                        score: Int(entry.score),
                        rank: entry.rank,
                        gamePlayerID: entry.player.gamePlayerID,
                        teamPlayerID: entry.player.teamPlayerID
                    )
                }
                func isLocal(_ s: EntrySnap) -> Bool {
                    if !localGID.isEmpty, s.gamePlayerID == localGID { return true }
                    if !localTID.isEmpty, s.teamPlayerID == localTID { return true }
                    return false
                }
                let page = (rankedEntries ?? []).map(snap)
                let localSnap = localEntry.map(snap)
                let others = page.filter { !isLocal($0) }
                let above = others.filter { $0.score > score }.count
                let insertionInPage = others.isEmpty
                    || others.contains(where: { $0.score <= score })
                    || page.count < 100
                let computed = above + 1
                let gcAlreadyUpdated = (localSnap?.score ?? 0) >= score
                let rank: Int?
                if insertionInPage {
                    rank = computed
                } else if gcAlreadyUpdated, let gcRank = localSnap?.rank, gcRank > 0 {
                    rank = gcRank
                } else {
                    rank = nil
                }
                print("[ScoreManager] rank inserting \(score) on \(leaderboardID): \(rank.map(String.init) ?? "nil") (above=\(above) page=\(others.count) gcScore=\(localSnap?.score ?? -1))")
                Task { @MainActor in completion(rank) }
            }
        }
    }
}

//
//  GameCenterManager.swift
//  Blomix
//
//  Authentification Game Center, envoi des scores (leaderboard App Store Connect « BlomixMainScore »)
//  et présentation du tableau des scores. Voir PROJECT_CONTEXT.md (Phase 3).
//

import GameKit
import UIKit

extension Notification.Name {
    /// Publié quand `GameCenterManager.isAuthenticated` change (succès ou échec d’auth).
    static let blomixGameCenterAuthDidChange = Notification.Name("blomixGameCenterAuthDidChange")
}

/// Délégué dédié pour fermer le tableau Game Center.
/// **Sans** `@MainActor` sur la classe : `GKGameCenterControllerDelegate` (GameKit / ObjC) n’est pas isolé comme le reste du module ;
/// l’UI est repassée sur le main thread pour le `dismiss`.
private final class GameCenterDashboardDelegate: NSObject, GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        DispatchQueue.main.async {
            gameCenterViewController.dismiss(animated: true)
        }
    }
}

/// Point d’entrée GameKit : singleton, à utiliser depuis `GameViewController` (auth) et `GameScene` (score).
/// Tout le flux Game Center est **main actor** (UIKit + callbacks GameKit), ce qui rend le singleton `Sendable` pour Swift 6.
@MainActor
final class GameCenterManager {
    static let shared = GameCenterManager()

    private let dashboardDelegate = GameCenterDashboardDelegate()

    private init() {}

    /// Mis à jour après `authenticatePlayer` / état du joueur local.
    private(set) var isAuthenticated = false

    /// Lance le flux d’authentification Game Center (feuille système si nécessaire).
    func authenticatePlayer(from viewController: UIViewController) {
        // GameKit peut rappeler ce handler hors du main thread : on repasse sur le main actor pour l’UI et `isAuthenticated`.
        GKLocalPlayer.local.authenticateHandler = { [weak self, weak viewController] gcAuthVC, error in
            Task { @MainActor in
                guard let self, let viewController else { return }
                if let gcAuthVC {
                    viewController.present(gcAuthVC, animated: true)
                    return
                }
                if let error {
                    print("Game Center auth error: \(error.localizedDescription)")
                    self.isAuthenticated = false
                    NotificationCenter.default.post(name: .blomixGameCenterAuthDidChange, object: nil)
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                print("Game Center authentifié : \(self.isAuthenticated)")
                NotificationCenter.default.post(name: .blomixGameCenterAuthDidChange, object: nil)
            }
        }
    }

    /// Envoie le score au classement `BlomixMainScore` (API `GKLeaderboard.submitScore`, iOS 14+).
    func reportScore(_ score: Int, leaderboardID: String = "BlomixMainScore") {
        guard isAuthenticated else { return }

        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { error in
            if let error {
                print("Erreur envoi score Game Center: \(error.localizedDescription)")
            } else {
                print("Score \(score) envoyé avec succès à Game Center")
            }
        }
    }

    /// Affiche le classement Game Center pour `BlomixMainScore`.
    func showLeaderboard(from viewController: UIViewController) {
        // L’auth est pilotée par `ScoreManager` ; l’état Game Center reste `GKLocalPlayer.local`.
        guard GKLocalPlayer.local.isAuthenticated else {
            print("Joueur non authentifié")
            return
        }

        let gcVC = GKGameCenterViewController(
            leaderboardID: "BlomixMainScore",
            playerScope: .global,
            timeScope: .allTime
        )
        gcVC.gameCenterDelegate = dashboardDelegate
        viewController.present(gcVC, animated: true)
    }
}

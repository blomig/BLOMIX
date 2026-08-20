//
//  BlomixReviewPrompt.swift
//  Blomix
//
//  Demande d’avis App Store : prompt système (GO, rare) + lien manuel Crédits.
//  Guideline 5.6.1 — pas de boîte custom « note-nous ».
//

import StoreKit
import UIKit

@MainActor
enum BlomixReviewPrompt {

    /// Parties Arcade/Zen terminées avant la première demande.
    static let minCompletedGames = 3
    /// Pause après l’overlay GO (laisser lire le récap).
    static let delayAfterGameOver: TimeInterval = 2.5

    private static let gamesKey = "blomix_review_completed_games"
    private static let lastVersionKey = "blomix_review_last_prompted_version"

    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(BlomixShareComposer.appStoreID)?action=write-review")!
    }

    static var completedGames: Int {
        max(0, UserDefaults.standard.integer(forKey: gamesKey))
    }

    static func recordCompletedGame() {
        UserDefaults.standard.set(completedGames + 1, forKey: gamesKey)
    }

    static func shouldRequestAfterGameOver() -> Bool {
        guard completedGames >= minCompletedGames else { return false }
        let current = currentMarketingVersion
        guard !current.isEmpty else { return false }
        let last = UserDefaults.standard.string(forKey: lastVersionKey) ?? ""
        return current != last
    }

    /// Prompt StoreKit si iOS l’accepte. Marque la version même si le dialogue est masqué (anti-spam).
    static func requestReview(in windowScene: UIWindowScene?) {
        guard shouldRequestAfterGameOver() else { return }
        guard let windowScene else { return }
        UserDefaults.standard.set(currentMarketingVersion, forKey: lastVersionKey)
        AppStore.requestReview(in: windowScene)
    }

    static func openWriteReview() {
        UIApplication.shared.open(writeReviewURL)
    }

    private static var currentMarketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

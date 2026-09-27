//
//  WatchL10n.swift
//  Exception AGENTS.md : pas BlomixL10n (zéro Swift partagé avec l’iPhone).
//

import Foundation

enum WatchL10n {
    static var playZen: String { tr("watch.play_zen") }
    static var continueGame: String { tr("watch.continue") }
    static var newGame: String { tr("watch.new_game") }
    static var bestScore: String { tr("watch.best_score") }
    static var homeA11y: String { tr("watch.home") }
    static var bombA11y: String { tr("watch.bomb") }
    static var scoreA11y: String { tr("watch.score") }
    static var abandonTitle: String { tr("watch.abandon") }
    static var abandonYes: String { tr("watch.abandon_yes") }
    static var abandonNo: String { tr("watch.abandon_no") }
    static var gameOver: String { tr("watch.game_over") }
    static var newRecord: String { tr("watch.new_record") }

    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }
}

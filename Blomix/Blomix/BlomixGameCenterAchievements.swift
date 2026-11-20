//
//  BlomixGameCenterAchievements.swift
//  Blomix
//
//  Traduit les compteurs du Salon en réalisations Game Center.
//  Les identifiants `blomix.ach.*` sont figés dans App Store Connect.
//  Aucun texte de réalisation ici : les noms vivent dans Game Center.
//

import Foundation

/// Pourcentage Game Center (0…100, deux décimales) à partir d’un compteur du Salon.
enum BlomixGCAchievementMath {
    enum Mode: Equatable, Sendable {
        case binary
        case progressive
    }

    /// `binary` : 0 ou 100. `progressive` : la part du seuil.
    /// Une réalisation cachée ne renvoie que 100, jamais une progression partielle.
    static func percent(value: Int, target: Int, mode: Mode, hidden: Bool) -> Double {
        guard target > 0, value > 0 else { return 0 }
        let raw = min(100, Double(value) / Double(target) * 100)
        let rounded = (raw * 100).rounded() / 100
        if hidden || mode == .binary {
            return rounded >= 100 ? 100 : 0
        }
        return rounded
    }

    /// Si plus de trois réalisations se complètent dans le même lot, une seule bannière :
    /// celle qui vaut le plus de points (à points égaux, la dernière de la table).
    static func soleBannerID(amongCompleted completed: [(gcID: String, points: Int)]) -> String? {
        guard completed.count > 3 else { return nil }
        return completed.enumerated().max { lhs, rhs in
            if lhs.element.points != rhs.element.points {
                return lhs.element.points < rhs.element.points
            }
            return lhs.offset < rhs.offset
        }?.element.gcID
    }
}

/// Table des 20 réalisations. L’envoi vers Game Center est branché à part.
@MainActor
final class BlomixGameCenterAchievements {
    static let shared = BlomixGameCenterAchievements()

    struct Entry {
        let gcID: String
        let target: Int
        let mode: BlomixGCAchievementMath.Mode
        let hidden: Bool
        /// Points ASC. Sert à choisir la bannière quand plusieurs se complètent ensemble.
        let points: Int
        let value: @MainActor () -> Int
    }

    /// Ordre et identifiants exacts de `docs/gamecenter/REALISATIONS_GAME_CENTER.md`.
    static let entries: [Entry] = [
        Entry(gcID: "blomix.ach.first_chain", target: 1, mode: .binary, hidden: false, points: 10) {
            BlomixTrophyStore.shared.progress(for: "chain_count").value
        },
        Entry(gcID: "blomix.ach.first_bomb", target: 1, mode: .binary, hidden: false, points: 10) {
            BlomixTrophyStore.shared.progress(for: "bomb").value
        },
        Entry(gcID: "blomix.ach.tutorial", target: 1, mode: .binary, hidden: false, points: 10) {
            BlomixTrophyStore.shared.progress(for: "play_tutorial").value
        },
        Entry(gcID: "blomix.ach.first_magix", target: 1, mode: .binary, hidden: false, points: 15) {
            BlomixTrophyStore.shared.progress(for: "magix_all_nine").value
        },
        Entry(gcID: "blomix.ach.pacifist", target: 1, mode: .binary, hidden: true, points: 15) {
            BlomixTrophyStore.shared.progress(for: "secret_five_bombs").value
        },
        Entry(gcID: "blomix.ach.super_combo", target: 1, mode: .binary, hidden: false, points: 25) {
            BlomixTrophyStore.shared.progress(for: "combo").value
        },
        Entry(gcID: "blomix.ach.stage_3", target: 3, mode: .progressive, hidden: false, points: 30) {
            BlomixTrophyStore.shared.progress(for: "arcade_stage").value
        },
        Entry(gcID: "blomix.ach.duel_win", target: 1, mode: .binary, hidden: false, points: 30) {
            BlomixTrophyStore.shared.progress(for: "duel_win").value
        },
        Entry(gcID: "blomix.ach.daily_streak_3", target: 3, mode: .progressive, hidden: false, points: 30) {
            BlomixTrophyStore.shared.progress(for: "daily_streak").value
        },
        Entry(gcID: "blomix.ach.five_tide_20", target: 20, mode: .progressive, hidden: false, points: 35) {
            BlomixTrophyStore.shared.progress(for: "five_lines").value
        },
        Entry(gcID: "blomix.ach.zen_2000", target: 2000, mode: .progressive, hidden: false, points: 30) {
            BlomixTrophyStore.shared.progress(for: "zen_score").value
        },
        Entry(gcID: "blomix.ach.stage_ultime", target: 6, mode: .progressive, hidden: false, points: 60) {
            BlomixTrophyStore.shared.progress(for: "arcade_stage").value
        },
        Entry(gcID: "blomix.ach.chain_10", target: 10, mode: .progressive, hidden: false, points: 60) {
            BlomixTrophyStore.shared.progress(for: "chain_size").value
        },
        Entry(gcID: "blomix.ach.magix_all_nine", target: 9, mode: .progressive, hidden: false, points: 70) {
            BlomixTrophyStore.shared.progress(for: "magix_all_nine").value
        },
        Entry(gcID: "blomix.ach.daily_streak_7", target: 7, mode: .progressive, hidden: false, points: 60) {
            BlomixTrophyStore.shared.progress(for: "daily_streak").value
        },
        Entry(gcID: "blomix.ach.trophies_30", target: 30, mode: .progressive, hidden: false, points: 60) {
            BlomixTrophyStore.shared.litVisibleCount
        },
        Entry(gcID: "blomix.ach.arcade_10k", target: 10000, mode: .progressive, hidden: false, points: 90) {
            BlomixTrophyStore.shared.progress(for: "arcade_score").value
        },
        Entry(gcID: "blomix.ach.combo_deep", target: 1, mode: .binary, hidden: false, points: 90) {
            BlomixTrophyStore.shared.progress(for: "combo_deep").value
        },
        Entry(gcID: "blomix.ach.daily_streak_30", target: 30, mode: .progressive, hidden: false, points: 100) {
            BlomixTrophyStore.shared.progress(for: "daily_streak").value
        },
        Entry(gcID: "blomix.ach.saintx_ultime", target: 1, mode: .binary, hidden: true, points: 100) {
            BlomixTrophyStore.shared.progress(for: "magix_saintx_ultime").value
        },
    ]

    private init() {}

    /// Pourcentage à envoyer pour une entrée, d’après le Salon actuel.
    func percent(for entry: Entry) -> Double {
        BlomixGCAchievementMath.percent(
            value: entry.value(),
            target: entry.target,
            mode: entry.mode,
            hidden: entry.hidden
        )
    }
}

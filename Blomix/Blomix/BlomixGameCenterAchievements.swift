//
//  BlomixGameCenterAchievements.swift
//  Blomix
//
//  Traduit les compteurs du Salon en réalisations Game Center.
//  Les identifiants `blomix.ach.*` sont figés dans App Store Connect.
//  Aucun texte de réalisation ici : les noms vivent dans Game Center.
//

import Foundation
@preconcurrency import GameKit

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

    /// Le serveur remplace le cache. Une réalisation absente vaut 0.
    /// L’ancien cache n’est pas lu : un 100 % sandbox ne doit pas masquer une production vide.
    /// Les identifiants hors table sont ignorés.
    static func storedAfterServer(
        knownIDs: [String],
        serverPercents: [String: Double]
    ) -> [String: Double] {
        var stored: [String: Double] = [:]
        stored.reserveCapacity(knownIDs.count)
        for id in knownIDs {
            let raw = serverPercents[id] ?? 0
            stored[id] = (raw * 100).rounded() / 100
        }
        return stored
    }

    /// Ce qui doit partir : le Salon est strictement au-dessus du cache fraîchement fusionné.
    static func increases(
        salon: [(gcID: String, percent: Double)],
        stored: [String: Double]
    ) -> [(gcID: String, percent: Double)] {
        salon.compactMap { item in
            guard item.percent > 0 else { return nil }
            let previous = stored[item.gcID] ?? -1
            guard item.percent > previous else { return nil }
            return item
        }
    }

    static func sendLog(count: Int, completed: Int) -> String {
        "[GCAch] envoi de \(count) réalisation(s), dont \(completed) complétée(s)"
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

    /// Debug parle au sandbox, Release à la production. L’ancienne clé sans
    /// préfixe (`blomix_gc_achievements_v1`) n’est plus lue : elle mélangeait les deux.
    enum CacheKey {
        static let legacy = "blomix_gc_achievements_v1"
        static let sandbox = "sandbox.blomix_gc_achievements_v1"
        static let release = "release.blomix_gc_achievements_v1"
        static var current: String {
            #if DEBUG
            sandbox
            #else
            release
            #endif
        }
    }

    private static var cacheKey: String { CacheKey.current }
    private static let debounceNanos: UInt64 = 1_500_000_000

    private struct CacheFile: Codable {
        var byPlayer: [String: [String: Double]] = [:]
    }

    private var observers: [NSObjectProtocol] = []
    private var needsSync = false
    private var didMergeServer = false
    private var debounceTask: Task<Void, Never>?
    private var debouncePending = false
    private var syncTask: Task<Void, Never>?
    private var runAgain = false

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

    /// Idempotent. S’abonne à l’auth et aux changements du Salon.
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .blomixGameCenterAuthDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAuthChange()
            }
        })
        observers.append(center.addObserver(
            forName: .blomixTrophiesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleSync()
            }
        })
    }

    /// Retour au premier plan, ou file d’attente après une coupure.
    func syncIfNeeded() {
        start()
        debounceTask?.cancel()
        debounceTask = nil
        debouncePending = false
        guard GKLocalPlayer.local.isAuthenticated else {
            needsSync = true
            print("[GCAch] joueur non authentifié, envoi reporté")
            return
        }
        if !didMergeServer {
            Task { await self.catchUpFromServerThenSync() }
            return
        }
        guard needsSync else {
            print("[GCAch] rien à envoyer")
            return
        }
        Task { await self.performSync(limitBanners: false) }
    }

    private func handleAuthChange() {
        guard GKLocalPlayer.local.isAuthenticated else {
            needsSync = true
            didMergeServer = false
            print("[GCAch] joueur non authentifié, envoi reporté")
            return
        }
        Task { await self.catchUpFromServerThenSync() }
    }

    private func scheduleSync() {
        needsSync = true
        guard GKLocalPlayer.local.isAuthenticated else { return }
        debounceTask?.cancel()
        debouncePending = true
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled else { return }
            self.debouncePending = false
            if !self.didMergeServer {
                await self.catchUpFromServerThenSync()
            } else {
                await self.performSync(limitBanners: false)
            }
        }
    }

    private func catchUpFromServerThenSync() async {
        guard GKLocalPlayer.local.isAuthenticated else {
            needsSync = true
            return
        }
        do {
            let remote = try await GKAchievement.loadAchievements()
            mergeServer(remote)
            didMergeServer = true
            print("[GCAch] état serveur fusionné (\(remote.count))")
        } catch {
            needsSync = true
            print("[GCAch] lecture serveur en échec : \(error.localizedDescription)")
            return
        }
        await performSync(limitBanners: true)
    }

    private func performSync(limitBanners: Bool) async {
        if let existing = syncTask {
            runAgain = true
            await existing.value
            return
        }
        let task = Task { @MainActor in
            await self.reportIncreased(limitBanners: limitBanners)
        }
        syncTask = task
        await task.value
        syncTask = nil
        if runAgain {
            runAgain = false
            await performSync(limitBanners: false)
        }
    }

    private func reportIncreased(limitBanners: Bool) async {
        guard let playerKey = currentPlayerKey() else {
            needsSync = true
            print("[GCAch] joueur non authentifié, envoi reporté")
            return
        }
        var cache = loadCache()
        var stored = cache.byPlayer[playerKey] ?? [:]
        let byID = Dictionary(uniqueKeysWithValues: Self.entries.map { ($0.gcID, $0) })
        let salon = Self.entries.map { (gcID: $0.gcID, percent: self.percent(for: $0)) }
        let pending: [(entry: Entry, percent: Double)] = BlomixGCAchievementMath.increases(
            salon: salon,
            stored: stored
        ).compactMap { item in
            guard let entry = byID[item.gcID] else { return nil }
            return (entry, item.percent)
        }
        guard !pending.isEmpty else {
            if !debouncePending { needsSync = false }
            print("[GCAch] rien à envoyer")
            return
        }

        let completed = pending
            .filter { $0.percent >= 100 }
            .map { (gcID: $0.entry.gcID, points: $0.entry.points) }
        let soleBanner = limitBanners
            ? BlomixGCAchievementMath.soleBannerID(amongCompleted: completed)
            : nil
        let achievements: [GKAchievement] = pending.map { item in
            let achievement = GKAchievement(identifier: item.entry.gcID)
            achievement.percentComplete = item.percent
            if item.percent >= 100, let soleBanner {
                achievement.showsCompletionBanner = item.entry.gcID == soleBanner
            } else {
                achievement.showsCompletionBanner = true
            }
            return achievement
        }

        do {
            try await GKAchievement.report(achievements)
            for item in pending {
                stored[item.entry.gcID] = item.percent
            }
            cache.byPlayer[playerKey] = stored
            saveCache(cache)
            if !debouncePending { needsSync = false }
            let done = completed.count
            print(BlomixGCAchievementMath.sendLog(count: pending.count, completed: done))
        } catch {
            needsSync = true
            print("[GCAch] envoi en échec : \(error.localizedDescription)")
        }
    }

    /// Game Center remplace le cache de ce joueur. Le cache ne sert ensuite
    /// qu’à ne pas renvoyer deux fois la même hausse dans la session.
    private func mergeServer(_ remote: [GKAchievement]) {
        guard let playerKey = currentPlayerKey() else { return }
        let known = Set(Self.entries.map(\.gcID))
        var server: [String: Double] = [:]
        for achievement in remote where known.contains(achievement.identifier) {
            server[achievement.identifier] = achievement.percentComplete
        }
        var cache = loadCache()
        cache.byPlayer[playerKey] = BlomixGCAchievementMath.storedAfterServer(
            knownIDs: Self.entries.map(\.gcID),
            serverPercents: server
        )
        saveCache(cache)
    }

    /// `teamPlayerID` sépare les comptes. `gamePlayerID` seulement s’il est vide.
    private func currentPlayerKey() -> String? {
        let local = GKLocalPlayer.local
        guard local.isAuthenticated else { return nil }
        if !local.teamPlayerID.isEmpty { return local.teamPlayerID }
        if !local.gamePlayerID.isEmpty { return local.gamePlayerID }
        return nil
    }

    private func loadCache() -> CacheFile {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data) else {
            return CacheFile()
        }
        return file
    }

    private func saveCache(_ file: CacheFile) {
        guard let data = try? JSONEncoder().encode(file) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

#if DEBUG
    /// Sans bouton. À appeler depuis le débogueur seulement.
    func resetReportedAchievementsForDebug() async {
        do {
            try await GKAchievement.resetAchievements()
            if let playerKey = currentPlayerKey() {
                var cache = loadCache()
                cache.byPlayer[playerKey] = [:]
                saveCache(cache)
            }
            didMergeServer = false
            needsSync = true
            print("[GCAch] réalisations réinitialisées (debug)")
        } catch {
            print("[GCAch] reset debug en échec : \(error.localizedDescription)")
        }
    }
#endif
}

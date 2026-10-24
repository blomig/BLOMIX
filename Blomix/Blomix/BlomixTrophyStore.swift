//
//  BlomixTrophyStore.swift
//  Blomix
//
//  Catalogue + store local JSON (`blomix_trophies_v1`). Pas Game Center, pas CloudKit.
//

import Foundation
import UIKit

extension Notification.Name {
    static let blomixTrophiesDidChange = Notification.Name("blomixTrophiesDidChange")
}

// MARK: - Murs / courbes / rangs

enum BlomixTrophyWall: String, CaseIterable, Sendable {
    case seuil, chaines, magix, arcade, five, defi, duel, zen, folie
}

enum BlomixTrophyCurve: Equatable, Sendable {
    /// s1 = 1 ; s2 / s3 fournis (défaut 10 / 100).
    case volume(s2: Int, s3: Int)
    /// 1 / 3 / 10
    case rare
    case quality(s1: Int, s2: Int, s3: Int)
    /// Allumé ou pas. Pas de tours.
    case unique

    static let volumeDefault = BlomixTrophyCurve.volume(s2: 10, s3: 100)

    var s1: Int {
        switch self {
        case .volume, .rare, .unique: return 1
        case .quality(let s1, _, _): return s1
        }
    }

    var s2: Int {
        switch self {
        case .volume(let s2, _): return s2
        case .rare: return 3
        case .quality(_, let s2, _): return s2
        case .unique: return 1
        }
    }

    var s3: Int {
        switch self {
        case .volume(_, let s3): return s3
        case .rare: return 10
        case .quality(_, _, let s3): return s3
        case .unique: return 1
        }
    }

    var hasTours: Bool {
        if case .unique = self { return false }
        return true
    }
}

enum BlomixTrophyRank: Int, Codable, Comparable, Sendable {
    case none = 0
    case i = 1
    case ii = 2
    case iii = 3

    static func < (lhs: BlomixTrophyRank, rhs: BlomixTrophyRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var roman: String {
        switch self {
        case .none: return ""
        case .i: return "I"
        case .ii: return "II"
        case .iii: return "III"
        }
    }
}

struct BlomixTrophyDef: Sendable {
    let id: String
    let wall: BlomixTrophyWall
    let curve: BlomixTrophyCurve
    let isSecret: Bool
    /// Titre Magix non traduit (CHROMAX, …). Sinon clé l10n.
    let magixTitle: String?
}

struct BlomixTrophyProgress: Codable, Equatable, Sendable {
    var value: Int = 0
    var firstAt: Date?
    var iiAt: Date?
    var iiiAt: Date?
    var seen: Bool = false
}

struct BlomixTrophyPromotion: Codable, Equatable, Sendable {
    let id: String
    let rank: BlomixTrophyRank
}

struct BlomixTrophyTourFill: Equatable, Sendable {
    /// 0…1 sur l’anneau s2. 0 tant que n < s1.
    var first: CGFloat
    /// 0…1 sur l’anneau s3. 0 tant que n < s2.
    var second: CGFloat
    var innerLit: Bool
    var bothFull: Bool
}

enum BlomixTrophyMath {
    /// Étoiles sous la cible (0…3). 1 à s3, 2 à 2×s3, 3 à 3×s3. Unique : 0.
    static func starCount(value: Int, curve: BlomixTrophyCurve) -> Int {
        guard curve.hasTours else { return 0 }
        let s3 = max(curve.s3, 1)
        guard value >= s3 else { return 0 }
        return min(3, value / s3)
    }

    static func rank(value: Int, curve: BlomixTrophyCurve) -> BlomixTrophyRank {
        switch curve {
        case .unique:
            return value >= 1 ? .i : .none
        case .volume, .rare, .quality:
            if value >= curve.s3 { return .iii }
            if value >= curve.s2 { return .ii }
            if value >= curve.s1 { return .i }
            return .none
        }
    }

    static func tours(value: Int, curve: BlomixTrophyCurve) -> BlomixTrophyTourFill {
        if case .unique = curve {
            let on = value >= 1
            return BlomixTrophyTourFill(first: 0, second: 0, innerLit: on, bothFull: false)
        }
        let s1 = curve.s1
        let s2 = max(curve.s2, 1)
        let s3 = max(curve.s3, 1)
        let inner = value >= s1
        if value <= 0 || value < s1 {
            return BlomixTrophyTourFill(first: 0, second: 0, innerLit: false, bothFull: false)
        }
        if value < s2 {
            return BlomixTrophyTourFill(
                first: min(1, CGFloat(value) / CGFloat(s2)),
                second: 0,
                innerLit: inner,
                bothFull: false
            )
        }
        let second = min(1, CGFloat(value) / CGFloat(s3))
        return BlomixTrophyTourFill(
            first: 1,
            second: second,
            innerLit: true,
            bothFull: value >= s3
        )
    }
}

// MARK: - Catalogue

enum BlomixTrophyCatalog {
    static let all: [BlomixTrophyDef] = {
        var rows: [BlomixTrophyDef] = []
        func add(
            _ id: String,
            _ wall: BlomixTrophyWall,
            _ curve: BlomixTrophyCurve,
            secret: Bool = false,
            magix: String? = nil
        ) {
            rows.append(BlomixTrophyDef(id: id, wall: wall, curve: curve, isSecret: secret, magixTitle: magix))
        }

        add("play_arcade", .seuil, .volumeDefault)
        add("play_zen", .seuil, .volumeDefault)
        add("play_five", .seuil, .volumeDefault)
        add("play_daily_arc", .seuil, .volumeDefault)
        add("play_daily_five", .seuil, .volumeDefault)
        add("play_duel", .seuil, .volumeDefault)
        add("play_tutorial", .seuil, .unique)
        add("play_both_dailies", .seuil, .volumeDefault)
        add("board_recover", .seuil, .volumeDefault)
        add("pure_streak", .seuil, .quality(s1: 10, s2: 50, s3: 100))

        add("chain_size", .chaines, .quality(s1: 5, s2: 8, s3: 10))
        add("chain_count", .chaines, .volume(s2: 100, s3: 1000))
        add("combo", .chaines, .volumeDefault)
        add("combo_deep", .chaines, .rare)
        add("connect", .chaines, .volumeDefault)
        add("board_empty", .chaines, .rare)
        add("brix_line", .chaines, .volume(s2: 5, s3: 10))
        add("bomb_brix", .chaines, .quality(s1: 3, s2: 9, s3: 13))

        add("magix_chromax", .magix, .volumeDefault, magix: "CHROMAX")
        add("magix_brixed", .magix, .rare, magix: "BRIXED")
        add("magix_brixed_strike", .magix, .rare)
        add("magix_crossx", .magix, .volumeDefault, magix: "CROSSX")
        add("magix_slashx", .magix, .volumeDefault, magix: "SLASHX")
        add("magix_scrumblx", .magix, .volumeDefault, magix: "SCRUMBLX")
        add("magix_colorx", .magix, .volumeDefault, magix: "COLORX")
        add("magix_saintx", .magix, .rare, magix: "SAINTX")
        add("magix_twistx", .magix, .volumeDefault, magix: "TWISTX")
        add("magix_bombx", .magix, .rare, magix: "BOMBX")
        add("magix_all_nine", .magix, .quality(s1: 1, s2: 5, s3: 9))
        add("magix_saintx_ultime", .magix, .rare)
        add("magix_last_minute", .magix, .volumeDefault)
        add("magix_last_cell", .magix, .volume(s2: 5, s3: 50))

        add("arcade_stage", .arcade, .quality(s1: 2, s2: 4, s3: 6))
        add("arcade_nuke", .arcade, .volumeDefault)
        add("arcade_score", .arcade, .quality(s1: 1_000, s2: 5_000, s3: 20_000))
        add("arcade_pb", .arcade, .rare)
        add("arcade_ultime_count", .arcade, .volumeDefault)

        add("five_lines", .five, .quality(s1: 5, s2: 20, s3: 50))
        add("five_score", .five, .quality(s1: 500, s2: 2_000, s3: 5_000))
        add("five_pb", .five, .rare)
        add("five_no_bomb", .five, .rare)
        add("five_empty", .five, .rare)

        add("daily_ghost_beat", .defi, .rare)
        add("daily_rank_1", .defi, .rare)
        add("daily_podium", .defi, .volume(s2: 10, s3: 50))
        add("daily_streak", .defi, .quality(s1: 3, s2: 7, s3: 30))
        add("daily_days", .defi, .volumeDefault)

        add("duel_win", .duel, .volumeDefault)
        add("duel_win_human", .duel, .rare)
        add("duel_win_local", .duel, .rare)
        add("duel_babybot", .duel, .volumeDefault)
        add("duel_bot1", .duel, .rare)
        add("duel_no_attack", .duel, .rare)
        add("duel_streak", .duel, .quality(s1: 3, s2: 5, s3: 10))

        add("zen_score", .zen, .quality(s1: 200, s2: 2_000, s3: 10_000))
        add("zen_pb", .zen, .rare)

        add("share_home", .folie, .rare)
        add("share_go", .folie, .rare)
        add("theme_light", .folie, .unique)
        add("app_store_review", .folie, .unique)
        add("bomb", .folie, .volume(s2: 100, s3: 1_000))
        add("continue_save", .folie, .volumeDefault)
        add("worst_move", .folie, .volumeDefault)
        add("justesse", .folie, .quality(s1: 80, s2: 90, s3: 100))
        add("bomb_stock", .folie, .quality(s1: 6, s2: 8, s3: 10))
        add("magix_combo", .folie, .volume(s2: 5, s3: 50))
        add("color_clear", .folie, .volumeDefault)

        add("secret_five_bombs", .folie, .rare, secret: true)
        add("secret_zero_bombs", .folie, .volumeDefault, secret: true)
        add("secret_timeout", .folie, .rare, secret: true)
        add("secret_bomb_cancel", .folie, .rare, secret: true)
        add("secret_duel_bomb_freeze", .folie, .rare, secret: true)
        add("secret_line_go", .folie, .volumeDefault, secret: true)
        add("secret_saintx_tiny", .folie, .rare, secret: true)
        add("secret_brixed_zero", .folie, .rare, secret: true)
        add("secret_share_pb", .folie, .rare, secret: true)
        add("secret_high_low", .folie, .volumeDefault, secret: true)
        add("secret_no_chain", .folie, .rare, secret: true)
        add("secret_line_chain", .folie, .volumeDefault, secret: true)
        add("secret_line_combo", .folie, .rare, secret: true)

        return rows
    }()

    static let byID: [String: BlomixTrophyDef] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    static let magixKindIDs: [(MagixKind, String)] = [
        (.chromax, "magix_chromax"),
        (.brixed, "magix_brixed"),
        (.crosx, "magix_crossx"),
        (.slashx, "magix_slashx"),
        (.scrumblx, "magix_scrumblx"),
        (.colorx, "magix_colorx"),
        (.cleanx, "magix_saintx"),
        (.twistx, "magix_twistx"),
        (.bombx, "magix_bombx"),
    ]

    static func def(id: String) -> BlomixTrophyDef? { byID[id] }

    static func trophies(on wall: BlomixTrophyWall) -> [BlomixTrophyDef] {
        all.filter { $0.wall == wall }
    }

    static var visibleCount: Int { all.filter { !$0.isSecret }.count }
}

// MARK: - Store

@MainActor
final class BlomixTrophyStore {
    static let shared = BlomixTrophyStore()

    private static let defaultsKey = "blomix_trophies_v1"

    private struct Payload: Codable {
        var version: Int = 1
        var didRetrofit: Bool = false
        var items: [String: BlomixTrophyProgress] = [:]
        var pending: [BlomixTrophyPromotion] = []
        var lastPromotion: BlomixTrophyPromotion?
        var lastDailyDay: String?
        var duelWinStreak: Int = 0
    }

    private var payload: Payload
    private var loaded = false
    /// Retrofit hiscores : allume les pastilles sans file de toasts (ce n’est pas un palier « maintenant »).
    private var suppressPromotionToasts = false

    private init() {
        payload = Payload()
        load()
        retrofitIfNeeded()
        backfillZenScoreIfNeeded()
    }

    // MARK: Lecture

    func progress(for id: String) -> BlomixTrophyProgress {
        payload.items[id] ?? BlomixTrophyProgress()
    }

    func rank(for id: String) -> BlomixTrophyRank {
        guard let def = BlomixTrophyCatalog.def(id: id) else { return .none }
        return BlomixTrophyMath.rank(value: progress(for: id).value, curve: def.curve)
    }

    func tours(for id: String) -> BlomixTrophyTourFill {
        guard let def = BlomixTrophyCatalog.def(id: id) else {
            return BlomixTrophyTourFill(first: 0, second: 0, innerLit: false, bothFull: false)
        }
        return BlomixTrophyMath.tours(value: progress(for: id).value, curve: def.curve)
    }

    var litVisibleCount: Int {
        BlomixTrophyCatalog.all.filter { def in
            !def.isSecret && rank(for: def.id) != .none
        }.count
    }

    var visibleTotal: Int { BlomixTrophyCatalog.visibleCount }

    func rankCounts() -> (i: Int, ii: Int, iii: Int) {
        var i = 0, ii = 0, iii = 0
        for def in BlomixTrophyCatalog.all where !def.isSecret {
            switch rank(for: def.id) {
            case .i: i += 1
            case .ii: ii += 1
            case .iii: iii += 1
            case .none: break
            }
        }
        return (i, ii, iii)
    }

    var lastPromotion: BlomixTrophyPromotion? { payload.lastPromotion }

    var hasUnseen: Bool {
        if !payload.pending.isEmpty { return true }
        for def in BlomixTrophyCatalog.all {
            let p = progress(for: def.id)
            if p.value > 0 && !p.seen { return true }
        }
        return false
    }

    func consumePendingPromotions() -> [BlomixTrophyPromotion] {
        guard !payload.pending.isEmpty else { return [] }
        let list = payload.pending
        payload.pending.removeAll()
        save()
        return list
    }

    func markSeen(_ id: String) {
        guard var item = payload.items[id], !item.seen else { return }
        item.seen = true
        payload.items[id] = item
        save()
        notify()
    }

    // MARK: Écriture

    @discardableResult
    func increment(_ id: String, by delta: Int = 1) -> BlomixTrophyRank? {
        guard delta > 0, let def = BlomixTrophyCatalog.def(id: id) else { return nil }
        var item = progress(for: id)
        if case .unique = def.curve, item.value >= 1 { return nil }
        item.value += delta
        return apply(id: id, def: def, old: progress(for: id), new: &item)
    }

    @discardableResult
    func recordBest(_ id: String, _ value: Int) -> BlomixTrophyRank? {
        guard let def = BlomixTrophyCatalog.def(id: id), value > 0 else { return nil }
        var item = progress(for: id)
        guard value > item.value else { return nil }
        item.value = value
        return apply(id: id, def: def, old: progress(for: id), new: &item)
    }

    @discardableResult
    func recordUnique(_ id: String) -> BlomixTrophyRank? {
        increment(id, by: 1)
    }

    func debugAdd(_ id: String, by delta: Int = 1) {
        _ = increment(id, by: delta)
        refreshDerivedMagixCollection()
    }

    // MARK: Dérivés

    func refreshDerivedMagixCollection() {
        let n = BlomixTrophyCatalog.magixKindIDs.filter { progress(for: $0.1).value >= 1 }.count
        _ = recordBest("magix_all_nine", n)
    }

    func noteDailyDay(_ day: String) {
        if payload.lastDailyDay == day { return }
        let streakKey = "blomix_trophy_daily_streak"
        var streak = UserDefaults.standard.integer(forKey: streakKey)
        if let last = payload.lastDailyDay, Self.utcDay(last, isImmediatelyBefore: day) {
            streak += 1
        } else {
            streak = 1
        }
        UserDefaults.standard.set(streak, forKey: streakKey)
        payload.lastDailyDay = day
        _ = increment("daily_days")
        _ = recordBest("daily_streak", streak)
        save()
    }

    private static func utcDay(_ earlier: String, isImmediatelyBefore later: String) -> Bool {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        guard let a = fmt.date(from: earlier), let b = fmt.date(from: later) else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.dateComponents([.day], from: a, to: b).day == 1
    }

    func noteDuelFinished(didWin: Bool) {
        _ = increment("play_duel")
        if didWin {
            payload.duelWinStreak += 1
            _ = increment("duel_win")
            _ = recordBest("duel_streak", payload.duelWinStreak)
        } else {
            payload.duelWinStreak = 0
            save()
        }
    }

    // MARK: Interne

    private func apply(
        id: String,
        def: BlomixTrophyDef,
        old: BlomixTrophyProgress,
        new: inout BlomixTrophyProgress
    ) -> BlomixTrophyRank? {
        let now = Date()
        let oldRank = BlomixTrophyMath.rank(value: old.value, curve: def.curve)
        let newRank = BlomixTrophyMath.rank(value: new.value, curve: def.curve)
        if newRank >= .i && new.firstAt == nil { new.firstAt = now }
        if newRank >= .ii && new.iiAt == nil { new.iiAt = now }
        if newRank >= .iii && new.iiiAt == nil { new.iiiAt = now }
        if newRank > oldRank {
            new.seen = false
            let promo = BlomixTrophyPromotion(id: id, rank: newRank)
            payload.lastPromotion = promo
            if !suppressPromotionToasts {
                payload.pending.append(promo)
            }
        }
        payload.items[id] = new
        save()
        notify()
        return newRank > oldRank ? newRank : nil
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            loaded = true
            return
        }
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            print("[Trophies] lecture JSON : \(error)")
            payload = Payload()
        }
        loaded = true
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } catch {
            print("[Trophies] écriture JSON : \(error)")
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .blomixTrophiesDidChange, object: nil)
    }

    private func retrofitIfNeeded() {
        guard !payload.didRetrofit else { return }
        payload.didRetrofit = true
        suppressPromotionToasts = true
        let arcade = ScoreManager.shared.getLocalHighScore()
        if arcade > 0 {
            _ = recordBest("arcade_score", arcade)
            if progress(for: "play_arcade").value == 0 {
                _ = increment("play_arcade")
            }
        }
        let zen = UserDefaults.standard.integer(forKey: "BlomixLocalZenHighScore")
        if zen > 0 {
            if progress(for: "play_zen").value == 0 {
                _ = increment("play_zen")
            }
        }
        let five = UserDefaults.standard.integer(forKey: "BlomixLocalFiveHighScore")
        if five > 0 {
            _ = recordBest("five_score", five)
            if progress(for: "play_five").value == 0 {
                _ = increment("play_five")
            }
        }
        let zenScore = UserDefaults.standard.integer(forKey: "BlomixLocalZenHighScore")
        if zenScore > 0 {
            _ = recordBest("zen_score", zenScore)
        }
        if BlomixAppearance.isLight {
            _ = recordUnique("theme_light")
        }
        payload.pending.removeAll()
        suppressPromotionToasts = false
        save()
    }

    private func backfillZenScoreIfNeeded() {
        guard progress(for: "zen_score").value == 0 else { return }
        let zen = UserDefaults.standard.integer(forKey: "BlomixLocalZenHighScore")
        guard zen > 0 else { return }
        suppressPromotionToasts = true
        _ = recordBest("zen_score", zen)
        payload.pending.removeAll()
        suppressPromotionToasts = false
        save()
    }
}

// MARK: - Hooks (GameScene)

enum BlomixTrophyHooks {
    @MainActor
    static func noteMagix(
        _ kind: MagixKind,
        isUltime: Bool,
        occupiedCells: Int,
        otherBrixCount: Int,
        consecutiveMagix: Bool = false
    ) {
        let id = BlomixTrophyCatalog.magixKindIDs.first { $0.0 == kind }?.1
        if let id {
            _ = BlomixTrophyStore.shared.increment(id)
        }
        if consecutiveMagix {
            _ = BlomixTrophyStore.shared.increment("magix_combo")
        }
        if kind == .cleanx, isUltime {
            _ = BlomixTrophyStore.shared.increment("magix_saintx_ultime")
        }
        if kind == .cleanx, occupiedCells <= 8 {
            _ = BlomixTrophyStore.shared.increment("secret_saintx_tiny")
        }
        if kind == .brixed, otherBrixCount == 0 {
            _ = BlomixTrophyStore.shared.increment("secret_brixed_zero")
        }
        if kind == .brixed, otherBrixCount > 24 {
            _ = BlomixTrophyStore.shared.increment("magix_brixed_strike")
        }
        // Magix déjà inscrit : une vide de moins qu’au choix de la pose.
        let emptyAtPose = max(0, 64 - occupiedCells) + 1
        if emptyAtPose < 10 {
            _ = BlomixTrophyStore.shared.increment("magix_last_minute")
        }
        if emptyAtPose == 1 {
            _ = BlomixTrophyStore.shared.increment("magix_last_cell")
        }
        BlomixTrophyStore.shared.refreshDerivedMagixCollection()
    }

    @MainActor
    static func noteChainWave(sizes: [Int], seriesLevel: Int, connectCount: Int) {
        let maxSize = sizes.max() ?? 0
        if maxSize >= 5 {
            _ = BlomixTrophyStore.shared.recordBest("chain_size", maxSize)
            _ = BlomixTrophyStore.shared.increment("chain_count", by: sizes.filter { $0 >= 5 }.count)
        }
        if seriesLevel == 1 {
            _ = BlomixTrophyStore.shared.increment("combo")
        }
        if seriesLevel == 4 {
            _ = BlomixTrophyStore.shared.increment("combo_deep")
        }
        if connectCount > 0 {
            _ = BlomixTrophyStore.shared.increment("connect", by: connectCount)
        }
    }

    @MainActor
    static func noteBoardEmpty(isFive: Bool) {
        _ = BlomixTrophyStore.shared.increment("board_empty")
        if isFive {
            _ = BlomixTrophyStore.shared.increment("five_empty")
        }
    }

    @MainActor
    static func noteBomb(isNuke: Bool, brixBroken: Int = 0) {
        _ = BlomixTrophyStore.shared.increment("bomb")
        if isNuke {
            _ = BlomixTrophyStore.shared.increment("arcade_nuke")
        }
        if brixBroken > 0 {
            _ = BlomixTrophyStore.shared.recordBest("bomb_brix", brixBroken)
        }
    }

    @MainActor
    static func noteShareHome() {
        _ = BlomixTrophyStore.shared.increment("share_home")
    }

    @MainActor
    static func noteShareGameOver(isNewPB: Bool) {
        _ = BlomixTrophyStore.shared.increment("share_go")
        if isNewPB {
            _ = BlomixTrophyStore.shared.increment("secret_share_pb")
        }
    }

    @MainActor
    static func noteThemeLight() {
        _ = BlomixTrophyStore.shared.recordUnique("theme_light")
    }

    @MainActor
    static func noteContinueSave() {
        _ = BlomixTrophyStore.shared.increment("continue_save")
    }

    @MainActor
    static func noteTutorialFinished() {
        _ = BlomixTrophyStore.shared.recordUnique("play_tutorial")
    }

    @MainActor
    static func noteWorstMove() {
        _ = BlomixTrophyStore.shared.increment("worst_move")
    }

    @MainActor
    static func noteBombCancel() {
        _ = BlomixTrophyStore.shared.increment("secret_bomb_cancel")
    }

    @MainActor
    static func noteDuelBombFreeze() {
        _ = BlomixTrophyStore.shared.increment("secret_duel_bomb_freeze")
    }

    @MainActor
    static func noteBombStock(_ count: Int) {
        _ = BlomixTrophyStore.shared.recordBest("bomb_stock", count)
    }

    @MainActor
    static func noteColorClear(count: Int) {
        guard count > 0 else { return }
        _ = BlomixTrophyStore.shared.increment("color_clear", by: count)
    }

    @MainActor
    static func noteColumnHighLow() {
        _ = BlomixTrophyStore.shared.increment("secret_high_low")
    }

    @MainActor
    static func noteBoardRecover() {
        _ = BlomixTrophyStore.shared.increment("board_recover")
    }

    @MainActor
    static func noteBrixLine() {
        _ = BlomixTrophyStore.shared.increment("brix_line")
    }

    @MainActor
    static func notePureStreak(_ count: Int) {
        _ = BlomixTrophyStore.shared.recordBest("pure_streak", count)
    }

    @MainActor
    static func noteAppStoreReview() {
        _ = BlomixTrophyStore.shared.recordUnique("app_store_review")
    }

    @MainActor
    static func noteIncomingLineChain() {
        _ = BlomixTrophyStore.shared.increment("secret_line_chain")
    }

    @MainActor
    static func noteIncomingLineCombo() {
        _ = BlomixTrophyStore.shared.increment("secret_line_combo")
    }

    @MainActor
    static func noteNoChainGameOver() {
        _ = BlomixTrophyStore.shared.increment("secret_no_chain")
    }

    @MainActor
    static func noteDailyGhostBeat() {
        _ = BlomixTrophyStore.shared.increment("daily_ghost_beat")
    }

    @MainActor
    static func noteDailyRank1() {
        _ = BlomixTrophyStore.shared.increment("daily_rank_1")
    }

    @MainActor
    static func noteDailyPodium() {
        _ = BlomixTrophyStore.shared.increment("daily_podium")
    }
}

//
//  BlomixDailyRNG.swift
//  Blomix
//
//  Deux flux déterministes pour le Défi du jour :
//  - File : LCG seedé (même suite Blox / Brix / Magix kind + lignes des 10).
//  - Effets Magix : LCG dérivé d’un hash d’événement (ne consomme pas la File).
//

import Foundation

/// LCG identique à `BlomixPvPSeededBlockRNG` (même constante), seedé par le jour UTC.
struct BlomixDailyFileRNG: Equatable {
    /// Graine du jour (figée au lancement de la run).
    let seed: UInt64
    /// État courant du LCG (persisté dans le slot daily).
    private(set) var state: UInt64

    init(seed: UInt64) {
        self.seed = seed == 0 ? 1 : seed
        self.state = self.seed
    }

    init(seed: UInt64, state: UInt64) {
        self.seed = seed == 0 ? 1 : seed
        self.state = state == 0 ? self.seed : state
    }

    mutating func nextUInt64() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func nextUnitDouble() -> Double {
        Double(nextUInt64() % 9_007_199_254_740_992) / 9_007_199_254_740_992
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(nextUInt64() % UInt64(upperBound))
    }

    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[nextInt(upperBound: items.count)]
    }
}

/// Hasard d’un effet Magix : seed jour + kind + coup + case. Indépendant de la File.
struct BlomixDailyEffectRNG {
    private var state: UInt64

    init(daySeed: UInt64, event: String, moveCount: Int, row: Int, col: Int) {
        var hash = BlomixDailySeed.fnv64("blomix-daily-fx-v1")
        hash = BlomixDailySeed.fnvMix(hash, daySeed)
        hash = BlomixDailySeed.fnvMix(hash, BlomixDailySeed.fnv64(event))
        hash = BlomixDailySeed.fnvMix(hash, UInt64(bitPattern: Int64(moveCount)))
        hash = BlomixDailySeed.fnvMix(hash, UInt64(bitPattern: Int64(row)))
        hash = BlomixDailySeed.fnvMix(hash, UInt64(bitPattern: Int64(col)))
        self.state = hash == 0 ? 1 : hash
    }

    mutating func nextUInt64() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func nextUnitDouble() -> Double {
        Double(nextUInt64() % 9_007_199_254_740_992) / 9_007_199_254_740_992
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(nextUInt64() % UInt64(upperBound))
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        return range.lowerBound + nextInt(upperBound: span)
    }

    mutating func nextBool() -> Bool {
        nextUnitDouble() < 0.5
    }

    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[nextInt(upperBound: items.count)]
    }
}

/// Calendrier UTC + graine documentée `hash("blomix-daily-v1" + YYYY-MM-DD)` (FNV-1a 64).
enum BlomixDailySeed {
    static let formatVersion = "v1"
    private static let salt = "blomix-daily-v1"

    static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    static func utcDayString(from date: Date = Date()) -> String {
        let c = utcCalendar().dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func previousUtcDayString(from date: Date = Date()) -> String {
        let cal = utcCalendar()
        let yesterday = cal.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400)
        return utcDayString(from: yesterday)
    }

    /// FNV-1a 64 de `"blomix-daily-v1" + YYYY-MM-DD`. Jamais 0.
    static func seed(forDay day: String) -> UInt64 {
        let hash = fnv64(salt + day)
        return hash == 0 ? 1 : hash
    }

    static func fnv64(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    static func fnvMix(_ hash: UInt64, _ extra: UInt64) -> UInt64 {
        var h = hash
        h ^= extra
        h = h &* 1_099_511_628_211
        return h
    }
}

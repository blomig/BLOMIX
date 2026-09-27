//
//  WatchBlockType.swift
//  Copie Watch des types iPhone. Ne pas importer le target iOS.
//

import Foundation

enum WatchMagixKind: String, Codable, Equatable, CaseIterable {
    case chromax, brixed, crosx, slashx, scrumblx, colorx, cleanx, twistx, bombx

    var glyph: String {
        switch self {
        case .chromax:  return "?"
        case .brixed:   return "9"
        case .crosx:    return "+"
        case .slashx:   return "X"
        case .scrumblx: return "="
        case .colorx:   return "O"
        case .cleanx:   return "∞"
        case .twistx:   return "§"
        case .bombx:    return "B"
        }
    }

    var label: String {
        switch self {
        case .chromax:  return "CHROMAX"
        case .brixed:   return "BRIXED"
        case .crosx:    return "CROSSX"
        case .slashx:   return "SLASHX"
        case .scrumblx: return "SCRUMBLX"
        case .colorx:   return "COLORX"
        case .cleanx:   return "SAINTX"
        case .twistx:   return "TWISTX"
        case .bombx:    return "BOMBX"
        }
    }
}

enum WatchBlockType: Equatable, Codable {
    case empty
    case color(String)
    case priks(Int)
    case magix(WatchMagixKind)

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    private enum Tag: String, Codable { case e, c, p, mx }
    private enum CodingKeys: String, CodingKey { case t, v }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Tag.self, forKey: .t) {
        case .e:  self = .empty
        case .c:  self = .color(try container.decode(String.self, forKey: .v))
        case .p:  self = .priks(try container.decode(Int.self, forKey: .v))
        case .mx: self = .magix(try container.decode(WatchMagixKind.self, forKey: .v))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty:
            try c.encode(Tag.e, forKey: .t)
        case .color(let name):
            try c.encode(Tag.c, forKey: .t)
            try c.encode(name, forKey: .v)
        case .priks(let hits):
            try c.encode(Tag.p, forKey: .t)
            try c.encode(hits, forKey: .v)
        case .magix(let kind):
            try c.encode(Tag.mx, forKey: .t)
            try c.encode(kind, forKey: .v)
        }
    }
}

struct WatchGridAddress: Hashable, Equatable {
    var row: Int
    var col: Int
}

enum WatchGridLayout {
    static let rowCount = 8
    static let columnCount = 8
    static let topRowIndex = 0
    static let bottomRowIndex = rowCount - 1
}

enum WatchPriksRules {
    static let spawnProbability: Double = 1.0 / 8.0
    static let initialHitsRemaining = 5
}

enum WatchMagixRules {
    static let spawnEnabled = true

    static let spawnProbabilityByKind: [(kind: WatchMagixKind, p: Double)] = [
        (.twistx,   1.0 / 324.0),
        (.colorx,   1.0 / 180.0),
        (.scrumblx, 1.0 / 180.0),
        (.crosx,    1.0 / 432.0),
        (.slashx,   1.0 / 432.0),
        (.chromax,  1.0 / 324.0),
        (.brixed,   1.0 / 324.0),
        (.cleanx,   1.0 / 500.0),
        (.bombx,    1.0 / 500.0),
    ]

    static var spawnProbability: Double {
        spawnProbabilityByKind.reduce(0) { $0 + $1.p }
    }

    static let chromaxPathLength = 15
    static let brixedInitialHits = 9
}

enum WatchZenRules {
    static let colorPalette = ["red", "blue", "green", "yellow", "purple", "orange"]
    static let fullyClearedBoardBonusPoints = 500
    static let clearedColumnBonusPoints = 10
    static let vanishedPriksBonusPoints = 20
    static let bombUsePoints = 10
    static let saintxBonusPoints = 200
    static let zenBombStock = 5
    static let compactAnimationDuration: Double = 0.22
    static let lineRiseAnimationDuration: Double = 0.32
    static let magixWaveDelay: Double = 0.07

    static let neighborDeltas8: [(dr: Int, dc: Int)] = [
        (-1, -1), (-1, 0), (-1, 1),
        (0, -1),          (0, 1),
        (1, -1),  (1, 0), (1, 1),
    ]

    static func chainClearScorePoints(chainSeriesLevel: Int, groupSize: Int) -> Int {
        let base: Int
        switch groupSize {
        case ..<6:  base = 5
        case 6:     base = 7
        case 7:     base = 10
        case 8:     base = 13
        case 9:     base = 15
        default:    base = 20
        }
        return base + chainSeriesLevel * 10
    }

    static func randomPlayableBlock() -> WatchBlockType {
        let r = Double.random(in: 0..<1)
        if WatchMagixRules.spawnEnabled, r < WatchMagixRules.spawnProbability {
            var cumul = 0.0
            var chosen: WatchMagixKind = .chromax
            for entry in WatchMagixRules.spawnProbabilityByKind {
                cumul += entry.p
                if r < cumul {
                    chosen = entry.kind
                    break
                }
            }
            return .magix(chosen)
        }
        let priksCut = (WatchMagixRules.spawnEnabled ? WatchMagixRules.spawnProbability : 0)
            + WatchPriksRules.spawnProbability
        if r < priksCut {
            return .priks(WatchPriksRules.initialHitsRemaining)
        }
        return .color(colorPalette.randomElement() ?? "red")
    }

    static func randomColorBlock() -> WatchBlockType {
        .color(colorPalette.randomElement() ?? "red")
    }

    /// Ligne / 10 : mêmes tirages que la file, Magix strippés en couleur.
    static func randomBottomLineRow() -> [WatchBlockType] {
        (0..<WatchGridLayout.columnCount).map { _ in
            let block = randomPlayableBlock()
            if case .magix = block { return randomColorBlock() }
            return block
        }
    }

    static func emptyGrid() -> [[WatchBlockType]] {
        Array(
            repeating: Array(repeating: WatchBlockType.empty, count: WatchGridLayout.columnCount),
            count: WatchGridLayout.rowCount
        )
    }

    static func bombAffectedCells(center: WatchGridAddress) -> [WatchGridAddress] {
        var result: [WatchGridAddress] = []
        for dr in -1...1 {
            for dc in -1...1 {
                let r = center.row + dr
                let c = center.col + dc
                guard r >= WatchGridLayout.topRowIndex, r < WatchGridLayout.rowCount,
                      c >= 0, c < WatchGridLayout.columnCount else { continue }
                result.append(WatchGridAddress(row: r, col: c))
            }
        }
        return result
    }
}

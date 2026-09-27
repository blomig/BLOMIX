//
//  WatchMagixResolve.swift
//  Occupancy 7.3, sans juice / sans resolveChains / sans compact.
//

import Foundation

struct WatchMagixFX: Equatable {
    var kind: WatchMagixKind
    var name: String
    var landing: WatchGridAddress
    var highlight: [WatchGridAddress]
    var paintColor: String?
}

struct WatchMagixPlan {
    var kind: WatchMagixKind
    var name: String
    var resultGrid: [[WatchBlockType]]
    var scoreDelta: Int
    var bombDelta: Int
    var paintColor: String?
    var paintWaves: [[WatchGridAddress]]
    var wipe: [WatchGridAddress]
    var rowShifts: [(row: Int, delta: Int)]
    var preShiftGrid: [[WatchBlockType]]? = nil
}

enum WatchMagixResolve {
    static func plan(
        kind: WatchMagixKind,
        at landing: WatchGridAddress,
        grid: [[WatchBlockType]],
        chainSeriesLevel: Int
    ) -> WatchMagixPlan {
        switch kind {
        case .chromax:  return chromax(at: landing, grid: grid)
        case .crosx:    return crosx(at: landing, grid: grid)
        case .slashx:   return slashx(at: landing, grid: grid)
        case .bombx:    return bombx(at: landing, grid: grid)
        case .brixed:   return brixed(at: landing, grid: grid)
        case .colorx:   return colorx(at: landing, grid: grid, chainSeriesLevel: chainSeriesLevel)
        case .cleanx:   return cleanx(at: landing, grid: grid)
        case .twistx:   return twistx(at: landing, grid: grid)
        case .scrumblx: return scrumblx(at: landing, grid: grid)
        }
    }

    // MARK: - Paint

    private static func chromax(at start: WatchGridAddress, grid: [[WatchBlockType]]) -> WatchMagixPlan {
        var g = grid
        let color = WatchZenRules.colorPalette.randomElement() ?? "red"
        var path: [WatchGridAddress] = [start]
        var visited: Set<WatchGridAddress> = [start]
        var current = start
        while path.count < WatchMagixRules.chromaxPathLength {
            let candidates = WatchZenRules.neighborDeltas8.compactMap { d -> WatchGridAddress? in
                let nr = current.row + d.dr
                let nc = current.col + d.dc
                guard inBounds(nr, nc), !g[nr][nc].isEmpty else { return nil }
                let addr = WatchGridAddress(row: nr, col: nc)
                guard !visited.contains(addr) else { return nil }
                return addr
            }
            guard let next = candidates.randomElement() else { break }
            path.append(next)
            visited.insert(next)
            current = next
        }
        for addr in path { g[addr.row][addr.col] = .color(color) }
        return WatchMagixPlan(
            kind: .chromax, name: WatchMagixKind.chromax.label, resultGrid: g,
            scoreDelta: 0, bombDelta: 0, paintColor: color,
            paintWaves: path.map { [$0] }, wipe: [], rowShifts: []
        )
    }

    private static func crosx(at landing: WatchGridAddress, grid: [[WatchBlockType]]) -> WatchMagixPlan {
        var cells: [WatchGridAddress] = []
        for c in 0..<WatchGridLayout.columnCount {
            switch grid[landing.row][c] {
            case .color, .priks: cells.append(WatchGridAddress(row: landing.row, col: c))
            default: break
            }
        }
        for r in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            if r == landing.row { continue }
            switch grid[r][landing.col] {
            case .color, .priks: cells.append(WatchGridAddress(row: r, col: landing.col))
            default: break
            }
        }
        return axisPaint(kind: .crosx, at: landing, cells: cells, grid: grid) { addr in
            abs(addr.row - landing.row) + abs(addr.col - landing.col)
        }
    }

    private static func slashx(at landing: WatchGridAddress, grid: [[WatchBlockType]]) -> WatchMagixPlan {
        var cells: [WatchGridAddress] = []
        for r in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for c in 0..<WatchGridLayout.columnCount {
                guard abs(r - landing.row) == abs(c - landing.col) else { continue }
                switch grid[r][c] {
                case .color, .priks: cells.append(WatchGridAddress(row: r, col: c))
                default: break
                }
            }
        }
        return axisPaint(kind: .slashx, at: landing, cells: cells, grid: grid) { addr in
            abs(addr.row - landing.row)
        }
    }

    private static func axisPaint(
        kind: WatchMagixKind,
        at landing: WatchGridAddress,
        cells: [WatchGridAddress],
        grid: [[WatchBlockType]],
        distance: (WatchGridAddress) -> Int
    ) -> WatchMagixPlan {
        var g = grid
        let color = WatchZenRules.colorPalette.randomElement() ?? "red"
        var paint = cells
        if !paint.contains(landing) { paint.append(landing) }
        for addr in paint { g[addr.row][addr.col] = .color(color) }
        let grouped = Dictionary(grouping: paint, by: distance)
        let waves = grouped.keys.sorted().map { grouped[$0]! }
        return WatchMagixPlan(
            kind: kind, name: kind.label, resultGrid: g,
            scoreDelta: 0, bombDelta: 0, paintColor: color,
            paintWaves: waves, wipe: [], rowShifts: []
        )
    }

    private static func bombx(at landing: WatchGridAddress, grid: [[WatchBlockType]]) -> WatchMagixPlan {
        var g = grid
        let color = WatchZenRules.colorPalette.randomElement() ?? "red"
        let rank0 = [landing]
        let rank1 = occupiedNeighbors(of: landing, in: grid)
        var rank2: [WatchGridAddress] = []
        for n in rank1 {
            let neigh = occupiedNeighbors(of: n, in: grid)
            if let pick = neigh.randomElement() { rank2.append(pick) }
        }
        var rank3: [WatchGridAddress] = []
        for s in rank2 {
            let neigh = occupiedNeighbors(of: s, in: grid)
            if let pick = neigh.randomElement() { rank3.append(pick) }
        }
        let ranks = [rank0, rank1, rank2, rank3].filter { !$0.isEmpty }
        let painted = Set(ranks.flatMap { $0 })
        for addr in painted { g[addr.row][addr.col] = .color(color) }
        return WatchMagixPlan(
            kind: .bombx, name: WatchMagixKind.bombx.label, resultGrid: g,
            scoreDelta: 0, bombDelta: 1, paintColor: color,
            paintWaves: ranks, wipe: [], rowShifts: []
        )
    }

    // MARK: - Rewrite

    private static func brixed(at landing: WatchGridAddress, grid: [[WatchBlockType]]) -> WatchMagixPlan {
        var g = grid
        g[landing.row][landing.col] = .priks(WatchMagixRules.brixedInitialHits)
        var wipe: [WatchGridAddress] = []
        for r in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for c in 0..<WatchGridLayout.columnCount {
                if r == landing.row && c == landing.col { continue }
                if case .priks = g[r][c] {
                    wipe.append(WatchGridAddress(row: r, col: c))
                    g[r][c] = .empty
                }
            }
        }
        return WatchMagixPlan(
            kind: .brixed, name: WatchMagixKind.brixed.label, resultGrid: g,
            scoreDelta: wipe.count * WatchZenRules.vanishedPriksBonusPoints,
            bombDelta: 0, paintColor: nil,
            paintWaves: wipe.isEmpty ? [] : [wipe], wipe: wipe, rowShifts: []
        )
    }

    private static func colorx(at landing: WatchGridAddress, grid: [[WatchBlockType]], chainSeriesLevel: Int) -> WatchMagixPlan {
        var g = grid
        g[landing.row][landing.col] = .empty
        let present = WatchZenRules.colorPalette.filter { name in
            g.contains { row in row.contains { if case .color(let n) = $0 { return n == name }; return false } }
        }
        let pool = present.isEmpty ? WatchZenRules.colorPalette : present
        let chosen = pool.randomElement() ?? "red"
        var wipe: [WatchGridAddress] = [landing]
        for r in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for c in 0..<WatchGridLayout.columnCount {
                if case .color(let n) = g[r][c], n == chosen {
                    wipe.append(WatchGridAddress(row: r, col: c))
                    g[r][c] = .empty
                }
            }
        }
        let colorCount = wipe.count - 1
        let pts = colorCount > 0
            ? WatchZenRules.chainClearScorePoints(chainSeriesLevel: chainSeriesLevel, groupSize: colorCount)
            : 0
        return WatchMagixPlan(
            kind: .colorx, name: WatchMagixKind.colorx.label, resultGrid: g,
            scoreDelta: pts, bombDelta: 0, paintColor: chosen,
            paintWaves: [wipe], wipe: wipe, rowShifts: []
        )
    }

    private static func cleanx(at landing: WatchGridAddress, grid: [[WatchBlockType]]) -> WatchMagixPlan {
        var g = grid
        var wipe: [WatchGridAddress] = []
        for r in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for c in 0..<WatchGridLayout.columnCount {
                if r == landing.row && c == landing.col { continue }
                if !g[r][c].isEmpty {
                    wipe.append(WatchGridAddress(row: r, col: c))
                    g[r][c] = .empty
                }
            }
        }
        g[landing.row][landing.col] = .priks(max(1, wipe.count))
        return WatchMagixPlan(
            kind: .cleanx, name: WatchMagixKind.cleanx.label, resultGrid: g,
            scoreDelta: WatchZenRules.saintxBonusPoints, bombDelta: 0, paintColor: nil,
            paintWaves: wipe.isEmpty ? [] : [wipe], wipe: wipe, rowShifts: []
        )
    }

    private static func twistx(at landing: WatchGridAddress, grid: [[WatchBlockType]]) -> WatchMagixPlan {
        var g = grid
        g[landing.row][landing.col] = .empty
        let present = WatchZenRules.colorPalette.filter { name in
            g.contains { row in row.contains { if case .color(let n) = $0 { return n == name }; return false } }
        }
        guard let chosen = present.randomElement() else {
            return WatchMagixPlan(
                kind: .twistx, name: WatchMagixKind.twistx.label, resultGrid: g,
                scoreDelta: 0, bombDelta: 0, paintColor: nil,
                paintWaves: [], wipe: [landing], rowShifts: []
            )
        }
        var minPriks = Int.max
        var colorCells: [WatchGridAddress] = []
        var priksCells: [WatchGridAddress] = []
        for r in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for c in 0..<WatchGridLayout.columnCount {
                switch g[r][c] {
                case .color(let n) where n == chosen:
                    colorCells.append(WatchGridAddress(row: r, col: c))
                case .priks(let n):
                    priksCells.append(WatchGridAddress(row: r, col: c))
                    minPriks = min(minPriks, n)
                default: break
                }
            }
        }
        let priksValue = (minPriks == Int.max) ? 3 : minPriks
        for addr in colorCells { g[addr.row][addr.col] = .priks(priksValue) }
        for addr in priksCells { g[addr.row][addr.col] = .color(chosen) }
        let swapped = colorCells + priksCells
        return WatchMagixPlan(
            kind: .twistx, name: WatchMagixKind.twistx.label, resultGrid: g,
            scoreDelta: 0, bombDelta: 0, paintColor: chosen,
            paintWaves: swapped.isEmpty ? [] : [swapped], wipe: [landing], rowShifts: []
        )
    }

    private static func scrumblx(at landing: WatchGridAddress, grid: [[WatchBlockType]]) -> WatchMagixPlan {
        var g = grid
        g[landing.row][landing.col] = .empty
        var wipe: [WatchGridAddress] = [landing]
        var score = 0
        for r in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for c in 0..<WatchGridLayout.columnCount {
                guard case .priks(let n) = g[r][c] else { continue }
                if n <= 1 {
                    g[r][c] = .empty
                    wipe.append(WatchGridAddress(row: r, col: c))
                    score += WatchZenRules.vanishedPriksBonusPoints
                } else {
                    g[r][c] = .priks(n - 1)
                }
            }
        }
        let preShift = g
        var shifts: [(row: Int, delta: Int)] = []
        let cols = WatchGridLayout.columnCount
        for r in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            let occupied = (0..<cols).contains { !g[r][$0].isEmpty }
            guard occupied else { continue }
            let dir = Bool.random() ? 1 : -1
            let steps = Int.random(in: 1...7)
            let delta = dir * steps
            shifts.append((r, delta))
            let old = g[r]
            var newRow = Array(repeating: WatchBlockType.empty, count: cols)
            for c in 0..<cols {
                let newC = ((c + delta) % cols + cols) % cols
                newRow[newC] = old[c]
            }
            g[r] = newRow
        }
        return WatchMagixPlan(
            kind: .scrumblx, name: WatchMagixKind.scrumblx.label, resultGrid: g,
            scoreDelta: score, bombDelta: 0, paintColor: nil,
            paintWaves: [], wipe: wipe, rowShifts: shifts, preShiftGrid: preShift
        )
    }

    // MARK: - Helpers

    private static func inBounds(_ r: Int, _ c: Int) -> Bool {
        r >= WatchGridLayout.topRowIndex && r < WatchGridLayout.rowCount
            && c >= 0 && c < WatchGridLayout.columnCount
    }

    private static func occupiedNeighbors(of addr: WatchGridAddress, in grid: [[WatchBlockType]]) -> [WatchGridAddress] {
        WatchZenRules.neighborDeltas8.compactMap { d in
            let nr = addr.row + d.dr
            let nc = addr.col + d.dc
            guard inBounds(nr, nc), !grid[nr][nc].isEmpty else { return nil }
            return WatchGridAddress(row: nr, col: nc)
        }
    }
}

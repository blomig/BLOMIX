//
//  WatchZenEngine.swift
//  Moteur Zen light Watch.
//

import Combine
import Foundation
import os

@MainActor
final class WatchZenEngine: ObservableObject {
    private static let log = Logger(subsystem: "blomig.BLOMIX.watchkitapp", category: "zen")

    @Published private(set) var run: WatchZenRunState
    @Published private(set) var liveCells: [WatchLiveCell] = []
    @Published private(set) var aimedBombCell: WatchGridAddress?
    @Published private(set) var highlightedColumn: Int?
    @Published private(set) var isGameOver = false
    @Published private(set) var incomingPreview: [WatchBlockType]?
    @Published private(set) var isProcessing = false
    @Published private(set) var magixFX: WatchMagixFX?
    /// Dernière chaîne à faire voler vers le score. Hors sauvegarde.
    @Published private(set) var chainSparkle: WatchChainSparkleRequest?
    /// Points de chaîne pas encore comptés dans le delta de `score`.
    private var chainSparklePoints = 0
    private var chainSparkleToken = 0

    var grid: [[WatchBlockType]] { run.grid }
    var moveCount: Int { run.moveCount }
    var chainSeriesLevel: Int { run.chainSeriesLevel }
    var bombCount: Int { run.bombCount }
    var isBombMode: Bool { run.isBombMode }
    var score: Int { run.score }
    var p0: WatchBlockType { run.p0 }
    var p1: WatchBlockType { run.p1 }
    var p2: WatchBlockType { run.p2 }
    var bombButtonEnabled: Bool { run.bombCount > 0 || run.isBombMode }

    private var shouldRunPostPlacementHooks = false
    private var cellIDs: [[UUID?]] = WatchZenEngine.emptyIDs()
    private var resolveTask: Task<Void, Never>?

    init(snapshot: WatchZenRunState? = nil) {
        if let snapshot {
            run = snapshot
        } else {
            run = WatchZenRunState.newGame()
        }
        aimedBombCell = nil
        highlightedColumn = nil
        refreshIncomingPreview()
        syncLiveCells()
    }

    func newGame() {
        resolveTask?.cancel()
        run = WatchZenRunState.newGame()
        cellIDs = Self.emptyIDs()
        aimedBombCell = nil
        highlightedColumn = nil
        isGameOver = false
        isProcessing = false
        shouldRunPostPlacementHooks = false
        magixFX = nil
        chainSparkle = nil
        chainSparklePoints = 0
        refreshIncomingPreview()
        syncLiveCells()
    }

    func restore(_ snapshot: WatchZenRunState) {
        resolveTask?.cancel()
        run = snapshot
        cellIDs = Self.emptyIDs()
        aimedBombCell = nil
        highlightedColumn = nil
        isGameOver = false
        isProcessing = false
        shouldRunPostPlacementHooks = false
        magixFX = nil
        chainSparkle = nil
        chainSparklePoints = 0
        refreshIncomingPreview()
        syncLiveCells()
    }

    func exportRunState() -> WatchZenRunState {
        var snapshot = run
        snapshot.savedAt = Date()
        return snapshot
    }

    /// Visée / highlight hors JSON. `isBombMode` reste dans le snapshot.
    func flushTransientAim() {
        highlightedColumn = nil
        aimedBombCell = nil
    }

    /// À appeler quand `score` change. Retire au plus `delta` points de chaîne
    /// déjà lancés vers le score, pour ne pas les ajouter une seconde fois.
    func consumeChainSparklePoints(upTo delta: Int) -> Int {
        let claimed = min(max(0, delta), chainSparklePoints)
        chainSparklePoints -= claimed
        return claimed
    }

    func setHighlightedColumn(_ col: Int?) {
        guard !isGameOver, !isProcessing, !run.isBombMode else { return }
        if let col {
            highlightedColumn = min(max(col, 0), WatchGridLayout.columnCount - 1)
        } else {
            highlightedColumn = nil
        }
    }

    func cancelGesture() {
        highlightedColumn = nil
        aimedBombCell = nil
    }

    func drop(column: Int) {
        guard !isGameOver, !isProcessing, !run.isBombMode else { return }
        switch run.p0 {
        case .color, .priks, .magix:
            break
        case .empty:
            return
        }

        let columnIndex = min(max(column, 0), WatchGridLayout.columnCount - 1)
        highlightedColumn = nil

        if highestEmptyRow(inColumn: columnIndex) == nil {
            let hasRoomElsewhere = (0..<WatchGridLayout.columnCount).contains {
                $0 != columnIndex && highestEmptyRow(inColumn: $0) != nil
            }
            if hasRoomElsewhere { return }
            triggerGameOver()
            return
        }
        guard let row = highestEmptyRow(inColumn: columnIndex) else { return }

        isProcessing = true
        let placed = run.p0
        write(placed, row: row, col: columnIndex)
        advanceQueue()
        shouldRunPostPlacementHooks = true
        run.chainSeriesLevel = 0
        let landing = WatchGridAddress(row: row, col: columnIndex)
        let placedID = cellIDs[row][columnIndex]

        resolveTask?.cancel()
        resolveTask = Task { @MainActor in
            if let placedID {
                self.syncLiveCells(rowOverride: [placedID: WatchGridLayout.rowCount])
                await self.pause(0.02)
            }
            self.syncLiveCells()
            await self.pause(WatchZenRules.lineRiseAnimationDuration)
            if case .magix(let kind) = placed {
                await self.playMagix(kind, at: landing)
            }
            _ = await self.resolveChainsAsync()
            self.syncLiveCells()
            Self.log.debug("drop col=\(columnIndex, privacy: .public) score=\(self.run.score, privacy: .public) moveCount=\(self.run.moveCount, privacy: .public)")
            if !self.isGameOver { self.isProcessing = false }
        }
    }

    func debugCycleP0Magix() {
        #if DEBUG
        let all = WatchMagixKind.allCases
        if case .magix(let kind) = run.p0, let idx = all.firstIndex(of: kind) {
            run.p0 = .magix(all[(idx + 1) % all.count])
        } else {
            run.p0 = .magix(all[0])
        }
        #endif
    }

    // MARK: - Bombe

    func toggleBombMode() {
        guard !isGameOver, !isProcessing else { return }
        highlightedColumn = nil
        aimedBombCell = nil
        if run.isBombMode {
            run.isBombMode = false
            run.bombCount += 1
        } else {
            guard run.bombCount > 0 else { return }
            run.isBombMode = true
            run.bombCount -= 1
        }
    }

    func updateBombAim(_ cell: WatchGridAddress?) {
        guard !isGameOver, !isProcessing, run.isBombMode else { return }
        aimedBombCell = cell
    }

    func placeBombAtAimedCell() {
        guard !isGameOver, !isProcessing, run.isBombMode else { return }
        guard run.bombCount >= 0 else {
            run.isBombMode = false
            aimedBombCell = nil
            return
        }
        guard let cell = aimedBombCell else {
            aimedBombCell = nil
            return
        }

        isProcessing = true
        aimedBombCell = nil
        shouldRunPostPlacementHooks = false

        let occupancy = occupancyByColumn()
        let blast = WatchZenRules.bombAffectedCells(center: cell)
        var priksHit = 0
        for addr in blast {
            if case .priks = run.grid[addr.row][addr.col] { priksHit += 1 }
            write(.empty, row: addr.row, col: addr.col)
        }
        run.score += WatchZenRules.bombUsePoints + priksHit * WatchZenRules.vanishedPriksBonusPoints
        run.isBombMode = false
        compactGridTowardTop()
        awardFullyClearedColumnBonuses(columnHadBlockBefore: occupancy)
        run.chainSeriesLevel = 1
        resolveTask?.cancel()
        resolveTask = Task { @MainActor in
            _ = await self.resolveChainsAsync()
            self.syncLiveCells()
            Self.log.debug("bomb r=\(cell.row, privacy: .public) c=\(cell.col, privacy: .public) score=\(self.run.score, privacy: .public)")
            if !self.isGameOver { self.isProcessing = false }
        }
    }

    // MARK: - Magix

    private func playMagix(_ kind: WatchMagixKind, at landing: WatchGridAddress) async {
        let occupancy = occupancyByColumn()
        magixFX = WatchMagixFX(
            kind: kind, name: kind.label, landing: landing,
            highlight: [landing], paintColor: nil
        )
        await pause(0.18)

        let plan = WatchMagixResolve.plan(
            kind: kind, at: landing, grid: run.grid, chainSeriesLevel: run.chainSeriesLevel
        )
        if var fx = magixFX {
            fx.paintColor = plan.paintColor
            fx.name = plan.name
            magixFX = fx
        }

        if case .priks = plan.resultGrid[landing.row][landing.col] {
            write(plan.resultGrid[landing.row][landing.col], row: landing.row, col: landing.col, keepID: true)
            syncLiveCells()
        }

        if let preShift = plan.preShiftGrid {
            if var fx = magixFX {
                fx.highlight = plan.wipe
                magixFX = fx
            }
            await pause(0.12)
            await animateDisappearance(ordered: orderedDisappearance(plan.wipe))
            guard !Task.isCancelled, !isGameOver else { return }
            adoptGrid(preShift)
            syncLiveCells()
            await pause(0.12)
            applyRowShifts(plan.rowShifts)
            syncLiveCells()
            await pause(0.28)
        } else {
            for wave in plan.paintWaves {
                guard !Task.isCancelled, !isGameOver else { return }
                if var fx = magixFX {
                    fx.highlight = wave
                    magixFX = fx
                }
                let vanishing = wave.filter { addr in
                    plan.resultGrid[addr.row][addr.col].isEmpty
                        && !run.grid[addr.row][addr.col].isEmpty
                }
                if vanishing.count >= 2 {
                    await animateDisappearance(ordered: orderedDisappearance(vanishing))
                    guard !Task.isCancelled, !isGameOver else { return }
                }
                for addr in wave {
                    let block = plan.resultGrid[addr.row][addr.col]
                    write(block, row: addr.row, col: addr.col, keepID: !block.isEmpty)
                }
                syncLiveCells()
                await pause(WatchZenRules.magixWaveDelay)
            }

            if !plan.wipe.isEmpty, plan.paintWaves.isEmpty || plan.kind == .twistx {
                if var fx = magixFX {
                    fx.highlight = plan.wipe
                    magixFX = fx
                }
                await pause(0.10)
                for addr in plan.wipe {
                    write(.empty, row: addr.row, col: addr.col)
                }
                syncLiveCells()
                await pause(0.10)
            }
        }

        adoptGrid(plan.resultGrid)
        run.score += plan.scoreDelta
        run.bombCount += plan.bombDelta
        magixFX = nil
        compactGridTowardTop()
        awardFullyClearedColumnBonuses(columnHadBlockBefore: occupancy)
        syncLiveCells()
        await pause(WatchZenRules.compactAnimationDuration)
    }

    // MARK: - Resolve

    @discardableResult
    private func resolveChainsAsync() async -> Bool {
        var rearranged = false
        while !isGameOver, !Task.isCancelled {
            let components = findWinningChainComponents()
            let winningCells: Set<WatchGridAddress> = components.reduce(into: Set()) { $0.formUnion($1) }
            guard !winningCells.isEmpty else {
                rearranged = await finishWhenNoChainsAsync() || rearranged
                return rearranged
            }

            rearranged = true
            run.chainClearWaveCount += 1
            var wavePoints = 0
            for component in components {
                wavePoints += WatchZenRules.chainClearScorePoints(
                    chainSeriesLevel: run.chainSeriesLevel,
                    groupSize: component.count
                )
            }

            let columnHadBlockBefore = occupancyByColumn()
            let ordered = orderedChainRemovalCells(from: components)
            // Le score logique attend la fin du fondu : une suspension au milieu
            // du vol ne peut pas sauver des points sans la grille qui va avec.
            publishChainSparkle(points: wavePoints, cells: ordered)
            await animateDisappearance(ordered: ordered)
            guard !Task.isCancelled, !isGameOver else {
                chainSparklePoints = 0
                return rearranged
            }
            if wavePoints > 0 {
                run.score += wavePoints
            }
            for address in winningCells {
                write(.empty, row: address.row, col: address.col)
            }
            let vanished = applyPriksAdjacentDecrement(touchingRemovedCells: winningCells)
            run.score += vanished.count * WatchZenRules.vanishedPriksBonusPoints
            compactGridTowardTop()
            awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
            run.chainSeriesLevel += 1
            syncLiveCells()
            await pause(WatchZenRules.compactAnimationDuration)
        }
        return rearranged
    }

    @discardableResult
    private func finishWhenNoChainsAsync() async -> Bool {
        run.chainSeriesLevel = 0
        guard shouldRunPostPlacementHooks else {
            refreshIncomingPreview()
            return false
        }
        shouldRunPostPlacementHooks = false
        run.moveCount += 1
        refreshIncomingPreview()
        if run.moveCount > 0, run.moveCount % 10 == 0 {
            await injectIncomingLineAnimated()
            if !isGameOver {
                _ = await resolveChainsAsync()
            }
            return true
        }
        return false
    }

    private func injectIncomingLineAnimated() async {
        guard run.nextBottomLine.count == WatchGridLayout.columnCount else { return }
        let blocked = (0..<WatchGridLayout.columnCount).filter { highestEmptyRow(inColumn: $0) == nil }
        if !blocked.isEmpty {
            triggerGameOver()
            return
        }

        let line = run.nextBottomLine
        var placements: [(row: Int, col: Int)] = []
        for col in 0..<WatchGridLayout.columnCount {
            guard let row = highestEmptyRow(inColumn: col) else {
                triggerGameOver()
                return
            }
            placements.append((row: row, col: col))
        }
        incomingPreview = nil
        var lineIDs: [UUID: Int] = [:]
        for p in placements {
            write(line[p.col], row: p.row, col: p.col)
            if let id = cellIDs[p.row][p.col] {
                lineIDs[id] = WatchGridLayout.rowCount
            }
        }
        run.nextBottomLine = WatchZenRules.randomBottomLineRow()
        refreshIncomingPreview()
        syncLiveCells(rowOverride: lineIDs)
        await pause(0.02)
        syncLiveCells()
        await pause(WatchZenRules.lineRiseAnimationDuration)
    }

    private func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        isProcessing = false
        highlightedColumn = nil
        aimedBombCell = nil
        syncLiveCells()
        Self.log.info("game_over score=\(self.run.score, privacy: .public)")
    }

    private func refreshIncomingPreview() {
        incomingPreview = (run.moveCount % 10 == 9) ? run.nextBottomLine : nil
    }

    private func advanceQueue() {
        run.p0 = run.p1
        run.p1 = run.p2
        run.p2 = WatchZenRules.randomPlayableBlock()
    }

    private func pause(_ seconds: Double) async {
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    // MARK: - Grille

    private static func emptyIDs() -> [[UUID?]] {
        Array(
            repeating: Array(repeating: UUID?.none, count: WatchGridLayout.columnCount),
            count: WatchGridLayout.rowCount
        )
    }

    /// Paillettes tout de suite. Les points restent hors de `score` jusqu’à la fin du fondu.
    private func publishChainSparkle(points: Int, cells: [WatchGridAddress]) {
        guard points > 0, !cells.isEmpty else { return }
        var sparkCells: [WatchChainSparkleCell] = []
        sparkCells.reserveCapacity(cells.count)
        for addr in cells {
            guard addr.row >= WatchGridLayout.topRowIndex,
                  addr.row < WatchGridLayout.rowCount,
                  addr.col >= 0, addr.col < WatchGridLayout.columnCount else { continue }
            if case .color(let name) = run.grid[addr.row][addr.col] {
                sparkCells.append(WatchChainSparkleCell(row: addr.row, col: addr.col, colorName: name))
            }
        }
        guard !sparkCells.isEmpty else { return }
        chainSparkleToken += 1
        chainSparklePoints += points
        chainSparkle = WatchChainSparkleRequest(
            token: chainSparkleToken,
            points: points,
            cells: sparkCells
        )
    }

    /// Fondu décalé, grille encore intacte. L’appelant retire les cases ensuite.
    private func animateDisappearance(ordered addresses: [WatchGridAddress]) async {
        var clearing: [UUID: Int] = [:]
        var count = 0
        for addr in addresses {
            guard addr.row >= WatchGridLayout.topRowIndex,
                  addr.row < WatchGridLayout.rowCount,
                  addr.col >= 0, addr.col < WatchGridLayout.columnCount else { continue }
            guard !run.grid[addr.row][addr.col].isEmpty else { continue }
            guard let id = cellIDs[addr.row][addr.col] else { continue }
            clearing[id] = count
            count += 1
        }
        guard count > 0 else { return }
        syncLiveCells(clearingIndex: clearing)
        await pause(WatchZenRules.chainClearTail(count: count))
    }

    /// Wipe Magix : balayage ligne / colonne. Les doublons sautent.
    private func orderedDisappearance(_ addresses: [WatchGridAddress]) -> [WatchGridAddress] {
        var seen = Set<WatchGridAddress>()
        var unique: [WatchGridAddress] = []
        for addr in addresses where seen.insert(addr).inserted {
            unique.append(addr)
        }
        return unique.sorted { a, b in
            if a.row != b.row { return a.row < b.row }
            return a.col < b.col
        }
    }

    /// Chaque composante à part, cases en (ligne, colonne) — même ordre que l’iPhone.
    private func orderedChainRemovalCells(from components: [Set<WatchGridAddress>]) -> [WatchGridAddress] {
        components.flatMap { cells in
            cells.sorted { a, b in
                if a.row != b.row { return a.row < b.row }
                return a.col < b.col
            }
        }
    }

    private func syncLiveCells(
        rowOverride: [UUID: Int] = [:],
        clearingIndex: [UUID: Int] = [:]
    ) {
        var cells: [WatchLiveCell] = []
        for row in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for col in 0..<WatchGridLayout.columnCount {
                let block = run.grid[row][col]
                guard !block.isEmpty else { continue }
                if cellIDs[row][col] == nil {
                    cellIDs[row][col] = UUID()
                }
                let id = cellIDs[row][col]!
                let displayRow = rowOverride[id] ?? row
                cells.append(WatchLiveCell(
                    id: id,
                    row: displayRow,
                    col: col,
                    block: block,
                    clearingIndex: clearingIndex[id]
                ))
            }
        }
        liveCells = cells
    }

    private func adoptGrid(_ newGrid: [[WatchBlockType]]) {
        var ids = cellIDs
        for row in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for col in 0..<WatchGridLayout.columnCount {
                let next = newGrid[row][col]
                if next.isEmpty {
                    ids[row][col] = nil
                } else if run.grid[row][col].isEmpty {
                    ids[row][col] = UUID()
                }
            }
        }
        run.grid = newGrid
        cellIDs = ids
    }

    private func applyRowShifts(_ shifts: [(row: Int, delta: Int)]) {
        var g = run.grid
        var ids = cellIDs
        let cols = WatchGridLayout.columnCount
        for (row, delta) in shifts {
            let oldG = g[row]
            let oldI = ids[row]
            var newG = Array(repeating: WatchBlockType.empty, count: cols)
            var newI = Array(repeating: UUID?.none, count: cols)
            for c in 0..<cols {
                let newC = ((c + delta) % cols + cols) % cols
                newG[newC] = oldG[c]
                newI[newC] = oldI[c]
            }
            g[row] = newG
            ids[row] = newI
        }
        run.grid = g
        cellIDs = ids
    }

    private func write(_ block: WatchBlockType, row: Int, col: Int, keepID: Bool = false) {
        var g = run.grid
        g[row][col] = block
        run.grid = g
        if block.isEmpty {
            cellIDs[row][col] = nil
        } else if !keepID || cellIDs[row][col] == nil {
            cellIDs[row][col] = UUID()
        }
    }

    func highestEmptyRow(inColumn columnIndex: Int) -> Int? {
        guard columnIndex >= 0, columnIndex < WatchGridLayout.columnCount else { return nil }
        for row in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            if run.grid[row][columnIndex].isEmpty { return row }
        }
        return nil
    }

    @discardableResult
    private func compactGridTowardTop() -> Bool {
        var g = run.grid
        var ids = cellIDs
        var didMove = false
        for col in 0..<WatchGridLayout.columnCount {
            var blocks: [WatchBlockType] = []
            var blockIDs: [UUID] = []
            var fromRows: [Int] = []
            for row in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
                let cell = g[row][col]
                if !cell.isEmpty {
                    blocks.append(cell)
                    blockIDs.append(ids[row][col] ?? UUID())
                    fromRows.append(row)
                }
            }
            var writeRow = WatchGridLayout.topRowIndex
            for i in 0..<blocks.count {
                if writeRow != fromRows[i] { didMove = true }
                g[writeRow][col] = blocks[i]
                ids[writeRow][col] = blockIDs[i]
                writeRow += 1
            }
            while writeRow < WatchGridLayout.rowCount {
                g[writeRow][col] = .empty
                ids[writeRow][col] = nil
                writeRow += 1
            }
        }
        run.grid = g
        cellIDs = ids
        return didMove
    }

    private func occupancyByColumn() -> [Bool] {
        (0..<WatchGridLayout.columnCount).map { col in
            (WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount).contains { !run.grid[$0][col].isEmpty }
        }
    }

    private func isPlayableGridCompletelyEmpty() -> Bool {
        (WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount).allSatisfy { row in
            (0..<WatchGridLayout.columnCount).allSatisfy { col in run.grid[row][col].isEmpty }
        }
    }

    private func awardFullyClearedColumnBonuses(columnHadBlockBefore: [Bool]) {
        let hadAnyBlockBefore = columnHadBlockBefore.contains(true)
        for col in 0..<WatchGridLayout.columnCount {
            let nowEmpty = (WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount)
                .allSatisfy { run.grid[$0][col].isEmpty }
            if columnHadBlockBefore[col], nowEmpty {
                run.score += WatchZenRules.clearedColumnBonusPoints
            }
        }
        if hadAnyBlockBefore, isPlayableGridCompletelyEmpty() {
            run.score += WatchZenRules.fullyClearedBoardBonusPoints
        }
    }

    private func findWinningChainComponents() -> [Set<WatchGridAddress>] {
        var globallyVisited = Set<WatchGridAddress>()
        var components: [Set<WatchGridAddress>] = []
        for row in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for col in 0..<WatchGridLayout.columnCount {
                let start = WatchGridAddress(row: row, col: col)
                guard !globallyVisited.contains(start) else { continue }
                guard case .color(let colorName) = run.grid[row][col] else { continue }
                let component = collectColorComponent8(
                    start: start,
                    colorName: colorName,
                    globallyVisited: &globallyVisited
                )
                guard component.count >= 5 else { continue }
                components.append(component)
            }
        }
        return components
    }

    private func collectColorComponent8(
        start: WatchGridAddress,
        colorName: String,
        globallyVisited: inout Set<WatchGridAddress>
    ) -> Set<WatchGridAddress> {
        var stack: [WatchGridAddress] = [start]
        var component = Set<WatchGridAddress>()
        while let current = stack.popLast() {
            if globallyVisited.contains(current) { continue }
            guard case .color(let name) = run.grid[current.row][current.col], name == colorName else { continue }
            globallyVisited.insert(current)
            component.insert(current)
            for delta in WatchZenRules.neighborDeltas8 {
                let nr = current.row + delta.dr
                let nc = current.col + delta.dc
                guard nr >= WatchGridLayout.topRowIndex, nr < WatchGridLayout.rowCount,
                      nc >= 0, nc < WatchGridLayout.columnCount else { continue }
                let neighbor = WatchGridAddress(row: nr, col: nc)
                if globallyVisited.contains(neighbor) { continue }
                guard case .color(let neighborName) = run.grid[nr][nc], neighborName == colorName else { continue }
                stack.append(neighbor)
            }
        }
        return component
    }

    private func applyPriksAdjacentDecrement(touchingRemovedCells: Set<WatchGridAddress>) -> Set<WatchGridAddress> {
        guard !touchingRemovedCells.isEmpty else { return [] }
        var vanished = Set<WatchGridAddress>()
        for row in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            for col in 0..<WatchGridLayout.columnCount {
                guard case .priks(let remaining) = run.grid[row][col], remaining > 0 else { continue }
                var touches = false
                for delta in WatchZenRules.neighborDeltas8 {
                    let nr = row + delta.dr
                    let nc = col + delta.dc
                    guard nr >= WatchGridLayout.topRowIndex, nr < WatchGridLayout.rowCount,
                          nc >= 0, nc < WatchGridLayout.columnCount else { continue }
                    if touchingRemovedCells.contains(WatchGridAddress(row: nr, col: nc)) {
                        touches = true
                        break
                    }
                }
                guard touches else { continue }
                let next = remaining - 1
                if next <= 0 {
                    write(.empty, row: row, col: col)
                    vanished.insert(WatchGridAddress(row: row, col: col))
                } else {
                    write(.priks(next), row: row, col: col, keepID: true)
                }
            }
        }
        return vanished
    }
}

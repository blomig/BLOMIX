//
//  BlomixDailyGhost.swift
//  Blomix
//
//  Fantôme du Défi du jour : joue la seed UTC en mémoire (lookahead 3
//  `computeOptimal`, Magix visés, bombes souples / Brix, sans timer).
//  File `.utility` dédiée — jamais `analyzerQueue`, jamais GameScene.
//

import Foundation

// MARK: - Affichage hub

enum BlomixDailyGhostDisplay: Equatable, Sendable {
    case computing
    case ready(score: Int)
}

// MARK: - Contrôleur (pause / cache / file)

private final class BlomixDailyGhostPauseFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false

    func pause() { lock.lock(); paused = true; lock.unlock() }
    func clear() { lock.lock(); paused = false; lock.unlock() }
    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }
}

@MainActor
final class BlomixDailyGhostController {

    static let shared = BlomixDailyGhostController()

    /// Bump si la sim Magix ou le scoring change (invalide le cache).
    static let engineVersion = 5

    private static let cacheDayKey = "blomix_daily_ghost_day"
    private static let cacheScoreKey = "blomix_daily_ghost_score"
    private static let cacheVerKey = "blomix_daily_ghost_ver"

    private let queue = DispatchQueue(label: "blomix.dailyGhost", qos: .utility)
    private let pauseFlag = BlomixDailyGhostPauseFlag()

    private(set) var display: BlomixDailyGhostDisplay = .computing
    var onDisplayChange: ((BlomixDailyGhostDisplay) -> Void)?

    private var isWorkerRunning = false
    private var isPausedForGameplay = false
    private var hubHasRequested = false
    private var pausedEngine: BlomixDailyGhostEngine?
    private var didInstallObservers = false

    private init() {
        installObserversIfNeeded()
    }

    func hubAppeared() {
        installObserversIfNeeded()
        hubHasRequested = true
        startOrResume()
    }

    func pauseForGameplay() {
        isPausedForGameplay = true
        pauseFlag.pause()
    }

    // MARK: - Cycle de vie

    private func installObserversIfNeeded() {
        guard !didInstallObservers else { return }
        didInstallObservers = true
        NotificationCenter.default.addObserver(
            forName: .blomixDidBeginGameplayMatch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseForGameplay()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .blomixDidPresentStartScreen,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeAfterGameplayIfNeeded()
            }
        }
    }

    private func resumeAfterGameplayIfNeeded() {
        isPausedForGameplay = false
        pauseFlag.clear()
        guard hubHasRequested || pausedEngine != nil else { return }
        startOrResume()
    }

    private func startOrResume() {
        let day = BlomixDailySeed.utcDayString()
        if let cached = Self.cachedScore(forDay: day) {
            publish(.ready(score: cached))
            pausedEngine = nil
            return
        }
        guard !isPausedForGameplay else {
            publish(.computing)
            return
        }
        if isWorkerRunning { return }
        publish(.computing)

        let seed = BlomixDailySeed.seed(forDay: day)
        var engine = pausedEngine
        if engine == nil || engine?.utcDay != day || engine?.seed != seed {
            engine = BlomixDailyGhostEngine.start(day: day, seed: seed)
        }
        pausedEngine = nil
        guard let started = engine else { return }

        pauseFlag.clear()
        isWorkerRunning = true
        let startedAt = CFAbsoluteTimeGetCurrent()
        let flag = pauseFlag
        queue.async { [weak self] in
            var local = started
            let outcome = local.playUntilStop { flag.isPaused }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWorkerRunning = false
                switch outcome {
                case .paused:
                    self.pausedEngine = local
                    if self.isPausedForGameplay {
                        self.publish(.computing)
                    } else {
                        self.startOrResume()
                    }
                case .finished(let score, let moves):
                    self.pausedEngine = nil
                    Self.storeCache(day: day, score: score)
                    self.publish(.ready(score: score))
                    #if DEBUG
                    let ms = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                    print("[DailyGhost] \(day) score=\(score) moves=\(moves) \(ms)ms")
                    #endif
                }
            }
        }
    }

    private func publish(_ display: BlomixDailyGhostDisplay) {
        self.display = display
        onDisplayChange?(display)
    }

    private static func cachedScore(forDay day: String) -> Int? {
        let d = UserDefaults.standard
        guard d.integer(forKey: cacheVerKey) == engineVersion,
              d.string(forKey: cacheDayKey) == day,
              d.object(forKey: cacheScoreKey) != nil else { return nil }
        return d.integer(forKey: cacheScoreKey)
    }

    private static func storeCache(day: String, score: Int) {
        let d = UserDefaults.standard
        d.set(engineVersion, forKey: cacheVerKey)
        d.set(day, forKey: cacheDayKey)
        d.set(score, forKey: cacheScoreKey)
    }
}

// MARK: - Moteur (état RAM, copiable pour pause)

private struct Addr: Hashable {
    let row: Int
    let col: Int
}

struct BlomixDailyGhostEngine: Sendable {
    let utcDay: String
    let seed: UInt64

    private var file: BlomixDailyFileRNG
    private var grid: [[BlockType]]
    private var p0: BlockType
    private var p1: BlockType
    private var p2: BlockType
    private var nextLine: [BlockType]
    private var moveCount: Int
    private var score: Int
    private var chainSeriesLevel: Int
    private var stageIndex: Int
    private var bombCount: Int
    private var movesPlayed: Int

    private static let rows = 8
    private static let cols = 8
    private static let maxMoves = 500
    private static let palette = ["red", "blue", "green", "yellow", "purple", "orange"]
    private static let stageMins = [0, 250, 1000, 2000, 3000, 5000]
    private static let stageMuls = [1, 2, 3, 4, 5, 6]
    private static let deltas8: [(dr: Int, dc: Int)] = [
        (-1, -1), (-1, 0), (-1, 1),
        (0, -1), (0, 1),
        (1, -1), (1, 0), (1, 1),
    ]

    static func start(day: String, seed: UInt64) -> BlomixDailyGhostEngine {
        var file = BlomixDailyFileRNG(seed: seed)
        let p0 = drawPlayable(using: &file)
        let p1 = drawPlayable(using: &file)
        let p2 = drawPlayable(using: &file)
        let line = drawColorLine(using: &file)
        return BlomixDailyGhostEngine(
            utcDay: day,
            seed: seed,
            file: file,
            grid: Array(repeating: Array(repeating: .empty, count: cols), count: rows),
            p0: p0, p1: p1, p2: p2,
            nextLine: line,
            moveCount: 0,
            score: 0,
            chainSeriesLevel: 0,
            stageIndex: 0,
            bombCount: 5,
            movesPlayed: 0
        )
    }

    enum Stop: Sendable {
        case paused
        case finished(score: Int, moves: Int)
    }

    /// Joue jusqu’au game over, ou s’arrête entre deux coups si `shouldPause`.
    mutating func playUntilStop(shouldPause: @escaping @Sendable () -> Bool) -> Stop {
        while movesPlayed < Self.maxMoves {
            if shouldPause() { return .paused }
            switch playOneMove() {
            case .continuePlaying:
                continue
            case .gameOver:
                return .finished(score: score, moves: movesPlayed)
            }
        }
        return .finished(score: score, moves: movesPlayed)
    }

    private enum MoveOutcome {
        case continuePlaying
        case gameOver
    }

    private mutating func playOneMove() -> MoveOutcome {
        // Magix : posé dès qu’il est P0 — pas de bombe à sa place.
        // Blox / Brix : bombe souple si le meilleur drop ne soulage pas un plafond.
        if bombCount > 0, !isMagixP0, shouldSoftBomb() {
            _ = detonateBestBomb()
        }
        while !hasAnyLanding(), bombCount > 0 {
            if !detonateBestBomb() { break }
        }
        guard let column = pickColumn() else { return .gameOver }
        let placed = p0
        p0 = p1
        p1 = p2
        p2 = Self.drawPlayable(using: &file)

        guard let row = landingRow(column) else { return .gameOver }
        grid[row][column] = placed
        movesPlayed += 1

        if case .magix(let kind) = placed {
            applyMagix(kind, at: Addr(row: row, col: column))
        }
        if resolveAllScoring(runPlacementHooks: true) {
            return .gameOver
        }
        return .continuePlaying
    }

    private func pickColumn() -> Int? {
        if case .magix(let kind) = p0 {
            return pickMagixColumn(kind)
        }
        // Ligne des 10 toujours connue du fantôme : le lookahead l’injecte
        // à la ply qui franchit la décennie (le joueur, lui, ne la passe que si visible).
        let result = BlomixMoveAnalyzer.computeOptimal(
            grid: grid,
            piece0: p0,
            piece1: p1,
            piece2: p2,
            moveCount: moveCount,
            pendingLine: nextLine
        )
        var bestCol: Int?
        var bestScore = Int.min
        for c in 0..<Self.cols {
            guard let s = result.scorePerColumn[c] else { continue }
            if s > bestScore {
                bestScore = s
                bestCol = c
            }
        }
        return bestCol ?? shortestThenLeftColumn()
    }

    private func shortestThenLeftColumn() -> Int? {
        var bestCol: Int?
        var bestHeight = Int.max
        for c in 0..<Self.cols {
            guard let h = landingRow(c) else { continue }
            if h < bestHeight {
                bestHeight = h
                bestCol = c
            }
        }
        return bestCol
    }

    /// CHROMAX : colonne jouable la plus remplie (Blox + Brix), puis gauche.
    private func fullestThenLeftColumn() -> Int? {
        var bestCol: Int?
        var bestFill = -1
        for c in 0..<Self.cols {
            guard landingRow(c) != nil else { continue }
            let fill = columnOccupiedCount(c)
            if fill > bestFill {
                bestFill = fill
                bestCol = c
            }
        }
        return bestCol ?? shortestThenLeftColumn()
    }

    private func columnOccupiedCount(_ column: Int) -> Int {
        var n = 0
        for r in 0..<Self.rows where grid[r][column] != .empty { n += 1 }
        return n
    }

    private func brixCount(in grid: [[BlockType]]? = nil) -> Int {
        let g = grid ?? self.grid
        var n = 0
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if case .priks = g[r][c] { n += 1 }
            }
        }
        return n
    }

    /// CROSSX / SLASHX / BOMBX / … : simule les 8 atterrissages, garde
    /// le plus de points Arcade, puis le plus de Brix enlevés, puis le `maxH` le plus bas.
    private func pickMagixColumn(_ kind: MagixKind) -> Int? {
        if kind == .chromax {
            return fullestThenLeftColumn()
        }
        let scoreBefore = score
        let brixBefore = brixCount()
        var bestCol: Int?
        var bestDelta = Int.min
        var bestBrix = -1
        var bestH = Int.max
        for c in 0..<Self.cols {
            guard landingRow(c) != nil else { continue }
            var trial = self
            guard trial.playMagixTrial(column: c) else { continue }
            let delta = trial.score - scoreBefore
            let brixRemoved = brixBefore - trial.brixCount()
            let h = trial.maxHeight()
            let better: Bool
            if let current = bestCol {
                better = delta > bestDelta
                    || (delta == bestDelta && brixRemoved > bestBrix)
                    || (delta == bestDelta && brixRemoved == bestBrix && h < bestH)
                    || (delta == bestDelta && brixRemoved == bestBrix && h == bestH && c < current)
            } else {
                better = true
            }
            if better {
                bestDelta = delta
                bestBrix = brixRemoved
                bestH = h
                bestCol = c
            }
        }
        return bestCol ?? shortestThenLeftColumn()
    }

    /// Pose le Magix P0 dans `column` et résout (copie d’essai — ne touche pas `self`).
    private mutating func playMagixTrial(column: Int) -> Bool {
        guard case .magix(let kind) = p0 else { return false }
        guard let row = landingRow(column) else { return false }
        grid[row][column] = p0
        applyMagix(kind, at: Addr(row: row, col: column))
        return !resolveAllScoring(runPlacementHooks: true)
    }

    private func landingRow(_ column: Int) -> Int? {
        BlomixMoveAnalyzer.landingRow(in: grid, column: column)
    }

    private var isMagixP0: Bool {
        if case .magix = p0 { return true }
        return false
    }

    private func hasAnyLanding() -> Bool {
        (0..<Self.cols).contains { landingRow($0) != nil }
    }

    private func columnHeight(_ column: Int, in grid: [[BlockType]]? = nil) -> Int {
        let g = grid ?? self.grid
        return BlomixMoveAnalyzer.landingRow(in: g, column: column) ?? Self.rows
    }

    private func maxHeight(in grid: [[BlockType]]? = nil) -> Int {
        (0..<Self.cols).map { columnHeight($0, in: grid) }.max() ?? 0
    }

    private func occupiedCount(in grid: [[BlockType]]) -> Int {
        var n = 0
        for r in 0..<Self.rows {
            for c in 0..<Self.cols where grid[r][c] != .empty { n += 1 }
        }
        return n
    }

    /// Plateau haut et le meilleur drop n’abaisse pas `maxH` et n’efface presque rien.
    private func shouldSoftBomb() -> Bool {
        let h = maxHeight()
        guard h >= 7 else { return false }
        guard let col = pickColumn() else { return false }
        guard let (after, _) = BlomixMoveAnalyzer.simulateDrop(
            grid: grid, block: p0, column: col,
            moveCount: moveCount, pendingLine: nextLine
        ) else { return false }
        let newH = maxHeight(in: after)
        let net = occupiedCount(in: grid) - occupiedCount(in: after)
        return newH >= h && net <= 1
    }

    /// Explosion 3×3 + croix de stage, centrée pour casser le plus dans les colonnes les plus hautes.
    @discardableResult
    private mutating func detonateBestBomb() -> Bool {
        guard bombCount > 0, let center = bestBombCenter() else { return false }
        bombCount -= 1
        let blast = bombAffectedCells(centerRow: center.row, centerCol: center.col)
        let had = columnOccupiedFlags()
        var brixHit = 0
        var any = false
        for a in blast {
            switch grid[a.row][a.col] {
            case .empty:
                continue
            case .priks:
                brixHit += 1
                any = true
                grid[a.row][a.col] = .empty
            default:
                any = true
                grid[a.row][a.col] = .empty
            }
        }
        guard any else {
            bombCount += 1
            return false
        }
        addScore(10)
        addScore(brixHit * 20)
        compactTowardTop()
        awardColumnAndBoardBonuses(hadBlockBefore: had)
        chainSeriesLevel = 1
        _ = resolveAllScoring(runPlacementHooks: false)
        refreshStage()
        return true
    }

    private func bestBombCenter() -> Addr? {
        let heights = (0..<Self.cols).map { columnHeight($0) }
        let maxH = heights.max() ?? 0
        let tall = Set((0..<Self.cols).filter { heights[$0] == maxH })
        var bestBrix = -1
        var bestTall = -1
        var bestTotal = -1
        var best: Addr?
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                let blast = bombAffectedCells(centerRow: r, centerCol: c)
                guard blast.contains(where: { tall.contains($0.col) }) else { continue }
                var brixHit = 0
                var tallBroken = 0
                var total = 0
                for a in blast {
                    switch grid[a.row][a.col] {
                    case .empty:
                        continue
                    case .priks:
                        brixHit += 1
                        total += 1
                        if tall.contains(a.col) { tallBroken += 1 }
                    default:
                        total += 1
                        if tall.contains(a.col) { tallBroken += 1 }
                    }
                }
                guard total > 0 else { continue }
                let better: Bool
                if let current = best {
                    better = brixHit > bestBrix
                        || (brixHit == bestBrix && tallBroken > bestTall)
                        || (brixHit == bestBrix && tallBroken == bestTall && total > bestTotal)
                        || (brixHit == bestBrix && tallBroken == bestTall && total == bestTotal
                            && (c < current.col || (c == current.col && r < current.row)))
                } else {
                    better = true
                }
                if better {
                    bestBrix = brixHit
                    bestTall = tallBroken
                    bestTotal = total
                    best = Addr(row: r, col: c)
                }
            }
        }
        return best
    }

    /// Même zone que `GameScene.bombAffectedCells` : 3×3 + bras cardinaux de longueur `stageIndex`.
    private func bombAffectedCells(centerRow: Int, centerCol: Int) -> [Addr] {
        var result: [Addr] = []
        for dr in -1...1 {
            for dc in -1...1 {
                let r = centerRow + dr, c = centerCol + dc
                guard r >= 0, r < Self.rows, c >= 0, c < Self.cols else { continue }
                result.append(Addr(row: r, col: c))
            }
        }
        let arm = stageIndex
        guard arm > 0 else { return result }
        let cardinals = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for (dr, dc) in cardinals {
            for step in 2...(1 + arm) {
                let r = centerRow + dr * step, c = centerCol + dc * step
                guard r >= 0, r < Self.rows, c >= 0, c < Self.cols else { break }
                result.append(Addr(row: r, col: c))
            }
        }
        return result
    }

    // MARK: File

    private static func drawPlayable(using rng: inout BlomixDailyFileRNG) -> BlockType {
        let r = rng.nextUnitDouble()
        if r < MagixRules.spawnProbability {
            var cumul = 0.0
            var chosen: MagixKind = .chromax
            for entry in MagixRules.spawnProbabilityByKind {
                cumul += entry.p
                if r < cumul { chosen = entry.kind; break }
            }
            return .magix(chosen)
        }
        if r < MagixRules.spawnProbability + PriksRules.spawnProbability {
            return .priks(PriksRules.initialHitsRemaining)
        }
        return .color(rng.pick(palette) ?? "red")
    }

    private static func drawColorLine(using rng: inout BlomixDailyFileRNG) -> [BlockType] {
        (0..<cols).map { _ in .color(rng.pick(palette) ?? "red") }
    }

    // MARK: Scoring Arcade

    private var stageMul: Int { Self.stageMuls[min(stageIndex, Self.stageMuls.count - 1)] }

    private mutating func addScore(_ base: Int) {
        guard base > 0 else { return }
        score += base * stageMul
    }

    private mutating func refreshStage() {
        var target = 0
        for (i, minScore) in Self.stageMins.enumerated() where score >= minScore {
            target = i
        }
        stageIndex = target
    }

    private static func chainPoints(level: Int, groupSize: Int) -> Int {
        let base: Int
        switch groupSize {
        case ..<6:  base = 5
        case 6:     base = 7
        case 7:     base = 10
        case 8:     base = 13
        case 9:     base = 15
        default:    base = 20
        }
        return base + level * 10
    }

    /// `true` = game over (ligne des 10 impossible).
    private mutating func resolveAllScoring(runPlacementHooks: Bool) -> Bool {
        var hooks = runPlacementHooks
        var iterations = 0
        while iterations < 64 {
            iterations += 1
            let components = findChainComponents()
            if components.isEmpty {
                chainSeriesLevel = 0
                if hooks {
                    hooks = false
                    moveCount += 1
                    refreshStage()
                    if moveCount > 0, moveCount % 10 == 0 {
                        if injectLineIsFatal() { return true }
                        injectLine()
                        continue
                    }
                }
                return false
            }
            let hadBlock = columnOccupiedFlags()
            var cleared = Set<Addr>()
            for comp in components {
                addScore(Self.chainPoints(level: chainSeriesLevel, groupSize: comp.count))
                cleared.formUnion(comp)
            }
            for a in cleared { grid[a.row][a.col] = .empty }
            let vanished = decrementPriks(touching: cleared)
            addScore(vanished * 20)
            compactTowardTop()
            awardColumnAndBoardBonuses(hadBlockBefore: hadBlock)
            chainSeriesLevel += 1
        }
        return false
    }

    private func injectLineIsFatal() -> Bool {
        (0..<Self.cols).contains { landingRow($0) == nil }
    }

    private mutating func injectLine() {
        let line = nextLine
        nextLine = Self.drawColorLine(using: &file)
        for c in 0..<Self.cols {
            if let r = landingRow(c), c < line.count {
                grid[r][c] = line[c]
            }
        }
    }

    private mutating func afterMagixCompact(hadBlockBefore: [Bool]) {
        compactTowardTop()
        awardColumnAndBoardBonuses(hadBlockBefore: hadBlockBefore)
        chainSeriesLevel += 1
    }

    private func columnOccupiedFlags() -> [Bool] {
        (0..<Self.cols).map { c in
            (0..<Self.rows).contains { grid[$0][c] != .empty }
        }
    }

    private mutating func awardColumnAndBoardBonuses(hadBlockBefore: [Bool]) {
        let hadAny = hadBlockBefore.contains(true)
        for c in 0..<Self.cols {
            let emptyNow = (0..<Self.rows).allSatisfy { grid[$0][c] == .empty }
            if hadBlockBefore[c], emptyNow {
                addScore(10)
            }
        }
        guard hadAny else { return }
        let boardEmpty = (0..<Self.rows).allSatisfy { r in
            (0..<Self.cols).allSatisfy { grid[r][$0] == .empty }
        }
        if boardEmpty { addScore(500) }
    }

    // MARK: Grille

    private mutating func compactTowardTop() {
        for c in 0..<Self.cols {
            let blocks = (0..<Self.rows).compactMap { grid[$0][c] == .empty ? nil : grid[$0][c] }
            for r in 0..<Self.rows {
                grid[r][c] = r < blocks.count ? blocks[r] : .empty
            }
        }
    }

    private func findChainComponents() -> [Set<Addr>] {
        var visited = Set<Addr>()
        var components: [Set<Addr>] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                let a = Addr(row: r, col: c)
                guard !visited.contains(a) else { continue }
                guard case .color(let name) = grid[r][c] else { continue }
                let comp = flood8(start: a, colorName: name, visited: &visited)
                if comp.count >= 5 { components.append(comp) }
            }
        }
        return components
    }

    private func flood8(start: Addr, colorName: String, visited: inout Set<Addr>) -> Set<Addr> {
        var stack = [start]
        var component = Set<Addr>()
        while let cur = stack.popLast() {
            guard !visited.contains(cur) else { continue }
            guard case .color(let n) = grid[cur.row][cur.col], n == colorName else { continue }
            visited.insert(cur)
            component.insert(cur)
            for d in Self.deltas8 {
                let nr = cur.row + d.dr, nc = cur.col + d.dc
                guard nr >= 0, nr < Self.rows, nc >= 0, nc < Self.cols else { continue }
                let nb = Addr(row: nr, col: nc)
                guard !visited.contains(nb) else { continue }
                stack.append(nb)
            }
        }
        return component
    }

    private mutating func decrementPriks(touching removed: Set<Addr>) -> Int {
        guard !removed.isEmpty else { return 0 }
        var vanished = 0
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                guard case .priks(let n) = grid[r][c], n > 0 else { continue }
                let touches = Self.deltas8.contains { d in
                    let nr = r + d.dr, nc = c + d.dc
                    return nr >= 0 && nr < Self.rows && nc >= 0 && nc < Self.cols
                        && removed.contains(Addr(row: nr, col: nc))
                }
                if touches {
                    if n <= 1 {
                        grid[r][c] = .empty
                        vanished += 1
                    } else {
                        grid[r][c] = .priks(n - 1)
                    }
                }
            }
        }
        return vanished
    }

    private func effectRNG(event: String, at cell: Addr) -> BlomixDailyEffectRNG {
        BlomixDailyEffectRNG(
            daySeed: seed,
            event: event,
            moveCount: moveCount,
            row: cell.row,
            col: cell.col
        )
    }

    private func presentColors() -> [String] {
        Self.palette.filter { name in
            (0..<Self.rows).contains { r in
                (0..<Self.cols).contains { c in
                    if case .color(let n) = grid[r][c] { return n == name }
                    return false
                }
            }
        }
    }

    // MARK: Magix

    private mutating func applyMagix(_ kind: MagixKind, at cell: Addr) {
        switch kind {
        case .chromax:  applyChromax(at: cell)
        case .brixed:   applyBrixed(at: cell)
        case .crosx:    applyCrosx(at: cell)
        case .slashx:   applySlashx(at: cell)
        case .scrumblx: applyScrumblx(at: cell)
        case .colorx:   applyColorx(at: cell)
        case .cleanx:   applyCleanx(at: cell)
        case .twistx:   applyTwistx(at: cell)
        case .bombx:    applyBombx(at: cell)
        }
    }

    private mutating func applyColorx(at cell: Addr) {
        let had = columnOccupiedFlags()
        grid[cell.row][cell.col] = .empty
        let present = presentColors()
        let pool = present.isEmpty ? Self.palette : present
        var rng = effectRNG(event: "colorx", at: cell)
        let finalColor = rng.pick(pool) ?? pool.first ?? "red"
        var targets: [Addr] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if case .color(let name) = grid[r][c], name == finalColor {
                    targets.append(Addr(row: r, col: c))
                    grid[r][c] = .empty
                }
            }
        }
        if !targets.isEmpty {
            addScore(Self.chainPoints(level: chainSeriesLevel, groupSize: targets.count))
        }
        afterMagixCompact(hadBlockBefore: had)
    }

    private mutating func applyCleanx(at cell: Addr) {
        let had = columnOccupiedFlags()
        var cleared = 0
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if r == cell.row, c == cell.col { continue }
                if grid[r][c] != .empty {
                    grid[r][c] = .empty
                    cleared += 1
                }
            }
        }
        grid[cell.row][cell.col] = .priks(max(1, cleared))
        addScore(200)
        afterMagixCompact(hadBlockBefore: had)
    }

    private mutating func applyTwistx(at cell: Addr) {
        grid[cell.row][cell.col] = .empty
        let present = presentColors()
        var rng = effectRNG(event: "twistx", at: cell)
        guard let chosen = rng.pick(present) ?? present.first else { return }
        var minPriks = Int.max
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if case .priks(let n) = grid[r][c] { minPriks = min(minPriks, n) }
            }
        }
        let priksValue = (minPriks == Int.max) ? 3 : minPriks
        var colorCells: [Addr] = []
        var priksCells: [Addr] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                switch grid[r][c] {
                case .color(let n) where n == chosen: colorCells.append(Addr(row: r, col: c))
                case .priks:                          priksCells.append(Addr(row: r, col: c))
                default: break
                }
            }
        }
        for a in colorCells { grid[a.row][a.col] = .priks(priksValue) }
        for a in priksCells { grid[a.row][a.col] = .color(chosen) }
    }

    private mutating func applyChromax(at start: Addr) {
        var rng = effectRNG(event: "chromax", at: start)
        let color = rng.pick(Self.palette) ?? "red"
        var path: [Addr] = [start]
        var visited: Set<Addr> = [start]
        var current = start
        while path.count < MagixRules.chromaxPathLength {
            let candidates = Self.deltas8.compactMap { d -> Addr? in
                let nr = current.row + d.dr, nc = current.col + d.dc
                guard nr >= 0, nr < Self.rows, nc >= 0, nc < Self.cols else { return nil }
                let addr = Addr(row: nr, col: nc)
                guard !visited.contains(addr), grid[nr][nc] != .empty else { return nil }
                return addr
            }
            guard !candidates.isEmpty else { break }
            let next = rng.pick(candidates) ?? candidates[0]
            path.append(next)
            visited.insert(next)
            current = next
        }
        for a in path { grid[a.row][a.col] = .color(color) }
    }

    private mutating func applyBrixed(at cell: Addr) {
        let had = columnOccupiedFlags()
        grid[cell.row][cell.col] = .priks(MagixRules.brixedInitialHits)
        var vanished = 0
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                if r == cell.row, c == cell.col { continue }
                if case .priks = grid[r][c] {
                    grid[r][c] = .empty
                    vanished += 1
                }
            }
        }
        addScore(vanished * 20)
        afterMagixCompact(hadBlockBefore: had)
    }

    private mutating func applyCrosx(at cell: Addr) {
        var cells: [Addr] = []
        for c in 0..<Self.cols {
            switch grid[cell.row][c] {
            case .color, .priks: cells.append(Addr(row: cell.row, col: c))
            default: break
            }
        }
        for r in 0..<Self.rows {
            if r == cell.row { continue }
            switch grid[r][cell.col] {
            case .color, .priks: cells.append(Addr(row: r, col: cell.col))
            default: break
            }
        }
        paintAxis(at: cell, cells: cells)
    }

    private mutating func applySlashx(at cell: Addr) {
        var cells: [Addr] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                guard abs(r - cell.row) == abs(c - cell.col) else { continue }
                switch grid[r][c] {
                case .color, .priks: cells.append(Addr(row: r, col: c))
                default: break
                }
            }
        }
        paintAxis(at: cell, cells: cells)
    }

    private mutating func paintAxis(at cell: Addr, cells: [Addr]) {
        var rng = effectRNG(event: "axis_paint", at: cell)
        let color = rng.pick(Self.palette) ?? "red"
        var paint = cells
        if !paint.contains(cell) { paint.append(cell) }
        for a in paint { grid[a.row][a.col] = .color(color) }
    }

    private mutating func applyBombx(at cell: Addr) {
        var rng = effectRNG(event: "bombx", at: cell)
        let color = rng.pick(Self.palette) ?? "red"
        let rank0 = [cell]
        let rank1 = occupiedNeighbors(of: cell)
        var rank2: [Addr] = []
        for n in rank1 {
            let neighbors = occupiedNeighbors(of: n)
            if let s = rng.pick(neighbors) { rank2.append(s) }
        }
        var rank3: [Addr] = []
        for s in rank2 {
            let neighbors = occupiedNeighbors(of: s)
            if let t = rng.pick(neighbors) { rank3.append(t) }
        }
        var painted = Set(rank0 + rank1 + rank2 + rank3)
        painted.insert(cell)
        for a in painted { grid[a.row][a.col] = .color(color) }
        bombCount += 1
    }

    private func occupiedNeighbors(of addr: Addr) -> [Addr] {
        var out: [Addr] = []
        for d in Self.deltas8 {
            let nr = addr.row + d.dr, nc = addr.col + d.dc
            guard nr >= 0, nr < Self.rows, nc >= 0, nc < Self.cols else { continue }
            if grid[nr][nc] != .empty {
                out.append(Addr(row: nr, col: nc))
            }
        }
        return out
    }

    private mutating func applyScrumblx(at cell: Addr) {
        grid[cell.row][cell.col] = .empty
        var vanished = 0
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                guard case .priks(let n) = grid[r][c] else { continue }
                if n <= 1 {
                    grid[r][c] = .empty
                    vanished += 1
                } else {
                    grid[r][c] = .priks(n - 1)
                }
            }
        }
        addScore(vanished * 20)
        let had = columnOccupiedFlags()
        var rng = effectRNG(event: "scrumblx", at: cell)
        for r in 0..<Self.rows {
            let hasBlock = (0..<Self.cols).contains { grid[r][$0] != .empty }
            guard hasBlock else { continue }
            let dir = rng.nextBool() ? 1 : -1
            let steps = rng.nextInt(in: 1...7)
            let delta = dir * steps
            let oldRow = grid[r]
            var newRow = [BlockType](repeating: .empty, count: Self.cols)
            for c in 0..<Self.cols {
                let newC = ((c + delta) % Self.cols + Self.cols) % Self.cols
                newRow[newC] = oldRow[c]
            }
            grid[r] = newRow
        }
        afterMagixCompact(hadBlockBefore: had)
    }
}

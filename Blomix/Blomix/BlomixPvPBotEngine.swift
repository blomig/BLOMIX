//
//  BlomixPvPBotEngine.swift
//  Blomix
//
//  Duel vs bots : horloges + éventuel 1/N colonne au hasard, un cerveau (`computeOptimal`).
//  File `blomix.pvpBot` QoS .utility — jamais `analyzerQueue`, jamais MainActor
//  pour le lookahead. Pas de Magix, bombes 3×3, attaques palier 50.
//

import Foundation
import UIKit

// MARK: - Identité bot (noms non traduits)

enum BlomixPvPBotKind: String, CaseIterable, Sendable {
    case babybot = "bot:baby"
    case minibot = "bot:mini"
    case bobbot = "bot:bob"
    case bot10 = "bot:10"
    case bot5 = "bot:5"
    case supreme = "bot:supreme"

    var displayName: String {
        switch self {
        case .babybot: return "BABYBOT"
        case .minibot: return "MINIBOT"
        case .bobbot: return "BOBBOT"
        case .bot10: return "BOT10"
        case .bot5: return "BOT5"
        case .supreme: return "BOTSUPREME"
        }
    }

    /// Budget de réflexion par coup (secondes). Si `computeOptimal` dépasse : jouer dès que prêt.
    var thinkSeconds: TimeInterval {
        switch self {
        case .babybot, .minibot, .bobbot, .bot5: return 5
        case .bot10: return 10
        case .supreme: return 1
        }
    }

    /// Colonne de ce coup. BOT5 / BOTSUPREME : toujours optimal.
    func columnPolicy(moveCount: Int) -> BlomixPvPBotColumnPolicy {
        switch self {
        case .babybot:
            return .worst
        case .minibot:
            return .randomLegal
        case .bobbot:
            let phase = moveCount % 5
            return (phase == 0 || phase == 2) ? .worst : .optimal
        case .bot10:
            return (moveCount % 2 == 0) ? .worst : .optimal
        case .bot5, .supreme:
            return .optimal
        }
    }
}

enum BlomixPvPBotColumnPolicy: Sendable {
    case optimal
    case randomLegal
    case worst
}

// MARK: - Pause / stop (file bot)

private final class BlomixPvPBotRunFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false
    private var stopped = false

    func pause() { lock.lock(); paused = true; lock.unlock() }
    func resume() { lock.lock(); paused = false; lock.unlock() }
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    func resetForNewRound() {
        lock.lock()
        paused = false
        stopped = false
        lock.unlock()
    }

    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return paused
    }

    var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }
}

// MARK: - Horloge (glue)

/// Pousse attaques / fill / iLost vers le coordinateur **canal .bot**, 0 octet réseau.
/// Pas `@MainActor` : la file `blomix.pvpBot` possède le moteur ; les callbacks hoppent sur le main.
final class BlomixPvPBotMatchController: @unchecked Sendable {

    private let kind: BlomixPvPBotKind
    private let queue = DispatchQueue(label: "blomix.pvpBot", qos: .utility)
    private let flags = BlomixPvPBotRunFlag()
    private weak var coordinator: BlomixPvPMatchCoordinator?
    private let genLock = NSLock()
    private var generation: UInt64 = 0
    private var pendingPlayerAttacks: [[BlockType]] = []
    private var didInstallAppObservers = false

    init(kind: BlomixPvPBotKind, coordinator: BlomixPvPMatchCoordinator) {
        self.kind = kind
        self.coordinator = coordinator
        installAppObserversIfNeeded()
    }

    func start(seed: UInt64) {
        flags.resetForNewRound()
        let gen = bumpGeneration()
        let engine = BlomixPvPBotEngine.start(seed: seed, kind: kind)
        queue.async { [weak self] in
            self?.runLoop(engine: engine, generation: gen)
        }
    }

    func stop() {
        flags.stop()
        _ = bumpGeneration()
    }

    func injectPlayerAttack(_ line: [BlockType]) {
        queue.async { [weak self] in
            self?.pendingPlayerAttacks.append(line)
        }
    }

    private func currentGeneration() -> UInt64 {
        genLock.lock(); defer { genLock.unlock() }
        return generation
    }

    private func bumpGeneration() -> UInt64 {
        genLock.lock()
        generation += 1
        let g = generation
        genLock.unlock()
        return g
    }

    private func installAppObserversIfNeeded() {
        guard !didInstallAppObservers else { return }
        didInstallAppObservers = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flags.pause()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flags.resume()
        }
    }

    private func runLoop(engine initial: BlomixPvPBotEngine, generation: UInt64) {
        var engine = initial
        while !flags.isStopped, generation == currentGeneration() {
            waitWhilePaused()
            guard !flags.isStopped, generation == currentGeneration() else { return }

            drainPendingAttacks(into: &engine)

            let budget = kind.thinkSeconds
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = engine.planMove()
            let elapsed = CFAbsoluteTimeGetCurrent() - t0
            let remain = budget - elapsed
            if remain > 0 {
                sleepRemaining(remain, generation: generation)
            }
            guard !flags.isStopped, generation == currentGeneration() else { return }

            drainPendingAttacks(into: &engine)
            // Re-plan après d’éventuelles attaques reçues pendant la pensée (colonne fraîche, 0 wait).
            let planned = engine.planMove()
            let applied = engine.applyPlanned(planned)
            let fill = engine.fillDepth
            let score = engine.score
            let attack = applied.outgoingAttack
            let lost = applied.gameOver

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.currentGeneration() else { return }
                Task { @MainActor in
                    self.coordinator?.handleBotFillDepth(fill, score: score)
                    if let attack {
                        self.coordinator?.handleBotAttack(attack)
                    }
                    if lost {
                        self.flags.stop()
                        self.coordinator?.handleBotLost()
                    }
                }
            }
            if lost { return }
        }
    }

    private func drainPendingAttacks(into engine: inout BlomixPvPBotEngine) {
        let batch = pendingPlayerAttacks
        pendingPlayerAttacks.removeAll(keepingCapacity: true)
        for line in batch {
            engine.receiveAttack(line)
        }
    }

    private func waitWhilePaused() {
        while flags.isPaused, !flags.isStopped {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func sleepRemaining(_ seconds: TimeInterval, generation: UInt64) {
        var deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if flags.isStopped || generation != self.generation { return }
            if flags.isPaused {
                Thread.sleep(forTimeInterval: 0.05)
                deadline = deadline.addingTimeInterval(0.05)
                continue
            }
            let slice = min(0.05, deadline.timeIntervalSinceNow)
            if slice <= 0 { return }
            Thread.sleep(forTimeInterval: slice)
        }
    }
}

// MARK: - Coup planifié (compute puis wait puis apply)

private struct BlomixPvPBotPlannedMove: Sendable {
    enum Kind: Sendable {
        case drop(column: Int)
        case bombThenDrop(center: BlomixPvPBotAddr, column: Int)
        case survivalBombsThenDrop
        case gameOver
    }

    let kind: Kind
}

private struct BlomixPvPBotApplyResult: Sendable {
    var outgoingAttack: [BlockType]?
    var gameOver: Bool
}

struct BlomixPvPBotAddr: Hashable, Sendable {
    let row: Int
    let col: Int
}

// MARK: - Moteur RAM (règles Duel, pas Arcade)

struct BlomixPvPBotEngine: Sendable {
    private let kind: BlomixPvPBotKind
    /// Mélange déterministe pour les colonnes « au hasard » — **pas** le RNG des pièces.
    private let fidgetSeed: UInt64
    private var rng: BlomixPvPSeededBlockRNG
    private var grid: [[BlockType]]
    private var p0: BlockType
    private var p1: BlockType
    private var p2: BlockType
    private var nextLine: [BlockType]
    private var incomingAttacks: [[BlockType]]
    private var moveCount: Int
    private(set) var score: Int
    private var lastAttackBracket: Int
    private var chainSeriesLevel: Int
    private var bombCount: Int

    private static let rows = 8
    private static let cols = 8
    private static let deltas8: [(dr: Int, dc: Int)] = [
        (-1, -1), (-1, 0), (-1, 1),
        (0, -1), (0, 1),
        (1, -1), (1, 0), (1, 1),
    ]

    static func start(seed: UInt64, kind: BlomixPvPBotKind) -> BlomixPvPBotEngine {
        var rng = BlomixPvPSeededBlockRNG(seed: seed)
        let p0 = rng.nextPlayableBlock()
        let p1 = rng.nextPlayableBlock()
        let p2 = rng.nextPlayableBlock()
        let line = rng.nextRandomLineRowIndependentCells()
        var mix: UInt64 = 0
        for b in kind.rawValue.utf8 {
            mix = mix &* 16777619 &+ UInt64(b)
        }
        return BlomixPvPBotEngine(
            kind: kind,
            fidgetSeed: seed &* 0x9E3779B97F4A7C15 &+ mix,
            rng: rng,
            grid: Array(repeating: Array(repeating: .empty, count: cols), count: rows),
            p0: p0, p1: p1, p2: p2,
            nextLine: line,
            incomingAttacks: [],
            moveCount: 0,
            score: 0,
            lastAttackBracket: 0,
            chainSeriesLevel: 0,
            bombCount: 3
        )
    }

    var fillDepth: Int {
        max(0, min(8, maxHeight()))
    }

    mutating func receiveAttack(_ line: [BlockType]) {
        rng.discardNextRandomLineDrawsMatchingOpponentGeneration()
        incomingAttacks.append(line)
    }

    fileprivate func planMove() -> BlomixPvPBotPlannedMove {
        if bombCount > 0, shouldSoftBomb() {
            if let center = bestBombCenter(), let col = pickColumnAfterHypotheticalBomb(center) {
                return BlomixPvPBotPlannedMove(kind: .bombThenDrop(center: center, column: col))
            }
        }
        if !hasAnyLanding(), bombCount > 0 {
            return BlomixPvPBotPlannedMove(kind: .survivalBombsThenDrop)
        }
        guard let column = pickColumn() else {
            return BlomixPvPBotPlannedMove(kind: .gameOver)
        }
        return BlomixPvPBotPlannedMove(kind: .drop(column: column))
    }

    fileprivate mutating func applyPlanned(_ planned: BlomixPvPBotPlannedMove) -> BlomixPvPBotApplyResult {
        switch planned.kind {
        case .gameOver:
            return BlomixPvPBotApplyResult(outgoingAttack: nil, gameOver: true)
        case .bombThenDrop(let center, let column):
            _ = detonateBomb(at: center)
            if applyDrop(column: column) {
                return finishApply(gameOver: true)
            }
        case .survivalBombsThenDrop:
            while !hasAnyLanding(), bombCount > 0 {
                if !detonateBestBomb() { break }
            }
            guard hasAnyLanding(), let column = pickColumn() else {
                return finishApply(gameOver: true)
            }
            if applyDrop(column: column) {
                return finishApply(gameOver: true)
            }
        case .drop(let column):
            if applyDrop(column: column) {
                return finishApply(gameOver: true)
            }
        }
        return finishApply(gameOver: false)
    }

    private mutating func finishApply(gameOver: Bool) -> BlomixPvPBotApplyResult {
        var attack: [BlockType]?
        let bracket = score / 50
        if !gameOver, bracket > lastAttackBracket {
            lastAttackBracket = bracket
            attack = rng.nextRandomLineRowIndependentCells()
        }
        return BlomixPvPBotApplyResult(outgoingAttack: attack, gameOver: gameOver)
    }

    /// `true` = game over.
    private mutating func applyDrop(column: Int) -> Bool {
        guard let row = landingRow(column) else { return true }
        let placed = p0
        p0 = p1
        p1 = p2
        p2 = rng.nextPlayableBlock()
        grid[row][column] = placed
        return resolveAllScoring(runPlacementHooks: true)
    }

    // MARK: Politique (engine 5, sans Magix)

    private func pickColumn() -> Int? {
        switch kind.columnPolicy(moveCount: moveCount) {
        case .randomLegal:
            return randomLegalColumn()
        case .worst:
            return columnByEval(pickBest: false)
        case .optimal:
            return columnByEval(pickBest: true)
        }
    }

    /// `pickBest` : argmax `scorePerColumn`. Sinon argmin (pire coup jouable, égalité → gauche).
    private func columnByEval(pickBest: Bool) -> Int? {
        let result = BlomixMoveAnalyzer.computeOptimal(
            grid: grid,
            piece0: p0,
            piece1: p1,
            piece2: p2,
            moveCount: moveCount,
            pendingLine: nextLine
        )
        var chosen: Int?
        var chosenScore = pickBest ? Int.min : Int.max
        for c in 0..<Self.cols {
            guard let s = result.scorePerColumn[c] else { continue }
            let better = pickBest ? (s > chosenScore) : (s < chosenScore)
            if better {
                chosenScore = s
                chosen = c
            }
        }
        return chosen ?? shortestThenLeftColumn()
    }

    /// Colonne avec atterrissage, tirage déterministe (seed match + coup). Pas le RNG des pièces.
    private func randomLegalColumn() -> Int? {
        let legal = (0..<Self.cols).filter { landingRow($0) != nil }
        guard !legal.isEmpty else { return nil }
        var x = fidgetSeed &+ UInt64(moveCount &+ 1) &* 0x9E3779B97F4A7C15
        x ^= x >> 30
        x = x &* 0xBF58476D1CE4E5B9
        x ^= x >> 27
        x = x &* 0x94D049BB133111EB
        x ^= x >> 31
        return legal[Int(x % UInt64(legal.count))]
    }

    private func pickColumnAfterHypotheticalBomb(_ center: BlomixPvPBotAddr) -> Int? {
        var trial = self
        guard trial.detonateBomb(at: center) else { return pickColumn() }
        return trial.pickColumn()
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

    private func landingRow(_ column: Int) -> Int? {
        BlomixMoveAnalyzer.landingRow(in: grid, column: column)
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

    @discardableResult
    private mutating func detonateBestBomb() -> Bool {
        guard bombCount > 0, let center = bestBombCenter() else { return false }
        return detonateBomb(at: center)
    }

    @discardableResult
    private mutating func detonateBomb(at center: BlomixPvPBotAddr) -> Bool {
        guard bombCount > 0 else { return false }
        bombCount -= 1
        let blast = bombAffectedCells3x3(centerRow: center.row, centerCol: center.col)
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
        awardColumnBonuses(hadBlockBefore: had)
        chainSeriesLevel = 1
        _ = resolveAllScoring(runPlacementHooks: false)
        return true
    }

    private func bestBombCenter() -> BlomixPvPBotAddr? {
        let heights = (0..<Self.cols).map { columnHeight($0) }
        let maxH = heights.max() ?? 0
        let tall = Set((0..<Self.cols).filter { heights[$0] == maxH })
        var bestBrix = -1
        var bestTall = -1
        var bestTotal = -1
        var best: BlomixPvPBotAddr?
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                let blast = bombAffectedCells3x3(centerRow: r, centerCol: c)
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
                    best = BlomixPvPBotAddr(row: r, col: c)
                }
            }
        }
        return best
    }

    /// Duel : cœur 3×3 uniquement (pas de croix de stage).
    private func bombAffectedCells3x3(centerRow: Int, centerCol: Int) -> [BlomixPvPBotAddr] {
        var result: [BlomixPvPBotAddr] = []
        for dr in -1...1 {
            for dc in -1...1 {
                let r = centerRow + dr, c = centerCol + dc
                guard r >= 0, r < Self.rows, c >= 0, c < Self.cols else { continue }
                result.append(BlomixPvPBotAddr(row: r, col: c))
            }
        }
        return result
    }

    // MARK: Scoring Duel (pas de × stage, pas de +500 grille)

    private mutating func addScore(_ base: Int) {
        guard base > 0 else { return }
        score += base
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

    /// `true` = game over (ligne impossible).
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
                    if injectIncomingOrDecadeIsFatal() { return true }
                    continue
                }
                return false
            }
            let hadBlock = columnOccupiedFlags()
            var cleared = Set<BlomixPvPBotAddr>()
            for comp in components {
                addScore(Self.chainPoints(level: chainSeriesLevel, groupSize: comp.count))
                cleared.formUnion(comp)
            }
            for a in cleared { grid[a.row][a.col] = .empty }
            let vanished = decrementPriks(touching: cleared)
            addScore(vanished * 20)
            compactTowardTop()
            awardColumnBonuses(hadBlockBefore: hadBlock)
            chainSeriesLevel += 1
        }
        return false
    }

    /// Une ligne par idle (attaque en file, sinon décennie) — comme le Duel humain.
    private mutating func injectIncomingOrDecadeIsFatal() -> Bool {
        if !incomingAttacks.isEmpty {
            let line = incomingAttacks.removeFirst()
            return injectLine(line)
        }
        if moveCount > 0, moveCount % 10 == 0 {
            let line = nextLine
            nextLine = rng.nextRandomLineRowIndependentCells()
            return injectLine(line)
        }
        return false
    }

    /// `true` si l’injection est fatale.
    private mutating func injectLine(_ line: [BlockType]) -> Bool {
        if (0..<Self.cols).contains(where: { landingRow($0) == nil }) {
            return true
        }
        for c in 0..<Self.cols {
            if let r = landingRow(c), c < line.count {
                grid[r][c] = line[c]
            }
        }
        return false
    }

    private func columnOccupiedFlags() -> [Bool] {
        (0..<Self.cols).map { c in
            (0..<Self.rows).contains { grid[$0][c] != .empty }
        }
    }

    private mutating func awardColumnBonuses(hadBlockBefore: [Bool]) {
        for c in 0..<Self.cols {
            let emptyNow = (0..<Self.rows).allSatisfy { grid[$0][c] == .empty }
            if hadBlockBefore[c], emptyNow {
                addScore(10)
            }
        }
    }

    private mutating func compactTowardTop() {
        for c in 0..<Self.cols {
            let blocks = (0..<Self.rows).compactMap { grid[$0][c] == .empty ? nil : grid[$0][c] }
            for r in 0..<Self.rows {
                grid[r][c] = r < blocks.count ? blocks[r] : .empty
            }
        }
    }

    private func findChainComponents() -> [Set<BlomixPvPBotAddr>] {
        var visited = Set<BlomixPvPBotAddr>()
        var components: [Set<BlomixPvPBotAddr>] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                let a = BlomixPvPBotAddr(row: r, col: c)
                guard !visited.contains(a) else { continue }
                guard case .color(let name) = grid[r][c] else { continue }
                let comp = flood8(start: a, colorName: name, visited: &visited)
                if comp.count >= 5 { components.append(comp) }
            }
        }
        return components
    }

    private func flood8(
        start: BlomixPvPBotAddr,
        colorName: String,
        visited: inout Set<BlomixPvPBotAddr>
    ) -> Set<BlomixPvPBotAddr> {
        var stack = [start]
        var component = Set<BlomixPvPBotAddr>()
        while let cur = stack.popLast() {
            guard !visited.contains(cur) else { continue }
            guard case .color(let n) = grid[cur.row][cur.col], n == colorName else { continue }
            visited.insert(cur)
            component.insert(cur)
            for d in Self.deltas8 {
                let nr = cur.row + d.dr, nc = cur.col + d.dc
                guard nr >= 0, nr < Self.rows, nc >= 0, nc < Self.cols else { continue }
                let nb = BlomixPvPBotAddr(row: nr, col: nc)
                guard !visited.contains(nb) else { continue }
                stack.append(nb)
            }
        }
        return component
    }

    private mutating func decrementPriks(touching removed: Set<BlomixPvPBotAddr>) -> Int {
        guard !removed.isEmpty else { return 0 }
        var vanished = 0
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                guard case .priks(let n) = grid[r][c], n > 0 else { continue }
                let touches = Self.deltas8.contains { d in
                    let nr = r + d.dr, nc = c + d.dc
                    return nr >= 0 && nr < Self.rows && nc >= 0 && nc < Self.cols
                        && removed.contains(BlomixPvPBotAddr(row: nr, col: nc))
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
}

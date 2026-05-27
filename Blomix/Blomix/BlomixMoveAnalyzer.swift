//
//  BlomixMoveAnalyzer.swift
//  Blomix
//
//  Moteur fantôme synchrone pour l'analyse des coups après chaque stabilisation.
//  Aucune dépendance SpriteKit — pure logique Swift opérant sur des copies de grille.
//

import Foundation

// MARK: - Enregistrement d'un coup

struct BlomixMoveRecord {
    /// Meilleur score atteignable sur l'horizon 3 depuis n'importe quelle colonne.
    let optimalScore: Int
    /// Meilleur score atteignable sur l'horizon 3 depuis la colonne choisie par le joueur.
    let chosenScore: Int
    /// Écart entre optimal et réel (toujours ≥ 0).
    var delta: Int { optimalScore - chosenScore }
}

// MARK: - Statistiques de partie

struct BlomixGameMoveStats {
    private(set) var records: [BlomixMoveRecord] = []

    var totalMoves:    Int { records.count }
    var excellentCount: Int { records.filter { $0.delta <= BlomixMoveAnalyzer.excellentThreshold }.count }
    var badCount:       Int { records.filter { $0.delta >  BlomixMoveAnalyzer.badThreshold      }.count }

    /// Score d'optimalité global en % (0–100).
    /// Formule : 100 × moyenne(max(0, 1 − delta/referenceScale))
    var optimalityPercent: Int {
        guard !records.isEmpty else { return 100 }
        let ref = Double(BlomixMoveAnalyzer.referenceScaleDelta)
        let sum = records.reduce(0.0) { acc, r in
            acc + max(0.0, 1.0 - Double(max(0, r.delta)) / ref)
        }
        return Int((sum / Double(records.count)) * 100.0)
    }

    mutating func append(_ record: BlomixMoveRecord) { records.append(record) }
    mutating func reset() { records.removeAll() }
}

// MARK: - Qualité d'un coup

enum BlomixMoveQuality: Equatable {
    case excellent  // delta ≤ excellentThreshold → "!!"
    case bad        // delta >  badThreshold       → "?"
    case neutral
}

// MARK: - Résultat du lookahead

struct BlomixLookAheadResult {
    /// Score de la meilleure continuation globale (sur toutes les colonnes possibles).
    let optimalScore: Int
    /// Score de la meilleure continuation depuis chaque colonne (nil = colonne pleine ou invalide).
    let scorePerColumn: [Int?]  // 8 entrées, indexées par colonne

    func quality(forChosenColumn col: Int) -> BlomixMoveQuality {
        let chosen = scorePerColumn[col] ?? (optimalScore - BlomixMoveAnalyzer.badThreshold - 1)
        let delta = optimalScore - chosen

        if delta <= BlomixMoveAnalyzer.excellentThreshold {
            // "!!" uniquement si le choix avait vraiment un enjeu :
            // au moins une colonne était significativement moins bonne.
            let scores = scorePerColumn.compactMap { $0 }
            let worst  = scores.min() ?? optimalScore
            let spread = optimalScore - worst
            guard spread >= BlomixMoveAnalyzer.minSpreadForExcellent else { return .neutral }
            return .excellent
        }
        if delta > BlomixMoveAnalyzer.badThreshold { return .bad }
        return .neutral
    }

    func record(forChosenColumn col: Int) -> BlomixMoveRecord {
        let chosen = scorePerColumn[col] ?? (optimalScore - BlomixMoveAnalyzer.badThreshold - 1)
        return BlomixMoveRecord(optimalScore: optimalScore, chosenScore: chosen)
    }
}

// MARK: - Moteur principal

enum BlomixMoveAnalyzer {

    // ─── Feature flags ───────────────────────────────────────────────────────
    /// `false` → tout le système désactivé, zéro surcoût CPU.
    static let evalEnabled = false
    /// `false` → données accumulées mais aucun popup en cours de partie.
    static let realtimeFeedbackEnabled = true

    // ─── Seuils de qualité ────────────────────────────────────────────────────
    /// Delta ≤ ce seuil → coup "!!" (excellent).
    static let excellentThreshold = 50
    /// Delta > ce seuil → coup "?" (mauvais).
    static let badThreshold = 900
    /// Écart min entre la meilleure et la moins bonne colonne pour que "!!" puisse s'afficher.
    /// Si toutes les colonnes donnent des scores proches (situation désespérée ou sans enjeu),
    /// aucun "!!" ne s'affiche même si le joueur a choisi la meilleure option.
    static let minSpreadForExcellent = 900
    /// Échelle de référence pour le calcul du % d'optimalité.
    static let referenceScaleDelta = 2000

    // ─── Dimensions (mirroir de GridLayout) ──────────────────────────────────
    static let rows = 8
    static let cols = 8

    typealias SimGrid = [[BlockType]]

    // 8-connectivité (identique à chainNeighborDeltas8 dans GameScene).
    private static let deltas8: [(dr: Int, dc: Int)] = [
        (-1,-1),(-1, 0),(-1, 1),
        ( 0,-1),        ( 0, 1),
        ( 1,-1),( 1, 0),( 1, 1),
    ]

    // MARK: - Helpers grille

    /// Première rangée vide depuis le haut (là où un bloc tombe dans `column`).
    /// Retourne `nil` si la colonne est pleine.
    static func landingRow(in grid: SimGrid, column: Int) -> Int? {
        guard column >= 0, column < cols else { return nil }
        for row in 0..<rows where grid[row][column] == .empty { return row }
        return nil
    }

    // MARK: - Drop + résolution complète

    /// Pose `block` dans `column`, résout toutes les cascades, injecte la ligne bonus
    /// si `(moveCount+1) % 10 == 0` et que `pendingLine` est connu.
    /// Retourne `nil` si la colonne est pleine ou si l'injection déclenche un game-over.
    static func simulateDrop(
        grid: SimGrid,
        block: BlockType,
        column: Int,
        moveCount: Int,
        pendingLine: [BlockType]?
    ) -> (grid: SimGrid, newMoveCount: Int)? {
        simulateDropAny(grid: grid, block: block, column: column,
                        moveCount: moveCount, pendingLine: pendingLine)
    }

    private static func simulateDropAny(
        grid: SimGrid,
        block: BlockType,
        column: Int,
        moveCount: Int,
        pendingLine: [BlockType]?
    ) -> (grid: SimGrid, newMoveCount: Int)? {

        guard block != .empty else { return nil }
        guard let row = landingRow(in: grid, column: column) else { return nil }

        var g = grid
        g[row][column] = block
        g = resolveAll(g)

        let newMC = moveCount + 1

        // Injection de la ligne si on franchit une décennie ET qu'on la connaît.
        if newMC % 10 == 0, let line = pendingLine, line.count == cols {
            // Si une colonne est déjà pleine → branche invalide (game over).
            guard (0..<cols).allSatisfy({ landingRow(in: g, column: $0) != nil }) else { return nil }
            var injected = g
            for c in 0..<cols {
                if let r = landingRow(in: injected, column: c) {
                    injected[r][c] = line[c]
                }
            }
            g = resolveAll(injected)
        }
        return (g, newMC)
    }

    // MARK: - Résolution complète (cascades jusqu'à stabilité)

    static func resolveAll(_ grid: SimGrid) -> SimGrid {
        var g = grid
        var iterations = 0
        let maxIterations = 64  // garde-fou contre une boucle infinie théorique
        while iterations < maxIterations {
            iterations += 1
            let cleared = findChainCells(in: g)
            guard !cleared.isEmpty else { break }
            for a in cleared { g[a.row][a.col] = .empty }
            g = decrementPriks(touching: cleared, in: g)
            g = compactTowardTop(g)
        }
        return g
    }

    // MARK: - Détection des chaînes (≥ 5, 8-con, même couleur)

    private struct Addr: Hashable {
        let row: Int
        let col: Int
    }

    private static func findChainCells(in grid: SimGrid) -> Set<Addr> {
        var globalVisited = Set<Addr>()
        var toRemove      = Set<Addr>()
        for r in 0..<rows {
            for c in 0..<cols {
                let a = Addr(row: r, col: c)
                guard !globalVisited.contains(a) else { continue }
                guard case .color(let name) = grid[r][c] else { continue }
                let comp = flood8(grid: grid, start: a, colorName: name, visited: &globalVisited)
                if comp.count >= 5 { toRemove.formUnion(comp) }
            }
        }
        return toRemove
    }

    private static func flood8(
        grid: SimGrid, start: Addr, colorName: String,
        visited: inout Set<Addr>
    ) -> Set<Addr> {
        var stack     = [start]
        var component = Set<Addr>()
        while let cur = stack.popLast() {
            guard !visited.contains(cur) else { continue }
            guard case .color(let n) = grid[cur.row][cur.col], n == colorName else { continue }
            visited.insert(cur)
            component.insert(cur)
            for d in deltas8 {
                let nr = cur.row + d.dr, nc = cur.col + d.dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                let nb = Addr(row: nr, col: nc)
                guard !visited.contains(nb) else { continue }
                stack.append(nb)
            }
        }
        return component
    }

    // MARK: - Décrémentation des priks adjacents

    private static func decrementPriks(touching removed: Set<Addr>, in grid: SimGrid) -> SimGrid {
        guard !removed.isEmpty else { return grid }
        var g = grid
        for r in 0..<rows {
            for c in 0..<cols {
                guard case .priks(let n) = g[r][c], n > 0 else { continue }
                let touches = deltas8.contains { d in
                    let nr = r + d.dr, nc = c + d.dc
                    return nr >= 0 && nr < rows && nc >= 0 && nc < cols
                        && removed.contains(Addr(row: nr, col: nc))
                }
                if touches { g[r][c] = n <= 1 ? .empty : .priks(n - 1) }
            }
        }
        return g
    }

    // MARK: - Compactage vers le haut

    private static func compactTowardTop(_ grid: SimGrid) -> SimGrid {
        var g = grid
        for c in 0..<cols {
            let blocks = (0..<rows).compactMap { r -> BlockType? in
                grid[r][c] == .empty ? nil : grid[r][c]
            }
            for r in 0..<rows { g[r][c] = r < blocks.count ? blocks[r] : .empty }
        }
        return g
    }

    // MARK: - Fonction d'évaluation

    /// Calcule le score de position d'une grille stable.
    /// Ordre strict : hauteurs → groupes → brix → stability → somme.
    static func evaluate(grid: SimGrid, moveCount: Int) -> Int {
        // ── 1. Hauteurs ──────────────────────────────────────────────────────
        // Les blocs se compactent vers le haut (row 0 = sommet).
        // La hauteur d'une colonne = première rangée vide en partant du haut
        // = nombre de blocs occupant le sommet de la colonne.
        var maxH = 0, sumH = 0, fullCols = 0
        for c in 0..<cols {
            // Première rangée vide en descendant depuis le haut → = hauteur de la pile.
            let h = (0..<rows).first(where: { grid[$0][c] == .empty }) ?? rows
            if h > maxH { maxH = h }
            sumH += h
            if h == rows { fullCols += 1 }
        }
        let risk = -1200 * maxH - 90 * sumH - 3000 * fullCols

        // ── 2. Groupes couleur (8-con, couleurs uniquement) ──────────────────
        var visitedG = Set<Addr>()
        var nGe5 = 0, nGe4 = 0, nGe3 = 0, totalInGe3 = 0
        for r in 0..<rows {
            for c in 0..<cols {
                let a = Addr(row: r, col: c)
                guard !visitedG.contains(a),
                      case .color(let name) = grid[r][c] else { continue }
                let comp = flood8(grid: grid, start: a, colorName: name, visited: &visitedG)
                if comp.count >= 5 {
                    nGe5 += 1; nGe4 += 1; nGe3 += 1; totalInGe3 += comp.count
                } else if comp.count == 4 {
                    nGe4 += 1; nGe3 += 1; totalInGe3 += comp.count
                } else if comp.count == 3 {
                    nGe3 += 1; totalInGe3 += comp.count
                }
            }
        }
        // nGe4 : groupes de exactement 4 (à un bloc d'une élimination) — fortement valorisés
        // pour que le lookahead préfère construire vers 5 plutôt que d'ignorer ces groupes.
        let clearing  = 45 * nGe5 + 30 * nGe4 + 15 * nGe3
        let structure = 12 * totalInGe3

        // ── 3. Brix (priks) ──────────────────────────────────────────────────
        var brixRaw = 0
        for r in 0..<rows {
            for c in 0..<cols {
                if case .priks(let n) = grid[r][c] {
                    brixRaw += 40 * (5 - n) + (r >= 5 ? -30 : 0)
                }
            }
        }
        let brixScore = max(-600, brixRaw)

        // ── 4. Stabilité ──────────────────────────────────────────────────────
        let stability = 18 * (10 - (moveCount % 10))

        return risk + clearing + brixScore + stability + structure
    }

    // MARK: - Lookahead 3 niveaux

    /// Calcule le meilleur score atteignable à horizon 3 (pièce courante + 2 suivantes).
    /// Retourne le score optimal global et le meilleur score par colonne de départ.
    static func computeOptimal(
        grid: SimGrid,
        piece0: BlockType,
        piece1: BlockType,
        piece2: BlockType,
        moveCount: Int,
        pendingLine: [BlockType]?
    ) -> BlomixLookAheadResult {

        var scorePerCol: [Int?] = Array(repeating: nil, count: cols)
        var globalBest = Int.min

        for col0 in 0..<cols {
            guard piece0 != .empty else { continue }
            guard let (g1, mc1) = simulateDropAny(
                grid: grid, block: piece0, column: col0,
                moveCount: moveCount, pendingLine: pendingLine
            ) else { continue }

            // Après niveau 1, la pendingLine a peut-être été injectée → inconnue pour niveaux 2+
            var best1 = Int.min

            for col1 in 0..<cols {
                guard piece1 != .empty else { continue }
                guard let (g2, mc2) = simulateDropAny(
                    grid: g1, block: piece1, column: col1,
                    moveCount: mc1, pendingLine: nil
                ) else { continue }

                for col2 in 0..<cols {
                    guard piece2 != .empty else { continue }
                    guard let (g3, mc3) = simulateDropAny(
                        grid: g2, block: piece2, column: col2,
                        moveCount: mc2, pendingLine: nil
                    ) else { continue }

                    let s = evaluate(grid: g3, moveCount: mc3)
                    if s > best1 { best1 = s }
                }
            }

            // Fallback si toutes les branches de niveau 2+ sont invalides :
            // on évalue directement la grille après niveau 1.
            if best1 == Int.min {
                best1 = evaluate(grid: g1, moveCount: mc1)
            }

            scorePerCol[col0] = best1
            if best1 > globalBest { globalBest = best1 }
        }

        let optimal = globalBest == Int.min ? evaluate(grid: grid, moveCount: moveCount) : globalBest
        return BlomixLookAheadResult(optimalScore: optimal, scorePerColumn: scorePerCol)
    }
}

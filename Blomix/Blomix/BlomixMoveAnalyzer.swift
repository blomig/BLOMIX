//
//  BlomixMoveAnalyzer.swift
//  Blomix
//
//  Moteur fantôme synchrone pour l'analyse des coups après chaque stabilisation.
//  Aucune dépendance SpriteKit — pure logique Swift opérant sur des copies de grille.
//

import Foundation

// MARK: - Enregistrement d'un coup

struct BlomixMoveRecord: Codable {
    /// Meilleur score atteignable sur l'horizon 3 depuis n'importe quelle colonne.
    let optimalScore: Int
    /// Meilleur score atteignable sur l'horizon 3 depuis la colonne choisie par le joueur.
    let chosenScore: Int
    /// Score de la pire colonne jouable parmi les 8 colonnes.
    let worstScore: Int
    /// Écart entre optimal et réel (toujours ≥ 0).
    var delta: Int  { optimalScore - chosenScore }
    /// Étendue des options disponibles (optimal − pire).
    var spread: Int { optimalScore - worstScore }
}

// MARK: - Statistiques de partie

struct BlomixGameMoveStats {
    private(set) var records: [BlomixMoveRecord] = []

    var totalMoves:    Int { records.count }
    var excellentCount: Int { records.filter { $0.delta <= BlomixMoveAnalyzer.excellentThreshold }.count }
    var badCount:       Int { records.filter { $0.delta >  BlomixMoveAnalyzer.badThreshold      }.count }

    /// Score d'optimalité global en % (0–100).
    /// Formule : moyenne sur tous les coups de (chosenScore − worstScore) / (optimalScore − worstScore).
    /// Un coup où le joueur choisit la meilleure colonne → 1.0.
    /// Un coup où il choisit la pire colonne → 0.0.
    /// Si le spread < 200 pts (toutes colonnes équivalentes), le coup ne pénalise pas : contribution 1.0.
    var optimalityPercent: Int {
        guard !records.isEmpty else { return 100 }
        let minSpread = 200
        let sum = records.reduce(0.0) { acc, r in
            let sp = r.spread
            guard sp >= minSpread else { return acc + 1.0 }
            let quality = Double(r.chosenScore - r.worstScore) / Double(sp)
            return acc + max(0.0, min(1.0, quality))
        }
        return Int((sum / Double(records.count)) * 100.0)
    }

    mutating func append(_ record: BlomixMoveRecord) { records.append(record) }
    mutating func reset() { records.removeAll() }
    mutating func restore(records saved: [BlomixMoveRecord]) { records = saved }
}

// MARK: - Qualité d'un coup

enum BlomixMoveQuality: Equatable {
    case excellent  // delta ≤ excellentThreshold → "!!"
    case bad        // delta >  badThreshold       → "?"
    case neutral
}

// MARK: - Snapshot du pire coup de la partie

/// Instantané de la position au moment du pire coup (écart optimal − choix max).
/// Stocké en mémoire vive uniquement pendant la session Game Over.
struct BlomixWorstMistakeSnapshot {
    /// Grille avant le coup (8×8, coordonnées identiques au moteur).
    let grid: [[BlockType]]
    /// Bloc qui était à jouer (p0 — celui que le joueur a lancé).
    let block: BlockType
    /// Bloc suivant visible dans la file (p1).
    let nextBlock: BlockType
    /// Bloc d'après visible dans la file (p2).
    let blockTwoAhead: BlockType
    /// Ligne entrante visible uniquement quand moveCount % 10 == 9 (nil sinon).
    let pendingLine: [BlockType]?
    /// Colonne choisie par le joueur.
    let chosenColumn: Int
    /// Toutes les colonnes dont le score == optimalScore (peuvent être plusieurs).
    let optimalColumns: [Int]
    /// Écart = optimalScore − chosenScore (toujours > 0 ici).
    let delta: Int
    /// Texte du level au moment du coup (ex. "1", "2", "Ultimate" — nil si mode non-stagé).
    let stageLevelText: String?
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
        let worst  = scorePerColumn.compactMap { $0 }.min() ?? chosen
        return BlomixMoveRecord(optimalScore: optimalScore, chosenScore: chosen, worstScore: worst)
    }
}

// MARK: - Moteur principal

enum BlomixMoveAnalyzer {

    // ─── Feature flags ───────────────────────────────────────────────────────
    /// `false` → tout le système désactivé, zéro surcoût CPU.
    static let evalEnabled = true
    /// `false` → données accumulées mais aucun popup en cours de partie.
    static let realtimeFeedbackEnabled = false

    // ─── Seuils de qualité ────────────────────────────────────────────────────
    /// Delta ≤ ce seuil → coup "!!" (excellent).
    static let excellentThreshold = 50
    /// Delta > ce seuil → coup "?" (mauvais).
    static let badThreshold = 900
    /// Écart min entre la meilleure et la moins bonne colonne pour que "!!" puisse s'afficher.
    /// Si toutes les colonnes donnent des scores proches (situation désespérée ou sans enjeu),
    /// aucun "!!" ne s'affiche même si le joueur a choisi la meilleure option.
    static let minSpreadForExcellent = 900

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
        // Les blocs Magix ont des effets non simulables dans le lookahead ; on ignore cette branche.
        if case .magix = block { return nil }
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

    // MARK: - Fonction d'évaluation v2

    /// Calcule le score de position d'une grille stable (v2).
    /// Ordre d'exécution : hauteurs → landing rows → groupes/accessibilité/cellGroupSize
    ///   → preChainScore par colonne → risk (facteur dynamique) → clearing (brixTouch)
    ///   → brixPotential → stabilité → somme.
    static func evaluate(grid: SimGrid, moveCount: Int) -> Int {

        // ── 1. Hauteurs ───────────────────────────────────────────────────────────
        // Blocs compactés vers le haut (row 0 = sommet) ; hauteur = première rangée vide.
        var maxH = 0, sumH = 0, fullCols = 0, maxHColumn = 0
        for c in 0..<cols {
            let h = (0..<rows).first(where: { grid[$0][c] == .empty }) ?? rows
            if h > maxH { maxH = h; maxHColumn = c }
            sumH += h
            if h == rows { fullCols += 1 }
        }
        let k = 10 - (moveCount % 10)                  // coups avant la prochaine ligne [1..10]
        let t = Double(10 - k) / 9.0                   // 0.0 quand k=10, 1.0 quand k=1
        let urgencyH  = 0.80 + 0.20 * t                // [0.80 .. 1.00]
        let urgencySH = 0.90 + 0.10 * t                // [0.90 .. 1.00]

        // ── 2. Landing rows ───────────────────────────────────────────────────────
        var landingRows = [Int?](repeating: nil, count: cols)
        for c in 0..<cols { landingRows[c] = landingRow(in: grid, column: c) }

        // ── 3. Groupes couleur : taille, accessibilité, cellGroupSize ─────────────
        // cellGroupSize[r * cols + c] = taille de la composante 8-connexe contenant la case (r,c)
        // (0 pour les cases vides ou Brix). Tableau plat 1D pour limiter les allocations heap
        // (evaluate() est appelée 512× par lookahead).
        var cellGroupSize = [Int](repeating: 0, count: rows * cols)

        var visitedG = Set<Addr>()
        var nGe5 = 0, nGe4 = 0, nGe3 = 0, totalInGe3 = 0

        // Accessibilité v2 : tailles 2, 3, 4 (v1 : 3 et 4 seulement).
        var accessPoints4 = 0, accessPoints3 = 0, accessPoints2 = 0
        var deadGroups4 = 0, deadGroups3 = 0, deadGroups2 = 0

        // brixTouchBonus (clearing) : +8 par composante ≥ 5 qui touche un Brix.
        var brixTouchBonus = 0

        for r in 0..<rows {
            for c in 0..<cols {
                let a = Addr(row: r, col: c)
                guard !visitedG.contains(a),
                      case .color(let name) = grid[r][c] else { continue }
                let comp = flood8(grid: grid, start: a, colorName: name, visited: &visitedG)
                let sz = comp.count

                // Stocker la taille pour chaque case du groupe (utile pour brixPotential).
                for addr in comp { cellGroupSize[addr.row * cols + addr.col] = sz }

                if sz >= 5 {
                    nGe5 += 1; nGe4 += 1; nGe3 += 1; totalInGe3 += sz
                    // Bonus si le groupe ≥ 5 est 8-adjacent à un Brix (chaîne qui fait progresser).
                    var touchesBrix = false
                    outer: for addr in comp {
                        for d in deltas8 {
                            let nr = addr.row + d.dr, nc = addr.col + d.dc
                            guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                            if case .priks = grid[nr][nc] { touchesBrix = true; break outer }
                        }
                    }
                    if touchesBrix { brixTouchBonus += 8 }
                } else if sz == 4 {
                    nGe4 += 1; nGe3 += 1; totalInGe3 += sz
                } else if sz == 3 {
                    nGe3 += 1; totalInGe3 += sz
                }

                // Accessibilité pour les groupes de taille 2, 3, 4.
                if sz == 2 || sz == 3 || sz == 4 {
                    var accessCols = Set<Int>()
                    for addr in comp {
                        for d in deltas8 {
                            let nr = addr.row + d.dr, nc = addr.col + d.dc
                            guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                            guard grid[nr][nc] == .empty else { continue }
                            if landingRows[nc] == nr { accessCols.insert(nc) }
                        }
                    }
                    let nAP = accessCols.count
                    switch sz {
                    case 4:
                        accessPoints4 += nAP
                        if nAP == 0 { deadGroups4 += 1 }
                    case 3:
                        accessPoints3 += nAP
                        if nAP == 0 { deadGroups3 += 1 }
                    default:
                        accessPoints2 += nAP
                        if nAP == 0 { deadGroups2 += 1 }
                    }
                }
            }
        }

        let structure     = 12 * totalInGe3
        let accessibility = 25 * accessPoints4 +  9 * accessPoints3 + 3 * accessPoints2
                          - 40 * deadGroups4   - 15 * deadGroups3   - 6 * deadGroups2

        // ── 4. preChainScore par colonne ─────────────────────────────────────────
        // Calculé avant `risk` pour alimenter le facteur dynamique.
        // Pour chaque case d'atterrissage L, on somme les composantes 8-adjacentes
        // de même couleur (y compris groupes fragmentés réunis par ce seul bloc).
        // Bonus +20 si L est aussi 8-adjacent à un Brix (double bénéfice du coup).
        var perCellPreChain = [Int](repeating: 0, count: cols)  // score preChain par colonne
        var preChainScore = 0
        for c in 0..<cols {
            guard let lr = landingRows[c] else { continue }

            var floodVisited = Set<Addr>()
            var colorTotals: [String: Int] = [:]
            for d in deltas8 {
                let nr = lr + d.dr, nc = c + d.dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                let a = Addr(row: nr, col: nc)
                guard !floodVisited.contains(a),
                      case .color(let name) = grid[nr][nc] else { continue }
                let comp = flood8(grid: grid, start: a, colorName: name, visited: &floodVisited)
                colorTotals[name, default: 0] += comp.count
            }

            var cellScore = 0
            for (_, total) in colorTotals {
                if      total + 1 >= 5 { cellScore += 150 }
                else if total + 1 == 4 { cellScore += 45  }
                else if total + 1 == 3 { cellScore += 12  }
            }
            // Bonus si L est 8-adjacent à un Brix (coup qui crée chaîne ET avance le Brix).
            if cellScore > 0 {
                for d in deltas8 {
                    let nr = lr + d.dr, nc = c + d.dc
                    guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                    if case .priks = grid[nr][nc] { cellScore += 20; break }
                }
            }
            perCellPreChain[c] = cellScore
            preChainScore += cellScore
        }

        // ── 5. risk — coefficient réduit + facteur dynamique ─────────────────────
        // Le facteur dynamique atténue la pénalité si la colonne la plus haute a
        // de la valeur structurelle (groupe ≥ 3 présent ou landing spot avec preChain > 0).
        var dynamicFactor = 1.0
        if maxH >= 4 {
            var colHasGoodStructure = false
            for r in 0..<rows {
                if cellGroupSize[r * cols + maxHColumn] >= 3 { colHasGoodStructure = true; break }
            }
            if colHasGoodStructure || perCellPreChain[maxHColumn] > 0 {
                dynamicFactor = 0.75
            }
        }
        let risk = -Int(Double(900 * maxH)  * urgencyH  * dynamicFactor)
                 - Int(Double(85  * sumH)   * urgencySH)
                 - 3000 * fullCols

        // ── 6. clearing (base + brixTouchBonus) ──────────────────────────────────
        let clearing = 45 * nGe5 + 30 * nGe4 + 15 * nGe3 + brixTouchBonus

        // ── 7. brixPotential — version dynamique (remplace brixScore) ────────────
        // base  : récompense l'usure du Brix (comme v1)
        // +25   : si le Brix est 8-adjacent à un groupe ≥ 3 (prochaine chaîne probable)
        // +35   : si le Brix est 8-adjacent à une landing spot avec preChainScore ≥ 45
        var brixRaw = 0
        for r in 0..<rows {
            for c in 0..<cols {
                guard case .priks(let n) = grid[r][c] else { continue }
                var base = 40 * (5 - n)
                if r >= 5 { base -= 30 }

                var futureBonus = 0
                // Adjacent à un groupe couleur ≥ 3 ?
                for d in deltas8 {
                    let nr = r + d.dr, nc = c + d.dc
                    guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                    if cellGroupSize[nr * cols + nc] >= 3 { futureBonus += 25; break }
                }
                // Adjacent à une landing spot avec preChainScore ≥ 45 ?
                for d in deltas8 {
                    let nr = r + d.dr, nc = c + d.dc
                    guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                    guard grid[nr][nc] == .empty, landingRows[nc] == nr else { continue }
                    if perCellPreChain[nc] >= 45 { futureBonus += 35; break }
                }
                brixRaw += base + futureBonus
            }
        }
        let brixPotential = max(-550, brixRaw)

        // ── 8. Stabilité ─────────────────────────────────────────────────────────
        let stability = 4 * (10 - (moveCount % 10))   // [4 .. 40]

        return risk + clearing + brixPotential + stability + structure + accessibility + preChainScore
    }

    // MARK: - Lookahead 3 niveaux

    // MARK: - Bonus d'effacement immédiat

    /// Nombre de cases non vides dans une grille.
    private static func cellCount(_ g: SimGrid) -> Int {
        var n = 0
        for r in 0..<rows { for c in 0..<cols { if g[r][c] != .empty { n += 1 } } }
        return n
    }

    /// Bonus pour les blocs NET effacés entre deux états de grille (avant/après simulateDrop).
    /// Une chaîne de 5 efface 4 blocs nets (5 disparus − 1 posé) → bonus = 4 × 65 = 260 pts.
    /// Captures les bonnes chaînes qui appauvrissent temporairement la grille aux yeux de evaluate().
    private static func immediateClearing(before: SimGrid, after: SimGrid) -> Int {
        let net = cellCount(before) - cellCount(after)   // positif si des blocs ont disparu
        return max(0, net) * 65
    }

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

        // Les blocs Magix ont des effets non simulables : on retourne un résultat vide (pas de colonne optimale).
        if case .magix = piece0 {
            return BlomixLookAheadResult(optimalScore: 0, scorePerColumn: Array(repeating: nil, count: cols))
        }

        var scorePerCol: [Int?] = Array(repeating: nil, count: cols)
        var globalBest = Int.min

        for col0 in 0..<cols {
            guard piece0 != .empty else { continue }
            guard let (g1, mc1) = simulateDropAny(
                grid: grid, block: piece0, column: col0,
                moveCount: moveCount, pendingLine: pendingLine
            ) else { continue }

            // Bonus pour les blocs effacés par la chaîne du coup 0 (non capturés par evaluate(g3)).
            let bonus0 = immediateClearing(before: grid, after: g1)

            // Après niveau 1, la pendingLine a peut-être été injectée → inconnue pour niveaux 2+
            var best1 = Int.min

            for col1 in 0..<cols {
                guard piece1 != .empty else { continue }
                guard let (g2, mc2) = simulateDropAny(
                    grid: g1, block: piece1, column: col1,
                    moveCount: mc1, pendingLine: nil
                ) else { continue }

                let bonus1 = immediateClearing(before: g1, after: g2)

                for col2 in 0..<cols {
                    guard piece2 != .empty else { continue }
                    guard let (g3, mc3) = simulateDropAny(
                        grid: g2, block: piece2, column: col2,
                        moveCount: mc2, pendingLine: nil
                    ) else { continue }

                    let bonus2 = immediateClearing(before: g2, after: g3)
                    let s = evaluate(grid: g3, moveCount: mc3) + bonus0 + bonus1 + bonus2
                    if s > best1 { best1 = s }
                }
            }

            // Fallback si toutes les branches de niveau 2+ sont invalides :
            // on évalue directement la grille après niveau 1.
            if best1 == Int.min {
                best1 = evaluate(grid: g1, moveCount: mc1) + bonus0
            }

            scorePerCol[col0] = best1
            if best1 > globalBest { globalBest = best1 }
        }

        let optimal = globalBest == Int.min ? evaluate(grid: grid, moveCount: moveCount) : globalBest
        return BlomixLookAheadResult(optimalScore: optimal, scorePerColumn: scorePerCol)
    }
}

import XCTest
@testable import BLOMIX

/// Références sur `BlomixMoveAnalyzer`. `BlockType` vit dans `GameScene.swift` :
/// ce fichier reste dans la cible de test hébergée par l’app, pas dans le package.
final class AnalyzerReferenceTests: XCTestCase {

    private func emptyGrid() -> [[BlockType]] {
        Array(repeating: Array(repeating: BlockType.empty, count: 8), count: 8)
    }

    func testLandingRowAndFullColumn() {
        let grid = emptyGrid()
        XCTAssertEqual(BlomixMoveAnalyzer.landingRow(in: grid, column: 3), 0)
        XCTAssertNil(BlomixMoveAnalyzer.landingRow(in: grid, column: 8))
        var full = grid
        for row in 0..<8 { full[row][2] = .color("red") }
        XCTAssertNil(BlomixMoveAnalyzer.landingRow(in: full, column: 2))
    }

    func testFiveBlueClearsAndFourDoesNot() {
        var four = emptyGrid()
        for col in 0..<4 { four[0][col] = .color("blue") }
        let kept = BlomixMoveAnalyzer.resolveAll(four)
        for col in 0..<4 {
            XCTAssertEqual(kept[0][col], .color("blue"))
        }

        var five = emptyGrid()
        for col in 0..<5 { five[0][col] = .color("blue") }
        let cleared = BlomixMoveAnalyzer.resolveAll(five)
        for col in 0..<5 {
            XCTAssertEqual(cleared[0][col], .empty)
        }
    }

    func testMagixPieceIsNotScored() {
        let result = BlomixMoveAnalyzer.computeOptimal(
            grid: emptyGrid(),
            piece0: .magix(.bombx),
            piece1: .color("red"),
            piece2: .color("blue"),
            moveCount: 0,
            pendingLine: nil
        )
        XCTAssertEqual(result.optimalScore, 0)
        XCTAssertEqual(result.scorePerColumn.count, 8)
        XCTAssertTrue(result.scorePerColumn.allSatisfy { $0 == nil })
        XCTAssertNil(BlomixMoveAnalyzer.simulateDrop(
            grid: emptyGrid(),
            block: .magix(.cleanx),
            column: 0,
            moveCount: 0,
            pendingLine: nil
        ))
    }

    func testOptimalityPercentReferenceCases() {
        var stats = BlomixGameMoveStats()
        XCTAssertEqual(stats.optimalityPercent, 100)

        stats.append(BlomixMoveRecord(optimalScore: 100, chosenScore: 0, worstScore: 0))
        XCTAssertEqual(stats.optimalityPercent, 100)

        stats.reset()
        stats.append(BlomixMoveRecord(optimalScore: 1000, chosenScore: 0, worstScore: 0))
        XCTAssertEqual(stats.optimalityPercent, 0)

        stats.reset()
        stats.append(BlomixMoveRecord(optimalScore: 1000, chosenScore: 1000, worstScore: 0))
        XCTAssertEqual(stats.optimalityPercent, 100)
    }
}

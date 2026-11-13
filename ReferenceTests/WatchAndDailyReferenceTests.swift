import XCTest
@testable import WatchEngine
@testable import BlomixDailyRNG

final class WatchAndDailyReferenceTests: XCTestCase {

    func testChainScoreAndBombFootprint() {
        XCTAssertEqual(WatchZenRules.chainClearScorePoints(chainSeriesLevel: 0, groupSize: 5), 5)
        XCTAssertEqual(WatchZenRules.chainClearScorePoints(chainSeriesLevel: 1, groupSize: 5), 15)
        XCTAssertEqual(WatchZenRules.chainClearScorePoints(chainSeriesLevel: 0, groupSize: 6), 7)
        XCTAssertEqual(WatchZenRules.chainClearScorePoints(chainSeriesLevel: 0, groupSize: 10), 20)

        let corner = WatchZenRules.bombAffectedCells(center: WatchGridAddress(row: 0, col: 0))
        XCTAssertEqual(corner.count, 4)
        XCTAssertTrue(corner.contains(WatchGridAddress(row: 0, col: 0)))
        XCTAssertTrue(corner.contains(WatchGridAddress(row: 1, col: 1)))
        XCTAssertFalse(corner.contains(WatchGridAddress(row: 2, col: 0)))

        let mid = WatchZenRules.bombAffectedCells(center: WatchGridAddress(row: 3, col: 3))
        XCTAssertEqual(mid.count, 9)
    }

    func testBrixedWipesOtherPriksAndKeepsLanding() {
        var grid = WatchZenRules.emptyGrid()
        grid[2][2] = .priks(4)
        grid[4][1] = .priks(1)
        grid[1][1] = .color("blue")
        let landing = WatchGridAddress(row: 0, col: 0)
        let plan = WatchMagixResolve.plan(kind: .brixed, at: landing, grid: grid, chainSeriesLevel: 0)
        XCTAssertEqual(plan.bombDelta, 0)
        XCTAssertEqual(plan.scoreDelta, 40)
        XCTAssertEqual(plan.resultGrid[0][0], .priks(WatchMagixRules.brixedInitialHits))
        XCTAssertEqual(plan.resultGrid[2][2], .empty)
        XCTAssertEqual(plan.resultGrid[4][1], .empty)
        XCTAssertEqual(plan.resultGrid[1][1], .color("blue"))
        XCTAssertEqual(plan.wipe.count, 2)
    }

    func testCleanxTurnsLandingIntoPriksOfWipedCount() {
        var grid = WatchZenRules.emptyGrid()
        grid[1][1] = .color("red")
        grid[2][3] = .priks(2)
        let landing = WatchGridAddress(row: 0, col: 0)
        let plan = WatchMagixResolve.plan(kind: .cleanx, at: landing, grid: grid, chainSeriesLevel: 0)
        XCTAssertEqual(plan.scoreDelta, WatchZenRules.saintxBonusPoints)
        XCTAssertEqual(plan.bombDelta, 0)
        XCTAssertEqual(plan.wipe.count, 2)
        XCTAssertEqual(plan.resultGrid[0][0], .priks(2))
        XCTAssertEqual(plan.resultGrid[1][1], .empty)
        XCTAssertEqual(plan.resultGrid[2][3], .empty)
    }

    func testCrosxPaintsRowAndColumnOnly() {
        var grid = WatchZenRules.emptyGrid()
        grid[3][1] = .color("red")
        grid[3][6] = .priks(3)
        grid[0][4] = .color("blue")
        grid[5][5] = .color("green")
        let landing = WatchGridAddress(row: 3, col: 4)
        let plan = WatchMagixResolve.plan(kind: .crosx, at: landing, grid: grid, chainSeriesLevel: 0)
        XCTAssertEqual(plan.scoreDelta, 0)
        XCTAssertEqual(plan.bombDelta, 0)
        guard case .color(let painted) = plan.resultGrid[3][4] else {
            return XCTFail("la case d’arrivée doit être peinte")
        }
        XCTAssertEqual(plan.resultGrid[3][1], .color(painted))
        XCTAssertEqual(plan.resultGrid[3][6], .color(painted))
        XCTAssertEqual(plan.resultGrid[0][4], .color(painted))
        XCTAssertEqual(plan.resultGrid[5][5], .color("green"))
    }

    func testBombxGrantsOneBombWithoutScoring() {
        var grid = WatchZenRules.emptyGrid()
        grid[1][1] = .color("red")
        let landing = WatchGridAddress(row: 1, col: 0)
        let plan = WatchMagixResolve.plan(kind: .bombx, at: landing, grid: grid, chainSeriesLevel: 0)
        XCTAssertEqual(plan.bombDelta, 1)
        XCTAssertEqual(plan.scoreDelta, 0)
        guard case .color = plan.resultGrid[1][0] else {
            return XCTFail("BOMBX peint au moins la case d’arrivée")
        }
    }

    func testDailyFileRNGIsStableForAFixedSeed() {
        var a = BlomixDailyFileRNG(seed: 1)
        var b = BlomixDailyFileRNG(seed: 0)
        let first = a.nextUInt64()
        XCTAssertEqual(first, 6_364_136_223_846_793_006)
        XCTAssertEqual(b.nextUInt64(), first)
        XCTAssertEqual(a.nextUInt64(), 13_885_033_948_157_127_959)
        XCTAssertEqual(a.nextUInt64(), 14_678_909_342_070_756_876)
        XCTAssertEqual(a.nextUInt64(), 14_340_359_694_176_818_205)
        var again = BlomixDailyFileRNG(seed: 1)
        var replay: [UInt64] = []
        for _ in 0..<4 { replay.append(again.nextUInt64()) }
        XCTAssertEqual(replay, [
            6_364_136_223_846_793_006,
            13_885_033_948_157_127_959,
            14_678_909_342_070_756_876,
            14_340_359_694_176_818_205,
        ])
    }

    func testDailySeedSeparatesArcadeAndFive() {
        let day = "2026-11-13"
        let arcade = BlomixDailySeed.seed(forDay: day)
        let five = BlomixDailySeed.seed(forDay: day, salt: BlomixDailySeed.fiveSalt)
        XCTAssertEqual(arcade, 9_106_842_356_666_756_806)
        XCTAssertEqual(five, 16_975_958_191_775_742_943)
        XCTAssertNotEqual(arcade, five)
        XCTAssertEqual(BlomixDailySeed.seed(forDay: day), arcade)
    }

    func testDailyEffectRNGDoesNotDependOnTheFile() {
        let day = BlomixDailySeed.seed(forDay: "2026-11-13")
        var fx = BlomixDailyEffectRNG(daySeed: day, event: "bombx", moveCount: 3, row: 1, col: 2)
        XCTAssertEqual(fx.nextUInt64(), 2_129_943_815_899_060_339)
        var again = BlomixDailyEffectRNG(daySeed: day, event: "bombx", moveCount: 3, row: 1, col: 2)
        XCTAssertEqual(again.nextUInt64(), 2_129_943_815_899_060_339)
        var other = BlomixDailyEffectRNG(daySeed: day, event: "bombx", moveCount: 4, row: 1, col: 2)
        XCTAssertNotEqual(other.nextUInt64(), 2_129_943_815_899_060_339)
    }
}

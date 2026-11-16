import CoreText
import UIKit
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

/// Le lavis doit peindre les cases posées, pas leur miroir.
final class InkMaskOrientationTests: XCTestCase {

    func testDiagonalPairStaysOnItsCorners() {
        let canvas = CGSize(width: 80, height: 80)
        let topLeft = CGPath(
            roundedRect: CGRect(x: 4, y: 4, width: 32, height: 32),
            cornerWidth: 4, cornerHeight: 4, transform: nil
        )
        let bottomRight = CGPath(
            roundedRect: CGRect(x: 44, y: 44, width: 32, height: 32),
            cornerWidth: 4, cornerHeight: 4, transform: nil
        )
        let image = render(canvas: canvas, paths: [topLeft, bottomRight])
        XCTAssertGreaterThan(coverage(image, x: 20, y: 20), 80, "haut gauche posé")
        XCTAssertGreaterThan(coverage(image, x: 60, y: 60), 80, "bas droit posé")
        XCTAssertLessThan(coverage(image, x: 60, y: 20), 20, "haut droit vide")
        XCTAssertLessThan(coverage(image, x: 20, y: 60), 20, "bas gauche vide")
    }

    func testSideBySidePairStaysOnItsRow() {
        let canvas = CGSize(width: 80, height: 80)
        let left = CGPath(
            roundedRect: CGRect(x: 4, y: 4, width: 32, height: 32),
            cornerWidth: 4, cornerHeight: 4, transform: nil
        )
        let right = CGPath(
            roundedRect: CGRect(x: 44, y: 4, width: 32, height: 32),
            cornerWidth: 4, cornerHeight: 4, transform: nil
        )
        let image = render(canvas: canvas, paths: [left, right])
        XCTAssertGreaterThan(coverage(image, x: 20, y: 20), 80)
        XCTAssertGreaterThan(coverage(image, x: 60, y: 20), 80)
        XCTAssertLessThan(coverage(image, x: 20, y: 60), 20)
        XCTAssertLessThan(coverage(image, x: 60, y: 60), 20)
    }

    /// Encre : la diagonale s'arrête au bord des blox. Elle ne traverse pas les cases.
    func testEncreDiagonalIsOnlyTheGapBetweenCells() {
        let pitch: CGFloat = 40
        let cells: Set<BlomixNewBlockRenderer.FusionRC> = [
            .init(row: 0, col: 0),
            .init(row: 1, col: 1)
        ]
        let silhouette = BlomixNewBlockRenderer.fusionSilhouette(
            cells: cells, minRow: 0, minCol: 0, cellPitch: pitch
        )
        XCTAssertEqual(silhouette.bridges.count, 1)
        let bridge = silhouette.bridges[0]
        let box = bridge.boundingBox
        XCTAssertLessThan(max(box.width, box.height), 18, "le pont ne va pas d'un centre à l'autre")
        XCTAssertGreaterThan(min(box.width, box.height), 4, "le pont couvre l'écart")
        XCTAssertFalse(bridge.contains(CGPoint(x: 30, y: 30)), "le centre de la case n'est pas dans le pont")
        XCTAssertTrue(bridge.contains(CGPoint(x: 50, y: 50)), "le milieu de l'écart est dans le pont")

        let canvas = CGSize(width: 100, height: 100)
        let image = render(
            canvas: canvas,
            paths: silhouette.bodies + silhouette.bridges,
            bodyPaths: silhouette.bodies,
            bridgePaths: silhouette.bridges
        )
        XCTAssertGreaterThan(coverage(image, x: 30, y: 30), 80, "la case reste encrée")
        XCTAssertGreaterThan(coverage(image, x: 50, y: 50), 40, "l'écart entre les blox est encré")
        XCTAssertLessThan(coverage(image, x: 50, y: 30), 20, "à côté de la case, pas de barre")
    }

    /// Le pont hors de la case s'efface. La case elle-même reste couverte.
    func testDiagonalBridgeFadesOutsideTheCell() {
        let canvas = CGSize(width: 80, height: 40)
        let body = CGPath(
            roundedRect: CGRect(x: 4, y: 4, width: 32, height: 32),
            cornerWidth: 4, cornerHeight: 4, transform: nil
        )
        let bridge = CGPath(
            roundedRect: CGRect(x: 24, y: 16, width: 48, height: 6),
            cornerWidth: 3, cornerHeight: 3, transform: nil
        )
        let image = render(canvas: canvas, paths: [body, bridge], bodyPaths: [body], bridgePaths: [bridge])
        XCTAssertGreaterThan(coverage(image, x: 16, y: 20), 80, "la case reste encrée")
        let xs = [44, 52, 60]
        let core = averageCoverage(image, points: xs.map { ($0, 19) })
        let edge = averageCoverage(image, points: xs.flatMap { x in [(x, 16), (x, 21)] })
        XCTAssertGreaterThan(core, 40, "le milieu du pont reste encré")
        XCTAssertLessThan(edge, core / 2, "le bord du pont ne fait pas un trait")
    }

    private func render(
        canvas: CGSize,
        paths: [CGPath],
        bodyPaths: [CGPath] = [],
        bridgePaths: [CGPath] = []
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            BlomixNewInkRenderer.drawMask(
                in: context.cgContext,
                paths: paths,
                seed: 1,
                canvas: canvas,
                rim: 0.95,
                bodyPaths: bodyPaths,
                bridgePaths: bridgePaths
            )
        }
    }

    private func coverage(_ image: UIImage, x: Int, y: Int) -> Int {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data),
              x >= 0, y >= 0, x < cg.width, y < cg.height else { return -1 }
        let bpp = max(1, cg.bitsPerPixel / 8)
        let p = ptr + y * cg.bytesPerRow + x * bpp
        var peak = 0
        for i in 0..<bpp { peak = max(peak, Int(p[i])) }
        return peak
    }

    private func averageCoverage(_ image: UIImage, points: [(Int, Int)]) -> Int {
        let samples = points.map { coverage(image, x: $0.0, y: $0.1) }
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / samples.count
    }
}

/// Le gros score Encre est le lavis dans les chiffres. Pas un rectangle autour.
final class ScoreGlyphWashTests: XCTestCase {

    func testWashStaysInsideUprightDigitsAndKeepsCounters() {
        let font = displayFont(size: 52)
        guard let layout = BlomixNewInkRenderer.scoreGlyphLayout(text: "804", font: font),
              let wash = BlomixNewInkRenderer.scoreGlyphImage(text: "804", font: font, light: true, scale: 2)
        else {
            XCTFail("pas de glyphes")
            return
        }
        let reference = uprightReference(text: "804", font: font, layout: layout, scale: 2)
        let washMap = alphaMap(wash)
        let refMap = alphaMap(reference)
        XCTAssertEqual(washMap.width, refMap.width)
        XCTAssertEqual(washMap.height, refMap.height)

        let w = washMap.width
        let h = washMap.height
        XCTAssertLessThan(washMap.alpha[0], 12, "coin haut gauche vide")
        XCTAssertLessThan(washMap.alpha[w - 1], 12, "coin haut droit vide")
        XCTAssertLessThan(washMap.alpha[(h - 1) * w], 12, "coin bas gauche vide")
        XCTAssertLessThan(washMap.alpha[h * w - 1], 12, "coin bas droit vide")

        var washInk = 0
        var overlap = 0
        var outside = 0
        for i in 0..<(w * h) {
            let painted = washMap.alpha[i] > 40
            if painted {
                washInk += 1
                if refMap.alpha[i] > 20 || neighborInk(refMap, index: i) {
                    overlap += 1
                } else {
                    outside += 1
                }
            }
        }
        XCTAssertGreaterThan(washInk, 200, "les chiffres sont encrés")
        XCTAssertLessThan(Double(washInk) / Double(w * h), 0.55, "pas un rectangle plein")
        XCTAssertEqual(outside, 0, "le lavis ne dépasse pas des glyphes")
        XCTAssertGreaterThan(Double(overlap) / Double(washInk), 0.98)

        assertCounterIsClear(text: "0", font: font)
        assertCounterIsClear(text: "8", font: font)
        assertCounterIsClear(text: "6", font: font)
    }

    /// Le trou du chiffre reste transparent, à la même place que le glyphe debout.
    private func assertCounterIsClear(text: String, font: UIFont) {
        guard let layout = BlomixNewInkRenderer.scoreGlyphLayout(text: text, font: font),
              let wash = BlomixNewInkRenderer.scoreGlyphImage(text: text, font: font, light: true, scale: 2)
        else {
            XCTFail("pas de glyphe \(text)")
            return
        }
        let reference = uprightReference(text: text, font: font, layout: layout, scale: 2)
        guard let hole = counterCentroid(alphaMap(reference), clearBelow: 20) else {
            XCTFail("pas de contreforme dans \(text)")
            return
        }
        let washMap = alphaMap(wash)
        XCTAssertLessThan(
            washMap.alpha[hole.y * washMap.width + hole.x],
            15,
            "le trou de \(text) est peint"
        )
        guard let washHole = counterCentroid(washMap, clearBelow: 20) else {
            XCTFail("le lavis bouche \(text)")
            return
        }
        XCTAssertLessThan(abs(washHole.x - hole.x), 4)
        XCTAssertLessThan(abs(washHole.y - hole.y), 4)
    }

    private func displayFont(size: CGFloat) -> UIFont {
        let name = "ChelseaMarket-Regular"
        if UIFont(name: name, size: size) == nil,
           let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
    }

    /// Même baseline que le masque. `CTLineDraw` avec ce retournement est debout dans un contexte UIKit.
    private func uprightReference(
        text: String,
        font: UIFont,
        layout: BlomixNewInkRenderer.ScoreGlyphLayout,
        scale: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: layout.canvas, format: format).image { context in
            let ctx = context.cgContext
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black])
            )
            ctx.textMatrix = .identity
            ctx.translateBy(x: layout.originX, y: layout.baselineFromTop)
            ctx.scaleBy(x: 1, y: -1)
            CTLineDraw(line, ctx)
        }
    }

    private struct AlphaMap {
        var alpha: [UInt8]
        var width: Int
        var height: Int
    }

    private func alphaMap(_ image: UIImage) -> AlphaMap {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return AlphaMap(alpha: [], width: 0, height: 0)
        }
        let width = cg.width
        let height = cg.height
        let bpp = max(1, cg.bitsPerPixel / 8)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let p = ptr + y * cg.bytesPerRow + x * bpp
                var peak = 0
                for i in 0..<bpp { peak = max(peak, Int(p[i])) }
                alpha[y * width + x] = UInt8(min(255, peak))
            }
        }
        return AlphaMap(alpha: alpha, width: width, height: height)
    }

    private func neighborInk(_ map: AlphaMap, index: Int) -> Bool {
        let x = index % map.width
        let y = index / map.width
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x + dx
                let ny = y + dy
                guard nx >= 0, ny >= 0, nx < map.width, ny < map.height else { continue }
                if map.alpha[ny * map.width + nx] > 20 { return true }
            }
        }
        return false
    }

    /// Centroïde du plus grand trou fermé (un seul, pas la moyenne de deux contreformes).
    private func counterCentroid(_ map: AlphaMap, clearBelow: UInt8) -> (x: Int, y: Int)? {
        let w = map.width
        let h = map.height
        guard w > 2, h > 2 else { return nil }
        var seen = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        func pushOutside(_ i: Int) {
            guard map.alpha[i] < clearBelow, !seen[i] else { return }
            seen[i] = true
            stack.append(i)
        }
        for x in 0..<w {
            pushOutside(x)
            pushOutside((h - 1) * w + x)
        }
        for y in 0..<h {
            pushOutside(y * w)
            pushOutside(y * w + w - 1)
        }
        while let i = stack.popLast() {
            let x = i % w
            let y = i / w
            if x > 0 { pushOutside(i - 1) }
            if x + 1 < w { pushOutside(i + 1) }
            if y > 0 { pushOutside(i - w) }
            if y + 1 < h { pushOutside(i + w) }
        }
        var bestCount = 0
        var bestX = 0
        var bestY = 0
        for start in 0..<(w * h) where map.alpha[start] < clearBelow && !seen[start] {
            var count = 0
            var sumX = 0
            var sumY = 0
            seen[start] = true
            stack = [start]
            while let i = stack.popLast() {
                count += 1
                sumX += i % w
                sumY += i / w
                let x = i % w
                let y = i / w
                for next in [i - 1, i + 1, i - w, i + w] {
                    guard next >= 0, next < w * h else { continue }
                    if next == i - 1, x == 0 { continue }
                    if next == i + 1, x + 1 == w { continue }
                    guard map.alpha[next] < clearBelow, !seen[next] else { continue }
                    seen[next] = true
                    stack.append(next)
                }
            }
            if count > bestCount {
                bestCount = count
                bestX = sumX / count
                bestY = sumY / count
            }
        }
        guard bestCount > 8 else { return nil }
        return (bestX, bestY)
    }
}

//
//  BlomixNewBlockRenderer.swift
//  Blomix
//
//  Blox couleur du look New. La géométrie reste celle des pièces fusionnées.
//  La matière est l'encre (`BlomixNewInkRenderer`) : plus de reflet gelée.
//  Textures Core Graphics, mises en cache. Pas de shader par bloc.
//
//  La texture est un masque (gris), pas la teinte du skin.
//  Le sprite porte `color` = teinte et `colorBlendFactor` = 1, donc les
//  animations qui écrivent `sprite.color` (dissolution, SAINTX) restent valables.
//
//  Grille New : une texture par groupe de Blox de même couleur (8-connexité).
//  L'orthogonal est une seule pièce (coins extérieurs et intérieurs arrondis).
//  Une diagonale déjà dans cette pièce n'est pas redessinée. Une diagonale seule
//  est un trait de la même matière, largeur du trait Classique (sqrt(32)), dans
//  le même contour. Pas un disque au coin.
//

import SpriteKit
import UIKit

enum BlomixNewBlockRenderer {

    /// Blox ou Brix en encre. Taille, ancre (0,5, 0,5). `fill` = teinte du skin.
    /// MainActor : `SKSpriteNode` l’exige. La fabrique de `GameScene` l’est déjà.
    @MainActor
    static func makeColorSprite(fill: SKColor, pointSize: CGSize) -> SKSpriteNode {
        let sprite = SKSpriteNode()
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        applyJelly(to: sprite, fill: fill, pointSize: pointSize)
        return sprite
    }

    /// Même matière sur un sprite déjà en place (file, aperçu, mue). Retire un vieux reflet.
    @MainActor
    static func applyJelly(to sprite: SKSpriteNode, fill: SKColor, pointSize: CGSize) {
        sprite.childNode(withName: specularNodeName)?.removeFromParent()
        guard pointSize.width > 1, pointSize.height > 1 else {
            sprite.texture = nil
            sprite.color = fill
            sprite.colorBlendFactor = 1
            sprite.size = pointSize
            return
        }

        let channels = rgba(of: fill)
        let light = BlomixAppearance.isLight
        let scale = max(1, UITraitCollection.current.displayScale)
        let key = CacheKey(
            r: channels.r,
            g: channels.g,
            b: channels.b,
            a: channels.a,
            pixelWidth: max(1, Int((pointSize.width * scale).rounded())),
            pixelHeight: max(1, Int((pointSize.height * scale).rounded())),
            light: light
        )
        let texture = cache.jellyTexture(for: key) {
            bakeJellyMask(
                pointSize: pointSize,
                scale: scale,
                red: CGFloat(channels.r) / 255,
                green: CGFloat(channels.g) / 255,
                blue: CGFloat(channels.b) / 255,
                light: light
            )
        }

        sprite.texture = texture
        sprite.size = pointSize
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.color = fill
        sprite.colorBlendFactor = 1
    }

    /// Nom de l'enfant-reflet. N'est pas un chiffre Priks ni un halo Magix.
    static let specularNodeName = "blomixNewSpecular"

    // MARK: - Cache

    private struct CacheKey: Hashable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
        var pixelWidth: Int
        var pixelHeight: Int
        var light: Bool
    }

    private struct JunctionKey: Hashable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
        var pixelWidth: Int
        var pixelHeight: Int
        var vertical: Bool
        var light: Bool
    }

    private static let cache = TextureCache()

    private final class TextureCache: @unchecked Sendable {
        private let lock = NSLock()
        private var jellies: [CacheKey: SKTexture] = [:]
        private var junctions: [JunctionKey: SKTexture] = [:]
        private var fusions: [FusionKey: SKTexture] = [:]

        func jellyTexture(for key: CacheKey, make: () -> SKTexture) -> SKTexture {
            lock.lock()
            if let hit = jellies[key] {
                lock.unlock()
                return hit
            }
            lock.unlock()
            let built = make()
            lock.lock()
            if let hit = jellies[key] {
                lock.unlock()
                return hit
            }
            jellies[key] = built
            lock.unlock()
            return built
        }

        func junctionTexture(for key: JunctionKey, make: () -> SKTexture) -> SKTexture {
            lock.lock()
            if let hit = junctions[key] {
                lock.unlock()
                return hit
            }
            lock.unlock()
            let built = make()
            lock.lock()
            if let hit = junctions[key] {
                lock.unlock()
                return hit
            }
            junctions[key] = built
            lock.unlock()
            return built
        }

        func fusionTexture(for key: FusionKey, make: () -> SKTexture) -> SKTexture {
            lock.lock()
            if let hit = fusions[key] {
                lock.unlock()
                return hit
            }
            lock.unlock()
            let built = make()
            lock.lock()
            if let hit = fusions[key] {
                lock.unlock()
                return hit
            }
            fusions[key] = built
            lock.unlock()
            return built
        }
    }

    // MARK: - Géométrie

    /// Corps dans le carré du sprite (UIKit, y vers le bas) et reflet (SpriteKit, y vers le haut).
    private struct FaceLayout {
        var body: CGRect
        var radius: CGFloat
        var ring: CGFloat
        var shadowRoom: CGFloat
        var glintCenter: CGPoint
        var glintSize: CGSize
    }

    private static func faceLayout(for size: CGSize) -> FaceLayout {
        let m = min(size.width, size.height)
        // Marge très mince : avec un sprite de grille `cell − 1`, le filet entre
        // deux corps tombe vers 2 pt (maquette). Le liseré reste dans cette marge.
        let margin = max(0.45, m * 0.012)
        let shadowRoom = max(0.65, m * 0.018)
        let body = CGRect(
            x: margin,
            y: margin,
            width: max(1, size.width - 2 * margin),
            height: max(1, size.height - 2 * margin)
        )
        let radius = min(body.width, body.height) * 0.12
        let ring = min(margin * 0.85, max(0.40, m * 0.011))
        // Reflet net, haut-gauche du corps.
        let gx = body.minX + body.width * 0.30
        let gy = body.minY + body.height * 0.24
        let center = CGPoint(x: gx - size.width / 2, y: size.height / 2 - gy)
        let glintSize = CGSize(width: body.width * 0.46, height: body.height * 0.20)
        return FaceLayout(
            body: body,
            radius: radius,
            ring: ring,
            shadowRoom: shadowRoom,
            glintCenter: center,
            glintSize: glintSize
        )
    }

    /// Pont orthogonal entre deux Blox de même couleur.
    /// Horizontal : voisins gauche/droite, même dégradé que le corps (clair en haut).
    /// Vertical : voisins haut/bas, sombre en haut de la fente (bas du bloc du dessus), clair en bas.
    enum JunctionAxis {
        case horizontal
        case vertical
    }

    /// `span` = plat du contact (sans entrer dans les coins). `thickness` = fente + recouvrement du liseré.
    static func orthogonalBridgeSize(blockPointSize: CGSize, cellPitch: CGFloat) -> (span: CGFloat, thickness: CGFloat) {
        let face = faceLayout(for: blockPointSize)
        // Le plat, plus un rien dans le congé : le bord du pont prolonge la tangente du coin.
        let span = max(4, face.body.height - 2 * face.radius + 1.2)
        let insetTop = face.body.minY
        let insetBottom = blockPointSize.height - face.body.maxY
        let visualGap = (cellPitch - blockPointSize.height) + insetTop + insetBottom
        let thickness = visualGap + face.ring * 2 + 0.8
        return (span, thickness)
    }

    /// Barre de jonction en gelée. `color` = teinte, `colorBlendFactor` = 1.
    @MainActor
    static func makeJunctionSprite(fill: SKColor, size: CGSize, axis: JunctionAxis) -> SKSpriteNode {
        guard size.width > 1, size.height > 1 else {
            let fallback = SKSpriteNode(color: fill, size: size)
            fallback.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            fallback.colorBlendFactor = 1
            return fallback
        }
        let channels = rgba(of: fill)
        let light = BlomixAppearance.isLight
        let scale = max(1, UITraitCollection.current.displayScale)
        let key = JunctionKey(
            r: channels.r,
            g: channels.g,
            b: channels.b,
            a: channels.a,
            pixelWidth: max(1, Int((size.width * scale).rounded())),
            pixelHeight: max(1, Int((size.height * scale).rounded())),
            vertical: axis == .vertical,
            light: light
        )
        let texture = cache.junctionTexture(for: key) {
            bakeJunctionMask(pointSize: size, scale: scale, vertical: axis == .vertical)
        }
        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.color = fill
        sprite.colorBlendFactor = 1
        return sprite
    }

    /// Bassin de pigment, très léger. Les teintes claires descendent un peu plus
    /// pour rester lisibles sur le washi, sans liseré gris.
    private static func edgeMultiplier(red: CGFloat, green: CGFloat, blue: CGFloat, light: Bool) -> CGFloat {
        let lum = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        if light {
            return max(0.84, 0.98 - 0.10 * lum)
        }
        return max(0.90, 0.99 - 0.05 * lum)
    }

    // MARK: - Cuisson

    private static func bakeJellyMask(
        pointSize: CGSize,
        scale: CGFloat,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        light: Bool
    ) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let edge = edgeMultiplier(red: red, green: green, blue: blue, light: light)
        let image = renderer.image { context in
            drawJellyMask(
                in: context.cgContext,
                pointSize: pointSize,
                edge: edge,
                red: red,
                green: green,
                blue: blue
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func drawJellyMask(
        in ctx: CGContext,
        pointSize: CGSize,
        edge: CGFloat,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) {
        let face = faceLayout(for: pointSize)
        let bodyPath = CGPath(
            roundedRect: face.body,
            cornerWidth: face.radius,
            cornerHeight: face.radius,
            transform: nil
        )
        BlomixNewInkRenderer.drawMask(
            in: ctx,
            paths: [bodyPath],
            seed: BlomixNewInkRenderer.seed(red: red, green: green, blue: blue),
            canvas: pointSize,
            rim: edge
        )
    }

    private static func bakeJunctionMask(pointSize: CGSize, scale: CGFloat, vertical: Bool) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let image = renderer.image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: pointSize)
            // Bouts presque droits : un gros rayon ferait un goulot entre les deux Blox.
            let radius = min(1.15, min(pointSize.width, pointSize.height) * 0.12)
            let path = CGPath(roundedRect: rect.insetBy(dx: 0.2, dy: 0.2), cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(path)
            ctx.clip()
            // Encre dans la fente : plus dense au bord, sans reflet.
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(white: 0.90, alpha: 1).cgColor,
                    UIColor(white: vertical ? 0.72 : 0.78, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) else { return }
            let start = vertical
                ? CGPoint(x: 0, y: pointSize.height / 2)
                : CGPoint(x: pointSize.width / 2, y: 0)
            let end = vertical
                ? CGPoint(x: pointSize.width, y: pointSize.height / 2)
                : CGPoint(x: pointSize.width / 2, y: pointSize.height)
            ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func rgba(of color: SKColor) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        let ui = color
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return (115, 115, 115, 255)
        }
        return (byte(r), byte(g), byte(b), byte(a))
    }

    private static func byte(_ channel: CGFloat) -> UInt8 {
        UInt8(min(255, max(0, Int((channel * 255).rounded()))))
    }

    // MARK: - Forme complète (groupe de même couleur)

    private struct FusionKey: Hashable {
        var signature: String
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
        var light: Bool
        var scale: Int
    }

    private struct FusionRC: Hashable {
        var row: Int
        var col: Int
    }

    /// Marge autour du groupe pour l'ombre. Le corps, lui, s'arrête à 1 pt du bord de case.
    private static let fusionPad: CGFloat = 10
    private static let fusionInset: CGFloat = 1
    private static let fusionCornerRadius: CGFloat = 4.6
    /// Demi-largeur du trait diagonal Classique (`lineWidth = sqrt(32)`).
    private static let fusionDiagonalHalfWidth: CGFloat = 2.82842712475

    /// Une pièce gelée pour tout le groupe. `cellCenter` est dans le repère du conteneur (y vers le haut).
    /// Le masque suit la même règle que les Blox isolés : `color` = teinte, `colorBlendFactor` = 1.
    @MainActor
    static func makeFusionSprite(
        cells: [(row: Int, col: Int)],
        fill: SKColor,
        cellPitch: CGFloat,
        cellCenter: (Int, Int) -> CGPoint
    ) -> SKSpriteNode {
        let points = cells.map { FusionRC(row: $0.row, col: $0.col) }
        guard let minR = points.map(\.row).min(),
              let maxR = points.map(\.row).max(),
              let minC = points.map(\.col).min(),
              let maxC = points.map(\.col).max(),
              cellPitch > 1 else {
            let empty = SKSpriteNode(color: fill, size: CGSize(width: 1, height: 1))
            empty.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            return empty
        }
        let cols = maxC - minC + 1
        let rows = maxR - minR + 1
        let size = CGSize(
            width: CGFloat(cols) * cellPitch + 2 * fusionPad,
            height: CGFloat(rows) * cellPitch + 2 * fusionPad
        )
        let anchor = cellCenter(minR, minC)
        let center = CGPoint(
            x: anchor.x - cellPitch / 2 + CGFloat(cols) * cellPitch / 2,
            y: anchor.y + cellPitch / 2 - CGFloat(rows) * cellPitch / 2
        )

        let channels = rgba(of: fill)
        let light = BlomixAppearance.isLight
        let scale = max(1, UITraitCollection.current.displayScale)
        let signature = points
            .map { "\($0.row - minR)_\($0.col - minC)" }
            .sorted()
            .joined(separator: ",")
        let key = FusionKey(
            signature: signature,
            r: channels.r, g: channels.g, b: channels.b, a: channels.a,
            light: light,
            scale: Int(scale.rounded())
        )
        let texture = cache.fusionTexture(for: key) {
            bakeFusionMask(
                cells: Set(points),
                minRow: minR,
                minCol: minC,
                pointSize: size,
                cellPitch: cellPitch,
                red: CGFloat(channels.r) / 255,
                green: CGFloat(channels.g) / 255,
                blue: CGFloat(channels.b) / 255,
                light: light,
                scale: scale
            )
        }

        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.position = center
        sprite.color = fill
        sprite.colorBlendFactor = 1
        return sprite
    }

    private static func bakeFusionMask(
        cells: Set<FusionRC>,
        minRow: Int,
        minCol: Int,
        pointSize: CGSize,
        cellPitch: CGFloat,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        light: Bool,
        scale: CGFloat
    ) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let edge = edgeMultiplier(red: red, green: green, blue: blue, light: light)
        let paths = fusionPaths(cells: cells, minRow: minRow, minCol: minCol, cellPitch: cellPitch)
        let salt = cells.reduce(0) { $0 &+ $1.row &* 17 &+ $1.col }
        let image = renderer.image { context in
            BlomixNewInkRenderer.drawMask(
                in: context.cgContext,
                paths: paths,
                seed: BlomixNewInkRenderer.seed(red: red, green: green, blue: blue, salt: salt),
                canvas: pointSize,
                rim: edge
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Contours arrondis des pièces orthogonales, plus un trait (capsule) pour chaque
    /// diagonale qui relie deux pièces distinctes. Même largeur que le trait Classique.
    /// L'ensemble est une seule silhouette.
    private static func fusionPaths(
        cells: Set<FusionRC>,
        minRow: Int,
        minCol: Int,
        cellPitch: CGFloat
    ) -> [CGPath] {
        var paths: [CGPath] = []
        for loop in orthogonalLoops(cells: cells, minRow: minRow, minCol: minCol, cellPitch: cellPitch) where loop.count >= 3 {
            paths.append(roundedOrthogonalPath(loop))
        }
        let ids = orthogonalComponentIDs(cells)
        var seen = Set<String>()
        for cell in cells {
            for delta in [(1, 1), (1, -1)] {
                let other = FusionRC(row: cell.row + delta.0, col: cell.col + delta.1)
                guard cells.contains(other), ids[cell] != ids[other] else { continue }
                let key = [cell, other]
                    .map { "\($0.row),\($0.col)" }
                    .sorted()
                    .joined(separator: "|")
                guard seen.insert(key).inserted else { continue }
                let a = CGPoint(
                    x: fusionPad + (CGFloat(cell.col - minCol) + 0.5) * cellPitch,
                    y: fusionPad + (CGFloat(cell.row - minRow) + 0.5) * cellPitch
                )
                let b = CGPoint(
                    x: fusionPad + (CGFloat(other.col - minCol) + 0.5) * cellPitch,
                    y: fusionPad + (CGFloat(other.row - minRow) + 0.5) * cellPitch
                )
                paths.append(diagonalBarPath(from: a, to: b, halfWidth: fusionDiagonalHalfWidth))
            }
        }
        if paths.isEmpty {
            for cell in cells {
                let rect = CGRect(
                    x: fusionPad + CGFloat(cell.col - minCol) * cellPitch + fusionInset,
                    y: fusionPad + CGFloat(cell.row - minRow) * cellPitch + fusionInset,
                    width: cellPitch - 2 * fusionInset,
                    height: cellPitch - 2 * fusionInset
                )
                paths.append(CGPath(roundedRect: rect, cornerWidth: fusionCornerRadius, cornerHeight: fusionCornerRadius, transform: nil))
            }
        }
        return paths
    }

    /// Trait diagonal : capsule centre à centre, bouts ronds, même épaisseur que Classique.
    /// Parcours de même signe que le contour orthogonal : le remplissage ajoute le trait.
    private static func diagonalBarPath(from a: CGPoint, to b: CGPoint, halfWidth: CGFloat) -> CGPath {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.01 else {
            return CGPath(
                ellipseIn: CGRect(x: a.x - halfWidth, y: a.y - halfWidth, width: halfWidth * 2, height: halfWidth * 2),
                transform: nil
            )
        }
        let ux = dx / length
        let uy = dy / length
        let px = -uy * halfWidth
        let py = ux * halfWidth
        let path = CGMutablePath()
        path.move(to: CGPoint(x: a.x - px, y: a.y - py))
        path.addLine(to: CGPoint(x: b.x - px, y: b.y - py))
        path.addArc(
            center: b,
            radius: halfWidth,
            startAngle: atan2(-py, -px),
            endAngle: atan2(py, px),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: a.x + px, y: a.y + py))
        path.addArc(
            center: a,
            radius: halfWidth,
            startAngle: atan2(py, px),
            endAngle: atan2(-py, -px),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private static func orthogonalComponentIDs(_ cells: Set<FusionRC>) -> [FusionRC: Int] {
        var ids: [FusionRC: Int] = [:]
        var next = 0
        let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for start in cells where ids[start] == nil {
            var stack = [start]
            ids[start] = next
            while let cell = stack.popLast() {
                for dir in dirs {
                    let neighbor = FusionRC(row: cell.row + dir.0, col: cell.col + dir.1)
                    guard cells.contains(neighbor), ids[neighbor] == nil else { continue }
                    ids[neighbor] = next
                    stack.append(neighbor)
                }
            }
            next += 1
        }
        return ids
    }

    /// Coins du contour, y vers le bas, pas de pitch. Intérieur à droite.
    private static func orthogonalLoops(
        cells: Set<FusionRC>,
        minRow: Int,
        minCol: Int,
        cellPitch: CGFloat
    ) -> [[CGPoint]] {
        let dirs = [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1)]
        func interior(_ cx: Int, _ cy: Int, _ dir: Int) -> FusionRC {
            switch dir {
            case 0: return FusionRC(row: cy + minRow, col: cx + minCol)
            case 1: return FusionRC(row: cy + minRow, col: cx - 1 + minCol)
            case 2: return FusionRC(row: cy - 1 + minRow, col: cx - 1 + minCol)
            default: return FusionRC(row: cy - 1 + minRow, col: cx + minCol)
            }
        }
        func exterior(_ cx: Int, _ cy: Int, _ dir: Int) -> FusionRC {
            switch dir {
            case 0: return FusionRC(row: cy - 1 + minRow, col: cx + minCol)
            case 1: return FusionRC(row: cy + minRow, col: cx + minCol)
            case 2: return FusionRC(row: cy + minRow, col: cx - 1 + minCol)
            default: return FusionRC(row: cy - 1 + minRow, col: cx - 1 + minCol)
            }
        }
        func isBoundary(_ cx: Int, _ cy: Int, _ dir: Int) -> Bool {
            cells.contains(interior(cx, cy, dir)) && !cells.contains(exterior(cx, cy, dir))
        }
        struct Edge: Hashable { var cx, cy, dir: Int }
        var unused = Set<Edge>()
        let rel = cells.map { FusionRC(row: $0.row - minRow, col: $0.col - minCol) }
        let maxC = rel.map(\.col).max() ?? 0
        let maxR = rel.map(\.row).max() ?? 0
        for cy in 0...maxR + 1 {
            for cx in 0...maxC + 1 {
                for dir in 0..<4 where isBoundary(cx, cy, dir) {
                    unused.insert(Edge(cx: cx, cy: cy, dir: dir))
                }
            }
        }
        var loops: [[CGPoint]] = []
        while let start = unused.min(by: { ($0.cy, $0.cx, $0.dir) < ($1.cy, $1.cx, $1.dir) }) {
            var cx = start.cx
            var cy = start.cy
            var dir = start.dir
            var corners: [CGPoint] = []
            var guardSteps = 0
            repeat {
                unused.remove(Edge(cx: cx, cy: cy, dir: dir))
                let previous = dir
                cx += Int(dirs[dir].x)
                cy += Int(dirs[dir].y)
                let prefer = [(dir + 1) % 4, dir, (dir + 3) % 4, (dir + 2) % 4]
                var next = dir
                for candidate in prefer where isBoundary(cx, cy, candidate) {
                    next = candidate
                    break
                }
                if next != previous {
                    corners.append(CGPoint(
                        x: fusionPad + CGFloat(cx) * cellPitch,
                        y: fusionPad + CGFloat(cy) * cellPitch
                    ))
                }
                dir = next
                guardSteps += 1
            } while (cx, cy, dir) != (start.cx, start.cy, start.dir) && guardSteps < 800
            if corners.count >= 3 { loops.append(corners) }
        }
        return loops
    }

    private static func roundedOrthogonalPath(_ corners: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let count = corners.count
        guard count >= 3 else { return path }
        func unit(_ v: CGPoint) -> CGPoint {
            let length = max(0.001, hypot(v.x, v.y))
            return CGPoint(x: v.x / length, y: v.y / length)
        }
        func right(_ v: CGPoint) -> CGPoint { CGPoint(x: -v.y, y: v.x) }
        var starts: [CGPoint] = []
        var ends: [CGPoint] = []
        var centers: [CGPoint] = []
        var concaves: [Bool] = []
        var pulls: [CGFloat] = []
        starts.reserveCapacity(count)
        for index in 0..<count {
            let previous = corners[(index + count - 1) % count]
            let current = corners[index]
            let next = corners[(index + 1) % count]
            let incoming = unit(CGPoint(x: current.x - previous.x, y: current.y - previous.y))
            let outgoing = unit(CGPoint(x: next.x - current.x, y: next.y - current.y))
            let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
            let concave = cross < 0
            let edgeIn = hypot(current.x - previous.x, current.y - previous.y)
            let edgeOut = hypot(next.x - current.x, next.y - current.y)
            let pull = min(fusionCornerRadius, min(edgeIn, edgeOut) * 0.45)
            let nIn = right(incoming)
            let nOut = right(outgoing)
            let insetCorner = CGPoint(
                x: current.x + (nIn.x + nOut.x) * fusionInset,
                y: current.y + (nIn.y + nOut.y) * fusionInset
            )
            let start = CGPoint(x: insetCorner.x - incoming.x * pull, y: insetCorner.y - incoming.y * pull)
            let end = CGPoint(x: insetCorner.x + outgoing.x * pull, y: insetCorner.y + outgoing.y * pull)
            let normal = concave ? CGPoint(x: -nIn.x, y: -nIn.y) : nIn
            let center = CGPoint(x: start.x + normal.x * pull, y: start.y + normal.y * pull)
            starts.append(start)
            ends.append(end)
            centers.append(center)
            concaves.append(concave)
            pulls.append(pull)
        }
        path.move(to: starts[0])
        for index in 0..<count {
            let startAngle = atan2(starts[index].y - centers[index].y, starts[index].x - centers[index].x)
            let endAngle = atan2(ends[index].y - centers[index].y, ends[index].x - centers[index].x)
            path.addArc(
                center: centers[index],
                radius: pulls[index],
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: concaves[index]
            )
            path.addLine(to: starts[(index + 1) % count])
        }
        path.closeSubpath()
        return path
    }
}

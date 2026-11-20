//
//  BlomixInkChrome.swift
//  Blomix
//
//  Encre seulement : papier washi des boutons, liseré d’aquarelle, confettis.
//  Textures cuites une fois, teintées par le skin. Le Classique n’appelle rien ici.
//

import SpriteKit
import UIKit

@MainActor
enum BlomixInkChrome {

    /// Accueil et menus : le style choisi. Une partie Encre garde ce chrome
    /// même si le joueur a déjà basculé Classique pour la partie suivante.
    static var isActive: Bool {
        BlomixVisualStyle.activeRunIsInk || BlomixVisualStyle.current == .new
    }

    /// Même gris que le gros score au repos, sur le papier clair.
    static var inkGray: SKColor {
        SKColor(white: BlomixNewInkRenderer.scoreDigitWhite(light: true), alpha: 1)
    }

    static var inkGrayUI: UIColor {
        UIColor(white: BlomixNewInkRenderer.scoreDigitWhite(light: true), alpha: 1)
    }

    /// Fibre un peu plus brune que la feuille. L’alpha du sprite fait le filigrane.
    static var watermarkSK: SKColor {
        SKColor(red: 0.42, green: 0.33, blue: 0.22, alpha: 1)
    }

    static var watermarkUI: UIColor {
        UIColor(red: 0.42, green: 0.33, blue: 0.22, alpha: 1)
    }

    static let plateAlpha: ClosedRange<CGFloat> = 0.10...0.18
    static let airAlpha: ClosedRange<CGFloat> = 0.08...0.16
    static let airSide: ClosedRange<CGFloat> = 4...7
    static let airTravel: ClosedRange<TimeInterval> = 9...16

    /// Le liseré s’étale, puis revient. Le libellé ne bouge pas.
    static let spreadScale: CGFloat = 1.14
    static let spreadOutDuration: TimeInterval = 0.15
    static let spreadBackDuration: TimeInterval = 0.16

    static let confettiCount = 4

    // MARK: - Papier

    static func paperTexture(size: CGSize, cornerRadius: CGFloat) -> SKTexture {
        let key = cacheKey("paper", size: size, corner: cornerRadius)
        if let cached = paperTextures[key] { return cached }
        let texture = SKTexture(image: paperImage(size: size, cornerRadius: cornerRadius))
        texture.filteringMode = .linear
        paperTextures[key] = texture
        return texture
    }

    static func paperImage(size: CGSize, cornerRadius: CGFloat) -> UIImage {
        let key = cacheKey("paper", size: size, corner: cornerRadius)
        if let cached = paperImages[key] { return cached }
        let image = drawPaper(size: quantized(size), cornerRadius: cornerRadius)
        paperImages[key] = image
        return image
    }

    // MARK: - Liseré

    static func brushRingTexture(size: CGSize, cornerRadius: CGFloat) -> SKTexture {
        let key = cacheKey("brush", size: size, corner: cornerRadius)
        if let cached = brushTextures[key] { return cached }
        let texture = SKTexture(image: brushRingImage(size: size, cornerRadius: cornerRadius))
        texture.filteringMode = .linear
        brushTextures[key] = texture
        return texture
    }

    static func brushRingImage(size: CGSize, cornerRadius: CGFloat) -> UIImage {
        let key = cacheKey("brush", size: size, corner: cornerRadius)
        if let cached = brushImages[key] { return cached }
        let image = drawBrushRing(size: quantized(size), cornerRadius: cornerRadius)
        brushImages[key] = image
        return image
    }

    // MARK: - Confettis

    static func confettiTexture(variant: Int) -> SKTexture {
        let index = variant % confettiCount
        if let cached = confettiTextures[index] { return cached }
        let texture = SKTexture(image: confettiImage(variant: index))
        texture.filteringMode = .linear
        confettiTextures[index] = texture
        return texture
    }

    static func confettiImage(variant: Int) -> UIImage {
        let index = variant % confettiCount
        if let cached = confettiImages[index] { return cached }
        let image = drawTornSquare(seed: 0xA11CE &+ UInt64(index &* 97))
        confettiImages[index] = image
        return image
    }

    static func makeConfettiSprite(side: CGFloat, variant: Int, tint: SKColor, alpha: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: confettiTexture(variant: variant), size: CGSize(width: side, height: side))
        node.color = tint
        node.colorBlendFactor = 1
        node.alpha = alpha
        return node
    }

    // MARK: - Caches

    private static var paperImages: [String: UIImage] = [:]
    private static var paperTextures: [String: SKTexture] = [:]
    private static var brushImages: [String: UIImage] = [:]
    private static var brushTextures: [String: SKTexture] = [:]
    private static var confettiImages: [Int: UIImage] = [:]
    private static var confettiTextures: [Int: SKTexture] = [:]

    private static func quantized(_ size: CGSize) -> CGSize {
        CGSize(width: max(8, size.width.rounded()), height: max(8, size.height.rounded()))
    }

    private static func cacheKey(_ prefix: String, size: CGSize, corner: CGFloat) -> String {
        let q = quantized(size)
        return "\(prefix)|\(q.width)x\(q.height)|r\(corner.rounded())"
    }

    /// Une feuille de grain, réutilisée par tous les boutons. Pas de filet de crayon.
    private static let grainTile: CGImage = {
        let points: CGFloat = 420
        let scale: CGFloat = 2
        let width = Int((points * scale).rounded())
        let height = width
        let base = BlomixNewInkRenderer.gridPaperUIColor(light: true)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        base.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let seed: UInt64 = 0xC0FFEE
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for y in 0..<height {
                let py = CGFloat(y)
                for x in 0..<width {
                    let px = CGFloat(x)
                    let fine = valueNoise(seed, px, py, spacing: 1.7 * scale, salt: 17)
                    let slow = valueNoise(seed, px, py, spacing: 6.5 * scale, salt: 31)
                    let delta = fine * 0.010 + slow * 0.005
                    let i = (y * width + x) * 4
                    base[i] = channel(red + delta)
                    base[i + 1] = channel(green + delta)
                    base[i + 2] = channel(blue + delta)
                    base[i + 3] = 255
                }
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }()

    private static func drawPaper(size: CGSize, cornerRadius: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            let radius = min(cornerRadius, min(size.width, size.height) / 2)
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            let tileSide = CGFloat(grainTile.width) / format.scale
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.cgContext.draw(grainTile, in: CGRect(x: x, y: y, width: tileSide, height: tileSide))
                    x += tileSide
                }
                y += tileSide
            }
        }
    }

    private static func drawBrushRing(size: CGSize, cornerRadius: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            // Trait fin : le pigment utile tient dans ~1,3…2,7 pt. Le fusé du 7e tampon
            // reste court, pour que le liseré ne redevienne pas une gouttière.
            let inset: CGFloat = min(2.4, min(size.width, size.height) * 0.08)
            let rect = CGRect(
                x: inset,
                y: inset,
                width: max(4, size.width - inset * 2),
                height: max(4, size.height - inset * 2)
            )
            let radius = min(max(2, cornerRadius - inset * 0.25), min(rect.width, rect.height) / 2)
            let points = sampleRoundedRect(rect, radius: radius, step: 1.8)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            for (index, point) in points.enumerated() {
                let along = hash01(0xB415, index)
                let radiusStamp = 1.25 + along * 1.45
                let pull = (hash01(0xB415, index &+ 17) - 0.70) * 1.05
                let dx = point.x - mid.x
                let dy = point.y - mid.y
                let len = max(1, hypot(dx, dy))
                let center = CGPoint(x: point.x + dx / len * pull, y: point.y + dy / len * pull)
                let alpha = 0.42 + hash01(0xB415, index &+ 41) * 0.38
                stampSoftDisc(cg, center: center, radius: radiusStamp, alpha: alpha)
                if index % 7 == 0 {
                    stampSoftDisc(cg, center: center, radius: radiusStamp + 1.35, alpha: 0.10)
                }
            }
        }
    }

    private static func stampSoftDisc(_ ctx: CGContext, center: CGPoint, radius: CGFloat, alpha: CGFloat) {
        let colors = [
            UIColor(white: 1, alpha: alpha).cgColor,
            UIColor(white: 1, alpha: alpha * 0.45).cgColor,
            UIColor(white: 1, alpha: 0).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0, 0.42, 1]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
        ctx.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
    }

    private static func drawTornSquare(seed: UInt64) -> UIImage {
        let side: CGFloat = 36
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let ctx = context.cgContext
            let margin: CGFloat = 5
            let inner = side - margin * 2
            let perEdge = 9
            var points: [CGPoint] = []
            points.reserveCapacity(perEdge * 4)
            for edge in 0..<4 {
                let normal: CGPoint
                switch edge {
                case 0: normal = CGPoint(x: 0, y: -1)
                case 1: normal = CGPoint(x: 1, y: 0)
                case 2: normal = CGPoint(x: 0, y: 1)
                default: normal = CGPoint(x: -1, y: 0)
                }
                for step in 0..<perEdge {
                    let t = CGFloat(step) / CGFloat(perEdge)
                    let base: CGPoint
                    switch edge {
                    case 0: base = CGPoint(x: margin + t * inner, y: margin)
                    case 1: base = CGPoint(x: side - margin, y: margin + t * inner)
                    case 2: base = CGPoint(x: side - margin - t * inner, y: side - margin)
                    default: base = CGPoint(x: margin, y: side - margin - t * inner)
                    }
                    let jag = (hash01(seed, edge * perEdge + step) - 0.42) * 3.4
                    points.append(CGPoint(x: base.x + normal.x * jag, y: base.y + normal.y * jag))
                }
            }
            let path = UIBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.close()
            ctx.addPath(path.cgPath)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillPath()

            ctx.setBlendMode(.destinationOut)
            for nick in 0..<4 {
                let cx = margin + hash01(seed, 200 &+ nick) * inner
                let cy = margin + hash01(seed, 240 &+ nick) * inner
                let edgeDistance = min(cx - margin, side - margin - cx, cy - margin, side - margin - cy)
                guard edgeDistance < 7 else { continue }
                let nickRadius = 0.55 + hash01(seed, 280 &+ nick) * 1.15
                ctx.setFillColor(UIColor(white: 0, alpha: 0.70).cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - nickRadius, y: cy - nickRadius, width: nickRadius * 2, height: nickRadius * 2))
            }
        }
    }

    private static func sampleRoundedRect(_ rect: CGRect, radius: CGFloat, step: CGFloat) -> [CGPoint] {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let top = max(0, rect.width - 2 * r)
        let side = max(0, rect.height - 2 * r)
        let arc = CGFloat.pi / 2 * r
        let perimeter = max(step, 2 * top + 2 * side + 4 * arc)
        let count = max(12, Int((perimeter / step).rounded()))
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let distance = perimeter * CGFloat(index) / CGFloat(count)
            points.append(pointOnRoundedRect(rect, radius: r, distance: distance, top: top, side: side, arc: arc))
        }
        return points
    }

    /// +y vers le bas, comme le bitmap. Angle 0 = +x.
    private static func pointOnRoundedRect(
        _ rect: CGRect,
        radius r: CGFloat,
        distance raw: CGFloat,
        top: CGFloat,
        side: CGFloat,
        arc: CGFloat
    ) -> CGPoint {
        var d = raw
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        if d <= top { return CGPoint(x: minX + r + d, y: minY) }
        d -= top
        if d <= arc {
            let a = -CGFloat.pi / 2 + (d / max(arc, 0.001)) * (CGFloat.pi / 2)
            let c = CGPoint(x: maxX - r, y: minY + r)
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        }
        d -= arc
        if d <= side { return CGPoint(x: maxX, y: minY + r + d) }
        d -= side
        if d <= arc {
            let a = (d / max(arc, 0.001)) * (CGFloat.pi / 2)
            let c = CGPoint(x: maxX - r, y: maxY - r)
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        }
        d -= arc
        if d <= top { return CGPoint(x: maxX - r - d, y: maxY) }
        d -= top
        if d <= arc {
            let a = CGFloat.pi / 2 + (d / max(arc, 0.001)) * (CGFloat.pi / 2)
            let c = CGPoint(x: minX + r, y: maxY - r)
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        }
        d -= arc
        if d <= side { return CGPoint(x: minX, y: maxY - r - d) }
        d -= side
        let a = CGFloat.pi + min(1, d / max(arc, 0.001)) * (CGFloat.pi / 2)
        let c = CGPoint(x: minX + r, y: minY + r)
        return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
    }

    private static func channel(_ value: CGFloat) -> UInt8 {
        UInt8((min(1, max(0, value)) * 255).rounded())
    }

    private static func hash01(_ seed: UInt64, _ i: Int) -> CGFloat {
        var h = seed &+ UInt64(bitPattern: Int64(i)) &* 0x9E3779B97F4A7C15
        h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
        h = h ^ (h >> 31)
        return CGFloat(h % 10_000) / 9_999
    }

    private static func valueNoise(_ seed: UInt64, _ x: CGFloat, _ y: CGFloat, spacing: CGFloat, salt: Int) -> CGFloat {
        let step = max(1, spacing)
        let sx = x / step
        let sy = y / step
        let x0 = Int(floor(sx))
        let y0 = Int(floor(sy))
        let tx = sx - CGFloat(x0)
        let ty = sy - CGFloat(y0)
        let ux = tx * tx * (3 - 2 * tx)
        let uy = ty * ty * (3 - 2 * ty)
        let v00 = hashSigned(seed, x0, y0, salt)
        let v10 = hashSigned(seed, x0 &+ 1, y0, salt)
        let v01 = hashSigned(seed, x0, y0 &+ 1, salt)
        let v11 = hashSigned(seed, x0 &+ 1, y0 &+ 1, salt)
        let a = v00 + (v10 - v00) * ux
        let b = v01 + (v11 - v01) * ux
        return a + (b - a) * uy
    }

    private static func hashSigned(_ seed: UInt64, _ x: Int, _ y: Int, _ salt: Int) -> CGFloat {
        var h = seed
            &+ UInt64(bitPattern: Int64(x)) &* 0x9E3779B97F4A7C15
            &+ UInt64(bitPattern: Int64(y)) &* 0xBF58476D1CE4E5B9
            &+ UInt64(bitPattern: Int64(salt)) &* 0x94D049BB133111EB
        h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
        h = h ^ (h >> 31)
        return CGFloat(h & 0xFFFF) / 32767.5 - 1
    }
}

//
//  BlomixInkChrome.swift
//  Blomix
//
//  Encre seulement : papier washi des boutons, tour d’aquarelle, confettis.
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

    /// Tour d’épaisseur constante, en points. Le lavis vit dedans, pas la largeur.
    nonisolated static let rimWidth: CGFloat = 2.4
    /// Front de la couleur à l’appui, en points. Identique au retour.
    nonisolated static let floodFeather: CGFloat = 2.4
    /// Temps pour couvrir le bouton depuis le doigt, et pour y revenir. Vitesse constante.
    nonisolated static let floodDuration: TimeInterval = 0.16

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

    // MARK: - Tour et surface

    static func rimWashTexture(size: CGSize, cornerRadius: CGFloat) -> SKTexture {
        cachedWashTexture(band: true, size: size, cornerRadius: cornerRadius)
    }

    static func rimWashImage(size: CGSize, cornerRadius: CGFloat) -> UIImage {
        ensureWashPair(size: size, cornerRadius: cornerRadius).rim
    }

    static func faceWashTexture(size: CGSize, cornerRadius: CGFloat) -> SKTexture {
        cachedWashTexture(band: false, size: size, cornerRadius: cornerRadius)
    }

    static func faceWashImage(size: CGSize, cornerRadius: CGFloat) -> UIImage {
        ensureWashPair(size: size, cornerRadius: cornerRadius).face
    }

    private static func cachedWashTexture(band: Bool, size: CGSize, cornerRadius: CGFloat) -> SKTexture {
        let prefix = band ? "rim" : "face"
        let key = cacheKey(prefix, size: size, corner: cornerRadius)
        if let cached = washTextures[key] { return cached }
        let image = band
            ? rimWashImage(size: size, cornerRadius: cornerRadius)
            : faceWashImage(size: size, cornerRadius: cornerRadius)
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        washTextures[key] = texture
        return texture
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
    private static var washPairs: [String: (face: UIImage, rim: UIImage)] = [:]
    private static var washTextures: [String: SKTexture] = [:]
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

    /// Un seul passage : la surface et le tour lisent le même lavis, au même endroit.
    private static func ensureWashPair(size: CGSize, cornerRadius: CGFloat) -> (face: UIImage, rim: UIImage) {
        let key = cacheKey("wash", size: size, corner: cornerRadius)
        if let cached = washPairs[key] { return cached }
        let pair = drawWashPair(size: quantized(size), cornerRadius: cornerRadius)
        washPairs[key] = pair
        return pair
    }

    /// `sd` négatif à l’intérieur. Le tour est une bande de `rimWidth` le long du bord.
    private static func drawWashPair(size: CGSize, cornerRadius: CGFloat) -> (face: UIImage, rim: UIImage) {
        let scale: CGFloat = 2
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        let radius = min(cornerRadius, min(size.width, size.height) / 2)
        let phaseX = size.width * 17
        let phaseY = size.height * 11
        var facePx = [UInt8](repeating: 0, count: width * height * 4)
        var rimPx = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let py = (CGFloat(y) + 0.5) / scale
            for x in 0..<width {
                let px = (CGFloat(x) + 0.5) / scale
                let sd = roundedRectSDF(CGPoint(x: px, y: py), size: size, radius: radius)
                let faceCover: CGFloat = sd < 0.7 ? (1 - smoothstep(-0.15, 0.50, sd)) : 0
                let rimCover: CGFloat
                if sd < 0.7, sd > -rimWidth - 0.7 {
                    let outer = 1 - smoothstep(-0.05, 0.40, sd)
                    let inner = smoothstep(-rimWidth - 0.30, -rimWidth + 0.30, sd)
                    rimCover = outer * inner
                } else {
                    rimCover = 0
                }
                if faceCover <= 0.004, rimCover <= 0.004 { continue }
                let sample = BlomixNewInkRenderer.bloxWashSample(px: px + phaseX, py: py + phaseY)
                let o = (y * width + x) * 4
                if faceCover > 0.004 {
                    writeWash(&facePx, at: o, sample: sample, cover: faceCover)
                }
                if rimCover > 0.004 {
                    writeWash(&rimPx, at: o, sample: sample, cover: rimCover)
                }
            }
        }
        return (
            face: image(from: facePx, width: width, height: height, scale: scale),
            rim: image(from: rimPx, width: width, height: height, scale: scale)
        )
    }

    private static func writeWash(
        _ pixels: inout [UInt8],
        at offset: Int,
        sample: (gray: CGFloat, alpha: CGFloat),
        cover: CGFloat
    ) {
        let alpha = min(1, sample.alpha * cover)
        let channel = UInt8((sample.gray * alpha * 255).rounded())
        pixels[offset] = channel
        pixels[offset + 1] = channel
        pixels[offset + 2] = channel
        pixels[offset + 3] = UInt8((alpha * 255).rounded())
    }

    private static func image(from pixels: [UInt8], width: Int, height: Int, scale: CGFloat) -> UIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return UIImage()
        }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    /// Distance signée au rectangle arrondi. Négatif à l’intérieur. `point` depuis le haut gauche.
    private static func roundedRectSDF(_ point: CGPoint, size: CGSize, radius: CGFloat) -> CGFloat {
        let halfW = size.width / 2
        let halfH = size.height / 2
        let r = min(radius, min(halfW, halfH))
        let qx = abs(point.x - halfW) - halfW + r
        let qy = abs(point.y - halfH) - halfH + r
        let outside = hypot(max(qx, 0), max(qy, 0))
        let inside = min(max(qx, qy), 0)
        return outside + inside - r
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - edge0) / max(edge1 - edge0, 0.0001)))
        return t * t * (3 - 2 * t)
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

/// Masque UIKit de l’appui Encre. `spread` 0…1 anime le rayon. L’origine est
/// en points, y vers le haut (le `draw` de CALayer). Le lavis n’est pas scalé :
/// seul le disque grandit, puis se referme sur le point d’appui.
final class BlomixInkFloodMaskLayer: CALayer {
    @NSManaged var spread: CGFloat

    var origin: CGPoint = .zero
    var maxRadius: CGFloat = 1
    var wash: CGImage?

    override init() {
        super.init()
        spread = 0
        isOpaque = false
        contentsScale = 2
        needsDisplayOnBoundsChange = true
        actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
    }

    override init(layer: Any) {
        let other = layer as? BlomixInkFloodMaskLayer
        origin = other?.origin ?? .zero
        maxRadius = other?.maxRadius ?? 1
        wash = other?.wash
        super.init(layer: layer)
        spread = other?.spread ?? 0
        if let other {
            contentsScale = other.contentsScale
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override class func needsDisplay(forKey key: String) -> Bool {
        key == "spread" || super.needsDisplay(forKey: key)
    }

    override func action(forKey event: String) -> (any CAAction)? {
        if event == "spread" { return NSNull() }
        return super.action(forKey: event)
    }

    override func draw(in ctx: CGContext) {
        guard spread > 0.001, let wash, bounds.width > 1, bounds.height > 1 else { return }
        let radius = max(0.25, maxRadius * spread)
        let feather = BlomixInkChrome.floodFeather
        ctx.saveGState()
        let colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) {
            let inner = max(0, radius - feather)
            ctx.drawRadialGradient(
                gradient,
                startCenter: origin,
                startRadius: inner,
                endCenter: origin,
                endRadius: max(radius, inner + 0.25),
                options: [.drawsBeforeStartLocation]
            )
        }
        ctx.setBlendMode(.destinationIn)
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .medium
        ctx.draw(wash, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
    }
}

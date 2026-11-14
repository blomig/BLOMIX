//
//  BlomixNewBlockRenderer.swift
//  Blomix
//
//  Blox couleur en matière gelée (look New, étape 1). Textures Core Graphics
//  mises en cache. Pas de shader par bloc.
//
//  La texture est un masque d'éclairage (gris), pas la teinte du skin.
//  Le sprite porte `color` = teinte et `colorBlendFactor` = 1, donc les
//  animations qui écrivent `sprite.color` (dissolution, SAINTX) restent valables.
//  Le reflet blanc est un enfant : la multiplication par la teinte ne peut pas
//  dépasser la couleur du skin.
//
//  Une partie typique construit 6 textures gelée (6 couleurs du skin × une taille
//  `cell − 4` × une apparence × l'échelle de l'écran) et 1 texture de reflet partagée.
//

import SpriteKit
import UIKit

enum BlomixNewBlockRenderer {

    /// Blox couleur gelée. Taille, ancre (0,5, 0,5). `fill` = teinte du skin.
    /// MainActor : `SKSpriteNode` l’exige. La fabrique de `GameScene` l’est déjà.
    @MainActor
    static func makeColorSprite(fill: SKColor, pointSize: CGSize) -> SKSpriteNode {
        guard pointSize.width > 1, pointSize.height > 1 else {
            let fallback = SKSpriteNode(color: fill, size: pointSize)
            fallback.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            fallback.colorBlendFactor = 1
            return fallback
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

        let sprite = SKSpriteNode(texture: texture, size: pointSize)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.color = fill
        sprite.colorBlendFactor = 1

        let face = faceLayout(for: pointSize)
        let glint = SKSpriteNode(texture: cache.glintTexture(make: bakeGlint), size: face.glintSize)
        glint.position = face.glintCenter
        glint.zRotation = -0.42
        glint.zPosition = 2
        glint.colorBlendFactor = 0
        glint.name = specularNodeName
        sprite.addChild(glint)
        return sprite
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

    private static let cache = TextureCache()

    private final class TextureCache: @unchecked Sendable {
        private let lock = NSLock()
        private var jellies: [CacheKey: SKTexture] = [:]
        private var glint: SKTexture?

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

        func glintTexture(make: () -> SKTexture) -> SKTexture {
            lock.lock()
            if let hit = glint {
                lock.unlock()
                return hit
            }
            lock.unlock()
            let built = make()
            lock.lock()
            if let hit = glint {
                lock.unlock()
                return hit
            }
            glint = built
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
        let shadowRoom = m * 0.145
        let margin = m * 0.04
        let body = CGRect(
            x: margin,
            y: margin,
            width: max(1, size.width - margin - shadowRoom),
            height: max(1, size.height - margin - shadowRoom)
        )
        let radius = min(body.width, body.height) * 0.32
        let ring = max(0.9, m * 0.030)
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

    /// Anneau plus sombre que la teinte. Plus la teinte est claire, plus l'anneau descend,
    /// surtout sur le crème (violet / jaune / bleu).
    private static func edgeMultiplier(red: CGFloat, green: CGFloat, blue: CGFloat, light: Bool) -> CGFloat {
        let lum = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        if light {
            return max(0.38, 0.62 - 0.20 * lum)
        }
        return max(0.46, 0.70 - 0.14 * lum)
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
            drawJellyMask(in: context.cgContext, pointSize: pointSize, edge: edge, light: light)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func drawJellyMask(in ctx: CGContext, pointSize: CGSize, edge: CGFloat, light: Bool) {
        let face = faceLayout(for: pointSize)
        let body = face.body
        let bodyPath = CGPath(
            roundedRect: body,
            cornerWidth: face.radius,
            cornerHeight: face.radius,
            transform: nil
        )
        let ringRect = body.insetBy(dx: -face.ring, dy: -face.ring)
        let ringPath = CGPath(
            roundedRect: ringRect,
            cornerWidth: face.radius + face.ring,
            cornerHeight: face.radius + face.ring,
            transform: nil
        )

        // Contour sombre : dessiné sous le corps, il ne dépasse que sur le pourtour.
        ctx.addPath(ringPath)
        ctx.setFillColor(UIColor(white: edge, alpha: 1).cgColor)
        ctx.fillPath()

        // Ombre portée courte, bas-droite. Le noir reste noir après × teinte.
        ctx.saveGState()
        let shadowAlpha: CGFloat = light ? 0.34 : 0.50
        ctx.setShadow(
            offset: CGSize(width: face.shadowRoom * 0.34, height: face.shadowRoom * 0.42),
            blur: face.shadowRoom * 0.55,
            color: UIColor(white: 0, alpha: shadowAlpha).cgColor
        )
        ctx.addPath(bodyPath)
        ctx.setFillColor(UIColor(white: 0.72, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Volume : plus clair en haut, plus profond en bas.
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        let volume = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(white: 0.98, alpha: 1).cgColor,
                UIColor(white: 0.80, alpha: 1).cgColor,
                UIColor(white: 0.52, alpha: 1).cgColor,
            ] as CFArray,
            locations: [0, 0.42, 1]
        )
        if let volume {
            ctx.drawLinearGradient(
                volume,
                start: CGPoint(x: body.midX, y: body.minY),
                end: CGPoint(x: body.midX, y: body.maxY),
                options: []
            )
        }

        // Liseré intérieur clair. Le volume (plus sombre en bas) fait le biseau.
        ctx.setLineWidth(max(0.9, min(pointSize.width, pointSize.height) * 0.032))
        ctx.addPath(bodyPath)
        ctx.setStrokeColor(UIColor(white: 1, alpha: 1).cgColor)
        ctx.strokePath()

        // Éclat doux haut-gauche, encore dans le masque (plafonné à la teinte).
        let sheen = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(white: 1, alpha: 0.70).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )
        if let sheen {
            let center = CGPoint(x: body.minX + body.width * 0.28, y: body.minY + body.height * 0.20)
            ctx.drawRadialGradient(
                sheen,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: body.width * 0.62,
                options: []
            )
        }
        ctx.restoreGState()
    }

    private static func bakeGlint() -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 64), format: format)
        let image = renderer.image { context in
            let ctx = context.cgContext
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(white: 1, alpha: 0.96).cgColor,
                    UIColor(white: 1, alpha: 0.55).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor,
                ] as CFArray,
                locations: [0, 0.28, 1]
            ) else { return }
            ctx.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 64, y: 32),
                startRadius: 0,
                endCenter: CGPoint(x: 64, y: 32),
                endRadius: 36,
                options: []
            )
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
}

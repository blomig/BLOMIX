//
//  BlomixNewInkRenderer.swift
//  Blomix
//
//  9.0 Ink: matière encre / aquarelle du mode New (la gelée n'est plus un style).
//  Géométrie des pièces : BlomixNewBlockRenderer. Ici, le papier et le pigment.
//  Textures Core Graphics, en cache. Pas de shader par bloc.
//

import SpriteKit
import UIKit

enum BlomixNewInkRenderer {

    /// Indigo profond des Brix. Le chiffre reste blanc, par-dessus.
    static let priksFill = SKColor(red: 0.11, green: 0.15, blue: 0.40, alpha: 1)

    static func paperUIColor(light: Bool) -> UIColor {
        if light {
            return UIColor(red: 0xF6 / 255, green: 0xF1 / 255, blue: 0xE7 / 255, alpha: 1)
        }
        return UIColor(red: 0x26 / 255, green: 0x23 / 255, blue: 0x1F / 255, alpha: 1)
    }

    static var paperSKColor: SKColor {
        paperUIColor(light: BlomixAppearance.isLight)
    }

    /// Papier washi de la grille, une texture par thème et par taille.
    @MainActor
    static func paperTexture(pointSize: CGSize, divisions: Int = 8) -> SKTexture {
        let light = BlomixAppearance.isLight
        let scale = max(1, UITraitCollection.current.displayScale)
        let key = PaperKey(
            pixelWidth: max(1, Int((pointSize.width * scale).rounded())),
            pixelHeight: max(1, Int((pointSize.height * scale).rounded())),
            light: light,
            divisions: divisions
        )
        return paperCache.texture(for: key) {
            bakePaper(pointSize: pointSize, scale: scale, light: light, divisions: divisions)
        }
    }

    /// Masque d'encre (gris). Le sprite le multiplie par la teinte du skin.
    /// Centre plus clair, liseré plus sombre, bord tremblé stable, grain qui laisse voir le papier.
    static func drawMask(
        in ctx: CGContext,
        paths: [CGPath],
        seed: UInt64,
        canvas: CGSize,
        rim: CGFloat
    ) {
        guard !paths.isEmpty, canvas.width > 1, canvas.height > 1 else { return }
        let wobbled = paths.map { wobble($0, seed: seed, amplitude: 0.9) }

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0.35, height: 0.5),
            blur: 1.1,
            color: UIColor(white: 0, alpha: 0.10).cgColor
        )
        ctx.setFillColor(UIColor(white: 0.72, alpha: 1).cgColor)
        for path in wobbled { ctx.addPath(path) }
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        for path in wobbled { ctx.addPath(path) }
        ctx.clip(using: .winding)
        let mid = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let reach = max(canvas.width, canvas.height) * 0.62
        if let wash = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(white: 1.0, alpha: 0.96).cgColor,
                UIColor(white: 0.86, alpha: 1).cgColor,
                UIColor(white: max(rim, 0.55), alpha: 1).cgColor,
            ] as CFArray,
            locations: [0, 0.55, 1]
        ) {
            ctx.drawRadialGradient(
                wash,
                startCenter: mid,
                startRadius: 0,
                endCenter: mid,
                endRadius: reach,
                options: []
            )
        }
        ctx.setBlendMode(.destinationOut)
        let area = canvas.width * canvas.height
        let dots = min(160, max(18, Int(area / 90)))
        for i in 0..<dots {
            let x = unit(seed, i &* 3) * canvas.width
            let y = unit(seed, i &* 3 &+ 1) * canvas.height
            let radius = 0.25 + unit(seed, i &* 3 &+ 2) * 0.7
            ctx.setFillColor(UIColor(white: 1, alpha: 0.16).cgColor)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
        }
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor(white: rim, alpha: 1).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        for path in wobbled { ctx.addPath(path) }
        ctx.strokePath()
    }

    static func seed(red: CGFloat, green: CGFloat, blue: CGFloat, salt: Int = 0) -> UInt64 {
        let r = UInt64((min(1, max(0, red)) * 255).rounded())
        let g = UInt64((min(1, max(0, green)) * 255).rounded())
        let b = UInt64((min(1, max(0, blue)) * 255).rounded())
        return (r << 16) | (g << 8) | b | (UInt64(bitPattern: Int64(salt)) &* 0x9E3779B97F4A7C15)
    }

    // MARK: - Papier

    private struct PaperKey: Hashable {
        var pixelWidth: Int
        var pixelHeight: Int
        var light: Bool
        var divisions: Int
    }

    private static let paperCache = PaperCache()

    private final class PaperCache: @unchecked Sendable {
        private let lock = NSLock()
        private var textures: [PaperKey: SKTexture] = [:]

        func texture(for key: PaperKey, make: () -> SKTexture) -> SKTexture {
            lock.lock()
            if let hit = textures[key] {
                lock.unlock()
                return hit
            }
            lock.unlock()
            let built = make()
            lock.lock()
            if let hit = textures[key] {
                lock.unlock()
                return hit
            }
            textures[key] = built
            lock.unlock()
            return built
        }
    }

    private static func bakePaper(pointSize: CGSize, scale: CGFloat, light: Bool, divisions: Int) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: pointSize, format: format).image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: pointSize)
            ctx.setFillColor(paperUIColor(light: light).cgColor)
            ctx.fill(rect)

            let seed: UInt64 = light ? 0xC0FFEE : 0x5A11
            let specks = min(700, max(120, Int(pointSize.width * pointSize.height / 28)))
            for i in 0..<specks {
                let x = unit(seed, i &* 2) * pointSize.width
                let y = unit(seed, i &* 2 &+ 1) * pointSize.height
                let gray: CGFloat = light ? 0.45 : 0.85
                let alpha = 0.035 + unit(seed, i &+ 9) * 0.05
                ctx.setFillColor(UIColor(white: gray, alpha: alpha).cgColor)
                let side = 0.4 + unit(seed, i &+ 3) * 0.8
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: side, height: side * 0.6))
            }

            ctx.setStrokeColor(UIColor(white: light ? 0.35 : 0.82, alpha: light ? 0.10 : 0.12).cgColor)
            ctx.setLineWidth(0.7)
            ctx.setLineCap(.round)
            for i in 0..<6 {
                let y = unit(seed, 400 &+ i) * pointSize.height
                let drift = (unit(seed, 500 &+ i) - 0.5) * pointSize.height * 0.08
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addQuadCurve(
                    to: CGPoint(x: pointSize.width, y: y + drift),
                    control: CGPoint(x: pointSize.width * (0.3 + unit(seed, 600 &+ i) * 0.4), y: y - drift)
                )
            }
            ctx.strokePath()

            let count = max(1, divisions)
            ctx.setStrokeColor(UIColor(white: light ? 0.28 : 0.78, alpha: light ? 0.14 : 0.16).cgColor)
            ctx.setLineWidth(0.6)
            for i in 0...count {
                let x = pointSize.width * CGFloat(i) / CGFloat(count)
                let y = pointSize.height * CGFloat(i) / CGFloat(count)
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: pointSize.height))
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: pointSize.width, y: y))
            }
            ctx.strokePath()
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    // MARK: - Bord tremblé

    private final class Step {
        var i = 0
    }

    private static func wobble(_ path: CGPath, seed: UInt64, amplitude: CGFloat) -> CGPath {
        let out = CGMutablePath()
        let step = Step()
        path.applyWithBlock { element in
            let e = element.pointee
            func j(_ point: CGPoint) -> CGPoint {
                let n = step.i
                step.i += 1
                let u = unit(seed, n &* 2)
                let v = unit(seed, n &* 2 &+ 1)
                return CGPoint(
                    x: point.x + (u - 0.5) * 2 * amplitude,
                    y: point.y + (v - 0.5) * 2 * amplitude
                )
            }
            switch e.type {
            case .moveToPoint:
                out.move(to: j(e.points[0]))
            case .addLineToPoint:
                out.addLine(to: j(e.points[0]))
            case .addQuadCurveToPoint:
                out.addQuadCurve(to: j(e.points[1]), control: j(e.points[0]))
            case .addCurveToPoint:
                out.addCurve(to: j(e.points[2]), control1: j(e.points[0]), control2: j(e.points[1]))
            case .closeSubpath:
                out.closeSubpath()
            default:
                break
            }
        }
        return out
    }

    private static func unit(_ seed: UInt64, _ index: Int) -> CGFloat {
        var x = seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x = x ^ (x >> 31)
        return CGFloat(x % 10_000) / 10_000
    }
}

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
            // Un cran plus ocre que le premier essai (#F6F1E7), encore très clair.
            return UIColor(red: 0xF3 / 255, green: 0xE8 / 255, blue: 0xD4 / 255, alpha: 1)
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
    /// Granulation fine, pas de grandes flaques : deux cases d'une même pièce
    /// ne portent pas le même motif. Pas de liseré.
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
            offset: CGSize(width: 0.2, height: 0.3),
            blur: 0.6,
            color: UIColor(white: 0, alpha: 0.05).cgColor
        )
        ctx.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
        for path in wobbled { ctx.addPath(path) }
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        for path in wobbled { ctx.addPath(path) }
        ctx.clip(using: .winding)
        ctx.clear(CGRect(origin: .zero, size: canvas))
        drawWatercolorField(in: ctx, seed: seed, canvas: canvas, rim: rim)
        ctx.restoreGState()
    }

    /// Trois octaves de bruit de valeur, en points (pas en fraction de la pièce).
    /// Lente et discrète, moyenne = granulation, fine = grain du papier.
    /// Les creux gardent un peu plus de pigment, les pointes laissent voir le washi.
    private static func drawWatercolorField(
        in ctx: CGContext,
        seed: UInt64,
        canvas: CGSize,
        rim: CGFloat
    ) {
        let scale = max(1, hypot(ctx.ctm.a, ctx.ctm.c))
        let width = max(1, Int((canvas.width * scale).rounded()))
        let height = max(1, Int((canvas.height * scale).rounded()))
        guard width * height <= 1_600_000 else { return }

        let granulation = 0.9 + (1 - min(1, max(0, rim))) * 1.6
        let phaseX = unit(seed, 3) * 4096
        let phaseY = unit(seed, 5) * 4096

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let py = CGFloat(y) + phaseY
                for x in 0..<width {
                    let px = CGFloat(x) + phaseX
                    let sample = pigment(seed: seed, px: px, py: py, scale: scale, granulation: granulation)
                    let channel = UInt8((sample.gray * sample.alpha * 255).rounded())
                    let a = UInt8((sample.alpha * 255).rounded())
                    let i = (y * width + x) * 4
                    buffer[i] = channel
                    buffer[i + 1] = channel
                    buffer[i + 2] = channel
                    buffer[i + 3] = a
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(origin: .zero, size: canvas))
    }

    /// Même granulation que le champ des Blox. `gray` 0,90…1, `alpha` = dent du papier.
    private static func pigment(
        seed: UInt64,
        px: CGFloat,
        py: CGFloat,
        scale: CGFloat,
        granulation: CGFloat
    ) -> (gray: CGFloat, alpha: CGFloat) {
        let low = valueNoise(seed, px, py, spacing: 18 * scale, salt: 11)
        let mid = valueNoise(seed, px, py, spacing: 5.2 * scale, salt: 29)
        let fine = valueNoise(seed, px, py, spacing: 1.55 * scale, salt: 47)
        let valley = max(0, -mid) * 0.55 + max(0, -fine) * 0.45
        var gray = 0.985
            + low * 0.018
            + mid * 0.018 * granulation
            - valley * 0.038 * granulation
        gray = min(1, max(0.90, gray))
        let tooth = max(0, fine)
        let alpha = max(0.72, 1 - tooth * 0.28 * granulation)
        return (gray, alpha)
    }

    /// Disque Magix / bombe. Le centre a le grain des Blox. La couronne est de l’encre
    /// dont l’épaisseur et la charge varient : pas un trait circulaire. `salt` sépare
    /// le Magix de la bombe. Une taille = une texture.
    @MainActor
    static func discTexture(pointSize: CGSize, salt: Int) -> SKTexture {
        let scale = max(1, UITraitCollection.current.displayScale)
        let key = DiscKey(
            pixelWidth: max(1, Int((pointSize.width * scale).rounded())),
            pixelHeight: max(1, Int((pointSize.height * scale).rounded())),
            salt: salt
        )
        return discCache.texture(for: key) {
            bakeDisc(pointSize: pointSize, scale: scale, salt: salt)
        }
    }

    private struct DiscKey: Hashable {
        var pixelWidth: Int
        var pixelHeight: Int
        var salt: Int
    }

    private static let discCache = DiscCache()

    private final class DiscCache: @unchecked Sendable {
        private let lock = NSLock()
        private var textures: [DiscKey: SKTexture] = [:]

        func texture(for key: DiscKey, make: () -> SKTexture) -> SKTexture {
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

    private static func bakeDisc(pointSize: CGSize, scale: CGFloat, salt: Int) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: pointSize, format: format).image { context in
            drawDiscMask(in: context.cgContext, canvas: pointSize, scale: scale, salt: salt)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Masque pré-multiplié. Le shader récupère la charge (`rgb / a`) puis la couverture.
    private static func drawDiscMask(in ctx: CGContext, canvas: CGSize, scale: CGFloat, salt: Int) {
        let width = max(1, Int((canvas.width * scale).rounded()))
        let height = max(1, Int((canvas.height * scale).rounded()))
        guard width * height <= 1_600_000, canvas.width > 1, canvas.height > 1 else { return }

        let seed = 0xE5C1_5A17 &+ UInt64(bitPattern: Int64(salt)) &* 0x9E3779B97F4A7C15
        let phaseX = unit(seed, 3) * 4096
        let phaseY = unit(seed, 5) * 4096
        let phase = unit(seed, 7) * 2 * .pi
        let side = min(canvas.width, canvas.height)
        let cx = canvas.width * 0.5
        let cy = canvas.height * 0.5
        let granulation: CGFloat = 1.05

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                for x in 0..<width {
                    let px = (CGFloat(x) + 0.5) / scale
                    let py = (CGFloat(y) + 0.5) / scale
                    let angle = atan2(py - cy, px - cx)
                    let dist = hypot(px - cx, py - cy)
                    let arc = angle * side * 0.5 * scale
                    let lowN = valueNoise(seed, arc, 12, spacing: 16 * scale, salt: 83)
                    let midN = valueNoise(seed, arc, 48, spacing: 5.2 * scale, salt: 89)
                    // Le tour reste un disque (le glyphe tient au centre) mais l’encre
                    // s’épaissit et se sèche : ce n’est plus un trait au compas.
                    let outerR = side * 0.446
                        + sin(angle * 3 + phase) * side * 0.022
                        + lowN * side * 0.012
                    var thickness = side * 0.056
                        + sin(angle * 2 + phase) * side * 0.032
                        + sin(angle * 5 + phase * 0.7) * side * 0.012
                        + lowN * side * 0.014
                        + midN * side * 0.008
                    thickness = min(max(thickness, side * 0.026), side * 0.098)
                    let innerR = outerR - thickness
                    let cover = 1 - smoothstep(outerR - 0.25, outerR + 0.85, dist)
                    let rim = smoothstep(innerR - 0.55, innerR + 0.18, dist) * cover
                    let sample = pigment(
                        seed: seed,
                        px: CGFloat(x) + phaseX,
                        py: CGFloat(y) + phaseY,
                        scale: scale,
                        granulation: granulation
                    )
                    let wash = 0.5 + 0.5 * midN
                    // L’encre s’accumule là où le tour est large, et sèche là où il est fin.
                    let pooled = min(1, max(0, (thickness / side - 0.026) / 0.072))
                    let dark = 0.02 + 0.18 * (1 - pooled) + 0.04 * (1 - wash)
                    let rimMix = rim * (0.72 + 0.28 * max(0, wash))
                    let shade = min(1, sample.gray * (1 - rimMix) + dark * rimMix)
                    let rimAlpha = max(sample.alpha * 0.5, 0.82)
                    let alpha = max(0, min(1, cover * (sample.alpha * (1 - rim) + rimAlpha * rim)))
                    let channel = UInt8((shade * alpha * 255).rounded())
                    let a = UInt8((alpha * 255).rounded())
                    let i = (y * width + x) * 4
                    buffer[i] = channel
                    buffer[i + 1] = channel
                    buffer[i + 2] = channel
                    buffer[i + 3] = a
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(origin: .zero, size: canvas))
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let span = edge1 - edge0
        if span == 0 { return x < edge0 ? 0 : 1 }
        let t = min(1, max(0, (x - edge0) / span))
        return t * t * (3 - 2 * t)
    }

    /// Bruit de valeur lissé, dans −1…1. `spacing` est en pixels du bitmap.
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

//
//  BlomixNewInkRenderer.swift
//  Blomix
//
//  9.0 Ink: matière encre / aquarelle du mode New (la gelée n'est plus un style).
//  Géométrie des pièces : BlomixNewBlockRenderer. Ici, le papier et le pigment.
//  Textures Core Graphics, en cache. Pas de shader par bloc.
//

import CoreText
import SpriteKit
import UIKit

enum BlomixNewInkRenderer {

    static func paperUIColor(light: Bool) -> UIColor {
        if light {
            // Pourtour de la partie. Un cran plus ocre que #F6F1E7, encore très clair.
            return UIColor(red: 0xF3 / 255, green: 0xE8 / 255, blue: 0xD4 / 255, alpha: 1)
        }
        return UIColor(red: 0x26 / 255, green: 0x23 / 255, blue: 0x1F / 255, alpha: 1)
    }

    /// Feuille sous les cases. Clair : même teinte que les cases vides Classique
    /// (`BlomixAppearance.emptyCell`, `#F0E6D2`). Le pourtour reste `paperUIColor`.
    static func gridPaperUIColor(light: Bool) -> UIColor {
        if light {
            return UIColor(red: 0xF0 / 255, green: 0xE6 / 255, blue: 0xD2 / 255, alpha: 1)
        }
        return paperUIColor(light: false)
    }

    static var paperSKColor: SKColor {
        paperUIColor(light: BlomixAppearance.isLight)
    }

    /// Gris du gros score. Le lavis est un masque : la teinte du sprite le colore.
    /// Clair : gris foncé (0,30) sur `#F3E8D4`. Sombre : gris moyen (0,58) sur `#26231F`.
    /// L’alpha des flaques laisse passer le papier. Pas une plaque derrière les chiffres.
    static func scoreDigitWhite(light: Bool) -> CGFloat {
        light ? 0.30 : 0.58
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
    /// La silhouette est celle des `paths` (case, pièce, diagonale) : le lavis
    /// ne redessine pas le contour. Flaques en points absolus.
    /// Pas de liseré gris : le bord des cases est la même teinte, plus chargée.
    /// `bridgePaths` : capsules diagonales. Seul le pont hors des cases s'efface.
    static func drawMask(
        in ctx: CGContext,
        paths: [CGPath],
        seed: UInt64,
        canvas: CGSize,
        rim: CGFloat,
        bodyPaths: [CGPath] = [],
        bridgePaths: [CGPath] = []
    ) {
        guard !paths.isEmpty, canvas.width > 1, canvas.height > 1 else { return }

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0.2, height: 0.3),
            blur: 0.6,
            color: UIColor(white: 0, alpha: 0.05).cgColor
        )
        ctx.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
        // Pas de blanc sous la capsule : un fondu posé dessus redevient un trait.
        let underlay = bridgePaths.isEmpty ? paths : bodyPaths
        for path in underlay { ctx.addPath(path) }
        ctx.fillPath()
        ctx.restoreGState()

        // La silhouette est le chemin des cases posées. Le bitmap ne peut pas
        // déborder : un miroir peindrait la case d'à côté.
        ctx.saveGState()
        for path in paths {
            ctx.addPath(path)
            ctx.addPath(path.copy(
                strokingWithWidth: 2.4,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 2
            ))
        }
        ctx.clip(using: .winding)
        ctx.clear(CGRect(origin: .zero, size: canvas))
        drawWatercolorField(
            in: ctx,
            paths: paths,
            bodyPaths: bodyPaths,
            bridgePaths: bridgePaths,
            seed: seed,
            canvas: canvas,
            rim: rim
        )
        ctx.restoreGState()
    }

    /// Lavis strictement dans les glyphes. Pas d’élargissement de 2,4 pt :
    /// un trait autour sortirait des chiffres. Les contreformes restent des trous
    /// (remplissage winding). Le fondu extérieur de 1 pt est coupé par ce clip.
    static func drawGlyphMask(
        in ctx: CGContext,
        paths: [CGPath],
        seed: UInt64,
        canvas: CGSize,
        rim: CGFloat
    ) {
        guard !paths.isEmpty, canvas.width > 1, canvas.height > 1 else { return }
        ctx.saveGState()
        for path in paths { ctx.addPath(path) }
        ctx.clip(using: .winding)
        ctx.clear(CGRect(origin: .zero, size: canvas))
        drawWatercolorField(
            in: ctx,
            paths: paths,
            bodyPaths: [],
            bridgePaths: [],
            seed: seed,
            canvas: canvas,
            rim: rim
        )
        ctx.restoreGState()
    }

    /// Marge autour du corps (rayon 5) pour le bord qui s’efface.
    static let raceMarkEdgePad: CGFloat = 1.6

    static func raceMarkCanvasSide(radius: CGFloat) -> CGFloat {
        (radius + raceMarkEdgePad) * 2
    }

    /// Tache des repères de la ligne de course. Gris pré-multiplié : le sprite
    /// porte la teinte (`color`, `colorBlendFactor` 1). Une forme = une texture.
    @MainActor
    static func raceMarkTexture(diamond: Bool, radius: CGFloat) -> SKTexture {
        let scale = max(1, UITraitCollection.current.displayScale)
        let key = RaceMarkKey(
            diamond: diamond,
            pixelRadius: max(1, Int((radius * scale).rounded())),
            scaleHundredths: Int((scale * 100).rounded())
        )
        return raceMarkCache.texture(for: key) {
            bakeRaceMark(diamond: diamond, radius: radius, scale: scale)
        }
    }

    /// Image du gros score. Le canvas est la boîte typographique du label
    /// (ascender / descender), centrée comme un `SKLabelNode` en `.center`.
    /// Marge horizontale transparente de 1 pt : rien n’est peint hors des glyphes.
    /// `variant` 0 garde la graine historique. Le HUD ne peint que les chiffres 0–9,
    /// en quelques variantes, pour ne pas refaire ce lavis à chaque entier du roll.
    static func scoreGlyphImage(
        text: String,
        font: UIFont,
        light: Bool,
        scale: CGFloat,
        variant: Int = 0
    ) -> UIImage? {
        guard let layout = scoreGlyphLayout(text: text, font: font), scale > 0 else { return nil }
        let white = scoreDigitWhite(light: light)
        let rim = scoreRim(white: white, light: light)
        var seed = glyphSeed(text)
        if variant != 0 {
            seed ^= UInt64(variant) &* 0x9E3779B97F4A7C15
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        return UIGraphicsImageRenderer(size: layout.canvas, format: format).image { context in
            drawGlyphMask(
                in: context.cgContext,
                paths: layout.paths,
                seed: seed,
                canvas: layout.canvas,
                rim: rim
            )
        }
    }

    /// Trois lavis par chiffre. Le roll pioche dedans : pas de nouvelle peinture.
    static let scoreDigitVariantCount = 3

    /// Variante stable pour ce score et cette place. Deux « 1 » d’un même nombre diffèrent.
    static func scoreDigitVariant(forScore text: String, index: Int) -> Int {
        let mixed = glyphSeed(text) &+ UInt64(index) &* 0x9E3779B97F4A7C15
        return Int(mixed % UInt64(scoreDigitVariantCount))
    }

    /// Texture en cache (texte + variante + police + corps + thème + échelle).
    /// Le gros score n’en demande que les chiffres, pas chaque entier du roll.
    @MainActor
    static func scoreGlyphTexture(
        text: String,
        fontName: String,
        pointSize: CGFloat,
        light: Bool,
        variant: Int = 0
    ) -> (texture: SKTexture, pointSize: CGSize)? {
        let scale = max(1, UITraitCollection.current.displayScale)
        let font = UIFont(name: fontName, size: pointSize) ?? UIFont.systemFont(ofSize: pointSize)
        let key = glyphKey(
            text: text,
            variant: variant,
            fontName: font.fontName,
            pointSize: pointSize,
            light: light,
            scale: scale
        )
        if let hit = glyphCache.entry(for: key) {
            return (hit.texture, hit.pointSize)
        }
        guard let image = scoreGlyphImage(
            text: text,
            font: font,
            light: light,
            scale: scale,
            variant: variant
        ) else {
            return nil
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let canvas = image.size
        glyphCache.store(key, texture: texture, pointSize: canvas)
        return (texture, canvas)
    }

    /// Peint 0–9 hors du fil du jeu, une fois par police et par thème.
    /// Le chiffre déjà affiché peut encore être peint sur le fil : un seul glyphe.
    @MainActor
    static func prewarmScoreDigits(fontName: String, pointSize: CGFloat, light: Bool) {
        let scale = max(1, UITraitCollection.current.displayScale)
        let font = UIFont(name: fontName, size: pointSize) ?? UIFont.systemFont(ofSize: pointSize)
        let warm = "\(font.fontName)|\(Int((pointSize * 1000).rounded()))|\(light ? 1 : 0)|\(Int((scale * 1000).rounded()))"
        guard glyphCache.claimWarm(warm) else { return }
        let capturedName = font.fontName
        let capturedSize = pointSize
        DispatchQueue.global(qos: .userInteractive).async {
            var boxes: [GlyphImageBox] = []
            let bakeFont = UIFont(name: capturedName, size: capturedSize)
                ?? UIFont.systemFont(ofSize: capturedSize)
            for digit in 0...9 {
                for variant in 0..<scoreDigitVariantCount {
                    let text = String(digit)
                    let key = glyphKey(
                        text: text,
                        variant: variant,
                        fontName: bakeFont.fontName,
                        pointSize: capturedSize,
                        light: light,
                        scale: scale
                    )
                    if glyphCache.entry(for: key) != nil { continue }
                    guard let image = scoreGlyphImage(
                        text: text,
                        font: bakeFont,
                        light: light,
                        scale: scale,
                        variant: variant
                    ) else { continue }
                    boxes.append(GlyphImageBox(image: image, key: key))
                }
            }
            guard !boxes.isEmpty else { return }
            DispatchQueue.main.async {
                for box in boxes {
                    if glyphCache.entry(for: box.key) != nil { continue }
                    let texture = SKTexture(image: box.image)
                    texture.filteringMode = .linear
                    glyphCache.store(box.key, texture: texture, pointSize: box.image.size)
                }
            }
        }
    }

    /// Repère partagé avec le test : origine à gauche de la ligne, baseline depuis le haut.
    struct ScoreGlyphLayout {
        var canvas: CGSize
        var originX: CGFloat
        var baselineFromTop: CGFloat
        var paths: [CGPath]
    }

    static func scoreGlyphLayout(text: String, font: UIFont) -> ScoreGlyphLayout? {
        guard !text.isEmpty else { return nil }
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        guard lineWidth > 0.5 else { return nil }
        let pad: CGFloat = 2
        let canvas = CGSize(
            width: lineWidth + pad,
            height: max(1, font.ascender - font.descender)
        )
        let originX = (canvas.width - lineWidth) / 2
        let baseline = font.ascender
        let ctFont = font as CTFont
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return nil }
        var paths: [CGPath] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            glyphs.withUnsafeMutableBufferPointer { glyphBuf in
                positions.withUnsafeMutableBufferPointer { posBuf in
                    guard let glyphPtr = glyphBuf.baseAddress, let positionPtr = posBuf.baseAddress else { return }
                    CTRunGetGlyphs(run, CFRange(location: 0, length: count), glyphPtr)
                    CTRunGetPositions(run, CFRange(location: 0, length: count), positionPtr)
                }
            }
            for index in 0..<count {
                guard let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[index], nil) else { continue }
                var transform = CGAffineTransform(
                    a: 1, b: 0, c: 0, d: -1,
                    tx: originX + positions[index].x,
                    ty: baseline - positions[index].y
                )
                if let placed = glyphPath.copy(using: &transform) {
                    paths.append(placed)
                }
            }
        }
        guard !paths.isEmpty else { return nil }
        return ScoreGlyphLayout(
            canvas: canvas,
            originX: originX,
            baselineFromTop: baseline,
            paths: paths
        )
    }

    /// Un chiffre du gros score, centré comme le label (y vers le haut).
    struct ScoreDigitPlacement {
        var character: String
        var center: CGPoint
    }

    /// Places des glyphes dans le repère d’un `SKLabelNode` en `.center`.
    /// La largeur vient de la ligne entière, pour garder l’approche de Chelsea.
    static func scoreDigitPlacements(text: String, font: UIFont) -> [ScoreDigitPlacement] {
        guard !text.isEmpty else { return [] }
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        guard lineWidth > 0.5, let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        let ns = text as NSString
        var placements: [ScoreDigitPlacement] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            positions.withUnsafeMutableBufferPointer { posBuf in
                advances.withUnsafeMutableBufferPointer { advBuf in
                    guard let positionPtr = posBuf.baseAddress, let advancePtr = advBuf.baseAddress else { return }
                    CTRunGetPositions(run, CFRange(location: 0, length: count), positionPtr)
                    CTRunGetAdvances(run, CFRange(location: 0, length: count), advancePtr)
                }
            }
            let stringRange = CTRunGetStringRange(run)
            for index in 0..<count {
                let loc = stringRange.location + index
                let character: String
                if loc >= 0, loc < ns.length {
                    character = ns.substring(with: NSRange(location: loc, length: 1))
                } else {
                    character = "?"
                }
                let pen = positions[index].x
                let advance = advances[index].width
                placements.append(ScoreDigitPlacement(
                    character: character,
                    center: CGPoint(x: pen + advance / 2 - lineWidth / 2, y: 0)
                ))
            }
        }
        return placements
    }

    /// Lavis dans la silhouette d'origine. Flaques de 9–18 pt, duvet fin calmé,
    /// charge sur les 2 pt intérieurs des formes épaisses, fondu sur 1 pt à l'extérieur.
    /// Coordonnées en pixels, y vers le bas.
    private static func drawWatercolorField(
        in ctx: CGContext,
        paths: [CGPath],
        bodyPaths: [CGPath],
        bridgePaths: [CGPath],
        seed: UInt64,
        canvas: CGSize,
        rim: CGFloat
    ) {
        let scale = max(1, hypot(ctx.ctm.a, ctx.ctm.c))
        let budgetWidth = max(1, Int((canvas.width * scale).rounded()))
        let budgetHeight = max(1, Int((canvas.height * scale).rounded()))
        guard budgetWidth * budgetHeight <= 1_600_000 else { return }
        guard let covered = coverageMask(paths: paths, canvas: canvas, scale: scale),
              covered.inside.count == covered.width * covered.height,
              covered.width * covered.height <= 1_600_000 else { return }
        let width = covered.width
        let height = covered.height
        let inside = covered.inside
        let pixelScale = CGFloat(width) / max(canvas.width, 0.001)

        let fromOutside = chamfer(
            seedsZero: inside.map { $0 ? UInt8(0) : UInt8(1) },
            width: width, height: height
        )
        let fromInside = chamfer(
            seedsZero: inside.map { $0 ? UInt8(1) : UInt8(0) },
            width: width, height: height
        )
        let granulation = 0.9 + (1 - min(1, max(0, rim))) * 1.6
        let phaseX = unit(seed, 3) * 4096
        let phaseY = unit(seed, 5) * 4096
        // Teintes pâles : `rim` plus bas, cuvette un peu plus marquée. Pas de trait gris.
        let loadStrength = 0.16 + (1 - min(1, max(0.84, rim))) * 0.45
        // Demi-largeur locale en cases de 4 pt : une case dépasse 4,5 pt.
        // Une seule passe, pas une marche par pixel de bord.
        let thickCut = UInt16(min(65535, Int((4.5 * 3 * pixelScale).rounded(.up))))
        let bridgeField = bridgeDistance(
            bodyPaths: bodyPaths,
            bridgePaths: bridgePaths,
            canvas: canvas,
            scale: scale,
            width: width,
            height: height
        )
        let bin = max(1, Int((4 * pixelScale).rounded()))
        let binsX = max(1, (width + bin - 1) / bin)
        let binsY = max(1, (height + bin - 1) / bin)
        var coarse = [UInt16](repeating: 0, count: binsX * binsY)
        for y in 0..<height {
            let by = min(binsY - 1, y / bin)
            let row = by * binsX
            for x in 0..<width {
                let i = y * width + x
                guard inside[i] else { continue }
                let k = row + min(binsX - 1, x / bin)
                if fromOutside[i] > coarse[k] { coarse[k] = fromOutside[i] }
            }
        }
        var depth = coarse
        for by in 0..<binsY {
            for bx in 0..<binsX {
                var peak = coarse[by * binsX + bx]
                for dy in -1...1 {
                    let ny = by + dy
                    guard ny >= 0, ny < binsY else { continue }
                    for dx in -1...1 {
                        let nx = bx + dx
                        guard nx >= 0, nx < binsX else { continue }
                        peak = max(peak, coarse[ny * binsX + nx])
                    }
                }
                depth[by * binsX + bx] = peak
            }
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let py = CGFloat(y) + phaseY
                for x in 0..<width {
                    let i = y * width + x
                    let dPts = (inside[i] ? CGFloat(fromOutside[i]) : -CGFloat(fromInside[i])) / 3 / pixelScale
                    let bridgePts = bridgeField?.signed[i] ?? -999
                    let inBody = bridgeField?.inBody[i] ?? false
                    // Hors de la case, et seulement contre la capsule. Le tour
                    // des autres cases garde son fondu de 1 pt.
                    let onBridge = bridgeField != nil && !inBody && bridgePts > -1.05
                    if onBridge {
                        // Lentille : rien hors de la capsule, le milieu garde le lavis.
                        // Un bord plus opaque traçait la barre. Les cases ne passent pas ici.
                        guard bridgePts > 0 else { continue }
                    } else if dPts < -1.05 {
                        continue
                    }
                    let px = CGFloat(x) + phaseX
                    var sample = pigment(
                        seed: seed, px: px, py: py, scale: pixelScale,
                        granulation: granulation, wash: true
                    )
                    if onBridge {
                        sample.alpha *= smoothstep(0, 2.6, bridgePts)
                    } else if dPts < 0 {
                        sample.alpha *= smoothstep(-1, 0, dPts)
                    } else if dPts < 2.2 {
                        let band = 1 - smoothstep(0, 2, dPts)
                        let load = band * band * (3 - 2 * band)
                        let thick = depth[min(binsY - 1, y / bin) * binsX + min(binsX - 1, x / bin)] >= thickCut
                        if thick {
                            sample.gray *= (1 - loadStrength * load)
                        }
                        sample.alpha = min(1, sample.alpha + (1 - sample.alpha) * 0.85 * load)
                    }
                    let channel = UInt8((sample.gray * sample.alpha * 255).rounded())
                    let a = UInt8((sample.alpha * 255).rounded())
                    let o = i * 4
                    buffer[o] = channel
                    buffer[o + 1] = channel
                    buffer[o + 2] = channel
                    buffer[o + 3] = a
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
        // Le buffer est haut → bas. `draw` dans le contexte UIKit le retourne,
        // et la pièce diagonale se retrouve sur l'autre coin.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .low
        // Remplace le blanc résiduel. Un fondu en source-over sur ce blanc
        // redevient opaque et trace la barre.
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(origin: .zero, size: canvas))
        ctx.restoreGState()
    }

    /// `wash` : flaques d'aquarelle (Blox, Brix). Le disque Magix / bombe garde le grain serré.
    private static func pigment(
        seed: UInt64,
        px: CGFloat,
        py: CGFloat,
        scale: CGFloat,
        granulation: CGFloat,
        wash: Bool = false
    ) -> (gray: CGFloat, alpha: CGFloat) {
        let low = valueNoise(seed, px, py, spacing: 18 * scale, salt: 11)
        let mid = valueNoise(seed, px, py, spacing: (wash ? 9.5 : 5.2) * scale, salt: 29)
        let fine = valueNoise(seed, px, py, spacing: 1.55 * scale, salt: 47)
        if !wash {
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
        // Creux de 9–16 pt : le washi apparaît par taches. Plancher 0,58, le chiffre
        // des Brix reste sur un fond tenu. Le duvet de 1,55 pt ne fait plus la surface.
        let pool = max(0, -low) * 0.70 + max(0, -mid) * 0.40
        let opened = min(0.42, pool * 0.50)
        let tooth = max(0, fine) * 0.06 * min(1.25, granulation)
        let alpha = max(0.58, 1 - opened - tooth)
        var gray = 0.995 - min(0.045, pool * 0.05)
        gray = min(1, max(0.94, gray))
        return (gray, alpha)
    }

    /// Distance signée à la capsule, en points. `inBody` vient des cases seules :
    /// le pont ne recouvre pas leur lavis. Nil s'il n'y a pas de diagonale.
    private struct BridgeField {
        var signed: [CGFloat]
        var inBody: [Bool]
    }

    private static func bridgeDistance(
        bodyPaths: [CGPath],
        bridgePaths: [CGPath],
        canvas: CGSize,
        scale: CGFloat,
        width: Int,
        height: Int
    ) -> BridgeField? {
        guard !bodyPaths.isEmpty, !bridgePaths.isEmpty else { return nil }
        guard let body = coverageMask(paths: bodyPaths, canvas: canvas, scale: scale),
              let bridge = coverageMask(paths: bridgePaths, canvas: canvas, scale: scale),
              body.width == width, body.height == height,
              bridge.width == width, bridge.height == height,
              body.inside.count == width * height,
              bridge.inside.count == width * height else { return nil }
        let pixelScale = CGFloat(width) / max(canvas.width, 0.001)
        let fromOutside = chamfer(
            seedsZero: bridge.inside.map { $0 ? UInt8(0) : UInt8(1) },
            width: width, height: height
        )
        let fromInside = chamfer(
            seedsZero: bridge.inside.map { $0 ? UInt8(1) : UInt8(0) },
            width: width, height: height
        )
        var signed = [CGFloat](repeating: 0, count: width * height)
        for i in 0..<signed.count {
            signed[i] = (bridge.inside[i] ? CGFloat(fromOutside[i]) : -CGFloat(fromInside[i])) / 3 / pixelScale
        }
        return BridgeField(signed: signed, inBody: body.inside)
    }

    /// Blanc = intérieur, dans l'espace UIKit (y vers le bas), même format que le masque.
    private static func coverageMask(
        paths: [CGPath],
        canvas: CGSize,
        scale: CGFloat
    ) -> (inside: [Bool], width: Int, height: Int)? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            let g = renderer.cgContext
            g.setShouldAntialias(false)
            g.setFillColor(UIColor.black.cgColor)
            g.fill(CGRect(origin: .zero, size: canvas))
            g.setFillColor(UIColor.white.cgColor)
            for path in paths { g.addPath(path) }
            g.fillPath(using: .winding)
        }
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let width = cg.width
        let height = cg.height
        let bpp = max(1, cg.bitsPerPixel / 8)
        let rowBytes = cg.bytesPerRow
        var inside = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let p = ptr + y * rowBytes + x * bpp
                inside[y * width + x] = p[0] > 128 || (bpp > 1 && p[1] > 128)
            }
        }
        return (inside, width, height)
    }

    /// Distance chamfrein 3-4, en tiers de pixel. Les graines valent 0.
    private static func chamfer(seedsZero: [UInt8], width: Int, height: Int) -> [UInt16] {
        let n = width * height
        var dist = [UInt16](repeating: 65535, count: n)
        guard width > 0, height > 0, seedsZero.count == n else { return dist }
        for i in 0..<n where seedsZero[i] != 0 {
            dist[i] = 0
        }
        func near(_ v: UInt16, _ add: UInt16) -> UInt16 {
            v >= 65535 - add ? 65535 : v + add
        }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                var d = dist[i]
                if x > 0 { d = min(d, near(dist[i - 1], 3)) }
                if y > 0 { d = min(d, near(dist[i - width], 3)) }
                if x > 0, y > 0 { d = min(d, near(dist[i - width - 1], 4)) }
                if x + 1 < width, y > 0 { d = min(d, near(dist[i - width + 1], 4)) }
                dist[i] = d
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                var d = dist[i]
                if x + 1 < width { d = min(d, near(dist[i + 1], 3)) }
                if y + 1 < height { d = min(d, near(dist[i + width], 3)) }
                if x + 1 < width, y + 1 < height { d = min(d, near(dist[i + width + 1], 4)) }
                if x > 0, y + 1 < height { d = min(d, near(dist[i + width - 1], 4)) }
                dist[i] = d
            }
        }
        return dist
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

    private struct RaceMarkKey: Hashable {
        var diamond: Bool
        var pixelRadius: Int
        var scaleHundredths: Int
    }

    private static let raceMarkCache = RaceMarkCache()

    private final class RaceMarkCache: @unchecked Sendable {
        private let lock = NSLock()
        private var textures: [RaceMarkKey: SKTexture] = [:]

        func texture(for key: RaceMarkKey, make: () -> SKTexture) -> SKTexture {
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

    /// Goutte de 10 pt. Les flaques sont plus serrées que sur un Blox, sinon
    /// le point entier serait un seul creux. Le bord s’efface sur ~1 pt.
    private static func bakeRaceMark(diamond: Bool, radius: CGFloat, scale: CGFloat) -> SKTexture {
        let side = raceMarkCanvasSide(radius: radius)
        let canvas = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            drawRaceMark(
                in: context.cgContext,
                canvas: canvas,
                scale: scale,
                diamond: diamond,
                radius: radius
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func drawRaceMark(
        in ctx: CGContext,
        canvas: CGSize,
        scale: CGFloat,
        diamond: Bool,
        radius: CGFloat
    ) {
        let width = max(1, Int((canvas.width * scale).rounded()))
        let height = max(1, Int((canvas.height * scale).rounded()))
        let seed: UInt64 = diamond ? 0xD1A0_5EED : 0xC1A0_1E01
        let phaseX = unit(seed, 3) * 4096
        let phaseY = unit(seed, 5) * 4096
        let cx = canvas.width * 0.5
        let cy = canvas.height * 0.5
        let pixelScale = CGFloat(width) / max(canvas.width, 0.001)
        // Espacement ~0,42 : deux ou trois creux tiennent dans le point.
        let pigmentScale = pixelScale * 0.42

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let px = (CGFloat(x) + 0.5) / scale
                    let py = (CGFloat(y) + 0.5) / scale
                    let dx = px - cx
                    let dy = py - cy
                    let angle = atan2(dy, dx)
                    let wobble = valueNoise(seed, angle * 8 + 20, 4, spacing: 3.2, salt: 17) * 0.40
                    let dist = diamond ? abs(dx) + abs(dy) : hypot(dx, dy)
                    let cover = 1 - smoothstep(radius - 0.15, radius + 0.9, dist - wobble)
                    if cover <= 0.004 { continue }
                    var sample = pigment(
                        seed: seed,
                        px: CGFloat(x) + phaseX,
                        py: CGFloat(y) + phaseY,
                        scale: pigmentScale,
                        granulation: 1,
                        wash: true
                    )
                    // Le creux éclaircit. Il ne perce pas le repère.
                    sample.alpha = min(1, (0.62 + 0.38 * sample.alpha) * cover)
                    let channel = UInt8((sample.gray * sample.alpha * 255).rounded())
                    let a = UInt8((sample.alpha * 255).rounded())
                    let o = (y * width + x) * 4
                    base[o] = channel
                    base[o + 1] = channel
                    base[o + 2] = channel
                    base[o + 3] = a
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
        ctx.saveGState()
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .low
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(origin: .zero, size: canvas))
        ctx.restoreGState()
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

    /// Même cuvette que les pièces (`edgeMultiplier`). Le gris du score est une teinte pâle ou moyenne.
    private static func scoreRim(white: CGFloat, light: Bool) -> CGFloat {
        if light {
            return max(0.84, 0.98 - 0.10 * white)
        }
        return max(0.90, 0.99 - 0.05 * white)
    }

    /// Stable pour un même nombre : chaque entier a son lavis, toujours le même.
    private static func glyphSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xC0FFEE
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x9E3779B97F4A7C15
            hash = (hash << 7) | (hash >> 57)
        }
        return hash
    }

    private struct GlyphKey: Hashable {
        var text: String
        var variant: Int
        var fontName: String
        var pointSizeMilli: Int
        var light: Bool
        var scaleMilli: Int
    }

    private struct GlyphEntry {
        var texture: SKTexture
        var pointSize: CGSize
    }

    /// Passe une image peinte hors du fil vers la création de texture.
    private final class GlyphImageBox: @unchecked Sendable {
        let image: UIImage
        let key: GlyphKey
        init(image: UIImage, key: GlyphKey) {
            self.image = image
            self.key = key
        }
    }

    private static func glyphKey(
        text: String,
        variant: Int,
        fontName: String,
        pointSize: CGFloat,
        light: Bool,
        scale: CGFloat
    ) -> GlyphKey {
        GlyphKey(
            text: text,
            variant: variant,
            fontName: fontName,
            pointSizeMilli: Int((pointSize * 1000).rounded()),
            light: light,
            scaleMilli: Int((scale * 1000).rounded())
        )
    }

    private static let glyphCache = GlyphCache()

    /// Les chiffres 0–9 et leurs variantes tiennent largement sous le plafond.
    private final class GlyphCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [GlyphKey: GlyphEntry] = [:]
        private var order: [GlyphKey] = []
        private var warmed: Set<String> = []
        private let limit = 64

        func entry(for key: GlyphKey) -> GlyphEntry? {
            lock.lock()
            defer { lock.unlock() }
            return entries[key]
        }

        func store(_ key: GlyphKey, texture: SKTexture, pointSize: CGSize) {
            lock.lock()
            defer { lock.unlock() }
            if entries[key] != nil { return }
            entries[key] = GlyphEntry(texture: texture, pointSize: pointSize)
            order.append(key)
            while order.count > limit {
                let drop = order.removeFirst()
                entries[drop] = nil
            }
        }

        /// Une seule préchauffe par police et par thème.
        func claimWarm(_ key: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if warmed.contains(key) { return false }
            warmed.insert(key)
            return true
        }
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
            drawPaperField(in: ctx, rect: rect, scale: scale, light: light)

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

    /// Grain continu, très léger, sur toute la feuille. Pas de points isolés :
    /// ils se lisaient comme des salissures. Le filet de crayon est tracé après.
    private static func drawPaperField(in ctx: CGContext, rect: CGRect, scale: CGFloat, light: Bool) {
        let base = gridPaperUIColor(light: light)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard base.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            ctx.setFillColor(base.cgColor)
            ctx.fill(rect)
            return
        }
        let width = max(1, Int((rect.width * scale).rounded()))
        let height = max(1, Int((rect.height * scale).rounded()))
        guard width * height <= 1_600_000 else {
            ctx.setFillColor(base.cgColor)
            ctx.fill(rect)
            return
        }

        let seed: UInt64 = light ? 0xC0FFEE : 0x5A11
        // ± environ 1,5 % : visible de près, sans motif.
        let fineAmp: CGFloat = 0.010
        let slowAmp: CGFloat = 0.005
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let py = CGFloat(y)
                for x in 0..<width {
                    let px = CGFloat(x)
                    let fine = valueNoise(seed, px, py, spacing: 1.7 * scale, salt: 17)
                    let slow = valueNoise(seed, px, py, spacing: 6.5 * scale, salt: 31)
                    let delta = fine * fineAmp + slow * slowAmp
                    let i = (y * width + x) * 4
                    buffer[i] = paperChannel(red + delta)
                    buffer[i + 1] = paperChannel(green + delta)
                    buffer[i + 2] = paperChannel(blue + delta)
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
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            ctx.setFillColor(base.cgColor)
            ctx.fill(rect)
            return
        }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: rect)
    }

    private static func paperChannel(_ value: CGFloat) -> UInt8 {
        UInt8((min(1, max(0, value)) * 255).rounded())
    }

    private static func unit(_ seed: UInt64, _ index: Int) -> CGFloat {
        var x = seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x = x ^ (x >> 31)
        return CGFloat(x % 10_000) / 10_000
    }
}

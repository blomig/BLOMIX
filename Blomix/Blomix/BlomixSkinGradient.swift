//
//  BlomixSkinGradient.swift
//  Blomix
//
//  Dégradé vivant de la palette blox du skin (même matière que les Magix / pastilles,
//  plus lent). Plancher des puits de boutons — SpriteKit + UIKit.
//

import CoreText
import QuartzCore
import SpriteKit
import UIKit

// MARK: - Constantes

@MainActor
enum BlomixSkinGradient {
    /// Plus lent que le shader Magix (`u_time * 0.09`).
    static let wellTimeScale: Float = 0.035

    static func paletteSKColors() -> [SKColor] {
        let colors = BlomixSkinCatalog.shared.bloxSKColors()
        if colors.count >= 2 { return colors }
        return [
            SKColor(red: 0.00, green: 0.70, blue: 0.91, alpha: 1),
            SKColor(red: 0.95, green: 0.00, blue: 0.62, alpha: 1),
            SKColor(red: 0.00, green: 0.56, blue: 0.20, alpha: 1),
            SKColor(red: 1.00, green: 0.70, blue: 0.00, alpha: 1),
            SKColor(red: 0.99, green: 0.63, blue: 1.00, alpha: 1),
            SKColor(red: 0.00, green: 0.41, blue: 0.55, alpha: 1),
        ]
    }

    static func paletteUIColors() -> [UIColor] {
        paletteSKColors().map { UIColor(cgColor: $0.cgColor) }
    }

    /// Texture 2×2 blanche — SpriteKit a besoin d’UVs valides pour le fragment shader.
    static let shaderBaseTexture: SKTexture = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
    }()

    private static var shaderCache: [String: SKShader] = [:]

    static func invalidateShaderCache() {
        shaderCache.removeAll()
    }

    static func makeShader(timeScale: Float = wellTimeScale, timeOffset: Float = 0) -> SKShader {
        let colors = paletteSKColors()
        let n = colors.count
        let key = "\(BlomixSkinCatalog.shared.selectedSkinId)|\(n)|\(timeScale)|\(timeOffset)"
        if let cached = shaderCache[key] { return cached }

        func v3(_ c: SKColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "vec3(%.4f,%.4f,%.4f)", Float(r), Float(g), Float(b))
        }

        var branches = ""
        for i in 0..<n {
            let next = (i + 1) % n
            let limit = String(format: "%.1f", Float(i + 1))
            if i == 0 {
                branches += "    if (fi<\(limit)){ca=\(v3(colors[i]));cb=\(v3(colors[next]));}\n"
            } else if i < n - 1 {
                branches += "    else if (fi<\(limit)){ca=\(v3(colors[i]));cb=\(v3(colors[next]));}\n"
            } else {
                branches += "    else{ca=\(v3(colors[i]));cb=\(v3(colors[next]));}\n"
            }
        }
        let nStr = String(format: "%.1f", Float(n))
        let src = """
        vec3 mgxPal(float t){
            float N=\(nStr);
            float ti=fract(t)*N;
            float fi=floor(ti);
            float f=smoothstep(0.0,1.0,fract(ti));
            vec3 ca=vec3(1.0),cb=vec3(1.0);
        \(branches)    return mix(ca,cb,f);
        }
        void main(){
            vec2 uv=v_tex_coord;
            float t=u_time*\(String(format: "%.4f", timeScale))+\(String(format: "%.4f", timeOffset));
            vec3 c1=mgxPal(t);
            vec3 c2=mgxPal(t+0.333);
            vec3 c3=mgxPal(t+0.667);
            float wx=sin(uv.x*3.14159+t*0.5)*0.5+0.5;
            float wy=cos(uv.y*2.2-t*0.35)*0.5+0.5;
            vec3 ab=mix(c1,c2,wx);
            vec3 col=mix(ab,c3,wy*0.38);
            gl_FragColor=vec4(col,1.0);
        }
        """
        let shader = SKShader(source: src)
        shaderCache[key] = shader
        return shader
    }

    /// Puits SpriteKit : sprite shader clipé en rectangle arrondi. Ne pas scaler ce nœud à l’appui.
    static func makeWellNode(size: CGSize, cornerRadius: CGFloat, timeOffset: Float = 0) -> SKCropNode {
        let crop = SKCropNode()
        crop.name = "blomixWell"
        crop.userData = NSMutableDictionary()
        crop.userData?["cornerRadius"] = cornerRadius

        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let mask = SKShapeNode(rect: rect, cornerRadius: cornerRadius)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask

        let fill = SKSpriteNode(texture: shaderBaseTexture, size: size)
        fill.name = "blomixWellFill"
        fill.colorBlendFactor = 0
        fill.color = .white
        fill.shader = makeShader(timeOffset: timeOffset)
        crop.addChild(fill)

        let lip = SKSpriteNode(
            texture: BlomixButtonRelief.wellInnerShadowTexture(size: size, cornerRadius: cornerRadius),
            size: size
        )
        lip.name = "blomixWellInnerShadow"
        lip.zPosition = 1
        crop.addChild(lip)
        return crop
    }

    static func refreshWellNode(_ root: SKNode, timeOffset: Float = 0) {
        if let fill = root.childNode(withName: "//blomixWellFill") as? SKSpriteNode {
            fill.shader = makeShader(timeOffset: timeOffset)
        }
        if let lip = root.childNode(withName: "//blomixWellInnerShadow") as? SKSpriteNode {
            let size = lip.size
            let stored = (lip.parent?.userData?["cornerRadius"] as? CGFloat)
                ?? BlomixUIDestinationButtonStyle.cornerRadius
            lip.texture = BlomixButtonRelief.wellInnerShadowTexture(size: size, cornerRadius: stored)
        }
    }
}

// MARK: - Relief (liseré / ombres de puits)

@MainActor
enum BlomixButtonRelief {
    static var wellLipAlpha: CGFloat { BlomixAppearance.isDark ? 0.42 : 0.22 }
    static var contactShadowAlpha: CGFloat { BlomixAppearance.isDark ? 0.32 : 0.18 }
    static var contactShadowAlphaPressed: CGFloat { BlomixAppearance.isDark ? 0.10 : 0.06 }
    static let contactShadowOffsetY: CGFloat = 2.5
    static var highlightAlpha: CGFloat { BlomixAppearance.isDark ? 0.42 : 0.55 }
    static var capsuleBottomShadeAlpha: CGFloat { BlomixAppearance.isDark ? 0.28 : 0.14 }

    static func wellInnerShadowImage(size: CGSize, cornerRadius: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)

            cg.saveGState()
            path.addClip()

            let top = wellLipAlpha
            let colors = [
                UIColor.black.withAlphaComponent(top).cgColor,
                UIColor.black.withAlphaComponent(top * 0.35).cgColor,
                UIColor.clear.cgColor,
            ] as CFArray
            let locs: [CGFloat] = [0, 0.22, 0.55]
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locs) {
                cg.drawLinearGradient(
                    grad,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height * 0.62),
                    options: []
                )
            }

            cg.setShadow(
                offset: CGSize(width: 0, height: 2.2),
                blur: 3.2,
                color: UIColor.black.withAlphaComponent(top * 0.85).cgColor
            )
            cg.setFillColor(UIColor.black.cgColor)
            let outer = rect.insetBy(dx: -28, dy: -28)
            cg.addRect(outer)
            cg.addPath(path.cgPath)
            cg.drawPath(using: .eoFill)
            cg.restoreGState()
        }
    }

    static func wellInnerShadowTexture(size: CGSize, cornerRadius: CGFloat) -> SKTexture {
        let tex = SKTexture(image: wellInnerShadowImage(size: size, cornerRadius: cornerRadius))
        tex.filteringMode = .linear
        return tex
    }

    /// Liseré haut + ombre bas sur la face de la capsule.
    static func capsuleBevelImage(size: CGSize, cornerRadius: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            cg.saveGState()
            path.addClip()

            let hi = highlightAlpha
            let topColors = [
                UIColor.white.withAlphaComponent(hi).cgColor,
                UIColor.white.withAlphaComponent(hi * 0.35).cgColor,
                UIColor.clear.cgColor,
            ] as CFArray
            let topLocs: [CGFloat] = [0, 0.12, 0.34]
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: topColors, locations: topLocs) {
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height * 0.42), options: [])
            }

            // Sombre : ombre bas en noir translucide (lisible sur #232323).
            // Clair : pas de voile noir — le dégradé haut se termine en transparent
            // (= teinte exacte de la capsule), sinon le bas paraît plus sombre que le fill.
            if BlomixAppearance.isDark {
                let sh = capsuleBottomShadeAlpha
                let botColors = [
                    UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(sh * 0.45).cgColor,
                    UIColor.black.withAlphaComponent(sh).cgColor,
                ] as CFArray
                let botLocs: [CGFloat] = [0.55, 0.82, 1]
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: botColors, locations: botLocs) {
                    cg.drawLinearGradient(
                        grad,
                        start: CGPoint(x: 0, y: size.height * 0.45),
                        end: CGPoint(x: 0, y: size.height),
                        options: []
                    )
                }
            }

            // Liseré fin sur l’arête haute.
            cg.saveGState()
            let band = CGRect(x: 0, y: 0, width: size.width, height: max(3, size.height * 0.22))
            cg.addRect(band)
            cg.clip()
            cg.setStrokeColor(UIColor.white.withAlphaComponent(hi * 0.85).cgColor)
            cg.setLineWidth(1.35)
            cg.addPath(path.cgPath)
            cg.strokePath()
            cg.restoreGState()

            cg.restoreGState()
        }
    }

    static func capsuleBevelTexture(size: CGSize, cornerRadius: CGFloat) -> SKTexture {
        let tex = SKTexture(image: capsuleBevelImage(size: size, cornerRadius: cornerRadius))
        tex.filteringMode = .linear
        return tex
    }

    // MARK: Wordmark trou (BLOMIX)

    static let wordmarkText = "BLOMIX"
    static let wordmarkPad: CGFloat = 10

    static func wordmarkFont(size: CGFloat) -> UIFont {
        BlomixTypography.displayFont(size: size)
    }

    static func wordmarkLayout(fontSize: CGFloat) -> (font: UIFont, canvas: CGSize, drawOrigin: CGPoint) {
        cutoutLayout(text: wordmarkText, fontSize: fontSize, pad: wordmarkPad)
    }

    static func cutoutLayout(
        text: String,
        fontSize: CGFloat,
        pad: CGFloat = wordmarkPad
    ) -> (font: UIFont, canvas: CGSize, drawOrigin: CGPoint) {
        let font = wordmarkFont(size: fontSize)
        let sz = (text as NSString).size(withAttributes: [.font: font])
        let canvas = CGSize(
            width: max(1, ceil(sz.width) + pad * 2),
            height: max(1, ceil(sz.height) + pad * 2)
        )
        return (font, canvas, CGPoint(x: pad, y: pad))
    }

    static func wordmarkMaskImage(fontSize: CGFloat) -> UIImage {
        cutoutMaskImage(text: wordmarkText, fontSize: fontSize, pad: wordmarkPad)
    }

    static func cutoutMaskImage(text: String, fontSize: CGFloat, pad: CGFloat = wordmarkPad) -> UIImage {
        let layout = cutoutLayout(text: text, fontSize: fontSize, pad: pad)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        return UIGraphicsImageRenderer(size: layout.canvas, format: format).image { _ in
            (text as NSString).draw(
                at: layout.drawOrigin,
                withAttributes: [
                    .font: layout.font,
                    .foregroundColor: UIColor.white,
                ]
            )
        }
    }

    static func wordmarkGlyphPath(fontSize: CGFloat) -> (path: CGPath, canvas: CGSize) {
        cutoutGlyphPath(text: wordmarkText, fontSize: fontSize, pad: wordmarkPad)
    }

    /// Un glyphe du wordmark, chemin en coordonnées UIKit (Y vers le bas) du canvas complet.
    struct CutoutGlyphSlice {
        let character: Character
        let path: CGPath
        let bounds: CGRect
    }

    static func cutoutGlyphSlices(
        text: String,
        fontSize: CGFloat,
        pad: CGFloat = wordmarkPad
    ) -> (slices: [CutoutGlyphSlice], canvas: CGSize) {
        let layout = cutoutLayout(text: text, fontSize: fontSize, pad: pad)
        let ctFont = layout.font as CTFont
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: layout.font])
        )
        let baselineY = layout.drawOrigin.y + layout.font.ascender
        let chars = Array(text)
        var charIndex = 0
        var slices: [CutoutGlyphSlice] = []
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            var runFont = ctFont
            if let attrs = CTRunGetAttributes(run) as? [CFString: Any],
               let f = attrs[kCTFontAttributeName] {
                runFont = (f as! CTFont)
            }
            for i in 0..<count {
                let ch: Character = charIndex < chars.count ? chars[charIndex] : "?"
                if charIndex < chars.count { charIndex += 1 }
                guard let gpath = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                var t = CGAffineTransform.identity
                t = t.translatedBy(x: layout.drawOrigin.x + positions[i].x, y: baselineY)
                t = t.scaledBy(x: 1, y: -1)
                let mapped = CGMutablePath()
                mapped.addPath(gpath, transform: t)
                let bounds = mapped.boundingBoxOfPath
                guard bounds.width > 0.4, bounds.height > 0.4 else { continue }
                slices.append(CutoutGlyphSlice(character: ch, path: mapped, bounds: bounds))
            }
        }
        return (slices, layout.canvas)
    }

    /// Contour des glyphes en coordonnées UIKit (Y vers le bas), pour le même inner-shadow que les puits.
    static func cutoutGlyphPath(
        text: String,
        fontSize: CGFloat,
        pad: CGFloat = wordmarkPad
    ) -> (path: CGPath, canvas: CGSize) {
        let (slices, canvas) = cutoutGlyphSlices(text: text, fontSize: fontSize, pad: pad)
        let path = CGMutablePath()
        for slice in slices {
            path.addPath(slice.path)
        }
        return (path, canvas)
    }

    /// Masque serré d’une lettre (blanc = plein) pour intro poinçon / crop par glyphe.
    static func cutoutLetterMaskImage(
        slice: CutoutGlyphSlice,
        pad: CGFloat = 2
    ) -> (image: UIImage, size: CGSize) {
        let bounds = slice.bounds
        let size = CGSize(
            width: max(1, ceil(bounds.width + pad * 2)),
            height: max(1, ceil(bounds.height + pad * 2))
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: -bounds.origin.x + pad, y: -bounds.origin.y + pad)
            cg.setFillColor(UIColor.white.cgColor)
            cg.addPath(slice.path)
            cg.drawPath(using: .eoFill)
        }
        return (image, size)
    }

    static func wordmarkInnerShadowImage(fontSize: CGFloat) -> UIImage {
        cutoutInnerShadowImage(text: wordmarkText, fontSize: fontSize, pad: wordmarkPad)
    }

    /// Ombre sous le rebord haut du trou (même recette que `wellInnerShadowImage`). Pas de liseré clair.
    static func cutoutInnerShadowImage(
        text: String,
        fontSize: CGFloat,
        pad: CGFloat = wordmarkPad
    ) -> UIImage {
        let (letterPath, canvas) = cutoutGlyphPath(text: text, fontSize: fontSize, pad: pad)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        let top = wellLipAlpha
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: canvas)
            cg.saveGState()
            cg.addPath(letterPath)
            cg.clip()
            cg.setShadow(
                offset: CGSize(width: 0, height: 2.2),
                blur: 3.2,
                color: UIColor.black.withAlphaComponent(top * 0.85).cgColor
            )
            cg.setFillColor(UIColor.black.cgColor)
            cg.addRect(rect.insetBy(dx: -28, dy: -28))
            cg.addPath(letterPath)
            cg.drawPath(using: .eoFill)
            cg.restoreGState()
        }
    }
}

// MARK: - Wordmark trou SpriteKit

@MainActor
final class BlomixCutoutWordmarkNode: SKNode {
    private var text: String
    private let fontSize: CGFloat
    private let timeOffset: Float
    private let pad: CGFloat

    convenience init(fontSize: CGFloat, timeOffset: Float = 0.08) {
        self.init(text: BlomixButtonRelief.wordmarkText, fontSize: fontSize, timeOffset: timeOffset)
    }

    init(text: String, fontSize: CGFloat, timeOffset: Float = 0.08, pad: CGFloat = BlomixButtonRelief.wordmarkPad) {
        self.text = text
        self.fontSize = fontSize
        self.timeOffset = timeOffset
        self.pad = pad
        super.init()
        rebuild()
        _ = NotificationCenter.default.addObserver(
            forName: .blomixSkinDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        _ = NotificationCenter.default.addObserver(
            forName: .blomixAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func setText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        rebuild()
    }

    func rebuild() {
        removeAllChildren()
        guard !text.isEmpty else { return }
        let layout = BlomixButtonRelief.cutoutLayout(text: text, fontSize: fontSize, pad: pad)
        let canvas = layout.canvas

        let crop = SKCropNode()
        crop.name = "blomixWordmarkWell"

        let maskTex = SKTexture(image: BlomixButtonRelief.cutoutMaskImage(text: text, fontSize: fontSize, pad: pad))
        maskTex.filteringMode = .linear
        let mask = SKSpriteNode(texture: maskTex, size: canvas)
        crop.maskNode = mask

        let fill = SKSpriteNode(texture: BlomixSkinGradient.shaderBaseTexture, size: canvas)
        fill.name = "blomixWellFill"
        fill.colorBlendFactor = 0
        fill.color = .white
        fill.shader = BlomixSkinGradient.makeShader(timeOffset: timeOffset)
        crop.addChild(fill)

        let lipTex = SKTexture(image: BlomixButtonRelief.cutoutInnerShadowImage(text: text, fontSize: fontSize, pad: pad))
        lipTex.filteringMode = .linear
        let lip = SKSpriteNode(texture: lipTex, size: canvas)
        lip.name = "blomixWordmarkLip"
        lip.zPosition = 1
        crop.addChild(lip)

        addChild(crop)
    }

    /// Cold launch accueil : six poinçons L→R (~2 s).
    static let punchIntroDuration: TimeInterval = 2.0

    private enum PunchIntro {
        static let firstPunchAt: TimeInterval = 0.20
        /// Cadence uniforme historique — fixe encore l’instant du dernier impact.
        static let interval: TimeInterval = 0.22
        /// Écart B → L (un peu plus posé que l’uniforme, pour laisser accélérer la suite).
        static let regularGap: TimeInterval = interval * 1.18
        static let settleDuration: TimeInterval = 0.16
        static let afterLastBeat: TimeInterval = 0.12
        static let impactScaleX: CGFloat = 1.18
        static let impactScaleY: CGFloat = 0.86
        static let impactDrop: CGFloat = 2.0

        /// Deux premières lettres à cadence régulière, ensuite accélération légère. Dernier impact inchangé.
        static func punchDelay(index i: Int, count n: Int) -> TimeInterval {
            let first = firstPunchAt
            let last = first + interval * TimeInterval(max(0, n - 1))
            if n <= 2 || i <= 1 {
                let gap = n <= 2 ? interval : regularGap
                return first + gap * TimeInterval(i)
            }
            let t1 = first + regularGap
            let steps = n - 2
            let span = last - t1
            let startGap = regularGap * 0.92
            let sumK = TimeInterval(steps * (steps - 1) / 2)
            let d = sumK > 0 ? (TimeInterval(steps) * startGap - span) / sumK : 0
            var acc: TimeInterval = 0
            for k in 0..<(i - 1) {
                acc += startGap - TimeInterval(k) * d
            }
            return t1 + acc
        }
    }

    /// Délai avant le reste de l’accueil (dernier poinçon + settle + un temps de lecture).
    static var punchIntroChromeDelay: TimeInterval {
        let gaps = max(0, BlomixButtonRelief.wordmarkText.count - 1)
        return PunchIntro.firstPunchAt
            + PunchIntro.interval * TimeInterval(gaps)
            + PunchIntro.settleDuration
            + PunchIntro.afterLastBeat
    }

    /// Le mot n’existe pas encore : chaque glyphe s’ouvre d’un coup (trou skin + lèvre), squash type atterrissage Brix.
    func playPunchIntro(onPunch: @escaping () -> Void) {
        guard let crop = childNode(withName: "blomixWordmarkWell") as? SKCropNode else { return }
        let layout = BlomixButtonRelief.cutoutLayout(text: text, fontSize: fontSize, pad: pad)
        let canvas = layout.canvas
        let slices = BlomixButtonRelief.cutoutGlyphSlices(text: text, fontSize: fontSize, pad: pad).slices
        guard !slices.isEmpty else { return }

        let maskRoot = SKNode()
        maskRoot.name = "blomixWordmarkPunchMask"
        var letterMasks: [SKSpriteNode] = []
        var letterRadii: [CGFloat] = []
        letterMasks.reserveCapacity(slices.count)
        letterRadii.reserveCapacity(slices.count)

        for (i, slice) in slices.enumerated() {
            let (maskImg, letterSize) = BlomixButtonRelief.cutoutLetterMaskImage(slice: slice)
            let skCenter = CGPoint(
                x: slice.bounds.midX - canvas.width / 2,
                y: canvas.height / 2 - slice.bounds.midY
            )
            let maskTex = SKTexture(image: maskImg)
            maskTex.filteringMode = .linear
            let letter = SKSpriteNode(texture: maskTex, size: letterSize)
            letter.name = "blomixWordmarkPunchLetter\(i)"
            letter.position = skCenter
            letter.xScale = 0.001
            letter.yScale = 0.001
            letter.isHidden = true
            maskRoot.addChild(letter)
            letterMasks.append(letter)
            letterRadii.append(min(letterSize.width, letterSize.height) / 2)
        }
        crop.maskNode = maskRoot

        func eased(_ action: SKAction, _ mode: SKActionTimingMode) -> SKAction {
            action.timingMode = mode
            return action
        }

        let palette = BlomixSkinCatalog.shared.bloxSKColors()
        let count = letterMasks.count

        for (i, letter) in letterMasks.enumerated() {
            let rest = letter.position
            let punchAt = PunchIntro.punchDelay(index: i, count: count)
            let sparkleColor = palette.isEmpty
                ? SKColor(white: 0.92, alpha: 1)
                : palette[i % palette.count]
            let sparkleRadius = letterRadii[i]
            let impact = SKAction.run { [weak self, weak letter] in
                guard let letter else { return }
                letter.isHidden = false
                letter.position = CGPoint(x: rest.x, y: rest.y - PunchIntro.impactDrop)
                letter.xScale = PunchIntro.impactScaleX
                letter.yScale = PunchIntro.impactScaleY
                onPunch()
                self?.spawnPunchSparkles(at: rest, radius: sparkleRadius, color: sparkleColor)
            }
            let settle = SKAction.group([
                eased(SKAction.scaleX(to: 1.0, duration: PunchIntro.settleDuration), .easeOut),
                eased(SKAction.scaleY(to: 1.0, duration: PunchIntro.settleDuration), .easeOut),
                eased(SKAction.move(to: rest, duration: PunchIntro.settleDuration), .easeOut),
            ])
            letter.run(.sequence([
                .wait(forDuration: punchAt),
                impact,
                settle,
            ]))
        }

        let lastPunchAt = PunchIntro.punchDelay(index: count - 1, count: count)
        let punchWindow = lastPunchAt + PunchIntro.settleDuration
        // SKCropNode ne suit pas les enfants du masque : on le ré-assigne chaque frame.
        crop.run(SKAction.customAction(withDuration: punchWindow) { node, _ in
            guard let crop = node as? SKCropNode else { return }
            let mask = crop.maskNode
            crop.maskNode = nil
            crop.maskNode = mask
        })
        run(.sequence([
            .wait(forDuration: punchWindow + 0.04),
            .run { [weak self, weak crop] in
                guard let self, let crop else { return }
                let maskTex = SKTexture(image: BlomixButtonRelief.cutoutMaskImage(
                    text: self.text,
                    fontSize: self.fontSize,
                    pad: self.pad
                ))
                maskTex.filteringMode = .linear
                crop.maskNode = SKSpriteNode(texture: maskTex, size: canvas)
            },
        ]))
    }

    /// Paillettes d’impact (version discrète de l’atterrissage blox), hors masque pour rester visibles.
    private func spawnPunchSparkles(at center: CGPoint, radius: CGFloat, color: SKColor) {
        let blockRadius = max(7, radius * 0.52)

        let ejectDuration: TimeInterval = 0.22
        for _ in 0..<14 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let startDist = CGFloat.random(in: (blockRadius - 2)...(blockRadius + 2))
            let endDist = startDist + CGFloat.random(in: 8...16)
            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.6...1.4))
            spark.fillColor = color
            spark.strokeColor = .clear
            spark.alpha = 0
            spark.zPosition = 6
            spark.position = CGPoint(
                x: center.x + cos(angle) * startDist,
                y: center.y + sin(angle) * startDist
            )
            addChild(spark)
            let move = SKAction.move(
                to: CGPoint(
                    x: center.x + cos(angle) * endDist,
                    y: center.y + sin(angle) * endDist
                ),
                duration: ejectDuration
            )
            move.timingMode = .easeOut
            spark.run(.sequence([
                .group([
                    move,
                    .sequence([
                        .fadeAlpha(to: 0.90, duration: 0.03),
                        .fadeAlpha(to: 0, duration: ejectDuration - 0.03),
                    ]),
                ]),
                .removeFromParent(),
            ]))
        }

        let cloudDuration: TimeInterval = 0.55
        for _ in 0..<32 {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let startDist = CGFloat.random(in: (blockRadius - 4)...(blockRadius + 3))
            let drift = CGFloat.random(in: 1...4)
            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.4...0.9))
            spark.fillColor = color
            spark.strokeColor = .clear
            spark.alpha = 0
            spark.zPosition = 5
            spark.position = CGPoint(
                x: center.x + cos(angle) * startDist,
                y: center.y + sin(angle) * startDist
            )
            addChild(spark)
            let move = SKAction.move(
                to: CGPoint(
                    x: center.x + cos(angle) * (startDist + drift),
                    y: center.y + sin(angle) * (startDist + drift) + CGFloat.random(in: 0...2)
                ),
                duration: cloudDuration
            )
            move.timingMode = .easeOut
            let peak = CGFloat.random(in: 0.55...0.90)
            spark.run(.sequence([
                .group([
                    move,
                    .sequence([
                        .fadeAlpha(to: peak, duration: 0.05),
                        .fadeAlpha(to: 0, duration: cloudDuration - 0.05),
                    ]),
                ]),
                .removeFromParent(),
            ]))
        }
    }
}

// MARK: - Titre trou UIKit (Réglages / Guide / Crédits / Score / Multijoueur)

/// Même matière que `BlomixCutoutWordmarkNode` : masque glyphe + dégradé skin + ombre interne.
@MainActor
final class BlomixCutoutTitleView: UIView {
    private var text: String
    private let fontSize: CGFloat
    private let pad: CGFloat
    private let gradient = BlomixSkinGradientLayer()
    private let lip = CALayer()
    private let maskLayer = CALayer()
    private var lastSize: CGSize = .zero

    init(text: String, fontSize: CGFloat, pad: CGFloat = 6) {
        self.text = text
        self.fontSize = fontSize
        self.pad = pad
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .header
        accessibilityLabel = text
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        gradient.actions = ["contents": NSNull()]
        layer.addSublayer(gradient)
        BlomixSkinGradientClock.shared.register(gradient)

        lip.contentsGravity = .resize
        lip.actions = ["contents": NSNull()]
        layer.addSublayer(lip)

        maskLayer.contentsGravity = .resize
        maskLayer.actions = ["contents": NSNull()]
        layer.mask = maskLayer

        _ = NotificationCenter.default.addObserver(
            forName: .blomixAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastSize = .zero
                self?.setNeedsLayout()
            }
        }
        _ = NotificationCenter.default.addObserver(
            forName: .blomixSkinDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastSize = .zero
                self?.setNeedsLayout()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var intrinsicContentSize: CGSize {
        BlomixButtonRelief.cutoutLayout(text: text, fontSize: fontSize, pad: pad).canvas
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        gradient.frame = bounds
        lip.frame = bounds
        maskLayer.frame = bounds
        let key = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard key != lastSize, size.width > 1, size.height > 1 else { return }
        lastSize = key
        maskLayer.contents = BlomixButtonRelief.cutoutMaskImage(
            text: text,
            fontSize: fontSize,
            pad: pad
        ).cgImage
        lip.contents = BlomixButtonRelief.cutoutInnerShadowImage(
            text: text,
            fontSize: fontSize,
            pad: pad
        ).cgImage
    }
}

// MARK: - Horloge UIKit (bitmap partagé)

@MainActor
final class BlomixSkinGradientClock: NSObject {
    static let shared = BlomixSkinGradientClock()

    private(set) var time: CGFloat = 0
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private let layers = NSHashTable<BlomixSkinGradientLayer>.weakObjects()
    private var cachedImage: CGImage?
    private var lastPaletteSignature: String = ""

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .blomixSkinDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                BlomixSkinGradient.invalidateShaderCache()
                self?.cachedImage = nil
                self?.lastPaletteSignature = ""
                self?.publish()
            }
        }
    }

    func register(_ layer: BlomixSkinGradientLayer) {
        layers.add(layer)
        startIfNeeded()
        if let img = currentImage() {
            layer.contents = img
        }
    }

    func unregister(_ layer: BlomixSkinGradientLayer) {
        layers.remove(layer)
        if layers.count == 0 {
            link?.invalidate()
            link = nil
            lastTimestamp = 0
        }
    }

    private func startIfNeeded() {
        guard link == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(tick(_:)))
        dl.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
        dl.add(to: .main, forMode: .common)
        link = dl
    }

    @objc private func tick(_ dl: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = dl.timestamp }
        let dt = dl.timestamp - lastTimestamp
        lastTimestamp = dl.timestamp
        time += CGFloat(dt)
        if layers.count == 0 {
            link?.invalidate()
            link = nil
            lastTimestamp = 0
            return
        }
        cachedImage = nil
        publish()
    }

    private func paletteSignature() -> String {
        BlomixSkinCatalog.shared.selectedSkinId + ":" +
            BlomixSkinGradient.paletteUIColors().map { c in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getRed(&r, green: &g, blue: &b, alpha: &a)
                return String(format: "%.3f%.3f%.3f", r, g, b)
            }.joined()
    }

    func currentImage() -> CGImage? {
        let sig = paletteSignature()
        if let cachedImage, sig == lastPaletteSignature { return cachedImage }
        lastPaletteSignature = sig
        let img = renderImage(time: time)
        cachedImage = img
        return img
    }

    private func publish() {
        guard let img = currentImage() else { return }
        for case let layer as BlomixSkinGradientLayer in layers.allObjects {
            layer.contents = img
        }
    }

    private func renderImage(time t: CGFloat) -> CGImage? {
        let pw = 48
        let ph = 48
        let scale: CGFloat = 1
        let colors = BlomixSkinGradient.paletteUIColors()
        let rgb: [(CGFloat, CGFloat, CGFloat)] = colors.map { c in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }
        let n = max(rgb.count, 1)
        let timeScale = CGFloat(BlomixSkinGradient.wellTimeScale)

        func pal(_ tRaw: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            let ti = (tRaw - floor(tRaw)) * CGFloat(n)
            let fi = floor(ti)
            let frac = ti - fi
            let f = frac * frac * (3 - 2 * frac)
            let i = Int(fi) % n
            let j = (i + 1) % n
            let a = rgb[i], b = rgb[j]
            return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
        }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pw, height: ph), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let tt = t * timeScale
            let c1 = pal(tt)
            let c2 = pal(tt + 0.333)
            let c3 = pal(tt + 0.667)
            for y in 0..<ph {
                let v = (CGFloat(y) + 0.5) / CGFloat(ph)
                for x in 0..<pw {
                    let u = (CGFloat(x) + 0.5) / CGFloat(pw)
                    let wx = sin(u * .pi + tt * 0.5) * 0.5 + 0.5
                    let wy = cos(v * 2.2 - tt * 0.35) * 0.5 + 0.5
                    var r = c1.0 + (c2.0 - c1.0) * wx
                    var g = c1.1 + (c2.1 - c1.1) * wx
                    var b = c1.2 + (c2.2 - c1.2) * wx
                    r += (c3.0 - r) * wy * 0.38
                    g += (c3.1 - g) * wy * 0.38
                    b += (c3.2 - b) * wy * 0.38
                    cg.setFillColor(red: r, green: g, blue: b, alpha: 1)
                    cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return image.cgImage
    }
}

// MARK: - Layer UIKit

final class BlomixSkinGradientLayer: CALayer {
    override init() {
        super.init()
        contentsGravity = .resize
        actions = ["contents": NSNull()]
    }

    override init(layer: Any) {
        super.init(layer: layer)
        contentsGravity = .resize
        actions = ["contents": NSNull()]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

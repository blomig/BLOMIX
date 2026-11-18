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
//  Grille New : une texture par groupe de Blox de même couleur (8-connexité),
//  sauf une case seule : son tampon d'adresse, pas le tampon « 0_0 » partagé.
//  L'orthogonal est une seule pièce (coins extérieurs et intérieurs arrondis).
//  Une diagonale déjà dans cette pièce n'est pas redessinée. Une diagonale seule
//  est le tronçon du trait Classique qui reste entre les deux blox (sqrt(32)),
//  pas le trait centre à centre. Pas un disque au coin.
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

    /// Graine d’une case. Une pièce somme celles de ses cases.
    /// Sur la grille 8×8, chaque adresse a un sel distinct, toujours ≥ 1.
    /// Le sel 0 est le tampon partagé de la file, de l’aperçu et des Brix.
    static func cellPigmentSalt(row: Int, col: Int) -> Int {
        // +1 : la case (0, 0) ne reprend pas le tampon partagé de la file (sel 0).
        (row &* 17 &+ col) &+ 1
    }

    /// Masque d’adresse. Le motif ne dépend que du sel. La teinte est `sprite.color`,
    /// donc un jeu de 64 masques sert toutes les couleurs, sans repeindre en partie.
    private static let addressStampNeutral = SKColor(white: 0.55, alpha: 1)

    /// Même matière sur un sprite déjà en place (file, aperçu, mue). Retire un vieux reflet.
    /// `salt` 0 : un masque par couleur (file, aperçu, Brix). Une case de grille passe son adresse.
    @MainActor
    static func applyJelly(to sprite: SKSpriteNode, fill: SKColor, pointSize: CGSize, salt: Int = 0) {
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
            light: light,
            salt: salt
        )
        let texture = cache.jellyTexture(for: key) {
            bakeJellyMask(
                pointSize: pointSize,
                scale: scale,
                red: CGFloat(channels.r) / 255,
                green: CGFloat(channels.g) / 255,
                blue: CGFloat(channels.b) / 255,
                light: light,
                salt: salt
            )
        }

        // La texture @3x fait ~3 cases si on la pose pendant un scale.
        // On fige l’échelle, on impose la taille de la case, puis on rend l’échelle.
        let scaleX = sprite.xScale
        let scaleY = sprite.yScale
        sprite.xScale = 1
        sprite.yScale = 1
        sprite.texture = texture
        sprite.size = pointSize
        sprite.xScale = scaleX
        sprite.yScale = scaleY
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.color = fill
        sprite.colorBlendFactor = 1
    }

    /// Nom de l'enfant-reflet. N'est pas un chiffre Priks ni un halo Magix.
    static let specularNodeName = "blomixNewSpecular"

    /// Vide les textures UIGraphics. Après un passage en arrière-plan, SpriteKit
    /// ne réuploade pas ces masques : le rectangle de la pièce redevient opaque.
    @MainActor
    static func discardCachedTextures() {
        cache.discardAll()
    }

    // MARK: - Cache

    private struct CacheKey: Hashable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
        var pixelWidth: Int
        var pixelHeight: Int
        var light: Bool
        /// 0 pour la file et l’aperçu. L’adresse de la case pour un blox séparé.
        var salt: Int
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
        private var generation: UInt64 = 0
        private var jellies: [CacheKey: SKTexture] = [:]
        private var junctions: [JunctionKey: SKTexture] = [:]
        private var fusions: [FusionKey: SKTexture] = [:]
        private var fusionWaiters: [FusionKey: [() -> Void]] = [:]
        private var jellyWaiters: [CacheKey: [() -> Void]] = [:]

        func discardAll() {
            lock.lock()
            generation &+= 1
            jellies.removeAll()
            junctions.removeAll()
            fusions.removeAll()
            fusionWaiters.removeAll()
            jellyWaiters.removeAll()
            lock.unlock()
        }

        func jellyTextureIfPresent(_ key: CacheKey) -> SKTexture? {
            lock.lock()
            defer { lock.unlock() }
            return jellies[key]
        }

        /// `nil` si le lavis est déjà en cache ou déjà en peinture (le waiter est alors noté).
        func claimJellyBake(_ key: CacheKey, waiter: @escaping () -> Void) -> UInt64? {
            lock.lock()
            defer { lock.unlock() }
            if jellies[key] != nil {
                return nil
            }
            if jellyWaiters[key] != nil {
                jellyWaiters[key]?.append(waiter)
                return nil
            }
            jellyWaiters[key] = [waiter]
            return generation
        }

        func finishJellyBake(_ key: CacheKey, texture: SKTexture, token: UInt64) -> [() -> Void] {
            lock.lock()
            defer { lock.unlock() }
            guard token == generation else { return [] }
            if jellies[key] == nil {
                jellies[key] = texture
            }
            return jellyWaiters.removeValue(forKey: key) ?? []
        }

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

        func fusionTextureIfPresent(_ key: FusionKey) -> SKTexture? {
            lock.lock()
            defer { lock.unlock() }
            return fusions[key]
        }

        /// Jeton de génération si cet appel peint. `nil` si la pièce est déjà en cache
        /// ou si une peinture est déjà en cours (le waiter est alors enregistré).
        func claimFusionBake(_ key: FusionKey, waiter: @escaping () -> Void) -> UInt64? {
            lock.lock()
            defer { lock.unlock() }
            if fusions[key] != nil {
                return nil
            }
            if fusionWaiters[key] != nil {
                fusionWaiters[key]?.append(waiter)
                return nil
            }
            fusionWaiters[key] = [waiter]
            return generation
        }

        /// Ignore une peinture lancée avant `discardAll` : sa texture GPU est morte,
        /// et ses waiters ne sont plus ceux de la pièce en cours.
        func finishFusionBake(_ key: FusionKey, texture: SKTexture, token: UInt64) -> [() -> Void] {
            lock.lock()
            defer { lock.unlock() }
            guard token == generation else { return [] }
            if fusions[key] == nil {
                fusions[key] = texture
            }
            return fusionWaiters.removeValue(forKey: key) ?? []
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

    /// Les 64 tampons d’adresse, deux par deux. Le fil du jeu ne peint pas.
    /// Vide pendant la partie : tout est déjà en cache avant la première chaîne.
    private static let cellWashQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "blomix.ink.cellwash"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    /// Peint un masque par adresse, une fois. Les couleurs ne font que le teindre.
    /// Un second appel ne repeint pas ce qui est déjà en cache ou en cours.
    @MainActor
    static func prepareAddressStamps(rows: Int, columns: Int, pointSize: CGSize) {
        guard rows > 0, columns > 0, pointSize.width > 1, pointSize.height > 1 else { return }
        for row in 0..<rows {
            for col in 0..<columns {
                let key = addressStampKey(pointSize: pointSize, row: row, col: col)
                if cache.jellyTextureIfPresent(key) != nil { continue }
                let token = cache.claimJellyBake(key) {}
                if cache.jellyTextureIfPresent(key) != nil { continue }
                guard let token else { continue }
                enqueueCellWash(
                    key: key,
                    fill: addressStampNeutral,
                    pointSize: pointSize,
                    salt: cellPigmentSalt(row: row, col: col),
                    token: token,
                    soon: true
                )
            }
        }
    }

    /// Pose le tampon de cette adresse s’il est prêt. Sinon il est déjà en peinture
    /// (ou lancé ici), et il arrive sans bloquer. `true` si la texture est en place.
    /// `fill` est la teinte du skin, pas la graine du masque.
    @MainActor
    @discardableResult
    static func applyAddressStampWhenReady(
        to sprite: SKSpriteNode,
        fill: SKColor,
        pointSize: CGSize,
        row: Int,
        col: Int,
        onReady: (@MainActor () -> Void)? = nil
    ) -> Bool {
        guard pointSize.width > 1, pointSize.height > 1 else { return false }
        let key = addressStampKey(pointSize: pointSize, row: row, col: col)
        if let texture = cache.jellyTextureIfPresent(key) {
            assignAddressStamp(sprite, texture: texture, fill: fill, pointSize: pointSize)
            return true
        }
        let token = cache.claimJellyBake(key) { [weak sprite] in
            guard let texture = cache.jellyTextureIfPresent(key) else { return }
            if let sprite, sprite.parent != nil {
                assignAddressStamp(sprite, texture: texture, fill: fill, pointSize: pointSize)
            }
            onReady?()
        }
        if let texture = cache.jellyTextureIfPresent(key) {
            assignAddressStamp(sprite, texture: texture, fill: fill, pointSize: pointSize)
            return true
        }
        guard let token else { return false }
        enqueueCellWash(
            key: key,
            fill: addressStampNeutral,
            pointSize: pointSize,
            salt: cellPigmentSalt(row: row, col: col),
            token: token,
            soon: true
        )
        return false
    }

    /// Tampon d’adresse déjà peint, sans le poser.
    @MainActor
    static func cachedAddressStamp(pointSize: CGSize, row: Int, col: Int) -> SKTexture? {
        guard pointSize.width > 1, pointSize.height > 1 else { return nil }
        return cache.jellyTextureIfPresent(addressStampKey(pointSize: pointSize, row: row, col: col))
    }

    @MainActor
    private static func addressStampKey(pointSize: CGSize, row: Int, col: Int) -> CacheKey {
        jellyCacheKey(
            fill: addressStampNeutral,
            pointSize: pointSize,
            salt: cellPigmentSalt(row: row, col: col)
        )
    }

    @MainActor
    private static func jellyCacheKey(fill: SKColor, pointSize: CGSize, salt: Int) -> CacheKey {
        let channels = rgba(of: fill)
        let scale = max(1, UITraitCollection.current.displayScale)
        return CacheKey(
            r: channels.r,
            g: channels.g,
            b: channels.b,
            a: channels.a,
            pixelWidth: max(1, Int((pointSize.width * scale).rounded())),
            pixelHeight: max(1, Int((pointSize.height * scale).rounded())),
            light: BlomixAppearance.isLight,
            salt: salt
        )
    }

    @MainActor
    private static func enqueueCellWash(
        key: CacheKey,
        fill: SKColor,
        pointSize: CGSize,
        salt: Int,
        token: UInt64,
        soon: Bool
    ) {
        let channels = rgba(of: fill)
        let scale = max(1, UITraitCollection.current.displayScale)
        let red = CGFloat(channels.r) / 255
        let green = CGFloat(channels.g) / 255
        let blue = CGFloat(channels.b) / 255
        let light = BlomixAppearance.isLight
        let operation = BlockOperation {
            let image = renderJellyImage(
                pointSize: pointSize,
                scale: scale,
                red: red,
                green: green,
                blue: blue,
                light: light,
                salt: salt
            )
            let box = ImageBox(image)
            DispatchQueue.main.async {
                let texture = SKTexture(image: box.image)
                texture.filteringMode = .linear
                let waiters = cache.finishJellyBake(key, texture: texture, token: token)
                for waiter in waiters {
                    waiter()
                }
            }
        }
        operation.queuePriority = soon ? .veryHigh : .normal
        cellWashQueue.addOperation(operation)
    }

    @MainActor
    private static func assignAddressStamp(
        _ sprite: SKSpriteNode,
        texture: SKTexture,
        fill: SKColor,
        pointSize: CGSize
    ) {
        // Déjà ce tampon, à la taille de la case : ne pas toucher au scale du geste.
        if sprite.texture === texture,
           abs(sprite.size.width - pointSize.width) < 0.5,
           abs(sprite.size.height - pointSize.height) < 0.5 {
            sprite.color = fill
            sprite.colorBlendFactor = 1
            return
        }
        // La texture @3x fait ~3 cases si on la pose pendant un scale.
        let scaleX = sprite.xScale
        let scaleY = sprite.yScale
        sprite.xScale = 1
        sprite.yScale = 1
        sprite.texture = texture
        sprite.size = pointSize
        sprite.xScale = scaleX
        sprite.yScale = scaleY
        sprite.color = fill
        sprite.colorBlendFactor = 1
    }

    private static func bakeJellyMask(
        pointSize: CGSize,
        scale: CGFloat,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        light: Bool,
        salt: Int
    ) -> SKTexture {
        let image = renderJellyImage(
            pointSize: pointSize,
            scale: scale,
            red: red,
            green: green,
            blue: blue,
            light: light,
            salt: salt
        )
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func renderJellyImage(
        pointSize: CGSize,
        scale: CGFloat,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        light: Bool,
        salt: Int
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let edge = edgeMultiplier(red: red, green: green, blue: blue, light: light)
        return renderer.image { context in
            drawJellyMask(
                in: context.cgContext,
                pointSize: pointSize,
                edge: edge,
                red: red,
                green: green,
                blue: blue,
                salt: salt
            )
        }
    }

    private static func drawJellyMask(
        in ctx: CGContext,
        pointSize: CGSize,
        edge: CGFloat,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        salt: Int
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
            seed: BlomixNewInkRenderer.seed(red: red, green: green, blue: blue, salt: salt),
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

    struct FusionRC: Hashable, Sendable {
        var row: Int
        var col: Int
    }

    /// Tout ce qu'il faut pour peindre hors du fil du jeu. Pas de nœud SpriteKit.
    private struct FusionBakeJob: Sendable {
        var cells: [FusionRC]
        var minRow: Int
        var minCol: Int
        var width: CGFloat
        var height: CGFloat
        var cellPitch: CGFloat
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var light: Bool
        var displayScale: CGFloat
    }

    private struct FusionPlan {
        var key: FusionKey
        var job: FusionBakeJob
        var size: CGSize
        var center: CGPoint
        var fill: SKColor
    }

    private final class ImageBox: @unchecked Sendable {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
    }

    /// Marge autour du groupe pour l'ombre. Le corps, lui, s'arrête à 1 pt du bord de case.
    private static let fusionPad: CGFloat = 10
    private static let fusionInset: CGFloat = 1
    private static let fusionCornerRadius: CGFloat = 4.6
    /// Demi-largeur du trait diagonal Classique (`lineWidth = sqrt(32)`).
    private static let fusionDiagonalHalfWidth: CGFloat = 2.82842712475

    /// Pièce déjà en cache. `nil` si elle n'est pas peinte : l'appelant laisse les cases
    /// visibles et lance `preloadFusion`. Le fil du jeu ne peint pas.
    @MainActor
    static func makeCachedFusionSprite(
        cells: [(row: Int, col: Int)],
        fill: SKColor,
        cellPitch: CGFloat,
        cellCenter: (Int, Int) -> CGPoint
    ) -> SKSpriteNode? {
        guard let plan = fusionPlan(cells: cells, fill: fill, cellPitch: cellPitch, cellCenter: cellCenter),
              let texture = cache.fusionTextureIfPresent(plan.key) else { return nil }
        return fusionSprite(plan: plan, texture: texture)
    }

    /// Peint la pièce hors du fil du jeu. `completion` est sur le fil principal,
    /// une fois la texture en cache. Plusieurs demandes de la même pièce n'en peignent qu'une.
    @MainActor
    static func preloadFusion(
        cells: [(row: Int, col: Int)],
        fill: SKColor,
        cellPitch: CGFloat,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let plan = fusionPlan(
            cells: cells,
            fill: fill,
            cellPitch: cellPitch,
            cellCenter: { _, _ in .zero }
        ) else {
            DispatchQueue.main.async { completion() }
            return
        }
        if cache.fusionTextureIfPresent(plan.key) != nil {
            DispatchQueue.main.async { completion() }
            return
        }
        let job = plan.job
        let key = plan.key
        let token = cache.claimFusionBake(key) { completion() }
        if token == nil, cache.fusionTextureIfPresent(key) != nil {
            DispatchQueue.main.async { completion() }
            return
        }
        guard let token else { return }
        DispatchQueue.global(qos: .userInteractive).async {
            let box = ImageBox(renderFusionImage(job))
            DispatchQueue.main.async {
                let texture = SKTexture(image: box.image)
                texture.filteringMode = .linear
                let waiters = cache.finishFusionBake(key, texture: texture, token: token)
                for waiter in waiters {
                    waiter()
                }
            }
        }
    }

    @MainActor
    private static func fusionPlan(
        cells: [(row: Int, col: Int)],
        fill: SKColor,
        cellPitch: CGFloat,
        cellCenter: (Int, Int) -> CGPoint
    ) -> FusionPlan? {
        let points = cells.map { FusionRC(row: $0.row, col: $0.col) }
        guard let minR = points.map(\.row).min(),
              let maxR = points.map(\.row).max(),
              let minC = points.map(\.col).min(),
              let maxC = points.map(\.col).max(),
              cellPitch > 1 else { return nil }
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
        let job = FusionBakeJob(
            cells: points,
            minRow: minR,
            minCol: minC,
            width: size.width,
            height: size.height,
            cellPitch: cellPitch,
            red: CGFloat(channels.r) / 255,
            green: CGFloat(channels.g) / 255,
            blue: CGFloat(channels.b) / 255,
            light: light,
            displayScale: scale
        )
        return FusionPlan(key: key, job: job, size: size, center: center, fill: fill)
    }

    @MainActor
    private static func fusionSprite(plan: FusionPlan, texture: SKTexture) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: texture, size: plan.size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.position = plan.center
        sprite.color = plan.fill
        sprite.colorBlendFactor = 1
        return sprite
    }

    /// Plafond de pixels du lavis. Au-delà, on baisse l'échelle : la pièce reste
    /// lisible (filtre linéaire) et la peinture ne dure pas un temps de chaîne.
    private static func fusionRasterScale(pointSize: CGSize, displayScale: CGFloat) -> CGFloat {
        let display = max(1, displayScale)
        let area = max(1, pointSize.width * pointSize.height)
        let budget: CGFloat = 64_000
        let full = area * display * display
        guard full > budget else { return display }
        return max(0.75, display * sqrt(budget / full))
    }

    private static func renderFusionImage(_ job: FusionBakeJob) -> UIImage {
        let pointSize = CGSize(width: job.width, height: job.height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = fusionRasterScale(pointSize: pointSize, displayScale: job.displayScale)
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let edge = edgeMultiplier(red: job.red, green: job.green, blue: job.blue, light: job.light)
        let cells = Set(job.cells)
        let silhouette = fusionSilhouette(cells: cells, minRow: job.minRow, minCol: job.minCol, cellPitch: job.cellPitch)
        let salt = job.cells.reduce(0) { $0 &+ cellPigmentSalt(row: $1.row, col: $1.col) }
        return renderer.image { context in
            BlomixNewInkRenderer.drawMask(
                in: context.cgContext,
                paths: silhouette.bodies + silhouette.bridges,
                seed: BlomixNewInkRenderer.seed(red: job.red, green: job.green, blue: job.blue, salt: salt),
                canvas: pointSize,
                rim: edge,
                bodyPaths: silhouette.bodies,
                bridgePaths: silhouette.bridges
            )
        }
    }

    struct FusionSilhouette {
        var bodies: [CGPath]
        var bridges: [CGPath]
    }

    /// Cases arrondies, plus le tronçon de diagonale qui reste entre deux pièces
    /// distinctes. Même largeur que le trait Classique, coupé au bord des blox.
    /// L'ensemble est une seule silhouette. Le lavis des cases ne dépend pas du pont.
    static func fusionSilhouette(
        cells: Set<FusionRC>,
        minRow: Int,
        minCol: Int,
        cellPitch: CGFloat
    ) -> FusionSilhouette {
        var bodies: [CGPath] = []
        var bridges: [CGPath] = []
        for loop in orthogonalLoops(cells: cells, minRow: minRow, minCol: minCol, cellPitch: cellPitch) where loop.count >= 3 {
            bodies.append(roundedOrthogonalPath(loop))
        }
        if bodies.isEmpty {
            for cell in cells {
                let rect = CGRect(
                    x: fusionPad + CGFloat(cell.col - minCol) * cellPitch + fusionInset,
                    y: fusionPad + CGFloat(cell.row - minRow) * cellPitch + fusionInset,
                    width: cellPitch - 2 * fusionInset,
                    height: cellPitch - 2 * fusionInset
                )
                bodies.append(CGPath(roundedRect: rect, cornerWidth: fusionCornerRadius, cornerHeight: fusionCornerRadius, transform: nil))
            }
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
                if let gap = diagonalBetweenPath(from: a, to: b, halfWidth: fusionDiagonalHalfWidth, bodies: bodies) {
                    bridges.append(gap)
                }
            }
        }
        return FusionSilhouette(bodies: bodies, bridges: bridges)
    }

    /// Tronçon du trait diagonal qui n'est pas sous un blox. Les bouts s'arrêtent
    /// au contour. Un léger recouvrement évite un filet de papier au raccord.
    private static func diagonalBetweenPath(
        from a: CGPoint,
        to b: CGPoint,
        halfWidth: CGFloat,
        bodies: [CGPath]
    ) -> CGPath? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return nil }
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + dx * t, y: a.y + dy * t)
        }
        func inside(_ t: CGFloat) -> Bool {
            let p = point(t)
            return bodies.contains { $0.contains(p) }
        }
        guard inside(0), inside(1) else {
            return diagonalBarPath(from: a, to: b, halfWidth: halfWidth)
        }
        // Déjà reliées par le contour orthogonal : rien entre les deux.
        guard !inside(0.5) else { return nil }
        func crossing(from low: CGFloat, to high: CGFloat, insideAtLow: Bool) -> CGFloat {
            var lo = low
            var hi = high
            for _ in 0..<18 {
                let mid = (lo + hi) / 2
                if inside(mid) == insideAtLow { lo = mid } else { hi = mid }
            }
            return (lo + hi) / 2
        }
        let leave = crossing(from: 0, to: 0.5, insideAtLow: true)
        let enter = crossing(from: 0.5, to: 1, insideAtLow: false)
        let overlap = 1.2 / length
        let t0 = max(0, leave - overlap)
        let t1 = min(1, enter + overlap)
        guard t1 - t0 > 0.5 / length else { return nil }
        return flatBarPath(from: point(t0), to: point(t1), halfWidth: halfWidth)
    }

    /// Même sens de parcours que la capsule : le remplissage ajoute le joint.
    private static func flatBarPath(from a: CGPoint, to b: CGPoint, halfWidth: CGFloat) -> CGPath {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.01 else {
            return CGPath(
                ellipseIn: CGRect(x: a.x - halfWidth, y: a.y - halfWidth, width: halfWidth * 2, height: halfWidth * 2),
                transform: nil
            )
        }
        let px = -dy / length * halfWidth
        let py = dx / length * halfWidth
        let path = CGMutablePath()
        path.move(to: CGPoint(x: a.x - px, y: a.y - py))
        path.addLine(to: CGPoint(x: b.x - px, y: b.y - py))
        path.addLine(to: CGPoint(x: b.x + px, y: b.y + py))
        path.addLine(to: CGPoint(x: a.x + px, y: a.y + py))
        path.closeSubpath()
        return path
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

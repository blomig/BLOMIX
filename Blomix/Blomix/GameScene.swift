//
//  GameScene.swift
//  Blomix
//
//  Scène SpriteKit principale. Le gameplay sera porté depuis `old_web_code`
//  (voir PROJECT_CONTEXT.md).
//  Textures PNG : catalogue `Assets.xcassets` → groupe « WebImages » (bombe, écrans, etc.).
//  Blox couleur + Priks : carrés **générés** (SKSpriteNode couleur unie), mêmes hexa que les jonctions (+ teinte Priks).
//  Sons : ressources « Sounds » du projet, copiées à la racine du bundle (`begin.wav`, `empty_coll.wav`, `.aiff`, …) ; police `BitcountGridSingleInk-Variable.ttf` via UIAppFonts.
//

import AVFoundation
import GameKit
import SpriteKit
import UIKit

// MARK: - Réglages jeu (skins + volume) — contenu regroupé ici pour garantir la compilation cible

extension Notification.Name {
    /// Publié quand l’utilisateur choisit un autre skin (`BlomixSkinCatalog.shared.selectedSkinId`).
    static let blomixSkinDidChange = Notification.Name("blomixSkinDidChange")
    /// Publié une fois l’UI de partie prête après **START** (tutoriel UIKit dans `GameViewController`).
    static let blomixDidBeginGameplayMatch = Notification.Name("blomixDidBeginGameplayMatch")
    /// Publié quand les grilles PvP sont prêtes et que le modal de préparation peut se fermer.
    static let blomixPvPBoardsReady = Notification.Name("blomixPvPBoardsReady")
    /// Publié si la préparation PvP échoue avant l’entrée en partie.
    static let blomixPvPPreparationFailed = Notification.Name("blomixPvPPreparationFailed")
    /// Publié quand le joueur distant passe à l’état `.connected` (GKMatch relay établi).
    /// L’objet `object` est le `GKPlayer` connecté.
    static let blomixPvPOpponentConnected = Notification.Name("blomixPvPOpponentConnected")
    /// Publié quand une invitation sortante (vers un joueur récent) démarre ou se termine.
    /// `userInfo["active"]` : `true` = en cours, `false` = terminée.
    static let blomixPvPOutgoingInviteStateChanged = Notification.Name("blomixPvPOutgoingInviteStateChanged")
    /// Publié quand `BlomixAvailablePlayersManager.shared.isAvailableForChallenge` change.
    static let blomixAvailabilityChanged = Notification.Name("blomixAvailabilityChanged")
    /// Publié après le premier save CloudKit (userInfo: success: Bool, message: String).
    static let blomixAvailabilityPublishResult = Notification.Name("blomixAvailabilityPublishResult")
    /// Publié quand un défi entrant est détecté dans CloudKit (polling global).
    /// userInfo: challengerGamePlayerID, challengerDisplayName, matchPlayerGroup.
    static let blomixIncomingChallengeDetected = Notification.Name("blomixIncomingChallengeDetected")
}

/// Gain appliqué à chaque `AVAudioPlayer` des bruitages de partie (le volume système reste celui de l’appareil).
/// Accès effectif depuis le main thread (SpriteKit / UI) ; `@unchecked Sendable` pour le singleton Swift 6.
final class BlomixMatchAudioSettings: @unchecked Sendable {
    static let shared = BlomixMatchAudioSettings()
    private let userDefaultsKey      = "BlomixMasterVolume"
    private let musicUserDefaultsKey = "BlomixMasterMusicVolume"
    private init() {}

    /// Volume maître des effets sonores (SFX + sons procéduraux).
    var masterVolume: Float {
        get {
            if UserDefaults.standard.object(forKey: userDefaultsKey) == nil { return 1.0 }
            return min(1, max(0, UserDefaults.standard.float(forKey: userDefaultsKey)))
        }
        set { UserDefaults.standard.set(min(1, max(0, newValue)), forKey: userDefaultsKey) }
    }

    /// Volume maître de la musique d'ambiance (indépendant des SFX).
    var masterMusicVolume: Float {
        get {
            if UserDefaults.standard.object(forKey: musicUserDefaultsKey) == nil { return 0.5 }
            return min(1, max(0, UserDefaults.standard.float(forKey: musicUserDefaultsKey)))
        }
        set { UserDefaults.standard.set(min(1, max(0, newValue)), forKey: musicUserDefaultsKey) }
    }
}

private struct BlomixColorSkinsFile: Decodable {
    let skins: [BlomixSkinDefinition]
}

struct BlomixSkinDefinition: Decodable, Sendable {
    let id: String
    let displayName: String
    let blox: [String: String]
    let priks: String
    let prikstext: String?
}

/// Slot éditable du skin **Perso** (pastille → `UIColorPickerViewController`).
enum BlomixPersoColorSlot: String, CaseIterable {
    case red, blue, green, yellow, purple, orange
    case priks
    case prikstext

    static var displayOrdered: [BlomixPersoColorSlot] {
        ["red", "blue", "green", "yellow", "purple", "orange"].compactMap { BlomixPersoColorSlot(rawValue: $0) } + [.priks, .prikstext]
    }

    var storageKey: String { rawValue }

    var userDefaultsHexKey: String { "BlomixPersoSkin_hex_\(storageKey)" }
}

/// Catalogue skins + `UserDefaults` ; usage jeu sur le main thread. `@unchecked Sendable` pour `shared` (Swift 6).
final class BlomixSkinCatalog: @unchecked Sendable {
    static let shared = BlomixSkinCatalog()

    /// Skin personnalisable (couleurs en `UserDefaults`).
    static let persoSkinId  = "perso"
    static let persoSkin2Id = "perso2"
    /// Skin aléatoire (régénérable par le joueur via le bouton ↺).
    static let aleaSkinId   = "alea"

    private let selectedIdKey = "BlomixSelectedSkinId"
    private let resourceName = "color_skins"
    private var skins: [BlomixSkinDefinition] = []
    private var skinById: [String: BlomixSkinDefinition] = [:]

    private init() { reloadFromBundle() }

    static let bloxDisplayOrder = ["red", "blue", "green", "yellow", "purple", "orange"]

    func reloadFromBundle() {
        let fallback = Self.builtinDefaultSkin
        let persoIds: Set<String> = [Self.persoSkinId, Self.persoSkin2Id, Self.aleaSkinId]
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(BlomixColorSkinsFile.self, from: data),
           !decoded.skins.isEmpty {
            skins = decoded.skins.filter { !persoIds.contains($0.id) }
        } else {
            skins = [fallback].filter { !persoIds.contains($0.id) }
        }
        appendOrRefreshPersoSkins()
        if skinById[selectedSkinId] == nil {
            UserDefaults.standard.set(skins.first?.id ?? "default", forKey: selectedIdKey)
        }
    }

    /// Après choix dans `UIColorPickerViewController` : enregistre le hex, rafraîchit les skins Perso en mémoire, notifie la scène.
    /// `skinId` : `persoSkinId` (Perso) ou `persoSkin2Id` (Perso 2).
    func applyPersoColorSave(hex raw: String, slot: BlomixPersoColorSlot, skinId: String = "perso") {
        guard let norm = Self.normalizeHexForStorage(raw) else { return }
        UserDefaults.standard.set(norm, forKey: Self.udPersoHexKey(slot.storageKey, skinId: skinId))
        appendOrRefreshPersoSkins()
        NotificationCenter.default.post(name: .blomixSkinDidChange, object: nil)
    }

    /// Couleur actuelle d'un slot pour le skin perso désigné par `skinId`.
    func uiColorForPersoSlot(_ slot: BlomixPersoColorSlot, skinId: String = "perso") -> UIColor {
        let h = Self.readPersoHexStatic(bloxKey: slot.storageKey, skinId: skinId)
        return (Self.skColorFromHexString(h) as UIColor?) ?? .white
    }

    /// Reconstruit (ou crée) les skins perso + alea depuis UserDefaults et les place en fin de liste.
    private func appendOrRefreshPersoSkins() {
        for id in [Self.persoSkinId, Self.persoSkin2Id, Self.aleaSkinId] {
            skins.removeAll { $0.id == id }
            if id == Self.aleaSkinId { Self.ensureAleaColorsExistInDefaults() }
            skins.append(Self.makePersoSkinDefinitionFromDefaults(skinId: id))
        }
        skinById = Dictionary(uniqueKeysWithValues: skins.map { ($0.id, $0) })
    }

    // MARK: - Alea : génération aléatoire de couleurs

    /// Convertit HSL (0…1, 0…1, 0…1) en `#RRGGBB`.
    private static func hslToHex(h: Double, s: Double, l: Double) -> String {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(h * 6) % 6 {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return String(format: "#%02X%02X%02X",
                      Int(((r1 + m) * 255).rounded()),
                      Int(((g1 + m) * 255).rounded()),
                      Int(((b1 + m) * 255).rounded()))
    }

    /// Écrit un set de couleurs aléatoires en UserDefaults pour le skin Alea (sans notifier).
    private static func writeRandomAleaColorsToDefaults() {
        // 6 couleurs de blox : cercle chromatique en 6 secteurs de 60° + jitter ±20°.
        let baseHue = Double.random(in: 0..<360)
        for (i, key) in bloxDisplayOrder.enumerated() {
            var rawHue = baseHue + Double(i) * 60.0 + Double.random(in: -20...20)
            rawHue = (rawHue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            let hue = rawHue / 360.0
            let sat   = Double.random(in: 0.55...0.90)
            let light = Double.random(in: 0.42...0.62)
            UserDefaults.standard.set(hslToHex(h: hue, s: sat, l: light),
                                      forKey: udPersoHexKey(key, skinId: aleaSkinId))
        }
        // Brix fond : tirage indépendant.
        let priksH = Double.random(in: 0..<1)
        let priksS = Double.random(in: 0.30...0.60)
        let priksL = Double.random(in: 0.28...0.52)
        UserDefaults.standard.set(hslToHex(h: priksH, s: priksS, l: priksL),
                                  forKey: udPersoHexKey("priks", skinId: aleaSkinId))
        // Brix texte : contraste garanti (clair si fond sombre, sombre si fond clair).
        let textL = priksL > 0.42 ? Double.random(in: 0.10...0.25) : Double.random(in: 0.75...0.92)
        var textH = priksH + Double.random(in: -0.08...0.08)
        textH = (textH.truncatingRemainder(dividingBy: 1.0) + 1.0).truncatingRemainder(dividingBy: 1.0)
        let textS = Double.random(in: 0.10...0.40)
        UserDefaults.standard.set(hslToHex(h: textH, s: textS, l: textL),
                                  forKey: udPersoHexKey("prikstext", skinId: aleaSkinId))
    }

    /// Génère des couleurs Alea uniquement si aucune n'existe encore en UserDefaults.
    private static func ensureAleaColorsExistInDefaults() {
        let firstKey = udPersoHexKey(bloxDisplayOrder[0], skinId: aleaSkinId)
        guard UserDefaults.standard.string(forKey: firstKey) == nil else { return }
        writeRandomAleaColorsToDefaults()
    }

    /// API publique (appelée par le bouton ↺ dans les Réglages) : nouveau set + notifie le jeu.
    func generateAndSaveAleaColors() {
        Self.writeRandomAleaColorsToDefaults()
        appendOrRefreshPersoSkins()
        NotificationCenter.default.post(name: .blomixSkinDidChange, object: nil)
    }

    private static func makePersoSkinDefinitionFromDefaults(skinId: String = persoSkinId) -> BlomixSkinDefinition {
        var blox: [String: String] = [:]
        for k in bloxDisplayOrder {
            blox[k] = readPersoHexStatic(bloxKey: k, skinId: skinId)
        }
        let displayName: String
        switch skinId {
        case Self.persoSkin2Id: displayName = BlomixL10n.skinDisplayPerso2
        case Self.aleaSkinId:   displayName = BlomixL10n.skinDisplayAlea
        default:                displayName = BlomixL10n.skinDisplayPerso
        }
        return BlomixSkinDefinition(
            id: skinId,
            displayName: displayName,
            blox: blox,
            priks: readPersoHexStatic(bloxKey: "priks", skinId: skinId),
            prikstext: readPersoHexStatic(bloxKey: "prikstext", skinId: skinId)
        )
    }

    /// Clé UserDefaults pour un slot perso selon le skin (`perso`, `perso2` ou `alea`).
    private static func udPersoHexKey(_ bloxKey: String, skinId: String) -> String {
        switch skinId {
        case persoSkin2Id: return "BlomixPerso2Skin_hex_\(bloxKey)"
        case aleaSkinId:   return "BlomixAleaSkin_hex_\(bloxKey)"
        default:           return "BlomixPersoSkin_hex_\(bloxKey)"
        }
    }

    /// Hex `#RRGGBB` pour un slot du skin perso désigné (fallback = palette par défaut).
    private static func readPersoHexStatic(bloxKey: String, skinId: String = persoSkinId) -> String {
        let udKey = udPersoHexKey(bloxKey, skinId: skinId)
        if let s = UserDefaults.standard.string(forKey: udKey),
           let norm = normalizeHexForStorage(s) {
            return norm
        }
        if bloxKey == "priks" {
            return normalizeHexForStorage(builtinDefaultSkin.priks) ?? "#6B5B73"
        }
        if bloxKey == "prikstext" {
            return normalizeHexForStorage(builtinDefaultSkin.prikstext ?? "#FFFFFF") ?? "#FFFFFF"
        }
        if let h = builtinDefaultSkin.blox[bloxKey] {
            return normalizeHexForStorage(h) ?? h
        }
        return "#808080"
    }

    /// Accepte `#RGB`, `#RRGGBB`, `RRGGBB` ; retourne `#RRGGBB` en majuscules ou `nil`.
    private static func normalizeHexForStorage(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            let ch = Array(s)
            guard ch.count == 3 else { return nil }
            s = "\(ch[0])\(ch[0])\(ch[1])\(ch[1])\(ch[2])\(ch[2])"
        }
        guard s.count == 6, UInt32(s, radix: 16) != nil else { return nil }
        return "#\(s)"
    }

    func allSkins() -> [BlomixSkinDefinition] { skins }

    var selectedSkinId: String {
        get { UserDefaults.standard.string(forKey: selectedIdKey) ?? skins.first?.id ?? "default" }
        set {
            guard skinById[newValue] != nil else { return }
            let old = UserDefaults.standard.string(forKey: selectedIdKey)
            guard old != newValue else { return }
            UserDefaults.standard.set(newValue, forKey: selectedIdKey)
            NotificationCenter.default.post(name: .blomixSkinDidChange, object: nil)
        }
    }

    func skin(withId id: String) -> BlomixSkinDefinition? { skinById[id] }

    func bloxSKColor(forNormalizedKey key: String) -> SKColor? {
        guard let skin = skinById[selectedSkinId],
              let hex = skin.blox[key.lowercased()] else { return nil }
        return Self.skColorFromHexString(hex)
    }

    func priksSKColor() -> SKColor {
        guard let skin = skinById[selectedSkinId],
              let c = Self.skColorFromHexString(skin.priks) else {
            return Self.skColorFromHexString("#6B5B73") ?? SKColor(white: 0.42, alpha: 1)
        }
        return c
    }

    func priksDigitSKColor() -> SKColor {
        guard let skin = skinById[selectedSkinId],
              let raw = skin.prikstext,
              let c = Self.skColorFromHexString(raw) else {
            return SKColor(white: 1, alpha: 1)
        }
        return c
    }

    func priksDigitUIColor() -> UIColor { priksDigitSKColor() as UIColor }

    func bloxUIColor(forNormalizedKey key: String) -> UIColor? {
        bloxSKColor(forNormalizedKey: key) as UIColor?
    }

    /// Les 6 couleurs de blox du skin actuel (ordre d'affichage), utilisées pour les particules Magix.
    func bloxSKColors() -> [SKColor] {
        Self.bloxDisplayOrder.compactMap { bloxSKColor(forNormalizedKey: $0) }
    }

    func priksUIColor() -> UIColor { priksSKColor() as UIColor }

    private static func skColorFromHexString(_ raw: String) -> SKColor? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xff) / 255
        let g = CGFloat((v >> 8) & 0xff) / 255
        let b = CGFloat(v & 0xff) / 255
        return SKColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static let builtinDefaultSkin = BlomixSkinDefinition(
        id: "default",
        displayName: BlomixL10n.skinDisplayDefault,
        blox: [
            "blue": "#299D8F", "red": "#E66F51", "purple": "#264753",
            "yellow": "#E8C46A", "green": "#8BB17D", "orange": "#F4A261",
        ],
        priks: "#6B5B73",
        prikstext: "#FFFFFF"
    )
}

// MARK: - Audio (bundle racine : fichiers listés dans « Copy Bundle Resources »)

/// Sons listés dans `Sounds/` du projet ; une fois compilés, ils sont à la **racine** du bundle (`begin.wav`, etc.).
private enum BlomixMatchSFX: String, CaseIterable {
    case begin = "begin.wav"
    case place = "place.wav"
    case bomb = "bomb.wav"
    case connectE = "connect_E.wav"
    case connectF = "connect_F.wav"
    case connectGb = "connect_Gb.wav"
    /// Première chaîne d’une résolution (pas encore de combo).
    case chainNew = "chain_new.wav"
    /// `chain_new-1.wav` : cascades (`chainSeriesLevel == 1`) **ou** première vague avec chaîne 6–8 blox.
    case chainNewCascade1 = "chain_new-1.wav"
    /// `chain_new-2.wav` : cascades (`chainSeriesLevel >= 2`) **ou** première vague avec chaîne ≥ 9 blox.
    case chainNewCascade2 = "chain_new-2.wav"
    case line = "line.mp3"
    case end = "end.wav"
    case victory = "victory.mp3"
    case wrong = "wrong.wav"
    /// Colonne entièrement vidée (bonus +10).
    case emptyColumnClear = "empty_coll.wav"
    /// Ligne des 10 coups : apparition de l’aperçu en bas de grille (`moveCount % 10 == 9`).
    case pendingRandomLineBloopa = "5251__noisecollector__bloopa01.aiff"
    /// Disparition d’un Priks quand son compteur atteint 0.
    case priksVanish = "prix.wav"
    /// Son joué au démarrage des écrans de transition (tuto, passage de stage…).
    case transition = "transition.wav"
    /// Son joué à l'atterrissage d'un bloc Magix.
    case magix = "magix.wav"
    /// Son joué quand le joueur active la bombe (la sort du stock pour la mettre en jeu).
    case bombLoad = "gun_load.wav"
    /// Son atmosphérique joué au déclenchement de l'effet CLEANX.
    case cleanx = "cleanx.wav"
    /// Son atmosphérique joué au déclenchement de l'effet SCRUMBLX.
    case scrumblx = "scrumblx.wav"
}

/// Précharge et joue les `AVAudioPlayer` (simple, sans dépendance à `SKAction` pour le décodage à chaque fois).
private final class BlomixSoundBank {
    private var players: [BlomixMatchSFX: AVAudioPlayer] = [:]

    func preloadAll() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        for sfx in BlomixMatchSFX.allCases {
            let raw = sfx.rawValue as NSString
            let base = raw.deletingPathExtension
            let ext = raw.pathExtension
            guard let url = Bundle.main.url(forResource: base, withExtension: ext) else { continue }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                if sfx == .chainNew {
                    player.enableRate = true
                }
                player.prepareToPlay()
                players[sfx] = player
            } catch {
                continue
            }
        }
    }

    func play(_ sfx: BlomixMatchSFX, playbackRate: Float = 1.0) {
        guard let player = players[sfx] else { return }
        player.stop()
        player.currentTime = 0
        if sfx == .chainNew {
            player.rate = playbackRate
        } else {
            player.rate = 1.0
        }
        let master = BlomixMatchAudioSettings.shared.masterVolume
        let relative = BlomixAudioMixSettings.shared.relativeVolume(forSoundNamed: sfx.rawValue)
        player.volume = min(1, max(0, master * relative))
        player.play()
    }
}

// MARK: - Jonction Blox (connexions visuelles SKShapeNode)

/// Position discrète sur la grille 8×8 pour la pose et les jonctions.
struct GridPosition: Hashable {
    let row: Int
    let col: Int
}

// MARK: - Modèle grille (Phase 2 — étapes 1 & 2)

/// Contenu d’une case de la grille 8×8 (aligné sur l’ancien `priks.html`).
/// Variante d'un bloc Magix.
enum MagixKind: String, Codable, Equatable, CaseIterable {
    /// Transformation serpent (chemin aléatoire ≤ 15 blocs) + grosse chaîne garantie.
    case chromax
    /// Décrémente de 2 tous les Brix de la grille ; reste dans la grille en tant que Brix(9).
    case brixed
    /// Transformation en croix (ligne + colonne) + chaîne.
    case crosx
    /// Mélange la grille : chaque ligne se décale aléatoirement (direction + distance 1–7, wrap-around).
    case scrumblx
    /// Roulette de couleur : choisit une couleur au ralenti, efface tous les blocs de cette couleur.
    case colorx
    /// Efface tout le contenu de la grille et laisse un Brix valant le nombre de cases supprimées.
    case cleanx
    /// Échange interactif de deux couleurs : le joueur sélectionne successivement deux couleurs.
    case twistx
}

enum BlockType: Equatable {
    case empty
    /// Couleur logique : `red`, `blue`, … — rendu **sprite plein** (hexa = jonctions).
    case color(String)
    /// Priks : carré plein + chiffre au centre — `Int` = **coups restants** avant disparition (ex. 5 → 4 → … → 0).
    case priks(Int)
    /// Bloc Magix : effet spécial à l'atterrissage selon la variante.
    case magix(MagixKind)
}

// MARK: - BlockType Codable (sauvegarde solo)

extension BlockType: Codable {
    private enum Tag: String, Codable { case e, c, p, mx }
    private enum CodingKeys: String, CodingKey { case t, v }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Tag.self, forKey: .t) {
        case .e:  self = .empty
        case .c:  self = .color(try container.decode(String.self, forKey: .v))
        case .p:  self = .priks(try container.decode(Int.self, forKey: .v))
        case .mx: self = .magix(try container.decode(MagixKind.self, forKey: .v))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty:
            try c.encode(Tag.e, forKey: .t)
        case .color(let name):
            try c.encode(Tag.c, forKey: .t)
            try c.encode(name, forKey: .v)
        case .priks(let hits):
            try c.encode(Tag.p, forKey: .t)
            try c.encode(hits, forKey: .v)
        case .magix(let kind):
            try c.encode(Tag.mx, forKey: .t)
            try c.encode(kind, forKey: .v)
        }
    }
}

// MARK: - Sauvegarde de partie solo

struct BlomixSoloGameSave: Codable {
    static let currentVersion = 7   // v7 : isZenMode ajouté
    let version: Int
    let grid: [[BlockType]]
    let currentBlock: BlockType
    let blockAfterCurrent: BlockType
    let blockTwoAhead: BlockType
    let selectedColumn: Int
    let moveCount: Int
    let nextBottomLine: [BlockType]
    let bombCount: Int
    let isBombMode: Bool
    let chainClearWaveCount: Int
    let score: Int
    let displayedScore: Int
    let chainSeriesLevel: Int
    let savedAt: Date
    let currentStageIndex: Int
    let stageTimerSecondsRemaining: Int
    let moveRecords: [BlomixMoveRecord]
    let hintsRemaining: Int
    let isZenMode: Bool

    // Initializer explicite (nécessaire car init(from:) supprime le memberwise synthétique).
    init(version: Int, grid: [[BlockType]], currentBlock: BlockType, blockAfterCurrent: BlockType,
         blockTwoAhead: BlockType, selectedColumn: Int, moveCount: Int, nextBottomLine: [BlockType],
         bombCount: Int, isBombMode: Bool, chainClearWaveCount: Int, score: Int, displayedScore: Int,
         chainSeriesLevel: Int, savedAt: Date, currentStageIndex: Int, stageTimerSecondsRemaining: Int,
         moveRecords: [BlomixMoveRecord], hintsRemaining: Int, isZenMode: Bool) {
        self.version                    = version
        self.grid                       = grid
        self.currentBlock               = currentBlock
        self.blockAfterCurrent          = blockAfterCurrent
        self.blockTwoAhead              = blockTwoAhead
        self.selectedColumn             = selectedColumn
        self.moveCount                  = moveCount
        self.nextBottomLine             = nextBottomLine
        self.bombCount                  = bombCount
        self.isBombMode                 = isBombMode
        self.chainClearWaveCount        = chainClearWaveCount
        self.score                      = score
        self.displayedScore             = displayedScore
        self.chainSeriesLevel           = chainSeriesLevel
        self.savedAt                    = savedAt
        self.currentStageIndex          = currentStageIndex
        self.stageTimerSecondsRemaining = stageTimerSecondsRemaining
        self.moveRecords                = moveRecords
        self.hintsRemaining             = hintsRemaining
        self.isZenMode                  = isZenMode
    }

    // Décodage rétrocompatible : isZenMode défaut à false pour les sauvegardes antérieures.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version                   = try c.decode(Int.self,           forKey: .version)
        grid                      = try c.decode([[BlockType]].self,  forKey: .grid)
        currentBlock              = try c.decode(BlockType.self,      forKey: .currentBlock)
        blockAfterCurrent         = try c.decode(BlockType.self,      forKey: .blockAfterCurrent)
        blockTwoAhead             = try c.decode(BlockType.self,      forKey: .blockTwoAhead)
        selectedColumn            = try c.decode(Int.self,            forKey: .selectedColumn)
        moveCount                 = try c.decode(Int.self,            forKey: .moveCount)
        nextBottomLine            = try c.decode([BlockType].self,    forKey: .nextBottomLine)
        bombCount                 = try c.decode(Int.self,            forKey: .bombCount)
        isBombMode                = try c.decode(Bool.self,           forKey: .isBombMode)
        chainClearWaveCount       = try c.decode(Int.self,            forKey: .chainClearWaveCount)
        score                     = try c.decode(Int.self,            forKey: .score)
        displayedScore            = try c.decode(Int.self,            forKey: .displayedScore)
        chainSeriesLevel          = try c.decode(Int.self,            forKey: .chainSeriesLevel)
        savedAt                   = try c.decode(Date.self,           forKey: .savedAt)
        currentStageIndex         = try c.decode(Int.self,            forKey: .currentStageIndex)
        stageTimerSecondsRemaining = try c.decode(Int.self,           forKey: .stageTimerSecondsRemaining)
        moveRecords               = try c.decode([BlomixMoveRecord].self, forKey: .moveRecords)
        hintsRemaining            = try c.decode(Int.self,            forKey: .hintsRemaining)
        isZenMode                 = (try? c.decode(Bool.self,         forKey: .isZenMode)) ?? false
    }
}

final class BlomixSoloSaveManager: @unchecked Sendable {
    static let shared = BlomixSoloSaveManager()
    private let udKey = "blomix_solo_save_v2"
    private init() {}

    var hasSave: Bool { UserDefaults.standard.data(forKey: udKey) != nil }

    func save(_ s: BlomixSoloGameSave) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }

    func load() -> BlomixSoloGameSave? {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let s = try? JSONDecoder().decode(BlomixSoloGameSave.self, from: data),
              s.version == BlomixSoloGameSave.currentVersion else {
            clear()
            return nil
        }
        return s
    }

    func clear() { UserDefaults.standard.removeObject(forKey: udKey) }
}

/// Règles Priks alignées sur `old_web_code/priks.html` (`getNextBlock`, dégâts de chaîne).
private enum PriksRules {
    /// Probabilité Priks par tirage : **1 chance sur 8** (file à lancer + chaque case de la ligne des 10 coups).
    static let spawnProbability: Double = 1.0 / 8.0
    /// Valeur initiale du compteur sur le bloc suivant (même tableau que le web).
    static let initialHitsRemaining: Int = 5
}

private enum MagixRules {
    /// Probabilité par variante Magix. L'ordre du tableau détermine la priorité de tirage.
    /// Total ≈ 1/100 + 1/100 + 1/150 + 1/150 ≈ 1/30.
    static let spawnProbabilityByKind: [(kind: MagixKind, p: Double)] = [
        (.twistx,   1.0 / 324.0),
        (.colorx,   1.0 / 180.0),
        (.scrumblx, 1.0 / 180.0),
        (.crosx,    1.0 / 216.0),
        (.chromax,  1.0 / 324.0),
        (.brixed,   1.0 / 324.0),
        (.cleanx,   1.0 / 500.0),
    ]
    /// Probabilité globale cumulée (utilisée pour le check rapide avant tirage de variante).
    static var spawnProbability: Double { spawnProbabilityByKind.reduce(0) { $0 + $1.p } }
    /// Longueur maximale du chemin pour CHROMAX (cellules occupées transformées).
    static let chromaxPathLength: Int = 15
    /// Décrément appliqué à tous les Brix lors de l'effet BRIXED.
    static let brixedGlobalDecrement: Int = 2
    /// Valeur initiale du Brix créé par BRIXED (il reste dans la grille comme un Priks normal).
    static let brixedInitialHits: Int = 9

    /// Texte du popup affiché à l'atterrissage d'un bloc Magix.
    static func label(for kind: MagixKind) -> String {
        switch kind {
        case .chromax:  return "CHROMAX"
        case .brixed:   return "BRIXED"
        case .crosx:    return "CROSSX"
        case .scrumblx: return "SCRUMBLX"
        case .colorx:   return "COLORX"
        case .cleanx:   return "SAINTX"
        case .twistx:   return "TWISTX"
        }
    }

    /// Symbole court affiché sur le sprite Magix (queue, preview, chute).
    static func symbol(for kind: MagixKind) -> String {
        switch kind {
        case .chromax:  return "?"
        case .brixed:   return "9"
        case .crosx:    return "+"
        case .scrumblx: return "="
        case .colorx:   return "O"
        case .cleanx:   return "∞"
        case .twistx:   return "X"
        }
    }

    /// Nom SpriteKit du label de symbole sur les sprites Magix (permet le cleanup lors du reuse).
    static let symbolLabelName = "magixSymbol"
    /// Nom SpriteKit du nœud de halo blanc derrière le sprite Magix.
    static let glowNodeName    = "magixGlow"
    /// Clé SKAction du spawner de particules orbitales colorées autour d'un bloc Magix.
    static let orbitParticlesActionKey = "magixOrbitParticles"
}

/// Constantes de mise en page héritées du canvas web (360×400, zone grille 320×320, 8×8).
private enum GridLayout {
    static let rowCount = 8
    static let columnCount = 8
    /// Indice de la **dernière** ligne = **bas** de la grille.
    static let bottomRowIndex = rowCount - 1
    /// Indice de la **première** ligne = **haut** de la grille (les blocs se posent d’abord en haut de colonne).
    static let topRowIndex = 0
    /// Ancien `cellSize = 320 / gridSize` dans `priks.html`.
    static let cellPoints: CGFloat = 40
    static var spanPoints: CGFloat { CGFloat(columnCount) * cellPoints }
}

/// Scène 2D du jeu Blomix.
final class GameScene: SKScene {

    // MARK: - Nœuds racine (Phase 1)

    private static let backgroundNodeName = "rootBackground"
    private static let titleNodeName = "titleBLOMIX"
    private static let gameplaySubtitleUnderTitleName = "gameplaySubtitleUnderTitle"
    private static let gridContainerName = "gridContainer"
    /// Contour 1 pt autour de la grille (#E0E0E0), décalé de 2 pt du bord extérieur des cases.
    private static let gridFrameOutlineName = "gridFrameOutline"
    /// Préfixe des `SKShapeNode` de jonction (retirés / reconstruits avec `drawGrid`).
    private static let junctionNodeNamePrefix = "junction_"
    private static let previewNodeName = "currentBlockPreview"
    private static let fallingSpriteName = "fallingBlockTemp"
    private static let previewPriksDigitName = "previewPriksDigit"
    /// Bande de **8** cases sous la **preview du joueur** (`moveCount % 10 == 9`).
    private static let bottomLinePreviewStripName = "bottomLinePreviewStrip"
    private static let bottomLinePreviewJitterActionKey = "bottomLinePreviewJitter"
    private static let randomLineRisingSpritePrefix = "randomLineRisingCol"
    private static let bombHudIconName = "bombHudIcon"
    private static let bombHudCountLabelName = "bombHudCountLabel"
    /// Label de debug temporaire affichant le score d'évaluation en temps réel (visible quand evalEnabled = true).
    private static let evalDebugLabelName = "evalDebugLabel"
    /// Aperçus **sous** la grille : à gauche = bloc dans **2** coups, à droite = **prochain** après `currentBlock`.
    private static let upcomingSlotTwoAheadName = "upcomingSlotTwoAhead"
    private static let upcomingSlotNextName = "upcomingSlotNext"
    private static let upcomingQueueCaptionLabelName = "upcomingQueueCaptionLabel"
    private static let queueSlotPriksDigitName = "queueSlotPriksDigit"
    private static let bombNukeDigitName        = "bombNukeDigit"
    private static let scoreHudLabelName = "hudScoreLabel"
    private static let bestScoreAboveName    = "hudBestScoreAbove"     // chiffre seul au-dessus du score
    private static let bombeCaptionName      = "hudBombeCaption"   // conservé pour compatibilité saves
    private static let bombeValueName        = "hudBombeValue"     // conservé pour compatibilité saves
    private static let hudTimerCaptionName   = "hudTimerCaption"
    private static let ligneCaptionName = "hudLigneCaption"
    private static let ligneValueName   = "hudLigneValue"
    private static let scorePulseActionKey = "scorePulse"
    private static let scoreRollActionKey  = "scoreRoll"
    private static let pvpMilestoneScoreFlashKey = "pvpMilestoneFlash"
    /// Calque « fin de partie » : fond + textes ; retiré par `returnToStartScreenFromGameOver()`.
    private static let gameOverOverlayName = "gameOverOverlay"
    private static let gameOverTitleLabelName = "gameOverTitleLabel"
    private static let gameOverScoreLabelName = "gameOverScoreLabel"
    private static let gameOverDimBackgroundName = "gameOverDimBackground"
    private static let gameOverRestartLabelName = "gameOverRestartLabel"
    private static let gameOverLeaderboardLabelName = "gameOverLeaderboardLabel"
    private static let gameOverPersonalBestLabelName = "gameOverPersonalBestLabel"
    private static let gameOverWorstMoveButtonName = "gameOverWorstMoveButton"
    private static let worstMistakeOverlayName  = "worstMistakeOverlay"
    /// Dialog de confirmation "Quitter la partie ?" (SpriteKit natif).
    private static let quitConfirmOverlayName   = "quitConfirmOverlay"
    private static let quitConfirmBtnQuitName   = "quitConfirmBtnQuit"
    private static let quitConfirmBtnCancelName = "quitConfirmBtnCancel"
    private static let hintGhostContainerName = "hintGhostContainer"
    private static let colorxOverlayContainerName = "colorxOverlayContainer"
    private static let gameOverQuoteLine1LabelName = "gameOverQuoteLine1Label"
    private static let gameOverQuoteLine2LabelName = "gameOverQuoteLine2Label"
    private static let gameOverQuoteAuthorLabelName = "gameOverQuoteAuthorLabel"
    /// Indicateur d’auth Game Center (coin supérieur droit).
    private static let gameCenterStatusLabelName = "hudGameCenterStatus"

    /// Menu déroulant (icône + liste) en haut à droite pendant la partie.
    private static let bottomMenuContainerName = "bottomMenuContainer"
    private static let bottomMenuNewGameName = "bottomMenuNewGame"
    private static let bottomMenuScoresName = "bottomMenuScores"
    private static let bottomMenuRulesName = "bottomMenuRules"
    private static let bottomMenuSettingsName = "bottomMenuSettings"
    private static let bottomMenuMultiplayerName = "bottomMenuMultiplayer"
    private static let hudGameMenuIconName = "hudGameMenuIcon"
    private static let hudGameMenuDropdownName = "hudGameMenuDropdown"
    private static let hudGameMenuPanelName = "hudGameMenuPanel"

    private static let startScreenOverlayName = "startScreenOverlay"
    private static let startScreenBackdropName = "startScreenBackdrop"
    private static let startScreenAmbientBlocksContainerName = "startScreenAmbientBlocksContainer"
    private static let startScreenAmbientBlocksSpawnActionKey = "startScreenAmbientBlocksSpawn"
    private static let gameOverAmbientBlocksContainerName = "gameOverAmbientBlocksContainer"
    private static let gameOverAmbientBlocksSpawnActionKey = "gameOverAmbientBlocksSpawn"
    private static let startScreenTitleLabelName = "startScreenTitleLabel"
    private static let startScreenSubtitleLabelName = "startScreenSubtitleLabel"
    private static let startScreenPlayerNameLabelName = "startScreenPlayerNameLabel"
    private static let startScreenPlayerEloLabelName = "startScreenPlayerEloLabel"
    private static let startScreenRankDiscsContainerName = "startScreenRankDiscsContainer"
    private static let startScreenRankDiscSoloName       = "startScreenRankDiscSolo"
    private static let startScreenRankDiscAvgName        = "startScreenRankDiscAvg"
    private static let startScreenRankDiscZenName        = "startScreenRankDiscZen"
    /// Suffixe ajouté au nom du disc pour nommer le SKLabelNode du rang.
    private static let rankDiscRankLabelSuffix           = "_rank"
    private static let startScreenStartLabelName = "startScreenStartLabel"
    private static let startScreenScoresLabelName = "startScreenScoresLabel"
    private static let startScreenSettingsLabelName = "startScreenSettingsLabel"
    private static let startScreenCreditsLabelName = "startScreenCreditsLabel"
    private static let startScreenPvPLabelName = "startScreenPvPLabel"
    private static let startScreenZenLabelName = "startScreenZenLabel"
    private static let startScreenStartChipName = "startScreenStartChip"
    private static let startScreenScoresChipName = "startScreenScoresChip"
    private static let startScreenPvPChipName = "startScreenPvPChip"
    private static let startScreenSettingsChipName = "startScreenSettingsChip"
    private static let startScreenCreditsChipName = "startScreenCreditsChip"
    private static let startScreenZenChipName = "startScreenZenChip"
    private static let startScreenRulesLabelName = "startScreenRulesLabel"
    private static let startScreenRulesChipName = "startScreenRulesChip"
    private static let studioSplashOverlayName = "studioSplashOverlay"
    private static let hudPvPTurnTimerName = "hudPvPCountdown"
    private static let hudPvPOpponentName = "hudPvPOpponentName"
    private static let pvpConnectingOverlayName = "pvpConnectingOverlay"

    // Barre "Prochaine ligne" supprimée en v1.5 (remplacée par compteur LIGNE en haut).
    // Barre "Prochaine bombe" supprimée en v1.5 (remplacée par compteur BOMBE en haut).
    private static let pvpRemoteFillContainerName = "pvpRemoteFillIndicator"
    private static let pvpRemoteFillSegPrefix      = "pvpRemoteFillSeg_"
    private static let pvpRemoteScoreLabelName     = "pvpRemoteScoreLabel"

    /// Nom PostScript courant de la police choisie par le joueur.
    private static var customUIFontPostScriptName: String { BlomixTypography.shared.spriteKitFontName }
    private static let gameOverQuotesFileBaseName = "gameover_quotes"
    private static let tipsOfDayFileBaseName = "tips_of_day"
    private static let startScreenTipContainerName = "startScreenTipContainer"
    private static let startScreenTipTextLabelName = "startScreenTipTextLabel"
    private static let studioLogoAssetName    = "StudioLogo"
    // Dans WebImages (provides-namespace:true), le nom de chargement inclut le préfixe.
    private static let studioLogoOffAssetName = "WebImages/StudioLogo_off"
    private static let startScreenAmbientBlockColorKeys = ["red", "blue", "green", "yellow", "purple", "orange"]

    /// Décalages des **8 voisins** (orthogonal + diagonal) pour la détection des chaînes.
    private static let chainNeighborDeltas8: [(dr: Int, dc: Int)] = [
        (-1, -1), (-1, 0), (-1, 1),
        (0, -1), (0, 1),
        (1, -1), (1, 0), (1, 1),
    ]

    // MARK: - Chaînes (types & constantes)

    /// Coordonnées discrètes d’une case ; `Hashable` pour les `Set` (composantes connexes, cellules déjà traitées).
    private struct GridAddress: Hashable {
        let row: Int
        let col: Int
    }

    /// Un bloc qui doit **glisser vers le haut** dans sa colonne après un compact (coordonnées **avant** mutation par `compactGridTowardTop()`).
    private struct CompactRiseMove {
        let column: Int
        let fromRow: Int
        let toRow: Int
    }


    /// Animation des blocs qui remontent après suppression d’une chaîne.
    private enum LandingBounce {
        /// Phase A : squash à l'impact (centre légèrement au-dessus, aplatissement + étalement) — 0.04 s.
        static let squashDuration:  TimeInterval = 0.09
        /// Phase B : rebond élastique vers le bas (centre sous p0, allongement vertical) — 0.05 s.
        static let stretchDuration: TimeInterval = 0.03
        /// Phase C : stabilisation complète — 0.06 s.
        static let settleDuration:  TimeInterval = 0.03
        static var totalDuration: TimeInterval { squashDuration + stretchDuration + settleDuration }
    }

    /// Déformation du bloc pendant le vol (squash-and-stretch de vol).
    /// xScale < 1 (resserrement latéral) + yScale > 1 (allongement dans le sens du mouvement).
    /// Le de-stretch ramène exactement à (1.0, 1.0) à l'atterrissage → transition parfaite
    /// avec la phase A du LandingBounce qui part de (1.0, 1.0).
    private enum FlightStretch {
        static let xScale: CGFloat = 0.82
        static let yScale: CGFloat = 1.25
    }

    private enum CompactRiseAnimation {
        static let duration: TimeInterval = 0.25
    }

    /// Paramètres du **feedback visuel** après une suppression de chaîne (dissolution des sprites avant mutation de la grille).
    private enum ChainClearFeedback {
        static let dissolveScaleUpDuration: TimeInterval   = 0.20
        static let dissolveScaleDownDuration: TimeInterval = 0.16
        static let dissolveFadeDuration: TimeInterval      = 0.14
        static var dissolvePerCellAnimationDuration: TimeInterval {
            dissolveScaleUpDuration + dissolveScaleDownDuration + dissolveFadeDuration
        }
        /// Décalage entre le début de l’animation de deux cases (~0,03–0,05 s).
        static let dissolveStagger: TimeInterval = 0.04
        /// Mélange vers le blanc au pic de la phase scaleDown (conserve la teinte du blox).
        static let dissolveBrightenTowardWhite: CGFloat = 0.30
        /// Paillettes de dissolution : apparaissent à des positions aléatoires dans la case et tombent lentement.
        static let popDotRadiusRange: ClosedRange<CGFloat> = 2.0...3.5
        static let popDotFallDistance: ClosedRange<CGFloat> = 10...22
        static let popDotFadeDuration: TimeInterval         = 0.45
        /// Courte pause après la phase physique avant de re-scanner la grille (cascades plus lisibles).
        static let cascadeBeatDuration: TimeInterval = 0.07
        /// Disparition d’un Priks à 0 : petit spin rapide + fade.
        static let priksVanishDuration: TimeInterval = 0.18
    }

    /// Animation discrète de la ligne des 10 en attente (léger tremblement).
    private enum PendingLinePreviewFeedback {
        static let jitterAmplitudeX: CGFloat = 1.0
        static let jitterAmplitudeY: CGFloat = 0.5
        static let organicCycleDuration: TimeInterval = 1.1
    }

    /// Feedback "points -> score" : points en même temps que le popup `+N`, bump score à l’arrivée des points.
    private enum ScorePopupFeedback {
        static let transferDuration: TimeInterval = 0.2
        static let transferStartFadeDuration: TimeInterval = 0.06
        /// Petite phase d’« éjection » radiale avant le trajet vers le score (dizaines de px).
        static let radialBurstDuration: TimeInterval = 0.08
        static let radialBurstDistance: ClosedRange<CGFloat> = 22...46
        static let transferDotRadiusRange: ClosedRange<CGFloat> = 1.8...2.8 // ~4..6 px de diametre
        static let transferStartSpreadRadius: CGFloat = 28
        static let transferTargetJitterX: CGFloat = 26
        static let transferTargetJitterY: CGFloat = 12
        static let dotsPerPoint: CGFloat = 0.38
        static let minDots = 9
        static let maxDots = 52
        /// Durée totale du trajet des points depuis leur apparition : fade-in + éjection + move vers le score.
        static var transferPostPopupFlightDuration: TimeInterval {
            transferStartFadeDuration + radialBurstDuration + transferDuration
        }
    }

    /// Pré-animation de Game Over : cercles concentriques qui se referment sur la zone de perte.
    private enum GameOverFocusFeedback {
        static let totalDuration: TimeInterval = 1.38
        static let ringCount = 4
        static let ringLineWidth: CGFloat = 2.0
        static let ringStartRadius: CGFloat = GridLayout.cellPoints * 2.1
        static let ringEndScale: CGFloat = 0.18
        static let ringStartAlpha: CGFloat = 0.9
        static let ringStagger: TimeInterval = 0.12
        static let layerZ: CGFloat = 160
        static let titleDuration: TimeInterval = 0.28
        static let titleHoldDuration: TimeInterval = 0.18
        static let titleStartFontSize: CGFloat = 20
        static let titleEndFontSize: CGFloat = 40
    }

    /// Citation affichée sur l’overlay de fin de partie.
    private struct GameOverQuote: Decodable {
        let text: String
        let author: String
    }

    /// Conseil du jour affiché sur l’écran d’accueil.
    private struct TipOfDay: Decodable {
        let text: String
    }

    /// Feedback visuel **explosion bombe** (onde + blox puis mutation grille dans le `completion`).
    private enum BombExplosionFeedback {
        static let shockWaveDuration: TimeInterval = 0.52   // durée de chaque cercle
        static let shockWaveCount: Int = 5                  // nombre de cercles en train
        static let shockWaveStagger: TimeInterval = 0.09    // décalage entre cercles
        static var shockWaveTrainDuration: TimeInterval {   // durée totale du train
            shockWaveDuration + TimeInterval(shockWaveCount - 1) * shockWaveStagger
        }
        static let shockWaveEndScale: CGFloat = 3.5         // scale final (départ = 1.0)
        static let shockWaveStartAlpha: CGFloat = 1.0
        static let shockWaveBaseRadius: CGFloat = 24        // rayon de départ (visible dès le 1er frame)
        static let shockWaveRingWidth: CGFloat  = 9.0       // épaisseur de l'anneau (path fill)
        static let shockWaveZ: CGFloat = 46
        // Flash central
        static let flashRadius: CGFloat = 28
        static let flashDuration: TimeInterval = 0.15
        static let flashZ: CGFloat = 47

        static let blockStaggerPerStep: TimeInterval = 0.02
        static let radialPushDuration: TimeInterval = 0.18
        static let blockScaleUpDuration: TimeInterval = 0.12
        static let blockRotateDuration: TimeInterval = 0.2
        static let blockCollapseDuration: TimeInterval = 0.22
        static var blockPhase1Duration: TimeInterval {
            max(radialPushDuration, blockScaleUpDuration, blockRotateDuration)
        }
        static var blockPerCellAnimationDuration: TimeInterval {
            blockPhase1Duration + blockCollapseDuration
        }
        static let radialPushDistanceMin: CGFloat = 12
        static let radialPushDistanceMax: CGFloat = 20
        static let rotationDegreesRange: ClosedRange<CGFloat> = 15...30
        static let blockAnimZ: CGFloat = 34

        static let emitterLifetime: TimeInterval = 0.4
        static let emitterZ: CGFloat = 44
    }

    /// Barres de progression « prochaine ligne » / « prochaine bombe » (segments `SKSpriteNode`).
    private enum ProgressHUD {
        static let segmentCount = 10
        static let lineBarHeight: CGFloat = 6
        static let lineSegmentGap: CGFloat = 2
        static let lineMarginBelowGrid: CGFloat = 8
        static let bombBarHeight: CGFloat = 5
        static let bombSegmentGap: CGFloat = 1.5
        static let bombBarMinWidth: CGFloat = 52
        /// Écart entre le **bas** de l’icône bombe et le **haut** de la barre « Next bomb ».
        static let bombStackBelowIcon: CGFloat = 6
        /// Cases **vides** des barres (comme avant).
        static let dimTrack = SKColor(white: 0.2, alpha: 1)
        /// Cases **remplies** — Next line & Next bomb (#ADADAD). Pas d’appel à `GameScene.skColor` ici (init statique non isolé du MainActor).
        static let segmentFilled: SKColor = {
            let h: UInt32 = 0xADADAD
            let r = CGFloat((h >> 16) & 0xff) / 255
            let g = CGFloat((h >> 8) & 0xff) / 255
            let b = CGFloat(h & 0xff) / 255
            return SKColor(red: r, green: g, blue: b, alpha: 1)
        }()
        static let lineFill = segmentFilled
        static let bombFill = segmentFilled

        static let remoteFillSegmentWidth: CGFloat = 4
        static let remoteFillGap: CGFloat = 4
        static let remoteFillMarginLeftOfGrid: CGFloat = 8
    }

    /// Aperçus miniatures de la file (sous la zone d’aperçu des lignes), à gauche de la bombe.
    private enum UpcomingQueueLayout {
        static let cellPoints: CGFloat = 28
        /// Slot de gauche (`blockTwoAhead`) : moitié du côté du slot « next », même ancrage bas.
        static let leftSlotCellFactor: CGFloat = 0.5
        static let gapBetweenSlots: CGFloat = 6
        static let captionGapBelowSlots: CGFloat = 6
    }

    // MARK: - Modèle

    /// Grille indexée `[ligne][colonne]`.
    /// - `row == GridLayout.topRowIndex` → **haut** de l’aire de jeu.
    /// - `row == GridLayout.bottomRowIndex` → **bas** de l’aire de jeu.
    private var grid: [[BlockType]] = []

    /// Pièce en attente de pose : couleur **ou** Priks (`randomNextPlayableBlock`, 1/8 Priks).
    private var currentBlock: BlockType = .empty
    /// Bloc joué **juste après** `currentBlock` (aperçu à droite dans la file sous la grille).
    private var blockAfterCurrent: BlockType = .empty
    /// Bloc dans **deux** coups après `currentBlock` (aperçu à gauche dans la file).
    private var blockTwoAhead: BlockType = .empty

    /// Colonne cible (0…7) : déplacement clavier + preview ; repasse au **milieu (3)** après chaque pose.
    private var selectedColumn: Int = 3

    /// Couleurs jouables (noms logiques ; rendu sprite plein, pas de PNG blox).
    private static let colorPalette = ["red", "blue", "green", "yellow", "purple", "orange"]

    /// Pendant une montée animée : pas de nouveau déplacement / pose (aligné sur `isProcessing` du web).
    private var isProcessing = false

    // Tip of the day pool (loaded lazily from JSON, shuffled for variety).
    private var tipOfDayPool: [TipOfDay] = []
    private var lastTipIndex: Int = -1

    /// `true` après `triggerGameOver()` : entrées bloquées ; **RESTART** ou **R** → retour écran d’accueil.
    private var isGameOver = false

    /// Score final au moment du **Game Over** (identique à `score` dans `triggerGameOver`) — envoi `ScoreManager` / affichage record.
    private(set) var gameOverFinalScore: Int = 0

    /// `true` tant que l’écran d’accueil plein écran est affiché ; la partie n’a pas encore commencé.
    private var isStartScreen = true
    /// Accesseurs exposés à GameViewController pour les guards de bannière défi entrant.
    var pvpCoordinatorIsNil: Bool { pvpCoordinator == nil }
    /// Ne montrer le logo studio qu’au tout premier affichage de la scene.
    private var didShowStudioSplash = false
    /// Taille des chips d'accueil, mémorisée pour positionner le dot PvP auto-search.
    private var startScreenChipSize: CGSize = .zero

    /// Banque audio préchargée (`BlomixSoundBank`).
    private let soundBank = BlomixSoundBank()

    /// Nombre de **poses réussies** depuis le début de la partie (incrémenté après chaînes + compact, comme `moveCount++` puis `addRandomLine` dans le web).
    private var moveCount: Int = 0

    /// Prochaine ligne des 10 coups : **8** tirages indépendants (`randomNextPlayableBlock` par case).
    private var nextBottomLine: [BlockType] = []

    /// Évite de rejouer le « bloopa » à chaque `drawGrid` tant que `moveCount` n’a pas changé.
    private var pendingBottomLineBloopaSoundPlayedAtMoveCount: Int?
    /// Même logique que ci-dessus, mais pour la preview des lignes d'attaque PvP en attente.
    private var pvpIncomingAttackPreviewSoundPlayedForID: Int?

    /// `true` juste après un `dropBlock` réussi : au prochain `resolveChains()` sans chaîne, on incrémente `moveCount` et on teste la ligne des 10 coups.
    private var shouldRunPostPlacementHooks = false

    /// Évite de mettre `isProcessing = false` pendant qu’on enchaîne insertion de ligne + `resolveChains()` (appels différés).
    private var isInjectingBottomRandomLine = false

    /// Bombes restantes (`priks.html` : `bombCount = 1` au départ).
    private var bombCount: Int = 1
    /// Mode placement bombe (preview bombe ; `B` ou tap sur l’icône pour basculer).
    private var isBombMode: Bool = false

    // (TWISTX n'a pas d'état interactif — effet entièrement automatique à l'atterrissage)

    /// Nombre de **vagues** où au moins une chaîne ≥ 5 a été supprimée — aligné sur `chainCount++` dans `checkChains` du web.
    private var chainClearWaveCount: Int = 0

    /// Score cumulé (`priks.html` : `score`).
    private var score: Int = 0
    /// Dernière centaine franchie (100, 200, …) ; déclenche l'explosion de dots sur le score HUD.
    private var lastScoreHundredMilestone: Int = 0
    /// Explosion de milestone en attente d'être synchronisée avec le début du rolling counter.
    private enum PendingMilestoneKind { case none, hundred, thousand }
    private var pendingMilestoneExplosion: PendingMilestoneKind = .none
    /// Score actuellement affiché (peut etre decalé pour synchroniser l'effet de transfert des points).
    private var displayedScore: Int = 0
    /// Borne de départ de l'animation rolling du label score (= valeur texte au moment du déclenchement).
    private var scoreRollStart: Int = 0
    /// Cible courante de l'animation rolling ; mise à jour à chaque incrément pendant la montée.
    private var scoreRollTarget: Int = 0
    /// Meilleur score affiché dans le HUD (fallback local immédiat, Game Center si disponible).
    private var hudBestScoreValue: Int = 0
    /// Ignore les retours asynchrones obsolètes lors des rafraîchissements du record.
    private var bestScoreFetchGeneration: Int = 0

    // MARK: - Analyse des coups (BlomixMoveAnalyzer)

    /// Queue dédiée aux calculs de lookahead (hors main thread).
    private static let analyzerQueue = DispatchQueue(label: "blomix.moveAnalyzer", qos: .userInitiated)
    /// Génération courante : incrémentée à chaque triggerMoveAnalysis, pour ignorer les résultats périmés.
    private var analyzerGeneration: Int = 0
    /// Dernier résultat de lookahead calculé proactivement après stabilisation.
    private var analyzerLookAhead: BlomixLookAheadResult? = nil
    /// Qualité du coup en attente d'affichage (fixée au tap, consommée à l'atterrissage).
    private var analyzerPendingQuality: BlomixMoveQuality? = nil
    /// Statistiques de la partie en cours.
    private var analyzerGameStats = BlomixGameMoveStats()
    /// Grille et file de blocs capturés au moment où `analyzerLookAhead` a été lancé
    /// (= état avant le prochain coup du joueur, identique à ce que voyait le joueur).
    private var analyzerPreMoveGrid: [[BlockType]]? = nil
    private var analyzerPreMoveBlock: BlockType = .empty
    private var analyzerPreMoveNext1: BlockType = .empty
    private var analyzerPreMoveNext2: BlockType = .empty
    private var analyzerPreMovePendingLine: [BlockType]? = nil
    /// Pire coup de la partie en cours (écart optimal − choix le plus élevé).
    /// Nil jusqu'à ce qu'au moins un coup ait été analysé avec un écart > 0.
    private(set) var worstMistakeSnapshot: BlomixWorstMistakeSnapshot? = nil

    // MARK: - Bonus de score (solo uniquement)

    /// N : total de blox entrés dans la grille (posés + lignes aléatoires).
    /// B : parmi N, combien sont des brix (priks).

    /// Bonus = excès de brix au-delà du nombre théorique (proba 1/8).
    /// Exemple : N=80, B=15 → théorique=10 → excès=5 → bonus=+5 pts.
    /// Toujours ≥ 0 (on ne pénalise pas un déficit de brix).
    /// Profondeur de combo **dans la résolution en cours** : 0 = première chaîne de la vague, puis +1 après chaque vague avec suppression (comme `chainSeriesLevel` dans `checkChains`).
    private var chainSeriesLevel: Int = 0

    /// Multijoueur temps réel (nil = solo, chemins PvP inactifs).
    private var pvpCoordinator: BlomixPvPMatchCoordinator?
    /// Vrai entre le moment où beginPvPWithMatch démarre et la fin du handshake (ou l'abandon).
    /// Protège contre la double-entrée : AutoSearcher.onMatch + lobby.onMatch peuvent se déclencher
    /// simultanément pour le même match → le second appel doit être ignoré.
    private var pvpMatchSetupInProgress = false
    /// Après une ligne d’attaque PvP, la ligne « tous les 10 coups » doit encore partir le même cycle si elle était due.
    private var pvpNeedsDecadeLineAfterAttackInjection = false
    /// Empêche de recalculer / resoumettre l’Elo plusieurs fois pour la même partie PvP.
    private var didFinalizePvPEloForCurrentMatch = false
    /// Nom affiché de l’adversaire courant pour le HUD et le résultat de match.
    private var pvpOpponentDisplayName: String?
    /// Dernier résultat Elo connu pour cette partie PvP.
    private var pvpLastEloResult: BlomixEloResult?
    /// Overlay de résultat actuellement présenté, pour mise à jour asynchrone de l’Elo.
    private weak var pvpPresentedResultViewController: BlomixPvPResultViewController?
    /// Profondeur de remplissage connue de la grille adverse (0 = vide, 8 = jusqu'en bas).
    private var pvpRemoteBoardFillDepth: Int = 0
    private var pvpRemoteScore: Int = 0

    // MARK: - Aide (Hint)
    /// Nombre d'aides restantes pour la partie en cours.
    private var hintsRemaining: Int = 5
    /// true si le joueur a tapé le bouton "?" mais que analyzerLookAhead était encore nil.
    private var pendingHintRequest: Bool = false

    // MARK: Ghost drop preview (appui maintenu → colonne grisée + bloc fantôme)
    /// Timer qui déclenche le mode ghost après `ghostHoldDelay` secondes.
    private var ghostHoldTimer: Timer?
    /// Colonne actuellement ciblée par le ghost (nil = pas de tracking actif).
    private var ghostPreviewColumn: Int?
    /// true tant que le doigt est posé sur la grille et que le drop n'a pas encore eu lieu.
    private var ghostTouchIsLive: Bool = false
    private static let ghostHoldDelay: TimeInterval = 0.12
    private static let ghostContainerName = "ghostDropContainer"

    // Visée bombe : appui maintenu sur la grille → overlay blast avant placement.
    private var bombAimTouchIsLive: Bool = false
    private var bombAimTargetCell: GridAddress? = nil

    // Bouton SpriteKit actuellement appuyé (animation press/release).
    private weak var lastPressedSKButton: BlomixSKButtonNode?

    // Action différée jusqu'à touchesEnded (comportement « fire on release »).
    private var pendingButtonAction: (() -> Void)?
    // Position du doigt lors de l'appui sur un bouton (pour détecter la sortie de zone).
    private var pendingButtonTouchOrigin: CGPoint?
    private static let bombBlastPreviewContainerName = "bombBlastPreviewContainer"

    // MARK: - Interactive Tutorial Mode

    private enum TutorialStep: Equatable {
        case intro            // Overlay 1 : animation doigt, attendre 2 drops
        case chainPrompt      // Overlay 2 : image chaîne, fournir des bleus jusqu'à chaîne
        case chainCelebration // Overlay 2b : "Super ! 5 = effacés !" (auto-dismiss)
        case awaitingBrix     // Pas d'overlay ; on attend que le brix devienne currentBlock
        case brixIntro        // Overlay 3 : explication Brix, fournir jaune jusqu'au décrément
        case brixCelebration  // Overlay 3b : "Super !" (auto-dismiss)
        case freePlay         // Pas d'overlay ; 2 drops libres avant la bombe
        case bombIntro        // Overlay 4 : animation bombe, attendre bomb drop
        case bombCelebration  // Overlay 4b : "Super ! Tu sais tout !" (auto-dismiss → magixIntro)
        case magixIntro       // Overlay 5  : les 3 blocs MAGIX + "Il y a encore des surprises…" (tap ou 3 s → sortie)
    }

    private static let tutorialOverlayName      = "tutoStepOverlay"
    private static let tutorialLineOverlayName  = "tutoLineOverlay"
    private static let tutorialSkipBtnName      = "tutoSkipBtn"
    private static let tutorialFreePlayDropsNeeded = 2

    private var isTutorialMode:       Bool          = false
    private var isZenMode:            Bool          = false
    private var tutorialStep:         TutorialStep  = .intro
    private var tutorialStepDrops:    Int           = 0
    private var tutorialBombUnlocked: Bool          = false
    private var tutorialPriksShown:   Bool          = false
    private var tutorialBlockQueue:   [BlockType]   = []
    private var tutorialLineShown:    Bool          = false   // overlay "1ère ligne" affiché une seule fois
    private var pendingTutorialStart: Bool          = false
    /// Vrai pendant toute la séquence unwindToStartScreen (teardown → reset → restore).
    /// Empêche willResignActiveNotification d'écraser la sauvegarde solo avec un état transitoire.
    private var isWindingDown: Bool = false

    // MARK: In-app update banner
    private static let updateBannerName    = "appUpdateBanner"
    private static let updateBannerCloseName = "appUpdateBannerClose"
    /// URL de la fiche App Store, disponible dès qu'une MAJ est détectée.
    private var updateStoreURL: URL?
    /// true une fois la vérification lancée (évite de rappeler l'API à chaque retour écran d'accueil).
    private var didCheckForUpdate = false

    /// Jonction Blox — arêtes horizontales / verticales (`H_ligne_colGauche`, `V_ligneHaute_colonne`).
    private var borderConnections: [String: SKShapeNode] = [:]
    /// Jonction Blox — diagonales (`D_r1_c1_r2_c2` lexicographique).
    private var diagonalConnections: [String: SKShapeNode] = [:]
    /// Incrémenté à chaque nouveau trait pour garder un ordre de superposition stable.
    private var bloxJunctionZCounter: CGFloat = 0

    /// Observer pour rafraîchir le libellé « GC: » après authentification Game Center.
    /// `nonisolated(unsafe)` : jeton `NotificationCenter` lu dans `deinit` (toujours `nonisolated`).
    nonisolated(unsafe) private var gameCenterAuthObserver: NSObjectProtocol?
    /// Rafraîchit grille / previews quand le skin couleur change (réglages).
    nonisolated(unsafe) private var skinChangeObserver: NSObjectProtocol?
    /// Rafraîchit la typographie globale visible dès que le joueur change de police.
    nonisolated(unsafe) private var fontChangeObserver: NSObjectProtocol?
    /// Son de tap pour les boutons UIKit (`BlomixUIButton`).
    nonisolated(unsafe) private var uiButtonTapObserver: NSObjectProtocol?
    /// Masque l'overlay statique juste avant la transition de fermeture d'un modal.
    nonisolated(unsafe) private var modalWillDismissObserver: NSObjectProtocol?
    /// Rejoue les animations d'accueil quand un modal se ferme vers l'écran d'accueil.
    nonisolated(unsafe) private var modalDismissObserver: NSObjectProtocol?

    deinit {
        if let observer = gameCenterAuthObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = skinChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = fontChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = uiButtonTapObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = modalWillDismissObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = modalDismissObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Cycle de vie

    /// Appelée lorsque la scène est ajoutée à un `SKView` — point d’entrée pour l’UI statique,
    /// les labels, le fond, et toute configuration qui ne dépend pas de la boucle `update`.
    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Pré-chauffe les Taptic Engines pour que les premiers retours soient immédiats.
        hapticEngine.prepare()
        hapticLightEngine.prepare()

        childNode(withName: Self.backgroundNodeName)?.removeFromParent()
        childNode(withName: Self.titleNodeName)?.removeFromParent()
        childNode(withName: Self.gameplaySubtitleUnderTitleName)?.removeFromParent()
        childNode(withName: Self.gridContainerName)?.removeFromParent()
        childNode(withName: Self.previewNodeName)?.removeFromParent()
        childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()
        childNode(withName: Self.gameOverOverlayName)?.removeFromParent()
        childNode(withName: Self.startScreenOverlayName)?.removeFromParent()
        childNode(withName: Self.bottomMenuContainerName)?.removeFromParent()

        addFullscreenBackground()

        soundBank.preloadAll()
        // Pré-chauffe le synthétiseur procédural sur un thread de fond pour éviter
        // le freeze au premier effet MAGIX (init AVAudioEngine coûteuse).
        DispatchQueue.global(qos: .userInitiated).async {
            _ = BlomixProceduralSFX.shared
        }
        BlomixMusicPlayer.shared.start()
        registerSoloSaveObserverIfNeeded()

        uiButtonTapObserver = NotificationCenter.default.addObserver(
            forName: .blomixButtonTap,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.playMatchSound(.connectE)
        }

        modalWillDismissObserver = NotificationCenter.default.addObserver(
            forName: .blomixModalWillDismiss,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isStartScreen else { return }
            // Masque immédiatement l'overlay statique : la transition modale (crossDissolve)
            // révèle ainsi le fond noir plutôt que l'accueil figé.
            self.childNode(withName: Self.startScreenOverlayName)?.alpha = 0
        }

        modalDismissObserver = NotificationCenter.default.addObserver(
            forName: .blomixModalDidDismiss,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.replayStartScreenIfNeeded()
        }
        BlomixAvailablePlayersManager.shared.setup()

        stopStageTimer()
        isProcessing = false
        isGameOver = false
        isStartScreen = true
        resetSessionModelForNewMatch()

        if didShowStudioSplash {
            presentStartScreenOrRestoreSoloSave()
        } else {
            didShowStudioSplash = true
            presentStudioSplashThenStartScreen()
        }

        setupGameCenterStatusLabelIfNeeded()
        layoutGameCenterStatusLabel()
        refreshGameCenterStatusLabelText()
        registerGameCenterAuthObserverIfNeeded()
        registerSkinChangeObserverIfNeeded()
        registerFontChangeObserverIfNeeded()

        if let inputView = view as? BlomixSKView {
            inputView.inputScene = self
            inputView.becomeFirstResponder()
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutGameCenterStatusLabel()
        layoutGameOverflowMenuIfNeeded()
        guard !isStartScreen else { return }
        layoutScoreLabel()
        layoutBombHUD()
        refreshUpcomingQueueSlots()
        refreshProgressHUDBars()
        layoutPvPTurnCountdownIfNeeded()
    }

    /// Remet le modèle de jeu à l’état initial (grille vide, score, bombes, etc.) — sans recréer l’UI gameplay.
    private func resetSessionModelForNewMatch() {
        isZenMode = false
        grid = Self.makeEmptyGrid()
        selectedColumn = 3
        currentBlock = nextPlayableBlockForSession()
        blockAfterCurrent = nextPlayableBlockForSession()
        blockTwoAhead = nextPlayableBlockForSession()
        moveCount = 0
        shouldRunPostPlacementHooks = false
        isInjectingBottomRandomLine = false
        nextBottomLine = nextBottomLineRowForSession()
        bombCount = pvpCoordinator == nil ? 5 : 3
        isBombMode = false
        chainClearWaveCount = 0
        score = 0
        lastScoreHundredMilestone = 0
        pendingMilestoneExplosion = .none
        displayedScore = 0
        scoreRollStart  = 0
        scoreRollTarget = 0
        gameOverFinalScore = 0
        chainSeriesLevel = 0
        currentStageIndex = 0
        stageTimerSecondsRemaining = Self.soloStages[0].timerSeconds
        pendingBottomLineBloopaSoundPlayedAtMoveCount = nil
        pvpIncomingAttackPreviewSoundPlayedForID = nil
        pvpNeedsDecadeLineAfterAttackInjection = false
        analyzerGeneration    &+= 1          // invalide tout résultat encore en vol
        analyzerLookAhead = nil
        analyzerPendingQuality = nil
        analyzerGameStats.reset()
        analyzerPreMoveGrid        = nil
        analyzerPreMoveBlock       = .empty
        analyzerPreMoveNext1       = .empty
        analyzerPreMoveNext2       = .empty
        analyzerPreMovePendingLine = nil
        worstMistakeSnapshot       = nil
        hintsRemaining  = 5
        pendingHintRequest = false
    }

    private func nextPlayableBlockForSession() -> BlockType {
        if isTutorialMode { return nextTutorialBlock() }
        return pvpCoordinator?.nextPlayableBlockForSharedMatch() ?? Self.randomNextPlayableBlock()
    }

    private func nextTutorialBlock() -> BlockType {
        guard !tutorialBlockQueue.isEmpty else { return Self.randomNextPlayableBlock() }
        return tutorialBlockQueue.removeFirst()
    }

    private func nextBottomLineRowForSession() -> [BlockType] {
        var row = pvpCoordinator?.nextRandomBottomLineForSharedMatch() ?? Self.generateNextRandomLineRowIndependentCells()
        // Pas de blocs Magix ni Priks dans les lignes qui montent en tutoriel.
        // Les blocs Magix ne doivent jamais apparaître dans les lignes du bas (effet trop brutal).
        row = row.map { block in
            switch block {
            case .magix:
                return Self.colorPalette.randomElement().map { .color($0) } ?? .color("red")
            case .priks where isTutorialMode:
                return Self.randomNextPlayableBlock()
            default:
                return block
            }
        }
        return row
    }

    // Style des chips : centralisé dans BlomixSKButtonNode (cornerRadius, padH, padV, defaultFontSize).

    /// Largeur et hauteur communes : le plus long des libellés (à `fontSize`) + marges, sans dépasser l’écran.
    private static func startScreenUnifiedChipSize(texts: [String], fontSize: CGFloat, maxOuterWidth: CGFloat) -> CGSize {
        let font = BlomixTypography.uiFont(size: fontSize, weight: .regular)
        var maxTW: CGFloat = 0
        var maxTH: CGFloat = 0
        for t in texts {
            let s = (t as NSString).size(withAttributes: [.font: font])
            maxTW = max(maxTW, ceil(s.width))
            maxTH = max(maxTH, ceil(s.height))
        }
        let w = min(maxOuterWidth, maxTW + BlomixSKButtonNode.padH * 2)
        let h = maxTH + BlomixSKButtonNode.padV * 2
        return CGSize(width: max(w, 88), height: max(h, 40))
    }

    /// Délègue à `BlomixSKButtonNode` : fond arrondi #232323 + bordure + libellé blanc Bitcount.
    private func makeStartScreenButtonChip(chipName: String, labelName: String, text: String, chipSize: CGSize, fontSize: CGFloat) -> BlomixSKButtonNode {
        BlomixSKButtonNode(name: chipName, labelName: labelName, text: text, size: chipSize, fontSize: fontSize)
    }

    private func sceneHitRectForStartScreenChip(named chipName: String, edgeSlop: CGFloat = 4) -> CGRect {
        guard let overlay = childNode(withName: Self.startScreenOverlayName),
              let chip = overlay.childNode(withName: chipName) else { return .zero }
        let box = chip.calculateAccumulatedFrame()
        let bl = overlay.convert(CGPoint(x: box.minX, y: box.minY), to: self)
        let tr = overlay.convert(CGPoint(x: box.maxX, y: box.maxY), to: self)
        let r = CGRect(
            x: min(bl.x, tr.x),
            y: min(bl.y, tr.y),
            width: abs(tr.x - bl.x),
            height: abs(tr.y - bl.y)
        )
        return r.insetBy(dx: -edgeSlop, dy: -edgeSlop)
    }

    private func presentStartScreenOrRestoreSoloSave() {
        if let save = BlomixSoloSaveManager.shared.load() {
            BlomixSoloSaveManager.shared.clear()
            isZenMode = save.isZenMode  // restauré avant restoreFromSoloSave pour isInStagedSoloMode
            restoreFromSoloSave(save)
        } else {
            presentStartScreen()
        }
    }

    /// Appelé par `GameViewController.viewDidAppear` au retour d'une modale.
    /// Reconstruit et rejoue les animations d'entrée uniquement si l'accueil est visible.
    func replayStartScreenIfNeeded() {
        guard isStartScreen else { return }
        presentStartScreen()
    }

    /// Fond noir plein écran, titre **BLOMIX**, sous-titre, **START** remonté, **Settings**, puis **Credits** (overlay).
    private func presentStartScreen() {
        childNode(withName: Self.startScreenOverlayName)?.removeFromParent()

        isStartScreen = true

        let overlay = SKNode()
        overlay.name = Self.startScreenOverlayName
        overlay.zPosition = 120
        addChild(overlay)

        let backdrop = SKSpriteNode(color: .black, size: size)
        backdrop.name = Self.startScreenBackdropName
        backdrop.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backdrop.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backdrop.zPosition = 0
        overlay.addChild(backdrop)

        let ambientBlocks = SKNode()
        ambientBlocks.name = Self.startScreenAmbientBlocksContainerName
        ambientBlocks.zPosition = 0.5
        overlay.addChild(ambientBlocks)
        startStartScreenAmbientBlocksAnimation(in: overlay)

        let startScreenVerticalLift = size.height * 0.25

        let title = SKLabelNode(text: "BLOMIX")
        title.name = Self.startScreenTitleLabelName
        title.fontName = Self.customUIFontPostScriptName
        title.fontSize = 40
        title.fontColor = .white
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.58 + startScreenVerticalLift)
        title.zPosition = 1
        overlay.addChild(title)

        let subtitle = SKLabelNode(text: BlomixL10n.gameTagline)
        subtitle.name = Self.startScreenSubtitleLabelName
        subtitle.fontName = Self.customUIFontPostScriptName
        subtitle.fontSize = 15
        subtitle.fontColor = .white
        subtitle.horizontalAlignmentMode = .center
        subtitle.verticalAlignmentMode = .center
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.58 - 44 + startScreenVerticalLift)
        subtitle.zPosition = 1
        overlay.addChild(subtitle)

        let playerNameLabel = SKLabelNode(text: BlomixL10n.startScreenPlayerName(GKLocalPlayer.local.displayName.isEmpty ? BlomixL10n.startScreenPlayerUnknown : GKLocalPlayer.local.displayName))
        playerNameLabel.name = Self.startScreenPlayerNameLabelName
        playerNameLabel.fontName = Self.customUIFontPostScriptName
        playerNameLabel.fontSize = 12
        playerNameLabel.fontColor = UIColor(white: 0.9, alpha: 1)
        playerNameLabel.horizontalAlignmentMode = .center
        playerNameLabel.verticalAlignmentMode = .center
        playerNameLabel.position = CGPoint(x: size.width / 2, y: subtitle.position.y - 26)
        playerNameLabel.zPosition = 1
        overlay.addChild(playerNameLabel)

        let playerEloLabel = SKLabelNode(text: BlomixL10n.startScreenPlayerEloUnavailable)
        playerEloLabel.name = Self.startScreenPlayerEloLabelName
        playerEloLabel.fontName = Self.customUIFontPostScriptName
        playerEloLabel.fontSize = 12
        playerEloLabel.fontColor = UIColor(white: 0.82, alpha: 1)
        playerEloLabel.horizontalAlignmentMode = .center
        playerEloLabel.verticalAlignmentMode = .center
        playerEloLabel.position = CGPoint(x: size.width / 2, y: playerNameLabel.position.y - 20)
        playerEloLabel.zPosition = 1
        overlay.addChild(playerEloLabel)
        refreshStartScreenPlayerIdentityIfVisible()

        let startLift = GridLayout.cellPoints * 4.5
        let labelGap: CGFloat = 14
        let maxChipOuter = size.width - 32
        let chipFont = BlomixUIDestinationButtonStyle.navigationTitleFontSize
        let chipTitles = [
            BlomixL10n.startButton,
            BlomixL10n.startPvPButton,
            BlomixL10n.menuScores,
            BlomixL10n.menuTutorial,
            BlomixL10n.settings,
            BlomixL10n.credits,
        ]
        let chipSize = Self.startScreenUnifiedChipSize(texts: chipTitles, fontSize: chipFont, maxOuterWidth: maxChipOuter)
        let hChip = chipSize.height

        let startY = size.height * 0.12 + startLift + startScreenVerticalLift

        // ── Disques de classement (SOLO / MOY. / ZEN) ───────────────────────────
        // Trois disques animés (style MAGIX) centrés dans l'espace vertical entre
        // le label Elo et le premier bouton.  Chaque disque démarre alpha=0 et
        // se révèle indépendamment dès que son fetch Game Center retourne.
        let discDiameter: CGFloat = 60
        let discGap:      CGFloat = 14          // espace entre les bords des disques
        let discCenterY = (playerEloLabel.position.y + startY + chipSize.height / 2) / 2 - 4
        let discStep = discDiameter + discGap   // pas centre-à-centre
        let discCx   = size.width / 2

        let discsContainer = SKNode()
        discsContainer.name      = Self.startScreenRankDiscsContainerName
        discsContainer.position  = CGPoint(x: discCx, y: discCenterY)
        discsContainer.zPosition = 1
        overlay.addChild(discsContainer)

        // Les 3 offsets de phase (0.0 / 0.33 / 0.67) désynchronisent l'ondulation
        // de couleur entre les disques tout en couvrant le cycle complet de la palette.
        let soloDisc = Self.makeRankDiscNode(name: Self.startScreenRankDiscSoloName,
                                             category: "SOLO",
                                             discDiameter: discDiameter,
                                             timeOffset: 0.0)
        soloDisc.position = CGPoint(x: -discStep, y: 0)
        soloDisc.alpha    = 0
        discsContainer.addChild(soloDisc)

        let avgDisc = Self.makeRankDiscNode(name: Self.startScreenRankDiscAvgName,
                                            category: "MOY.",
                                            discDiameter: discDiameter,
                                            timeOffset: 0.33)
        avgDisc.position = CGPoint(x: 0, y: 0)
        avgDisc.alpha    = 0
        discsContainer.addChild(avgDisc)

        let zenDisc = Self.makeRankDiscNode(name: Self.startScreenRankDiscZenName,
                                            category: "ZEN",
                                            discDiameter: discDiameter,
                                            timeOffset: 0.67)
        zenDisc.position = CGPoint(x: discStep, y: 0)
        zenDisc.alpha    = 0
        discsContainer.addChild(zenDisc)
        // ─────────────────────────────────────────────────────────────────────────

        // Décale les boutons vers le bas d'un écart supplémentaire égal à l'espacement
        // inter-boutons, pour aérer l'espace sous les disques de ranking.
        var cy = startY - (hChip + labelGap) / 2
        let cx = size.width / 2

        let startChip = makeStartScreenButtonChip(
            chipName: Self.startScreenStartChipName,
            labelName: Self.startScreenStartLabelName,
            text: BlomixL10n.startButton,
            chipSize: chipSize,
            fontSize: chipFont
        )
        startChip.position = CGPoint(x: cx, y: cy)
        startChip.zPosition = 2
        overlay.addChild(startChip)

        cy -= hChip / 2 + labelGap + hChip / 2
        let pvpChip = makeStartScreenButtonChip(
            chipName: Self.startScreenPvPChipName,
            labelName: Self.startScreenPvPLabelName,
            text: BlomixL10n.startPvPButton,
            chipSize: chipSize,
            fontSize: chipFont
        )
        pvpChip.position = CGPoint(x: cx, y: cy)
        pvpChip.zPosition = 2
        overlay.addChild(pvpChip)

        cy -= hChip / 2 + labelGap + hChip / 2
        let zenChip = makeStartScreenButtonChip(
            chipName: Self.startScreenZenChipName,
            labelName: Self.startScreenZenLabelName,
            text: BlomixL10n.zenButton,
            chipSize: chipSize,
            fontSize: chipFont
        )
        zenChip.position = CGPoint(x: cx, y: cy)
        zenChip.zPosition = 2
        overlay.addChild(zenChip)

        cy -= hChip / 2 + labelGap + hChip / 2
        let scoresChip = makeStartScreenButtonChip(
            chipName: Self.startScreenScoresChipName,
            labelName: Self.startScreenScoresLabelName,
            text: BlomixL10n.menuScores,
            chipSize: chipSize,
            fontSize: chipFont
        )
        scoresChip.position = CGPoint(x: cx, y: cy)
        scoresChip.zPosition = 2
        overlay.addChild(scoresChip)

        cy -= hChip / 2 + labelGap + hChip / 2
        let rulesChip = makeStartScreenButtonChip(
            chipName: Self.startScreenRulesChipName,
            labelName: Self.startScreenRulesLabelName,
            text: BlomixL10n.menuTutorial,
            chipSize: chipSize,
            fontSize: chipFont
        )
        rulesChip.position = CGPoint(x: cx, y: cy)
        rulesChip.zPosition = 2
        overlay.addChild(rulesChip)

        cy -= hChip / 2 + labelGap + hChip / 2
        let settingsChip = makeStartScreenButtonChip(
            chipName: Self.startScreenSettingsChipName,
            labelName: Self.startScreenSettingsLabelName,
            text: BlomixL10n.settings,
            chipSize: chipSize,
            fontSize: chipFont
        )
        settingsChip.position = CGPoint(x: cx, y: cy)
        settingsChip.zPosition = 2
        overlay.addChild(settingsChip)

        // --- Conseil du jour (sous le dernier bouton) ---
        // Vide le pool pour recharger dans la bonne langue et piocher un nouveau conseil.
        tipOfDayPool = []
        lastTipIndex = -1

        let tipGap: CGFloat = 28
        let tipContainerY = cy - hChip / 2 - tipGap

        let tipContainer = SKNode()
        tipContainer.name = Self.startScreenTipContainerName
        tipContainer.position = CGPoint(x: cx, y: tipContainerY)
        tipContainer.zPosition = 2
        tipContainer.alpha = 0  // démarre invisible, fade-in ci-dessous

        let tipHeader = SKLabelNode(text: BlomixL10n.startScreenTipHeader)
        tipHeader.fontName = Self.customUIFontPostScriptName
        tipHeader.fontSize = 9
        tipHeader.fontColor = UIColor(white: 0.45, alpha: 1)
        tipHeader.horizontalAlignmentMode = .center
        tipHeader.verticalAlignmentMode = .center
        tipHeader.position = .zero
        tipContainer.addChild(tipHeader)

        let tipTextLabel = SKLabelNode()
        tipTextLabel.name = Self.startScreenTipTextLabelName
        tipTextLabel.horizontalAlignmentMode = .center
        tipTextLabel.verticalAlignmentMode = .top
        tipTextLabel.numberOfLines = 0
        tipTextLabel.preferredMaxLayoutWidth = size.width - 48
        tipTextLabel.attributedText = Self.tipAttributedString(pickNextTip().text)
        tipTextLabel.position = CGPoint(x: 0, y: -16)
        tipContainer.addChild(tipTextLabel)

        overlay.addChild(tipContainer)
        // Fade-in avec un léger délai pour que la phrase apparaisse doucement à chaque affichage.
        tipContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.4),
            SKAction.fadeIn(withDuration: 0.5),
        ]))

        // Rotation automatique toutes les 5 s — accrochée sur l'overlay qui est détruit à la sortie.
        let tipRotation = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 5),
            SKAction.run { [weak self, weak overlay] in
                guard let self, let overlay else { return }
                self.rotateTipInStartScreen(in: overlay)
            },
        ]))
        overlay.run(tipRotation, withKey: "tipRotation")

        // Vérifie si une mise à jour App Store est disponible et affiche la bannière le cas échéant.
        checkAndShowUpdateBannerIfNeeded(in: overlay)

        // ── Animations d'entrée ──────────────────────────────────────────────────────

        // Titre BLOMIX : effet slot machine — chaque lettre défile à travers des caractères
        // aléatoires avant de se stabiliser sur la bonne, en cascade de gauche à droite.
        // Chaque lettre reçoit une couleur unique tirée du skin actif du joueur.
        title.alpha = 0
        title.setScale(1)
        let slotCorrect    = Array("BLOMIX")
        let slotAlphabet   = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let slotSeqLen     = 32
        let slotDuration: TimeInterval = 2.0
        let slotSettleAt: [Double]     = [0.70, 0.75, 0.80, 0.85, 0.90, 0.95]
        let slotTotalSteps = Double(slotSeqLen - 1)
        // Séquences aléatoires pré-générées — différentes à chaque apparition.
        let slotSeqs: [[Character]] = slotCorrect.map { _ in
            (0..<slotSeqLen).map { _ in slotAlphabet.randomElement()! }
        }
        // Palette mélangée : 1 couleur skin unique par lettre (couleur finale après settle).
        let slotPaletteKeys = ["blue", "red", "purple", "yellow", "green", "orange"].shuffled()
        let slotColors: [UIColor] = slotPaletteKeys.prefix(slotCorrect.count).map { key in
            Self.bloxSolidFillColor(forNormalizedKey: key) ?? .white
        }
        // Séquences de couleurs aléatoires — changent en même temps que les caractères.
        let slotColorSeqs: [[UIColor]] = slotCorrect.map { _ in
            (0..<slotSeqLen).map { _ in slotColors.randomElement()! }
        }
        let slotUIFont = UIFont(name: Self.customUIFontPostScriptName, size: 40)
                      ?? UIFont.systemFont(ofSize: 40)
        title.run(SKAction.customAction(withDuration: slotDuration) { node, elapsed in
            guard let label = node as? SKLabelNode else { return }
            // Fade-in rapide sur les 130 premières ms.
            label.alpha = CGFloat(min(Double(elapsed) / 0.13, 1.0))
            let t = Double(elapsed) / slotDuration
            let attrStr = NSMutableAttributedString()
            for i in 0..<slotCorrect.count {
                let sp = slotSettleAt[i]
                let char: Character
                let color: UIColor
                if t >= sp {
                    // Lettre et couleur stabilisées.
                    char  = slotCorrect[i]
                    color = slotColors[i]
                } else {
                    // Ease-out quadratique : caractère et couleur changent ensemble.
                    let stepIdx = min(Int(slotTotalSteps * (1.0 - pow(1.0 - t / sp, 2.0))), slotSeqLen - 1)
                    char  = slotSeqs[i][stepIdx]
                    color = slotColorSeqs[i][stepIdx]
                }
                attrStr.append(NSAttributedString(
                    string: String(char),
                    attributes: [.foregroundColor: color, .font: slotUIFont]
                ))
            }
            label.attributedText = attrStr
        })

        // Sous-titre + labels joueur : fade-in décalé.
        subtitle.alpha        = 0
        playerNameLabel.alpha = 0
        playerEloLabel.alpha  = 0
        subtitle.run(.sequence([.wait(forDuration: 0.18), .fadeIn(withDuration: 0.22)]))
        playerNameLabel.run(.sequence([.wait(forDuration: 0.23), .fadeIn(withDuration: 0.22)]))
        playerEloLabel.run(.sequence([.wait(forDuration: 0.28), .fadeIn(withDuration: 0.22)]))

        // Boutons : stagger de bas en haut (le bouton le plus bas apparaît en premier).
        // Ordre des chips dans l'écran, du bas vers le haut :
        // settings → rules → scores → zen → pvp → start
        let staggeredChips: [(chip: BlomixSKButtonNode, delay: TimeInterval)] = [
            (settingsChip, 0.10),
            (rulesChip,    0.16),
            (scoresChip,   0.22),
            (zenChip,      0.28),
            (pvpChip,      0.34),
            (startChip,    0.40),
        ]
        let chipSlideDistance: CGFloat = 14   // décalage initial vers le bas (pts)

        for (chip, delay) in staggeredChips {
            chip.alpha = 0
            chip.setScale(0)
            chip.position.y -= chipSlideDistance   // point de départ légèrement sous la position finale

            // Phase 1 : scale-in 0→1.15 + remontée + fade-in.
            let cP1 = SKAction.group([
                { let a = SKAction.scale(to: 1.15, duration: 0.18); a.timingMode = .easeOut; return a }(),
                SKAction.moveBy(x: 0, y: chipSlideDistance, duration: 0.16),
                SKAction.fadeIn(withDuration: 0.12),
            ])
            // Phase 2 : rebond settle 1.15→1.0.
            let cP2: SKAction = {
                let a = SKAction.scale(to: 1.0, duration: 0.10)
                a.timingMode = .easeInEaseOut
                return a
            }()
            chip.run(.sequence([.wait(forDuration: delay), cP1, cP2]))
        }

        // Si le joueur avait cliqué "Tutoriel" depuis une partie en cours, on le lance maintenant.
        if pendingTutorialStart {
            pendingTutorialStart = false
            run(SKAction.wait(forDuration: 0.3)) { [weak self] in self?.startTutorialGameWithIntro() }
        }
    }

    private func startStartScreenAmbientBlocksAnimation(in overlay: SKNode) {
        startAmbientBlocksAnimation(
            in: overlay,
            containerName: Self.startScreenAmbientBlocksContainerName,
            actionKey: Self.startScreenAmbientBlocksSpawnActionKey
        )
    }

    /// Version générique réutilisée par l'écran d'accueil ET l'overlay game over.
    private func startAmbientBlocksAnimation(in overlay: SKNode, containerName: String, actionKey: String) {
        overlay.removeAction(forKey: actionKey)

        func scheduleNextSpawn(on overlay: SKNode) {
            let wait = SKAction.wait(forDuration: Double.random(in: 0...2))
            let spawn = SKAction.run { [weak self, weak overlay] in
                guard let self, let overlay else { return }
                guard overlay.parent != nil else { return }
                self.spawnAmbientBlock(in: overlay, containerName: containerName)
                scheduleNextSpawn(on: overlay)
            }
            overlay.run(SKAction.sequence([wait, spawn]), withKey: actionKey)
        }

        scheduleNextSpawn(on: overlay)
    }

    private func spawnAmbientStartScreenBlock(in overlay: SKNode) {
        spawnAmbientBlock(in: overlay, containerName: Self.startScreenAmbientBlocksContainerName)
    }

    private func spawnAmbientBlock(in overlay: SKNode, containerName: String) {
        guard let container = overlay.childNode(withName: containerName) else { return }

        let miniSize = CGSize(width: 18, height: 18)
        let colorKey = Self.startScreenAmbientBlockColorKeys.randomElement() ?? "red"
        let block = SKSpriteNode(
            color: Self.bloxSolidFillColor(forNormalizedKey: colorKey) ?? SKColor(white: 0.45, alpha: 1),
            size: miniSize
        )
        block.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        block.alpha = 0.92
        block.zPosition = 0

        let horizontalInset = miniSize.width / 2 + 8
        let x = CGFloat.random(in: horizontalInset...(size.width - horizontalInset))
        let startY = -miniSize.height
        let endY = size.height + miniSize.height
        block.position = CGPoint(x: x, y: startY)
        container.addChild(block)

        // Même base que la montée des blox pendant la partie (~40 pt en 0,4 s),
        // avec une variation aléatoire entre 1/3x et 3x pour l’ambiance d’accueil.
        let basePointsPerSecond = GridLayout.cellPoints / 0.4
        let speedMultiplier = CGFloat.random(in: (1.0 / 3.0)...3.0)
        let pointsPerSecond = basePointsPerSecond * speedMultiplier
        let distance = endY - startY
        let duration = TimeInterval(distance / pointsPerSecond)
        let move = SKAction.moveTo(y: endY, duration: duration)
        move.timingMode = .linear
        let cleanup = SKAction.removeFromParent()
        block.run(SKAction.sequence([move, cleanup]))
    }

    /// Splash court du studio (fond noir + logo), puis ecran titre habituel.
    private func presentStudioSplashThenStartScreen() {
        childNode(withName: Self.studioSplashOverlayName)?.removeFromParent()

        let overlay = SKNode()
        overlay.name = Self.studioSplashOverlayName
        overlay.zPosition = 180
        addChild(overlay)

        let backdrop = SKSpriteNode(color: .black, size: size)
        backdrop.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backdrop.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backdrop.alpha = 1.0
        overlay.addChild(backdrop)

        // Pré-chauffe les 3 shaders des disques de ranking pendant le splash.
        // Chaque timeOffset produit un source GLSL distinct → Metal doit compiler 3 programmes.
        // Les sprites sont hors-écran (alpha 0.01, position négative) mais rendus,
        // ce qui déclenche la compilation GPU avant l'affichage de l'écran d'accueil.
        for (i, offset) in [Float(0.0), Float(0.33), Float(0.67)].enumerated() {
            let w = SKSpriteNode(texture: Self.magixShaderBaseTexture,
                                 size: CGSize(width: 2, height: 2))
            w.shader    = Self.makeMagixPaletteShader(timeOffset: offset)
            w.position  = CGPoint(x: -1000, y: -1000 - CGFloat(i) * 3)
            w.alpha     = 0.01
            w.zPosition = -200
            overlay.addChild(w)
        }

        // Crée le logo via SKSpriteNode(imageNamed:) pour conserver le comportement
        // de sizing d'origine (gestion x1/x2/x3 identique à avant).
        let logo = SKSpriteNode(imageNamed: Self.studioLogoAssetName)
        guard logo.texture != nil else {
            overlay.removeFromParent()
            presentStartScreenOrRestoreSoloSave()
            return
        }

        logo.position = CGPoint(x: size.width / 2, y: size.height / 2)
        logo.zPosition = 1
        logo.alpha = 0
        logo.setScale(1.0)

        let maxWidth  = size.width  * 0.62
        let maxHeight = size.height * 0.26
        let textureSize = logo.texture?.size() ?? CGSize(width: 1, height: 1)
        let fitRatio = min(maxWidth / max(1, textureSize.width), maxHeight / max(1, textureSize.height))
        logo.size = CGSize(width: textureSize.width * fitRatio, height: textureSize.height * fitRatio)
        overlay.addChild(logo)

        // Pré-charge les deux textures pour les hard-cuts de l'effet néon.
        let texOn     = logo.texture!
        let texOff    = SKTexture(imageNamed: Self.studioLogoOffAssetName)
        let hasOffTex = texOff.size().width > 2   // texture valide si > 1x1 placeholder
        // Taille figée une fois pour toutes (evite tout recalcul inattendu de SpriteKit).
        let fixedSize = logo.size

        // Démarre sur la texture "éteinte" si disponible.
        if hasOffTex {
            logo.texture = texOff
            logo.size    = fixedSize   // force explicitement, au cas où
        }

        // Actions de swap robustes : on impose texture ET taille ensemble via run{}.
        // setTexture(resize:false) peut recalculer la taille sur certaines versions de SpriteKit.
        let switchOn: SKAction = .run { [weak logo] in
            logo?.texture = texOn
            logo?.size    = fixedSize
        }
        let switchOff: SKAction = hasOffTex
            ? .run { [weak logo] in
                logo?.texture = texOff
                logo?.size    = fixedSize
            }
            : .run {}   // si texOff absent les phases "éteint" ne font rien

        // Séquence "néon qui s'allume" : clignotements irréguliers, rythme légèrement ralenti.
        let sequence = SKAction.sequence([
            SKAction.fadeAlpha(to: 1.0, duration: 0.08),   // apparition douce sur éteint
            SKAction.wait(forDuration: 0.65),               // pause éteint
            switchOn,  SKAction.wait(forDuration: 0.10),    // flash 1
            switchOff, SKAction.wait(forDuration: 0.09),
            switchOn,  SKAction.wait(forDuration: 0.14),    // flash 2
            switchOff, SKAction.wait(forDuration: 0.11),
            switchOn,  SKAction.wait(forDuration: 0.18),    // flash 3 (plus long)
            switchOff, SKAction.wait(forDuration: 0.09),
            switchOn,  SKAction.wait(forDuration: 0.65),    // stable allumé
            SKAction.fadeOut(withDuration: 0.28),
            SKAction.run { [weak self, weak overlay] in
                overlay?.removeFromParent()
                self?.presentStartScreenOrRestoreSoloSave()
            },
        ])
        logo.run(sequence)
    }

    /// Démarre la partie après **START** : masque l’accueil, construit l’UI jeu, joue `begin.wav`.
    private func beginNewMatchFromStartScreen() {
        guard isStartScreen else { return }

        // Premier lancement : démarrer le tutoriel interactif à la place d'une partie normale.
        if !isTutorialMode && !UserDefaults.standard.hasSeenInteractiveTutorial {
            startTutorialGameWithIntro()
            return
        }

        cancelGhostPreview()
        // En mode tutoriel : on conserve la sauvegarde de la partie précédente (restaurée à la fin du tuto).
        if !isTutorialMode { BlomixSoloSaveManager.shared.clear() }
        childNode(withName: Self.startScreenOverlayName)?.removeFromParent()
        isStartScreen = false
        hapticSoft()

        resetSessionModelForNewMatch()

        addTopTitle()
        setupBombHUD()
        setupScoreHUD()
        drawGrid()
        updatePreviewSprite()
        ensureGameOverflowMenuIfNeeded()
        layoutGameOverflowMenuIfNeeded()
        setGameplayNodesHidden(false)

        soundBank.play(.begin)
        refreshGameCenterStatusLabelText()

        NotificationCenter.default.post(name: .blomixDidBeginGameplayMatch, object: self)

        // Mode solo (hors tutoriel) : overlay Stage 1 + démarrage du timer.
        if isInStagedSoloMode {
            startStagedSoloSession()
        }
    }

    /// Lance une partie en mode Zen (sans timer, sans niveaux) depuis l’écran d’accueil.
    private func beginZenModeFromStartScreen() {
        guard isStartScreen else { return }

        cancelGhostPreview()
        BlomixSoloSaveManager.shared.clear()
        childNode(withName: Self.startScreenOverlayName)?.removeFromParent()
        isStartScreen = false
        hapticSoft()

        resetSessionModelForNewMatch()
        isZenMode = true  // activé après reset pour ne pas être écrasé

        addTopTitle()
        setupBombHUD()
        setupScoreHUD()
        drawGrid()
        updatePreviewSprite()
        ensureGameOverflowMenuIfNeeded()
        layoutGameOverflowMenuIfNeeded()
        setGameplayNodesHidden(false)

        soundBank.play(.begin)
        refreshGameCenterStatusLabelText()

        NotificationCenter.default.post(name: .blomixDidBeginGameplayMatch, object: self)

        startZenSession()
    }

    /// Affiche l’overlay d’intro Zen puis démarre la musique Stage 1 en boucle.
    private func startZenSession() {
        guard isZenMode else { return }
        showTransitionOverlay(
            levelPrefix: "Zen",
            stageLevelText: "Mode",
            line1: "tranquille",
            line2: ""
        ) { [weak self] in
            guard let self else { return }
            BlomixMusicPlayer.shared.switchToFile(Self.soloStages[0].musicFilename)
        }
    }

    /// Masque ou affiche grille, preview, HUD et titre (écran d’accueil / retour menu).
    private func setGameplayNodesHidden(_ hidden: Bool) {
        childNode(withName: Self.titleNodeName)?.isHidden = hidden
        childNode(withName: Self.gameplaySubtitleUnderTitleName)?.isHidden = hidden
        childNode(withName: Self.gridContainerName)?.isHidden = hidden
        childNode(withName: Self.previewNodeName)?.isHidden = hidden
        childNode(withName: Self.bombHudIconName)?.isHidden = hidden
        childNode(withName: Self.bombHudCountLabelName)?.isHidden = hidden
        childNode(withName: Self.upcomingSlotTwoAheadName)?.isHidden = hidden
        childNode(withName: Self.upcomingSlotNextName)?.isHidden = hidden
        childNode(withName: Self.upcomingQueueCaptionLabelName)?.isHidden = hidden
        childNode(withName: Self.scoreHudLabelName)?.isHidden = hidden
        childNode(withName: Self.bestScoreAboveName)?.isHidden = hidden || pvpCoordinator != nil
        childNode(withName: Self.hudTimerCaptionName)?.isHidden = hidden || isZenMode
        // Compteur LIGNE
        childNode(withName: Self.ligneCaptionName)?.isHidden = hidden
        childNode(withName: Self.ligneValueName)?.isHidden = hidden
        childNode(withName: Self.bottomLinePreviewStripName)?.isHidden = hidden
        childNode(withName: Self.bottomMenuContainerName)?.isHidden = hidden
        if let stageLbl = childNode(withName: Self.stageTimerHudName) as? SKLabelNode {
            stageLbl.isHidden = hidden || !isInStagedSoloMode
        }
        if let badge = childNode(withName: Self.stageBadgeNodeName) as? SKLabelNode {
            badge.isHidden = hidden || !isInStagedSoloMode
        }
        if let pvpTimer = childNode(withName: Self.hudPvPTurnTimerName) as? SKLabelNode {
            pvpTimer.isHidden = hidden || pvpCoordinator == nil
        }
        if let pvpOpponent = childNode(withName: Self.hudPvPOpponentName) as? SKLabelNode {
            pvpOpponent.isHidden = hidden || pvpCoordinator == nil
        }
        if hidden { closeGameOverflowMenu() }
    }

    private func playMatchSound(_ sfx: BlomixMatchSFX, playbackRate: Float = 1.0) {
        soundBank.play(sfx, playbackRate: playbackRate)
    }

    /// Son de chaîne : sans cascade (`chainSeriesLevel == 0`), selon la taille de la **plus grande** chaîne de la vague (5 → `chain_new`, 6–8 → `-1`, ≥9 → `-2`). En cascade, inchangé : 1ʳᵉ cascade → `-1`, suivantes → `-2`.
    private func playChainClearSound(largestChainSizeInWave: Int) {
        let sfx: BlomixMatchSFX
        switch chainSeriesLevel {
        case 0:
            switch largestChainSizeInWave {
            case 5: sfx = .chainNew
            case 6...8: sfx = .chainNewCascade1
            default: sfx = .chainNewCascade2 // ≥ 9 (les chaînes valides font au moins 5)
            }
        case 1: sfx = .chainNewCascade1
        default: sfx = .chainNewCascade2
        }
        playMatchSound(sfx, playbackRate: 1.0)
    }

    /// Son d'arrivée après une pose normale, selon la taille de la composante 8-connexe créée par le blox posé.
    /// Les chaînes (>= 5) laissent la priorité au son de suppression, donc aucun son d'arrivée n'est joué ici.
    private func landingSoundForPlacedBlock(_ placedBlock: BlockType, at address: GridAddress) -> BlomixMatchSFX? {
        if case .magix = placedBlock { return .magix }
        guard case .color(let colorName) = placedBlock else { return .place }
        var visited = Set<GridAddress>()
        let component = collectColorComponent8(start: address, colorName: colorName, globallyVisited: &visited)
        switch component.count {
        case 2:
            return .connectE
        case 3:
            return .connectF
        case 4:
            return .connectGb
        case 5...:
            return nil
        default:
            return .place
        }
    }

    /// Zone tactile élargie autour d’un `SKLabelNode` exprimée en coordonnées **scène**.
    private func sceneHitRect(for label: SKLabelNode, minWidth: CGFloat = 160, minHeight: CGFloat = 48, padding: CGFloat = 20) -> CGRect {
        guard let parent = label.parent else { return .zero }
        let center = convert(label.position, from: parent)
        let w = max(label.frame.width + padding * 2, minWidth)
        let h = max(label.frame.height + padding * 2, minHeight)
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    private func touchHitsStartButton(_ scenePoint: CGPoint) -> Bool {
        sceneHitRectForStartScreenChip(named: Self.startScreenStartChipName).contains(scenePoint)
    }

    private func touchHitsStartScreenSettingsButton(_ scenePoint: CGPoint) -> Bool {
        sceneHitRectForStartScreenChip(named: Self.startScreenSettingsChipName).contains(scenePoint)
    }

    private func touchHitsStartScreenScoresButton(_ scenePoint: CGPoint) -> Bool {
        sceneHitRectForStartScreenChip(named: Self.startScreenScoresChipName).contains(scenePoint)
    }

    private func touchHitsStartScreenCreditsButton(_ scenePoint: CGPoint) -> Bool {
        sceneHitRectForStartScreenChip(named: Self.startScreenCreditsChipName).contains(scenePoint)
    }

    private func touchHitsStartScreenZenButton(_ scenePoint: CGPoint) -> Bool {
        sceneHitRectForStartScreenChip(named: Self.startScreenZenChipName).contains(scenePoint)
    }

    private func touchHitsStartScreenPvPButton(_ scenePoint: CGPoint) -> Bool {
        sceneHitRectForStartScreenChip(named: Self.startScreenPvPChipName).contains(scenePoint)
    }

    private func touchHitsStartScreenRulesButton(_ scenePoint: CGPoint) -> Bool {
        sceneHitRectForStartScreenChip(named: Self.startScreenRulesChipName).contains(scenePoint)
    }

    private func touchHitsGameOverRestartButton(_ scenePoint: CGPoint) -> Bool {
        guard let overlay = childNode(withName: Self.gameOverOverlayName),
              let node = overlay.childNode(withName: Self.gameOverRestartLabelName) else { return false }
        return sceneHitRectForGameOverButton(node).contains(scenePoint)
    }

    private func touchHitsGameOverLeaderboardButton(_ scenePoint: CGPoint) -> Bool {
        guard let overlay = childNode(withName: Self.gameOverOverlayName),
              let node = overlay.childNode(withName: Self.gameOverLeaderboardLabelName) else { return false }
        return sceneHitRectForGameOverButton(node).contains(scenePoint)
    }

    private func touchHitsGameOverWorstMoveButton(_ scenePoint: CGPoint) -> Bool {
        guard let overlay = childNode(withName: Self.gameOverOverlayName),
              let node = overlay.childNode(withName: Self.gameOverWorstMoveButtonName) else { return false }
        return sceneHitRectForGameOverButton(node).contains(scenePoint)
    }

    /// Hit-rect pour les boutons du game over (fonctionne avec SKLabelNode et BlomixSKButtonNode).
    private func sceneHitRectForGameOverButton(_ node: SKNode, minW: CGFloat = 180, minH: CGFloat = 44) -> CGRect {
        guard let parent = node.parent else { return .zero }
        let box    = node.calculateAccumulatedFrame()
        let center = convert(CGPoint(x: box.midX, y: box.midY), from: parent)
        let w = max(box.width,  minW)
        let h = max(box.height, minH)
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    // MARK: - Game Center (test / HUD)

    private func setupGameCenterStatusLabelIfNeeded() {
        guard childNode(withName: Self.gameCenterStatusLabelName) == nil else { return }
        let label = SKLabelNode(text: BlomixL10n.gcStatusChecking)
        label.name = Self.gameCenterStatusLabelName
        label.fontName = Self.customUIFontPostScriptName
        label.fontSize = 11
        label.fontColor = .white
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .center
        label.zPosition = 130
        addChild(label)
    }

    private func layoutGameCenterStatusLabel() {
        guard let label = childNode(withName: Self.gameCenterStatusLabelName) as? SKLabelNode else { return }
        let margin: CGFloat = 12
        let liftGameplayCluster = 2 * GridLayout.cellPoints
        label.position = CGPoint(x: size.width - margin, y: size.height - margin + liftGameplayCluster)
    }

    private func refreshGameCenterStatusLabelText() {
        Task { @MainActor in
            let ok = GKLocalPlayer.local.isAuthenticated
            let text = ok ? BlomixL10n.gcStatusOk : BlomixL10n.gcStatusOff
            (self.childNode(withName: Self.gameCenterStatusLabelName) as? SKLabelNode)?.text = text
            self.refreshStartScreenPlayerIdentityIfVisible()
            self.refreshBestScoreHUDIfNeeded()
        }
    }

    private func applyBestScoreHUDValue(_ value: Int, isLiveBeat: Bool = false) {
        hudBestScoreValue = max(0, value)
        guard let n = childNode(withName: Self.bestScoreAboveName) as? SKLabelNode else { return }
        n.text = "\(hudBestScoreValue)"
        let green = SKColor(red: 0.20, green: 0.85, blue: 0.35, alpha: 1)
        let gray  = SKColor(red: 0xA3/255.0, green: 0xA3/255.0, blue: 0xA3/255.0, alpha: 1)
        n.fontColor = isLiveBeat ? green : gray
    }

    private func refreshBestScoreHUDIfNeeded() {
        guard childNode(withName: Self.bestScoreAboveName) != nil else { return }

        let localBest = isZenMode
            ? ScoreManager.shared.getLocalZenHighScore()
            : ScoreManager.shared.getLocalHighScore()
        let fallbackLocalBest = max(localBest, score, hudBestScoreValue)
        applyBestScoreHUDValue(fallbackLocalBest)

        bestScoreFetchGeneration += 1
        let generation = bestScoreFetchGeneration
        guard ScoreManager.shared.isAuthenticated else { return }

        let leaderboardID = isZenMode ? ScoreManager.zenLeaderboardID : ScoreManager.mainLeaderboardID
        ScoreManager.shared.fetchLocalPlayerBestScore(leaderboardID: leaderboardID) { [weak self] result in
            guard let self else { return }
            guard generation == self.bestScoreFetchGeneration else { return }
            let localFallback = self.isZenMode
                ? ScoreManager.shared.getLocalZenHighScore()
                : ScoreManager.shared.getLocalHighScore()
            switch result {
            case .success(let best):
                let resolved = max(best ?? 0, localFallback, self.score)
                self.applyBestScoreHUDValue(resolved)
            case .failure:
                let resolved = max(localFallback, self.score, self.hudBestScoreValue)
                self.applyBestScoreHUDValue(resolved)
            }
        }
    }


    private func refreshStartScreenPlayerIdentityIfVisible() {
        guard isStartScreen else { return }
        guard let overlay = childNode(withName: Self.startScreenOverlayName) else { return }
        guard let playerNameLabel = overlay.childNode(withName: Self.startScreenPlayerNameLabelName) as? SKLabelNode,
              let playerEloLabel = overlay.childNode(withName: Self.startScreenPlayerEloLabelName) as? SKLabelNode else { return }

        let displayName = GKLocalPlayer.local.displayName.isEmpty ? BlomixL10n.startScreenPlayerUnknown : GKLocalPlayer.local.displayName
        playerNameLabel.text = BlomixL10n.startScreenPlayerName(displayName)
        playerEloLabel.text = BlomixL10n.startScreenPlayerEloUnavailable

        guard GKLocalPlayer.local.isAuthenticated else { return }
        Task { @MainActor [weak self] in
            do {
                let elo = try await BlomixEloManager.shared.fetchLocalPlayerElo()
                guard let self, self.isStartScreen else { return }
                guard let overlay = self.childNode(withName: Self.startScreenOverlayName),
                      let eloLabel = overlay.childNode(withName: Self.startScreenPlayerEloLabelName) as? SKLabelNode else { return }
                eloLabel.text = BlomixL10n.startScreenPlayerElo(elo)
            } catch {
                guard let self, self.isStartScreen else { return }
                guard let overlay = self.childNode(withName: Self.startScreenOverlayName),
                      let eloLabel = overlay.childNode(withName: Self.startScreenPlayerEloLabelName) as? SKLabelNode else { return }
                eloLabel.text = BlomixL10n.startScreenPlayerEloUnavailable
            }
        }
        refreshStartScreenRankDiscsIfVisible()
    }

    /// Fetche le rang du joueur sur les 3 leaderboards (SOLO, Moyenne, Zen) et
    /// révèle le disque correspondant dès que sa réponse Game Center arrive.
    /// Aucune restriction de rang : le joueur voit sa position même s'il est 5 000e.
    private func refreshStartScreenRankDiscsIfVisible() {
        guard isStartScreen, GKLocalPlayer.local.isAuthenticated else { return }

        let specs: [(leaderboardID: String, discName: String)] = [
            (ScoreManager.mainLeaderboardID,    Self.startScreenRankDiscSoloName),
            (ScoreManager.averageLeaderboardID, Self.startScreenRankDiscAvgName),
            (ScoreManager.zenLeaderboardID,     Self.startScreenRankDiscZenName),
        ]

        for (leaderboardID, discName) in specs {
            ScoreManager.shared.fetchLocalPlayerRank(leaderboardID: leaderboardID) { [weak self] rank in
                guard let self, self.isStartScreen else { return }
                guard let rank else { return }          // pas encore d'entrée sur ce leaderboard
                guard let overlay = self.childNode(withName: Self.startScreenOverlayName),
                      let container = overlay.childNode(withName: Self.startScreenRankDiscsContainerName),
                      let discNode  = container.childNode(withName: discName),
                      let rankLabel = discNode.childNode(withName: discName + Self.rankDiscRankLabelSuffix) as? SKLabelNode
                else { return }

                rankLabel.text = "#\(rank)"
                discNode.removeAllActions()
                discNode.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.1),
                    SKAction.fadeIn(withDuration: 0.35),
                ]))
            }
        }
    }

    private func registerGameCenterAuthObserverIfNeeded() {
        guard gameCenterAuthObserver == nil else { return }
        gameCenterAuthObserver = NotificationCenter.default.addObserver(
            forName: .blomixGameCenterAuthDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshGameCenterStatusLabelText()
        }
    }

    private func registerSkinChangeObserverIfNeeded() {
        guard skinChangeObserver == nil else { return }
        skinChangeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.blomixSkinDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard !self.isStartScreen else { return }
            self.drawGrid()
            self.updatePreviewSprite()
            self.refreshUpcomingQueueSlots()
            self.refreshBombHudIcon()
        }
    }

    private func registerFontChangeObserverIfNeeded() {
        guard fontChangeObserver == nil else { return }
        fontChangeObserver = NotificationCenter.default.addObserver(
            forName: .blomixFontDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyTypographyChangeToVisibleScene()
        }
    }

    private func applyTypographyChangeToVisibleScene() {
        guard let rootVC = modalRootViewController() else { return }
        rootVC.view.setNeedsLayout()
        rootVC.view.layoutIfNeeded()

        if isStartScreen {
            presentStartScreen()
            refreshStartScreenPlayerIdentityIfVisible()
            layoutGameCenterStatusLabel()
            refreshGameCenterStatusLabelText()
            return
        }

        childNode(withName: Self.titleNodeName)?.removeFromParent()
        childNode(withName: Self.gameplaySubtitleUnderTitleName)?.removeFromParent()
        childNode(withName: Self.gridContainerName)?.removeFromParent()
        childNode(withName: Self.previewNodeName)?.removeFromParent()
        childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()
        childNode(withName: Self.scoreHudLabelName)?.removeFromParent()
        childNode(withName: Self.bestScoreAboveName)?.removeFromParent()
        childNode(withName: Self.hudTimerCaptionName)?.removeFromParent()
        childNode(withName: Self.bombHudIconName)?.removeFromParent()
        childNode(withName: Self.hudPvPTurnTimerName)?.removeFromParent()
        childNode(withName: Self.hudPvPOpponentName)?.removeFromParent()

        applyCurrentTypographyToLabelNodes(in: self)
        addTopTitle()
        setupScoreHUD()
        setupBombHUD()
        drawGrid()
        updatePreviewSprite()
        refreshUpcomingQueueSlots()
        updateBombHUD()
        refreshProgressHUDBars()
        ensurePvPTurnCountdownLabelIfNeeded()
        ensurePvPOpponentLabelIfNeeded()
        layoutScoreLabel()
        layoutBombHUD()
        layoutPvPTurnCountdownIfNeeded()
        layoutGameOverflowMenuIfNeeded()
        layoutGameCenterStatusLabel()
        refreshGameCenterStatusLabelText()
    }

    private func applyCurrentTypographyToLabelNodes(in node: SKNode) {
        if let label = node as? SKLabelNode {
            label.fontName = Self.customUIFontPostScriptName
        }
        for child in node.children {
            applyCurrentTypographyToLabelNodes(in: child)
        }
    }

    // MARK: - Game Center Integration

    private func modalRootViewController() -> UIViewController? {
        guard let skView = self.view as? SKView,
              let rootVC = skView.window?.rootViewController else { return nil }
        return rootVC
    }

    private func presentFullScreenModal(_ viewController: UIViewController) {
        guard let rootVC = modalRootViewController() else {
            print("[GameScene] Impossible de trouver le rootViewController (modal)")
            return
        }
        viewController.modalPresentationStyle = .overFullScreen
        viewController.modalTransitionStyle = .crossDissolve
        rootVC.present(viewController, animated: true)
    }

    /// Bouton « Voir le classement » (Game Over) : présente `LeaderboardViewController` depuis le `rootViewController` UIKit.
    private func showLeaderboard() {
        let vc = LeaderboardViewController()
        vc.onMatch = { [weak self] match in
            self?.beginPvPWithMatch(match)
        }
        presentFullScreenModal(vc)
        print("[GameScene] LeaderboardViewController présenté")
    }

    /// Écran réglages (volume SFX + skins), comme le classement : modal UIKit plein écran.
    private func showSettings() {
        presentFullScreenModal(SettingsViewController())
    }

    /// Règles : ouvre le tutoriel paginé par-dessus le jeu (accessible à tout moment depuis le menu).
    private func showRules() {
        guard let gameVC = modalRootViewController() as? GameViewController else { return }
        let anchors = makeTutorialLayoutAnchorsForOverlay()
        gameVC.showTutorialOverlay(anchors: anchors)
    }

    /// Crédits (`credits.txt`) : même présentation modale.
    private func showCredits() {
        let body = loadCreditsPlainText()
        presentFullScreenModal(BlomixPlainTextModalViewController(screenTitle: BlomixL10n.modalCreditsTitle, body: body))
    }

    /// Prochain bloc « preview » : **1 chance sur 8** d’un `.priks(5)`, sinon couleur aléatoire.
    static func randomNextPlayableBlock() -> BlockType {
        let r = Double.random(in: 0..<1)
        if r < MagixRules.spawnProbability {
            // Tirage pondéré : chaque variante a sa propre probabilité.
            var cumul = 0.0
            var chosenKind: MagixKind = .chromax
            for entry in MagixRules.spawnProbabilityByKind {
                cumul += entry.p
                if r < cumul { chosenKind = entry.kind; break }
            }
            return .magix(chosenKind)
        }
        if r < MagixRules.spawnProbability + PriksRules.spawnProbability {
            return .priks(PriksRules.initialHitsRemaining)
        }
        let name = colorPalette.randomElement() ?? "red"
        return .color(name)
    }

    /// Première case **vide** en descendant depuis le **haut** de la colonne (`topRowIndex` → `bas`) : la case vide **la plus haute** ; c’est là que le bloc s’arrête en montant depuis sous la grille.
    private func highestEmptyRow(inColumn columnIndex: Int) -> Int? {
        for row in GridLayout.topRowIndex..<GridLayout.rowCount {
            if grid[row][columnIndex] == .empty {
                return row
            }
        }
        return nil
    }

    /// Première case **occupée** en remontant depuis le **bas** de la colonne (là où la bombe « s’arrête »). Si toute la colonne est vide → `nil` (la bombe va tout en **haut**, `topRowIndex`).
    private func lowestOccupiedRow(inColumn columnIndex: Int) -> Int? {
        guard columnIndex >= 0, columnIndex < GridLayout.columnCount else { return nil }
        for row in (GridLayout.topRowIndex..<GridLayout.rowCount).reversed() {
            if grid[row][columnIndex] != .empty {
                return row
            }
        }
        return nil
    }

    // MARK: - Game over (solo)

    /// `true` si le **bloc courant** ne peut pas être posé dans cette colonne : aucune case vide du haut vers le bas.
    /// Les **bombes** ne passent pas par cette règle (pas besoin d’une case vide).
    private func checkGameOver(forNormalDropInColumn columnIndex: Int) -> Bool {
        guard !isBombMode else { return false }
        guard columnIndex >= 0, columnIndex < GridLayout.columnCount else { return true }
        return highestEmptyRow(inColumn: columnIndex) == nil
    }

    /// Bloque les entrées ; joue `end.wav` puis affiche l’overlay de fin (avec pré-animation ciblée si `focusPoint` est fourni).
    private func triggerGameOver(focusPoint: CGPoint? = nil) {
        guard !isGameOver else { return }
        cancelGhostPreview()

        if pvpCoordinator != nil {
            pvpCoordinator?.localPlayerLost()
            return
        }

        BlomixSoloSaveManager.shared.clear()
        isGameOver = true
        isProcessing = true
        stopStageTimer()
        hapticHeavy()

        let finalScore = score
        gameOverFinalScore = finalScore

        playMatchSound(.end)

        childNode(withName: Self.fallingSpriteName)?.removeFromParent()
        if let preview = childNode(withName: Self.previewNodeName) {
            preview.isHidden = true
        }
        childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()

        let showOverlay = { [weak self] in
            guard let self else { return }
            self.presentGameOverOverlay(finalScore: finalScore)
        }

        guard let focusPoint else {
            showOverlay()
            return
        }

        playGameOverFocusAnimation(at: focusPoint) {
            showOverlay()
        }
    }

    private func presentGameOverOverlay(finalScore: Int) {

        childNode(withName: Self.gameOverOverlayName)?.removeFromParent()
        let overlay = SKNode()
        overlay.name = Self.gameOverOverlayName
        overlay.zPosition = 200
        addChild(overlay)

        let dim = SKSpriteNode(color: .black, size: size)
        dim.name = Self.gameOverDimBackgroundName
        dim.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.alpha = 0.72
        dim.zPosition = 0
        overlay.addChild(dim)

        // Décalage vertical pour faire de la place au récapitulatif d'analyse si des coups ont été analysés.
        let showAnalysisRecap = BlomixMoveAnalyzer.evalEnabled && analyzerGameStats.totalMoves > 0
        let analysisPanelShift: CGFloat = showAnalysisRecap ? -60 : 0

        // Blox flottants (entre le fond assombri z=0 et le contenu z=10).
        let gameOverAmbient = SKNode()
        gameOverAmbient.name = Self.gameOverAmbientBlocksContainerName
        gameOverAmbient.zPosition = 0.5
        overlay.addChild(gameOverAmbient)
        startAmbientBlocksAnimation(
            in: overlay,
            containerName: Self.gameOverAmbientBlocksContainerName,
            actionKey: Self.gameOverAmbientBlocksSpawnActionKey
        )

        // ── Récap analyse des coups (affiché uniquement si des coups ont été analysés) ──
        if showAnalysisRecap {
            let stats    = analyzerGameStats
            let optPct   = stats.optimalityPercent
            let recapBaseY: CGFloat = size.height / 2 + 230

            // Couleur thématique selon le score
            let accentColor: SKColor
            if optPct >= 60 {
                accentColor = SKColor(red: 0.22, green: 0.72, blue: 0.37, alpha: 1)
            } else if optPct >= 30 {
                accentColor = SKColor(red: 0.95, green: 0.72, blue: 0.25, alpha: 1)
            } else {
                accentColor = SKColor(red: 0.90, green: 0.35, blue: 0.25, alpha: 1)
            }

            // ── Grand pourcentage animé ──
            let bigPctLabel = SKLabelNode(text: "0%")
            bigPctLabel.fontName               = Self.customUIFontPostScriptName
            bigPctLabel.fontSize               = 34
            bigPctLabel.fontColor              = accentColor
            bigPctLabel.horizontalAlignmentMode = .center
            bigPctLabel.verticalAlignmentMode   = .center
            bigPctLabel.position  = CGPoint(x: size.width / 2, y: recapBaseY)
            bigPctLabel.alpha     = 0
            bigPctLabel.zPosition = 10
            overlay.addChild(bigPctLabel)
            bigPctLabel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.35),
                SKAction.group([
                    SKAction.fadeIn(withDuration: 0.2),
                    SKAction.customAction(withDuration: 1.3) { node, elapsed in
                        guard let lbl = node as? SKLabelNode else { return }
                        let eased = min(sqrt(Double(elapsed) / 1.3), 1.0)
                        lbl.text  = "\(Int(Double(optPct) * eased))%"
                    },
                ]),
            ]))

            // ── Sous-titre "optimalité" ──
            let subLabel = SKLabelNode(text: "optimalité")
            subLabel.fontName               = Self.customUIFontPostScriptName
            subLabel.fontSize               = 11
            subLabel.fontColor              = SKColor(white: 0.60, alpha: 1)
            subLabel.horizontalAlignmentMode = .center
            subLabel.verticalAlignmentMode   = .center
            subLabel.position  = CGPoint(x: size.width / 2, y: recapBaseY - 36)
            subLabel.alpha     = 0
            subLabel.zPosition = 10
            overlay.addChild(subLabel)
            subLabel.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.30),
                SKAction.fadeIn(withDuration: 0.2),
            ]))

            // ── Barre de progression ──
            let barWidth:  CGFloat = 200
            let barHeight: CGFloat = 14
            let cornerR:   CGFloat = barHeight / 2
            let barY = recapBaseY - 60

            // Fond de la barre (remplissage semi-transparent)
            let barBg = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight),
                                    cornerRadius: cornerR)
            barBg.fillColor   = SKColor(white: 1, alpha: 0.10)
            barBg.strokeColor = .clear
            barBg.position    = CGPoint(x: size.width / 2, y: barY)
            barBg.zPosition   = 10
            barBg.alpha       = 0
            overlay.addChild(barBg)
            barBg.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.35),
                SKAction.fadeIn(withDuration: 0.2),
            ]))

            // Remplissage animé — SKCropNode pour rester dans les limites arrondies
            let targetScale = CGFloat(optPct) / 100.0
            let cropNode = SKCropNode()
            cropNode.position  = CGPoint(x: size.width / 2, y: barY)
            cropNode.zPosition = 11
            cropNode.alpha     = 0

            let fillBar = SKSpriteNode(color: accentColor,
                                       size: CGSize(width: barWidth, height: barHeight))
            fillBar.anchorPoint = CGPoint(x: 0, y: 0.5)
            fillBar.position    = CGPoint(x: -barWidth / 2, y: 0)
            fillBar.xScale      = 0
            cropNode.addChild(fillBar)

            let maskShape = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight),
                                        cornerRadius: cornerR)
            maskShape.fillColor   = .white
            maskShape.strokeColor = .clear
            cropNode.maskNode = maskShape
            overlay.addChild(cropNode)

            cropNode.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.35),
                SKAction.fadeIn(withDuration: 0.2),
            ]))
            fillBar.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.35),
                SKAction.customAction(withDuration: 1.3) { node, elapsed in
                    let eased = min(sqrt(CGFloat(elapsed) / 1.3), 1.0)
                    node.xScale = eased * targetScale
                },
            ]))

            // Contour fin E0E0E0 au-dessus du remplissage
            let barBorder = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight),
                                        cornerRadius: cornerR)
            barBorder.fillColor   = .clear
            barBorder.strokeColor = SKColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 0.65)
            barBorder.lineWidth   = 1
            barBorder.position    = CGPoint(x: size.width / 2, y: barY)
            barBorder.zPosition   = 12
            barBorder.alpha       = 0
            overlay.addChild(barBorder)
            barBorder.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.35),
                SKAction.fadeIn(withDuration: 0.2),
            ]))

            // ── Compteurs coups excellents / erreurs ──
            let excellentLabel = SKLabelNode(
                text: "✦ \(stats.excellentCount) coups excellents  •  \(stats.badCount) erreurs"
            )
            excellentLabel.fontName               = Self.customUIFontPostScriptName
            excellentLabel.fontSize               = 13
            excellentLabel.fontColor              = SKColor(white: 0.76, alpha: 1)
            excellentLabel.horizontalAlignmentMode = .center
            excellentLabel.verticalAlignmentMode   = .center
            excellentLabel.position  = CGPoint(x: size.width / 2, y: recapBaseY - 84)
            excellentLabel.alpha     = 0
            excellentLabel.zPosition = 10
            overlay.addChild(excellentLabel)
            excellentLabel.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.65),
                SKAction.fadeIn(withDuration: 0.22),
            ]))

            // ── Séparateur visuel ──
            let sep = SKShapeNode(rect: CGRect(
                x: size.width / 2 - 80, y: recapBaseY - 100, width: 160, height: 1
            ))
            sep.fillColor   = SKColor(white: 1, alpha: 0.22)
            sep.strokeColor = .clear
            sep.zPosition   = 10
            sep.alpha       = 0
            overlay.addChild(sep)
            sep.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.18),
                SKAction.fadeIn(withDuration: 0.2),
            ]))
        }

        let title = SKLabelNode(text: BlomixL10n.gameOverTitle)
        title.name = Self.gameOverTitleLabelName
        title.fontName = Self.customUIFontPostScriptName
        title.fontSize = 32
        title.fontColor = .white
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 36 - analysisPanelShift)
        title.setScale(0.2)
        title.alpha = 1
        title.zPosition = 10
        overlay.addChild(title)
        let popIn = SKAction.scale(to: 1.0, duration: 0.4)
        popIn.timingMode = .easeOut
        title.run(popIn)

        let scoreLine = SKLabelNode(text: BlomixL10n.gameOverScore(finalScore))
        scoreLine.name = Self.gameOverScoreLabelName
        scoreLine.fontName = Self.customUIFontPostScriptName
        scoreLine.fontSize = 36
        scoreLine.fontColor = .white
        scoreLine.horizontalAlignmentMode = .center
        scoreLine.verticalAlignmentMode = .center
        scoreLine.position = CGPoint(x: size.width / 2, y: size.height / 2 - 8 - analysisPanelShift)
        scoreLine.alpha = 0
        scoreLine.zPosition = 10
        overlay.addChild(scoreLine)
        scoreLine.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.2),
            SKAction.fadeIn(withDuration: 0.22),
        ]))

        let goButtonFontSize = BlomixUIDestinationButtonStyle.navigationTitleFontSize
        let goButtonSize = BlomixSKButtonNode.unifiedSize(
            for: [BlomixL10n.gameOverRestart, BlomixL10n.gameOverLeaderboard],
            fontSize: goButtonFontSize,
            maxWidth: size.width - 48
        )
        let restart = BlomixSKButtonNode(
            name: Self.gameOverRestartLabelName,
            text: BlomixL10n.gameOverRestart,
            size: goButtonSize,
            fontSize: goButtonFontSize
        )
        restart.position = CGPoint(x: size.width / 2, y: size.height / 2 - 64 - analysisPanelShift)
        restart.alpha = 0
        restart.zPosition = 10
        overlay.addChild(restart)
        restart.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.35),
            SKAction.fadeIn(withDuration: 0.2),
        ]))

        let leaderboard = BlomixSKButtonNode(
            name: Self.gameOverLeaderboardLabelName,
            text: BlomixL10n.gameOverLeaderboard,
            size: goButtonSize,
            fontSize: goButtonFontSize
        )
        leaderboard.position = CGPoint(x: size.width / 2, y: size.height / 2 - 64 - goButtonSize.height - 10 - analysisPanelShift)
        leaderboard.alpha = 0
        leaderboard.zPosition = 10
        overlay.addChild(leaderboard)
        leaderboard.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.42),
            SKAction.fadeIn(withDuration: 0.22),
        ]))

        let quote = randomGameOverQuote()
        let quoteMaxChars = max(18, Int((size.width - 40) / 11))
        let wrapped = Self.wrapQuoteForGameOver(quote.text, maxCharsPerLine: quoteMaxChars, maxLines: 4)

        // Si le bouton "pire coup" est visible, la citation descend d'une hauteur de bouton supplémentaire.
        let worstMoveBtnShift: CGFloat = (BlomixMoveAnalyzer.evalEnabled && worstMistakeSnapshot != nil)
            ? goButtonSize.height + 36
            : 0

        if !wrapped.isEmpty {
            let lineHeight: CGFloat = 24
            let firstLineY = size.height / 2 - 162 - analysisPanelShift - worstMoveBtnShift
            for (index, line) in wrapped.enumerated() {
                let quoteLine = SKLabelNode(text: line)
                quoteLine.name = index == 0 ? Self.gameOverQuoteLine1LabelName : Self.gameOverQuoteLine2LabelName
                quoteLine.fontName = Self.customUIFontPostScriptName
                quoteLine.fontSize = 20
                quoteLine.fontColor = .white
                quoteLine.horizontalAlignmentMode = .center
                quoteLine.verticalAlignmentMode = .center
                quoteLine.position = CGPoint(x: size.width / 2, y: firstLineY - CGFloat(index) * lineHeight)
                quoteLine.alpha = 0
                quoteLine.zPosition = 10
                overlay.addChild(quoteLine)
                quoteLine.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.62 + Double(index) * 0.03),
                    SKAction.fadeIn(withDuration: 0.24),
                ]))
            }
        }

        let author = SKLabelNode(text: "- \(quote.author)")
        author.name = Self.gameOverQuoteAuthorLabelName
        author.fontName = Self.customUIFontPostScriptName
        author.fontSize = 18
        author.fontColor = SKColor(white: 0.86, alpha: 1)
        author.horizontalAlignmentMode = .center
        author.verticalAlignmentMode = .center
        let authorY = size.height / 2 - 162 - CGFloat(max(1, wrapped.count)) * 24 - 10 - analysisPanelShift - worstMoveBtnShift
        author.position = CGPoint(x: size.width / 2, y: authorY)
        author.alpha = 0
        author.zPosition = 10
        overlay.addChild(author)
        author.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.72),
            SKAction.fadeIn(withDuration: 0.24),
        ]))

        // ── Bouton "Voir ton pire coup" ──────────────────────────────────────────
        // Toujours affiché si le système d'analyse a capturé au moins un coup.
        if BlomixMoveAnalyzer.evalEnabled && worstMistakeSnapshot != nil {
            let worstBtn = BlomixSKButtonNode(
                name:     Self.gameOverWorstMoveButtonName,
                text:     "Voir ton pire coup",
                size:     goButtonSize,
                fontSize: goButtonFontSize
            )
            let leaderboardY = size.height / 2 - 64 - goButtonSize.height - 10 - analysisPanelShift
            worstBtn.position = CGPoint(x: size.width / 2,
                                        y: leaderboardY - goButtonSize.height - 10)
            worstBtn.alpha    = 0
            worstBtn.zPosition = 10
            overlay.addChild(worstBtn)
            worstBtn.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.50),
                SKAction.fadeIn(withDuration: 0.22),
            ]))
        }

        // Game Center : soumission solo uniquement sur BlomixMainScore_v3.
        // Les scores PvP sont gérés par le système Elo et n'entrent pas dans ce leaderboard.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.pvpCoordinator == nil else { return }
            let isNewPB = self.isZenMode
                ? ScoreManager.shared.isNewZenPersonalBest(finalScore)
                : ScoreManager.shared.isNewPersonalBest(finalScore)
            if self.isZenMode {
                // Mode Zen : soumission au leaderboard Zen uniquement, pas de contribution à la moyenne.
                ScoreManager.shared.submitScore(finalScore, leaderboardID: ScoreManager.zenLeaderboardID, completion: nil)
            } else {
                ScoreManager.shared.submitScore(finalScore, completion: nil)
                ScoreManager.shared.recordGameScore(finalScore)
            }
            guard isNewPB,
                  let overlay = self.childNode(withName: Self.gameOverOverlayName) else { return }
            let personalBest = SKLabelNode(text: BlomixL10n.gameOverPersonalBest)
            personalBest.name = Self.gameOverPersonalBestLabelName
            personalBest.fontName = Self.customUIFontPostScriptName
            personalBest.fontSize = 14
            personalBest.fontColor = .white
            personalBest.horizontalAlignmentMode = .center
            personalBest.verticalAlignmentMode = .center
            personalBest.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2 - 30)
            personalBest.alpha = 0
            personalBest.zPosition = 10
            overlay.addChild(personalBest)
            personalBest.run(SKAction.fadeIn(withDuration: 0.22))
        }
    }


    // MARK: - Overlay "Pire coup"

    /// Affiche un overlay plein-ecran avec la mini-grille du pire coup de la partie.
    /// Un tap n'importe ou ferme l'overlay.
    private func showWorstMistakeOverlay() {
        guard let snap = worstMistakeSnapshot else { return }

        childNode(withName: Self.worstMistakeOverlayName)?.removeFromParent()

        let overlay = SKNode()
        overlay.name      = Self.worstMistakeOverlayName
        overlay.zPosition = 300
        addChild(overlay)

        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.88), size: size)
        dim.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        dim.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.zPosition   = 0
        overlay.addChild(dim)

        let cols      = GridLayout.columnCount
        let rows      = GridLayout.rowCount
        let cellSize: CGFloat = min(30, (size.width - 48) / CGFloat(cols))
        let gridW     = cellSize * CGFloat(cols)
        let gridH     = cellSize * CGFloat(rows)

        // Tailles décroissantes : p0 (joué) > p1 (suivant) > p2 (d'après).
        let sizeP0: CGFloat = cellSize * 1.15
        let sizeP1: CGFloat = cellSize * 0.85
        let sizeP2: CGFloat = cellSize * 0.70
        let pendingLineH: CGFloat = cellSize * 0.55

        // Hauteur totale sous la grille : ligne entrante (si présente) + file de 3 blocs (2 rangées) + badge stage.
        // p0 (rangée haute) + gap + p1 (rangée basse) + badge éventuel + label = sizeP0 * 2 + gap + badgeH + 18
        let hasPendingLine = snap.pendingLine != nil && !(snap.pendingLine!.allSatisfy { $0 == .empty })
        let hasStageBadgeForLayout = snap.stageLevelText != nil
        let belowGridH: CGFloat = 8
            + (hasPendingLine ? pendingLineH + 6 : 0)
            + 10 + sizeP0 + 6 + sizeP0
            + (hasStageBadgeForLayout ? 8 + 50 : 0)
            + 18 + 28
        let contentH  = 70 + gridH + belowGridH   // 70 = 2 lignes légende + titre
        let gridOriginX = (size.width - gridW) / 2
        let gridOriginY = (size.height - contentH) / 2 + belowGridH

        let gridContainer = SKNode()
        gridContainer.position  = CGPoint(x: gridOriginX, y: gridOriginY)
        gridContainer.zPosition = 10
        overlay.addChild(gridContainer)

        let optColsSet = Set(snap.optimalColumns)
        var landingRowPerCol = [Int: Int]()
        for c in 0..<cols {
            if let r = BlomixMoveAnalyzer.landingRow(in: snap.grid, column: c) {
                landingRowPerCol[c] = r
            }
        }
        let chosenLandingRow    = landingRowPerCol[snap.chosenColumn]
        let chosenIsAlsoOptimal = optColsSet.contains(snap.chosenColumn)

        for r in 0..<rows {
            for c in 0..<cols {
                let block = snap.grid[r][c]
                let cellX = CGFloat(c) * cellSize
                let cellY = CGFloat(rows - 1 - r) * cellSize

                let bg = SKShapeNode(
                    rectOf: CGSize(width: cellSize - 1, height: cellSize - 1),
                    cornerRadius: 3)
                bg.position  = CGPoint(x: cellX + cellSize / 2, y: cellY + cellSize / 2)
                bg.zPosition = 0

                switch block {
                case .color(let name):
                    bg.fillColor   = Self.bloxSolidFillColor(colorName: name) ?? SKColor(white: 0.45, alpha: 1)
                    bg.strokeColor = .clear
                case .priks(let n):
                    bg.fillColor   = Self.priksSolidFillColor()
                    bg.strokeColor = .clear
                    let nLbl = SKLabelNode(text: "\(n)")
                    nLbl.fontName               = Self.customUIFontPostScriptName
                    nLbl.fontSize               = cellSize * 0.45
                    nLbl.fontColor              = .white
                    nLbl.verticalAlignmentMode  = .center
                    nLbl.horizontalAlignmentMode = .center
                    nLbl.zPosition = 1
                    bg.addChild(nLbl)
                case .magix(let kind):
                    bg.fillColor   = SKColor(white: 0.78, alpha: 1)
                    bg.strokeColor = .clear
                    let mLbl = SKLabelNode(text: "M")
                    mLbl.fontName               = "Helvetica-Bold"
                    mLbl.fontSize               = cellSize * 0.45
                    mLbl.fontColor              = .black
                    mLbl.verticalAlignmentMode  = .center
                    mLbl.horizontalAlignmentMode = .center
                    mLbl.zPosition = 1
                    bg.addChild(mLbl)
                case .empty:
                    bg.fillColor   = SKColor(white: 0.10, alpha: 1)
                    bg.strokeColor = SKColor(white: 0.22, alpha: 1)
                    bg.lineWidth   = 0.5
                }
                gridContainer.addChild(bg)

                let isOptimalLanding = optColsSet.contains(c) && landingRowPerCol[c] == r
                let isChosenLanding  = c == snap.chosenColumn && chosenLandingRow == r

                if isOptimalLanding {
                    let lbl = SKLabelNode(text: "⭐")
                    lbl.fontName               = "Helvetica"
                    lbl.fontSize               = cellSize * 0.52
                    lbl.verticalAlignmentMode  = .center
                    lbl.horizontalAlignmentMode = .center
                    lbl.zPosition = 2
                    bg.addChild(lbl)
                } else if isChosenLanding && !chosenIsAlsoOptimal {
                    let lbl = SKLabelNode(text: "💀")
                    lbl.fontName               = "Helvetica"
                    lbl.fontSize               = cellSize * 0.52
                    lbl.verticalAlignmentMode  = .center
                    lbl.horizontalAlignmentMode = .center
                    lbl.zPosition = 2
                    bg.addChild(lbl)
                }
            }
        }

        // ── Ligne entrante (si visible au moment du coup) ────────────────────────
        var pendingLineBottomY = gridOriginY - 8   // référence Y pour empiler vers le bas
        if hasPendingLine, let pLine = snap.pendingLine {
            let lineCenterY = pendingLineBottomY - pendingLineH / 2
            for c in 0..<cols {
                let block = pLine[c]
                let cx = gridOriginX + CGFloat(c) * cellSize + cellSize / 2
                let lc = SKShapeNode(rectOf: CGSize(width: cellSize - 2, height: pendingLineH - 1),
                                     cornerRadius: 2)
                lc.position  = CGPoint(x: cx, y: lineCenterY)
                lc.zPosition = 10
                switch block {
                case .color(let name):
                    lc.fillColor   = Self.bloxSolidFillColor(colorName: name) ?? SKColor(white: 0.40, alpha: 1)
                    lc.strokeColor = .clear
                case .priks(let n):
                    lc.fillColor   = Self.priksSolidFillColor()
                    lc.strokeColor = .clear
                    let nl = SKLabelNode(text: "\(n)")
                    nl.fontName               = Self.customUIFontPostScriptName
                    nl.fontSize               = pendingLineH * 0.55
                    nl.fontColor              = .white
                    nl.verticalAlignmentMode  = .center
                    nl.horizontalAlignmentMode = .center
                    nl.zPosition = 1
                    lc.addChild(nl)
                case .magix:
                    lc.fillColor   = SKColor(white: 0.78, alpha: 1)
                    lc.strokeColor = .clear
                case .empty:
                    lc.fillColor   = SKColor(white: 0.10, alpha: 1)
                    lc.strokeColor = SKColor(white: 0.20, alpha: 1)
                    lc.lineWidth   = 0.5
                }
                overlay.addChild(lc)
            }
            let lineLbl = SKLabelNode(text: "ligne entrante")
            lineLbl.fontName               = Self.customUIFontPostScriptName
            lineLbl.fontSize               = 9
            lineLbl.fontColor              = SKColor(white: 0.42, alpha: 1)
            lineLbl.horizontalAlignmentMode = .left
            lineLbl.verticalAlignmentMode   = .center
            lineLbl.position  = CGPoint(x: gridOriginX, y: lineCenterY - pendingLineH / 2 - 8)
            lineLbl.zPosition = 10
            overlay.addChild(lineLbl)
            pendingLineBottomY -= pendingLineH + 6
        }

        // ── File de 3 blocs : disposition miroir de l'in-game ────────────────────
        //   [  p0  ]      ← bloc joué (centré)
        //   [p2][p1]      ← p1 sous p0, p2 à gauche de p1
        let bs: CGFloat  = sizeP0   // taille unique pour les 3
        let gap: CGFloat = 6
        let badgeSize: CGFloat = 50   // espace réservé pour le badge textuel
        let hasStageBadge = snap.stageLevelText != nil

        let p0CenterX = size.width / 2
        let p0CenterY = pendingLineBottomY - 10 - bs / 2
        let p1CenterX = p0CenterX               // aligné sous p0
        let p1CenterY = p0CenterY - bs - gap
        let p2CenterX = p1CenterX - bs - gap    // à gauche de p1
        let p2CenterY = p1CenterY

        let blockPositions: [(block: BlockType, cx: CGFloat, cy: CGFloat, label: String)] = [
            (snap.block,         p0CenterX, p0CenterY, "joue"),
            (snap.nextBlock,     p1CenterX, p1CenterY, "suiv."),
            (snap.blockTwoAhead, p2CenterX, p2CenterY, "apres"),
        ]

        func makeBlockCell(_ block: BlockType, size sz: CGFloat) -> SKShapeNode {
            let cell = SKShapeNode(rectOf: CGSize(width: sz - 2, height: sz - 2), cornerRadius: 4)
            switch block {
            case .color(let name):
                cell.fillColor   = Self.bloxSolidFillColor(colorName: name) ?? SKColor(white: 0.45, alpha: 1)
                cell.strokeColor = .clear
            case .priks(let n):
                cell.fillColor   = Self.priksSolidFillColor()
                cell.strokeColor = .clear
                let nl = SKLabelNode(text: "\(n)")
                nl.fontName               = Self.customUIFontPostScriptName
                nl.fontSize               = sz * 0.45
                nl.fontColor              = .white
                nl.verticalAlignmentMode  = .center
                nl.horizontalAlignmentMode = .center
                nl.zPosition = 1
                cell.addChild(nl)
            case .magix(let kind):
                cell.fillColor   = SKColor(white: 0.78, alpha: 1)
                cell.strokeColor = .clear
                let ml = SKLabelNode(text: MagixRules.label(for: kind))
                ml.fontName               = "Helvetica-Bold"
                ml.fontSize               = sz * 0.32
                ml.fontColor              = .black
                ml.verticalAlignmentMode  = .center
                ml.horizontalAlignmentMode = .center
                ml.zPosition = 1
                cell.addChild(ml)
            case .empty:
                cell.fillColor   = SKColor(white: 0.22, alpha: 1)
                cell.strokeColor = .clear
            }
            return cell
        }

        for (block, cx, cy, _) in blockPositions {
            let cell = makeBlockCell(block, size: bs)
            cell.position  = CGPoint(x: cx, y: cy)
            cell.zPosition = 10
            overlay.addChild(cell)
        }

        // ── Badge de stage textuel (sous la file de blocs, même espace qu'en jeu) ─
        if hasStageBadge, let lv = snap.stageLevelText {
            let badgeLabel = SKLabelNode()
            badgeLabel.fontName               = Self.customUIFontPostScriptName
            badgeLabel.fontSize               = 18
            badgeLabel.fontColor              = .white
            badgeLabel.horizontalAlignmentMode = .center
            badgeLabel.verticalAlignmentMode   = .center
            badgeLabel.text      = lv == "Ultimate" ? "L★" : "L\(lv)"
            badgeLabel.position  = CGPoint(x: size.width / 2, y: p2CenterY - bs / 2 - gap - badgeSize / 2)
            badgeLabel.zPosition = 10
            overlay.addChild(badgeLabel)
        }

        // ── Légende (en haut, même style que le sous-titre) ─────────────────────
        let legendColor = SKColor(white: 0.50, alpha: 1)
        let legendFontSize: CGFloat = 14
        let legendBaseY = gridOriginY + gridH + 76

        let legend1 = SKLabelNode(text: "⭐ : le meilleur coup à jouer")
        legend1.fontName               = Self.customUIFontPostScriptName
        legend1.fontSize               = legendFontSize
        legend1.fontColor              = legendColor
        legend1.horizontalAlignmentMode = .center
        legend1.verticalAlignmentMode   = .center
        legend1.position  = CGPoint(x: size.width / 2, y: legendBaseY)
        legend1.zPosition = 10
        overlay.addChild(legend1)

        let legend2 = SKLabelNode(text: "💀 : ton pire coup")
        legend2.fontName               = Self.customUIFontPostScriptName
        legend2.fontSize               = legendFontSize
        legend2.fontColor              = legendColor
        legend2.horizontalAlignmentMode = .center
        legend2.verticalAlignmentMode   = .center
        legend2.position  = CGPoint(x: size.width / 2, y: legendBaseY - 18)
        legend2.zPosition = 10
        overlay.addChild(legend2)

        let titleLbl = SKLabelNode(text: "Ton pire coup")
        titleLbl.fontName               = Self.customUIFontPostScriptName
        titleLbl.fontSize               = 15
        titleLbl.fontColor              = SKColor(white: 0.90, alpha: 1)
        titleLbl.horizontalAlignmentMode = .center
        titleLbl.verticalAlignmentMode   = .center
        titleLbl.position  = CGPoint(x: size.width / 2, y: legendBaseY - 40)
        titleLbl.zPosition = 10
        overlay.addChild(titleLbl)

        let hintLbl = SKLabelNode(text: "Tape pour fermer")
        hintLbl.fontName               = Self.customUIFontPostScriptName
        hintLbl.fontSize               = 11
        hintLbl.fontColor              = SKColor(white: 0.45, alpha: 1)
        hintLbl.horizontalAlignmentMode = .center
        hintLbl.verticalAlignmentMode   = .center
        hintLbl.position  = CGPoint(x: size.width / 2, y: 20)
        hintLbl.zPosition = 10
        overlay.addChild(hintLbl)

        overlay.alpha = 0
        overlay.run(SKAction.fadeIn(withDuration: 0.22))
    }

    /// Cercles concentriques « lock-on » qui se referment vers `focusPoint` avant l’overlay Game Over.
    private func playGameOverFocusAnimation(at focusPoint: CGPoint, completion: @escaping () -> Void) {
        // Onde de choc vers l'extérieur + tremblement d'écran au moment de l'impact.
        addBombShockWave(at: focusPoint)
        shakeScreen(intensity: 2.5)

        let holder = SKNode()
        holder.zPosition = GameOverFocusFeedback.layerZ
        addChild(holder)

        for i in 0..<GameOverFocusFeedback.ringCount {
            let ring = SKShapeNode(circleOfRadius: GameOverFocusFeedback.ringStartRadius)
            ring.position = focusPoint
            ring.lineWidth = GameOverFocusFeedback.ringLineWidth
            ring.strokeColor = SKColor(white: 1.0, alpha: 0.95)
            ring.fillColor = .clear
            ring.alpha = 0
            holder.addChild(ring)

            let wait = SKAction.wait(forDuration: Double(i) * GameOverFocusFeedback.ringStagger)
            let prep = SKAction.run {
                ring.alpha = GameOverFocusFeedback.ringStartAlpha
                ring.setScale(1.0)
            }
            let closeIn = SKAction.scale(to: GameOverFocusFeedback.ringEndScale, duration: 0.34)
            closeIn.timingMode = .easeIn
            let fade = SKAction.fadeOut(withDuration: 0.34)
            fade.timingMode = .easeIn
            ring.run(SKAction.sequence([wait, prep, SKAction.group([closeIn, fade])]))
        }

        let title = SKLabelNode(text: BlomixL10n.gameOverFocusTitle)
        title.fontName = Self.customUIFontPostScriptName
        title.fontSize = GameOverFocusFeedback.titleStartFontSize
        title.fontColor = .white
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = focusPoint
        title.zPosition = GameOverFocusFeedback.layerZ + 1
        title.alpha = 0
        addChild(title)

        let titleAppear = SKAction.fadeIn(withDuration: GameOverFocusFeedback.titleDuration)
        titleAppear.timingMode = .easeOut
        let titleGrow = SKAction.customAction(withDuration: GameOverFocusFeedback.titleDuration) { node, elapsed in
            guard let label = node as? SKLabelNode else { return }
            let progress = max(0, min(1, elapsed / CGFloat(GameOverFocusFeedback.titleDuration)))
            label.fontSize = GameOverFocusFeedback.titleStartFontSize + (GameOverFocusFeedback.titleEndFontSize - GameOverFocusFeedback.titleStartFontSize) * progress
        }
        let titleCleanup = SKAction.run { [weak title] in
            title?.removeFromParent()
        }
        title.run(
            SKAction.sequence([
                SKAction.group([titleAppear, titleGrow]),
                SKAction.wait(forDuration: GameOverFocusFeedback.titleHoldDuration),
                titleCleanup,
            ])
        )

        run(
            SKAction.sequence([
                SKAction.wait(forDuration: GameOverFocusFeedback.totalDuration),
                SKAction.run { [weak holder, weak title] in
                    holder?.removeFromParent()
                    title?.removeFromParent()
                    completion()
                },
            ])
        )
    }

    /// Pioche une citation aléatoire depuis `gameover_quotes.json` (bundle), sinon fallback interne.
    private func randomGameOverQuote() -> GameOverQuote {
        if let url = Bundle.main.url(forResource: Self.gameOverQuotesFileBaseName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let quotes = try? JSONDecoder().decode([GameOverQuote].self, from: data),
           !quotes.isEmpty,
           let picked = quotes.randomElement() {
            return picked
        }

        // Fallback de securite si le fichier est absent/invalide.
        let fallback: [GameOverQuote] = [
            .init(text: "Ce n est qu un debut, recommence.", author: "Rainer Maria Rilke"),
            .init(text: "La chute prepare souvent un nouvel elan.", author: "Victor Hugo"),
            .init(text: "On apprend a force de recommencer.", author: "Seneca"),
        ]
        return fallback.randomElement() ?? fallback[0]
    }

    // MARK: - Tip of the day helpers

    /// Charge les conseils du jour depuis `tips_of_day.json` en respectant la langue du joueur.
    private func loadTipPoolIfNeeded() {
        guard tipOfDayPool.isEmpty else { return }
        tipOfDayPool = Self.loadLocalizedTips(fileBaseName: Self.tipsOfDayFileBaseName).shuffled()
    }

    private static func loadLocalizedTips(fileBaseName: String) -> [TipOfDay] {
        // Cherche d’abord dans le dossier de la langue préférée du système.
        let preferredLangs = Locale.preferredLanguages.map { String($0.prefix(2)) }
        for lang in preferredLangs {
            if let url = Bundle.main.url(forResource: fileBaseName, withExtension: "json", subdirectory: "\(lang).lproj"),
               let data = try? Data(contentsOf: url),
               let tips = try? JSONDecoder().decode([TipOfDay].self, from: data),
               !tips.isEmpty {
                return tips
            }
        }
        // Fallback standard (fonctionne si le fichier est localisé dans Xcode).
        if let url = Bundle.main.url(forResource: fileBaseName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let tips = try? JSONDecoder().decode([TipOfDay].self, from: data),
           !tips.isEmpty {
            return tips
        }
        // Dernier recours intégré — toutes les phrases disponibles.
        let lang2 = preferredLangs.first ?? "en"
        if lang2.hasPrefix("fr") {
            return [
                TipOfDay(text: "N’oubliez pas les diagonales."),
                TipOfDay(text: "Jouez la bombe au bon moment."),
                TipOfDay(text: "Plus les chaînes sont longues, plus vous marquez de points."),
                TipOfDay(text: "Pensez aux coups suivants."),
                TipOfDay(text: "Soignez vos empilements."),
                TipOfDay(text: "Regardez les blox à venir."),
                TipOfDay(text: "Respirez, lentement."),
                TipOfDay(text: "Vous pouvez tout paramétrer à votre goût dans les réglages."),
                TipOfDay(text: "Pas plus de 5 parties par jour."),
            ]
        }
        return [
            TipOfDay(text: "Don’t forget the diagonals."),
            TipOfDay(text: "Use the bomb at the right moment."),
            TipOfDay(text: "The longer the chains, the more points you score."),
            TipOfDay(text: "Think ahead."),
            TipOfDay(text: "Mind your stacking."),
            TipOfDay(text: "Keep an eye on the upcoming blocks."),
            TipOfDay(text: "Breathe, slowly."),
            TipOfDay(text: "You can customise everything in the settings."),
            TipOfDay(text: "No more than 5 games a day."),
        ]
    }

    /// Pioche le conseil suivant (pas le même que le précédent).
    private func pickNextTip() -> TipOfDay {
        loadTipPoolIfNeeded()
        guard tipOfDayPool.count > 1 else { return tipOfDayPool.first ?? TipOfDay(text: "") }
        var nextIndex: Int
        repeat {
            nextIndex = Int.random(in: 0..<tipOfDayPool.count)
        } while nextIndex == lastTipIndex
        lastTipIndex = nextIndex
        return tipOfDayPool[nextIndex]
    }

    /// Met à jour le label de conseil sur l’écran d’accueil avec un fondu enchaîné.
    /// Construit un NSAttributedString centré pour les tips (conserve police et couleur).
    private static func tipAttributedString(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: customUIFontPostScriptName, size: 13) ?? UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor(white: 0.7, alpha: 1),
            .paragraphStyle: para,
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    private func rotateTipInStartScreen(in overlay: SKNode) {
        guard let container = overlay.childNode(withName: Self.startScreenTipContainerName),
              let label = container.childNode(withName: Self.startScreenTipTextLabelName) as? SKLabelNode
        else { return }
        let newAttributedText = Self.tipAttributedString(pickNextTip().text)
        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.4)
        let changeText = SKAction.run { label.attributedText = newAttributedText }
        let fadeIn = SKAction.fadeAlpha(to: 1, duration: 0.4)
        label.run(SKAction.sequence([fadeOut, changeText, fadeIn]))
    }

    /// Coupe une citation en 1-2 lignes lisibles pour un `SKLabelNode`.
    private static func wrapQuoteForGameOver(_ text: String, maxCharsPerLine: Int, maxLines: Int) -> [String] {
        guard maxCharsPerLine > 8, maxLines > 0 else { return [text] }
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        var lines: [String] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count <= maxCharsPerLine {
                current = candidate
            } else {
                if !current.isEmpty {
                    lines.append(current)
                } else {
                    lines.append(word)
                }
                current = current.isEmpty ? "" : word
                if lines.count >= maxLines { break }
            }
        }

        if lines.count < maxLines, !current.isEmpty {
            lines.append(current)
        }

        if lines.count > maxLines {
            return Array(lines.prefix(maxLines))
        }
        return lines
    }

    /// Nettoie la partie en cours et affiche l’écran d’accueil (Game Over, **New Game**, etc.).
    /// Nettoie la scène et affiche l'écran d'accueil.
    /// `restoreSave: true` → utilise `presentStartScreenOrRestoreSoloSave()` pour reprendre
    /// automatiquement une partie solo sauvegardée (fin de tutoriel ou de match PvP).
    private func unwindToStartScreen(restoreSave: Bool = false) {
        // Bloque saveCurrentSoloGameState() pendant toute la phase de démontage/reset,
        // pour éviter qu'un willResignActiveNotification écrase la sauvegarde solo
        // avec un état transitoire (grille vide, modèle PvP, etc.).
        isWindingDown = true
        // Retour à la piste de base quelle que soit la situation (fin de partie solo stagée, PvP, tuto…).
        BlomixMusicPlayer.shared.resetToBase()
        blomixPvP_teardown()
        removeAllActions()
        childNode(withName: Self.gameOverOverlayName)?.removeFromParent()
        childNode(withName: Self.fallingSpriteName)?.removeFromParent()
        for col in 0..<GridLayout.columnCount {
            childNode(withName: "\(Self.randomLineRisingSpritePrefix)\(col)")?.removeFromParent()
        }
        childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()

        isGameOver = false
        isProcessing = false
        isInjectingBottomRandomLine = false
        resetSessionModelForNewMatch()

        updateBombHUD()
        if let scoreLabel = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode {
            scoreLabel.text = "0"
        }
        drawGrid()
        setGameplayNodesHidden(true)
        // isWindingDown reste true jusqu'après la présentation/restauration pour bloquer tout
        // saveCurrentSoloGameState() déclenché par willResignActive dans la micro-fenêtre
        // entre la réinitialisation du modèle (grille vide) et la restauration de la sauvegarde solo.
        // presentStartScreen → isStartScreen = true (prochaine sauvegarde légitimement bloquée).
        // restoreFromSoloSave → isStartScreen = false mais state solo correctement reconstruit.
        if restoreSave {
            presentStartScreenOrRestoreSoloSave()
        } else {
            presentStartScreen()
        }
        isWindingDown = false
    }

    /// Après Game Over : nettoie la scène, réinitialise le modèle, affiche de nouveau l’écran d’accueil.
    private func returnToStartScreenFromGameOver() {
        guard isGameOver else { return }
        unwindToStartScreen()
    }

    /// Bouton **New Game** : retour menu depuis une partie active (hors flux Game Over).
    private func returnToStartScreenFromNewGameButton() {
        guard !isStartScreen else { return }

        // Partie solo active (pas PvP, pas encore terminée) → demander confirmation.
        if pvpCoordinator == nil, !isGameOver {
            confirmQuitSoloThenUnwind()
            return
        }

        // En PvP actif (partie commencée, pas encore terminée) : le joueur local abandonne → défaite.
        if let coord = pvpCoordinator, coord.isGameActive, !isGameOver {
            blomixPvP_finalizeEloIfNeeded(outcome: .loss)
            coord.forfeitMatch()
        }
        unwindToStartScreen()
    }

    /// Affiche la dialog SpriteKit de confirmation avant de quitter une partie solo.
    /// Les boutons sont détectés dans `touchesBegan` via `pendingButtonAction` (fire-on-release).
    private func confirmQuitSoloThenUnwind() {
        showQuitConfirmOverlay()
    }

    private func showQuitConfirmOverlay() {
        childNode(withName: Self.quitConfirmOverlayName)?.removeFromParent()

        let overlay = SKNode()
        overlay.name      = Self.quitConfirmOverlayName
        overlay.zPosition = 250   // au-dessus de tout (game over = 200, start screen = 120)
        addChild(overlay)

        // Fond assombri plein écran.
        let dim = SKSpriteNode(color: .black, size: size)
        dim.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        dim.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.alpha       = 0.78
        dim.zPosition   = 0
        overlay.addChild(dim)

        // Panneau central arrondi.
        let panelW: CGFloat = min(300, size.width - 48)
        let panelH: CGFloat = 185
        let panelRect = CGRect(x: -panelW / 2, y: -panelH / 2, width: panelW, height: panelH)
        let panel = SKShapeNode(rect: panelRect, cornerRadius: 14)
        panel.fillColor   = SKColor(white: 0.10, alpha: 1)
        panel.strokeColor = SKColor(white: 0.28, alpha: 1)
        panel.lineWidth   = 0.75
        panel.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.zPosition   = 1
        overlay.addChild(panel)

        // Titre.
        let title = SKLabelNode(text: BlomixL10n.quitConfirmTitle)
        title.fontName                = Self.customUIFontPostScriptName
        title.fontSize                = 18
        title.fontColor               = .white
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.position                = CGPoint(x: 0, y: 66)
        title.zPosition               = 2
        panel.addChild(title)

        // Message (multi-lignes).
        let msg = SKLabelNode(text: BlomixL10n.quitConfirmMessage)
        msg.fontName                = Self.customUIFontPostScriptName
        msg.fontSize                = 13
        msg.fontColor               = SKColor(white: 0.75, alpha: 1)
        msg.horizontalAlignmentMode = .center
        msg.verticalAlignmentMode   = .center
        msg.numberOfLines           = 0
        msg.preferredMaxLayoutWidth = panelW - 32
        msg.position                = CGPoint(x: 0, y: 24)
        msg.zPosition               = 2
        panel.addChild(msg)

        // Boutons côte à côte.
        let btnFontSize = BlomixUIDestinationButtonStyle.navigationTitleFontSize
        let btnSize = BlomixSKButtonNode.unifiedSize(
            for: [BlomixL10n.quitConfirmQuit, BlomixL10n.cancel],
            fontSize: btnFontSize,
            maxWidth: (panelW - 40) / 2
        )
        let gap: CGFloat  = 10
        let btnY: CGFloat = -panelH / 2 + btnSize.height / 2 + 14

        let btnCancel = BlomixSKButtonNode(
            name: Self.quitConfirmBtnCancelName,
            text: BlomixL10n.cancel,
            size: btnSize,
            fontSize: btnFontSize
        )
        btnCancel.position = CGPoint(x: -(btnSize.width / 2 + gap / 2), y: btnY)
        btnCancel.zPosition = 2
        panel.addChild(btnCancel)

        let btnQuit = BlomixSKButtonNode(
            name: Self.quitConfirmBtnQuitName,
            text: BlomixL10n.quitConfirmQuit,
            size: btnSize,
            fontSize: btnFontSize
        )
        btnQuit.position = CGPoint(x: btnSize.width / 2 + gap / 2, y: btnY)
        btnQuit.zPosition = 2
        panel.addChild(btnQuit)

        overlay.alpha = 0
        overlay.run(SKAction.fadeIn(withDuration: 0.16))
    }

    private func dismissQuitConfirmOverlay() {
        childNode(withName: Self.quitConfirmOverlayName)?.removeFromParent()
    }

    // MARK: - Chaînes (résolution)

    /// Points par chaîne : vague de base = nombre de blox (5→5, 6→6, …) ; en cascade = ce total + 5 (5→10, 6→11, …).
    private static func chainClearScorePoints(chainSeriesLevel: Int, groupSize: Int) -> Int {
        let base: Int
        switch groupSize {
        case ..<6:  base = 5
        case 6:     base = 7
        case 7:     base = 10
        case 8:     base = 13
        case 9:     base = 15
        default:    base = 20   // 10 blox et plus
        }
        return base + chainSeriesLevel * 10
    }

    /// Toutes les composantes **8-connexes** de `.color` d’au moins **5** cases (chaque groupe = une entrée pour le scoring web).
    private func findWinningChainComponents() -> [Set<GridAddress>] {
        var globallyVisited = Set<GridAddress>()
        var components: [Set<GridAddress>] = []

        for row in GridLayout.topRowIndex..<GridLayout.rowCount {
            for col in 0..<GridLayout.columnCount {
                let start = GridAddress(row: row, col: col)
                guard !globallyVisited.contains(start) else { continue }
                guard case .color(let colorName) = grid[row][col] else { continue }

                let component = collectColorComponent8(
                    start: start,
                    colorName: colorName,
                    globallyVisited: &globallyVisited
                )
                guard component.count >= 5 else { continue }
                components.append(component)
            }
        }
        return components
    }

    /// Toute case `.priks` dont au moins un **voisin 8-con** est dans `touchingRemovedCells` perd **1** sur son compteur
    /// pour cette vague (même idée que `priksAffected` dans `priks.html` : un Priks ne perd qu’au plus un point par résolution).
    /// Compteur ≤ 0 → la case devient `.empty` (disparition + bonus +10).
    /// - Returns: Cellules Priks effectivement supprimées (compteur arrivé à 0), pour animation visuelle.
    private func applyPriksAdjacentDecrement(touchingRemovedCells: Set<GridAddress>) -> Set<GridAddress> {
        guard !touchingRemovedCells.isEmpty else { return [] }
        var vanishedPriks = Set<GridAddress>()

        for row in GridLayout.topRowIndex..<GridLayout.rowCount {
            for col in 0..<GridLayout.columnCount {
                guard case .priks(let remaining) = grid[row][col], remaining > 0 else { continue }

                var touchesRemovedChain = false
                for delta in Self.chainNeighborDeltas8 {
                    let nr = row + delta.dr
                    let nc = col + delta.dc
                    guard nr >= GridLayout.topRowIndex, nr < GridLayout.rowCount,
                          nc >= 0, nc < GridLayout.columnCount else { continue }
                    if touchingRemovedCells.contains(GridAddress(row: nr, col: nc)) {
                        touchesRemovedChain = true
                        break
                    }
                }
                guard touchesRemovedChain else { continue }

                let next = remaining - 1
                if next <= 0 {
                    grid[row][col] = .empty
                    let cell = GridAddress(row: row, col: col)
                    vanishedPriks.insert(cell)
                    // Bonus Priks : affiché après l’animation de disparition (évite que le gros « +10 » masque le spin).
                } else {
                    grid[row][col] = .priks(next)
                    if isTutorialMode { tutorialPriksDecremented() }
                }
            }
        }
        return vanishedPriks
    }

    /// Retourne le nombre de Priks adjacents (8-voisinage) à `touchingRemovedCells` qui ont
    /// `remaining == 1` et disparaîtront après le décrement — lecture seule, grille inchangée.
    private func countPriksAboutToVanish(touchingRemovedCells: Set<GridAddress>) -> Int {
        guard !touchingRemovedCells.isEmpty else { return 0 }
        var count = 0
        for row in GridLayout.topRowIndex..<GridLayout.rowCount {
            for col in 0..<GridLayout.columnCount {
                guard case .priks(let remaining) = grid[row][col], remaining == 1 else { continue }
                for delta in Self.chainNeighborDeltas8 {
                    let nr = row + delta.dr
                    let nc = col + delta.dc
                    guard nr >= GridLayout.topRowIndex, nr < GridLayout.rowCount,
                          nc >= 0, nc < GridLayout.columnCount else { continue }
                    if touchingRemovedCells.contains(GridAddress(row: nr, col: nc)) {
                        count += 1
                        break
                    }
                }
            }
        }
        return count
    }

    /// Anime la disparition des Priks arrivés à 0 (tournoiement rapide + fade), puis appelle `completion`.
    private func animateVanishingPriks(cells: Set<GridAddress>, completion: @escaping () -> Void) {
        guard !cells.isEmpty else {
            completion()
            return
        }
        guard let container = childNode(withName: Self.gridContainerName) else {
            completion()
            return
        }

        // Sons staggerés synchronisés avec le début de la disparition visuelle.
        // Stagger 0.07 s entre chaque Brix si plusieurs disparaissent simultanément.
        for i in 0..<cells.count {
            if i == 0 {
                playMatchSound(.priksVanish)
            } else {
                run(SKAction.sequence([
                    SKAction.wait(forDuration: TimeInterval(i) * 0.07),
                    SKAction.run { [weak self] in self?.playMatchSound(.priksVanish) },
                ]))
            }
        }

        for cell in cells {
            let nodeName = "cell_\(cell.row)_\(cell.col)"
            guard let sprite = container.childNode(withName: nodeName) as? SKSpriteNode else { continue }
            sprite.zPosition = 26

            let spin = SKAction.rotate(byAngle: .pi * 2, duration: ChainClearFeedback.priksVanishDuration)
            spin.timingMode = .easeIn
            let fade = SKAction.fadeAlpha(to: 0, duration: ChainClearFeedback.priksVanishDuration)
            fade.timingMode = .easeIn
            let shrink = SKAction.scale(to: max(0.6, sprite.xScale * 0.65), duration: ChainClearFeedback.priksVanishDuration)
            shrink.timingMode = .easeIn
            sprite.run(SKAction.group([spin, fade, shrink]))
        }

        run(
            SKAction.sequence([
                SKAction.wait(forDuration: ChainClearFeedback.priksVanishDuration),
                SKAction.run(completion),
            ])
        )
    }

    /// Supprime les chaînes (≥ 5, 8-voisinage, même couleur) après une **animation de dissolution** sur les sprites,
    /// puis **disparition** (vidage + Priks), `drawGrid()`, compactage **vers le haut** avec **animation de remontée**
    /// (`SKAction.move`, easeOut, en parallèle), resync, et **re-scan** pour les **cascades**. Quand plus aucun groupe
    /// n’existe, libère le joueur.
    ///
    /// - Priks : décrémentés s’ils touchent la chaîne supprimée ; **ligne des 10 coups** via `moveCount` / `addRandomLine()`.
    /// - `isProcessing` doit déjà être `true` lors de l’appel depuis `dropBlock` ; reste `true` pendant les animations et entre cascades.
    private func resolveChains() {
        let components = findWinningChainComponents()
        let winningCells: Set<GridAddress> = components.reduce(into: Set()) { $0.formUnion($1) }

        // Aucune chaîne : fin de vague / de partie — reset du combo (`priks.html` : `else { chainSeriesLevel = 0 }` dans la boucle).
        guard !winningCells.isEmpty else {
            chainSeriesLevel = 0
            if shouldRunPostPlacementHooks {
                shouldRunPostPlacementHooks = false
                moveCount += 1
                refreshLigneCounterHUD()
                let decade = moveCount > 0 && moveCount % 10 == 0
                // Ligne de décennie différée (clash attaque + décennie au bloc précédent)
                if pvpNeedsDecadeLineAfterAttackInjection {
                    pvpNeedsDecadeLineAfterAttackInjection = false
                    switch addRandomLinePushingGridUp() {
                    case .animating:
                        if decade { pvpNeedsDecadeLineAfterAttackInjection = true }
                        return
                    case .gameOver:
                        return
                    case .didNotRun:
                        break
                    }
                }
                if let atk = pvpCoordinator?.consumeNextIncomingAttackLineIfAny() {
                    nextBottomLine = atk
                    switch addRandomLinePushingGridUp() {
                    case .animating:
                        if decade { pvpNeedsDecadeLineAfterAttackInjection = true }
                        return
                    case .gameOver:
                        return
                    case .didNotRun:
                        break
                    }
                }
                if decade {
                    switch addRandomLinePushingGridUp() {
                    case .animating:
                        return
                    case .gameOver:
                        return
                    case .didNotRun:
                        break
                    }
                }
            }
            if !isInjectingBottomRandomLine, !isGameOver {
                isProcessing = false
                pvpCoordinator?.sceneBecameIdleForLocalTurn()
                refreshPendingBottomLinePreview()
                // Jitter sur le bloc courant si c'est le dernier avant la ligne entrante.
                // updatePreviewSprite() est appelé dans dropBlock AVANT moveCount += 1 ;
                // on corrige ici, une fois moveCount à jour, pour cibler le bon bloc.
                if moveCount % 10 == 9 {
                    startPreviewJitter()
                }
                triggerMoveAnalysis()
                // Vérifier passage de stage APRÈS les animations ; si avance → l'overlay relance le timer
                // lui-même dans sa completion. Sinon on relance directement.
                let stageBeforeCheck = currentStageIndex
                checkStageAdvance()
                if currentStageIndex == stageBeforeCheck {
                    restartStageTimer()
                }
            }
            drawGrid()
            return
        }

        let largestChainSize = components.map { $0.count }.max() ?? 5
        playChainClearSound(largestChainSizeInWave: largestChainSize)

        chainClearWaveCount += 1
        updateBombHUD()

        // Score : **une** attribution par composante ≥ 5, même `chainSeriesLevel` pour toutes les composantes de cette vague.
        // La couleur de la composante est extraite (première cellule .color) pour teinter les dots et le label.
        for component in components {
            let pts = Self.chainClearScorePoints(chainSeriesLevel: chainSeriesLevel, groupSize: component.count)
            let floatAt = sceneCentroid(for: component)
            let dotColor: SKColor? = component.lazy.compactMap { [self] addr -> SKColor? in
                if case .color(let name) = self.grid[addr.row][addr.col] {
                    return Self.bloxTrailColor(for: .color(name))
                }
                return nil
            }.first
            addScore(points: pts, chainMultiplier: chainSeriesLevel, floatAt: floatAt, dotColor: dotColor)
        }

        // Popup « COMBO » / « SUPER COMBO » à partir du niveau 2 de cascade.
        // Couleur = celle de la plus grande composante (lue avant que la grille soit effacée).
        // Position = centroïde de toutes les composantes de la vague.
        if chainSeriesLevel >= 1 {
            let allCells = Set(components.flatMap { $0 })
            let center   = sceneCentroid(for: allCells)
            let largest  = components.max(by: { $0.count < $1.count }) ?? []
            let blockType: BlockType = largest.lazy.compactMap { [self] addr -> BlockType? in
                let bt = self.grid[addr.row][addr.col]
                if case .color = bt { return bt }
                return nil
            }.first ?? .empty
            let color = Self.bloxTrailColor(for: blockType)
            spawnComboLabelPopup(level: chainSeriesLevel, at: center, color: color)
        }

        if isTutorialMode { tutorialChainDetected() }

        // Dissolution sur les **sprites** existants ; la grille logique reste inchangée jusqu’à `applyChainClearPhysicalWave`.
        animateWinningChainDisappearance(components: components) { [weak self] in
            guard let self else { return }
            self.applyChainClearPhysicalWave(winningCells: winningCells)
        }
    }

    /// Ordre stable pour le stagger : chaque composante, cases triées par `(ligne, colonne)`.
    private static func orderedChainRemovalCells(from components: [Set<GridAddress>]) -> [GridAddress] {
        components.flatMap { cells in
            cells.sorted { a, b in
                if a.row != b.row { return a.row < b.row }
                return a.col < b.col
            }
        }
    }

    /// Dissolution (scale ×1.20 sans couleur, rétrécissement avec éclaircissement + pop paillettes, fondu)
    /// avec décalage case par case ; grille **non** mutée avant `completion`.
    private func animateWinningChainDisappearance(
        components: [Set<GridAddress>],
        completion: @escaping () -> Void
    ) {
        let ordered = Self.orderedChainRemovalCells(from: components)
        guard !ordered.isEmpty else {
            completion()
            return
        }
        guard let container = childNode(withName: Self.gridContainerName) as? SKNode else {
            completion()
            return
        }

        hapticLight()
        let chainCells = Set(ordered)
        let stagger  = ChainClearFeedback.dissolveStagger
        let cellAnim = ChainClearFeedback.dissolvePerCellAnimationDuration
        let tail     = Double(max(ordered.count - 1, 0)) * stagger + cellAnim
        removeBloxJunctionElementsTouching(chainCells)

        let zDuringDissolve: CGFloat = 24

        for (index, address) in ordered.enumerated() {
            let nodeName = "cell_\(address.row)_\(address.col)"
            guard let sprite = container.childNode(withName: nodeName) as? SKSpriteNode else { continue }

            let baseColor  = sprite.color
            let blockType  = grid[address.row][address.col]
            let dotColor   = Self.bloxTrailColor(for: blockType)
            let peakColor  = Self.skColorLerp(baseColor, .white, ChainClearFeedback.dissolveBrightenTowardWhite)
            let baseScale  = sprite.xScale

            let wait = SKAction.wait(forDuration: Double(index) * stagger)

            let slotSize = CGSize(width: GridLayout.cellPoints - 4,
                                  height: GridLayout.cellPoints - 4)
            let prep = SKAction.run {
                sprite.zPosition = zDuringDissolve
                // Sprite de fond vide inséré juste avant la dissolution :
                // pendant le fondu du blox (alpha 1→0), ce placeholder gris empêche
                // le fond noir de la scène de transparaître. drawGrid() le supprimera
                // automatiquement (préfixe "cell_").
                let bg = SKSpriteNode(color: SKColor(white: 0.12, alpha: 1), size: slotSize)
                bg.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                bg.position    = sprite.position
                bg.zPosition   = 0
                bg.name        = "cell_dissolve_bg_\(address.row)_\(address.col)"
                container.addChild(bg)
            }

            // Phase 1 : grossissement ×1.20, pas d'éclaircissement
            let scaleUp = SKAction.scale(to: baseScale * 1.30,
                                         duration: ChainClearFeedback.dissolveScaleUpDuration)
            scaleUp.timingMode = .easeOut

            // Phase 2 : au pic → pop de paillettes de la couleur exacte du blox
            let popDots = SKAction.run { [weak self] in
                guard let self else { return }
                let scenePoint = self.convert(sprite.position, from: container)
                self.spawnChainPopDots(at: scenePoint, color: dotColor)
            }

            // Phase 2 (suite) : rétrécissement + éclaircissement simultanés
            let brighten = SKAction.customAction(
                withDuration: ChainClearFeedback.dissolveScaleDownDuration
            ) { node, elapsed in
                guard let s = node as? SKSpriteNode else { return }
                let t = CGFloat(elapsed / ChainClearFeedback.dissolveScaleDownDuration)
                s.color = Self.skColorLerp(baseColor, peakColor, min(1, max(0, t)))
            }

            let scaleDown = SKAction.scale(to: baseScale,
                                           duration: ChainClearFeedback.dissolveScaleDownDuration)
            scaleDown.timingMode = .easeInEaseOut

            // Phase 3 : fondu (inchangé)
            let fade = SKAction.fadeAlpha(to: 0, duration: ChainClearFeedback.dissolveFadeDuration)

            let dissolve = SKAction.sequence([
                scaleUp,
                popDots,
                SKAction.group([scaleDown, brighten]),
                fade,
            ])

            sprite.run(SKAction.sequence([wait, prep, dissolve]))
        }

        run(SKAction.sequence([SKAction.wait(forDuration: tail), SKAction.run(completion)]))
    }

    /// Paillettes de dissolution : cercles colorés éparpillés aléatoirement dans la case,
    /// qui tombent lentement vers le bas en s'effaçant.
    private func spawnChainPopDots(at scenePoint: CGPoint, color: SKColor) {
        let cellHalf = GridLayout.cellPoints * 0.42   // ≈16 pt de demi-case
        let duration = ChainClearFeedback.popDotFadeDuration

        // Dots principaux (inchangés) : 7–10, rayon 2.0–3.5 pt.
        let count = Int.random(in: 7...10)
        for _ in 0..<count {
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: ChainClearFeedback.popDotRadiusRange))
            dot.fillColor   = color
            dot.strokeColor = .clear
            dot.alpha       = 1.0
            dot.zPosition   = 36
            dot.position = CGPoint(
                x: scenePoint.x + CGFloat.random(in: -cellHalf...cellHalf),
                y: scenePoint.y + CGFloat.random(in: -cellHalf...cellHalf)
            )
            addChild(dot)
            let move = SKAction.moveBy(x: 0, y: -CGFloat.random(in: ChainClearFeedback.popDotFallDistance), duration: duration)
            move.timingMode = .easeIn
            dot.run(SKAction.sequence([
                SKAction.group([move, SKAction.fadeOut(withDuration: duration)]),
                SKAction.removeFromParent(),
            ]))
        }

        // Micro-dots supplémentaires : 10, rayon 1.5 pt, même timing et répartition.
        for _ in 0..<10 {
            let dot = SKShapeNode(circleOfRadius: 1.5)
            dot.fillColor   = color
            dot.strokeColor = .clear
            dot.alpha       = 1.0
            dot.zPosition   = 36
            dot.position = CGPoint(
                x: scenePoint.x + CGFloat.random(in: -cellHalf...cellHalf),
                y: scenePoint.y + CGFloat.random(in: -cellHalf...cellHalf)
            )
            addChild(dot)
            let move = SKAction.moveBy(x: 0, y: -CGFloat.random(in: ChainClearFeedback.popDotFallDistance), duration: duration)
            move.timingMode = .easeIn
            dot.run(SKAction.sequence([
                SKAction.group([move, SKAction.fadeOut(withDuration: duration)]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    /// Après la dissolution : vide la chaîne, Priks, `drawGrid()`, animation de remontée si besoin, puis cascade.
    private func applyChainClearPhysicalWave(winningCells: Set<GridAddress>) {
        let columnHadBlockBefore: [Bool] = (0..<GridLayout.columnCount).map { col in
            (GridLayout.topRowIndex..<GridLayout.rowCount).contains { grid[$0][col] != .empty }
        }

        for address in winningCells {
            let row = address.row
            let col = address.col
            guard row >= GridLayout.topRowIndex, row < GridLayout.rowCount,
                  col >= 0, col < GridLayout.columnCount else { continue }
            grid[row][col] = .empty
        }

        let vanishedPriks = applyPriksAdjacentDecrement(touchingRemovedCells: winningCells)

        let continueWithCompaction: () -> Void = { [weak self] in
            guard let self else { return }
            // Grille logique encore **non compactée** : `drawGrid()` place les sprites exactement là où ils sont,
            // y compris les trous — c’est la pose de départ pour l’animation de remontée.
            self.drawGrid()

            let riseMoves = self.computeCompactRiseMovesReadingCurrentGrid()
            self.compactGridTowardTop()

            guard let container = self.childNode(withName: Self.gridContainerName) else {
                self.drawGrid()
                self.awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
                self.finishChainWaveAfterPhysicalPhase()
                return
            }

            if riseMoves.isEmpty {
                self.drawGrid()
                self.awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
                self.finishChainWaveAfterPhysicalPhase()
                return
            }

            let movingSourceCells = Set(riseMoves.map { GridAddress(row: $0.fromRow, col: $0.column) })
            self.removeBloxJunctionElementsTouching(movingSourceCells)

            for move in riseMoves {
                guard move.column >= 0, move.column < GridLayout.columnCount,
                      move.fromRow >= GridLayout.topRowIndex, move.fromRow < GridLayout.rowCount,
                      move.toRow >= GridLayout.topRowIndex, move.toRow < GridLayout.rowCount else { continue }

                let nodeName = "cell_\(move.fromRow)_\(move.column)"
                guard let sprite = container.childNode(withName: nodeName) as? SKSpriteNode else { continue }

                let targetLocal = Self.gridContainerLocalCellCenter(row: move.toRow, column: move.column)
                let moveAction = SKAction.move(to: targetLocal, duration: CompactRiseAnimation.duration)
                moveAction.timingMode = .easeOut
                sprite.run(moveAction)
            }

            self.run(
                SKAction.sequence([
                    SKAction.wait(forDuration: CompactRiseAnimation.duration),
                    SKAction.run { [weak self] in
                        guard let self else { return }
                        self.drawGrid()
                        self.awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
                        self.finishChainWaveAfterPhysicalPhase()
                    },
                ])
            )
        }

        guard !vanishedPriks.isEmpty else {
            continueWithCompaction()
            return
        }

        // Le son prix.wav est joué en amont dans resolveChains() (avant chain_new.wav).
        animateVanishingPriks(cells: vanishedPriks) { [weak self] in
            guard let self else { return }
            let bonus = vanishedPriks.count * 20
            if bonus > 0 {
                let floatAt = self.sceneCentroid(for: vanishedPriks)
                self.addScore(points: bonus, chainMultiplier: 0, floatAt: floatAt)
            }
            continueWithCompaction()
        }
    }

    /// +10 par colonne passée entièrement vide alors qu’elle contenait au moins un bloc avant cette vague.
    private func awardFullyClearedColumnBonuses(columnHadBlockBefore: [Bool]) {
        // Collecte les colonnes vidées de gauche à droite.
        let clearedCols = (0..<GridLayout.columnCount).filter { col in
            columnHadBlockBefore[col] &&
            (GridLayout.topRowIndex..<GridLayout.rowCount).allSatisfy { grid[$0][col] == .empty }
        }
        guard !clearedCols.isEmpty else { return }

        // Stagger gauche → droite : chaque colonne se décale de 90 ms par rapport à la précédente.
        let stagger: TimeInterval = 0.09
        for (i, col) in clearedCols.enumerated() {
            let floatAt = scenePointCellCenter(row: GridLayout.topRowIndex, column: col)
            run(SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * stagger),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    self.playMatchSound(.emptyColumnClear)
                    self.addScore(points: 10, chainMultiplier: 0, floatAt: floatAt)
                },
            ]))
        }
    }

    /// Barycentre des centres cases (affichage +points sur la chaîne).
    private func sceneCentroid(for cells: Set<GridAddress>) -> CGPoint {
        guard !cells.isEmpty else { return gridAreaCenter }
        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for cell in cells {
            let p = scenePointCellCenter(row: cell.row, column: cell.col)
            sx += p.x
            sy += p.y
        }
        let n = CGFloat(cells.count)
        return CGPoint(x: sx / n, y: sy / n)
    }

    /// Incrémente `chainSeriesLevel` pour la **prochaine** cascade, courte pause, puis re-scan (sans nouvelle dissolution).
    private func finishChainWaveAfterPhysicalPhase() {
        chainSeriesLevel += 1
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: ChainClearFeedback.cascadeBeatDuration),
                SKAction.run { [weak self] in
                    self?.resolveChains()
                },
            ])
        )
    }

    /// Ajoute les points au total, met à jour le label ; `chainMultiplier` = `chainSeriesLevel` **utilisé** pour ce gain (animation un peu plus forte en combo).
    /// `floatAt` : affiche « +N » à cet endroit (fade légèrement plus lent pour une meilleure lisibilité).
    private func addScore(points: Int, chainMultiplier: Int, floatAt scenePoint: CGPoint? = nil, dotColor: SKColor? = nil) {
        guard points > 0 else { return }
        let multipliedPoints = isInStagedSoloMode ? points * currentStageConfig.multiplier : points
        let scoreBefore = score
        score += multipliedPoints
        let thousandAfter  = (score      / 1000) * 1000
        let thousandBefore = (scoreBefore / 1000) * 1000
        let hundredAfter   = (score      / 100)  * 100
        let hundredBefore  = (scoreBefore / 100)  * 100
        if thousandAfter > thousandBefore, thousandAfter > 0 {
            lastScoreHundredMilestone = thousandAfter
            pendingMilestoneExplosion = .thousand
        } else if hundredAfter > hundredBefore, hundredAfter > 0 {
            lastScoreHundredMilestone = hundredAfter
            pendingMilestoneExplosion = .hundred
        }
        if score > hudBestScoreValue {
            applyBestScoreHUDValue(score, isLiveBeat: true)
        }
        if pvpCoordinator?.localScoreDidUpdate(score) == true {
            triggerPvPAttackSentVisuals()
        }
        if let p = scenePoint {
            spawnFloatingScorePopup(points: multipliedPoints, at: p, dotColor: dotColor) { [weak self] in
                self?.applyDisplayedScoreIncrement(points: multipliedPoints, chainMultiplier: chainMultiplier, scoreColor: dotColor)
            }
            return
        }
        applyDisplayedScoreIncrement(points: multipliedPoints, chainMultiplier: chainMultiplier)
    }

    private func applyDisplayedScoreIncrement(points: Int, chainMultiplier: Int, scoreColor: SKColor? = nil) {
        guard points > 0 else { return }
        displayedScore += points
        displayedScore = min(displayedScore, score)
        guard let label = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode else { return }

        // Déclenche l'explosion de milestone en même temps que le début du rolling counter.
        switch pendingMilestoneExplosion {
        case .thousand: spawnScoreThousandExplosion()
        case .hundred:  spawnScoreMilestoneExplosion()
        case .none:     break
        }
        pendingMilestoneExplosion = .none

        // ── Rolling counter ──────────────────────────────────────────────────────
        // Repart de la valeur *actuellement affichée* (mid-animation si une montée
        // est déjà en cours) vers le nouveau target.  Chaque incrément relance
        // l'animation depuis là où le texte en est, donnant un effet de "chasse".
        scoreRollStart  = Int(label.text ?? "0") ?? 0
        scoreRollTarget = displayedScore
        let gain = max(1, scoreRollTarget - scoreRollStart)
        let rollDuration = min(0.60, 0.40 + Double(gain) / 2000.0 * 0.20)

        label.removeAction(forKey: Self.scoreRollActionKey)
        let roll = SKAction.customAction(withDuration: rollDuration) { [weak self] node, elapsed in
            guard let self, let lbl = node as? SKLabelNode else { return }
            let t = min(1, CGFloat(elapsed) / CGFloat(rollDuration))
            // Ease-out cubique : démarre vite, finit en douceur.
            let eased = 1 - pow(1 - t, 3)
            let shown = Int(CGFloat(self.scoreRollStart) + eased * CGFloat(self.scoreRollTarget - self.scoreRollStart))
            lbl.text = "\(shown)"
        }
        label.run(roll, withKey: Self.scoreRollActionKey)

        // ── Flash couleur de chaîne → retour au blanc ────────────────────────────
        // Déclenché uniquement quand les dots viennent d'une chaîne colorée.
        if let scoreColor {
            var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
            scoreColor.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
            label.removeAction(forKey: "scoreColorFlash")
            label.fontColor = scoreColor
            // Retour au blanc après le rolling counter.
            let fadeBack = SKAction.customAction(withDuration: 0.30) { node, elapsed in
                guard let lbl = node as? SKLabelNode else { return }
                let t = min(1, CGFloat(elapsed) / 0.30)
                lbl.fontColor = SKColor(red: cr + (1-cr)*t, green: cg + (1-cg)*t, blue: cb + (1-cb)*t, alpha: 1)
            }
            label.run(SKAction.sequence([
                SKAction.wait(forDuration: rollDuration),
                fadeBack,
                SKAction.run { label.fontColor = .white },
            ]), withKey: "scoreColorFlash")
        }

        // ── Bump de scale (inchangé) ─────────────────────────────────────────────
        // Plancher x1.2 à chaque arrivée de dots ; le chainMultiplier amplifie jusqu'à x1.38.
        label.removeAction(forKey: Self.scorePulseActionKey)
        let peakScale = 1.2 + min(CGFloat(max(0, chainMultiplier)), 6) * 0.03
        let pulse = SKAction.sequence([
            SKAction.scale(to: peakScale, duration: 0.33),
            SKAction.scale(to: 1.0,       duration: 0.11),
        ])
        pulse.timingMode = .easeOut
        label.run(pulse, withKey: Self.scorePulseActionKey)
    }

    private func spawnFloatingScorePopup(points: Int, at scenePoint: CGPoint, dotColor: SKColor? = nil, onTransferArrival: @escaping () -> Void) {
        let text = SKLabelNode(text: "+\(points)")
        text.fontName = Self.customUIFontPostScriptName
        text.fontSize = 62
        text.fontColor = dotColor ?? .white
        text.horizontalAlignmentMode = .center
        text.verticalAlignmentMode = .center
        text.position = scenePoint
        text.setScale(0.12)
        text.alpha = 1
        text.zPosition = 35
        addChild(text)

        // Grow à pleine opacité, puis fondu + légère décroissance simultanés pour une sortie souple.
        let grow = SKAction.scale(to: 1.0, duration: 0.58)
        grow.timingMode = .easeOut
        let shrink = SKAction.scale(to: 0.72, duration: 0.33)
        shrink.timingMode = .easeIn
        let fade = SKAction.fadeOut(withDuration: 0.33)
        text.run(SKAction.sequence([
            grow,
            SKAction.group([shrink, fade]),
            SKAction.removeFromParent(),
        ]))

        spawnScoreTransferDots(points: points, from: scenePoint, color: dotColor ?? .white)

        run(
            SKAction.sequence([
                SKAction.wait(forDuration: ScorePopupFeedback.transferPostPopupFlightDuration),
                SKAction.run(onTransferArrival),
            ])
        )
    }

    // MARK: - Combo label popup (cascade niveaux 2 et 3+)

    /// Affiche « COMBO » (cascade niveau 2) ou « SUPER / COMBO » (cascade niveau 3+) au centroïde de la vague.
    /// La couleur reprend celle de la composante la plus grande.
    private func spawnComboLabelPopup(level: Int, at position: CGPoint, color: SKColor) {
        let delay: TimeInterval = 0.45

        let container = SKNode()
        container.position = position
        container.setScale(0.12)
        container.alpha   = 1
        container.zPosition = 37        // au-dessus du "+N" (zPos 35)
        addChild(container)

        let font = Self.customUIFontPostScriptName
        let fSize: CGFloat = 62
        let lineSpacing: CGFloat = 56

        func makeLabel(_ text: String, yOffset: CGFloat) -> SKLabelNode {
            let lbl = SKLabelNode(text: text)
            lbl.fontName = font
            lbl.fontSize = fSize
            lbl.fontColor = color   // couleur de la composante (différence intentionnelle vs "+N" blanc)
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode   = .center
            lbl.position = CGPoint(x: 0, y: yOffset)
            return lbl
        }

        if level >= 2 {
            container.addChild(makeLabel("SUPER", yOffset:  lineSpacing / 2))
            container.addChild(makeLabel("COMBO", yOffset: -lineSpacing / 2))
        } else {
            container.addChild(makeLabel("COMBO", yOffset: 0))
        }

        // Mêmes paramètres que le "+N" : grow à pleine opacité, puis shrink + fade simultanés.
        let grow = SKAction.scale(to: 1.0, duration: 0.58)
        grow.timingMode = .easeOut
        let shrink = SKAction.scale(to: 0.72, duration: 0.33)
        shrink.timingMode = .easeIn
        let fade = SKAction.fadeOut(withDuration: 0.33)

        // SUPER COMBO (level ≥ 2) : shake un peu plus marqué.
        let shakeIntensity: CGFloat = level >= 2 ? 2.0 : 1.4
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in self?.shakeScreen(intensity: shakeIntensity) },
            grow,
            SKAction.group([shrink, fade]),
            SKAction.removeFromParent(),
        ]))
    }

    /// Points de score : blancs par défaut, ou de la couleur de la chaîne si `color` est fourni.
    private func spawnScoreTransferDots(points: Int, from sourceCenter: CGPoint, color: SKColor = .white) {
        guard points > 0 else { return }
        guard let scoreLabel = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode else { return }
        let targetFrame = scoreLabel.calculateAccumulatedFrame()
        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let rawCount = Int((CGFloat(points) * ScorePopupFeedback.dotsPerPoint).rounded())
        let dotCount = min(ScorePopupFeedback.maxDots, max(ScorePopupFeedback.minDots, rawCount))
        spawnTransferDots(count: dotCount, from: sourceCenter, to: targetCenter, color: color, onArrival: nil)
    }

    /// Moteur générique de transfert de dots entre deux nœuds.
    /// `onArrival` est appelé une seule fois quand le dernier dot arrive.
    private func spawnTransferDots(count: Int, from sourceCenter: CGPoint, to targetCenter: CGPoint, flightDuration: TimeInterval = ScorePopupFeedback.transferDuration, color: SKColor = .white, onArrival: (() -> Void)?) {
        guard count > 0 else { return }
        let totalFlight = ScorePopupFeedback.transferStartFadeDuration
                        + ScorePopupFeedback.radialBurstDuration
                        + ScorePopupFeedback.transferDuration

        for i in 0..<count {
            let radius = CGFloat.random(in: ScorePopupFeedback.transferDotRadiusRange)
            let dot = SKShapeNode(circleOfRadius: radius)
            dot.fillColor = color
            dot.strokeColor = .clear
            dot.alpha = 0
            dot.zPosition = 36

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist = CGFloat.random(in: 0...ScorePopupFeedback.transferStartSpreadRadius)
            let spawn = CGPoint(
                x: sourceCenter.x + cos(angle) * dist,
                y: sourceCenter.y + sin(angle) * dist
            )
            dot.position = spawn
            addChild(dot)

            let burstAngle = CGFloat.random(in: 0...(2 * .pi))
            let burstDist = CGFloat.random(in: ScorePopupFeedback.radialBurstDistance)
            let burstOffset = CGPoint(x: cos(burstAngle) * burstDist, y: sin(burstAngle) * burstDist)
            let postBurst = CGPoint(x: spawn.x + burstOffset.x, y: spawn.y + burstOffset.y)

            let destination = CGPoint(
                x: targetCenter.x + CGFloat.random(in: -ScorePopupFeedback.transferTargetJitterX...ScorePopupFeedback.transferTargetJitterX),
                y: targetCenter.y + CGFloat.random(in: -ScorePopupFeedback.transferTargetJitterY...ScorePopupFeedback.transferTargetJitterY)
            )

            let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: ScorePopupFeedback.transferStartFadeDuration)
            fadeIn.timingMode = .easeOut
            let burst = SKAction.move(to: postBurst, duration: ScorePopupFeedback.radialBurstDuration)
            burst.timingMode = .easeOut
            let move = SKAction.move(to: destination, duration: flightDuration)
            move.timingMode = .easeIn

            // Appeler onArrival seulement pour le dernier dot
            let isLast = (i == count - 1)
            dot.run(
                SKAction.sequence([
                    fadeIn,
                    burst,
                    move,
                    SKAction.run { [weak self] in
                        if isLast { onArrival?() }
                        _ = self  // capture weak self pour éviter le warning
                    },
                    SKAction.removeFromParent(),
                ])
            )
        }
        _ = totalFlight  // utilisé si besoin d'un délai externe
    }


    /// ~50 points blancs qui partent radialement depuis la cellule de pose de la bombe,
    /// vitesse et direction aléatoires, fondu pendant le vol — même aspect que les dots de score.
    private func spawnBombExplosionParticles(at center: CGPoint) {
        let dotCount = 50
        for _ in 0..<dotCount {
            let radius = CGFloat.random(in: 1.5...3.0)
            let dot = SKShapeNode(circleOfRadius: radius)
            dot.fillColor = .white
            dot.strokeColor = .clear
            dot.alpha = 1
            dot.zPosition = 37
            dot.position = center
            addChild(dot)

            let angle  = CGFloat.random(in: 0...(2 * .pi))
            let speed  = CGFloat.random(in: 60...200)          // pts/s
            let flight = CGFloat.random(in: 0.30...0.65)       // durée en secondes
            let dist   = speed * flight

            let destination = CGPoint(
                x: center.x + cos(angle) * dist,
                y: center.y + sin(angle) * dist
            )

            let move = SKAction.move(to: destination, duration: flight)
            move.timingMode = .easeOut
            let fade = SKAction.fadeAlpha(to: 0, duration: flight * 0.85)
            fade.timingMode = .easeIn

            dot.run(SKAction.sequence([
                SKAction.group([move, fade]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    /// Explosion radiale de ~20 points blancs depuis le label score HUD au passage d'une centaine (100, 200, …).
    /// Les dots partent en burst radial sur ~40 pt puis s'estompent lentement.
    private func spawnScoreMilestoneExplosion() {
        guard let scoreLabel = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode else { return }
        let center = scoreLabel.position
        let dotCount = 22
        for _ in 0..<dotCount {
            let radius = CGFloat.random(in: 2.5...4.5)
            let dot = SKShapeNode(circleOfRadius: radius)
            dot.fillColor   = .white
            dot.strokeColor = .clear
            dot.alpha       = 1.0
            dot.zPosition   = 38
            dot.position    = CGPoint(
                x: center.x + CGFloat.random(in: -8...8),
                y: center.y + CGFloat.random(in: -8...8)
            )
            addChild(dot)

            let angle  = CGFloat.random(in: 0...(2 * .pi))
            let speed  = CGFloat.random(in: 80...200)    // pts/s
            let flight = CGFloat.random(in: 0.35...0.65) // secondes
            let dist   = speed * flight                  // 28–130 pt

            let destination = CGPoint(
                x: dot.position.x + cos(angle) * dist,
                y: dot.position.y + sin(angle) * dist
            )

            let move = SKAction.move(to: destination, duration: flight)
            move.timingMode = .easeOut
            // Fondu : démarre après 20 % du vol, dure jusqu'à la fin.
            let holdDuration = flight * 0.20
            let fadeDuration = flight * 0.80
            let fade = SKAction.fadeAlpha(to: 0, duration: fadeDuration)
            fade.timingMode = .easeIn

            dot.run(SKAction.sequence([
                SKAction.group([
                    move,
                    SKAction.sequence([
                        SKAction.wait(forDuration: holdDuration),
                        fade,
                    ]),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    /// Explosion XXL au passage d'un millier (1000, 2000, …) : 10× les particules, 2× la distance, dots multicolores (palette du joueur).
    private func spawnScoreThousandExplosion() {
        guard let scoreLabel = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode else { return }
        let center = scoreLabel.position
        let palette = Self.colorPalette.compactMap { Self.bloxSolidFillColor(colorName: $0) }
        let dotCount = 220
        for _ in 0..<dotCount {
            let radius = CGFloat.random(in: 2.0...4.0)
            let dot = SKShapeNode(circleOfRadius: radius)
            dot.fillColor   = palette.isEmpty ? .white : palette[Int.random(in: 0..<palette.count)]
            dot.strokeColor = .clear
            dot.alpha       = 1.0
            dot.zPosition   = 38
            dot.position    = CGPoint(
                x: center.x + CGFloat.random(in: -10...10),
                y: center.y + CGFloat.random(in: -10...10)
            )
            addChild(dot)

            let angle  = CGFloat.random(in: 0...(2 * .pi))
            let speed  = CGFloat.random(in: 160...400)   // 2× centaine (80–200 → 160–400) pts/s
            let flight = CGFloat.random(in: 0.35...0.65) // même durée → distance 2×
            let dist   = speed * flight                  // 56–260 pt

            let destination = CGPoint(
                x: dot.position.x + cos(angle) * dist,
                y: dot.position.y + sin(angle) * dist
            )

            let move = SKAction.move(to: destination, duration: flight)
            move.timingMode = .easeOut
            let holdDuration = flight * 0.20
            let fadeDuration = flight * 0.80
            let fade = SKAction.fadeAlpha(to: 0, duration: fadeDuration)
            fade.timingMode = .easeIn

            dot.run(SKAction.sequence([
                SKAction.group([
                    move,
                    SKAction.sequence([
                        SKAction.wait(forDuration: holdDuration),
                        fade,
                    ]),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    // MARK: - Move Analysis helpers

    /// Déclenche le calcul proactif du lookahead sur un thread dédié.
    /// Appelé juste après chaque stabilisation de grille en mode solo.
    func triggerMoveAnalysis() {
        guard BlomixMoveAnalyzer.evalEnabled else { return }
        guard pvpCoordinator == nil, !isTutorialMode, !isGameOver, !isStartScreen else { return }
        // Bombe active ou bloc Magix : pas d'analyse (effet déterministe ou aléatoire non simulable).
        guard !isBombMode else { return }
        guard currentBlock != .empty else { return }
        if case .magix = currentBlock {
            analyzerLookAhead = nil
            analyzerPendingQuality = nil
            return
        }

        // Snapshot sur le main thread.
        let gridSnap   = grid
        let p0         = currentBlock
        let p1         = blockAfterCurrent
        let p2         = blockTwoAhead
        let mc         = moveCount
        // La ligne est visible (et donc connue) uniquement quand moveCount % 10 == 9.
        let pending: [BlockType]? = (mc % 10 == 9) ? nextBottomLine : nil

        analyzerLookAhead = nil   // invalide l'ancien résultat
        // Capture la position et la file de blocs AVANT le prochain coup du joueur —
        // identique à ce que voyait le joueur (grille, blocs en file, ligne éventuelle).
        analyzerPreMoveGrid        = gridSnap
        analyzerPreMoveBlock       = p0
        analyzerPreMoveNext1       = p1
        analyzerPreMoveNext2       = p2
        analyzerPreMovePendingLine = pending

        // Incrémente la génération : le callback ignorera silencieusement tout résultat
        // calculé pour une génération antérieure (joueur qui joue vite → résultats périmés).
        analyzerGeneration &+= 1
        let gen = analyzerGeneration

        Self.analyzerQueue.async { [weak self] in
            let result = BlomixMoveAnalyzer.computeOptimal(
                grid:        gridSnap,
                piece0:      p0,
                piece1:      p1,
                piece2:      p2,
                moveCount:   mc,
                pendingLine: pending
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.analyzerGeneration == gen else { return }
                self.analyzerLookAhead = result
                // Si le joueur avait tapé "?" avant que l'analyse soit prête, l'honorer maintenant.
                if self.pendingHintRequest {
                    self.showHintGhost()
                }
            }
        }
    }

    /// Enregistre la qualité du coup pour la colonne choisie, en s'appuyant sur
    /// le résultat proactif (si disponible). Appelé au moment du tap, avant `dropBlock`.
    func recordMoveChoice(column: Int) {
        guard BlomixMoveAnalyzer.evalEnabled, let la = analyzerLookAhead else {
            analyzerPendingQuality = nil
            return
        }
        analyzerLookAhead = nil

        // Pas de feedback si la grille est encore trop peu remplie
        // (tous les blocs dans les 2 premières rangées = hauteur max ≤ 2).
        // On enregistre quand même le coup pour les stats de fin de partie.
        let record = la.record(forChosenColumn: column)
        analyzerGameStats.append(record)

        // Mise à jour du pire coup si cet écart est le plus grand de la partie.
        if record.delta > (worstMistakeSnapshot?.delta ?? 0),
           let preMoveGrid = analyzerPreMoveGrid {
            let optCols = la.scorePerColumn.indices.filter { idx in
                guard let s = la.scorePerColumn[idx] else { return false }
                return s == la.optimalScore
            }
            worstMistakeSnapshot = BlomixWorstMistakeSnapshot(
                grid:          preMoveGrid,
                block:         analyzerPreMoveBlock,
                nextBlock:     analyzerPreMoveNext1,
                blockTwoAhead: analyzerPreMoveNext2,
                pendingLine:   analyzerPreMovePendingLine,
                chosenColumn:  column,
                optimalColumns: optCols,
                delta:          record.delta,
                stageLevelText: isInStagedSoloMode ? currentStageConfig.levelText : nil
            )
        }

        let currentMaxH = (0..<GridLayout.columnCount).map { col in
            (0..<GridLayout.rowCount).first(where: { grid[$0][col] == .empty }) ?? GridLayout.rowCount
        }.max() ?? 0
        guard currentMaxH > 2 else {
            analyzerPendingQuality = nil
            return
        }

        analyzerPendingQuality = la.quality(forChosenColumn: column)
    }

    /// Affiche un mini-popup "!!" ou "?" au-dessus de la case d'atterrissage.
    func showMoveQualityFeedback(quality: BlomixMoveQuality, at landingPoint: CGPoint) {
        guard BlomixMoveAnalyzer.realtimeFeedbackEnabled else { return }
        guard quality != .neutral else { return }

        let text: String
        let color: SKColor
        switch quality {
        case .excellent:
            text  = "!!"
            color = SKColor(red: 0.22, green: 0.85, blue: 0.42, alpha: 1)  // vert
        case .bad:
            text  = "?"
            color = SKColor(red: 1.0, green: 0.42, blue: 0.18, alpha: 1)   // orange-rouge
        case .neutral:
            return
        }

        let label = SKLabelNode(text: text)
        label.fontName     = Self.customUIFontPostScriptName
        label.fontSize     = 22
        label.fontColor    = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .center
        label.position  = CGPoint(x: landingPoint.x, y: landingPoint.y + GridLayout.cellPoints * 1.2)
        label.zPosition = 50
        label.alpha     = 0
        addChild(label)

        let rise   = SKAction.moveBy(x: 0, y: 22, duration: 0.55)
        rise.timingMode = .easeOut
        let fadeIn  = SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.12),
            SKAction.wait(forDuration: 0.25),
            SKAction.fadeOut(withDuration: 0.18),
        ])
        let pop = SKAction.sequence([
            SKAction.scale(to: 1.25, duration: 0.10),
            SKAction.scale(to: 1.0,  duration: 0.08),
        ])
        label.run(SKAction.sequence([
            SKAction.group([rise, fadeIn, pop]),
            SKAction.removeFromParent(),
        ]))
    }

    /// Animation bombe gagnée : "+1" depuis le compteur BOMBE, 10 dots volent vers le compteur de bombes dispo.
    private func spawnBombEarnedAnimation() {
        guard let bombeValue  = childNode(withName: Self.bombeValueName)      as? SKLabelNode  else { return }
        guard let bombIcon    = childNode(withName: Self.bombHudIconName)      as? SKSpriteNode else { return }
        guard let bombCountLabel = childNode(withName: Self.bombHudCountLabelName) as? SKLabelNode else { return }

        let sourceCenter = bombeValue.position

        // Cible : centre de l'icône bombe en bas
        let iconFrame  = bombIcon.calculateAccumulatedFrame()
        let targetCenter = CGPoint(x: iconFrame.midX, y: iconFrame.midY)

        let flightDuration: TimeInterval = 0.52

        // — Image bombe volante (part de la position BOMBE 10/10, rejoint l'icône) —
        let flyingBomb = SKSpriteNode(imageNamed: currentBombImageName)
        flyingBomb.size      = CGSize(width: 28, height: 28)
        flyingBomb.position  = sourceCenter
        flyingBomb.zPosition = 38
        flyingBomb.setScale(0.5)
        addChild(flyingBomb)

        let scaleUp = SKAction.scale(to: 1.0, duration: 0.10)
        scaleUp.timingMode = .easeOut
        let fly    = SKAction.move(to: targetCenter, duration: flightDuration)
        fly.timingMode = .easeIn
        let shrink = SKAction.scale(to: 0.2, duration: flightDuration * 0.5)
        shrink.timingMode = .easeIn

        flyingBomb.run(
            SKAction.sequence([
                scaleUp,
                SKAction.group([fly, shrink]),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    // Mise à jour visuelle du compteur synchronisée avec l'arrivée
                    self.updateBombHUD()
                    let pulse = SKAction.sequence([
                        SKAction.scale(to: 1.6, duration: 0.08),
                        SKAction.scale(to: 1.0, duration: 0.15),
                    ])
                    pulse.timingMode = .easeOut
                    bombCountLabel.run(pulse)
                    bombIcon.run(pulse.copy() as! SKAction)
                },
                SKAction.removeFromParent(),
            ])
        )

        // — Dots blancs qui volent vers la même cible —
        spawnTransferDots(count: 12, from: sourceCenter, to: targetCenter, flightDuration: flightDuration, onArrival: nil)
    }

    /// Label « score » centré au-dessus de la grille (police doublée vs l’ancienne version).
    private func setupScoreHUD() {
        childNode(withName: Self.scoreHudLabelName)?.removeFromParent()
        childNode(withName: Self.bestScoreAboveName)?.removeFromParent()
        childNode(withName: Self.bombeCaptionName)?.removeFromParent()
        childNode(withName: Self.bombeValueName)?.removeFromParent()
        childNode(withName: Self.ligneCaptionName)?.removeFromParent()
        childNode(withName: Self.ligneValueName)?.removeFromParent()
        let label = SKLabelNode(text: "0")
        label.name = Self.scoreHudLabelName
        label.fontName = Self.customUIFontPostScriptName
        label.fontSize = 52
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 12
        addChild(label)

        // Best score — chiffre seul, centré, au-dessus du score (solo uniquement)
        let grayColor14 = UIColor(red: CGFloat(0xA3) / 255, green: CGFloat(0xA3) / 255,
                                  blue: CGFloat(0xA3) / 255, alpha: 1)
        let bestAboveLabel = SKLabelNode(text: "\(max(ScoreManager.shared.getLocalHighScore(), hudBestScoreValue))")
        bestAboveLabel.name = Self.bestScoreAboveName
        bestAboveLabel.fontName = Self.customUIFontPostScriptName
        bestAboveLabel.fontSize = 14
        bestAboveLabel.fontColor = grayColor14
        bestAboveLabel.horizontalAlignmentMode = .center
        bestAboveLabel.verticalAlignmentMode = .center
        bestAboveLabel.zPosition = 12
        bestAboveLabel.isHidden = pvpCoordinator != nil
        addChild(bestAboveLabel)

        // Caption "TEMPS" — label de titre partagé par le stage timer (solo) et le PvP timer.
        // La valeur numérique est portée par hudStageTimer (solo) ou hudPvPTurnTimerName (PvP).
        let timerCaptionLabel = SKLabelNode(text: "TEMPS")
        timerCaptionLabel.name = Self.hudTimerCaptionName
        timerCaptionLabel.fontName = Self.customUIFontPostScriptName
        timerCaptionLabel.fontSize = 14
        timerCaptionLabel.fontColor = grayColor14
        timerCaptionLabel.horizontalAlignmentMode = .right
        timerCaptionLabel.verticalAlignmentMode = .center
        timerCaptionLabel.zPosition = 12
        timerCaptionLabel.isHidden = isZenMode   // pas de timer en mode Zen
        addChild(timerCaptionLabel)

        // Compteur LIGNE (gauche du score — symétrique du RECORD à droite)
        let grayColor = UIColor(red: CGFloat(0xA3) / 255, green: CGFloat(0xA3) / 255,
                                blue: CGFloat(0xA3) / 255, alpha: 1)
        let ligneCaptionLabel = SKLabelNode(text: "LIGNE")
        ligneCaptionLabel.name = Self.ligneCaptionName
        ligneCaptionLabel.fontName = Self.customUIFontPostScriptName
        ligneCaptionLabel.fontSize = 14
        ligneCaptionLabel.fontColor = grayColor
        ligneCaptionLabel.horizontalAlignmentMode = .left
        ligneCaptionLabel.verticalAlignmentMode = .center
        ligneCaptionLabel.zPosition = 12
        addChild(ligneCaptionLabel)

        let ligneValueLabel = SKLabelNode(text: "0/10")
        ligneValueLabel.name = Self.ligneValueName
        ligneValueLabel.fontName = Self.customUIFontPostScriptName
        ligneValueLabel.fontSize = 14
        ligneValueLabel.fontColor = grayColor
        ligneValueLabel.horizontalAlignmentMode = .left
        ligneValueLabel.verticalAlignmentMode = .center
        ligneValueLabel.zPosition = 12
        addChild(ligneValueLabel)

        layoutScoreLabel()
        refreshBestScoreHUDIfNeeded()
    }

    private func layoutScoreLabel() {
        guard let label = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode else { return }
        label.fontSize = 52
        let half = GridLayout.spanPoints / 2
        let liftAboveGrid: CGFloat = 26 + GridLayout.cellPoints / 2
        label.position = CGPoint(
            x: gridAreaCenter.x,
            y: gridAreaCenter.y + half + liftAboveGrid
        )
        // Best score centré au-dessus du score (solo uniquement)
        if let bestAbove = childNode(withName: Self.bestScoreAboveName) as? SKLabelNode {
            bestAbove.fontSize = 14
            // Positionné au même endroit que le timer PvP (ils ne coexistent jamais)
            bestAbove.position = CGPoint(
                x: gridAreaCenter.x,
                y: label.position.y + 26 + 8 + 11
            )
        }
        // Caption "TEMPS" — positionné à droite du score (emplacement ancien compteur BOMBE)
        if let timerCaption = childNode(withName: Self.hudTimerCaptionName) as? SKLabelNode {
            timerCaption.fontSize = 14
            timerCaption.position = CGPoint(
                x: gridAreaCenter.x + half,
                y: label.position.y + 11
            )
        }
        // Compteur LIGNE
        // Mode normal : en haut à gauche (symétrique de TEMPS à droite).
        // Mode Zen    : en bas à gauche, LIGNE aligné en haut avec l'icône bombe.
        if isZenMode {
            let bandY  = sceneYCenterForBombAndUpcomingBand()
            let leftX  = gridAreaCenter.x - half
            // Alignement : haut texte "LIGNE" (centre + ½ hauteur ≈ 7 pts) == haut icône bombe (bandY + 18).
            // → centre LIGNE = bandY + 18 − 7 = bandY + 11
            let ligneCaptionY = bandY + 11
            if let ligneCaption = childNode(withName: Self.ligneCaptionName) as? SKLabelNode {
                ligneCaption.fontSize = 14
                ligneCaption.position = CGPoint(x: leftX, y: ligneCaptionY)
            }
            if let ligneValue = childNode(withName: Self.ligneValueName) as? SKLabelNode {
                ligneValue.fontSize = 14
                ligneValue.position = CGPoint(x: leftX, y: ligneCaptionY - 14)
            }
        } else {
            if let ligneCaption = childNode(withName: Self.ligneCaptionName) as? SKLabelNode {
                ligneCaption.fontSize = 14
                ligneCaption.position = CGPoint(
                    x: gridAreaCenter.x - half,
                    y: label.position.y + 11
                )
            }
            if let ligneValue = childNode(withName: Self.ligneValueName) as? SKLabelNode {
                ligneValue.fontSize = 14
                ligneValue.position = CGPoint(
                    x: gridAreaCenter.x - half,
                    y: label.position.y - 11
                )
            }
        }
    }

    /// Points d’ancrage du tutoriel (coordonnées **vue UIKit**, origine en haut à gauche), pour l’overlay au-dessus du `SKView`.
    func makeTutorialLayoutAnchorsForOverlay() -> TutorialLayoutAnchors? {
        guard let skView = view else { return nil }
        let h = skView.bounds.height
        guard h > 0 else { return nil }

        func sceneToOverlay(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: h - p.y)
        }

        guard let scoreLabel = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode else { return nil }
        let scoreScene = scoreLabel.position
        let gridScene = gridAreaCenter
        guard let slotNext = childNode(withName: Self.upcomingSlotNextName) as? SKSpriteNode else { return nil }
        let nextScene = slotNext.position
        guard let bombIcon = childNode(withName: Self.bombHudIconName) as? SKSpriteNode else { return nil }
        let bombScene = bombIcon.position

        return TutorialLayoutAnchors(
            scorePoint: sceneToOverlay(scoreScene),
            gridCenter: sceneToOverlay(gridScene),
            nextQueuePoint: sceneToOverlay(nextScene),
            bombPoint: sceneToOverlay(bombScene)
        )
    }

    /// Icône hamburger lisible dans SpriteKit : glyphe blanc aplati sur fond noir (les SF Symbols seuls peuvent apparaître noirs selon le chemin de rendu).
    private static func makeGameOverflowMenuIconNode() -> SKNode {
        let chipW: CGFloat = 44
        let chipH: CGFloat = 34
        let imgSize = CGSize(width: chipW, height: chipH)
        let weightCfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let sym = UIImage(systemName: "line.3.horizontal", withConfiguration: weightCfg.applying(
            UIImage.SymbolConfiguration(paletteColors: [.white])
        ))?.withTintColor(.white, renderingMode: .alwaysOriginal)
            ?? UIImage(systemName: "line.3.horizontal", withConfiguration: weightCfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = UIScreen.main.scale
        let flat = UIGraphicsImageRenderer(size: imgSize, format: format).image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: imgSize)).fill()
            guard let s = sym else {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: UIColor.white,
                ]
                let t = "≡" as NSString
                let sz = t.size(withAttributes: attrs)
                t.draw(
                    at: CGPoint(x: (imgSize.width - sz.width) / 2, y: (imgSize.height - sz.height) / 2 - 1),
                    withAttributes: attrs
                )
                return
            }
            let insetW = imgSize.width * 0.22
            let insetH = imgSize.height * 0.2
            let drawRect = CGRect(
                x: insetW,
                y: insetH,
                width: imgSize.width - 2 * insetW,
                height: imgSize.height - 2 * insetH
            )
            s.draw(in: drawRect)
        }

        let tex = SKTexture(image: flat)
        let sprite = SKSpriteNode(texture: tex)
        sprite.size = imgSize
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        return sprite
    }

    /// Ordonnée du haut des lettres du titre « BLOMIX » (repère scène), pour aligner le chip menu.
    private func gameplayTitleTopY() -> CGFloat {
        if let title = childNode(withName: Self.titleNodeName) as? SKLabelNode, !title.isHidden {
            return title.frame.maxY
        }
        let titleLiftFromTop: CGFloat = 56
        let titleY = size.height - titleLiftFromTop - GridLayout.cellPoints
        return titleY + 15
    }

    private func ensureGameOverflowMenuIfNeeded() {
        guard childNode(withName: Self.bottomMenuContainerName) == nil else { return }
        let container = SKNode()
        container.name = Self.bottomMenuContainerName
        container.zPosition = 15

        let iconNode = Self.makeGameOverflowMenuIconNode()
        iconNode.name = Self.hudGameMenuIconName
        container.addChild(iconNode)

        let dropdown = SKNode()
        dropdown.name = Self.hudGameMenuDropdownName
        dropdown.isHidden = true
        dropdown.zPosition = 2

        let panelW = min(280, max(200, size.width - 28))
        let rowH: CGFloat = 34
        let entries: [(text: String, name: String)] = [
            (BlomixL10n.menuNewGame, Self.bottomMenuNewGameName),
            (BlomixL10n.menuScores, Self.bottomMenuScoresName),
            (BlomixL10n.menuTutorial, Self.bottomMenuRulesName),
            (BlomixL10n.menuSettings, Self.bottomMenuSettingsName),
            (BlomixL10n.menuMultiplayer, Self.bottomMenuMultiplayerName),
        ]
        let panelH = CGFloat(entries.count) * rowH + 20
        let panel = SKSpriteNode(color: UIColor(white: 0.08, alpha: 0.94), size: CGSize(width: panelW, height: panelH))
        panel.name = Self.hudGameMenuPanelName
        panel.anchorPoint = CGPoint(x: 1, y: 1)
        panel.position = .zero
        panel.zPosition = 0
        dropdown.addChild(panel)

        let fontSize: CGFloat = size.width < 360 ? 12 : 14
        for (i, entry) in entries.enumerated() {
            let label = SKLabelNode(text: entry.text)
            label.name = entry.name
            label.fontName = Self.customUIFontPostScriptName
            label.fontSize = fontSize
            label.fontColor = .white
            label.horizontalAlignmentMode = .right
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: -14, y: -18 - CGFloat(i) * rowH - rowH / 2)
            label.zPosition = 1
            dropdown.addChild(label)
        }

        container.addChild(dropdown)
        addChild(container)
    }

    private func layoutGameOverflowMenuIfNeeded() {
        guard let container = childNode(withName: Self.bottomMenuContainerName),
              let icon = container.childNode(withName: Self.hudGameMenuIconName),
              let dropdown = container.childNode(withName: Self.hudGameMenuDropdownName) else { return }

        let margin: CGFloat = 14
        let rightX = size.width - margin
        let chipW: CGFloat = 44
        let chipH: CGFloat = 34
        let titleTop = gameplayTitleTopY()
        let iconCenterY = titleTop - chipH / 2
        icon.position = CGPoint(x: rightX - chipW / 2, y: iconCenterY)

        let panelW = min(280, max(200, size.width - 28))
        let rowH: CGFloat = 34
        let names = [
            Self.bottomMenuNewGameName,
            Self.bottomMenuScoresName,
            Self.bottomMenuRulesName,
            Self.bottomMenuSettingsName,
            Self.bottomMenuMultiplayerName,
        ]
        let panelH = CGFloat(names.count) * rowH + 20
        if let panel = dropdown.childNode(withName: Self.hudGameMenuPanelName) as? SKSpriteNode {
            panel.size = CGSize(width: panelW, height: panelH)
        }

        let gapBelowChip: CGFloat = 6
        let iconBottomY = iconCenterY - chipH / 2 - gapBelowChip
        dropdown.position = CGPoint(x: rightX, y: iconBottomY)

        let fontSize: CGFloat = size.width < 360 ? 12 : 14
        for (i, name) in names.enumerated() {
            guard let label = dropdown.childNode(withName: name) as? SKLabelNode else { continue }
            label.fontSize = fontSize
            label.position = CGPoint(x: -14, y: -18 - CGFloat(i) * rowH - rowH / 2)
        }
    }

    private func gameOverflowMenuDropdownIsOpen() -> Bool {
        guard let container = childNode(withName: Self.bottomMenuContainerName),
              let drop = container.childNode(withName: Self.hudGameMenuDropdownName) else { return false }
        return !drop.isHidden
    }

    private func closeGameOverflowMenu() {
        childNode(withName: Self.bottomMenuContainerName)?
            .childNode(withName: Self.hudGameMenuDropdownName)?.isHidden = true
    }

    private func toggleGameOverflowMenu() {
        guard let drop = childNode(withName: Self.bottomMenuContainerName)?
            .childNode(withName: Self.hudGameMenuDropdownName) else { return }
        drop.isHidden.toggle()
    }

    private func sceneHitRect(forMenuNode node: SKNode, padding: CGFloat = 10) -> CGRect {
        let f = node.calculateAccumulatedFrame()
        guard let parent = node.parent else { return .zero }
        let bl = convert(CGPoint(x: f.minX, y: f.minY), from: parent)
        let tr = convert(CGPoint(x: f.maxX, y: f.maxY), from: parent)
        let rect = CGRect(
            x: min(bl.x, tr.x),
            y: min(bl.y, tr.y),
            width: abs(tr.x - bl.x),
            height: abs(tr.y - bl.y)
        )
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    private func touchHitsGameMenuIcon(scenePoint: CGPoint) -> Bool {
        guard let container = childNode(withName: Self.bottomMenuContainerName),
              let icon = container.childNode(withName: Self.hudGameMenuIconName),
              !container.isHidden else { return false }
        var r = sceneHitRect(forMenuNode: icon, padding: 8)
        let minSide: CGFloat = 44
        if r.width < minSide { r = r.insetBy(dx: -(minSide - r.width) / 2, dy: 0) }
        if r.height < minSide { r = r.insetBy(dx: 0, dy: -(minSide - r.height) / 2) }
        return r.contains(scenePoint)
    }

    private func touchHitsOverflowMenuItem(named name: String, scenePoint: CGPoint) -> Bool {
        guard gameOverflowMenuDropdownIsOpen(),
              let container = childNode(withName: Self.bottomMenuContainerName),
              let drop = container.childNode(withName: Self.hudGameMenuDropdownName),
              let label = drop.childNode(withName: name) as? SKLabelNode,
              !container.isHidden else { return false }
        return sceneHitRect(for: label, minWidth: max(140, label.frame.width + 28), minHeight: 36, padding: 6).contains(scenePoint)
    }

    private func loadCreditsPlainText() -> String {
        guard let url = Bundle.main.url(forResource: "credits", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return BlomixL10n.creditsMissingBody
        }
        return raw
    }

    /// Centre d’une case en coordonnées **locales** du nœud `gridContainer` (identique au calcul dans `drawGrid()`).
    private static func gridContainerLocalCellCenter(row: Int, column: Int) -> CGPoint {
        let half = GridLayout.spanPoints / 2
        let x = -half + (CGFloat(column) + 0.5) * GridLayout.cellPoints
        let y = half - (CGFloat(row) + 0.5) * GridLayout.cellPoints
        return CGPoint(x: x, y: y)
    }

    /// Pour chaque colonne, liste les blocs non vides **du haut vers le bas** puis compare à l’empilement idéal
    /// (lignes `0 … k-1`). Toute différence `fromRow != toRow` produit un `CompactRiseMove`.
    ///
    /// - Précondition : `grid` reflète l’état **après** clears **et** dégâts Priks, mais **avant** `compactGridTowardTop()`.
    private func computeCompactRiseMovesReadingCurrentGrid() -> [CompactRiseMove] {
        var moves: [CompactRiseMove] = []
        for col in 0..<GridLayout.columnCount {
            var occupiedFromRows: [Int] = []
            for row in GridLayout.topRowIndex..<GridLayout.rowCount {
                if grid[row][col] != .empty {
                    occupiedFromRows.append(row)
                }
            }
            for (targetIndex, fromRow) in occupiedFromRows.enumerated() {
                let toRow = GridLayout.topRowIndex + targetIndex
                if fromRow != toRow {
                    moves.append(CompactRiseMove(column: col, fromRow: fromRow, toRow: toRow))
                }
            }
        }
        return moves
    }

    /// Parcours en profondeur (pile explicite) : toutes les cases **8-connexes** de la même `colorName` que `start`,
    /// en ne traversant que des `.color` identiques. Met à jour `globallyVisited` pour chaque case atteinte.
    ///
    /// - Important : `start` doit être une case `.color` de ce nom et ne pas être déjà dans `globallyVisited` (garanti par l’appelant).
    private func collectColorComponent8(
        start: GridAddress,
        colorName: String,
        globallyVisited: inout Set<GridAddress>
    ) -> Set<GridAddress> {
        var stack: [GridAddress] = [start]
        var component = Set<GridAddress>()

        while let current = stack.popLast() {
            if globallyVisited.contains(current) { continue }
            guard case .color(let name) = grid[current.row][current.col], name == colorName else { continue }

            globallyVisited.insert(current)
            component.insert(current)

            for delta in Self.chainNeighborDeltas8 {
                let nr = current.row + delta.dr
                let nc = current.col + delta.dc
                guard nr >= GridLayout.topRowIndex, nr < GridLayout.rowCount,
                      nc >= 0, nc < GridLayout.columnCount else { continue }

                let neighbor = GridAddress(row: nr, col: nc)
                if globallyVisited.contains(neighbor) { continue }
                guard case .color(let neighborName) = grid[nr][nc], neighborName == colorName else { continue }

                stack.append(neighbor)
            }
        }

        return component
    }

    /// Après des disparitions (ligne de **5** blocs **même couleur** se touchant en **latéral ou diagonal**, bombes, etc.), les blocs **ne retombent jamais vers le bas**.
    /// Chaque colonne est réécrite : on lit les cases du **haut au bas**, on garde l’ordre des pièces non vides, puis on les re-place à partir du **haut** — tout trou au-dessus d’un bloc est ainsi comblé en faisant monter les blocs.
    ///
    /// Appelée depuis `resolveChains()` après des suppressions ; pas après un simple `dropBlock` sans chaîne (la grille est déjà cohérente).
    private func compactGridTowardTop() {
        for col in 0..<GridLayout.columnCount {
            var columnBlocks: [BlockType] = []
            for row in GridLayout.topRowIndex..<GridLayout.rowCount {
                let cell = grid[row][col]
                if cell != .empty {
                    columnBlocks.append(cell)
                }
            }
            var writeRow = GridLayout.topRowIndex
            for block in columnBlocks {
                grid[writeRow][col] = block
                writeRow += 1
            }
            while writeRow < GridLayout.rowCount {
                grid[writeRow][col] = .empty
                writeRow += 1
            }
        }
    }

    // MARK: - Ligne aléatoire (tous les 10 coups, `priks.html`)

    /// Chaque case de la ligne suivante est tirée **indépendamment** comme `randomNextPlayableBlock()` (1/8 Priks, 7/8 couleur).
    private static func generateNextRandomLineRowIndependentCells() -> [BlockType] {
        (0..<GridLayout.columnCount).map { _ in randomNextPlayableBlock() }
    }

    /// Bord **bas** de la zone de jeu 8×8 (repère scène).
    private func gridPlayfieldBottomY() -> CGFloat {
        gridAreaCenter.y - GridLayout.spanPoints / 2
    }

    /// Centre vertical de référence pour des éléments sous l'icône bombe (repère scène).
    private func bombProgressBarCenterY() -> CGFloat {
        guard let icon = childNode(withName: Self.bombHudIconName) as? SKSpriteNode else {
            let marginBelowGrid: CGFloat = 6
            return gridPlayfieldBottomY() - marginBelowGrid - ProgressHUD.lineBarHeight / 2
        }
        let iconBottomY = icon.position.y - icon.size.height / 2
        return iconBottomY - ProgressHUD.bombStackBelowIcon - ProgressHUD.bombBarHeight / 2
    }

    /// Bord **bas** du bloc « Next line » **sous la grille** (ancre pour la bande preview / bombe) — inchangé
    /// quand la barre « Next line » est dessinée plus bas près de la bombe.
    private func sceneBottomOfNextLineProgressHUD() -> CGFloat {
        let marginBelowGrid: CGFloat = 6
        let barCY = gridPlayfieldBottomY() - marginBelowGrid - ProgressHUD.lineBarHeight / 2
        let labelDy = -(ProgressHUD.lineBarHeight / 2 + 6 + 5)
        let labelHalfHeight: CGFloat = 5
        return barCY + labelDy - labelHalfHeight
    }

    /// Ordonnée de départ (montée) des blocs de la ligne des 10 : alignée sur l’aperçu « demi-case » bas de grille.
    private func sceneIncomingLineRiseStartY() -> CGFloat {
        scenePointCellCenter(row: GridLayout.bottomRowIndex, column: 0).y - GridLayout.cellPoints / 4
    }

    /// Cellule d’aperçu pour la bande sous la grille (même taille que les cases jouées).
    private static func makeBottomLinePreviewCellNode(block: BlockType) -> SKSpriteNode {
        let size = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
        switch block {
        case .color:
            let s = makeSolidGameplayBlockSprite(block: block, pixelSize: size)
            return s
        case .priks, .magix:
            return makeSolidGameplayBlockSprite(block: block, pixelSize: size)
        case .empty:
            let slot = SKSpriteNode(color: SKColor(white: 0.12, alpha: 1), size: size)
            slot.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            return slot
        }
    }

    /// Affiche `nextBottomLine` dans la **demi-case basse** de la dernière rangée (masque : seul le haut des sprites est visible).
    /// - Parameter ignoreProcessing: `true` pour les callbacks réseau PvP — affiche le strip
    ///   même pendant une animation afin que le joueur voie toujours la ligne d'attaque arriver.
    private func refreshPendingBottomLinePreview(ignoreProcessing: Bool = false) {
        guard !isStartScreen else {
            childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()
            return
        }
        // Pendant le traitement : ne pas toucher le strip existant sauf si forcé (attaque PvP).
        guard !isProcessing || ignoreProcessing else { return }

        let incomingAttackPreview = pvpCoordinator?.peekNextIncomingAttackLinePreview()
        let previewLine: [BlockType]
        if let incomingAttackPreview {
            previewLine = incomingAttackPreview.line
        } else if !isProcessing && pvpNeedsDecadeLineAfterAttackInjection {
            previewLine = nextBottomLine
        } else if !isProcessing && moveCount % 10 == 9 {
            previewLine = nextBottomLine
        } else {
            // Aucune ligne à signaler. Retirer le strip uniquement hors du traitement.
            if !isProcessing {
                childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()
                pendingBottomLineBloopaSoundPlayedAtMoveCount = nil
            }
            return
        }
        guard previewLine.count == GridLayout.columnCount else {
            if !isProcessing { childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent() }
            return
        }

        // Supprimer l'éventuel strip précédent avant de créer le nouveau.
        childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()

        let strip = SKNode()
        strip.name = Self.bottomLinePreviewStripName
        strip.zPosition = 5
        let maskH = GridLayout.cellPoints / 2
        let maskW = GridLayout.cellPoints

        for col in 0..<GridLayout.columnCount {
            let block = previewLine[col]
            let cellCenter = scenePointCellCenter(row: GridLayout.bottomRowIndex, column: col)
            let crop = SKCropNode()
            crop.position = CGPoint(x: cellCenter.x, y: cellCenter.y - GridLayout.cellPoints / 2)
            crop.zPosition = 0

            let mask = SKSpriteNode(color: .white, size: CGSize(width: maskW, height: maskH))
            mask.anchorPoint = CGPoint(x: 0.5, y: 0)
            mask.position = .zero
            crop.maskNode = mask

            let node = Self.makeBottomLinePreviewCellNode(block: block)
            node.position = CGPoint(x: 0, y: GridLayout.cellPoints / 4)
            crop.addChild(node)
            strip.addChild(crop)
        }
        addChild(strip)
        let jitter = SKAction.repeatForever(
            SKAction.customAction(withDuration: PendingLinePreviewFeedback.organicCycleDuration) { node, elapsed in
                let t = CGFloat(elapsed)
                let x1 = sin(t * 18.0) * PendingLinePreviewFeedback.jitterAmplitudeX
                let x2 = sin(t * 7.3 + 1.2) * PendingLinePreviewFeedback.jitterAmplitudeX * 0.55
                let y1 = cos(t * 15.5 + 0.7) * PendingLinePreviewFeedback.jitterAmplitudeY
                node.position = CGPoint(x: x1 + x2, y: y1)
            }
        )
        strip.run(jitter, withKey: Self.bottomLinePreviewJitterActionKey)
        if let incomingAttackPreview {
            if pvpIncomingAttackPreviewSoundPlayedForID != incomingAttackPreview.id {
                pvpIncomingAttackPreviewSoundPlayedForID = incomingAttackPreview.id
                playMatchSound(.pendingRandomLineBloopa)
            }
        } else if pendingBottomLineBloopaSoundPlayedAtMoveCount != moveCount {
            pendingBottomLineBloopaSoundPlayedAtMoveCount = moveCount
            playMatchSound(.pendingRandomLineBloopa)
        }
    }

    /// Résultat de l’insertion de la ligne des 10 coups (`priks.html` : `addRandomLine`).
    private enum RandomLinePushResult {
        /// Buffer invalide : pas d’animation.
        case didNotRun
        /// Sprites en montée ; garder `isProcessing` jusqu’au prochain `resolveChains()`.
        case animating
        /// Au moins une colonne sans case libre → partie terminée.
        case gameOver
    }

    /// Chaque bloc de `nextBottomLine` **monte** vers la case vide **la plus haute** de sa colonne (même durée / easeOut que `CompactRiseAnimation`), puis écrit la grille et relance `resolveChains()`.
    private func addRandomLinePushingGridUp() -> RandomLinePushResult {
        guard nextBottomLine.count == GridLayout.columnCount else { return .didNotRun }

        // Si plusieurs colonnes sont déjà pleines avant la poussée,
        // on choisit l'une d'elles au hasard pour focaliser l'animation de défaite.
        let blockedColumns = (0..<GridLayout.columnCount).filter { highestEmptyRow(inColumn: $0) == nil }
        if let blockedColumn = blockedColumns.randomElement() {
            let losePoint = scenePointCellCenter(row: GridLayout.bottomRowIndex, column: blockedColumn)
            triggerGameOver(focusPoint: losePoint)
            return .gameOver
        }

        var placements: [(column: Int, row: Int)] = []
        for col in 0..<GridLayout.columnCount {
            guard let row = highestEmptyRow(inColumn: col) else {
                triggerGameOver()
                return .gameOver
            }
            placements.append((column: col, row: row))
        }

        let line = nextBottomLine
        nextBottomLine = nextBottomLineRowForSession()

        // Fondu du strip de prévisualisation en même temps que les sprites commencent à monter :
        // le jitter s'arrête et le strip disparaît doucement pendant les premiers instants du trajet,
        // donnant l'impression que les blocs tremblotants s'élèvent directement.
        if let strip = childNode(withName: Self.bottomLinePreviewStripName) {
            strip.removeAction(forKey: Self.bottomLinePreviewJitterActionKey)
            strip.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.15),
                SKAction.removeFromParent(),
            ]))
        }

        isInjectingBottomRandomLine = true
        // Pendant l’injection déclenchée au 10e coup, la barre « Next line » doit rester visuellement pleine.
        refreshProgressHUDBars()

        if isTutorialMode && !tutorialLineShown {
            tutorialLineShown = true
            showTutorialLineArrivalOverlay()
        }

        let startY = sceneIncomingLineRiseStartY()

        // Vitesse constante : durée calée sur la colonne qui parcourt la plus grande distance.
        let blockFallSpeed = GridLayout.cellPoints * CGFloat(GridLayout.rowCount) / 0.25  // ≈ 1280 pts/s
        let maxColumnDistance = placements.map {
            abs(scenePointCellCenter(row: $0.row, column: $0.column).y - startY)
        }.max() ?? GridLayout.cellPoints
        let duration = max(0.10, TimeInterval(maxColumnDistance / blockFallSpeed))

        for placement in placements {
            let col = placement.column
            let block = line[col]
            let sprite = makeFallingBlockNode(for: block)
            sprite.name = "\(Self.randomLineRisingSpritePrefix)\(col)"
            sprite.position = CGPoint(x: scenePointCellCenter(row: GridLayout.bottomRowIndex, column: col).x, y: startY)
            sprite.size = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
            sprite.zPosition = 22

            // Stretch proportionnel à la vitesse relative de la colonne (plus loin = plus étiré).
            let colDistance = abs(scenePointCellCenter(row: placement.row, column: col).y - startY)
            let stretchFactor = maxColumnDistance > 0 ? colDistance / maxColumnDistance : 0
            sprite.xScale = 1.0 - (1.0 - FlightStretch.xScale) * stretchFactor
            sprite.yScale = 1.0 + (FlightStretch.yScale - 1.0) * stretchFactor

            addChild(sprite)

            // De-stretch pendant le vol : revient exactement à (1.0, 1.0) à l’atterrissage.
            let unstretchX = SKAction.scaleX(to: 1.0, duration: duration)
            unstretchX.timingMode = .easeIn
            let unstretchY = SKAction.scaleY(to: 1.0, duration: duration)
            unstretchY.timingMode = .easeIn

            // Traîne de paillettes pour chaque colonne de la ligne entrante.
            run(makeTrailSpawnAction(riseDuration: duration,
                                     color: Self.bloxTrailColor(for: block),
                                     trackedSprite: sprite))

            let endPoint = scenePointCellCenter(row: placement.row, column: col)
            let move = SKAction.move(to: endPoint, duration: duration)
            move.timingMode = .easeOut
            sprite.run(SKAction.group([move, unstretchX, unstretchY]))
        }

        let lineCopy = line
        let placementsCopy = placements

        let finishInjection: () -> Void = { [weak self] in
            guard let self else { return }
            self.playMatchSound(.line)
            self.hapticHeavy()
            for col in 0..<GridLayout.columnCount {
                self.childNode(withName: "\(Self.randomLineRisingSpritePrefix)\(col)")?.removeFromParent()
            }
            for p in placementsCopy {
                guard p.row >= GridLayout.topRowIndex, p.row < GridLayout.rowCount,
                      p.column >= 0, p.column < GridLayout.columnCount else { continue }
                self.grid[p.row][p.column] = lineCopy[p.column]
            }
            // Comptabilise chaque cellule de la ligne injectée pour le multiplicateur (solo uniquement).
            if self.pvpCoordinator == nil {
                for col in 0..<GridLayout.columnCount {
                    let block = lineCopy[col]
                    if case .empty = block { continue }
                }
            }
            self.isInjectingBottomRandomLine = false
            self.drawGrid()
            // Bounce sur chaque case nouvellement placée (effet vague colonne par colonne).
            if let container = self.childNode(withName: Self.gridContainerName) {
                for (i, p) in placementsCopy.enumerated() {
                    if let cell = container.childNode(withName: "cell_\(p.row)_\(p.column)") as? SKSpriteNode {
                        let delay = Double(i) * 0.018
                        let blockColor = Self.bloxTrailColor(for: lineCopy[p.column])
                        cell.run(SKAction.sequence([
                            SKAction.wait(forDuration: delay),
                            SKAction.run { [weak self] in self?.playLandingBounce(on: cell, blockColor: blockColor) },
                        ]))
                    }
                }
            }
            let lineStaggerTotal = Double(GridLayout.columnCount - 1) * 0.018
            self.run(SKAction.sequence([
                SKAction.wait(forDuration: LandingBounce.totalDuration + lineStaggerTotal),
                SKAction.run { self.resolveChains() },
            ]))
        }

        run(
            SKAction.sequence([
                SKAction.wait(forDuration: duration),
                SKAction.run { finishInjection() },
            ])
        )
        return .animating
    }

    /// Fait visuellement transiter `currentBlock` : preview → bas de colonne (très rapide) → montée jusqu’à la case d’empilement, puis l’inscrit dans `grid`.
    /// - Parameter column: `nil` → `selectedColumn`. Sinon colonne du tap sur la grille.
    private func dropBlock(usingColumn column: Int? = nil) {
        guard !isStartScreen, !isGameOver, !isProcessing else { return }
        // En mode bombe, le placement se fait exclusivement via placeBombAtCell (tap direct sur case).
        guard !isBombMode else { return }

        let placedKind = currentBlock
        switch placedKind {
        case .color, .priks, .magix:
            break
        case .empty:
            return
        }

        let columnIndex: Int = {
            guard let c = column else { return selectedColumn }
            return min(max(c, 0), GridLayout.columnCount - 1)
        }()

        if checkGameOver(forNormalDropInColumn: columnIndex) {
            let hasRoomElsewhere = (0..<GridLayout.columnCount).contains { $0 != columnIndex && !checkGameOver(forNormalDropInColumn: $0) }
            if hasRoomElsewhere {
                playMatchSound(.wrong)
                return
            }
            let losePoint = scenePointCellCenter(row: GridLayout.bottomRowIndex, column: columnIndex)
            triggerGameOver(focusPoint: losePoint)
            return
        }
        guard let row = highestEmptyRow(inColumn: columnIndex) else { return }

        let placedBlock = placedKind
        isProcessing = true
        childNode(withName: Self.fallingSpriteName)?.removeFromParent()
        childNode(withName: Self.hintGhostContainerName)?.removeFromParent()

        if let preview = childNode(withName: Self.previewNodeName) {
            preview.isHidden = true
        }

        // Départ visuel depuis la preview, puis recentrage quasi instantané au bas de la colonne.
        let start = scenePointPreviewRow(column: columnIndex)
        let launchStart = scenePointLaunchStartBelowGrid(column: columnIndex)
        let end = scenePointCellCenter(row: row, column: columnIndex)

        let falling = makeFallingBlockNode(for: placedBlock)
        falling.name = Self.fallingSpriteName
        falling.position = start
        falling.size = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
        falling.xScale = FlightStretch.xScale
        falling.yScale = FlightStretch.yScale
        falling.zPosition = 20
        addChild(falling)

        // File sous la grille : avance tout de suite (le sprite qui tombe reste `placedKind`).
        currentBlock = blockAfterCurrent
        blockAfterCurrent = blockTwoAhead
        blockTwoAhead = nextPlayableBlockForSession()
        refreshUpcomingQueueSlots()
        updatePreviewSprite()
        if isTutorialMode { tutorialDidAdvanceBlockQueue() }

        let snapToColumn = SKAction.move(to: launchStart, duration: 0.0)

        // Vitesse constante calée sur la hauteur totale de la grille (8 cases = 0.25 s pour le trajet le plus long).
        let blockFallSpeed = GridLayout.cellPoints * CGFloat(GridLayout.rowCount) / 0.25  // ≈ 1280 pts/s
        let riseDuration = max(0.07, TimeInterval(abs(end.y - launchStart.y) / blockFallSpeed))

        let rise = SKAction.move(to: end, duration: riseDuration)
        rise.timingMode = .easeOut

        // De-stretch pendant le vol : easeIn pour que la forme revienne exactement à (1.0, 1.0)
        // à l’atterrissage — transition parfaite avec le squash du LandingBounce.
        let unstretchX = SKAction.scaleX(to: 1.0, duration: riseDuration)
        unstretchX.timingMode = .easeIn
        let unstretchY = SKAction.scaleY(to: 1.0, duration: riseDuration)
        unstretchY.timingMode = .easeIn

        // Traîne de paillettes : démarre après le snap instantané (snapToColumn dure 0 s).
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.001),
            makeTrailSpawnAction(riseDuration: riseDuration,
                                 color: Self.bloxTrailColor(for: placedBlock),
                                 trackedSprite: falling),
        ]))

        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            falling.removeFromParent()
            self.grid[row][columnIndex] = placedBlock
            // Comptabilise le bloc posé pour le multiplicateur (solo uniquement).
            if self.pvpCoordinator == nil {
            }
            let placedAddress = GridAddress(row: row, col: columnIndex)
            if let sfx = self.landingSoundForPlacedBlock(placedBlock, at: placedAddress) {
                self.playMatchSound(sfx)
            }
            self.selectedColumn = 3
            self.drawGrid(junctionFocus: GridPosition(row: row, col: columnIndex))
            if let preview = self.childNode(withName: Self.previewNodeName) {
                preview.isHidden = false
            }
            self.updatePreviewSprite()
            // Bounce sur le sprite fraîchement créé par drawGrid.
            if let container = self.childNode(withName: Self.gridContainerName),
               let cell = container.childNode(withName: "cell_\(row)_\(columnIndex)") as? SKSpriteNode {
                self.playLandingBounce(on: cell, blockColor: Self.bloxTrailColor(for: placedBlock))
            }
            // Feedback qualité du coup (si disponible, mode solo uniquement).
            if let quality = self.analyzerPendingQuality {
                self.analyzerPendingQuality = nil
                self.showMoveQualityFeedback(quality: quality, at: end)
            }
            // `isProcessing` reste `true` jusqu’à la fin de toute la résolution des chaînes (y compris cascades + ligne des 10).
            self.shouldRunPostPlacementHooks = true
            // Délai = durée du bounce pour éviter conflit avec la dissolution si chaîne immédiate.
            let magixAddress = GridAddress(row: row, col: columnIndex)
            self.run(SKAction.sequence([
                SKAction.wait(forDuration: LandingBounce.totalDuration),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    if case .magix(let kind) = placedBlock {
                        self.applyMagixEffect(kind: kind, at: magixAddress)
                    } else {
                        self.resolveChains()
                    }
                },
            ]))
        }

        falling.run(SKAction.sequence([snapToColumn, SKAction.group([rise, unstretchX, unstretchY]), finish]))
    }

    // MARK: - Blocs Magix — rendu visuel

    /// Construit un SKShader qui affiche un dégradé mouvant entre 3 couleurs de la palette du skin.
    /// Le dégradé est piloté par `u_time` (fourni automatiquement par SpriteKit) ; aucune SKAction
    /// n'est nécessaire — le shader tourne en continu tant qu'il est attaché au sprite.
    ///
    /// Principe : une texture 1D encode les 6 couleurs du skin en un dégradé continu (avec wrap).
    /// Trois coordonnées de sample glissent dans des directions différentes, créant à tout instant
    /// un mélange de ~3 couleurs qui évolue en continu.
    private static func makeMagixPaletteShader(timeOffset: Float = 0.0) -> SKShader {
        // Les couleurs de la palette sont intégrées directement dans le source GLSL
        // pour éviter tout problème de mapping de sampler (SpriteKit peut remapper
        // les uniformes de type texture sur la texture du sprite).
        let uiColors = colorPalette.compactMap { bloxSolidFillColor(colorName: $0) }
        let safeColors = uiColors.isEmpty
            ? [SKColor.red, SKColor.green, SKColor.blue,
               SKColor.yellow, SKColor(red: 0.6, green: 0, blue: 0.9, alpha: 1), SKColor.orange]
            : uiColors
        let n = safeColors.count

        // Convertit une SKColor en littéral vec3 GLSL.
        func v3(_ c: SKColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "vec3(%.4f,%.4f,%.4f)", Float(r), Float(g), Float(b))
        }

        // Génère une chaîne if-else qui associe chaque segment de palette à deux couleurs.
        var branches = ""
        for i in 0..<n {
            let next = (i + 1) % n
            let limit = String(format: "%.1f", Float(i + 1))
            if i == 0 {
                branches += "    if (fi<\(limit)){ca=\(v3(safeColors[i]));cb=\(v3(safeColors[next]));}\n"
            } else if i < n - 1 {
                branches += "    else if (fi<\(limit)){ca=\(v3(safeColors[i]));cb=\(v3(safeColors[next]));}\n"
            } else {
                branches += "    else{ca=\(v3(safeColors[i]));cb=\(v3(safeColors[next]));}\n"
            }
        }
        let nStr = String(format: "%.1f", Float(n))

        // Shader GLSL : une fonction de palette + main.
        // v_tex_coord est fourni par SpriteKit (UV normalisés 0→1 sur le sprite).
        // u_time      est fourni automatiquement par SpriteKit (secondes).
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
            // t pilote le cycle couleur (lent) ; la position dans la palette avance doucement.
            float t=u_time*0.09+\(String(format: "%.4f", timeOffset));
            // 3 couleurs equidistantes dans la palette — toujours 3 teintes distinctes.
            vec3 c1=mgxPal(t);
            vec3 c2=mgxPal(t+0.333);
            vec3 c3=mgxPal(t+0.667);
            // Gradient spatial doux : demi-cycle sur la largeur du bloc (pas de bandes).
            // Fréquence basse = grandes zones lisses.
            float wx=sin(uv.x*3.14159+t*0.5)*0.5+0.5;
            float wy=cos(uv.y*2.2-t*0.35)*0.5+0.5;
            // Fusion en deux étapes : c1↔c2 dominants, c3 subtile.
            vec3 ab=mix(c1,c2,wx);
            vec3 col=mix(ab,c3,wy*0.38);
            gl_FragColor=vec4(col,1.0);
        }
        """
        // Aucun uniforme personnalisé : les couleurs sont compilées dans le shader.
        return SKShader(source: src)
    }

    /// Texture halo pré-générée pour les disques de ranking (paramètres fixes : rayon 30, spread 12).
    /// Mise en cache pour éviter un rendu Core Graphics synchrone à chaque `makeRankDiscNode`.
    private static let rankDiscHaloTextureCached: SKTexture = makeRankDiscHaloTexture(discRadius: 30, spread: 12)

    /// Texture pixel blanc 2×2 : base obligatoire pour que SpriteKit initialise
    /// correctement `v_tex_coord` dans le fragment shader (sans texture, les UV
    /// peuvent être indéfinis et le shader sort noir).
    private static let magixShaderBaseTexture: SKTexture = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let img = renderer.image { ctx in
            SKColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
    }()

    /// Applique le shader dégradé Magix sur `sprite` (réutilisé ou neuf).
    /// Texture blanche avec dégradé radial : opaque au bord du bloc, transparent au bord du halo.
    /// `blockSize` = taille du sprite Magix, `spread` = extension en pts au-delà de chaque bord.
    private static func makeMagixHaloTexture(blockSize: CGSize, spread: CGFloat) -> SKTexture {
        let total = CGSize(width: blockSize.width + spread * 2, height: blockSize.height + spread * 2)
        let renderer = UIGraphicsImageRenderer(size: total)
        let image = renderer.image { ctx in
            let center   = CGPoint(x: total.width * 0.5, y: total.height * 0.5)
            let innerR   = min(blockSize.width, blockSize.height) * 0.5   // bord du bloc
            let outerR   = innerR + spread                                  // bord du halo
            let cs       = CGColorSpaceCreateDeviceRGB()
            let colors   = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let locs: [CGFloat] = [0, 1]
            guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) else { return }
            // .drawsBeforeStartLocation remplit le centre (zone couverte par le bloc) avec la couleur de départ.
            ctx.cgContext.drawRadialGradient(grad,
                                             startCenter: center, startRadius: innerR,
                                             endCenter:   center, endRadius:   outerR,
                                             options: .drawsBeforeStartLocation)
        }
        return SKTexture(image: image)
    }

    // MARK: - Disques de rang (écran d'accueil)

    /// Texture halo radial pour un disque (cercle), analogue à `makeMagixHaloTexture`.
    /// Le dégradé va de blanc opaque (bord du disque) à blanc transparent (bord du halo).
    private static func makeRankDiscHaloTexture(discRadius: CGFloat, spread: CGFloat) -> SKTexture {
        let total = (discRadius + spread) * 2
        let sz = CGSize(width: total, height: total)
        let renderer = UIGraphicsImageRenderer(size: sz)
        let image = renderer.image { ctx in
            let center = CGPoint(x: total * 0.5, y: total * 0.5)
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor.white.cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let locs: [CGFloat] = [0, 1]
            guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) else { return }
            ctx.cgContext.drawRadialGradient(grad,
                                             startCenter: center, startRadius: discRadius,
                                             endCenter:   center, endRadius:   discRadius + spread,
                                             options: .drawsBeforeStartLocation)
        }
        return SKTexture(image: image)
    }

    /// Nœud SK complet représentant un classement : disque animé (shader MAGIX via SKCropNode circulaire)
    /// + halo radial + rang centré + label catégorie en dessous.
    /// Le rang est vide ("") à la construction ; il est mis à jour après le fetch Game Center.
    /// - Parameters:
    ///   - name:         Identifiant unique du nœud racine.
    ///   - category:     Texte affiché sous le disque ("SOLO", "MOY.", "ZEN").
    ///   - discDiameter: Diamètre du disque en pts.
    private static func makeRankDiscNode(name: String, category: String, discDiameter: CGFloat,
                                          timeOffset: Float = 0.0) -> SKNode {
        let container = SKNode()
        container.name = name

        let radius      = discDiameter / 2
        let haloSpread: CGFloat = 12

        // ── Halo radial ───────────────────────────────────────────────────────
        // Texture pré-générée (paramètres fixes) : évite un rendu Core Graphics à chaque appel.
        let haloTex = (radius == 30 && haloSpread == 12)
            ? rankDiscHaloTextureCached
            : makeRankDiscHaloTexture(discRadius: radius, spread: haloSpread)
        let haloSide = (radius + haloSpread) * 2
        let halo     = SKSpriteNode(texture: haloTex, size: CGSize(width: haloSide, height: haloSide))
        halo.alpha     = 0.40
        halo.zPosition = -2
        halo.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 1.2),
            SKAction.fadeAlpha(to: 0.22, duration: 1.2),
        ])))
        container.addChild(halo)

        // ── Disque animé : shader MAGIX (éprouvé) clipé par SKCropNode ────────
        // Le clip circulaire est délégué à SKCropNode + masque SKShapeNode,
        // évitant tout problème de compilation GLSL lié à un early-return.
        let cropNode  = SKCropNode()
        cropNode.zPosition = 0

        let maskCircle = SKShapeNode(circleOfRadius: radius)
        maskCircle.fillColor   = .white
        maskCircle.strokeColor = .clear
        cropNode.maskNode = maskCircle

        let disc = SKSpriteNode(texture: magixShaderBaseTexture,
                                size: CGSize(width: discDiameter, height: discDiameter))
        disc.colorBlendFactor = 0
        disc.color  = .white
        disc.shader = makeMagixPaletteShader(timeOffset: timeOffset)
        cropNode.addChild(disc)
        container.addChild(cropNode)

        // ── Bordure circulaire (jaune du set joueur) ───────────────────────────
        let borderColor = bloxSolidFillColor(colorName: "yellow")
            ?? SKColor(red: 0.91, green: 0.77, blue: 0.42, alpha: 1)
        let border = SKShapeNode(circleOfRadius: radius)
        border.fillColor   = .clear
        border.strokeColor = borderColor
        border.lineWidth   = 2.5
        border.zPosition   = 1.5
        container.addChild(border)

        // ── Rang centré dans le disque (au-dessus du cropNode) ────────────────
        let rankLabel = SKLabelNode(text: "")
        rankLabel.name                    = name + rankDiscRankLabelSuffix
        rankLabel.fontName                = customUIFontPostScriptName
        rankLabel.fontSize                = discDiameter * 0.30
        rankLabel.fontColor               = .white
        rankLabel.horizontalAlignmentMode = .center
        rankLabel.verticalAlignmentMode   = .center
        rankLabel.position                = .zero
        rankLabel.zPosition               = 2
        container.addChild(rankLabel)

        // ── Catégorie sous le disque ──────────────────────────────────────────
        let catLabel = SKLabelNode(text: category)
        catLabel.fontName                = customUIFontPostScriptName
        catLabel.fontSize                = discDiameter * 0.21
        catLabel.fontColor               = SKColor(white: 0.60, alpha: 1)
        catLabel.horizontalAlignmentMode = .center
        catLabel.verticalAlignmentMode   = .top
        catLabel.position                = CGPoint(x: 0, y: -(radius + 6))
        catLabel.zPosition               = 1
        container.addChild(catLabel)

        return container
    }

    private static func applyMagixShader(to sprite: SKSpriteNode, size: CGSize,
                                          kind: MagixKind, symbolLabelName: String) {
        // La texture blanche garantit que v_tex_coord est correctement interpolé.
        sprite.texture          = magixShaderBaseTexture
        sprite.colorBlendFactor = 0   // le shader fournit 100 % de la couleur
        sprite.color            = .white
        sprite.size             = size
        sprite.shader           = makeMagixPaletteShader()

        // ── Halo blanc dégradé radial (glow) ───────────────────────────────────
        sprite.removeAction(forKey: MagixRules.orbitParticlesActionKey)
        sprite.childNode(withName: MagixRules.glowNodeName)?.removeFromParent()
        let haloSpread: CGFloat = 16   // pts au-delà du bord du bloc jusqu'au transparent total
        let haloTexture = Self.makeMagixHaloTexture(blockSize: size, spread: haloSpread)
        let glow = SKSpriteNode(texture: haloTexture,
                                size: CGSize(width:  size.width  + haloSpread * 2,
                                             height: size.height + haloSpread * 2))
        glow.name        = MagixRules.glowNodeName
        glow.alpha       = 0.45
        glow.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        glow.zPosition   = -2   // derrière le sprite principal et les biseaux
        // Pulsing doux indépendant du breathing général.
        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 1.2),
            SKAction.fadeAlpha(to: 0.28, duration: 1.2),
        ])))
        sprite.addChild(glow)

        // ── Particules orbitales colorées (palette du joueur) ──────────────────
        // Rayon de base : bord du bloc + 35 % du spread (zone lumineuse du dégradé).
        let orbitR = size.width * 0.5 + haloSpread * 0.35
        let orbitSpawner = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 0.175, withRange: 0.09),
            SKAction.run { [weak sprite] in
                guard let sprite else { return }
                let colors = BlomixSkinCatalog.shared.bloxSKColors()
                guard !colors.isEmpty else { return }
                let color = colors.randomElement()!
                let angle  = CGFloat.random(in: 0..<(2 * .pi))
                let r      = CGFloat.random(in: (orbitR - 3)...(orbitR + 4))
                let pos    = CGPoint(x: cos(angle) * r,  y: sin(angle) * r)
                let drift  = CGFloat.random(in: 6...12)
                let endPos = CGPoint(x: cos(angle) * (r + drift), y: sin(angle) * (r + drift))
                let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.0...1.8))
                dot.fillColor   = color
                dot.strokeColor = .clear
                dot.position    = pos
                dot.alpha       = 0
                dot.zPosition   = -1   // entre le halo (-2) et le corps du bloc (0+)
                sprite.addChild(dot)
                dot.run(.sequence([
                    .group([
                        .sequence([.fadeAlpha(to: 0.82, duration: 0.28),
                                   .wait(forDuration: 0.35),
                                   .fadeOut(withDuration: 0.62)]),
                        .move(to: endPos, duration: 1.25),
                    ]),
                    .removeFromParent(),
                ]))
            },
        ]))
        sprite.run(orbitSpawner, withKey: MagixRules.orbitParticlesActionKey)

        // ── Symbole "?", "+", "9" ──────────────────────────────────────────────
        sprite.childNode(withName: symbolLabelName)?.removeFromParent()
        let sym = SKLabelNode(text: MagixRules.symbol(for: kind))
        sym.name                     = symbolLabelName
        sym.fontName                 = customUIFontPostScriptName
        sym.fontSize                 = size.height * 0.69
        sym.fontColor                = .black
        sym.horizontalAlignmentMode  = .center
        sym.verticalAlignmentMode    = .center
        sym.position                 = .zero
        sym.zPosition                = 5
        sprite.addChild(sym)
    }

    /// Crée un sprite Magix autonome avec shader dégradé + biseau + symbole. Utilisé pour le bloc en chute.
    private static func makeMagixShaderSprite(size: CGSize, kind: MagixKind) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: magixShaderBaseTexture, size: size)
        sprite.colorBlendFactor = 0
        sprite.color            = .white
        sprite.anchorPoint      = CGPoint(x: 0.5, y: 0.5)
        applyMagixShader(to: sprite, size: size, kind: kind,
                         symbolLabelName: MagixRules.symbolLabelName)
        return sprite
    }

    // MARK: - Bombe (sprite MAGIX-style noir/rouge/jaune)

    /// Shader cyclique noir → rouge joueur → jaune joueur, identique au MAGIX mais sur 3 couleurs.
    private static func makeBombPaletteShader() -> SKShader {
        let red    = bloxSolidFillColor(colorName: "red")    ?? SKColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)
        let yellow = bloxSolidFillColor(colorName: "yellow") ?? SKColor(red: 0.91, green: 0.77, blue: 0.42, alpha: 1)
        let black  = SKColor.black

        func v3(_ c: SKColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "vec3(%.4f,%.4f,%.4f)", Float(r), Float(g), Float(b))
        }
        // 3 couleurs : noir → rouge → jaune (cycle continu, même formule que MAGIX).
        let cols = [black, red, yellow]
        var branches = ""
        for (i, c) in cols.enumerated() {
            let next = (i + 1) % cols.count
            let lim  = String(format: "%.1f", Float(i + 1))
            if i == 0 {
                branches += "    if(fi<\(lim)){ca=\(v3(c));cb=\(v3(cols[next]));}\n"
            } else if i < cols.count - 1 {
                branches += "    else if(fi<\(lim)){ca=\(v3(c));cb=\(v3(cols[next]));}\n"
            } else {
                branches += "    else{ca=\(v3(c));cb=\(v3(cols[next]));}\n"
            }
        }
        let src = """
        vec3 bmbPal(float t){
            float N=3.0;
            float ti=fract(t)*N;
            float fi=floor(ti);
            float f=smoothstep(0.0,1.0,fract(ti));
            vec3 ca=vec3(0.0),cb=vec3(0.0);
        \(branches)    return mix(ca,cb,f);
        }
        void main(){
            vec2 uv=v_tex_coord;
            float t=u_time*0.09;
            vec3 c1=bmbPal(t);
            vec3 c2=bmbPal(t+0.333);
            vec3 c3=bmbPal(t+0.667);
            float wx=sin(uv.x*3.14159+t*0.5)*0.5+0.5;
            float wy=cos(uv.y*2.2-t*0.35)*0.5+0.5;
            vec3 ab=mix(c1,c2,wx);
            vec3 col=mix(ab,c3,wy*0.38);
            // Disque avec contour noir : ring masque la couleur dans la couronne externe (~2-3 pt).
            float d=distance(uv,vec2(0.5,0.5));
            float a=1.0-smoothstep(0.46,0.50,d);
            float ring=1.0-smoothstep(0.38,0.43,d);
            gl_FragColor=vec4(col*ring*a,a);
        }
        """
        return SKShader(source: src)
    }

    /// Applique le look bombe MAGIX-style sur un sprite existant (réutilisable pour icône HUD).
    private static func applyBombShader(to sprite: SKSpriteNode, size: CGSize) {
        sprite.texture          = magixShaderBaseTexture
        sprite.colorBlendFactor = 0
        sprite.color            = .white
        sprite.size             = size
        sprite.shader           = makeBombPaletteShader()

        // Nettoyer le symbole MAGIX éventuel (preview réutilisée).
        sprite.childNode(withName: MagixRules.symbolLabelName)?.removeFromParent()

        // ── Halo dégradé radial ────────────────────────────────────────────────
        sprite.removeAction(forKey: MagixRules.orbitParticlesActionKey)
        sprite.childNode(withName: MagixRules.glowNodeName)?.removeFromParent()
        let haloSpread: CGFloat = 16
        let haloTexture = makeMagixHaloTexture(blockSize: size, spread: haloSpread)
        let glow = SKSpriteNode(texture: haloTexture,
                                size: CGSize(width:  size.width  + haloSpread * 2,
                                             height: size.height + haloSpread * 2))
        glow.name        = MagixRules.glowNodeName
        glow.alpha       = 0.45
        glow.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        glow.zPosition   = -2
        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 1.2),
            SKAction.fadeAlpha(to: 0.28, duration: 1.2),
        ])))
        sprite.addChild(glow)

        // ── Particules orbitales noir / rouge joueur / jaune joueur ────────────
        let orbitR = size.width * 0.5 + haloSpread * 0.35
        let orbitSpawner = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 0.175, withRange: 0.09),
            SKAction.run { [weak sprite] in
                guard let sprite else { return }
                // Couleurs : rouge palette, jaune palette, ou quasi-noir.
                let roll = Int.random(in: 0..<3)
                let color: SKColor
                switch roll {
                case 0: color = bloxSolidFillColor(colorName: "red")    ?? SKColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)
                case 1: color = bloxSolidFillColor(colorName: "yellow") ?? SKColor(red: 0.91, green: 0.77, blue: 0.42, alpha: 1)
                default: color = SKColor(white: 0.12, alpha: 1)
                }
                let angle  = CGFloat.random(in: 0..<(2 * .pi))
                let r      = CGFloat.random(in: (orbitR - 3)...(orbitR + 4))
                let pos    = CGPoint(x: cos(angle) * r,  y: sin(angle) * r)
                let drift  = CGFloat.random(in: 6...12)
                let endPos = CGPoint(x: cos(angle) * (r + drift), y: sin(angle) * (r + drift))
                let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.0...1.8))
                dot.fillColor   = color
                dot.strokeColor = .clear
                dot.position    = pos
                dot.alpha       = 0
                dot.zPosition   = -1
                sprite.addChild(dot)
                dot.run(.sequence([
                    .group([
                        .sequence([.fadeAlpha(to: 0.82, duration: 0.28),
                                   .wait(forDuration: 0.35),
                                   .fadeOut(withDuration: 0.62)]),
                        .move(to: endPos, duration: 1.25),
                    ]),
                    .removeFromParent(),
                ]))
            },
        ]))
        sprite.run(orbitSpawner, withKey: MagixRules.orbitParticlesActionKey)
    }

    /// Crée un sprite bombe MAGIX-style autonome (shader + biseau + halo + particules).
    private static func makeBombShaderSprite(size: CGSize) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: magixShaderBaseTexture, size: size)
        sprite.colorBlendFactor = 0
        sprite.color            = .white
        sprite.anchorPoint      = CGPoint(x: 0.5, y: 0.5)
        applyBombShader(to: sprite, size: size)
        return sprite
    }

    /// Popup texte "CHROMAX" / "BRIXED" / "CROSSX" au centre de la case d'atterrissage,
    /// sur le même modèle que les popups COMBO.
    private func spawnMagixNamePopup(name: String, at position: CGPoint) {
        let lbl = SKLabelNode(text: name)
        lbl.fontName   = Self.customUIFontPostScriptName
        lbl.fontSize   = 22
        lbl.fontColor  = .white
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode   = .center
        lbl.position   = position
        lbl.zPosition  = 45
        addChild(lbl)

        let rise = SKAction.moveBy(x: 0, y: 44, duration: 0.85)
        rise.timingMode = .easeOut
        let fade = SKAction.sequence([
            SKAction.wait(forDuration: 0.38),
            SKAction.fadeAlpha(to: 0, duration: 0.47),
        ])
        lbl.run(SKAction.group([rise, fade])) { lbl.removeFromParent() }
    }

    // MARK: - Blocs Magix — logique

    /// Dispatche vers la bonne routine selon la variante du bloc Magix qui vient d'atterrir.
    private func applyMagixEffect(kind: MagixKind, at cell: GridAddress) {
        // Popup "CHROMAX" / "BRIXED" / "CROSSX" centré sur la case d'atterrissage.
        spawnMagixNamePopup(name: MagixRules.label(for: kind),
                            at: scenePointCellCenter(row: cell.row, column: cell.col))
        switch kind {
        case .chromax:  applyMagixEffect_chromax(at: cell)
        case .brixed:   applyMagixEffect_brixed(at: cell)
        case .crosx:    applyMagixEffect_crosx(at: cell)
        case .scrumblx: applyMagixEffect_scrumblx(at: cell)
        case .colorx:   applyMagixEffect_colorx(at: cell)
        case .cleanx:   applyMagixEffect_cleanx(at: cell)
        case .twistx:   applyMagixEffect_twistx(at: cell)
        }
    }

    // MARK: COLORX

    /// Crée ou rafraîchit le container d'overlays blancs sur les cellules de `colorName`.
    /// Appelé à chaque étape de la roulette COLORX.
    private func showColorxOverlays(for colorName: String) {
        guard let container = childNode(withName: Self.gridContainerName) else { return }

        let overlayContainer: SKNode
        if let existing = container.childNode(withName: Self.colorxOverlayContainerName) {
            overlayContainer = existing
            overlayContainer.removeAllChildren()
            overlayContainer.removeAllActions()
            overlayContainer.alpha = 1
        } else {
            let nc = SKNode()
            nc.name = Self.colorxOverlayContainerName
            container.addChild(nc)
            overlayContainer = nc
        }

        let cellSize = CGSize(width: GridLayout.cellPoints, height: GridLayout.cellPoints)
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            for c in 0..<GridLayout.columnCount {
                guard case .color(let name) = grid[r][c], name == colorName else { continue }
                guard let cell = container.childNode(withName: "cell_\(r)_\(c)") as? SKSpriteNode else { continue }
                let ov = SKSpriteNode(color: .white, size: cellSize)
                ov.alpha = 0
                ov.position = cell.position
                ov.zPosition = 8   // au-dessus des cellules (z 1) et de toutes les jonctions (z 2.01+)
                overlayContainer.addChild(ov)
                ov.run(SKAction.fadeAlpha(to: 0.70, duration: 0.06))
            }
        }
    }

    /// Supprime le container d'overlays COLORX (appel de sécurité hors dissolution normale).
    private func removeColorxOverlays() {
        childNode(withName: Self.gridContainerName)?
            .childNode(withName: Self.colorxOverlayContainerName)?
            .removeFromParent()
    }

    /// Roulette de couleur : le sprite COLORX s'arrête sur une couleur de la grille, puis tous
    /// les blocs de cette couleur disparaissent (score chaîne pour le nombre effacé).
    private func applyMagixEffect_colorx(at cell: GridAddress) {
        // Snapshot AVANT toute modification (bonus colonne vidée).
        let columnHadBlock: [Bool] = (0..<GridLayout.columnCount).map { col in
            (GridLayout.topRowIndex..<GridLayout.rowCount).contains { self.grid[$0][col] != .empty }
        }

        // ── 1. COLORX consommé immédiatement.
        grid[cell.row][cell.col] = .empty
        removeBloxJunctionElementsTouching([cell])

        // ── 2. Couleur finale : priorité aux couleurs présentes dans la grille.
        let presentColors: [String] = Self.colorPalette.filter { name in
            (GridLayout.topRowIndex..<GridLayout.rowCount).contains { r in
                (0..<GridLayout.columnCount).contains { c in
                    if case .color(let n) = grid[r][c] { return n == name }
                    return false
                }
            }
        }
        let candidatePool = presentColors.isEmpty ? Self.colorPalette : presentColors
        let finalColor    = candidatePool.randomElement() ?? Self.colorPalette.randomElement() ?? "red"

        // ── 3. Séquence de couleurs intermédiaires (4 couleurs ≠ finale, puis finale).
        //    Durées croissantes → effet de "ralentissement sur la couleur choisie".
        let stepDurations: [TimeInterval] = [0.10, 0.15, 0.22, 0.30, 0.50]
        var cycleColors: [String] = []
        var tempPool = Self.colorPalette.filter { $0 != finalColor }
        for _ in 0..<(stepDurations.count - 1) {
            if tempPool.isEmpty { tempPool = Self.colorPalette.filter { $0 != finalColor } }
            if let c = tempPool.randomElement() {
                cycleColors.append(c)
                tempPool.removeAll { $0 == c }
            }
        }
        cycleColors.append(finalColor)

        // ── 4. Fallback si pas de container.
        guard let container = childNode(withName: Self.gridContainerName) else {
            dissolveColorxMatchingBlocks(color: finalColor, columnHadBlockBefore: columnHadBlock)
            return
        }

        // ── 5. Animation roulette sur le sprite COLORX dans le container.
        let cellNodeName = "cell_\(cell.row)_\(cell.col)"
        guard let colorxSprite = container.childNode(withName: cellNodeName) as? SKSpriteNode else {
            dissolveColorxMatchingBlocks(color: finalColor, columnHadBlockBefore: columnHadBlock)
            return
        }
        colorxSprite.name = "cell_colorx_spinning"
        // Retirer shader et décorations Magix pour afficher une couleur unie.
        colorxSprite.shader           = nil
        colorxSprite.colorBlendFactor = 1
        colorxSprite.removeAction(forKey: MagixRules.orbitParticlesActionKey)
        colorxSprite.childNode(withName: MagixRules.glowNodeName)?.removeFromParent()
        colorxSprite.childNode(withName: MagixRules.symbolLabelName)?.removeFromParent()

        // Chaîne d'actions : changement de couleur + pop, puis dissolution.
        var steps: [SKAction] = []
        for (i, colorName) in cycleColors.enumerated() {
            let duration    = stepDurations[i]
            let captured    = colorName
            let capturedIdx = i
            steps.append(SKAction.run { [weak self, weak colorxSprite] in
                guard let self, let sprite = colorxSprite else { return }
                BlomixProceduralSFX.shared.playColorxRouletteClick(step: capturedIdx)
                sprite.color = Self.bloxSolidFillColor(colorName: captured) ?? SKColor(white: 0.5, alpha: 1)
                let pop = SKAction.sequence([
                    SKAction.scale(to: 1.25, duration: duration * 0.35),
                    SKAction.scale(to: 1.00, duration: duration * 0.65),
                ])
                sprite.run(pop)
                self.showColorxOverlays(for: captured)
            })
            steps.append(SKAction.wait(forDuration: duration))
        }
        // Bref hold sur la couleur finale, puis dissolution.
        steps.append(SKAction.run { [weak self, weak colorxSprite] in
            guard let self else { return }
            colorxSprite?.removeFromParent()
            self.dissolveColorxMatchingBlocks(color: finalColor, columnHadBlockBefore: columnHadBlock)
        })
        run(SKAction.sequence(steps))
    }

    /// Efface tous les blocs de `color` dans la grille, attribue les points (formule chaîne),
    /// anime leur disparition, puis applique la gravité et continue.
    private func dissolveColorxMatchingBlocks(color: String, columnHadBlockBefore: [Bool]) {
        // ── 1. Collecter et effacer les blocs de la couleur choisie.
        var targets: [GridAddress] = []
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            for c in 0..<GridLayout.columnCount {
                if case .color(let name) = grid[r][c], name == color {
                    targets.append(GridAddress(row: r, col: c))
                    grid[r][c] = .empty
                }
            }
        }

        // ── 2. Score (formule chaîne pour N blocs).
        if !targets.isEmpty {
            let pts      = Self.chainClearScorePoints(chainSeriesLevel: chainSeriesLevel,
                                                      groupSize: targets.count)
            let center   = sceneCentroid(for: Set(targets))
            let dotColor = Self.bloxSolidFillColor(colorName: color)
            addScore(points: pts, chainMultiplier: chainSeriesLevel,
                     floatAt: center, dotColor: dotColor)
        }
        removeBloxJunctionElementsTouching(Set(targets))

        // ── 3. Animation de dissolution (pop → fondu).
        guard let container = childNode(withName: Self.gridContainerName), !targets.isEmpty else {
            removeColorxOverlays()
            drawGrid()
            applyMagixCompactionAndContinue(columnHadBlockBefore: columnHadBlockBefore)
            return
        }

        let stagger: TimeInterval = 0.025
        // Sons de pop pour les 8 premiers blocs au maximum (évite la saturation audio).
        let popLimit = min(targets.count, 8)
        for (i, addr) in targets.enumerated() {
            guard let sprite = container.childNode(withName: "cell_\(addr.row)_\(addr.col)") as? SKSpriteNode
            else { continue }
            let shouldPlayPop = i < popLimit
            sprite.run(SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * stagger),
                SKAction.run {
                    if shouldPlayPop {
                        BlomixProceduralSFX.shared.playColorxDissolvePop()
                    }
                },
                SKAction.group([
                    SKAction.sequence([
                        SKAction.scale(to: 1.30, duration: 0.10),
                        SKAction.scale(to: 0.01, duration: 0.14),
                    ]),
                    SKAction.sequence([
                        SKAction.wait(forDuration: 0.10),
                        SKAction.fadeOut(withDuration: 0.14),
                    ]),
                ]),
                SKAction.removeFromParent(),
            ]))
        }

        // Fade-out synchronisé des overlays COLORX avec la dissolution des blocs.
        let dissolveDuration = Double(max(0, targets.count - 1)) * stagger + 0.24
        if let overlayContainer = container.childNode(withName: Self.colorxOverlayContainerName) {
            overlayContainer.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: dissolveDuration),
                SKAction.removeFromParent()
            ]))
        }

        let totalWait = Double(max(0, targets.count - 1)) * stagger + 0.26
        run(SKAction.sequence([
            SKAction.wait(forDuration: totalWait),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.drawGrid()
                self.applyMagixCompactionAndContinue(columnHadBlockBefore: columnHadBlockBefore)
            },
        ]))
    }

    // MARK: CLEANX

    /// Efface tout le contenu de la grille (animation 2 s : cycle couleurs + overlay blanc 0.1→1.0),
    /// puis laisse un Brix dont la valeur = nombre de cases supprimées.
    /// Le sprite CLEANX se transforme visuellement en ce Brix au moment de la dissolution.
    private func applyMagixEffect_cleanx(at cell: GridAddress) {

        // ── 1. Snapshot colonnes occupées (pour bonus colonne vidée).
        let columnHadBlock: [Bool] = (0..<GridLayout.columnCount).map { col in
            (GridLayout.topRowIndex..<GridLayout.rowCount).contains { self.grid[$0][col] != .empty }
        }

        // ── 2. Collecter toutes les cases occupées (hors CLEANX lui-même).
        var targets: [GridAddress] = []
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            for c in 0..<GridLayout.columnCount {
                guard !(r == cell.row && c == cell.col) else { continue }
                guard grid[r][c] != .empty else { continue }
                targets.append(GridAddress(row: r, col: c))
            }
        }
        let clearedCount = targets.count

        // ── 3. Supprimer jonctions et biseaux de groupe.
        removeBloxJunctionElementsTouching(Set(targets).union([cell]))

        // ── 4. Fallback sans container.
        guard let container = childNode(withName: Self.gridContainerName) else {
            for addr in targets { grid[addr.row][addr.col] = .empty }
            grid[cell.row][cell.col] = .priks(max(1, clearedCount))
            addScore(points: 200, chainMultiplier: chainSeriesLevel,
                     floatAt: scenePointCellCenter(row: cell.row, column: cell.col), dotColor: .white)
            drawGrid()
            applyMagixCompactionAndContinue(columnHadBlockBefore: columnHadBlock)
            return
        }

        // ── 5. Animation : cycle couleurs + overlay blanc progressif sur les blocs cibles.
        let overlayDuration: TimeInterval = 2.0
        let cycleInterval:   TimeInterval = 0.40   // ≈ 5 changements sur 2 s
        let palette = Self.colorPalette

        // Son atmosphérique CLEANX — démarre avec l'animation.
        playMatchSound(.cleanx)

        // Container d'overlays (préfixe "cell_" → supprimé automatiquement par drawGrid).
        let overlayContainer = SKNode()
        overlayContainer.name = "cell_cleanxOverlays"
        container.addChild(overlayContainer)

        for addr in targets {
            guard let sprite = container.childNode(withName: "cell_\(addr.row)_\(addr.col)") as? SKSpriteNode
            else { continue }

            // Cycle de couleurs sous l'overlay.
            var colorActions: [SKAction] = []
            let steps = Int(overlayDuration / cycleInterval) + 2
            for _ in 0..<steps {
                let col = palette.randomElement() ?? "red"
                colorActions.append(SKAction.run { [weak sprite] in
                    sprite?.color = Self.bloxSolidFillColor(colorName: col) ?? .white
                    sprite?.colorBlendFactor = 1
                })
                colorActions.append(SKAction.wait(forDuration: cycleInterval))
            }
            sprite.run(SKAction.sequence(colorActions), withKey: "cleanxColorCycle")

            // Overlay blanc 0.1 → 1.0.
            let cellSize = CGSize(width: GridLayout.cellPoints, height: GridLayout.cellPoints)
            let ov = SKSpriteNode(color: .white, size: cellSize)
            ov.alpha    = 0.1
            ov.position = sprite.position
            ov.zPosition = 8
            overlayContainer.addChild(ov)
            ov.run(SKAction.fadeAlpha(to: 1.0, duration: overlayDuration))
        }

        // ── 6. Après 2 s : fade-out overlay → dissolution visible + transformation CLEANX → Brix.
        let overlayFadeDuration: TimeInterval = 0.20
        run(SKAction.sequence([
            SKAction.wait(forDuration: overlayDuration),
            // Phase A : l'overlay blanc disparaît, révélant les blocs colorés en dessous.
            SKAction.run { [weak overlayContainer] in
                overlayContainer?.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: overlayFadeDuration),
                    SKAction.removeFromParent(),
                ]))
            },
            SKAction.wait(forDuration: overlayFadeDuration),
            // Phase B : dissolution des blocs + particules, maintenant visibles sur fond sombre.
            SKAction.run { [weak self] in
                guard let self else { return }

                // Arrêter cycles couleur + dissoudre chaque cible.
                for addr in targets {
                    guard let sprite = container.childNode(withName: "cell_\(addr.row)_\(addr.col)") as? SKSpriteNode
                    else { continue }
                    sprite.removeAction(forKey: "cleanxColorCycle")
                    let scenePos = self.convert(sprite.position, from: container)
                    self.spawnChainPopDots(at: scenePos, color: sprite.color)
                    sprite.run(SKAction.sequence([
                        SKAction.group([
                            SKAction.sequence([
                                SKAction.scale(to: 1.30, duration: 0.10),
                                SKAction.scale(to: 0.01, duration: 0.14),
                            ]),
                            SKAction.sequence([
                                SKAction.wait(forDuration: 0.10),
                                SKAction.fadeOut(withDuration: 0.14),
                            ]),
                        ]),
                        SKAction.removeFromParent(),
                    ]))
                }

                // Transformer le sprite CLEANX en Brix visuellement.
                if let cleanxSprite = container.childNode(withName: "cell_\(cell.row)_\(cell.col)") as? SKSpriteNode {
                    cleanxSprite.removeAction(forKey: MagixRules.orbitParticlesActionKey)
                    cleanxSprite.childNode(withName: MagixRules.glowNodeName)?.removeFromParent()
                    cleanxSprite.childNode(withName: MagixRules.symbolLabelName)?.removeFromParent()
                    cleanxSprite.shader           = nil
                    cleanxSprite.color            = Self.priksSolidFillColor()
                    cleanxSprite.colorBlendFactor = 1
                    let digitNode = SKLabelNode(text: "\(max(1, clearedCount))")
                    digitNode.fontName                = Self.customUIFontPostScriptName
                    digitNode.fontSize                = clearedCount >= 10 ? 13 : 18
                    digitNode.fontColor               = Self.priksDigitLabelColor()
                    digitNode.horizontalAlignmentMode = .center
                    digitNode.verticalAlignmentMode   = .center
                    digitNode.position                = .zero
                    digitNode.zPosition               = 2
                    cleanxSprite.addChild(digitNode)
                    let cellSize = Self.solidGameplayBloxPixelSize()
                    cleanxSprite.run(SKAction.sequence([
                        SKAction.scale(to: 1.25, duration: 0.10),
                        SKAction.scale(to: 1.00, duration: 0.15),
                    ]))
                }

                // Mettre à jour le modèle de grille.
                for addr in targets { self.grid[addr.row][addr.col] = .empty }
                self.grid[cell.row][cell.col] = .priks(max(1, clearedCount))

                // Score : 200 pts de base, multiplicateur de stage appliqué dans addScore.
                let scorePos = self.scenePointCellCenter(row: cell.row, column: cell.col)
                self.addScore(points: 200, chainMultiplier: self.chainSeriesLevel,
                              floatAt: scorePos, dotColor: .white)

                // Après la dissolution, redessiner et compacter.
                self.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.30),
                    SKAction.run { [weak self] in
                        guard let self else { return }
                        self.drawGrid()
                        self.applyMagixCompactionAndContinue(columnHadBlockBefore: columnHadBlock)
                    },
                ]))
            },
        ]))
    }

    // MARK: TWISTX

    /// TWISTX — échange automatique d'une couleur aléatoire avec les Priks.
    ///
    /// À l'atterrissage :
    /// 1. Choisit aléatoirement une couleur présente dans la grille.
    /// 2. Trouve la valeur minimale parmi tous les Priks existants (défaut 3 si aucun Priks).
    /// 3. Échange : blocs de la couleur choisie → Priks(minValue), tous les Priks → color(chosenColor).
    private func applyMagixEffect_twistx(at cell: GridAddress) {
        grid[cell.row][cell.col] = .empty
        removeBloxJunctionElementsTouching([cell])

        // ── 1. Couleur cible aléatoire parmi celles présentes ─────────────────
        let presentColors: [String] = Self.colorPalette.filter { name in
            (GridLayout.topRowIndex..<GridLayout.rowCount).contains { r in
                (0..<GridLayout.columnCount).contains { c in
                    if case .color(let n) = grid[r][c] { return n == name }
                    return false
                }
            }
        }
        guard let chosenColor = presentColors.randomElement() else {
            // Aucune couleur dans la grille → rien à faire.
            isProcessing = false
            return
        }

        // ── 2. Valeur minimale des Priks (défaut 3 si aucun) ─────────────────
        var minPriks = Int.max
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            for c in 0..<GridLayout.columnCount {
                if case .priks(let n) = grid[r][c] { minPriks = min(minPriks, n) }
            }
        }
        let priksValue = (minPriks == Int.max) ? 3 : minPriks

        // ── 3. Collecte + suppression des jonctions ────────────────────────────
        var colorCells: [GridAddress] = []
        var priksCells: [GridAddress] = []
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            for c in 0..<GridLayout.columnCount {
                switch grid[r][c] {
                case .color(let n) where n == chosenColor: colorCells.append(GridAddress(row: r, col: c))
                case .priks:                               priksCells.append(GridAddress(row: r, col: c))
                default: break
                }
            }
        }
        let allAffected = Set(colorCells + priksCells)
        if !allAffected.isEmpty { removeBloxJunctionElementsTouching(allAffected) }

        // ── 4. Animation pop case par case (mélangé, stagger 0.04 s) ──────────
        guard let container = childNode(withName: Self.gridContainerName) else {
            for addr in colorCells { grid[addr.row][addr.col] = .priks(priksValue) }
            for addr in priksCells { grid[addr.row][addr.col] = .color(chosenColor) }
            drawGrid(); resolveChains()
            return
        }

        // Paires (adresse, nouveau bloc) mélangées pour un rendu organique.
        var swapPairs: [(GridAddress, BlockType)] = []
        for addr in colorCells { swapPairs.append((addr, .priks(priksValue))) }
        for addr in priksCells { swapPairs.append((addr, .color(chosenColor))) }
        swapPairs.shuffle()

        let stagger: TimeInterval = 0.04
        for (idx, (addr, newBlock)) in swapPairs.enumerated() {
            let delay         = TimeInterval(idx) * stagger
            let captured      = addr
            let capturedBlock = newBlock
            let capturedIdx   = idx
            run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    BlomixProceduralSFX.shared.playTwistxFlip(index: capturedIdx)
                    self.grid[captured.row][captured.col] = capturedBlock
                    let nodeName = "cell_\(captured.row)_\(captured.col)"
                    container.childNode(withName: nodeName)?.removeFromParent()
                    let newSprite = Self.makeSolidGameplayBlockSprite(block: capturedBlock)
                    newSprite.name     = nodeName
                    newSprite.position = Self.gridContainerLocalCellCenter(
                        row: captured.row, column: captured.col)
                    newSprite.setScale(0.5)
                    container.addChild(newSprite)
                    newSprite.run(SKAction.sequence([
                        SKAction.scale(to: 1.35, duration: 0.07),
                        SKAction.scale(to: 1.00, duration: 0.05),
                    ]))
                },
            ]))
        }

        let totalDelay = TimeInterval(swapPairs.count) * stagger + 0.15
        run(SKAction.sequence([
            SKAction.wait(forDuration: totalDelay),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.drawGrid()
                self.resolveChains()
            },
        ]))
    }

    // MARK: CHROMAX

    /// Marche aléatoire 8-connexe depuis `startCell`, transforme jusqu'à 15 cellules occupées
    /// (y compris la case d'atterrissage) en `chosenColor`, anime la propagation cellule par cellule,
    /// puis appelle `resolveChains()` pour déclencher la chaîne.
    private func applyMagixEffect_chromax(at startCell: GridAddress) {
        let chosenColor = Self.colorPalette.randomElement() ?? "red"

        // ── 1. Marche aléatoire 8-connexe ─────────────────────────────────────
        var path: [GridAddress] = [startCell]
        var visited: Set<GridAddress> = [startCell]
        var current = startCell

        while path.count < MagixRules.chromaxPathLength {
            let candidates = Self.chainNeighborDeltas8.compactMap { d -> GridAddress? in
                let nr = current.row + d.dr
                let nc = current.col + d.dc
                guard nr >= GridLayout.topRowIndex, nr < GridLayout.rowCount,
                      nc >= 0, nc < GridLayout.columnCount else { return nil }
                let addr = GridAddress(row: nr, col: nc)
                guard !visited.contains(addr), grid[nr][nc] != .empty else { return nil }
                return addr
            }
            guard !candidates.isEmpty else { break }
            let next = candidates.randomElement()!
            path.append(next)
            visited.insert(next)
            current = next
        }

        // ── 2. Suppression immédiate des barres de jonction (diagonales) touchant
        //      le chemin — évite les artefacts visuels pendant la transformation.
        removeBloxJunctionElementsTouching(Set(path))

        // ── 3. Fallback sans container ─────────────────────────────────────────
        guard let container = childNode(withName: Self.gridContainerName) else {
            for addr in path { grid[addr.row][addr.col] = .color(chosenColor) }
            drawGrid()
            resolveChains()
            return
        }

        // ── 4. Transformation PROGRESSIVE : une case à la fois ────────────────
        // Chaque case : on remplace son sprite par un nouveau sprite coloré avec
        // un effet « pop » (scale 0.5 → 1.4 → 1.0), puis on met à jour la grille.
        // La grille logique est mise à jour au fil de l'animation pour que
        // resolveChains() trouve l'état final correct.
        let stepDelay: TimeInterval = 0.08
        var totalDelay: TimeInterval = 0
        let pathTotal = path.count

        for (stepIdx, addr) in path.enumerated() {
            let capturedAddr  = addr
            let capturedStep  = stepIdx
            run(SKAction.sequence([
                SKAction.wait(forDuration: totalDelay),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    BlomixProceduralSFX.shared.playChromaxTick(step: capturedStep, total: pathTotal)
                    // Mise à jour logique
                    self.grid[capturedAddr.row][capturedAddr.col] = .color(chosenColor)
                    // Remplacement du sprite
                    let nodeName = "cell_\(capturedAddr.row)_\(capturedAddr.col)"
                    container.childNode(withName: nodeName)?.removeFromParent()
                    let newSprite = Self.makeSolidGameplayBlockSprite(block: .color(chosenColor))
                    newSprite.name = nodeName
                    newSprite.position = Self.gridContainerLocalCellCenter(
                        row: capturedAddr.row, column: capturedAddr.col)
                    newSprite.setScale(0.5)
                    container.addChild(newSprite)
                    newSprite.run(SKAction.sequence([
                        SKAction.scale(to: 1.40, duration: 0.07),
                        SKAction.scale(to: 1.00, duration: 0.05),
                    ]))
                },
            ]))
            totalDelay += stepDelay
        }

        // ── 4. Resynchronisation + résolution des chaînes après l'animation ────
        run(SKAction.sequence([
            SKAction.wait(forDuration: totalDelay + 0.12),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.drawGrid()
                self.resolveChains()
            },
        ]))
    }

        // MARK: BRIXED

    /// Pose le BRIXED comme un Priks(9), applique un flash sur tous les Brix existants,
    /// puis les décrémente de 2 (ceux à ≤ 0 disparaissent), applique la gravité et appelle `resolveChains()`.
    private func applyMagixEffect_brixed(at cell: GridAddress) {
        // ── 1. Le BRIXED devient un Priks(9) dans la grille ───────────────────
        grid[cell.row][cell.col] = .priks(MagixRules.brixedInitialHits)

        // ── 2. Collecte tous les autres Brix (avec leur valeur courante) ───────
        var affectedPriks: [(addr: GridAddress, currentValue: Int)] = []
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            for c in 0..<GridLayout.columnCount {
                let addr = GridAddress(row: r, col: c)
                if addr == cell { continue }
                guard case .priks(let n) = grid[r][c] else { continue }
                affectedPriks.append((addr, n))
            }
        }

        // ── 3. Dessin initial (Priks(9) visible à la case d'atterrissage) ─────
        drawGrid()

        // ── 4. Flash blanc sur tous les Brix ────────────────────────────────
        guard let container = childNode(withName: Self.gridContainerName) else {
            finishBrixedDecrement(at: cell, affected: affectedPriks)
            return
        }
        let flashDuration: TimeInterval = 0.20

        // Impact grave au déclenchement du flash BRIXED.
        BlomixProceduralSFX.shared.playBrixedImpact()

        // Flash sur le nouveau Priks(9) + tous les autres Brix affectés
        var allPriksAddrs = affectedPriks.map { $0.addr }
        allPriksAddrs.append(cell)
        for addr in allPriksAddrs {
            guard let sprite = container.childNode(withName: "cell_\(addr.row)_\(addr.col)") as? SKSpriteNode else { continue }
            sprite.run(SKAction.sequence([
                SKAction.colorize(with: .white, colorBlendFactor: 0.85, duration: flashDuration * 0.35),
                SKAction.colorize(with: .white, colorBlendFactor: 0.0,  duration: flashDuration * 0.65),
            ]))
        }

        // ── 5. Après le flash, décrement + gravité ────────────────────────────
        run(SKAction.sequence([
            SKAction.wait(forDuration: flashDuration + 0.05),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.finishBrixedDecrement(at: cell, affected: self.affectedPriks_snapshot)
            },
        ]))

        // Sauvegarde temporaire pour le callback (capture sans retain cycle fort)
        affectedPriks_snapshot = affectedPriks
    }

    /// Snapshot temporaire utilisé par `applyMagixEffect_brixed` pour le callback asynchrone.
    private var affectedPriks_snapshot: [(addr: GridAddress, currentValue: Int)] = []

    private func finishBrixedDecrement(at cell: GridAddress, affected: [(addr: GridAddress, currentValue: Int)]) {
        affectedPriks_snapshot = []
        let columnHadBlockBefore: [Bool] = (0..<GridLayout.columnCount).map { col in
            (GridLayout.topRowIndex..<GridLayout.rowCount).contains { grid[$0][col] != .empty }
        }

        // Élimine TOUS les Brix existants — seul le Priks(9) apporté par le BRIXED reste.
        var vanishedPriks = Set<GridAddress>()
        for item in affected {
            grid[item.addr.row][item.addr.col] = .empty
            vanishedPriks.insert(item.addr)
        }
        // Supprimer les barres de jonction des cases détruites avant l'animation.
        if !vanishedPriks.isEmpty {
            removeBloxJunctionElementsTouching(vanishedPriks)
        }

        // Score immédiat pour les Brix détruits.
        if !vanishedPriks.isEmpty {
            let pts = vanishedPriks.count * 20
            addScore(points: pts, chainMultiplier: 0, floatAt: sceneCentroid(for: vanishedPriks))
        }

        // Animation de disparition des Brix → puis gravité → resolveChains.
        let continueAfterVanish: () -> Void = { [weak self] in
            guard let self else { return }
            self.applyMagixCompactionAndContinue(columnHadBlockBefore: columnHadBlockBefore)
        }

        if vanishedPriks.isEmpty {
            drawGrid()
            continueAfterVanish()
        } else {
            animateVanishingPriks(cells: vanishedPriks) { [weak self] in
                guard let self else { return }
                self.drawGrid()
                continueAfterVanish()
            }
        }
    }

    // MARK: CROSX

    /// Transforme toutes les cases `.color()` de la croix (même ligne + même colonne)
    /// ainsi que la case d'atterrissage en une couleur aléatoire, puis appelle `resolveChains()`.
    private func applyMagixEffect_crosx(at cell: GridAddress) {
        let chosenColor = Self.colorPalette.randomElement() ?? "red"

        // ── 1. Collecte : LIGNE ENTIÈRE + COLONNE ENTIÈRE centrées sur la case d'atterrissage.
        // Transformées : Blox (.color) ET Brix (.priks) → tous deviennent la couleur aléatoire.
        // Cases vides et Magix ignorées.
        var crossCells: [GridAddress] = []

        // Ligne horizontale complète
        for c in 0..<GridLayout.columnCount {
            let addr = GridAddress(row: cell.row, col: c)
            switch grid[cell.row][c] {
            case .color, .priks: crossCells.append(addr)
            default: break
            }
        }
        // Colonne verticale complète (évite le doublon sur la case centrale)
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            if r == cell.row { continue }
            let addr = GridAddress(row: r, col: cell.col)
            switch grid[r][cell.col] {
            case .color, .priks: crossCells.append(addr)
            default: break
            }
        }
        // La case centrale elle-même (le CROSX qui vient d'atterrir)
        if !crossCells.contains(cell) { crossCells.append(cell) }

        // ── 2. Suppression immédiate des barres de jonction touchant la croix.
        removeBloxJunctionElementsTouching(Set(crossCells))

        // ── 3. Fallback sans container ─────────────────────────────────────────
        guard let container = childNode(withName: Self.gridContainerName) else {
            for addr in crossCells { grid[addr.row][addr.col] = .color(chosenColor) }
            drawGrid()
            resolveChains()
            return
        }

        // ── 3. Animation PROGRESSIVE depuis le centre vers l'extérieur.
        // Les cases sont triées par distance de Manhattan au centre (0, 1, 2, …).
        // Toutes les cases d'une même distance s'animent simultanément, puis les
        // cases plus éloignées suivent avec un léger décalage.
        let sorted = crossCells.sorted {
            let d1 = abs($0.row - cell.row) + abs($0.col - cell.col)
            let d2 = abs($1.row - cell.row) + abs($1.col - cell.col)
            return d1 < d2
        }

        let waveDelay: TimeInterval = 0.06
        var totalDelay: TimeInterval = 0
        var prevDist  = -1
        var ringIndex = 0

        for addr in sorted {
            let dist = abs(addr.row - cell.row) + abs(addr.col - cell.col)
            if dist != prevDist {
                // Nouvelle vague : décalage supplémentaire + son d'anneau.
                if prevDist >= 0 { totalDelay += waveDelay }
                let capturedRing  = ringIndex
                let capturedDelay = totalDelay
                run(SKAction.sequence([
                    SKAction.wait(forDuration: capturedDelay),
                    SKAction.run { BlomixProceduralSFX.shared.playCrosxPulse(ring: capturedRing) },
                ]))
                prevDist  = dist
                ringIndex += 1
            }
            let capturedAddr = addr
            let capturedDelay = totalDelay
            run(SKAction.sequence([
                SKAction.wait(forDuration: capturedDelay),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    self.grid[capturedAddr.row][capturedAddr.col] = .color(chosenColor)
                    let nodeName = "cell_\(capturedAddr.row)_\(capturedAddr.col)"
                    container.childNode(withName: nodeName)?.removeFromParent()
                    let newSprite = Self.makeSolidGameplayBlockSprite(block: .color(chosenColor))
                    newSprite.name = nodeName
                    newSprite.position = Self.gridContainerLocalCellCenter(
                        row: capturedAddr.row, column: capturedAddr.col)
                    newSprite.setScale(0.5)
                    container.addChild(newSprite)
                    newSprite.run(SKAction.sequence([
                        SKAction.scale(to: 1.35, duration: 0.07),
                        SKAction.scale(to: 1.00, duration: 0.05),
                    ]))
                },
            ]))
        }
        let finalDelay = totalDelay + waveDelay  // inclut la dernière vague

        // ── 4. Resynchronisation + résolution des chaînes ─────────────────────
        run(SKAction.sequence([
            SKAction.wait(forDuration: finalDelay + 0.12),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.drawGrid()
                self.resolveChains()
            },
        ]))
    }

    // MARK: SCRUMBLX

    /// Chaque ligne occupée se décale horizontalement d'un nombre de crans aléatoire (1–7)
    /// dans une direction aléatoire, avec wrap-around.
    /// Les déplacements sont animés cran par cran (0.08 s/cran) avec un décalage de 0.3 s entre lignes.
    /// Séquence : flash blanc sur toute la grille → animations → drawGrid + resolveChains.
    private func applyMagixEffect_scrumblx(at cell: GridAddress) {
        // ── 1. La case d'atterrissage disparaît immédiatement (le SCRUMBLX n'est pas dans la grille après).
        grid[cell.row][cell.col] = .empty

        // ── 2. −1 sur tous les Brix de la grille (avant l'animation de décalage).
        var vanishedBrixAddrs = Set<GridAddress>()
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            for c in 0..<GridLayout.columnCount {
                guard case .priks(let n) = grid[r][c] else { continue }
                if n <= 1 {
                    grid[r][c] = .empty
                    vanishedBrixAddrs.insert(GridAddress(row: r, col: c))
                } else {
                    grid[r][c] = .priks(n - 1)
                }
            }
        }
        if !vanishedBrixAddrs.isEmpty {
            let pts = vanishedBrixAddrs.count * 20
            addScore(points: pts, chainMultiplier: 0, floatAt: sceneCentroid(for: vanishedBrixAddrs))
        }

        // ── 3. Supprime toutes les barres de jonction (fausses après décalage + Brix disparus).
        let allOccupied: Set<GridAddress> = {
            var s = Set<GridAddress>()
            for r in GridLayout.topRowIndex..<GridLayout.rowCount {
                for c in 0..<GridLayout.columnCount {
                    if grid[r][c] != .empty { s.insert(GridAddress(row: r, col: c)) }
                }
            }
            return s
        }()
        removeBloxJunctionElementsTouching(allOccupied.union(vanishedBrixAddrs))


        // ── 4. Flash blanc sur le sprite SCRUMBLX uniquement, puis il disparaît.
        guard let container = childNode(withName: Self.gridContainerName) else {
            // Fallback sans container : décalage instantané, compaction, puis resolveChains.
            let colHad: [Bool] = (0..<GridLayout.columnCount).map { col in
                (GridLayout.topRowIndex..<GridLayout.rowCount).contains { self.grid[$0][col] != .empty }
            }
            applyMagixEffect_scrumblx_shiftGrid()
            drawGrid()
            applyMagixCompactionAndContinue(columnHadBlockBefore: colHad)
            return
        }

        // Mise à jour visuelle des Brix dans le container existant (avant l'animation).
        // Brix disparus : sprite supprimé. Brix survivants : label mis à jour.
        // Sons staggerés pour les Brix qui disparaissent à cause du SCRUMBLX (−1 → 0).
        let sortedVanished = vanishedBrixAddrs.sorted { a, b in
            a.row != b.row ? a.row < b.row : a.col < b.col
        }
        for (i, _) in sortedVanished.enumerated() {
            if i == 0 {
                playMatchSound(.priksVanish)
            } else {
                run(SKAction.sequence([
                    SKAction.wait(forDuration: TimeInterval(i) * 0.07),
                    SKAction.run { [weak self] in self?.playMatchSound(.priksVanish) },
                ]))
            }
        }

        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            for c in 0..<GridLayout.columnCount {
                let addr = GridAddress(row: r, col: c)
                let nodeName = "cell_\(r)_\(c)"
                if vanishedBrixAddrs.contains(addr) {
                    container.childNode(withName: nodeName)?.removeFromParent()
                } else if case .priks(let newN) = grid[r][c],
                          let bg = container.childNode(withName: nodeName),
                          let lbl = bg.children.first(where: { $0 is SKLabelNode }) as? SKLabelNode {
                    lbl.text = "\(newN)"
                }
            }
        }

        // ── Clip visuel : on enveloppe le container dans un SKCropNode masqué à la taille exacte
        //    de la grille. Aucun sprite ne peut apparaître en dehors quelle que soit l'animation.
        //
        //    Le gridFrameOutline dépasse légèrement hors du masque (frameMargin + strokeW/2 ≈ 2.5 pt).
        //    On le détache du container AVANT le clip et on le pose directement dans la scène
        //    pour qu'il reste visible pendant toute l'animation.
        //    drawGrid() le recrée à l'intérieur du container à la fin de l'animation.
        let containerScenePos = container.position
        let tempOutline = container.childNode(withName: Self.gridFrameOutlineName)
        tempOutline?.removeFromParent()
        if let outline = tempOutline {
            outline.position = containerScenePos   // identique à sa position scène d'origine
            addChild(outline)
        }

        let gridClipSize = CGSize(
            width:  GridLayout.spanPoints,
            height: CGFloat(GridLayout.rowCount) * GridLayout.cellPoints)
        let cropWrapper = SKCropNode()
        cropWrapper.maskNode = SKSpriteNode(color: .white, size: gridClipSize)
        cropWrapper.position  = containerScenePos
        cropWrapper.zPosition = container.zPosition
        container.removeFromParent()
        container.position = .zero          // position relative au cropWrapper
        cropWrapper.addChild(container)
        addChild(cropWrapper)

        // Son atmosphérique SCRUMBLX — démarre avec le flash.
        playMatchSound(.scrumblx)

        let flashDur: TimeInterval = 0.18
        if let scrumblxSprite = container.childNode(withName: "cell_\(cell.row)_\(cell.col)") as? SKSpriteNode {
            // Renommer immédiatement pour que le loop de décalage de ligne ne le trouve pas
            // et ne tente pas de l'animer en même temps que le fondu de disparition.
            scrumblxSprite.name = "cell_scrumblx_vanishing"
            scrumblxSprite.run(SKAction.sequence([
                SKAction.colorize(with: .white, colorBlendFactor: 0.95, duration: flashDur * 0.35),
                SKAction.fadeAlpha(to: 0, duration: flashDur * 0.65),
                SKAction.removeFromParent(),
            ]))
        }

        // ── 4. Prépare les décalages par ligne (haut → bas, seulement les lignes non vides).
        // Structure : (rowIndex, direction: +1 right / -1 left, steps: 1…7)
        struct RowShift { let row: Int; let direction: Int; let steps: Int }
        var shifts: [RowShift] = []
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            let hasBlock = (0..<GridLayout.columnCount).contains { grid[r][$0] != .empty }
            guard hasBlock else { continue }
            let dir   = Bool.random() ? 1 : -1
            let steps = Int.random(in: 1...7)
            shifts.append(RowShift(row: r, direction: dir, steps: steps))
        }

        // ── 5. Animation : un cran à la fois, wrap-around visuel à chaque bord.
        //
        // Pour chaque cran, on identifie les sprites qui sortiraient de la grille et on les
        // téléporte instantanément à l'opposé (colonne −1 ou colonne 8) avant le moveBy.
        // Résultat : on ne voit jamais un bloc hors de la grille.
        let cranDur:  TimeInterval = 0.08
        let rowGap:   TimeInterval = 0.30
        let cellPts:  CGFloat      = GridLayout.cellPoints
        let cols      = GridLayout.columnCount
        let half      = GridLayout.spanPoints / 2   // demi-largeur du container

        for (shiftIdx, shift) in shifts.enumerated() {
            let lineStartDelay = flashDur + Double(shiftIdx) * rowGap

            for step in 1...shift.steps {
                let stepDelay        = lineStartDelay + Double(step - 1) * cranDur
                let stepsDoneBefore  = step - 1   // crans déjà effectués avant celui-ci

                run(SKAction.sequence([
                    SKAction.wait(forDuration: stepDelay),
                    SKAction.run { [weak self] in
                        guard let self else { return }
                        let dx = CGFloat(shift.direction) * cellPts

                        for c in 0..<cols {
                            guard let sprite = container.childNode(
                                withName: "cell_\(shift.row)_\(c)") as? SKSpriteNode
                            else { continue }

                            // Colonne logique courante du sprite (après stepsDoneBefore crans).
                            let currentCol = ((c + shift.direction * stepsDoneBefore) % cols + cols) % cols

                            // Stoppe tout moveBy résiduel et snap à la position grille exacte.
                            // Évite les dérives de position liées au timing sub-frame entre steps.
                            sprite.removeAllActions()
                            let snapX = (-half) + (CGFloat(currentCol) + 0.5) * cellPts
                            sprite.position = CGPoint(x: snapX, y: sprite.position.y)

                            // Wrap-around : ce cran fait-il sortir le sprite de la grille ?
                            let wraps = (shift.direction == 1 && currentCol == cols - 1)
                                     || (shift.direction == -1 && currentCol == 0)
                            if wraps {
                                // Téléportation au bord opposé (hors grille d'1 case) avant le moveBy.
                                let teleportX: CGFloat = shift.direction == 1
                                    ? -half - cellPts / 2   // juste à gauche de la colonne 0
                                    :  half + cellPts / 2   // juste à droite de la colonne (cols−1)
                                sprite.position = CGPoint(x: teleportX, y: sprite.position.y)
                            }

                            let move = SKAction.moveBy(x: dx, y: 0, duration: cranDur * 0.9)
                            move.timingMode = .easeInEaseOut
                            sprite.run(move)
                        }
                    },
                ]))
            }

            // Après le dernier cran : mise à jour grille + renommage sprites.
            let finalDelay = lineStartDelay + Double(shift.steps) * cranDur
            run(SKAction.sequence([
                SKAction.wait(forDuration: finalDelay),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    let r     = shift.row
                    let delta = shift.direction * shift.steps

                    let oldRow = self.grid[r]
                    var newRow = [BlockType](repeating: .empty, count: cols)
                    for c in 0..<cols {
                        let newC = ((c + delta) % cols + cols) % cols
                        newRow[newC] = oldRow[c]
                    }
                    self.grid[r] = newRow

                    // Renommage via préfixe temporaire pour éviter les collisions.
                    for c in 0..<cols {
                        container.childNode(withName: "cell_\(r)_\(c)")?.name = "cell_tmp_\(r)_\(c)"
                    }
                    for c in 0..<cols {
                        let origC = ((c - delta) % cols + cols) % cols
                        container.childNode(withName: "cell_tmp_\(r)_\(origC)")?.name = "cell_\(r)_\(c)"
                    }
                },
            ]))
        }

        // ── 6. Après toutes les animations : gravité (compaction vers le haut) puis resolveChains.
        let lastShiftEnd: TimeInterval = {
            guard let last = shifts.last else { return flashDur }
            return flashDur + Double(shifts.count - 1) * rowGap + Double(last.steps) * cranDur
        }()

        // Snapshot des colonnes occupées pris maintenant (avant compaction) pour les bonus colonne vidée.
        let columnHadBlock: [Bool] = (0..<GridLayout.columnCount).map { col in
            (GridLayout.topRowIndex..<GridLayout.rowCount).contains { self.grid[$0][col] != .empty }
        }

        run(SKAction.sequence([
            SKAction.wait(forDuration: lastShiftEnd + 0.15),
            SKAction.run { [weak self] in
                guard let self else { return }
                // Retirer le border temporaire posé dans la scène : drawGrid() le recrée dans le container.
                tempOutline?.removeFromParent()
                // Restaurer le container depuis le cropWrapper avant de redessiner la grille.
                cropWrapper.removeFromParent()
                container.removeFromParent()
                container.position = containerScenePos
                self.addChild(container)
                self.drawGrid()
                self.applyMagixCompactionAndContinue(columnHadBlockBefore: columnHadBlock)
            },
        ]))
    }

    /// Version synchrone sans animation — décale la grille logique uniquement (fallback).
    private func applyMagixEffect_scrumblx_shiftGrid() {
        let cols = GridLayout.columnCount
        for r in GridLayout.topRowIndex..<GridLayout.rowCount {
            let hasBlock = (0..<cols).contains { grid[r][$0] != .empty }
            guard hasBlock else { continue }
            let dir   = Bool.random() ? 1 : -1
            let steps = Int.random(in: 1...7)
            let delta = dir * steps
            let oldRow = grid[r]
            var newRow = [BlockType](repeating: .empty, count: cols)
            for c in 0..<cols {
                let newC = ((c + delta) % cols + cols) % cols
                newRow[newC] = oldRow[c]
            }
            grid[r] = newRow
        }
    }

        // MARK: Compaction helper Magix

    /// Compacte la grille (gravité vers le haut), anime les blocs, puis appelle `finishChainWaveAfterPhysicalPhase()`.
    /// Utilisé après les effets BRIXED (les Brix disparaissent mais ne forment pas une chaîne ordinaire).
    private func applyMagixCompactionAndContinue(columnHadBlockBefore: [Bool]) {
        let riseMoves = computeCompactRiseMovesReadingCurrentGrid()
        compactGridTowardTop()

        guard let container = childNode(withName: Self.gridContainerName) else {
            drawGrid()
            awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
            finishChainWaveAfterPhysicalPhase()
            return
        }

        if riseMoves.isEmpty {
            drawGrid()
            awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
            finishChainWaveAfterPhysicalPhase()
            return
        }

        let movingSourceCells = Set(riseMoves.map { GridAddress(row: $0.fromRow, col: $0.column) })
        removeBloxJunctionElementsTouching(movingSourceCells)

        for move in riseMoves {
            let nodeName = "cell_\(move.fromRow)_\(move.column)"
            guard let sprite = container.childNode(withName: nodeName) as? SKSpriteNode else { continue }
            let targetLocal = Self.gridContainerLocalCellCenter(row: move.toRow, column: move.column)
            let moveAction = SKAction.move(to: targetLocal, duration: CompactRiseAnimation.duration)
            moveAction.timingMode = .easeOut
            sprite.run(moveAction)
        }

        run(SKAction.sequence([
            SKAction.wait(forDuration: CompactRiseAnimation.duration),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.drawGrid()
                self.awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
                self.finishChainWaveAfterPhysicalPhase()
            },
        ]))
    }

        // MARK: - Bombes (`priks.html`)

    /// Icône + compteur **sous** la zone d’aperçu des lignes (à droite) ; file des 2 prochains blocs à sa gauche.
    private func setupBombHUD() {
        childNode(withName: Self.bombHudIconName)?.removeFromParent()
        childNode(withName: Self.bombHudCountLabelName)?.removeFromParent()
        childNode(withName: Self.upcomingSlotTwoAheadName)?.removeFromParent()
        childNode(withName: Self.upcomingSlotNextName)?.removeFromParent()
        childNode(withName: Self.upcomingQueueCaptionLabelName)?.removeFromParent()
        childNode(withName: Self.evalDebugLabelName)?.removeFromParent()

        let iconSize = CGSize(width: 36, height: 36)
        let icon = Self.makeBombShaderSprite(size: iconSize)
        icon.name = Self.bombHudIconName
        icon.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        icon.zPosition = 12

        let label = SKLabelNode(text: "1")
        label.name = Self.bombHudCountLabelName
        label.fontName = Self.customUIFontPostScriptName
        label.fontSize = 21
        label.fontColor = .white
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .center
        label.zPosition = 12

        addChild(icon)
        addChild(label)

        let cell = UpcomingQueueLayout.cellPoints
        let leftCell = cell * UpcomingQueueLayout.leftSlotCellFactor
        let slotTwo = SKSpriteNode()
        slotTwo.name = Self.upcomingSlotTwoAheadName
        slotTwo.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        slotTwo.zPosition = 12
        slotTwo.size = CGSize(width: leftCell, height: leftCell)
        addChild(slotTwo)

        let slotNext = SKSpriteNode()
        slotNext.name = Self.upcomingSlotNextName
        slotNext.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        slotNext.zPosition = 12
        slotNext.size = CGSize(width: cell, height: cell)
        addChild(slotNext)

        let caption = SKLabelNode(text: BlomixL10n.hudNextBlox)
        caption.name = Self.upcomingQueueCaptionLabelName
        caption.fontName = Self.customUIFontPostScriptName
        caption.fontSize = 11
        caption.fontColor = .white
        caption.horizontalAlignmentMode = .center
        caption.verticalAlignmentMode = .center
        caption.zPosition = 12
        addChild(caption)

        // Label de debug eval désactivé (affichage masqué, fonction toujours active).

        layoutBombHUD()
        refreshUpcomingQueueSlots()
        updateBombHUD()
    }

    private func refreshUpcomingQueueSlots() {
        guard let slotTwo = childNode(withName: Self.upcomingSlotTwoAheadName) as? SKSpriteNode,
              let slotNext = childNode(withName: Self.upcomingSlotNextName) as? SKSpriteNode else { return }
        let cell = UpcomingQueueLayout.cellPoints
        let leftCell = cell * UpcomingQueueLayout.leftSlotCellFactor
        let displayedNext: BlockType
        let displayedTwoAhead: BlockType
        if isBombMode {
            // Visuellement, la bombe s'intercale avant `currentBlock` sans changer la file réelle.
            // bombCount peut être 0 : la bombe est "dans la main" (stock décrémmenté à l'activation).
            displayedNext = currentBlock
            displayedTwoAhead = blockAfterCurrent
        } else {
            displayedNext = blockAfterCurrent
            displayedTwoAhead = blockTwoAhead
        }
        Self.applyBlockTypeToQueueSprite(sprite: slotTwo, block: displayedTwoAhead, slotCellPoints: leftCell)
        Self.applyBlockTypeToQueueSprite(sprite: slotNext, block: displayedNext, slotCellPoints: cell)
    }

    /// Miniature couleur / Priks pour la file sous la grille (`slotCellPoints` = côté du cadre ; gauche = moitié du droit).
    private static func applyBlockTypeToQueueSprite(sprite: SKSpriteNode, block: BlockType, slotCellPoints: CGFloat) {
        let inner = max(4, slotCellPoints - 2)
        let innerSize = CGSize(width: inner, height: inner)
        let priksDigitRef: CGFloat = 16
        let priksFont = max(6, priksDigitRef * (slotCellPoints / UpcomingQueueLayout.cellPoints))
        // Nettoyer les anciens enfants (Priks digit + biseau) — le sprite est réutilisé entre les appels.
        sprite.childNode(withName: Self.queueSlotPriksDigitName)?.removeFromParent()
        // Supprimer le shader, le halo et les particules Magix si le slot change de type.
        sprite.shader = nil
        sprite.removeAction(forKey: MagixRules.orbitParticlesActionKey)
        sprite.childNode(withName: MagixRules.glowNodeName)?.removeFromParent()
        sprite.colorBlendFactor = 0
        sprite.color = .white
        switch block {
        case .color(let colorName):
            sprite.texture = nil
            sprite.color = Self.bloxSolidFillColor(colorName: colorName) ?? SKColor(white: 0.45, alpha: 1)
            sprite.colorBlendFactor = 1
            sprite.size = innerSize
        case .priks(let value):
            sprite.texture = nil
            sprite.color = Self.priksSolidFillColor()
            sprite.colorBlendFactor = 1
            sprite.size = innerSize
            let digit = SKLabelNode(text: "\(value)")
            digit.name = Self.queueSlotPriksDigitName
            digit.fontName = Self.customUIFontPostScriptName
            digit.fontSize = priksFont
            digit.fontColor = Self.priksDigitLabelColor()
            digit.horizontalAlignmentMode = .center
            digit.verticalAlignmentMode = .center
            digit.position = .zero
            digit.zPosition = 2
            sprite.addChild(digit)
        case .magix(let kind):
            // Shader dégradé mouvant — piloté par u_time ; symbole centré via queueSlotPriksDigitName
            // (nettoyé automatiquement par le bloc de cleanup en tête de fonction).
            applyMagixShader(to: sprite, size: innerSize, kind: kind,
                             symbolLabelName: Self.queueSlotPriksDigitName)
        case .empty:
            sprite.texture = nil
            sprite.color = SKColor(white: 0.12, alpha: 1)
            sprite.colorBlendFactor = 1
            sprite.size = CGSize(width: slotCellPoints, height: slotCellPoints)
        }
    }

    private func layoutBombHUD() {
        guard let icon = childNode(withName: Self.bombHudIconName) as? SKSpriteNode,
              let label = childNode(withName: Self.bombHudCountLabelName) as? SKLabelNode,
              let slotTwo = childNode(withName: Self.upcomingSlotTwoAheadName) as? SKSpriteNode,
              let slotNext = childNode(withName: Self.upcomingSlotNextName) as? SKSpriteNode,
              let caption = childNode(withName: Self.upcomingQueueCaptionLabelName) as? SKLabelNode else { return }

        let bandY = sceneYCenterForBombAndUpcomingBand()
        /// Remonte la file « next blox » + minis d’un demi-case (sans bouger l’icône bombe).
        let queueBandLift = GridLayout.cellPoints / 2
        let half = GridLayout.spanPoints / 2
        let gridRight = gridAreaCenter.x + half
        let gapCount: CGFloat = 8
        let cell = UpcomingQueueLayout.cellPoints
        let slotGap = UpcomingQueueLayout.gapBetweenSlots
        let previewSize = GridLayout.cellPoints - 4
        let previewCenterX = size.width / 2
        let miniVisualSize = max(4, cell - 2)
        let leftSlotCell = cell * UpcomingQueueLayout.leftSlotCellFactor
        let miniLeftVisualSize = max(4, leftSlotCell - 2)

        // [slotTwo][gap][slotNext] puis gros preview : bord droit du slot « next » aligné sur le bord droit du gros.
        let nextCenterX = previewCenterX + previewSize / 2 - miniVisualSize / 2
        let twoAheadCenterX = nextCenterX - miniVisualSize - slotGap

        let queueY = bandY + queueBandLift
        // Même abscisse qu’avant ; ordonnée : bas des deux minis alignés (le gauche est plus petit).
        let queueYLeft = queueY + (miniLeftVisualSize - miniVisualSize) / 2
        slotTwo.position = CGPoint(x: twoAheadCenterX, y: queueYLeft)
        slotNext.position = CGPoint(x: nextCenterX, y: queueY)

        let captionMidX = (twoAheadCenterX + nextCenterX) / 2
        let captionCenterY = queueY - cell / 2 - UpcomingQueueLayout.captionGapBelowSlots - 4
        caption.position = CGPoint(x: captionMidX, y: captionCenterY)

        icon.position = CGPoint(x: gridRight - icon.size.width / 2, y: bandY)
        label.position = CGPoint(
            x: icon.position.x - icon.size.width / 2 - gapCount,
            y: bandY
        )

        // Debug eval label — sous l'icône bombe, aligné à droite sur le bord de la grille.
        if let evalLbl = childNode(withName: Self.evalDebugLabelName) as? SKLabelNode {
            evalLbl.position = CGPoint(x: gridRight, y: bandY - icon.size.height / 2 - 10)
        }
    }

    /// Met à jour le chiffre ; désactive le mode bombe si plus de munitions.
    private func updateBombHUD() {
        // bombCount peut être 0 quand une bombe est "sortie" (isBombMode = true) — ne pas annuler dans ce cas.
        // On annule seulement si le stock est négatif (incohérence) ou si on n'est pas en mode bombe.
        if bombCount < 0 {
            bombCount = 0
            isBombMode = false
        }
        (childNode(withName: Self.bombHudCountLabelName) as? SKLabelNode)?.text = "\(bombCount)"
        (childNode(withName: Self.bombHudIconName) as? SKSpriteNode)?.alpha = (bombCount > 0 || isBombMode) ? 1.0 : 0.4
        refreshUpcomingQueueSlots()
    }

    private func toggleBombMode() {
        guard !isStartScreen else { return }
        // En tutoriel, la bombe est bloquée jusqu'à l'étape bombIntro.
        if isTutorialMode && !tutorialBombUnlocked { return }
        if isBombMode {
            // Annulation : on restitue la bombe dans le stock (et on cache l'overlay visée si actif).
            cancelBombAim()
            isBombMode = false
            bombCount += 1
            updateBombHUD()
        } else {
            guard bombCount > 0 else { return }
            // Activation : la bombe sort du stock immédiatement
            playMatchSound(.bombLoad)
            isBombMode = true
            bombCount -= 1
            updateBombHUD()
        }
        updatePreviewSprite()
        refreshUpcomingQueueSlots()
        updateHintButton()
    }

    private func touchHitsBombHUD(_ locationInScene: CGPoint) -> Bool {
        var union = CGRect.null
        for name in [Self.bombHudIconName, Self.bombHudCountLabelName] {
            guard let node = childNode(withName: name) else { continue }
            union = union.union(node.calculateAccumulatedFrame())
        }
        return union.contains(locationInScene)
    }

    /// Vide les **9** cases du carré 3×3 centré sur `(centerRow, centerCol)` (Priks inclus).
    // MARK: - Bomb / Nuke blast area

    /// Longueur des bras de la croix au-delà du carré 3×3.
    /// Solo stage 1 → 0 (bombe standard), stage 2 → 1, stage 3 → 2 … stage 6 → 5.
    /// PvP / tutoriel → toujours 0.
    private var bombCrossArmLength: Int {
        isInStagedSoloMode ? currentStageIndex : 0
    }

    /// Nom de la texture à utiliser pour l'icône et les sprites bombe.
    private var currentBombImageName: String {
        bombCrossArmLength > 0 ? "WebImages/nuke" : "WebImages/bomb"
    }

    /// Toutes les cases de la zone d'explosion pour le stage courant (carré 3×3 + bras de croix).
    /// Les cases hors grille sont silencieusement ignorées.
    private func bombAffectedCells(centerRow: Int, centerCol: Int) -> [GridAddress] {
        var result: [GridAddress] = []
        // Cœur 3×3
        for dr in -1...1 {
            for dc in -1...1 {
                let r = centerRow + dr; let c = centerCol + dc
                guard r >= GridLayout.topRowIndex, r < GridLayout.rowCount,
                      c >= 0, c < GridLayout.columnCount else { continue }
                result.append(GridAddress(row: r, col: c))
            }
        }
        // Bras de croix : cases aux distances 2 … 1+armLength dans les 4 directions cardinales
        let arm = bombCrossArmLength
        guard arm > 0 else { return result }
        let cardinals = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for (dr, dc) in cardinals {
            for step in 2...(1 + arm) {
                let r = centerRow + dr * step; let c = centerCol + dc * step
                guard r >= GridLayout.topRowIndex, r < GridLayout.rowCount,
                      c >= 0, c < GridLayout.columnCount else { break }
                result.append(GridAddress(row: r, col: c))
            }
        }
        return result
    }

    private func applyBombExplosion3x3(centerRow: Int, centerCol: Int) {
        for addr in bombAffectedCells(centerRow: centerRow, centerCol: centerCol) {
            grid[addr.row][addr.col] = .empty
        }
    }

    /// Cases de la zone d'explosion **dans la grille** (indices valides).
    private func bombBlastGridAddresses(centerRow: Int, centerCol: Int) -> [GridAddress] {
        bombAffectedCells(centerRow: centerRow, centerCol: centerCol)
    }

    /// Cases **occupées** dans la zone d'explosion, triées par distance au centre (les plus proches en premier → stagger plus court).
    private func bombOccupiedCellsInBlastSortedByDistance(centerRow: Int, centerCol: Int) -> [GridAddress] {
        let items: [(GridAddress, Int)] = bombAffectedCells(centerRow: centerRow, centerCol: centerCol)
            .compactMap { addr -> (GridAddress, Int)? in
                guard grid[addr.row][addr.col] != .empty else { return nil }
                let dr = addr.row - centerRow; let dc = addr.col - centerCol
                return (addr, dr * dr + dc * dc)
            }
        return items.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.0.row != b.0.row { return a.0.row < b.0.row }
            return a.0.col < b.0.col
        }.map(\.0)
    }

    /// Ajoute un label numérique (bras de croix) sur un sprite nuke si le stage est ≥ 2.
    /// Supprime d'abord tout digit existant (sprite réutilisable).
    private func attachNukeDigitIfNeeded(to sprite: SKSpriteNode, size: CGSize) {
        sprite.childNode(withName: Self.bombNukeDigitName)?.removeFromParent()
        let arm = bombCrossArmLength
        guard arm > 0 else { return }
        let digit = SKLabelNode(text: "\(arm)")
        digit.name                   = Self.bombNukeDigitName
        digit.fontName               = Self.customUIFontPostScriptName
        digit.fontSize               = max(10, size.width * 0.38)
        digit.fontColor              = .white
        digit.horizontalAlignmentMode = .center
        digit.verticalAlignmentMode   = .center
        digit.position               = .zero
        digit.zPosition              = 2
        sprite.addChild(digit)
    }

    /// Met à jour le shader et le digit de l'icône bombe HUD du bas (appelé au changement de stage ou de palette).
    private func refreshBombHudIcon() {
        guard let icon = childNode(withName: Self.bombHudIconName) as? SKSpriteNode else { return }
        Self.applyBombShader(to: icon, size: icon.size)
        attachNukeDigitIfNeeded(to: icon, size: icon.size)
    }

    /// Couleurs distinctes des blox dans la zone 3×3 (pour gerbes secondaires optionnelles).
    private func distinctBloxFillColorsInBombBlast(centerRow: Int, centerCol: Int, maxColors: Int) -> [SKColor] {
        var seen = Set<String>()
        var colors: [SKColor] = []
        for dr in -1...1 {
            for dc in -1...1 {
                let r = centerRow + dr
                let c = centerCol + dc
                guard r >= GridLayout.topRowIndex, r < GridLayout.rowCount,
                      c >= 0, c < GridLayout.columnCount else { continue }
                switch grid[r][c] {
                case .color(let name):
                    guard seen.insert(name).inserted else { continue }
                    if let col = Self.bloxSolidFillColor(colorName: name) {
                        colors.append(col)
                    }
                case .priks:
                    guard seen.insert("__priks__").inserted else { continue }
                    colors.append(Self.priksSolidFillColor())
                case .magix, .empty:
                    break
                }
                if colors.count >= maxColors { return colors }
            }
        }
        return colors
    }

    /// Crée un nœud annulaire via un CGPath fill (évite le bug strokeColor/Metal de SKShapeNode).
    /// - Parameter color: couleur de remplissage (blanc par défaut, jaune pour les premiers anneaux).
    private func makeShockWaveRing(color: SKColor = SKColor(white: 0.95, alpha: 1)) -> SKShapeNode {
        let outerR = BombExplosionFeedback.shockWaveBaseRadius
        let innerR = outerR - BombExplosionFeedback.shockWaveRingWidth
        let path   = CGMutablePath()
        // Cercle extérieur sens horaire, cercle intérieur sens anti-horaire → even-odd rule creuse l'anneau.
        path.addEllipse(in: CGRect(x: -outerR, y: -outerR, width: outerR * 2, height: outerR * 2))
        path.addEllipse(in: CGRect(x: -innerR, y: -innerR, width: innerR * 2, height: innerR * 2))
        let node = SKShapeNode(path: path, centered: false)
        node.fillColor   = color
        node.strokeColor = .clear
        node.lineWidth   = 0
        return node
    }

    /// Train de 5 anneaux concentriques échelonnés (2 jaunis + 3 blancs).
    /// Tous les rings sont ajoutés immédiatement (alpha=0) ; chacun attend son délai via SKAction
    /// puis apparaît instantanément (fadeAlpha duration:0) et lance grow+fade.
    private func addBombShockWave(at scenePoint: CGPoint) {
        let count   = BombExplosionFeedback.shockWaveCount
        let stagger = BombExplosionFeedback.shockWaveStagger
        // Les 2 premiers anneaux utilisent le jaune du set du joueur pour un effet de chaleur à l'épicentre.
        let yellow  = Self.bloxSolidFillColor(colorName: "yellow") ?? SKColor(red: 0.91, green: 0.77, blue: 0.42, alpha: 1)
        let white   = SKColor(white: 0.95, alpha: 1)
        for i in 0..<count {
            let delay = TimeInterval(i) * stagger
            let ringColor = i < 2 ? yellow : white
            let ring  = makeShockWaveRing(color: ringColor)
            ring.position  = scenePoint
            ring.zPosition = BombExplosionFeedback.shockWaveZ
            ring.alpha     = 0          // invisible jusqu'à son tour
            ring.name      = "bombShockWave"
            addChild(ring)

            let appear = SKAction.fadeAlpha(to: BombExplosionFeedback.shockWaveStartAlpha, duration: 0)
            let grow   = SKAction.scale(to: BombExplosionFeedback.shockWaveEndScale,
                                        duration: BombExplosionFeedback.shockWaveDuration)
            grow.timingMode = .easeOut
            let fade   = SKAction.fadeAlpha(to: 0, duration: BombExplosionFeedback.shockWaveDuration)
            ring.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                appear,
                SKAction.group([grow, fade]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    /// Gerbe courte blanche + petites rafales teintées (sans texture).
    private func addBombExplosionEmitters(at scenePoint: CGPoint, centerRow: Int, centerCol: Int) {
        let holder = SKNode()
        holder.name = "bombExplosionEmitterHolder"
        holder.position = scenePoint
        holder.zPosition = BombExplosionFeedback.emitterZ
        addChild(holder)

        let spark = SKEmitterNode()
        spark.particleBirthRate = 420
        spark.numParticlesToEmit = 72
        spark.particleLifetime = 0.32
        spark.particleLifetimeRange = 0.12
        spark.particleSpeed = 100
        spark.particleSpeedRange = 60
        spark.emissionAngle = 0
        spark.emissionAngleRange = .pi * 2
        spark.particleAlpha = 0.95
        spark.particleAlphaSpeed = -4
        spark.particleScale = 0.07
        spark.particleScaleRange = 0.035
        spark.particleColor = SKColor(white: 0.96, alpha: 1)
        spark.particleBlendMode = .add
        spark.position = .zero
        spark.zPosition = 1
        holder.addChild(spark)

        var zDebris: CGFloat = 0.5
        for fill in distinctBloxFillColorsInBombBlast(centerRow: centerRow, centerCol: centerCol, maxColors: 3) {
            let e = SKEmitterNode()
            e.particleBirthRate = 280
            e.numParticlesToEmit = 16
            e.particleLifetime = 0.28
            e.particleLifetimeRange = 0.08
            e.particleSpeed = 72
            e.particleSpeedRange = 36
            e.emissionAngle = 0
            e.emissionAngleRange = .pi * 2
            e.particleAlpha = 0.85
            e.particleAlphaSpeed = -4.5
            e.particleScale = 0.055
            e.particleScaleRange = 0.02
            e.particleColor = fill
            e.particleBlendMode = .alpha
            e.position = .zero
            e.zPosition = zDebris
            zDebris -= 0.01
            holder.addChild(e)
        }

        run(
            SKAction.sequence([
                SKAction.wait(forDuration: BombExplosionFeedback.emitterLifetime),
                SKAction.run { [weak holder] in
                    holder?.removeFromParent()
                },
            ])
        )
    }

    /// Animation d’explosion : onde + (option) emitters + blox 3×3 ; la grille **n’est pas** modifiée avant `completion`.
    private func animateBombExplosionAtLanding(
        centerScenePoint: CGPoint,
        centerRow: Int,
        centerCol: Int,
        spawnEmitter: Bool,
        completion: @escaping () -> Void
    ) {
        playMatchSound(.bomb)
        shakeScreen(intensity: 2.5)
        hapticHeavy()

        guard let container = childNode(withName: Self.gridContainerName) as? SKNode else {
            completion()
            return
        }

        // Flash central : disque plein qui apparaît instantanément puis se réduit et s'efface.
        let flash = SKShapeNode(circleOfRadius: BombExplosionFeedback.flashRadius)
        flash.fillColor   = SKColor(white: 1.0, alpha: 0.9)
        flash.strokeColor = .clear
        flash.position    = centerScenePoint
        flash.zPosition   = BombExplosionFeedback.flashZ
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 0.1, duration: BombExplosionFeedback.flashDuration),
                SKAction.fadeAlpha(to: 0, duration: BombExplosionFeedback.flashDuration),
            ]),
            SKAction.removeFromParent(),
        ]))

        addBombShockWave(at: centerScenePoint)
        if spawnEmitter {
            addBombExplosionEmitters(at: centerScenePoint, centerRow: centerRow, centerCol: centerCol)
        }

        let blastCells = Set(bombBlastGridAddresses(centerRow: centerRow, centerCol: centerCol))
        removeBloxJunctionElementsTouching(blastCells)

        let bombLocal = convert(centerScenePoint, to: container)
        let occupiedSorted = bombOccupiedCellsInBlastSortedByDistance(centerRow: centerRow, centerCol: centerCol)

        let stagger = BombExplosionFeedback.blockStaggerPerStep
        let cellDur = BombExplosionFeedback.blockPerCellAnimationDuration
        let zBoost = BombExplosionFeedback.blockAnimZ

        for (index, address) in occupiedSorted.enumerated() {
            let name = "cell_\(address.row)_\(address.col)"
            guard let sprite = container.childNode(withName: name) as? SKSpriteNode else { continue }

            let cellLocal = Self.gridContainerLocalCellCenter(row: address.row, column: address.col)
            var vx = cellLocal.x - bombLocal.x
            var vy = cellLocal.y - bombLocal.y
            let len = hypot(vx, vy)
            if len < 0.001 {
                vx = 0
                vy = 1
            } else {
                vx /= len
                vy /= len
            }
            let push = CGFloat.random(in: BombExplosionFeedback.radialPushDistanceMin...BombExplosionFeedback.radialPushDistanceMax)
            let dx = vx * push
            let dy = vy * push

            let baseScale = sprite.xScale
            let rotDegrees = CGFloat.random(in: BombExplosionFeedback.rotationDegreesRange)
            let rotSign: CGFloat = Bool.random() ? 1 : -1
            let deltaAngle = rotSign * rotDegrees * (.pi / 180)

            let wait = SKAction.wait(forDuration: Double(index) * stagger)
            let slotSize = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
            let prep = SKAction.run {
                sprite.zPosition = zBoost
                // Placeholder gris derrière le blox animé : évite le fond noir pendant le fondu.
                let bg = SKSpriteNode(color: SKColor(white: 0.12, alpha: 1), size: slotSize)
                bg.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                bg.position    = sprite.position
                bg.zPosition   = 0
                bg.name        = "cell_bomb_bg_\(address.row)_\(address.col)"
                container.addChild(bg)
            }

            let pushAct = SKAction.moveBy(x: dx, y: dy, duration: BombExplosionFeedback.radialPushDuration)
            pushAct.timingMode = .easeOut
            let scaleUp = SKAction.scale(to: baseScale * 1.25, duration: BombExplosionFeedback.blockScaleUpDuration)
            scaleUp.timingMode = .easeOut
            let rot = SKAction.rotate(byAngle: deltaAngle, duration: BombExplosionFeedback.blockRotateDuration)
            rot.timingMode = .easeInEaseOut

            let phase1 = SKAction.group([pushAct, scaleUp, rot])

            let collapse = SKAction.scale(to: 0.01, duration: BombExplosionFeedback.blockCollapseDuration)
            collapse.timingMode = .easeIn
            let fade = SKAction.fadeAlpha(to: 0, duration: BombExplosionFeedback.blockCollapseDuration)
            let phase2 = SKAction.group([collapse, fade])

            sprite.run(SKAction.sequence([wait, prep, phase1, phase2]))
        }

        let blockTail = Double(max(occupiedSorted.count - 1, 0)) * stagger + cellDur
        let totalWait = max(BombExplosionFeedback.shockWaveTrainDuration, blockTail)

        run(SKAction.sequence([SKAction.wait(forDuration: totalWait), SKAction.run(completion)]))
    }

    /// Bombe : placement direct sur la case touchée, tremblements 0.3 s, puis explosion 3×3.
    private func placeBombAtCell(row: Int, col: Int) {
        guard !isStartScreen, !isGameOver, !isProcessing else { return }
        // bombCount peut être 0 : la bombe est déjà "sortie" du stock à l'activation.
        guard bombCount >= 0 else {
            isBombMode = false
            updatePreviewSprite()
            return
        }

        isProcessing = true
        childNode(withName: Self.fallingSpriteName)?.removeFromParent()
        childNode(withName: Self.previewNodeName)?.isHidden = true

        let cellCenter = scenePointCellCenter(row: row, column: col)

        let bombSpriteSize = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
        let bombSprite = Self.makeBombShaderSprite(size: bombSpriteSize)
        bombSprite.name       = Self.fallingSpriteName
        bombSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        bombSprite.position   = cellCenter
        bombSprite.zPosition  = 22
        attachNukeDigitIfNeeded(to: bombSprite, size: bombSpriteSize)
        addChild(bombSprite)

        // Tremblement marqué sur 0.3 s (6 demi-oscillations de ±6 pts, 0.05 s chacune)
        let dx: CGFloat = 6
        let dt: TimeInterval = 0.05
        let shake = SKAction.sequence([
            SKAction.moveBy(x: -dx, y: 0, duration: dt),
            SKAction.moveBy(x:  dx * 2, y: 0, duration: dt),
            SKAction.moveBy(x: -dx * 2, y: 0, duration: dt),
            SKAction.moveBy(x:  dx * 2, y: 0, duration: dt),
            SKAction.moveBy(x: -dx * 2, y: 0, duration: dt),
            SKAction.moveBy(x:  dx,     y: 0, duration: dt),
        ])

        let columnHadBlockBefore: [Bool] = (0..<GridLayout.columnCount).map { c in
            (GridLayout.topRowIndex..<GridLayout.rowCount).contains { self.grid[$0][c] != .empty }
        }

        let explode = SKAction.run { [weak self] in
            guard let self else { return }
            bombSprite.removeFromParent()
            self.spawnBombExplosionParticles(at: cellCenter)
            self.animateBombExplosionAtLanding(
                centerScenePoint: cellCenter,
                centerRow: row,
                centerCol: col,
                spawnEmitter: false
            ) { [weak self] in
                guard let self else { return }
                // Capture les Brix dans la zone avant effacement (applyBombExplosion3x3 met tout à .empty).
                let blastCells   = self.bombAffectedCells(centerRow: row, centerCol: col)
                let priksInBlast = Set(blastCells.filter { if case .priks = self.grid[$0.row][$0.col] { return true }; return false })
                self.applyBombExplosion3x3(centerRow: row, centerCol: col)
                self.addScore(points: 10, chainMultiplier: 0, floatAt: cellCenter)
                if !priksInBlast.isEmpty {
                    let priksCenter = self.sceneCentroid(for: priksInBlast)
                    self.addScore(points: priksInBlast.count * 20, chainMultiplier: 0, floatAt: priksCenter)
                }
                self.isBombMode = false
                self.updateBombHUD()
                if self.isTutorialMode { self.tutorialBombDropped() }

                self.drawGrid()
                let riseMoves = self.computeCompactRiseMovesReadingCurrentGrid()
                self.compactGridTowardTop()

                let finish: () -> Void = { [weak self] in
                    guard let self else { return }
                    self.drawGrid()
                    self.awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
                    self.childNode(withName: Self.previewNodeName)?.isHidden = false
                    self.updatePreviewSprite()
                    // Les chaînes qui suivent une explosion de bombe démarrent au niveau 1 (cascade),
                    // de sorte que les cascades éventuelles soient comptées niveau 2, 3, etc.
                    self.chainSeriesLevel = 1
                    self.resolveChains()
                }

                guard !riseMoves.isEmpty,
                      let container = self.childNode(withName: Self.gridContainerName) else {
                    finish()
                    return
                }

                let movingSourceCells = Set(riseMoves.map { GridAddress(row: $0.fromRow, col: $0.column) })
                self.removeBloxJunctionElementsTouching(movingSourceCells)
                for move in riseMoves {
                    guard move.column >= 0, move.column < GridLayout.columnCount,
                          move.fromRow >= GridLayout.topRowIndex, move.fromRow < GridLayout.rowCount,
                          move.toRow   >= GridLayout.topRowIndex, move.toRow   < GridLayout.rowCount else { continue }
                    let nodeName = "cell_\(move.fromRow)_\(move.column)"
                    guard let sprite = container.childNode(withName: nodeName) as? SKSpriteNode else { continue }
                    let targetLocal = Self.gridContainerLocalCellCenter(row: move.toRow, column: move.column)
                    let moveAction  = SKAction.move(to: targetLocal, duration: CompactRiseAnimation.duration)
                    moveAction.timingMode = .easeOut
                    sprite.run(moveAction)
                }
                self.run(SKAction.sequence([
                    SKAction.wait(forDuration: CompactRiseAnimation.duration),
                    SKAction.run(finish),
                ]))
            }
        }

        bombSprite.run(SKAction.sequence([shake, explode]))
    }

    /// Bombe (PvP / fallback colonne) : montée depuis la file, impact sur la première case occupée.
    private func dropBomb(usingColumn column: Int? = nil) {
        guard !isStartScreen, !isGameOver, !isProcessing else { return }
        guard bombCount >= 0 else {
            isBombMode = false
            updatePreviewSprite()
            return
        }

        let columnIndex: Int = {
            guard let c = column else { return selectedColumn }
            return min(max(c, 0), GridLayout.columnCount - 1)
        }()

        // Symétrie avec `dropBlock` : ici `checkGameOver` retourne toujours `false` (mode bombe).
        if checkGameOver(forNormalDropInColumn: columnIndex) {
            triggerGameOver()
            return
        }

        let landingRow: Int = {
            if let occupied = lowestOccupiedRow(inColumn: columnIndex) {
                return occupied
            }
            return GridLayout.topRowIndex
        }()

        isProcessing = true
        childNode(withName: Self.fallingSpriteName)?.removeFromParent()

        if let preview = childNode(withName: Self.previewNodeName) {
            preview.isHidden = true
        }

        let start = scenePointPreviewRow(column: columnIndex)
        let launchStart = scenePointLaunchStartBelowGrid(column: columnIndex)
        let end = scenePointCellCenter(row: landingRow, column: columnIndex)

        let bombDropSize = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
        let falling = Self.makeBombShaderSprite(size: bombDropSize)
        falling.name = Self.fallingSpriteName
        falling.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        falling.position = start
        falling.xScale = FlightStretch.xScale
        falling.yScale = FlightStretch.yScale
        falling.zPosition = 20
        addChild(falling)

        let snapToColumn = SKAction.move(to: launchStart, duration: 0.0)

        let rise = SKAction.move(to: end, duration: 0.4)
        rise.timingMode = .easeOut

        let unstretchX = SKAction.scaleX(to: 1.0, duration: 0.4)
        unstretchX.timingMode = .easeIn
        let unstretchY = SKAction.scaleY(to: 1.0, duration: 0.4)
        unstretchY.timingMode = .easeIn

        // Traîne dorée pour la bombe.
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.001),
            makeTrailSpawnAction(riseDuration: 0.4,
                                 color: SKColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 1),
                                 trackedSprite: falling),
        ]))

        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            falling.removeFromParent()
            let columnHadBlockBefore: [Bool] = (0..<GridLayout.columnCount).map { col in
                (GridLayout.topRowIndex..<GridLayout.rowCount).contains { self.grid[$0][col] != .empty }
            }
            let bombFloatAt = self.scenePointCellCenter(row: landingRow, column: columnIndex)
            // `spawnEmitter: true` → gerbes `SKEmitterNode` (un peu plus coûteux).
            self.animateBombExplosionAtLanding(
                centerScenePoint: bombFloatAt,
                centerRow: landingRow,
                centerCol: columnIndex,
                spawnEmitter: false
            ) { [weak self] in
                guard let self else { return }
                // Capture les Brix dans la zone avant effacement.
                let blastCells   = self.bombAffectedCells(centerRow: landingRow, centerCol: columnIndex)
                let priksInBlast = Set(blastCells.filter { if case .priks = self.grid[$0.row][$0.col] { return true }; return false })
                self.applyBombExplosion3x3(centerRow: landingRow, centerCol: columnIndex)

                // Non-visual updates first (order-independent of animation)
                self.addScore(points: 10, chainMultiplier: 0, floatAt: bombFloatAt)
                if !priksInBlast.isEmpty {
                    let priksCenter = self.sceneCentroid(for: priksInBlast)
                    self.addScore(points: priksInBlast.count * 20, chainMultiplier: 0, floatAt: priksCenter)
                }
                self.isBombMode = false
                self.updateBombHUD()
                if self.isTutorialMode { self.tutorialBombDropped() }

                // Draw grid with holes so existing sprites sit at pre-compact positions,
                // then compute which blocks need to animate upward, then mutate the model.
                self.drawGrid()
                let riseMoves = self.computeCompactRiseMovesReadingCurrentGrid()
                self.compactGridTowardTop()

                let finishBombDrop: () -> Void = { [weak self] in
                    guard let self else { return }
                    self.drawGrid()
                    self.awardFullyClearedColumnBonuses(columnHadBlockBefore: columnHadBlockBefore)
                    if let preview = self.childNode(withName: Self.previewNodeName) {
                        preview.isHidden = false
                    }
                    self.updatePreviewSprite()
                    // Idem placeBombAtCell : la première chaîne après la bombe = niveau 1.
                    self.chainSeriesLevel = 1
                    self.resolveChains()
                }

                guard !riseMoves.isEmpty,
                      let container = self.childNode(withName: Self.gridContainerName) else {
                    finishBombDrop()
                    return
                }

                let movingSourceCells = Set(riseMoves.map { GridAddress(row: $0.fromRow, col: $0.column) })
                self.removeBloxJunctionElementsTouching(movingSourceCells)

                for move in riseMoves {
                    guard move.column >= 0, move.column < GridLayout.columnCount,
                          move.fromRow >= GridLayout.topRowIndex, move.fromRow < GridLayout.rowCount,
                          move.toRow >= GridLayout.topRowIndex, move.toRow < GridLayout.rowCount else { continue }
                    let nodeName = "cell_\(move.fromRow)_\(move.column)"
                    guard let sprite = container.childNode(withName: nodeName) as? SKSpriteNode else { continue }
                    let targetLocal = Self.gridContainerLocalCellCenter(row: move.toRow, column: move.column)
                    let moveAction = SKAction.move(to: targetLocal, duration: CompactRiseAnimation.duration)
                    moveAction.timingMode = .easeOut
                    sprite.run(moveAction)
                }

                self.run(SKAction.sequence([
                    SKAction.wait(forDuration: CompactRiseAnimation.duration),
                    SKAction.run(finishBombDrop),
                ]))
            }
        }

        falling.run(SKAction.sequence([snapToColumn, SKAction.group([rise, unstretchX, unstretchY]), finish]))
    }

    /// Sprite de la pièce qui **monte** (couleur classique ou Priks + étiquette chiffre).
    private func makeFallingBlockNode(for block: BlockType) -> SKSpriteNode {
        switch block {
        case .color:
            let s = Self.makeSolidGameplayBlockSprite(block: block)
            return s
        case .priks(let value):
            return Self.makeSolidGameplayBlockSprite(block: .priks(value), priksDigitFontSize: 20)
        case .magix(let kind):
            let size = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
            return Self.makeMagixShaderSprite(size: size, kind: kind)
        case .empty:
            return SKSpriteNode(color: .clear, size: CGSize(width: 1, height: 1))
        }
    }

    /// Case (row, col) sous le point `scene` si le tap est dans la zone jouable ; sinon `nil`.
    private func gridCellAtScenePoint(_ point: CGPoint) -> (row: Int, col: Int)? {
        let half = GridLayout.spanPoints / 2
        let c = gridAreaCenter
        let left   = c.x - half
        let right  = c.x + half
        let bottom = c.y - half
        let top    = c.y + half
        guard point.x >= left, point.x <= right, point.y >= bottom, point.y <= top else { return nil }
        let col = Int(floor((point.x - left)  / GridLayout.cellPoints))
        let row = Int(floor((top   - point.y) / GridLayout.cellPoints))
        guard col >= 0, col < GridLayout.columnCount,
              row >= GridLayout.topRowIndex, row < GridLayout.rowCount else { return nil }
        return (row: row, col: col)
    }

    /// Colonne sous le point `scene` si le tap est dans la zone **jouable** de la grille ; sinon `nil`.
    private func columnAtScenePoint(_ point: CGPoint) -> Int? {
        let half = GridLayout.spanPoints / 2
        let c = gridAreaCenter
        let left = c.x - half
        let right = c.x + half
        let bottom = c.y - half
        let top = c.y + half
        guard point.x >= left, point.x <= right, point.y >= bottom, point.y <= top else { return nil }
        let col = Int(floor((point.x - left) / GridLayout.cellPoints))
        guard col >= 0, col < GridLayout.columnCount else { return nil }
        return col
    }

    /// Comme `columnAtScenePoint` mais étend la zone vers le bas jusqu'au bas du bloc en attente de lancer.
    /// Utilisé pour le ghost drop : le joueur peut commencer (ou glisser) son geste dans la zone de lancement.
    private func columnAtScenePointOrLaunchZone(_ point: CGPoint) -> Int? {
        let half = GridLayout.spanPoints / 2
        let c = gridAreaCenter
        let left  = c.x - half
        let right = c.x + half
        let top   = c.y + half
        // Bas étendu = bas du bloc prévisualisé (y_centre - demi-hauteur - marge d'1 case).
        let extendedBottom = scenePointPreviewRow(column: 0).y - GridLayout.cellPoints
        guard point.x >= left, point.x <= right,
              point.y >= extendedBottom, point.y <= top else { return nil }
        let col = Int(floor((point.x - left) / GridLayout.cellPoints))
        guard col >= 0, col < GridLayout.columnCount else { return nil }
        return col
    }

    /// Flèches + Espace (simulateur avec clavier matériel : I/O → Keyboard → Connecter le clavier).
    func handleKeyboardPressesBegan(_ presses: Set<UIPress>) {
        if isStartScreen {
            for press in presses {
                guard let key = press.key else { continue }
                switch key.keyCode {
                case .keyboardSpacebar, .keyboardReturnOrEnter:
                    beginNewMatchFromStartScreen()
                    return
                default:
                    let ch = key.charactersIgnoringModifiers
                    if ch == " " || ch == "\r" {
                        beginNewMatchFromStartScreen()
                        return
                    }
                    break
                }
            }
            return
        }

        var didRestartFromGameOver = false
        for press in presses {
            guard let key = press.key else { continue }
            let lowered = key.charactersIgnoringModifiers.lowercased()
            if lowered == "r" {
                if isGameOver {
                    returnToStartScreenFromGameOver()
                    didRestartFromGameOver = true
                }
                continue
            }
        }
        if didRestartFromGameOver { return }
        guard !isGameOver, !isProcessing else { return }
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardLeftArrow:
                selectedColumn = max(0, selectedColumn - 1)
                updatePreviewSprite()
            case .keyboardRightArrow:
                selectedColumn = min(GridLayout.columnCount - 1, selectedColumn + 1)
                updatePreviewSprite()
            case .keyboardSpacebar:
                dropBlock()
            case .keyboardB:
                toggleBombMode()
            default:
                if key.charactersIgnoringModifiers.lowercased() == "b" {
                    toggleBombMode()
                }
                break
            }
        }
    }

    /// Aperçu sous la grille : texture du `currentBlock`, centré horizontalement sur `selectedColumn`.
    private func updatePreviewSprite() {
        guard !isStartScreen else { return }
        let preview = childNode(withName: Self.previewNodeName) as? SKSpriteNode ?? {
            let node = SKSpriteNode()
            node.name = Self.previewNodeName
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.zPosition = 4
            addChild(node)
            return node
        }()

        preview.childNode(withName: Self.previewPriksDigitName)?.removeFromParent()
        preview.childNode(withName: Self.bombNukeDigitName)?.removeFromParent()
        preview.colorBlendFactor = 0
        preview.color = .white

        if isBombMode {
            // Nettoyer shader/halo/particules MAGIX éventuels (preview réutilisée).
            preview.shader = nil
            preview.removeAction(forKey: MagixRules.orbitParticlesActionKey)
            preview.childNode(withName: MagixRules.glowNodeName)?.removeFromParent()
            preview.childNode(withName: MagixRules.symbolLabelName)?.removeFromParent()
            let previewBombSize = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
            Self.applyBombShader(to: preview, size: previewBombSize)
            attachNukeDigitIfNeeded(to: preview, size: previewBombSize)
            preview.position = scenePointPreviewRow(column: selectedColumn)
            refreshPendingBottomLinePreview()
            startPreviewBreathing()
            return
        }

        // Supprimer le shader, le halo et les particules Magix si le bloc courant a changé de type.
        preview.shader = nil
        preview.removeAction(forKey: MagixRules.orbitParticlesActionKey)
        preview.childNode(withName: MagixRules.glowNodeName)?.removeFromParent()

        switch currentBlock {
        case .color(let colorName):
            preview.texture = nil
            preview.colorBlendFactor = 1
            preview.color = Self.bloxSolidFillColor(colorName: colorName) ?? SKColor(white: 0.45, alpha: 1)
        case .priks(let value):
            preview.texture = nil
            preview.colorBlendFactor = 1
            preview.color = Self.priksSolidFillColor()
            let digit = SKLabelNode(text: "\(value)")
            digit.name = Self.previewPriksDigitName
            digit.fontName = Self.customUIFontPostScriptName
            digit.fontSize = 19
            digit.fontColor = Self.priksDigitLabelColor()
            digit.horizontalAlignmentMode = .center
            digit.verticalAlignmentMode = .center
            digit.position = .zero
            digit.zPosition = 2
            preview.addChild(digit)
        case .magix(let kind):
            // Shader dégradé mouvant — piloté par u_time ; symbole centré via previewPriksDigitName
            // (nettoyé automatiquement par le bloc de cleanup en tête de fonction).
            Self.applyMagixShader(to: preview,
                                  size: CGSize(width: GridLayout.cellPoints - 4,
                                               height: GridLayout.cellPoints - 4),
                                  kind: kind,
                                  symbolLabelName: Self.previewPriksDigitName)
        case .empty:
            preview.texture = nil
            preview.colorBlendFactor = 1
            preview.color = SKColor(white: 0.2, alpha: 1)
        }

        let previewBlockSize = CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
        preview.size = previewBlockSize
        preview.position = scenePointPreviewRow(column: selectedColumn)

        // Biseau sur le blox courant (pas sur la bombe ni sur .empty).
        if case .empty = currentBlock {} else {
        }

        refreshPendingBottomLinePreview()
        startPreviewBreathing()
    }

    private static let previewBreathKey  = "previewBreath"
    private static let previewJitterKey  = "previewJitter"

    private func startPreviewBreathing() {
        guard let preview = childNode(withName: Self.previewNodeName) as? SKSpriteNode,
              !preview.isHidden else { return }
        preview.removeAction(forKey: Self.previewBreathKey)
        preview.removeAction(forKey: Self.previewJitterKey)
        preview.setScale(1.0)
        preview.position = scenePointPreviewRow(column: selectedColumn) // reset position après éventuel jitter
        let up   = SKAction.scale(to: 1.2, duration: 0.5)
        up.timingMode   = .easeInEaseOut
        let down = SKAction.scale(to: 1.0, duration: 0.5)
        down.timingMode = .easeInEaseOut
        preview.run(SKAction.repeatForever(SKAction.sequence([up, down])),
                    withKey: Self.previewBreathKey)
    }

    /// Tremblement organique du bloc preview quand la ligne entrante est imminente (9e coup sur 10).
    /// Même signature sin/cos que le jitter du strip de prévisualisation en bas.
    private func startPreviewJitter() {
        guard let preview = childNode(withName: Self.previewNodeName) as? SKSpriteNode,
              !preview.isHidden else { return }
        preview.removeAction(forKey: Self.previewBreathKey)
        preview.removeAction(forKey: Self.previewJitterKey)
        preview.setScale(1.0)
        let jitter = SKAction.repeatForever(
            SKAction.customAction(withDuration: PendingLinePreviewFeedback.organicCycleDuration) { [weak self] node, elapsed in
                guard let self else { return }
                let t  = CGFloat(elapsed)
                // Fréquences ~1.7× plus rapides que le strip du bas pour différencier les deux.
                let dx = sin(t * 30.0) * PendingLinePreviewFeedback.jitterAmplitudeX
                     + sin(t * 12.5 + 1.2) * PendingLinePreviewFeedback.jitterAmplitudeX * 0.55
                let dy = cos(t * 26.0 + 0.7) * PendingLinePreviewFeedback.jitterAmplitudeY
                let base = self.scenePointPreviewRow(column: self.selectedColumn)
                node.position = CGPoint(x: base.x + dx, y: base.y + dy)
            }
        )
        preview.run(jitter, withKey: Self.previewJitterKey)
    }

    private func stopPreviewBreathing() {
        guard let preview = childNode(withName: Self.previewNodeName) else { return }
        preview.removeAction(forKey: Self.previewBreathKey)
        preview.removeAction(forKey: Self.previewJitterKey)
        let snap = SKAction.scale(to: 1.0, duration: 0.06)
        snap.timingMode = .easeOut
        preview.run(snap)
        // Snap de position vers le centre de colonne (annule le décalage du jitter).
        if let spr = preview as? SKSpriteNode {
            spr.position = scenePointPreviewRow(column: selectedColumn)
        }
    }

    /// Centre de la case `(row, col)` en coordonnées **scène** (aligné sur `drawGrid`).
    private func scenePointCellCenter(row: Int, column: Int) -> CGPoint {
        let half = GridLayout.spanPoints / 2
        let xLocal = -half + (CGFloat(column) + 0.5) * GridLayout.cellPoints
        let yLocal = half - (CGFloat(row) + 0.5) * GridLayout.cellPoints
        return CGPoint(x: gridAreaCenter.x + xLocal, y: gridAreaCenter.y + yLocal)
    }

    /// Point de la **preview du bloc courant** : à droite des deux mini « next blox », alignée par le bas.
    private func scenePointPreviewRow(column: Int) -> CGPoint {
        _ = column // Conserve la signature actuelle utilisée par l’existant.
        let cell = UpcomingQueueLayout.cellPoints
        let previewSize = GridLayout.cellPoints - 4
        let miniVisualSize = max(4, cell - 2)
        let x = size.width / 2

        // Alignement des bas: le gros bloc dépasse vers le haut.
        let miniBottomY = sceneYCenterForBombAndUpcomingBand() - miniVisualSize / 2
        let y = miniBottomY + previewSize / 2 + 1.5 * GridLayout.cellPoints
        return CGPoint(x: x, y: y)
    }

    /// Point de lancement au bas de la colonne ciblée, juste sous la grille.
    private func scenePointLaunchStartBelowGrid(column: Int) -> CGPoint {
        let clampedColumn = min(max(column, 0), GridLayout.columnCount - 1)
        let x = scenePointCellCenter(row: GridLayout.bottomRowIndex, column: clampedColumn).x
        let blockHalfHeight = (GridLayout.cellPoints - 4) / 2
        let y = gridPlayfieldBottomY() - blockHalfHeight
        return CGPoint(x: x, y: y)
    }

    /// Ordonnée du **centre** vertical de la rangée bombe + file des deux prochains blocs (sous la preview et le HUD « Next line », décalée d’1,5 case pour éviter le bloc courant).
    private func sceneYCenterForBombAndUpcomingBand() -> CGFloat {
        let rowHalf = max(36, UpcomingQueueLayout.cellPoints) / 2
        return sceneBottomOfNextLineProgressHUD() - 12 - rowHalf - 1.5 * GridLayout.cellPoints
    }

    /// Grille 8×8 entièrement vide.
    private static func makeEmptyGrid() -> [[BlockType]] {
        Array(
            repeating: Array(repeating: BlockType.empty, count: GridLayout.columnCount),
            count: GridLayout.rowCount
        )
    }

    /// Fond plein écran sombre (repère scène : origine en bas à gauche, centre en `width/2`, `height/2`).
    private func addFullscreenBackground() {
        let background = SKSpriteNode(color: .black, size: size)
        background.name = Self.backgroundNodeName
        background.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.zPosition = -10
        addChild(background)
    }

    /// Titre + sous-titre en haut (hors décalage « jeu » : le reste suit `gridAreaCenter`).
    private func addTopTitle() {
        childNode(withName: Self.titleNodeName)?.removeFromParent()
        childNode(withName: Self.gameplaySubtitleUnderTitleName)?.removeFromParent()

        let titleLiftFromTop: CGFloat = 56
        let titleY = size.height - titleLiftFromTop - GridLayout.cellPoints
        let title = SKLabelNode(text: "BLOMIX")
        title.name = Self.titleNodeName
        title.fontName = Self.customUIFontPostScriptName
        title.fontSize = 36
        title.fontColor = .white
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: size.width / 2, y: titleY)
        title.zPosition = 5
        addChild(title)

        // Sur les petits écrans (H < 700 pt : iPhone SE 2/3, iPhone 8…), le sous-titre est supprimé
        // pour libérer l'espace entre le titre et le score. Sur les grands écrans, rien ne change.
        guard size.height >= 700 else { return }

        let subtitle = SKLabelNode(text: BlomixL10n.gameTagline)
        subtitle.name = Self.gameplaySubtitleUnderTitleName
        subtitle.fontName = Self.customUIFontPostScriptName
        subtitle.fontSize = 12
        subtitle.fontColor = .white
        subtitle.horizontalAlignmentMode = .center
        subtitle.verticalAlignmentMode = .center
        let titleHalfApprox: CGFloat = 18
        let gapTitleSubtitle: CGFloat = 6
        let subtitleHalfApprox: CGFloat = 6
        subtitle.position = CGPoint(
            x: size.width / 2,
            y: titleY - titleHalfApprox - gapTitleSubtitle - subtitleHalfApprox
        )
        subtitle.zPosition = 5
        addChild(subtitle)
    }

    /// Centre de la zone 320×320 ; **+2 cases** en Y pour remonter tout le jeu (grille, HUD bas, preview…) sans changer les écarts relatifs entre ces éléments.
    ///
    /// Sur les écrans de hauteur comprise entre 620 et 750 pt (iPhone SE 2/3, iPhone 8 Plus),
    /// la bande score+compteurs empiète sur le titre avec la position par défaut.
    /// On abaisse la grille juste assez pour garantir ≥ 8 pt d'espace titre ↔ score,
    /// en respectant un plancher à 290 pt (la bande bombe reste visible au bas de l'écran).
    /// En dessous de 620 pt l'écran est trop petit ; on conserve le comportement actuel.
    private var gridAreaCenter: CGPoint {
        let defaultY = size.height * 0.42 + 2 * GridLayout.cellPoints
        let y: CGFloat
        if size.height >= 620 {
            // maxY = clearance nécessaire pour que le sommet du score (gridCenter + 232)
            // reste 8 pt sous le bas du titre (H − 114) → gridCenter < H − 354.
            let maxY = size.height - 354
            // plancher : bande bombe à ≥ 12 pt du bord bas (gridCenter − 278 ≥ 12)
            let floorY: CGFloat = 290
            y = max(floorY, min(defaultY, maxY))
        } else {
            y = defaultY
        }
        return CGPoint(x: size.width / 2, y: y)
    }

    // MARK: - Jonction Blox & sprites blox (SKColor / SKShapeNode)

    private static func skColor(hex6: UInt32, alpha: CGFloat = 1) -> SKColor {
        let r = CGFloat((hex6 >> 16) & 0xff) / 255
        let g = CGFloat((hex6 >> 8) & 0xff) / 255
        let b = CGFloat(hex6 & 0xff) / 255
        return SKColor(red: r, green: g, blue: b, alpha: alpha)
    }

    private static func skColorLerp(_ a: SKColor, _ b: SKColor, _ t: CGFloat) -> SKColor {
        let u = min(1, max(0, t))
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              b.getRed(&br, green: &bg, blue: &bb, alpha: &ba) else {
            return u < 0.5 ? a : b
        }
        return SKColor(
            red: ar + (br - ar) * u,
            green: ag + (bg - ag) * u,
            blue: ab + (bb - ab) * u,
            alpha: aa + (ba - aa) * u
        )
    }

    /// Remplissage des blox couleur (skin actif dans `color_skins.json` + `BlomixSkinCatalog`).
    private static func bloxSolidFillColor(forNormalizedKey key: String) -> SKColor? {
        BlomixSkinCatalog.shared.bloxSKColor(forNormalizedKey: key)
    }

    private static func bloxSolidFillColor(colorName: String) -> SKColor? {
        bloxSolidFillColor(forNormalizedKey: colorName)
    }

    /// Teinte unie Priks (skin actif).
    private static func priksSolidFillColor() -> SKColor {
        BlomixSkinCatalog.shared.priksSKColor()
    }

    /// Couleur du chiffre sur les Priks (skin : `prikstext`).
    private static func priksDigitLabelColor() -> SKColor {
        BlomixSkinCatalog.shared.priksDigitSKColor()
    }

    private static func solidGameplayBloxPixelSize() -> CGSize {
        CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
    }

    // MARK: - Bounce d'atterrissage

    /// Bounce à l'atterrissage en trois phases (squash-and-stretch physique) :
    ///   A – squash à l'impact : centre légèrement au-dessus (p0+h×0.055), aplatissement + étalement latéral
    ///   B – rebond élastique : centre redescend sous p0 (p0−h×0.13), allongement vertical, rétrécissement latéral
    ///   C – stabilisation : retour exact à p0, scales 1.0
    /// Pas de changement d'anchorPoint : les positions cibles sont calculées analytiquement.
    private func playLandingBounce(on sprite: SKSpriteNode, blockColor: SKColor = SKColor(white: 0.8, alpha: 1)) {
        let p0 = sprite.position
        let h  = sprite.size.height
        // Coordonnées scène pour les paillettes (sprite est enfant du gridContainer, pas de la scène).
        let sceneCenter = sprite.parent.map { convert(sprite.position, from: $0) } ?? sprite.position

        // Phase A : squash à l'impact — centre légèrement au-dessus, bloc aplati et étalé
        let moveA   = SKAction.move(to: CGPoint(x: p0.x, y: p0.y + h * 0.055),
                                    duration: LandingBounce.squashDuration)
        moveA.timingMode   = .easeOut
        let scaleXA = SKAction.scaleX(to: 1.32, duration: LandingBounce.squashDuration)
        scaleXA.timingMode = .easeOut
        let scaleYA = SKAction.scaleY(to: 0.78, duration: LandingBounce.squashDuration)
        scaleYA.timingMode = .easeOut
        let phaseA  = SKAction.group([moveA, scaleXA, scaleYA])

        // Phase B : rebond élastique — centre redescend sous p0, allongement + rétrécissement latéral
        let moveB   = SKAction.move(to: CGPoint(x: p0.x, y: p0.y - h * 0.13),
                                    duration: LandingBounce.stretchDuration)
        moveB.timingMode   = .easeOut
        let scaleXB = SKAction.scaleX(to: 0.94, duration: LandingBounce.stretchDuration)
        scaleXB.timingMode = .easeOut
        let scaleYB = SKAction.scaleY(to: 1.15, duration: LandingBounce.stretchDuration)
        scaleYB.timingMode = .easeOut
        let phaseB  = SKAction.group([moveB, scaleXB, scaleYB])

        // Phase C : stabilisation — retour à la position et taille d'origine
        let moveC   = SKAction.move(to: p0, duration: LandingBounce.settleDuration)
        moveC.timingMode   = .easeInEaseOut
        let scaleXC = SKAction.scaleX(to: 1.0, duration: LandingBounce.settleDuration)
        scaleXC.timingMode = .easeInEaseOut
        let scaleYC = SKAction.scaleY(to: 1.0, duration: LandingBounce.settleDuration)
        scaleYC.timingMode = .easeInEaseOut
        let phaseC  = SKAction.group([moveC, scaleXC, scaleYC])

        sprite.run(SKAction.sequence([phaseA, phaseB, phaseC]))

        // Burst centrifuge synchrone avec l'impact : les paillettes partent du bord du bloc,
        // se dispersent radialement (easeOut) et disparaissent quand le bloc a retrouvé
        // sa taille définitive (durée totale = LandingBounce.totalDuration).
        spawnLandingImpactSparkles(at: sceneCenter, color: blockColor)
    }

    /// Effet d'impact à l'atterrissage : deux couches de paillettes superposées.
    /// - Couche 1 (éjection) : ~12 particules, déplacement radial rapide, disparaissent en ~0.22s.
    /// - Couche 2 (nuage/poudre) : ~26 particules très fines, quasi sur place, s'estompent en ~0.55s.
    private func spawnLandingImpactSparkles(at center: CGPoint, color: SKColor) {
        let blockRadius: CGFloat = GridLayout.cellPoints / 2   // 20 pt

        // ── Couche 1 : éjection rapide ──────────────────────────────────────────────
        let ejectDuration: TimeInterval = 0.22

        for _ in 0..<12 {
            let angle     = CGFloat.random(in: 0...(2 * .pi))
            let startDist = CGFloat.random(in: (blockRadius - 3)...(blockRadius + 3))
            let endDist   = startDist + CGFloat.random(in: 12...26)

            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.8...1.8))
            spark.fillColor   = color
            spark.strokeColor = .clear
            spark.alpha       = 0
            spark.zPosition   = 37
            spark.position    = CGPoint(x: center.x + cos(angle) * startDist,
                                        y: center.y + sin(angle) * startDist)
            addChild(spark)

            let move = SKAction.move(
                to: CGPoint(x: center.x + cos(angle) * endDist,
                            y: center.y + sin(angle) * endDist),
                duration: ejectDuration)
            move.timingMode = .easeOut

            spark.run(SKAction.sequence([
                SKAction.group([
                    move,
                    SKAction.sequence([
                        SKAction.fadeAlpha(to: 0.9, duration: 0.03),
                        SKAction.fadeAlpha(to: 0,   duration: ejectDuration - 0.03),
                    ]),
                ]),
                SKAction.removeFromParent(),
            ]))
        }

        // ── Couche 2 : nuage en suspension (poudre) ─────────────────────────────────
        let cloudDuration: TimeInterval = 0.80

        for _ in 0..<38 {
            let angle     = CGFloat.random(in: 0...(2 * .pi))
            let startDist = CGFloat.random(in: (blockRadius - 5)...(blockRadius + 5))
            // Déplacement minimal = particules quasi immobiles, effet poudre en suspension.
            let drift     = CGFloat.random(in: 1...5)
            let upBias    = CGFloat.random(in: 0...3)   // légère dérive vers le haut

            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.5...1.2))
            spark.fillColor   = color
            spark.strokeColor = .clear
            spark.alpha       = 0
            spark.zPosition   = 36
            spark.position    = CGPoint(x: center.x + cos(angle) * startDist,
                                        y: center.y + sin(angle) * startDist)
            addChild(spark)

            let move = SKAction.move(
                to: CGPoint(x: center.x + cos(angle) * (startDist + drift),
                            y: center.y + sin(angle) * (startDist + drift) + upBias),
                duration: cloudDuration)
            move.timingMode = .easeOut

            let peakAlpha = CGFloat.random(in: 0.60...0.95)
            spark.run(SKAction.sequence([
                SKAction.group([
                    move,
                    SKAction.sequence([
                        SKAction.fadeAlpha(to: peakAlpha, duration: 0.05),
                        SKAction.fadeAlpha(to: 0,         duration: cloudDuration - 0.05),
                    ]),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    // MARK: - Effet traîne (paillettes lors du lancement d'un blox/brix/bombe)

    /// Couleur de paillettes pour un type de bloc (lit le skin actif du joueur).
    private static func bloxTrailColor(for block: BlockType) -> SKColor {
        switch block {
        case .color(let name): return bloxSolidFillColor(colorName: name) ?? SKColor(white: 0.8, alpha: 1)
        case .priks:           return priksSolidFillColor()
        case .magix:           return SKColor(white: 0.92, alpha: 1)   // traîne blanche "magique"
        case .empty:           return SKColor(white: 0.7, alpha: 1)
        }
    }

    /// Retourne une SKAction qui lit la position de `trackedSprite` à intervalles réguliers
    /// et dépose des paillettes (SKShapeNode, même technique que les score dots) directement
    /// dans la scène. Chaque paillette s'estompe en ~0.38 s.
    private func makeTrailSpawnAction(
        riseDuration: TimeInterval,
        color: SKColor,
        trackedSprite: SKSpriteNode
    ) -> SKAction {
        let interval: TimeInterval = 0.04          // ~25 spawns/s → 10 points pour 0.4 s
        let count = max(1, Int((riseDuration / interval).rounded()))
        // Traînes latérales : même décalage aléatoire ±4/−5..+2, centrées à ±9 pt du sprite.
        let sideOffsets: [CGFloat] = [0, -9, 9]
        var steps: [SKAction] = []
        for _ in 0..<count {
            steps.append(SKAction.wait(forDuration: interval))
            steps.append(SKAction.run { [weak self, weak trackedSprite] in
                guard let self, let sprite = trackedSprite else { return }
                for (idx, xOff) in sideOffsets.enumerated() {
                    let radius = idx == 0
                        ? CGFloat.random(in: 1.8...3.0)   // traîne centrale
                        : CGFloat.random(in: 1.0...2.0)   // traînes latérales, plus fines
                    let dot = SKShapeNode(circleOfRadius: radius)
                    dot.fillColor   = color
                    dot.strokeColor = .clear
                    dot.alpha       = 0.9
                    dot.zPosition   = 36
                    let yJitter: ClosedRange<CGFloat> = idx == 0
                        ? -5...2    // centrale : traîne resserrée sous le bloc
                        : -12...2   // latérales : plus d'éparpillement vertical
                    dot.position    = CGPoint(
                        x: sprite.position.x + xOff + CGFloat.random(in: -4...4),
                        y: sprite.position.y + CGFloat.random(in: yJitter)
                    )
                    self.addChild(dot)
                    dot.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.38),
                        SKAction.removeFromParent(),
                    ]))
                }
                // 4 micro-paillettes supplémentaires à positions X/Y entièrement aléatoires.
                for _ in 0..<4 {
                    let micro = SKShapeNode(circleOfRadius: 1.0)
                    micro.fillColor   = color
                    micro.strokeColor = .clear
                    micro.alpha       = 0.9
                    micro.zPosition   = 36
                    micro.position    = CGPoint(
                        x: sprite.position.x + CGFloat.random(in: -15...15),
                        y: sprite.position.y + CGFloat.random(in: -20...0)
                    )
                    self.addChild(micro)
                    micro.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.38),
                        SKAction.removeFromParent(),
                    ]))
                }
            })
        }
        return SKAction.sequence(steps)
    }


    /// Carré couleur unie 36×36 (ou `pixelSize`) : blox classique ou Priks + chiffre.
    private static func makeSolidGameplayBlockSprite(
        block: BlockType,
        pixelSize: CGSize? = nil,
        priksDigitFontSize: CGFloat = 18
    ) -> SKSpriteNode {
        let size = pixelSize ?? solidGameplayBloxPixelSize()
        switch block {
        case .color(let colorName):
            let c = bloxSolidFillColor(colorName: colorName) ?? SKColor(white: 0.45, alpha: 1)
            let s = SKSpriteNode(color: c, size: size)
            s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            return s
        case .priks(let value):
            let s = SKSpriteNode(color: priksSolidFillColor(), size: size)
            s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let digit = SKLabelNode(text: "\(value)")
            digit.fontName = customUIFontPostScriptName
            // Réduction automatique de la taille de police pour les valeurs à 2 chiffres (≥10).
            digit.fontSize = value >= 10 ? priksDigitFontSize * 0.72 : priksDigitFontSize
            digit.fontColor = Self.priksDigitLabelColor()
            digit.horizontalAlignmentMode = .center
            digit.verticalAlignmentMode = .center
            digit.position = .zero
            digit.zPosition = 2
            s.addChild(digit)
            return s
        case .magix(let kind):
            // Grille : apparition brève (~0.3 s pendant le bounce) → couleur statique aléatoire suffit.
            let c = colorPalette.randomElement().flatMap { bloxSolidFillColor(colorName: $0) }
                    ?? SKColor(white: 0.75, alpha: 1)
            let s = SKSpriteNode(color: c, size: size)
            s.colorBlendFactor = 1
            s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let sym = SKLabelNode(text: MagixRules.symbol(for: kind))
            sym.fontName                = customUIFontPostScriptName
            sym.fontSize                = size.height * 0.69
            sym.fontColor               = .black
            sym.horizontalAlignmentMode = .center
            sym.verticalAlignmentMode   = .center
            sym.position                = .zero
            sym.zPosition               = 5
            s.addChild(sym)
            return s
        case .empty:
            let s = SKSpriteNode(color: .clear, size: size)
            s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            return s
        }
    }

    /// Couleur de jonction à partir du nom de fichier / chemin (`blue.png`, `WebImages/blue`, etc.).
    private static func colorFromTextureName(_ name: String) -> SKColor? {
        guard let key = normalizedTextureColorKey(name) else { return nil }
        return bloxSolidFillColor(forNormalizedKey: key)
    }

    /// Extrait `blue` / `red` / … depuis `WebImages/blue`, `blue.png`, etc.
    private static func normalizedTextureColorKey(_ textureName: String) -> String? {
        var s = textureName.lowercased().replacingOccurrences(of: "\\", with: "/")
        if let r = s.range(of: "webimages/") {
            s = String(s[r.upperBound...])
        }
        s = s.replacingOccurrences(of: ".png", with: "")
        s = s.replacingOccurrences(of: ".jpg", with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let palette = ["blue", "red", "purple", "yellow", "green", "orange"]
        return palette.contains(s) ? s : nil
    }

    private func colorBlockNameAt(row: Int, col: Int) -> String? {
        guard row >= GridLayout.topRowIndex, row < GridLayout.rowCount,
              col >= 0, col < GridLayout.columnCount else { return nil }
        guard case .color(let name) = grid[row][col] else { return nil }
        return name
    }

    private static func cellCenterLocal(row: Int, col: Int) -> CGPoint {
        let half = GridLayout.spanPoints / 2
        let x = -half + (CGFloat(col) + 0.5) * GridLayout.cellPoints
        let y = half - (CGFloat(row) + 0.5) * GridLayout.cellPoints
        return CGPoint(x: x, y: y)
    }

    private func nextBloxJunctionZ() -> CGFloat {
        bloxJunctionZCounter += 0.01
        return bloxJunctionZCounter
    }

    private func registerBorderShape(_ key: String, node: SKShapeNode, in container: SKNode) {
        borderConnections[key]?.removeFromParent()
        borderConnections[key] = node
        container.addChild(node)
    }

    private func registerDiagonalShape(_ key: String, node: SKShapeNode, in container: SKNode) {
        diagonalConnections[key]?.removeFromParent()
        diagonalConnections[key] = node
        container.addChild(node)
    }

    /// Pose les connexions visuelles pour le blox **déjà** présent en `position` (même couleur que `textureName` / grille).
    /// - Parameter container: `nil` → utilise `gridContainer` s’il existe.
    private func settleBlock(at position: GridPosition, textureName: String, in container: SKNode? = nil) {
        guard let container = container ?? childNode(withName: Self.gridContainerName) as? SKNode else { return }
        guard let junctionColor = Self.colorFromTextureName(textureName),
              let texKey = Self.normalizedTextureColorKey(textureName),
              let myName = colorBlockNameAt(row: position.row, col: position.col),
              texKey == myName else { return }

        let r = position.row
        let c = position.col
        let half = GridLayout.spanPoints / 2

        // Voisin droit : même ligne — fente **4 pt (x) × 36 pt (y)** entre les deux blox (pas 36×4).
        if let rightName = colorBlockNameAt(row: r, col: c + 1), rightName == myName {
            let key = "H_\(r)_\(c)"
            if borderConnections[key] == nil {
                let x0 = -half + (CGFloat(c) + 0.5) * GridLayout.cellPoints
                let y = half - (CGFloat(r) + 0.5) * GridLayout.cellPoints
                let midX = x0 + GridLayout.cellPoints / 2
                let rect = CGRect(x: -2, y: -18, width: 4, height: 36)
                let shape = SKShapeNode(rect: rect)
                shape.name = "\(Self.junctionNodeNamePrefix)\(key)"
                shape.fillColor = junctionColor
                shape.strokeColor = .clear
                shape.lineWidth = 0
                shape.position = CGPoint(x: midX, y: y)
                shape.zPosition = nextBloxJunctionZ()
                registerBorderShape(key, node: shape, in: container)
            }
        }

        // Voisin gauche : fente 4×36 entre les colonnes c−1 et c.
        if c > 0, let leftName = colorBlockNameAt(row: r, col: c - 1), leftName == myName {
            let key = "H_\(r)_\(c - 1)"
            if borderConnections[key] == nil {
                let x0 = -half + (CGFloat(c - 1) + 0.5) * GridLayout.cellPoints
                let y = half - (CGFloat(r) + 0.5) * GridLayout.cellPoints
                let midX = x0 + GridLayout.cellPoints / 2
                let rect = CGRect(x: -2, y: -18, width: 4, height: 36)
                let shape = SKShapeNode(rect: rect)
                shape.name = "\(Self.junctionNodeNamePrefix)\(key)"
                shape.fillColor = junctionColor
                shape.strokeColor = .clear
                shape.lineWidth = 0
                shape.position = CGPoint(x: midX, y: y)
                shape.zPosition = nextBloxJunctionZ()
                registerBorderShape(key, node: shape, in: container)
            }
        }

        // Voisin bas : même colonne — fente **36 pt (x) × 4 pt (y)** entre les deux rangées.
        if let downName = colorBlockNameAt(row: r + 1, col: c), downName == myName {
            let key = "V_\(r)_\(c)"
            if borderConnections[key] == nil {
                let x = -half + (CGFloat(c) + 0.5) * GridLayout.cellPoints
                let y0 = half - (CGFloat(r) + 0.5) * GridLayout.cellPoints
                let midY = y0 - GridLayout.cellPoints / 2
                let rect = CGRect(x: -18, y: -2, width: 36, height: 4)
                let shape = SKShapeNode(rect: rect)
                shape.name = "\(Self.junctionNodeNamePrefix)\(key)"
                shape.fillColor = junctionColor
                shape.strokeColor = .clear
                shape.lineWidth = 0
                shape.position = CGPoint(x: x, y: midY)
                shape.zPosition = nextBloxJunctionZ()
                registerBorderShape(key, node: shape, in: container)
            }
        }

        // Voisin haut : fente 36×4 entre les rangées r−1 et r.
        if r > 0, let upName = colorBlockNameAt(row: r - 1, col: c), upName == myName {
            let key = "V_\(r - 1)_\(c)"
            if borderConnections[key] == nil {
                let x = -half + (CGFloat(c) + 0.5) * GridLayout.cellPoints
                let y0 = half - (CGFloat(r - 1) + 0.5) * GridLayout.cellPoints
                let midY = y0 - GridLayout.cellPoints / 2
                let rect = CGRect(x: -18, y: -2, width: 36, height: 4)
                let shape = SKShapeNode(rect: rect)
                shape.name = "\(Self.junctionNodeNamePrefix)\(key)"
                shape.fillColor = junctionColor
                shape.strokeColor = .clear
                shape.lineWidth = 0
                shape.position = CGPoint(x: x, y: midY)
                shape.zPosition = nextBloxJunctionZ()
                registerBorderShape(key, node: shape, in: container)
            }
        }

        let diagDeltas = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        for (dr, dc) in diagDeltas {
            let nr = r + dr
            let nc = c + dc
            guard let neighName = colorBlockNameAt(row: nr, col: nc), neighName == myName else { continue }
            let (r1, c1, r2, c2): (Int, Int, Int, Int) = {
                if r < nr || (r == nr && c < nc) { return (r, c, nr, nc) }
                return (nr, nc, r, c)
            }()
            let key = "D_\(r1)_\(c1)_\(r2)_\(c2)"
            guard diagonalConnections[key] == nil else { continue }

            let p1 = Self.cellCenterLocal(row: r1, col: c1)
            let p2 = Self.cellCenterLocal(row: r2, col: c2)
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -dx / 2, y: -dy / 2))
            path.addLine(to: CGPoint(x: dx / 2, y: dy / 2))
            let line = SKShapeNode(path: path)
            line.name = "\(Self.junctionNodeNamePrefix)\(key)"
            line.strokeColor = junctionColor
            line.fillColor = .clear
            line.lineWidth = CGFloat(sqrt(32.0))
            line.lineCap = .round
            line.position = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            line.zPosition = nextBloxJunctionZ()
            registerDiagonalShape(key, node: line, in: container)
        }
    }

    private func rebuildBloxJunctionShapes(in container: SKNode) {
        borderConnections.removeAll()
        diagonalConnections.removeAll()
        bloxJunctionZCounter = 2
        for row in GridLayout.topRowIndex..<GridLayout.rowCount {
            for col in 0..<GridLayout.columnCount {
                guard case .color(let colorName) = grid[row][col] else { continue }
                let tex = "\(colorName).png"
                settleBlock(at: GridPosition(row: row, col: col), textureName: tex, in: container)
            }
        }
    }

    private func junctionBorderKeyTouchesCell(_ key: String, row: Int, col: Int) -> Bool {
        let parts = key.split(separator: "_")
        guard parts.count == 3, parts[0] == "H" || parts[0] == "V" else { return false }
        guard let a = Int(parts[1]), let b = Int(parts[2]) else { return false }
        if parts[0] == "H" {
            return a == row && (b == col || b == col - 1)
        }
        return b == col && (a == row || a == row - 1)
    }

    private func junctionDiagonalKeyTouchesCell(_ key: String, row: Int, col: Int) -> Bool {
        let parts = key.split(separator: "_")
        guard parts.count == 5, parts[0] == "D" else { return false }
        guard let r1 = Int(parts[1]), let c1 = Int(parts[2]), let r2 = Int(parts[3]), let c2 = Int(parts[4]) else { return false }
        return (r1 == row && c1 == col) || (r2 == row && c2 == col)
    }

    /// Retire les liaisons (H / V / diagonales) qui touchent au moins une case de la chaîne, **avant** l’animation des blox.
    private func removeBloxJunctionElementsTouching(_ cells: Set<GridAddress>) {
        guard !cells.isEmpty else { return }

        let borderKeys = borderConnections.keys.filter { key in
            cells.contains { junctionBorderKeyTouchesCell(key, row: $0.row, col: $0.col) }
        }
        for key in borderKeys {
            borderConnections[key]?.removeFromParent()
            borderConnections.removeValue(forKey: key)
        }

        let diagonalKeys = diagonalConnections.keys.filter { key in
            cells.contains { junctionDiagonalKeyTouchesCell(key, row: $0.row, col: $0.col) }
        }
        for key in diagonalKeys {
            diagonalConnections[key]?.removeFromParent()
            diagonalConnections.removeValue(forKey: key)
        }
    }

    /// Remonte les traits qui touchent la case du **dernier** blox posé.
    private func elevateBloxJunctionsTouching(_ focus: GridPosition) {
        let r = focus.row
        let c = focus.col
        var z: CGFloat = 12
        for (key, node) in borderConnections where junctionBorderKeyTouchesCell(key, row: r, col: c) {
            node.zPosition = z
            z += 0.02
        }
        for (key, node) in diagonalConnections where junctionDiagonalKeyTouchesCell(key, row: r, col: c) {
            node.zPosition = z
            z += 0.02
        }
    }

    /// Dessine toute la grille : supprime les anciens nœuds du conteneur puis recrée les cases.
    private func drawGrid(junctionFocus: GridPosition? = nil) {
        let container = childNode(withName: Self.gridContainerName) as? SKNode ?? {
            let node = SKNode()
            node.name = Self.gridContainerName
            node.zPosition = 1
            addChild(node)
            return node
        }()
        for child in Array(container.children) {
            guard let name = child.name else { continue }
            if name.hasPrefix("cell_") || name.hasPrefix(Self.junctionNodeNamePrefix)
                || name == Self.colorxOverlayContainerName {
                child.removeFromParent()
            }
        }
        borderConnections.removeAll()
        diagonalConnections.removeAll()
        container.position = gridAreaCenter

        let half = GridLayout.spanPoints / 2

        for row in 0..<GridLayout.rowCount {
            for col in 0..<GridLayout.columnCount {
                let block = grid[row][col]
                let x = -half + (CGFloat(col) + 0.5) * GridLayout.cellPoints
                let y = half - (CGFloat(row) + 0.5) * GridLayout.cellPoints

                switch block {
                case .empty:
                    let slot = SKSpriteNode(
                        color: SKColor(white: 0.12, alpha: 1),
                        size: CGSize(width: GridLayout.cellPoints - 4, height: GridLayout.cellPoints - 4)
                    )
                    slot.name = "cell_\(row)_\(col)"
                    slot.position = CGPoint(x: x, y: y)
                    slot.zPosition = 0
                    container.addChild(slot)

                case .color(let colorName):
                    let sprite = Self.makeSolidGameplayBlockSprite(block: .color(colorName))
                    sprite.name = "cell_\(row)_\(col)"
                    sprite.position = CGPoint(x: x, y: y)
                    sprite.zPosition = 1
                    container.addChild(sprite)

                case .priks(let value):
                    let sprite = Self.makeSolidGameplayBlockSprite(block: .priks(value))
                    sprite.name = "cell_\(row)_\(col)"
                    sprite.position = CGPoint(x: x, y: y)
                    sprite.zPosition = 1
                    container.addChild(sprite)

                case .magix(let kind):
                    let sprite = Self.makeSolidGameplayBlockSprite(block: .magix(kind))
                    sprite.name = "cell_\(row)_\(col)"
                    sprite.position = CGPoint(x: x, y: y)
                    sprite.zPosition = 1
                    container.addChild(sprite)
                }
            }
        }

        rebuildBloxJunctionShapes(in: container)
        if let focus = junctionFocus {
            elevateBloxJunctionsTouching(focus)
        }

        container.childNode(withName: Self.gridFrameOutlineName)?.removeFromParent()
        let frameMargin: CGFloat = 2
        let strokeW: CGFloat = 1
        let originXY = -half - frameMargin - strokeW * 0.5
        let outerSide = GridLayout.spanPoints + 2 * frameMargin + strokeW
        let outlineRect = CGRect(x: originXY, y: originXY, width: outerSide, height: outerSide)
        let outline = SKShapeNode(rect: outlineRect)
        outline.name = Self.gridFrameOutlineName
        outline.strokeColor = ProgressHUD.segmentFilled
        outline.fillColor = .clear
        outline.lineWidth = strokeW
        outline.lineJoin = .miter
        outline.zPosition = 50
        container.addChild(outline)

        layoutBombHUD()
        refreshUpcomingQueueSlots()
        layoutScoreLabel()
        refreshProgressHUDBars()
        refreshPendingBottomLinePreview()
        pvpCoordinator?.localBoardFillDepthDidUpdate(currentBoardFillDepth(), score: score)
    }

    private func currentBoardFillDepth() -> Int {
        for row in (GridLayout.topRowIndex..<GridLayout.rowCount).reversed() {
            let hasAnyBlock = (0..<GridLayout.columnCount).contains { grid[row][$0] != .empty }
            if hasAnyBlock {
                return row + 1
            }
        }
        return 0
    }

    // MARK: - Barres de progression (ligne des 10 / bombe bonus)

    private static func pvpRemoteFillSegmentName(_ index: Int) -> String {
        "\(Self.pvpRemoteFillSegPrefix)\(index)"
    }

    private func ensureRemoteBoardFillIndicatorIfNeeded() {
        guard pvpCoordinator != nil else { return }
        guard childNode(withName: Self.pvpRemoteFillContainerName) == nil else { return }
        let container = SKNode()
        container.name = Self.pvpRemoteFillContainerName
        container.zPosition = 12
        addChild(container)

        for i in 0..<GridLayout.rowCount {
            let seg = SKSpriteNode(
                color: ProgressHUD.dimTrack,
                size: CGSize(width: ProgressHUD.remoteFillSegmentWidth, height: GridLayout.cellPoints - ProgressHUD.remoteFillGap)
            )
            seg.name = Self.pvpRemoteFillSegmentName(i)
            seg.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            seg.zPosition = 0
            container.addChild(seg)
        }

        // Légende "Grille / adversaire" sous l'indicateur, à gauche.
        let grayColor = SKColor(red: 0xA3 / 255.0, green: 0xA3 / 255.0, blue: 0xA3 / 255.0, alpha: 1)
        let gridBottomY = -(GridLayout.spanPoints / 2)

        // x dans l'espace container = bord gauche de la grille
        let labelX = ProgressHUD.remoteFillMarginLeftOfGrid + ProgressHUD.remoteFillSegmentWidth / 2

        for (index, text) in [BlomixL10n.pvpRemoteFillLabelLine1, BlomixL10n.pvpRemoteFillLabelLine2].enumerated() {
            let lbl = SKLabelNode(text: text)
            lbl.fontName = Self.customUIFontPostScriptName
            lbl.fontSize = 14
            lbl.fontColor = grayColor
            lbl.horizontalAlignmentMode = .left
            lbl.verticalAlignmentMode = .top
            lbl.zPosition = 0
            lbl.position = CGPoint(x: labelX, y: gridBottomY - 6 - CGFloat(index) * 16)
            container.addChild(lbl)
        }

        // Score de l'adversaire, sous "adversaire".
        let scoreLbl = SKLabelNode(text: "–")
        scoreLbl.name = Self.pvpRemoteScoreLabelName
        scoreLbl.fontName = Self.customUIFontPostScriptName
        scoreLbl.fontSize = 14
        scoreLbl.fontColor = grayColor
        scoreLbl.horizontalAlignmentMode = .left
        scoreLbl.verticalAlignmentMode = .top
        scoreLbl.zPosition = 0
        scoreLbl.position = CGPoint(x: labelX, y: gridBottomY - 6 - 2 * 16)
        container.addChild(scoreLbl)
    }

    /// Rafraîchit les indicateurs HUD de progression + compteurs.
    private func refreshProgressHUDBars() {
        guard !isStartScreen else { return }
        refreshRemoteBoardFillIndicator()
        refreshLigneCounterHUD()
        updateEvalDebugHUD()
    }

    /// Affiche le score d'évaluation de la grille courante sous l'icône bombe (debug, temporaire).
    private func updateEvalDebugHUD() {
        guard BlomixMoveAnalyzer.evalEnabled else { return }
        guard let lbl = childNode(withName: Self.evalDebugLabelName) as? SKLabelNode else { return }
        guard !isStartScreen, !isGameOver else { lbl.text = "eval: –"; return }
        let score = BlomixMoveAnalyzer.evaluate(grid: grid, moveCount: moveCount)
        lbl.text = "eval: \(score)"
    }

    /// Met à jour le compteur "LIGNE x/10" en haut à gauche.
    /// Couleurs : 0-5 gris, 6-8 orange, 9-10 rouge + shake.
    private func refreshLigneCounterHUD() {
        guard !isStartScreen else { return }
        guard let caption = childNode(withName: Self.ligneCaptionName) as? SKLabelNode,
              let value   = childNode(withName: Self.ligneValueName)   as? SKLabelNode else { return }

        let displayValue: Int = isInjectingBottomRandomLine ? 10 : moveCount % 10
        value.text = "\(displayValue)/10"

        let gray   = SKColor(red: 0xA3/255.0, green: 0xA3/255.0, blue: 0xA3/255.0, alpha: 1)
        let orange = SKColor(red: 244/255.0,  green: 162/255.0,  blue: 97/255.0,   alpha: 1)
        let red    = SKColor(red: 0.90,        green: 0.20,        blue: 0.20,       alpha: 1)

        switch displayValue {
        case 0...5:
            value.fontColor = gray
            caption.fontColor = gray
        case 6...8:
            value.fontColor = orange
            caption.fontColor = orange
        default:
            value.fontColor = red
            caption.fontColor = red
        }

        let shakeKey = "ligneShake"
        if displayValue >= 9 {
            if value.action(forKey: shakeKey) == nil {
                let dx: CGFloat = 2
                let dt: TimeInterval = 0.05
                let shake = SKAction.repeatForever(SKAction.sequence([
                    SKAction.moveBy(x: -dx, y: 0, duration: dt),
                    SKAction.moveBy(x:  dx * 2, y: 0, duration: dt),
                    SKAction.moveBy(x: -dx * 2, y: 0, duration: dt),
                    SKAction.moveBy(x:  dx * 2, y: 0, duration: dt),
                    SKAction.moveBy(x: -dx, y: 0, duration: dt),
                    SKAction.wait(forDuration: 0.5),
                ]))
                value.run(shake, withKey: shakeKey)
            }
        } else {
            value.removeAction(forKey: shakeKey)
            // Réinitialiser l'offset X résiduel de l'animation.
            let half = GridLayout.spanPoints / 2
            value.position.x = gridAreaCenter.x - half
        }
    }

    /// Met à jour le compteur "BOMBE x/10" en haut à droite.
    /// Couleurs : 0-5 gris, 6-8 bleu pâle, 9-10 vert + shake.
    private func refreshBombeCounterHUD() {
        // Le compteur BOMBE x/10 est supprimé (v3 : bombes fixes dès le départ).
    }

    private func refreshRemoteBoardFillIndicator() {
        guard !isStartScreen else { return }
        guard pvpCoordinator != nil else {
            childNode(withName: Self.pvpRemoteFillContainerName)?.removeFromParent()
            return
        }

        ensureRemoteBoardFillIndicatorIfNeeded()
        guard let container = childNode(withName: Self.pvpRemoteFillContainerName) else { return }

        let half = GridLayout.spanPoints / 2
        let x = gridAreaCenter.x - half - ProgressHUD.remoteFillMarginLeftOfGrid - ProgressHUD.remoteFillSegmentWidth / 2
        container.position = CGPoint(x: x, y: gridAreaCenter.y)

        let localHalf = GridLayout.spanPoints / 2
        for row in 0..<GridLayout.rowCount {
            guard let seg = container.childNode(withName: Self.pvpRemoteFillSegmentName(row)) as? SKSpriteNode else { continue }
            let y = localHalf - (CGFloat(row) + 0.5) * GridLayout.cellPoints
            seg.position = CGPoint(x: 0, y: y)
            seg.size = CGSize(width: ProgressHUD.remoteFillSegmentWidth, height: GridLayout.cellPoints - ProgressHUD.remoteFillGap)
            seg.color = row < pvpRemoteBoardFillDepth ? ProgressHUD.lineFill : ProgressHUD.dimTrack
        }

        if let scoreLbl = container.childNode(withName: Self.pvpRemoteScoreLabelName) as? SKLabelNode {
            scoreLbl.text = pvpRemoteScore > 0 ? "\(pvpRemoteScore)" : "–"
        }
    }

    // MARK: - Sauvegarde automatique solo

    private func registerSoloSaveObserverIfNeeded() {
        for notifName in [UIApplication.willResignActiveNotification,
                          UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.addObserver(
                forName: notifName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.saveCurrentSoloGameState()
            }
        }
    }

    private func saveCurrentSoloGameState() {
        guard !isStartScreen, !isGameOver, pvpCoordinator == nil, !isTutorialMode, !isWindingDown else { return }
        let save = BlomixSoloGameSave(
            version: BlomixSoloGameSave.currentVersion,
            grid: grid,
            currentBlock: currentBlock,
            blockAfterCurrent: blockAfterCurrent,
            blockTwoAhead: blockTwoAhead,
            selectedColumn: selectedColumn,
            moveCount: moveCount,
            nextBottomLine: nextBottomLine,
            bombCount: bombCount,
            isBombMode: isBombMode,
            chainClearWaveCount: chainClearWaveCount,
            score: score,
            displayedScore: displayedScore,
            chainSeriesLevel: chainSeriesLevel,
            savedAt: Date(),
            currentStageIndex: currentStageIndex,
            stageTimerSecondsRemaining: stageTimerSecondsRemaining,
            moveRecords: analyzerGameStats.records,
            hintsRemaining: hintsRemaining,
            isZenMode: isZenMode
        )
        BlomixSoloSaveManager.shared.save(save)
    }

    private func restoreFromSoloSave(_ save: BlomixSoloGameSave) {
        // Sécurité : si un pendingTutorialStart traîne d'un chemin non consommé, on l'annule —
        // la restauration d'une sauvegarde prend la priorité sur le lancement différé du tutoriel.
        pendingTutorialStart = false
        // Restauration de l'état logique
        grid = save.grid
        currentBlock = save.currentBlock
        blockAfterCurrent = save.blockAfterCurrent
        blockTwoAhead = save.blockTwoAhead
        selectedColumn = save.selectedColumn
        moveCount = save.moveCount
        nextBottomLine = save.nextBottomLine
        bombCount = save.bombCount
        isBombMode = save.isBombMode
        chainClearWaveCount = save.chainClearWaveCount
        score = save.score
        displayedScore = save.displayedScore
        chainSeriesLevel = save.chainSeriesLevel
        currentStageIndex = save.currentStageIndex
        stageTimerSecondsRemaining = save.stageTimerSecondsRemaining
        analyzerGameStats.restore(records: save.moveRecords)
        hintsRemaining = save.hintsRemaining

        // Passage en mode jeu (comme beginNewMatchFromStartScreen, sans reset)
        childNode(withName: Self.startScreenOverlayName)?.removeFromParent()
        isStartScreen = false

        addTopTitle()
        setupBombHUD()
        setupScoreHUD()
        drawGrid()
        updatePreviewSprite()
        ensureGameOverflowMenuIfNeeded()
        layoutGameOverflowMenuIfNeeded()
        setGameplayNodesHidden(false)

        // Synchronisation des labels HUD avec les valeurs restaurées
        if let label = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode {
            label.text = "\(displayedScore)"
        }
        updateBombHUD()
        updateHintButton()
        refreshBombHudIcon()
        ensureStageBadge()
        layoutStageBadge()
        refreshStageBadge()
        refreshBestScoreHUDIfNeeded()
        refreshLigneCounterHUD()
        refreshPendingBottomLinePreview()
        if !isZenMode {
            ensureStageTimerHUD()
            layoutStageTimerHUD()
            updateStageTimerHUD()
            restartStageTimer()
        }

        soundBank.play(.begin)
        refreshGameCenterStatusLabelText()
        // Reprendre la musique du mode sauvegardé.
        if isZenMode {
            BlomixMusicPlayer.shared.switchToFile(Self.soloStages[0].musicFilename)
        } else if isInStagedSoloMode {
            BlomixMusicPlayer.shared.switchToFile(Self.soloStages[currentStageIndex].musicFilename)
        }
        NotificationCenter.default.post(name: .blomixDidBeginGameplayMatch, object: self)
    }

    // MARK: - Boucle de jeu

    /// Une fois par frame — physique, timers, logique dépendante du delta temps.
    override func update(_ currentTime: TimeInterval) {
    }

    // MARK: - Visée bombe (blast preview)

    /// Affiche (ou met à jour) l'overlay blanc semi-transparent des cases impactées.
    private func showBombBlastPreview(row: Int, col: Int) {
        hideBombBlastPreview()
        let container = SKNode()
        container.name      = Self.bombBlastPreviewContainerName
        container.zPosition = 19  // entre ghost-drop (18) et bloc tombant (20)
        addChild(container)
        let cellSize = CGSize(width: GridLayout.cellPoints - 2, height: GridLayout.cellPoints - 2)
        for addr in bombAffectedCells(centerRow: row, centerCol: col) {
            let tile       = SKShapeNode(rectOf: cellSize, cornerRadius: 3)
            tile.fillColor   = SKColor(white: 0.0, alpha: 0.75)
            tile.strokeColor = .clear
            tile.position    = scenePointCellCenter(row: addr.row, column: addr.col)
            container.addChild(tile)
        }
    }

    /// Retire l'overlay de visée bombe.
    private func hideBombBlastPreview() {
        childNode(withName: Self.bombBlastPreviewContainerName)?.removeFromParent()
    }

    /// Annule la visée bombe : retire l'overlay et remet l'état à zéro.
    private func cancelBombAim() {
        bombAimTouchIsLive = false
        bombAimTargetCell  = nil
        hideBombBlastPreview()
    }

    // MARK: - Ghost drop preview

    /// Démarre le suivi du doigt : arme un timer qui activera le ghost après 120 ms.
    private func beginGhostTracking(column: Int) {
        ghostTouchIsLive = true
        ghostPreviewColumn = column
        ghostHoldTimer?.invalidate()
        let t = Timer(timeInterval: Self.ghostHoldDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.ghostTouchIsLive else { return }
                if let col = self.ghostPreviewColumn {
                    self.showGhostPreview(column: col)
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ghostHoldTimer = t
    }

    /// Appelé sur touchesMoved : met à jour la colonne et le ghost si déjà actif.
    private func moveGhostToColumn(_ column: Int) {
        guard ghostTouchIsLive else { return }
        let changed = ghostPreviewColumn != column
        ghostPreviewColumn = column
        // Mettre à jour l'affichage uniquement si le ghost est déjà visible.
        if changed, childNode(withName: Self.ghostContainerName) != nil {
            showGhostPreview(column: column)
        }
    }

    // MARK: - Retours haptiques

    // MARK: - Retours haptiques

    /// Générateur haptique `.medium` pour les événements clés (démarrage, game over, auto-drop, nouvelle ligne).
    private let hapticEngine      = UIImpactFeedbackGenerator(style: .medium)
    /// Générateur haptique `.heavy` pour les impacts percutants (explosion bombe).
    private let hapticHeavyEngine = UIImpactFeedbackGenerator(style: .heavy)
    /// Générateur haptique `.light` pour les chaînes (action fréquente, toucher doux).
    private let hapticLightEngine = UIImpactFeedbackGenerator(style: .light)

    private func hapticSoft() {
        if Thread.isMainThread {
            hapticEngine.impactOccurred()
            hapticEngine.prepare()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.hapticEngine.impactOccurred()
                self?.hapticEngine.prepare()
            }
        }
    }

    private func hapticHeavy() {
        if Thread.isMainThread {
            hapticHeavyEngine.impactOccurred()
            hapticHeavyEngine.prepare()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.hapticHeavyEngine.impactOccurred()
                self?.hapticHeavyEngine.prepare()
            }
        }
    }

    /// Retour haptique léger — déclenché à chaque création de chaîne.
    private func hapticLight() {
        if Thread.isMainThread {
            hapticLightEngine.impactOccurred()
            hapticLightEngine.prepare()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.hapticLightEngine.impactOccurred()
                self?.hapticLightEngine.prepare()
            }
        }
    }

    /// Micro-tremblement de l'écran via `CAKeyframeAnimation` sur la vue hôte.
    /// `intensity` : amplitude en points (~1.5 = léger, ~2.5 = marqué).
    private func shakeScreen(intensity: CGFloat = 2.0) {
        guard let view = self.view else { return }
        let anim = CAKeyframeAnimation(keyPath: "position.x")
        let v = intensity
        anim.values    = [0, v, -v, v * 0.55, -v * 0.55, v * 0.20, -v * 0.20, 0]
        anim.duration  = 0.14
        anim.isAdditive = true
        if Thread.isMainThread {
            view.layer.add(anim, forKey: "screenShake")
        } else {
            DispatchQueue.main.async { view.layer.add(anim, forKey: "screenShake") }
        }
    }

    /// Retire le ghost et nettoie tout l'état de tracking (appelé sur drop, cancel ou interruption).
    private func cancelGhostPreview() {
        ghostTouchIsLive = false
        ghostHoldTimer?.invalidate()
        ghostHoldTimer = nil
        ghostPreviewColumn = nil
        childNode(withName: Self.ghostContainerName)?.removeFromParent()
        childNode(withName: Self.hintGhostContainerName)?.removeFromParent()
        pendingHintRequest = false
        // Recentre le sprite preview à sa position d'origine (annulation sans drop).
        childNode(withName: Self.previewNodeName)?.position.x = size.width / 2
    }

    // MARK: - Hint

    /// Met à jour l'apparence du bouton "?" selon le stock et la disponibilité de l'analyse.
    func updateHintButton() { /* bouton hint supprimé */ }

    /// Affiche les ghost blocs fantômes sur toutes les colonnes optimales, avec clignotement.
    /// Décrémente `hintsRemaining` et auto-supprime après 2.5 s.
    func showHintGhost() {
        guard hintsRemaining > 0 else { return }
        guard !isProcessing, !isGameOver, !isStartScreen, !isBombMode else { return }
        guard pvpCoordinator == nil, !isTutorialMode else { return }

        guard let la = analyzerLookAhead else {
            // Analyse pas encore prête : mémoriser la demande, elle sera honorée dès que le résultat arrive.
            pendingHintRequest = true
            return
        }

        pendingHintRequest = false
        hintsRemaining -= 1
        updateHintButton()

        // Retire un éventuel hint ghost déjà présent.
        childNode(withName: Self.hintGhostContainerName)?.removeFromParent()

        let container = SKNode()
        container.name = Self.hintGhostContainerName
        container.zPosition = 17  // juste sous le ghost d'appui long (18)
        addChild(container)

        // Trouve les colonnes optimales.
        let optCols = la.scorePerColumn.indices.filter { idx in
            guard let s = la.scorePerColumn[idx] else { return false }
            return s == la.optimalScore
        }

        for col in optCols {
            guard let landingRow = highestEmptyRow(inColumn: col) else { continue }
            let ghost = Self.makeSolidGameplayBlockSprite(block: currentBlock)
            ghost.position = scenePointCellCenter(row: landingRow, column: col)
            ghost.alpha    = 0.60
            ghost.zPosition = 2
            // Clignotement doux
            let blink = SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.20, duration: 0.45),
                SKAction.fadeAlpha(to: 0.60, duration: 0.45),
            ]))
            ghost.run(blink)
            container.addChild(ghost)
        }

        // Le ghost reste visible jusqu'au prochain coup du joueur (supprimé par cancelGhostPreview / dropBlock).
    }

    /// Retourne toujours false — bouton hint supprimé.
    private func touchHitsHintButton(_ pt: CGPoint) -> Bool {
        return false
    }
    /// Construit (ou reconstruit) le nœud ghost pour la colonne donnée :
    /// cases vides en gris #444 + sprite semi-transparent du bloc courant à l'emplacement d'atterrissage.
    private func showGhostPreview(column: Int) {
        childNode(withName: Self.ghostContainerName)?.removeFromParent()
        guard !isProcessing, !isGameOver, !isStartScreen else { return }
        guard column >= 0, column < GridLayout.columnCount else { return }
        guard !checkGameOver(forNormalDropInColumn: column) || isBombMode else { return }

        let container = SKNode()
        container.name = Self.ghostContainerName
        container.zPosition = 18  // au-dessus de la grille, en dessous du bloc tombant (z 20)
        addChild(container)

        let cp = GridLayout.cellPoints

        // ── Surbrillance des cases vides de la colonne ───────────────────────
        for row in GridLayout.topRowIndex..<GridLayout.rowCount {
            guard grid[row][column] == .empty else { continue }
            let pos = scenePointCellCenter(row: row, column: column)
            let cell = SKShapeNode(rectOf: CGSize(width: cp - 2, height: cp - 2), cornerRadius: 3)
            cell.fillColor   = SKColor(white: 0.267, alpha: 0.9)   // ~#444
            cell.strokeColor = .clear
            cell.position    = pos
            container.addChild(cell)
        }

        // ── Bloc fantôme à la position d'atterrissage ─────────────────────────
        if !isBombMode, let landingRow = highestEmptyRow(inColumn: column) {
            let ghost = Self.makeSolidGameplayBlockSprite(block: currentBlock)
            ghost.position = scenePointCellCenter(row: landingRow, column: column)
            ghost.alpha    = 0.55
            ghost.zPosition = 2   // au-dessus des cellules grises
            container.addChild(ghost)
        }

        // ── Déplace le sprite preview sous la colonne ciblée ─────────────────
        childNode(withName: Self.previewNodeName)?.position.x =
            scenePointCellCenter(row: GridLayout.bottomRowIndex, column: column).x
    }


    // MARK: - Interactive Tutorial Mode

    // ── Séquence de blox prédéfinie ─────────────────────────────────────────────

    private func buildTutorialBlockQueue() -> [BlockType] {
        var q: [BlockType] = []
        // Phase intro : jaune + rouge (2 drops)
        q += [.color("yellow"), .color("red")]
        // Phase chaîne : 16 bleus (suffisant pour toute disposition)
        q += Array(repeating: .color("blue"), count: 16)
        // Post-chaîne : 6 blocs variés avant le Brix
        q += [.color("yellow"), .color("blue"), .color("green"),
              .color("red"),    .color("blue"), .color("blue")]
        // Brix
        q.append(.priks(PriksRules.initialHitsRemaining))
        // Phase Brix : 16 jaunes pour faciliter les chaînes adjacentes
        q += Array(repeating: .color("yellow"), count: 16)
        // Free play avant bombe : 4 blocs variés
        q += [.color("red"), .color("green"), .color("blue"), .color("yellow")]
        // Après bombe : continuation libre
        q += Array(repeating: .color("blue"), count: 10)
        return q
    }

    // ── Démarrage ────────────────────────────────────────────────────────────────

    /// Point d'entrée unique pour lancer une partie tutoriel (premier lancement ou bouton "Tutoriel").
    private func startTutorialGameWithIntro() {
        // Évite un double-déclenchement si le tutoriel est déjà en cours.
        guard !isTutorialMode else { return }
        showTransitionOverlay(
            line1: BlomixL10n.transitionTutorialTitle,
            line2:  BlomixL10n.transitionTutorialSubtitle
        ) { [weak self] in
            self?.startTutorialGame()
        }
    }


    // MARK: - Stage system (solo)

    private struct SoloStageConfig {
        let minScore: Int
        let timerSeconds: Int
        let multiplier: Int
        let displayName: String
        /// Texte affiché sous "Level" dans l'overlay de transition et dans les badges.
        let levelText: String
        /// Nom du fichier audio à jouer en boucle pendant ce stage.
        let musicFilename: String
        /// Ligne 1 de l'overlay de transition.
        var overlayLine1: String { "\(timerSeconds) s par coup" }
        /// Ligne 2 de l'overlay de transition.
        var overlayLine2: String { "Points x \(multiplier)" }
    }

    private static let soloStages: [SoloStageConfig] = [
        SoloStageConfig(minScore:    0, timerSeconds: 32, multiplier: 1, displayName: "STAGE 1",      levelText: "1",        musicFilename: "Puzzle Game 2.mp3"),
        SoloStageConfig(minScore:  250, timerSeconds: 16, multiplier: 2, displayName: "STAGE 2",      levelText: "2",        musicFilename: "Puzzle Game 2 - 1.1.mp3"),
        SoloStageConfig(minScore: 1000, timerSeconds:  8, multiplier: 3, displayName: "STAGE 3",      levelText: "3",        musicFilename: "Puzzle Game 2 - 1.2.mp3"),
        SoloStageConfig(minScore: 2000, timerSeconds:  4, multiplier: 4, displayName: "STAGE 4",      levelText: "4",        musicFilename: "Puzzle Game 2 - 1.3.mp3"),
        SoloStageConfig(minScore: 3000, timerSeconds:  2, multiplier: 5, displayName: "STAGE 5",      levelText: "5",        musicFilename: "Puzzle Game 2 - 1.4.mp3"),
        SoloStageConfig(minScore: 5000, timerSeconds:  1, multiplier: 6, displayName: "STAGE ULTIME", levelText: "Ultimate", musicFilename: "Puzzle Game 2 - 1.5.mp3"),
    ]

    private static let stageTimerHudName    = "hudStageTimer"
    private static let stageBadgeNodeName   = "hudStageBadge"
    private static let stageTimerActionKey  = "soloStageCountdown"
    /// Durée minimale pendant laquelle le preview tremblotant est visible avant que le timer
    /// ne commence à décompter. Garantit 1.5 s même au Stage Ultime (timer natif = 1 s).
    private static let stageTimerPreviewGrace: TimeInterval = 1.5

    private var currentStageIndex: Int = 0
    private var stageTimerSecondsRemaining: Int = 32

    private var isInStagedSoloMode: Bool { pvpCoordinator == nil && !isTutorialMode && !isZenMode }

    private var currentStageConfig: SoloStageConfig {
        Self.soloStages[min(currentStageIndex, Self.soloStages.count - 1)]
    }


    // MARK: - Stage HUD

    private func ensureStageTimerHUD() {
        guard childNode(withName: Self.stageTimerHudName) == nil else { return }
        let lbl = SKLabelNode(text: "32s")
        lbl.name                    = Self.stageTimerHudName
        lbl.fontName                = Self.customUIFontPostScriptName
        lbl.fontSize                = 14
        lbl.fontColor               = .white
        lbl.horizontalAlignmentMode = .right
        lbl.verticalAlignmentMode   = .center
        lbl.zPosition               = 12
        lbl.isHidden                = true
        addChild(lbl)
        layoutStageTimerHUD()
    }

    private func layoutStageTimerHUD() {
        guard let lbl = childNode(withName: Self.stageTimerHudName) as? SKLabelNode else { return }
        guard let scoreLbl = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode else { return }
        let half = GridLayout.spanPoints / 2
        // Emplacement de l'ancien compteur BOMBE — bord droit du score, juste en dessous de "TEMPS"
        lbl.position = CGPoint(x: gridAreaCenter.x + half, y: scoreLbl.position.y - 11)
    }

    private func updateStageTimerHUD() {
        guard let lbl = childNode(withName: Self.stageTimerHudName) as? SKLabelNode else { return }
        lbl.text    = "\(stageTimerSecondsRemaining)s"
        lbl.isHidden = !isInStagedSoloMode || isStartScreen || isGameOver
        // Couleur urgence
        switch stageTimerSecondsRemaining {
        case 0...2: lbl.fontColor = SKColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)
        case 3...5: lbl.fontColor = SKColor(red: 244/255, green: 162/255, blue: 97/255, alpha: 1)
        default:    lbl.fontColor = .white
        }
        // Synchronise la visibilité de la caption "TEMPS"
        childNode(withName: Self.hudTimerCaptionName)?.isHidden = lbl.isHidden
    }

    // MARK: - Stage badge (image 100×100 en jeu)

    /// Crée le badge si absent. Appelé dans la completion de l'overlay de transition.
    private func ensureStageBadge() {
        guard isInStagedSoloMode else { return }
        guard childNode(withName: Self.stageBadgeNodeName) == nil else { return }
        let badge = SKLabelNode()
        badge.name                   = Self.stageBadgeNodeName
        badge.fontName               = Self.customUIFontPostScriptName
        badge.fontSize               = 18
        badge.fontColor              = .white
        badge.horizontalAlignmentMode = .center
        badge.verticalAlignmentMode   = .center
        badge.zPosition              = 12
        badge.isHidden               = true   // layoutStageBadge + refreshStageBadge l'affichent
        addChild(badge)
    }

    /// Positionne le badge à gauche de la grille, aligné verticalement sur le compteur de bombes.
    private func layoutStageBadge() {
        guard let badge = childNode(withName: Self.stageBadgeNodeName) as? SKLabelNode else { return }
        let half  = GridLayout.spanPoints / 2
        let bandY = sceneYCenterForBombAndUpcomingBand()
        badge.position = CGPoint(x: gridAreaCenter.x - half + 25, y: bandY)
    }

    /// Met à jour le texte et la visibilité du badge.
    private func refreshStageBadge() {
        guard let badge = childNode(withName: Self.stageBadgeNodeName) as? SKLabelNode else { return }
        let lv = currentStageConfig.levelText
        badge.text     = lv == "Ultimate" ? "L★" : "L\(lv)"
        badge.isHidden = !isInStagedSoloMode || isStartScreen || isGameOver
    }

    // MARK: - Stage timer

    /// Redémarre le timer depuis la durée complète du stage courant.
    func restartStageTimer() {
        guard isInStagedSoloMode, !isGameOver, !isStartScreen else { return }
        removeAction(forKey: Self.stageTimerActionKey)
        stageTimerSecondsRemaining = currentStageConfig.timerSeconds
        updateStageTimerHUD()
        // Le premier tick est retardé d'au moins stageTimerPreviewGrace (1.5 s) pour garantir
        // que le preview tremblotant est visible même au Stage Ultime (timer natif = 1 s).
        let firstDelay = max(1.0, Self.stageTimerPreviewGrace)
        let seq = SKAction.sequence([
            SKAction.wait(forDuration: firstDelay),
            SKAction.run { [weak self] in self?.stageTimerTick() },
            SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.run { [weak self] in self?.stageTimerTick() },
            ])),
        ])
        run(seq, withKey: Self.stageTimerActionKey)
    }

    func stopStageTimer() {
        removeAction(forKey: Self.stageTimerActionKey)
    }

    private func stageTimerTick() {
        guard isInStagedSoloMode, !isGameOver, !isStartScreen else {
            stopStageTimer()
            return
        }
        // Pause pendant traitement (chaînes / injection ligne) ou en mode bombe (joueur a la main)
        guard !isProcessing, !isInjectingBottomRandomLine, !isBombMode else { return }
        stageTimerSecondsRemaining -= 1
        updateStageTimerHUD()
        if stageTimerSecondsRemaining <= 0 {
            // Auto-drop dans la colonne la plus libre disponible
            stopStageTimer()
            if let col = autoDropPreferredColumn() {
                selectedColumn = col
                updatePreviewSprite()
                hapticSoft()
                dropBlock(usingColumn: col)
            } else {
                triggerGameOver()
            }
        }
    }

    // MARK: - Stage advance

    /// Vérifie si le score courant fait passer à un nouveau stage.
    /// Appelé après chaque addScore en solo.
    private func checkStageAdvance() {
        guard isInStagedSoloMode else { return }
        // Trouver l'index du stage correspondant au score actuel
        var targetIndex = 0
        for (i, cfg) in Self.soloStages.enumerated() {
            if score >= cfg.minScore { targetIndex = i }
        }
        guard targetIndex > currentStageIndex else { return }
        // Nouveau stage atteint
        let newCfg = Self.soloStages[targetIndex]
        currentStageIndex = targetIndex
        refreshBombHudIcon()   // mise à jour icône bombe → nuke si stage ≥ 2
        childNode(withName: Self.stageBadgeNodeName)?.isHidden = true  // masqué pendant la transition
        stopStageTimer()
        showTransitionOverlay(stageLevelText: newCfg.levelText,
                              line1: newCfg.overlayLine1,
                              line2: newCfg.overlayLine2) { [weak self] in
            // Changement de musique APRÈS disparition de l'overlay (évite la superposition avec transition.wav).
            BlomixMusicPlayer.shared.switchToFile(newCfg.musicFilename)
            self?.refreshStageBadge()
            self?.restartStageTimer()
        }
    }

    /// Lance le Stage 1 overlay au démarrage d'une partie solo, puis démarre le timer.
    private func startStagedSoloSession() {
        guard isInStagedSoloMode else { return }
        ensureStageTimerHUD()
        layoutStageTimerHUD()
        let cfg = Self.soloStages[0]
        showTransitionOverlay(stageLevelText: cfg.levelText,
                              line1: cfg.overlayLine1,
                              line2: cfg.overlayLine2) { [weak self] in
            guard let self else { return }
            // Stage 1 = piste de base déjà en cours. On la reconfirme pour le cas d'une
            // partie lancée après une session PvP ou un tutoriel.
            BlomixMusicPlayer.shared.switchToFile(cfg.musicFilename)
            self.ensureStageBadge()
            self.layoutStageBadge()
            self.refreshStageBadge()
            self.restartStageTimer()
        }
    }

    // MARK: - Transition overlay (réutilisable)

    /// Retourne une `SKAction` qui, pendant `slideDuration`, lit la position scène de `trackedNode`
    /// toutes les 0.04 s et dépose des petits cercles de couleur qui restent sur place et se fondent.
    /// Identique à `makeTrailSpawnAction` pour les blox, adapté au déplacement horizontal.
    /// - `movingRight` : true = nœud vient de la gauche, false = vient de la droite.
    private func makeTextSlideTrailAction(
        slideDuration: TimeInterval,
        color: SKColor,
        trackedNode: SKNode,
        movingRight: Bool
    ) -> SKAction {
        let interval: TimeInterval = 0.04
        let count = max(1, Int((slideDuration / interval).rounded()))
        // Trois lignes de traîne verticales (centrale + haut + bas), comme pour les blox.
        let vertOffsets: [CGFloat] = [0, -9, 9]
        // Décalage horizontal derrière le déplacement pour "peupler" le sillage.
        let behindSign: CGFloat = movingRight ? -1 : 1

        var steps: [SKAction] = []
        for _ in 0..<count {
            steps.append(SKAction.wait(forDuration: interval))
            steps.append(SKAction.run { [weak self, weak trackedNode] in
                guard let self, let node = trackedNode else { return }
                // Position du nœud en coordonnées scène (overlayNode est à l'origine).
                let pos = node.position

                for (idx, yOff) in vertOffsets.enumerated() {
                    let radius: CGFloat = idx == 0
                        ? CGFloat.random(in: 1.8...3.0)   // ligne centrale, plus épaisse
                        : CGFloat.random(in: 1.0...2.0)   // lignes latérales, plus fines
                    let dot = SKShapeNode(circleOfRadius: radius)
                    dot.fillColor   = color
                    dot.strokeColor = .clear
                    dot.alpha       = 0.9
                    dot.zPosition   = 301
                    dot.position    = CGPoint(
                        x: pos.x + behindSign * CGFloat.random(in: 0...8) + CGFloat.random(in: -3...3),
                        y: pos.y + yOff + CGFloat.random(in: -4...4)
                    )
                    self.addChild(dot)
                    dot.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.38),
                        SKAction.removeFromParent(),
                    ]))
                }
                // 4 micro-paillettes dispersées autour du sillage.
                for _ in 0..<4 {
                    let micro = SKShapeNode(circleOfRadius: 1.0)
                    micro.fillColor   = color
                    micro.strokeColor = .clear
                    micro.alpha       = 0.9
                    micro.zPosition   = 301
                    micro.position    = CGPoint(
                        x: pos.x + behindSign * CGFloat.random(in: 0...20) + CGFloat.random(in: -8...8),
                        y: pos.y + CGFloat.random(in: -15...15)
                    )
                    self.addChild(micro)
                    micro.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.38),
                        SKAction.removeFromParent(),
                    ]))
                }
            })
        }
        return SKAction.sequence(steps)
    }

    /// Affiche un overlay de transition cinématique :
    /// `line1` arrive de la gauche, `line2` arrive de la droite, les deux convergent vers le centre.
    /// Après 1 s de pause l'overlay disparaît en fondu, puis `completion` est appelé.
    /// Overlay de transition cinématique.
    /// - `stageLevelText` non-nil → variante "stage" : "Level" + chiffre/texte + 2 lignes d'infos.
    /// - `stageLevelText` nil      → variante "texte seul" : line1 glisse de gauche, line2 de droite.
    private func showTransitionOverlay(levelPrefix: String = "Level",
                                       stageLevelText: String? = nil,
                                       line1: String, line2: String,
                                       completion: @escaping () -> Void) {
        // Bloque toute saisie pendant la durée de l'overlay (empêche de poser le 10ème blox
        // pendant que l'overlay masque le preview strip).
        isProcessing = true
        soundBank.play(.transition)
        let overlayNode = SKNode()
        overlayNode.name      = "transitionOverlay"
        overlayNode.zPosition = 300
        addChild(overlayNode)

        // ── Fond semi-transparent ────────────────────────────────────
        let dim = SKSpriteNode(color: .black, size: size)
        dim.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        dim.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.alpha       = 0
        dim.zPosition   = 0
        overlayNode.addChild(dim)
        dim.run(SKAction.fadeAlpha(to: 0.52, duration: 0.20))

        let centerX    = size.width  / 2
        let slideIn:  TimeInterval = 0.45
        let pause:    TimeInterval = 1.0
        let fadeOut:  TimeInterval = 0.35
        let maxW:      CGFloat = size.width - 48

        // Couleurs du skin joueur (fallback si skin non chargé).
        let yellowColor = BlomixSkinCatalog.shared.bloxSKColor(forNormalizedKey: "yellow")
                       ?? SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        let outlineColor = BlomixSkinCatalog.shared.bloxSKColor(forNormalizedKey: "orange")
                        ?? SKColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1)

        func makeOutlinedLabel(_ text: String, fontSize: CGFloat) -> SKLabelNode {
            let uiFont = UIFont(name: Self.customUIFontPostScriptName, size: fontSize)
                      ?? UIFont.boldSystemFont(ofSize: fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            uiFont,
                .foregroundColor: yellowColor,
                .strokeColor:     outlineColor,
                .strokeWidth:     -4.5,
            ]
            let lbl = SKLabelNode(attributedText: NSAttributedString(string: text, attributes: attrs))
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode   = .center
            lbl.numberOfLines           = 1
            lbl.preferredMaxLayoutWidth = maxW
            lbl.zPosition               = 1
            return lbl
        }

        if let levelText = stageLevelText {
            // ── Variante STAGE : "Level" + numéro/mot + 2 lignes d'infos ──────
            let levelFontSize: CGFloat = 34
            let numFontSize:   CGFloat = 76
            let infoFontSize:  CGFloat = 26

            // Layout vertical centré légèrement au-dessus du milieu.
            let blockCenterY = size.height / 2 + 18
            let levelLabelY  = blockCenterY + numFontSize * 0.55 + levelFontSize * 0.45
            let numberY      = blockCenterY + 8
            let line1Y       = blockCenterY - numFontSize * 0.55 - infoFontSize * 0.8
            let line2Y       = line1Y - infoFontSize * 1.6

            // Groupe "Level" + numéro dans un SKNode pour animer ensemble.
            let headerNode = SKNode()
            headerNode.zPosition = 1

            let labelLevel = makeOutlinedLabel(levelPrefix, fontSize: levelFontSize)
            labelLevel.position = CGPoint(x: 0, y: levelLabelY - blockCenterY)
            headerNode.addChild(labelLevel)

            let labelNum = makeOutlinedLabel(levelText, fontSize: numFontSize)
            labelNum.position = CGPoint(x: 0, y: numberY - blockCenterY)
            headerNode.addChild(labelNum)

            headerNode.position = CGPoint(x: -size.width - 20, y: blockCenterY)
            overlayNode.addChild(headerNode)

            let infoLabel1 = makeOutlinedLabel(line1, fontSize: infoFontSize)
            infoLabel1.position = CGPoint(x: size.width * 2 + 20, y: line1Y)
            overlayNode.addChild(infoLabel1)

            let infoLabel2 = makeOutlinedLabel(line2, fontSize: infoFontSize)
            infoLabel2.position = CGPoint(x: -size.width - 20, y: line2Y)
            overlayNode.addChild(infoLabel2)

            let slideHeader = SKAction.moveTo(x: centerX, duration: slideIn)
            slideHeader.timingMode = .easeOut
            headerNode.run(slideHeader)

            let slide1 = SKAction.moveTo(x: centerX, duration: slideIn)
            slide1.timingMode = .easeOut
            infoLabel1.run(slide1)

            let slide2 = SKAction.moveTo(x: centerX, duration: slideIn)
            slide2.timingMode = .easeOut
            infoLabel2.run(slide2)

            // ── Traînées de particules dans le sillage du slide ──────────
            // headerNode  : vient de la gauche → movingRight = true
            headerNode.run(makeTextSlideTrailAction(
                slideDuration: slideIn, color: yellowColor,
                trackedNode: headerNode, movingRight: true))
            // infoLabel1  : vient de la droite → movingRight = false
            infoLabel1.run(makeTextSlideTrailAction(
                slideDuration: slideIn, color: yellowColor,
                trackedNode: infoLabel1, movingRight: false))
            // infoLabel2  : vient de la gauche → movingRight = true
            infoLabel2.run(makeTextSlideTrailAction(
                slideDuration: slideIn, color: yellowColor,
                trackedNode: infoLabel2, movingRight: true))

        } else {
            // ── Variante TEXTE (tuto) : deux lignes qui se croisent ──
            let fontSize:  CGFloat = 36
            let lineGap: CGFloat = fontSize * 2.8
            let centerY = size.height / 2 + lineGap / 2

            func makeLabel(_ text: String) -> SKLabelNode {
                let para = NSMutableParagraphStyle()
                para.alignment     = .center
                para.lineBreakMode = .byWordWrapping
                let uiFont = UIFont(name: Self.customUIFontPostScriptName, size: fontSize)
                          ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: uiFont, .foregroundColor: UIColor.white, .paragraphStyle: para,
                ]
                let lbl = SKLabelNode(attributedText: NSAttributedString(string: text, attributes: attrs))
                lbl.horizontalAlignmentMode = .center
                lbl.verticalAlignmentMode   = .center
                lbl.numberOfLines           = 0
                lbl.preferredMaxLayoutWidth = maxW
                lbl.zPosition               = 1
                return lbl
            }

            let label1 = makeLabel(line1)
            label1.position = CGPoint(x: -size.width - 20, y: centerY)
            overlayNode.addChild(label1)

            let label2 = makeLabel(line2)
            label2.position = CGPoint(x: size.width * 2 + 20, y: centerY - lineGap)
            overlayNode.addChild(label2)

            let slide1 = SKAction.moveTo(x: centerX, duration: slideIn)
            slide1.timingMode = .easeOut
            label1.run(slide1)

            let slide2 = SKAction.moveTo(x: centerX, duration: slideIn)
            slide2.timingMode = .easeOut
            label2.run(slide2)
        }

        // ── Séquence de sortie commune ────────────────────────────────
        overlayNode.run(
            SKAction.sequence([
                SKAction.wait(forDuration: slideIn + pause),
                SKAction.fadeAlpha(to: 0, duration: fadeOut),
                SKAction.run { [weak self] in
                    overlayNode.removeFromParent()
                    // Rétablit les saisies et rafraîchit le preview avant d'appeler
                    // la completion (qui peut relancer le timer, changer de badge, etc.)
                    self?.isProcessing = false
                    self?.refreshPendingBottomLinePreview()
                    completion()
                    _ = self
                },
            ])
        )
    }

    private func startTutorialGame() {
        // Marquer le tutoriel comme vu dès son démarrage.
        // Même si le joueur quitte l'app en cours de route, il ne sera plus re-déclenché
        // automatiquement au prochain lancement. Il reste accessible via le bouton "Tutoriel".
        UserDefaults.standard.hasSeenGameTutorial        = true
        UserDefaults.standard.hasSeenInteractiveTutorial = true

        // Préparer les flags avant tout appel à nextPlayableBlockForSession().
        isTutorialMode       = true
        tutorialStep         = .intro
        tutorialStepDrops    = 0
        tutorialBombUnlocked = false
        tutorialPriksShown   = false
        tutorialLineShown    = false
        tutorialBlockQueue   = buildTutorialBlockQueue()

        if isStartScreen {
            // Lancement direct depuis l'écran d'accueil.
            beginNewMatchFromStartScreen()
        } else {
            // Depuis une partie en cours : sauvegarder et reset.
            if !isGameOver && pvpCoordinator == nil {
                saveCurrentSoloGameState()
            }
            isStartScreen = true   // passe le guard de beginNewMatchFromStartScreen
            isGameOver    = false
            beginNewMatchFromStartScreen()
        }
        // Afficher le skip + l'overlay 1 après le fondu d'apparition du jeu.
        run(SKAction.wait(forDuration: 0.9)) { [weak self] in
            self?.showTutorialSkipButton()
            self?.showTutorialStepOverlay(for: .intro)
        }
    }

    // ── Machine à états ──────────────────────────────────────────────────────────

    /// Appelé après chaque avancement de file (queue) dans dropBlock.
    private func tutorialDidAdvanceBlockQueue() {
        tutorialStepDrops += 1

        // Détecter l'apparition du Brix comme currentBlock.
        if case .priks = currentBlock, !tutorialPriksShown,
           tutorialStep == .awaitingBrix || tutorialStep == .chainCelebration {
            tutorialPriksShown = true
            tutorialStep       = .brixIntro
            tutorialStepDrops  = 0
            run(SKAction.wait(forDuration: 0.5)) { [weak self] in
                self?.showTutorialStepOverlay(for: .brixIntro)
            }
            return
        }

        switch tutorialStep {
        case .intro:
            if tutorialStepDrops >= 2 {
                tutorialAdvanceTo(.chainPrompt)
            }
        case .freePlay:
            if tutorialStepDrops >= Self.tutorialFreePlayDropsNeeded {
                tutorialAdvanceTo(.bombIntro)
            }
        default:
            break
        }
    }

    /// Chaîne détectée pendant resolveChains().
    private func tutorialChainDetected() {
        guard tutorialStep == .chainPrompt else { return }
        tutorialAdvanceTo(.chainCelebration)
    }

    /// Priks décrémenté N→N−1 (pas encore à zéro).
    private func tutorialPriksDecremented() {
        guard tutorialStep == .brixIntro else { return }
        tutorialAdvanceTo(.brixCelebration)
    }

    /// Bombe lancée.
    private func tutorialBombDropped() {
        guard tutorialStep == .bombIntro else { return }
        tutorialAdvanceTo(.magixIntro)
    }

    private func tutorialAdvanceTo(_ step: TutorialStep) {
        tutorialStep      = step
        tutorialStepDrops = 0
        showTutorialStepOverlay(for: step)

        // Auto-dismiss des célébrations.
        switch step {
        case .chainCelebration:
            run(SKAction.wait(forDuration: 2.8)) { [weak self] in
                guard let self, self.tutorialStep == .chainCelebration else { return }
                self.dismissCurrentTutorialOverlay()
                self.tutorialStep     = .awaitingBrix
                self.tutorialStepDrops = 0
            }
        case .brixCelebration:
            run(SKAction.wait(forDuration: 2.8)) { [weak self] in
                guard let self, self.tutorialStep == .brixCelebration else { return }
                self.dismissCurrentTutorialOverlay()
                self.tutorialStep     = .freePlay
                self.tutorialStepDrops = 0
            }
        case .magixIntro:
            // Auto-dismiss après 3 s ; le tap est géré dans touchesBegan.
            run(SKAction.wait(forDuration: 3.0)) { [weak self] in
                guard let self, self.tutorialStep == .magixIntro else { return }
                self.tutorialAdvanceTo(.bombCelebration)
            }
        case .bombCelebration:
            run(SKAction.wait(forDuration: 3.0)) { [weak self] in
                guard let self, self.tutorialStep == .bombCelebration else { return }
                self.exitTutorial()
            }
        case .bombIntro:
            tutorialBombUnlocked = true
        default:
            break
        }
    }

    // ── Overlays ─────────────────────────────────────────────────────────────────

    private func showTutorialStepOverlay(for step: TutorialStep) {
        dismissCurrentTutorialOverlay()

        let bannerW: CGFloat = min(size.width - 48, 320)
        let cx = size.width / 2

        // Tous les overlays sont centrés sur la zone des 2e et 3e lignes du bas de la grille.
        let row2Y = scenePointCellCenter(row: GridLayout.bottomRowIndex - 1, column: 0).y
        let row3Y = scenePointCellCenter(row: GridLayout.bottomRowIndex - 2, column: 0).y
        let overlayY = (row2Y + row3Y) / 2

        let overlay = SKNode()
        overlay.name      = Self.tutorialOverlayName
        overlay.position  = CGPoint(x: cx, y: overlayY)
        overlay.zPosition = 200
        addChild(overlay)

        switch step {
        case .intro:
            buildSimpleOverlay(node: overlay, width: bannerW,
                               main: BlomixL10n.tutorialIntroText,
                               hint: nil,
                               showFingerAnim: true)

        case .chainPrompt:
            buildSimpleOverlay(node: overlay, width: bannerW,
                               main: BlomixL10n.tutorialChainPrompt,
                               hint: BlomixL10n.tutorialChainHint,
                               showChainImage: true)

        case .chainCelebration:
            buildCelebrationOverlay(node: overlay, width: bannerW,
                                    text: BlomixL10n.tutorialChainSuccess)

        case .brixIntro:
            buildSimpleOverlay(node: overlay, width: bannerW,
                               main: BlomixL10n.tutorialBrixPrompt,
                               hint: BlomixL10n.tutorialBrixHint)

        case .brixCelebration:
            buildCelebrationOverlay(node: overlay, width: bannerW,
                                    text: BlomixL10n.tutorialBrixSuccess)

        case .bombIntro:
            buildSimpleOverlay(node: overlay, width: bannerW,
                               main: BlomixL10n.tutorialBombPrompt,
                               hint: BlomixL10n.tutorialBombHint,
                               showBombImage: true)

        case .bombCelebration:
            buildCelebrationOverlay(node: overlay, width: bannerW,
                                    text: BlomixL10n.tutorialBombSuccess)

        case .magixIntro:
            buildMagixIntroOverlay(node: overlay, width: bannerW)

        case .awaitingBrix, .freePlay:
            overlay.removeFromParent()
            return
        }

        overlay.alpha = 0
        overlay.run(SKAction.fadeIn(withDuration: 0.35))
    }

    private func dismissCurrentTutorialOverlay() {
        childNode(withName: Self.tutorialOverlayName)?.removeFromParent()
    }

    // ── Builders d'overlays ──────────────────────────────────────────────────────

    private func buildSimpleOverlay(node: SKNode, width: CGFloat,
                                    main: String, hint: String?,
                                    showFingerAnim: Bool = false,
                                    showChainImage: Bool = false,
                                    showBombImage:  Bool = false) {
        let pad: CGFloat = 14
        let mainFont: CGFloat = 16
        let hintFont: CGFloat = 12
        let bombImageSize: CGFloat = 36
        let textWidth = width - pad * 2

        // Mesurer la hauteur réelle des textes (ils peuvent wrapper sur plusieurs lignes).
        let mainAttr = tutorialAttributedText(main, size: mainFont, bold: true)
        let mainLabelH = ceil(mainAttr.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil).height)

        var hintLabelH: CGFloat = 0
        if let hint {
            let hintAttr = tutorialAttributedText(hint, size: hintFont, bold: false)
            hintLabelH = ceil(hintAttr.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil).height)
        }

        var contentHeight: CGFloat = pad * 2 + mainLabelH + 4
        if hint != nil     { contentHeight += hintLabelH + 10 }
        if showChainImage  { contentHeight += 28 }
        if showFingerAnim  { contentHeight += 36 }
        if showBombImage   { contentHeight += bombImageSize + 8 }

        let bg = SKShapeNode(rectOf: CGSize(width: width, height: contentHeight), cornerRadius: 10)
        bg.fillColor   = UIColor(white: 0.08, alpha: 0.93)
        bg.strokeColor = UIColor(white: 1, alpha: 0.18)
        bg.lineWidth   = 0.5
        bg.zPosition   = 0
        node.addChild(bg)

        var curY: CGFloat = contentHeight / 2 - pad

        // Animation doigt (overlay 1)
        if showFingerAnim {
            let finger = SKLabelNode(text: "👆")
            finger.fontSize             = 24
            finger.verticalAlignmentMode = .top
            finger.position = CGPoint(x: 0, y: curY)
            finger.zPosition = 1
            node.addChild(finger)
            finger.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: -6, duration: 0.5),
                SKAction.moveBy(x: 0, y:  6, duration: 0.5),
            ])))
            curY -= 32
        }

        // Image chaîne de 5 blox bleus (overlay 2)
        if showChainImage {
            let chainNode = buildChainImageNode()
            chainNode.position = CGPoint(x: 0, y: curY - 10)
            chainNode.zPosition = 1
            node.addChild(chainNode)
            curY -= 28
        }

        // Sprite bombe animé (shader couleurs + halo + particules) + animation pulsée
        if showBombImage {
            let bombSize = CGSize(width: bombImageSize, height: bombImageSize)
            let bombSprite = Self.makeBombShaderSprite(size: bombSize)
            bombSprite.position  = CGPoint(x: 0, y: curY - bombImageSize / 2)
            bombSprite.zPosition = 1
            node.addChild(bombSprite)
            bombSprite.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.15, duration: 0.4),
                SKAction.scale(to: 1.0,  duration: 0.4),
            ])))
            curY -= bombImageSize + 8
        }

        // Texte principal — descend de sa hauteur réelle mesurée.
        let mainLabel = SKLabelNode()
        mainLabel.attributedText          = mainAttr
        mainLabel.numberOfLines           = 0
        mainLabel.preferredMaxLayoutWidth = textWidth
        mainLabel.verticalAlignmentMode   = .top
        mainLabel.position  = CGPoint(x: 0, y: curY)
        mainLabel.zPosition = 1
        node.addChild(mainLabel)
        curY -= mainLabelH + 10

        // Texte hint — positionné après la hauteur réelle du texte principal.
        if let hint {
            let hintLabel = SKLabelNode()
            hintLabel.attributedText          = tutorialAttributedText(hint, size: hintFont, bold: false)
            hintLabel.numberOfLines           = 0
            hintLabel.preferredMaxLayoutWidth = textWidth
            hintLabel.verticalAlignmentMode   = .top
            hintLabel.position  = CGPoint(x: 0, y: curY)
            hintLabel.zPosition = 1
            node.addChild(hintLabel)
        }
    }

    private func buildCelebrationOverlay(node: SKNode, width: CGFloat, text: String) {
        let h: CGFloat = 64
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: h), cornerRadius: 10)
        bg.fillColor   = UIColor(white: 0.08, alpha: 0.93)
        bg.strokeColor = UIColor(white: 1, alpha: 0.28)
        bg.lineWidth   = 0.5
        bg.zPosition   = 0
        node.addChild(bg)

        let label = SKLabelNode()
        label.attributedText = tutorialAttributedText(text, size: 17, bold: true)
        label.numberOfLines          = 0
        label.preferredMaxLayoutWidth = width - 20
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .center
        label.position  = .zero
        label.zPosition = 1
        node.addChild(label)

        // Petit pop-in
        node.setScale(0.85)
        node.run(SKAction.scale(to: 1.0, duration: 0.2))
    }

    /// Overlay Magix : 3 blocs animés (CHROMAX, CROSX, BRIXED) + texte "surprises".
    /// Tap ou auto-dismiss 3 s → `exitTutorial()`.
    private func buildMagixIntroOverlay(node: SKNode, width: CGFloat) {
        let pad: CGFloat        = 14
        let blockSize: CGFloat  = 30
        let blockGap: CGFloat   = 8
        let blocksRowH: CGFloat = blockSize + 10   // hauteur réservée à la rangée de blocs
        let mainFont: CGFloat   = 14

        // Mesurer la hauteur du texte.
        let textWidth = width - pad * 2
        let text = BlomixL10n.tutorialMagixIntro
        let mainAttr = tutorialAttributedText(text, size: mainFont, bold: false)
        let textH = ceil(mainAttr.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil).height)

        let contentH = pad * 2 + blocksRowH + 8 + textH

        // Fond.
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: contentH), cornerRadius: 10)
        bg.fillColor   = UIColor(white: 0.08, alpha: 0.93)
        bg.strokeColor = UIColor(white: 1, alpha: 0.18)
        bg.lineWidth   = 0.5
        bg.zPosition   = 0
        node.addChild(bg)

        var curY: CGFloat = contentH / 2 - pad

        // 3 blocs MAGIX animés (un par variante).
        let kinds: [MagixKind] = [.chromax, .crosx, .brixed, .scrumblx]
        let totalBlocksW = CGFloat(kinds.count) * blockSize + CGFloat(kinds.count - 1) * blockGap
        var blockX = -totalBlocksW / 2 + blockSize / 2
        let blockY = curY - blockSize / 2

        for kind in kinds {
            let sprite = Self.makeMagixShaderSprite(
                size: CGSize(width: blockSize, height: blockSize),
                kind: kind
            )
            sprite.position  = CGPoint(x: blockX, y: blockY)
            sprite.zPosition = 1
            node.addChild(sprite)
            blockX += blockSize + blockGap
        }
        curY -= blocksRowH + 8

        // Texte explicatif.
        let mainLabel = SKLabelNode()
        mainLabel.attributedText          = mainAttr
        mainLabel.numberOfLines           = 0
        mainLabel.preferredMaxLayoutWidth = textWidth
        mainLabel.verticalAlignmentMode   = .top
        mainLabel.position  = CGPoint(x: 0, y: curY)
        mainLabel.zPosition = 1
        node.addChild(mainLabel)

        // Léger pop-in identique aux célébrations.
        node.setScale(0.88)
        node.run(SKAction.scale(to: 1.0, duration: 0.2))
    }

    private func buildChainImageNode() -> SKNode {
        let container = SKNode()
        let blockSize: CGFloat = 18
        let gap: CGFloat = 3
        let total = 5
        let startX = -(CGFloat(total) * (blockSize + gap) - gap) / 2 + blockSize / 2
        let blueColor = BlomixSkinCatalog.shared.bloxSKColor(forNormalizedKey: "blue") ?? SKColor.systemBlue
        for i in 0..<total {
            let sq = SKShapeNode(rectOf: CGSize(width: blockSize, height: blockSize), cornerRadius: 3)
            sq.fillColor   = blueColor
            sq.strokeColor = UIColor(white: 1, alpha: 0.3)
            sq.lineWidth   = 0.5
            sq.position    = CGPoint(x: startX + CGFloat(i) * (blockSize + gap), y: 0)
            container.addChild(sq)
        }
        return container
    }

    private func tutorialAttributedText(_ text: String, size: CGFloat, bold: Bool) -> NSAttributedString {
        let weight: UIFont.Weight = bold ? .semibold : .regular
        let font = UIFont(name: Self.customUIFontPostScriptName, size: size)
                   ?? UIFont.systemFont(ofSize: size, weight: weight)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font:            font,
            .foregroundColor: UIColor.white,
            .paragraphStyle:  para,
        ])
    }

    // ── Bouton Skip ──────────────────────────────────────────────────────────────

    private func showTutorialSkipButton() {
        childNode(withName: Self.tutorialSkipBtnName)?.removeFromParent()

        let chipSize = CGSize(width: 80, height: 34)
        let chip = makeStartScreenButtonChip(
            chipName:  Self.tutorialSkipBtnName,
            labelName: Self.tutorialSkipBtnName + "_lbl",
            text:      BlomixL10n.tutorialSkip,
            chipSize:  chipSize,
            fontSize:  13
        )

        // Centre horizontal aligné sur la file de blocs (preview centré sur la largeur).
        let chipX = size.width / 2
        // Vertical : juste sous le label caption de la queue ; fallback en bas d'écran si absent.
        let captionY = (childNode(withName: Self.upcomingQueueCaptionLabelName)?.position.y)
                    ?? (size.height * 0.12)
        let chipY = captionY - chipSize.height - 8

        chip.position  = CGPoint(x: chipX, y: chipY)
        chip.zPosition = 210
        addChild(chip)
    }

    private func hideTutorialSkipButton() {
        childNode(withName: Self.tutorialSkipBtnName)?.removeFromParent()
    }

    // ── Sortie ───────────────────────────────────────────────────────────────────

    private func exitTutorial() {
        UserDefaults.standard.hasSeenInteractiveTutorial = true
        isTutorialMode       = false
        tutorialBombUnlocked = false
        dismissCurrentTutorialOverlay()
        hideTutorialSkipButton()
        // Overlay de fin de tutoriel, puis retour accueil.
        showTransitionOverlay(
            line1: BlomixL10n.transitionTutorialEndTitle,
            line2:  BlomixL10n.transitionTutorialEndSubtitle
        ) { [weak self] in
            self?.unwindToStartScreen(restoreSave: true)
        }
    }

    /// Overlay informatif une seule fois lors de la 1ère ligne qui monte, sans interrompre le jeu.
    private func showTutorialLineArrivalOverlay() {
        childNode(withName: Self.tutorialLineOverlayName)?.removeFromParent()

        let bannerW: CGFloat = min(size.width - 48, 320)
        let overlay = SKNode()
        let row2Y = scenePointCellCenter(row: GridLayout.bottomRowIndex - 1, column: 0).y
        let row3Y = scenePointCellCenter(row: GridLayout.bottomRowIndex - 2, column: 0).y
        overlay.name      = Self.tutorialLineOverlayName
        overlay.position  = CGPoint(x: size.width / 2, y: (row2Y + row3Y) / 2)
        overlay.zPosition = 205
        addChild(overlay)

        buildCelebrationOverlay(node: overlay, width: bannerW, text: BlomixL10n.tutorialLineArrival)

        overlay.alpha = 0
        overlay.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent(),
        ]))
    }

    private func touchHitsTutorialSkipButton(_ point: CGPoint) -> Bool {
        guard let btn = childNode(withName: Self.tutorialSkipBtnName) else { return false }
        return btn.calculateAccumulatedFrame().contains(point)
    }

    // MARK: - In-app update banner

    /// Lance la vérification (une seule fois par session) et affiche la bannière si une MAJ est dispo.
    private func checkAndShowUpdateBannerIfNeeded(in overlay: SKNode) {
        guard !didCheckForUpdate else { return }
        didCheckForUpdate = true
        Task { @MainActor [weak self, weak overlay] in
            guard let self, let overlay, overlay.parent != nil else { return }
            guard let info = await Self.fetchAppStoreUpdateInfo() else { return }
            self.updateStoreURL = info.storeURL
            self.showUpdateBanner(version: info.version, in: overlay)
        }
    }

    /// Appelle l'iTunes Lookup API et retourne (version, URL) si une version plus récente est dispo.
    private static func fetchAppStoreUpdateInfo() async -> (version: String, storeURL: URL)? {
        guard let apiURL = URL(string: "https://itunes.apple.com/lookup?bundleId=blomig.BLOMIX") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: apiURL) else { return nil }
        guard let json        = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results      = json["results"] as? [[String: Any]],
              let first        = results.first,
              let storeVersion = first["version"]      as? String,
              let storeURLStr  = first["trackViewUrl"]  as? String,
              let storeURL     = URL(string: storeURLStr) else { return nil }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard storeVersion.compare(currentVersion, options: .numeric) == .orderedDescending else { return nil }
        return (storeVersion, storeURL)
    }

    /// Ajoute la bannière de mise à jour en bas de l'overlay de l'écran d'accueil.
    private func showUpdateBanner(version: String, in overlay: SKNode) {
        overlay.childNode(withName: Self.updateBannerName)?.removeFromParent()

        let bannerW: CGFloat = size.width - 48
        let bannerH: CGFloat = 54
        let bannerY: CGFloat = 26

        let banner = SKNode()
        banner.name      = Self.updateBannerName
        banner.position  = CGPoint(x: size.width / 2, y: bannerY)
        banner.zPosition = 10
        overlay.addChild(banner)

        let bg = SKShapeNode(rectOf: CGSize(width: bannerW, height: bannerH), cornerRadius: 10)
        bg.fillColor   = BlomixUIDestinationButtonStyle.startScreenChipFillSKColor
        bg.strokeColor = BlomixUIDestinationButtonStyle.borderColor
        bg.lineWidth   = BlomixUIDestinationButtonStyle.hairlineBorderWidth
        bg.zPosition   = 0
        banner.addChild(bg)

        let textLabel = SKLabelNode(text: BlomixL10n.updateBannerAvailable(version))
        textLabel.fontName              = Self.customUIFontPostScriptName
        textLabel.fontSize              = 15
        textLabel.fontColor             = .white
        textLabel.horizontalAlignmentMode = .left
        textLabel.verticalAlignmentMode   = .center
        textLabel.position  = CGPoint(x: -bannerW / 2 + 16, y: 0)
        textLabel.zPosition = 1
        banner.addChild(textLabel)

        let closeLabel = SKLabelNode(text: "✕")
        closeLabel.name                 = Self.updateBannerCloseName
        closeLabel.fontName             = Self.customUIFontPostScriptName
        closeLabel.fontSize             = 16
        closeLabel.fontColor            = UIColor(white: 1, alpha: 0.55)
        closeLabel.horizontalAlignmentMode = .center
        closeLabel.verticalAlignmentMode   = .center
        closeLabel.position  = CGPoint(x: bannerW / 2 - 20, y: 0)
        closeLabel.zPosition = 1
        banner.addChild(closeLabel)

        // Animation de "respiration" : oscillation subtile de scale, démarre après le fade-in.
        let breathe = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.04, duration: 1.1),
            SKAction.scale(to: 1.00, duration: 1.1),
        ]))
        // Les deux phases ont un timing doux pour une pulsation naturelle.
        let fadeInThenBreathe = SKAction.sequence([
            SKAction.wait(forDuration: 0.6),
            SKAction.fadeIn(withDuration: 0.4),
            SKAction.run { banner.run(breathe, withKey: "breathe") },
        ])

        banner.alpha = 0
        banner.run(fadeInThenBreathe)
    }

    // MARK: - Entrées utilisateur (tactile)

    /// Tap sur la **grille** : pose dans la colonne touchée (comme un clic colonne dans le canvas web).
    /// Remonte la hiérarchie depuis le nœud touché pour trouver un `BlomixSKButtonNode`.
    private func blomixButtonAtPoint(_ point: CGPoint) -> BlomixSKButtonNode? {
        var node: SKNode? = atPoint(point)
        while let n = node {
            if let btn = n as? BlomixSKButtonNode { return btn }
            node = n.parent
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Mémorisé dès le début ; utilisé pour la détection de sortie de zone dans touchesMoved.
        pendingButtonTouchOrigin = location

        // Animation press sur tout BlomixSKButtonNode touché.
        if let btn = blomixButtonAtPoint(location) {
            btn.animatePressed()
            lastPressedSKButton = btn
        }

        // Bouton "Passer" du tutoriel : priorité absolue, visible en permanence.
        if isTutorialMode && touchHitsTutorialSkipButton(location) {
            pendingButtonAction = { [weak self] in self?.exitTutorial() }
            return
        }

        // Overlay Magix (étape 4c du tutoriel) : tap n'importe où → écran "Tu sais tout".
        if isTutorialMode && tutorialStep == .magixIntro {
            pendingButtonAction = { [weak self] in
                guard let self, self.tutorialStep == .magixIntro else { return }
                self.tutorialAdvanceTo(.bombCelebration)
            }
            return
        }

        // Dialog de confirmation "Quitter" — intercepte tout le reste tant qu'elle est visible.
        if childNode(withName: Self.quitConfirmOverlayName) != nil {
            let tappedBtn = blomixButtonAtPoint(location)
            if tappedBtn?.name == Self.quitConfirmBtnQuitName {
                pendingButtonAction = { [weak self] in
                    guard let self else { return }
                    self.dismissQuitConfirmOverlay()
                    ScoreManager.shared.recordGameScore(self.score)
                    self.unwindToStartScreen()
                }
            } else {
                // Tap sur "Annuler" ou hors du panneau → fermeture uniquement.
                pendingButtonAction = { [weak self] in self?.dismissQuitConfirmOverlay() }
            }
            return
        }

        if isStartScreen {
            // Bannière de mise à jour : "✕" ferme, le reste ouvre l'App Store.
            if let overlay = childNode(withName: Self.startScreenOverlayName),
               let banner  = overlay.childNode(withName: Self.updateBannerName) {
                let bannerFrame = banner.calculateAccumulatedFrame()
                if bannerFrame.contains(location) {
                    if location.x > bannerFrame.maxX - 44 {
                        banner.removeFromParent()
                    } else if let url = updateStoreURL {
                        UIApplication.shared.open(url)
                    }
                    return
                }
            }

            if touchHitsStartScreenZenButton(location) {
                pendingButtonAction = { [weak self] in self?.beginZenModeFromStartScreen() }
                return
            }
            if touchHitsStartScreenScoresButton(location) {
                pendingButtonAction = { [weak self] in self?.showLeaderboard() }
                return
            }
            if touchHitsStartScreenSettingsButton(location) {
                pendingButtonAction = { [weak self] in self?.showSettings() }
                return
            }
            if touchHitsStartScreenPvPButton(location) {
                pendingButtonAction = { [weak self] in self?.showPvPLobby() }
                return
            }
            if touchHitsStartScreenRulesButton(location) {
                pendingButtonAction = { [weak self] in self?.startTutorialGameWithIntro() }
                return
            }
            if touchHitsStartButton(location) {
                pendingButtonAction = { [weak self] in self?.beginNewMatchFromStartScreen() }
            }
            return
        }

        if isGameOver {
            // Fermer l'overlay du pire coup si ouvert.
            if childNode(withName: Self.worstMistakeOverlayName) != nil {
                childNode(withName: Self.worstMistakeOverlayName)?.removeFromParent()
                return
            }
            if touchHitsGameOverRestartButton(location) {
                pendingButtonAction = { [weak self] in self?.returnToStartScreenFromGameOver() }
                return
            }
            if touchHitsGameOverLeaderboardButton(location) {
                pendingButtonAction = { [weak self] in self?.showLeaderboard() }
                return
            }
            if touchHitsGameOverWorstMoveButton(location) {
                pendingButtonAction = { [weak self] in self?.showWorstMistakeOverlay() }
                return
            }
            return
        }

        if gameOverflowMenuDropdownIsOpen() {
            if touchHitsOverflowMenuItem(named: Self.bottomMenuNewGameName, scenePoint: location) {
                closeGameOverflowMenu()
                pendingButtonAction = { [weak self] in self?.returnToStartScreenFromNewGameButton() }
                return
            }
            if touchHitsOverflowMenuItem(named: Self.bottomMenuScoresName, scenePoint: location) {
                closeGameOverflowMenu()
                pendingButtonAction = { [weak self] in self?.showLeaderboard() }
                return
            }
            if touchHitsOverflowMenuItem(named: Self.bottomMenuRulesName, scenePoint: location) {
                closeGameOverflowMenu()
                pendingButtonAction = { [weak self] in
                    guard let self else { return }
                    if !self.isStartScreen {
                        if self.pvpCoordinator != nil {
                            // En PvP : on ne peut pas lancer le tutoriel sans casser la session réseau.
                            // On affiche le tutoriel paginé (lecture seule) à la place.
                            self.showRules()
                        } else {
                            // Solo : sauvegarder AVANT que unwindToStartScreen ne réinitialise le modèle.
                            self.saveCurrentSoloGameState()
                            self.pendingTutorialStart = true
                            self.unwindToStartScreen()
                        }
                    } else {
                        self.startTutorialGameWithIntro()
                    }
                }
                return
            }
            if touchHitsOverflowMenuItem(named: Self.bottomMenuSettingsName, scenePoint: location) {
                closeGameOverflowMenu()
                pendingButtonAction = { [weak self] in self?.showSettings() }
                return
            }
            if touchHitsOverflowMenuItem(named: Self.bottomMenuMultiplayerName, scenePoint: location) {
                closeGameOverflowMenu()
                pendingButtonAction = { [weak self] in self?.showPvPLobby() }
                return
            }
            if touchHitsGameMenuIcon(scenePoint: location) {
                pendingButtonAction = { [weak self] in self?.toggleGameOverflowMenu() }
                return
            }
            closeGameOverflowMenu()
            return
        }

        if touchHitsGameMenuIcon(scenePoint: location) {
            pendingButtonAction = { [weak self] in self?.toggleGameOverflowMenu() }
            return
        }

        guard !isProcessing else { return }
        stopPreviewBreathing()

        if touchHitsBombHUD(location) {
            pendingButtonAction = { [weak self] in self?.toggleBombMode() }
            return
        }

        // En mode bombe : appui sur la grille → démarrage de la visée (overlay blast) ; lâcher → placement.
        if isBombMode {
            if let cell = gridCellAtScenePoint(location) {
                bombAimTouchIsLive = true
                bombAimTargetCell  = GridAddress(row: cell.row, col: cell.col)
                showBombBlastPreview(row: cell.row, col: cell.col)
            }
            return
        }

        guard let column = columnAtScenePointOrLaunchZone(location) else { return }
        // Arme le tracking ghost ; le drop effectif se fait dans touchesEnded.
        beginGhostTracking(column: column)
    }

    /// Déplacement du doigt pendant le contact.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Sortie de zone bouton : annule l'action différée et relâche l'animation.
        if pendingButtonAction != nil {
            let exited: Bool
            if let btn = lastPressedSKButton {
                // BlomixSKButtonNode : le doigt n'est plus sur ce bouton.
                exited = blomixButtonAtPoint(location) !== btn
            } else if let origin = pendingButtonTouchOrigin {
                // Bouton plain (overflow menu, bombe…) : distance > 50 pt de l'origine.
                let dx = location.x - origin.x, dy = location.y - origin.y
                exited = (dx * dx + dy * dy) > 2500   // 50² = 2500
            } else {
                exited = false
            }
            if exited {
                pendingButtonAction = nil
                pendingButtonTouchOrigin = nil
                lastPressedSKButton?.animateReleased()
                lastPressedSKButton = nil
            }
            return  // Pas de tracking ghost/bombe pendant qu'un bouton est appuyé (ou vient d'être annulé).
        }

        // Visée bombe : mise à jour de l'overlay si la case change.
        if bombAimTouchIsLive {
            if let cell = gridCellAtScenePoint(location) {
                let addr = GridAddress(row: cell.row, col: cell.col)
                if addr != bombAimTargetCell {
                    bombAimTargetCell = addr
                    showBombBlastPreview(row: cell.row, col: cell.col)
                }
            } else {
                // Doigt sorti de la grille : overlay masqué, visée annulée.
                bombAimTargetCell = nil
                hideBombBlastPreview()
            }
            return
        }

        // Ghost drop blox/brix : mise à jour de la colonne.
        guard ghostTouchIsLive else { return }
        // On accepte la grille ET la zone de lancement sous la grille.
        // Si le doigt sort de cette zone étendue, on garde la dernière colonne valide.
        if let column = columnAtScenePointOrLaunchZone(location) {
            moveGhostToColumn(column)
        }
    }

    /// Fin du contact (lift) : place la bombe ou pose le bloc selon le mode actif.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Animation release sur le bouton SpriteKit précédemment appuyé.
        lastPressedSKButton?.animateReleased()
        lastPressedSKButton = nil

        // Exécuter l'action différée du bouton SpriteKit (fire on release) + son de tap.
        if let action = pendingButtonAction {
            pendingButtonAction = nil
            pendingButtonTouchOrigin = nil
            playMatchSound(.connectE)
            action()
            return
        }

        // Lâcher en mode visée bombe : placement effectif si une case est ciblée.
        if bombAimTouchIsLive {
            let target = bombAimTargetCell
            cancelBombAim()
            if let addr = target {
                guard !isProcessing else { return }
                placeBombAtCell(row: addr.row, col: addr.col)
            }
            return
        }
        guard ghostTouchIsLive else { return }
        let col = ghostPreviewColumn
        cancelGhostPreview()
        guard !isProcessing else { return }
        // Analyse : enregistrer le choix du joueur (utilise le lookahead proactif).
        if let c = col { recordMoveChoice(column: c) }
        dropBlock(usingColumn: col)
    }

    /// Annulation (interruption système, alerte, etc.).
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Annulation : l'action ne s'exécute pas.
        pendingButtonAction = nil
        pendingButtonTouchOrigin = nil
        lastPressedSKButton?.animateReleased()
        lastPressedSKButton = nil
        cancelGhostPreview()
        cancelBombAim()
    }

    // MARK: - Multijoueur PvP (optionnel ; `pvpCoordinator == nil` → tout le solo inchangé)

    private func blomixPvP_teardown() {
        // Reprend le polling de défi entrant si le joueur était disponible.
        BlomixAvailablePlayersManager.shared.setActiveMatch(false)
        pvpMatchSetupInProgress = false
        pvpNeedsDecadeLineAfterAttackInjection = false
        didFinalizePvPEloForCurrentMatch = false
        pvpOpponentDisplayName = nil
        pvpLastEloResult = nil
        pvpPresentedResultViewController = nil
        pvpRemoteBoardFillDepth = 0
        pvpRemoteScore = 0
        childNode(withName: Self.pvpConnectingOverlayName)?.removeFromParent()
        childNode(withName: Self.hudPvPTurnTimerName)?.removeFromParent()
        childNode(withName: Self.hudPvPOpponentName)?.removeFromParent()
        childNode(withName: Self.pvpRemoteFillContainerName)?.removeFromParent()
        pvpCoordinator?.tearDown()
        pvpCoordinator = nil
    }

    private func showPvPLobby() {
        let lobby = BlomixPvPLobbyViewController()
        lobby.modalPresentationStyle = .overFullScreen
        lobby.modalTransitionStyle = .crossDissolve
        lobby.onMatch = { [weak self] match in
            self?.beginPvPWithMatch(match)
        }
        presentFullScreenModal(lobby)
    }

    /// Appelé depuis le lobby Game Center une fois le `GKMatch` prêt.
    func beginPvPWithMatch(_ match: GKMatch) {
        // Si une partie est déjà en cours (handshake terminé), on ignore le nouveau match
        // et on le raccroche proprement pour éviter un double-coordinator / FastSyncTransportError.
        if let active = pvpCoordinator, active.isGameActive {
            print("[PvP] beginPvPWithMatch ignoré : partie active en cours.")
            match.disconnect()
            return
        }
        // Protège contre la double-entrée (AutoSearcher.onMatch + lobby.onMatch déclenchés
        // simultanément pour le même match → second appel ignoré, overlay non orphelin).
        if pvpMatchSetupInProgress {
            print("[PvP] beginPvPWithMatch ignoré : setup déjà en cours.")
            return
        }
        // Arrête toute recherche automatique encore en cours sur tous les appareils
        // (cas : AutoSearcher + invite simultanés → deux GKMatch créés).
        BlomixPvPAutoSearcher.shared.stopSearching()

        // Teardown AVANT la sauvegarde : blomixPvP_teardown() met pvpCoordinator = nil, ce qui
        // permet à saveCurrentSoloGameState() de passer son guard `pvpCoordinator == nil`.
        // Cas traité : un coordinateur précédent (handshake incomplet, isGameActive == false) existait
        // encore et bloquait silencieusement la sauvegarde dans l'ancien ordre.
        // La grille en mémoire n'est pas encore réinitialisée ici (c'est blomixPvP_onHandshakeCompleteRestartBoard
        // qui le fait) : on capture donc bien l'état solo courant.
        blomixPvP_teardown()
        pvpMatchSetupInProgress = true
        saveCurrentSoloGameState()
        pvpNeedsDecadeLineAfterAttackInjection = false
        didFinalizePvPEloForCurrentMatch = false
        removeAllActions()
        childNode(withName: Self.gameOverOverlayName)?.removeFromParent()
        childNode(withName: Self.fallingSpriteName)?.removeFromParent()
        for col in 0..<GridLayout.columnCount {
            childNode(withName: "\(Self.randomLineRisingSpritePrefix)\(col)")?.removeFromParent()
        }
        childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()

        // Signale au manager que le polling de défi doit être suspendu.
        BlomixAvailablePlayersManager.shared.setActiveMatch(true)
        pvpCoordinator = BlomixPvPMatchCoordinator(match: match)
        pvpOpponentDisplayName = match.players.first?.displayName ?? BlomixL10n.pvpUnknownOpponent
        pvpLastEloResult = nil
        pvpCoordinator?.attach(to: self)
        blomixPvP_showConnectingOverlayIfNeeded()
    }

    private func blomixPvP_showConnectingOverlayIfNeeded() {
        childNode(withName: Self.pvpConnectingOverlayName)?.removeFromParent()

        // Conteneur parent : retirer le conteneur supprime automatiquement tous les enfants.
        let container = SKNode()
        container.name = Self.pvpConnectingOverlayName
        container.zPosition = 170
        addChild(container)

        // Fond semi-transparent — même opacité que l'overlay de stage.
        let dim = SKSpriteNode(color: .black, size: size)
        dim.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        dim.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.alpha       = 0
        dim.zPosition   = 0
        container.addChild(dim)
        dim.run(SKAction.fadeAlpha(to: 0.52, duration: 0.20))

        let centerX:   CGFloat       = size.width / 2
        let slideIn:   TimeInterval  = 0.45
        let phraseFontSize: CGFloat  = 22
        let maxW:      CGFloat       = size.width - 80

        // Couleurs du skin joueur.
        let pvpYellowColor  = BlomixSkinCatalog.shared.bloxSKColor(forNormalizedKey: "yellow")
                           ?? SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        let pvpOutlineColor = BlomixSkinCatalog.shared.bloxSKColor(forNormalizedKey: "orange")
                           ?? SKColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1)

        // ── En-tête "P vs P" (remplace l'image) — glisse depuis la gauche ──────────
        let pvpFontSize: CGFloat = 72
        let blockCenterY = size.height / 2 + 40
        let labelY       = blockCenterY - pvpFontSize * 0.7 - phraseFontSize * 0.8

        let pvpHeaderFont = UIFont(name: Self.customUIFontPostScriptName, size: pvpFontSize)
                         ?? UIFont.boldSystemFont(ofSize: pvpFontSize)
        let pvpHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font:            pvpHeaderFont,
            .foregroundColor: pvpYellowColor,
            .strokeColor:     pvpOutlineColor,
            .strokeWidth:     -4.5,
        ]
        let pvpTitleNode = SKLabelNode(
            attributedText: NSAttributedString(string: "P vs P", attributes: pvpHeaderAttrs))
        pvpTitleNode.horizontalAlignmentMode = .center
        pvpTitleNode.verticalAlignmentMode   = .center
        pvpTitleNode.numberOfLines           = 1
        pvpTitleNode.zPosition               = 1
        pvpTitleNode.position = CGPoint(x: -size.width - 20, y: blockCenterY)
        container.addChild(pvpTitleNode)

        let slidePvP = SKAction.moveTo(x: centerX, duration: slideIn)
        slidePvP.timingMode = .easeOut
        pvpTitleNode.run(slidePvP)

        // Traînée de particules dans le sillage de "P vs P" (vient de la gauche).
        pvpTitleNode.run(makeTextSlideTrailAction(
            slideDuration: slideIn, color: pvpYellowColor,
            trackedNode: pvpTitleNode, movingRight: true))

        // ── Texte tournant (phrases d'attente) — glisse depuis la droite ─────────
        let label = SKLabelNode()
        label.fontName                = Self.customUIFontPostScriptName
        label.fontSize                = phraseFontSize
        label.fontColor               = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .center
        label.numberOfLines           = 0
        label.lineBreakMode           = .byWordWrapping
        label.preferredMaxLayoutWidth = maxW
        label.zPosition               = 1

        let phrases = BlomixL10n.pvpWaitingPhrases.filter { !$0.isEmpty }
        label.text     = phrases.first ?? BlomixL10n.pvpMatchFoundLaunching
        label.position = CGPoint(x: size.width * 2 + 20, y: labelY)
        container.addChild(label)

        let slideLabel = SKAction.moveTo(x: centerX, duration: slideIn)
        slideLabel.timingMode = .easeOut
        label.run(slideLabel)

        // Rotation des phrases après le slide-in.
        guard phrases.count > 1 else { return }
        let phraseDur: TimeInterval = 1.8
        let fadeDur:   TimeInterval = 0.28

        var steps: [SKAction] = [
            // Attente initiale : laisse la première phrase visible le temps du slide + une durée complète.
            SKAction.wait(forDuration: slideIn + phraseDur - fadeDur),
        ]
        for i in 1...phrases.count {       // boucle infinie : index modulo
            let phrase = phrases[i % phrases.count]
            steps += [
                SKAction.fadeOut(withDuration: fadeDur),
                SKAction.run { label.text = phrase },
                SKAction.fadeIn(withDuration: fadeDur),
                SKAction.wait(forDuration: phraseDur - fadeDur * 2),
            ]
        }
        label.run(SKAction.repeatForever(SKAction.sequence(steps)))
    }

    // MARK: - Wrappers publics pour l'overlay PvP de préparation

    /// Affiche immédiatement l'overlay PvP (image + textes rotatifs) dès l'acceptation du défi,
    /// **avant** que GameKit ait terminé de trouver/connecter le match.
    /// Appelé depuis `GameViewController.acceptIncomingChallenge()`.
    func showPvPWaitingForMatchOverlay() {
        blomixPvP_showConnectingOverlayIfNeeded()
    }

    /// Retire l'overlay de préparation PvP (cas d'échec : timeout, erreur réseau…).
    /// Appelé depuis `GameViewController` quand le matchmaking échoue avant `beginPvPWithMatch`.
    func hidePvPWaitingForMatchOverlay() {
        blomixPvP_removeConnectingOverlay()
    }

    private func blomixPvP_removeConnectingOverlay() {
        childNode(withName: Self.pvpConnectingOverlayName)?.removeFromParent()
    }

    /// Fait disparaître l'overlay de connexion en fondu, puis le retire.
    /// Utilisé après la fin du handshake pour couvrir l'animation de fermeture du lobby VC (~0.3 s).
    private func blomixPvP_fadeOutAndRemoveConnectingOverlay() {
        guard let overlay = childNode(withName: Self.pvpConnectingOverlayName) else { return }
        overlay.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.25),
            SKAction.fadeOut(withDuration: 0.30),
            SKAction.removeFromParent(),
        ]))
    }

    func blomixPvP_refreshPendingAttackLinePreview() {
        // ignoreProcessing: true → le strip apparaît même pendant une chaîne en cours,
        // garantissant que le joueur voit toujours l'attaque adverse avant son prochain coup.
        refreshPendingBottomLinePreview(ignoreProcessing: true)
    }

    /// Flash du score + envol de blocs vers le haut quand une ligne d'attaque est envoyée.
    private func triggerPvPAttackSentVisuals() {
        // — 1. Flash du label de score : vert skin × 1.3 → retour normal —
        if let label = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode {
            let accentColor = Self.bloxSolidFillColor(forNormalizedKey: "green")
                ?? SKColor(red: 0.22, green: 0.85, blue: 0.38, alpha: 1)
            label.removeAction(forKey: Self.pvpMilestoneScoreFlashKey)
            let flash = SKAction.sequence([
                SKAction.run { label.fontColor = accentColor },
                SKAction.scale(to: 1.3, duration: 0.12),
                SKAction.scale(to: 1.0, duration: 0.22),
                SKAction.run { label.fontColor = .white },
            ])
            label.run(flash, withKey: Self.pvpMilestoneScoreFlashKey)
        }

        // — 2. Rangée de mini-blocs qui s'envolent du haut de la grille —
        let miniSize = CGSize(
            width: GridLayout.cellPoints - 8,
            height: GridLayout.cellPoints - 8
        )
        let flyHeight = size.height * 0.45
        let palette = Self.colorPalette

        for col in 0..<GridLayout.columnCount {
            let topCenter = scenePointCellCenter(row: GridLayout.topRowIndex, column: col)
            let startY = topCenter.y + GridLayout.cellPoints * 0.5

            let colorKey = palette[col % palette.count]
            let color = Self.bloxSolidFillColor(forNormalizedKey: colorKey)
                ?? SKColor(white: 0.5, alpha: 1)

            let block = SKSpriteNode(color: color, size: miniSize)
            block.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            block.position = CGPoint(x: topCenter.x, y: startY)
            block.alpha = 1.0
            block.zPosition = 10
            addChild(block)

            let delay = Double(col) * 0.022
            let totalDuration: TimeInterval = 0.45
            let action = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.group([
                    SKAction.moveBy(x: 0, y: flyHeight, duration: totalDuration),
                    SKAction.sequence([
                        SKAction.wait(forDuration: totalDuration * 0.35),
                        SKAction.fadeOut(withDuration: totalDuration * 0.65),
                    ]),
                ]),
                SKAction.removeFromParent(),
            ])
            block.run(action)
        }
    }

    func blomixPvP_setRemoteBoardFillDepth(_ fillDepth: Int) {
        pvpRemoteBoardFillDepth = max(0, min(GridLayout.rowCount, fillDepth))
        refreshRemoteBoardFillIndicator()
    }

    func blomixPvP_setRemoteScore(_ newScore: Int) {
        guard newScore != pvpRemoteScore else { return }
        pvpRemoteScore = max(0, newScore)
        refreshRemoteBoardFillIndicator()
    }

    func blomixPvP_onHandshakeCompleteRestartBoard() {
        pvpMatchSetupInProgress = false
        // L'overlay reste visible jusqu'à ce que l'animation de fermeture du lobby (~0.3 s)
        // soit terminée, afin d'éviter le flash de l'écran d'accueil ou de la partie solo.
        blomixPvP_fadeOutAndRemoveConnectingOverlay()
        // Filet de sécurité : ferme tout modal UIKit encore ouvert (lobby, leaderboard…)
        // qui n'aurait pas été fermé via la notification .blomixPvPBoardsReady.
        if let rootVC = modalRootViewController(), rootVC.presentedViewController != nil {
            rootVC.dismiss(animated: true)
        }
        pvpOpponentDisplayName = pvpCoordinator?.primaryRemotePlayer?.displayName ?? pvpOpponentDisplayName ?? BlomixL10n.pvpUnknownOpponent
        if isStartScreen {
            childNode(withName: Self.startScreenOverlayName)?.removeFromParent()
            isStartScreen = false
            hapticSoft()
        }
        if childNode(withName: Self.titleNodeName) == nil {
            addTopTitle()
        }
        if childNode(withName: Self.bombHudIconName) == nil {
            setupBombHUD()
        }
        if childNode(withName: Self.scoreHudLabelName) == nil {
            setupScoreHUD()
        }
        ensureRemoteBoardFillIndicatorIfNeeded()
        ensurePvPTurnCountdownLabelIfNeeded()
        ensurePvPOpponentLabelIfNeeded()

        resetSessionModelForNewMatch()
        isGameOver = false
        isProcessing = false
        isInjectingBottomRandomLine = false
        // Remet le label score à zéro visuellement (le modèle est déjà à 0 via resetSessionModelForNewMatch).
        if let scoreLabel = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode {
            scoreLabel.text = "0"
        }

        if childNode(withName: Self.gridContainerName) == nil {
            let node = SKNode()
            node.name = Self.gridContainerName
            node.zPosition = 1
            addChild(node)
        }
        drawGrid()
        updatePreviewSprite()
        refreshUpcomingQueueSlots()
        updateBombHUD()
        refreshProgressHUDBars()
        ensureGameOverflowMenuIfNeeded()
        layoutGameOverflowMenuIfNeeded()
        setGameplayNodesHidden(false)
        layoutPvPTurnCountdownIfNeeded()
        refreshRemoteBoardFillIndicator()
        soundBank.play(.begin)
        refreshGameCenterStatusLabelText()
        // Informe le lobby du vrai nom juste avant qu'il se ferme —
        // c'est ici que GKPlayer.displayName est garanti disponible.
        if let resolvedName = pvpOpponentDisplayName, !resolvedName.isEmpty,
           resolvedName != BlomixL10n.pvpUnknownOpponent {
            let gamePlayerID = pvpCoordinator?.primaryRemotePlayer?.gamePlayerID ?? ""
            NotificationCenter.default.post(
                name: .blomixPvPOpponentConnected,
                object: nil,
                userInfo: ["displayName": resolvedName, "gamePlayerID": gamePlayerID]
            )
        }
        NotificationCenter.default.post(name: .blomixPvPBoardsReady, object: nil)
        NotificationCenter.default.post(name: .blomixDidBeginGameplayMatch, object: self)
        pvpCoordinator?.sceneBecameIdleForLocalTurn()
    }

    private func ensurePvPTurnCountdownLabelIfNeeded() {
        guard pvpCoordinator != nil else { return }
        guard childNode(withName: Self.hudPvPTurnTimerName) == nil else { return }
        let label = SKLabelNode(text: "10s")
        label.name                    = Self.hudPvPTurnTimerName
        label.fontName                = Self.customUIFontPostScriptName
        label.fontSize                = 14
        label.fontColor               = .white
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode   = .center
        label.zPosition               = 125
        addChild(label)
        layoutPvPTurnCountdownIfNeeded()
    }

    private func ensurePvPOpponentLabelIfNeeded() {
        guard pvpCoordinator != nil else { return }
        guard childNode(withName: Self.hudPvPOpponentName) == nil else { return }
        let label = SKLabelNode(text: BlomixL10n.pvpHudMatchAgainst(pvpOpponentDisplayName ?? BlomixL10n.pvpUnknownOpponent))
        label.name = Self.hudPvPOpponentName
        label.fontName = Self.customUIFontPostScriptName
        label.fontSize = 12
        label.fontColor = SKColor(white: 0.84, alpha: 1)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = GridLayout.spanPoints
        label.zPosition = 125
        addChild(label)
        layoutPvPTurnCountdownIfNeeded()
    }

    private func layoutPvPTurnCountdownIfNeeded() {
        guard let label = childNode(withName: Self.hudPvPTurnTimerName) as? SKLabelNode else { return }
        guard let scoreLbl = childNode(withName: Self.scoreHudLabelName) as? SKLabelNode else { return }
        let half = GridLayout.spanPoints / 2
        // Même emplacement que le stage timer solo : bord droit du score, en dessous de la caption "TEMPS"
        label.position = CGPoint(x: gridAreaCenter.x + half, y: scoreLbl.position.y - 11)
        label.isHidden = pvpCoordinator == nil
        // La caption "TEMPS" reste visible en PvP (partagée avec le stage timer)
        childNode(withName: Self.hudTimerCaptionName)?.isHidden = pvpCoordinator == nil
        childNode(withName: Self.bestScoreAboveName)?.isHidden = pvpCoordinator != nil
        if let opponentLabel = childNode(withName: Self.hudPvPOpponentName) as? SKLabelNode {
            opponentLabel.text = BlomixL10n.pvpHudMatchAgainst(pvpOpponentDisplayName ?? BlomixL10n.pvpUnknownOpponent)
            let liftAboveGrid: CGFloat = 26 + GridLayout.cellPoints / 2
            let scoreY = scoreLbl.position.y
            opponentLabel.position = CGPoint(x: gridAreaCenter.x, y: scoreY + 34)
            opponentLabel.isHidden = pvpCoordinator == nil
        }
    }

    /// Retourne la colonne à utiliser pour un auto-drop (timer expiré).
    /// Priorité 1 : colonnes avec au moins une case vide non en top (plus d'espace).
    /// Priorité 2 : toutes les colonnes jouables.
    /// Retourne nil si aucune colonne n'est disponible (game over imminent).
    private func autoDropPreferredColumn() -> Int? {
        // Vérifie directement la grille (indépendant de isBombMode, car on drop un bloc normal, pas une bombe).
        let allPlayable = (0..<GridLayout.columnCount).filter { col in
            highestEmptyRow(inColumn: col) != nil
        }
        guard !allPlayable.isEmpty else { return nil }
        // Préférer les colonnes dont la ligne du haut est encore libre (plus d'espace disponible)
        let mostOpen = allPlayable.filter { col in grid[GridLayout.topRowIndex][col] == .empty }
        return (mostOpen.isEmpty ? allPlayable : mostOpen).randomElement()
    }

    func blomixPvP_setTurnCountdown(_ seconds: Int) {
        guard pvpCoordinator != nil else { return }
        ensurePvPTurnCountdownLabelIfNeeded()
        guard let lbl = childNode(withName: Self.hudPvPTurnTimerName) as? SKLabelNode else { return }
        lbl.text = "\(seconds)s"
        switch seconds {
        case 0...2: lbl.fontColor = SKColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)
        case 3...5: lbl.fontColor = SKColor(red: 244/255, green: 162/255, blue: 97/255, alpha: 1)
        default:    lbl.fontColor = .white
        }
    }

    func blomixPvP_shouldRunTurnTimer() -> Bool {
        guard pvpCoordinator != nil else { return false }
        guard !isStartScreen, !isGameOver else { return false }
        guard !isBombMode else { return false }
        return !isProcessing
    }

    func blomixPvP_performAutoRandomDrop() {
        guard pvpCoordinator != nil else { return }
        guard !isStartScreen, !isGameOver else { return }
        guard !isProcessing else { return }
        if isBombMode { return }

        guard let col = autoDropPreferredColumn() else {
            triggerGameOver()
            return
        }
        selectedColumn = col
        updatePreviewSprite()
        dropBlock(usingColumn: col)
    }

    func blomixPvP_presentLocalDefeat() {
        guard pvpCoordinator != nil else { return }
        blomixPvP_finalizeEloIfNeeded(outcome: .loss)
        isGameOver = true
        isProcessing = true
        playMatchSound(.end)
        childNode(withName: Self.fallingSpriteName)?.removeFromParent()
        if let preview = childNode(withName: Self.previewNodeName) {
            preview.isHidden = true
        }
        childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()

        // Animation circles + "GAME OVER" identique au solo, sur la colonne bloquée.
        let blockedColumns = (0..<GridLayout.columnCount).filter { highestEmptyRow(inColumn: $0) == nil }
        let focusColumn = blockedColumns.randomElement() ?? GridLayout.columnCount / 2
        let focusPoint = scenePointCellCenter(row: GridLayout.bottomRowIndex, column: focusColumn)
        playGameOverFocusAnimation(at: focusPoint) { [weak self] in
            self?.blomixPvP_showPvPResult(didWin: false)
        }
    }

    func blomixPvP_presentRemoteVictory() {
        guard pvpCoordinator != nil else { return }
        blomixPvP_finalizeEloIfNeeded(outcome: .win)
        isGameOver = true
        isProcessing = true
        playMatchSound(.victory)
        childNode(withName: Self.fallingSpriteName)?.removeFromParent()
        if let preview = childNode(withName: Self.previewNodeName) {
            preview.isHidden = true
        }
        childNode(withName: Self.bottomLinePreviewStripName)?.removeFromParent()
        blomixPvP_showPvPResult(didWin: true)
    }

    private func blomixPvP_showPvPResult(didWin: Bool) {
        guard let rootVC = modalRootViewController() else { return }
        let result = BlomixPvPResultViewController(
            didWin: didWin,
            opponentName: pvpOpponentDisplayName ?? BlomixL10n.pvpUnknownOpponent
        )
        if let pvpLastEloResult {
            result.applyEloResult(pvpLastEloResult)
        }
        result.onHome = { [weak self] in
            self?.blomixPvP_returnToHomeAfterMatch()
        }
        result.onRematch = { [weak self] in
            self?.pvpCoordinator?.localPlayerRequestedRematch()
        }
        result.modalPresentationStyle = .overFullScreen
        result.modalTransitionStyle = .crossDissolve
        pvpPresentedResultViewController = result
        rootVC.present(result, animated: true)
    }

    func blomixPvP_remotePlayerRequestedRematch() {
        pvpPresentedResultViewController?.markRemotePlayerRequestedRematch()
    }

    func blomixPvP_startRematch() {
        // Remet à zéro les données Elo et ferme l'écran de résultat.
        // Le nouveau handshake appellera blomixPvP_onHandshakeCompleteRestartBoard.
        didFinalizePvPEloForCurrentMatch = false
        pvpLastEloResult = nil
        pvpPresentedResultViewController?.markLaunchingRematch()
        pvpPresentedResultViewController?.dismiss(animated: true)
        pvpPresentedResultViewController = nil
    }

    private func blomixPvP_finalizeEloIfNeeded(outcome: BlomixPvPMatchOutcome) {
        guard !didFinalizePvPEloForCurrentMatch else { return }
        guard let coordinator = pvpCoordinator else { return }
        guard let remotePlayer = coordinator.primaryRemotePlayer else {
            print("[PvP Elo] Impossible de finaliser l’Elo : adversaire introuvable.")
            return
        }

        didFinalizePvPEloForCurrentMatch = true
        Task { @MainActor in
            do {
                let result = try await BlomixEloManager.shared.finalizeLocalPlayerRating(
                    outcome: outcome,
                    against: remotePlayer
                )
                self.pvpLastEloResult = result
                self.pvpPresentedResultViewController?.applyEloResult(result)
            } catch {
                self.pvpLastEloResult = nil
                self.pvpPresentedResultViewController?.applyEloResult(nil)
                print("[PvP Elo] Échec de finalisation Elo : \(error.localizedDescription)")
            }
        }
    }

    private func blomixPvP_returnToHomeAfterMatch() {
        // isWindingDown bloque saveCurrentSoloGameState() dans la micro-fenêtre entre
        // blomixPvP_teardown() (qui met pvpCoordinator = nil) et unwindToStartScreen()
        // (qui pose lui-même isWindingDown = true). Sans cette protection, un
        // willResignActiveNotification peut sauver un état PvP invalide (isZenMode:false,
        // grille PvP) et écraser la save Zen correcte écrite lors du beginPvPWithMatch.
        isWindingDown = true
        blomixPvP_teardown()
        unwindToStartScreen(restoreSave: true)
    }

    func blomixPvP_peerDisconnected() {
        guard pvpCoordinator != nil else { return }
        // Signal la préparation échouée pour fermer l'éventuel lobby encore visible.
        NotificationCenter.default.post(name: .blomixPvPPreparationFailed, object: nil)
        // Si la partie était en cours, l'adversaire a abandonné : le joueur local gagne.
        let wasInGame = pvpCoordinator?.isGameActive == true && !isGameOver
        if wasInGame {
            blomixPvP_finalizeEloIfNeeded(outcome: .win)
        }
        // Protège la sauvegarde solo pendant l'overlay de déconnexion (≈2,5 s) :
        // blomixPvP_teardown() met pvpCoordinator = nil, ce qui lèverait sinon le guard
        // de saveCurrentSoloGameState() alors que la grille contient encore l'état PvP.
        isWindingDown = true
        blomixPvP_teardown()
        // Overlay de notification avant le retour à l'écran d'accueil.
        showPvPDisconnectOverlay(wasInGame: wasInGame) { [weak self] in
            // unwindToStartScreen gère lui-même isWindingDown (true→reset→false→restore).
            self?.unwindToStartScreen(restoreSave: true)
        }
    }

    func blomixPvP_matchFailed(_ error: Error?) {
        guard pvpCoordinator != nil else { return }
        NotificationCenter.default.post(name: .blomixPvPPreparationFailed, object: nil)
        blomixPvP_teardown()
        unwindToStartScreen(restoreSave: true)
    }

    /// Affiche brièvement un message de déconnexion (2,5 s) puis appelle `completion`.
    private func showPvPDisconnectOverlay(wasInGame: Bool, completion: @escaping () -> Void) {
        let overlayName = "pvpDisconnectOverlay"
        childNode(withName: overlayName)?.removeFromParent()

        let overlay = SKNode()
        overlay.name      = overlayName
        overlay.position  = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 400
        addChild(overlay)

        // Fond semi-transparent
        let bg = SKShapeNode(rect: CGRect(origin: CGPoint(x: -size.width / 2, y: -size.height / 2),
                                          size: size))
        bg.fillColor   = SKColor.black.withAlphaComponent(0.75)
        bg.strokeColor = .clear
        bg.zPosition   = 0
        overlay.addChild(bg)

        let titleText = BlomixL10n.pvpDisconnectTitle.uppercased()
        let title = SKLabelNode(text: titleText)
        title.fontName                = Self.customUIFontPostScriptName
        title.fontSize                = 26
        title.fontColor               = .white
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.numberOfLines           = 0
        title.lineBreakMode           = .byWordWrapping
        title.preferredMaxLayoutWidth = size.width - 80
        title.position                = CGPoint(x: 0, y: wasInGame ? 36 : 0)
        title.zPosition               = 1
        overlay.addChild(title)

        if wasInGame {
            let sub = SKLabelNode(text: BlomixL10n.pvpDisconnectMessage)
            sub.fontName                = Self.customUIFontPostScriptName
            sub.fontSize                = 18
            sub.fontColor               = SKColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1)
            sub.horizontalAlignmentMode = .center
            sub.verticalAlignmentMode   = .center
            sub.numberOfLines           = 0
            sub.lineBreakMode           = .byWordWrapping
            sub.preferredMaxLayoutWidth = size.width - 80
            sub.position                = CGPoint(x: 0, y: -28)
            sub.zPosition               = 1
            overlay.addChild(sub)
        }

        overlay.alpha = 0
        overlay.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 2.0),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
            .run(completion)
        ]))
    }
}

// MARK: - SKView clavier (simulateur)

/// `SKView` qui reçoit les **presses** (clavier matériel) et les transmet à `GameScene`.
/// `SKScene` n’est pas `UIResponder` pour les touches clavier sur iOS.
final class BlomixSKView: SKView {

    weak var inputScene: GameScene?

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        inputScene?.handleKeyboardPressesBegan(presses)
        super.pressesBegan(presses, with: event)
    }
}

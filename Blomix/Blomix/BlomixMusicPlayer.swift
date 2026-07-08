//
//  BlomixMusicPlayer.swift
//  Blomix
//
//  Lecteur de musique d'ambiance en boucle infinie et sans coupure.
//  Volume effectif = masterVolume × relativeVolume("Puzzle Game 2.mp3").
//  Utilise AVAudioEngine + scheduleBuffer(.loops) pour un bouclage au niveau
//  hardware, ce qui élimine le silence inter-boucle inhérent au format MP3
//  avec AVAudioPlayer.numberOfLoops.
//

import AVFoundation
import Foundation

// MARK: - Track enum

enum BlomixMusicTrack: String, CaseIterable {
    case puzzleGame2 = "Puzzle Game 2.mp3"
    case calm        = "calm.mp3"

    var displayName: String {
        switch self {
        case .puzzleGame2: return BlomixL10n.musicTrackPuzzleGame2
        case .calm:        return BlomixL10n.musicTrackCalm
        }
    }
}

// MARK: - Noms de fichiers par stage solo

extension BlomixMusicPlayer {
    /// Nom de fichier correspondant à chaque index de stage solo (0 = Stage 1, …, 5 = Stage Ultime).
    static func stageMusicFilename(forStageIndex index: Int) -> String {
        switch index {
        case 0:  return "Puzzle Game 2.mp3"
        case 1:  return "Puzzle Game 2 - 1.1.mp3"
        case 2:  return "Puzzle Game 2 - 1.2.mp3"
        case 3:  return "Puzzle Game 2 - 1.3.mp3"
        case 4:  return "Puzzle Game 2 - 1.4.mp3"
        default: return "Puzzle Game 2 - 1.5.mp3"
        }
    }
}

// MARK: - Player

final class BlomixMusicPlayer: @unchecked Sendable {

    static let shared = BlomixMusicPlayer()

    /// Clé utilisée dans `BlomixAudioMixSettings` pour le volume relatif de la musique.
    /// Les deux morceaux partagent ce même curseur de volume.
    static let soundKey = "Puzzle Game 2.mp3"

    private static let trackDefaultsKey = "BlomixSelectedMusicTrack"

    // MARK: Track selection (persisted)

    var selectedTrack: BlomixMusicTrack {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.trackDefaultsKey) ?? ""
            return BlomixMusicTrack(rawValue: raw) ?? .puzzleGame2
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.trackDefaultsKey)
        }
    }

    // MARK: Engine

    private static let baseFilename = "Puzzle Game 2.mp3"

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isStarted  = false
    private var volumeObserverToken: NSObjectProtocol?

    private init() {}

    // MARK: Public API

    /// Démarre la musique (idempotent — appelé une seule fois après que l'AVAudioSession est active).
    /// Toujours sur la piste de base ("Puzzle Game 2.mp3"), indépendamment de tout choix précédent.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        engine.attach(playerNode)
        load(filename: Self.baseFilename, andPlay: true)
        volumeObserverToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.engine.mainMixerNode.outputVolume = self?.effectiveVolume() ?? 0
        }
    }

    /// Change le morceau à la volée et redémarre la lecture sans toucher au moteur.
    /// Persiste le choix dans UserDefaults (usage : sélecteur manuel).
    func switchToTrack(_ track: BlomixMusicTrack) {
        guard isStarted else { return }
        selectedTrack = track
        playerNode.stop()
        load(filename: track.rawValue, andPlay: true)
    }

    /// Change le morceau à la volée **sans** persister dans UserDefaults.
    /// Utilisé pour les changements automatiques de musique par stage solo.
    func switchToFile(_ filename: String) {
        guard isStarted else { return }
        playerNode.stop()
        load(filename: filename, andPlay: true)
    }

    /// Revient à la piste de base ("Puzzle Game 2.mp3").
    /// Appelé à la fin d'une partie, au retour à l'écran d'accueil ou en PvP.
    func resetToBase() {
        switchToFile(Self.baseFilename)
    }

    // MARK: Private

    private func load(filename: String, andPlay: Bool) {
        let name = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[Music] '\(filename)' introuvable dans le bundle.")
            return
        }
        do {
            let file = try AVAudioFile(forReading: url)

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                print("[Music] Impossible de créer le buffer PCM pour '\(filename)'.")
                return
            }
            try file.read(into: buffer)

            // Reconnect node with correct format (handles format changes between tracks)
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
            engine.mainMixerNode.outputVolume = effectiveVolume()

            if !engine.isRunning {
                try engine.start()
            }

            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            if andPlay { playerNode.play() }
        } catch {
            print("[Music] Erreur chargement '\(filename)' : \(error)")
        }
    }

    private func effectiveVolume() -> Float {
        min(1, max(0, BlomixMatchAudioSettings.shared.masterMusicVolume))
    }
}

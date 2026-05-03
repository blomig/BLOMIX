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

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isStarted  = false
    private var volumeObserverToken: NSObjectProtocol?

    private init() {}

    // MARK: Public API

    /// Démarre la musique (idempotent — appelé une seule fois après que l'AVAudioSession est active).
    func start() {
        guard !isStarted else { return }
        isStarted = true

        engine.attach(playerNode)

        load(track: selectedTrack, andPlay: true)

        volumeObserverToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.engine.mainMixerNode.outputVolume = self?.effectiveVolume() ?? 0
        }
    }

    /// Change le morceau à la volée et redémarre la lecture sans toucher au moteur.
    func switchToTrack(_ track: BlomixMusicTrack) {
        guard isStarted else { return }
        selectedTrack = track
        playerNode.stop()
        load(track: track, andPlay: true)
    }

    // MARK: Private

    private func load(track: BlomixMusicTrack, andPlay: Bool) {
        let rawName = track.rawValue
        let name    = (rawName as NSString).deletingPathExtension
        let ext     = (rawName as NSString).pathExtension

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[Music] '\(rawName)' introuvable dans le bundle.")
            return
        }
        do {
            let file = try AVAudioFile(forReading: url)

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                print("[Music] Impossible de créer le buffer PCM pour '\(rawName)'.")
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
            print("[Music] Erreur chargement '\(rawName)' : \(error)")
        }
    }

    private func effectiveVolume() -> Float {
        let master   = BlomixMatchAudioSettings.shared.masterVolume
        let relative = BlomixAudioMixSettings.shared.relativeVolume(forSoundNamed: Self.soundKey)
        return min(1, max(0, master * relative))
    }
}

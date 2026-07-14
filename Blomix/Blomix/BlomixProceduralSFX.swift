//
//  BlomixProceduralSFX.swift
//  Blomix
//
//  Synthétiseur de sons procéduraux pour les effets MAGIX "courts et précis".
//  Aucun fichier audio externe requis : les buffers PCM sont générés en mémoire.
//
//  Effets couverts :
//    • CHROMAX  — tick montant par case (stagger 0.08 s)
//    • CROSX    — pulse par anneau concentrique (stagger 0.06 s)
//    • TWISTX   — flip court par case (stagger 0.04 s)
//    • COLORX   — clic roulette (× 5 étapes) + pop dissolution par bloc
//    • BRIXED   — impact grave sur le flash initial
//    • SAINTX   — nappe procédurale sur toute l'animation + blop final à l'atterrissage du Brix
//    • SCRUMBLX — cliquets sourds synchronisés sur les crans de décalage par ligne
//

import AVFoundation

final class BlomixProceduralSFX: @unchecked Sendable {

    static let shared = BlomixProceduralSFX()

    // MARK: - Engine & pool

    private let engine   = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextIdx  = 0
    private let poolSize = 14
    private let sr: Double = 44_100

    private init() {
        setupEngine()
    }

    private func setupEngine() {
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        for _ in 0..<poolSize {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: mono)
            players.append(node)
        }
        engine.mainMixerNode.outputVolume = 1.0

        // Redémarrage automatique sur changement de config (route audio, interruption…)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.startEngine()
        }

        startEngine()
    }

    private func startEngine() {
        do {
            try engine.start()
            for node in players where !node.isPlaying { node.play() }
        } catch {
            // L'engine redémarrera au prochain appel via restartIfNeeded()
        }
    }

    /// Réactive l'engine s'il a été interrompu (appel entrant, background, etc.).
    func restartIfNeeded() {
        guard !engine.isRunning else { return }
        startEngine()
    }

    // MARK: - Helpers

    private var masterVol: Float {
        BlomixMatchAudioSettings.shared.masterVolume
    }

    private func nextNode() -> AVAudioPlayerNode {
        let node = players[nextIdx % poolSize]
        nextIdx &+= 1
        return node
    }

    // MARK: - Buffer synthesis

    /// Génère un buffer PCM mono avec enveloppe attaque/release.
    /// `waveform(t)` → valeur instantanée [-1 … 1], `t` en secondes.
    private func makeBuffer(
        duration: Float,
        attack:   Float  = 0.004,
        release:  Float  = 0.030,
        gain:     Float  = 1.0,
        waveform: (Float) -> Float
    ) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let frames = AVAudioFrameCount(duration * Float(sr))
        guard frames > 0,
              let buf  = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buf.floatChannelData?[0]
        else { return nil }
        buf.frameLength = frames

        let fsr   = Float(sr)
        let total = Float(frames)
        let att   = attack  * fsr
        let rel   = release * fsr
        let vol   = gain * masterVol

        for i in 0..<Int(frames) {
            let fi  = Float(i)
            let env: Float
            if fi < att {
                env = fi / att
            } else if fi > total - rel {
                env = max(0, (total - fi) / rel)
            } else {
                env = 1.0
            }
            data[i] = waveform(fi / fsr) * env * vol
        }
        return buf
    }

    /// Génère un buffer avec un sweep de fréquence exponentiel (phase intégrée).
    private func makeSweepBuffer(
        f0:       Float,
        f1:       Float,
        duration: Float,
        attack:   Float = 0.005,
        release:  Float = 0.080,
        gain:     Float = 1.0
    ) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let frames = AVAudioFrameCount(duration * Float(sr))
        guard frames > 0,
              let buf  = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buf.floatChannelData?[0]
        else { return nil }
        buf.frameLength = frames

        let fsr   = Float(sr)
        let total = Float(frames)
        let att   = attack  * fsr
        let rel   = release * fsr
        let vol   = gain * masterVol
        var phase: Float = 0

        for i in 0..<Int(frames) {
            let fi   = Float(i)
            let t    = fi / fsr
            let freq = f0 * pow(f1 / f0, t / duration)
            phase += 2 * .pi * freq / fsr
            let env: Float
            if fi < att {
                env = fi / att
            } else if fi > total - rel {
                env = max(0, (total - fi) / rel)
            } else {
                env = 1.0
            }
            data[i] = sin(phase) * env * vol
        }
        return buf
    }

    private func play(_ buf: AVAudioPCMBuffer) {
        restartIfNeeded()
        let node = nextNode()
        if !node.isPlaying { node.play() }
        node.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
    }

    // MARK: - SAINTX : nappe + blop final

    /// Son procédural "SAINTX" : nappe continue sur toute l'animation.
    /// Doit être appelée au début de `applyMagixEffect_cleanx`.
    func playSaintxWash(duration: Float) {
        guard masterVol > 0 else { return }
        let dur = max(0.2, duration)
        guard let buf = makeBuffer(
            duration: dur,
            attack:   0.012,
            release:  0.140,
            gain:     0.60,
            waveform: { t in
                let progress = t / dur
                // Fréquence qui monte progressivement pendant l'absorption (E3 → ~G4).
                let pitchMult = pow(1.42, progress)
                let baseAtTime: Float = 165.0 * pitchMult
                let drift = 0.25 + 0.75 * progress
                let vib = sin(2 * .pi * 2.2 * t) * 2.5
                let f1 = baseAtTime + vib
                let f2 = baseAtTime * 1.503 + vib * 0.6
                let f3 = baseAtTime * 2.01
                let tone =
                    sin(2 * .pi * f1 * t) * (0.55 * drift) +
                    sin(2 * .pi * f2 * t) * (0.28 * drift) +
                    sin(2 * .pi * f3 * t) * (0.12 * drift)

                let airEnv = max(0, min(1, (t / 0.20))) * max(0, min(1, (dur - t) / 0.25))
                let air = Float.random(in: -1...1) * 0.06 * airEnv

                // Pulsation qui accélère et s'intensifie (effet d'accumulation).
                let pulsePhase = 2 * .pi * (4.0 * t + 7.0 * t * t / dur)
                let pulseDepth = 0.10 + 0.20 * progress
                let pulse = 1.0 - pulseDepth * (0.5 + 0.5 * sin(pulsePhase))
                return (tone + air) * pulse
            }
        ) else { return }
        play(buf)
    }

    /// "Blop" final à jouer au moment où le Brix restant atterrit à sa position finale.
    func playSaintxBlop() {
        guard masterVol > 0 else { return }

        // Sweep descendant très court + petit click bruité en attaque.
        guard let swp = makeSweepBuffer(
            f0: 620, f1: 190,
            duration: 0.090,
            attack: 0.002,
            release: 0.060,
            gain: 0.70
        ) else { return }

        if let data = swp.floatChannelData?[0] {
            let noiseF = Int(min(swp.frameLength, AVAudioFrameCount(0.020 * Float(sr))))
            let fsr = Float(sr)
            for i in 0..<noiseF {
                let fi = Float(i)
                let att = 0.0018 * fsr
                let decay = 0.015 * fsr
                let env: Float = fi < att ? fi / att
                    : fi < att + decay ? 1.0 - (fi - att) / decay
                    : 0
                data[i] += Float.random(in: -0.22...0.22) * env * masterVol
            }
        }

        play(swp)
    }

    // MARK: - SCRUMBLX : cliquets sourds

    /// Petit "cliquet sourd" type Rubik's cube / crémaillère.
    /// À jouer à chaque cran de déplacement horizontal (0.08 s/cran).
    func playScrumblxClack(intensity: Float = 1.0) {
        guard masterVol > 0 else { return }
        let k = max(0.25, min(1.0, intensity))
        let f0 = Float.random(in: 120...185)
        let f1 = f0 * Float.random(in: 1.45...1.75)
        let dur: Float = 0.040

        guard let buf = makeBuffer(
            duration: dur,
            attack:   0.0015,
            release:  0.020,
            gain:     0.55 * k * 1.25,
            waveform: { t in
                // Corps : deux partiels + composante "bois" très courte.
                let tone = sin(2 * .pi * f0 * t) * 0.72
                         + sin(2 * .pi * f1 * t) * 0.18
                // Transient bruité (très bref) : sensation de mécano.
                let clickEnv = max(0, 1.0 - (t / 0.010))
                let click = Float.random(in: -1...1) * 0.22 * clickEnv
                // Petit "choc" en fin (mini-rebond) : évite le son trop sec.
                let tailEnv = max(0, (t - 0.016) / 0.020)
                let tail = sin(2 * .pi * (f0 * 0.85) * t) * 0.10 * tailEnv
                return tone + click + tail
            }
        ) else { return }

        play(buf)
    }

    // MARK: - CHROMAX : tick montant par case

    /// Jouer à chaque case transformée.
    /// `step` : index 0-based dans le chemin.
    /// `total` : longueur totale du chemin (pour calculer le pitch).
    func playChromaxTick(step: Int, total: Int) {
        guard masterVol > 0 else { return }
        // Pitch : C5 (523 Hz) → C6 (1047 Hz) sur la longueur du chemin.
        let t    = total > 1 ? Float(step) / Float(total - 1) : 0
        let freq = 523.0 * pow(2.0, t)          // octave montant
        guard let buf = makeBuffer(
            duration: 0.055,
            attack:   0.003,
            release:  0.030,
            gain:     0.55,
            waveform: { time in
                sin(2 * .pi * freq * time) * 0.80
              + sin(2 * .pi * freq * 2.0 * time) * 0.20
            }
        ) else { return }
        play(buf)
    }

    // MARK: - CROSX : pulse par anneau

    /// Jouer une fois par anneau (distance de Manhattan depuis le centre).
    /// `ring` : distance 0 = centre, 1, 2, …
    func playCrosxPulse(ring: Int) {
        guard masterVol > 0 else { return }
        // Pitch légèrement descendant pour donner une sensation de propagation.
        let freq = 700.0 / pow(1.07, Float(ring))
        guard let buf = makeBuffer(
            duration: 0.075,
            attack:   0.004,
            release:  0.040,
            gain:     0.50,
            waveform: { time in
                sin(2 * .pi * freq * time) * 0.70
              + sin(2 * .pi * freq * 3.0 * time) * 0.18
            }
        ) else { return }
        play(buf)
    }

    // MARK: - TWISTX : flip par case

    /// Jouer à chaque case swappée.
    /// `index` : index dans la liste shufflée des paires — alterne la couleur tonale.
    func playTwistxFlip(index: Int) {
        guard masterVol > 0 else { return }
        let freq: Float = index % 2 == 0 ? 880.0 : 660.0
        guard let buf = makeBuffer(
            duration: 0.038,
            attack:   0.002,
            release:  0.018,
            gain:     0.45,
            waveform: { time in
                sin(2 * .pi * freq * time)
            }
        ) else { return }
        play(buf)
    }

    // MARK: - COLORX : clic roulette

    /// Jouer à chaque étape du cycle de couleurs (0 = plus rapide, 4 = plus lent).
    func playColorxRouletteClick(step: Int) {
        guard masterVol > 0 else { return }
        // Pitch descend avec chaque étape (la roulette ralentit).
        let freq = 880.0 - Float(step) * 38.0      // 880 → 728 Hz
        guard let buf = makeBuffer(
            duration: 0.055,
            attack:   0.002,
            release:  0.038,
            gain:     0.60,
            waveform: { time in
                // Wood block : fondamental + harmonique légère
                sin(2 * .pi * freq * time) * 0.78
              + sin(2 * .pi * freq * 2.4 * time) * 0.15
            }
        ) else { return }
        play(buf)
    }

    // MARK: - COLORX : pop de dissolution

    /// Jouer à chaque bloc dissous (micro-variation de timbre).
    func playColorxDissolvePop() {
        guard masterVol > 0 else { return }
        // Légère variation aléatoire pour éviter l'effet "machine gun".
        let freq = Float.random(in: 340...480)
        guard let buf = makeBuffer(
            duration: 0.030,
            attack:   0.001,
            release:  0.022,
            gain:     0.40,
            waveform: { time in
                sin(2 * .pi * freq * time)
            }
        ) else { return }
        play(buf)
    }

    // MARK: - BRIXED : impact grave

    /// Jouer au moment du flash initial sur tous les Brix.
    func playBrixedImpact() {
        guard masterVol > 0 else { return }
        // Sine sweep 115 → 42 Hz + bruit blanc léger → "thud" grave percussif.
        guard let sineSwp = makeSweepBuffer(
            f0: 115, f1: 42, duration: 0.210,
            attack: 0.005, release: 0.085, gain: 0.70
        ) else { return }

        // Ajouter un peu de bruit sur les premiers 120 ms pour le "click" initial.
        let noiseDur: Float = 0.120
        let noiseFrames = AVAudioFrameCount(noiseDur * Float(sr))
        if let nd = sineSwp.floatChannelData?[0] {
            let totalF = Int(sineSwp.frameLength)
            let noiseF = Int(min(noiseFrames, sineSwp.frameLength))
            let vol    = masterVol
            for i in 0..<noiseF {
                let fi    = Float(i)
                let att   = 0.005 * Float(sr)
                let decay = 0.080 * Float(sr)
                let env: Float = fi < att ? fi / att
                    : fi < att + decay ? 1.0 - (fi - att) / decay
                    : 0
                nd[i] += Float.random(in: -0.12...0.12) * env * vol
                _ = totalF   // silence unused-warning
            }
        }
        play(sineSwp)
    }
}

import Foundation

/// Mixage relatif par bruitage, appliqué **après** le volume maître.
/// Cette couche permet d'équilibrer les sons individuellement et servira plus tard
/// si l'on expose ces paramètres dans l'écran de réglages.
final class BlomixAudioMixSettings: @unchecked Sendable {
    static let shared = BlomixAudioMixSettings()

    static let adjustableSoundNames: [String] = [
        "Puzzle Game 2.mp3",
        "begin.wav",
        "place.wav",
        "bomb.wav",
        "connect_E.wav",
        "connect_F.wav",
        "connect_Gb.wav",
        "chain_new.wav",
        "chain_new-1.wav",
        "chain_new-2.wav",
        "line.mp3",
        "end.wav",
        "victory.mp3",
        "wrong.wav",
        "empty_coll.wav",
        "5251__noisecollector__bloopa01.aiff",
        "prix.wav",
    ]

    private let userDefaultsKey = "BlomixRelativeSoundVolumes"

    private let defaultRelativeVolumes: [String: Float] = [
        "Puzzle Game 2.mp3": 0.5,
        "connect_E.wav": 0.5,
        "connect_F.wav": 0.5,
        "connect_Gb.wav": 0.5,
    ]

    private init() {}

    func relativeVolume(forSoundNamed soundName: String) -> Float {
        if let stored = storedRelativeVolumes()[soundName] {
            return clamped(stored)
        }
        return defaultRelativeVolumes[soundName] ?? 1.0
    }

    func setRelativeVolume(_ value: Float, forSoundNamed soundName: String) {
        var merged = storedRelativeVolumes()
        merged[soundName] = clamped(value)
        UserDefaults.standard.set(merged, forKey: userDefaultsKey)
    }

    func allConfiguredRelativeVolumes() -> [String: Float] {
        defaultRelativeVolumes.merging(storedRelativeVolumes()) { _, stored in clamped(stored) }
    }

    private func storedRelativeVolumes() -> [String: Float] {
        guard let raw = UserDefaults.standard.dictionary(forKey: userDefaultsKey) else { return [:] }
        var out: [String: Float] = [:]
        for (key, value) in raw {
            if let number = value as? NSNumber {
                out[key] = number.floatValue
            }
        }
        return out
    }

    private func clamped(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}

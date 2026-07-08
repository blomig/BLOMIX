import Foundation

/// Mixage relatif par bruitage, appliqué **après** le volume maître.
/// Cette couche permet d'équilibrer les sons individuellement et servira plus tard
/// si l'on expose ces paramètres dans l'écran de réglages.
final class BlomixAudioMixSettings: @unchecked Sendable {
    static let shared = BlomixAudioMixSettings()

    static let adjustableSoundNames: [String] = [
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
        "gun_load.wav",
        "cleanx.wav",
        "scrumblx.wav",
    ]

    private let userDefaultsKey = "BlomixRelativeSoundVolumes"

    private let defaultRelativeVolumes: [String: Float] = [
        "begin.wav":                              0.75,
        "place.wav":                              0.60,
        "bomb.wav":                               0.85,
        "connect_E.wav":                          0.55,
        "connect_F.wav":                          0.65,
        "connect_Gb.wav":                         0.75,
        "chain_new.wav":                          0.80,
        "chain_new-1.wav":                        0.80,
        "chain_new-2.wav":                        0.80,
        "line.mp3":                               0.75,
        "end.wav":                                0.80,
        "victory.mp3":                            0.80,
        "wrong.wav":                              0.65,
        "empty_coll.wav":                         0.70,
        "5251__noisecollector__bloopa01.aiff":    0.75,
        "prix.wav":                               0.70,
        "gun_load.wav":                           0.75,
        "cleanx.wav":                             0.80,
        "scrumblx.wav":                           0.80,
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

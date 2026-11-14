//
//  BlomixTelemetry.swift
//  Blomix
//
//  Mesure anonyme 8.9 (D1). File locale, envoi groupé vers CloudKit Public
//  `TelemetryBatch`. Pas de SDK tiers, pas d’IDFA, pas d’identifiant Game Center.
//  Hors ligne, iCloud absent ou schéma non déployé : la partie ne change pas.
//  Schéma et étiquette : docs/TELEMETRY.md.
//

import CloudKit
import Foundation

/// Chrono de temps de jeu actif. N’avance que pendant un segment ouvert.
/// Les dates sont passées par l’appelant : la logique se teste sans horloge murale.
struct BlomixActivePlayClock: Equatable {
    private(set) var banked: TimeInterval
    private(set) var segmentStartedAt: Date?
    /// Vrai si `noteGameResumed` a restauré cette partie au moins une fois.
    private(set) var resumed: Bool

    init(banked: TimeInterval = 0, segmentStartedAt: Date? = nil, resumed: Bool = false) {
        self.banked = max(0, banked)
        self.segmentStartedAt = segmentStartedAt
        self.resumed = resumed
    }

    /// Ouvre ou ferme le segment. Un second départ ne réinitialise pas le segment déjà ouvert.
    mutating func setRunning(_ running: Bool, at now: Date) {
        if running {
            if segmentStartedAt == nil {
                segmentStartedAt = now
            }
        } else if let start = segmentStartedAt {
            banked += max(0, now.timeIntervalSince(start))
            segmentStartedAt = nil
        }
    }

    /// Secondes entières, segment ouvert compris. Troncature vers zéro.
    func elapsedSeconds(at now: Date) -> Int {
        var total = banked
        if let start = segmentStartedAt {
            total += max(0, now.timeIntervalSince(start))
        }
        return max(0, Int(total))
    }
}

/// Partie suivie + premier plan + hors pause. C’est ce que `BlomixTelemetry` pilote.
struct BlomixActivePlaySession: Equatable {
    private(set) var clock = BlomixActivePlayClock()
    private(set) var gameOpen = false
    private(set) var foreground = false
    private(set) var paused = false

    private mutating func sync(at now: Date) {
        clock.setRunning(gameOpen && foreground && !paused, at: now)
    }

    mutating func setForeground(_ value: Bool, at now: Date) {
        foreground = value
        sync(at: now)
    }

    mutating func setPaused(_ value: Bool, at now: Date) {
        paused = value
        sync(at: now)
    }

    /// Partie neuve. Remet le compteur et `resumed` à zéro.
    mutating func begin(at now: Date) {
        clock = BlomixActivePlayClock()
        gameOpen = true
        paused = false
        sync(at: now)
    }

    /// Reprise d’une sauvegarde. Pas un début de partie. `resumed` passe à vrai.
    mutating func resume(activePlaySeconds: Int, at now: Date) {
        clock = BlomixActivePlayClock(banked: TimeInterval(max(0, activePlaySeconds)), resumed: true)
        gameOpen = true
        paused = false
        sync(at: now)
    }

    /// Menu, sauvegarde quittée. Le temps à écrire est `persistedSeconds` **avant** cet appel.
    mutating func suspend(at now: Date) {
        gameOpen = false
        paused = false
        sync(at: now)
        clock = BlomixActivePlayClock()
    }

    /// `durationSec` et `resumed` sont nil si aucune partie n’était ouverte.
    mutating func end(at now: Date) -> (durationSec: Int?, resumed: Bool?) {
        guard gameOpen else { return (nil, nil) }
        sync(at: now)
        let duration = clock.elapsedSeconds(at: now)
        let wasResumed = clock.resumed
        gameOpen = false
        paused = false
        clock = BlomixActivePlayClock()
        return (duration, wasResumed)
    }

    /// Valeur à poser dans la sauvegarde. 0 si aucune partie n’est ouverte.
    func persistedSeconds(at now: Date) -> Int {
        guard gameOpen else { return 0 }
        return clock.elapsedSeconds(at: now)
    }
}

/// Élément de `eventsJSON`. `resumed` absent sur les anciens lots et hors `game_end`.
struct BlomixTelemetryEvent: Codable, Equatable {
    var id: String
    var kind: String
    var mode: String?
    var durationSec: Int?
    var day: String?
    var resumed: Bool?
    var at: Date
}

@MainActor
enum BlomixTelemetry {

    static let recordType = "TelemetryBatch"

    private static let installKey = "blomix_telemetry_install_id"
    private static let firstLaunchKey = "blomix_telemetry_did_note_first_launch"
    private static let queueKey = "blomix_telemetry_queue_v1"
    private static let cooldownKey = "blomix_telemetry_cooldown_until"
    private static let queueCap = 200
    private static let batchCap = 20

    private static let container = CKContainer(identifier: "iCloud.blomig.BLOMIX")
    private static var publicDB: CKDatabase { container.publicCloudDatabase }

    private static var sessionOpen = false
    private static var flushing = false
    private static var play = BlomixActivePlaySession()

    // MARK: - Cycle de vie

    /// Un début de session par retour au premier plan. Le premier inclut aussi `first_launch`.
    static func noteBecameActive() {
        play.setForeground(true, at: Date())
        guard !sessionOpen else {
            Task { await flush() }
            return
        }
        sessionOpen = true
        if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            enqueue(kind: "first_launch", mode: nil, durationSec: nil, day: nil)
        }
        enqueue(kind: "session_start", mode: nil, durationSec: nil, day: nil)
        Task { await flush() }
    }

    static func noteEnteredBackground() {
        play.setForeground(false, at: Date())
        sessionOpen = false
    }

    /// Début d’une partie neuve. La reprise ne doit pas appeler ceci.
    static func noteGameBegan(mode _: String) {
        play.begin(at: Date())
    }

    /// Reprise d’une sauvegarde. Restaure le chrono. N’émet ni début de partie ni `daily_played`.
    static func noteGameResumed(mode _: String, activePlaySeconds: Int) {
        play.resume(activePlaySeconds: activePlaySeconds, at: Date())
    }

    /// Menu ☰, modal ouvert depuis la partie, confirmation quitter. Le chrono s’arrête.
    static func setPlayPaused(_ paused: Bool) {
        play.setPaused(paused, at: Date())
    }

    /// Retour au menu sans `game_end`. Lire `activePlaySecondsForSave()` avant.
    static func noteGameSuspended() {
        play.suspend(at: Date())
    }

    /// Secondes actives à écrire dans la sauvegarde. 0 hors partie.
    static func activePlaySecondsForSave() -> Int {
        play.persistedSeconds(at: Date())
    }

    /// Fin de partie. `mode` est le libellé stable (arcade, zen, five, daily_arcade, daily_five, duel, tutorial).
    static func noteGameEnded(mode: String) {
        let outcome = play.end(at: Date())
        enqueue(kind: "game_end", mode: mode, durationSec: outcome.durationSec, day: nil, resumed: outcome.resumed)
        Task { await flush() }
    }

    /// Nouvelle partie de défi (pas la reprise). `utcDay` est le jour de la graine.
    static func noteDailyPlayed(mode: String, utcDay: String) {
        enqueue(kind: "daily_played", mode: mode, durationSec: nil, day: utcDay)
        Task { await flush() }
    }

    // MARK: - File

    private static func enqueue(kind: String, mode: String?, durationSec: Int?, day: String?, resumed: Bool? = nil) {
        var queue = loadQueue()
        queue.append(BlomixTelemetryEvent(
            id: UUID().uuidString,
            kind: kind,
            mode: mode,
            durationSec: durationSec,
            day: day,
            resumed: resumed,
            at: Date()
        ))
        if queue.count > queueCap {
            queue.removeFirst(queue.count - queueCap)
        }
        saveQueue(queue)
    }

    private static func loadQueue() -> [BlomixTelemetryEvent] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let queue = try? JSONDecoder().decode([BlomixTelemetryEvent].self, from: data) else { return [] }
        return queue
    }

    private static func saveQueue(_ queue: [BlomixTelemetryEvent]) {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }

    /// Identifiant aléatoire local. Créé une fois. Jamais l’IDFA, jamais le Game Center.
    private static func installID() -> String {
        if let existing = UserDefaults.standard.string(forKey: installKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installKey)
        return fresh
    }

    // MARK: - Envoi

    private static func flush() async {
        guard !flushing else { return }
        if let until = UserDefaults.standard.object(forKey: cooldownKey) as? Date, Date() < until {
            return
        }
        if BlomixPublicCloudGate.shared.isBlocked { return }
        let batch = Array(loadQueue().prefix(batchCap))
        guard !batch.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        do {
            let status = try await container.accountStatus()
            guard status == .available else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let payload = try encoder.encode(batch)
            guard let json = String(data: payload, encoding: .utf8) else { return }
            let record = CKRecord(recordType: recordType)
            record["installID"] = installID() as CKRecordValue
            record["eventsJSON"] = json as CKRecordValue
            record["appVersion"] = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") as CKRecordValue
            record["locale"] = (Locale.current.language.languageCode?.identifier ?? "und") as CKRecordValue
            record["sentAt"] = Date() as CKRecordValue
            _ = try await publicDB.save(record)
            let sent = Set(batch.map(\.id))
            saveQueue(loadQueue().filter { !sent.contains($0.id) })
            UserDefaults.standard.removeObject(forKey: cooldownKey)
        } catch {
            // Ne pas appeler le robinet public : une erreur de schéma ne doit pas geler le Duel.
            if shouldCooldown(error) {
                UserDefaults.standard.set(Date().addingTimeInterval(3600), forKey: cooldownKey)
            }
        }
    }

    /// Schéma absent, compte refusé : attendre. Réseau : réessayer au prochain passage.
    private static func shouldCooldown(_ error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return false
        default:
            return true
        }
    }
}

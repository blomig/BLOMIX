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
    private static var openStartedAt: Date?

    private struct Event: Codable, Equatable {
        var id: String
        var kind: String
        var mode: String?
        var durationSec: Int?
        var day: String?
        var at: Date
    }

    // MARK: - Cycle de vie

    /// Un début de session par retour au premier plan. Le premier inclut aussi `first_launch`.
    static func noteBecameActive() {
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
        sessionOpen = false
    }

    /// Début d’une partie neuve. La reprise ne doit pas appeler ceci.
    static func noteGameBegan(mode _: String) {
        openStartedAt = Date()
    }

    /// Fin de partie. `mode` est le libellé stable (arcade, zen, five, daily_arcade, daily_five, duel, tutorial).
    static func noteGameEnded(mode: String) {
        let duration: Int?
        if let start = openStartedAt {
            duration = max(0, Int(Date().timeIntervalSince(start)))
        } else {
            duration = nil
        }
        openStartedAt = nil
        enqueue(kind: "game_end", mode: mode, durationSec: duration, day: nil)
        Task { await flush() }
    }

    /// Nouvelle partie de défi (pas la reprise). `utcDay` est le jour de la graine.
    static func noteDailyPlayed(mode: String, utcDay: String) {
        enqueue(kind: "daily_played", mode: mode, durationSec: nil, day: utcDay)
        Task { await flush() }
    }

    // MARK: - File

    private static func enqueue(kind: String, mode: String?, durationSec: Int?, day: String?) {
        var queue = loadQueue()
        queue.append(Event(
            id: UUID().uuidString,
            kind: kind,
            mode: mode,
            durationSec: durationSec,
            day: day,
            at: Date()
        ))
        if queue.count > queueCap {
            queue.removeFirst(queue.count - queueCap)
        }
        saveQueue(queue)
    }

    private static func loadQueue() -> [Event] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let queue = try? JSONDecoder().decode([Event].self, from: data) else { return [] }
        return queue
    }

    private static func saveQueue(_ queue: [Event]) {
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

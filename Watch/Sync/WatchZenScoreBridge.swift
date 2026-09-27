//
//  WatchZenScoreBridge.swift
//  Watch → iPhone : file `transferUserInfo` (survitat iPhone tué / sac).
//  Pas de GameKit sur Watch.
//

import Foundation
import os
@preconcurrency import WatchConnectivity

enum WatchZenScorePayload {
    static let schemaKey = "schema"
    static let modeKey = "mode"
    static let scoreKey = "score"
    static let dateKey = "date"
    static let schema = 1
    static let modeZen = "zen"
}

@MainActor
final class WatchZenScoreBridge: NSObject, WCSessionDelegate {
    static let shared = WatchZenScoreBridge()

    private static let log = Logger(subsystem: "blomig.BLOMIX.watchkitapp", category: "sync")
    private static let lastEnqueuedKey = "blomix_watch_zen_last_enqueued"
    private static let pendingKey = "blomix_watch_zen_pending_transfer"

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
        }
        if session.activationState != .activated {
            session.activate()
        } else {
            sendPendingIfPossible()
        }
    }

    /// GO Watch : n’enfile que si `score` bat le dernier PB déjà en file (max monotone).
    func enqueueZenPersonalBest(_ score: Int) {
        guard score > 0 else { return }
        let last = UserDefaults.standard.integer(forKey: Self.lastEnqueuedKey)
        let pending = UserDefaults.standard.integer(forKey: Self.pendingKey)
        let floor = max(last, pending)
        guard score > floor else { return }
        UserDefaults.standard.set(score, forKey: Self.pendingKey)
        sendPendingIfPossible()
    }

    private func sendPendingIfPossible() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            if session.delegate !== self { session.delegate = self }
            session.activate()
            return
        }
        let pending = UserDefaults.standard.integer(forKey: Self.pendingKey)
        let last = UserDefaults.standard.integer(forKey: Self.lastEnqueuedKey)
        guard pending > last, pending > 0 else { return }

        let payload: [String: Any] = [
            WatchZenScorePayload.schemaKey: WatchZenScorePayload.schema,
            WatchZenScorePayload.modeKey: WatchZenScorePayload.modeZen,
            WatchZenScorePayload.scoreKey: pending,
            WatchZenScorePayload.dateKey: ISO8601DateFormatter().string(from: Date()),
        ]
        _ = session.transferUserInfo(payload)
        try? session.updateApplicationContext(payload)
        UserDefaults.standard.set(pending, forKey: Self.lastEnqueuedKey)
        UserDefaults.standard.set(0, forKey: Self.pendingKey)
        Self.log.info("transferUserInfo_enqueued score=\(pending, privacy: .public)")
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            WatchZenScoreBridge.shared.sendPendingIfPossible()
        }
    }
}

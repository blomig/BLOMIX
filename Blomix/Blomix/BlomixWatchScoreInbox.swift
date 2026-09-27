//
//  BlomixWatchScoreInbox.swift
//  Pont Watch → iPhone. Pas GameScene. Pas de save solo / daily.
//

import Foundation
import os
@preconcurrency import WatchConnectivity

enum BlomixWatchScorePayload {
    static let schemaKey = "schema"
    static let modeKey = "mode"
    static let scoreKey = "score"
    static let dateKey = "date"
    static let schema = 1
    static let modeZen = "zen"
}

final class BlomixWatchScoreInbox: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = BlomixWatchScoreInbox()

    private static let log = Logger(subsystem: "blomig.BLOMIX", category: "watch-inbox")

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
        }
        if session.activationState == .activated {
            return
        }
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        applyIncoming(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyIncoming(applicationContext)
    }

    private nonisolated func applyIncoming(_ userInfo: [String: Any]) {
        let schema = (userInfo[BlomixWatchScorePayload.schemaKey] as? Int)
            ?? (userInfo[BlomixWatchScorePayload.schemaKey] as? NSNumber)?.intValue
        guard schema == BlomixWatchScorePayload.schema else { return }
        guard let mode = userInfo[BlomixWatchScorePayload.modeKey] as? String,
              mode == BlomixWatchScorePayload.modeZen else { return }
        let score: Int
        if let value = userInfo[BlomixWatchScorePayload.scoreKey] as? Int {
            score = value
        } else if let number = userInfo[BlomixWatchScorePayload.scoreKey] as? NSNumber {
            score = number.intValue
        } else {
            return
        }
        guard score > 0 else { return }

        Task { @MainActor in
            let local = ScoreManager.shared.getLocalZenHighScore()
            guard score > local else {
                Self.log.info("iphone_skipped_not_better score=\(score, privacy: .public) local=\(local, privacy: .public)")
                return
            }
            ScoreManager.shared.submitScore(score, leaderboardID: ScoreManager.zenLeaderboardID)
            Self.log.info("iphone_applied score=\(score, privacy: .public)")
        }
    }
}

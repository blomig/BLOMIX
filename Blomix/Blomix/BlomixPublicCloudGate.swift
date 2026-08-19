//
//  BlomixPublicCloudGate.swift
//  Blomix
//
//  Robinet unique pour iCloud.blomig.BLOMIX Public DB.
//  Un 503 / Retry-After bloque H2H **et** Joueurs disponibles / chfrom_*.
//

import CloudKit
import Foundation

@MainActor
final class BlomixPublicCloudGate {

    static let shared = BlomixPublicCloudGate()
    private init() {}

    private var retryAfter: Date?

    var isBlocked: Bool {
        guard let t = retryAfter else { return false }
        if Date() >= t {
            retryAfter = nil
            return false
        }
        return true
    }

    /// Secondes restantes (0 si libre).
    var retryRemainingSeconds: Int {
        guard let t = retryAfter else { return 0 }
        return max(0, Int(ceil(t.timeIntervalSinceNow)))
    }

    func noteSuccess() {
        retryAfter = nil
    }

    func noteError(_ error: Error) {
        let wait = Self.retryDelaySeconds(from: error)
        guard wait > 0 else { return }
        let until = Date().addingTimeInterval(wait)
        if let current = retryAfter, current > until { return }
        retryAfter = until
        print("[CKGate] blocked \(Int(wait))s — \(error.localizedDescription)")
    }

    func throwIfBlocked() throws {
        guard isBlocked else { return }
        let sec = max(1, retryRemainingSeconds)
        throw NSError(
            domain: "BlomixPublicCloudGate",
            code: 503,
            userInfo: [NSLocalizedDescriptionKey: BlomixL10n.pvpCloudBusyRetry(sec)]
        )
    }

    private static func retryDelaySeconds(from error: Error) -> TimeInterval {
        if let ck = error as? CKError {
            switch ck.code {
            case .serviceUnavailable, .requestRateLimited, .zoneBusy, .networkUnavailable:
                if let n = ck.userInfo[CKErrorRetryAfterKey] as? NSNumber {
                    return max(5, n.doubleValue)
                }
                return 45
            default:
                break
            }
        }
        let msg = error.localizedDescription
        if let range = msg.range(of: #"Retry after ([0-9]+(?:\.[0-9]+)?)"#, options: .regularExpression) {
            let num = msg[range].replacingOccurrences(of: "Retry after ", with: "")
            if let v = Double(num) { return max(5, v) }
        }
        if msg.localizedCaseInsensitiveContains("throttl") || msg.contains("503") {
            return 45
        }
        return 0
    }
}

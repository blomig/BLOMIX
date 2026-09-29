//
//  WatchZenStore.swift
//  Slot Watch only — n’écrit jamais blomix_solo_save_v2 / blomix_zen_save_v1 / blomix_daily_save_v1.
//

import Foundation
import os

enum WatchZenStore {
    private static let bestKey = "blomix_watch_zen_best_v1"
    private static let runKey = "blomix_watch_zen_save_v1"
    private static let log = Logger(subsystem: "blomig.BLOMIX.watchkitapp", category: "save")

    static var bestScore: Int {
        max(0, UserDefaults.standard.integer(forKey: bestKey))
    }

    static var hasMidRun: Bool { load() != nil }

    static func recordScore(_ score: Int) {
        guard score > bestScore else { return }
        UserDefaults.standard.set(score, forKey: bestKey)
    }

    static func save(_ run: WatchZenRunState) {
        do {
            let data = try JSONEncoder().encode(run)
            UserDefaults.standard.set(data, forKey: runKey)
            log.info("save_ok")
        } catch {
            log.error("save_fail")
        }
    }

    static func load() -> WatchZenRunState? {
        guard let data = UserDefaults.standard.data(forKey: runKey) else { return nil }
        guard let run = try? JSONDecoder().decode(WatchZenRunState.self, from: data),
              run.version == 1 else {
            clearRun()
            return nil
        }
        return run
    }

    static func clearRun() {
        UserDefaults.standard.removeObject(forKey: runKey)
    }
}

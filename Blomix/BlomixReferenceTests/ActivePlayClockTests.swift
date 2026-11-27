import Foundation
import XCTest
@testable import BLOMIX

/// Chrono actif, sans `GameScene` ni CloudKit. Les dates sont injectées.
final class ActivePlayClockTests: XCTestCase {

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func testStoppedClockDoesNotAdvance() {
        let clock = BlomixActivePlayClock()
        XCTAssertEqual(clock.elapsedSeconds(at: t(10_000)), 0)
    }

    func testOpenSegmentCountsAndCloseBanks() {
        var clock = BlomixActivePlayClock()
        clock.setRunning(true, at: t(100))
        XCTAssertEqual(clock.elapsedSeconds(at: t(112.9)), 12)
        clock.setRunning(false, at: t(112.9))
        XCTAssertEqual(clock.elapsedSeconds(at: t(500)), 12)
    }

    func testSecondStartDoesNotResetTheOpenSegment() {
        var clock = BlomixActivePlayClock()
        clock.setRunning(true, at: t(100))
        clock.setRunning(true, at: t(105))
        XCTAssertEqual(clock.elapsedSeconds(at: t(110)), 10)
    }

    func testBackwardJumpDoesNotSubtract() {
        var clock = BlomixActivePlayClock()
        clock.setRunning(true, at: t(50))
        clock.setRunning(false, at: t(40))
        XCTAssertEqual(clock.elapsedSeconds(at: t(80)), 0)
        clock.setRunning(true, at: t(80))
        XCTAssertEqual(clock.elapsedSeconds(at: t(83)), 3)
    }

    func testBackgroundAndPauseAreExcluded() {
        var session = BlomixActivePlaySession()
        session.setForeground(true, at: t(0))
        session.begin(at: t(0))
        session.setForeground(false, at: t(10))
        session.setForeground(true, at: t(1_000))
        session.setPaused(true, at: t(1_015))
        session.setPaused(false, at: t(1_050))
        let end = session.end(at: t(1_058))
        // 10 s avant l’arrière-plan + 15 s au retour + 8 s après la pause.
        XCTAssertEqual(end.durationSec, 33)
        XCTAssertEqual(end.resumed, false)
    }

    func testPauseStaysPausedAcrossBackground() {
        var session = BlomixActivePlaySession()
        session.setForeground(true, at: t(0))
        session.begin(at: t(0))
        session.setPaused(true, at: t(10))
        session.setForeground(false, at: t(15))
        session.setForeground(true, at: t(1_000))
        session.setPaused(false, at: t(1_005))
        let end = session.end(at: t(1_008))
        XCTAssertEqual(end.durationSec, 13)
        XCTAssertEqual(end.resumed, false)
    }

    func testFreshGameResetsAccumulator() {
        var session = BlomixActivePlaySession()
        session.setForeground(true, at: t(0))
        session.resume(activePlaySeconds: 40, at: t(0))
        session.begin(at: t(5))
        let end = session.end(at: t(9))
        XCTAssertEqual(end.durationSec, 4)
        XCTAssertEqual(end.resumed, false)
    }

    func testResumeRestoresSecondsAndMarksResumedWithoutCountingTheGap() {
        var first = BlomixActivePlaySession()
        first.setForeground(true, at: t(0))
        first.begin(at: t(0))
        let saved = first.persistedSeconds(at: t(20))
        XCTAssertEqual(saved, 20)
        first.suspend(at: t(20))
        XCTAssertEqual(first.persistedSeconds(at: t(9_000)), 0)
        XCTAssertNil(first.end(at: t(9_000)).durationSec)

        var second = BlomixActivePlaySession()
        second.setForeground(true, at: t(10_000))
        second.resume(activePlaySeconds: saved, at: t(10_000))
        let end = second.end(at: t(10_007))
        XCTAssertEqual(end.durationSec, 27)
        XCTAssertEqual(end.resumed, true)
    }

    func testEndWithoutAnOpenGameOmitsDuration() {
        var session = BlomixActivePlaySession()
        session.setForeground(true, at: t(0))
        let end = session.end(at: t(30))
        XCTAssertNil(end.durationSec)
        XCTAssertNil(end.resumed)
    }

    func testBeginWhileBackgroundedDoesNotCountUntilForeground() {
        var session = BlomixActivePlaySession()
        session.begin(at: t(0))
        XCTAssertEqual(session.persistedSeconds(at: t(40)), 0)
        session.setForeground(true, at: t(40))
        XCTAssertEqual(session.persistedSeconds(at: t(46)), 6)
    }

    func testGameEndJSONAddsResumedAndKeepsDuration() throws {
        let event = BlomixTelemetryEvent(
            id: "1",
            kind: "game_end",
            mode: "zen",
            durationSec: 42,
            day: nil,
            resumed: false,
            at: t(0)
        )
        let object = try jsonObject(event)
        XCTAssertEqual(object["kind"] as? String, "game_end")
        XCTAssertEqual(object["mode"] as? String, "zen")
        XCTAssertEqual(object["durationSec"] as? Int, 42)
        XCTAssertEqual(object["resumed"] as? Bool, false)
        XCTAssertNil(object["day"])
        XCTAssertNotNil(object["at"])
        XCTAssertNotNil(object["id"])
    }

    func testOtherKindsOmitDurationAndResumed() throws {
        let session = BlomixTelemetryEvent(
            id: "s",
            kind: "session_start",
            mode: nil,
            durationSec: nil,
            day: nil,
            resumed: nil,
            at: t(0)
        )
        let sessionJSON = try jsonObject(session)
        XCTAssertNil(sessionJSON["durationSec"])
        XCTAssertNil(sessionJSON["resumed"])
        XCTAssertNil(sessionJSON["day"])
        XCTAssertNil(sessionJSON["mode"])

        let daily = BlomixTelemetryEvent(
            id: "d",
            kind: "daily_played",
            mode: "daily_five",
            durationSec: nil,
            day: "2026-11-14",
            resumed: nil,
            at: t(0)
        )
        let dailyJSON = try jsonObject(daily)
        XCTAssertEqual(dailyJSON["day"] as? String, "2026-11-14")
        XCTAssertEqual(dailyJSON["mode"] as? String, "daily_five")
        XCTAssertNil(dailyJSON["durationSec"])
        XCTAssertNil(dailyJSON["resumed"])
    }

    func testQueuedEventWithoutResumedStillDecodes() throws {
        let legacy = """
        {"id":"old","kind":"game_end","mode":"arcade","durationSec":7,"at":"1970-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(BlomixTelemetryEvent.self, from: legacy)
        XCTAssertEqual(event.durationSec, 7)
        XCTAssertEqual(event.mode, "arcade")
        XCTAssertNil(event.resumed)
        XCTAssertNil(event.day)
        XCTAssertNil(event.stepIndex)
        XCTAssertNil(event.stepId)
        XCTAssertNil(event.result)
        XCTAssertNil(event.isNewInstall)
    }

    func testTutorialEndJSONUsesSnakeCaseAndOmitsEmptyKeys() throws {
        let event = BlomixTelemetryEvent(
            id: "t",
            kind: "tutorial_end",
            mode: nil,
            durationSec: nil,
            day: nil,
            resumed: nil,
            at: t(0),
            stepIndex: 4,
            stepId: "brix_intro",
            result: "abandoned",
            isNewInstall: nil
        )
        let object = try jsonObject(event)
        XCTAssertEqual(object["kind"] as? String, "tutorial_end")
        XCTAssertEqual(object["step_index"] as? Int, 4)
        XCTAssertEqual(object["step_id"] as? String, "brix_intro")
        XCTAssertEqual(object["result"] as? String, "abandoned")
        XCTAssertNil(object["stepIndex"])
        XCTAssertNil(object["is_new_install"])
        XCTAssertNil(object["mode"])
        XCTAssertNil(object["durationSec"])
    }

    func testFirstLaunchJSONKeepsTheNewInstallFlag() throws {
        let event = BlomixTelemetryEvent(
            id: "f",
            kind: "first_launch",
            at: t(0),
            isNewInstall: true
        )
        let object = try jsonObject(event)
        XCTAssertEqual(object["is_new_install"] as? Bool, true)
        XCTAssertNil(object["result"])
        XCTAssertNil(object["step_id"])
    }

    func testGuidedGameEventsAddNoExtraKeys() throws {
        let event = BlomixTelemetryEvent(
            id: "g",
            kind: "first_guided_game_start",
            at: t(0)
        )
        let object = try jsonObject(event)
        XCTAssertEqual(object["kind"] as? String, "first_guided_game_start")
        XCTAssertNil(object["is_new_install"])
        XCTAssertNil(object["step_index"])
        XCTAssertNil(object["result"])
        XCTAssertNil(object["mode"])
    }

    func testInstallCensusTreatsAnEmptySuiteAsNew() {
        let name = "blomix-census-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertTrue(BlomixInstallCensus.isNewInstall(defaults: defaults))
        defaults.set(true, forKey: "BlomixHasSeenInteractiveTutorial_v1")
        XCTAssertFalse(BlomixInstallCensus.isNewInstall(defaults: defaults))
        defaults.removePersistentDomain(forName: name)
        defaults.set(12, forKey: "BlomixLocalZenHighScore")
        XCTAssertFalse(BlomixInstallCensus.isNewInstall(defaults: defaults))
        defaults.removePersistentDomain(forName: name)
        let trophy = #"{"items":{"theme_light":{"value":1}}}"#.data(using: .utf8)!
        defaults.set(trophy, forKey: "blomix_trophies_v1")
        XCTAssertTrue(BlomixInstallCensus.isNewInstall(defaults: defaults))
        let played = #"{"items":{"play_arcade":{"value":1}}}"#.data(using: .utf8)!
        defaults.set(played, forKey: "blomix_trophies_v1")
        XCTAssertFalse(BlomixInstallCensus.isNewInstall(defaults: defaults))
        defaults.removePersistentDomain(forName: name)
    }

    private func jsonObject(_ event: BlomixTelemetryEvent) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}

/// Pourcentages des réalisations, sans Game Center.
final class GameCenterAchievementMathTests: XCTestCase {

    func testBinaryIsZeroOrComplete() {
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 0, target: 1, mode: .binary, hidden: false), 0)
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 1, target: 1, mode: .binary, hidden: false), 100)
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 4, target: 1, mode: .binary, hidden: false), 100)
    }

    func testProgressiveRoundsToTwoDecimals() {
        XCTAssertEqual(
            BlomixGCAchievementMath.percent(value: 2, target: 7, mode: .progressive, hidden: false),
            28.57,
            accuracy: 0.001
        )
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 3, target: 6, mode: .progressive, hidden: false), 50)
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 5, target: 10, mode: .progressive, hidden: false), 50)
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 12, target: 10, mode: .progressive, hidden: false), 100)
    }

    func testHiddenSendsOnlyCompletion() {
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 0, target: 1, mode: .binary, hidden: true), 0)
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 1, target: 1, mode: .binary, hidden: true), 100)
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 2, target: 7, mode: .progressive, hidden: true), 0)
        XCTAssertEqual(BlomixGCAchievementMath.percent(value: 7, target: 7, mode: .progressive, hidden: true), 100)
    }

    func testBurstKeepsOnlyTheHighestPointBanner() {
        let few = [
            (gcID: "a", points: 10),
            (gcID: "b", points: 30),
            (gcID: "c", points: 60),
        ]
        XCTAssertNil(BlomixGCAchievementMath.soleBannerID(amongCompleted: few))
        let many = few + [
            (gcID: "d", points: 100),
            (gcID: "e", points: 100),
        ]
        XCTAssertEqual(BlomixGCAchievementMath.soleBannerID(amongCompleted: many), "e")
    }

    @MainActor
    func testTableMatchesTheTwentyASCIdentifiers() {
        let ids = BlomixGameCenterAchievements.entries.map(\.gcID)
        XCTAssertEqual(ids, [
            "blomix.ach.first_chain",
            "blomix.ach.first_bomb",
            "blomix.ach.tutorial",
            "blomix.ach.first_magix",
            "blomix.ach.pacifist",
            "blomix.ach.super_combo",
            "blomix.ach.stage_3",
            "blomix.ach.duel_win",
            "blomix.ach.daily_streak_3",
            "blomix.ach.five_tide_20",
            "blomix.ach.zen_2000",
            "blomix.ach.stage_ultime",
            "blomix.ach.chain_10",
            "blomix.ach.magix_all_nine",
            "blomix.ach.daily_streak_7",
            "blomix.ach.trophies_30",
            "blomix.ach.arcade_10k",
            "blomix.ach.combo_deep",
            "blomix.ach.daily_streak_30",
            "blomix.ach.saintx_ultime",
        ])
        let hidden = Set(BlomixGameCenterAchievements.entries.filter(\.hidden).map(\.gcID))
        XCTAssertEqual(hidden, ["blomix.ach.pacifist", "blomix.ach.saintx_ultime"])
    }

    /// Cache sandbox à 100, réalisations serveur vides : le Salon repart vers Game Center.
    @MainActor
    func testStaleSandboxCacheSendsSalonWhenServerIsEmpty() {
        let ids = BlomixGameCenterAchievements.entries.map(\.gcID)
        let polluted = Dictionary(uniqueKeysWithValues: ids.map { ($0, 100.0) })
        XCTAssertEqual(polluted["blomix.ach.first_chain"], 100)

        let stored = BlomixGCAchievementMath.storedAfterServer(knownIDs: ids, serverPercents: [:])
        XCTAssertEqual(stored.count, ids.count)
        XCTAssertTrue(stored.values.allSatisfy { $0 == 0 })
        XCTAssertNil(stored["not.ours"])

        let salon: [(gcID: String, percent: Double)] = ids.map { id in
            let percent = id == "blomix.ach.first_chain"
                ? BlomixGCAchievementMath.percent(value: 1, target: 1, mode: .binary, hidden: false)
                : 0
            return (gcID: id, percent: percent)
        }
        let pending = BlomixGCAchievementMath.increases(salon: salon, stored: stored)
        XCTAssertEqual(pending.map(\.gcID), ["blomix.ach.first_chain"])
        XCTAssertEqual(pending.first?.percent, 100)

        let completed = pending.filter { $0.percent >= 100 }.count
        let line = BlomixGCAchievementMath.sendLog(count: pending.count, completed: completed)
        print(line)
        XCTAssertEqual(line, "[GCAch] envoi de 1 réalisation(s), dont 1 complétée(s)")
    }

    func testServerValueBlocksOnlyWhatProductionAlreadyHas() {
        let ids = ["blomix.ach.first_chain", "blomix.ach.first_bomb"]
        let stored = BlomixGCAchievementMath.storedAfterServer(
            knownIDs: ids,
            serverPercents: ["blomix.ach.first_bomb": 100, "not.ours": 100]
        )
        XCTAssertEqual(stored["blomix.ach.first_bomb"], 100)
        XCTAssertEqual(stored["blomix.ach.first_chain"], 0)
        XCTAssertNil(stored["not.ours"])

        let pending = BlomixGCAchievementMath.increases(
            salon: [
                (gcID: "blomix.ach.first_chain", percent: 100),
                (gcID: "blomix.ach.first_bomb", percent: 100),
            ],
            stored: stored
        )
        XCTAssertEqual(pending.map(\.gcID), ["blomix.ach.first_chain"])
    }

    @MainActor
    func testCacheKeyIsSplitFromTheLegacySandboxMix() {
        XCTAssertNotEqual(
            BlomixGameCenterAchievements.CacheKey.sandbox,
            BlomixGameCenterAchievements.CacheKey.release
        )
        XCTAssertNotEqual(
            BlomixGameCenterAchievements.CacheKey.current,
            BlomixGameCenterAchievements.CacheKey.legacy
        )
        #if DEBUG
        XCTAssertEqual(
            BlomixGameCenterAchievements.CacheKey.current,
            BlomixGameCenterAchievements.CacheKey.sandbox
        )
        #else
        XCTAssertEqual(
            BlomixGameCenterAchievements.CacheKey.current,
            BlomixGameCenterAchievements.CacheKey.release
        )
        #endif
    }
}

/// Pastilles vertes du Duel : lignes envoyées, encore en suspens chez l’autre.
final class SentAttackLedgerTests: XCTestCase {

    func testSentLineStaysPendingUntilItLands() {
        var ledger = BlomixPvPSentAttackLedger()
        ledger.noteSent(attackId: 1)
        XCTAssertEqual(ledger.pendingCount, 1)
        XCTAssertEqual(ledger.displayedCount, 1)
        ledger.noteSent(attackId: 1)
        XCTAssertEqual(ledger.pendingCount, 1, "un second envoi du même id ne double pas la pastille")
        ledger.noteTaken(through: 1)
        XCTAssertEqual(ledger.pendingCount, 0)
        XCTAssertEqual(ledger.displayedCount, 0)
    }

    func testSeveralSendsStayLitUntilEachOneLands() {
        var ledger = BlomixPvPSentAttackLedger()
        ledger.noteSent(attackId: 1)
        ledger.noteSent(attackId: 2)
        ledger.noteSent(attackId: 3)
        XCTAssertEqual(ledger.displayedCount, 3)
        XCTAssertEqual(ledger.pendingIds, [1, 2, 3])
        ledger.noteTaken(through: 1)
        XCTAssertEqual(ledger.pendingIds, [2, 3])
        ledger.noteTakenCount(1)
        XCTAssertEqual(ledger.pendingIds, [3])
    }

    func testDisplayCapsAtFourWhileTheRestStaysQueued() {
        var ledger = BlomixPvPSentAttackLedger()
        for id in 1...5 {
            ledger.noteSent(attackId: id)
        }
        XCTAssertEqual(ledger.pendingCount, 5)
        XCTAssertEqual(ledger.displayedCount, 4)
        ledger.noteTaken(through: 1)
        XCTAssertEqual(ledger.pendingCount, 4)
        XCTAssertEqual(ledger.displayedCount, 4)
        ledger.noteTaken(through: 2)
        XCTAssertEqual(ledger.displayedCount, 3)
    }

    func testWatermarkClearsOlderIdsAndIgnoresARepeat() {
        var ledger = BlomixPvPSentAttackLedger()
        ledger.noteSent(attackId: 1)
        ledger.noteSent(attackId: 2)
        ledger.noteSent(attackId: 4)
        ledger.noteTaken(through: 2)
        XCTAssertEqual(ledger.pendingIds, [4])
        ledger.noteTaken(through: 2)
        XCTAssertEqual(ledger.pendingIds, [4])
        ledger.noteSent(attackId: 2)
        XCTAssertEqual(ledger.pendingIds, [4], "un id déjà posé ne se rallume pas")
    }

    func testResetLetsTheNextMatchStartEmpty() {
        var ledger = BlomixPvPSentAttackLedger()
        ledger.noteSent(attackId: 3)
        ledger.noteTaken(through: 3)
        ledger.reset()
        XCTAssertEqual(ledger.pendingCount, 0)
        XCTAssertEqual(ledger.takenThrough, 0)
        ledger.noteSent(attackId: 1)
        XCTAssertEqual(ledger.pendingIds, [1])
    }
}

/// Contrat Défi Super : graine, bombes, série de déblocage, isolation du record Zen.
final class SuperDailyTests: XCTestCase {

    func testSuperKindContract() {
        let kind = BlomixDailyKind.superDaily
        XCTAssertEqual(kind.rawValue, "super")
        XCTAssertEqual(kind.startingBombCount, 0)
        XCTAssertEqual(BlomixDailyKind.arcade.startingBombCount, 5)
        XCTAssertEqual(BlomixDailyKind.five.startingBombCount, 5)
        XCTAssertTrue(kind.isUntimed)
        XCTAssertFalse(BlomixDailyKind.arcade.isUntimed)
        XCTAssertEqual(kind.linePeriod, 10)
        XCTAssertEqual(kind.recordType, "SuperDailyScore")
        XCTAssertEqual(kind.ckDayKey, "day")
        XCTAssertEqual(kind.leaderboardID, "dailywin_super")
        XCTAssertEqual(kind.creditedPrefix, "credited_super_")
        XCTAssertEqual(kind.seedSalt, "blomix-super-v1")
        XCTAssertEqual(kind.fxSalt, "blomix-super-fx-v1")
        XCTAssertEqual(kind.saveKey, "blomix_super_daily_save_v1")
        XCTAssertNotEqual(kind.seedSalt, BlomixDailyKind.arcade.seedSalt)
        XCTAssertNotEqual(kind.seedSalt, BlomixDailyKind.five.seedSalt)
    }

    func testSuperSeedDiffersAndStaysStable() {
        let day = "2026-11-13"
        let arcade = BlomixDailySeed.seed(forDay: day, salt: BlomixDailyKind.arcade.seedSalt)
        let five = BlomixDailySeed.seed(forDay: day, salt: BlomixDailyKind.five.seedSalt)
        let superSeed = BlomixDailySeed.seed(forDay: day, salt: BlomixDailyKind.superDaily.seedSalt)
        XCTAssertNotEqual(superSeed, arcade)
        XCTAssertNotEqual(superSeed, five)
        XCTAssertEqual(superSeed, BlomixDailySeed.seed(forDay: day, salt: BlomixDailySeed.superSalt))
    }

    func testSuperGameOverWritesSuperModeNotZen() {
        XCTAssertEqual(
            BlomixRunRecordSink.forGameOver(isSuperDaily: true, isFive: false, isZen: true),
            .superMode
        )
        XCTAssertNotEqual(
            BlomixRunRecordSink.forGameOver(isSuperDaily: true, isFive: false, isZen: true),
            .zen
        )
        XCTAssertEqual(
            BlomixRunRecordSink.forGameOver(isSuperDaily: false, isFive: false, isZen: true),
            .zen
        )
        XCTAssertEqual(ScoreManager.superLeaderboardID, "SuperMode")
        XCTAssertNotEqual(ScoreManager.superLeaderboardID, ScoreManager.zenLeaderboardID)
    }

    func testSevenCompleteDaysUnlockAndAGapResets() {
        let days = (1...7).map { String(format: "2026-11-%02d", $0) }
        XCTAssertEqual(BlomixSuperUnlockMath.streak(completeDays: Set(days), today: days[6]), 7)
        let gapped = Set(days.dropLast())
        XCTAssertEqual(BlomixSuperUnlockMath.streak(completeDays: gapped, today: "2026-11-09"), 0)
    }

    func testASingleChallengeDayDoesNotCountAndTodayCanStayOpen() {
        let onlyYesterday = Set(["2026-11-06"])
        XCTAssertEqual(BlomixSuperUnlockMath.streak(completeDays: onlyYesterday, today: "2026-11-07"), 1)
        XCTAssertEqual(BlomixSuperUnlockMath.streak(completeDays: onlyYesterday, today: "2026-11-08"), 0)
        XCTAssertEqual(BlomixSuperUnlockMath.streak(completeDays: [], today: "2026-11-07"), 0)
    }

    func testADayCountsOnceInTheStreak() {
        let days: Set<String> = ["2026-11-01", "2026-11-02", "2026-11-02"]
        XCTAssertEqual(BlomixSuperUnlockMath.streak(completeDays: days, today: "2026-11-02"), 2)
    }

    func testOpenTodayKeepsYesterdaysStreak() {
        let days = Set((1...6).map { String(format: "2026-11-%02d", $0) })
        XCTAssertEqual(BlomixSuperUnlockMath.streak(completeDays: days, today: "2026-11-07"), 6)
    }

    func testOneFinishedChallengeDoesNotCountAndUnlockIsPermanent() throws {
        let name = "blomix-super-unlock-tests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: BlomixSuperUnlock.bootstrappedKey)
        defaults.set("2026-11-01", forKey: BlomixDailyKind.arcade.finishedDayKey)
        BlomixSuperUnlock.noteChallengeFinished(kind: .arcade, day: "2026-11-01", defaults: defaults)
        XCTAssertTrue(BlomixSuperUnlock.completeDays(defaults: defaults).isEmpty)

        defaults.set("2026-11-01", forKey: BlomixDailyKind.five.finishedDayKey)
        BlomixSuperUnlock.noteChallengeFinished(kind: .five, day: "2026-11-01", defaults: defaults)
        BlomixSuperUnlock.noteChallengeFinished(kind: .arcade, day: "2026-11-01", defaults: defaults)
        XCTAssertEqual(BlomixSuperUnlock.completeDays(defaults: defaults), ["2026-11-01"])

        let today = "2026-11-07"
        var cursor = today
        var days: [String] = []
        for _ in 0..<7 {
            days.append(cursor)
            cursor = try XCTUnwrap(BlomixSuperUnlockMath.previousDay(before: cursor))
        }
        defaults.set(days, forKey: BlomixSuperUnlock.daysKey)
        BlomixSuperUnlock.refreshStreak(today: today, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: BlomixSuperUnlock.unlockedKey))
        XCTAssertTrue(defaults.bool(forKey: BlomixSuperUnlock.celebrateKey))

        BlomixSuperUnlock.refreshStreak(today: "2026-12-01", defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: BlomixSuperUnlock.unlockedKey))
        XCTAssertEqual(defaults.integer(forKey: BlomixSuperUnlock.streakKey), 0)
        defaults.removePersistentDomain(forName: name)
    }
}

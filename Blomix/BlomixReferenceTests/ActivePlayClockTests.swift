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
}

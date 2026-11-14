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
    }

    private func jsonObject(_ event: BlomixTelemetryEvent) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}

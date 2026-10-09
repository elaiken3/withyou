//
//  FocusSessionStoreTests.swift
//  WithYouTests
//

import Foundation
import SwiftData
import XCTest
@testable import WithYou

@MainActor
final class FocusSessionStoreTests: XCTestCase {

    /// A fixed clock keeps the math exact.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let twentyFiveMinutes = 25 * 60

    /// In-memory store. Created before any `@Model` instance, as SwiftData requires.
    /// The container is returned too so it stays alive for the whole test.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: FocusSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    private func secondsAgo(_ seconds: Int) -> Date {
        now.addingTimeInterval(TimeInterval(-seconds))
    }

    // MARK: - Not started

    func testNotStartedHasFullDurationAndNoOvertime() throws {
        let (container, context) = try makeContext()
        let session = FocusSession(focusTitle: "Write intro", durationSeconds: twentyFiveMinutes)
        context.insert(session)

        XCTAssertEqual(FocusSessionStore.remainingSeconds(for: session, now: now), twentyFiveMinutes)
        XCTAssertEqual(FocusSessionStore.overtimeSeconds(for: session, now: now), 0)
        withExtendedLifetime(container) {}
    }

    // MARK: - Running

    func testRunningSessionCountsDown() throws {
        let (container, context) = try makeContext()
        let session = FocusSession(
            focusTitle: "Write intro",
            durationSeconds: twentyFiveMinutes,
            startedAt: secondsAgo(10 * 60)
        )
        context.insert(session)

        XCTAssertEqual(FocusSessionStore.remainingSeconds(for: session, now: now), 15 * 60)
        XCTAssertEqual(FocusSessionStore.overtimeSeconds(for: session, now: now), 0)
        withExtendedLifetime(container) {}
    }

    // MARK: - Paused

    func testFinishedPausesDoNotCount() throws {
        let (container, context) = try makeContext()
        let session = FocusSession(
            focusTitle: "Write intro",
            durationSeconds: twentyFiveMinutes,
            startedAt: secondsAgo(10 * 60),
            pausedSeconds: 2 * 60
        )
        context.insert(session)

        // 10 min elapsed − 2 min paused = 8 min used.
        XCTAssertEqual(FocusSessionStore.remainingSeconds(for: session, now: now), 17 * 60)
        XCTAssertEqual(FocusSessionStore.overtimeSeconds(for: session, now: now), 0)
        withExtendedLifetime(container) {}
    }

    func testPauseThatIsStillRunningDoesNotCount() throws {
        let (container, context) = try makeContext()
        let session = FocusSession(
            focusTitle: "Write intro",
            durationSeconds: twentyFiveMinutes,
            startedAt: secondsAgo(10 * 60),
            pausedSeconds: 60,
            pausedAt: secondsAgo(2 * 60)
        )
        context.insert(session)

        // 10 min elapsed − (1 min earlier pause + 2 min current pause) = 7 min used.
        XCTAssertEqual(FocusSessionStore.remainingSeconds(for: session, now: now), 18 * 60)

        // While paused, the clock stands still.
        let aMinuteLater = now.addingTimeInterval(60)
        XCTAssertEqual(FocusSessionStore.remainingSeconds(for: session, now: aMinuteLater), 18 * 60)
        withExtendedLifetime(container) {}
    }

    func testRemainingNeverExceedsDuration() throws {
        let (container, context) = try makeContext()
        let session = FocusSession(
            focusTitle: "Write intro",
            durationSeconds: twentyFiveMinutes,
            startedAt: secondsAgo(60),
            pausedSeconds: 5 * 60
        )
        context.insert(session)

        XCTAssertEqual(FocusSessionStore.remainingSeconds(for: session, now: now), twentyFiveMinutes)
        XCTAssertEqual(FocusSessionStore.overtimeSeconds(for: session, now: now), 0)
        withExtendedLifetime(container) {}
    }

    // MARK: - Overtime

    func testOvertimeAfterPlannedEnd() throws {
        let (container, context) = try makeContext()
        let session = FocusSession(
            focusTitle: "Write intro",
            durationSeconds: twentyFiveMinutes,
            startedAt: secondsAgo(twentyFiveMinutes + 192)
        )
        context.insert(session)

        XCTAssertEqual(FocusSessionStore.remainingSeconds(for: session, now: now), 0)
        XCTAssertEqual(FocusSessionStore.overtimeSeconds(for: session, now: now), 192) // "+3:12"
        withExtendedLifetime(container) {}
    }

    func testOvertimeExcludesPausedTime() throws {
        let (container, context) = try makeContext()
        let session = FocusSession(
            focusTitle: "Write intro",
            durationSeconds: twentyFiveMinutes,
            startedAt: secondsAgo(30 * 60),
            pausedSeconds: 3 * 60
        )
        context.insert(session)

        // 30 min elapsed − 3 min paused = 27 min used: 2 min past the plan.
        XCTAssertEqual(FocusSessionStore.remainingSeconds(for: session, now: now), 0)
        XCTAssertEqual(FocusSessionStore.overtimeSeconds(for: session, now: now), 2 * 60)
        withExtendedLifetime(container) {}
    }
}

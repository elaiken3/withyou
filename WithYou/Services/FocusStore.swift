//
//  FocusStore.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData

struct FocusSessionStore {
    static func activeSession(in context: ModelContext) -> FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { (s: FocusSession) in
                s.isActive && s.endedAt == nil
            },
            sortBy: [SortDescriptor<FocusSession>(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Optional hardening: if multiple sessions are active, keep newest and end the rest.
    static func normalizeActiveSessions(in context: ModelContext) {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { (s: FocusSession) in
                s.isActive && s.endedAt == nil
            },
            sortBy: [SortDescriptor<FocusSession>(\.createdAt, order: .reverse)]
        )

        guard let active = try? context.fetch(descriptor), active.count > 1 else { return }

        for s in active.dropFirst() {
            s.isActive = false
            s.endedAt = Date()
            NotificationManager.shared.cancelFocusEnd(sessionId: s.id)
        }
        try? context.save()
    }

    // MARK: - Starting

    /// Creates a focus session (ending any other active one).
    ///
    /// - `beginImmediately: false` leaves `startedAt` nil so the Focus tab shows the
    ///   Brain Dump step first; "Begin Focus" then calls `begin(_:in:)`.
    /// - `beginImmediately: true` starts the timer now and schedules the end notification.
    @discardableResult
    static func start(
        title: String,
        startStep: String,
        durationSeconds: Int,
        sourceKind: FocusSourceKind? = nil,
        sourceId: UUID? = nil,
        beginImmediately: Bool,
        in context: ModelContext
    ) throws -> FocusSession {
        if let existing = activeSession(in: context) {
            existing.isActive = false
            existing.endedAt = Date()
            NotificationManager.shared.cancelFocusEnd(sessionId: existing.id)
        }

        let session = FocusSession(
            focusTitle: title,
            focusStartStep: startStep,
            durationSeconds: durationSeconds,
            createdAt: Date(),
            startedAt: beginImmediately ? Date() : nil,
            endedAt: nil,
            isActive: true,
            sourceKindRaw: sourceKind?.rawValue,
            sourceId: sourceId
        )
        context.insert(session)
        try context.save()

        if beginImmediately {
            scheduleEndNotification(for: session)
        }
        return session
    }

    /// Starts the timer for a session created earlier (Brain Dump → "Begin Focus").
    /// Always (re)schedules the end notification — the old code skipped it whenever
    /// `startedAt` was already set, so the notification was never scheduled.
    static func begin(_ session: FocusSession, in context: ModelContext) throws {
        if session.startedAt == nil {
            session.startedAt = Date()
        }
        session.isActive = true
        session.endedAt = nil
        try context.save()
        scheduleEndNotification(for: session)
    }

    // MARK: - Time math

    /// Seconds left, excluding paused time (including a pause that is still running).
    static func remainingSeconds(for session: FocusSession, now: Date = Date()) -> Int {
        guard let startedAt = session.startedAt else { return session.durationSeconds }
        let elapsed = Int(now.timeIntervalSince(startedAt))
        let livePaused = session.pausedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        let effectiveElapsed = max(0, elapsed - (session.pausedSeconds + livePaused))
        return max(0, session.durationSeconds - effectiveElapsed)
    }

    /// Seconds past the planned end (0 while time remains). Used for a gentle "+3:12" overtime display.
    static func overtimeSeconds(for session: FocusSession, now: Date = Date()) -> Int {
        guard let startedAt = session.startedAt else { return 0 }
        let elapsed = Int(now.timeIntervalSince(startedAt))
        let livePaused = session.pausedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        let effectiveElapsed = max(0, elapsed - (session.pausedSeconds + livePaused))
        return max(0, effectiveElapsed - session.durationSeconds)
    }

    // MARK: - Notifications

    /// Replaces the "Focus complete" notification so it fires when time actually runs out.
    /// Paused or already-finished sessions get no notification.
    static func scheduleEndNotification(for session: FocusSession) {
        let id = session.id
        let title = session.focusTitle
        NotificationManager.shared.cancelFocusEnd(sessionId: id)

        guard session.isActive, session.endedAt == nil, session.pausedAt == nil else { return }
        let remaining = remainingSeconds(for: session)
        guard remaining > 0 else { return }
        let endDate = Date().addingTimeInterval(TimeInterval(remaining))

        Task {
            await NotificationManager.shared.ensureAuthorization()
            do {
                try await NotificationManager.shared.scheduleFocusEnd(
                    sessionId: id,
                    focusTitle: title,
                    endDate: endDate
                )
            } catch {
                print("❌ Focus end notification failed:", error)
            }
        }
    }
}

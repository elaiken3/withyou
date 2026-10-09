//
//  CaptureSaverTests.swift
//  WithYouTests
//

import Foundation
import SwiftData
import XCTest
@testable import WithYou

@MainActor
final class CaptureSaverTests: XCTestCase {

    /// A fixed clock keeps the ordering checks exact.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private struct SchedulingFailed: Error {}

    /// In-memory store with the models a capture can create. The container is returned
    /// too so it stays alive for the whole test.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: InboxItem.self,
            VerboseReminder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    /// Creates the reminder like `ReminderStore` does, without asking for notification permission.
    private var quietScheduler: CaptureSaver.ReminderScheduler {
        { item, date, context in
            let reminder = VerboseReminder(
                title: item.title,
                startStep: item.firstStep,
                estimateMinutes: item.estimateMinutes,
                scheduledAt: date
            )
            context.insert(reminder)
            try context.save()
            return reminder.id
        }
    }

    private func suggestion(
        _ title: String,
        step: String = "Open it",
        minutes: Int = 5,
        at date: Date? = nil,
        original: String? = nil
    ) -> CaptureSuggestion {
        CaptureSuggestion(
            title: title,
            firstStep: step,
            estimateMinutes: minutes,
            scheduledAt: date,
            originalText: original ?? title
        )
    }

    private func inboxItems(in context: ModelContext) throws -> [InboxItem] {
        try context.fetch(FetchDescriptor<InboxItem>())
    }

    private func reminders(in context: ModelContext) throws -> [VerboseReminder] {
        try context.fetch(FetchDescriptor<VerboseReminder>())
    }

    // MARK: - Inbox vs scheduled

    func testUntimedSuggestionsGoToTheInbox() async throws {
        let (container, context) = try makeContext()

        let summary = try await CaptureSaver.save(
            [suggestion("Buy oat milk", original: "buy oat milk and email Sam"),
             suggestion("Email Sam", original: "buy oat milk and email Sam")],
            source: .siri,
            in: context,
            now: now,
            scheduler: quietScheduler
        )

        XCTAssertEqual(summary.inboxCount, 2)
        XCTAssertEqual(summary.scheduledCount, 0)
        XCTAssertNil(summary.firstScheduledAt)

        let items = try inboxItems(in: context)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(try reminders(in: context).isEmpty)
        for item in items {
            XCTAssertEqual(item.source, .siri)
            XCTAssertEqual(item.content, "buy oat milk and email Sam", "The original words are kept")
        }

        // The Inbox lists newest first; the first thing said should come out on top.
        let newestFirst = items.sorted { $0.createdAt > $1.createdAt }.map { $0.title }
        XCTAssertEqual(newestFirst, ["Buy oat milk", "Email Sam"])
        withExtendedLifetime(container) {}
    }

    func testTimedSuggestionsAreScheduled() async throws {
        let (container, context) = try makeContext()
        let later = now.addingTimeInterval(2 * 86_400)
        let sooner = now.addingTimeInterval(86_400)

        let summary = try await CaptureSaver.save(
            [suggestion("Call the dentist", at: later),
             suggestion("Water the plants"),
             suggestion("Finish the slides", at: sooner)],
            source: .app,
            in: context,
            now: now,
            scheduler: quietScheduler
        )

        XCTAssertEqual(summary.inboxCount, 1)
        XCTAssertEqual(summary.scheduledCount, 2)
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.firstScheduledAt, sooner, "The earliest time is the one to mention")

        let saved = try reminders(in: context)
        XCTAssertEqual(Set(saved.map { $0.title }), ["Call the dentist", "Finish the slides"])
        XCTAssertEqual(Set(saved.map { $0.id }), Set(summary.reminderIds))
        XCTAssertEqual(try inboxItems(in: context).map { $0.title }, ["Water the plants"])
        withExtendedLifetime(container) {}
    }

    func testFirstStepAndEstimateAreKept() async throws {
        let (container, context) = try makeContext()

        _ = try await CaptureSaver.save(
            [suggestion("Pay rent", step: "Open the bank app", minutes: 10)],
            source: .app,
            in: context,
            now: now,
            scheduler: quietScheduler
        )

        let item = try XCTUnwrap(try inboxItems(in: context).first)
        XCTAssertEqual(item.startStep, "Open the bank app")
        XCTAssertEqual(item.estimateMinutes, 10)
        withExtendedLifetime(container) {}
    }

    func testNothingToSaveCreatesNothing() async throws {
        let (container, context) = try makeContext()

        let summary = try await CaptureSaver.save(
            [suggestion("  ", original: " \n ")],
            source: .app,
            in: context,
            now: now,
            scheduler: quietScheduler
        )

        XCTAssertEqual(summary, CaptureSaveSummary())
        XCTAssertTrue(try inboxItems(in: context).isEmpty)
        withExtendedLifetime(container) {}
    }

    // MARK: - All or nothing

    func testAFailedReminderUndoesTheWholeSave() async throws {
        let (container, context) = try makeContext()
        let tomorrow = now.addingTimeInterval(86_400)
        // The first reminder is created, the second one fails.
        let flaky: CaptureSaver.ReminderScheduler = { item, date, context in
            if item.title == "Book the car service" { throw SchedulingFailed() }
            let reminder = VerboseReminder(title: item.title, startStep: item.firstStep, scheduledAt: date)
            context.insert(reminder)
            try context.save()
            return reminder.id
        }

        do {
            _ = try await CaptureSaver.save(
                [suggestion("Water the plants"),
                 suggestion("Call the dentist", at: tomorrow),
                 suggestion("Book the car service", at: tomorrow)],
                source: .app,
                in: context,
                now: now,
                scheduler: flaky
            )
            XCTFail("Expected the save to throw")
        } catch is SchedulingFailed {
            // Expected.
        }

        XCTAssertTrue(try inboxItems(in: context).isEmpty, "A retry must not make doubles")
        XCTAssertTrue(try reminders(in: context).isEmpty, "A retry must not make doubles")
        withExtendedLifetime(container) {}
    }

    // MARK: - Undo

    func testUndoRemovesWhatTheSaveCreated() async throws {
        let (container, context) = try makeContext()
        let keep = InboxItem(content: "Keep me", title: "Keep me", source: .app, startStep: "")
        context.insert(keep)
        try context.save()

        let summary = try await CaptureSaver.save(
            [suggestion("Buy oat milk"), suggestion("Email Sam")],
            source: .app,
            in: context,
            now: now,
            scheduler: quietScheduler
        )
        XCTAssertEqual(try inboxItems(in: context).count, 3)

        CaptureSaver.undo(summary, in: context)

        XCTAssertEqual(try inboxItems(in: context).map { $0.title }, ["Keep me"])
        withExtendedLifetime(container) {}
    }

    // MARK: - Tidying

    func testPreparedFallsBackToTheOriginalWords() throws {
        let item = try XCTUnwrap(CaptureSaver.prepared(suggestion("   ", original: "  call mom  ")))
        XCTAssertEqual(item.title, "call mom")
        XCTAssertEqual(item.originalText, "call mom")
    }

    func testPreparedKeepsTitlesOnOneLine() throws {
        let item = try XCTUnwrap(CaptureSaver.prepared(suggestion("Email\n  landlord ", step: " Open Mail\n")))
        XCTAssertEqual(item.title, "Email landlord")
        XCTAssertEqual(item.firstStep, "Open Mail")
    }

    func testPreparedClampsTheEstimate() throws {
        XCTAssertEqual(CaptureSaver.prepared(suggestion("A", minutes: 0))?.estimateMinutes, 1)
        XCTAssertEqual(CaptureSaver.prepared(suggestion("A", minutes: 999))?.estimateMinutes, 240)
    }

    func testPreparedSkipsEmptySuggestions() {
        XCTAssertNil(CaptureSaver.prepared(suggestion(" ", original: "")))
    }

    func testPreparedKeepsTheId() throws {
        let original = suggestion("Pay rent")
        XCTAssertEqual(try XCTUnwrap(CaptureSaver.prepared(original)).id, original.id)
    }

    // MARK: - Confirmation words

    private func summary(inbox: Int, scheduled dates: [Date] = []) -> CaptureSaveSummary {
        CaptureSaveSummary(
            inboxItemIds: (0..<inbox).map { _ in UUID() },
            reminderIds: dates.map { _ in UUID() },
            scheduledDates: dates
        )
    }

    func testMessageForInboxOnly() {
        XCTAssertEqual(CaptureSaver.message(for: summary(inbox: 1)), "Saved to your Inbox.")
        XCTAssertEqual(CaptureSaver.message(for: summary(inbox: 3)), "Saved 3 things to your Inbox.")
    }

    func testMessageForScheduledOnly() {
        let tomorrow = TestDates.tomorrow(at: 9, from: Date())
        let later = TestDates.day(offset: 3, at: 14, from: Date())

        XCTAssertEqual(
            CaptureSaver.message(for: summary(inbox: 0, scheduled: [tomorrow])),
            "Scheduled for \(tomorrow.friendlyDayTime)."
        )
        XCTAssertEqual(
            CaptureSaver.message(for: summary(inbox: 0, scheduled: [later, tomorrow])),
            "Scheduled 2 things, starting \(tomorrow.friendlyDayTime)."
        )
    }

    func testMessageForAMix() {
        let tomorrow = TestDates.tomorrow(at: 9, from: Date())
        let later = TestDates.day(offset: 2, at: 9, from: Date())

        XCTAssertEqual(
            CaptureSaver.message(for: summary(inbox: 1, scheduled: [tomorrow])),
            "Saved 1 thing to your Inbox and scheduled 1 for \(tomorrow.friendlyDayTime)."
        )
        XCTAssertEqual(
            CaptureSaver.message(for: summary(inbox: 2, scheduled: [later, tomorrow, later])),
            "Saved 2 things to your Inbox and scheduled 3, starting \(tomorrow.friendlyDayTime)."
        )
    }

    func testMessageWhenNothingWasSaved() {
        XCTAssertEqual(CaptureSaver.message(for: CaptureSaveSummary()), "There was nothing to save.")
    }

    func testMessagesStayCalm() {
        let tomorrow = TestDates.tomorrow(at: 9, from: Date())
        let messages = [
            summary(inbox: 0), summary(inbox: 1), summary(inbox: 4),
            summary(inbox: 0, scheduled: [tomorrow]), summary(inbox: 2, scheduled: [tomorrow, tomorrow])
        ].map { CaptureSaver.message(for: $0) }

        for message in messages {
            XCTAssertFalse(message.contains("!"), message)
            for word in ["overdue", "missed", "failed", "late"] {
                XCTAssertFalse(message.lowercased().contains(word), "“\(word)” in: \(message)")
            }
        }
    }

    // MARK: - Rules fallback

    func testRulesSuggestionMatchesTheParser() throws {
        let morning = TestDates.today(at: 10)
        let text = "  Email landlord tomorrow at 9am "
        let parsed = CaptureParser().parse(text, profile: nil, now: morning)

        let suggestions = CaptureSaver.rulesSuggestions(for: text, profile: nil, now: morning)

        XCTAssertEqual(suggestions.count, 1)
        let item = try XCTUnwrap(suggestions.first)
        XCTAssertEqual(item.title, parsed.title)
        XCTAssertEqual(item.firstStep, parsed.startStep)
        XCTAssertEqual(item.estimateMinutes, parsed.estimateMinutes)
        XCTAssertEqual(item.scheduledAt, parsed.scheduledAt)
        XCTAssertNotNil(item.scheduledAt)
        XCTAssertEqual(item.originalText, "Email landlord tomorrow at 9am")
    }

    func testRulesSuggestionWithoutATimeGoesToTheInbox() throws {
        let suggestions = CaptureSaver.rulesSuggestions(for: "Buy oat milk", profile: nil, now: TestDates.today(at: 10))
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertNil(try XCTUnwrap(suggestions.first).scheduledAt)
    }

    func testRulesSuggestionsForBlankTextAreEmpty() {
        XCTAssertTrue(CaptureSaver.rulesSuggestions(for: "  \n ", profile: nil).isEmpty)
    }

    // MARK: - Deadline

    func testFirstResultReturnsAQuickAnswer() async {
        let value = await CaptureSaver.firstResult(within: 5) { "quick" }
        XCTAssertEqual(value, "quick")
    }

    func testFirstResultGivesUpAtTheDeadline() async {
        let started = Date()
        let value = await CaptureSaver.firstResult(within: 0.2) { () -> String in
            try? await Task.sleep(for: .seconds(10))
            return "slow"
        }

        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "Should not wait for the slow answer")
    }

    func testFirstResultDoesNotWaitForWorkThatIgnoresCancellation() async {
        let started = Date()
        let value = await CaptureSaver.firstResult(within: 0.2) { () -> Int in
            // Ignores cancellation, like a request that can't be stopped: a detached
            // task isn't cancelled along with the task waiting for it.
            await Task.detached {
                try? await Task.sleep(for: .seconds(1.5))
            }.value
            return 1
        }

        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.2)
    }
}

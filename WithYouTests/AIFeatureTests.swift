//
//  AIFeatureTests.swift
//  WithYouTests
//
//  The pure parts of the AI features: what "Help me pick" chooses from (and what it leaves
//  out after "Something else"), how a broken-down step becomes the first step, today's energy,
//  and how tidied thoughts land in the Inbox with the original words kept.
//

import Foundation
import SwiftData
import XCTest
@testable import WithYou

@MainActor
final class AIFeatureTests: XCTestCase {

    /// A fixed afternoon, so "later today" never crosses midnight.
    private let now = TestDates.today(at: 14)
    private let restInterval: TimeInterval = 90 * 60

    /// In-memory store; returned with its context so it stays alive for the whole test.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: InboxItem.self,
            VerboseReminder.self,
            FocusDumpItem.self,
            UserProfile.self,
            AppState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    private func reminder(
        _ title: String,
        at date: Date,
        isDone: Bool = false,
        checkedAt: Date? = nil,
        in context: ModelContext
    ) -> VerboseReminder {
        let reminder = VerboseReminder(
            title: title,
            startStep: "Open it.",
            estimateMinutes: 10,
            scheduledAt: date,
            isDone: isDone,
            lastCheckedAt: checkedAt
        )
        context.insert(reminder)
        return reminder
    }

    private func inboxItem(_ title: String, minutes: Int = 3, in context: ModelContext) -> InboxItem {
        let item = InboxItem(content: title, title: title, source: .app, startStep: "", estimateMinutes: minutes)
        context.insert(item)
        return item
    }

    private func candidate(_ id: String, title: String? = nil, step: String = "") -> PickCandidate {
        PickCandidate(
            next: NextCandidate(id: id, title: title ?? "Task \(id)", estimateMinutes: 5, scheduledAt: nil),
            kind: .inbox,
            sourceId: UUID(),
            startStep: step
        )
    }

    // MARK: - Help me pick: candidates

    func testCandidatesAreTodaysUpcomingRemindersThenInboxInOrder() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }

        let later = reminder("Call the bank", at: TestDates.today(at: 15, minute: 30, reference: now), in: context)
        let soon = reminder("Email landlord", at: TestDates.today(at: 14, minute: 30, reference: now), in: context)
        let evening = reminder(
            "Water plants",
            at: TestDates.today(at: 18, reference: now),
            checkedAt: now.addingTimeInterval(-3 * 60 * 60), // rested long enough ago
            in: context
        )
        let earlier = reminder("Earlier today", at: TestDates.today(at: 10, reference: now), in: context)
        let first = inboxItem("Book dentist", in: context)
        let second = inboxItem("Buy stamps", in: context)

        let candidates = HelpMePick.candidates(
            inbox: [first, second],
            reminders: [later, earlier, soon, evening],
            now: now,
            restInterval: restInterval
        )
        XCTAssertEqual(candidates.map { $0.next.id }, [
            soon.id.uuidString, later.id.uuidString, evening.id.uuidString,
            first.id.uuidString, second.id.uuidString
        ])
        XCTAssertEqual(candidates.map { $0.kind }, [.reminder, .reminder, .reminder, .inbox, .inbox])
        XCTAssertEqual(candidates.map { $0.sourceId }, [soon.id, later.id, evening.id, first.id, second.id])
        XCTAssertEqual(candidates[3].next.estimateMinutes, 3)
        XCTAssertNil(candidates[3].next.scheduledAt)
    }

    func testCandidatesLeaveOutPastTomorrowDoneAndRestingReminders() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }

        let reminders = [
            reminder("Earlier today", at: TestDates.today(at: 10, reference: now), in: context),
            reminder("Tomorrow", at: TestDates.tomorrow(at: 9, from: now), in: context),
            reminder("Already done", at: TestDates.today(at: 16, reference: now), isDone: true, in: context),
            reminder(
                "Resting after Not now",
                at: TestDates.today(at: 17, reference: now),
                checkedAt: now.addingTimeInterval(-10 * 60),
                in: context
            )
        ]

        let candidates = HelpMePick.candidates(inbox: [], reminders: reminders, now: now, restInterval: restInterval)
        XCTAssertTrue(candidates.isEmpty, "Got \(candidates.map { $0.next.title })")
    }

    func testRemindersCarryScheduledInMinutesAndInboxItemsDont() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }

        let soon = reminder("Email landlord", at: TestDates.today(at: 14, minute: 30, reference: now), in: context)
        let later = reminder("Call the bank", at: TestDates.today(at: 15, minute: 30, reference: now), in: context)
        let item = inboxItem("Book dentist", in: context)

        let candidates = HelpMePick.candidates(inbox: [item], reminders: [soon, later], now: now, restInterval: restInterval)
        let input = CloudAIRequests.next(candidates.map { $0.next }, energy: .low, minutesAvailable: nil, now: now)

        XCTAssertEqual(input.candidates.map { $0.scheduledInMinutes }, [30, 90, nil])
        XCTAssertEqual(input.candidates.map { $0.id }, [soon.id.uuidString, later.id.uuidString, item.id.uuidString])
        XCTAssertEqual(input.energy, "low")
    }

    func testCandidatesSkipBlankTitlesAndStopAtThirty() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }

        var items = [inboxItem("   ", in: context)]
        for number in 1...40 {
            items.append(inboxItem("Thing \(number)", in: context))
        }

        let candidates = HelpMePick.candidates(inbox: items, reminders: [], now: now, restInterval: restInterval)
        XCTAssertEqual(candidates.count, HelpMePick.maxCandidates)
        XCTAssertEqual(candidates.first?.next.title, "Thing 1")
        XCTAssertFalse(candidates.contains { $0.next.title.isEmpty })
    }

    func testHelpMePickIsOfferedOnlyWithAChoice() {
        XCTAssertFalse(HelpMePick.canOffer([]))
        XCTAssertFalse(HelpMePick.canOffer([candidate("a")]))
        XCTAssertTrue(HelpMePick.canOffer([candidate("a"), candidate("b")]))
    }

    // MARK: - Help me pick: Something else

    func testSomethingElseLeavesOutEarlierPicksAndKeepsOrder() {
        let all = [candidate("a"), candidate("b"), candidate("c")]

        XCTAssertEqual(HelpMePick.remaining(all, excluding: []).map { $0.next.id }, ["a", "b", "c"])
        XCTAssertEqual(HelpMePick.remaining(all, excluding: ["b"]).map { $0.next.id }, ["a", "c"])
        XCTAssertEqual(HelpMePick.remaining(all, excluding: ["a", "c"]).map { $0.next.id }, ["b"])
        XCTAssertTrue(HelpMePick.remaining(all, excluding: ["a", "b", "c"]).isEmpty)
    }

    func testAskingAgainAfterSomethingElsePicksADifferentOne() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }

        let soon = reminder("Email landlord", at: TestDates.today(at: 14, minute: 30, reference: now), in: context)
        let later = reminder("Call the bank", at: TestDates.today(at: 15, minute: 30, reference: now), in: context)
        let item = inboxItem("Book dentist", in: context)
        let all = HelpMePick.candidates(inbox: [item], reminders: [soon, later], now: now, restInterval: restInterval)

        var excluded: Set<String> = []
        var picks: [String] = []
        for _ in 0..<3 {
            let pool = HelpMePick.remaining(all, excluding: excluded)
            let pick = try XCTUnwrap(AIRules.suggestNext(from: pool.map { $0.next }, energy: nil, minutesAvailable: nil))
            XCTAssertNotNil(HelpMePick.match(pick, in: pool), "The pick is one of the remaining candidates")
            picks.append(pick.candidateId)
            excluded.insert(pick.candidateId)
        }

        XCTAssertEqual(picks, [soon.id.uuidString, later.id.uuidString, item.id.uuidString])
        XCTAssertTrue(HelpMePick.remaining(all, excluding: excluded).isEmpty)
    }

    func testMatchFindsTheNamedCandidateOnly() {
        let all = [candidate("a"), candidate("b")]
        let known = NextSuggestion(candidateId: "b", reason: "It fits.", firstStep: "Open it.")
        let unknown = NextSuggestion(candidateId: "z", reason: "It fits.", firstStep: "Open it.")

        XCTAssertEqual(HelpMePick.match(known, in: all)?.next.id, "b")
        XCTAssertNil(HelpMePick.match(unknown, in: all))
    }

    func testStartStepUsesSuggestionThenSavedStepThenARule() {
        let saved = candidate("a", title: "Email landlord", step: " Find the thread. ")
        let empty = candidate("b", title: "Email landlord", step: "  ")

        let suggested = NextSuggestion(candidateId: "a", reason: "It’s small.", firstStep: " Open Mail. ")
        XCTAssertEqual(HelpMePick.startStep(for: suggested, candidate: saved), "Open Mail.")

        let blank = NextSuggestion(candidateId: "a", reason: "It’s small.", firstStep: " ")
        XCTAssertEqual(HelpMePick.startStep(for: blank, candidate: saved), "Find the thread.")
        XCTAssertEqual(
            HelpMePick.startStep(for: blank, candidate: empty),
            SmallStepSuggester.ruleBasedStep(for: "Email landlord", current: "")
        )
    }

    // MARK: - Break it down

    func testPickingTheFirstStepCapsTheEstimateAtTwoMinutes() {
        let change = BreakDownChoice.change(picking: "  Open the document.\n", at: 0, previousEstimate: 25)
        XCTAssertEqual(change.startStep, "Open the document.")
        XCTAssertEqual(change.estimateMinutes, 2)
    }

    func testPickingALaterStepCapsTheEstimateAtFiveMinutes() {
        let change = BreakDownChoice.change(picking: "Write one messy sentence.", at: 2, previousEstimate: 25)
        XCTAssertEqual(change.startStep, "Write one messy sentence.")
        XCTAssertEqual(change.estimateMinutes, 5)
    }

    func testPickingAStepNeverRaisesTheEstimateOrGoesBelowAMinute() {
        XCTAssertEqual(BreakDownChoice.change(picking: "Open it.", at: 1, previousEstimate: 3).estimateMinutes, 3)
        XCTAssertEqual(BreakDownChoice.change(picking: "Open it.", at: 0, previousEstimate: 1).estimateMinutes, 1)
        XCTAssertEqual(BreakDownChoice.change(picking: "Open it.", at: 0, previousEstimate: 0).estimateMinutes, 1)
    }

    func testRulesBreakDownGivesStepsToPickFrom() {
        let steps = AIRules.breakDown(title: "Email landlord", currentStep: "")
        XCTAssertTrue((2...5).contains(steps.count), "Got \(steps)")

        let change = BreakDownChoice.change(picking: steps[0], at: 0, previousEstimate: 10)
        XCTAssertEqual(change.startStep, steps[0])
        XCTAssertEqual(change.estimateMinutes, 2)
    }

    // MARK: - Energy, coach and attribution

    func testEnergyCountsOnlyWhenPickedToday() {
        let today = EnergyCheckIn.dayValue(for: now)
        let yesterday = EnergyCheckIn.dayValue(for: now.addingTimeInterval(-24 * 60 * 60))

        XCTAssertEqual(EnergyCheckIn.level(raw: "low", day: today, on: now), .low)
        XCTAssertEqual(EnergyCheckIn.level(raw: "good", day: today, on: TestDates.today(at: 23, reference: now)), .good)
        XCTAssertNil(EnergyCheckIn.level(raw: "low", day: yesterday, on: now))
        XCTAssertNil(EnergyCheckIn.level(raw: "", day: today, on: now))
        XCTAssertNil(EnergyCheckIn.level(raw: "tired", day: today, on: now))
        XCTAssertNil(EnergyCheckIn.level(raw: "okay", day: 0, on: now))
    }

    func testCoachButtonNamesTheMinutes() {
        XCTAssertEqual(StuckCoachText.tryTitle(minutes: 1), "Try it for 1 minute")
        XCTAssertEqual(StuckCoachText.tryTitle(minutes: 5), "Try it for 5 minutes")
    }

    func testAttributionIsQuietAndOnlyForAI() {
        XCTAssertEqual(AIAttribution.text(for: .onDevice), "Suggested on this iPhone")
        XCTAssertEqual(AIAttribution.text(for: .cloud), "Suggested by cloud AI")
        XCTAssertNil(AIAttribution.text(for: .rules))
    }

    // MARK: - Tidy thoughts into the Inbox

    func testTidiedTitleAndStepReplaceTheParsersButNotItsEstimate() {
        let parsed = ParsedCapture(title: "Call dentist about the thing", startStep: "Find the number.", estimateMinutes: 5, scheduledAt: nil)

        let tidied = CompletionStore.inboxFields(
            parsed: parsed,
            tidy: TidyItem(title: " Call the dentist ", firstStep: "Look up their number.")
        )
        XCTAssertEqual(tidied.title, "Call the dentist")
        XCTAssertEqual(tidied.startStep, "Look up their number.")
        XCTAssertEqual(tidied.estimateMinutes, 5)

        let noStep = CompletionStore.inboxFields(parsed: parsed, tidy: TidyItem(title: "Call the dentist", firstStep: " "))
        XCTAssertEqual(noStep.startStep, "Find the number.")

        let blankTitle = CompletionStore.inboxFields(parsed: parsed, tidy: TidyItem(title: "  ", firstStep: "Look it up."))
        XCTAssertEqual(blankTitle.title, parsed.title)
        XCTAssertEqual(blankTitle.startStep, parsed.startStep)

        let none = CompletionStore.inboxFields(parsed: parsed, tidy: nil)
        XCTAssertEqual(none.title, parsed.title)
        XCTAssertEqual(none.startStep, parsed.startStep)
    }

    func testMovedThoughtsKeepTheirWordsAndUseTidiedTitles() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }

        let sessionId = UUID()
        let messy = FocusDumpItem(text: "ugh need to call the dentist about the thing", sessionId: sessionId)
        let plain = FocusDumpItem(text: "buy milk", sessionId: sessionId)
        context.insert(messy)
        context.insert(plain)
        try context.save()

        CompletionStore.moveThoughtsToInbox(
            [messy, plain],
            tidied: [messy.id: TidyItem(title: "Call the dentist", firstStep: "Find their number.")],
            in: context
        )
        try context.save()

        let inbox = try context.fetch(FetchDescriptor<InboxItem>())
        XCTAssertEqual(inbox.count, 2)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FocusDumpItem>()).isEmpty, "Moved thoughts leave the dump")

        let tidiedItem = try XCTUnwrap(inbox.first { $0.content == "ugh need to call the dentist about the thing" })
        XCTAssertEqual(tidiedItem.title, "Call the dentist")
        XCTAssertEqual(tidiedItem.startStep, "Find their number.")

        let parsed = CaptureParser().parse("buy milk", profile: nil)
        let plainItem = try XCTUnwrap(inbox.first { $0.content == "buy milk" })
        XCTAssertEqual(plainItem.title, parsed.title)
        XCTAssertEqual(plainItem.startStep, parsed.startStep)
        XCTAssertEqual(plainItem.estimateMinutes, parsed.estimateMinutes)
    }
}

//
//  VoiceCaptureTests.swift
//  WithYouTests
//
//  The pure parts of voice capture: when listening stops by itself, how rounds of speech
//  join, the mic level, and the words on the voice and review screens.
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class VoiceCaptureTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func seconds(_ value: TimeInterval) -> Date {
        start.addingTimeInterval(value)
    }

    // MARK: - Auto-stop

    func testKeepsListeningWhileWordsAreComing() {
        XCTAssertNil(VoiceAutoStop.reason(startedAt: start, lastSpeechAt: seconds(10), now: seconds(11)))
    }

    func testStopsAfterAQuietPause() {
        XCTAssertNil(VoiceAutoStop.reason(startedAt: start, lastSpeechAt: seconds(10), now: seconds(12.4)))
        XCTAssertEqual(VoiceAutoStop.reason(startedAt: start, lastSpeechAt: seconds(10), now: seconds(12.5)), .silence)
    }

    func testWaitsLongerForTheFirstWords() {
        XCTAssertNil(VoiceAutoStop.reason(startedAt: start, lastSpeechAt: nil, now: seconds(5)))
        XCTAssertEqual(VoiceAutoStop.reason(startedAt: start, lastSpeechAt: nil, now: seconds(8)), .nothingHeard)
    }

    func testStopsAtTheTimeLimitEvenWhileTalking() {
        XCTAssertEqual(VoiceAutoStop.reason(startedAt: start, lastSpeechAt: seconds(59.9), now: seconds(60)), .timeLimit)
    }

    func testAutoStopMessagesAreKind() {
        let reasons: [VoiceAutoStop.Reason] = [.silence, .nothingHeard, .timeLimit, .interrupted]
        for reason in reasons {
            let message = VoiceAutoStop.message(for: reason)
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("!"), message)
            for word in ["error", "failed", "wrong"] {
                XCTAssertFalse(message.lowercased().contains(word), "“\(word)” in: \(message)")
            }
        }
    }

    // MARK: - Joining rounds

    func testJoinAddsNewWordsAfterEarlierOnes() {
        XCTAssertEqual(VoiceTranscript.joined("Buy oat milk.", "Call mom tomorrow."), "Buy oat milk. Call mom tomorrow.")
    }

    func testJoinTrimsAndSkipsEmptyParts() {
        XCTAssertEqual(VoiceTranscript.joined("", " Call mom "), "Call mom")
        XCTAssertEqual(VoiceTranscript.joined(" Buy milk \n", ""), "Buy milk")
        XCTAssertEqual(VoiceTranscript.joined("  ", "  "), "")
    }

    // MARK: - Mic level

    func testLevelIsZeroForSilenceAndBadInput() {
        XCTAssertEqual(VoiceLevel.normalized(rms: 0), 0)
        XCTAssertEqual(VoiceLevel.normalized(rms: -1), 0)
        XCTAssertEqual(VoiceLevel.normalized(rms: .nan), 0)
        XCTAssertEqual(VoiceLevel.normalized(rms: 0.000_1), 0, "-80 dB is a quiet room")
    }

    func testLevelStaysBetweenZeroAndOne() {
        XCTAssertEqual(VoiceLevel.normalized(rms: 1), 1, "0 dB is as loud as it gets")
        let middle = VoiceLevel.normalized(rms: 0.01)   // -40 dB
        XCTAssertEqual(middle, 0.25, accuracy: 0.001)
    }

    func testLevelRisesWithVolume() {
        XCTAssertLessThan(VoiceLevel.normalized(rms: 0.005), VoiceLevel.normalized(rms: 0.05))
    }

    // MARK: - Problems

    func testPermissionProblemsOfferSettings() {
        XCTAssertTrue(VoiceIssue.microphoneDenied.opensSettings)
        XCTAssertTrue(VoiceIssue.speechDenied.opensSettings)
        XCTAssertFalse(VoiceIssue.unavailable.opensSettings)
        XCTAssertFalse(VoiceIssue.audioFailed.opensSettings)
    }

    func testEveryProblemOffersTypingInstead() {
        let issues: [VoiceIssue] = [.microphoneDenied, .speechDenied, .unavailable, .audioFailed]
        for issue in issues {
            XCTAssertTrue(issue.message.contains("type instead"), issue.message)
            XCTAssertFalse(issue.message.contains("!"), issue.message)
        }
    }

    // MARK: - Routing

    func testVoiceDeepLinkOpensVoiceCapture() {
        let router = AppRouter.shared
        let earlier = router.consume()

        router.open(deepLink: "withyou://voice")
        // Consumed in the same turn so the running app never acts on it.
        XCTAssertEqual(router.consume(), .voiceCapture)

        if let earlier {
            router.open(earlier)
        }
    }

    // MARK: - Review screen words

    func testSaveButtonTitle() {
        XCTAssertEqual(CaptureReviewText.saveTitle(count: 0), "Save")
        XCTAssertEqual(CaptureReviewText.saveTitle(count: 1), "Save")
        XCTAssertEqual(CaptureReviewText.saveTitle(count: 3), "Save 3")
        XCTAssertEqual(CaptureReviewText.saveAccessibilityLabel(count: 1), "Save 1 item")
        XCTAssertEqual(CaptureReviewText.saveAccessibilityLabel(count: 3), "Save 3 items")
    }

    func testAttributionOnlyForAI() {
        XCTAssertEqual(CaptureReviewText.attribution(for: .onDevice), "Suggested on this iPhone")
        XCTAssertEqual(CaptureReviewText.attribution(for: .cloud), "Suggested by cloud AI")
        XCTAssertNil(CaptureReviewText.attribution(for: .rules))
    }

    func testDestinationWords() {
        let tomorrow = TestDates.tomorrow(at: 9, from: Date())
        XCTAssertEqual(CaptureReviewText.destination(for: nil), "→ Inbox")
        XCTAssertEqual(CaptureReviewText.destination(for: tomorrow), "→ \(tomorrow.friendlyDayTime)")
        XCTAssertEqual(CaptureReviewText.spokenDestination(for: nil), "Goes to your Inbox")
        XCTAssertEqual(CaptureReviewText.spokenDestination(for: tomorrow), "Scheduled for \(tomorrow.friendlyDayTime)")
    }

    func testReviewRowRemembersTheSuggestedTime() {
        let tomorrow = TestDates.tomorrow(at: 9, from: Date())
        var row = CaptureReviewRow(
            CaptureSuggestion(title: "Call the dentist", firstStep: "Find the number", estimateMinutes: 5,
                              scheduledAt: tomorrow, originalText: "call the dentist tomorrow")
        )
        XCTAssertTrue(row.isIncluded)

        row.suggestion.scheduledAt = nil   // "Put it in the Inbox instead"
        XCTAssertEqual(row.suggestedDate, tomorrow, "So it can be scheduled again")
    }
}

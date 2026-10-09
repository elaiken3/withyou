//
//  SmallStepSuggesterTests.swift
//  WithYouTests
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class SmallStepSuggesterTests: XCTestCase {

    /// One title per rule, plus one that only matches the generic fallback.
    private let titles = [
        "Email landlord",
        "Reply to Sam",
        "Text Alex back",
        "Call dentist",
        "Pay rent",
        "Clean kitchen",
        "Write cover letter",
        "Book haircut appointment",
        "Water the plants"
    ]

    func testNeverReturnsTheCurrentStep() {
        for title in titles {
            let first = SmallStepSuggester.ruleBasedStep(for: title, current: "")
            XCTAssertFalse(first.isEmpty, title)

            // Asking again from the suggestion we just gave must offer something different.
            let second = SmallStepSuggester.ruleBasedStep(for: title, current: first)
            XCTAssertNotEqual(second, first, title)
            XCTAssertFalse(second.isEmpty, title)

            // Surrounding whitespace doesn't make the same step count as new.
            let padded = SmallStepSuggester.ruleBasedStep(for: title, current: "  \(first)\n")
            XCTAssertNotEqual(padded, first, title)
        }
    }

    func testGenericStepIsNotRepeated() {
        let step = SmallStepSuggester.ruleBasedStep(for: "Water the plants", current: SmallStepSuggester.genericStep)
        XCTAssertNotEqual(step, SmallStepSuggester.genericStep)
    }

    func testEmailTitlesMentionMail() {
        for title in ["Email landlord", "email the school about Friday"] {
            let step = SmallStepSuggester.ruleBasedStep(for: title, current: "")
            XCTAssertTrue(step.contains("Mail"), "\(title) → \(step)")
        }
    }
}

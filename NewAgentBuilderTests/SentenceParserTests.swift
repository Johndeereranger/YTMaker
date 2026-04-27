import XCTest
@testable import NewAgentBuilder

final class SentenceParserTests: XCTestCase {

    func testBasicSentenceSplit() {
        XCTAssertEqual(
            SentenceParser.parse("Hello world. This is next."),
            ["Hello world.", "This is next."]
        )
    }

    func testAbbreviationDoesNotSplit() {
        XCTAssertEqual(
            SentenceParser.parse("Dr. Smith went home. He slept."),
            ["Dr. Smith went home.", "He slept."]
        )
    }

    func testDecimalDoesNotSplit() {
        XCTAssertEqual(
            SentenceParser.parse("The value is 3.14. That is pi-ish."),
            ["The value is 3.14.", "That is pi-ish."]
        )
    }

    func testQuoteStartSplits() {
        XCTAssertEqual(
            SentenceParser.parse("He stopped. \"Then he left.\""),
            ["He stopped.", "\"Then he left.\""]
        )
    }

    func testParenProseStartSplits() {
        XCTAssertEqual(
            SentenceParser.parse("He stopped. (Then he left.)"),
            ["He stopped.", "(Then he left.)"]
        )
    }

    func testStageDirectionBetweenSentencesIsRemoved() {
        XCTAssertEqual(
            SentenceParser.parse("He ran away. (dramatic music) Then he hid."),
            ["He ran away.", "Then he hid."]
        )
    }

    func testApplauseBetweenSentencesIsRemoved() {
        XCTAssertEqual(
            SentenceParser.parse("We looked up. (applause) And then we continued."),
            ["We looked up.", "And then we continued."]
        )
    }

    func testLyricMarkerBetweenSentencesIsRemoved() {
        XCTAssertEqual(
            SentenceParser.parse("He paused. ♪ suspenseful sting ♪ Then spoke again."),
            ["He paused.", "Then spoke again."]
        )
    }

    func testInlineDashDoesNotSplit() {
        XCTAssertEqual(
            SentenceParser.parse("This matters - but not for the reason you think."),
            ["This matters - but not for the reason you think."]
        )
    }

    func testDashWithoutPunctuationDoesNotSplit() {
        XCTAssertEqual(
            SentenceParser.parse("He paused - and then continued talking without a period"),
            ["He paused - and then continued talking without a period"]
        )
    }

    func testPreformattedLinesPassThrough() {
        let text = """
        This is the first sentence.
        This is the second sentence.
        """

        XCTAssertEqual(
            SentenceParser.parse(text),
            ["This is the first sentence.", "This is the second sentence."]
        )
    }
}

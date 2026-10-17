import XCTest
@testable import ClearBrowser

final class TextReaderTests: XCTestCase {
    func testChunkingPreservesLongUnicodeDocumentExactly() {
        let input = String(repeating: "Hello 👨‍👩‍👧‍👦. 你好！ Café is open.\n\n", count: 2_000)
        let pages = ReaderText.chunks(input)
        XCTAssertEqual(pages.joined(), input)
        XCTAssertTrue(pages.allSatisfy { !$0.isEmpty && $0.count <= 3_000 })
        XCTAssertGreaterThan(pages.count, 1)
    }

    func testOverlongTokenStillMakesProgress() {
        let input = String(repeating: "a", count: 9_001)
        XCTAssertEqual(ReaderText.chunks(input).map(\.count), [3_000, 3_000, 3_000, 1])
        XCTAssertEqual(ReaderText.chunks(input).joined(), input)
    }

    func testEmptyAndExactBoundary() {
        XCTAssertEqual(ReaderText.chunks(""), [])
        let input = String(repeating: "x", count: 3_000)
        XCTAssertEqual(ReaderText.chunks(input), [input])
    }

    func testPrefersSentenceBoundaryOverLaterWhitespace() {
        let input = "First sentence. More words to follow here"
        let pages = ReaderText.chunks(input, limit: 25)
        XCTAssertEqual(pages.first, "First sentence.")
        XCTAssertEqual(pages.joined(), input)
    }

    func testRepeatedSentenceRangesAdvanceAndPreserveOriginalText() {
        let text = "Hello again.\n\nHello again."
        let timings = [
            ReaderTiming(text: "Hello again.", start: 0, duration: 1, end: 1),
            ReaderTiming(text: "Hello again.", start: 1.5, duration: 1, end: 2.5)
        ]
        let spans = ReaderSpan.map(timings, to: text)
        XCTAssertEqual(spans.count, 2)
        XCTAssertNotEqual(spans[0].range, spans[1].range)
        XCTAssertEqual(String(text[spans[1].range]), "Hello again.")
        XCTAssertFalse(1.2 >= spans[0].start && 1.2 < spans[0].end)
    }

    func testUnmatchedTimingsDoNotHighlightUnrelatedText() {
        let timing = ReaderTiming(text: "Unrelated sentence", start: 0, duration: 1, end: nil)
        XCTAssertTrue(ReaderSpan.map([timing], to: "Actual document text.").isEmpty)
    }

    func testNormalizedServerWhitespaceMatchesOriginalText() {
        let text = "Hello   world.\n\nMore text."
        let timing = ReaderTiming(text: "Hello world.", start: 0, duration: 1, end: nil)
        let spans = ReaderSpan.map([timing], to: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(String(text[spans[0].range]), "Hello   world.")
    }

    func testNullServerTimingIsDecodedAndSkipped() throws {
        let payload = Data(#"{"sentenceTimings":[{"text":"!","start":null,"duration":0,"end":null}]}"#.utf8)
        let timings = try JSONDecoder().decode(ReaderTimings.self, from: payload)
        XCTAssertTrue(ReaderSpan.map(timings.sentenceTimings ?? [], to: "!").isEmpty)
    }

    func testAudioVixTimingPayloadAndOptionalTimingData() throws {
        let payload = Data(#"{"sentenceTimings":[{"text":"Hello.","start":0.2,"end":1.5}],"wordTimings":[]}"#.utf8)
        let timings = try JSONDecoder().decode(ReaderTimings.self, from: payload)
        XCTAssertEqual(timings.sentenceTimings?.first?.endTime, 1.5)
        XCTAssertNil(try JSONDecoder().decode(ReaderTimings.self, from: Data("{}".utf8)).sentenceTimings)
    }

    func testDocumentRoundTripKeepsResumeState() throws {
        var document = ReaderDocument(title: "Saved reading", sourceURL: "https://example.com", pages: ["One.", "Two."])
        document.page = 1
        document.position = 12.5
        document.speed = 1.5
        let restored = try JSONDecoder().decode(ReaderDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(restored.id, document.id)
        XCTAssertEqual(restored.pages, document.pages)
        XCTAssertEqual(restored.page, 1)
        XCTAssertEqual(restored.position, 12.5)
        XCTAssertEqual(restored.speed, 1.5)
    }
}

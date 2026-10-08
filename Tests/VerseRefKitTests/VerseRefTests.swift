import XCTest

@testable import VerseRefKit

// Cases live in data/tests and are shared with the Kotlin library's tests.
final class VerseRefTests: XCTestCase {

    private func cases(_ name: String) throws -> [(String, String)] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/tests/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { line in
                let parts = line.components(separatedBy: "\t")
                return (parts[0], parts.count > 1 ? parts[1] : "")
            }
    }

    func testReadableToUsfm() throws {
        for (input, expected) in try cases("usfm.tsv") {
            XCTAssertEqual(VerseRef.usfm(from: input), expected, input)
        }
    }

    func testUsfmToReadable() throws {
        for (input, expected) in try cases("readable.tsv") {
            XCTAssertEqual(VerseRef.humanReadable(from: input), expected, input)
        }
    }

    func testFindsReferenceSpans() throws {
        for (text, expected) in try cases("spans.tsv") {
            let spans = VerseRef.findReferenceSpans(in: text).map(\.text).joined(separator: " | ")
            XCTAssertEqual(spans, expected, text)
        }
    }

    func testSpanRangesPointAtTheMatchedText() {
        let text = "a യോഹ. 3:16, b"
        let spans = VerseRef.findReferenceSpans(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(String(text[spans[0].range]), spans[0].text)
    }

    func testLegacyZwjChilluMatches() {
        let legacy = "യോഹന്നാന\u{0D4D}\u{200D} 3:16"
        XCTAssertEqual(VerseRef.usfm(from: legacy), "JHN.3.16")
        XCTAssertEqual(VerseRef.findReferenceSpans(in: legacy).count, 1)
    }

    func testEnglishOrderingAndNames() {
        XCTAssertEqual(BibleReference(book: "1CO", chapter: 3, verse: 4).bookName, "1 Corinthians")
        XCTAssertTrue(BibleReference(book: "GEN", chapter: 1, verse: 1) < BibleReference(book: "EXO", chapter: 1, verse: 1))
    }
}

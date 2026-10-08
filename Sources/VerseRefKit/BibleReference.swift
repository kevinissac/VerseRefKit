import Foundation

/// A single parsed Bible reference.
///
/// - Book only:    `BibleReference(book: "GEN", chapter: nil, verse: nil)`
/// - Chapter only: `BibleReference(book: "GEN", chapter: 1, verse: nil)`
/// - Verse:        `BibleReference(book: "GEN", chapter: 1, verse: 2)`
public struct BibleReference: Hashable, Codable, Comparable, Sendable {

    /// Canonical USFM book code, e.g. `"GEN"`, `"2CO"`.
    public let book: String

    /// `nil` = whole-book reference.
    public let chapter: Int?

    /// `nil` = whole-chapter reference.
    public let verse: Int?

    public init(book: String, chapter: Int?, verse: Int?) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
    }

    /// The full display name of the book, e.g. `"2 Corinthians"`.
    public var bookName: String {
        VerseRef.nameForCode(book) ?? book
    }

    // MARK: Comparable — canonical Bible ordering

    public static func < (lhs: BibleReference, rhs: BibleReference) -> Bool {
        let li = VerseRef.bookIndex(lhs.book) ?? Int.max
        let ri = VerseRef.bookIndex(rhs.book) ?? Int.max
        if li != ri { return li < ri }
        let lc = lhs.chapter ?? 0
        let rc = rhs.chapter ?? 0
        if lc != rc { return lc < rc }
        return (lhs.verse ?? 0) < (rhs.verse ?? 0)
    }
}

/// A reference found inside free text: where it is and what it says.
public struct ReferenceSpan: Hashable, Sendable {
    public let range: Range<String.Index>
    public let text: String
}

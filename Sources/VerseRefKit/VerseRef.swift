import Foundation

/// Converts between USFM-style Bible references and human-readable strings, in any
/// supported language, and finds references inside free text.
///
/// ```swift
/// VerseRef.usfm(from: "1 Cor 3:4")             // "1CO.3.4"
/// VerseRef.usfm(from: "റോമർ 8:28")             // "ROM.8.28"
/// VerseRef.humanReadable(from: "GEN.1.2 + GEN.1.3") // "Genesis 1:2–3"
/// ```
public enum VerseRef {

    // MARK: - Book Tables (generated into BookData.swift)

    private static let canonicalBooks = BookData.canonicalBooks

    private static let bookNames: [String: String] = {
        Dictionary(uniqueKeysWithValues: canonicalBooks.map { ($0.code, $0.name) })
    }()

    private static let bookOrder: [String: Int] = {
        Dictionary(uniqueKeysWithValues: canonicalBooks.enumerated().map { ($1.code, $0) })
    }()

    // Legacy Malayalam encodes a chillu as consonant + virama + ZWJ; the data files
    // and lookups use the atomic chillu code points.
    private static let legacyChillus: [(legacy: String, atomic: String)] = [
        ("ണ\u{0D4D}\u{200D}", "ൺ"), ("ന\u{0D4D}\u{200D}", "ൻ"), ("ര\u{0D4D}\u{200D}", "ർ"),
        ("ല\u{0D4D}\u{200D}", "ൽ"), ("ള\u{0D4D}\u{200D}", "ൾ"),
    ]

    private static func normalizeBookKey(_ raw: String) -> String {
        var key =
            raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        for (legacy, atomic) in legacyChillus {
            key = key.replacingOccurrences(of: legacy, with: atomic, options: .literal)
        }
        return key
    }

    /// Normalised lowercase string → canonical USFM code.
    private static let bookLookup: [String: String] = {
        var lookup: [String: String] = [:]
        for (code, name) in canonicalBooks { lookup[name.lowercased()] = code }
        for (alias, code) in BookData.englishAliases { lookup[alias] = code }
        for language in BookData.languageNames {
            for (code, names) in language {
                for name in names { lookup[normalizeBookKey(name)] = code }
            }
        }
        return lookup
    }()

    private static let chapterVerseCounts = BookData.chapterVerseCounts

    // MARK: - Accessors

    public static func nameForCode(_ code: String) -> String? {
        bookNames[code.uppercased()]
    }

    public static func bookIndex(_ code: String) -> Int? {
        bookOrder[code.uppercased()]
    }

    public static func chapterCount(_ code: String) -> Int? {
        chapterVerseCounts[code.uppercased()]?.count
    }

    // MARK: - Public API

    /// Converts a USFM reference string to a human-readable string.
    ///
    /// - Parameter usfm: e.g. `"GEN"`, `"2CO.12"`, `"GEN.1.2 + GEN.1.3"`
    /// - Returns: e.g. `"Genesis"`, `"2 Corinthians 12"`, `"Genesis 1:2–3"`
    public static func humanReadable(from usfm: String) -> String {
        let refs = parseUSFM(usfm)
        guard !refs.isEmpty else { return usfm }
        return formatReferences(refs)
    }

    /// Converts a human-readable reference to a USFM string.
    ///
    /// - Parameter readable: e.g. `"Gen 1:2"`, `"1 Cor 3:4"`, `"Genesis 1:2, 4, 6"`
    /// - Returns: e.g. `"GEN.1.2"`, `"1CO.3.4"`, `"GEN.1.2 + GEN.1.4 + GEN.1.6"`
    public static func usfm(from readable: String) -> String {
        let refs = parseHumanReadable(readable)
        guard !refs.isEmpty else { return readable }
        return formatUSFM(refs)
    }

    /// Parses a USFM string into an array of `BibleReference` values.
    public static func parse(usfm: String) -> [BibleReference] {
        parseUSFM(usfm)
    }

    /// Parses a human-readable string into an array of `BibleReference` values.
    public static func parse(readable: String) -> [BibleReference] {
        parseHumanReadable(readable)
    }

    // MARK: - USFM Parsing

    private static func parseUSFM(_ usfm: String) -> [BibleReference] {
        usfm
            .components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { part -> BibleReference? in
                let components = part.components(separatedBy: ".")
                guard !components.isEmpty else { return nil }

                // Resolve alternate codes (e.g. SOS → SNG, EZE → EZK)
                let book = resolvedCode(for: components[0].uppercased())
                guard bookNames[book] != nil else { return nil }

                // Book-only: "GEN"
                guard components.count >= 2, let chapter = Int(components[1]) else {
                    return BibleReference(book: book, chapter: nil, verse: nil)
                }

                // Chapter-only: "GEN.1"
                guard components.count >= 3, let verse = Int(components[2]) else {
                    return BibleReference(book: book, chapter: chapter, verse: nil)
                }

                // Full: "GEN.1.2"
                return BibleReference(book: book, chapter: chapter, verse: verse)
            }
    }

    // MARK: - Human-Readable Parsing

    private static func parseHumanReadable(_ readable: String) -> [BibleReference] {
        var result: [BibleReference] = []

        // Track the last seen book + chapter so bare verse numbers after a comma
        // can inherit context: "Genesis 1:2, 4, 6" → GEN.1.2, GEN.1.4, GEN.1.6
        var lastBook: String?
        var lastChapter: Int?

        let parts =
            readable
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        for part in parts {

            // ── Bare verse continuation: "4" or "6" after "Genesis 1:2" ──
            if let book = lastBook,
                let chapter = lastChapter,
                let verse = Int(part)
            {
                result.append(BibleReference(book: book, chapter: chapter, verse: verse))
                continue
            }

            // ── Full reference pattern ─────────────────────────────────────
            //
            // Groups:
            //   1 – book name  (required; may start with "1 ", "2 ", "3 ")
            //   2 – chapter    (optional)
            //   3 – start verse (optional)
            //   4 – end verse for a range (optional)
            let pattern =
                #"^((?:\d[\s.])?\p{L}[\p{L}\p{M}\u200C\u200D.\s]*?)(?:\s*(\d+)(?::(\d+)(?:[–—-](\d+))?)?)?$"#

            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: part, range: NSRange(part.startIndex..., in: part)),
                let bookNameRange = Range(match.range(at: 1), in: part)
            else { continue }

            // Normalise & look up the book name
            let rawName = String(part[bookNameRange]).trimmingCharacters(in: .whitespaces)
            let normKey = normalizeBookKey(rawName)

            guard let bookCode = bookLookup[normKey] else { continue }

            // Chapter (group 2)
            let chapter: Int?
            if match.range(at: 2).location != NSNotFound,
                let r = Range(match.range(at: 2), in: part)
            {
                chapter = Int(part[r])
            } else {
                chapter = nil
            }

            // Start verse (group 3)
            let startVerse: Int?
            if match.range(at: 3).location != NSNotFound,
                let r = Range(match.range(at: 3), in: part)
            {
                startVerse = Int(part[r])
            } else {
                startVerse = nil
            }

            // End verse for range (group 4)
            let endVerse: Int?
            if match.range(at: 4).location != NSNotFound,
                let r = Range(match.range(at: 4), in: part)
            {
                endVerse = Int(part[r])
            } else {
                endVerse = nil
            }

            // Update continuation context
            lastBook = bookCode
            lastChapter = chapter

            // Emit
            if let chapter = chapter {
                if let sv = startVerse {
                    result.append(BibleReference(book: bookCode, chapter: chapter, verse: sv))
                    if let ev = endVerse, ev > sv {
                        for v in (sv + 1)...ev {
                            result.append(
                                BibleReference(book: bookCode, chapter: chapter, verse: v))
                        }
                    }
                } else {
                    result.append(BibleReference(book: bookCode, chapter: chapter, verse: nil))
                }
            } else {
                result.append(BibleReference(book: bookCode, chapter: nil, verse: nil))
            }
        }

        return result
    }

    // MARK: - Free-Text Reference Scanning

    /// Built from every known book name/abbreviation, longest first so "1 corinthians"
    /// wins over "1 co" (regex alternation takes the first successful alternative).
    /// `\b` is not used: it splits Indic words at combining marks.
    private static let findReferencesRegex: NSRegularExpression = {
        func escaped(_ key: String) -> String {
            var pattern = NSRegularExpression.escapedPattern(for: key)
                .replacingOccurrences(of: " ", with: "\\s+")
            for (legacy, atomic) in legacyChillus {
                pattern = pattern.replacingOccurrences(of: atomic, with: "(?:\(atomic)|\(legacy))")
            }
            return pattern
        }
        let alternatives = bookLookup.keys
            .sorted { $0.count > $1.count }
            .map(escaped)
            .joined(separator: "|")
        let pattern =
            "(?<![\\p{L}\\p{M}\\p{N}])(\(alternatives))\\.?\\s+(\\d{1,3})(?::(\\d{1,3})(?:[-–—](\\d{1,3}))?)?(?!\\p{N})"
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    /// Scans free-form text for Bible references anywhere within it — unlike
    /// `parse(readable:)`, which requires the whole string to be one reference.
    /// A verse range like "Rom 8:28-30" expands to one `BibleReference` per verse.
    public static func findReferences(in text: String) -> [BibleReference] {
        var result: [BibleReference] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for match in findReferencesRegex.matches(in: text, range: fullRange) {
            guard match.range(at: 1).location != NSNotFound,
                match.range(at: 2).location != NSNotFound,
                let chapter = Int(nsText.substring(with: match.range(at: 2)))
            else { continue }

            guard let bookCode = bookLookup[normalizeBookKey(nsText.substring(with: match.range(at: 1)))]
            else { continue }

            guard match.range(at: 3).location != NSNotFound,
                let startVerse = Int(nsText.substring(with: match.range(at: 3)))
            else {
                result.append(BibleReference(book: bookCode, chapter: chapter, verse: nil))
                continue
            }

            result.append(BibleReference(book: bookCode, chapter: chapter, verse: startVerse))

            if match.range(at: 4).location != NSNotFound,
                let endVerse = Int(nsText.substring(with: match.range(at: 4))),
                endVerse > startVerse
            {
                for verse in (startVerse + 1)...endVerse {
                    result.append(BibleReference(book: bookCode, chapter: chapter, verse: verse))
                }
            }
        }

        return result
    }

    /// Like `findReferences(in:)` but returns each match's position and original text
    /// (a range stays one span), for turning references in prose into links.
    public static func findReferenceSpans(in text: String) -> [ReferenceSpan] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return findReferencesRegex.matches(in: text, range: fullRange).compactMap { match in
            guard bookLookup[normalizeBookKey(nsText.substring(with: match.range(at: 1)))] != nil,
                let range = Range(match.range, in: text)
            else { return nil }
            return ReferenceSpan(range: range, text: String(text[range]))
        }
    }

    // MARK: - USFM Formatting

    private static func formatUSFM(_ refs: [BibleReference]) -> String {
        refs.sorted()
            .map { ref -> String in
                guard let chapter = ref.chapter else { return ref.book }
                guard let verse = ref.verse else { return "\(ref.book).\(chapter)" }
                return "\(ref.book).\(chapter).\(verse)"
            }
            .joined(separator: " + ")
    }

    // MARK: - Human-Readable Formatting

    private static func formatReferences(_ refs: [BibleReference]) -> String {
        let sorted = refs.sorted()
        guard let first = sorted.first else { return "" }

        // ── Single reference ──────────────────────────────────────────────
        if sorted.count == 1 { return label(for: first) }

        let sameBook = sorted.allSatisfy { $0.book == first.book }
        let sameChapter = sorted.allSatisfy { $0.chapter == first.chapter }
        let allWholeBook = sorted.allSatisfy { $0.chapter == nil }
        let allWholeChapter = sorted.allSatisfy { $0.verse == nil && $0.chapter != nil }

        // ── Multiple whole-book references ────────────────────────────────
        if allWholeBook {
            return sorted.map { $0.bookName }.joined(separator: "; ")
        }

        // ── Same book, all whole-chapter ──────────────────────────────────
        if sameBook && allWholeChapter {
            let chapters = sorted.compactMap { $0.chapter }
            if isConsecutive(chapters) {
                return "\(first.bookName) \(chapters.first!)–\(chapters.last!)"
            } else {
                return chapters.map { "\(first.bookName) \($0)" }.joined(separator: ", ")
            }
        }

        // ── Same book & chapter, verse-level ──────────────────────────────
        if sameBook && sameChapter, let chapter = first.chapter {
            let verses = sorted.compactMap { $0.verse }
            if !verses.isEmpty {
                if isConsecutive(verses) {
                    return "\(first.bookName) \(chapter):\(verses.first!)–\(verses.last!)"
                } else {
                    return
                        "\(first.bookName) \(chapter):\(verses.map(String.init).joined(separator: ", "))"
                }
            }
        }

        // ── Same book, cross-chapter ──────────────────────────────────────
        if sameBook {
            // Two-verse cross-chapter range (e.g. "Genesis 1:31–2:1")
            if sorted.count == 2,
                let c1 = sorted[0].chapter, let v1 = sorted[0].verse,
                let c2 = sorted[1].chapter, let v2 = sorted[1].verse,
                c1 < c2,
                isLastVerseOfChapter(book: first.book, chapter: c1, verse: v1),
                v2 == 1
            {
                return "\(first.bookName) \(c1):\(v1)–\(c2):\(v2)"
            }

            return
                sorted
                .map { label(for: $0, bookName: first.bookName) }
                .joined(separator: ", ")
        }

        // ── Different books ───────────────────────────────────────────────
        return sorted.map { label(for: $0) }.joined(separator: "; ")
    }

    // MARK: - Helpers

    /// Produces a single human-readable label for a reference.
    private static func label(for ref: BibleReference, bookName override: String? = nil) -> String {
        let name = override ?? ref.bookName
        guard let chapter = ref.chapter else { return name }
        guard let verse = ref.verse else { return "\(name) \(chapter)" }
        return "\(name) \(chapter):\(verse)"
    }

    private static func isConsecutive(_ numbers: [Int]) -> Bool {
        guard numbers.count > 1 else { return false }
        return zip(numbers, numbers.dropFirst()).allSatisfy { $1 - $0 == 1 }
    }

    /// Returns `true` when `verse` is the final verse of `chapter` in `book`.
    /// Uses the precise chapter-verse table; falls back to a heuristic if data is absent.
    private static func isLastVerseOfChapter(book: String, chapter: Int, verse: Int) -> Bool {
        if let counts = chapterVerseCounts[book], chapter <= counts.count {
            return verse == counts[chapter - 1]
        }
        return verse > 20  // fallback heuristic
    }

    /// Maps known alternate USFM codes to the canonical code used in this formatter.
    private static func resolvedCode(for code: String) -> String {
        BookData.codeAliases[code] ?? code
    }
}

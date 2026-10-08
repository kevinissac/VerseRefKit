package com.kevinissac.verserefkit

// MARK: - VerseRef

object VerseRef {

    // All 66 canonical books in Bible order
    private val canonicalBooks: List<Pair<String, String>> = BookData.canonicalBooks

    // USFM code → display name
    private val bookNames: Map<String, String> =
        canonicalBooks.associate { (code, name) -> code to name }

    // USFM code → canonical index (for sort ordering)
    private val bookOrder: Map<String, Int> =
        canonicalBooks.mapIndexed { index, (code, _) -> code to index }.toMap()

    // Legacy Malayalam encodes a chillu as consonant + virama + ZWJ; the data files
    // and lookups use the atomic chillu code points.
    private val legacyChillus = mapOf(
        "ണ\u0D4D\u200D" to "ൺ", "ന\u0D4D\u200D" to "ൻ", "ര\u0D4D\u200D" to "ർ",
        "ല\u0D4D\u200D" to "ൽ", "ള\u0D4D\u200D" to "ൾ",
    )

    // Normalised lowercase string → canonical USFM code
    private val bookLookup: Map<String, String> = buildMap {
        // 1. Full display names
        for ((code, name) in bookNames) {
            put(name.lowercase(), code)
        }
        // 2. English abbreviations & alternate names
        for ((alias, code) in BookData.englishAliases) {
            put(alias, code)
        }
        // 3. Other languages
        for (language in BookData.languageNames) {
            for ((code, names) in language) {
                for (name in names) put(normalizeBookKey(name), code)
            }
        }
    }

    private val chapterVerseCounts: Map<String, List<Int>> = BookData.chapterVerseCounts

    private fun legacyChilluFor(atomic: String): String = legacyChillus.entries.first { it.value == atomic }.key

    private fun normalizeBookKey(raw: String): String {
        var key = raw.trim().lowercase().replace(Regex("""\s+"""), " ").trimEnd('.')
        for ((legacy, atomic) in legacyChillus) key = key.replace(legacy, atomic)
        return key
    }

    // MARK: - Internal Accessors

    fun nameForCode(code: String): String? = bookNames[code.uppercase()]

    fun bookIndex(code: String): Int? = bookOrder[code.uppercase()]

    fun chapterCount(bookCode: String): Int? = chapterVerseCounts[bookCode.uppercase()]?.size

    // MARK: - Public API

    /** Converts a USFM reference string to a human-readable string.
     *  e.g. "GEN" → "Genesis", "2CO.12" → "2 Corinthians 12", "GEN.1.2 + GEN.1.3" → "Genesis 1:2–3" */
    fun humanReadable(usfm: String): String {
        val refs = parseUsfm(usfm)
        return if (refs.isEmpty()) usfm else formatReferences(refs)
    }

    /** Converts a human-readable reference to a USFM string.
     *  e.g. "Gen 1:2" → "GEN.1.2", "1 Cor 3:4" → "1CO.3.4", "Genesis 1:2, 4, 6" → "GEN.1.2 + GEN.1.4 + GEN.1.6" */
    fun usfm(readable: String): String {
        val refs = parseReadable(readable)
        return if (refs.isEmpty()) readable else formatUSFM(refs)
    }

    /** Parses a USFM string into a list of BibleReference values. */
    fun parseUsfm(usfm: String): List<BibleReference> {
        return usfm
            .split("+")
            .map { it.trim() }
            .mapNotNull { part ->
                val components = part.split(".")
                if (components.isEmpty()) return@mapNotNull null
                val book = resolvedCode(components[0].uppercase())
                if (bookNames[book] == null) return@mapNotNull null
                if (components.size < 2) return@mapNotNull BibleReference(book, null, null)
                val chapter = components[1].toIntOrNull()
                    ?: return@mapNotNull BibleReference(book, null, null)
                if (components.size < 3) return@mapNotNull BibleReference(book, chapter, null)
                val verse = components[2].toIntOrNull()
                    ?: return@mapNotNull BibleReference(book, chapter, null)
                BibleReference(book, chapter, verse)
            }
    }

    /** Parses a human-readable reference string into a list of BibleReference values.
     *  Supports: "Gen 1:2", "1 Cor 3:4", "Genesis 1:2, 4, 6", "Gen 1:2–5" */
    fun parseReadable(readable: String): List<BibleReference> {
        val result = mutableListOf<BibleReference>()
        var lastBook: String? = null
        var lastChapter: Int? = null

        // Pattern groups:
        //   1 – book name (may start with "1 ", "2 ", "3 ")
        //   2 – chapter (optional)
        //   3 – start verse (optional)
        //   4 – end verse for range (optional)
        val pattern = Regex(
            """^((?:\d[\s.])?\p{L}[\p{L}\p{M}\u200C\u200D.\s]*?)(?:\s*(\d+)(?::(\d+)(?:[-–—](\d+))?)?)?$"""
        )

        val parts = readable.split(",").map { it.trim() }

        for (part in parts) {
            // Bare verse continuation: "4" or "6" after "Genesis 1:2"
            if (lastBook != null && lastChapter != null) {
                val verse = part.toIntOrNull()
                if (verse != null) {
                    result.add(BibleReference(lastBook, lastChapter, verse))
                    continue
                }
            }

            val match = pattern.find(part) ?: continue
            val rawName = match.groupValues[1].trim()
            val normKey = normalizeBookKey(rawName)

            val bookCode = bookLookup[normKey] ?: continue

            val chapter = match.groupValues[2].toIntOrNull()
            val startVerse = match.groupValues[3].toIntOrNull()
            val endVerse = match.groupValues[4].toIntOrNull()

            lastBook = bookCode
            lastChapter = chapter

            if (chapter != null) {
                if (startVerse != null) {
                    result.add(BibleReference(bookCode, chapter, startVerse))
                    if (endVerse != null && endVerse > startVerse) {
                        for (v in (startVerse + 1)..endVerse) {
                            result.add(BibleReference(bookCode, chapter, v))
                        }
                    }
                } else {
                    result.add(BibleReference(bookCode, chapter, null))
                }
            } else {
                result.add(BibleReference(bookCode, null, null))
            }
        }

        return result
    }

    // Built from bookLookup's keys (book names + abbreviations), longest
    // first so e.g. "1 corinthians" wins over "1 co" when both could match
    // at the same position — alternation in Kotlin/Java regex takes the
    // first successful alternative, not the longest overall match. Keys are
    // plain letters/digits/spaces (no regex metacharacters), so no escaping is
    // needed beyond turning literal spaces into flexible whitespace.
    private val findReferencesPattern: Regex by lazy {
        val alternatives = bookLookup.keys
            .sortedByDescending { it.length }
            .joinToString("|") { key ->
                key.replace(" ", "\\s+").replace(Regex("[ൺൻർൽൾ]")) { "(?:${it.value}|${legacyChilluFor(it.value)})" }
            }
        // \b is ASCII-only on some runtimes and splits Indic words at combining marks.
        Regex("""(?<![\p{L}\p{M}\p{N}])($alternatives)\.?\s+(\d{1,3})(?::(\d{1,3})(?:[-–—](\d{1,3}))?)?(?!\p{N})""", RegexOption.IGNORE_CASE)
    }

    /** Scans free-form text (e.g. a note's body) for Bible references anywhere within it —
     *  unlike [parseReadable], which requires the whole string to be one. A verse range like
     *  "Rom 8:28-30" expands to one BibleReference per verse. No iOS equivalent exists for this. */
    fun findReferences(text: String): List<BibleReference> {
        val result = mutableListOf<BibleReference>()
        for (match in findReferencesPattern.findAll(text)) {
            val bookCode = bookLookup[normalizeBookKey(match.groupValues[1])] ?: continue
            val chapter = match.groupValues[2].toIntOrNull() ?: continue

            val startVerseStr = match.groupValues[3]
            if (startVerseStr.isEmpty()) {
                result.add(BibleReference(bookCode, chapter, null))
                continue
            }
            val startVerse = startVerseStr.toIntOrNull() ?: continue
            result.add(BibleReference(bookCode, chapter, startVerse))

            val endVerse = match.groupValues[4].toIntOrNull()
            if (endVerse != null && endVerse > startVerse) {
                for (v in (startVerse + 1)..endVerse) {
                    result.add(BibleReference(bookCode, chapter, v))
                }
            }
        }
        return result
    }

    /** Like [findReferences] but returns each match's position and original text (a range stays
     *  one span), for turning references in prose into links. No iOS equivalent exists for this. */
    fun findReferenceSpans(text: String): List<Pair<IntRange, String>> =
        findReferencesPattern.findAll(text)
            .filter { bookLookup.containsKey(normalizeBookKey(it.groupValues[1])) }
            .map { it.range to it.value }
            .toList()

    // MARK: - USFM Formatting

    private fun formatUSFM(refs: List<BibleReference>): String {
        return refs.sorted().joinToString(" + ") { ref ->
            val chapter = ref.chapter ?: return@joinToString ref.book
            val verse = ref.verse ?: return@joinToString "${ref.book}.$chapter"
            "${ref.book}.$chapter.$verse"
        }
    }

    // MARK: - Human-Readable Formatting

    private fun formatReferences(refs: List<BibleReference>): String {
        val sorted = refs.sorted()
        val first = sorted.firstOrNull() ?: return ""

        if (sorted.size == 1) return label(first)

        val sameBook = sorted.all { it.book == first.book }
        val sameChapter = sorted.all { it.chapter == first.chapter }
        val allWholeBook = sorted.all { it.chapter == null }
        val allWholeChapter = sorted.all { it.verse == null && it.chapter != null }

        // Multiple whole-book references
        if (allWholeBook) return sorted.joinToString("; ") { it.bookName }

        // Same book, all whole-chapter
        if (sameBook && allWholeChapter) {
            val chapters = sorted.mapNotNull { it.chapter }
            return if (isConsecutive(chapters)) {
                "${first.bookName} ${chapters.first()}–${chapters.last()}"
            } else {
                chapters.joinToString(", ") { "${first.bookName} $it" }
            }
        }

        // Same book & chapter, verse-level
        if (sameBook && sameChapter) {
            val chapter = first.chapter
            if (chapter != null) {
                val verses = sorted.mapNotNull { it.verse }
                if (verses.isNotEmpty()) {
                    return if (isConsecutive(verses)) {
                        "${first.bookName} $chapter:${verses.first()}–${verses.last()}"
                    } else {
                        "${first.bookName} $chapter:${verses.joinToString(", ")}"
                    }
                }
            }
        }

        // Same book, cross-chapter
        if (sameBook) {
            // Two-verse cross-chapter range (e.g. "Genesis 1:31–2:1")
            if (sorted.size == 2) {
                val c1 = sorted[0].chapter
                val v1 = sorted[0].verse
                val c2 = sorted[1].chapter
                val v2 = sorted[1].verse
                if (c1 != null && v1 != null && c2 != null && v2 != null &&
                    c1 < c2 && isLastVerseOfChapter(first.book, c1, v1) && v2 == 1
                ) {
                    return "${first.bookName} $c1:$v1–$c2:$v2"
                }
            }
            return sorted.joinToString(", ") { label(it, first.bookName) }
        }

        // Different books
        return sorted.joinToString("; ") { label(it) }
    }

    // MARK: - Helpers

    private fun label(ref: BibleReference, bookNameOverride: String? = null): String {
        val name = bookNameOverride ?: ref.bookName
        val chapter = ref.chapter ?: return name
        val verse = ref.verse ?: return "$name $chapter"
        return "$name $chapter:$verse"
    }

    private fun isConsecutive(numbers: List<Int>): Boolean {
        if (numbers.size <= 1) return false
        return numbers.zip(numbers.drop(1)).all { (a, b) -> b - a == 1 }
    }

    private fun isLastVerseOfChapter(book: String, chapter: Int, verse: Int): Boolean {
        val counts = chapterVerseCounts[book]
        return if (counts != null && chapter <= counts.size) {
            verse == counts[chapter - 1]
        } else {
            verse > 20 // fallback heuristic
        }
    }

    private fun resolvedCode(code: String): String {
        return BookData.codeAliases[code] ?: code
    }
}

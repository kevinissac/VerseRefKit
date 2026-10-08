package com.kevinissac.verserefkit

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

// Cases live in data/tests and are shared with the Swift package's tests.
class VerseRefTest {

    private fun cases(name: String): List<Pair<String, String>> =
        File("../data/tests/$name").readLines()
            .filter { it.isNotBlank() }
            .map { line -> line.substringBefore('\t') to line.substringAfter('\t', "") }

    @Test
    fun readableToUsfm() {
        for ((input, expected) in cases("usfm.tsv")) {
            assertEquals(input, expected, VerseRef.usfm(input))
        }
    }

    @Test
    fun usfmToReadable() {
        for ((input, expected) in cases("readable.tsv")) {
            assertEquals(input, expected, VerseRef.humanReadable(input))
        }
    }

    @Test
    fun findsReferenceSpans() {
        for ((text, expected) in cases("spans.tsv")) {
            val spans = VerseRef.findReferenceSpans(text).joinToString(" | ") { it.second }
            assertEquals(text, expected, spans)
        }
    }

    @Test
    fun spanRangesPointAtTheMatchedText() {
        val text = "a യോഹ. 3:16, b"
        val (range, reference) = VerseRef.findReferenceSpans(text).single()
        assertEquals(reference, text.substring(range))
    }

    @Test
    fun legacyZwjChilluMatches() {
        val legacy = "യോഹന്നാന്‍ 3:16"
        assertEquals("JHN.3.16", VerseRef.usfm(legacy))
        assertEquals(1, VerseRef.findReferenceSpans(legacy).size)
    }
}

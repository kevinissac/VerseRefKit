package com.kevinissac.verserefkit

// MARK: - BibleReference

data class BibleReference(
    val book: String,
    val chapter: Int?,
    val verse: Int?
) : Comparable<BibleReference> {

    val bookName: String get() = VerseRef.nameForCode(book) ?: book

    override fun compareTo(other: BibleReference): Int {
        val li = VerseRef.bookIndex(book) ?: Int.MAX_VALUE
        val ri = VerseRef.bookIndex(other.book) ?: Int.MAX_VALUE
        if (li != ri) return li.compareTo(ri)
        val lc = chapter ?: 0
        val rc = other.chapter ?: 0
        if (lc != rc) return lc.compareTo(rc)
        return (verse ?: 0).compareTo(other.verse ?: 0)
    }
}

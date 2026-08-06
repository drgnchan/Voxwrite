package dev.raymond.voxwrite

import org.junit.Assert.assertEquals
import org.junit.Test

class TextDeletionTest {
    @Test
    fun `uses one UTF-16 code unit for ordinary characters`() {
        assertEquals(1, previousCodePointCodeUnitCount("a"))
        assertEquals(1, previousCodePointCodeUnitCount("文字"))
    }

    @Test
    fun `uses both UTF-16 code units for a supplementary character`() {
        assertEquals(2, previousCodePointCodeUnitCount("text🙂"))
    }

    @Test
    fun `falls back to one code unit when surrounding text is unavailable`() {
        assertEquals(1, previousCodePointCodeUnitCount(null))
        assertEquals(1, previousCodePointCodeUnitCount(""))
    }
}

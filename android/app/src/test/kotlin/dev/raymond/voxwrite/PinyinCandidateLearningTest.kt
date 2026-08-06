package dev.raymond.voxwrite

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PinyinCandidateLearningTest {
    @Test
    fun selectedCandidateMovesAheadForTheSamePinyinOnly() {
        val learning = PinyinCandidateLearning.empty()

        assertTrue(learning.recordSelection("Ni'Hao", "拟好"))

        assertEquals(
            listOf("拟好", "你好", "你号"),
            learning.rerank("nihao", listOf("你好", "你号", "拟好"))
        )
        assertEquals(
            listOf("你好", "拟好"),
            learning.rerank("nihau", listOf("你好", "拟好"))
        )
    }

    @Test
    fun learningRoundTripsThroughPrivatePreferenceEncoding() {
        val learning = PinyinCandidateLearning.empty()
        learning.recordSelection("huiyi", "回忆")
        learning.recordSelection("huiyi", "会议")
        learning.recordSelection("huiyi", "会议")

        val restored = PinyinCandidateLearning.fromEncoded(learning.encodedEntries())

        assertEquals(2, restored.selectionCount("huiyi", "会议"))
        assertEquals(1, restored.selectionCount("huiyi", "回忆"))
        assertEquals(
            listOf("会议", "回忆", "会意"),
            restored.rerank("huiyi", listOf("回忆", "会意", "会议"))
        )
    }

    @Test
    fun rejectsUnsafeOrMalformedLearningEntries() {
        val learning = PinyinCandidateLearning.fromEncoded(
            setOf(
                "huiyi\tbad\t会议",
                "\t2\t会议",
                "huiyi\t3\t",
                "huiyi\t4\t回忆"
            )
        )

        assertEquals(4, learning.selectionCount("huiyi", "回忆"))
        assertFalse(learning.recordSelection("", "会议"))
        assertFalse(learning.recordSelection("huiyi", "会\n议"))
    }
}

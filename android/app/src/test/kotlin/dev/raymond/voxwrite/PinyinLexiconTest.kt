package dev.raymond.voxwrite

import org.junit.Assert.assertEquals
import org.junit.Test

class PinyinLexiconTest {
    @Test
    fun normalizesCaseApostrophesAndUmlauts() {
        assertEquals("nvhai", PinyinLexicon.normalize("NÜ'HAI"))
    }

    @Test
    fun returnsRankedCandidatesForExactPinyin() {
        val lexicon = PinyinLexicon.fromLines(
            sequenceOf(
                "# comment",
                "ni\t你 尼 泥",
                "nihao\t你好 拟好"
            )
        )

        assertEquals(listOf("你好", "拟好"), lexicon.candidates("Ni'Hao"))
        assertEquals(listOf("你", "尼"), lexicon.candidates("ni", limit = 2))
        assertEquals(emptyList<String>(), lexicon.candidates("unknown"))
    }

    @Test
    fun segmentsLongPinyinIntoRankedSentences() {
        val lexicon = PinyinLexicon.fromLines(
            sequenceOf(
                "jin\t今 金",
                "tian\t天 田",
                "jintian\t今天",
                "qu\t去 取",
                "kai\t开 凯",
                "hui\t会 回",
                "kaihui\t开会"
            )
        )

        val candidates = lexicon.candidates("jintianqukaihui")

        assertEquals("今天去开会", candidates.first())
        assert(candidates.contains("今天取开会"))
    }

    @Test
    fun includesSyllableSplitCandidatesBehindExactCandidates() {
        val lexicon = PinyinLexicon.fromLines(
            sequenceOf(
                "xi\t西 希",
                "an\t安 按",
                "xian\t先 线"
            )
        )

        val candidates = lexicon.candidates("xian")

        assertEquals(listOf("先", "线"), candidates.take(2))
        assert(candidates.contains("西安"))
    }
}

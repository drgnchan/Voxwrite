package dev.raymond.voxwrite

import android.content.res.AssetManager
import java.util.Locale

internal class PinyinLexicon private constructor(
    private val entries: Map<String, List<String>>
) {
    private data class SentencePath(
        val text: String,
        val score: Int,
        val segmentCount: Int
    )

    private data class SyllablePath(val boundaries: List<Int>) {
        val syllableCount: Int get() = boundaries.size - 1
    }

    private val singleSyllableKeys = entries
        .asSequence()
        .filter { (_, words) -> words.any { it.length == 1 } }
        .mapTo(hashSetOf()) { it.key }
    private val maxSyllableLength = singleSyllableKeys.maxOfOrNull(String::length) ?: 0

    fun candidates(rawPinyin: String, limit: Int = 18): List<String> {
        val key = normalize(rawPinyin)
        if (key.isEmpty() || limit <= 0) return emptyList()

        val exact = entries[key].orEmpty()
        val exactSet = exact.toHashSet()
        val segmented = segmentedCandidates(key, limit).filterNot(exactSet::contains)
        if (segmented.isEmpty()) return exact.take(limit)
        if (exact.isEmpty()) return segmented.take(limit)

        val segmentedQuota = minOf(6, segmented.size, limit - 1)
        val exactQuota = minOf(exact.size, limit - segmentedQuota)
        return buildList(limit) {
            addAll(exact.take(exactQuota))
            addAll(segmented.take(segmentedQuota))
            if (size < limit) addAll(exact.drop(exactQuota).take(limit - size))
        }
    }

    private fun segmentedCandidates(key: String, limit: Int): List<String> {
        val parses = syllableParses(key)
        if (parses.isEmpty()) return emptyList()

        val candidatesByParse = parses.map {
            candidatesForSyllableParse(key, it.boundaries, limit)
        }
        if (candidatesByParse.size == 1) return candidatesByParse.first()

        val result = linkedSetOf<String>()
        val alternativeQuota = minOf(6, limit - 1)
        result.addAll(candidatesByParse.first().take(limit - alternativeQuota))
        candidatesByParse.drop(1).forEach { alternatives ->
            alternatives.take(3).forEach {
                if (result.size < limit) result.add(it)
            }
        }
        if (result.size < limit) {
            candidatesByParse.first().forEach {
                if (result.size < limit) result.add(it)
            }
        }
        return result.take(limit)
    }

    private fun syllableParses(key: String): List<SyllablePath> {
        if (maxSyllableLength == 0) return emptyList()
        val paths = Array(key.length + 1) { mutableListOf<SyllablePath>() }
        paths[0].add(SyllablePath(listOf(0)))

        for (start in key.indices) {
            pruneSyllablePaths(paths[start])
            if (paths[start].isEmpty()) continue
            val lastEnd = minOf(key.length, start + maxSyllableLength)
            for (end in start + 1..lastEnd) {
                if (key.substring(start, end) !in singleSyllableKeys) continue
                paths[start].forEach { path ->
                    paths[end].add(SyllablePath(path.boundaries + end))
                }
            }
        }
        pruneSyllablePaths(paths[key.length], SYLLABLE_PARSE_LIMIT)
        return paths[key.length].take(SYLLABLE_PARSE_LIMIT)
    }

    private fun pruneSyllablePaths(
        paths: MutableList<SyllablePath>,
        limit: Int = SYLLABLE_PARSE_BEAM_WIDTH
    ) {
        if (paths.size <= 1) return
        val pruned = paths
            .distinctBy(SyllablePath::boundaries)
            .sortedWith(
                compareBy<SyllablePath> { it.syllableCount }
                    .thenComparator { first, second ->
                        compareBoundaries(first.boundaries, second.boundaries)
                    }
            )
            .take(limit)
        paths.clear()
        paths.addAll(pruned)
    }

    private fun compareBoundaries(first: List<Int>, second: List<Int>): Int {
        val sharedLength = minOf(first.size, second.size)
        for (index in 1 until sharedLength) {
            val comparison = second[index].compareTo(first[index])
            if (comparison != 0) return comparison
        }
        return first.size.compareTo(second.size)
    }

    private fun candidatesForSyllableParse(
        key: String,
        boundaries: List<Int>,
        limit: Int
    ): List<String> {
        val syllableCount = boundaries.size - 1
        if (syllableCount < 2) return emptyList()
        val beams = Array(syllableCount + 1) { mutableListOf<SentencePath>() }
        beams[0].add(SentencePath("", 0, 0))

        for (start in 0 until syllableCount) {
            pruneSentenceBeam(beams[start])
            val source = beams[start]
            if (source.isEmpty()) continue
            for (end in start + 1..syllableCount) {
                val pinyinKey = key.substring(boundaries[start], boundaries[end])
                val expectedWordLength = end - start
                val words = entries[pinyinKey]
                    ?.asSequence()
                    ?.filter { it.length == expectedWordLength }
                    ?.take(CANDIDATES_PER_SEGMENT)
                    ?.toList()
                    .orEmpty()
                if (words.isEmpty()) continue
                val destination = beams[end]
                source.forEach { path ->
                    words.forEachIndexed { rank, word ->
                        destination.add(
                            SentencePath(
                                text = path.text + word,
                                score = path.score +
                                    expectedWordLength * expectedWordLength * WORD_LENGTH_WEIGHT -
                                    rank * CANDIDATE_RANK_PENALTY -
                                    SEGMENT_PENALTY,
                                segmentCount = path.segmentCount + 1
                            )
                        )
                    }
                }
            }
        }

        pruneSentenceBeam(beams[syllableCount], maxOf(SENTENCE_BEAM_WIDTH, limit * 2))
        return beams[syllableCount]
            .asSequence()
            .filter { it.segmentCount > 1 }
            .map(SentencePath::text)
            .distinct()
            .take(limit)
            .toList()
    }

    private fun pruneSentenceBeam(
        paths: MutableList<SentencePath>,
        limit: Int = SENTENCE_BEAM_WIDTH
    ) {
        if (paths.size <= 1) return
        val pruned = paths
            .groupBy(SentencePath::text)
            .mapNotNull { (_, duplicates) -> duplicates.maxByOrNull(SentencePath::score) }
            .sortedWith(
                compareByDescending<SentencePath> { it.score }
                    .thenBy { it.segmentCount }
                    .thenBy { it.text }
            )
            .take(limit)
        paths.clear()
        paths.addAll(pruned)
    }

    companion object {
        private const val SENTENCE_BEAM_WIDTH = 32
        private const val SYLLABLE_PARSE_BEAM_WIDTH = 12
        private const val SYLLABLE_PARSE_LIMIT = 3
        private const val CANDIDATES_PER_SEGMENT = 3
        private const val WORD_LENGTH_WEIGHT = 100
        private const val CANDIDATE_RANK_PENALTY = 12
        private const val SEGMENT_PENALTY = 25

        fun load(assets: AssetManager): PinyinLexicon =
            assets.open("pinyin_lexicon.tsv")
                .bufferedReader(Charsets.UTF_8)
                .useLines(::fromLines)

        internal fun fromLines(lines: Sequence<String>): PinyinLexicon {
            val entries = HashMap<String, List<String>>(70_000)
            lines.forEach { line ->
                if (line.isBlank() || line.startsWith('#')) return@forEach
                val separator = line.indexOf('\t')
                if (separator <= 0 || separator == line.lastIndex) return@forEach
                val key = line.substring(0, separator)
                val words = line.substring(separator + 1)
                    .split(' ')
                    .filter(String::isNotBlank)
                if (words.isNotEmpty()) entries[key] = words
            }
            return PinyinLexicon(entries)
        }

        fun normalize(rawPinyin: String): String = rawPinyin
            .lowercase(Locale.ROOT)
            .replace("ü", "v")
            .filter { it in 'a'..'z' }
    }
}

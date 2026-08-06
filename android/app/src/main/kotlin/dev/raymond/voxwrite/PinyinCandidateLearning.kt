package dev.raymond.voxwrite

internal class PinyinCandidateLearning private constructor(
    private val selectionCounts: MutableMap<String, MutableMap<String, Int>>
) {
    fun rerank(rawPinyin: String, candidates: List<String>): List<String> {
        val key = PinyinLexicon.normalize(rawPinyin)
        val counts = selectionCounts[key].orEmpty()
        return candidates
            .distinct()
            .withIndex()
            .sortedWith(
                compareByDescending<IndexedValue<String>> { counts[it.value] ?: 0 }
                    .thenBy { it.index }
            )
            .map(IndexedValue<String>::value)
    }

    fun recordSelection(rawPinyin: String, candidate: String): Boolean {
        val key = PinyinLexicon.normalize(rawPinyin)
        if (
            key.isEmpty() ||
            candidate.isBlank() ||
            candidate.any { it == '\t' || it == '\n' || it == '\r' }
        ) {
            return false
        }
        val counts = selectionCounts.getOrPut(key) { mutableMapOf() }
        counts[candidate] = ((counts[candidate] ?: 0) + 1).coerceAtMost(MAX_COUNT)
        return true
    }

    fun encodedEntries(limit: Int = MAX_STORED_SELECTIONS): Set<String> = selectionCounts
        .flatMap { (key, candidates) ->
            candidates.map { (candidate, count) ->
                EncodedSelection(key, candidate, count)
            }
        }
        .sortedWith(
            compareByDescending<EncodedSelection> { it.count }
                .thenBy { it.key }
                .thenBy { it.candidate }
        )
        .take(limit.coerceAtLeast(0))
        .mapTo(linkedSetOf()) { "${it.key}\t${it.count}\t${it.candidate}" }

    internal fun selectionCount(rawPinyin: String, candidate: String): Int =
        selectionCounts[PinyinLexicon.normalize(rawPinyin)]?.get(candidate) ?: 0

    private data class EncodedSelection(
        val key: String,
        val candidate: String,
        val count: Int
    )

    companion object {
        private const val MAX_COUNT = 999
        private const val MAX_STORED_SELECTIONS = 512

        fun empty(): PinyinCandidateLearning = PinyinCandidateLearning(mutableMapOf())

        fun fromEncoded(entries: Set<String>): PinyinCandidateLearning {
            val counts = mutableMapOf<String, MutableMap<String, Int>>()
            entries.forEach { entry ->
                val parts = entry.split('\t', limit = 3)
                if (parts.size != 3) return@forEach
                val key = PinyinLexicon.normalize(parts[0])
                val count = parts[1].toIntOrNull() ?: return@forEach
                val candidate = parts[2]
                if (
                    key.isEmpty() ||
                    count <= 0 ||
                    candidate.isBlank() ||
                    candidate.any { it == '\n' || it == '\r' }
                ) {
                    return@forEach
                }
                counts.getOrPut(key) { mutableMapOf() }[candidate] =
                    count.coerceAtMost(MAX_COUNT)
            }
            return PinyinCandidateLearning(counts)
        }
    }
}

#!/usr/bin/env python3
"""Generate VoxWrite's compact offline Pinyin candidate lexicon.

Inputs are jieba's MIT-licensed frequency dictionary and pypinyin's
MIT-licensed pronunciation data. Install the pinned generator dependencies:

    python3 -m pip install jieba==0.42.1 pypinyin==0.55.0

The generated TSV is checked in so Android builds do not require Python.
"""

from __future__ import annotations

import argparse
import collections
import re
from pathlib import Path

from pypinyin import Style, lazy_pinyin

HAN_WORD = re.compile(r"^[\u3400-\u9fff]+$")

# Product names and high-value daily phrases get deterministic priority over
# the generic frequency corpus.
BOOSTED_WORDS = {
    "VoxWrite": 0,  # Documented here, but excluded by the Han-only filter.
    "你好": 1_000_000_000,
    "谢谢": 999_000_000,
    "可以": 998_000_000,
    "好的": 997_000_000,
    "收到": 996_000_000,
    "稍等": 995_000_000,
    "马上": 994_000_000,
    "今天": 993_000_000,
    "明天": 992_000_000,
    "现在": 991_000_000,
    "时间": 990_000_000,
    "工作": 989_000_000,
    "会议": 988_000_000,
    "消息": 987_000_000,
    "文件": 986_000_000,
    "问题": 985_000_000,
    "需要": 984_000_000,
    "已经": 983_000_000,
    "没有": 982_000_000,
    "因为": 981_000_000,
    "所以": 980_000_000,
    "我们": 979_000_000,
    "我想": 978_000_000,
    "明天见": 977_000_000,
    "上午": 976_000_000,
    "下午": 975_000_000,
    "晚上": 974_000_000,
    "吃饭": 973_000_000,
    "开会": 972_000_000,
    "开个会": 971_000_000,
    "等一下": 970_000_000,
    "没问题": 969_000_000,
    "知道了": 968_000_000,
    "辛苦了": 967_000_000,
    "稍后回复": 966_000_000,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jieba-dict", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-words", type=int, default=80_000)
    parser.add_argument("--candidates-per-key", type=int, default=32)
    return parser.parse_args()


def pronunciation(word: str) -> str:
    syllables = lazy_pinyin(
        word,
        style=Style.NORMAL,
        neutral_tone_with_five=False,
        errors="ignore",
    )
    return "".join(syllables).lower().replace("ü", "v")


def main() -> None:
    args = parse_args()
    ranked: dict[str, int] = {}
    with args.jieba_dict.open(encoding="utf-8") as source:
        for line in source:
            try:
                word, raw_frequency, _ = line.rstrip().split(" ", 2)
                frequency = int(raw_frequency)
            except ValueError:
                continue
            if not HAN_WORD.fullmatch(word) or len(word) > 8:
                continue
            ranked[word] = max(frequency, ranked.get(word, 0))

    single_characters = [(word, freq) for word, freq in ranked.items() if len(word) == 1]
    multi_character = sorted(
        ((word, freq) for word, freq in ranked.items() if len(word) > 1),
        key=lambda item: (-item[1], item[0]),
    )[: args.max_words]
    selected = dict(single_characters + multi_character)
    for word, frequency in BOOSTED_WORDS.items():
        if HAN_WORD.fullmatch(word):
            selected[word] = frequency

    candidates: dict[str, list[tuple[str, int]]] = collections.defaultdict(list)
    for word, frequency in selected.items():
        key = pronunciation(word)
        if key and key.isascii() and key.isalpha():
            candidates[key].append((word, frequency))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as output:
        output.write("# VoxWrite offline Pinyin lexicon v2\n")
        output.write("# Generated from jieba 0.42.1 + pypinyin 0.55.0 (MIT)\n")
        for key in sorted(candidates):
            ordered = sorted(candidates[key], key=lambda item: (-item[1], len(item[0]), item[0]))
            words: list[str] = []
            seen: set[str] = set()
            for word, _ in ordered:
                if word in seen:
                    continue
                words.append(word)
                seen.add(word)
                if len(words) >= args.candidates_per_key:
                    break
            output.write(f"{key}\t{' '.join(words)}\n")

    print(
        f"wrote {len(candidates):,} pinyin keys from {len(selected):,} words "
        f"to {args.output}"
    )


if __name__ == "__main__":
    main()

package dev.raymond.voxwrite

internal fun previousCodePointCodeUnitCount(text: CharSequence?): Int {
    if (text.isNullOrEmpty()) return 1
    return Character.charCount(Character.codePointBefore(text, text.length))
}

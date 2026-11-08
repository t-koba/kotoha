package org.kotoha.app

/** Reuses 16-bit activity-result codes after completion; abandoned requests stay reserved. */
class ActivityRequestCodePool(firstCode: Int = 0) {
    private val active = HashSet<Int>()
    private val abandoned = HashSet<Int>()
    private var nextCode = firstCode.also { require(it in 0..CODE_MASK) }

    fun acquire(): Int? {
        repeat(CODE_COUNT) {
            val code = nextCode
            nextCode = (code + 1) and CODE_MASK
            if (code !in active && code !in abandoned) {
                active.add(code)
                return code
            }
        }
        return null
    }

    fun release(code: Int) {
        active.remove(code)
    }

    fun abandon(code: Int) {
        if (active.remove(code)) abandoned.add(code)
    }

    fun consumeAbandoned(code: Int): Boolean = abandoned.remove(code)

    companion object {
        private const val CODE_COUNT = 1 shl 16
        private const val CODE_MASK = CODE_COUNT - 1
    }
}

/** Single 16-bit pool shared by every activity-result picker so codes never collide. */
object SharedActivityRequestCodes {
    val pool = ActivityRequestCodePool()
}

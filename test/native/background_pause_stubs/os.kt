package android.os

object Build {
    object VERSION { var SDK_INT = 37 }
    object VERSION_CODES { const val P = 28; const val R = 30 }
}

object SystemClock {
    /** Defaults to "booted at the epoch": no reboot is ever inferred. */
    var elapsed: Long? = null
    fun elapsedRealtime(): Long = elapsed ?: System.currentTimeMillis()
}

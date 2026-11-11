package io.github.agentphone.app

/** QA main-thread work must always return to the instrumentation framework. */
internal object Bb8MainCallback {
    fun run(sync: (Runnable) -> Unit, action: () -> Unit): Boolean {
        var succeeded = true
        sync(Runnable {
            try { action() }
            catch (_: Throwable) { succeeded = false }
        })
        return succeeded
    }
}

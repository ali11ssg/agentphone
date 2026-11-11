package io.github.agentphone.app

/** ActivityManager registration is trusted; a fresh Java process map is not. */
internal object PhoneAgentAuthColdOwner {
    fun permitsLockCleanup(registered: Set<Int>, currentPid: Int, inventory: () -> Set<Int>): Boolean = try {
        inventory().all { it == currentPid || it in registered }
    } catch (_: Exception) { false }
}

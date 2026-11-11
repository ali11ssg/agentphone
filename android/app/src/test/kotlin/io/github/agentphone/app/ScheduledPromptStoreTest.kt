package io.github.agentphone.app

import android.content.SharedPreferences
import java.time.Instant
import java.util.concurrent.CountDownLatch
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduledPromptStoreTest {
    @Test fun phoneLeaseSurvivesHostRestartAndIgnoresWallClockChangesOnSameBoot() {
        val prefs = MemoryPreferences()
        ScheduledPromptPhoneLease(prefs).begin("phone", "owned", 1000,
            ScheduledPromptPhoneLease.Clock(8, 100_000, 1_000_000))
        val restarted = ScheduledPromptPhoneLease(prefs)
        assertTrue(restarted.active(ScheduledPromptPhoneLease.Clock(8, 101_000, 9_000_000)))
        assertTrue(restarted.active(ScheduledPromptPhoneLease.Clock(8, 101_000, 1)))
        assertFalse(restarted.active(ScheduledPromptPhoneLease.Clock(8, 167_000, 1)))
        assertTrue(prefs.values.containsKey("flutter.oc.schedulePhoneLease.phone"))
    }
    @Test fun confirmedRebootInvalidatesPhoneLeaseEvenBeforeWallDeadline() {
        val prefs = MemoryPreferences()
        ScheduledPromptPhoneLease(prefs).begin("phone", "owned", 1000,
            ScheduledPromptPhoneLease.Clock(8, 100_000, 1_000_000))
        assertFalse(ScheduledPromptPhoneLease(prefs).active(ScheduledPromptPhoneLease.Clock(9, 10, 1_000_001)))
    }
    @Test fun unavailableBootCountKeepsLeaseBoundedWithoutWallClockBypass() {
        val prefs = MemoryPreferences()
        ScheduledPromptPhoneLease(prefs).begin("phone", "owned", 1000,
            ScheduledPromptPhoneLease.Clock(-1, 100_000, 1_000_000))
        val lease = ScheduledPromptPhoneLease(prefs)
        assertTrue(lease.active(ScheduledPromptPhoneLease.Clock(-1, 101_000, 9_000_000)))
        assertFalse(lease.active(ScheduledPromptPhoneLease.Clock(-1, 167_000, 1)))
        assertTrue(lease.active(ScheduledPromptPhoneLease.Clock(-1, 10, 1_000_001)))
        assertFalse(lease.active(ScheduledPromptPhoneLease.Clock(-1, 67_000, 1)))
    }
    @Test fun stalePhoneLeaseReleaseCannotClearNewOwnerOrAnotherProfile() {
        val prefs = MemoryPreferences()
        val lease = ScheduledPromptPhoneLease(prefs)
        val clock = ScheduledPromptPhoneLease.Clock(8, 100_000, 1_000_000)
        lease.begin("phone", "old", 1000, clock)
        lease.begin("phone", "new", 1000, clock)
        lease.begin("other", "other-token", 1000, clock)
        lease.release("old")
        assertTrue(prefs.values.containsKey("flutter.oc.schedulePhoneLease.phone"))
        lease.release("new")
        assertFalse(prefs.values.containsKey("flutter.oc.schedulePhoneLease.phone"))
        assertTrue(lease.active(clock))
        lease.release("other-token")
        assertFalse(lease.active(clock))
    }
    @Test fun failedPhoneLeaseCommitPreventsAdmissionAndFailedReleaseRetainsGuard() {
        val prefs = MemoryPreferences()
        val lease = ScheduledPromptPhoneLease(prefs)
        val clock = ScheduledPromptPhoneLease.Clock(8, 100_000, 1_000_000)
        prefs.failCommits = true
        assertTrue(runCatching { lease.begin("phone", "owned", 1000, clock) }.isFailure)
        assertFalse(lease.active(clock))
        prefs.failCommits = false
        lease.begin("phone", "owned", 1000, clock)
        prefs.failCommits = true
        assertTrue(runCatching { lease.release("owned") }.isFailure)
        assertTrue(lease.active(clock))
    }
    private val profile = "phone"
    private val key = "oc.scheduledPrompts.$profile"
    private val due = System.currentTimeMillis() - 3_600_000L
    private fun preferences() = MemoryPreferences().also {
        it.values["flutter.oc.profiles"] = "[{\"id\":\"phone\"}]"
    }
    private fun envelope(revision: Long = 1, enabled: Boolean = true): String = JSONObject()
        .put("schemaVersion", 1).put("schedules", JSONArray().put(JSONObject()
            .put("id", "daily").put("profileId", profile).put("revision", revision).put("enabled", enabled)
            .put("nextRunAt", Instant.ofEpochMilli(due).toString()).put("recurrence", JSONObject()
                .put("kind", "interval").put("at", Instant.ofEpochMilli(due).toString()).put("hours", 2))))
        .put("runs", JSONArray())
        .put("digest", JSONObject().put("enabled", false).put("hour", 8).put("minute", 0)).toString()
    private fun entry() = ScheduledPromptStore.Entry(profile, "daily", 1, due)

    @Test fun twoEnginesCannotCommitAgainstSameOldEnvelope() {
        val prefs = preferences()
        val first = ScheduledPromptStore(prefs)
        val second = ScheduledPromptStore(prefs)
        val start = CountDownLatch(1)
        val results = java.util.concurrent.ConcurrentLinkedQueue<Boolean>()
        val threads = listOf(first, second).mapIndexed { index, store -> Thread {
            start.await()
            results.add(store.cas(key, null, envelope(index + 1L)))
        }.also { it.start() } }
        start.countDown()
        threads.forEach { it.join() }
        assertEquals(1, results.count { it })
        assertEquals(1, results.count { !it })
    }
    @Test fun envelopeSurvivesSaveBeforeIndexCrashAndRebuildUsesLatestRevision() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        val initial = envelope()
        assertTrue(store.cas(key, null, initial))
        assertEquals(emptyList<ScheduledPromptStore.Entry>(), store.entries(profile))
        val restarted = ScheduledPromptStore(prefs)
        assertEquals(listOf(profile), restarted.profiles())
        assertTrue(restarted.replace(profile))
        assertEquals(1L, restarted.entries(profile).single().revision)
        assertTrue(store.cas(key, initial, envelope(2)))
        assertTrue(restarted.replace(profile))
        assertEquals(2L, restarted.entries(profile).single().revision)
    }
    @Test fun claimSurvivesProcessDeathAndNeverBecomesNewAgain() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        store.cas(key, null, envelope()); store.replace(profile)
        assertEquals("new", store.claim(entry()))
        val restarted = ScheduledPromptStore(prefs)
        assertEquals("recover", restarted.claim(entry()))
        restarted.settle(entry())
        assertEquals("duplicate", store.claim(entry()))
    }
    @Test fun clockRollbackAfterClaimRearmsFreshUnsentOccurrenceWithoutHistoryOrAdvance() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        val data = envelope()
        store.cas(key, null, data); store.replace(profile)
        assertEquals("new", store.claim(entry()))
        assertTrue(store.deferEarlyOccurrence(entry(), due - 1, recovering = false))
        store.replace(profile)
        assertEquals(due, store.entries(profile).single().due)
        assertEquals(data, store.read(key))
        assertTrue(store.receipts(profile).isEmpty())
        assertEquals("new", store.claim(entry()))
    }
    @Test fun earlyRecoveryNeverMakesAnUncertainOccurrenceNewAgain() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        store.cas(key, null, envelope()); store.replace(profile); store.claim(entry())
        assertEquals("recover", store.claim(entry()))
        assertTrue(store.deferEarlyOccurrence(entry(), due - 1, recovering = true))
        assertEquals("recover", store.claim(entry()))
    }
    @Test fun recordedRunIsNeverReleasedForAnotherSendAfterClockRollback() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        val data = JSONObject(envelope())
        data.getJSONArray("runs").put(JSONObject().put("id", entry().occurrence).put("status", "running"))
        store.cas(key, null, data.toString()); store.replace(profile); store.claim(entry())
        assertTrue(store.deferEarlyOccurrence(entry(), due - 1, recovering = false))
        assertEquals("recover", store.claim(entry()))
    }
    @Test fun earlyReleaseRejectsDueOrEditedOrDeletedOccurrences() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        val data = envelope()
        store.cas(key, null, data); store.replace(profile); store.claim(entry())
        assertFalse(store.deferEarlyOccurrence(entry(), due, recovering = false))
        store.cas(key, data, envelope(2)); store.replace(profile)
        assertFalse(store.deferEarlyOccurrence(entry(), due - 1, recovering = false))
        store.clear(profile)
        assertFalse(store.deferEarlyOccurrence(entry(), due - 1, recovering = false))
    }
    @Test fun nativeFailureCommitsHistoryAndFutureRecurrenceTogether() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        store.cas(key, null, envelope()); store.replace(profile); store.claim(entry())
        store.settle(entry(), "interrupted")
        val state = JSONObject(store.read(key)!!)
        assertEquals("failed", state.getJSONArray("runs").getJSONObject(0).getString("status"))
        val nextRunAt = state.getJSONArray("schedules").getJSONObject(0).getString("nextRunAt")
        assertTrue(Instant.parse(nextRunAt).toEpochMilli() > System.currentTimeMillis())
        assertEquals(1, store.receipts(profile).size)
        store.replace(profile)
        assertFalse(store.occurrenceCurrent(entry()))
    }
    @Test fun tombstoneFencesReadsCasClaimsAndReceiptResurrection() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        val data = envelope()
        store.cas(key, null, data); store.replace(profile)
        store.clear(profile)
        assertFalse(store.profileExists(profile))
        assertFalse(store.cas(key, data, envelope(2)))
        assertTrue(runCatching { store.read(key) }.isFailure)
        assertEquals("stale", store.claim(entry()))
        store.acknowledge(profile, setOf("anything"))
        assertFalse(prefs.values.containsKey("flutter.oc.scheduleReceipts.$profile"))
        store.restoreProfile(profile); store.replace(profile)
        assertTrue(store.profileExists(profile))
        assertEquals(1, store.entries(profile).size)
    }
    @Test fun failedDurableWriteNeverReportsSuccessfulDeleteOrSave() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        prefs.failCommits = true
        assertFalse(store.cas(key, null, envelope()))
        assertTrue(runCatching { store.clear(profile) }.isFailure)
        assertTrue(store.profileExists(profile))
        assertFalse(prefs.values.containsKey("flutter.$key"))
    }
    @Test fun unrelatedReindexPreservesOverdueDigestUntilSettled() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        val data = JSONObject(envelope())
        data.getJSONObject("digest").put("enabled", true)
        store.cas(key, null, data.toString())
        val oldDue = java.time.ZonedDateTime.now().minusDays(1).withHour(8).withMinute(0).withSecond(0).withNano(0)
            .toInstant().toEpochMilli()
        prefs.values["flutter.oc.scheduleIndex.$profile"] = JSONArray().put(JSONObject()
            .put("id", "__digest").put("revision", 0).put("dueAtMs", oldDue)).toString()
        store.replace(profile)
        assertEquals(oldDue, store.entries(profile).first { it.id == "__digest" }.due)
        val digestEntry = ScheduledPromptStore.Entry(profile, "__digest", 0, oldDue)
        assertEquals("new", store.claim(digestEntry))
        store.settle(digestEntry)
        store.replace(profile)
        assertTrue(store.entries(profile).first { it.id == "__digest" }.due > System.currentTimeMillis())
    }
    @Test fun pausedOrDeletedScheduleCannotBeClaimedFromOldAlarm() {
        val prefs = preferences()
        val store = ScheduledPromptStore(prefs)
        val data = envelope()
        store.cas(key, null, data); store.replace(profile)
        store.cas(key, data, envelope(2, false)); store.replace(profile)
        assertTrue(store.entries(profile).isEmpty())
        assertEquals("stale", store.claim(entry()))
    }
}

private class MemoryPreferences : SharedPreferences {
    val values = mutableMapOf<String, Any?>()
    var failCommits = false
    override fun getAll(): MutableMap<String, *> = values
    override fun getString(key: String?, defValue: String?): String? = values[key] as? String ?: defValue
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
    override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue
    override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue
    override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue
    override fun getBoolean(key: String?, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue
    override fun contains(key: String?): Boolean = values.containsKey(key)
    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit
    override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private var clear = false
        override fun putString(key: String?, value: String?) = apply { pending[key!!] = value }
        override fun putStringSet(key: String?, values: MutableSet<String>?) = apply { pending[key!!] = values }
        override fun putInt(key: String?, value: Int) = apply { pending[key!!] = value }
        override fun putLong(key: String?, value: Long) = apply { pending[key!!] = value }
        override fun putFloat(key: String?, value: Float) = apply { pending[key!!] = value }
        override fun putBoolean(key: String?, value: Boolean) = apply { pending[key!!] = value }
        override fun remove(key: String?) = apply { pending[key!!] = null }
        override fun clear() = apply { clear = true }
        override fun commit(): Boolean {
            if (failCommits) return false
            if (clear) values.clear()
            pending.forEach { (key, value) -> if (value == null) values.remove(key) else values[key] = value }
            return true
        }
        override fun apply() { commit() }
    }
}

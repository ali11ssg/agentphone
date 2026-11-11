package io.github.agentphone.app

import java.time.Instant
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduledPromptRecoveryTest {
    private val zone = ZoneId.of("UTC")
    private val due = Instant.parse("2026-10-15T08:00:00Z").toEpochMilli()
    private val now = due + 5 * 3_600_000L
    private fun state(kind: String = "interval"): JSONObject = JSONObject().put("schemaVersion", 1)
        .put("schedules", JSONArray().put(JSONObject().put("id", "daily").put("revision", 2)
            .put("enabled", true).put("nextRunAt", Instant.ofEpochMilli(due).toString())
            .put("recurrence", JSONObject().put("kind", kind).put("at", Instant.ofEpochMilli(due).toString())
                .put("hours", 2).put("hour", 8).put("minute", 0))))
        .put("runs", JSONArray())
    private fun repair(state: JSONObject) = ScheduledPromptRecovery.repair(
        state, ScheduledPromptRecovery.Target("daily", 2, due), now, "interrupted", zone,
    )

    @Test fun interruptedIntervalPersistsFailureAndCollapsesMissedRunsWithoutDrift() {
        val data = state()
        assertTrue(repair(data))
        val run = data.getJSONArray("runs").getJSONObject(0)
        assertEquals("failed", run.getString("status"))
        assertEquals("interrupted", run.getString("errorCode"))
        assertTrue(run.getBoolean("late"))
        assertEquals("2026-10-15T14:00:00Z", data.getJSONArray("schedules").getJSONObject(0).getString("nextRunAt"))
        assertTrue(repair(data))
        assertEquals(1, data.getJSONArray("runs").length())
    }
    @Test fun completedOnceDoesNotRearm() {
        val data = state("once")
        repair(data)
        assertTrue(data.getJSONArray("schedules").getJSONObject(0).isNull("nextRunAt"))
    }
    @Test fun editedRevisionKeepsItsNewTiming() {
        val data = state()
        data.getJSONArray("schedules").getJSONObject(0).put("revision", 3)
        repair(data)
        val next = data.getJSONArray("schedules").getJSONObject(0).getString("nextRunAt")
        assertEquals(Instant.ofEpochMilli(due).toString(), next)
        assertEquals(1, data.getJSONArray("runs").length())
    }
    @Test fun deletedScheduleNeverResurrectsHistory() {
        val data = state().put("schedules", JSONArray())
        assertFalse(repair(data))
        assertEquals(0, data.getJSONArray("runs").length())
    }
    @Test fun alreadyAcceptedRunIsNotOverwrittenWhenAdvanceFailed() {
        val data = state()
        data.getJSONArray("runs").put(
            JSONObject().put("id", "daily:2:$due").put("status", "ran").put("sessionId", "conversation"),
        )
        repair(data)
        val run = data.getJSONArray("runs").getJSONObject(0)
        assertEquals("ran", run.getString("status"))
        assertEquals("conversation", run.getString("sessionId"))
        assertEquals("2026-10-15T14:00:00Z", data.getJSONArray("schedules").getJSONObject(0).getString("nextRunAt"))
    }
    @Test fun interruptedRunningHistoryKeepsConversationDestination() {
        val data = state()
        data.getJSONArray("runs").put(
            JSONObject().put("id", "daily:2:$due").put("status", "running").put("sessionId", "conversation"),
        )
        repair(data)
        val run = data.getJSONArray("runs").getJSONObject(0)
        assertEquals("failed", run.getString("status"))
        assertEquals("conversation", run.getString("sessionId"))
    }
}

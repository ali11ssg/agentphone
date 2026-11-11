package io.github.agentphone.app

import java.io.File

fun main() {
    val status = "Name:\tapp\nGroups:\t3003 9997 20209 50209 \nCapInh:\t0\n"
    val gids = AndroidGroupNames.parseGroups(status)
    check(gids == listOf(3003, 9997, 20209, 50209)) { "parse $gids" }
    check(AndroidGroupNames.parseGroups("Name:\tx\n").isEmpty())

    val base = "root:x:0:\ndaemon:x:1:"
    val merged = AndroidGroupNames.merged(base, gids)!!
    check(merged == "root:x:0:\ndaemon:x:1:\naid_3003:x:3003:\naid_9997:x:9997:\naid_20209:x:20209:\naid_50209:x:50209:\n") { merged }
    check(AndroidGroupNames.merged(merged, gids) == null) { "not idempotent" }
    check(AndroidGroupNames.merged("root:x:0:\naid_inet:x:3003:\n", listOf(3003, 3003, 9997))!!
        .endsWith("aid_9997:x:9997:\n"))

    val rootfs = File.createTempFile("rootfs", "").apply { delete(); mkdirs() }
    File(rootfs, "etc").mkdirs()
    File(rootfs, "etc/group").writeText("root:x:0:\n")
    val statusFile = File(rootfs, "status").apply { writeText(status) }
    AndroidGroupNames.apply(rootfs, statusFile)
    AndroidGroupNames.apply(rootfs, statusFile)
    val lines = File(rootfs, "etc/group").readLines()
    check(lines.size == 5 && lines.count { it.startsWith("aid_3003:") } == 1) { "$lines" }
    check(!File(rootfs, "etc/group.oc-new").exists())
    AndroidGroupNames.apply(File(rootfs, "missing"), statusFile)
    println("PASS android-group-names")
}

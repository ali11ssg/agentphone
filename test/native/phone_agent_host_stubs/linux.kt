package io.github.agentphone.app
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
class BuiltinLinux(val home: File, var script: String = "read password; exec sleep 10") {
    val rootfs = File(home, "ubuntu")
    var holdStart = false
    val startEntered = CountDownLatch(1)
    val releaseStart = CountDownLatch(1)
    @Volatile var configWrites = 0
    @Volatile var launches = 0
    var tracked = 0
    var helperVersion = "0.9.2"
    var versionCalls = 0
    var daemonStops = 0
    var otherPrivateProcess = false
    var unowned = false
    private var trackedProcess: Process? = null
    val installed = true
    fun privateAgentDiagnostics(name: String): Map<String, Any?> = emptyMap()
    fun writeAgentConfig(profile: String, config: String) { configWrites++ }
    fun clearStaleAgentLoginLock(profile: String) {}
    var portAnswers = false
    fun agentPaseoHome(profile: String) = File(home, "profiles/$profile/paseo")
    fun agentPortAnswers(port: Int) = portAnswers
    fun startAgentProcess(profile: String, args: List<String>): Process {
        if (args == listOf("/home/oc/.local/bin/paseo", "--version")) {
            versionCalls++
            return ProcessBuilder("/bin/sh", "-c", "printf '%s' '$helperVersion'").start()
        }
        launches++
        startEntered.countDown()
        if (holdStart) check(releaseStart.await(5, TimeUnit.SECONDS))
        val shell = if (File("/system/bin/sh").canExecute()) "/system/bin/sh" else "/bin/sh"
        return ProcessBuilder(shell, "-c", script).start()
    }
    fun trackPrivateAgentService(name: String, child: Process, port: Int) { tracked++; trackedProcess = child }
    fun requireAgentHostUpdateIdle(profile: String, process: Process?) {
        if (unowned || (process != null && process !== trackedProcess)) throw PhoneAgentHost.Failure("agent_host_unowned")
        if (otherPrivateProcess) throw PhoneAgentHost.Failure("agent_host_busy")
    }
    fun stopAgentProcess(child: Process) {
        if (child === trackedProcess && child.isAlive) daemonStops++
        child.destroyForcibly(); child.waitFor()
    }
    fun stopService(name: String) {}
    fun blockAgentProfile(profile: String) {}
    fun deleteAgentHome(profile: String) {}
    val agentSignIn = SignIn()
    class SignIn { fun deleteProfile(profile: String) {} }
}

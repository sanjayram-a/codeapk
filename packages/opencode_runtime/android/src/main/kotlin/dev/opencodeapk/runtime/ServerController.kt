package dev.opencodeapk.runtime

/** What [ServerController] needs from the thing that actually runs the server ([ServerSupervisor]). */
interface ServerBackend {
    fun start(extraEnv: Map<String, String>): ServerInfo
    fun stop()
    fun isRunning(): Boolean
    fun logTail(): String
}

enum class ServerState { STOPPED, STARTING, RUNNING, RESTARTING, FAILED }

data class ServerSnapshot(
    val state: ServerState,
    val port: Int? = null,
    val password: String? = null,
    val error: String? = null,
    val logTail: String? = null,
    /** Why the server stopped: "user", "idle", "memory". Only set while [state] is STOPPED. */
    val stopReason: String? = null,
)

data class ControllerConfig(
    val idleTimeoutMs: Long = 15 * 60_000,
    val maxRestarts: Int = 3,
    val restartBackoffMs: List<Long> = listOf(1_000, 3_000, 10_000),
    /** A server that stays up this long is considered healthy again: the restart counter starts over. */
    val stableResetMs: Long = 10 * 60_000,
)

/**
 * Lifecycle policy for the one resident OpenCode server: crash restarts with backoff, idle stop, and the
 * state that the UI observes. It has no threads of its own; the host calls [tick] about once a second.
 *
 * - [sessions] is the number of open terminal sessions, [busy] says whether OpenCode is working on something.
 *   While either is true, or a UI client is attached, the idle timer keeps resetting.
 * - If [busy] throws (probe failed), the server counts as busy: never stop work we cannot see.
 */
class ServerController(
    private val backend: ServerBackend,
    private val clock: Clock,
    private val sessions: () -> Int,
    private val busy: () -> Boolean,
    config: ControllerConfig = ControllerConfig(),
    private val onState: (ServerSnapshot) -> Unit,
) {
    @Volatile var snapshot: ServerSnapshot = ServerSnapshot(ServerState.STOPPED)
        private set

    private var config = config
    private var extraEnv: Map<String, String> = emptyMap()
    private var clients = 0
    private var attempts = 0
    private var runningSince = 0L
    private var nextRestartAt = 0L
    private var idleSince = 0L

    @Synchronized
    fun start(extraEnv: Map<String, String> = emptyMap()): ServerSnapshot {
        if (snapshot.state == ServerState.RUNNING) return snapshot
        this.extraEnv = extraEnv
        attempts = 0
        publish(ServerSnapshot(ServerState.STARTING))
        try {
            markRunning(backend.start(extraEnv))
        } catch (e: ServerStartException) {
            publish(ServerSnapshot(ServerState.FAILED, error = e.message, logTail = e.logTail))
            throw e
        } catch (e: Exception) {
            publish(ServerSnapshot(ServerState.FAILED, error = e.message, logTail = backend.logTail()))
            throw e
        }
        return snapshot
    }

    @Synchronized
    fun stop(reason: String = "user") {
        backend.stop()
        attempts = 0
        publish(ServerSnapshot(ServerState.STOPPED, stopReason = reason))
    }

    @Synchronized
    fun setClients(n: Int) {
        clients = n.coerceAtLeast(0)
        idleSince = clock.now()
    }

    @Synchronized
    fun setIdleTimeout(ms: Long) {
        config = config.copy(idleTimeoutMs = ms.coerceAtLeast(60_000))
    }

    @Synchronized
    fun tick() {
        when (snapshot.state) {
            ServerState.RUNNING -> tickRunning()
            ServerState.RESTARTING -> if (clock.now() >= nextRestartAt) restartNow()
            else -> Unit
        }
    }

    private fun tickRunning() {
        val now = clock.now()
        if (!backend.isRunning()) {
            if (now - runningSince >= config.stableResetMs) attempts = 0
            publish(ServerSnapshot(ServerState.RESTARTING, error = "server exited", logTail = backend.logTail()))
            scheduleRestart()
            return
        }
        if (now - runningSince >= config.stableResetMs) attempts = 0
        if (clients > 0 || sessions() > 0 || isBusy()) {
            idleSince = now
        } else if (now - idleSince >= config.idleTimeoutMs) {
            backend.stop()
            attempts = 0
            publish(ServerSnapshot(ServerState.STOPPED, stopReason = "idle"))
        }
    }

    private fun isBusy(): Boolean = try {
        busy()
    } catch (_: Exception) {
        true
    }

    private fun scheduleRestart() {
        val backoff = config.restartBackoffMs
        nextRestartAt = clock.now() + backoff[minOf(attempts, backoff.size - 1)]
    }

    private fun restartNow() {
        attempts++
        try {
            markRunning(backend.start(extraEnv))
        } catch (e: Exception) {
            val tail = (e as? ServerStartException)?.logTail ?: backend.logTail()
            if (attempts >= config.maxRestarts) {
                publish(ServerSnapshot(ServerState.FAILED, error = e.message, logTail = tail))
            } else {
                publish(ServerSnapshot(ServerState.RESTARTING, error = e.message, logTail = tail))
                scheduleRestart()
            }
        }
    }

    private fun markRunning(info: ServerInfo) {
        runningSince = clock.now()
        idleSince = runningSince
        publish(ServerSnapshot(ServerState.RUNNING, port = info.port, password = info.password))
    }

    private fun publish(s: ServerSnapshot) {
        snapshot = s
        onState(s)
    }
}

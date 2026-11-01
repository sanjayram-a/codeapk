package dev.opencodeapk.runtime

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

interface HostListener {
    fun onServerState(s: ServerSnapshot) {}
    fun onTerminalOutput(id: Int, bytes: ByteArray) {}
    fun onTerminalExit(id: Int, code: Int) {}
}

/**
 * Everything that must outlive a Flutter engine, one per process. The foreground [RuntimeService] only keeps this
 * process alive; all behaviour lives here so a new engine can attach to a server that is already running.
 *
 * Idle detection asks OpenCode itself whether it is working: `GET /session/status` returns a JSON object keyed by
 * session id whose values have a `type` (`idle`, `busy`, `retry`). Anything but an empty object / all `idle`
 * counts as busy, and any error counts as busy too (see [ServerController]). To be re-checked against the
 * server's `/doc` on a device (docs/opencode-api.md).
 */
class RuntimeHost private constructor(appContext: Context) {
    private val context: Context = appContext.applicationContext
    val paths = Paths(context.filesDir, File(context.applicationInfo.nativeLibraryDir))
    val fileManager = FileManager(File(paths.home.apply { mkdirs() }.path))
    val supervisor = ServerSupervisor(paths, heapMb = nodeHeapMb())
    private val listeners = CopyOnWriteArrayList<HostListener>()
    private val fileOps = AndroidFileOps()

    @Volatile var clients = 0
        private set

    val terminals = TerminalManager(
        ProotTerminalFactory(paths),
        { id, b -> listeners.forEach { it.onTerminalOutput(id, b) } },
        { id, code -> listeners.forEach { it.onTerminalExit(id, code) } },
    )

    val controller: ServerController = ServerController(
        backend = supervisor,
        clock = Clock.System,
        sessions = { terminals.attachedCount() },
        busy = { isServerBusy() },
    ) { snapshot ->
        syncService(snapshot)
        listeners.forEach { it.onServerState(snapshot) }
    }

    val environment = EnvironmentManager(paths, fileOps) {
        controller.snapshot.state != ServerState.STOPPED || terminals.count() > 0
    }

    private val worker = Executors.newCachedThreadPool()
    private val ticker: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "runtime-ticker").apply { isDaemon = true }
    }.also { ex ->
        ex.scheduleWithFixedDelay({ runCatching { controller.tick() } }, 1, 1, TimeUnit.SECONDS)
    }

    fun addListener(l: HostListener) { listeners += l }
    fun removeListener(l: HostListener) { listeners -= l }

    /** Starts the foreground service first (the app is in the foreground here), then the server. */
    fun startServer(extraEnv: Map<String, String>): ServerSnapshot {
        if (controller.snapshot.state != ServerState.RUNNING) startService()
        return controller.start(extraEnv)
    }

    fun stopServer(reason: String = "user") = controller.stop(reason)

    fun stopServerAsync(reason: String) { worker.execute { runCatching { controller.stop(reason) } } }

    fun setClients(n: Int) {
        clients = n
        controller.setClients(n)
    }

    fun onTrimMemory(level: Int) {
        worker.execute { runCatching { MemoryGuard.onTrim(level, terminals, controller, clients) } }
    }

    /** Foreground service follows the server: up while starting/running/restarting, down once stopped or failed. */
    private fun syncService(s: ServerSnapshot) {
        if (s.state == ServerState.STOPPED || s.state == ServerState.FAILED) {
            runCatching { context.stopService(Intent(context, RuntimeService::class.java)) }
        }
    }

    private fun startService() {
        runCatching { context.startForegroundService(Intent(context, RuntimeService::class.java)) }
    }

    private fun isServerBusy(): Boolean {
        val s = controller.snapshot
        val port = s.port ?: throw IllegalStateException("no server")
        val password = s.password ?: throw IllegalStateException("no server")
        val conn = URL("http://127.0.0.1:$port/session/status").openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 1000
            conn.readTimeout = 2000
            val token = Base64.getEncoder().encodeToString("opencode:$password".toByteArray())
            conn.setRequestProperty("Authorization", "Basic $token")
            if (conn.responseCode != 200) throw IllegalStateException("status ${conn.responseCode}")
            return statusIsBusy(conn.inputStream.bufferedReader().readText())
        } finally {
            conn.disconnect()
        }
    }

    private fun nodeHeapMb(): Int {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        return (info.totalMem / (1024 * 1024) / 4).toInt().coerceIn(512, 2048)
    }

    companion object {
        @Volatile private var instance: RuntimeHost? = null

        fun get(context: Context): RuntimeHost =
            instance ?: synchronized(this) { instance ?: RuntimeHost(context).also { instance = it } }

        private val TYPE = Regex(""""type"\s*:\s*"([^"]*)"""")

        /**
         * True when the `/session/status` body mentions any session whose `type` is not `idle`.
         * Throws when the body is not a JSON object, so a wrong endpoint is treated as "busy", never as "idle".
         */
        internal fun statusIsBusy(body: String): Boolean {
            val t = body.trim()
            if (!t.startsWith("{") || !t.endsWith("}")) throw IllegalStateException("unexpected status body")
            return TYPE.findAll(t).any { it.groupValues[1] != "idle" }
        }
    }
}

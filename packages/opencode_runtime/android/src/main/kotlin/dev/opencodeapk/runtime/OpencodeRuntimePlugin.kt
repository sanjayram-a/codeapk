package dev.opencodeapk.runtime

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import android.os.Handler
import android.os.Looper
import com.github.luben.zstd.ZstdInputStream
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.BufferedInputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Flutter bridge. Holds no state that must outlive the engine: servers, terminals and files live in [RuntimeHost].
 *
 *  - MethodChannel "opencode_runtime": server, terminal, file and environment calls
 *  - EventChannel "opencode_runtime/install": entries extracted so far; ends when the rootfs is ready
 *  - EventChannel "opencode_runtime/state": server state snapshots (the current one first)
 *  - EventChannel "opencode_runtime/terminal/<id>": raw terminal output, one channel per session
 * All work runs on background threads; results are posted back on the main thread.
 */
class OpencodeRuntimePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var messenger: BinaryMessenger
    private lateinit var host: RuntimeHost
    private lateinit var methods: MethodChannel
    private lateinit var installEvents: EventChannel
    private lateinit var stateEvents: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newCachedThreadPool()
    private val streams = ConcurrentHashMap<Int, TerminalStream>()
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        messenger = binding.binaryMessenger
        host = RuntimeHost.get(context)
        host.addListener(terminalListener)
        methods = MethodChannel(messenger, "opencode_runtime").also { it.setMethodCallHandler(this) }
        installEvents = EventChannel(messenger, "opencode_runtime/install").also { it.setStreamHandler(InstallStream()) }
        stateEvents = EventChannel(messenger, "opencode_runtime/state").also { it.setStreamHandler(StateStream()) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        installEvents.setStreamHandler(null)
        stateEvents.setStreamHandler(null)
        host.removeListener(terminalListener)
        // Sessions stay alive in the host; with no listener they count as detached (the memory guard sheds them).
        streams.keys.forEach { host.terminals.setAttached(it, false) }
        streams.clear()
        // The server is deliberately NOT stopped here: it keeps running under the foreground service.
    }

    // ---- activity (only needed to ask for the notification permission) ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (code != PERMISSION_REQUEST) return false
        pendingPermission?.success(results.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
        return true
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        val a = activity
        if (Build.VERSION.SDK_INT < 33 || a == null ||
            a.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(Build.VERSION.SDK_INT < 33 ||
                a?.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        a.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    // ---- method calls ----

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "selfTest" -> background(result) { selfTest() }
            "startServer" -> background(result) {
                @Suppress("UNCHECKED_CAST")
                val env = call.argument<Map<String, String>>("env") ?: emptyMap()
                snapshotMap(host.startServer(env))
            }
            "stopServer" -> background(result) { host.stopServer(); null }
            "serverSnapshot" -> result.success(snapshotMap(host.controller.snapshot))
            "serverLog" -> result.success(host.supervisor.log.tail())
            "setClients" -> { host.setClients(call.argument<Int>("n") ?: 0); result.success(null) }
            "setIdleTimeoutMinutes" -> {
                host.controller.setIdleTimeout((call.argument<Int>("minutes") ?: 15) * 60_000L)
                result.success(null)
            }
            "requestNotificationPermission" -> requestNotificationPermission(result)

            "terminalOpen" -> background(result) {
                val command = call.argument<List<String>>("command")
                val id = host.terminals.open(command, call.argument<Int>("rows") ?: 24, call.argument<Int>("cols") ?: 80)
                stream(id) // make sure the output channel exists before Dart is told the id
                id
            }
            "terminalWrite" -> background(result) {
                host.terminals.write(call.argument<Int>("id")!!, call.argument<ByteArray>("bytes")!!); null
            }
            "terminalResize" -> background(result) {
                host.terminals.resize(call.argument<Int>("id")!!, call.argument<Int>("rows") ?: 24, call.argument<Int>("cols") ?: 80)
                null
            }
            "terminalClose" -> background(result) {
                val id = call.argument<Int>("id")!!
                streams.remove(id)
                host.terminals.close(id)
                null
            }

            "fileList" -> background(result) {
                host.fileManager.list(call.argument<String>("path") ?: "/root").map {
                    mapOf("name" to it.name, "path" to it.path, "isDir" to it.isDir, "size" to it.size, "modifiedMs" to it.modifiedMs)
                }
            }
            "fileMkdir" -> background(result) { host.fileManager.mkdir(call.argument<String>("path")!!); null }
            "fileCreate" -> background(result) { host.fileManager.createFile(call.argument<String>("path")!!); null }
            "fileRename" -> background(result) {
                host.fileManager.rename(call.argument<String>("path")!!, call.argument<String>("newName")!!); null
            }
            "fileDelete" -> background(result) { host.fileManager.delete(call.argument<String>("path")!!); null }
            "fileCopy" -> background(result) {
                host.fileManager.copy(call.argument<String>("src")!!, call.argument<String>("dstDir")!!); null
            }
            "fileMove" -> background(result) {
                host.fileManager.move(call.argument<String>("src")!!, call.argument<String>("dstDir")!!); null
            }
            "fileReadText" -> background(result) { host.fileManager.readText(call.argument<String>("path")!!) }
            "fileWriteText" -> background(result) {
                host.fileManager.writeText(call.argument<String>("path")!!, call.argument<String>("text") ?: ""); null
            }

            "environmentInfo" -> background(result) {
                val i = host.environment.info()
                mapOf(
                    "rootfsBytes" to i.rootfsBytes, "homeBytes" to i.homeBytes,
                    "rootfsVersion" to i.rootfsVersion, "extraPackages" to i.extraPackages,
                )
            }
            "resetEnvironment" -> background(result) { host.environment.reset(); null }
            "storageInfo" -> background(result) {
                val i = host.environment.storageInfo()
                mapOf(
                    "npmBytes" to i.npmBytes, "pythonBytes" to i.pythonBytes,
                    "projects" to i.projects.map { mapOf("name" to it.name, "path" to it.path, "bytes" to it.bytes) },
                )
            }
            "clearCache" -> background(result) {
                val kind = CacheKind.valueOf(call.argument<String>("kind")!!.uppercase())
                host.environment.clearCache(kind)
            }
            "saveToDownloads" -> background(result) { saveToDownloads(call.argument<String>("path")!!) }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: ServerStartException) {
                main.post { result.error("server_start", e.message, e.logTail) }
            } catch (e: SecurityException) {
                main.post { result.error("outside_sandbox", e.message, null) }
            } catch (e: IllegalArgumentException) {
                main.post { result.error("invalid", e.message, null) }
            } catch (e: IllegalStateException) {
                main.post { result.error(if (e.message == "busy") "busy" else "state", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error(e.javaClass.simpleName, e.message, null) }
            }
        }
    }

    /** Copies a sandbox file into the phone's public Downloads folder. Returns the name it was saved under. */
    private fun saveToDownloads(guestPath: String): String {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { "Saving to Downloads needs Android 10 or newer" }
        val source = host.fileManager.regularFile(guestPath)
        val ext = source.extension.lowercase()
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, source.name)
            put(MediaStore.Downloads.MIME_TYPE, MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream")
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw java.io.IOException("cannot create the file in Downloads")
        try {
            resolver.openOutputStream(uri)!!.use { out -> source.inputStream().use { it.copyTo(out) } }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return source.name
    }

    /** Runs one shell line through proot and returns one value per probe. */
    private fun selfTest(): Map<String, String> {
        val paths = host.paths
        listOf(paths.home, paths.tmp, paths.prootTmp).forEach { it.mkdirs() }
        val keys = listOf("arch", "node", "python", "opencode")
        val script = "uname -m; node -v; python3 -V; /usr/local/bin/opencode --version"
        val argv = ProotLauncher.argv(paths, listOf("/bin/sh", "-c", script))
        val proc = ProcessSpawner.spawn(argv, EnvBuilder.build(paths), paths.filesDir)
        val lines = proc.stdout.bufferedReader().readLines()
        val values = lines.filter { it.isNotBlank() && !it.startsWith("proot warning") }
        if (values.size < keys.size) throw IllegalStateException("self-test output:\n" + lines.joinToString("\n"))
        return keys.zip(values.takeLast(keys.size)).toMap()
    }

    private fun snapshotMap(s: ServerSnapshot): Map<String, Any?> = mapOf(
        "state" to s.state.name.lowercase(),
        "port" to s.port, "password" to s.password,
        "error" to s.error, "logTail" to s.logTail, "stopReason" to s.stopReason,
    )

    // ---- streams ----

    private inner class InstallStream : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            worker.execute {
                try {
                    val abi = Build.SUPPORTED_ABIS.first()
                    val bundled = context.assets.open("rootfs/rootfs.version").bufferedReader().readText().trim()
                    RootfsInstaller.ensureInstalled(
                        RootfsInstaller(host.paths, AndroidFileOps()),
                        openTar = {
                            ZstdInputStream(BufferedInputStream(context.assets.open("rootfs/rootfs-$abi.tar.zst"), 1 shl 20))
                        },
                        bundledVersion = bundled,
                    ) { n -> if (n % 100 == 0) main.post { events.success(n) } }
                    main.post { events.endOfStream() }
                } catch (e: Exception) {
                    main.post { events.error(e.javaClass.simpleName, e.message, null) }
                }
            }
        }

        override fun onCancel(arguments: Any?) = Unit
    }

    private inner class StateStream : EventChannel.StreamHandler {
        private var listener: HostListener? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            listener?.let { host.removeListener(it) }
            val l = object : HostListener {
                override fun onServerState(s: ServerSnapshot) { main.post { events.success(snapshotMap(s)) } }
            }
            listener = l
            host.addListener(l)
            events.success(snapshotMap(host.controller.snapshot))
        }

        override fun onCancel(arguments: Any?) {
            listener?.let { host.removeListener(it) }
            listener = null
        }
    }

    /** Output for one terminal session. Output produced before Dart starts listening is kept (bounded) and replayed. */
    private inner class TerminalStream(val id: Int) : EventChannel.StreamHandler {
        private val lock = Any()
        private var sink: EventChannel.EventSink? = null
        private val backlog = ArrayDeque<ByteArray>()
        private var backlogBytes = 0
        private var exited = false

        fun output(bytes: ByteArray) = synchronized(lock) {
            val s = sink
            if (s != null) {
                main.post { s.success(bytes) }
            } else {
                backlog.addLast(bytes)
                backlogBytes += bytes.size
                while (backlogBytes > MAX_BACKLOG && backlog.size > 1) backlogBytes -= backlog.removeFirst().size
            }
        }

        fun exit() = synchronized(lock) {
            exited = true
            sink?.let { s -> main.post { s.endOfStream() } }
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            synchronized(lock) {
                sink = events
                while (backlog.isNotEmpty()) { val b = backlog.removeFirst(); main.post { events.success(b) } }
                backlogBytes = 0
                if (exited) main.post { events.endOfStream() }
            }
            host.terminals.setAttached(id, true)
        }

        override fun onCancel(arguments: Any?) {
            synchronized(lock) { sink = null }
            host.terminals.setAttached(id, false)
        }
    }

    private val terminalListener = object : HostListener {
        override fun onTerminalOutput(id: Int, bytes: ByteArray) { stream(id).output(bytes) }
        override fun onTerminalExit(id: Int, code: Int) { stream(id).exit() }
    }

    private fun stream(id: Int): TerminalStream = streams.getOrPut(id) {
        TerminalStream(id).also { s ->
            main.post { EventChannel(messenger, "opencode_runtime/terminal/$id").setStreamHandler(s) }
        }
    }

    companion object {
        private const val PERMISSION_REQUEST = 4711
        private const val MAX_BACKLOG = 256 * 1024
    }
}

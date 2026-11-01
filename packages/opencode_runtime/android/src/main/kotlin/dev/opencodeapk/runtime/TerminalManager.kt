package dev.opencodeapk.runtime

import java.io.InputStream

/** One interactive process on a pseudo-terminal. [PtySession] is the real implementation. */
interface TerminalProcess {
    val output: InputStream
    fun write(b: ByteArray)
    fun resize(rows: Int, cols: Int)
    fun waitFor(): Int
    fun close()
}

/** Opens a terminal process. A null [command] means the login shell (`/bin/bash -l`). */
fun interface TerminalFactory {
    fun open(command: List<String>?, rows: Int, cols: Int): TerminalProcess
}

/** Real factory: proot + the same explicit environment as the server. */
class ProotTerminalFactory(private val paths: Paths) : TerminalFactory {
    override fun open(command: List<String>?, rows: Int, cols: Int): TerminalProcess {
        listOf(paths.home, paths.tmp, paths.prootTmp).forEach { it.mkdirs() }
        val argv = ProotLauncher.argv(paths, command ?: listOf("/bin/bash", "-l"))
        val session = PtySession(argv, EnvBuilder.build(paths), paths.filesDir.absolutePath, rows, cols)
        return object : TerminalProcess {
            override val output = session.output
            override fun write(b: ByteArray) = session.write(b)
            override fun resize(rows: Int, cols: Int) = session.resize(rows, cols)
            override fun waitFor() = session.waitFor()
            override fun close() = session.close()
        }
    }
}

/**
 * Terminal sessions by id. Output and exit events are pushed to the callbacks from a reader thread per session.
 * A session whose process has exited stays known (so the UI can show "[process exited]") until [close]d, but no
 * longer counts as live.
 */
class TerminalManager(
    private val factory: TerminalFactory,
    private val onOutput: (id: Int, bytes: ByteArray) -> Unit,
    private val onExit: (id: Int, code: Int) -> Unit,
) {
    private class Session(val process: TerminalProcess) {
        @Volatile var attached = false
        @Volatile var exited = false
        @Volatile var closed = false
    }

    private val sessions = LinkedHashMap<Int, Session>()
    private var nextId = 1

    fun open(command: List<String>?, rows: Int, cols: Int): Int {
        val process = factory.open(command, clamp(rows), clamp(cols))
        val session = Session(process)
        val id = synchronized(this) { nextId++.also { sessions[it] = session } }
        Thread({ pump(id, session) }, "terminal-$id").apply { isDaemon = true; start() }
        return id
    }

    private fun pump(id: Int, s: Session) {
        val buf = ByteArray(8192)
        try {
            while (true) {
                val n = s.process.output.read(buf)
                if (n < 0) break
                if (s.closed) return
                if (n > 0) onOutput(id, buf.copyOf(n))
            }
        } catch (_: Exception) {
            // output stream closed under us
        }
        if (s.closed) return
        val code = try { s.process.waitFor() } catch (_: Exception) { -1 }
        s.exited = true
        if (!s.closed) onExit(id, code)
    }

    fun write(id: Int, bytes: ByteArray) {
        val s = live(id) ?: return
        try { s.process.write(bytes) } catch (_: Exception) { /* process went away */ }
    }

    fun resize(id: Int, rows: Int, cols: Int) {
        val s = live(id) ?: return
        try { s.process.resize(clamp(rows), clamp(cols)) } catch (_: Exception) { /* process went away */ }
    }

    fun close(id: Int) {
        val s = synchronized(this) { sessions.remove(id) } ?: return
        s.closed = true
        try { s.process.close() } catch (_: Exception) { }
    }

    fun setAttached(id: Int, attached: Boolean) {
        synchronized(this) { sessions[id] }?.attached = attached
    }

    /** Sessions whose process is still running. */
    @Synchronized
    fun count(): Int = sessions.values.count { !it.exited }

    /** Live sessions that no Dart listener is attached to. */
    @Synchronized
    fun detachedIds(): List<Int> = sessions.filter { !it.value.attached }.keys.toList()

    fun closeAll() {
        val ids = synchronized(this) { sessions.keys.toList() }
        ids.forEach { close(it) }
    }

    private fun live(id: Int): Session? = synchronized(this) { sessions[id] }?.takeIf { !it.exited && !it.closed }

    private fun clamp(n: Int) = n.coerceIn(1, 500)
}

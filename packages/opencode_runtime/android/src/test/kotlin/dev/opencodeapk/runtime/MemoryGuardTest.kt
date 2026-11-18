package dev.opencodeapk.runtime

import java.io.InputStream
import kotlin.test.Test
import kotlin.test.assertEquals

internal class MemoryGuardTest {
    private class Proc : TerminalProcess {
        @Volatile var closed = false
        override val output: InputStream = object : InputStream() {
            override fun read(): Int { while (!closed) Thread.sleep(5); return -1 }
        }
        override fun write(b: ByteArray) = Unit
        override fun resize(rows: Int, cols: Int) = Unit
        override fun waitFor() = 0
        override fun close() { closed = true }
    }

    private class Backend : ServerBackend {
        var alive = false
        var stops = 0
        override fun start(extraEnv: Map<String, String>): ServerInfo { alive = true; return ServerInfo(4100, "pw") }
        override fun stop() { alive = false; stops++ }
        override fun isRunning() = alive
        override fun logTail() = ""
    }

    private class Rig {
        val procs = mutableListOf<Proc>()
        val terminals = TerminalManager({ _, _, _ -> Proc().also { procs += it } }, { _, _ -> }, { _, _ -> })
        val backend = Backend()
        val controller = ServerController(backend, Clock.System, { terminals.count() }, { false }) { }
        init { controller.start() }
    }

    @Test
    fun calmLevelsDoNothing() {
        val r = Rig()
        r.terminals.open(null, 24, 80)
        for (level in listOf(0, 5, 20 /* UI_HIDDEN: just "app went to background" */)) {
            MemoryGuard.onTrim(level, r.terminals, r.controller, clients = 0)
        }
        assertEquals(1, r.terminals.count())
        assertEquals(0, r.backend.stops)
    }

    @Test
    fun runningLowClosesOnlyDetachedTerminals() {
        val r = Rig()
        val attached = r.terminals.open(null, 24, 80)
        r.terminals.open(null, 24, 80)
        r.terminals.setAttached(attached, true)
        MemoryGuard.onTrim(10, r.terminals, r.controller, clients = 0)
        assertEquals(1, r.terminals.count())
        assertEquals(listOf(false, true), r.procs.map { it.closed })
        assertEquals(0, r.backend.stops)
    }

    @Test
    fun criticalStopsServerOnlyWithoutClients() {
        val withClient = Rig()
        MemoryGuard.onTrim(15, withClient.terminals, withClient.controller, clients = 1)
        assertEquals(0, withClient.backend.stops)

        val without = Rig()
        MemoryGuard.onTrim(15, without.terminals, without.controller, clients = 0)
        assertEquals(1, without.backend.stops)
        assertEquals("memory", without.controller.snapshot.stopReason)
    }

    @Test
    fun cachedProcessLevelsAlsoShedTerminals() {
        val r = Rig()
        r.terminals.open(null, 24, 80)
        MemoryGuard.onTrim(40, r.terminals, r.controller, clients = 0)
        assertEquals(0, r.terminals.count())
        assertEquals(0, r.backend.stops) // BACKGROUND level alone does not stop the server
        MemoryGuard.onTrim(60, r.terminals, r.controller, clients = 0)
        assertEquals(1, r.backend.stops)
    }
}

package dev.opencodeapk.runtime

import java.io.InputStream
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class TerminalManagerTest {
    private class FakeProcess : TerminalProcess {
        private val pipe = PipedOutputStream()
        override val output: InputStream = PipedInputStream(pipe, 1 shl 16)
        val writes = CopyOnWriteArrayList<String>()
        val resizes = CopyOnWriteArrayList<Pair<Int, Int>>()
        val exited = CountDownLatch(1)
        @Volatile var closed = false
        @Volatile var code = 0
        override fun write(b: ByteArray) { writes += String(b) }
        override fun resize(rows: Int, cols: Int) { resizes += rows to cols }
        override fun waitFor(): Int { exited.await(2, TimeUnit.SECONDS); return code }
        override fun close() { closed = true; exit(130) }
        fun emit(text: String) { pipe.write(text.toByteArray()); pipe.flush() }
        fun exit(c: Int = 0) { code = c; runCatching { pipe.close() }; exited.countDown() }
    }

    private class Rig {
        val procs = mutableListOf<FakeProcess>()
        val commands = mutableListOf<List<String>?>()
        val out = CopyOnWriteArrayList<Pair<Int, String>>()
        val exits = CopyOnWriteArrayList<Pair<Int, Int>>()
        val manager = TerminalManager(
            { cmd, _, _ -> commands += cmd; FakeProcess().also { procs += it } },
            { id, bytes -> out += id to String(bytes) },
            { id, code -> exits += id to code },
        )
    }

    private fun await(what: String, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + 3000
        while (!cond()) {
            if (System.currentTimeMillis() > end) throw AssertionError("timed out waiting for $what")
            Thread.sleep(5)
        }
    }

    @Test
    fun opensAndRoutesOutputById() {
        val r = Rig()
        val a = r.manager.open(null, 24, 80)
        val b = r.manager.open(listOf("/bin/sh", "-c", "true"), 24, 80)
        assertTrue(a != b)
        assertEquals(listOf(null, listOf("/bin/sh", "-c", "true")), r.commands)
        r.procs[0].emit("from-a")
        r.procs[1].emit("from-b")
        await("output") { r.out.size == 2 }
        assertTrue((a to "from-a") in r.out)
        assertTrue((b to "from-b") in r.out)
        assertEquals(2, r.manager.count())
    }

    @Test
    fun clampsResize() {
        val r = Rig()
        val id = r.manager.open(null, 24, 80)
        r.manager.resize(id, 0, 0)
        r.manager.resize(id, 99999, 99999)
        assertEquals(listOf(1 to 1, 500 to 500), r.procs[0].resizes.toList())
    }

    @Test
    fun clampsInitialSize() {
        val sizes = mutableListOf<Pair<Int, Int>>()
        val m = TerminalManager({ _, rows, cols -> sizes += rows to cols; FakeProcess() }, { _, _ -> }, { _, _ -> })
        m.open(null, 0, -5)
        assertEquals(listOf(1 to 1), sizes)
    }

    @Test
    fun writeAfterExitIsIgnored() {
        val r = Rig()
        val id = r.manager.open(null, 24, 80)
        r.procs[0].exit(7)
        await("exit event") { r.exits.isNotEmpty() }
        assertEquals(listOf(id to 7), r.exits.toList())
        r.manager.write(id, "x".toByteArray())
        r.manager.resize(id, 10, 10)
        assertTrue(r.procs[0].writes.isEmpty())
        assertEquals(0, r.manager.count()) // an exited session is no longer live
    }

    @Test
    fun unknownIdIsIgnored() {
        val r = Rig()
        r.manager.write(99, "x".toByteArray())
        r.manager.resize(99, 1, 1)
        r.manager.close(99)
        r.manager.setAttached(99, true)
    }

    @Test
    fun closeRemovesSessionAndStopsOutput() {
        val r = Rig()
        val id = r.manager.open(null, 24, 80)
        r.manager.close(id)
        assertTrue(r.procs[0].closed)
        assertEquals(0, r.manager.count())
        runCatching { r.procs[0].emit("late") }
        Thread.sleep(50)
        assertFalse(r.out.any { it.second == "late" })
        assertTrue(r.exits.none { it.first == id }) // a closed session does not report an exit
    }

    @Test
    fun detachedIdsTracksAttachedFlag() {
        val r = Rig()
        val a = r.manager.open(null, 24, 80)
        val b = r.manager.open(null, 24, 80)
        assertEquals(setOf(a, b), r.manager.detachedIds().toSet())
        r.manager.setAttached(a, true)
        assertEquals(listOf(b), r.manager.detachedIds())
        r.manager.setAttached(a, false)
        assertEquals(setOf(a, b), r.manager.detachedIds().toSet())
    }

    @Test
    fun closeAllClosesEverything() {
        val r = Rig()
        r.manager.open(null, 24, 80)
        r.manager.open(null, 24, 80)
        r.manager.closeAll()
        assertEquals(0, r.manager.count())
        assertTrue(r.procs.all { it.closed })
    }
}

package dev.opencodeapk.runtime

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class ServerControllerTest {
    private class FakeClock : Clock {
        var t = 0L
        override fun now() = t
        override fun sleep(ms: Long) { t += ms }
        fun advance(ms: Long) { t += ms }
    }

    private class FakeBackend : ServerBackend {
        var starts = 0
        var stops = 0
        var alive = false
        var failWith: ServerStartException? = null
        override fun start(extraEnv: Map<String, String>): ServerInfo {
            starts++
            failWith?.let { throw it }
            alive = true
            return ServerInfo(4100 + starts, "pw$starts")
        }
        override fun stop() { stops++; alive = false }
        override fun isRunning() = alive
        override fun logTail() = "log tail"
    }

    private class Rig(config: ControllerConfig = ControllerConfig()) {
        val clock = FakeClock()
        val backend = FakeBackend()
        val states = mutableListOf<ServerSnapshot>()
        var sessions = 0
        var busy: () -> Boolean = { false }
        val controller = ServerController(backend, clock, { sessions }, { busy() }, config) { states += it }
        fun minutes(n: Long) = clock.advance(n * 60_000)
    }

    @Test
    fun startMovesThroughStartingToRunning() {
        val r = Rig()
        val s = r.controller.start()
        assertEquals(listOf(ServerState.STARTING, ServerState.RUNNING), r.states.map { it.state })
        assertEquals(ServerState.RUNNING, s.state)
        assertEquals(4101, s.port)
        assertEquals("pw1", s.password)
    }

    @Test
    fun startWhenRunningIsNoOp() {
        val r = Rig()
        val first = r.controller.start()
        val second = r.controller.start()
        assertEquals(first.port, second.port)
        assertEquals(1, r.backend.starts)
    }

    @Test
    fun restartsAfterCrashWithBackoff() {
        val r = Rig()
        r.controller.start()
        r.backend.alive = false
        r.controller.tick()
        assertEquals(ServerState.RESTARTING, r.controller.snapshot.state)
        r.clock.advance(500)
        r.controller.tick()
        assertEquals(1, r.backend.starts) // still waiting for the 1 s backoff
        r.clock.advance(600)
        r.controller.tick()
        assertEquals(2, r.backend.starts)
        assertEquals(ServerState.RUNNING, r.controller.snapshot.state)
        assertEquals(4102, r.controller.snapshot.port)
        assertEquals("pw2", r.controller.snapshot.password)
    }

    @Test
    fun givesUpAfterMaxRestarts() {
        val r = Rig()
        r.controller.start()
        r.backend.failWith = ServerStartException("x", "boom")
        r.backend.alive = false
        repeat(40) {
            r.controller.tick()
            r.clock.advance(5_000)
        }
        assertEquals(ServerState.FAILED, r.controller.snapshot.state)
        assertTrue(r.controller.snapshot.logTail!!.contains("boom"))
        assertEquals(1 + 3, r.backend.starts) // the original start plus 3 restarts
        val before = r.backend.starts
        repeat(10) { r.controller.tick(); r.clock.advance(60_000) }
        assertEquals(before, r.backend.starts)
    }

    @Test
    fun restartCounterResetsAfterStableRun() {
        val r = Rig()
        r.controller.start()
        repeat(6) {
            r.minutes(11) // stable for longer than stableResetMs
            r.controller.tick()
            r.backend.alive = false
            r.controller.tick()
            r.clock.advance(1_100)
            r.controller.tick()
            assertEquals(ServerState.RUNNING, r.controller.snapshot.state, "round $it")
        }
    }

    @Test
    fun userStopNeverRestarts() {
        val r = Rig()
        r.controller.start()
        r.controller.stop()
        assertEquals(ServerState.STOPPED, r.controller.snapshot.state)
        assertEquals("user", r.controller.snapshot.stopReason)
        repeat(5) { r.controller.tick(); r.minutes(1) }
        assertEquals(1, r.backend.starts)
    }

    @Test
    fun idleStopsAfterTimeout() {
        val r = Rig()
        r.controller.start()
        r.controller.setClients(0)
        r.minutes(14)
        r.controller.tick()
        assertEquals(ServerState.RUNNING, r.controller.snapshot.state)
        r.minutes(1)
        r.controller.tick()
        assertEquals(ServerState.STOPPED, r.controller.snapshot.state)
        assertEquals("idle", r.controller.snapshot.stopReason)
        assertEquals(1, r.backend.stops)
    }

    @Test
    fun attachedClientResetsIdle() {
        val r = Rig()
        r.controller.start()
        r.controller.setClients(1)
        repeat(20) { r.minutes(1); r.controller.tick() }
        assertEquals(ServerState.RUNNING, r.controller.snapshot.state)
        r.controller.setClients(0)
        r.minutes(14)
        r.controller.tick()
        assertEquals(ServerState.RUNNING, r.controller.snapshot.state)
        r.minutes(1)
        r.controller.tick()
        assertEquals(ServerState.STOPPED, r.controller.snapshot.state)
    }

    @Test
    fun idleNeverStopsWithTerminalOrBusyServer() {
        val r = Rig()
        r.controller.start()
        r.controller.setClients(0)
        r.sessions = 1
        repeat(30) { r.minutes(1); r.controller.tick() }
        assertEquals(ServerState.RUNNING, r.controller.snapshot.state)
        r.sessions = 0
        r.busy = { true }
        repeat(30) { r.minutes(1); r.controller.tick() }
        assertEquals(ServerState.RUNNING, r.controller.snapshot.state)
    }

    @Test
    fun busyProbeErrorCountsAsBusy() {
        val r = Rig()
        r.controller.start()
        r.controller.setClients(0)
        r.busy = { throw RuntimeException("probe down") }
        repeat(30) { r.minutes(1); r.controller.tick() }
        assertEquals(ServerState.RUNNING, r.controller.snapshot.state)
    }

    @Test
    fun failedStartReportsLogAndRethrows() {
        val r = Rig()
        r.backend.failWith = ServerStartException("nope", "tail!")
        val e = runCatching { r.controller.start() }.exceptionOrNull()
        assertNotNull(e)
        assertEquals(ServerState.FAILED, r.controller.snapshot.state)
        assertEquals("tail!", r.controller.snapshot.logTail)
        assertNull(r.controller.snapshot.port)
    }

    @Test
    fun explicitStartAfterFailedWorks() {
        val r = Rig()
        r.backend.failWith = ServerStartException("nope", "tail!")
        runCatching { r.controller.start() }
        r.backend.failWith = null
        assertEquals(ServerState.RUNNING, r.controller.start().state)
    }
}

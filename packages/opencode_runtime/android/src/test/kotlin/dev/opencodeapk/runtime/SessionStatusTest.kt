package dev.opencodeapk.runtime

import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class SessionStatusTest {
    @Test
    fun emptyObjectIsIdle() = assertFalse(RuntimeHost.statusIsBusy("{}"))

    @Test
    fun allIdleIsIdle() = assertFalse(RuntimeHost.statusIsBusy("""{"ses_1":{"type":"idle"},"ses_2":{ "type" : "idle" }}"""))

    @Test
    fun anyBusyOrRetryIsBusy() {
        assertTrue(RuntimeHost.statusIsBusy("""{"ses_1":{"type":"idle"},"ses_2":{"type":"busy"}}"""))
        assertTrue(RuntimeHost.statusIsBusy("""{"ses_1":{"type":"retry","attempt":2}}"""))
    }

    @Test
    fun nonObjectBodyThrows() {
        assertFailsWith<IllegalStateException> { RuntimeHost.statusIsBusy("<html>not found</html>") }
        assertFailsWith<IllegalStateException> { RuntimeHost.statusIsBusy("") }
    }
}

package dev.opencodeapk.runtime

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class EnvironmentManagerTest {
    private lateinit var base: File
    private lateinit var paths: Paths
    private var busy = false
    private lateinit var manager: EnvironmentManager

    @BeforeTest
    fun setUp() {
        base = Files.createTempDirectory("env-test").toFile()
        paths = Paths(File(base, "files"), File(base, "lib"))
        paths.filesDir.mkdirs()
        manager = EnvironmentManager(paths, RecordingFileOps()) { busy }
    }

    @AfterTest
    fun tearDown() {
        base.deleteRecursively()
    }

    private fun file(f: File, text: String) {
        f.parentFile.mkdirs()
        f.writeText(text)
    }

    @Test
    fun infoSumsSizesAndReadsExtras() {
        file(File(paths.rootfs, "bin/sh"), "x".repeat(100))
        file(File(paths.rootfs, ".manifest.json"), """{"version":"2026.10.0","arch":"x86_64"}""")
        file(File(paths.home, "projects/a.py"), "y".repeat(40))
        file(File(paths.home, ".apk-extra"), "build-base\n\nvim\n")
        val info = manager.info()
        assertEquals(100L + File(paths.rootfs, ".manifest.json").length(), info.rootfsBytes)
        assertEquals(40L + File(paths.home, ".apk-extra").length(), info.homeBytes)
        assertEquals("2026.10.0", info.rootfsVersion)
        assertEquals(listOf("build-base", "vim"), info.extraPackages)
    }

    @Test
    fun infoOnMissingRootfs() {
        val info = manager.info()
        assertEquals(0L, info.rootfsBytes)
        assertEquals(0L, info.homeBytes)
        assertNull(info.rootfsVersion)
        assertEquals(emptyList(), info.extraPackages)
    }

    @Test
    fun keepsHome() {
        file(File(paths.rootfs, "bin/sh"), "x")
        file(File(paths.rootfsNew, "partial"), "x")
        file(File(paths.rootfsOld, "old"), "x")
        file(File(paths.home, "projects/a.py"), "print(1)")
        manager.reset()
        assertFalse(paths.rootfs.exists())
        assertFalse(paths.rootfsNew.exists())
        assertFalse(paths.rootfsOld.exists())
        assertEquals("print(1)", File(paths.home, "projects/a.py").readText())
    }

    @Test
    fun refusesWhileBusy() {
        file(File(paths.rootfs, "bin/sh"), "x")
        busy = true
        assertFailsWith<IllegalStateException> { manager.reset() }
        assertTrue(File(paths.rootfs, "bin/sh").exists())
    }
}

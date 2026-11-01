package dev.opencodeapk.runtime

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class FileManagerTest {
    private lateinit var base: File
    private lateinit var home: File
    private lateinit var fm: FileManager

    @BeforeTest
    fun setUp() {
        base = Files.createTempDirectory("fm-test").toFile()
        home = File(base, "home").apply { mkdirs() }
        fm = FileManager(home)
    }

    @AfterTest
    fun tearDown() {
        base.deleteRecursively()
    }

    private fun put(rel: String, text: String = "x") {
        val f = File(home, rel)
        f.parentFile.mkdirs()
        f.writeText(text)
    }

    @Test
    fun listsFoldersFirstThenFilesCaseInsensitive() {
        put("b.txt"); put("A.txt"); put("zdir/inner.txt"); put("Adir/inner.txt")
        val names = fm.list("/root").map { it.name }
        assertEquals(listOf("Adir", "zdir", "A.txt", "b.txt"), names)
        val e = fm.list("/root").first { it.name == "A.txt" }
        assertEquals("/root/A.txt", e.path)
        assertFalse(e.isDir)
        assertEquals(1L, e.size)
    }

    @Test
    fun emptyPathMeansRoot() {
        put("a.txt")
        assertEquals(listOf("a.txt"), fm.list("").map { it.name })
        assertEquals(listOf("a.txt"), fm.list("/root/").map { it.name })
    }

    @Test
    fun rejectsTraversal() {
        for (p in listOf("/root/../x", "/etc/passwd", "/root/../../x", "../x", "/rootx/a")) {
            assertFailsWith<SecurityException>(p) { fm.readText(p) }
        }
        assertFailsWith<SecurityException> { fm.mkdir("/root/../evil") }
        assertFalse(File(base, "evil").exists())
    }

    @Test
    fun rejectsSymlinkEscape() {
        val outside = File(base, "secret.txt").apply { writeText("secret") }
        val link = File(home, "link")
        try {
            Files.createSymbolicLink(link.toPath(), outside.toPath())
        } catch (e: Exception) {
            return // this host cannot create symlinks (Windows without developer mode)
        }
        assertFailsWith<SecurityException> { fm.readText("/root/link") }
        assertFailsWith<SecurityException> { fm.writeText("/root/link", "pwn") }
        assertEquals("secret", outside.readText())
        // deleting the link itself is allowed and must not delete the target
        fm.delete("/root/link")
        assertTrue(outside.exists())
    }

    @Test
    fun deleteRefusesRoot() {
        put("a.txt")
        assertFailsWith<SecurityException> { fm.delete("/root") }
        assertFailsWith<SecurityException> { fm.delete("") }
        assertTrue(File(home, "a.txt").exists())
    }

    @Test
    fun deleteIsRecursive() {
        put("d/e/f.txt")
        fm.delete("/root/d")
        assertFalse(File(home, "d").exists())
    }

    @Test
    fun renameRejectsSlashAndExistingName() {
        put("a.txt"); put("b.txt")
        assertFailsWith<IllegalArgumentException> { fm.rename("/root/a.txt", "x/y") }
        assertFailsWith<IllegalArgumentException> { fm.rename("/root/a.txt", "..") }
        assertFailsWith<IllegalArgumentException> { fm.rename("/root/a.txt", "b.txt") }
        fm.rename("/root/a.txt", "c.txt")
        assertTrue(File(home, "c.txt").exists())
        assertFalse(File(home, "a.txt").exists())
    }

    @Test
    fun mkdirAndCreateFile() {
        fm.mkdir("/root/projects/new")
        assertTrue(File(home, "projects/new").isDirectory)
        fm.createFile("/root/projects/new/a.py")
        assertTrue(File(home, "projects/new/a.py").isFile)
        assertFailsWith<IllegalArgumentException> { fm.createFile("/root/projects/new/a.py") } // exists
    }

    @Test
    fun copyAndMoveIntoSubfolder() {
        put("a.txt", "hello"); put("d/keep.txt")
        fm.copy("/root/a.txt", "/root/d")
        assertEquals("hello", File(home, "d/a.txt").readText())
        assertTrue(File(home, "a.txt").exists())
        // the name already exists in the target: must not silently overwrite
        assertFailsWith<IllegalArgumentException> { fm.move("/root/a.txt", "/root/d") }
        assertTrue(File(home, "a.txt").exists())
    }

    @Test
    fun moveRemovesSource() {
        put("a.txt", "hello"); put("d/keep.txt")
        fm.move("/root/a.txt", "/root/d")
        assertFalse(File(home, "a.txt").exists())
        assertEquals("hello", File(home, "d/a.txt").readText())
    }

    @Test
    fun copyFolderRecursivelyButNotIntoItself() {
        put("d/e/f.txt", "deep")
        fm.mkdir("/root/dst")
        fm.copy("/root/d", "/root/dst")
        assertEquals("deep", File(home, "dst/d/e/f.txt").readText())
        assertFailsWith<IllegalArgumentException> { fm.copy("/root/d", "/root/d/e") }
        assertFailsWith<IllegalArgumentException> { fm.move("/root/d", "/root/d/e") }
    }

    @Test
    fun readTextRejectsBinaryAndOversize() {
        File(home, "bin.dat").writeBytes(byteArrayOf(1, 2, 0, 3))
        assertFailsWith<IllegalArgumentException> { fm.readText("/root/bin.dat") }
        put("big.txt", "a".repeat(100))
        assertFailsWith<IllegalArgumentException> { fm.readText("/root/big.txt", maxBytes = 10) }
        put("ok.txt", "héllo")
        assertEquals("héllo", fm.readText("/root/ok.txt"))
    }

    @Test
    fun writeTextReplacesContentAndLeavesNoTempFile() {
        put("a.txt", "old")
        fm.writeText("/root/a.txt", "new")
        assertEquals("new", File(home, "a.txt").readText())
        fm.writeText("/root/sub/dir/b.txt", "made")
        assertEquals("made", File(home, "sub/dir/b.txt").readText())
        assertEquals(setOf("a.txt", "sub"), home.list()!!.toSet())
    }
}

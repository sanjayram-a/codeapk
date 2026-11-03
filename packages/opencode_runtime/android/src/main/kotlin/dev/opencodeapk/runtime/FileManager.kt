package dev.opencodeapk.runtime

import java.io.File
import java.io.IOException
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.BasicFileAttributes
import java.util.UUID

data class FileEntry(val name: String, val path: String, val isDir: Boolean, val size: Long, val modifiedMs: Long)

/**
 * File operations on the user's home folder (guest `/root`), used by the Files tab.
 *
 * Everything is addressed with guest paths (`/root/projects/a.py`). Each path is resolved against [home] and
 * must stay inside it: `..` segments, other roots and symlinks that lead outside all throw [SecurityException].
 * Works directly on the app's storage, so it needs neither proot nor a running server.
 */
class FileManager(home: File) {
    private val home: File = real(home)
    private val rootPath: Path = this.home.toPath()

    fun list(path: String): List<FileEntry> {
        val dir = resolve(path)
        require(dir.isDirectory) { "not a folder: $path" }
        val base = guestPath(dir)
        val entries = (dir.listFiles() ?: emptyArray()).mapNotNull { child ->
            val inside = runCatching { real(child).toPath().startsWith(rootPath) }.getOrDefault(false)
            val isLink = Files.isSymbolicLink(child.toPath())
            val usable = inside || !isLink
            FileEntry(
                name = child.name,
                path = if (base == ROOT) "$ROOT/${child.name}" else "$base/${child.name}",
                isDir = usable && child.isDirectory,
                size = if (usable && child.isFile) child.length() else 0,
                modifiedMs = child.lastModified(),
            )
        }
        return entries.sortedWith(compareByDescending<FileEntry> { it.isDir }.thenBy { it.name.lowercase() })
    }

    fun mkdir(path: String) {
        val dir = resolve(path, mustExist = false)
        require(!dir.exists()) { "already exists: $path" }
        if (!dir.mkdirs()) throw IOException("cannot create $path")
    }

    fun createFile(path: String) {
        val f = resolve(path, mustExist = false)
        require(!f.exists()) { "already exists: $path" }
        f.parentFile?.mkdirs()
        if (!f.createNewFile()) throw IOException("cannot create $path")
    }

    fun rename(path: String, newName: String) {
        require(newName.isNotBlank() && newName != "." && newName != ".." && '/' !in newName && '\u0000' !in newName) {
            "invalid name: $newName"
        }
        val src = resolve(path, followLast = false)
        if (src == home) throw SecurityException("cannot rename the home folder")
        val dst = File(src.parentFile, newName)
        require(!dst.exists()) { "already exists: $newName" }
        if (!src.renameTo(dst)) throw IOException("cannot rename $path")
    }

    fun delete(path: String) {
        val target = resolve(path, followLast = false)
        if (target == home) throw SecurityException("cannot delete the home folder")
        deleteTree(target.toPath())
    }

    fun copy(src: String, dstDir: String) {
        val from = resolve(src, followLast = false)
        val to = destination(from, dstDir)
        copyTree(from.toPath(), to.toPath())
    }

    fun move(src: String, dstDir: String) {
        val from = resolve(src, followLast = false)
        if (from == home) throw SecurityException("cannot move the home folder")
        val to = destination(from, dstDir)
        if (!from.renameTo(to)) {
            copyTree(from.toPath(), to.toPath())
            deleteTree(from.toPath())
        }
    }

    /** The host file behind guest [path], checked to be a regular file inside the sandbox (for saving it elsewhere). */
    fun regularFile(path: String): File {
        val f = resolve(path)
        require(f.isFile) { "not a file: $path" }
        return f
    }

    fun readText(path: String, maxBytes: Long = 1_048_576): String {
        val f = resolve(path)
        require(f.isFile) { "not a file: $path" }
        require(f.length() <= maxBytes) { "file too large: ${f.length()} bytes" }
        val bytes = f.readBytes()
        require(bytes.take(8192).none { it == 0.toByte() }) { "binary file" }
        return String(bytes, Charsets.UTF_8)
    }

    fun writeText(path: String, text: String) {
        val f = resolve(path, mustExist = false)
        require(!f.isDirectory) { "is a folder: $path" }
        val parent = f.parentFile!!
        parent.mkdirs()
        val tmp = File(parent, ".${f.name}.tmp-${UUID.randomUUID()}")
        try {
            tmp.writeText(text, Charsets.UTF_8)
            Files.move(tmp.toPath(), f.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally {
            tmp.delete()
        }
    }

    // ---- internals ----

    /** Target path for copying/moving [from] into the folder [dstDir]; rejects collisions and self-nesting. */
    private fun destination(from: File, dstDir: String): File {
        val dir = resolve(dstDir)
        require(dir.isDirectory) { "not a folder: $dstDir" }
        val fromCanon = real(from).toPath()
        val dirCanon = real(dir).toPath()
        require(!dirCanon.startsWith(fromCanon)) { "cannot put a folder inside itself" }
        val to = File(dir, from.name)
        require(!to.exists()) { "already exists: ${from.name}" }
        return to
    }

    /**
     * Guest path -> host file, checked to be inside [home]. With [followLast] the final component is resolved
     * through symlinks too (reads and writes); without it only its parent must be inside, so a link can be
     * renamed or deleted as itself.
     */
    private fun resolve(guest: String, mustExist: Boolean = true, followLast: Boolean = true): File {
        val rel = relative(guest)
        val file = if (rel.isEmpty()) home else File(home, rel)
        val checked = if (followLast) file else (file.parentFile?.takeIf { file != home } ?: file)
        val canonical = try {
            real(checked)
        } catch (e: IOException) {
            throw SecurityException("cannot resolve $guest")
        }
        if (!canonical.toPath().startsWith(rootPath)) throw SecurityException("outside the sandbox: $guest")
        if (mustExist && !Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)) {
            throw IllegalArgumentException("not found: $guest")
        }
        return file
    }

    private fun relative(guest: String): String {
        val p = guest.trim()
        if (p.isEmpty()) return ""
        if (p != ROOT && !p.startsWith("$ROOT/")) throw SecurityException("outside the sandbox: $guest")
        val parts = p.removePrefix(ROOT).split('/').filter { it.isNotEmpty() && it != "." }
        if (parts.any { it == ".." }) throw SecurityException("outside the sandbox: $guest")
        return parts.joinToString("/")
    }

    private fun guestPath(f: File): String {
        val rel = rootPath.relativize(real(f).toPath()).toString().replace(File.separatorChar, '/')
        return if (rel.isEmpty()) ROOT else "$ROOT/$rel"
    }

    private fun deleteTree(path: Path) {
        Files.walkFileTree(path, object : SimpleFileVisitor<Path>() {
            override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                Files.delete(file); return FileVisitResult.CONTINUE
            }

            override fun postVisitDirectory(dir: Path, exc: IOException?): FileVisitResult {
                Files.delete(dir); return FileVisitResult.CONTINUE
            }
        })
    }

    private fun copyTree(from: Path, to: Path) {
        Files.walkFileTree(from, object : SimpleFileVisitor<Path>() {
            override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult {
                Files.createDirectories(to.resolve(from.relativize(dir).toString())); return FileVisitResult.CONTINUE
            }

            override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                Files.copy(file, to.resolve(from.relativize(file).toString()), LinkOption.NOFOLLOW_LINKS)
                return FileVisitResult.CONTINUE
            }
        })
    }

    private companion object {
        const val ROOT = "/root"

        /**
         * The file with every symlink resolved. `File.canonicalFile` does not follow symlinks on Windows, so use
         * `toRealPath`; for a path that does not exist yet, resolve its nearest existing ancestor and append the rest.
         */
        fun real(f: File): File {
            var existing: File? = f.absoluteFile
            val tail = ArrayDeque<String>()
            while (existing != null && !Files.exists(existing.toPath(), LinkOption.NOFOLLOW_LINKS)) {
                tail.addFirst(existing.name)
                existing = existing.parentFile
            }
            var resolved = (existing ?: f.absoluteFile).toPath().toRealPath()
            for (name in tail) resolved = resolved.resolve(name)
            return resolved.normalize().toFile()
        }
    }
}

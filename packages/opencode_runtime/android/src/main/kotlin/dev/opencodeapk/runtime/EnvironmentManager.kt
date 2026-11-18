package dev.opencodeapk.runtime

import java.io.File
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes

data class EnvironmentInfo(
    val rootfsBytes: Long,
    val homeBytes: Long,
    val rootfsVersion: String?,
    /** Packages the user added with apk, recorded one per line in `/root/.apk-extra`. */
    val extraPackages: List<String>,
)

enum class CacheKind(val dirs: List<String>) {
    /** npm's download cache and Node's compile cache. */
    NPM(listOf(".npm", ".cache/node-compile")),

    /** pip's and uv's download caches. */
    PYTHON(listOf(".cache/pip", ".cache/uv")),
}

data class ProjectSize(val name: String, val path: String, val bytes: Long)

data class StorageInfo(val npmBytes: Long, val pythonBytes: Long, val projects: List<ProjectSize>)

/** Backs the Environment page: disk usage and "reset environment" (which never touches `/root`). */
class EnvironmentManager(
    private val paths: Paths,
    private val ops: FileOps,
    private val isBusy: () -> Boolean,
) {
    fun info(): EnvironmentInfo = EnvironmentInfo(
        rootfsBytes = sizeOf(paths.rootfs),
        homeBytes = sizeOf(paths.home),
        rootfsVersion = RootfsInstaller(paths, ops).installedVersion(),
        extraPackages = File(paths.home, ".apk-extra").takeIf { it.isFile }
            ?.readLines()?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList(),
    )

    /** Cache sizes and the size of each folder in `/root/projects`, largest first. Can take a while on big projects. */
    fun storageInfo(): StorageInfo = StorageInfo(
        npmBytes = cacheBytes(CacheKind.NPM),
        pythonBytes = cacheBytes(CacheKind.PYTHON),
        projects = (File(paths.home, "projects").listFiles() ?: emptyArray())
            .filter { it.isDirectory && !Files.isSymbolicLink(it.toPath()) }
            .map { ProjectSize(it.name, "/root/projects/${it.name}", sizeOf(it)) }
            .sortedWith(compareByDescending<ProjectSize> { it.bytes }.thenBy { it.name.lowercase() }),
    )

    /** Deletes the cache folders of [kind] (downloaded packages only, never project files). Returns the bytes freed. */
    fun clearCache(kind: CacheKind): Long {
        val before = cacheBytes(kind)
        kind.dirs.map { File(paths.home, it) }.filter { it.exists() }.forEach { ops.deleteRecursively(it) }
        return before
    }

    private fun cacheBytes(kind: CacheKind): Long = kind.dirs.sumOf { sizeOf(File(paths.home, it)) }

    /** Removes the rootfs (and leftovers of an interrupted install). The next install extracts a fresh one. */
    fun reset() {
        check(!isBusy()) { "busy" }
        listOf(paths.rootfs, paths.rootfsNew, paths.rootfsOld, paths.tmp, paths.prootTmp).forEach {
            if (it.exists()) ops.deleteRecursively(it)
        }
    }

    private fun sizeOf(dir: File): Long {
        if (!dir.exists()) return 0
        var total = 0L
        // Does not follow symlinks: the rootfs is full of absolute links that would point outside it.
        Files.walkFileTree(dir.toPath(), object : SimpleFileVisitor<java.nio.file.Path>() {
            override fun visitFile(file: java.nio.file.Path, attrs: BasicFileAttributes): FileVisitResult {
                if (attrs.isRegularFile) total += attrs.size()
                return FileVisitResult.CONTINUE
            }

            override fun visitFileFailed(file: java.nio.file.Path, exc: java.io.IOException) = FileVisitResult.CONTINUE
        })
        return total
    }
}

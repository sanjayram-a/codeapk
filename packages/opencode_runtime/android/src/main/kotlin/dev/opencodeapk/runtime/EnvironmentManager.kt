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

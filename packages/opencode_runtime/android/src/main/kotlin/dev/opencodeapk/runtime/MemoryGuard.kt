package dev.opencodeapk.runtime

/**
 * Reacts to `onTrimMemory`. Policy from the spec: shed idle terminal sessions first, the server last.
 *
 * Levels (ComponentCallbacks2): 5 RUNNING_MODERATE, 10 RUNNING_LOW, 15 RUNNING_CRITICAL, 20 UI_HIDDEN,
 * 40 BACKGROUND, 60 MODERATE, 80 COMPLETE. UI_HIDDEN only means "the app went to the background", so it is
 * ignored; reacting to it would stop the server every time the user leaves the app.
 */
object MemoryGuard {
    fun onTrim(level: Int, terminals: TerminalManager, controller: ServerController, clients: Int) {
        val pressure = level == 10 || level == 15 || level >= 40
        if (!pressure) return
        terminals.detachedIds().forEach { terminals.close(it) }
        val critical = level == 15 || level >= 60
        if (critical && clients == 0 && controller.snapshot.state == ServerState.RUNNING) {
            controller.stop("memory")
        }
    }
}

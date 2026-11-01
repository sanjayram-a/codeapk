# opencode-local

An experimental Android app that runs the [OpenCode](https://github.com/sst/opencode)
server inside an Alpine Linux userland using proot, then opens the OpenCode web UI
in a WebView.

> **Status:** Pre-release. The native app shell is built and unit-tested (home with
> session history and search, file manager, terminal, settings, foreground service with
> crash restart and idle stop), but it has **not yet been run on a real device**. Release
> packaging (Play asset pack, 16 KB page alignment), LAN mode and secure key storage are
> still to do. See `docs/device-test-checklist.md`.
> This is an unofficial project and is not affiliated with the OpenCode project.

## Layout

- `app/` — Flutter Android app: onboarding, Home (history + search), Files, Terminal, Settings;
  chat is the OpenCode web UI opened on a chosen session.
- `packages/opencode_runtime/` — Kotlin runtime: rootfs installer, proot launcher,
  server supervisor/controller, foreground service, terminals, sandboxed file manager.
- `native/proot/` — fetches and patches the Termux proot binaries.
- `rootfs/` — builds the Alpine + OpenCode rootfs.
- `docs/` — design notes and spike results.

## Build

The app uses Flutter and the Android Gradle plugin. The rootfs asset is not
committed; build it with `rootfs/build.sh`, pack it with `rootfs/pack.sh`, and
copy it with `tool/copy_rootfs.sh <abi>`.

## License

Original project code is licensed under **GPL-3.0-or-later**. Third-party
components remain under their own licenses; see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and
[`SOURCE_OFFER.md`](SOURCE_OFFER.md). Full license texts are in
[`LICENSES/`](LICENSES/).

“OpenCode” is a trademark of its respective owner. This project does not grant
any trademark rights.

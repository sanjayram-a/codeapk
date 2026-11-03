#!/usr/bin/env bash
# Copy built rootfs archives into the app's assets (Phase 0/1; Phase 2 moves them to a Play asset pack).
#   bash tool/copy_rootfs.sh               -> both ABIs
#   bash tool/copy_rootfs.sh arm64-v8a     -> device build only
#   bash tool/copy_rootfs.sh x86_64        -> emulator only
#
# arm64-v8a goes to the :rootfs_pack asset pack (install-time pack in an AAB; merged into app assets for APK builds).
# rootfs.version stays in app src/main so the base module always knows which rootfs it expects.
# x86_64 goes to src/debug: it is emulator-only (4 KB-aligned proot, see native/proot/SOURCES.md)
# and must never ship in a Play release.
set -euo pipefail
cd "$(dirname "$0")/.."
. rootfs/versions.env
MAIN=app/android/app/src/main/assets/rootfs
PACK=app/android/rootfs_pack/src/main/assets/rootfs
DEBUG=app/android/app/src/debug/assets/rootfs
rm -rf "$MAIN" "$PACK" "$DEBUG"; mkdir -p "$MAIN" "$PACK"
[ "$#" -eq 0 ] && set -- arm64-v8a x86_64
for a in "$@"; do
  case "$a" in
    arm64-v8a) cp "out/rootfs-$a.tar.zst" "$PACK/" ;;
    x86_64)    mkdir -p "$DEBUG"; cp "out/rootfs-$a.tar.zst" "$DEBUG/" ;;
    *) echo "unknown abi: $a (use arm64-v8a or x86_64)" >&2; exit 2 ;;
  esac
done
printf '%s\n' "$ROOTFS_VERSION" > "$MAIN/rootfs.version"
ls -l "$MAIN" "$PACK" "$DEBUG" 2>/dev/null || true

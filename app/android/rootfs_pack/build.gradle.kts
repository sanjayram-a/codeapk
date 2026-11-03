plugins {
    id("com.android.asset-pack")
}

// Install-time asset pack: holds rootfs/rootfs-arm64-v8a.tar.zst (see tool/copy_rootfs.sh).
// Installed with the app and read through the normal AssetManager, so the runtime code is unchanged.
assetPack {
    packName.set("rootfs_pack")
    dynamicDelivery {
        deliveryType.set("install-time")
    }
}

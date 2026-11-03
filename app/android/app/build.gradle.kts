import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload-key settings live in app/android/key.properties (git-ignored). Absent file = debug-signed local builds.
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// Play's 200 MB base-module limit cannot hold the ~112 MB rootfs plus the app, so for bundles the arm64 rootfs
// ships in the install-time asset pack :rootfs_pack. APK builds (sideload/testing) cannot use asset packs, so
// there the same folder is added to the app's own assets instead.
val isBundleBuild = gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }

android {
    namespace = "com.opencode.dotwellabs"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.opencode.dotwellabs"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Release ships arm64-v8a only: the x86_64 proot is 4 KB-aligned (fails Play's 16 KB rule) and is emulator-only.
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    // proot ships as lib*.so files and must be extracted to nativeLibraryDir to be exec'd.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            // Prebuilt, already-stripped, patchelf-edited binaries: do not let AGP strip them again.
            keepDebugSymbols += listOf("**/libproot.so", "**/libproot-loader.so", "**/libtalloc.so", "**/libandroid-shmem.so")
        }
    }

    // Keep the rootfs uncompressed in the APK so it can be streamed through zstd directly.
    androidResources { noCompress += "zst" }

    signingConfigs {
        create("release") {
            if (keystoreProps.isNotEmpty()) {
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
            }
        }
    }

    if (isBundleBuild) {
        assetPacks += listOf(":rootfs_pack")
    } else {
        sourceSets.getByName("main").assets.srcDir("../rootfs_pack/src/main/assets")
    }

    buildTypes {
        debug {
            // Emulator support: x86_64 libs here, and its rootfs lives in src/debug/assets (see tool/copy_rootfs.sh).
            ndk { abiFilters += listOf("x86_64") }
        }
        release {
            // Upload key when key.properties exists; otherwise debug keys so `flutter run --release` still works.
            signingConfig = signingConfigs.getByName(if (keystoreProps.isNotEmpty()) "release" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// abiFilters does not apply to bundles, so strip the non-arm64 libraries from release explicitly. x86_64 is the
// 4 KB-aligned emulator-only proot (fails Play's 16 KB rule); 32-bit ABIs have no proot/rootfs at all.
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(listOf("lib/x86_64/**", "lib/x86/**", "lib/armeabi-v7a/**"))
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

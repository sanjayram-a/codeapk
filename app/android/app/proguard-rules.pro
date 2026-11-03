# zstd-jni's native library looks up Java fields/methods by name via JNI (srcPos, dstPos, ...).
# R8 renaming or stripping them aborts the process with NoSuchFieldError.
-keep class com.github.luben.zstd.** { *; }
-keepclassmembers class com.github.luben.zstd.** { *; }

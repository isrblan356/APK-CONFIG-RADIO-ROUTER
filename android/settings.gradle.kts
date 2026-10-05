pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

// flutter_inappwebview_android 1.1.3 llama
// getDefaultProguardFile('proguard-android.txt'), que el AGP 9 rechaza
// (contiene -dontoptimize y bloquea las optimizaciones de R8).
// Se parchea su build.gradle justo antes de evaluarlo (idempotente):
// la variante -optimize.txt hace lo mismo sin esa restricción.
gradle.beforeProject {
    if (name == "flutter_inappwebview_android") {
        val f = buildFile
        if (f.exists()) {
            val txt = f.readText()
            if (txt.contains("proguard-android.txt")) {
                f.writeText(
                    txt.replace("proguard-android.txt", "proguard-android-optimize.txt")
                )
            }
        }
    }
}

include(":app")

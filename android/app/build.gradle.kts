plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.radio.grradio"
    compileSdk = 36  // Updated to 36 for plugin compatibility
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.radio.grradio"
        minSdk = flutter.minSdkVersion  // Set explicitly for better compatibility
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Disable R8/ProGuard completely for release builds
    buildTypes.forEach { buildType ->
        buildType.isMinifyEnabled = false
        buildType.isShrinkResources = false
    }
}

flutter {
    source = "../.."
}

// Fix APK output location for Flutter - must be outside android block
afterEvaluate {
    tasks.named("assembleRelease").configure {
        doLast {
            val apkDir = file("${project.rootDir}/../build/app/outputs/flutter-apk")
            apkDir.mkdirs()

            val releaseApk = file("${buildDir}/outputs/apk/release/app-release.apk")
            if (releaseApk.exists()) {
                releaseApk.copyTo(File(apkDir, "app-release.apk"), overwrite = true)
                println("✓ APK copied to: ${apkDir.absolutePath}/app-release.apk")
            }
        }
    }
}
afterEvaluate {
    tasks.named("assembleDebug").configure {
        doLast {
            val apkDir = file("${project.rootDir}/../build/app/outputs/flutter-apk")
            apkDir.mkdirs()

            val releaseApk = file("${buildDir}/outputs/apk/debug/app-debug.apk")
            if (releaseApk.exists()) {
                releaseApk.copyTo(File(apkDir, "app-debug.apk"), overwrite = true)
                println("✓ APK copied to: ${apkDir.absolutePath}/app-debug.apk")
            }
        }
    }
}
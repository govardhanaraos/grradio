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
        targetSdk = 33
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // 💡 ADD: For debug builds
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module"
            )
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
dependencies {
    implementation("androidx.multidex:multidex:2.0.1") // For multidex support
    implementation("com.google.android.gms:play-services-ads:22.6.0") // Latest version

    // Optional: For mediation adapters if you plan to use other ad networks
    // implementation("com.google.ads.mediation:facebook:6.16.0.0")
    // implementation("com.google.ads.mediation:applovin:12.1.0.0")
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
// Fix: Automatically inject namespace for older library plugins (e.g., google_mobile_ads < 5.0.0)
// This should be placed in your root `android/build.gradle.kts` file.
subprojects {
    afterEvaluate {
        // Only apply this fix to projects that are Android Libraries (plugins)
        if (project.plugins.hasPlugin("com.android.library")) {
            android {
                // If a library plugin is missing the 'namespace', set it using the project's group ID
                if (namespace == null) {
                    namespace = project.group.toString()
                }
            }
        }
    }
}
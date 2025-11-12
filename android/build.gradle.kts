// android/build.gradle.kts (The root one)

import org.gradle.api.tasks.Delete

// --- BLOCK 1: Repositories for ALL projects ---
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// --- BLOCK 2: Buildscript Configuration ---
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.7.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.0")
    }
}

// --- BLOCK 3: Subprojects Configuration ---
subprojects {


    // Apply Java Toolchain to force Java 17 everywhere
    afterEvaluate {
        extensions.findByType<JavaPluginExtension>()?.apply {
            toolchain {
                languageVersion.set(JavaLanguageVersion.of(17))
            }
        }
    }

    // Force Java 17 for all Java compilation tasks
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }

    // Force Java 17 for all Kotlin compilation tasks
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }
}

// --- BLOCK 4: Clean Task ---
tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
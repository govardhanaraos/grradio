// android/build.gradle.kts (The root one)

import org.gradle.api.tasks.Delete
// ... other imports ...

// --- BLOCK 1: Repositories for ALL projects (correctly placed) ---
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
// -----------------------------------------------------------------

// --- BLOCK 2: Buildscript Configuration (correctly placed) ---
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Ensure these versions match your latest uploaded settings.gradle.kts (8.7.0 and 2.1.0)
        classpath("com.android.tools.build:gradle:8.3.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22")
    }
}
// -----------------------------------------------------------------


subprojects {

    // 1. Force Java 17 for all projects (Java tasks)
    tasks.withType<JavaCompile>().configureEach {
        // CRITICAL: Ensure JavaCompile uses Java 17 (version 55)
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }

    // 2. Force Java 17 for all projects (Kotlin tasks)
    // CRITICAL: Ensure KotlinCompile also uses Java 17 for consistency
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }


}



// --- BLOCK 4: Clean Task (can be placed at the end) ---
tasks.register<Delete>("clean") {
    // ... clean task logic ...
}
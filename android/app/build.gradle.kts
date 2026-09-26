plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mbn.movie"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mbn.movie"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 7.0+ keeps the APK installable on older 32-bit and 64-bit
        // phones. Predictive-back remains enabled only where Android supports it.
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "MBNMovie"
    }

    val releaseStore = System.getenv("MBN_KEYSTORE_PATH")
    signingConfigs {
        if (!releaseStore.isNullOrBlank()) {
            create("mbnmovieRelease") {
                storeFile = file(releaseStore)
                storePassword = System.getenv("MBN_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("MBN_KEY_ALIAS")
                keyPassword = System.getenv("MBN_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            // Keep local/debug installs separate from the signed public app.
            // Otherwise Flutter may uninstall the release build after an
            // INSTALL_FAILED_UPDATE_INCOMPATIBLE error and erase user data.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            manifestPlaceholders["appLabel"] = "MBNMovie Debug"
        }
        release {
            signingConfig = if (!releaseStore.isNullOrBlank()) signingConfigs.getByName("mbnmovieRelease") else null
        }
    }
}

// Never silently publish another APK with an ephemeral debug identity.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } && System.getenv("MBN_KEYSTORE_PATH").isNullOrBlank()) {
        throw GradleException("Release signing is required. Use Build-MBNMovie-Release.ps1 or configure MBN_KEYSTORE_* variables.")
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

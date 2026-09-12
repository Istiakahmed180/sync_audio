import java.util.Properties

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

val signingValue: (String) -> String? = { key ->
    signingProperties.getProperty(key)?.takeIf { it.isNotBlank() }
        ?: System.getenv("ANDROID_${key.uppercase()}")?.takeIf { it.isNotBlank() }
}
val signingStoreFile = signingValue("storeFile")
val hasReleaseSigning = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
    .all { signingValue(it) != null }
val isReleaseTask = gradle.startParameter.taskNames.any {
    it.lowercase().contains("release")
}
if (isReleaseTask && !hasReleaseSigning) {
    error("Release signing is not configured. Add android/key.properties or ANDROID_* signing variables.")
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.syncmesh.audio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.syncmesh.audio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = signingValue("keyAlias")
            keyPassword = signingValue("keyPassword")
            storeFile = signingStoreFile?.let(::file)
            storePassword = signingValue("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
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

// `integration_test` is a dev dependency, but running integration tests
// rewrites the generated Android plugin registrant to include it. Flutter only
// filters dev dependencies when it regenerates the file, so a later release
// build can reuse the stale registrant and fail to compile (the debug-only
// plugin is not on the release classpath). Strip it before release compilation.
tasks.configureEach {
    if (name.startsWith("compile") && name.contains("Release") &&
        name.endsWith("JavaWithJavac")
    ) {
        doFirst {
            val registrant = file(
                "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
            )
            if (registrant.exists()) {
                val lines = registrant.readLines()
                if (lines.any { it.contains("IntegrationTestPlugin") }) {
                    registrant.writeText(
                        lines.filterNot {
                            it.contains("integration_test") ||
                                it.contains("IntegrationTestPlugin")
                        }.joinToString("\n")
                    )
                }
            }
        }
    }
}

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

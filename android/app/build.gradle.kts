import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// The Firebase plugin is activated only when the real Firebase config is present.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing is supplied securely by GitHub Actions secrets.
// Local/debug builds continue to use the standard Android debug configuration.
val releaseStoreFile = System.getenv("PCWORK_KEYSTORE_FILE")
val releaseStorePassword = System.getenv("PCWORK_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("PCWORK_KEY_ALIAS")
val releaseKeyPassword = System.getenv("PCWORK_KEY_PASSWORD")
val hasReleaseSigning = listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all { !it.isNullOrBlank() }

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

android {
    namespace = "com.pcworkbg.pcwork_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.pcworkbg.pcwork_mobile"
        minSdk = 23
        // POST_NOTIFICATIONS requires Android 13+ runtime permission handling.
        targetSdk = maxOf(flutter.targetSdkVersion, 33)
        // Flutter derives these values from pubspec.yaml (version: x.y.z+build).
        // Keep Android's manifest metadata aligned with the single project version source.
        val resolvedVersionCode = flutter.versionCode
        val resolvedVersionName = flutter.versionName
        require(resolvedVersionCode > 0) { "Android versionCode must be a positive integer." }
        require(resolvedVersionName.matches(Regex("^[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$"))) {
            "Android versionName must be a valid semantic app version, got: $resolvedVersionName"
        }
        versionCode = resolvedVersionCode
        versionName = resolvedVersionName
        multiDexEnabled = true
    }
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }
    buildTypes {
        getByName("release") {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

tasks.configureEach {
    if (name.contains("Release", ignoreCase = true) && name.startsWith("package", ignoreCase = true)) {
        doFirst {
            if (!hasReleaseSigning) {
                throw GradleException("Release signing is not configured. Add the four PCWORK_* GitHub Actions secrets configured as PCWORK_KEYSTORE_FILE, PCWORK_KEYSTORE_PASSWORD, PCWORK_KEY_ALIAS and PCWORK_KEY_PASSWORD.")
            }
        }
    }
}

flutter { source = "../.." }

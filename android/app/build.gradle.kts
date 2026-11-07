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

android {
    namespace = "com.pcworkbg.pcwork_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }

    defaultConfig {
        applicationId = "com.pcworkbg.pcwork_mobile"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
                throw GradleException("Release signing is not configured. Add the four PCWORK_* GitHub Actions secrets described in SIGNING_SETUP_BG.md.")
            }
        }
    }
}

flutter { source = "../.." }

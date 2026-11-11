plugins {
    id("com.android.application")
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
        // POST_NOTIFICATIONS requires Android 13+ runtime permission handling.
        targetSdk = maxOf(flutter.targetSdkVersion, 33)
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
                throw GradleException("Release signing is not configured. Add the four PCWORK_* GitHub Actions secrets configured as PCWORK_KEYSTORE_FILE, PCWORK_KEYSTORE_PASSWORD, PCWORK_KEY_ALIAS and PCWORK_KEY_PASSWORD.")
            }
        }
    }
}

flutter { source = "../.." }

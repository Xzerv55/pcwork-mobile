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
        // Read the app version directly from the repository's pubspec.yaml.
        // Flutter's Gradle extension may fall back to 1.0/1 when its version
        // properties are not explicitly populated by the invoking workflow.
        // Parsing the single source of truth here keeps every Android variant aligned.
        val pubspecFile = rootProject.file("../pubspec.yaml")
        require(pubspecFile.isFile) {
            "pubspec.yaml was not found at ${pubspecFile.absolutePath}."
        }
        val pubspecVersionLine = pubspecFile.readLines().firstOrNull { it.startsWith("version:") }
            ?: error("pubspec.yaml does not declare an app version.")
        val versionMatch = Regex("""^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$""")
            .matchEntire(pubspecVersionLine)
            ?: error("pubspec.yaml version must use MAJOR.MINOR.PATCH+BUILD format; got: $pubspecVersionLine")
        val resolvedVersionName = versionMatch.groupValues[1]
        val resolvedVersionCode = versionMatch.groupValues[2].toIntOrNull()
            ?: error("pubspec.yaml build number is outside Android's supported integer range.")
        require(resolvedVersionCode > 0) { "Android versionCode must be a positive integer." }
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

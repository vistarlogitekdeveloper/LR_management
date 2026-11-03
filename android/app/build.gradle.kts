import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (see android/RELEASE_SIGNING.md). android/key.properties and
// the keystore it points at stay on the build machine — both are git-ignored
// (android/.gitignore). Without them the release build falls back to the debug
// key, as before, so a fresh checkout still builds.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseKey = keystorePropertiesFile.exists()
logger.lifecycle(
    if (hasReleaseKey) ">> Release APK signed with the release key (android/key.properties)"
    else ">> No android/key.properties: release APK signed with the DEBUG key (test builds only)"
)

android {
    namespace = "com.example.lr_management"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Kept as is: changing the application id would make Android treat the
        // app as a different one, installed side by side with the old.
        applicationId = "com.example.lr_management"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml `version: <name>+<code>`. The code MUST go up for
        // every APK handed out, or Android refuses it as an update.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // No key on this machine: debug-signed, as before. Fine for a
                // test build; never hand one out once users have a release-signed
                // APK (Android will not update one with the other).
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // El plugin de Flutter debe aplicarse después de Android y Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase (lee google-services.json)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.favric.proxi_app"
    compileSdk = 36
    // Firebase/geolocator requieren NDK 27 (retrocompatible).
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.favric.proxi_app"
        // UWB requiere Android 12 (API 31) o superior.
        minSdk = 31
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Jetpack UWB (device-to-device ranging). Versión estable.
    implementation("androidx.core.uwb:uwb:1.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}

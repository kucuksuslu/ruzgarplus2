plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services") // Firebase servisini aktif et
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ruzgarplus"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.ruzgarplus"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
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

repositories {
    google()
    mavenCentral()
   

}

dependencies {
    implementation("com.google.firebase:firebase-firestore:24.10.3")
    // Agora SDK (en güncel stabil sürüm için Agora resmi dokümantasyonunu kontrol edin)
    implementation("com.google.firebase:firebase-messaging:23.4.1")
    implementation("io.agora.rtc:full-sdk:4.1.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fbs"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.fbs"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // 剔除 AAR 中预编译的非 arm64 原生库
    packagingOptions {
        exclude("lib/x86_64/**")
        exclude("lib/armeabi-v7a/**")
        exclude("lib/x86/**")
    }
}

dependencies {
    // Shizuku SDK
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    
    // PaddleOCR-Lite
    implementation(files("libs/ppocr-sdk-release.aar"))
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.21.1")
    implementation("org.opencv:opencv:4.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

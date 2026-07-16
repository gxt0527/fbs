plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.hyperislandtest"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.example.hyperislandtest"
        minSdk = 27
        targetSdk = 37
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt")
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }

    buildFeatures {
        compose = false
    }
}

dependencies {
    // AndroidX Core
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")
    implementation("androidx.recyclerview:recyclerview:1.4.0")

    // HyperIsland-ToolKit — HyperOS Dynamic Island / Focus Notification
    implementation("io.github.d4viddf:hyperisland_kit:0.4.3")
}

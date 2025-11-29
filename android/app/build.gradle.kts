buildscript {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://chaquo.com/maven") }
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.9.1")
        classpath("com.chaquo.python:gradle:15.0.1")
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.adobe"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.adobe"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        ndk {
            // On Apple silicon, you can omit x86_64.
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

chaquopy {
    defaultConfig {
        version = "3.8"
        val isWindows = System.getProperty("os.name").lowercase().contains("windows")
        val pythonFile = if (isWindows) file("../../python_env/Scripts/python.exe") else file("../../python_env/bin/python")
        buildPython(pythonFile.absolutePath)
        pip {
            install("pillow")
            install("numpy")
            install("opencv-contrib-python-headless")
            install("instaloader")
            install("scikit-learn")
            install("joblib")
        }
    }
}

flutter {
    source = "../.."
}

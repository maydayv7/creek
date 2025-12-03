# adobe

A Flutter project with AI-based image analysis

## Prerequisites

- `git` & `git-lfs`
- Flutter SDK **>=3.7**
- Python **3.8**
- Gradle **8.9.1**
- Java/JDK **17** & Kotlin
- Android SDK & NDK
  - Platform Level **>=34**
  - Build Tools **>=34.0.0**
  - NDK Version **27.0.12077973**
  - CMake **3.22.1**

Ensure that all these programs with the correct versions are installed on your system before using this repository

## Setup

### 1. Clone Repository

Clone using `git lfs clone` to ensure all models are correctly pulled

### 2. Setup Python

The Android app compiles Python code using [Chaquopy](https://chaquo.com/chaquopy/), which requires the following setup, mandatorily using Python Version 3.8:

#### A) Install Python 3.8

Download from [python.org](https://www.python.org/downloads/release/python-3810/)

#### B) Set up Virtual Environment

```bash
python -m venv python_env
```

### 3. Build the APK

```bash
flutter clean
flutter pub get
flutter build apk
```

If you have `adb` properly installed, you can use `flutter run`

## Backend

Read [flask/README.md](flask/README.md) to run the server

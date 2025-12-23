# Binary

The pre-built APK file can be downloaded from [here](https://github.com/maydayv7/creek/releases/latest/download/app-release.apk) to experience the app on your Android phone without any hassle (uses a pre-deployed [Modal.com](https://modal.com) backend).  
To build the app from source, read the rest of this document.

# Prerequisites

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

> [!NOTE]
> For [Nix](https://nixos.org/) users, a [Flake](./flake.nix) for the development shell is provided

# Setup

### 1. Download Models

Download all the models from [here](https://drive.google.com/drive/folders/1b2cEsZao5miX7WxYmp160XkKd_lfBmPN) and place them inside the [`assets`](./assets) directory

### 2. Setup Python

The Android app compiles Python code using [Chaquopy](https://chaquo.com/chaquopy/), which requires the following setup, mandatorily using Python Version 3.8:

#### A) Install Python 3.8

Download from [python.org](https://www.python.org/downloads/release/python-3810/)

#### B) Set up Virtual Environment

```bash
python -m venv python_env
```

### 3. Create .env

Create the `.env` file in the root directory containing the following:

```dotenv
URL_ASSET=<Background Removal Backend Endpoint>
URL_DESCRIBE=<Florence-v2 Description Backend Endpoint>
URL_GENERATE=<Stable Diffusion Image Generation Backend Endpoint>
URL_INPAINTING=<Stable Diffusion Inpainting Backend Endpoint>
URL_INPAINTING_API=<Fal.ai Inpainting Backend Endpoint>
URL_SKETCH_API=<Sketch to Image Backend Endpoint>
SHARED_SECRET_KEY=<Base64 Security Key>
```

### 4. Build the application APK

```bash
flutter clean
flutter pub get
flutter build apk
```

If you have `adb` properly installed, you can use `flutter run`

# Backend

Read [flask/README.md](flask/README.md) to run the server

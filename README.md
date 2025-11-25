# adobe

A Flutter project with Python image analysis using Chaquopy.

## Prerequisites

- Flutter SDK
- Python 3.11 (for build-time)
- Android SDK

## Setup

### 1. Install Python 3.11

**macOS:**

```bash
brew install python@3.11
```

**Linux:**

```bash
sudo apt-get install python3.11 python3.11-venv
```

**Windows:**
Download from [python.org](https://www.python.org/downloads/)

### 2. Set up Python Virtual Environment

Run the setup script to create a Python virtual environment in the repository:

```bash
./setup_python_env.sh
```

This creates a `python_env` directory with Python 3.11, which will be used by the build system. This ensures all developers use the same Python version.

### 3. Build the APK

```bash
flutter build apk --release
```

## Project Structure

- `android/app/src/main/python/` - Python code (image analysis)
- `python_env/` - Python virtual environment (created by setup script)
- `lib/` - Flutter/Dart code

## Notes

- The Python runtime version (embedded in the app) is **3.8** (configured in `android/app/build.gradle.kts`)
- The build-time Python version is **3.11** (from the virtual environment)
- The virtual environment is used only during build, not at runtime

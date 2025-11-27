# adobe

A Flutter project with AI-based image analysis

## Prerequisites

- Flutter SDK
- Python 3.8
- Kotlin + Gradle
- JDK
- Android SDK

## Setup

### 1. Setup Python

#### A) Install Python 3.8

**macOS:**

```bash
brew install python@3.8
```

**Linux:**

```bash
sudo apt-get install python3.8 python3.8-venv
```

**Windows:**
Download from [python.org](https://www.python.org/downloads/)

#### B) Set up Virtual Environment

```bash
python -m venv python_env
```

### 3. AI Models

Download the models from [here](https://mega.nz/folder/WghwgRYA#byC4igRSImx0LRd9KW40hw) and place them under `assets`

### 4. Build the APK

```bash
flutter clean
flutter build apk --release
```

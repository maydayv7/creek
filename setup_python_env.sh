#!/bin/bash

# Setup script for Python virtual environment
# This ensures all developers use the same Python version for builds

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/python_env"

echo "Setting up Python virtual environment for Chaquopy builds..."

# Check if Python 3.11 is available
if command -v python3.11 &> /dev/null; then
    PYTHON_CMD="python3.11"
elif command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
    if [ "$PYTHON_VERSION" = "3.11" ]; then
        PYTHON_CMD="python3"
    else
        echo "Error: Python 3.11 is required but not found."
        echo "Please install Python 3.11:"
        echo "  macOS: brew install python@3.11"
        echo "  Linux: sudo apt-get install python3.11 python3.11-venv"
        echo "  Or download from https://www.python.org/downloads/"
        exit 1
    fi
else
    echo "Error: Python 3.11 is required but not found."
    echo "Please install Python 3.11 first."
    exit 1
fi

echo "Using Python: $($PYTHON_CMD --version)"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment at $VENV_DIR..."
    $PYTHON_CMD -m venv "$VENV_DIR"
    echo "Virtual environment created successfully!"
else
    echo "Virtual environment already exists at $VENV_DIR"
fi

# Verify the venv
if [ -f "$VENV_DIR/bin/python" ]; then
    VENV_PYTHON_VERSION=$("$VENV_DIR/bin/python" --version)
    echo "Virtual environment Python version: $VENV_PYTHON_VERSION"
    echo ""
    echo "✓ Python virtual environment is ready!"
    echo "  Location: $VENV_DIR"
    echo ""
    echo "The build system will automatically use this Python environment."
else
    echo "Error: Failed to create virtual environment"
    exit 1
fi


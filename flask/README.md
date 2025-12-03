# AI Image Generator Backend

This project sets up a local Flask server that uses the Stable Diffusion v1.5 model to generate images from text prompts.
Prerequisites
Before you begin, ensure you have the following installed:
Python 3.10 or 3.11 (Recommended for compatibility)

### Prerequisites

- NVIDIA GPU (Recommended)  
  You need a GPU with at least 4GB VRAM  
  Ensure you have the latest NVIDIA drivers installed  
  Check CUDA availability: Open terminal and run `nvidia-smi`

## Installation & Setup

### A. Install Standard Packages

```
pip install flask flask-cors diffusers transformers accelerate safetensors
```

### B. Install PyTorch & xFormers (GPU Acceleration)

This step differs slightly depending on your OS and GPU

#### Windows (NVIDIA GPU)

To ensure you get the version compatible with your GPU, run:

```
pip install torch torchvision xformers --index-url https://download.pytorch.org/whl/cu118
```

If you have a very new GPU, you can try `cu121` instead of `cu118`

#### Mac (M1/M2/M3 Silicon)

Macs use "MPS" (Metal Performance Shaders) instead of CUDA

```
pip install torch torchvision torchaudio
```

### C. Models

Download the requisite models from [here](https://github.com/adobeinter/Adobe-Models/tree/main)

## Running the Server

```shell
python index.py
```

# Server Deployment

To deploy to [Modal](https://modal.com/) server, simply modify `modal_app.py` according to your requirements and run `modal deploy modal_app.py`

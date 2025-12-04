# Backend

> [!NOTE]
> Python 3.11 is the preferred version for running the backend

This project provides a unified AI backend for image generation, inpainting, background removal, and captioning. It supports two modes of operation:

## 1. Local Server (`index.py`)

Runs purely on your local machine

> [!IMPORTANT]
> Requires Cuda-enabled NVIDIA GPU

To run backend locally, run the following commands:

```shell
pip install -r requirements.txt
python ./index.py
```

## 2. Cloud Server (`modal_app.py`)

Deploys to [Modal.com](https://modal.com) for serverless GPU inference

To deploy, run the following commands:

```shell
pip install modal
modal setup
modal deploy modal_app.py
```

## Environment Variables

Ensure that a `.env` file is present in this directory containing the following contents:

```dotenv
FAL_KEY=<Fal.ai API Key>
SHARED_SECRET_KEY=<Base64 Security Key>
```

> [!NOTE]
> You must update the root `.env` file for the app to recognize the deployed backend

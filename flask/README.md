# Backend

This project provides a unified AI backend for image generation, inpainting, background removal, and captioning. It supports two modes of operation:

## 1. Local Server (`index.py`)

Runs on your local machine.

> [!IMPORTANT]
> Requires Cuda-enabled NVIDIA GPU

To run backend locally, run the following commands:

```shell
pip install -r requirements.txt
python ./index.py
```

## 2. Cloud Server (`modal_app.py`)

Deploys to [Modal.com](https://modal.com) for serverless GPU inference.

To deploy, run the following commands:

```shell
pip install modal
modal setup
modal deploy modal_app.py
```

# Setup

> [!NOTE]
> Python 3.11 is the preferred version for running the backend

## Models

Download all the models from [here](https://drive.google.com/drive/folders/143A296pgkTiUGqffE4xG8ADPPEGOY-W2) and place them inside this directory

## Environment Variables

Ensure that a [`.env`](./.env) file is present in this directory containing the following contents:

```dotenv
FAL_KEY=<Fal.ai API Key>
SHARED_SECRET_KEY=<Base64 Security Key>
```

> [!NOTE]
> You must update the root [`.env`](../.env) file for the app to recognize the deployed backend

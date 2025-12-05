"""
Sketch to Image
Original file: https://colab.research.google.com/drive/1rE5rC71QRvdyxlhnjZUZ320xOV0xrdgx
"""

## Stable Diffusion

!pip install diffusers==0.30.0 transformers accelerate safetensors xformers torch --upgrade

from diffusers import StableDiffusionPipeline
import torch
from PIL import Image

model_id = "runwayml/stable-diffusion-v1-5"

pipe = StableDiffusionPipeline.from_pretrained(
    model_id, torch_dtype=torch.float16, use_safetensors=True
).to("cuda")

pipe.enable_xformers_memory_efficient_attention()
pipe.enable_attention_slicing()

import time
from PIL import Image
import subprocess

prompt = "A luxury wristwatch placed on a black velvet pedestal, enclosed within a subtle metallic frame. Low-key dramatic lighting with controlled highlights. High-end jewelry product atmosphere. Deep neutral palette with soft contrast transitions."
negative_prompt = ""

height, width = 512, 512
steps = 30
cfg = 7

torch.cuda.empty_cache()
start = time.time()

image = pipe(
    prompt=prompt,
    negative_prompt=negative_prompt,
    height=height,
    width=width,
    guidance_scale=cfg,
    num_inference_steps=steps,
).images[0]

end = time.time()

image.save("output.png")

print(f"Generation Time: {end - start:.2f} seconds")

## GPU Usage

!nvidia-smi

gpu_usage = subprocess.getoutput("nvidia-smi").split("\n")
print("\n".join(gpu_usage[:10]))

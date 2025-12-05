"""
Inpainting
Original file: https://colab.research.google.com/drive/15HZcoDGdzTaDO9d1uIUMI8LQToCP4ryC
"""

## Fal.ai API

!pip install fal-client

import numpy as np
import pandas as pd
import fal_client
import requests
import os
import numpy as np
import scipy.ndimage
from io import BytesIO
from PIL import Image, ImageFilter
from IPython.display import display

os.environ["FAL_KEY"] = "YOUR_API_KEY"

CLEAN_IMAGE_PATH = "clean_image_path"
DRAWN_IMAGE_PATH = "drawn_image_path"
MASK_OUTPUT_PATH = "solid_mask.png"


def generate_and_save_mask(clean_path, drawn_path, save_path):
    print("Generating mask with robust filtering...")

    if not os.path.exists(clean_path) or not os.path.exists(drawn_path):
        print(" Error: Input images not found.")
        return False

    img_clean = Image.open(clean_path).convert("RGB").resize((1024, 1024))
    img_drawn = Image.open(drawn_path).convert("RGB").resize((1024, 1024))

    clean_blur = np.array(img_clean.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16)
    drawn_blur = np.array(img_drawn.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16)

    diff_arr = np.abs(drawn_blur - clean_blur)
    mask_arr = np.max(diff_arr, axis=2)

    mask_binary = mask_arr > 30

    mask_filled = scipy.ndimage.binary_fill_holes(mask_binary)
    mask = Image.fromarray((mask_filled * 255).astype(np.uint8))
    mask = mask.filter(ImageFilter.MaxFilter(9))

    mask.save(save_path)
    img_clean.save("resized_clean.png")

    print(" The AI will ONLY edit the WHITE area below:")
    display(mask.resize((256, 256)))

    return True


def run_fal_inpainting(image_path, mask_path):
    print("Uploading images to Fal.ai...")

    image_url = fal_client.upload_file(image_path)
    mask_url = fal_client.upload_file(mask_path)

    print("Running Flux Dev Fill...")

    try:
        handler = fal_client.submit(
            "fal-ai/flux-lora-fill",
            arguments={
                "prompt": "The image shows a river running through a lush green valley surrounded by trees, plants, grass, and poles. In the background, the sky is filled with clouds, creating a peaceful atmosphere.",
                "image_url": image_url,
                "mask_url": mask_url,
                "guidance_scale": 30,
                "num_inference_steps": 28,
                "enable_safety_checker": False,
            },
        )

        result = handler.get()

        if "images" in result:
            output_url = result["images"][0]["url"]
            print(f"Success! Image generated: {output_url}")

            response = requests.get(output_url)
            img = Image.open(BytesIO(response.content))
            img.save("final_output.png")
            display(img)
        else:
            print(" API returned no images.")
            print(result)

    except Exception as e:
        print(f"Error during API call: {e}")


#  MAIN EXECUTION

if __name__ == "__main__":
    success = generate_and_save_mask(
        CLEAN_IMAGE_PATH, DRAWN_IMAGE_PATH, MASK_OUTPUT_PATH
    )
    if success:
        run_fal_inpainting("resized_clean.png", MASK_OUTPUT_PATH)

## Stable Diffusion

!pip install torch diffusers transformers accelerate gradio

import torch
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image, ImageFilter
from diffusers import AutoPipelineForInpainting
import os
import scipy.ndimage


def load_model():
    model_id = "runwayml/stable-diffusion-inpainting"
    device = "cuda" if torch.cuda.is_available() else "cpu"

    print(f"Loading model to {device} (this may take a minute)...")
    try:
        pipe = AutoPipelineForInpainting.from_pretrained(
            model_id, torch_dtype=torch.float16, variant="fp16"
        ).to(device)
        pipe.enable_attention_slicing()
        return pipe
    except Exception as e:
        print(f"Error loading model: {e}")
        return None


def run_sketch_to_image(
    pipe, clean_path, drawn_path, prompt, negative_prompt="", strength=0.85, seed=42
):
    if not os.path.exists(clean_path) or not os.path.exists(drawn_path):
        print(" Error: Images not found.")
        return

    img_clean = Image.open(clean_path).convert("RGB").resize((512, 512))
    img_drawn = Image.open(drawn_path).convert("RGB").resize((512, 512))

    clean_blur = np.array(
        img_clean.filter(ImageFilter.GaussianBlur(radius=2)), dtype=np.int16
    )
    drawn_blur = np.array(
        img_drawn.filter(ImageFilter.GaussianBlur(radius=2)), dtype=np.int16
    )

    diff_arr = np.abs(drawn_blur - clean_blur)

    mask_arr = np.max(diff_arr, axis=2)

    mask_binary = mask_arr > 30

    mask_filled = scipy.ndimage.binary_fill_holes(mask_binary)
    mask = Image.fromarray((mask_filled * 255).astype(np.uint8))

    mask = mask.filter(ImageFilter.MaxFilter(9))

    generator = torch.Generator(device="cuda").manual_seed(seed)

    print(f" Generating with Strength {strength}...")
    with torch.inference_mode():
        output = pipe(
            prompt=prompt,
            negative_prompt=negative_prompt,
            image=img_drawn,
            mask_image=mask,
            strength=strength,
            guidance_scale=8.0,
            num_inference_steps=50,
            generator=generator,
        ).images[0]

    fig, axs = plt.subplots(1, 4, figsize=(20, 6))
    axs[0].imshow(img_clean)
    axs[0].set_title("Initial")
    axs[1].imshow(img_drawn)
    axs[1].set_title("Sketch")
    axs[2].imshow(mask, cmap="gray")
    axs[2].set_title("Calculated Mask (Fixed)")
    axs[3].imshow(output)
    axs[3].set_title("Result")
    plt.tight_layout()
    plt.show()
    return output


if __name__ == "__main__":
    if "pipeline" not in globals():
        pipeline = load_model()

    if pipeline:
        run_sketch_to_image(
            pipe=pipeline,
            clean_path="/kaggle/input/sample/scenery.jpg.png",
            drawn_path="/kaggle/input/sample/scenery_sketch.jpg",
            prompt="The image shows a river running through a lush green valley surrounded by trees, plants, grass, and poles. In the background, the sky is filled with clouds, creating a peaceful atmosphere.",
            negative_prompt="",
            strength=0.85,
            seed=100,
        )


## Captioning

!pip install -q einops timm

import torch
from transformers import AutoProcessor, AutoModelForCausalLM
from PIL import Image
import time

device = "cuda" if torch.cuda.is_available() else "cpu"
model_id = "microsoft/Florence-2-base"

print(f" Loading Model: {model_id}...")

model = AutoModelForCausalLM.from_pretrained(
    model_id, trust_remote_code=True, torch_dtype=torch.float16
).to(device)

processor = AutoProcessor.from_pretrained(model_id, trust_remote_code=True)

print("Model Loaded & Moved to GPU. Ready for Inference.")


def generate_concise_caption(image_path):
    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16

    torch.cuda.reset_peak_memory_stats()
    torch.cuda.synchronize()
    start_time = time.time()

    image = Image.open(image_path).convert("RGB")

    prompt_task = "<DETAILED_CAPTION>"

    inputs = processor(text=prompt_task, images=image, return_tensors="pt").to(
        device, dtype
    )

    generated_ids = model.generate(
        input_ids=inputs["input_ids"],
        pixel_values=inputs["pixel_values"],
        max_new_tokens=64,
        num_beams=1,
        do_sample=False,
    )

    generated_text = processor.batch_decode(generated_ids, skip_special_tokens=False)[0]
    caption = processor.post_process_generation(
        generated_text, task=prompt_task, image_size=(image.width, image.height)
    )[prompt_task]

    caption = caption.strip()
    if not caption.endswith("."):
        last_period_index = caption.rfind(".")
        if last_period_index != -1:
            caption = caption[: last_period_index + 1]

    torch.cuda.synchronize()
    end_time = time.time()
    latency = end_time - start_time
    mem_gb = torch.cuda.max_memory_allocated() / (1024**3)

    print("-" * 30)
    print(f"Result: {caption}")
    print(f"Tokens: ~{len(caption.split())} words")  # Approx count
    print("-" * 30)
    print(f"⚡ Latency: {latency:.4f}s")
    print(f"VRAM:    {mem_gb:.2f} GB")
    print("-" * 30)

    return caption


text_output = generate_concise_caption("/kaggle/input/test1/tree_sketch.jpg")

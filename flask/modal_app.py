import os
import io
import sys
import base64
import modal

# ==============================================================================
# 1. DEFINE THE CLOUD ENVIRONMENT
# ==============================================================================
image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install(
        "libgl1-mesa-glx",
        "libglib2.0-0",
        "libstdc++6",
        "libxext6",
        "libsm6",
        "libxrender1",
    )
    .pip_install(
        "torch",
        "torchvision",
        "transformers",
        "diffusers",
        "accelerate",
        "safetensors",
        "opencv-python-headless",
        "pillow",
        "numpy",
        "scipy",
        "bitsandbytes",
        "timm",
        "einops",
        "kornia",
        "flask-cors",
        "fastapi[standard]",
        "fal-client",
        "requests",
    )
    # --- MOUNT LOCAL MODELS ---
    .add_local_dir("local_inpainting_model", remote_path="/models/sd-inpainting")
    .add_local_dir("Florence-2-4bit-Quantized", remote_path="/models/florence-2")
    .add_local_dir("BiRefNet", remote_path="/root/BiRefNet")
)

app = modal.App("adobe-flask", image=image)


# ==============================================================================
# 2. THE BACKEND SERVER CLASS
# ==============================================================================
@app.cls(
    gpu="any", 
    scaledown_window=300,
    secrets=[modal.Secret.from_name("fal-secret")]
)
class ModelBackend:

    @modal.enter()
    def load_models(self):
        """Runs once when container starts."""
        print("⏳ Loading models into GPU memory...")
        import torch
        import torch.nn as nn
        import sys

        self.device = "cuda"

        # FAL.AI API KEY
        if "FAL_KEY" not in os.environ:
            print("❌ Error: FAL_KEY secret not found!")
        else:
            print("✅ FAL_KEY loaded securely.")

        # --- 1. SETUP BiRefNet PATHS ---
        sys.path.append("/root/BiRefNet")

        # --- 2. LOAD STABLE DIFFUSION ---
        from diffusers import StableDiffusionInpaintPipeline

        self.sd_pipe = StableDiffusionInpaintPipeline.from_pretrained(
            "/models/sd-inpainting",
            torch_dtype=torch.float16,
            use_safetensors=True,
            local_files_only=True,
        ).to(self.device)
        self.sd_pipe.enable_attention_slicing()
        print("✅ Stable Diffusion Loaded")

        # --- 3. LOAD FLORENCE-2 ---
        import transformers.dynamic_module_utils

        # Patch 1: Fix import check
        def check_imports_fixed(filename):
            return []

        transformers.dynamic_module_utils.check_imports = check_imports_fixed

        # Patch 2: Fix '_supports_sdpa' error
        _old_getattr = nn.Module.__getattr__

        def _fixed_getattr(self, name):
            if name == "_supports_sdpa":
                return False
            return _old_getattr(self, name)

        nn.Module.__getattr__ = _fixed_getattr

        from transformers import AutoModelForCausalLM, AutoProcessor, BitsAndBytesConfig

        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.float16,
        )
        self.florence_model = AutoModelForCausalLM.from_pretrained(
            "/models/florence-2",
            quantization_config=bnb_config,
            trust_remote_code=True,
            local_files_only=True,
        ).to(self.device)
        self.florence_processor = AutoProcessor.from_pretrained(
            "/models/florence-2", trust_remote_code=True, local_files_only=True
        )
        print("✅ Florence-2 Loaded")

        # --- 4. LOAD BIREFNET ---
        try:
            from models.birefnet import BiRefNet

            self.birefnet = BiRefNet(bb_pretrained=False)

            weight_path = "/root/BiRefNet/birefnet_fp16.pt"
            state_dict = torch.load(weight_path, map_location=self.device)
            self.birefnet.load_state_dict(state_dict)
            self.birefnet.to(self.device).half().eval()
            print(f"✅ BiRefNet Loaded from {weight_path}")
        except Exception as e:
            print(f"❌ BiRefNet Error: {e}")
            self.birefnet = None

        from torchvision import transforms

        self.transform_birefnet = transforms.Compose(
            [
                transforms.Resize((1024, 1024)),
                transforms.ToTensor(),
                transforms.Normalize(
                    mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]
                ),
            ]
        )

    # ==========================================================================
    # 3. ENDPOINTS
    # ==========================================================================

    @modal.fastapi_endpoint(method="POST")
    def generate(self, item: dict):
        from PIL import Image

        prompt = item.get("prompt", "A luxury watch")
        print(f"🎨 Generating: {prompt}")

        empty_image = Image.new("RGB", (512, 512), (0, 0, 0))
        full_mask = Image.new("L", (512, 512), 255)

        image = self.sd_pipe(
            prompt=prompt,
            image=empty_image,
            mask_image=full_mask,
            height=512,
            width=512,
            num_inference_steps=30,
        ).images[0]

        return {"status": "success", "image": self._to_base64(image)}

    @modal.fastapi_endpoint(method="POST")
    def inpainting(self, item: dict):
        """Local Stable Diffusion Inpainting"""
        from PIL import Image, ImageFilter
        import numpy as np
        import scipy.ndimage
        import torch

        user_prompt = item.get("prompt", "")
        img_b64 = item.get("image")
        mask_b64 = item.get("mask_image")

        if not img_b64 or not mask_b64:
            return {"status": "error", "message": "Missing image or mask"}

        # 1. Decode Images
        raw_clean = self._decode_base64(img_b64).convert("RGB")
        raw_drawn = self._decode_base64(mask_b64).convert("RGB")

        # 2. Resize maintaining Aspect Ratio (Max 512 for Local SD)
        img_clean = self._resize_to_limit(raw_clean, max_dim=512)
        # Resize drawn image to match the clean image exactly
        img_drawn = raw_drawn.resize(img_clean.size)

        print(f"🔍 Calculating Robust Difference Mask (Size: {img_clean.size})...")

        # --- ROBUST MASKING ---
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
        mask_image = Image.fromarray((mask_filled * 255).astype(np.uint8))
        mask_image = mask_image.filter(ImageFilter.MaxFilter(9))
        print("✅ Mask calculated.")

        # --- FLORENCE-2 CONTEXT GENERATION ---
        generated_prompt = ""
        if self.florence_model and self.florence_processor:
            print("👁️ Generating context with Florence-2...")
            try:
                task_prompt = "<DETAILED_CAPTION>"
                # Use img_drawn (sketch) for context analysis
                inputs = self.florence_processor(
                    text=task_prompt, images=[img_drawn], return_tensors="pt"
                )
                inputs["pixel_values"] = inputs["pixel_values"].to(
                    self.device, torch.float16
                )
                inputs["input_ids"] = inputs["input_ids"].to(self.device)

                generated_ids = self.florence_model.generate(
                    input_ids=inputs["input_ids"],
                    pixel_values=inputs["pixel_values"],
                    max_new_tokens=128,
                    num_beams=1,
                    do_sample=False,
                    use_cache=False,  # Fix for transformers crash
                )

                generated_text = self.florence_processor.batch_decode(
                    generated_ids, skip_special_tokens=False
                )[0]
                generated_prompt = (
                    generated_text.replace(task_prompt, "")
                    .replace("</s>", "")
                    .replace("<s>", "")
                    .strip()
                )
                print(f"📝 Florence Generated: {generated_prompt}")
            except Exception as e:
                print(f"⚠️ Florence captioning failed: {e}")

        final_prompt = f"{generated_prompt} {user_prompt}".strip()
        negative_prompt = (
            "blurry, low quality, ugly, text, watermark, bad anatomy, deformed, noisy"
        )

        # --- INFERENCE ---
        print(f"🎨 Running Inference: {final_prompt}")
        output = self.sd_pipe(
            prompt=final_prompt,
            negative_prompt=negative_prompt,
            image=img_drawn,  # Input is the SKETCH
            mask_image=mask_image,  # Mask is where sketch differs
            num_inference_steps=50,
            strength=0.85,
            guidance_scale=8.5,
        ).images[0]

        return {"status": "success", "image": self._to_base64(output)}

    @modal.fastapi_endpoint(method="POST")
    def inpainting_api(self, item: dict):
        """Fal.ai Flux Lora Fill"""
        import fal_client
        import requests
        import uuid
        import numpy as np
        import scipy.ndimage
        from PIL import Image, ImageFilter

        prompt = item.get("prompt", "A high quality image")
        img_b64 = item.get("image")
        mask_b64 = item.get("mask_image")

        if not img_b64 or not mask_b64:
            return {"status": "error", "message": "Missing image or mask"}

        # 1. Decode & Resize (Flux supports higher res)
        raw_clean = self._decode_base64(img_b64).convert("RGB")
        raw_drawn = self._decode_base64(mask_b64).convert("RGB")

        img_clean = self._resize_to_limit(raw_clean, max_dim=1024)
        img_drawn = raw_drawn.resize(img_clean.size)

        # 2. Robust Mask Generation
        clean_blur = np.array(
            img_clean.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16
        )
        drawn_blur = np.array(
            img_drawn.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16
        )

        diff_arr = np.abs(drawn_blur - clean_blur)
        mask_arr = np.max(diff_arr, axis=2)
        mask_binary = mask_arr > 30

        mask_filled = scipy.ndimage.binary_fill_holes(mask_binary)
        mask = Image.fromarray((mask_filled * 255).astype(np.uint8))
        mask = mask.filter(ImageFilter.MaxFilter(9))

        # 3. Save to temp files for upload
        temp_id = str(uuid.uuid4())
        clean_path = f"/tmp/clean_{temp_id}.png"
        mask_path = f"/tmp/mask_{temp_id}.png"

        img_clean.save(clean_path)
        mask.save(mask_path)

        try:
            print("🚀 Uploading to Fal.ai...")
            image_url = fal_client.upload_file(clean_path)
            mask_url = fal_client.upload_file(mask_path)

            print(f"⚡ Running Flux Dev Fill for: {prompt}")
            handler = fal_client.submit(
                "fal-ai/flux-lora-fill",
                arguments={
                    "prompt": prompt,
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
                response = requests.get(output_url)
                result_img = Image.open(io.BytesIO(response.content))
                return {"status": "success", "image": self._to_base64(result_img)}
            else:
                return {"status": "error", "message": "Fal.ai returned no images"}

        except Exception as e:
            print(f"❌ Fal.ai Error: {e}")
            return {"status": "error", "message": str(e)}
        finally:
            if os.path.exists(clean_path):
                os.remove(clean_path)
            if os.path.exists(mask_path):
                os.remove(mask_path)

    @modal.fastapi_endpoint(method="POST")
    def sketch_api(self, item: dict):
        """Sketch Text-to-Image (Flux)"""
        import fal_client
        import requests
        from PIL import Image

        prompt = item.get("prompt")
        option = item.get("option", 1)

        if not prompt:
            return {"status": "error", "message": "Missing prompt"}

        enhanced_prompt = (
            f"{prompt}, sharp focus, high definition, 4k, vector art, crisp lines"
        )

        if int(option) == 1:
            model_id = "fal-ai/flux/schnell"
            arguments = {
                "image_size": "square_hd",
                "num_inference_steps": 4,
                "enable_safety_checker": False,
                "prompt": enhanced_prompt,
            }
        else:
            model_id = "fal-ai/flux/dev"
            arguments = {
                "image_size": "square_hd",
                "num_inference_steps": 28,
                "guidance_scale": 3.5,
                "safety_tolerance": "2",
                "enable_safety_checker": False,
                "prompt": enhanced_prompt,
            }

        try:
            print(f"🚀 Running Sketch Gen ({model_id})...")
            handler = fal_client.submit(model_id, arguments=arguments)
            result = handler.get()

            if "images" in result and len(result["images"]) > 0:
                image_url = result["images"][0]["url"]
                response = requests.get(image_url)
                if response.status_code == 200:
                    img = Image.open(io.BytesIO(response.content)).convert("RGB")
                    return {"status": "success", "image": self._to_base64(img)}

            return {"status": "error", "message": "Fal.ai returned no images"}
        except Exception as e:
            print(f"❌ Sketch API Error: {e}")
            return {"status": "error", "message": str(e)}

    @modal.fastapi_endpoint(method="POST")
    def asset(self, item: dict):
        import torch
        import numpy as np
        from PIL import Image

        if not self.birefnet:
            return {"status": "error", "message": "BiRefNet not loaded"}

        img_b64 = item.get("image")
        image = self._decode_base64(img_b64)
        orig_w, orig_h = image.size

        input_tensor = (
            self.transform_birefnet(image).unsqueeze(0).to(self.device).half()
        )
        with torch.no_grad():
            preds = self.birefnet(input_tensor)[-1].sigmoid()

        res = torch.nn.functional.interpolate(
            preds, size=(orig_h, orig_w), mode="bilinear", align_corners=True
        )
        mask_np = res.squeeze().cpu().numpy()
        mask_img = Image.fromarray((mask_np * 255).astype(np.uint8))

        image.putalpha(mask_img)
        return {"status": "success", "image": self._to_base64(image)}

    @modal.fastapi_endpoint(method="POST")
    def describe(self, item: dict):
        import torch

        img_b64 = item.get("image")
        prompt = item.get("prompt", "<DETAILED_CAPTION>")

        image = self._decode_base64(img_b64)

        inputs = self.florence_processor(text=prompt, images=image, return_tensors="pt")
        inputs["pixel_values"] = inputs["pixel_values"].to(self.device, torch.float16)
        inputs["input_ids"] = inputs["input_ids"].to(self.device)

        # --- FIX: Explicitly disable caching to prevent beam search crash ---
        generated_ids = self.florence_model.generate(
            input_ids=inputs["input_ids"],
            pixel_values=inputs["pixel_values"],
            max_new_tokens=1024,
            num_beams=3,
            use_cache=False,  # <--- CRITICAL FIX for Florence-2 on newer Transformers
        )

        text = self.florence_processor.batch_decode(
            generated_ids, skip_special_tokens=False
        )[0]
        clean_text = (
            text.replace("</s>", "").replace("<s>", "").replace(prompt, "").strip()
        )

        return {"status": "success", "output": clean_text}

    # --- HELPERS ---
    def _decode_base64(self, b64_str):
        from PIL import Image

        if "," in b64_str:
            b64_str = b64_str.split(",")[1]
        return Image.open(io.BytesIO(base64.b64decode(b64_str))).convert("RGB")

    def _to_base64(self, img):
        buffered = io.BytesIO()
        img.save(buffered, format="PNG")
        return base64.b64encode(buffered.getvalue()).decode("utf-8")

    def _resize_to_limit(self, img, max_dim=1024, multiple=8):
        from PIL import Image

        w, h = img.size
        ratio = min(max_dim / w, max_dim / h)
        new_w = int(w * ratio)
        new_h = int(h * ratio)
        new_w = new_w - (new_w % multiple)
        new_h = new_h - (new_h % multiple)
        if new_w < multiple:
            new_w = multiple
        if new_h < multiple:
            new_h = multiple
        return img.resize((new_w, new_h), Image.LANCZOS)

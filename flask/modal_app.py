import os
import io
import sys
import base64
import json
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
        "pycryptodome",
    )
    # --- MOUNT LOCAL MODELS ---
    .add_local_dir("local_inpainting_model", remote_path="/models/sd-inpainting")
    .add_local_dir("Florence-2-4bit-Quantized", remote_path="/models/florence-2")
    .add_local_dir("BiRefNet", remote_path="/root/BiRefNet")
)

app = modal.App("creekui", image=image)


# ==============================================================================
# 2. THE BACKEND SERVER CLASS
# ==============================================================================
@app.cls(
    gpu="any",
    scaledown_window=300,
    secrets=[modal.Secret.from_name("creek-secrets")],
)
class ModelBackend:

    @modal.enter()
    def load_models(self):
        """Runs once when container starts."""
        print("⏳ Loading models into GPU memory...")
        import torch
        import torch.nn as nn
        import sys
        from Crypto.Cipher import AES

        self.device = "cuda"

        # --- 1. SETUP CRYPTO ---
        secret_key_b64 = os.environ.get("SHARED_SECRET_KEY")
        if not secret_key_b64:
            raise ValueError("SHARED_SECRET_KEY not set in Modal Secrets")

        # Define CryptoManager inside container
        class CryptoManager:
            def __init__(self, key_base64):
                self.key = base64.b64decode(key_base64)

            def decrypt(self, encrypted_b64):
                try:
                    data = base64.b64decode(encrypted_b64)
                    nonce = data[:12]
                    tag = data[-16:]
                    ciphertext = data[12:-16]
                    cipher = AES.new(self.key, AES.MODE_GCM, nonce=nonce)
                    return cipher.decrypt_and_verify(ciphertext, tag).decode("utf-8")
                except Exception as e:
                    print(f"Decryption failed: {e}")
                    return None

            def encrypt(self, plain_text):
                nonce = os.urandom(12)
                cipher = AES.new(self.key, AES.MODE_GCM, nonce=nonce)
                ciphertext, tag = cipher.encrypt_and_digest(plain_text.encode("utf-8"))
                combined = nonce + ciphertext + tag
                return base64.b64encode(combined).decode("utf-8")

        self.crypto = CryptoManager(secret_key_b64)
        print("✅ Crypto Initialized")

        # Check FAL KEY
        if "FAL_KEY" not in os.environ:
            print("❌ Error: FAL_KEY secret not found!")
        else:
            print("✅ FAL_KEY loaded securely.")

        # --- 2. SETUP PATHS & MODELS ---
        sys.path.append("/root/BiRefNet")

        # Load Stable Diffusion
        from diffusers import StableDiffusionInpaintPipeline

        self.sd_pipe = StableDiffusionInpaintPipeline.from_pretrained(
            "/models/sd-inpainting",
            torch_dtype=torch.float16,
            use_safetensors=True,
            local_files_only=True,
        ).to(self.device)
        self.sd_pipe.enable_attention_slicing()
        print("✅ Stable Diffusion Loaded")

        # Load Florence-2
        import transformers.dynamic_module_utils

        transformers.dynamic_module_utils.check_imports = lambda f: []

        # Patch for _supports_sdpa
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

        # Load BiRefNet
        try:
            from models.birefnet import BiRefNet

            self.birefnet = BiRefNet(bb_pretrained=False)
            weight_path = "/root/BiRefNet/birefnet_fp16.pt"
            state_dict = torch.load(weight_path, map_location=self.device)
            self.birefnet.load_state_dict(state_dict)
            self.birefnet.to(self.device).half().eval()
            print(f"✅ BiRefNet Loaded")
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

    # --- SECURITY WRAPPER ---
    def _handle_secure_request(self, item: dict, logic_func):
        """Decrypts input -> Runs Logic -> Encrypts Output"""
        try:
            # 1. Decrypt Incoming
            if "data" not in item:
                return {"error": "Invalid format. Expected {'data': ...}"}

            decrypted_json_str = self.crypto.decrypt(item["data"])
            if decrypted_json_str is None:
                return {"error": "Decryption failed (Check Key)"}

            payload = json.loads(decrypted_json_str)

            # 2. Run Actual Logic
            result = logic_func(payload)

            # 3. Encrypt Outgoing
            encrypted_response = self.crypto.encrypt(json.dumps(result))
            return {"data": encrypted_response}

        except Exception as e:
            print(f"Request Error: {e}")
            return {"error": str(e)}

    # ==========================================================================
    # 3. ENDPOINTS
    # ==========================================================================

    @modal.fastapi_endpoint(method="POST")
    def generate(self, item: dict):
        def logic(data):
            from PIL import Image

            prompt = data.get("prompt", "A luxury watch")
            print(f"🎨 Generating: {prompt}")
            empty = Image.new("RGB", (512, 512))
            mask = Image.new("L", (512, 512), 255)
            img = self.sd_pipe(
                prompt=prompt,
                image=empty,
                mask_image=mask,
                height=512,
                width=512,
                num_inference_steps=30,
            ).images[0]
            return {"status": "success", "image": self._to_base64(img)}

        return self._handle_secure_request(item, logic)

    @modal.fastapi_endpoint(method="POST")
    def inpainting(self, item: dict):
        def logic(data):
            from PIL import Image, ImageFilter
            import numpy as np
            import scipy.ndimage
            import torch

            prompt = data.get("prompt", "")
            img_b64 = data.get("image")
            mask_b64 = data.get("mask_image")

            clean = self._decode_base64(img_b64).convert("RGB")
            drawn = self._decode_base64(mask_b64).convert("RGB")

            clean = self._resize_to_limit(clean, 512)
            drawn = drawn.resize(clean.size)

            # Robust Masking
            clean_blur = np.array(
                clean.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16
            )
            drawn_blur = np.array(
                drawn.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16
            )
            mask_arr = np.max(np.abs(drawn_blur - clean_blur), axis=2)
            mask = Image.fromarray(
                (scipy.ndimage.binary_fill_holes(mask_arr > 30) * 255).astype(np.uint8)
            ).filter(ImageFilter.MaxFilter(9))

            # Florence Context
            inputs = self.florence_processor(
                text="<DETAILED_CAPTION>", images=[drawn], return_tensors="pt"
            )
            inputs = {
                k: v.to(self.device, torch.float16 if k == "pixel_values" else None)
                for k, v in inputs.items()
            }
            gen_ids = self.florence_model.generate(
                **inputs, max_new_tokens=128, num_beams=1, use_cache=False
            )
            context = (
                self.florence_processor.batch_decode(
                    gen_ids, skip_special_tokens=False
                )[0]
                .replace("</s>", "")
                .replace("<s>", "")
                .replace("<DETAILED_CAPTION>", "")
                .strip()
            )

            full_prompt = f"{context} {prompt}".strip()

            output = self.sd_pipe(
                prompt=full_prompt,
                negative_prompt="blurry, low quality, ugly, text, watermark, bad anatomy, deformed, noisy",
                image=drawn,
                mask_image=mask,
                num_inference_steps=50,
                strength=0.85,
                guidance_scale=8.5,
            ).images[0]

            return {"status": "success", "image": self._to_base64(output)}

        return self._handle_secure_request(item, logic)

    @modal.fastapi_endpoint(method="POST")
    def inpainting_api(self, item: dict):
        def logic(data):
            import fal_client, requests, uuid, scipy.ndimage
            from PIL import Image, ImageFilter
            import numpy as np

            prompt = data.get("prompt", "High quality image")
            img_b64 = data.get("image")
            mask_b64 = data.get("mask_image")

            clean = self._decode_base64(img_b64).convert("RGB")
            drawn = self._decode_base64(mask_b64).convert("RGB")

            clean = self._resize_to_limit(clean, 1024)
            drawn = drawn.resize(clean.size)

            # Masking
            clean_blur = np.array(
                clean.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16
            )
            drawn_blur = np.array(
                drawn.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16
            )
            mask = Image.fromarray(
                (
                    scipy.ndimage.binary_fill_holes(
                        np.max(np.abs(drawn_blur - clean_blur), axis=2) > 30
                    )
                    * 255
                ).astype(np.uint8)
            ).filter(ImageFilter.MaxFilter(9))

            clean_p, mask_p = (
                f"/tmp/c_{uuid.uuid4()}.png",
                f"/tmp/m_{uuid.uuid4()}.png",
            )
            clean.save(clean_p)
            mask.save(mask_p)

            try:
                res = fal_client.submit(
                    "fal-ai/flux-lora-fill",
                    arguments={
                        "prompt": prompt,
                        "image_url": fal_client.upload_file(clean_p),
                        "mask_url": fal_client.upload_file(mask_p),
                        "guidance_scale": 30,
                        "num_inference_steps": 28,
                        "enable_safety_checker": False,
                    },
                ).get()

                if "images" in res:
                    img_resp = requests.get(res["images"][0]["url"])
                    img = Image.open(io.BytesIO(img_resp.content))
                    return {"status": "success", "image": self._to_base64(img)}
                return {"status": "error", "message": "No images from Fal"}
            finally:
                if os.path.exists(clean_p):
                    os.remove(clean_p)
                if os.path.exists(mask_p):
                    os.remove(mask_p)

        return self._handle_secure_request(item, logic)

    @modal.fastapi_endpoint(method="POST")
    def sketch_api(self, item: dict):
        def logic(data):
            import fal_client, requests
            from PIL import Image

            prompt = data.get("prompt", "")
            option = int(data.get("option", 1))

            enhanced_prompt = (
                f"{prompt}, sharp focus, high definition, 4k, vector art, crisp lines"
            )

            if option == 1:
                # Nano Banana
                print(f"🍌 Using Nano Banana for: {prompt}")
                model_id = "fal-ai/nano-banana"
                arguments = {
                    "prompt": enhanced_prompt,
                    "num_images": 1,
                    "aspect_ratio": "1:1",
                    "output_format": "png",
                }
            else:
                # Flux Dev
                print(f"🚀 Using Flux Dev for: {prompt}")
                model_id = "fal-ai/flux/dev"
                arguments = {
                    "image_size": "square_hd",
                    "num_inference_steps": 28,
                    "guidance_scale": 3.5,
                    "safety_tolerance": "2",
                    "enable_safety_checker": False,
                    "prompt": enhanced_prompt,
                }

            res = fal_client.submit(model_id, arguments=arguments).get()
            if "images" in res:
                img_resp = requests.get(res["images"][0]["url"])
                img = Image.open(io.BytesIO(img_resp.content)).convert("RGB")
                return {"status": "success", "image": self._to_base64(img)}
            return {"status": "error", "message": "No images returned"}

        return self._handle_secure_request(item, logic)

    @modal.fastapi_endpoint(method="POST")
    def asset(self, item: dict):
        def logic(data):
            import torch, numpy as np
            from PIL import Image

            img_b64 = data.get("image")
            img = self._decode_base64(img_b64)
            w, h = img.size

            inp = self.transform_birefnet(img).unsqueeze(0).to(self.device).half()
            with torch.no_grad():
                preds = self.birefnet(inp)[-1].sigmoid()

            import torch.nn.functional as F

            res = F.interpolate(preds, size=(h, w), mode="bilinear", align_corners=True)
            mask = Image.fromarray((res.squeeze().cpu().numpy() * 255).astype(np.uint8))
            img.putalpha(mask)

            return {"status": "success", "image": self._to_base64(img)}

        return self._handle_secure_request(item, logic)

    @modal.fastapi_endpoint(method="POST")
    def describe(self, item: dict):
        def logic(data):
            import torch

            img_b64 = data.get("image")
            img = self._decode_base64(img_b64)
            prompt = data.get("prompt", "<DETAILED_CAPTION>")

            inputs = self.florence_processor(
                text=prompt, images=img, return_tensors="pt"
            )
            inputs = {
                k: v.to(self.device, torch.float16 if k == "pixel_values" else None)
                for k, v in inputs.items()
            }

            gen_ids = self.florence_model.generate(
                **inputs, max_new_tokens=1024, num_beams=3, use_cache=False
            )
            txt = self.florence_processor.batch_decode(
                gen_ids, skip_special_tokens=False
            )[0]
            clean_txt = (
                txt.replace("</s>", "").replace("<s>", "").replace(prompt, "").strip()
            )

            return {"status": "success", "output": clean_txt}

        return self._handle_secure_request(item, logic)

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

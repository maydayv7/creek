import os
import io
import sys
import base64
import cv2
import re
import numpy as np
import torch
import traceback
import requests
import scipy.ndimage
import json
from functools import wraps
from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
from PIL import Image, ImageFilter
from torchvision import transforms
import time
import uuid
from Crypto.Cipher import AES
from dotenv import load_dotenv

load_dotenv()


class CryptoManager:
    def __init__(self, key_base64):
        # Decode the base64 key to raw bytes (must be 32 bytes for AES-256)
        self.key = base64.b64decode(key_base64)

    def encrypt(self, plain_text):
        # 1. Generate a random unique Nonce (12 bytes is standard for GCM)
        nonce = os.urandom(12)

        # 2. Initialize Cipher
        cipher = AES.new(self.key, AES.MODE_GCM, nonce=nonce)

        # 3. Encrypt and get Tag (MAC)
        ciphertext, tag = cipher.encrypt_and_digest(plain_text.encode("utf-8"))

        # 4. Pack: Nonce + Ciphertext + Tag
        combined = nonce + ciphertext + tag

        # 5. Return as Base64 string
        return base64.b64encode(combined).decode("utf-8")

    def decrypt(self, encrypted_b64):
        try:
            # 1. Decode Base64
            data = base64.b64decode(encrypted_b64)

            # 2. Unpack (Slice the bytes)
            nonce = data[:12]
            tag = data[-16:]
            ciphertext = data[12:-16]

            # 3. Decrypt
            cipher = AES.new(self.key, AES.MODE_GCM, nonce=nonce)
            decrypted_data = cipher.decrypt_and_verify(ciphertext, tag)
            return decrypted_data.decode("utf-8")
        except Exception as e:
            print(f"Decryption failed: {e}")
            return None


# Setup Secret Key
SHARED_SECRET_KEY = os.getenv("SHARED_SECRET_KEY")
if not SHARED_SECRET_KEY:
    print("❌ Error: SHARED_SECRET_KEY not found in .env")
    sys.exit(1)

crypto = CryptoManager(SHARED_SECRET_KEY)


# ==============================================================================
# SECURITY DECORATOR (Middleware)
# ==============================================================================
def secure_endpoint(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # --- 1. INCOMING DECRYPTION ---
        try:
            # Expecting JSON format: { "data": "BASE64_ENCRYPTED_STRING" }
            incoming = request.get_json(silent=True)
            if not incoming or "data" not in incoming:
                return (
                    jsonify(
                        {
                            "error": "Invalid format. Expected {'data': 'encrypted_string'}"
                        }
                    ),
                    400,
                )

            encrypted_b64 = incoming["data"]
            decrypted_json_str = crypto.decrypt(encrypted_b64)

            if decrypted_json_str is None:
                return jsonify({"error": "Decryption failed (Check Key or Nonce)"}), 403

            # Parse the decrypted string back to a Python dictionary
            decrypted_payload = json.loads(decrypted_json_str)

            # OVERRIDE request.get_json() so the inner function sees the decrypted data
            request.get_json = lambda **k: decrypted_payload

        except Exception as e:
            return jsonify({"error": f"Security Middleware Error: {str(e)}"}), 500

        # --- 2. EXECUTE ORIGINAL LOGIC ---
        response = f(*args, **kwargs)

        # --- 3. OUTGOING ENCRYPTION ---
        try:
            # Handle Flask response tuples (e.g., jsonify(...), 500)
            resp_obj = response
            status_code = 200
            if isinstance(response, tuple):
                resp_obj = response[0]
                if len(response) > 1:
                    status_code = response[1]

            # Extract the plain JSON data from the Response object
            if hasattr(resp_obj, "get_json"):
                plain_data = resp_obj.get_json()
            else:
                # Fallback if it's not a response object yet
                plain_data = resp_obj

            # Convert dict -> JSON String -> Encrypt
            plain_json_str = json.dumps(plain_data)
            encrypted_response = crypto.encrypt(plain_json_str)

            # Return standard encrypted wrapper
            return jsonify({"data": encrypted_response}), status_code

        except Exception as e:
            return jsonify({"error": f"Response Encryption Error: {str(e)}"}), 500

    return decorated_function


# --- FAL.AI IMPORTS ---
try:
    import fal_client

    # SETUP API KEY
    if os.getenv("FAL_KEY"):
        os.environ["FAL_KEY"] = os.getenv("FAL_KEY")
        FAL_AVAILABLE = True
    else:
        print("⚠️ Warning: FAL_KEY not found in environment variables.")
        FAL_AVAILABLE = False
except ImportError:
    print("⚠️ Fal.ai Client not installed. /inpainting-api will fail.")
    FAL_AVAILABLE = False

# --- FLORENCE-2 IMPORTS ---
try:
    import bitsandbytes
    from transformers import AutoModelForCausalLM, AutoProcessor, BitsAndBytesConfig
    import transformers.dynamic_module_utils
    import torch.nn as nn

    FLORENCE_AVAILABLE = True
except ImportError as e:
    print(
        f"⚠️ Florence-2 Disabled: {e} (Ensure 'bitsandbytes' and 'transformers' are installed)"
    )
    FLORENCE_AVAILABLE = False
except Exception as e:
    print(f"⚠️ Florence-2 Disabled: Unexpected initialization error: {e}")
    FLORENCE_AVAILABLE = False

# --- IMPORT BIREFNET ---
current_dir = os.path.dirname(os.path.abspath(__file__))
birefnet_path = os.path.join(current_dir, "BiRefNet")

if os.path.exists(birefnet_path):
    if birefnet_path not in sys.path:
        sys.path.append(birefnet_path)
    print(f"✅ Added {birefnet_path} to system path.")
else:
    print(f"❌ Error: '{birefnet_path}' not found. Please clone the repository.")

try:
    from models.birefnet import BiRefNet

    print("✅ BiRefNet imported successfully.")
except ImportError as e:
    print(f"⚠️ Import Error: {e}")
    try:
        import BiRefNet.models.birefnet as brn

        BiRefNet = brn.BiRefNet
        print("✅ BiRefNet imported via package path.")
    except ImportError:
        print(
            "❌ Failed to import BiRefNet. Ensure 'BiRefNet/models/birefnet.py' exists."
        )

# --- IMPORT STABLE DIFFUSION ---
try:
    from diffusers import StableDiffusionInpaintPipeline, AutoPipelineForInpainting
except ImportError:
    print("⚠️ Diffusers not found. SD features disabled.")
    StableDiffusionInpaintPipeline = None
    AutoPipelineForInpainting = None

app = Flask(__name__)
CORS(app)

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
print(f"🚀 Running on device: {DEVICE}")

# ==============================================================================
# 1. LOAD STABLE DIFFUSION
# ==============================================================================
print("⏳ Loading Stable Diffusion (Inpainting)...")
sd_pipe = None
try:
    if StableDiffusionInpaintPipeline:
        SD_MODEL_ID = (
            "./local_inpainting_model"
            if os.path.exists("./local_inpainting_model")
            else "runwayml/stable-diffusion-inpainting"
        )

        sd_pipe = StableDiffusionInpaintPipeline.from_pretrained(
            SD_MODEL_ID,
            torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32,
            use_safetensors=True,
        ).to(DEVICE)
        sd_pipe.enable_attention_slicing()
        sd_pipe.enable_model_cpu_offload()
        print("✅ Stable Diffusion Loaded!")
except Exception as e:
    print(f"❌ Failed to load SD: {e}")

# ==============================================================================
# 2. LOAD BIREFNET
# ==============================================================================
print("⏳ Loading BiRefNet...")
birefnet_model = None
BIREFNET_WEIGHTS = "./BiRefNet/birefnet_fp16.pt"
BIREFNET_SIZE = (1024, 1024)

try:
    if "BiRefNet" in locals() and os.path.exists(BIREFNET_WEIGHTS):
        birefnet_model = BiRefNet(bb_pretrained=False)
        state_dict = torch.load(BIREFNET_WEIGHTS, map_location=DEVICE)
        birefnet_model.load_state_dict(state_dict)
        birefnet_model.to(DEVICE)
        if DEVICE == "cuda":
            birefnet_model.half()
        birefnet_model.eval()
        print("✅ BiRefNet Weights Loaded!")
    else:
        print(f"⚠️ BiRefNet skipped. Weights found: {os.path.exists(BIREFNET_WEIGHTS)}")
except Exception as e:
    print(f"❌ Failed to load BiRefNet: {e}")

transform_birefnet = transforms.Compose(
    [
        transforms.Resize(BIREFNET_SIZE),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ]
)

# ==============================================================================
# 3. LOAD FLORENCE-2 (QUANTIZED)
# ==============================================================================
print("⏳ Loading Florence-2...")
florence_model = None
florence_processor = None
FLORENCE_PATH = os.path.join(current_dir, "Florence-2-4bit-Quantized")

if FLORENCE_AVAILABLE:
    try:

        def check_imports_fixed(filename):
            return []

        transformers.dynamic_module_utils.check_imports = check_imports_fixed

        _old_getattr = nn.Module.__getattr__

        def _fixed_getattr(self, name):
            if name == "_supports_sdpa":
                return False
            return _old_getattr(self, name)

        nn.Module.__getattr__ = _fixed_getattr

        if os.path.exists(FLORENCE_PATH):
            bnb_config = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_compute_dtype=torch.float16,
            )

            florence_model = AutoModelForCausalLM.from_pretrained(
                FLORENCE_PATH,
                quantization_config=bnb_config,
                trust_remote_code=True,
                device_map="cuda" if DEVICE == "cuda" else "cpu",
                local_files_only=True,
            )
            florence_processor = AutoProcessor.from_pretrained(
                FLORENCE_PATH, trust_remote_code=True
            )
            print("✅ Florence-2 Loaded Successfully!")
        else:
            print(f"⚠️ Florence-2 folder not found at: {FLORENCE_PATH}")
    except Exception as e:
        print(f"❌ Failed to load Florence-2: {e}")


# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================
def decode_base64_image(b64_str):
    if "," in b64_str:
        b64_str = b64_str.split(",")[1]
    image_data = base64.b64decode(b64_str)
    img = Image.open(io.BytesIO(image_data))

    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        background = Image.new("RGB", img.size, (255, 255, 255))
        if img.mode == "P":
            img = img.convert("RGBA")
        background.paste(img, mask=img.split()[3])
        return background
    else:
        return img.convert("RGB")


def encode_image_to_base64(pil_img):
    buffered = io.BytesIO()
    pil_img.save(buffered, format="PNG")
    return base64.b64encode(buffered.getvalue()).decode("utf-8")


def process_birefnet_output(preds, original_size):
    if isinstance(preds, (list, tuple)):
        pred_tensor = preds[-1]
    else:
        pred_tensor = preds

    pred_tensor = pred_tensor.sigmoid().cpu()
    mask_np = pred_tensor.squeeze().numpy().astype(np.float32)

    if len(mask_np.shape) > 2:
        mask_np = mask_np[0]

    mask_resized = cv2.resize(mask_np, original_size, interpolation=cv2.INTER_LINEAR)
    mask = (mask_resized > 0.5).astype(np.uint8) * 255

    return Image.fromarray(mask)


def resize_to_limit(img, max_dim=1024, multiple=8):
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


# ==============================================================================
# ROUTES
# ==============================================================================


@app.route("/")
def index():
    return "Image Processing API is running."


@app.route("/test-encrypt", methods=["POST"])
def test_encrypt():
    # Helper route to debug encryption/decryption
    try:
        data = request.get_json()
        plain_text = data.get("text", "Hello, World!")
        encrypted = crypto.encrypt(plain_text)
        decrypted = crypto.decrypt(encrypted)
        return jsonify(
            {"original": plain_text, "encrypted": encrypted, "decrypted": decrypted}
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/generate", methods=["POST"])
@secure_endpoint
def generate_image():
    if not sd_pipe:
        return jsonify({"error": "SD Model not loaded"}), 500
    try:
        data = request.get_json()
        prompt = data.get(
            "prompt",
            "The image shows a river running through a lush green valley surrounded by trees, plants, grass, and poles. In the background, the sky is filled with clouds, creating a peaceful atmosphere.",
        )
        empty_image = Image.new("RGB", (512, 512), (0, 0, 0))
        full_mask = Image.new("L", (512, 512), 255)
        print(f"🎨 Generating: {prompt}")
        image = sd_pipe(
            prompt=prompt,
            image=empty_image,
            mask_image=full_mask,
            height=512,
            width=512,
            num_inference_steps=30,
        ).images[0]
        return jsonify({"status": "success", "image": encode_image_to_base64(image)})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/inpainting", methods=["POST"])
@secure_endpoint
def inpaint_image():
    if not sd_pipe:
        return jsonify({"error": "SD Model not loaded"}), 500
    try:
        data = request.get_json()
        user_prompt = data.get("prompt", "")
        clean_b64 = data.get("image")
        drawn_b64 = data.get("mask_image")

        if not clean_b64 or not drawn_b64:
            return jsonify({"error": "Missing image or mask"}), 400

        # 1. Decode Images
        raw_clean = decode_base64_image(clean_b64).convert("RGB")
        raw_drawn = decode_base64_image(drawn_b64).convert("RGB")

        # 2. Resize maintaining Aspect Ratio (Max 512 for Local SD)
        img_clean = resize_to_limit(raw_clean, max_dim=512)
        # Resize drawn image to match the clean image exactly
        img_drawn = raw_drawn.resize(img_clean.size)

        print(f"🔍 Calculating Robust Difference Mask (Size: {img_clean.size})...")
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

        generated_prompt = ""
        if florence_model and florence_processor:
            print("👁️ Generating context with Florence-2...")
            try:
                task_prompt = "<DETAILED_CAPTION>"
                inputs = florence_processor(
                    text=task_prompt, images=[img_drawn], return_tensors="pt"
                )
                inputs["pixel_values"] = inputs["pixel_values"].to(
                    DEVICE, torch.float16
                )
                inputs["input_ids"] = inputs["input_ids"].to(DEVICE)

                generated_ids = florence_model.generate(
                    input_ids=inputs["input_ids"],
                    pixel_values=inputs["pixel_values"],
                    max_new_tokens=128,
                    num_beams=1,
                    do_sample=False,
                    use_cache=False,
                )

                generated_text = florence_processor.batch_decode(
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
        print(f"✨ Final Inpaint Prompt: {final_prompt}")

        save_dir = "input_data"
        os.makedirs(save_dir, exist_ok=True)
        timestamp = int(time.time())
        img_clean.save(os.path.join(save_dir, f"clean_{timestamp}.png"))
        img_drawn.save(os.path.join(save_dir, f"drawn_{timestamp}.png"))
        mask_image.save(os.path.join(save_dir, f"generated_mask_{timestamp}.png"))

        print(f"🎨 Running Inference with strength=0.85...")
        image = sd_pipe(
            prompt=final_prompt,
            negative_prompt=negative_prompt,
            image=img_drawn,
            mask_image=mask_image,
            num_inference_steps=50,
            strength=0.85,
            guidance_scale=8.5,
        ).images[0]

        final_image_path = os.path.join(save_dir, f"result_{timestamp}.png")
        image.save(final_image_path)
        print(f"💾 Saved output to {final_image_path}")

        return jsonify({"status": "success", "image": encode_image_to_base64(image)})

    except Exception as e:
        print(f"❌ Inpainting Error: {e}")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/asset", methods=["POST"])
@secure_endpoint
def remove_background():
    if not birefnet_model:
        return jsonify({"error": "BiRefNet not loaded"}), 500
    try:
        data = request.get_json()
        image_b64 = data.get("image")
        if not image_b64:
            return jsonify({"error": "No image provided"}), 400

        original_image = decode_base64_image(image_b64)
        orig_w, orig_h = original_image.size

        input_tensor = transform_birefnet(original_image).unsqueeze(0).to(DEVICE)
        if DEVICE == "cuda":
            input_tensor = input_tensor.half()

        print("✂️ Removing background...")
        with torch.no_grad():
            preds = birefnet_model(input_tensor)

        mask_pil = process_birefnet_output(preds, (orig_w, orig_h))
        original_image.putalpha(mask_pil)

        return jsonify(
            {"status": "success", "image": encode_image_to_base64(original_image)}
        )
    except Exception as e:
        print(f"❌ Error: {e}")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/describe", methods=["POST"])
@secure_endpoint
def describe_image():
    if not florence_model or not florence_processor:
        return jsonify({"error": "Florence-2 not loaded"}), 500
    try:
        data = request.get_json()
        image_b64 = data.get("image")
        prompt_type = data.get("prompt", "<DETAILED_CAPTION>")

        if not image_b64:
            return jsonify({"error": "No image provided"}), 400

        image = decode_base64_image(image_b64)
        print(f"👁️ Analyzing image with Florence-2...")

        inputs = florence_processor(
            text=prompt_type, images=[image], return_tensors="pt"
        )
        inputs["pixel_values"] = inputs["pixel_values"].to(DEVICE, torch.float16)
        inputs["input_ids"] = inputs["input_ids"].to(DEVICE)

        generated_ids = florence_model.generate(
            input_ids=inputs["input_ids"],
            pixel_values=inputs["pixel_values"],
            max_new_tokens=128,
            num_beams=1,
            do_sample=False,
            use_cache=False,
        )

        generated_text = florence_processor.batch_decode(
            generated_ids, skip_special_tokens=False
        )[0]
        cleaned_text = (
            generated_text.replace(prompt_type, "")
            .replace("</s>", "")
            .replace("<s>", "")
            .strip()
        )

        if cleaned_text and cleaned_text[-1] not in [".", "!", "?"]:
            last_dot = cleaned_text.rfind(".")
            last_excl = cleaned_text.rfind("!")
            last_ques = cleaned_text.rfind("?")
            cut_off = max(last_dot, last_excl, last_ques)
            if cut_off != -1:
                cleaned_text = cleaned_text[: cut_off + 1]

        final_answer = cleaned_text
        print(final_answer)

        if "<loc_" in cleaned_text or "<poly_" in cleaned_text:
            try:
                parsed = florence_processor.post_process_generation(
                    generated_text,
                    task=prompt_type,
                    image_size=(image.width, image.height),
                )
                if isinstance(parsed, dict) and prompt_type in parsed:
                    final_answer = parsed[prompt_type]
                else:
                    final_answer = parsed
            except Exception:

                def parse_loc_manually(text, w, h):
                    locs = re.findall(r"<loc_(\d+)>", text)
                    if locs and len(locs) % 4 == 0:
                        bboxes = []
                        for i in range(0, len(locs), 4):
                            x1 = int(int(locs[i]) / 1000 * w)
                            y1 = int(int(locs[i + 1]) / 1000 * h)
                            x2 = int(int(locs[i + 2]) / 1000 * w)
                            y2 = int(int(locs[i + 3]) / 1000 * h)
                            bboxes.append([x1, y1, x2, y2])
                        clean_text = re.sub(r"<loc_\d+>", "", text).strip()
                        return {"text": clean_text, "bboxes": bboxes}
                    return text

                final_answer = parse_loc_manually(
                    cleaned_text, image.width, image.height
                )

        return jsonify({"status": "success", "output": final_answer})

    except Exception as e:
        print(f"❌ Florence Error: {e}")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/inpainting-api", methods=["POST"])
@secure_endpoint
def inpainting_api_fal():
    if not FAL_AVAILABLE:
        return jsonify({"error": "Fal.ai client not installed or API Key missing"}), 500

    try:
        data = request.get_json()

        clean_b64 = data.get("image")
        drawn_b64 = data.get("mask_image")
        prompt = data.get(
            "prompt",
            "The image shows a river running through a lush green valley surrounded by trees, plants, grass, and poles. In the background, the sky is filled with clouds, creating a peaceful atmosphere.",
        )

        if not clean_b64 or not drawn_b64:
            return (
                jsonify({"error": "Missing 'image' (clean) or 'mask_image' (drawn)"}),
                400,
            )

        print(f"📥 Received Request: Prompt='{prompt}'")

        # 1. Decode Images
        raw_clean = decode_base64_image(clean_b64).convert("RGB")
        raw_drawn = decode_base64_image(drawn_b64).convert("RGB")

        # 2. Resize maintaining Aspect Ratio (Max 1024 for Flux)
        img_clean = resize_to_limit(raw_clean, max_dim=1024)
        # Resize drawn to match exactly
        img_drawn = raw_drawn.resize(img_clean.size)

        # 3. Setup Debug Directory
        debug_dir = "debug_fal"
        os.makedirs(debug_dir, exist_ok=True)
        unique_id = str(int(time.time()))

        clean_path = os.path.join(debug_dir, f"fal_clean_{unique_id}.png")
        mask_path = os.path.join(debug_dir, f"fal_mask_{unique_id}.png")
        fal_result_path = os.path.join(debug_dir, f"fal_result_{unique_id}.png")

        # 4. Mask Generation
        print(f"🛠️ Generating mask (Size: {img_clean.size})...")
        clean_blur = np.array(
            img_clean.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16
        )
        drawn_blur = np.array(
            img_drawn.filter(ImageFilter.GaussianBlur(2)), dtype=np.int16
        )

        diff_arr = np.abs(drawn_blur - clean_blur)
        mask_arr = np.max(diff_arr, axis=2)
        mask_binary = mask_arr > 30

        white_pixels = np.sum(mask_binary)
        print(f"📊 Mask Stats: {white_pixels} changed pixels detected.")
        if white_pixels < 10:
            print("⚠️ WARNING: Mask is almost empty!")

        mask_filled = scipy.ndimage.binary_fill_holes(mask_binary)
        mask = Image.fromarray((mask_filled * 255).astype(np.uint8))
        mask = mask.filter(ImageFilter.MaxFilter(9))

        # 5. Save Inputs for Inspection
        mask.save(mask_path)
        img_clean.save(clean_path)
        print(f"✅ Saved debug images to: {debug_dir}/")

        # 6. Run Fal.ai
        print("🚀 Uploading images to Fal.ai...")
        image_url = fal_client.upload_file(clean_path)
        mask_url = fal_client.upload_file(mask_path)

        print("⚡ Running Flux Dev Fill...")
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
        print("📡 Fal Response:", result)

        if "images" in result and len(result["images"]) > 0:
            output_url = result["images"][0]["url"]
            print(f"✨ Downloading Result: {output_url}")

            response = requests.get(output_url)
            if response.status_code == 200:
                result_img = Image.open(io.BytesIO(response.content)).convert("RGB")

                # Save Debug Output
                result_img.save(fal_result_path)
                print(f"💾 Saved final output to {fal_result_path}")

                return jsonify(
                    {"status": "success", "image": encode_image_to_base64(result_img)}
                )
            else:
                print(f"❌ Failed to download image. Status: {response.status_code}")
                return (
                    jsonify(
                        {"status": "error", "message": "Failed to download Fal output"}
                    ),
                    500,
                )
        else:
            print("❌ API returned no images.")
            return (
                jsonify(
                    {
                        "status": "error",
                        "message": "Fal.ai returned no images",
                        "details": result,
                    }
                ),
                500,
            )

    except Exception as e:
        print(f"❌ Error in /inpainting-api: {e}")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/sketch-api", methods=["POST"])
@secure_endpoint
def sketch_api():
    if not FAL_AVAILABLE:
        return jsonify({"error": "Fal.ai client not installed or API Key missing"}), 500

    try:
        data = request.get_json()
        prompt = data.get("prompt")
        option = data.get("option", 1)

        if not prompt:
            return jsonify({"error": "Missing prompt"}), 400

        # --- ENFORCE SHARPNESS IN PROMPT ---
        enhanced_prompt = (
            f"{prompt}, sharp focus, high definition, 4k, vector art, crisp lines"
        )

        if int(option) == 1:
            # Nano Banana
            print(f"🍌 Using Nano Banana for: {prompt}")
            model_id = "fal-ai/nano-banana"
            arguments = {
                "prompt": enhanced_prompt,
                "num_images": 1,
                "aspect_ratio": "1:1",
                "output_format": "png",
            }
        elif int(option) == 2:
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
        else:
            return (
                jsonify(
                    {"error": "Invalid option. Use 1 for Nano Banana, 2 for Flux Dev."}
                ),
                400,
            )

        # Execute request
        handler = fal_client.submit(model_id, arguments=arguments)
        result = handler.get()
        print("📡 Fal Response:", result)

        if "images" in result and len(result["images"]) > 0:
            image_url = result["images"][0]["url"]
            print(f"✨ Success! Image generated: {image_url}")

            response = requests.get(image_url)
            if response.status_code == 200:
                img = Image.open(io.BytesIO(response.content)).convert("RGB")
                return jsonify(
                    {"status": "success", "image": encode_image_to_base64(img)}
                )
            else:
                return (
                    jsonify(
                        {
                            "status": "error",
                            "message": "Failed to download image from Fal",
                        }
                    ),
                    500,
                )
        else:
            return (
                jsonify({"status": "error", "message": "No images returned from Fal"}),
                500,
            )

    except Exception as e:
        print(f"❌ Error in /sketch-api: {e}")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

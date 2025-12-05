"""
Lighting
Original file: https://colab.research.google.com/drive/1edtbuTtWprRBw_lOvGJuEEDu5HGc-KA3
"""

!pip install git+https://github.com/openai/CLIP.git --q
!pip install torch torchvision pillow --q

## Build Text Bank

import torch
import clip
from PIL import Image
import numpy as np

LIGHTING_CLASSES = [
    "soft-light",
    "specular-highlights",
    "backlit",
    "studio-lighting",
    "flat-lighting",
    "dramatic-contrast",
    "diffused",
]

LIGHTING_PHRASES = {
    "soft-light": "soft light",
    "specular-highlights": "strong specular highlights",
    "backlit": "backlit lighting from behind the subject",
    "studio-lighting": "professional studio lighting",
    "flat-lighting": "flat, low-contrast lighting",
    "dramatic-contrast": "dramatic high-contrast lighting",
    "diffused": "soft diffused lighting with low shadows",
}

PROMPT_TEMPLATES = [
    "a photo with {}",
    "a portrait lit with {}",
    "a high quality photograph with {}",
    "a cinematic shot using {}",
    "an image captured in {}",
    "a studio photo with {}",
    "a product photo taken with {}",
    "a landscape scene under {}",
    "a close-up shot with {}",
    "a professional photography setup using {}",
]


device = "cuda" if torch.cuda.is_available() else "cpu"
model, preprocess = clip.load("ViT-B/32", device=device)


def build_text_bank(output_path="lighting_text_bank.npz"):
    all_prompt_texts = []
    all_prompt_labels = []
    all_prompt_features = []

    class_centroids = []

    with torch.no_grad():
        for lighting in LIGHTING_CLASSES:
            phrase = LIGHTING_PHRASES[lighting]

            prompts = [tpl.format(phrase) for tpl in PROMPT_TEMPLATES]

            tokens = clip.tokenize(prompts).to(device)
            text_features = model.encode_text(tokens)
            text_features = text_features / text_features.norm(dim=-1, keepdim=True)

            all_prompt_texts.extend(prompts)
            all_prompt_labels.extend([lighting] * len(prompts))
            all_prompt_features.append(text_features.cpu().numpy())

            centroid = text_features.mean(dim=0)
            centroid = centroid / centroid.norm()
            class_centroids.append(centroid.cpu().numpy())

    all_prompt_features = np.concatenate(all_prompt_features, axis=0)
    class_centroids = np.stack(class_centroids, axis=0)

    np.savez(
        output_path,
        prompt_texts=np.array(all_prompt_texts),
        prompt_labels=np.array(all_prompt_labels),
        prompt_features=all_prompt_features,
        class_centroids=class_centroids,
        class_names=np.array(LIGHTING_CLASSES),
    )
    print(f"Saved text bank to {output_path}")


if __name__ == "__main__":
    build_text_bank()


## Classify Lighting

import numpy as np
import torch
import clip
from PIL import Image


def get_image_embedding(image_path: str) -> torch.Tensor:
    image = Image.open(image_path).convert("RGB")
    img_tensor = preprocess(image).unsqueeze(0).to(device)

    with torch.no_grad():
        img_feat = model.encode_image(img_tensor)
        img_feat = img_feat / img_feat.norm(dim=-1, keepdim=True)

    return img_feat.squeeze(0)


def load_text_bank(path="lighting_text_bank.npz"):
    data = np.load(path, allow_pickle=True)
    centroids = data["class_centroids"]
    class_names = list(data["class_names"])
    centroids = centroids / np.linalg.norm(centroids, axis=1, keepdims=True)
    return centroids, class_names


def classify_lighting(
    image_path: str, text_bank_path="lighting_text_bank.npz", threshold: float = 0.25
):
    centroids, class_names = load_text_bank(text_bank_path)

    img_feat = get_image_embedding(image_path)
    img_np = img_feat.cpu().numpy()[None, :]

    sims = img_np @ centroids.T
    sims = sims.squeeze(0)

    sorted_indices = np.argsort(sims)[::-1]

    top_n = 3
    results = []
    for i in range(min(top_n, len(class_names))):
        idx = sorted_indices[i]
        lighting_style = class_names[idx]
        similarity = float(sims[idx])
        results.append({"lighting_style": lighting_style, "similarity": similarity})

    return results


if __name__ == "__main__":
    img_path = "/content/test.png"
    result = classify_lighting(img_path)
    print(result)

## Demo Runner

!pip install ftfy regex tqdm

import torch
import clip
from PIL import Image
import numpy as np

device = "cuda" if torch.cuda.is_available() else "cpu"
model, preprocess = clip.load("ViT-B/32", device=device)

print("Device:", device)

LIGHTING_CLASSES = [
    "soft-light",
    "specular-highlights",
    "backlit",
    "studio-lighting",
    "flat-lighting",
    "dramatic-contrast",
    "diffused",
]


LIGHTING_PHRASES = {
    "soft-light": "soft light",
    "specular-highlights": "strong specular highlights",
    "backlit": "backlit lighting from behind the subject",
    "studio-lighting": "professional studio lighting",
    "flat-lighting": "flat, low-contrast lighting",
    "dramatic-contrast": "dramatic high-contrast lighting",
    "diffused": "soft diffused lighting with low shadows",
}


PROMPT_TEMPLATES = [
    "a photo with {}",
    "a portrait lit with {}",
    "a high quality photograph with {}",
    "a cinematic shot using {}",
    "an image captured in {}",
    "a studio photo with {}",
    "a product photo taken with {}",
    "a landscape scene under {}",
    "a close-up shot with {}",
    "a professional photography setup using {}",
]


def build_text_bank(output_path="lighting_text_bank.npz"):
    all_prompt_texts = []
    all_prompt_labels = []
    all_prompt_features = []

    class_centroids = []

    model.eval()
    with torch.no_grad():
        for lighting in LIGHTING_CLASSES:
            phrase = LIGHTING_PHRASES[lighting]

            prompts = [tpl.format(phrase) for tpl in PROMPT_TEMPLATES]
            tokens = clip.tokenize(prompts).to(device)

            text_features = model.encode_text(tokens)
            text_features = text_features / text_features.norm(dim=-1, keepdim=True)

            all_prompt_texts.extend(prompts)
            all_prompt_labels.extend([lighting] * len(prompts))
            all_prompt_features.append(text_features.cpu().numpy())

            centroid = text_features.mean(dim=0)
            centroid = centroid / centroid.norm()
            class_centroids.append(centroid.cpu().numpy())

    all_prompt_features = np.concatenate(all_prompt_features, axis=0)
    class_centroids = np.stack(class_centroids, axis=0)

    np.savez(
        output_path,
        prompt_texts=np.array(all_prompt_texts),
        prompt_labels=np.array(all_prompt_labels),
        prompt_features=all_prompt_features,
        class_centroids=class_centroids,
        class_names=np.array(LIGHTING_CLASSES),
    )
    print(f"Saved text bank → {output_path}")


build_text_bank()


def get_image_embedding(image_path: str) -> torch.Tensor:
    image = Image.open(image_path).convert("RGB")
    img_tensor = preprocess(image).unsqueeze(0).to(device)

    model.eval()
    with torch.no_grad():
        img_feat = model.encode_image(img_tensor)
        img_feat = img_feat / img_feat.norm(dim=-1, keepdim=True)

    return img_feat.squeeze(0)


DEFAULT_THRESHOLD = 0.28


def load_text_bank(path="lighting_text_bank.npz"):
    bank = np.load(path, allow_pickle=True)
    centroids = torch.tensor(bank["class_centroids"]).to(device)
    class_names = bank["class_names"]

    centroids = centroids / centroids.norm(dim=-1, keepdim=True)
    return centroids, class_names


def classify_lighting(image_path, threshold=DEFAULT_THRESHOLD):
    img_feat = get_image_embedding(image_path).to(device)

    centroids, class_names = load_text_bank()

    img_feat = img_feat.to(centroids.dtype)

    img_feat = img_feat / img_feat.norm()

    sims = centroids @ img_feat
    best_score, best_idx = torch.max(sims, dim=0)

    best_score = float(best_score.detach().cpu())
    sims_list = sims.detach().cpu().tolist()

    sims_dict = {str(cls): float(s) for cls, s in zip(class_names, sims_list)}

    if best_score < threshold:
        predicted = "no_specific_lighting"
    else:
        predicted = str(class_names[best_idx])

    return predicted, best_score, sims_dict


# Runner

from google.colab import files

uploaded = files.upload()

image_path = list(uploaded.keys())[0]

pred, score, sims = classify_lighting(image_path)

print("Prediction:", pred)
print("Best score:", score)
print("\nAll similarities:")
for k, v in sims.items():
    print(f"{k:20s}: {v:.3f}")

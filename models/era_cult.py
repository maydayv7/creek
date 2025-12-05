"""
Era / Cultural Reference
Original file: https://colab.research.google.com/drive/15k15A0X38sOgwqGR5j7QhDBS8_61R_ca
"""

!pip install git+https://github.com/openai/CLIP.git --q
!pip install torch torchvision ftfy regex tqdm --q

import torch
import clip
from PIL import Image
import numpy as np
from google.colab import files
import io

device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Using device: {device}")

model, preprocess = clip.load("ViT-B/32", device=device)

ERA_CLASSES = [
    "vintage-60s",
    "modern",
    "90s-magazine",
    "art-deco",
    "punk",
    "avant-garde",
]

ERA_DESCRIPTIONS = {
    "vintage-60s": "1960s aesthetic, psychedelic art, mod fashion, kodachrome film look, flower power era",
    "modern": "modern contemporary aesthetic, clean design, digital photography, high resolution, 21st century style",
    "90s-magazine": "1990s fashion magazine style, grunge aesthetic, harsh flash photography, teen vogue 90s, glossy editorial",
    "art-deco": "art deco style, 1920s geometric patterns, gold and black luxury, great gatsby aesthetic, streamline moderne",
    "punk": "punk rock aesthetic, diy zine style, xeroxed textures, safety pins, rebellious and chaotic visual style",
    "avant-garde": "avant-garde fashion, experimental art, high concept, unconventional silhouette, futuristic and edgy",
}

PROMPT_TEMPLATES = [
    "a photo representing the {} aesthetic",
    "artistic rendering in {} style",
    "an image from the {} era",
    "visuals depicting {}",
    "a high quality example of {} culture",
    "a magazine scan showing {}",
    "fashion photography in the style of {}",
    "a poster with {} design elements",
]


class EraClassifier:
    def __init__(self):
        self.centroids = None
        self.class_names = ERA_CLASSES
        self.build_text_features()

    def build_text_features(self):
        """
        Pre-computes the embedding centroids for all eras.
        """
        print("Building text embeddings for eras...")
        class_centroids = []

        with torch.no_grad():
            for label in self.class_names:
                desc = ERA_DESCRIPTIONS[label]

                prompts = [tpl.format(desc) for tpl in PROMPT_TEMPLATES]

                tokens = clip.tokenize(prompts).to(device)
                text_features = model.encode_text(tokens)

                text_features = text_features / text_features.norm(dim=-1, keepdim=True)

                centroid = text_features.mean(dim=0)
                centroid = centroid / centroid.norm()

                class_centroids.append(centroid)

        self.centroids = torch.stack(class_centroids).to(device)
        print("Text embeddings built successfully.")

    def predict(self, image_path, threshold=0.20):
        image = Image.open(image_path).convert("RGB")
        img_tensor = preprocess(image).unsqueeze(0).to(device)

        with torch.no_grad():
            img_feat = model.encode_image(img_tensor)
            img_feat = img_feat / img_feat.norm(dim=-1, keepdim=True)

        similarity = 100.0 * img_feat @ self.centroids.T

        probs = similarity.softmax(dim=-1).cpu().numpy()[0]
        raw_scores = similarity.cpu().numpy()[0] / 100.0

        results = []
        for i, label in enumerate(self.class_names):
            results.append(
                {
                    "label": label,
                    "score": float(raw_scores[i]),
                    "confidence_pct": float(probs[i] * 100),
                }
            )

        results.sort(key=lambda x: x["score"], reverse=True)
        top_result = results[0]

        if top_result["score"] < threshold:
            prediction = "undefined/mixed"
        else:
            prediction = top_result["label"]

        return prediction, results


# Runner

classifier = EraClassifier()

print("\nPlease upload an image to analyze...")
uploaded = files.upload()

if len(uploaded) > 0:
    img_path = list(uploaded.keys())[0]

    prediction, details = classifier.predict(img_path)

    print("\n" + "=" * 30)
    print(f"PREDICTED ERA: {prediction.upper()}")
    print("=" * 30)

    print(f"\nDetailed Breakdown:")
    print(f"{'Era/Style':<15} | {'Cosine Sim':<12} | {'Rel Confidence':<15}")
    print("-" * 45)

    for item in details:
        print(
            f"{item['label']:<15} | {item['score']:.4f}       | {item['confidence_pct']:.1f}%"
        )

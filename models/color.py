"""
Color
Original file: https://colab.research.google.com/drive/1o7cMSAesuuaxFQsteQL4ViwL_qNeTWbm
"""

import cv2
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from sklearn.cluster import KMeans
from google.colab import files
from PIL import Image
import io


def get_dominant_colors(image, k=5):
    """
    Extracts dominant colors using KMeans.
    Expects a PIL Image or Numpy array (RGB).
    """
    if isinstance(image, Image.Image):
        image = np.array(image)

    img_small = cv2.resize(image, (150, 150), interpolation=cv2.INTER_AREA)

    pixels = img_small.reshape((-1, 3))

    kmeans = KMeans(n_clusters=k, n_init="auto", random_state=42)
    kmeans.fit(pixels)

    colors = kmeans.cluster_centers_.astype(int)

    return sorted(colors.tolist(), key=lambda x: sum(x))


def classify_mood(rgb_colors):
    """
    Classifies mood based on HSV values using Matplotlib colors.
    """
    norm_colors = np.array(rgb_colors) / 255.0

    hsv_stats = mcolors.rgb_to_hsv(norm_colors)

    avg_sat = np.mean(hsv_stats[:, 1])
    avg_val = np.mean(hsv_stats[:, 2])

    if avg_sat < 0.15 and avg_val > 0.65:
        return "Minimalist"
    if avg_val < 0.35:
        return "Dark/Moody"
    if avg_sat < 0.45 and avg_val > 0.75:
        return "Pastel"
    if avg_sat > 0.65 and avg_val > 0.5:
        return "Neon"

    earthy_votes = sum(1 for h, s, v in hsv_stats if (0.02 <= h <= 0.42) and s < 0.8)
    if earthy_votes >= 3:
        return "Earthy"

    warm_votes = sum(1 for h, s, v in hsv_stats if h < 0.17 or h > 0.83)
    return "Warm" if warm_votes >= 3 else "Cool"


def rgb_to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(rgb[0], rgb[1], rgb[2])


# Runner


def analyze_uploaded_image():
    print("Please upload an image file...")
    uploaded = files.upload()

    for fn in uploaded.keys():
        print(f"\nProcessing {fn}...")

        image_data = uploaded[fn]
        image = Image.open(io.BytesIO(image_data)).convert("RGB")

        colors = get_dominant_colors(image)
        if colors is None:
            print("Error processing image.")
            continue

        mood = classify_mood(colors)
        hex_colors = [rgb_to_hex(c) for c in colors]

        print(f"Detected Mood: {mood}")
        print("Extracted Palette:")
        print("-" * 30)
        for i, h in enumerate(hex_colors):
            print(f"Color {i+1}: {h}")
        print("-" * 30)

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4))

        ax1.imshow(image)
        ax1.axis("off")
        ax1.set_title(f"Mood: {mood}", fontweight="bold")

        y_pos = np.arange(len(colors))
        ax2.barh(y_pos, [1] * len(colors), color=hex_colors)
        ax2.invert_yaxis()
        ax2.axis("off")

        for i, h in enumerate(hex_colors):
            brightness = sum(colors[i]) / 3
            text_col = "black" if brightness > 128 else "white"
            ax2.text(
                0.5,
                i,
                f"{h}",
                ha="center",
                va="center",
                color=text_col,
                fontweight="bold",
                fontsize=12,
            )

        plt.tight_layout()
        plt.show()


if __name__ == "__main__":
    analyze_uploaded_image()

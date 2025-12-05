import sys
import json
import traceback
import numpy as np
import cv2
from sklearn.cluster import KMeans

# ==========================================
# HELPER FUNCTIONS
# ==========================================


def get_dominant_colors(img_rgb, k=5):
    """
    Extracts dominant colors using KMeans.
    Expects a Numpy array (RGB).
    """
    # Resize to speed up processing
    img_small = cv2.resize(img_rgb, (150, 150), interpolation=cv2.INTER_AREA)

    # Reshape to a list of pixels
    pixels = img_small.reshape((-1, 3))

    # KMeans Clustering
    kmeans = KMeans(n_clusters=k, n_init=10, random_state=42)
    kmeans.fit(pixels)
    colors = kmeans.cluster_centers_.astype(int)

    # Sort by brightness (Sum of RGB channels)
    return sorted(colors.tolist(), key=lambda x: sum(x))


def classify_mood(rgb_colors):
    """
    Classifies mood based on HSV values.
    Adapted to use OpenCV instead of Matplotlib to reduce APK size and dependencies.
    """
    # Normalize RGB values to 0-1 range (Float32 required for CV2 conversion)
    norm_colors = np.array(rgb_colors, dtype=np.float32) / 255.0

    # Reshape to (1, N, 3) image format for cv2.cvtColor
    img_reshaped = norm_colors.reshape(1, -1, 3)

    # Convert RGB to HSV
    # OpenCV with float32 input returns: H[0-360], S[0-1], V[0-1]
    hsv_img = cv2.cvtColor(img_reshaped, cv2.COLOR_RGB2HSV)
    hsv_stats = hsv_img[0]  # Shape (N, 3)

    # Normalize Hue to 0-1 range to match original logic (Matplotlib uses 0-1)
    hsv_stats[:, 0] /= 360.0

    # Extract averages
    # hsv_stats structure is [Hue, Saturation, Value]
    avg_sat = np.mean(hsv_stats[:, 1])
    avg_val = np.mean(hsv_stats[:, 2])

    # Logic Rules
    if avg_sat < 0.15 and avg_val > 0.65:
        return "Minimalist"
    if avg_val < 0.35:
        return "Dark/Moody"
    if avg_sat < 0.45 and avg_val > 0.75:
        return "Pastel"
    if avg_sat > 0.65 and avg_val > 0.5:
        return "Neon"

    # Earthy logic: Hue between 0.02 and 0.42 (approx 7 to 150 deg), low saturation
    earthy_votes = sum(1 for p in hsv_stats if (0.02 <= p[0] <= 0.42) and p[1] < 0.8)
    if earthy_votes >= 3:
        return "Earthy"

    # Warm/Cool logic: Warm is usually red/orange/yellow (low Hue or very high Hue)
    warm_votes = sum(1 for p in hsv_stats if p[0] < 0.17 or p[0] > 0.83)
    return "Warm" if warm_votes >= 3 else "Cool"


def rgb_to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(rgb[0], rgb[1], rgb[2])


# ==========================================
# MAIN API
# ==========================================


def analyze_color_style(image_path):
    try:
        # 1. Load Image
        # OpenCV reads in BGR by default
        img_bgr = cv2.imread(image_path)
        if img_bgr is None:
            return json.dumps(
                {"success": False, "scores": {}, "error": "CV2 could not read image"}
            )

        # Convert to RGB
        img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)

        # 2. Extract Colors
        colors = get_dominant_colors(img_rgb)

        # 3. Classify Mood
        mood = classify_mood(colors)

        # 4. Format Results
        hex_colors = [rgb_to_hex(c) for c in colors]

        response = {
            "success": True,
            # Return the mood as a score of 1.0 for compatibility
            "scores": {mood: 1.0},
            "palette": hex_colors,
            "error": None,
        }

        return json.dumps(response)

    except Exception as e:
        return json.dumps(
            {
                "success": False,
                "scores": {},
                "error": f"Python Exception: {str(e)} | {traceback.format_exc()}",
            }
        )

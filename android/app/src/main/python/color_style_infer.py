import os
import sys
import json
import traceback
import numpy as np
import cv2
import joblib

# --- Global Cache ---
_MODEL_DATA = None

class NumpyEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (np.integer, int)):
            return int(obj)
        elif isinstance(obj, (np.floating, float)):
            return float(obj)
        elif isinstance(obj, np.ndarray):
            return obj.tolist()
        return super(NumpyEncoder, self).default(obj)

def _load_model_if_needed():
    global _MODEL_DATA
    if _MODEL_DATA is not None:
        return _MODEL_DATA

    try:
        base_dir = os.path.dirname(__file__)
        model_path = os.path.join(base_dir, "color_style_model.joblib")
        if os.path.exists(model_path):
            _MODEL_DATA = joblib.load(model_path)
    except Exception as e:
        print(f"Error loading model: {e}")
    return _MODEL_DATA

# --- Feature Extraction Helpers ---
def compute_color_features(bgr):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    H, S, V = cv2.split(hsv)
    L, A, B = cv2.split(lab)

    def stats(x):
        x = x.astype(np.float32) / 255.0
        return float(x.mean()), float(x.std()), float(np.percentile(x, 1)), float(np.percentile(x, 99))

    color = {}

    # Lightness / brightness
    mean_L, std_L, p1_L, p99_L = stats(L)
    color.update({"mean_L": mean_L, "std_L": std_L, "p1_L": p1_L, "p99_L": p99_L})

    # Saturation
    mean_S, std_S, p1_S, p99_S = stats(S)
    color.update({"mean_S": mean_S, "std_S": std_S, "p1_S": p1_S, "p99_S": p99_S})

    # Value / luminance
    mean_V, std_V, p1_V, p99_V = stats(V)
    color.update({"mean_V": mean_V, "std_V": std_V, "p1_V": p1_V, "p99_V": p99_V})

    # Hue stats
    Hf = H.astype(np.float32) * 2.0
    rad = np.deg2rad(Hf)
    sin_mean, cos_mean = np.sin(rad).mean(), np.cos(rad).mean()
    hue_mean_deg = np.rad2deg(np.arctan2(sin_mean, cos_mean)) % 360
    R = np.sqrt(sin_mean**2 + cos_mean**2)
    hue_dispersion = float(1 - R)
    color.update({"hue_mean_deg": float(hue_mean_deg), "hue_dispersion": hue_dispersion})

    # Colorfulness
    rg = (bgr[:, :, 2].astype(np.float32) - bgr[:, :, 1].astype(np.float32))
    yb = 0.5 * (bgr[:, :, 2].astype(np.float32) + bgr[:, :, 1].astype(np.float32)) - bgr[:, :, 0].astype(np.float32)
    sigma_rg, sigma_yb = rg.std(), yb.std()
    mean_rg, mean_yb = rg.mean(), yb.mean()
    colorfulness = np.sqrt(sigma_rg**2 + sigma_yb**2) + 0.3 * np.sqrt(mean_rg**2 + mean_yb**2)
    color["colorfulness"] = float(colorfulness)

    # Palette
    pixels = bgr.reshape(-1, 3).astype(np.float32)
    K = 5
    criteria = (cv2.TermCriteria_EPS + cv2.TermCriteria_MAX_ITER, 20, 1.0)
    _, _, centers = cv2.kmeans(pixels, K, None, criteria, 1, cv2.KMEANS_PP_CENTERS)
    color["palette_bgr"] = centers.astype(int).tolist()

    return color


def compute_editing_features(bgr):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    H, S, V = cv2.split(hsv)
    L, A, B = cv2.split(lab)

    feats = {}

    def stats(x):
        x = x.astype(np.float32) / 255.0
        return float(x.mean()), float(x.std()), float(np.percentile(x, 1)), float(np.percentile(x, 99))

    mean_V, std_V, p1_V, p99_V = stats(V)
    mean_S, std_S, p1_S, p99_S = stats(S)

    feats["brightness_mean"] = mean_V
    feats["brightness_range"] = p99_V - p1_V

    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    feats["contrast_rms"] = float(gray.std())
    feats["saturation_mean"] = mean_S
    feats["saturation_range"] = p99_S - p1_S
    feats["tint_a_mean"] = float(A.mean())
    feats["tint_b_mean"] = float(B.mean())

    Hf = H.astype(np.float32) * 2.0
    rad = np.deg2rad(Hf)
    sin_mean, cos_mean = np.sin(rad).mean(), np.cos(rad).mean()
    hue_mean_deg = np.rad2deg(np.arctan2(sin_mean, cos_mean)) % 360
    R = np.sqrt(sin_mean**2 + cos_mean**2)
    feats["hue_mean_deg"] = float(hue_mean_deg)
    feats["hue_dispersion"] = float(1 - R)

    patch_std = []
    step, k = 16, 16
    for y in range(0, gray.shape[0] - k + 1, step):
        for x in range(0, gray.shape[1] - k + 1, step):
            patch = gray[y:y + k, x:x + k]
            patch_std.append(patch.std())
    if len(patch_std) > 0:
        patch_std = np.array(patch_std)
        feats["local_contrast_mean"] = float(patch_std.mean())
        feats["local_contrast_std"] = float(patch_std.std())
    else:
        feats["local_contrast_mean"] = 0.0
        feats["local_contrast_std"] = 0.0

    return feats


def flatten_features(features_dict):
    flat_values = []
    # 1. Color Features
    color_feats = features_dict.get('color', {})
    for key, val in color_feats.items():
        if key == 'palette_bgr':
            flat_values.extend(np.array(val).flatten())
        else:
            flat_values.append(val)
    # 2. Editing Features
    edit_feats = features_dict.get('editing', {})
    for key, val in edit_feats.items():
        flat_values.append(val)
    return np.array(flat_values)


# --- Public API ---

def analyze_color_style(image_path):
    try:
        model_data = _load_model_if_needed()
        if model_data is None:
            return json.dumps({"success": False, "error": "Model failed to load"})

        if not os.path.exists(image_path):
            return json.dumps({"success": False, "error": f"Image not found at: {image_path}"})

        img = cv2.imread(image_path)
        if img is None:
            return json.dumps({"success": False, "error": "CV2 could not read image"})

        # Extract Features
        raw_features = {
            "color": compute_color_features(img),
            "editing": compute_editing_features(img)
        }

        flat_vector = flatten_features(raw_features)

        # Predict
        clf = model_data['model']
        le = model_data['encoder']

        probs = clf.predict_proba([flat_vector])[0]
        classes = le.classes_

        results = {}
        for c, p in zip(classes, probs):
            results[c] = float(p)

        sorted_features = sorted(results.items(), key=lambda x: x[1], reverse=True)
        response = {
            "success": True,
            "predictions": {k: float(v) for k, v in results.items()},
            "best": {sorted_features[0][0]: float(sorted_features[0][1])},
        }

        return json.dumps(response, cls=NumpyEncoder)

    except Exception as e:
        return json.dumps({"success": False, "error": f"Python Exception: {str(e)} | {traceback.format_exc()}"})

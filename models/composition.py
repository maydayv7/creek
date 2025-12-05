"""
Layout
Original file: https://colab.research.google.com/drive/1NzX6rAQSJkPTpdWWkOowDFlBpypoKl2U
"""

!pip install opencv-python numpy

import cv2
import numpy as np
import os
from math import hypot


def resize_for_fast_processing(img, max_side=640):
    h, w = img.shape[:2]
    scale = max_side / max(h, w) if max(h, w) > max_side else 1.0
    if scale != 1.0:
        img = cv2.resize(
            img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA
        )
    return img, scale


def compute_saliency_gray(img):
    sal = None
    try:
        salience = cv2.saliency.StaticSaliencySpectralResidual_create()
        success, sal = salience.computeSaliency(img)
        if not success:
            sal = None
    except Exception:
        sal = None
    if sal is None:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        blur1 = cv2.GaussianBlur(gray, (3, 3), 0)
        blur2 = cv2.GaussianBlur(gray, (21, 21), 0)
        sal = cv2.absdiff(blur1, blur2)
        sal = sal.astype(np.float32) / (sal.max() + 1e-9)
    else:
        sal = sal.astype(np.float32)
        if sal.max() > 0:
            sal /= sal.max()
    return sal


def saliency_centroid(sal):
    h, w = sal.shape
    M = sal.sum()
    if M <= 1e-6:
        return (w / 2, h / 2)
    ys, xs = np.indices(sal.shape)
    cx = (xs * sal).sum() / M
    cy = (ys * sal).sum() / M
    return (float(cx), float(cy))


def detect_lines(gray, canny_thresh1=50, canny_thresh2=150, hough_thresh=50):
    edges = cv2.Canny(gray, canny_thresh1, canny_thresh2)
    lines = cv2.HoughLinesP(
        edges,
        rho=1,
        theta=np.pi / 180,
        threshold=hough_thresh,
        minLineLength=min(gray.shape) // 10,
        maxLineGap=10,
    )
    if lines is None:
        return edges, []
    lines = [tuple(l[0]) for l in lines]
    return edges, lines


def project_sal_along_axis(sal, axis=0, smooth_k=15):
    proj = sal.sum(axis=1 - axis) if axis == 0 else sal.sum(axis=0)
    k = max(3, smooth_k)
    kernel = np.ones(k) / k
    proj_s = np.convolve(proj, kernel, mode="same")
    if proj_s.max() > 0:
        proj_s = proj_s / proj_s.max()
    return proj_s


def count_saliency_peaks_along_y(sal, min_sep_fraction=0.1, threshold=0.2):
    h, w = sal.shape
    proj = project_sal_along_axis(sal, axis=0, smooth_k=max(5, int(h * 0.03)))
    peaks = []
    for i in range(1, len(proj) - 1):
        if proj[i] > proj[i - 1] and proj[i] > proj[i + 1] and proj[i] > threshold:
            peaks.append(i)
    min_sep = int(min_sep_fraction * h)
    filtered = []
    for p in peaks:
        if not filtered or p - filtered[-1] >= min_sep:
            filtered.append(p)
    return len(filtered), filtered


def band_saliency_fractions(sal, bands=3):
    h, w = sal.shape
    sums = []
    total = sal.sum() + 1e-9
    for i in range(bands):
        band = sal[:, i * w // bands : (i + 1) * w // bands]
        sums.append(band.sum() / total)
    return sums


def sal_bbox_and_margins(sal, thresh=0.3):
    mask = sal > thresh
    if mask.sum() == 0:
        return (0, 0, 0, 0), None
    ys, xs = np.where(mask)
    minx, maxx = int(xs.min()), int(xs.max())
    miny, maxy = int(ys.min()), int(ys.max())
    return (minx, miny, maxx, maxy), mask


def component_bboxes_from_mask(mask):
    mask_u8 = mask.astype(np.uint8) * 255
    contours, _ = cv2.findContours(mask_u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    bboxes = []
    for c in contours:
        x, y, w, h = cv2.boundingRect(c)
        bboxes.append((x, y, x + w - 1, y + h - 1))
    return bboxes


def bbox_laplacian_variance(gray, bbox):
    x1, y1, x2, y2 = bbox
    roi = gray[y1 : y2 + 1, x1 : x2 + 1]
    if roi.size == 0:
        return 0.0
    lap = cv2.Laplacian(roi, cv2.CV_64F)
    return float(np.var(lap))


def _proj_and_peaks(sal, axis=0, smooth_k=15):
    proj = sal.sum(axis=1 - axis) if axis == 0 else sal.sum(axis=0)
    k = max(3, smooth_k)
    kernel = np.ones(k) / k
    proj_s = np.convolve(proj, kernel, mode="same")
    if proj_s.max() > 0:
        proj_s = proj_s / proj_s.max()
    return proj_s


def vertical_stack_score(sal, lines, min_peaks=2):
    h, w = sal.shape
    proj = _proj_and_peaks(sal, axis=0, smooth_k=max(5, int(h * 0.03)))
    peaks = [
        i
        for i in range(1, len(proj) - 1)
        if proj[i] > proj[i - 1] and proj[i] > proj[i + 1] and proj[i] > 0.18
    ]
    if len(peaks) == 0:
        return 0.0, {"peaks": 0}
    avg_peak = float(np.mean([proj[p] for p in peaks]))
    peak_count_score = min(1.0, len(peaks) / max(1.0, min_peaks))
    peak_prom_score = avg_peak
    h_lines = 0
    for x1, y1, x2, y2 in lines:
        dy = abs(y2 - y1)
        dx = abs(x2 - x1) + 1e-9
        slope = dy / dx
        if slope < 0.3 and abs(x2 - x1) > 0.6 * w:
            h_lines += 1
    sep_score = min(1.0, h_lines / 2.0)
    span_ok = 0
    for p in peaks:
        row = sal[max(0, p - 2) : min(h, p + 3), :]
        if row.sum() <= 1e-9:
            continue
        col_sum = row.sum(axis=0)
        frac_nonzero = (col_sum > (col_sum.max() * 0.05)).sum() / float(w)
        if frac_nonzero > 0.65:
            span_ok += 1
    span_score = min(1.0, span_ok / max(1.0, len(peaks)))
    score = (
        0.45 * peak_count_score
        + 0.25 * peak_prom_score
        + 0.15 * sep_score
        + 0.15 * span_score
    )
    return float(np.clip(score, 0.0, 1.0)), {
        "peaks": len(peaks),
        "avg_peak": avg_peak,
        "h_lines": h_lines,
        "span_ok": span_ok,
    }


def triptych_score(sal, lines):
    h, w = sal.shape
    total = sal.sum() + 1e-9
    bands = [sal[:, i * w // 3 : (i + 1) * w // 3].sum() / total for i in range(3)]
    mn, mx = min(bands), max(bands)
    balance = 1.0 - (mx - mn)
    balance = np.clip(balance, 0.0, 1.0)
    v_hits = 0
    for x1, y1, x2, y2 in lines:
        dx = abs(x2 - x1) + 1e-9
        dy = abs(y2 - y1)
        slope = dy / dx if dx > 1 else 1e9
        if slope > 3 and dy > 0.6 * h:
            cx = (x1 + x2) / 2
            if abs(cx - w / 3) < 0.08 * w or abs(cx - 2 * w / 3) < 0.08 * w:
                v_hits += 1
    line_score = np.tanh(v_hits / 2.0)
    band_floor = min(1.0, mn / 0.15)
    score = 0.55 * balance + 0.25 * line_score + 0.20 * band_floor
    return float(np.clip(score, 0.0, 1.0)), {"band_fracs": bands, "v_line_hits": v_hits}


def full_bleed_score(
    sal,
    img,
    edge_margin_frac=0.03,
    edge_sal_thresh=0.25,
    sal_bbox_thresh=0.2,
    white_thresh=245,
    white_frac_thresh=0.80,
    edge_sal_frac_thresh=0.50,
    bbox_touch_required=0.75,
):
    """
    Binary full-bleed detector (returns 0 or 1, plus info).
    - Rejects as full-bleed if a white margin/border is detected.
    - Uses saliency near edges and whether saliency bbox touches edges.
    """
    h, w = sal.shape
    m = max(1, int(min(h, w) * edge_margin_frac))

    mask_edge = np.zeros_like(sal, dtype=bool)
    mask_edge[:m, :] = True
    mask_edge[-m:, :] = True
    mask_edge[:, :m] = True
    mask_edge[:, -m:] = True
    edge_sal_frac = float((sal[mask_edge] > edge_sal_thresh).sum()) / (
        mask_edge.sum() + 1e-9
    )

    mask2 = sal > sal_bbox_thresh
    if mask2.sum() == 0:
        bbox_touch = 0.0
    else:
        ys, xs = np.where(mask2)
        minx, maxx = int(xs.min()), int(xs.max())
        miny, maxy = int(ys.min()), int(ys.max())
        touches = (
            int(minx <= 1) + int(maxx >= w - 2) + int(miny <= 1) + int(maxy >= h - 2)
        )
        bbox_touch = touches / 4.0

    band_top = img[:m, :, :] if m > 0 else np.zeros((0, w, 3), dtype=img.dtype)
    band_bottom = img[-m:, :, :] if m > 0 else np.zeros((0, w, 3), dtype=img.dtype)
    band_left = img[:, :m, :] if m > 0 else np.zeros((h, 0, 3), dtype=img.dtype)
    band_right = img[:, -m:, :] if m > 0 else np.zeros((h, 0, 3), dtype=img.dtype)

    border_pixels = np.concatenate(
        [
            band_top.reshape(-1, 3),
            band_bottom.reshape(-1, 3),
            band_left.reshape(-1, 3),
            band_right.reshape(-1, 3),
        ],
        axis=0,
    )
    if border_pixels.size == 0:
        white_border_frac = 0.0
    else:
        white_mask = np.all(border_pixels >= white_thresh, axis=1)
        white_border_frac = float(white_mask.sum()) / float(border_pixels.shape[0])

    border_std = float(np.std(border_pixels)) if border_pixels.size > 0 else 0.0
    border_uniform = border_std < 6.0  # small std => uniform border

    cond_edge_sal = edge_sal_frac >= edge_sal_frac_thresh
    cond_bbox_touch = bbox_touch >= bbox_touch_required

    is_full_bleed = (
        (cond_edge_sal or cond_bbox_touch)
        and (white_border_frac < white_frac_thresh)
        and (not (border_uniform and white_border_frac > 0.25))
    )

    score = 1 if is_full_bleed else 0

    info = {
        "edge_margin_px": m,
        "edge_sal_frac": edge_sal_frac,
        "edge_sal_thresh": edge_sal_thresh,
        "cond_edge_sal": cond_edge_sal,
        "bbox_touch": bbox_touch,
        "bbox_touch_required": bbox_touch_required,
        "white_border_frac": white_border_frac,
        "white_thresh": white_thresh,
        "white_frac_thresh": white_frac_thresh,
        "border_std": border_std,
        "border_uniform": border_uniform,
        "decision_full_bleed": bool(is_full_bleed),
    }
    return score, info


def tight_crop_score(sal, gray, sal_thresh=0.1):
    h, w = sal.shape
    mask = sal > sal_thresh
    if mask.sum() == 0:
        return 0.0, {"area_frac": 0.0, "tightness": 1.0}
    ys, xs = np.where(mask)
    minx, maxx = int(xs.min()), int(xs.max())
    miny, maxy = int(ys.min()), int(ys.max())
    bbox_area = (maxx - minx + 1) * (maxy - miny + 1)
    area_frac = bbox_area / float(w * h)
    left = minx
    right = w - 1 - maxx
    top = miny
    bottom = h - 1 - maxy
    tightness = min(left, right, top, bottom) / float(min(w, h) + 1e-9)
    area_score = np.clip((area_frac - 0.15) / (0.6 - 0.15), 0.0, 1.0)
    tight_score = 1.0 - np.clip(tightness / 0.08, 0.0, 1.0)
    score = 0.6 * area_score + 0.4 * tight_score
    return float(np.clip(score, 0.0, 1.0)), {
        "area_frac": area_frac,
        "tightness": tightness,
        "margins": (left, right, top, bottom),
    }


def layered_foreground_score(sal, gray):
    mask = (sal > 0.25).astype(np.uint8)
    kernel = np.ones((5, 5), np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    contours, _ = cv2.findContours(
        (mask * 255).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    bboxes = []
    sharpness = []
    for c in contours:
        x, y, w, h = cv2.boundingRect(c)
        if w * h < 0.005 * sal.size:
            continue
        bboxes.append((x, y, x + w - 1, y + h - 1))
        roi = gray[y : y + h, x : x + w]
        lap = cv2.Laplacian(roi, cv2.CV_64F)
        sharpness.append(float(np.var(lap)))
    n = len(bboxes)
    if n < 2:
        return 0.0, {"num_components": n}
    s = np.array(sharpness) + 1e-9
    s_norm = (s - s.mean()) / (s.std() + 1e-9)
    sharp_std = float(np.std(s_norm))
    overlaps = 0
    for i in range(len(bboxes)):
        for j in range(i + 1, len(bboxes)):
            a = bboxes[i]
            b = bboxes[j]
            ix1 = max(a[0], b[0])
            iy1 = max(a[1], b[1])
            ix2 = min(a[2], b[2])
            iy2 = min(a[3], b[3])
            if ix2 >= ix1 and iy2 >= iy1:
                inter = (ix2 - ix1 + 1) * (iy2 - iy1 + 1)
                area_a = (a[2] - a[0] + 1) * (a[3] - a[1] + 1)
                if inter > 0.05 * area_a:
                    overlaps += 1
    comp_score = np.clip((n - 1) / 4.0, 0, 1)
    sharp_score = np.tanh(sharp_std)
    overlap_score = np.tanh(overlaps / 2.0)
    score = 0.45 * comp_score + 0.35 * sharp_score + 0.20 * overlap_score
    return float(np.clip(score, 0.0, 1.0)), {
        "num_components": n,
        "sharp_std": sharp_std,
        "overlaps": overlaps,
    }


def balance_score(img_bgr, sal):
    img_lab = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = img_lab[:, :, 0] / 255.0
    img_hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    S = img_hsv[:, :, 1] / 255.0
    weight = sal * (L + 0.5 * S)
    M = weight.sum()
    h, w = sal.shape
    if M <= 1e-6:
        return 0.0
    ys, xs = np.indices(sal.shape)
    cx = (xs * weight).sum() / M
    cy = (ys * weight).sum() / M
    dx = abs(cx - w / 2) / (w / 2)
    dy = abs(cy - h / 2) / (h / 2)
    dist = np.sqrt(dx * dx + dy * dy) / np.sqrt(2)
    return float(max(0.0, 1.0 - dist * 1.4))


def symmetry_score(img_gray):
    h, w = img_gray.shape
    left = img_gray[:, : w // 2]
    right = img_gray[:, w - w // 2 :]
    right_flipped = cv2.flip(right, 1)
    if left.shape != right_flipped.shape:
        right_flipped = cv2.resize(right_flipped, (left.shape[1], left.shape[0]))
    leftf = left.astype(np.float32)
    rightf = right_flipped.astype(np.float32)
    if leftf.std() < 1e-3 or rightf.std() < 1e-3:
        return 0.0
    corr = np.corrcoef(leftf.flatten(), rightf.flatten())[0, 1]
    return float(max(0.0, min(1.0, (corr + 1) / 2)))


def thirds_score(sal, centroid):
    h, w = sal.shape
    cx, cy = centroid
    thirds_pts = [
        (w / 3, h / 3),
        (w / 3, 2 * h / 3),
        (2 * w / 3, h / 3),
        (2 * w / 3, 2 * h / 3),
    ]
    dists = [hypot(cx - x, cy - y) for (x, y) in thirds_pts]
    maxd = hypot(w, h)
    score = 1.0 - min(dists) / maxd * 1.2
    vline_dist = min(abs(cx - w / 3), abs(cx - 2 * w / 3)) / w
    hline_dist = min(abs(cy - h / 3), abs(cy - 2 * h / 3)) / h
    line_score = 1.0 - min(vline_dist, hline_dist)
    return float(max(0.0, min(1.0, 0.6 * score + 0.4 * line_score)))


def golden_ratio_score(sal, centroid):
    h, w = sal.shape
    gx = [0.382, 0.618]
    gy = [0.382, 0.618]
    cx, cy = centroid
    pts = [(g * w, g2 * h) for g in gx for g2 in gy]
    dists = [hypot(cx - x, cy - y) for x, y in pts]
    maxd = hypot(w, h)
    return float(max(0.0, min(1.0, 1.0 - min(dists) / (maxd * 0.9))))


def negative_space_score(sal):
    low = (sal < 0.15).sum() / sal.size
    return float(min(1.0, low))


def center_score(sal, centroid):
    h, w = sal.shape
    cx, cy = centroid
    dx = abs(cx - w / 2) / (w / 2)
    dy = abs(cy - h / 2) / (h / 2)
    dist = np.sqrt(dx * dx + dy * dy) / np.sqrt(2)
    return float(max(0.0, 1.0 - dist * 1.2))


def analyze_single_image(img_path):
    if not os.path.exists(img_path):
        print(f"Error: File not found at {img_path}")
        return

    img_full = cv2.imread(img_path)
    if img_full is None:
        print(f"Error: Could not load image. Check format.")
        return

    print(f"Analyzing: {os.path.basename(img_path)}...")

    img, scale = resize_for_fast_processing(img_full, max_side=640)
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    sal = compute_saliency_gray(img)
    if sal.shape != gray.shape:
        sal = cv2.resize(sal, (w, h), interpolation=cv2.INTER_LINEAR)
    centroid = saliency_centroid(sal)

    edges, lines = detect_lines(gray)
    _, thr = cv2.threshold(
        (gray).astype(np.uint8), 0, 255, cv2.THRESH_OTSU + cv2.THRESH_BINARY_INV
    )
    contours, _ = cv2.findContours(thr, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    composition_scores = {
        "Rule of Thirds": thirds_score(sal, centroid),
        "Golden Ratio": golden_ratio_score(sal, centroid),
        "Symmetry": symmetry_score(gray),
        "Negative Space": negative_space_score(sal),
        "Center Composition": center_score(sal, centroid),
    }

    v_score, v_info = vertical_stack_score(sal, lines)
    t_score, t_info = triptych_score(sal, lines)
    fb_score, fb_info = full_bleed_score(sal, img)
    tc_score, tc_info = tight_crop_score(sal, gray)
    lf_score, lf_info = layered_foreground_score(sal, gray)

    composition_scores["Vertical Stack"] = v_score
    composition_scores["Triptych"] = t_score
    composition_scores["Full Bleed"] = fb_score
    composition_scores["Tight Crop"] = tc_score
    composition_scores["Layered Foreground"] = lf_score

    print("-" * 40)
    print(f"Top Composition Scores:")
    sorted_comp = sorted(composition_scores.items(), key=lambda x: x[1], reverse=True)
    for k, v in sorted_comp[:10]:
        print(f"   - {k}: {v:.2f}")

    print("\n All Composition Scores:")
    for k, v in sorted_comp:
        print(f"   {k:<25} : {v:.3f}")
    print("-" * 40)

    diagnostics = {
        "Vertical Stack_info": v_info,
        "Triptych_info": t_info,
        "Full Bleed_info": fb_info,
        "Tight Crop_info": tc_info,
        "Layered Foreground_info": lf_info,
    }


# Runner

if __name__ == "__main__":
    target_image_path = "/content/test.png"
    analyze_single_image(target_image_path)

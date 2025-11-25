import cv2
import numpy as np
import os
import json
from math import hypot

# ==========================================
# 1. HELPER FUNCTIONS
# ==========================================

def resize_for_fast_processing(img, max_side=640):
    h, w = img.shape[:2]
    scale = max_side / max(h, w) if max(h, w) > max_side else 1.0
    if scale != 1.0:
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    return img, scale

def compute_saliency_gray(img):
    sal = None
    try:
        salience = cv2.saliency.StaticSaliencySpectralResidual_create()
        success, sal = salience.computeSaliency(img)
        if not success: sal = None
    except Exception:
        sal = None
    if sal is None:
        # Fallback: Simple Gaussian Difference
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        blur1 = cv2.GaussianBlur(gray, (3, 3), 0)
        blur2 = cv2.GaussianBlur(gray, (21, 21), 0)
        sal = cv2.absdiff(blur1, blur2)
        sal = sal.astype(np.float32) / (sal.max() + 1e-9)
    else:
        sal = sal.astype(np.float32)
        if sal.max() > 0: sal /= sal.max()
    return sal

def saliency_centroid(sal):
    h, w = sal.shape
    M = sal.sum()
    if M <= 1e-6: return (w / 2, h / 2)
    ys, xs = np.indices(sal.shape)
    cx = (xs * sal).sum() / M
    cy = (ys * sal).sum() / M
    return (float(cx), float(cy))

def detect_lines(gray, canny_thresh1=50, canny_thresh2=150, hough_thresh=50):
    edges = cv2.Canny(gray, canny_thresh1, canny_thresh2)
    lines = cv2.HoughLinesP(edges, rho=1, theta=np.pi / 180, threshold=hough_thresh,
                            minLineLength=min(gray.shape) // 10, maxLineGap=10)
    if lines is None: return edges, []
    lines = [tuple(l[0]) for l in lines]
    return edges, lines

# ==========================================
# 2. SCORING FUNCTIONS
# ==========================================

def saturation_score(img_bgr):
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    sat = hsv[:, :, 1] / 255.0
    return float(np.mean(sat))

def balance_score(img_bgr, sal):
    img_lab = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = img_lab[:,:,0] / 255.0
    img_hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    S = img_hsv[:,:,1] / 255.0
    weight = sal * (L + 0.5 * S)
    M = weight.sum()
    h,w = sal.shape
    if M <= 1e-6: return 0.0
    ys, xs = np.indices(sal.shape)
    cx = (xs * weight).sum() / M
    cy = (ys * weight).sum() / M
    dx = abs(cx - w/2) / (w/2)
    dy = abs(cy - h/2) / (h/2)
    dist = np.sqrt(dx*dx + dy*dy) / np.sqrt(2)
    return float(max(0.0, 1.0 - dist*1.4))

def depth_score(img_gray, sal):
    mask = sal > 0.3
    if mask.sum() == 0: return 0.0
    ys,xs = np.where(mask)
    minx, maxx = xs.min(), xs.max()
    miny, maxy = ys.min(), ys.max()
    lap = cv2.Laplacian(img_gray, cv2.CV_64F)
    inside = lap[miny:maxy+1, minx:maxx+1]
    outside_mask = np.ones_like(img_gray, dtype=bool)
    outside_mask[miny:maxy+1, minx:maxx+1] = False
    outside = lap[outside_mask]
    var_in = float(np.var(inside)) if inside.size>0 else 0.0
    var_out = float(np.var(outside)) if outside.size>0 else 0.0
    diff = var_in - var_out
    score = (diff / (abs(var_out) + 1e-6)) if var_out>1e-6 else (1.0 if diff>0 else 0.0)
    score = np.tanh(score)
    return float(max(0.0, min(1.0, (score+1)/2)))

def diagonals_triangles_score(lines, contours, centroid, img_shape):
    if not lines:
        diag_strength = 0.0
    else:
        angles = []
        for (x1,y1,x2,y2) in lines:
            dx = x2 - x1; dy = y2 - y1
            ang = abs(np.arctan2(dy, dx))
            ang = min(ang, np.pi - ang)
            angles.append(1.0 - abs(ang - np.pi/4) / (np.pi/4))
        diag_strength = float(np.mean(angles)) if angles else 0.0
    h,w = img_shape[0], img_shape[1]
    cx,cy = int(centroid[0]), int(centroid[1])
    tri_score = 0.0
    for c in contours:
        area = cv2.contourArea(c)
        if area < 0.01*w*h: continue
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.04 * peri, True)
        if len(approx) == 3:
            inside = cv2.pointPolygonTest(c, (cx,cy), False)
            dist_to_centroid = 0 if inside>=0 else min([np.linalg.norm(np.array(pt[0]) - np.array([cx,cy])) for pt in approx])
            tri_score = max(tri_score, max(0.0, 1.0 - dist_to_centroid / max(w,h)))
    combined = 0.6*diag_strength + 0.4*tri_score
    return float(max(0.0, min(1.0, combined)))

def symmetry_score(img_gray):
    h,w = img_gray.shape
    left = img_gray[:, :w//2]
    right = img_gray[:, w - w//2:]
    right_flipped = cv2.flip(right, 1)
    if left.shape != right_flipped.shape:
        right_flipped = cv2.resize(right_flipped, (left.shape[1], left.shape[0]))
    leftf = left.astype(np.float32); rightf = right_flipped.astype(np.float32)
    if leftf.std() < 1e-3 or rightf.std() < 1e-3: return 0.0
    corr = np.corrcoef(leftf.flatten(), rightf.flatten())[0,1]
    return float(max(0.0, min(1.0, (corr + 1)/2)))

def fill_frame_score(sal, threshold=0.5):
    mask = sal > threshold
    if mask.sum() == 0: return 0.0
    ys, xs = np.where(mask)
    h,w = sal.shape
    box_area = (xs.max()-xs.min()+1)*(ys.max()-ys.min()+1)
    frac = box_area / (w*h)
    return float(min(1.0, frac*2.0))

def negative_space_score(sal):
    low = (sal < 0.15).sum() / sal.size
    return float(min(1.0, low))

def thirds_score(sal, centroid):
    h,w = sal.shape
    cx, cy = centroid
    thirds_pts = [(w/3, h/3), (w/3, 2*h/3), (2*w/3, h/3), (2*w/3, 2*h/3)]
    dists = [hypot(cx-x, cy-y) for (x,y) in thirds_pts]
    maxd = hypot(w, h)
    score = 1.0 - min(dists)/maxd*1.2
    vline_dist = min(abs(cx - w/3), abs(cx - 2*w/3)) / w
    hline_dist = min(abs(cy - h/3), abs(cy - 2*h/3)) / h
    line_score = 1.0 - min(vline_dist, hline_dist)
    return float(max(0.0, min(1.0, 0.6*score + 0.4*line_score)))

def golden_ratio_score(sal, centroid):
    h,w = sal.shape
    gx = [0.382, 0.618]; gy = [0.382, 0.618]
    cx, cy = centroid
    pts = [(g*w, g2*h) for g in gx for g2 in gy]
    dists = [hypot(cx-x, cy-y) for x,y in pts]
    maxd = hypot(w, h)
    return float(max(0.0, min(1.0, 1.0 - min(dists)/ (maxd*0.9))))

def center_score(sal, centroid):
    h,w = sal.shape
    cx, cy = centroid
    dx = abs(cx - w/2) / (w/2)
    dy = abs(cy - h/2) / (h/2)
    dist = np.sqrt(dx*dx + dy*dy) / np.sqrt(2)
    return float(max(0.0, 1.0 - dist*1.2))


# ==========================================
# 3. SINGLE IMAGE ANALYZER
# ==========================================

def analyze_single_image(img_path):
    if not os.path.exists(img_path):
        return json.dumps({
            "error": f"File not found at {img_path}",
            "success": False
        })

    # Load Image
    img_full = cv2.imread(img_path)
    if img_full is None:
        return json.dumps({
            "error": "Could not load image. Check format.",
            "success": False
        })

    try:
        # 1. Preprocessing
        img, scale = resize_for_fast_processing(img_full, max_side=640)
        h, w = img.shape[:2]
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # 2. Saliency Map
        sal = compute_saliency_gray(img)
        if sal.shape != gray.shape:
            sal = cv2.resize(sal, (w, h), interpolation=cv2.INTER_LINEAR)
        centroid = saliency_centroid(sal)

        # 3. Geometric Features (Lines & Contours)
        edges, lines = detect_lines(gray)
        _, thr = cv2.threshold((gray).astype(np.uint8), 0, 255, cv2.THRESH_OTSU + cv2.THRESH_BINARY_INV)
        contours, _ = cv2.findContours(thr, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        # 4. Calculate Scores
        scores = {
            'Rule of Thirds': thirds_score(sal, centroid),
            'Golden Ratio': golden_ratio_score(sal, centroid),
            'Symmetry': symmetry_score(gray),
            'Fill Frame': fill_frame_score(sal, threshold=0.45),
            'Negative Space': negative_space_score(sal),
            'Center Composition': center_score(sal, centroid),
            'Visual Balance': balance_score(img, sal),
            'Depth': depth_score(gray, sal),
            'Saturation': saturation_score(img),
            'Diagonals & Triangles': diagonals_triangles_score(lines, contours, centroid, img.shape)
        }

        # 5. Sort and get top 5
        sorted_features = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        top5 = [{"name": k, "score": v} for k, v in sorted_features[:5]]
        
        # 6. Return JSON result
        result = {
            "success": True,
            "scores": {k: float(v) for k, v in scores.items()},
            "top5": top5,
            "image_name": os.path.basename(img_path)
        }
        
        return json.dumps(result)
        
    except Exception as e:
        return json.dumps({
            "error": str(e),
            "success": False
        })



# -*- coding: utf-8 -*-
"""
Style
Original file: https://colab.research.google.com/drive/1YFqRnpIrbZiN2fwOVcr3FUMdHS3WZdwf
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

STYLE_CLASSES = [
    # Pop / Comic / Print
    "pop-art",
    "halftone-print",
    "comic-book",
    "graphic-novel",
    "newspaper-comic-strip",
    # Cartoon / Animation
    "cartoon-style",
    "minimal-flat-cartoon",
    "rubber-hose",
    "retro-cartoon",
    "anime",
    "chibi",
    "manga-inking",
    "ghibli-style",
    "superhero-comic",
    "disney-style",
    # Line-Based
    "line-art",
    "continuous-line",
    "blind-contour",
    "cross-hatching",
    "stippling",
    "ink-drawing",
    "technical-blueprint",
    "engraving",
    "monoline-icons",
    # Traditional Media
    "watercolor",
    "gouache",
    "oil-painting",
    "acrylic-paint",
    "pastel-chalk",
    "oil-pastel",
    "marker-render",
    "crayon",
    "ink-wash",
    "colored-pencil",
    "mixed-media",
    # Realism / Naturalism
    "realism",
    "naturalism",
    "photorealism",
    "hyperrealism",
    "portrait-realism",
    "botanical-illustration",
    "wildlife-realism",
    "scientific-illustration",
    "documentary-illustration",
    # Abstract / Modernist
    "abstract-expressionism",
    "minimal-abstract",
    "geometric-abstraction",
    "color-field",
    "cubism",
    "futurism",
    "bauhaus",
    "constructivism",
    "surreal",
    "magical-realism",
    "op-art",
    "escher-impossible",
    # Collage / Cut
    "paper-cutout",
    "analog-collage",
    "digital-collage",
    "photomontage",
    # Historical / Cultural
    "ukiyo-e",
    "indian-miniature",
    "persian-miniature",
    "art-nouveau",
    "art-deco",
    "medieval-illustration",
    "byzantine-icon",
    # Retro / Vintage
    "vintage",
    "mid-century-modern",
    "psychedelic-60s",
    "groovy-70s",
    "vaporwave",
    "synthwave",
    "retro-futurism",
    "risograph",
    "screenprint",
    # Street / Subculture
    "graffiti",
    "street-art",
    "lowbrow-pop",
    "sticker-bomb",
    "zine-grunge",
    # Digital / 3D / Tech
    "pixel-art",
    "isometric-pixel",
    "voxel-art",
    "low-poly-3d",
    "hyperreal-3d",
    "clay-render",
    "cel-shaded-3d",
    "holographic-gradient",
    "glitch-art",
    "chromatic-aberration",
    "datamosh",
    "vhs-analog",
]


STYLE_DESCRIPTIONS = {
    # Pop / Comic / Print
    "pop-art": "pop art, comic book style, bold colors, halftone dots, thick outlines",
    "halftone-print": "halftone dot shading, CMYK print texture, vintage comic printing",
    "comic-book": "dynamic panels, bold inking, action lines, superhero comic style",
    "graphic-novel": "moody shadows, dramatic black ink, narrative panels, serious tone",
    "newspaper-comic-strip": "simple line work, flat shading, classic newspaper strip style",
    # Cartoon / Animation
    "cartoon-style": "bold outlines, flat colors, exaggerated characters and expressions",
    "minimal-flat-cartoon": "simple vector shapes, flat color fills, minimal details",
    "rubber-hose": "1930s animation, noodle limbs, vintage rubber hose characters",
    "retro-cartoon": "old-school grain, hand-drawn frames, muted vintage palette",
    "anime": "clean linework, cel-shading, large expressive eyes, Japanese animation",
    "chibi": "super-deformed characters, big heads, tiny bodies, cute aesthetic",
    "manga-inking": "black and white screentones, clean ink lines, manga style",
    "ghibli-style": "soft painterly shading, warm palettes, whimsical nature scenes",
    "superhero-comic": "muscular characters, dramatic shading, intense action poses",
    "disney-style": "smooth polished shading, expressive eyes, classic animation aesthetic",
    # Line-Based
    "line-art": "clean linear outlines, no shading, monochrome strokes",
    "continuous-line": "one unbroken flowing line forming the subject",
    "blind-contour": "distorted outlines, drawn without looking, loose sketch style",
    "cross-hatching": "intersecting lines for shading, dense ink texture",
    "stippling": "dot-based shading, gradual tonal gradients from dots",
    "ink-drawing": "strong black ink strokes, high contrast, brush or pen feel",
    "technical-blueprint": "precise technical diagrams, blue background, white lines",
    "engraving": "fine parallel carved lines, antique print look",
    "monoline-icons": "uniform line weight, minimal shapes, iconographic design",
    # Traditional Media
    "watercolor": "transparent washes, soft gradients, bleeding pigment, paper texture",
    "gouache": "opaque matte colors, flat coverage, velvety paint texture",
    "oil-painting": "rich color blends, heavy brushstrokes, textured canvas feel",
    "acrylic-paint": "opaque fast-drying strokes, strong colors, painterly texture",
    "pastel-chalk": "soft dusty texture, delicate blending, chalky edges",
    "oil-pastel": "waxy thick strokes, vibrant smears, layered pigments",
    "marker-render": "streaky marker fills, smooth gradients, alcohol ink texture",
    "crayon": "childlike wax texture, rough strokes, uneven coloring",
    "ink-wash": "monochrome fluid washes, sumi-e brush style, soft gradients",
    "colored-pencil": "fine pencil texture, layered shading, visible grain",
    "mixed-media": "combined materials, layered textures, hybrid collage effects",
    # Realism / Naturalism
    "realism": "accurate representation, natural lighting, lifelike detail",
    "naturalism": "organic colors, soft shading, true-to-life textures",
    "photorealism": "photo-like accuracy, crisp details, polished lighting",
    "hyperrealism": "ultra-detailed textures, exaggerated clarity, surreal realism",
    "portrait-realism": "true facial anatomy, realistic skin tones, fine shading",
    "botanical-illustration": "high-detail plants, scientific precision, fine lines",
    "wildlife-realism": "accurate animal anatomy, natural fur/feather rendering",
    "scientific-illustration": "precise labeled diagrams, technical accuracy",
    "documentary-illustration": "real-life scenes, muted tones, reportage style",
    # Abstract / Modernist
    "abstract-expressionism": "gestural strokes, energetic splashes, emotional color",
    "minimal-abstract": "simple geometric forms, large negative space, clarity",
    "geometric-abstraction": "strict shapes, patterns, bold geometry",
    "color-field": "large flat color areas, subtle tonal transitions",
    "cubism": "fragmented shapes, multiple viewpoints, angular abstraction",
    "futurism": "dynamic angles, motion streaks, mechanical aesthetic",
    "bauhaus": "primary colors, clean geometry, functional composition",
    "constructivism": "bold diagonals, industrial forms, propaganda flavor",
    "surreal": "dreamlike imagery, strange juxtapositions, impossible forms",
    "magical-realism": "ordinary scenes with subtle fantastical elements",
    "op-art": "optical illusions, vibrating lines, high-contrast patterns",
    "escher-impossible": "paradoxical architecture, infinite loops, tessellations",
    # Collage / Cut
    "paper-cutout": "flat colored shapes, crisp edges, layered paper look",
    "analog-collage": "torn paper edges, magazine scraps, glue texture",
    "digital-collage": "layered photography fragments, digital assembly",
    "photomontage": "multiple photos combined into surreal compositions",
    # Historical / Cultural
    "ukiyo-e": "japanese woodblock style, flat colors, bold outlines, wave patterns",
    "indian-miniature": "fine detailing, ornate patterns, traditional storytelling",
    "persian-miniature": "vibrant colors, intricate decoration, ornate scenes",
    "art-nouveau": "flowing curves, floral motifs, elegant decorative lines",
    "art-deco": "geometric symmetry, metallic accents, luxury aesthetic",
    "medieval-illustration": "flat perspective, gold leaf accents, illuminated style",
    "byzantine-icon": "gold backgrounds, frontal figures, religious icon style",
    # Retro / Vintage
    "vintage": "aged tones, film grain, retro print texture, nostalgic aesthetic",
    "mid-century-modern": "retro shapes, muted tones, playful geometric forms",
    "psychedelic-60s": "vivid gradients, swirling patterns, trippy colors",
    "groovy-70s": "warm earthy colors, wavy lines, bohemian retro vibe",
    "vaporwave": "neon pinks and blues, retro grids, greek busts, glitchy nostalgia",
    "synthwave": "neon purples, chrome shine, retrofuturistic sunset grids",
    "retro-futurism": "futuristic style imagined in the past, old sci-fi aesthetic",
    "risograph": "duotone neon inks, grainy overlays, misaligned color layers",
    "screenprint": "flat inks, bold shapes, layered silkscreen texture",
    # Street / Subculture
    "graffiti": "spray paint texture, drips, tags, bold lettering",
    "street-art": "urban wall murals, stencil work, mixed street media",
    "lowbrow-pop": "quirky surrealism, outsider cartoon style, punk influence",
    "sticker-bomb": "dense overlapping stickers, colorful chaotic layers",
    "zine-grunge": "photocopy texture, rough cut edges, DIY punk style",
    # Digital / 3D / Tech
    "pixel-art": "pixelated blocks, low resolution, retro game style",
    "isometric-pixel": "45-degree pixel perspective, 3D pixel illusion",
    "voxel-art": "3D cubes, blocky shapes, volumetric pixel aesthetic",
    "low-poly-3d": "simple polygon shapes, faceted surfaces, flat shading",
    "hyperreal-3d": "lifelike 3D rendering, photoreal materials and lighting",
    "clay-render": "soft clay surface, sculpted feel, neutral lighting",
    "cel-shaded-3d": "toon outlines, flat shading, stylized animation look",
    "holographic-gradient": "iridescent metallic rainbow gradients, glossy shine",
    "glitch-art": "broken pixels, digital errors, RGB misalignment",
    "chromatic-aberration": "red-blue fringing, lens distortion edges",
    "datamosh": "compression smears, frame artifacts, melting visuals",
    "vhs-analog": "scanlines, tape noise, retro analog glitch",
}


PROMPT_TEMPLATES = [
    "a photo in the style of {}",
    "artistic rendering of {}",
    "a {} style image",
    "a painting in the style of {}",
    "a high quality example of {} art",
    "visuals depicting {}",
    "artwork created using {}",
    "a poster with {}",
    "a photograph looking like {}",
    "an illustration inspired by {}",
    "a digital artwork following the rules of {}",
    "a creative piece showcasing {}",
    "a visual composition designed in {} style",
    "an artistic composition influenced by {}",
    "a scene presented with {} aesthetics",
    "an image heavily influenced by {} techniques",
    "a graphical representation in {} aesthetics",
    "a stylized depiction matching {}",
    "the visual language of {} applied to an artwork",
    "a concept image using {} characteristics",
    "a stylized portrait in the manner of {}",
    "a landscape interpreted through {} style",
    "a figure drawing executed in {} technique",
    "a creative poster influenced by {}",
    "a concept sketch using {} visual rules",
    "an editorial illustration drawn in {} style",
    "a rendered scene with {} visual identity",
    "an artistic study done with {} aesthetics",
    "an experiment in {} visual style",
    "a fully rendered image designed around {} style",
]


class StyleClassifier:
    def __init__(self):
        self.centroids = None
        self.class_names = STYLE_CLASSES
        self.build_text_features()

    def build_text_features(self):
        """
        Pre-computes the embedding centroids for all styles.
        """
        print("Building text embeddings for styles...")
        class_centroids = []

        with torch.no_grad():
            for style in self.class_names:
                desc = STYLE_DESCRIPTIONS[style]

                prompts = [tpl.format(desc) for tpl in PROMPT_TEMPLATES]

                tokens = clip.tokenize(prompts).to(device)

                text_features = model.encode_text(tokens)

                text_features = text_features / text_features.norm(dim=-1, keepdim=True)

                centroid = text_features.mean(dim=0)

                centroid = centroid / centroid.norm()

                class_centroids.append(centroid)

        self.centroids = torch.stack(class_centroids).to(device)
        print("Text embeddings built successfully.")

    def predict(self, image_path, threshold=0.22):
        try:
            image = Image.open(image_path).convert("RGB")
        except Exception as e:
            print(f"Error loading image: {e}")
            return "error", []

        img_tensor = preprocess(image).unsqueeze(0).to(device)

        with torch.no_grad():
            img_feat = model.encode_image(img_tensor)
            img_feat = img_feat / img_feat.norm(dim=-1, keepdim=True)

        similarity = 100.0 * img_feat @ self.centroids.T

        probs = similarity.softmax(dim=-1).cpu().numpy()[0]
        raw_scores = similarity.cpu().numpy()[0] / 100.0

        results = []
        for i, style in enumerate(self.class_names):
            results.append(
                {
                    "style": style,
                    "score": float(raw_scores[i]),
                    "confidence_pct": float(probs[i] * 100),
                }
            )

        results.sort(key=lambda x: x["score"], reverse=True)

        top_result = results[0]

        if top_result["score"] < threshold:
            prediction = "undefined/mixed"
        else:
            prediction = top_result["style"]

        return prediction, results


#  Runner

classifier = StyleClassifier()

print("\nPlease upload an image to analyze:")
uploaded = files.upload()

for filename in uploaded.keys():
    print(f"\nAnalyzing: {filename}...")
    prediction, details = classifier.predict(filename)

    print(f"TOP PREDICTION: {prediction.upper()}")
    print("-" * 30)
    print("Full Breakdown:")
    for res in details[:5]:
        print(
            f"{res['style']:<20} | Score: {res['score']:.4f} | Conf: {res['confidence_pct']:.2f}%"
        )

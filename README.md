# CreekUI | Re-Imagining Photoshop | The AI Editor of 2030

CreekUI is a lightweight, intent-driven mobile image editor designed to shift the creative workflow from manual pixel manipulation to semantic, AI-assisted design. It separates creativity into structured phases that prioritize **semantic understanding**, **energy efficiency**, and **selective use of heavy compute**.

This repository contains the full analysis pipeline, style synthesis logic, and generation workflow that together simulate how a future (circa 2030) mobile NPU might function in creative applications.

### See the [Demo Video](https://drive.google.com/file/d/1bvroGCCosPUEP54q06nFWq1LhNB4PiAf/view?usp=sharing)

> [!NOTE]
>
> - Check out the project [Deliverables](./Deliverables/README.md)
> - For installation and setup instructions, refer to [INSTALL.md](./INSTALL.md)
> - For model details, see the [models](./models) directory

---

# 1. Project Overview

CreekUI decomposes the creative workflow into three major stages:

1. **Image Analysis → Semantic representations**
2. **Stylesheet Generation → Parametric design language**
3. **Asset Synthesis → Inpainting / Sketch-to-Image / Final outputs**

Only when the user finalizes intent does the system touch heavy pixel-generation models; everything before that operates on lightweight metadata.

The runtime spans:

- **Flutter UI** (front-end, canvas, orchestration)
- **Kotlin Native Layer** (method channel, concurrency, device coordination)
- **Chaquopy Python Runtime** (OpenCV, clustering, ONNX inference)
- **Flask ML Middleware** (simulated NPU backend for heavy models)

---

# 2. High-Level Architecture

## A. Presentation Layer (Flutter)

The UI provides a responsive canvas and orchestrates analysis tasks. Key features:

- **`AnalysisQueueManager`**  
  Background queue that handles image jobs without blocking UI.
  Batches note (cropped-region) jobs to reduce redundant image decodes.

- **Canvas Tools**

  - Magic Draw (sketch-based generation)
  - Layer history and reversible state
  - Stylesheet asset import

- **Prompt Builder Hooks**  
  Integrates semantic cues, stylesheets, and user notes into a unified request.

## B. Native Intelligence Layer (Kotlin + Chaquopy)

A hybrid Kotlin/Python pipeline handles local (non-generative) ML work:

- Starts the Chaquopy Python runtime with controlled synchronization (`CountDownLatch`).
- Executes OpenCV operations (saliency, geometry, edge detection).
- Runs ONNX models for segmentation / embeddings where feasible.
- Uses Kotlin coroutines to keep analysis asynchronous and avoid blocking the UI thread.

This layer ensures low-latency feedback and offline capability for most non-generative tasks.

## C. Simulated NPU Backend (Flask Middleware)

Since current mobile hardware can’t run multi-billion-parameter generative models at interactive speed, a local Flask server stands in as a simulation of a “2030 mobile NPU.”

- Runs heavy models: Stable Diffusion, Flux-based models, Florence-2.
- Models are quantized to approximate mobile constraints.
- Provides GPU-accelerated endpoints while mimicking the API boundaries of on-device inference.

**Security:**
All payloads are wrapped with **AES-256-GCM** using a fresh nonce per request to emulate the privacy guarantees of true on-device processing.

---

# 3. Detailed Pipelines

## A. Image Analysis Pipeline (Moodboard)

Each image passes through several independent analyzers executed in parallel (thread-per-tag approach):

1. **Composition Analysis**  
   Lightweight OpenCV functions compute saliency, centroids, edge maps, and evaluate rules such as thirds, symmetry, and negative space.

2. **Segmentation (BiRefNet)**  
   Provides high-quality masks at low overhead after 16-bit quantization.

3. **Texture Embeddings (DINOv2)**  
   Extracts patch-level embeddings to classify textures against prototype centroids.

4. **Style / Era / Emotion (CLIP)**  
   Performs zero-shot similarity against curated descriptors.

5. **Typography Recognition (EasyOCR + FANnet)**  
   OCR tokens → FANnet embedding → nearest-neighbor font family lookup.

Each analyzer contributes structured JSON fragments. At the end of processing, the system merges these fragments into a comprehensive semantic summary for the image.

## B. Stylesheet Synthesis (Parametric Design Layer)

Multiple image summaries (from those uploaded to the moodboard) are fused into a project-level style profile.

Steps include:

- **Rank–decay weighted aggregation** to emphasize consistent patterns across the moodboard.
- **Palette extraction** via clustering.
- **Texture & layout consensus** using pooled embeddings and geometric heuristics.
- **Font aggregation** through repeated FANnet similarity scores.

The output is a compact `stylesheet.json` containing the project’s:

- Composition
- Typography
- Background/Texture
- Colours
- Material Look
- Lighting
- Style
- Era
- Emotion

This stylesheet avoids repeated inference during user exploration: everything from brush behavior to prompt generation uses this parametric design layer.

## C. Generation Pipeline (Sketch-to-Image / Inpainting)

When the user provides intent (sketches, strokes, notes), the system constructs a unified prompt:

1. **Caption** from a quantized Florence-2 model
2. **Style cues** extracted from the stylesheet
3. **User directives** or overrides (object placement, prompt, etc.)

Depending on context:

- **Sketch-to-Image** uses lightweight or high-quality external backends (Nano Banana, Flux).
- **Inpainting** performs localized edits using Stable Diffusion with a mask derived from canvas stroke differences, or FLUX LoRa Fill.

> Local generation is prioritized for privacy-sensitive edits; API generation is used for high fidelity or speed when allowed.

# 4. Compute Profile

> [!IMPORTANT]
> Models provided by [Fal.ai](https://fal.ai/) API are used

Approximate characteristics of each model in its quantized / optimized configuration:

| Algorithm / Model                         | Inference Time | Number of Parameters | VRAM Usage | RAM Usage |
| ----------------------------------------- | -------------- | -------------------- | ---------- | --------- |
| Composition Detection Algo.               | 30 ms          | -                    | -          | -         |
| BiRefNet                                  | 502 ms         | 221 million          | 3.5 GB     | 2 GB      |
| Typography Detection                      | 3 seconds      | 238k                 | 50 MB      | 70 MB     |
| Background / Texture / Material Detection | 23 ms          | 22 million           | 350 MB     | 2.46 GB   |
| Colour & Colour Palette Detection         | 10 ms          | -                    | -          | -         |
| Lighting, Style, Era & Emotion Detection  | 9 ms           | 150 million          | 240 MB     | 280 MB    |
| Florence 2 Base                           | 1 second       | 230 million          | 750 MB     | 380 MB    |
| Nano Banana API                           | 6 seconds      | -                    | -          | -         |
| Flux Dev API                              | 5 seconds      | -                    | -          | -         |
| Stable Diffusion v1.5                     | 6 seconds      | 983 million          | 3.6 GB     | 2.5 GB    |
| Flux LoRa Fill API                        | 7 seconds      | -                    | -          | -         |
| Stable Diffusion v1.5 Inpainting          | 7 seconds      | 860 million          | 4 GB       | 2.7 GB    |

---

<details>
<summary><b>DATASETS</b></summary>

- DIS5K-TR Dataset
- FANnet Dataset
- EasyOCR Dataset
- LAION-5B Dataset (_Stable Diffusion v1.5_)
- LAION-AESTHETICS V2 4.5 (_Stable Diffusion v1.5 inpainting_)

</details>

---

# 5. Deployment & Runtime Decisions

- **Quantization** provided the best balance of fidelity and memory footprint.
- **Distillation** was tested but discarded due to poor stability and hallucination issues.
- **Lazy model loading** and reuse of ONNX sessions reduce repeated overhead.
- **Thread-capped parallelism** ensures segmentation and embedding steps don’t overload memory.

### On-Device Layer

- Offload only lightweight analyzers (OpenCV, CLIP, DINOv2 depending on budget).
- Use asynchronous queues for all analysis tasks.
- Cache embeddings per image to avoid re-computation.

### Backend Layer

- Use mixed-precision and selective quantization for generative workloads.
- Keep session warm to avoid cold-start latency spikes.
- Choose between local-backend vs external APIs based on privacy and performance flags.

---

# 6. Future Roadmap

- **Global Style Profile**: Inferring a user's long-term visual taste across multiple projects to offer personalized defaults.
- **Composition-Aware Camera**: A real-time AR overlay that guides users to take photos that align with their current moodboard's composition scores.
- **Multi-Device Synchronization**: A seamless ecosystem where compute tasks are dynamically distributed across a user's phone, tablet, and desktop based on available power and thermal headroom.

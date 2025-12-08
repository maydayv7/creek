# Deliverables

```
┌── (A) Task 1
│   ├── Screen Mockups
│   └── Design Rationale
│
├── (B) Task 2
│   └── Editing Ecosystem Analysis
│
└── (C) Task 3
    ├── Technical Report (containing documentation and model/dataset details)
    └── Demo Video -> https://drive.google.com/file/d/1bvroGCCosPUEP54q06nFWq1LhNB4PiAf/view?usp=sharing
```

Optional Creative Artefacts -> https://drive.google.com/file/d/1kSpf-y0LhQCn9-fF2gMLyodV8R3NkQeR/view?usp=sharing

# Problem Statement

> **Inter IIT Tech Meet 14.0 - Adobe Mid Prep**

Design and prototype a lightweight, mobile-first AI image editor for 2030 that demonstrates how creative editing can become faster, more intuitive, and energy-efficient on low-compute devices.
Your solution should combine design thinking, market research, and AI engineering across three integrated tracks:

### Task 1: Product Design

Create a medium-fidelity mobile wire-frame (phone layout) showing your envisioned editor’s interface, navigation, and AI assistance flow.
Emphasize speed, clarity, and human-in-the-loop control, how the user sees what the AI did and how they can refine it.
Consider next-generation inputs such as gestures, stylus, voice prompts, or context-aware auto-suggestions.

### Task 2: Understanding the Editing Ecosystem

Analyze the core tool set of modern image editors (crop, retouch, background removal, relighting, stylization, color balance etc.). 
Identify which operations are already automated by AI and which remain
manual.
Select two key AI-powered features or editing workflows to implement in the
execution phase.
Example feature pairs:

- Object removal + background reconstruction (segmentation + in-painting)
- Lighting adjustment + style transfer (Adapter-based stylization)
- Automatic subject enhancement + color correction (retouching pipeline)

### Task 3: Execution

Build the above selected, two AI editing workflows, each corresponding to one of your selected features.
Use open-source diffusion backbones (SDXL Inpainting, Flux 1.1, Kandinsky) or lightweight adapters (LoRA, quantized weights).
You can employ region selection modules (e.g., SAM, Mask R-CNN, matting models) to define editable areas.
Ideally, target lightweight inference and demonstrate via Stream-lit / web prototype.

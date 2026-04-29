# 008 — What “A4B” means in Gemma 4 model names (e.g. 26B-A4B)

Model strings such as **`gemma-4-26B-A4B-it`** or **`gemma-4-26b-a4b-it-nvfp4`** look opaque until you split them into **family**, **scale**, **routing (MoE)**, **post-training**, and **optional packaging**.

Related NVFP4 / stack note: **[007 — NVFP4 and inference stack](007-nvfp4-inference-stack-and-gpu-matrix.md)**.

---

## 1. Token-by-token decoding (example: `gemma-4-26B-A4B-it`)

| Segment | Meaning |
|---------|---------|
| **`gemma-4`** | Fourth generation of the **Gemma** open model family from Google DeepMind / Google. |
| **`26B`** | **Total** parameter budget associated with the **model id** in the catalog sense (often cited for the full **Mixture-of-Experts** design). It is **not** “26 billion dense FLOPs per token.” |
| **`A4B`** | **“Active” ~4 billion parameters per token** (order-of-magnitude) in the **MoE** design: only a **subset of experts** participates in each forward step, so **per-token compute and much of the activation memory** scale with the **active** side of the model, not the full expert pool. **A4B** is **not** a month (“April B”), a product SKU, or a license tier—it is **routing / sparsity sizing**. |
| **`it`** | **Instruction-tuned** (“chat” / assistant-style) variant, as opposed to a base pretrain-only checkpoint. |

So **26B-A4B** reads as: **~26B-scale MoE catalog**, with **~4B active** parameters per token (sparse expert usage), in the Gemma 4 line.

---

## 2. Why MoE naming matters for ops

- **VRAM** is driven by **loaded experts**, **cache**, **batch**, and **precision** (BF16, FP8, NVFP4, …), not only the “26B” headline.
- **Throughput** depends on **how many experts** are touched per layer and how well the stack **fuses** MoE patterns on your **GPU architecture**.
- **Quantized** builds (e.g. **`-NVFP4`**) change **which kernels** run; the **A4B** part still tells you the **MoE shape** is in play.

---

## 3. Relationship to filenames in this repo

- **`values-gemma-4-26b-a4b-it-nvfp4.yaml`** is named for readability; the **Hugging Face id** uses Google’s casing: **`RedHatAI/gemma-4-26B-A4B-it-NVFP4`**.  
- The **`-NVFP4`** suffix is **artifact-specific** (quantization / packaging), not part of the core **A4B** MoE definition.

---

## 4. Where to read the definitive description

Google’s **Gemma 4** technical / model card material (on **Hugging Face** or **Google AI** documentation) is authoritative for **exact** expert counts, top‑k routing, and how **26B** vs **A4B** are measured. Use that if you need **precise** numbers for papers or capacity planning; this doc is an **operator-oriented** gloss.

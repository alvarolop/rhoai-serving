# 007 — NVFP4 weights, inference stack, and GPU matrix (Gemma 4 NVFP4)

This note explains **what NVFP4 means** for models such as **`RedHatAI/gemma-4-26B-A4B-it-NVFP4`**, which parts of the stack **this Helm chart does not pin**, and **what to verify on your cluster** before relying on NVFP4 in production.

Related values overlay: **`chart/values-gemma-4-26b-a4b-it-nvfp4.yaml`**.  
MoE naming (**A4B**): **[008 — Gemma 4 “A4B” naming](008-gemma-4-a4b-moe-naming.md)**.

---

## 1. What “NVFP4” means here

**NVFP4** refers to **NVIDIA’s 4-bit floating-point family** used for aggressive compression of large models, often in a **weights-and-activations** style setup (conceptually “low-bit” linear layers) packaged for vLLM via ecosystems such as **compressed-tensors** and tooling like **vllm-project/llm-compressor** / ModelOpt-style workflows.

For the Red Hat–published Gemma checkpoint:

- Weights (and, for this artifact, activations) are prepared for **vLLM’s quantized / compressed loading paths**, not a plain BF16 Hugging Face tree.
- The **on-disk** size is much smaller than full BF16, but **VRAM and context length** still dominate at runtime (KV cache, MoE routing, batching).

**Not the same as:** arbitrary community “FP4” names without the same vLLM loader support—always match **model card + vLLM version + GPU generation**.

---

## 2. What this repository controls vs the platform

| Layer | Owned by **`rhoai-serving`** chart? | What you set |
|--------|-------------------------------------|----------------|
| **`LLMInferenceService`** CR, resources, **`extraArgs` → `VLLM_ADDITIONAL_ARGS`** | Yes | `values-*.yaml` |
| **Which container image** runs vLLM (digest, vLLM commit, CUDA in image) | **No** (unless you use **`mainContainer.image`**) | **OpenShift AI** operator / **ServingRuntime** / platform defaults |
| **GPU driver**, **GPU Operator**, **node GPU model** | No | Cluster admins |
| **HardwareProfile** (`gpu-profile`, etc.) | Referenced by chart; CRs live in **`redhat-ods-applications`** (typical) | GitOps / admin |

So: the chart can point the workload at **`hf://…/gemma-4-26B-A4B-it-NVFP4`**, but **compatibility is decided by the platform inference image + driver + physical GPU**.

---

## 3. What to check: “Red Hat inference server” (generative worker)

OpenShift AI does not always use one marketing name for the vLLM worker in every doc string; in practice you care about **the image that backs your `LLMInferenceService` `main` container** after the operator reconciles it.

**Check on cluster (examples—adapt to your OpenShift / `oc` context):**

1. **Applied `LLMInferenceService`**  
   After deploy, inspect the owned **Deployment** / **Pod** and read **`spec.containers[?name=='main'].image`** (exact field names can vary slightly by KServe/RHOAI version).

2. **OpenShift AI / KServe release**  
   In **release notes** for your **OpenShift AI** (and underlying **KServe**) version, find the **documented vLLM** (or “inference runtime”) **version or image tag**.

3. **Upstream vLLM fixes for this model class**  
   Gemma 4 **quantized MoE** checkpoints depended on loader work merged in upstream **[vllm#39045](https://github.com/vllm-project/vllm/pull/39045)** (example timeline: merged **2026-04-09**).  
   **Rule of thumb:** your worker image must be **at least as new as** the product build that contains that vLLM revision (or a vendor backport). A label that only says **“0.13”** is **insufficient** unless **release notes or image SBOM** prove the commit is included.

4. **Optional custom image**  
   If you **must** pin vLLM, use the chart’s **`mainContainer`** override only when your platform supports it and you accept support boundaries for non-default images.

---

## 4. What to check: NVIDIA graphics / GPU stack

NVFP4 performance and even **kernel availability** are **tightly coupled to GPU architecture** (compute capability) and the **driver + CUDA** combination inside the inference image.

| Concern | Why it matters |
|---------|----------------|
| **GPU model on the node** | **Blackwell-class** (e.g. **B200**) is where NVIDIA’s FP4 story is most complete for datacenter inference paths. **Hopper (H100)** may hit **different code paths** (emulation, partial support, or unsupported combinations) depending on vLLM and CUDA build. |
| **NVIDIA GPU Operator / driver** | Must satisfy the **minimum driver** required by the **CUDA** bundled in the **inference container**. Mismatch → failed CUDA init or subtle runtime errors. |
| **MIG / time-slicing / shared GPU** | MoE + quantized kernels are **sensitive** to memory layout; prefer **full GPU** until validated. |
| **Node labels / `HardwareProfile`** | Ensure your **`gpu-profile`** (or equivalent) actually schedules **the GPU class you tested** (e.g. H100 vs B200). |

**Practical validation:** run a **short** `vllm serve` equivalent workload (or the chart’s deploy) on a **single GPU** node that matches production, then run **smoke** generation (not only “model loaded” logs). Some NVFP4 issues appear only under **decode** (e.g. empty completions on certain builds).

---

## 5. Decision matrix (high level)

| Goal | Suggestion |
|------|------------|
| **Production on Hopper (H100)** | Prefer **BF16** or **FP8** Gemma 4 artifacts with clear vLLM support in **your** release notes; treat **NVFP4** as **experimental** until validated. |
| **Production on Blackwell (B200)** | NVFP4 is a **natural** target; still verify **OpenShift AI image version** and **driver**. |
| **Strict change control** | Record **OpenShift AI version**, **inference image digest**, **GPU Operator version**, **driver version**, and **GPU SKU** in your runbook alongside **`chart/values-gemma-4-26b-a4b-it-nvfp4.yaml`**. |

---

## 6. Context length vs memory

Long **`--max-model-len`** (e.g. **96000**) dramatically increases **KV cache** pressure. The values overlay defaults to a **lower** context to reduce OOM risk on a **single 80GB-class** GPU; raise it only after **measured** headroom.

---

## 7. Authoritative references (external)

- **Model card:** [RedHatAI/gemma-4-26B-A4B-it-NVFP4](https://huggingface.co/RedHatAI/gemma-4-26B-A4B-it-NVFP4) (run instructions, disclaimers).  
- **vLLM:** release notes / image SBOM for the **exact** worker you run; upstream PRs for **Gemma 4** + **quantized MoE** + **NVFP4**.  
- **OpenShift AI:** version-specific documentation for **generative serving** and supported runtimes.

Exact product names and CRD shapes evolve between releases; prefer **your installed version’s** documentation when they disagree with this repo.

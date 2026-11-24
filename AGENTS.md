# AGENTS.md — AI Coding Agent Instructions

Read and follow **[`CLAUDE.md`](./CLAUDE.md)** as the single source of truth before modifying any code in this repository (applies to Google Antigravity, Claude Code, Codex, and all other coding agents).

## Quick Checklist Before Committing

1. **Never edit `shaders/` directly** — edit `tools/src/*.inc` (or `tools/build-shaders.py`) and regenerate.
2. **Never name a variable or parameter `P`** — `#define P(x,y)` is an active sampling macro; use `Pc` for center-pixel `vec3` values so RetroArch `rslc` (Vulkan/Slang) and mobile OpenGL ES drivers compile cleanly.
3. **Use `distSqYCbCr` with pre-squared thresholds** for boolean color-distance checks, and never re-fetch texels already cached in local `vec3` variables.
4. **Preserve `//#crisp{ ... //#crisp}` and `//#plain` markers** and keep rule numbers synced with `tools/src/header.inc` (Rules 1–49 on `main`).
5. **Enforce `LP_NATIVE_VECTOR_WIDTH=128` for Mesa `llvmpipe`** — AVX-512 miscompiles `resolve.glsl` (`lab_kit.py` sets this automatically; export it in any standalone EGL/Mesa run).
6. **Use the persistent 100-scene lab (`/home/antigravity/.gemini/xbrz_crisp_lab/lab_kit.py`)** when available, or the repo's built-in **Desktop + Mobile Studio v4 comparator** (`python3 tools/studio/build_studio.py --baseline-ref HEAD --out <path>.html`, template at `tools/studio/studio_template.html` with instant click-to-flip, multi-spot 1× pinning, `Copiar Spots`, and PNG export).
7. **Final-only latency benchmarks** — defer `lab_kit.py bench` (1 worker ONLY, idle CPU) until **after** all rule changes are finalized; never benchmark after each individual tweak.
8. **Run build & verification scripts from repo root:**
   ```bash
   python3 tools/build-shaders.py
   python3 tools/verify.py
   python3 tools/make-release.py
   ```

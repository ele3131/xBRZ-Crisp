# AGENTS.md — AI Coding Agent Instructions

Read and follow **[`CLAUDE.md`](./CLAUDE.md)** as the single source of truth before modifying any code in this repository (applies to Google Antigravity, Claude Code, Codex, and all other coding agents).

## Quick Checklist Before Committing

1. **Never edit `shaders/` directly** — edit `tools/src/*.inc` (or `tools/build-shaders.py`) and regenerate.
2. **Never name a variable or parameter `P`** — `#define P(x,y)` is an active sampling macro; use `Pc` for center-pixel `vec3` values so RetroArch `rslc` (Vulkan/Slang) and mobile OpenGL ES drivers compile cleanly.
3. **Use `distSqY` / `distSqYCbCr` with pre-squared thresholds (`SQ255(...)`)** for boolean color-distance checks, and never re-fetch texels already cached in local `vec3` variables.
4. **Preserve `//#crisp{ ... //#crisp}` and `//#plain` markers** and keep rule numbers synced with `tools/src/header.inc` (42 active rules across index 1–49 on `main`).
5. **Enforce `LP_NATIVE_VECTOR_WIDTH=128` for Mesa `llvmpipe`** — AVX-512 miscompiles `resolve.glsl` (`tools/verify.py`, `tools/lab.py`, `tools/render-docs.py`, and `tools/studio/build_studio.py` enforce this automatically; export it in any standalone EGL/Mesa run).
6. **Use the in-repo lab CLI (`tools/lab.py`) and Studio v4 comparator (`tools/studio/build_studio.py`)** — auto-discovers up to 55 scenes (`docs/img` + `tools/assets/micro` + `~/.cache/xbrz-crisp/suite50` via `XBRZ_SUITE_DIR`) with content-addressed `build/cache/<sha12>/` caching (`lab.py diff`, `lab.py check --full`, `lab.py trace`, `lab.py bisect`, `lab.py studio --preset desktop`).
7. **Final-only latency benchmarks** — defer `python3 tools/lab.py bench --ref HEAD` (1 worker ONLY, idle CPU) until **after** all rule changes are finalized; never benchmark after each individual tweak.
8. **Run build & verification scripts from repo root:**
   ```bash
   python3 tools/build-shaders.py
   python3 tools/verify.py --smoke --require-spirv
   python3 tools/make-release.py
   ```

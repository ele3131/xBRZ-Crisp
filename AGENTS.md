# AGENTS.md — AI Coding Agent Instructions

Read and follow **[`CLAUDE.md`](./CLAUDE.md)** as the single source of truth before modifying any code in this repository (applies to Google Antigravity, Claude Code, Codex, and all other coding agents).

## Quick Checklist Before Committing

1. **Never edit `shaders/` directly** — edit `tools/src/*.inc` (or `tools/build-shaders.py`) and regenerate.
2. **Never name a variable or parameter `P`** — `#define P(x,y)` is an active sampling macro; use `Pc` for center-pixel `vec3` values so RetroArch `rslc` (Vulkan/Slang) and mobile OpenGL ES drivers compile cleanly.
3. **Use `distSqYCbCr` with pre-squared thresholds** for boolean color-distance checks, and never re-fetch texels already cached in local `vec3` variables.
4. **Preserve `//#crisp{ ... //#crisp}` and `//#plain` markers** and keep rule numbers synced with `tools/src/header.inc`.
5. **Run build & verification scripts from repo root:**
   ```bash
   python3 tools/build-shaders.py
   python3 tools/verify.py
   python3 tools/make-release.py
   ```

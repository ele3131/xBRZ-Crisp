# CLAUDE.md — Architecture & Engineering Guide

This file defines the single-source build workflow, compiler constraints, and GPU optimization conventions for **xBRZ Crisp**. Follow these rules on every update.

## 1. Single-Source Shader Pipeline (Never Edit `shaders/` Directly)

All 10 `.slang` and `.glsl` files under `shaders/` are **generated artifacts**. Never hand-edit files in `shaders/`.

Edit only the shared templates in `tools/src/` and the generator in `tools/build-shaders.py`:

- `tools/src/license.inc` — GPLv3 / MIT license banner
- `tools/src/header.inc` — Full numbered rule catalog (included in `pass0.inc` only)
- `tools/src/header_short.inc` — Concise header for `resolve.inc`, `match.inc`, and `pass1.inc`
- `tools/src/color.inc` — Rec. 2020 `LUMA_W`, `luma()`, `distSqYCbCr()`, `distYCbCr()`, `dist255()`, `SQ255()`, `within255()`, `withinEq255()`
- `tools/src/point.inc` — Pass 0a (`point`): per-vertex 2x2 junction preprocessing
- `tools/src/pass0.inc` — Pass 0b (`pass0`): per-texel corner detection and Crisp rules
- `tools/src/resolve.inc` — Pass 0c (`resolve`): cross-neighbor corner resolution
- `tools/src/match.inc` — Pass 0d (`match`): diagonal burr restoration (`xbrz-crisp` only)
- `tools/src/pass1.inc` — Pass 1 (`pass1`): output-scale corner rasterization

After any shader or template change, run the build and verification scripts from the repository root:

```bash
python3 tools/build-shaders.py    # Regenerates all 10 Slang + GLSL shaders in shaders/
python3 tools/verify.py           # Lint + single-source sync + make-multipass + ES 1.00/3.00 compile
python3 tools/make-release.py     # Deterministic build/xbrz-crisp.zip + SHA256
# Optional helpers:
python3 tools/render-docs.py      # Render docs/img/*-crisp{10,20,30}.png locally (gitignored; built in CI)
python3 tools/publish-release.py 3.6 [--publish]  # Full release pipeline + changelog + GitHub Release
```

`build/` and `docs/img/*-crisp{10,20,30}.png` are gitignored (`.github/workflows/pages.yml` renders and deploys the comparison page automatically on push to `main`). Commit `tools/src/*` and the regenerated `shaders/*` files together so users cloning the repo or inspecting diffs see exact generated shader changes.

## 2. RetroArch `rslc` & Mobile GLSL ES Compiler Constraints

RetroArch compiles `.slang` shaders through its C preprocessor (`rslc`) and `.glsl` shaders through desktop GLSL (`120`/`130`) and mobile OpenGL ES (`100`/`300 es`, including strict Qualcomm Adreno drivers). Respect these rules strictly:

1. **Never shadow active sampling macros in variable or parameter names:**
   Each pass defines function-like macros such as `#define P(x,y)`, `#define P4(x,y)`, and `#define INFO(uv)`. Both `rslc` and Qualcomm Adreno's GLSL ES preprocessor fail with syntax errors if a function parameter or local variable is named `P` (e.g., `vec3 P`) and passed into another expression or macro. Always name center-pixel parameters/locals `Pc` (never `P`).
2. **Prefer typed helper functions over `#define` macros for color logic:**
   Keep helpers like `bool alike(vec3 a, vec3 b)` as typed GLSL functions rather than `#define` macros to avoid macro-expansion collisions and duplicate expression evaluation.
3. **Keep `@include` directives clean:**
   `tools/build-shaders.py` expands `@include "file.inc"` recursively from `tools/src/` and fails the build if any `@include` or `@PLACEHOLDER@` token remains unexpanded. Note that pass templates include `header.inc` (or `header_short.inc`) and `license.inc` sequentially — do not re-include `license.inc` inside headers.
4. **Keep uniform block (`UBO`) parameters consistent:**
   `point.slang` declares all 5 `#pragma parameter` floats in `UBO` alongside `pass0.slang` so RetroArch's preset parameter table stays aligned across drivers.
5. **GLSL ES 1.00 compatibility:**
   Avoid GLSL 1.30+-only builtins (`roundEven`, bitwise `&`/`|`/`>>`, integer textures, `texelFetch`, C-style array initializers) in shared `.inc` code; stick to float arithmetic, `floor()`, `fract()`, `step()`, `mix()`, and `COMPAT_TEXTURE`.

## 3. Upstream `xbrz-freescale-multipass` Compatibility (`//#crisp`)

`tools/make-multipass.py` derives the 4-pass plain libretro shader (`XBRZ_MINC = 0`, rules 2, 4–7, and 10 only) directly from the generated `shaders/` files:

- Wrap Crisp-only blocks in `//#crisp{` ... `//#crisp}` on their own lines (never nest `//#crisp{` blocks).
- Prefix plain-only fallback lines with `//#plain `.
- Keep `//#plain-default XBRZ_MINC 0` and exact header anchor strings expected by `tools/make-multipass.py`.
- Neither `xbrz_crisp` nor `xBRZ crisp` nor leftover `//#` markers may remain outside `//#crisp{ ... //#crisp}` blocks (`make-multipass.py` enforces this automatically).
- Keep the numbered rule descriptions in `tools/src/header.inc` synchronized with the numbered rule sections in `point.inc`, `pass0.inc`, `resolve.inc`, and `match.inc`.

## 4. GPU Performance & Algorithmic Invariants

1. **Squared YCbCr color comparisons (`distSqYCbCr`):**
   For boolean threshold tests (`< tol`, `< minc`, `> diag`), always compare `distSqYCbCr(a, b)` against pre-squared thresholds (`tolSq`, `mincSq`, `diagSq` computed once per pixel) instead of calling `sqrt()` via `distYCbCr` or `dist255`. Use `distYCbCr` only when summing linear distances (e.g., xBRZ weighted directional gradients).
2. **Zero redundant texture fetches:**
   Cache neighborhood texels in local `vec3` variables once per pass. Never re-sample `P(dx, dy)` for coordinates already in local variables, and defer outer-ring fetches inside the conditional blocks that actually require them.
3. **Preserve C++ xBRZ tie-breaking and symmetry:**
   - Keep exact `<` vs `<=` asymmetries where documented to match Zenju's C++ xBRZ 1.9.
   - Keep `TexCoord * 1.0001` in `pass1` vertex UV generation so `sign(0)` ties on even integer scales match libretro `xbrz-freescale`.
   - When fixing asymmetric directional checks (horizontal vs. vertical, 4 rotations of a corner), verify all 4 orientations symmetrically and re-check comparison scenes in `docs/img/` if visual output changes.

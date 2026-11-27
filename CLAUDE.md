# CLAUDE.md — Architecture & Engineering Guide

This file defines the single-source build workflow, compiler constraints, and GPU optimization conventions for **xBRZ Crisp**. Follow these rules on every update.

## 1. Single-Source Shader Pipeline (Never Edit `shaders/` Directly)

All 10 `.slang` and `.glsl` files under `shaders/` are **generated artifacts**. Never hand-edit files in `shaders/`.

Edit only the shared templates in `tools/src/` and the generator in `tools/build-shaders.py`:

- `tools/src/license.inc` — GPLv3 / MIT license banner
- `tools/src/header.inc` — Full numbered rule catalog, Pass-to-Rule Index, and Decision-Word Bit Layout (included in `pass0.inc` only)
- `tools/src/header_short.inc` — Concise header for `resolve.inc`, `match.inc`, and `pass1.inc`
- `tools/src/color.inc` — Rec. 2020 `LUMA_W`, `toYCbCr()`, `luma()`, `distSqY()`, `distSqYCbCr()`, `distYCbCr()`, `dist255()`, `SQ255()`, `withinY255()`, `withinEqY255()`, `within255()`, `withinEq255()`, `geomRamp4()`
- `tools/src/bits.inc` — Shared decision-word bit constants (`BIT_LINE`..`BIT_BLOCKED`, `BIT_LONG3`/`BIT_LONG4`, `BIT_ARC45`/`BIT_ARC21`) and word masks (`BLEND`, `FLAG`, `cut4`, `activeCutOf`, `cutNoWeak`, `drawsLine4`, `isLine45`, `wordPlain`, `wordLine45`)
- `tools/src/hold28.inc` — Shared Rule 28 hold-score, tie-breaker, and crossing drop helpers (`held28`, `holdOf28`, `holdOfEdge28`, `tie28`, `whole28Mask`, `dropCross28`) used by `resolve.inc` and `match.inc`
- `tools/src/point.inc` + `tools/src/point_checker46.inc` — Pass 0a (`point`): per-vertex 2×2 junction preprocessing + T-junction/dark-outline guards + Rules 31, 36, and 46 (checkerboards/50% meshes)
- `tools/src/pass0.inc` — Pass 0b (`pass0`): per-texel corner detection and Crisp rules (Rules 1–11, 13, 15, 16, 18, 30, 32, 33)
- `tools/src/resolve.inc` + `tools/src/resolve_steps14.inc` + `tools/src/resolve_junc20.inc` — Pass 0c (`resolve`): cross-neighbor corner resolution (Rules 1 weak, 2 chain/meet, 9 2nd, 14–15b, 17, 19–21 incl. 20b crosshair bar, 23, 24, 28, 29, 37)
- `tools/src/match.inc` + `tools/src/match_geom.inc` + `tools/src/match_r26.inc` + `tools/src/match_r28.inc` + `tools/src/match_junctions.inc` + `tools/src/match_strokes.inc` — Pass 0d (`match`): monotonic 4-phase post-resolve diagonal matching, junction guards, unified 2:1 downgrade (`downgrade21Collision`), stroke refinements (`xbrz-crisp` only; Rules 26, 28–28b, 38–41, 42b, 43–45, 48, 49), and Phase 5 `BIT_ARC45`/`BIT_ARC21` precomputation
- `tools/src/pass1.inc` — Pass 1 (`pass1`): zero-neighbor-fetch output-scale corner rasterization (45°, 2:1, 3:1, 4:1, small/thin, C1 circular fillets on bevels & `BIT_ARC45` corners, C1 `sdParab21` curves on `BIT_ARC21` flat→2:1→45° transitions)

After any shader or template change, run the build and verification scripts from the repository root:

```bash
python3 tools/build-shaders.py    # Regenerates all 10 Slang + GLSL shaders in shaders/
python3 tools/verify.py           # Lint + single-source sync + make-multipass + ES 1.00/3.00 compile
python3 tools/make-release.py     # Deterministic build/xbrz-crisp.zip + SHA256
# Optional helpers:
python3 tools/render-docs.py --all --include-xbrz  # Render docs/img/* and README docs/sheets/* locally (gitignored; built in CI)
python3 tools/publish-release.py 3.6 [--publish]   # Local release helper (or push tag e.g. `3.6` for .github/workflows/release.yml)
```

`build/`, `docs/sheets/`, `docs/img/*-crisp{10,20,30}.png`, `docs/img/*-xbrz.png`, and `docs/img/explain/*.png` are gitignored (`.github/workflows/pages.yml` renders and deploys both the README comparison sheets and the interactive comparison page automatically on push to `main`). Immutable 1× micro-sources for README multi-console sheets live in `tools/assets/micro/` and their declarative layout lives in `tools/sheets_spec.json`. Commit `tools/src/*` and the regenerated `shaders/*` files together so users cloning the repo or inspecting diffs see exact generated shader changes.

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

## 5. In-Repo Lab CLI (`tools/lab.py`), 55-Scene Suite & Latency Policy

Visual regression testing, pixel-level debugging, D4 symmetry verification, offline Studio v4 comparators, and performance profiling all live directly in the repository with zero external dependencies beyond Python 3 + Pillow/NumPy + headless Mesa EGL/GLES:

- **Scene discovery (up to 55 scenes):**
  - 12 full scenes in `docs/img/*-original.png` (with real Zenju C++ `*-xbrzcpp.png` references)
  - 9 micro scenes in `tools/assets/micro/*-original.png`
  - Optional 34-scene multi-console corpus in `~/.cache/xbrz-crisp/suite50/` (auto-discovered, or set `XBRZ_SUITE_DIR=/path/to/dir`)
- **Mandatory Mesa `llvmpipe` environment guard:**
  Always export `LP_NATIVE_VECTOR_WIDTH=128` before loading Mesa/EGL (`llvmpipe`'s AVX-512 backend miscompiles `resolve.glsl`). `tools/verify.py`, `tools/lab.py`, `tools/render-docs.py`, and `tools/studio/build_studio.py` all enforce this automatically; set it explicitly in any standalone script.
- **Fast iteration workflow (`tools/lab.py` + `build/cache/<sha12>/`):**
  - `python3 tools/verify.py --smoke --require-spirv` — Lint + single-source sync + ES 1.00/3.00/3.10 + Slang/SPIR-V (20/20) + 2-scene runtime smoke (ES100/300 parity, Full D4, Plain 4-pass).
  - `python3 tools/lab.py diff [--ref HEAD] [--workers 2] [--cards OUT.png]` — Content-addressed cached 6× diff scan across all discovered scenes, ranked table, and optional 4-panel hotspot contact sheet.
  - `python3 tools/lab.py check [--full] [--ref HEAD]` — Full ES 1.00/3.00 parity + Plain 4-pass check + Full D4 (`rot90/180/270/flipH`, target `0/0/0/0`; default 12 `docs/img`, `--full` for all 55).
  - `python3 tools/lab.py trace <scene> <x> <y> [--ref HEAD]` — 1× RGB/YCbCr neighborhood + decoded 5-pass decision words (`point`/`pass0`/`resolve`/`match`) with bit-flag names.
  - `python3 tools/lab.py bisect <scene> <x> <y> [--ref HEAD]` — Pinpoints the exact first pass diverging from `--ref` around `(x, y)`.
  - `python3 tools/lab.py studio [--ref HEAD] [--preset desktop|compact|full] --out <path>.studio.html` — Builds the offline Desktop + Mobile Studio v4 comparator (`--preset desktop` enforces `<= 900 KB`, real `xBRZ 1.9` layer, custom baseline/candidate labels, and `node --check`).
  - `python3 tools/lab.py cache-gc [--keep 6]` — Prunes old shader-hash directories under `build/cache/`.
- **Final-only latency benchmark policy:**
  **Defer `python3 tools/lab.py bench --ref HEAD` until AFTER all rule changes are finalized.** Never run latency benchmarks after each individual rule tweak. `lab.py bench` forces `LP_NUM_THREADS=1` (strictly single-worker) and must run on an idle CPU (never concurrently with renders, builds, or other heavy commands).

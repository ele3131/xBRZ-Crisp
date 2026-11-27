<p align="center">
  <img src="https://ele3131.github.io/xBRZ-Crisp/sheets/banner.png" alt="xBRZ Crisp: smooth outlines and text without melting checkerboards, textures, or faces — featuring KOF '98 50% mesh and Tales of Phantasia cobblestone comparisons against xBRZ 1.9" width="100%">
</p>

<div align="center">
  <p><b>Pixel-faithful edge smoothing for RetroArch — smooth outlines and typography without melting checkerboards, textures, or faces.</b></p>
  <p>
    <img src="https://img.shields.io/badge/RetroArch-GLSL%20%26%20Slang-238636?style=flat-square" alt="RetroArch GLSL & Slang">
    <img src="https://img.shields.io/badge/Pipeline-5%20Passes%20(42%20Rules%20%2B%20C1%20Arcs)-6e7681?style=flat-square" alt="5-Pass Pipeline (42 Rules + C1 Arcs)">
    <img src="https://img.shields.io/badge/Verified-100%20Scenes%20%C2%B7%20D4%200%2F0%2F0-8957e5?style=flat-square" alt="100-Scene Suite & D4 Symmetry">
    <img src="https://img.shields.io/badge/License-GPLv3-d29922?style=flat-square" alt="GPLv3">
  </p>
  <p>
    <a href="https://ele3131.github.io/xBRZ-Crisp/"><img src="https://img.shields.io/badge/%E2%9C%A8%20Open%20Interactive%20Comparator-238636?style=for-the-badge" alt="Open Interactive Comparator"></a>
    &nbsp;
    <a href="https://github.com/ele3131/xBRZ-Crisp/releases"><img src="https://img.shields.io/badge/%F0%9F%93%A6%20Download%20Latest%20ZIP-1f6feb?style=for-the-badge" alt="Download Latest ZIP"></a>
    &nbsp;
    <a href="#-30-second-retroarch-install"><img src="https://img.shields.io/badge/%E2%9A%A1%20Quick%20Install-30363d?style=for-the-badge" alt="Quick Install"></a>
  </p>
</div>

<p align="center">
  <img src="https://ele3131.github.io/xBRZ-Crisp/sheets/hero-smw.png" alt="Super Mario World hero triptych: Original 1x, xBRZ 1.9 melting checkerboards into zigzags, xBRZ Crisp keeping checkerboards crisp and Rex smooth" width="100%">
</p>

---

<h2 align="center">🔥 5 Classic xBRZ Problems — Solved Visually</h2>

<p align="center">Each strip below shows <b>Original 1×</b> on the left, Zenju's C++ <b>xBRZ 1.9</b> in the middle, and <b>xBRZ Crisp</b> (default <code>XBRZ_MINC = 20</code>) on the right.</p>

### 1. Checkerboards, Dithering & 50% Mesh Transparency

**Problem in xBRZ 1.9:** Alternating pixel patterns used for retro transparency and shading get misread as diagonal lines, turning HUD bars and gauges into tangled zigzag worms.  
**Solution in xBRZ Crisp:** Dedicated checkerboard and 50% mesh preservation keeps every 1×1 square razor-sharp while letting neighboring kanji, badges, and rock textures smooth naturally.

<p align="center">
  <img src="https://ele3131.github.io/xBRZ-Crisp/sheets/strip-1-checkerboard.png" alt="Problem to solution strip 1: KOF '98 EX gauge and Samurai Shodown III life bars" width="100%">
</p>

### 2. Organic Textures: Grass, Foliage & Stone

**Problem in xBRZ 1.9:** Subtle pixel-art shading on grass, wood grain, and cobblestones smears into painted blobs.  
**Solution in xBRZ Crisp:** Contrast-aware edge gating (`XBRZ_MINC = 20`) preserves organic pixel textures while keeping character silhouettes and stepping stones smooth.

<p align="center">
  <img src="https://ele3131.github.io/xBRZ-Crisp/sheets/strip-2-textures.png" alt="Problem to solution strip 2: Golden Sun grass and Tales of Phantasia cobblestones" width="100%">
</p>

### 3. Faces, Eyes & Small 8-Bit Icons

**Problem in xBRZ 1.9:** Tight multi-color junctions merge eyebrows into eyes, pinch tiny key loops, and stab spikes out of small 8-bit icons.  
**Solution in xBRZ Crisp:** Diagonal color-distance guards (`XBRZ_DIAG`) and small-icon rules preserve Link's eye/eyebrow and keep NES Key & Bomb geometry clean and symmetrical.

<p align="center">
  <img src="https://ele3131.github.io/xBRZ-Crisp/sheets/strip-3-faces.png" alt="Problem to solution strip 3: Minish Cap Link and NES Legend of Zelda Key and Bomb at 12x macro zoom" width="100%">
</p>

### 4. Clean Game HUDs, Health Bars & Frame Borders

**Problem in xBRZ 1.9:** Stacked health-bar tips round off unevenly, ornate gold HUD frames dent at corners, and thin HUD digits pinch at tight strokes.  
**Solution in xBRZ Crisp:** Stacked HP/MP bars end crisp and square, ornate frame borders stay ruler-straight, and HUD numbers stay clean and smooth.

<p align="center">
  <img src="https://ele3131.github.io/xBRZ-Crisp/sheets/strip-4-text-hud.png" alt="Problem to solution strip 4: Castlevania Aria of Sorrow full HUD" width="100%">
</p>

### 5. Crisp Dithered Backgrounds & Smooth Diagonal Silhouettes

**Problem in xBRZ 1.9:** High-frequency rock dithering turns into chaotic soup while trying to smooth diagonal starfighters and clouds in the same scene.  
**Solution in xBRZ Crisp:** Dithered rock canyons stay crisp and textured while diagonal starfighter silhouettes and clouds stay sleek and smooth.

<p align="center">
  <img src="https://ele3131.github.io/xBRZ-Crisp/sheets/strip-5-diagonals.png" alt="Problem to solution strip 5: Mega Drive Thunder Force IV dithered rock canyon and starfighter" width="100%">
</p>

---

<h2 align="center">🕹️ Verified Across 6 Classic Consoles</h2>

<p align="center"><sub>Each tile compares <b>xBRZ 1.9</b> (left) vs <b>xBRZ Crisp</b> (right) from our 100-scene multi-console test suite.</sub></p>

<table>
  <tr>
    <td align="center" width="33%"><img src="https://ele3131.github.io/xBRZ-Crisp/sheets/tile-nes.png" alt="NES The Legend of Zelda comparison" width="100%"></td>
    <td align="center" width="33%"><img src="https://ele3131.github.io/xBRZ-Crisp/sheets/tile-gbc.png" alt="GBC Pokemon Crystal comparison" width="100%"></td>
    <td align="center" width="33%"><img src="https://ele3131.github.io/xBRZ-Crisp/sheets/tile-gba.png" alt="GBA Dragon Ball Z Buu's Fury dither sky comparison" width="100%"></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="https://ele3131.github.io/xBRZ-Crisp/sheets/tile-snes.png" alt="SNES Chrono Trigger foliage comparison" width="100%"></td>
    <td align="center" width="33%"><img src="https://ele3131.github.io/xBRZ-Crisp/sheets/tile-md.png" alt="Mega Drive Shining Force II flowers comparison" width="100%"></td>
    <td align="center" width="33%"><img src="https://ele3131.github.io/xBRZ-Crisp/sheets/tile-neogeo.png" alt="Neo Geo Metal Slug X HUD comparison" width="100%"></td>
  </tr>
</table>

<p align="center">
  <a href="https://ele3131.github.io/xBRZ-Crisp/"><img src="docs/assets/button.svg" alt="Open the Interactive Comparison Tool" width="420"></a>
</p>

---

<h2 align="center">🎛️ Tune Your Contrast (<code>XBRZ_MINC</code>)</h2>

<p align="center">
  <img src="https://ele3131.github.io/xBRZ-Crisp/sheets/presets-strip.png" alt="Golden Sun stepping stone and grass across Original, xBRZ 1.9, Crisp 10, Crisp 20 default, and Crisp 30" width="100%">
</p>

| `10` · Smooth | `20` · Balanced (Default) | `30` · Pixel-Faithful |
|---|---|---|
| Closest to classic xBRZ. Keeps only the softest dithering and subtle shading crisp. | **Recommended sweet spot.** Grass, stone, and checkerboards stay crisp; outlines, faces, and text stay smooth. | Maximum texture fidelity. Retains nearly all pixel texture, with firmer steps on soft diagonals. |

---

<h2 align="center" id="-30-second-retroarch-install">💾 30-Second RetroArch Install</h2>

> [!TIP]
> Grab the ready-to-use zip from **[GitHub Releases](https://github.com/ele3131/xBRZ-Crisp/releases)**.

1. Extract the zip into RetroArch's shaders directory: `shaders_slang` for Vulkan, `glcore`, D3D, and Metal; `shaders_glsl` for the `gl` driver.
2. While running a game, open **Quick Menu › Shaders › Load** and select `edge-smoothing/xbrz/xbrz-crisp.slangp` (Slang) or `xbrz/xbrz-crisp.glslp` (GLSL).
3. Save via **Quick Menu › Shaders › Save › Save Global Preset** (or **Save Game Preset** per title).

---

<h2 align="center">🔬 Technical Specs & Details</h2>

> [!NOTE]
> **Which xBRZ?** xBRZ is [Zenju's C++ scaler](https://sourceforge.net/projects/xbrz/). Every comparison here pits xBRZ Crisp (default `XBRZ_MINC = 20`) against Zenju's original C++ **xBRZ 1.9** at 6×. xBRZ Crisp is an independent RetroArch shader (GLSL & Slang) built on libretro's `xbrz-freescale-multipass`; the [interactive comparison page](https://ele3131.github.io/xBRZ-Crisp/) also includes libretro's plain port side by side.

<details>
<summary>Show all shader parameters</summary>

<br>

| Parameter | Default | What it does |
|---|---|---|
| `XBRZ_MINC` | **20** | Minimum color contrast (`x/255`) for a corner to be rounded. `0` turns it off. |
| `XBRZ_DIAG` | **100** | Maximum color distance (`x/255`) between the two colors a cut would join. Above it, the corner stays square. `0` turns it off. |
| `XBRZ_TOL` | **15** | Equal-color tolerance. Zenju's original C++ xBRZ uses `30`. |
| `XBRZ_STEEP` | **3.2** | Steep and shallow line threshold. C++ xBRZ 1.9 uses `2.4` (`2.2` prior to 1.9), turning more 1px steps into slopes. |
| `XBRZ_DOM` | **3.8** | Dominant direction threshold. C++ xBRZ uses `3.6`; `3.8` keeps small corners close to square instead of cutting long tips. |

libretro's `xbrz-freescale-multipass` uses the same tolerance, steep, and dominant values as xBRZ Crisp, with `XBRZ_MINC` and `XBRZ_DIAG` set to `0`, so it differs from Zenju's C++ xBRZ in both thresholds and shader logic.

</details>

<details>
<summary>How the 42 Crisp rules & C1 circular fillets work (4 core pillars)</summary>

<br>

- **🌿 Soft shading, checkerboards & 50% mesh (`XBRZ_MINC`):** Low-contrast shading, exact/shaded checkerboard textures, 2×N checker strips, and 50% transparency meshes keep their crisp square pixels while strong outlines, antialiasing bands, and crossing strokes stay smooth.
- **🎨 Color junction protection (`XBRZ_DIAG`):** High-contrast 3- and 4-color junctions (eyes, eyebrows, outlines, orthogonal HUD crosshairs) are never bridged by fake diagonals, while intentional shade ramps (`geomRamp4`) and 45° corners stay continuous.
- **📏 Clean endings & 1px geometry:** Stacked bars end square, HUD frames stay straight, convex 8-bit icon corners bevel cleanly, and isolated 1px glints and 1px diagonal strokes keep their exact artist intent.
- **📐 Straight stepped slopes & C¹ curves:** Regular 2–6px staircases (italic fonts, parallel drop shadows, roofs, rails) smooth along their true angle (2:1, 3:1, 4:1), while plain bevels, isolated 45° corners meeting flat walls, and strictly convex flat → 2:1 → 45° transitions render as true C¹ circular/parabolic curves in `pass1` with zero neighbor fetches.

See the [interactive comparison page](https://ele3131.github.io/xBRZ-Crisp/#how) for visual diagrams of the core rules.

</details>

<details>
<summary>Port architecture, single-source pipeline & testing</summary>

<br>

xBRZ Crisp started as a set of fixes to libretro's `xbrz-freescale-multipass` and has since been largely rewritten around **42 streamlined visual rules** (indexed across the 1–49 catalog) plus zero-fetch C¹ corner/transition curves. Blend color ties, exact corner ties, dual shallow/steep corners, and corner processing order follow Zenju's C++ xBRZ 1.9, while the output pass reads directly from the pass preceding xBRZ so it chains cleanly after color-correction shaders.

It runs in **five passes** — four at native 1× game resolution (`point` → `pass0` → `resolve` → `match`) and one lightweight output rasterization pass (`pass1`) that only draws the resolved corners, with dual-path GLES 3.0+ / Slang `texelFetch` & `uvec4` support and full GLSL ES 1.00 compatibility.

Both Slang and GLSL passes are generated from shared single-source templates in `tools/src/` by `tools/build-shaders.py` (with `tools/make-multipass.py` deriving plain `xbrz-freescale-multipass`). Every visual asset in this README and the interactive comparator is deterministically rendered in GitHub Actions via `tools/render-docs.py --all`, and every rule change is verified for exact **D4 rotational/reflection symmetry (`0/0/0`)** across a **100-scene multi-console test suite** (NES, Master System, GBC, GBA, SNES, Mega Drive, PC Engine, Neo Geo, Arcade, WonderSwan).

</details>

---

<h2 align="center">🤝 Giving back to libretro</h2>

Part of xBRZ Crisp is now upstream in libretro's xBRZ port. Starting October 20, 2026, libretro's `xbrz-freescale-multipass` adopted our port fixes, tuned thresholds, lighter output pass, and the `xbrz-crisp` preset ([glsl #576](https://github.com/libretro/glsl-shaders/pull/576), [#577](https://github.com/libretro/glsl-shaders/pull/577), [slang #971](https://github.com/libretro/slang-shaders/pull/971), [#973](https://github.com/libretro/slang-shaders/pull/973)). None of these changes are in Zenju's original C++ xBRZ.

<h2 align="center">⚖️ License</h2>

xBRZ is © Zenju ([original C++ version](https://sourceforge.net/projects/xbrz/)) under the **GNU General Public License v3**; libretro's shader and xBRZ Crisp keep that license as noted in the shader headers. Hyllian's xBR vertex code and texel mapping retain their MIT-style license. The diagonal junction check is inspired by torcado's cleanEdge (MIT license; no cleanEdge code is included).

xBRZ Crisp is an independent shader — not affiliated with or endorsed by Zenju, and not the original xBRZ.

<sub>Developed with the help of Claude (Anthropic) and Google Antigravity.</sub>

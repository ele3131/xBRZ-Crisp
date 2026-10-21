<div align="center">

# xBRZ crisp

**An xBRZ shader for RetroArch that only rounds corners between clearly different colors.**

Outlines, text and sprites are smoothed as in xBRZ, while low-contrast shading and textures (grass, foliage, stone, dithering) keep their pixel detail instead of melting into blobs.

[![Latest release](https://img.shields.io/github/v/release/ele3131/xbrz-crisp?style=flat-square&label=release&color=2f6fd6)](https://github.com/ele3131/xbrz-crisp/releases)
![RetroArch](https://img.shields.io/badge/RetroArch-slang%20%7C%20glsl-555?style=flat-square)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-555?style=flat-square)](LICENSE)

[![Animated comparison: xBRZ on the left, xBRZ crisp on the right](comparisons/preview-24.webp)](https://ele3131.github.io/xbrz-crisp/)

</div>

## 🔍 Interactive Comparison

<div align="center">

[![Open the Interactive Comparison](https://img.shields.io/badge/%E2%96%B6%20%20Open%20the%20Interactive%20Comparison-2f6fd6?style=for-the-badge)](https://ele3131.github.io/xbrz-crisp/)

</div>

Drag the line between xBRZ crisp and xBRZ, integer scaling or MMPX Advanced on 10 Game Boy Advance scenes. Compare minimum contrast 12, 24 and 32, zoom in up to 3×, and mark in red every spot crisp changes.

## 🖼️ Side by side

![Golden Sun](comparisons/1-golden-sun-24.png)

Text stays readable too. The spell name in the top-left corner of Harry Potter: Prisoner of Azkaban keeps its letter shapes:

![Harry Potter: Prisoner of Azkaban, spell name: original, xBRZ freescale, MMPX Advanced and xBRZ crisp](comparisons/6-azkaban-text.png)

More: [Minish Cap](comparisons/2-minish-cap-24.png) · [Golden Sun battles](comparisons/5-golden-sun-battle-24.png) · [Castlevania](comparisons/4-castlevania-24.png) · [other games](comparisons/3-other-games-24.png)

## 🎚️ Presets

There is one preset, `xbrz-crisp`, with a minimum contrast of 24, which keeps the textures closest to the original art. To change it, set `XBRZ_MINC` in Quick Menu › Shaders › Shader Parameters and save the preset. Good steps:

| `XBRZ_MINC` | Look |
|---|---|
| 12 | Closest to xBRZ, with a light gain in detail. Only the softest shading and textures keep their pixels. |
| 24 (default) | More texture detail in grass and foliage, closer to the original art. Some soft diagonals turn into steps. |
| 32 | Sharpest. Pale skin and soft shadows can start to look blocky. |

The cost is the same as `xbrz-freescale-multipass` at any value.

## ⚙️ Parameters

| Parameter | Default | What it does |
|---|---|---|
| `XBRZ_MINC` | 24 | Minimum color contrast (x/255) for a corner to be rounded. 0 turns it off (the tolerance and steep thresholds below still apply). |
| `XBRZ_MINC_RAMP` | 0 | Width of a soft transition around the threshold, so corners shrink gradually. 0 is a hard cut. |
| `XBRZ_TOL` | 15 | Equal color tolerance. Stock xBRZ uses 30. |
| `XBRZ_STEEP` | 3.2 | Steep and shallow line threshold. Stock xBRZ uses 2.2, which turns 1-pixel steps into slopes; 3.2 keeps letters and 1-pixel details closer to the original. |
| `XBRZ_DOM` | 3.8 | Dominant direction threshold. Stock xBRZ uses 3.6; 3.8 cuts fewer curve tips, so each rounded pixel keeps more of its size. |
| `XBRZ_LUMA` | 1.0 | Weight of brightness against color in the comparisons. |

## 🧠 How it works

xBRZ decides corner by corner whether to cut a pixel's corner with a neighbor's color. xBRZ crisp keeps that decision and adds one check before drawing: if the pixel and the blend color are closer than `XBRZ_MINC` (YCbCr distance), the corner stays square. Edge detection is unchanged, so only the low-contrast blends are skipped.

The shader is based on the libretro `xbrz-freescale-multipass` port. A few details were aligned with the reference C++ xBRZ: blend color ties and the order of the four corners follow the original, and the GLSL version takes the output scale from the image size instead of the texture size.

Tested in RetroArch on Android (gl driver, Game Boy Advance at 6x). The slang version was compiled to SPIR-V with glslang and renders the same output as the GLSL version in an offline harness.

## 📦 Install

1. Download the latest zip from [Releases](https://github.com/ele3131/xbrz-crisp/releases) (or use the `shaders/` folder of this repository) and copy its contents into RetroArch's shader folder: `shaders_slang` is for the Vulkan, glcore, D3D and Metal drivers, `shaders_glsl` is for the gl driver.
2. In a game, open Quick Menu › Shaders › Load and pick `edge-smoothing/xbrz/xbrz-crisp.slangp` (slang) or `xbrz/xbrz-crisp.glslp` (glsl).
3. Save it with Quick Menu › Shaders › Save › Save Global Preset, or per game with Save Game Preset.

## 📜 License

xBRZ is © Zenju and distributed under the GNU General Public License v3, as noted in the shader headers. Hyllian's xBR vertex code and texel mapping are under the MIT-style license included there.

Developed with the help of Claude (Anthropic).

# xBRZ crisp

An xBRZ shader for RetroArch that only rounds corners between clearly different colors. Outlines, text and sprites are smoothed as in xBRZ, while low-contrast shading and textures (grass, foliage, stone, dithering) keep their pixel detail instead of melting into blobs.

## [▶ Open the interactive comparison](https://ele3131.github.io/xbrz-crisp/)

Drag the line between xBRZ crisp and xBRZ, integer scaling or MMPX Advanced on 10 Game Boy Advance scenes, compare minimum contrast 12, 24 and 32, zoom in up to 3×, and mark in red every spot crisp changes.

[![Animated comparison: xBRZ on the left, xBRZ crisp on the right](comparisons/preview-24.webp)](https://ele3131.github.io/xbrz-crisp/)

![Golden Sun](comparisons/1-golden-sun-24.png)

![Golden Sun village, current xBRZ on the left and xBRZ crisp on the right](comparisons/split-gs_village.png)

Text stays readable too. The spell name in the top-left corner of Harry Potter: Prisoner of Azkaban keeps its letter shapes with the steep threshold of 3.2 from version 1.3:

![Harry Potter: Prisoner of Azkaban, spell name: original, xBRZ, crisp 1.2 and crisp 1.3](comparisons/6-azkaban-text.png)

More: [other games](comparisons/3-other-games-24.png) · [Minish Cap](comparisons/2-minish-cap-24.png) · [Golden Sun battle](comparisons/split-gs_battle.png) · [Castlevania](comparisons/split-cv_aria.png)

## Presets

There is one preset, `xbrz-crisp`, with a minimum contrast of 24, which keeps the textures closest to the original art. To change it, set `XBRZ_MINC` in Quick Menu › Shaders › Shader Parameters and save the preset. Good steps:

| `XBRZ_MINC` | Look |
|---|---|
| 12 | Closest to xBRZ, with a light gain in detail. Only the softest shading and textures keep their pixels. |
| 24 (default) | More texture detail in grass and foliage, closer to the original art. Some soft diagonals turn into steps. |
| 32 | Sharpest. Pale skin and soft shadows can start to look blocky. |

The cost is the same as `xbrz-freescale-multipass` at any value.

## Install

1. Download [xbrz-crisp-v1.3.zip](https://github.com/ele3131/xbrz-crisp/releases/latest/download/xbrz-crisp-v1.3.zip) from [Releases](https://github.com/ele3131/xbrz-crisp/releases) (or use the `shaders/` folder of this repository) and copy its contents into RetroArch's shader folder: `shaders_slang` is for the Vulkan, glcore, D3D and Metal drivers, `shaders_glsl` is for the gl driver.
2. In a game, open Quick Menu › Shaders › Load and pick `edge-smoothing/xbrz/xbrz-crisp.slangp` (slang) or `xbrz/xbrz-crisp.glslp` (glsl).
3. Save it with Quick Menu › Shaders › Save › Save Global Preset, or per game with Save Game Preset.

## Parameters

| Parameter | Default | What it does |
|---|---|---|
| `XBRZ_MINC` | 24 | Minimum color contrast (x/255) for a corner to be rounded. 0 turns it off (the tolerance and steep thresholds below still apply). |
| `XBRZ_MINC_RAMP` | 0 | Width of a soft transition around the threshold, so corners shrink gradually. 0 is a hard cut. |
| `XBRZ_TOL` | 15 | Equal color tolerance. Stock xBRZ uses 30. |
| `XBRZ_STEEP` | 3.2 | Steep and shallow line threshold. Stock xBRZ uses 2.2, which turns 1-pixel steps into slopes; 3.2 keeps letters and 1-pixel details closer to the original. |
| `XBRZ_DOM` | 3.6 | Dominant direction threshold. |
| `XBRZ_LUMA` | 1.0 | Weight of brightness against color in the comparisons. |

## How it works

xBRZ decides corner by corner whether to cut a pixel's corner with a neighbor's color. xBRZ crisp keeps that decision and adds one check before drawing: if the pixel and the blend color are closer than `XBRZ_MINC` (YCbCr distance), the corner stays square. Edge detection is unchanged, so only the low-contrast blends are skipped.

The shader is based on the libretro `xbrz-freescale-multipass` port. A few details were aligned with the reference C++ xBRZ: blend color ties and the order of the four corners follow the original, and the GLSL version takes the output scale from the image size instead of the texture size.

Tested in RetroArch on Android (gl driver, Game Boy Advance at 6x). The slang version was compiled to SPIR-V with glslang and renders the same output as the GLSL version in an offline harness.

## License

xBRZ is © Zenju and distributed under the GNU General Public License v3, as noted in the shader headers. Hyllian's xBR vertex code and texel mapping are under the MIT-style license included there.

Developed with the help of Claude (Anthropic).

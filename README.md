<p align="center">
  <img src="comparisons/design/banner.png" alt="xBRZ Crisp: xBRZ on the left, xBRZ Crisp on the right" width="100%">
</p>

<p align="center">
  <b>The smoothness of xBRZ, with respect for every pixel the artist drew.</b><br><br>
  ✨ Outlines and text come out smooth and sharp, just like xBRZ<br>
  🌿 Grass, foliage, stone and dithering keep their original pixels<br>
  🙂 Faces and small sprites keep their expression, with no fake diagonals<br>
  🎮 Ready for RetroArch, in GLSL and slang
</p>

<p align="center">
  <a href="https://ele3131.github.io/xBRZ-Crisp/"><img src="comparisons/design/button.svg" alt="Open the Interactive Comparison" width="420"></a>
</p>

<div align="center">
<table align="center" width="100%">
  <tr>
    <td align="center" width="33%">🎯<br><b>Only clear edges</b><br><sub>A corner is rounded only when its two colors really differ</sub></td>
    <td align="center" width="33%">🌿<br><b>Textures stay intact</b><br><sub>Soft shading no longer melts into blobs</sub></td>
    <td align="center" width="33%">⚡<br><b>Same cost</b><br><sub>Runs like xbrz-freescale-multipass</sub></td>
  </tr>
</table>
</div>

<h2 align="center">🎬 Interactive Comparison</h2>

<a href="https://ele3131.github.io/xbrz-crisp/"><img src="comparisons/preview-20.png" alt="Animated comparison in Golden Sun, Castlevania: Aria of Sorrow, Harry Potter: Prisoner of Azkaban and Tales of Phantasia: xBRZ (latest), then xBRZ Crisp 20" width="100%"></a>

Pick integer scaling, MMPX Advanced, ScaleFX, xBRZ (latest) or xBRZ Crisp (contrast 12 to 30) on each side, drag the line across 10 Game Boy Advance scenes, zoom in up to 4×, hold a button to see the original pixels, and mark in red every spot where the two sides differ.

<h2 align="center">🌄 Gallery</h2>

<table>
  <tr>
    <td width="50%"><a href="comparisons/1-golden-sun-20.png"><img src="comparisons/1-golden-sun-20.png" alt="Golden Sun"></a><p align="center"><b>Golden Sun</b></p></td>
    <td width="50%"><a href="comparisons/2-minish-cap-20.png"><img src="comparisons/2-minish-cap-20.png" alt="The Minish Cap"></a><p align="center"><b>The Minish Cap</b></p></td>
  </tr>
  <tr>
    <td width="50%"><a href="comparisons/5-golden-sun-battle-20.png"><img src="comparisons/5-golden-sun-battle-20.png" alt="Golden Sun battles"></a><p align="center"><b>Golden Sun battles</b></p></td>
    <td width="50%"><a href="comparisons/4-castlevania-20.png"><img src="comparisons/4-castlevania-20.png" alt="Castlevania: Aria of Sorrow"></a><p align="center"><b>Castlevania: Aria of Sorrow</b></p></td>
  </tr>
</table>

Faces keep their expression. Since 1.4, a corner where three different colors meet is no longer cut into a fake diagonal, so Link's eyebrow stays straight instead of being pulled into his eye, and stacked stripes such as health bars end square:

<img src="comparisons/7-faces.png" alt="Link in The Minish Cap, a face in Final Fantasy Tactics Advance and the health bar of Castlevania: Aria of Sorrow: original, xBRZ (latest) and xBRZ Crisp" width="100%">

Text and portraits keep their shape too, as in the spell menu of Harry Potter: Prisoner of Azkaban:

<img src="comparisons/6-azkaban-menu.png" alt="Spell menu: original, xBRZ (latest), MMPX Advanced and xBRZ Crisp" width="100%">

<sub>More: [other games](comparisons/3-other-games-20.png)</sub>

<h2 align="center">🎛️ Presets</h2>

Three presets, from smoothest to closest to the original art. Load one, or change `XBRZ_MINC` in Quick Menu › Shaders › Shader Parameters:

<img src="comparisons/design/presets-strip.png" alt="Golden Sun grass: original, xBRZ (latest), crisp 16, 20 and 24" width="100%">

| Preset | `XBRZ_MINC` | Look |
|---|---|---|
| `xbrz-crisp-16` | 16 | The smoothest. Textures and soft shading keep their pixels, and everything else is smoothed as in xBRZ. |
| **`xbrz-crisp`** (default) | **20** | The balance. Grass, foliage and stone keep most of their detail, while outlines, faces, text and most soft diagonals stay smooth. |
| `xbrz-crisp-24` | 24 | The closest to the original art. Textures keep nearly all their pixels, and some soft diagonals turn into steps. |

20 is the default because up to 20 each step keeps more of the original pixels for little loss of smoothness. Past it, smooth antialiased shapes start to lose more.

<h2 align="center">🛠️ Parameters</h2>

<details>
<summary>Show all shader parameters</summary>

| Parameter | Default | What it does |
|---|---|---|
| `XBRZ_MINC` | 20 | Minimum color contrast (x/255) for a corner to be rounded. 0 turns it off. |
| `XBRZ_DIAG` | 100 | Maximum color distance (x/255) between the two colors a cut would join. Above it, the corner stays square. 0 turns it off. |
| `XBRZ_TOL` | 15 | Equal color tolerance. The reference C++ xBRZ uses 30. |
| `XBRZ_STEEP` | 3.2 | Steep and shallow line threshold. The reference C++ xBRZ uses 2.2, which turns 1-pixel steps into slopes. |
| `XBRZ_DOM` | 3.8 | Dominant direction threshold. The reference C++ xBRZ uses 3.6; 3.8 keeps small corners close to square instead of cutting them into long tips. |

libretro's `xbrz-freescale-multipass` uses the same tolerance, steep and dominant values, with `XBRZ_MINC` and `XBRZ_DIAG` at 0.

</details>

<h2 align="center">🔬 How it works</h2>

<details>
<summary>Show how xBRZ Crisp differs from xBRZ</summary>

<br>

xBRZ looks at each corner of each pixel and decides whether to round it. xBRZ Crisp keeps every one of those decisions and only says no when rounding would invent a shape the artist never drew. In that case the corner stays square. The red circles mark where the two differ.

<img src="comparisons/8-how-it-works.png" alt="Stone in Tales of Phantasia, a face in Tales of Phantasia and a menu frame in Castlevania: Aria of Sorrow: original, xBRZ (latest) and xBRZ Crisp, with the differences circled in red" width="100%">

1. 🌿 **Soft shading is not a shape** (`XBRZ_MINC`). When the two colors of a corner are closer than the minimum contrast, they are shading or texture, not an edge, so the corner stays square.
2. 🎨 **Different colors are not joined** (`XBRZ_DIAG`). Rounding a corner joins the two neighbors on its diagonal. When those are very different colors, the corner is a meeting point, not a line, so it stays square. Dark outlines, eyes and eyebrows keep their full shape.
3. 📏 **Lines end the way they were drawn.** Straight lines do not bend where they meet, stacked stripes end square, and diagonal lines run on to their end or up to the outline. A 45-degree diagonal the artist drew, like a lock of hair, and thin light strokes, like the white strokes of letters, are rounded as in xBRZ.

Edges are still found exactly as xBRZ finds them, so outlines and text are smoothed as before. The diagonal check is inspired by [cleanEdge](https://github.com/libretro/slang-shaders/tree/master/edge-smoothing/cleanEdge) by torcado. The [comparison page](https://ele3131.github.io/xBRZ-Crisp/#how) goes through every rule with more examples.

</details>

<details>
<summary>Port details and testing</summary>

The shader is based on the libretro `xbrz-freescale-multipass` port. Blend color ties and the order of the four corners follow the reference C++ xBRZ, the GLSL version takes the output scale from the image size instead of the texture size, and the output pass reads the image from the pass before xBRZ, so it also works after other shaders in a preset (a color correction, for example).

The code keeps the xBRZ part and the crisp rules apart: the crisp rules sit between `//#crisp{` and `//#crisp}` markers, and `tools/make-multipass.py` removes them to write plain `xbrz-freescale-multipass`.

Tested in RetroArch on Android (gl driver, Game Boy Advance at 6x). The slang version was compiled to SPIR-V with glslang and renders the same output as the GLSL version in an offline harness.

</details>

<h2 align="center">💾 Install</h2>

> [!TIP]
> Get the latest zip from **[Releases](https://github.com/ele3131/xbrz-crisp/releases)**.

1. Copy the zip's contents into RetroArch's shader folder: `shaders_slang` for Vulkan, glcore, D3D and Metal, `shaders_glsl` for the gl driver.
2. In a game, open Quick Menu › Shaders › Load and pick `edge-smoothing/xbrz/xbrz-crisp.slangp` (slang) or `xbrz/xbrz-crisp.glslp` (glsl). Use `xbrz-crisp-16` or `xbrz-crisp-24` for the other presets.
3. Save it with Quick Menu › Shaders › Save › Save Global Preset, or per game with Save Game Preset.

<h2 align="center">🤝 Giving back to xBRZ</h2>

Part of xBRZ Crisp is now in xBRZ itself. Starting with our first pull request on October 20, 2026, libretro's `xbrz-freescale-multipass` has taken in its port fixes, tuned thresholds and lighter output pass, plus the `xbrz-crisp` preset ([glsl #576](https://github.com/libretro/glsl-shaders/pull/576), [#577](https://github.com/libretro/glsl-shaders/pull/577), [slang #971](https://github.com/libretro/slang-shaders/pull/971), [#973](https://github.com/libretro/slang-shaders/pull/973)). The comparisons here use that improved version, labeled xBRZ (latest).

<h2 align="center">⚖️ License</h2>

xBRZ is © Zenju and distributed under the GNU General Public License v3, as noted in the shader headers. Hyllian's xBR vertex code and texel mapping are under the MIT-style license included there. The similar diagonal check is inspired by torcado's cleanEdge (MIT license); no cleanEdge code is included.

<sub>Developed with the help of Claude (Anthropic).</sub>

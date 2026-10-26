#version 450
//#crisp{
// xBRZ crisp: xBRZ freescale that only rounds corners between clearly different colors.
//
// This is xbrz-freescale-multipass with other defaults: tools/make-multipass.py writes that shader,
// dropping the lines between //#crisp{ and //#crisp} and turning the //#plain lines on.
//
// - Minimum contrast: a corner whose two colors differ by less than XBRZ_MINC (x/255, YCbCr
//   distance) is left square, so low-contrast shading, dithering and textures (grass, foliage,
//   stone) keep their pixel detail, while outlines, text and sprites are smoothed as in xBRZ.
// - Diagonal: a corner is left square when the two colors on its diagonal (the colors the cut
//   would join) differ by more than XBRZ_DIAG, so a junction of three different colors is not
//   pulled into a fake diagonal (an idea from torcado's cleanEdge, MIT license). Antialiasing
//   ramps, where one of those colors sits between the pixel and the other one, use 92 instead.
//   Shallow and steep lines are not blocked, unless they would cut a pixel with a lighter color,
//   so dark outlines, eyes and eyebrows keep their pixels. A blocked corner is still cut when a
//   neighbour on the same diagonal is cut, so lines are drawn to the end, and at the tip of a
//   1-pixel diagonal stripe, so the stripe runs on to the edge. Between two close inner tones the
//   cut also runs up to an outline darker than both, which stays whole (not at the corner of a
//   solid block, along a 1-pixel stripe or next to a corner the artist already rounded with an
//   antialiasing pixel), and a corner whose blend color runs straight on, like a frame or a
//   horizontal line, stays square, so lines do not bend where they meet. Where two dark strokes of
//   different colors meet in an L around a 1-pixel light gap, like a pupil under an eyebrow, the
//   corner stays square. A blocked corner comes back as in xBRZ where the pixel's color runs on as a
//   45-degree diagonal along the cut up to a straight line, like hair or a fence post, unless that
//   would bend a straight line or stretch a lone 1-pixel dot. It also comes back where a 1-pixel
//   stroke lighter than both colors runs on along the cut, like the white strokes of letters.
// - Stripe ends: where a stack of 1-pixel stripes of different colors ends flush, like the bars
//   of a gauge, the end corners stay square when their diagonal colors differ by more than 64,
//   so every stripe ends the same way.
// - Line shapes: the shallow and steep line tests weigh hue a little more than lightness (1.2x),
//   so lines in hue-shifted shading follow the artist's pixels.
// XBRZ_MINC = 0 turns the first rule off, and XBRZ_DIAG = 0 the others.
//#crisp}
//#plain // xBRZ freescale, multipass: xBRZ at any scale factor, in two passes.
//#plain //
//#plain // Two optional rules, both off by default (plain xBRZ); the xbrz-crisp preset turns them on:
//#plain // - XBRZ_MINC (crisp: 24) leaves a corner square when its two colors differ by less than this
//#plain //   (x/255, YCbCr distance), so soft shading and textures keep their pixels.
//#plain // - XBRZ_DIAG (crisp: 100) leaves a corner square when the two colors its cut would join differ
//#plain //   by more than this, so a junction of three colors is not pulled into a fake diagonal (an idea
//#plain //   from torcado's cleanEdge, MIT license). Antialiasing ramps use 92, shallow and steep lines are
//#plain //   only blocked when they would cut a pixel with a lighter color, a blocked corner is still cut
//#plain //   when a neighbour on the same diagonal is cut or at the tip of a 1-pixel diagonal stripe, a cut
//#plain //   between two close inner tones runs up to a darker outline, a corner whose blend color runs
//#plain //   straight on stays square, two dark strokes meeting in an L around a light gap (an eye) are
//#plain //   not joined, and where 1-pixel stripes end flush (gauges, health bars) the end corners stay
//#plain //   square.
//#plain //   The shallow and steep line tests also weigh hue a little more than lightness (1.2x).
//
// The first pass makes every blend decision once per input pixel (blend type, line type, blend
// color and the minimum contrast), so the second pass, which runs once per output pixel, only
// reads two textures where no corner is cut. Blend color ties and the order of the four corners
// follow the reference C++ xBRZ, and the second pass reads the image from the pass before xBRZ,
// so it also works after other shaders in a preset.
// Defaults: equal color tolerance 15, dominant direction 3.8, steep/shallow line 3.2
// (reference xBRZ: 30, 3.6 and 2.2).
/*
   Hyllian's xBR-vertex code and texel mapping
   Copyright (C) 2011/2016 Hyllian - sergiogdb@gmail.com
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:
   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.
*/
// This shader also uses code and/or concepts from xBRZ as it appears
// in the Desmume source code. The license for which is as follows:
// ****************************************************************************
// * This file is part of the HqMAME project. It is distributed under         *
// * GNU General Public License: http://www.gnu.org/licenses/gpl-3.0          *
// * Copyright (C) Zenju (zenju AT gmx DOT de) - All Rights Reserved          *
// *                                                                          *
// * Additionally and as a special exception, the author gives permission     *
// * to link the code of this program with the MAME library (or with modified *
// * versions of MAME that use the same license as MAME), and distribute      *
// * linked combinations including the two. You must obey the GNU General     *
// * Public License in all respects for all of the code used other than MAME. *
// * If you modify this file, you may extend this exception to your version   *
// * of the file, but you are not obligated to do so. If you do not wish to   *
// * do so, delete this exception statement from your version.                *
// ****************************************************************************

//#crisp{
// Pass 1 of xbrz-crisp (Vulkan / slang)
//#crisp}
//#plain // Pass 1 of xbrz-freescale-multipass (Vulkan / slang)

layout(push_constant) uniform Push
{
	vec4 SourceSize;
//#crisp{
	vec4 xbrz_crisp_refpassSize;
//#crisp}
//#plain	vec4 xbrz_fs_refpassSize;
	vec4 OutputSize;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord * 1.0001;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
layout(set = 0, binding = 2) uniform sampler2D Source;
// the input of the first pass (the preset's reference pass), which is the original image unless
// other shaders run before xBRZ
//#crisp{
layout(set = 0, binding = 3) uniform sampler2D xbrz_crisp_refpass;
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define P(x,y) texture(xbrz_crisp_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
//#crisp}
//#plain layout(set = 0, binding = 3) uniform sampler2D xbrz_fs_refpass;
//#plain #define ORIG_SIZE params.xbrz_fs_refpassSize
//#plain #define P(x,y) texture(xbrz_fs_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define OUT_SIZE params.OutputSize
#define ORIG_INPUT_SIZE ORIG_SIZE
#define INFO(uv) texture(Source, uv)

float get_left_ratio(vec2 center, vec2 origin, vec2 direction, vec2 scale)
{
  vec2 P0 = center - origin;
  vec2 proj = direction * (dot(P0, direction) / dot(direction, direction));
  vec2 distv = P0 - proj;
  vec2 orth = vec2(-direction.y, direction.x);
  float side = sign(dot(P0, orth));
  float v = side * length(distv * scale);
  return smoothstep(-sqrt(2.0)/2.0, sqrt(2.0)/2.0, v);
}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping: -|B|-
  //                      D|E|F
  //                      -|H|-

  vec2 scale = OUT_SIZE.xy / ORIG_INPUT_SIZE.xy;
  vec2 pos = fract(vTexCoord * ORIG_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * ORIG_SIZE.zw;

  vec4 info = floor(INFO(coord) * 255.0 + 0.5);
  vec3 E = P( 0., 0.);
  vec3 res = E;

  // info Mapping: x|y|
  //               w|z|
  vec4 blendResult = mod(info, 4.0);

  // a corner flagged by the first pass (+128, XBRZ_DIAG) is still cut when the same corner of a
  // neighbour along the cut is cut and not flagged, so diagonal lines are drawn to the end
  if (max(max(info.x, info.y), max(info.z, info.w)) >= 128.0)
  {
    vec4 blocked = floor(info / 128.0);
    info = mod(info, 128.0);
    blendResult = mod(info, 4.0);
    vec4 nA = floor(INFO(coord + vec2( 1.0,-1.0) * ORIG_SIZE.zw) * 255.0 + 0.5);
    vec4 nB = floor(INFO(coord + vec2(-1.0, 1.0) * ORIG_SIZE.zw) * 255.0 + 0.5);
    vec4 nC = floor(INFO(coord + vec2( 1.0, 1.0) * ORIG_SIZE.zw) * 255.0 + 0.5);
    vec4 nD = floor(INFO(coord + vec2(-1.0,-1.0) * ORIG_SIZE.zw) * 255.0 + 0.5);
    vec4 aA = vec4(greaterThan(mod(nA, 4.0), vec4(0.0))) * vec4(lessThan(nA, vec4(128.0)));
    vec4 aB = vec4(greaterThan(mod(nB, 4.0), vec4(0.0))) * vec4(lessThan(nB, vec4(128.0)));
    vec4 aC = vec4(greaterThan(mod(nC, 4.0), vec4(0.0))) * vec4(lessThan(nC, vec4(128.0)));
    vec4 aD = vec4(greaterThan(mod(nD, 4.0), vec4(0.0))) * vec4(lessThan(nD, vec4(128.0)));
    // top-left and bottom-right are cut along "/", top-right and bottom-left along "\"
    vec4 chain = vec4(max(aA.x, aB.x), max(aC.y, aD.y), max(aA.z, aB.z), max(aC.w, aD.w));
    blendResult *= max(1.0 - blocked, chain);
  }

  // most output pixels have no corner to blend, and only need these two reads
  if (blendResult.x + blendResult.y + blendResult.z + blendResult.w <= 0.0)
  {
    FRAG_OUT = vec4(res, 1.0);
    return;
  }

  vec4 doLineBlend = mod(floor(info / 4.0), 2.0);
  vec4 secondPix = mod(floor(info / 8.0), 2.0);
  vec4 haveShallowLine = floor(mod(info / 16.0, 4.0));
  vec4 haveSteepLine = floor(mod(info / 64.0, 4.0));

  // Corners are applied in the same order as the original xBRZ (0, 90, 180, 270 degrees). The first
  // pass picked each blend colour ("dist(e,f) <= dist(e,h) ? f : h").

  // Pixel Tap Mapping: -|-|-
  //                    -|E|F
  //                    -|H|-
  if(blendResult.z > 0.0)
  {
    vec2 origin = vec2(0.0, 1.0 / sqrt(2.0));
    vec2 direction = vec2(1.0, -1.0);
    if(doLineBlend.z > 0.0)
    {
      origin = haveShallowLine.z > 0.0? vec2(0.0, 0.25) : vec2(0.0, 0.5);
      direction.x += haveShallowLine.z;
      direction.y -= haveSteepLine.z;
    }
    vec3 blendPix = (secondPix.z > 0.0) ? P( 0., 1.) : P( 1., 0.);
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }

  // Pixel Tap Mapping: -|B|-
  //                    -|E|F
  //                    -|-|-
  if(blendResult.y > 0.0)
  {
    vec2 origin = vec2(1.0 / sqrt(2.0), 0.0);
    vec2 direction = vec2(-1.0, -1.0);
    if(doLineBlend.y > 0.0)
    {
      origin = haveShallowLine.y > 0.0? vec2(0.25, 0.0) : vec2(0.5, 0.0);
      direction.y -= haveShallowLine.y;
      direction.x -= haveSteepLine.y;
    }
    vec3 blendPix = (secondPix.y > 0.0) ? P( 1., 0.) : P( 0.,-1.);
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }

  // Pixel Tap Mapping: -|B|-
  //                    D|E|-
  //                    -|-|-
  if(blendResult.x > 0.0)
  {
    vec2 origin = vec2(0.0, -1.0 / sqrt(2.0));
    vec2 direction = vec2(-1.0, 1.0);
    if(doLineBlend.x > 0.0)
    {
      origin = haveShallowLine.x > 0.0? vec2(0.0, -0.25) : vec2(0.0, -0.5);
      direction.x -= haveShallowLine.x;
      direction.y += haveSteepLine.x;
    }
    vec3 blendPix = (secondPix.x > 0.0) ? P( 0.,-1.) : P(-1., 0.);
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }

  // Pixel Tap Mapping: -|-|-
  //                    D|E|-
  //                    -|H|-
  if(blendResult.w > 0.0)
  {
    vec2 origin = vec2(-1.0 / sqrt(2.0), 0.0);
    vec2 direction = vec2(1.0, 1.0);
    if(doLineBlend.w > 0.0)
    {
      origin = haveShallowLine.w > 0.0? vec2(-0.25, 0.0) : vec2(-0.5, 0.0);
      direction.y += haveShallowLine.w;
      direction.x += haveSteepLine.w;
    }
    vec3 blendPix = (secondPix.w > 0.0) ? P(-1., 0.) : P( 0., 1.);
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }

  FRAG_OUT = vec4(res, 1.0);
}

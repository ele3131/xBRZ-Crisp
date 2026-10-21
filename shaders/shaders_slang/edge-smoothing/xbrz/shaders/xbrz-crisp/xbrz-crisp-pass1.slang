#version 450
/*
   xBRZ crisp: xBRZ freescale that only rounds corners between clearly different colors.

   A corner whose two colors differ by less than XBRZ_MINC (x/255, YCbCr distance) is left
   square, so low-contrast shading, dithering and textures (grass, foliage, stone) keep their
   pixel detail instead of melting into blobs, while outlines, text and sprites are smoothed
   exactly as in xBRZ. XBRZ_MINC = 0 gives plain xBRZ with the thresholds below.
   Defaults: equal color tolerance 15 and steep/shallow line threshold 3.2 (stock xBRZ: 30 and 2.2).

   Based on "xbrz-freescale-multipass" from libretro glsl-shaders / slang-shaders, with these
   differences from that port so it matches the reference C++ xBRZ more closely:
   - blend color ties and the corner order follow the original xBRZ;
   - the GLSL pass uses the input image size (not the texture size) for the output scale;
   - the thresholds are runtime parameters.

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

// Pass 1 of xbrz-crisp (Vulkan / slang)

layout(push_constant) uniform Push
{
	vec4 SourceSize;
	vec4 OriginalSize;
	vec4 OutputSize;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
	float XBRZ_TOL;
	float XBRZ_DOM;
	float XBRZ_STEEP;
	float XBRZ_LUMA;
	float XBRZ_MINC;
	float XBRZ_MINC_RAMP;
} global;

#pragma parameter XBRZ_TOL "xBRZ: equal color tolerance (x/255)" 15 1 80 1
#pragma parameter XBRZ_DOM "xBRZ: dominant direction threshold" 3.75 1 8 0.05
#pragma parameter XBRZ_STEEP "xBRZ: steep/shallow line threshold" 3.2 1 6 0.1
#pragma parameter XBRZ_LUMA "xBRZ: luminance weight" 1 0.5 3 0.1
#pragma parameter XBRZ_MINC "xBRZ crisp: minimum contrast to round a corner (x/255)" 16 0 80 2
#pragma parameter XBRZ_MINC_RAMP "xBRZ crisp: soft transition width (0 = hard cut)" 0 0 64 2
#define XBRZ_TOL global.XBRZ_TOL
#define XBRZ_DOM global.XBRZ_DOM
#define XBRZ_STEEP global.XBRZ_STEEP
#define XBRZ_LUMA global.XBRZ_LUMA
#define XBRZ_MINC global.XBRZ_MINC
#define XBRZ_MINC_RAMP global.XBRZ_MINC_RAMP

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
layout(set = 0, binding = 3) uniform sampler2D Original;
#define OUT_SIZE params.OutputSize
#define ORIG_SIZE params.OriginalSize
#define ORIG_INPUT_SIZE params.OriginalSize
#define P(x,y) texture(Original, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define INFO(uv) texture(Source, uv)

#define BLEND_NONE 0
#define BLEND_NORMAL 1
#define BLEND_DOMINANT 2
#ifndef TOL_E
#define TOL_E XBRZ_TOL
#endif
#ifndef DOM_E
#define DOM_E XBRZ_DOM
#endif
#ifndef STEEP_E
#define STEEP_E XBRZ_STEEP
#endif
#define EQUAL_COLOR_TOLERANCE (TOL_E / 255.0)

float DistYCbCr(vec3 pixA, vec3 pixB)
{
  const vec3 w = vec3(0.2627, 0.6780, 0.0593);
  const float scaleB = 0.5 / (1.0 - 0.0593);
  const float scaleR = 0.5 / (1.0 - 0.2627);
  vec3 diff = pixA - pixB;
  float Y = dot(diff.rgb, w);
  float Cb = scaleB * (diff.b - Y);
  float Cr = scaleR * (diff.r - Y);
  return sqrt(((XBRZ_LUMA * Y) * (XBRZ_LUMA * Y)) + (Cb * Cb) + (Cr * Cr));
}

bool IsPixEqual(vec3 pixA, vec3 pixB)
{
  return (DistYCbCr(pixA, pixB) < EQUAL_COLOR_TOLERANCE);
}

#define eq(a,b)  (a == b)
#define neq(a,b) (a != b)

// Minimum contrast: how much of the corner cut a blend keeps, from its colour contrast (0 none, 1 all)
float mincKeep(float d)
{
  if (XBRZ_MINC <= 0.0) return 1.0;
  if (XBRZ_MINC_RAMP < 0.5) return d * 255.0 >= XBRZ_MINC ? 1.0 : 0.0;
  return clamp((d * 255.0 - (XBRZ_MINC - 0.5 * XBRZ_MINC_RAMP)) / XBRZ_MINC_RAMP, 0.0, 1.0);
}

// moves the blend line towards the pixel corner cp, so that only the fraction k of the cut remains
vec2 shrinkOrigin(vec2 origin, vec2 direction, vec2 cp, float k)
{
  if (k >= 1.0) return origin;
  vec2 n = normalize(vec2(-direction.y, direction.x));
  return origin + n * ((1.0 - k) * dot(cp - origin, n));
}

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
  bool ramp = XBRZ_MINC > 0.0 && XBRZ_MINC_RAMP >= 0.5;

  // Corners are applied in the same order as the original xBRZ (0, 90, 180, 270 degrees). The first
  // pass picked each blend colour ("dist(e,f) <= dist(e,h) ? f : h") and applied the minimum contrast;
  // only the soft transition still needs the contrast here.

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
    float keep = ramp ? mincKeep(DistYCbCr(E, blendPix)) : 1.0;
    if (keep > 0.0)
      res = mix(res, blendPix, get_left_ratio(pos, shrinkOrigin(origin, direction, vec2( 0.5, 0.5), keep), direction, scale));
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
    float keep = ramp ? mincKeep(DistYCbCr(E, blendPix)) : 1.0;
    if (keep > 0.0)
      res = mix(res, blendPix, get_left_ratio(pos, shrinkOrigin(origin, direction, vec2( 0.5,-0.5), keep), direction, scale));
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
    float keep = ramp ? mincKeep(DistYCbCr(E, blendPix)) : 1.0;
    if (keep > 0.0)
      res = mix(res, blendPix, get_left_ratio(pos, shrinkOrigin(origin, direction, vec2(-0.5,-0.5), keep), direction, scale));
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
    float keep = ramp ? mincKeep(DistYCbCr(E, blendPix)) : 1.0;
    if (keep > 0.0)
      res = mix(res, blendPix, get_left_ratio(pos, shrinkOrigin(origin, direction, vec2(-0.5, 0.5), keep), direction, scale));
  }

  FRAG_OUT = vec4(res, 1.0);
}

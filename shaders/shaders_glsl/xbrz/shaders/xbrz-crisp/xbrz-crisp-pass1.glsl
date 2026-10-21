/*
   xBRZ crisp: xBRZ freescale that only rounds corners between clearly different colors.

   A corner whose two colors differ by less than XBRZ_MINC (x/255, YCbCr distance) is left
   square, so low-contrast shading, dithering and textures (grass, foliage, stone) keep their
   pixel detail instead of melting into blobs, while outlines, text and sprites are smoothed
   exactly as in xBRZ. XBRZ_MINC = 0 gives plain xBRZ with the thresholds below.

   A corner is also left square when the two colors on its diagonal (the colors the cut would
   join) differ by more than XBRZ_DIAG, so a junction of three different colors is not pulled
   into a fake diagonal (an idea from torcado's cleanEdge, MIT license). Antialiasing ramps, where
   one of those colors sits between the pixel and the other one, use XBRZ_DIAG_AA instead,
   shallow and steep lines are never blocked, and a blocked corner is still cut when a neighbour
   on the same diagonal is cut, so lines are drawn to the end. XBRZ_DIAG = 0 turns this off.
   Where a stack of 1-pixel stripes of different colors ends flush, like the bars of a gauge, the
   end corners stay square when their diagonal colors differ by more than XBRZ_TIP, so every
   stripe ends the same way. XBRZ_TIP = 0 turns this off.
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

// Pass 1 of xbrz-crisp (OpenGL / GLES)
#pragma parameter XBRZ_TOL "xBRZ: equal color tolerance (x/255)" 15 1 80 1
#pragma parameter XBRZ_DOM "xBRZ: dominant direction threshold" 3.8 1 8 0.05
#pragma parameter XBRZ_STEEP "xBRZ: steep/shallow line threshold" 3.2 1 6 0.1
#pragma parameter XBRZ_LUMA "xBRZ: luminance weight" 1 0.5 3 0.1
#pragma parameter XBRZ_MINC "xBRZ crisp: minimum contrast to round a corner (x/255)" 16 0 80 2
#pragma parameter XBRZ_MINC_RAMP "xBRZ crisp: soft transition width (0 = hard cut)" 0 0 64 2
#pragma parameter XBRZ_DIAG "xBRZ crisp: max color distance on the diagonal (0 = off)" 100 0 160 4
#pragma parameter XBRZ_DIAG_AA "xBRZ crisp: same limit for antialiasing ramps" 92 0 160 4

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 COL0;
COMPAT_VARYING vec4 TEX0;

uniform mat4 MVPMatrix;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    TEX0.xy = TexCoord.xy * 1.0001;
}

#elif defined(FRAGMENT)

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out COMPAT_PRECISION vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;
#define vTexCoord TEX0.xy
#define FRAG_OUT FragColor
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float XBRZ_TOL;
uniform COMPAT_PRECISION float XBRZ_DOM;
uniform COMPAT_PRECISION float XBRZ_STEEP;
uniform COMPAT_PRECISION float XBRZ_LUMA;
uniform COMPAT_PRECISION float XBRZ_MINC;
uniform COMPAT_PRECISION float XBRZ_MINC_RAMP;
uniform COMPAT_PRECISION float XBRZ_DIAG;
uniform COMPAT_PRECISION float XBRZ_DIAG_AA;
#else
#define XBRZ_TOL 15.0
#define XBRZ_DOM 3.8
#define XBRZ_STEEP 3.2
#define XBRZ_LUMA 1.0
#define XBRZ_MINC 16.0
#define XBRZ_MINC_RAMP 0.0
#define XBRZ_DIAG 100.0
#define XBRZ_DIAG_AA 92.0
#endif

uniform sampler2D OrigTexture;
uniform COMPAT_PRECISION vec2 OrigTextureSize;
uniform COMPAT_PRECISION vec2 OrigInputSize;
#define OUT_SIZE OutputSize
#define ORIG_SIZE vec4(OrigTextureSize, 1.0 / OrigTextureSize)
#define ORIG_INPUT_SIZE OrigInputSize
#define P(x,y) COMPAT_TEXTURE(OrigTexture, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, uv)

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

#endif

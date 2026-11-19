//#crisp{
// xBRZ crisp: xBRZ freescale that only rounds corners between clearly different colors.
// See xbrz-crisp-pass0 for the full numbered rule catalog and pipeline overview.
//#crisp}
//#plain // xBRZ freescale, multipass: xBRZ at any scale factor, in four passes.
//#plain // See xbrz-freescale-pass0 / xbrz-crisp-pass0 for the full numbered rule catalog.
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
// Pass 1 of xbrz-crisp (OpenGL / GLES)
//#crisp}
//#plain // Pass 1 of xbrz-freescale-multipass (OpenGL / GLES)

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
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#define COMPAT_PRECISION highp
#else
precision mediump float;
#define COMPAT_PRECISION mediump
#endif
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 TEX0;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION vec2 OutputSize;
//#crisp{
uniform COMPAT_PRECISION vec2 PassPrev4InputSize;
//#crisp}
//#plain uniform COMPAT_PRECISION vec2 PassPrev3InputSize;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    TEX0.xy = TexCoord.xy * 1.0001;
//#crisp{
    TEX0.zw = OutputSize / PassPrev4InputSize;
//#crisp}
//#plain     TEX0.zw = OutputSize / PassPrev3InputSize;
}

#elif defined(FRAGMENT)

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#define COMPAT_PRECISION highp
#else
precision mediump float;
#define COMPAT_PRECISION mediump
#endif
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

//#crisp{
// the point pass (four passes back: pass 0, the resolve pass and the match pass come between), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev4Texture;
uniform COMPAT_PRECISION vec2 PassPrev4TextureSize;
#define OUT_SIZE OutputSize
#define ORIG_SIZE vec4(PassPrev4TextureSize, 1.0 / PassPrev4TextureSize)
#define ORIG_INPUT_SIZE PassPrev4InputSize
//#crisp}
//#plain // the point pass (three passes back: pass 0 and the resolve pass come between), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
//#plain uniform sampler2D PassPrev3Texture;
//#plain uniform COMPAT_PRECISION vec2 PassPrev3TextureSize;
//#plain #define OUT_SIZE OutputSize
//#plain #define ORIG_SIZE vec4(PassPrev3TextureSize, 1.0 / PassPrev3TextureSize)
//#plain #define ORIG_INPUT_SIZE PassPrev3InputSize
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
//#crisp{
#define P(x,y) COMPAT_TEXTURE(PassPrev4Texture, ocoord + ORIG_SIZE.zw * vec2(x, y)).rgb
//#crisp}
//#plain #define P(x,y) COMPAT_TEXTURE(PassPrev3Texture, ocoord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, uv)
#define INFO_STEP SRC_SIZE.zw

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

// the first pass's decisions for the four corners of the pixel at (x, y) from E; see the decision
// word in pass 0 (BLEND is the blend type, FLAG(r, f) one of its flags)
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
//#crisp{
#define XBRZ_TIPK 0.1  // 23. a loose pixel's tip: the cut line moves out by this
//#crisp}

// Evaluates the coverage ratio of a cut corner in the canonical bottom-right (z) frame; the other
// corners pass pos and scale rotated by multiples of 90 degrees.
float cornerRatio(vec2 p, vec2 sc, float doLine, float sh, float st, float bothL
//#crisp{
                  , float tipK, float lg, float shA
//#crisp}
                  )
{
  vec2 origin = vec2(0.0, 1.0 / sqrt(2.0));
//#crisp{
  origin *= tipK;
//#crisp}
  vec2 direction = vec2(1.0, -1.0);
  if (doLine > 0.0)
  {
    origin = sh > 0.0 ? vec2(0.0, 0.25) : vec2(0.0, 0.5);
    direction.x += sh;
    direction.y -= st;
//#crisp{
    if (lg > 0.0)
    {
      if (sh > 0.0) origin = vec2(0.5, 0.0);
      origin += shA * (sh > 0.0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
      direction.x += sh * lg;
      direction.y -= st * lg;
    }
//#crisp}
  }
  float ratio = get_left_ratio(p, origin, direction, sc);
  if (bothL > 0.0)
    ratio = max(get_left_ratio(p, vec2(0.0, 0.25), vec2(1.0, -1.0) + vec2(1.0, 0.0), sc),
                get_left_ratio(p, vec2(0.0, 0.5), vec2(1.0, -1.0) + vec2(0.0, -1.0), sc));
  return ratio;
}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping: -|B|-
  //                      D|E|F
  //                      -|H|-

  vec2 scale = TEX0.zw;
  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;
  vec2 ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;

  vec4 info = INFO_AT(0.0, 0.0);
  vec3 E = P( 0., 0.);
  vec3 res = E;

  // info Mapping: x|y|
  //               w|z|
  vec4 blendResult = BLEND(info);

  // most output pixels have no corner to blend, and only need these two reads
  if (blendResult.x + blendResult.y + blendResult.z + blendResult.w <= 0.0)
  {
    FRAG_OUT = vec4(res, 1.0);
    return;
  }

//#crisp{
  vec4 tip = 1.0 + XBRZ_TIPK * vec4(equal(blendResult, vec4(3.0)));
//#crisp}
  vec4 doLineBlend = FLAG(info, 4.0);
  vec4 secondPix = FLAG(info, 8.0);
  vec4 haveShallowLine = FLAG(info, 16.0);
  vec4 haveSteepLine = FLAG(info, 64.0);
  vec4 bothLines = doLineBlend * haveShallowLine * haveSteepLine;
//#crisp{
  vec4 longL = FLAG(info, 32.0) + 2.0 * FLAG(info, 128.0);
  vec4 shiftA = vec4(equal(blendResult, vec4(2.0))) * vec4(greaterThan(longL, vec4(0.0)));
  bothLines *= vec4(equal(longL, vec4(0.0)));
//#crisp}

  // ============================================================================================
  // xBRZ: drawing the corners (0, 90, 180, 270 degrees); neighbor color is fetched only when ratio > 0
  // ============================================================================================
  if (blendResult.z > 0.0)
  {
    float ratio = cornerRatio(pos, scale, doLineBlend.z, haveShallowLine.z, haveSteepLine.z, bothLines.z
//#crisp{
                              , tip.z, longL.z, shiftA.z
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.z > 0.0) ? vec2( 0., 1.) : vec2( 1., 0.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.y > 0.0)
  {
    float ratio = cornerRatio(vec2(-pos.y, pos.x), scale.yx, doLineBlend.y, haveShallowLine.y, haveSteepLine.y, bothLines.y
//#crisp{
                              , tip.y, longL.y, shiftA.y
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.y > 0.0) ? vec2( 1., 0.) : vec2( 0.,-1.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.x > 0.0)
  {
    float ratio = cornerRatio(-pos, scale, doLineBlend.x, haveShallowLine.x, haveSteepLine.x, bothLines.x
//#crisp{
                              , tip.x, longL.x, shiftA.x
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.x > 0.0) ? vec2( 0.,-1.) : vec2(-1., 0.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.w > 0.0)
  {
    float ratio = cornerRatio(vec2(pos.y, -pos.x), scale.yx, doLineBlend.w, haveShallowLine.w, haveSteepLine.w, bothLines.w
//#crisp{
                              , tip.w, longL.w, shiftA.w
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.w > 0.0) ? vec2(-1., 0.) : vec2( 0., 1.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  FRAG_OUT = vec4(res, 1.0);
}

#endif

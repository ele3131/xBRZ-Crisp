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
precision highp float;
#define COMPAT_PRECISION highp
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 TEX0;
COMPAT_VARYING vec4 TEX1;
COMPAT_VARYING vec4 TEX2;
COMPAT_VARYING vec4 TEX3;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
//#crisp{
uniform COMPAT_PRECISION vec2 PassPrev4TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev4InputSize;
//#crisp}
//#plain uniform COMPAT_PRECISION vec2 PassPrev3TextureSize;
//#plain uniform COMPAT_PRECISION vec2 PassPrev3InputSize;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
//#crisp{
    vec2 origTex = PassPrev4TextureSize;
    vec2 origIn = PassPrev4InputSize;
//#crisp}
//#plain     vec2 origTex = PassPrev3TextureSize;
//#plain     vec2 origIn = PassPrev3InputSize;
    vec2 sc = OutputSize / origIn;
    float scArea = (sc.x * sc.y) * 0.7071067811865475;
    float sx2 = sc.x * sc.x, sy2 = sc.y * sc.y;
    TEX0 = vec4(TexCoord.xy, sc);
    TEX1 = vec4(scArea * inversesqrt(vec3(sx2 + sy2, 4.0 * sx2 + sy2, sx2 + 4.0 * sy2)), scArea);
    vec2 srcInv = 1.0 / TextureSize;
    vec2 origInv = 1.0 / origTex;
    TEX2 = vec4(srcInv, origInv);
    TEX3 = vec4((origIn - 0.5) * origInv, TextureSize * origInv);
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
COMPAT_VARYING vec4 TEX1;
COMPAT_VARYING vec4 TEX2;
COMPAT_VARYING vec4 TEX3;
#define vTexCoord TEX0.xy
#define FRAG_OUT FragColor

//#crisp{
// the point pass (four passes back: pass 0, the resolve pass and the match pass come between), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev4Texture;
uniform COMPAT_PRECISION vec2 PassPrev4TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev4InputSize;
#define OUT_SIZE OutputSize
#define ORIG_TEX_SIZE PassPrev4TextureSize
#define ORIG_INPUT_SIZE PassPrev4InputSize
//#crisp}
//#plain // the point pass (three passes back: pass 0 and the resolve pass come between), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
//#plain uniform sampler2D PassPrev3Texture;
//#plain uniform COMPAT_PRECISION vec2 PassPrev3TextureSize;
//#plain uniform COMPAT_PRECISION vec2 PassPrev3InputSize;
//#plain #define OUT_SIZE OutputSize
//#plain #define ORIG_TEX_SIZE PassPrev3TextureSize
//#plain #define ORIG_INPUT_SIZE PassPrev3InputSize
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define CLAMP_ORIG(uv) min((uv), origMax)
//#crisp{
#define P_CENTER COMPAT_TEXTURE(PassPrev4Texture, ocoord).rgb
#define P(x,y) COMPAT_TEXTURE(PassPrev4Texture, CLAMP_ORIG(ocoord + origInv * vec2(x, y))).rgb
//#crisp}
//#plain #define P_CENTER COMPAT_TEXTURE(PassPrev3Texture, ocoord).rgb
//#plain #define P(x,y) COMPAT_TEXTURE(PassPrev3Texture, CLAMP_ORIG(ocoord + origInv * vec2(x, y))).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, uv)

const float INV_SQRT2 = 0.7071067811865475;

// the first pass's decisions for the four corners of the pixel at (x, y) from E; see the decision
// word in pass 0 (BLEND is the blend type, FLAG(r, f) one of its flags)
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
//#crisp{
#define XBRZ_TIPK 0.1  // 23. a loose pixel's tip: the cut line moves out by this
//#crisp}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping: -|B|-
  //                      D|E|F
  //                      -|H|-

  vec2 scale = TEX0.zw;
  vec3 scK = TEX1.xyz;
  float scArea = TEX1.w;
  vec2 srcInv = TEX2.xy;
  vec2 origInv = TEX2.zw;
  vec2 origMax = TEX3.xy;
  vec2 pos = fract(vTexCoord * TextureSize) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * srcInv;
  vec2 ocoord = coord * TEX3.zw;

  vec4 rawInfo = INFO(coord);

  // most output pixels have no corner to blend, and only need these two reads
  if (dot(rawInfo, vec4(1.0)) < 0.5 / 255.0)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }

  vec4 info = floor(rawInfo * 255.0 + 0.5);
  // info Mapping: x|y|
  //               w|z|
  vec4 blendResult = BLEND(info);
  vec4 isCut = vec4(greaterThan(blendResult, vec4(0.0)));
  vec4 doLineBlend = FLAG(info, 4.0);
  vec4 secondPix = FLAG(info, 8.0);
  vec4 haveShallowLine = FLAG(info, 16.0);
  vec4 haveSteepLine = FLAG(info, 64.0);
//#crisp{
  vec4 tip = 1.0 + XBRZ_TIPK * vec4(equal(blendResult, vec4(3.0)));
  vec4 longL = FLAG(info, 32.0) + 2.0 * FLAG(info, 128.0);
//#crisp}

  // Vectorized exact signed distance (pre-scaled by INV_SQRT2) for all 4 corners in canonical BR frame
  vec4 px = vec4(-pos.x, -pos.y,  pos.x,  pos.y);
  vec4 py = vec4(-pos.y,  pos.x,  pos.y, -pos.x);
  vec4 kSh = scK.yzyz;
  vec4 kSt = scK.zyzy;

  vec4 pSum = px + py;
//#crisp{
  vec4 dPlain = (pSum - INV_SQRT2 * tip) * scK.x;
//#crisp}
//#plain   vec4 dPlain = (pSum - INV_SQRT2) * scK.x;
  vec4 dLine45 = (pSum - 0.5) * scK.x;
  vec4 dSh = (px + 2.0 * py - 0.5) * kSh;
  vec4 dSt = (2.0 * px + py - 0.5) * kSt;
  vec4 d = mix(dPlain,
               mix(mix(dLine45, dSh, haveShallowLine),
                   mix(dSt, max(dSh, dSt), haveShallowLine),
                   haveSteepLine),
               doLineBlend);

//#crisp{
  vec4 isLong = isCut * doLineBlend * vec4(greaterThan(longL, vec4(0.0)));
  if (dot(isLong, vec4(1.0)) > 0.0)
  {
    float sx2 = scale.x * scale.x, sy2 = scale.y * scale.y;
    vec4 shiftA = vec4(equal(blendResult, vec4(2.0)));
    vec4 ox = (0.5 + shiftA) * haveShallowLine;
    vec4 oy = (0.5 + shiftA) * (1.0 - haveShallowLine);
    vec4 dx = 1.0 + haveShallowLine * (1.0 + longL);
    vec4 dy = 1.0 + haveSteepLine * (1.0 + longL);
    vec4 scX2 = vec4(sx2, sy2, sx2, sy2);
    vec4 scY2 = vec4(sy2, sx2, sy2, sx2);
    vec4 dLong = scArea * ((px - ox) * dy + (py - oy) * dx) * inversesqrt(dx * dx * scX2 + dy * dy * scY2);
    d = mix(d, dLong, isLong);
  }
//#crisp}

  // Exact smoothstep(-INV_SQRT2, INV_SQRT2, d_raw): d is already multiplied by INV_SQRT2
  vec4 t = isCut * clamp(d + 0.5, 0.0, 1.0);
  if (dot(t, vec4(1.0)) <= 1e-6)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }
  vec4 ratios = t * t * (3.0 - 2.0 * t);

  // ============================================================================================
  // xBRZ: drawing the corners (0, 90, 180, 270 degrees); neighbor color is fetched only when ratio > 0
  // ============================================================================================
//#crisp{
  float sumR = ratios.x + ratios.y + ratios.z + ratios.w;
  vec3 accCol = vec3(0.0);
  float keepE = 1.0;
  if (ratios.z > 0.0) { vec2 bo = secondPix.z > 0.0 ? vec2( 0., 1.) : vec2( 1., 0.); accCol += ratios.z * P(bo.x, bo.y); keepE *= 1.0 - ratios.z; }
  if (ratios.y > 0.0) { vec2 bo = secondPix.y > 0.0 ? vec2( 1., 0.) : vec2( 0.,-1.); accCol += ratios.y * P(bo.x, bo.y); keepE *= 1.0 - ratios.y; }
  if (ratios.x > 0.0) { vec2 bo = secondPix.x > 0.0 ? vec2( 0.,-1.) : vec2(-1., 0.); accCol += ratios.x * P(bo.x, bo.y); keepE *= 1.0 - ratios.x; }
  if (ratios.w > 0.0) { vec2 bo = secondPix.w > 0.0 ? vec2(-1., 0.) : vec2( 0., 1.); accCol += ratios.w * P(bo.x, bo.y); keepE *= 1.0 - ratios.w; }
  vec3 res = accCol / sumR;
  if (keepE > 1e-5) res = mix(P_CENTER, res, 1.0 - keepE);
  FRAG_OUT = vec4(res, 1.0);
//#crisp}
//#plain   vec3 res = P_CENTER;
//#plain   if (ratios.z > 0.0) { vec2 bo = secondPix.z > 0.0 ? vec2( 0., 1.) : vec2( 1., 0.); res = mix(res, P(bo.x, bo.y), ratios.z); }
//#plain   if (ratios.y > 0.0) { vec2 bo = secondPix.y > 0.0 ? vec2( 1., 0.) : vec2( 0.,-1.); res = mix(res, P(bo.x, bo.y), ratios.y); }
//#plain   if (ratios.x > 0.0) { vec2 bo = secondPix.x > 0.0 ? vec2( 0.,-1.) : vec2(-1., 0.); res = mix(res, P(bo.x, bo.y), ratios.x); }
//#plain   if (ratios.w > 0.0) { vec2 bo = secondPix.w > 0.0 ? vec2(-1., 0.) : vec2( 0., 1.); res = mix(res, P(bo.x, bo.y), ratios.w); }
//#plain   FRAG_OUT = vec4(res, 1.0);
}

#endif

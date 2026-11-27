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
#if __VERSION__ < 300
COMPAT_VARYING vec4 TEX2;
COMPAT_VARYING vec4 TEX3;
#endif

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
#if __VERSION__ >= 300
    TEX0 = vec4(TexCoord.xy * TextureSize, sc);
#else
    TEX0 = vec4(TexCoord.xy, sc);
    vec2 srcInv = 1.0 / TextureSize;
    vec2 origInv = 1.0 / origTex;
    TEX2 = vec4(srcInv, origInv);
    TEX3 = vec4((origIn - 0.5) * origInv, TextureSize * origInv);
#endif
    TEX1 = vec4(scArea * inversesqrt(vec3(sx2 + sy2, 4.0 * sx2 + sy2, sx2 + 4.0 * sy2)), scArea);
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
#if defined(GL_ES) && __VERSION__ >= 300
precision highp int;
#endif

uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;
COMPAT_VARYING vec4 TEX1;
#if __VERSION__ < 300
COMPAT_VARYING vec4 TEX2;
COMPAT_VARYING vec4 TEX3;
#endif
#define vTexCoord TEX0.xy
#define FRAG_OUT FragColor

#define MP
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
#if __VERSION__ >= 300
//#crisp{
#define P_CENTER texelFetch(PassPrev4Texture, ipx, 0).rgb
#define P(x,y) texelFetch(PassPrev4Texture, clamp(ipx + ivec2(int(x), int(y)), ivec2(0), maxOrig), 0).rgb
//#crisp}
//#plain #define P_CENTER texelFetch(PassPrev3Texture, ipx, 0).rgb
//#plain #define P(x,y) texelFetch(PassPrev3Texture, clamp(ipx + ivec2(int(x), int(y)), ivec2(0), maxOrig), 0).rgb
#define INFO_CENTER texelFetch(Texture, ipx, 0)
//#crisp{
#define INFO_AT(x, y) texelFetch(Texture, clamp(ipx + ivec2(int(x), int(y)), ivec2(0), maxOrig), 0)
//#crisp}
#else
#define CLAMP_ORIG(uv) min((uv), origMax)
//#crisp{
#define P_CENTER COMPAT_TEXTURE(PassPrev4Texture, ocoord).rgb
#define P(x,y) COMPAT_TEXTURE(PassPrev4Texture, CLAMP_ORIG(ocoord + origInv * vec2(x, y))).rgb
//#crisp}
//#plain #define P_CENTER COMPAT_TEXTURE(PassPrev3Texture, ocoord).rgb
//#plain #define P(x,y) COMPAT_TEXTURE(PassPrev3Texture, CLAMP_ORIG(ocoord + origInv * vec2(x, y))).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, uv)
#define INFO_CENTER INFO(coord)
//#crisp{
#define INFO_AT(x, y) INFO(clamp(coord + srcInv * vec2(x, y), vec2(0.0), (InputSize - 0.5) * srcInv))
//#crisp}
#endif

const float INV_SQRT2 = 0.7071067811865475;

#if __VERSION__ < 300
// the first pass's decisions for the four corners of the pixel at (x, y) from E; see the decision
// word in pass 0 (BLEND is the blend type, FLAG(r, f) one of its flags)
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
#endif
//#crisp{
#define XBRZ_TIPK 0.1  // 23. a loose pixel's tip: the cut line moves out by this

// Exact C1 signed distance to the corner chip outside a quarter-circle of radius r
// centered at (c, c) where c = 0.5 - r, tangent to y = 0.5 at (c, 0.5) and x = 0.5 at (0.5, c).
// Exact D4-symmetric in (cpx, cpy) with zero AA bleed along flat walls.
float sdCornerArc(float cpx, float cpy, float r)
{
  float c = 0.5 - r;
  float dx = cpx - c, dy = cpy - c;
  if (dx >= 0.0 && dy >= 0.0) return length(vec2(dx, dy)) - r;
  if (dx <  0.0 && dy >= 0.0) return -length(vec2(dx, cpy - 0.5));
  if (dy <  0.0 && dx >= 0.0) return -length(vec2(cpx - 0.5, dy));
  return -min(length(vec2(dx, cpy - 0.5)), length(vec2(cpx - 0.5, dy)));
}

#if __VERSION__ >= 300
bool cIs45U(uint w)  { return (w & 3u) != 0u && ((w >> 2u) & 1u) != 0u && (w & 240u) == 0u; }
bool cIsShLU(uint w) { return (w & 3u) != 0u && ((w >> 2u) & 1u) != 0u && ((w >> 4u) & 1u) != 0u && ((w >> 6u) & 1u) == 0u; }
bool cIsStLU(uint w) { return (w & 3u) != 0u && ((w >> 2u) & 1u) != 0u && ((w >> 6u) & 1u) != 0u && ((w >> 4u) & 1u) == 0u; }
bool flat45ArcU(uint wx, uint wy, uint wxr, uint wyr)
{
  bool p0Cont = cIs45U(wy) || cIsStLU(wy) || cIs45U(wyr) || cIsShLU(wyr);
  bool p1Cont = cIs45U(wx) || cIsShLU(wx) || cIs45U(wxr) || cIsStLU(wxr);
  return !p0Cont && !p1Cont;
}
#else
bool cIs45F(float w)  { return BLEND(w) > 0.0 && FLAG(w, 4.0) > 0.5 && (FLAG(w, 16.0) + FLAG(w, 32.0) + FLAG(w, 64.0) + FLAG(w, 128.0)) < 0.5; }
bool cIsShLF(float w) { return BLEND(w) > 0.0 && FLAG(w, 4.0) > 0.5 && FLAG(w, 16.0) > 0.5 && FLAG(w, 64.0) < 0.5; }
bool cIsStLF(float w) { return BLEND(w) > 0.0 && FLAG(w, 4.0) > 0.5 && FLAG(w, 64.0) > 0.5 && FLAG(w, 16.0) < 0.5; }
bool flat45ArcF(float wx, float wy, float wxr, float wyr)
{
  bool p0Cont = cIs45F(wy) || cIsStLF(wy) || cIs45F(wyr) || cIsShLF(wyr);
  bool p1Cont = cIs45F(wx) || cIsShLF(wx) || cIs45F(wxr) || cIsStLF(wxr);
  return !p0Cont && !p1Cont;
}
#endif
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
#if __VERSION__ >= 300
  vec2 pos = fract(vTexCoord) - vec2(0.5, 0.5);
  ivec2 maxOrig = ivec2(ORIG_INPUT_SIZE) - ivec2(1);
  ivec2 ipx = clamp(ivec2(floor(vTexCoord)), ivec2(0), maxOrig);
#else
  vec2 srcInv = TEX2.xy;
  vec2 origInv = TEX2.zw;
  vec2 origMax = TEX3.xy;
  vec2 pos = fract(vTexCoord * TextureSize) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * srcInv;
  vec2 ocoord = coord * TEX3.zw;
#endif

  vec4 rawInfo = INFO_CENTER;

  // most output pixels have no corner to blend, and only need these two reads
  if (dot(rawInfo, vec4(1.0)) < 0.5 / 255.0)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }

  // info Mapping: x|y|
  //               w|z|
#if __VERSION__ >= 300
  uvec4 iw = uvec4(rawInfo * 255.0 + 0.5);
  uvec4 blU = iw & 3u;
  MP vec4 blendResult = vec4(blU);
  MP vec4 isCut = vec4(notEqual(blU, uvec4(0u)));
  MP vec4 doLineBlend = vec4((iw >> 2u) & 1u);
  MP vec4 secondPix = vec4((iw >> 3u) & 1u);
  MP vec4 haveShallowLine = vec4((iw >> 4u) & 1u);
  MP vec4 haveSteepLine = vec4((iw >> 6u) & 1u);
//#crisp{
  MP vec4 tip = 1.0 + XBRZ_TIPK * vec4(equal(blU, uvec4(3u)));
//#crisp}
#else
  vec4 info = floor(rawInfo * 255.0 + 0.5);
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
#endif

  // Vectorized exact signed distance (pre-scaled by INV_SQRT2) for all 4 corners in canonical BR frame
  vec4 px = vec4(-pos.x, -pos.y,  pos.x,  pos.y);
  vec4 py = vec4(-pos.y,  pos.x,  pos.y, -pos.x);

  vec4 pSum = px + py;
//#crisp{
  vec4 d = (pSum - mix(INV_SQRT2 * tip, vec4(0.5), doLineBlend)) * scK.x;
//#crisp}
//#plain   vec4 d = (pSum - mix(vec4(INV_SQRT2), vec4(0.5), doLineBlend)) * scK.x;
#if __VERSION__ >= 300
  if (any(notEqual(iw & uvec4(80u), uvec4(0u))))
#else
  if (dot(doLineBlend * (haveShallowLine + haveSteepLine), vec4(1.0)) > 0.0)
#endif
  {
    vec4 dSh = (px + 2.0 * py - 0.5) * scK.yzyz;
    vec4 dSt = (2.0 * px + py - 0.5) * scK.zyzy;
    vec4 dLine = mix(mix(d, dSh, haveShallowLine),
                     mix(dSt, max(dSh, dSt), haveShallowLine),
                     haveSteepLine);
    d = mix(d, dLine, doLineBlend);
  }

//#crisp{
#if __VERSION__ >= 300
  if (any(notEqual(iw & uvec4(160u), uvec4(0u))))
  {
    MP vec4 longL = vec4(((iw >> 5u) & 1u) | (((iw >> 7u) & 1u) << 1u));
#endif
    MP vec4 isLong = isCut * doLineBlend * vec4(greaterThan(longL, vec4(0.0)));
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
#if __VERSION__ >= 300
  }
#endif
//#crisp}

  // Exact smoothstep(-INV_SQRT2, INV_SQRT2, d_raw): d is already multiplied by INV_SQRT2.
  // Because sdCornerArc(px, py, r) * scArc <= d_lin wherever d_lin <= -0.5 (Cauchy-Schwarz),
  // any corner already at t == 0 can skip B1-arc and its neighbor fetches bit-exactly.
  MP vec4 t = isCut * clamp(d + 0.5, 0.0, 1.0);
  if (dot(t, vec4(1.0)) <= 1e-4)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }

//#crisp{
  // C1 circular fillets on surviving corners only: plain bevels (0 neighbor fetches)
  // and isolated 45-deg corners meeting flat H & V walls (only the 2 neighbors of the active corner).
  MP float scArc = scK.x * 1.4142135623730951;
  MP vec4 actBev = vec4(greaterThan(t, vec4(0.0))) * (1.0 - doLineBlend);
  if (dot(actBev, vec4(1.0)) > 0.0)
  {
    MP vec4 rBev = max(vec4(0.05), 1.0 - INV_SQRT2 * tip);
    if (actBev.x > 0.5) d.x = sdCornerArc(px.x, py.x, rBev.x) * scArc;
    if (actBev.y > 0.5) d.y = sdCornerArc(px.y, py.y, rBev.y) * scArc;
    if (actBev.z > 0.5) d.z = sdCornerArc(px.z, py.z, rBev.z) * scArc;
    if (actBev.w > 0.5) d.w = sdCornerArc(px.w, py.w, rBev.w) * scArc;
    t = isCut * clamp(d + 0.5, 0.0, 1.0);
  }
#if __VERSION__ >= 300
  uvec4 act45U = uvec4(greaterThan(t, vec4(0.0))) * ((iw >> 2u) & 1u) * uvec4(equal(iw & uvec4(240u), uvec4(0u)));
  if (any(notEqual(act45U, uvec4(0u))))
  {
    if (act45U.x != 0u)
    {
      uvec4 iD = uvec4(INFO_AT(-1.0,  0.0) * 255.0 + 0.5);
      uvec4 iB = uvec4(INFO_AT( 0.0, -1.0) * 255.0 + 0.5);
      if (flat45ArcU(iD.z, iB.z, iD.y, iB.w)) d.x = sdCornerArc(px.x, py.x, 0.5) * scArc;
    }
    if (act45U.y != 0u)
    {
      uvec4 iB = uvec4(INFO_AT( 0.0, -1.0) * 255.0 + 0.5);
      uvec4 iF = uvec4(INFO_AT( 1.0,  0.0) * 255.0 + 0.5);
      if (flat45ArcU(iB.w, iF.w, iB.z, iF.x)) d.y = sdCornerArc(px.y, py.y, 0.5) * scArc;
    }
    if (act45U.z != 0u)
    {
      uvec4 iF = uvec4(INFO_AT( 1.0,  0.0) * 255.0 + 0.5);
      uvec4 iH = uvec4(INFO_AT( 0.0,  1.0) * 255.0 + 0.5);
      if (flat45ArcU(iF.x, iH.x, iF.w, iH.y)) d.z = sdCornerArc(px.z, py.z, 0.5) * scArc;
    }
    if (act45U.w != 0u)
    {
      uvec4 iH = uvec4(INFO_AT( 0.0,  1.0) * 255.0 + 0.5);
      uvec4 iD = uvec4(INFO_AT(-1.0,  0.0) * 255.0 + 0.5);
      if (flat45ArcU(iH.y, iD.y, iH.x, iD.z)) d.w = sdCornerArc(px.w, py.w, 0.5) * scArc;
    }
    t = isCut * clamp(d + 0.5, 0.0, 1.0);
  }
#else
  vec4 act45 = vec4(greaterThan(t, vec4(0.0))) * doLineBlend * (1.0 - haveShallowLine) * (1.0 - haveSteepLine) * vec4(equal(longL, vec4(0.0)));
  if (dot(act45, vec4(1.0)) > 0.0)
  {
    if (act45.x > 0.5)
    {
      vec4 iD = floor(INFO_AT(-1.0,  0.0) * 255.0 + 0.5);
      vec4 iB = floor(INFO_AT( 0.0, -1.0) * 255.0 + 0.5);
      if (flat45ArcF(iD.z, iB.z, iD.y, iB.w)) d.x = sdCornerArc(px.x, py.x, 0.5) * scArc;
    }
    if (act45.y > 0.5)
    {
      vec4 iB = floor(INFO_AT( 0.0, -1.0) * 255.0 + 0.5);
      vec4 iF = floor(INFO_AT( 1.0,  0.0) * 255.0 + 0.5);
      if (flat45ArcF(iB.w, iF.w, iB.z, iF.x)) d.y = sdCornerArc(px.y, py.y, 0.5) * scArc;
    }
    if (act45.z > 0.5)
    {
      vec4 iF = floor(INFO_AT( 1.0,  0.0) * 255.0 + 0.5);
      vec4 iH = floor(INFO_AT( 0.0,  1.0) * 255.0 + 0.5);
      if (flat45ArcF(iF.x, iH.x, iF.w, iH.y)) d.z = sdCornerArc(px.z, py.z, 0.5) * scArc;
    }
    if (act45.w > 0.5)
    {
      vec4 iH = floor(INFO_AT( 0.0,  1.0) * 255.0 + 0.5);
      vec4 iD = floor(INFO_AT(-1.0,  0.0) * 255.0 + 0.5);
      if (flat45ArcF(iH.y, iD.y, iH.x, iD.z)) d.w = sdCornerArc(px.w, py.w, 0.5) * scArc;
    }
    t = isCut * clamp(d + 0.5, 0.0, 1.0);
  }
#endif
  if (dot(t, vec4(1.0)) <= 1e-4)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }
//#crisp}
  MP vec4 ratios = t * t * (3.0 - 2.0 * t);

  // ============================================================================================
  // xBRZ: drawing the corners (0, 90, 180, 270 degrees); neighbor color is fetched only when ratio > 0
  // ============================================================================================
//#crisp{
  MP float sumR = dot(ratios, vec4(1.0));
  if (sumR <= 1e-4)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }
  MP vec4 om = 1.0 - ratios;
  MP float keepE = (om.x * om.y) * (om.z * om.w);
  MP float maxR = max(max(ratios.x, ratios.y), max(ratios.z, ratios.w));
  MP vec4 w = ratios;
  MP float sumW = sumR;
  if (sumR > maxR + 1e-4)
  {
    // Depth-sensitive weighting when 2+ corners overlap at the same output subpixel:
    // prefer the deeper half-plane (larger signed distance d) to prevent AA fringe bleed.
    vec4 dAct = mix(vec4(-1e4), d, isCut);
    float dMax = max(max(dAct.x, dAct.y), max(dAct.z, dAct.w));
    MP vec4 dw = clamp(1.0 - (dMax - d), 0.0, 1.0);
    w = ratios * (dw * dw);
    sumW = dot(w, vec4(1.0));
  }
  MP float wF = w.z * (1.0 - secondPix.z) + w.y * secondPix.y;
  MP float wH = w.z * secondPix.z         + w.w * (1.0 - secondPix.w);
  MP float wB = w.y * (1.0 - secondPix.y) + w.x * secondPix.x;
  MP float wD = w.x * (1.0 - secondPix.x) + w.w * secondPix.w;
  MP vec3 accCol = vec3(0.0);
  if (wF > 0.0) accCol += wF * P( 1., 0.);
  if (wH > 0.0) accCol += wH * P( 0., 1.);
  if (wB > 0.0) accCol += wB * P( 0.,-1.);
  if (wD > 0.0) accCol += wD * P(-1., 0.);
  MP vec3 res = accCol / sumW;
  if (keepE > 1e-4) res = mix(P_CENTER, res, 1.0 - keepE);
  FRAG_OUT = vec4(res, 1.0);
//#crisp}
//#plain   MP vec3 res = P_CENTER;
//#plain   if (ratios.z > 0.0) { vec2 bo = secondPix.z > 0.0 ? vec2( 0., 1.) : vec2( 1., 0.); res = mix(res, P(bo.x, bo.y), ratios.z); }
//#plain   if (ratios.y > 0.0) { vec2 bo = secondPix.y > 0.0 ? vec2( 1., 0.) : vec2( 0.,-1.); res = mix(res, P(bo.x, bo.y), ratios.y); }
//#plain   if (ratios.x > 0.0) { vec2 bo = secondPix.x > 0.0 ? vec2( 0.,-1.) : vec2(-1., 0.); res = mix(res, P(bo.x, bo.y), ratios.x); }
//#plain   if (ratios.w > 0.0) { vec2 bo = secondPix.w > 0.0 ? vec2(-1., 0.) : vec2( 0., 1.); res = mix(res, P(bo.x, bo.y), ratios.w); }
//#plain   FRAG_OUT = vec4(res, 1.0);
}

#endif

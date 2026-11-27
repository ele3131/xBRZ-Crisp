#version 310 es
precision highp float;
precision highp int;
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
layout(location = 0) out vec2 vPx;
layout(location = 1) out vec2 vScale;
layout(location = 2) out vec4 vScK;

void main()
{
   gl_Position = global.MVP * Position;
//#crisp{
   vec2 origSz = params.xbrz_crisp_refpassSize.xy;
//#crisp}
//#plain    vec2 origSz = params.xbrz_fs_refpassSize.xy;
   vPx = TexCoord * origSz;
   vec2 sc = params.OutputSize.xy / origSz;
   float scArea = (sc.x * sc.y) * 0.7071067811865475;
   float sx2 = sc.x * sc.x, sy2 = sc.y * sc.y;
   vScale = sc;
   vScK = vec4(scArea * inversesqrt(vec3(sx2 + sy2, 4.0 * sx2 + sy2, sx2 + 4.0 * sy2)), scArea);
}

#pragma stage fragment
layout(location = 0) in vec2 vPx;
layout(location = 1) in vec2 vScale;
layout(location = 2) in vec4 vScK;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
#define MP mediump
layout(set = 0, binding = 2) uniform sampler2D Source;
// the input of the first pass (the preset's reference pass), which is the original image unless
// other shaders run before xBRZ
//#crisp{
layout(set = 0, binding = 3) uniform sampler2D xbrz_crisp_refpass;
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define P_CENTER texelFetch(xbrz_crisp_refpass, ipx, 0).rgb
#define P(x,y) texelFetch(xbrz_crisp_refpass, clamp(ipx + ivec2(int(x), int(y)), ivec2(0), maxOrig), 0).rgb
//#crisp}
//#plain layout(set = 0, binding = 3) uniform sampler2D xbrz_fs_refpass;
//#plain #define ORIG_SIZE params.xbrz_fs_refpassSize
//#plain #define P_CENTER texelFetch(xbrz_fs_refpass, ipx, 0).rgb
//#plain #define P(x,y) texelFetch(xbrz_fs_refpass, clamp(ipx + ivec2(int(x), int(y)), ivec2(0), maxOrig), 0).rgb
#define OUT_SIZE params.OutputSize
#define INFO_CENTER texelFetch(Source, ipx, 0)

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

// Exact C1 strictly convex parabola y(t) = 0.5 * (1 - t^2) for flat (m=0) -> 2:1 -> 45-deg (m=-1).
// Clamped with straight 2:1 dLin so Cauchy-Schwarz early-out stays exact at all scales.
float sdParab21(float cpx, float cpy, float dLin, vec2 sc)
{
  float tv = clamp(cpx + 0.5, 0.0, 1.0);
  float yc = 0.5 * (1.0 - tv * tv);
  float dp = (cpy - yc) * (sc.x * sc.y * INV_SQRT2) * inversesqrt((tv * sc.y) * (tv * sc.y) + sc.x * sc.x);
  return min(dp, dLin);
}
//#crisp}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping: -|B|-
  //                      D|E|F
  //                      -|H|-

  vec2 scale = vScale;
  vec3 scK = vScK.xyz;
  float scArea = vScK.w;
  vec2 pos = fract(vPx) - vec2(0.5, 0.5);
  ivec2 maxOrig = ivec2(ORIG_SIZE.xy) - ivec2(1);
  ivec2 ipx = clamp(ivec2(floor(vPx)), ivec2(0), maxOrig);

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
//#crisp{
#if __VERSION__ >= 300
    if (any(notEqual(iw & uvec4(160u), uvec4(0u))))
    {
      MP vec4 longL = vec4(((iw >> 5u) & 1u) | (((iw >> 7u) & 1u) << 1u));
#endif
      MP vec4 isLong = isCut * doLineBlend * min(haveShallowLine + haveSteepLine, vec4(1.0))
                     * vec4(greaterThan(longL, vec4(0.0))) * vec4(lessThan(longL, vec4(2.5)));
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
  }

  // Exact smoothstep(-INV_SQRT2, INV_SQRT2, d_raw): d is already multiplied by INV_SQRT2.
  // Because sdCornerArc(px, py, r) * scArc <= d_lin and sdParab21 <= d_lin wherever d_lin <= -0.5,
  // any corner already at t == 0 skips C1 curves bit-exactly.
  MP vec4 t = isCut * clamp(d + 0.5, 0.0, 1.0);
  if (dot(t, vec4(1.0)) <= 1e-4)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }

//#crisp{
  // Zero-neighbor-fetch C1 curves on surviving corners only:
  // plain bevels (doLineBlend == 0), isolated flat-wall 45-deg corners (BIT_ARC45),
  // and strictly convex flat -> 2:1 -> 45-deg curves (BIT_ARC21).
  MP vec4 isSurv = vec4(greaterThan(t, vec4(0.0)));
#if __VERSION__ >= 300
  MP vec4 act45 = isSurv * vec4(equal(iw & uvec4(244u), uvec4(36u)));
#else
  MP vec4 act45 = isSurv * doLineBlend * (1.0 - haveShallowLine) * (1.0 - haveSteepLine) * vec4(equal(longL, vec4(1.0)));
#endif
  MP vec4 actArc = isSurv * (1.0 - doLineBlend) + act45;
  if (dot(actArc, vec4(1.0)) > 0.0)
  {
    MP float scArc = scK.x * 1.4142135623730951;
    MP vec4 rArc = mix(max(vec4(0.05), 1.0 - INV_SQRT2 * tip), vec4(0.5), act45);
    if (actArc.x > 0.5) d.x = sdCornerArc(px.x, py.x, rArc.x) * scArc;
    if (actArc.y > 0.5) d.y = sdCornerArc(px.y, py.y, rArc.y) * scArc;
    if (actArc.z > 0.5) d.z = sdCornerArc(px.z, py.z, rArc.z) * scArc;
    if (actArc.w > 0.5) d.w = sdCornerArc(px.w, py.w, rArc.w) * scArc;
    t = isCut * clamp(d + 0.5, 0.0, 1.0);
  }
#if __VERSION__ >= 300
  MP vec4 act21 = vec4(greaterThan(t, vec4(0.0))) * vec4(equal(iw & uvec4(164u), uvec4(164u)));
#else
  MP vec4 act21 = vec4(greaterThan(t, vec4(0.0))) * doLineBlend * vec4(greaterThan(longL, vec4(2.5)));
#endif
  if (dot(act21, vec4(1.0)) > 0.0)
  {
    vec2 sc_x = scale, sc_y = scale.yx, sc_z = scale, sc_w = scale.yx;
    if (act21.x > 0.5) d.x = haveShallowLine.x > 0.5 ? sdParab21(px.x, py.x, d.x, sc_x) : sdParab21(py.x, px.x, d.x, sc_x.yx);
    if (act21.y > 0.5) d.y = haveShallowLine.y > 0.5 ? sdParab21(px.y, py.y, d.y, sc_y) : sdParab21(py.y, px.y, d.y, sc_y.yx);
    if (act21.z > 0.5) d.z = haveShallowLine.z > 0.5 ? sdParab21(px.z, py.z, d.z, sc_z) : sdParab21(py.z, px.z, d.z, sc_z.yx);
    if (act21.w > 0.5) d.w = haveShallowLine.w > 0.5 ? sdParab21(px.w, py.w, d.w, sc_w) : sdParab21(py.w, px.w, d.w, sc_w.yx);
    t = isCut * clamp(d + 0.5, 0.0, 1.0);
  }
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

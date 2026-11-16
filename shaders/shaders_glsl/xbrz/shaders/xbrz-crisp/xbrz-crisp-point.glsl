//#crisp{
// xBRZ crisp, point pass (OpenGL / GLES): xBRZ's decision at each point where 4 pixels meet, made once.
//#crisp}
//#plain // xBRZ freescale multipass, point pass (OpenGL / GLES): xBRZ's decision at each point where 4 pixels meet, made once.
//
// xBRZ decides each point where 4 pixels meet once (its preprocessing) and the 4 pixels around the point
// use that decision. This pass does the same: each pixel decides the point at its bottom-right corner and
// writes the blend type of the 4 pixels there in the alpha channel, next to its own color, so pass 0 reads
// the decisions of the 4 points around a pixel with the colors it reads anyway. The rules that decide a
// point (31 and 36) run here too. Every later pass reads the image from this pass's color.
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

#pragma parameter XBRZ_TOL "xBRZ: equal color tolerance (x/255)" 15 1 80 1
#pragma parameter XBRZ_DOM "xBRZ: dominant direction threshold" 3.8 1 8 0.05
#pragma parameter XBRZ_STEEP "xBRZ: steep/shallow line threshold" 3.2 1 6 0.1
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
//#plain-default XBRZ_MINC 0
#pragma parameter XBRZ_DIAG "xBRZ: max color distance on the diagonal (0 = off)" 100 0 160 4

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
uniform COMPAT_PRECISION float XBRZ_MINC;
uniform COMPAT_PRECISION float XBRZ_DIAG;
#else
#define XBRZ_TOL 15.0
#define XBRZ_DOM 3.8
#define XBRZ_STEEP 3.2
#define XBRZ_MINC 20.0
#define XBRZ_DIAG 100.0
#endif

#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
#define P(x,y) COMPAT_TEXTURE(Texture, coord + SRC_SIZE.zw * vec2(x, y)).rgb

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
// two distances closer than this are a tie (the float colors of equal integer steps differ in the last bits)
#define TIE_EPS 1e-5
#define CRISP_RULES (XBRZ_MINC > 0.0 && XBRZ_DIAG > 0.0)
#define eq(a,b)  (a == b)
#define neq(a,b) (a != b)

// the luma weights (Rec. 2020) and the scales of the two chroma differences, for DistYCbCr and DistShape
const vec3 lumaW = vec3(0.2627, 0.6780, 0.0593);
const float scaleB = 0.5 / (1.0 - 0.0593);
const float scaleR = 0.5 / (1.0 - 0.2627);

float DistYCbCr(vec3 pixA, vec3 pixB)
{
  vec3 diff = pixA - pixB;
  float Y = dot(diff.rgb, lumaW);
  float Cb = scaleB * (diff.b - Y);
  float Cr = scaleR * (diff.r - Y);
  return sqrt((Y * Y) + (Cb * Cb) + (Cr * Cr));
}

// ============================================================================================
// 31. Exact ties
// ============================================================================================
// b is the top-left pixel of the 2x2 (offset from the pixel at cc); tieCont returns how many ends of each
// diagonal (x: top-left to bottom-right, y: top-right to bottom-left) go on as a diagonal stroke 1 pixel wide
#define PC(v) P((v).x, (v).y)
bool thinCont(vec2 coord, vec2 p, vec2 dd, vec3 col)
{
  vec2 q = p + dd;
  return eq(PC(q), col) && neq(PC(vec2(q.x, p.y)), col) && neq(PC(vec2(p.x, q.y)), col);
}
vec2 tieCont(vec2 coord, vec2 b)
{
  vec3 tl = PC(b), tr = PC(b + vec2(1.0, 0.0));
  float s1 = float(thinCont(coord, b, vec2(-1.0, -1.0), tl)) + float(thinCont(coord, b + vec2(1.0, 1.0), vec2(1.0, 1.0), tl));
  float s2 = float(thinCont(coord, b + vec2(1.0, 0.0), vec2(1.0, -1.0), tr)) + float(thinCont(coord, b + vec2(0.0, 1.0), vec2(-1.0, 1.0), tr));
  return vec2(s1, s2);
}
// how many pixels of each diagonal's color there are in the 8x8 around the 2x2 (the rarer color wins)
vec2 tieSparse(vec2 coord, vec2 b)
{
  vec3 tl = PC(b), tr = PC(b + vec2(1.0, 0.0));
  vec2 n = vec2(0.0);
  for (int j = -3; j <= 4; j++) for (int i = -3; i <= 4; i++)
  { vec3 c = PC(b + vec2(float(i), float(j))); n += vec2(float(eq(c, tl)), float(eq(c, tr))); }
  return n;
}
// the diagonal that loses (its two corners are cut) must have, at each of its two pixels, a neighbor of its
// color outside the 2x2 (to the side or diagonally), so no pixel is left alone
bool sideHeld(vec2 coord, vec2 p, vec2 a, vec3 col) { return eq(PC(p + vec2(a.x, 0.0)), col) || eq(PC(p + vec2(0.0, a.y)), col) || eq(PC(p + a), col); }
vec2 tieHeld(vec2 coord, vec2 b)
{
  vec3 tl = PC(b), tr = PC(b + vec2(1.0, 0.0));
  float h1 = float(sideHeld(coord, b, vec2(-1.0, -1.0), tl) && sideHeld(coord, b + vec2(1.0, 1.0), vec2(1.0, 1.0), tl));
  float h2 = float(sideHeld(coord, b + vec2(1.0, 0.0), vec2(1.0, -1.0), tr) && sideHeld(coord, b + vec2(0.0, 1.0), vec2(-1.0, 1.0), tr));
  return vec2(h1, h2);
}

// ============================================================================================
// 36. Crossing strokes
// ============================================================================================
// how many of the 5 neighbors of the 2x2 pixel at b + p that lie outside the 2x2 (offsets o1..o5 from b)
// have the color c (exact) or, with lim > 0, lie within lim of c1 or c2
float outerN(vec2 coord, vec2 b, vec2 o1, vec2 o2, vec2 o3, vec2 o4, vec2 o5, vec3 c1, vec3 c2, float lim)
{
  float n = 0.0;
  vec3 q;
  q = PC(b + o1); n += float(lim > 0.0 ? min(DistYCbCr(q, c1), DistYCbCr(q, c2)) * 255.0 < lim : eq(q, c1));
  q = PC(b + o2); n += float(lim > 0.0 ? min(DistYCbCr(q, c1), DistYCbCr(q, c2)) * 255.0 < lim : eq(q, c1));
  q = PC(b + o3); n += float(lim > 0.0 ? min(DistYCbCr(q, c1), DistYCbCr(q, c2)) * 255.0 < lim : eq(q, c1));
  q = PC(b + o4); n += float(lim > 0.0 ? min(DistYCbCr(q, c1), DistYCbCr(q, c2)) * 255.0 < lim : eq(q, c1));
  q = PC(b + o5); n += float(lim > 0.0 ? min(DistYCbCr(q, c1), DistYCbCr(q, c2)) * 255.0 < lim : eq(q, c1));
  return n;
}
#define S_TL vec2(0.0, -1.0), vec2(-1.0, 0.0), vec2(0.0, -1.0), vec2(-1.0, 0.0), vec2(0.0, -1.0)
#define S_TR vec2(1.0, -1.0), vec2(2.0, 0.0), vec2(1.0, -1.0), vec2(2.0, 0.0), vec2(1.0, -1.0)
#define S_BL vec2(-1.0, 1.0), vec2(0.0, 2.0), vec2(-1.0, 1.0), vec2(0.0, 2.0), vec2(-1.0, 1.0)
#define S_BR vec2(2.0, 1.0), vec2(1.0, 2.0), vec2(2.0, 1.0), vec2(1.0, 2.0), vec2(2.0, 1.0)
#define O_TL vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 0.0), vec2(-1.0, 1.0)
#define O_TR vec2(0.0, -1.0), vec2(1.0, -1.0), vec2(2.0, -1.0), vec2(2.0, 0.0), vec2(2.0, 1.0)
#define O_BL vec2(-1.0, 0.0), vec2(-1.0, 1.0), vec2(-1.0, 2.0), vec2(0.0, 2.0), vec2(1.0, 2.0)
#define O_BR vec2(2.0, 0.0), vec2(2.0, 1.0), vec2(2.0, 2.0), vec2(1.0, 2.0), vec2(0.0, 2.0)
// a 2x2 where one diagonal has one exact color and the other two close shades of one stroke, both far
// from the first: returns (1, 0) when the first diagonal (top-left to bottom-right) should join, (0, 1) the
// second, (0, 0) to leave xBRZ's choice. The stroke of two shades joins where each of its pixels goes on
// outward by exactly one pixel of its shades (a stroke 1 pixel wide) and a pixel of the exact color has
// two or more of its own color outward (a mass): a thin stroke breaks more visibly than a mass is nicked.
#define XBRZ_X36_DARK 0.15
#define XBRZ_X36_DULL 0.6
// (the four colors of the 2x2 are passed in: they are already among A to I)
vec2 crossWin(vec2 coord, vec2 b, vec3 tl, vec3 tr, vec3 bl, vec3 br)
{
  if (eq(tl, br) && neq(tr, bl))
  {
    float far = min(DistYCbCr(tl, tr), DistYCbCr(tl, bl)) * 255.0;
    if (far < 64.0 || DistYCbCr(tr, bl) * 255.0 >= 0.5 * far) return vec2(0.0);
    // a dark outline next to a dull stroke separates two areas: it stays joined
    if (dot(tl, lumaW) < XBRZ_X36_DARK && max(dot(tr, lumaW), dot(bl, lumaW)) < XBRZ_X36_DULL) return vec2(0.0);
    float lim = max(30.0, 0.8 * DistYCbCr(tr, bl) * 255.0);
    bool thin = outerN(coord, b, O_TR, tr, bl, lim) == 1.0 && outerN(coord, b, S_TR, tr, bl, lim) > 0.5
             && outerN(coord, b, O_BL, tr, bl, lim) == 1.0 && outerN(coord, b, S_BL, tr, bl, lim) > 0.5;
    bool mass = (outerN(coord, b, O_TL, tl, tl, 0.0) >= 2.0 && outerN(coord, b, S_TL, tl, tl, 0.0) > 0.5)
             || (outerN(coord, b, O_BR, tl, tl, 0.0) >= 2.0 && outerN(coord, b, S_BR, tl, tl, 0.0) > 0.5);
    return (thin && mass) ? vec2(0.0, 1.0) : vec2(0.0);
  }
  if (eq(tr, bl) && neq(tl, br))
  {
    float far = min(DistYCbCr(tr, tl), DistYCbCr(tr, br)) * 255.0;
    if (far < 64.0 || DistYCbCr(tl, br) * 255.0 >= 0.5 * far) return vec2(0.0);
    if (dot(tr, lumaW) < XBRZ_X36_DARK && max(dot(tl, lumaW), dot(br, lumaW)) < XBRZ_X36_DULL) return vec2(0.0);
    float lim = max(30.0, 0.8 * DistYCbCr(tl, br) * 255.0);
    bool thin = outerN(coord, b, O_TL, tl, br, lim) == 1.0 && outerN(coord, b, S_TL, tl, br, lim) > 0.5
             && outerN(coord, b, O_BR, tl, br, lim) == 1.0 && outerN(coord, b, S_BR, tl, br, lim) > 0.5;
    bool mass = (outerN(coord, b, O_TR, tr, tr, 0.0) >= 2.0 && outerN(coord, b, S_TR, tr, tr, 0.0) > 0.5)
             || (outerN(coord, b, O_BL, tr, tr, 0.0) >= 2.0 && outerN(coord, b, S_BL, tr, tr, 0.0) > 0.5);
    return (thin && mass) ? vec2(1.0, 0.0) : vec2(0.0);
  }
  return vec2(0.0);
}

// xBRZ decides each point where 4 pixels meet (its preprocessing) from the 4x4 pixels around it. The
// 2x2 at the point is f g / j k, with xBRZ's letters (the 4x4 without its corners a, d, m and p):
//   -|b|c|-
//   e|f|g|h
//   i|j|k|l
//   -|n|o|-
// pointBlend returns the blend type of each of the 4 pixels at the point, as (f, g, j, k). E reads the
// points at its 4 corners: its bottom-right corner is f of the point whose top-left pixel is E (b = (0, 0)),
// its bottom-left g of the point at (-1, 0), its top-right j of the point at (0, -1) and its top-left k of
// the point at (-1, -1). The two pixels of each distance are in reading order, like the rest of the code,
// so the compiler computes the 24 distances of the 4 points once.
ivec4 pointBlend(vec2 coord, vec2 b, vec3 kb, vec3 kc, vec3 ke, vec3 kf, vec3 kg, vec3 kh, vec3 ki, vec3 kj, vec3 kk, vec3 kl, vec3 kn, vec3 ko)
{
  ivec4 r = ivec4(BLEND_NONE);
  if (!((eq(kf,kg) && eq(kj,kk)) || (eq(kf,kj) && eq(kg,kk))))
  {
    // the weighted lengths of the two diagonals, j-g and f-k: the shorter one is drawn
    float jg = DistYCbCr(kf, ki) + DistYCbCr(kc, kf) + DistYCbCr(kk, kn) + DistYCbCr(kh, kk) + (4.0 * DistYCbCr(kg, kj));
    float fk = DistYCbCr(ke, kj) + DistYCbCr(kj, ko) + DistYCbCr(kb, kg) + DistYCbCr(kg, kl) + (4.0 * DistYCbCr(kf, kk));
    int t = (DOM_E * jg < fk) ? BLEND_DOMINANT : BLEND_NORMAL;
    if (jg < fk)
    {
      if (neq(kf,kg) && neq(kf,kj)) r.x = t;
      if (neq(kk,kj) && neq(kk,kg)) r.w = t;
    }
    t = (DOM_E * fk < jg) ? BLEND_DOMINANT : BLEND_NORMAL;
    if (fk < jg)
    {
      if (neq(kg,kf) && neq(kg,kk)) r.y = t;
      if (neq(kj,kf) && neq(kj,kk)) r.z = t;
    }
    // 31. an exact tie between two diagonals of one color each
    if (CRISP_RULES && abs(jg - fk) < 0.001 && jg > 0.0 && eq(kf,kk) && eq(kg,kj) && neq(kf,kg) && DistYCbCr(kf, kg) * 255.0 > 64.0)
    {
      vec2 c0 = tieCont(coord, b);
      if (c0.x != c0.y)
      {
        vec2 s = tieSparse(coord, b).yx + 0.5 * c0;
        vec2 h = tieHeld(coord, b);
        // the diagonal j-g joins (f and k are cut), or f-k joins (g and j are cut)
        if (s.y > s.x && h.x > 0.5) r = ivec4(BLEND_NORMAL, BLEND_NONE, BLEND_NONE, BLEND_NORMAL);
        else if (s.x > s.y && h.y > 0.5) r = ivec4(BLEND_NONE, BLEND_NORMAL, BLEND_NORMAL, BLEND_NONE);
      }
    }
  }
  // 36. Crossing strokes: k36.y joins j-g, k36.x joins f-k
  if (CRISP_RULES && XBRZ_MINC > 0.0)
  {
    vec2 k36 = crossWin(coord, b, kf, kg, kj, kk);
    if (k36.y > 0.5) { r.x = BLEND_NORMAL; r.w = BLEND_NORMAL; } else if (k36.x > 0.5) { r.x = BLEND_NONE; r.w = BLEND_NONE; }
    if (k36.x > 0.5) { r.y = BLEND_NORMAL; r.z = BLEND_NORMAL; } else if (k36.y > 0.5) { r.y = BLEND_NONE; r.z = BLEND_NONE; }
  }
  return r;
}

void main()
{
  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;
  vec3 kf = P(0., 0.), kg = P(1., 0.), kj = P(0., 1.), kk = P(1., 1.);
  ivec4 r = ivec4(BLEND_NONE);
  // where the 2x2 is two rows or two columns of one color nothing blends (and rules 31 and 36 need a
  // diagonal of one color), so the 4x4 is read only at the other points
  if (!((eq(kf,kg) && eq(kj,kk)) || (eq(kf,kj) && eq(kg,kk))))
    r = pointBlend(coord, vec2(0.0), P(0., -1.), P(1., -1.), P(-1., 0.), kf, kg, P(2., 0.), P(-1., 1.), kj, kk, P(2., 1.), P(0., 2.), P(1., 2.));
  FRAG_OUT = vec4(kf, float(r.x + 4 * r.y + 16 * r.z + 64 * r.w) / 255.0);
}

#endif

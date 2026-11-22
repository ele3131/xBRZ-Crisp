//#crisp{
// xBRZ crisp, point pass (OpenGL / GLES): xBRZ's decision at each point where 4 pixels meet, made once.
//#crisp}
//#plain // xBRZ freescale multipass, point pass (OpenGL / GLES): xBRZ's decision at each point where 4 pixels meet, made once.
//
// xBRZ decides each point where 4 pixels meet once (its preprocessing) and the 4 pixels around the point
// use that decision. This pass does the same: each pixel decides the point at its bottom-right corner and
// writes the blend type of the 4 pixels there in the alpha channel, next to its own color, so pass 0 reads
// the decisions of the 4 points around a pixel with the colors it reads anyway.
//#crisp{
// The crisp rules that decide a point (31, 36 and 46) run here too.
//#crisp}
// Every later pass reads the image from this pass's color.
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
#pragma parameter XBRZ_DOM "xBRZ: dominant direction threshold" 3.8 1 8 0.05
//#crisp{
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
#pragma parameter XBRZ_DIAG "xBRZ: max color distance on the diagonal (0 = off)" 100 0 160 4
//#crisp}

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

uniform mat4 MVPMatrix;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    TEX0.xy = TexCoord.xy;
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
#define vTexCoord TEX0.xy
#define FRAG_OUT FragColor
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float XBRZ_DOM;
//#crisp{
uniform COMPAT_PRECISION float XBRZ_MINC;
uniform COMPAT_PRECISION float XBRZ_DIAG;
//#crisp}
#else
#define XBRZ_DOM 3.8
//#crisp{
#define XBRZ_MINC 20.0
#define XBRZ_DIAG 100.0
//#crisp}
#endif

vec2 gSrcInv = vec2(0.0), gSrcMax = vec2(0.0);
#define SRC_SIZE vec4(TextureSize, gSrcInv)
// Clamp right/bottom edge to InputSize so POT-padded GL/GLES FBOs never sample padding (left/top handled by GL_CLAMP_TO_EDGE)
#define CLAMP_SRC(uv) min((uv), gSrcMax)
#define P(x,y) COMPAT_TEXTURE(Texture, CLAMP_SRC(coord + gSrcInv * vec2(x, y))).rgb

#define BLEND_NONE 0
#define BLEND_NORMAL 1
#define BLEND_DOMINANT 2
#ifndef DOM_E
#define DOM_E XBRZ_DOM
#endif
#define eq(a,b)  (a == b)
#define neq(a,b) (a != b)
// small epsilon on jg vs fk so exact floating-point ties don't break arbitrarily due to FMA/reassociation
const float TIE_EPS = 1e-4;

// Rec. 2020 luma weights and chroma difference scales, shared across passes
const vec3 LUMA_W = vec3(0.2627, 0.6780, 0.0593);
const float SCALE_B = 0.5 / (1.0 - 0.0593);
const float SCALE_R = 0.5 / (1.0 - 0.2627);

// Linear RGB -> YCbCr conversion so cached neighborhood texels convert once and
// subsequent squared distances reduce to dot(d, d) (6 ops vs 13 ops), luma to c.x.
vec3 toYCbCr(vec3 c)
{
  float Y = dot(c, LUMA_W);
  return vec3(Y, SCALE_B * (c.b - Y), SCALE_R * (c.r - Y));
}

float luma(vec3 c) { return dot(c, LUMA_W); }

float distSqY(vec3 a, vec3 b)
{
  vec3 d = a - b;
  return dot(d, d);
}

float distY(vec3 a, vec3 b) { return sqrt(distSqY(a, b)); }
float distY255(vec3 a, vec3 b) { return distY(a, b) * 255.0; }

float distSqYCbCr(vec3 pixA, vec3 pixB)
{
  vec3 diff = pixA - pixB;
  float Y = dot(diff, LUMA_W);
  float Cb = SCALE_B * (diff.b - Y);
  float Cr = SCALE_R * (diff.r - Y);
  return (Y * Y) + (Cb * Cb) + (Cr * Cr);
}

float distYCbCr(vec3 pixA, vec3 pixB)
{
  return sqrt(distSqYCbCr(pixA, pixB));
}

float dist255(vec3 pixA, vec3 pixB)
{
  return distYCbCr(pixA, pixB) * 255.0;
}

// Squared threshold in [0..255] YCbCr units, kept in [0..1.5] so GLSL ES mediump never overflows
#define SQ255(x) (((x) / 255.0) * ((x) / 255.0))
// FP16-safe division guard (> 6.1e-5 smallest FP16 normal) so FTZ GPUs never produce NaN
const float SAFE_EPS = 1e-4;

bool within255(vec3 pixA, vec3 pixB, float lim)
{
  return distSqYCbCr(pixA, pixB) < SQ255(lim);
}

bool withinEq255(vec3 pixA, vec3 pixB, float lim)
{
  return distSqYCbCr(pixA, pixB) <= SQ255(lim);
}

bool withinY255(vec3 a, vec3 b, float lim)
{
  return distSqY(a, b) < SQ255(lim);
}

bool withinEqY255(vec3 a, vec3 b, float lim)
{
  return distSqY(a, b) <= SQ255(lim);
}

// Unified hue-shifting-tolerant AA / sel-out ramp check in YCbCr space (0 sqrt).
// True when m lies strictly between endpoints a and b along their chord with
// bounded orthogonal deviation (allowing pixel-art hue-shifting) and monotonic luma.
bool isAaRampY(vec3 a, vec3 m, vec3 b, float orthoTolSq, float minSpanSq)
{
  vec3 ab = b - a;
  float abSq = dot(ab, ab);
  if (abSq < minSpanSq) return false;
  vec3 am = m - a;
  float proj = dot(am, ab);
  if (proj <= 0.05 * abSq || proj >= 0.95 * abSq) return false;
  float t = proj / abSq;
  vec3 err = am - t * ab;
  if (dot(err, err) > orthoTolSq * abSq) return false;
  float loY = min(a.x, b.x), hiY = max(a.x, b.x);
  if (hiY - loY > 0.08 && (m.x < loY - 0.02 || m.x > hiY + 0.02)) return false;
  return true;
}
#define PY(x,y) toYCbCr(P(x, y))

//#crisp{
#define CRISP_RULES (XBRZ_MINC > 0.0 && XBRZ_DIAG > 0.0)

// ============================================================================================
// 31. Exact ties
// ============================================================================================
// At the 2x2 around E's bottom-right point (tl = kf at (0,0), tr = kg at (1,0), bl = kj at (0,1), br = kk at (1,1)),
// all 8 side neighbors outside the 2x2 are already in registers kb..ko; only the 4 diagonal corners (-1,-1), (2,-1),
// (-1,2) and (2,2) need texture reads.
vec2 tieCont(vec3 tl, vec3 tr, vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko,
             vec3 cTL, vec3 cTR, vec3 cBL, vec3 cBR)
{
  float s1 = float(eq(cTL, tl) && neq(ke, tl) && neq(kb, tl)) + float(eq(cBR, tl) && neq(kl, tl) && neq(ko, tl));
  float s2 = float(eq(cTR, tr) && neq(kh, tr) && neq(kc, tr)) + float(eq(cBL, tr) && neq(ki, tr) && neq(kn, tr));
  return vec2(s1, s2);
}
vec2 tieHeld(vec3 tl, vec3 tr, vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko,
             vec3 cTL, vec3 cTR, vec3 cBL, vec3 cBR)
{
  float h1 = float((eq(ke, tl) || eq(kb, tl) || eq(cTL, tl)) && (eq(kl, tl) || eq(ko, tl) || eq(cBR, tl)));
  float h2 = float((eq(kh, tr) || eq(kc, tr) || eq(cTR, tr)) && (eq(ki, tr) || eq(kn, tr) || eq(cBL, tr)));
  return vec2(h1, h2);
}
vec2 tieCnt(vec3 c, vec3 tl, vec3 tr) { return vec2(float(eq(c, tl)), float(eq(c, tr))); }
// Local 4x4 color count (zero extra texture fetches beyond the 4 outer corners)
vec2 tieCount4x4(vec3 tl, vec3 tr, vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko,
                 vec3 cTL, vec3 cTR, vec3 cBL, vec3 cBR)
{
  // inner 2x2 is a checker (kf == kk == tl, kg == kj == tr, tl != tr), contributing 2 of each
  return vec2(2.0)
       + tieCnt(cTL, tl, tr) + tieCnt(kb, tl, tr) + tieCnt(kc, tl, tr) + tieCnt(cTR, tl, tr)
       + tieCnt(ke,  tl, tr) + tieCnt(kh, tl, tr) + tieCnt(ki, tl, tr) + tieCnt(kl,  tl, tr)
       + tieCnt(cBL, tl, tr) + tieCnt(kn, tl, tr) + tieCnt(ko, tl, tr) + tieCnt(cBR, tl, tr);
}

// ============================================================================================
// 36. Crossing strokes
// ============================================================================================
// Each 2x2 pixel has 2 cardinal outer neighbors (s1, s2) and 3 other outer neighbors (a1, a2 in registers kb..ko,
// plus 1 outer diagonal corner at offset diagOff).
// - thin: exactly 1 of the 5 outer neighbors matches (within lim of c1 or c2), and it is one of the 2 cardinal ones
// - mass: at least 2 of the 5 outer neighbors match c (exact), and at least 1 is one of the 2 cardinal ones
bool shadeInSq(vec3 q, vec3 c1, vec3 c2, float limSq)
{
  return min(distSqY(q, c1), distSqY(q, c2)) < limSq;
}
bool thinOuter(vec2 coord, vec3 s1, vec3 s2, vec3 a1, vec3 a2, vec2 diagOff, vec3 c1, vec3 c2, float limSq)
{
  if (shadeInSq(s1, c1, c2, limSq) == shadeInSq(s2, c1, c2, limSq)) return false;
  if (shadeInSq(a1, c1, c2, limSq) || shadeInSq(a2, c1, c2, limSq)) return false;
  return !shadeInSq(PY(diagOff.x, diagOff.y), c1, c2, limSq);
}
bool massOuter(vec2 coord, vec3 s1, vec3 s2, vec3 a1, vec3 a2, vec2 diagOff, vec3 c)
{
  bool ms1 = eq(s1, c), ms2 = eq(s2, c);
  if (!ms1 && !ms2) return false;
  if (ms1 && ms2) return true;
  if (eq(a1, c) || eq(a2, c)) return true;
  return eq(PY(diagOff.x, diagOff.y), c);
}
#define XBRZ_X36_DARK 0.15
#define XBRZ_X36_DULL 0.6
vec2 crossWin(vec2 coord, vec3 kb, vec3 kc, vec3 ke, vec3 tl, vec3 tr, vec3 kh, vec3 ki, vec3 bl, vec3 br, vec3 kl, vec3 kn, vec3 ko)
{
  if (eq(tl, br) && neq(tr, bl))
  {
    float farSq = min(distSqY(tl, tr), distSqY(tl, bl));
    float dStrokeSq = distSqY(tr, bl);
    if (farSq < SQ255(64.0) || dStrokeSq >= 0.25 * farSq) return vec2(0.0);
    // a dark outline next to a dull stroke separates two areas: it stays joined
    if (tl.x < XBRZ_X36_DARK && max(tr.x, bl.x) < XBRZ_X36_DULL) return vec2(0.0);
    float limSq = max(SQ255(30.0), 0.64 * dStrokeSq);
    bool thin = thinOuter(coord, kc, kh, kb, kl, vec2(2.0, -1.0), tr, bl, limSq)
             && thinOuter(coord, ki, kn, ke, ko, vec2(-1.0, 2.0), tr, bl, limSq);
    if (!thin) return vec2(0.0);
    bool mass = massOuter(coord, kb, ke, kc, ki, vec2(-1.0, -1.0), tl)
             || massOuter(coord, kl, ko, kh, kn, vec2(2.0, 2.0), tl);
    return mass ? vec2(0.0, 1.0) : vec2(0.0);
  }
  if (eq(tr, bl) && neq(tl, br))
  {
    float farSq = min(distSqY(tr, tl), distSqY(tr, br));
    float dStrokeSq = distSqY(tl, br);
    if (farSq < SQ255(64.0) || dStrokeSq >= 0.25 * farSq) return vec2(0.0);
    if (tr.x < XBRZ_X36_DARK && max(tl.x, br.x) < XBRZ_X36_DULL) return vec2(0.0);
    float limSq = max(SQ255(30.0), 0.64 * dStrokeSq);
    bool thin = thinOuter(coord, kb, ke, kc, ki, vec2(-1.0, -1.0), tl, br, limSq)
             && thinOuter(coord, kl, ko, kh, kn, vec2(2.0, 2.0), tl, br, limSq);
    if (!thin) return vec2(0.0);
    bool mass = massOuter(coord, kc, kh, kb, kl, vec2(2.0, -1.0), tr)
             || massOuter(coord, ki, kn, ke, ko, vec2(-1.0, 2.0), tr);
    return mass ? vec2(1.0, 0.0) : vec2(0.0);
  }
  return vec2(0.0);
}

// ============================================================================================
// 46. A checkerboard keeps its squares
// ============================================================================================
// Soft parity match: q is within tolSq of same and strictly at least 2x closer to same than to opp.
bool chkSoftEq(vec3 q, vec3 same, vec3 opp, float tolSq)
{
  float ds = distSqY(q, same);
  return ds <= tolSq && ds < 0.25 * distSqY(q, opp);
}
// a) 2D interior checkerboards: 3+ of the four 2x2 blocks beside (0, 0) are in-phase checkers of c1 and c2.
// b) 1D 2-pixel-wide checker strips: full 6-pixel axial run (bU && bD or bL && bR) bounded laterally by
//    axis-aligned walls (rejecting shifted 45-degree diagonal stripes).
bool checker46(vec2 coord, vec3 c1, vec3 c2, vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko)
{
  bool hL = eq(ke, c2) && eq(ki, c1);
  bool hR = eq(kh, c1) && eq(kl, c2);
  bool hU = eq(kb, c2) && eq(kc, c1);
  bool hD = eq(kn, c1) && eq(ko, c2);
  // Zero-fetch early-out: both cnt >= 3 and axial 2x6 strips require (hU && hD) || (hL && hR)
  if (!((hU && hD) || (hL && hR))) return false;
  bool bL = hL && eq(PY(-2.0, 0.0), c1) && eq(PY(-2.0, 1.0), c2);
  bool bR = hR && eq(PY( 3.0, 0.0), c2) && eq(PY( 3.0, 1.0), c1);
  bool bU = hU && eq(PY( 0.0,-2.0), c1) && eq(PY( 1.0,-2.0), c2);
  bool bD = hD && eq(PY( 0.0, 3.0), c2) && eq(PY( 1.0, 3.0), c1);
  if (int(bL) + int(bR) + int(bU) + int(bD) >= 3) return true;
  bool wL = eq(ke, ki), wR = eq(kh, kl), wU = eq(kb, kc), wD = eq(kn, ko);
  bool vStrip = bU && bD && ((wL && wR) || (wR && (eq(kh, c1) || eq(kh, c2)) && hL) || (wL && (eq(ke, c1) || eq(ke, c2)) && hR));
  bool hStrip = bL && bR && ((wU && wD) || (wD && (eq(kn, c1) || eq(kn, c2)) && hU) || (wU && (eq(kb, c1) || eq(kb, c2)) && hD));
  return vStrip || hStrip;
}
bool meshWall46(vec3 w0, vec3 w1, vec3 pM, vec3 oA, vec3 oB, float gapSq)
{
  return eq(w0, w1) && neq(w0, oA) && neq(w0, oB) && distSqY(w0, pM) >= gapSq;
}
bool meshParity46(vec2 coord, vec3 cA, vec3 cB, vec3 oA, vec3 oB, float tolSq, float gapSq,
                  vec3 mL, vec3 oL, vec3 mR, vec3 oR, vec3 mU, vec3 oU, vec3 mD, vec3 oD,
                  vec2 pmL, vec2 poL, vec2 pmR, vec2 poR, vec2 pmU, vec2 poU, vec2 pmD, vec2 poD)
{
  vec3 pM = 0.5 * (cA + cB);
  bool hL = distSqY(mL, pM) <= tolSq && distSqY(oL, pM) >= gapSq;
  bool hR = distSqY(mR, pM) <= tolSq && distSqY(oR, pM) >= gapSq;
  bool hU = distSqY(mU, pM) <= tolSq && distSqY(oU, pM) >= gapSq;
  bool hD = distSqY(mD, pM) <= tolSq && distSqY(oD, pM) >= gapSq;
  bool wL = meshWall46(mL, oL, pM, oA, oB, gapSq);
  bool wR = meshWall46(mR, oR, pM, oA, oB, gapSq);
  bool wU = meshWall46(mU, oU, pM, oA, oB, gapSq);
  bool wD = meshWall46(mD, oD, pM, oA, oB, gapSq);
  if (!((hL && hR && ((hU && hD) || (hU && wD) || (hD && wU)))
     || (hU && hD && ((hL && wR) || (hR && wL)))))
    return false;
  bool bL = hL && distSqY(PY(pmL.x, pmL.y), pM) <= tolSq && distSqY(PY(poL.x, poL.y), pM) >= gapSq;
  bool bR = hR && distSqY(PY(pmR.x, pmR.y), pM) <= tolSq && distSqY(PY(poR.x, poR.y), pM) >= gapSq;
  bool bU = hU && distSqY(PY(pmU.x, pmU.y), pM) <= tolSq && distSqY(PY(poU.x, poU.y), pM) >= gapSq;
  bool bD = hD && distSqY(PY(pmD.x, pmD.y), pM) <= tolSq && distSqY(PY(poD.x, poD.y), pM) >= gapSq;
  return (bL && bR && ((bU && bD) || (bU && wD) || (bD && wU)))
      || (bU && bD && ((bL && wR) || (bR && wL)));
}
// d) Shaded / gradient 2D checkerboards and high-contrast 1-parity 50% mesh-transparency overlays.
bool checkerShaded46(vec2 coord, vec3 kf, vec3 kg, vec3 kj, vec3 kk,
                     vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko)
{
  float minEdgeSq = min(min(distSqY(kf, kg), distSqY(kf, kj)), min(distSqY(kk, kg), distSqY(kk, kj)));
  if (minEdgeSq < SQ255(30.0)) return false;
  float d0 = distSqY(kf, kk), d1 = distSqY(kg, kj);
  if (max(d0, d1) < 0.18 * minEdgeSq)
  {
    vec3 p0 = 0.5 * (kf + kk), p1 = 0.5 * (kg + kj);
    float tolSq = 0.18 * distSqY(p0, p1);
    bool hL = chkSoftEq(ke, p1, p0, tolSq) && chkSoftEq(ki, p0, p1, tolSq);
    bool hR = chkSoftEq(kh, p0, p1, tolSq) && chkSoftEq(kl, p1, p0, tolSq);
    bool hU = chkSoftEq(kb, p1, p0, tolSq) && chkSoftEq(kc, p0, p1, tolSq);
    bool hD = chkSoftEq(kn, p0, p1, tolSq) && chkSoftEq(ko, p1, p0, tolSq);
    if ((hU && hD) || (hL && hR))
    {
      bool bL = hL && chkSoftEq(PY(-2.0, 0.0), p0, p1, tolSq) && chkSoftEq(PY(-2.0, 1.0), p1, p0, tolSq);
      bool bR = hR && chkSoftEq(PY( 3.0, 0.0), p1, p0, tolSq) && chkSoftEq(PY( 3.0, 1.0), p0, p1, tolSq);
      bool bU = hU && chkSoftEq(PY( 0.0,-2.0), p0, p1, tolSq) && chkSoftEq(PY( 1.0,-2.0), p1, p0, tolSq);
      bool bD = hD && chkSoftEq(PY( 0.0, 3.0), p1, p0, tolSq) && chkSoftEq(PY( 1.0, 3.0), p0, p1, tolSq);
      if (int(bL) + int(bR) + int(bU) + int(bD) >= 3) return true;
    }
  }
  if (minEdgeSq < SQ255(72.0)) return false;
  float mTolSq = min(SQ255(26.0), 0.08 * minEdgeSq);
  float mGapSq = max(SQ255(72.0), 4.0 * mTolSq);
  if (d0 <= mTolSq && meshParity46(coord, kf, kk, kg, kj, mTolSq, mGapSq,
                                   ki, ke, kh, kl, kc, kb, kn, ko,
                                   vec2(-2.0, 0.0), vec2(-2.0, 1.0), vec2(3.0, 1.0), vec2(3.0, 0.0),
                                   vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(1.0, 3.0), vec2(0.0, 3.0)))
    return true;
  if (d1 <= mTolSq && meshParity46(coord, kg, kj, kf, kk, mTolSq, mGapSq,
                                   ke, ki, kl, kh, kb, kc, ko, kn,
                                   vec2(-2.0, 1.0), vec2(-2.0, 0.0), vec2(3.0, 0.0), vec2(3.0, 1.0),
                                   vec2(1.0, -2.0), vec2(0.0, -2.0), vec2(0.0, 3.0), vec2(1.0, 3.0)))
    return true;
  return false;
}
// Helper for 2x4 shaded checker strip beside an exact 1x4 solid wall (in-register checks first, 2 corner fetches last).
bool chkEdgeSoft2x4(vec2 coord, vec3 a0, vec3 b0, vec3 a1, vec3 b1, vec3 a2, vec3 b2, vec2 oA, vec2 oB)
{
  float minEdgeSq = min(min(distSqY(a0, b0), distSqY(a0, b1)), min(distSqY(a1, b0), distSqY(a1, b1)));
  if (minEdgeSq < SQ255(35.0)) return false;
  if (max(distSqY(a0, a1), distSqY(b0, b1)) >= 0.18 * minEdgeSq) return false;
  vec3 pA = 0.5 * (a0 + a1), pB = 0.5 * (b0 + b1);
  float tolSq = 0.18 * distSqY(pA, pB);
  if (!(chkSoftEq(a2, pA, pB, tolSq) && chkSoftEq(b2, pB, pA, tolSq))) return false;
  return chkSoftEq(PY(oA.x, oA.y), pA, pB, tolSq) && chkSoftEq(PY(oB.x, oB.y), pB, pA, tolSq);
}
// c) A 4-pixel solid wall column/row immediately adjacent to a confirmed 2x4 checker strip (exact or shaded).
bool checkerEdge46(vec2 coord, vec3 kb, vec3 kc, vec3 ke, vec3 kf, vec3 kg, vec3 kh, vec3 ki, vec3 kj, vec3 kk, vec3 kl, vec3 kn, vec3 ko)
{
  if (eq(kg, kk) && eq(kc, kg) && eq(ko, kg) && neq(kf, kj))
  {
    if ((eq(kf, kg) || eq(kj, kg))
        && eq(kb, kj) && eq(kn, kf) && eq(ke, kj) && eq(ki, kf)
        && eq(PY(-1.0, -1.0), kf) && eq(PY(-1.0, 2.0), kj))
      return true;
    if (chkEdgeSoft2x4(coord, kf, kj, ki, ke, kn, kb, vec2(-1.0, -1.0), vec2(-1.0, 2.0)))
      return true;
  }
  if (eq(kf, kj) && eq(kb, kf) && eq(kn, kf) && neq(kg, kk))
  {
    if ((eq(kg, kf) || eq(kk, kf))
        && eq(kc, kk) && eq(ko, kg) && eq(kh, kk) && eq(kl, kg)
        && eq(PY( 2.0, -1.0), kg) && eq(PY( 2.0, 2.0), kk))
      return true;
    if (chkEdgeSoft2x4(coord, kg, kk, kl, kh, ko, kc, vec2(2.0, -1.0), vec2(2.0, 2.0)))
      return true;
  }
  if (eq(kj, kk) && eq(ki, kj) && eq(kl, kj) && neq(kf, kg))
  {
    if ((eq(kf, kj) || eq(kg, kj))
        && eq(ke, kg) && eq(kh, kf) && eq(kb, kg) && eq(kc, kf)
        && eq(PY(-1.0, -1.0), kf) && eq(PY( 2.0, -1.0), kg))
      return true;
    if (chkEdgeSoft2x4(coord, kf, kg, kc, kb, kh, ke, vec2(-1.0, -1.0), vec2(2.0, -1.0)))
      return true;
  }
  if (eq(kf, kg) && eq(ke, kf) && eq(kh, kf) && neq(kj, kk))
  {
    if ((eq(kj, kf) || eq(kk, kf))
        && eq(ki, kk) && eq(kl, kj) && eq(kn, kk) && eq(ko, kj)
        && eq(PY(-1.0,  2.0), kj) && eq(PY( 2.0, 2.0), kk))
      return true;
    if (chkEdgeSoft2x4(coord, kj, kk, ko, kn, kl, ki, vec2(-1.0, 2.0), vec2(2.0, 2.0)))
      return true;
  }
  return false;
}
//#crisp}

// xBRZ decides each point where 4 pixels meet (its preprocessing) from the 4x4 pixels around it. The
// 2x2 at the point is f g / j k, with xBRZ's letters (the 4x4 without its corners a, d, m and p):
//   -|b|c|-
//   e|f|g|h
//   i|j|k|l
//   -|n|o|-
// pointBlend returns the blend type of each of the 4 pixels at the point, as (f, g, j, k). E reads the
// points at its 4 corners: its bottom-right corner is f of the point whose top-left pixel is E, its
// bottom-left g of the point at (-1, 0), its top-right j of the point at (0, -1) and its top-left k of
// the point at (-1, -1). All color arguments are pre-converted to linear YCbCr.
ivec4 pointBlend(vec2 coord, vec3 kb, vec3 kc, vec3 ke, vec3 kf, vec3 kg, vec3 kh, vec3 ki, vec3 kj, vec3 kk, vec3 kl, vec3 kn, vec3 ko)
{
  ivec4 r = ivec4(BLEND_NONE);
  // the weighted lengths of the two diagonals, j-g and f-k: the shorter one is drawn
  float jg = distY(kf, ki) + distY(kc, kf) + distY(kk, kn) + distY(kh, kk) + (4.0 * distY(kg, kj));
  float fk = distY(ke, kj) + distY(kj, ko) + distY(kb, kg) + distY(kg, kl) + (4.0 * distY(kf, kk));
  if (jg + TIE_EPS < fk)
  {
    int t = (DOM_E * jg < fk) ? BLEND_DOMINANT : BLEND_NORMAL;
    if (neq(kf, kg) && neq(kf, kj)) r.x = t;
    if (neq(kk, kj) && neq(kk, kg)) r.w = t;
  }
  else if (fk + TIE_EPS < jg)
  {
    int t = (DOM_E * fk < jg) ? BLEND_DOMINANT : BLEND_NORMAL;
    if (neq(kg, kf) && neq(kg, kk)) r.y = t;
    if (neq(kj, kf) && neq(kj, kk)) r.z = t;
  }
//#crisp{
  if (CRISP_RULES)
  {
    bool isChecker = eq(kf, kk) && eq(kg, kj) && neq(kf, kg);
    // 31. an exact tie between two diagonals of one color each
    if (isChecker && abs(jg - fk) < 0.001 && jg > 0.0 && !withinEqY255(kf, kg, 64.0))
    {
      vec3 cTL = PY(-1.0, -1.0), cTR = PY(2.0, -1.0), cBL = PY(-1.0, 2.0), cBR = PY(2.0, 2.0);
      vec2 c0 = tieCont(kf, kg, kb, kc, ke, kh, ki, kl, kn, ko, cTL, cTR, cBL, cBR);
      if (c0.x != c0.y)
      {
        vec2 h = tieHeld(kf, kg, kb, kc, ke, kh, ki, kl, kn, ko, cTL, cTR, cBL, cBR);
        if (h.x + h.y > 0.5)
        {
          vec2 s = tieCount4x4(kf, kg, kb, kc, ke, kh, ki, kl, kn, ko, cTL, cTR, cBL, cBR).yx + 0.25 * c0;
          // the diagonal j-g joins (f and k are cut), or f-k joins (g and j are cut)
          if (s.y > s.x && h.x > 0.5) r = ivec4(BLEND_NORMAL, BLEND_NONE, BLEND_NONE, BLEND_NORMAL);
          else if (s.x > s.y && h.y > 0.5) r = ivec4(BLEND_NONE, BLEND_NORMAL, BLEND_NORMAL, BLEND_NONE);
        }
      }
    }
    // 36. Crossing strokes: k36.y joins j-g, k36.x joins f-k (preserve BLEND_DOMINANT if already set on that diagonal)
    vec2 k36 = crossWin(coord, kb, kc, ke, kf, kg, kh, ki, kj, kk, kl, kn, ko);
    if (k36.y > 0.5) r = ivec4(r.x == BLEND_DOMINANT ? BLEND_DOMINANT : BLEND_NORMAL, BLEND_NONE, BLEND_NONE, r.w == BLEND_DOMINANT ? BLEND_DOMINANT : BLEND_NORMAL);
    else if (k36.x > 0.5) r = ivec4(BLEND_NONE, r.y == BLEND_DOMINANT ? BLEND_DOMINANT : BLEND_NORMAL, r.z == BLEND_DOMINANT ? BLEND_DOMINANT : BLEND_NORMAL, BLEND_NONE);
    // 46. a 2x2 checker (exact, shaded, or 50% mesh) inside a checker texture (or its edge against a solid wall) keeps its corners square
    if (r.x + r.y + r.z + r.w > 0)
    {
      if (eq(kf, kg) || eq(kj, kk) || eq(kf, kj) || eq(kg, kk))
      {
        if (checkerEdge46(coord, kb, kc, ke, kf, kg, kh, ki, kj, kk, kl, kn, ko))
          r = ivec4(BLEND_NONE);
      }
      else if ((isChecker && checker46(coord, kf, kg, kb, kc, ke, kh, ki, kl, kn, ko))
               || checkerShaded46(coord, kf, kg, kj, kk, kb, kc, ke, kh, ki, kl, kn, ko))
        r = ivec4(BLEND_NONE);
    }
  }
//#crisp}
  return r;
}

void main()
{
  gSrcInv = 1.0 / TextureSize;
  gSrcMax = (InputSize - 0.5) * gSrcInv;
  vec2 pos = fract(vTexCoord * TextureSize) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * gSrcInv;
  vec3 rgbF = P(0., 0.), rgbG = P(1., 0.), rgbJ = P(0., 1.), rgbK = P(1., 1.);
  ivec4 r = ivec4(BLEND_NONE);
  // where the 2x2 is two rows or two columns of one color nothing blends (and rules 31 and 36 need a
  // diagonal of one color), so the 4x4 is read only at the other points
  if (!((eq(rgbF, rgbG) && eq(rgbJ, rgbK)) || (eq(rgbF, rgbJ) && eq(rgbG, rgbK))))
    r = pointBlend(coord, PY(0., -1.), PY(1., -1.), PY(-1., 0.), toYCbCr(rgbF), toYCbCr(rgbG), PY(2., 0.),
                   PY(-1., 1.), toYCbCr(rgbJ), toYCbCr(rgbK), PY(2., 1.), PY(0., 2.), PY(1., 2.));
  FRAG_OUT = vec4(rgbF, float(r.x + 4 * r.y + 16 * r.z + 64 * r.w) / 255.0);
}

#endif

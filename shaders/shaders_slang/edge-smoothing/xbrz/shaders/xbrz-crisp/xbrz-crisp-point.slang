#version 310 es
precision highp float;
precision highp int;
//#crisp{
// xBRZ crisp, point pass (Vulkan / slang): xBRZ's decision at each point where 4 pixels meet, made once.
//#crisp}
//#plain // xBRZ freescale multipass, point pass (Vulkan / slang): xBRZ's decision at each point where 4 pixels meet, made once.
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
layout(push_constant) uniform Push
{
	vec4 SourceSize;
	vec4 OutputSize;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
	float XBRZ_DOM;
//#crisp{
	float XBRZ_MINC;
	float XBRZ_DIAG;
//#crisp}
} global;

#pragma parameter XBRZ_DOM "xBRZ: dominant direction threshold" 3.8 1 8 0.05
//#crisp{
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
#pragma parameter XBRZ_DIAG "xBRZ: max color distance on the diagonal (0 = off)" 100 0 160 4
//#crisp}
#define XBRZ_DOM global.XBRZ_DOM
//#crisp{
#define XBRZ_MINC global.XBRZ_MINC
#define XBRZ_DIAG global.XBRZ_DIAG
//#crisp}

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
layout(set = 0, binding = 2) uniform sampler2D Source;
#define SRC_SIZE params.SourceSize
#define P(x,y) texture(Source, coord + SRC_SIZE.zw * vec2(x, y)).rgb

#define BLEND_NONE 0
#define BLEND_NORMAL 1
#define BLEND_DOMINANT 2
#ifndef DOM_E
#define DOM_E XBRZ_DOM
#endif
#define eq(a,b)  ((a) == (b))
#define neq(a,b) ((a) != (b))
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

float distSqY(vec3 a, vec3 b)
{
  vec3 d = a - b;
  return dot(d, d);
}

// Squared threshold in [0..255] YCbCr units, kept in [0..1.5] so GLSL ES mediump never overflows
#define SQ255(x) (((x) / 255.0) * ((x) / 255.0))
// FP16-safe division guard (> 6.1e-5 smallest FP16 normal) so FTZ GPUs never produce NaN
const float SAFE_EPS = 1e-4;

bool withinY255(vec3 a, vec3 b, float lim)
{
  return distSqY(a, b) < SQ255(lim);
}

bool withinEqY255(vec3 a, vec3 b, float lim)
{
  return distSqY(a, b) <= SQ255(lim);
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
bool crossWinCore(vec3 bg, vec3 st1, vec3 st2, float dStrokeSq)
{
  float farSq = min(distSqY(bg, st1), distSqY(bg, st2));
  if (farSq < SQ255(64.0) || dStrokeSq >= 0.25 * farSq) return false;
  // a dark outline next to a dull stroke separates two areas: it stays joined
  return !(bg.x < XBRZ_X36_DARK && max(st1.x, st2.x) < XBRZ_X36_DULL);
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
// a) 2D interior checkerboards: 3+ of the four 2x2 blocks beside (0, 0) are in-phase checkers of c1 and c2,
//    or 2 orthogonal 2x2 blocks plus the diagonal 2x2 corner between them form a solid 4x4 exact checkerboard.
// b) 1D 2-pixel-wide checker strips: full 6-pixel axial run (bU && bD or bL && bR) bounded laterally by
//    axis-aligned walls (rejecting shifted 45-degree diagonal stripes).
bool chkQuad46(vec2 coord, float ox, float oy, vec3 c1, vec3 c2)
{
  return eq(PY(ox, oy), c1) && eq(PY(ox + 1.0, oy), c2)
      && eq(PY(ox, oy + 1.0), c2) && eq(PY(ox + 1.0, oy + 1.0), c1);
}
bool chkWallBreak46(vec2 coord, vec3 c1, vec3 c2, vec3 w, vec3 o1, vec3 o2,
                    vec2 wE1, vec2 wE2, vec2 oE1, vec2 oE2)
{
  if (!(eq(w, c1) || eq(w, c2))) return false;
  vec3 opp = eq(w, c1) ? c2 : c1;
  bool s1 = eq(o1, opp) && neq(o2, c1) && neq(o2, c2);
  bool s2 = eq(o2, opp) && neq(o1, c1) && neq(o1, c2);
  if (!s1 && !s2) return false;
  if (!eq(PY(wE1.x, wE1.y), w) || !eq(PY(wE2.x, wE2.y), w)) return false;
  vec2 oe = s1 ? oE1 : oE2;
  return eq(PY(oe.x, oe.y), opp);
}
bool chkStrip46(vec2 coord, vec3 c1, vec3 c2, bool hA, bool hB, bool hS1, bool hS2,
                bool wA, bool wB, bool wS1, bool wS2, vec3 cA, vec3 cB, vec3 s1a, vec3 s1b, vec3 s2a, vec3 s2b,
                vec2 pA0, vec2 pA1, vec2 pB0, vec2 pB1, vec2 cTL, vec2 cBL, vec2 cTR, vec2 cBR)
{
  bool sWall = (wS1 && wS2) || (wS2 && (eq(s2a, c1) || eq(s2a, c2)) && hS1) || (wS1 && (eq(s1a, c1) || eq(s1a, c2)) && hS2);
  if (hA && hB)
  {
    if (sWall
        || (wS1 && chkWallBreak46(coord, c1, c2, s1a, s2a, s2b, cTL, cBL, cTR, cBR))
        || (wS2 && chkWallBreak46(coord, c1, c2, s2a, s1a, s1b, cTR, cBR, cTL, cBL)))
    {
      vec3 a0 = PY(pA0.x, pA0.y), a1 = PY(pA1.x, pA1.y), b0 = PY(pB0.x, pB0.y), b1 = PY(pB1.x, pB1.y);
      bool bA2 = eq(a0, c1) && eq(a1, c2), bB2 = eq(b0, c2) && eq(b1, c1);
      if (bA2 && bB2) return true;
      if (sWall && ((bA2 && eq(b0, b1) && neq(b0, c1) && neq(b0, c2))
                 || (bB2 && eq(a0, a1) && neq(a0, c1) && neq(a0, c2))))
        return true;
    }
    return false;
  }
  if (!sWall) return false;
  bool useA = hA && wB && neq(cB, c1) && neq(cB, c2);
  bool useB = !useA && hB && wA && neq(cA, c1) && neq(cA, c2);
  if (!useA && !useB) return false;
  vec3 cEnd = useA ? cB : cA;
  vec2 e0 = useA ? cBL : cTL, e1 = useA ? cBR : cTR;
  vec2 q0 = useA ? pA0 : pB0, q1 = useA ? pA1 : pB1;
  return eq(PY(e0.x, e0.y), cEnd) && eq(PY(e1.x, e1.y), cEnd)
      && eq(PY(q0.x, q0.y), useA ? c1 : c2) && eq(PY(q1.x, q1.y), useA ? c2 : c1);
}
bool checker46(vec2 coord, vec3 c1, vec3 c2, vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko)
{
  bool hL = eq(ke, c2) && eq(ki, c1);
  bool hR = eq(kh, c1) && eq(kl, c2);
  bool hU = eq(kb, c2) && eq(kc, c1);
  bool hD = eq(kn, c1) && eq(ko, c2);
  if (!(hL || hR || hU || hD)) return false;
  bool wL = eq(ke, ki), wR = eq(kh, kl), wU = eq(kb, kc), wD = eq(kn, ko);
  if ((hU || hD) && chkStrip46(coord, c1, c2, hU, hD, hL, hR, wU, wD, wL, wR, kb, kn, ke, ki, kh, kl,
                               vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(0.0, 3.0), vec2(1.0, 3.0),
                               vec2(-1.0, -1.0), vec2(-1.0, 2.0), vec2(2.0, -1.0), vec2(2.0, 2.0)))
    return true;
  if ((hL || hR) && chkStrip46(coord, c1, c2, hL, hR, hU, hD, wL, wR, wU, wD, ke, kh, kb, kc, kn, ko,
                               vec2(-2.0, 0.0), vec2(-2.0, 1.0), vec2(3.0, 0.0), vec2(3.0, 1.0),
                               vec2(-1.0, -1.0), vec2(2.0, -1.0), vec2(-1.0, 2.0), vec2(2.0, 2.0)))
    return true;
  if (!((hU || hD) && (hL || hR))) return false;
  bool bL = hL && eq(PY(-2.0, 0.0), c1) && eq(PY(-2.0, 1.0), c2);
  bool bR = hR && eq(PY( 3.0, 0.0), c2) && eq(PY( 3.0, 1.0), c1);
  if (!bL && !bR) return false;
  bool bU = hU && eq(PY( 0.0,-2.0), c1) && eq(PY( 1.0,-2.0), c2);
  bool bD = hD && eq(PY( 0.0, 3.0), c2) && eq(PY( 1.0, 3.0), c1);
  if (!bU && !bD) return false;
  if (int(bL) + int(bR) + int(bU) + int(bD) >= 3) return true;
  // Exactly 2 orthogonal 2x2 blocks match: accept if the diagonal 2x2 between them completes an exact 4x4 checker
  return chkQuad46(coord, bL ? -2.0 : 2.0, bU ? -2.0 : 2.0, c1, c2);
}
bool meshWall46(vec3 w0, vec3 w1, vec3 pM, vec3 oA, vec3 oB, float tolSq, float gapSq)
{
  if (!eq(w0, w1)) return false;
  float dw = distSqY(w0, pM);
  return dw <= tolSq || (dw >= gapSq && neq(w0, oA) && neq(w0, oB));
}
bool meshFlankStroke46(vec2 coord, vec3 oS, vec3 oOpp, vec3 oD1, vec3 oD2, vec3 oN1, vec3 oN2, vec2 pcFar, inout vec3 qFar, inout bool haveFar, float tolSq)
{
  if (distSqY(oD1, oS) > tolSq || distSqY(oD2, oS) > tolSq) return false;
  if (min(min(distSqY(oOpp, oS), distSqY(oN1, oS)), distSqY(oN2, oS)) < SQ255(54.0)) return false;
  if (!haveFar) { qFar = PY(pcFar.x, pcFar.y); haveFar = true; }
  if (distSqY(qFar, oS) < SQ255(54.0)) return false;
  vec2 pS = step(vec2(0.5), pcFar);
  vec2 dS = 2.0 * (pcFar - pS);
  vec2 pe1 = pS + vec2(-dS.y, dS.x), pe2 = pS - vec2(-dS.y, dS.x);
  return distSqY(PY(pe1.x, pe1.y), oS) <= tolSq || distSqY(PY(pe2.x, pe2.y), oS) <= tolSq;
}
bool meshQuad46(vec2 coord, float ox, float oy, vec3 pM, float tolSq, float gapSq, bool flip)
{
  vec3 q00 = PY(ox, oy), q10 = PY(ox + 1.0, oy), q01 = PY(ox, oy + 1.0), q11 = PY(ox + 1.0, oy + 1.0);
  if (!flip)
    return distSqY(q00, pM) <= tolSq && distSqY(q11, pM) <= tolSq
        && distSqY(q10, pM) >= gapSq && distSqY(q01, pM) >= gapSq;
  return distSqY(q10, pM) <= tolSq && distSqY(q01, pM) <= tolSq
      && distSqY(q00, pM) >= gapSq && distSqY(q11, pM) >= gapSq;
}
bool meshCornerOk46(vec2 coord, vec2 p, bool hA, bool hB, bool wA, bool wB, vec3 mA, vec3 mB, vec3 pM, float tolSq, float gapSq, bool isMeshSlot, bool strictNonMesh, inout vec3 qOut, inout bool haveOut)
{
  if (hA && hB)
  {
    if (!isMeshSlot && !strictNonMesh) return true;
    qOut = PY(p.x, p.y); haveOut = true;
    if (isMeshSlot) return distSqY(qOut, pM) <= tolSq;
    return distSqY(qOut, pM) >= gapSq;
  }
  if (wA && hB) { qOut = PY(p.x, p.y); haveOut = true; return eq(qOut, mA); }
  if (wB && hA) { qOut = PY(p.x, p.y); haveOut = true; return eq(qOut, mB); }
  if (wA && wB && eq(mA, mB)) { qOut = PY(p.x, p.y); haveOut = true; return eq(qOut, mA); }
  return true;
}
bool meshParity46(vec2 coord, vec3 cA, vec3 cB, vec3 oA, vec3 oB, float tolSq, float gapSq,
                  vec3 mH1, vec3 oH1, vec3 mH2, vec3 oH2, vec3 mV1, vec3 oV1, vec3 mV2, vec3 oV2,
                  vec2 pmH1, vec2 poH1, vec2 pmH2, vec2 poH2, vec2 pmV1, vec2 poV1, vec2 pmV2, vec2 poV2,
                  vec2 pcA, vec2 pcB)
{
  vec3 pM = 0.5 * (cA + cB);
  bool hH1 = distSqY(mH1, pM) <= tolSq && distSqY(oH1, pM) >= gapSq;
  bool hH2 = distSqY(mH2, pM) <= tolSq && distSqY(oH2, pM) >= gapSq;
  if (!hH1 && !hH2) return false;
  bool hV1 = distSqY(mV1, pM) <= tolSq && distSqY(oV1, pM) >= gapSq;
  bool hV2 = distSqY(mV2, pM) <= tolSq && distSqY(oV2, pM) >= gapSq;
  if (!hV1 && !hV2) return false;
  // Zero-fetch early-out: every side must be either mesh (h*) or a solid wall (w*).
  bool wH1 = !hH1 && meshWall46(mH1, oH1, pM, oA, oB, tolSq, gapSq);
  bool wH2 = !hH2 && meshWall46(mH2, oH2, pM, oA, oB, tolSq, gapSq);
  if (!(hH1 || wH1) || !(hH2 || wH2)) return false;
  bool wV1 = !hV1 && meshWall46(mV1, oV1, pM, oA, oB, tolSq, gapSq);
  bool wV2 = !hV2 && meshWall46(mV2, oV2, pM, oA, oB, tolSq, gapSq);
  if (!(hV1 || wV1) || !(hV2 || wV2)) return false;
  bool bH1 = false, bH2 = false, bV1 = false, bV2 = false;
  bool eH1 = false, eH2 = false, eV1 = false, eV2 = false;
  if (hH1) { vec3 qm = PY(pmH1.x, pmH1.y), qo = PY(poH1.x, poH1.y); bH1 = distSqY(qm, pM) <= tolSq && distSqY(qo, pM) >= gapSq; eH1 = bH1 || meshWall46(qm, qo, pM, oA, oB, tolSq, gapSq); }
  if (hH2) { vec3 qm = PY(pmH2.x, pmH2.y), qo = PY(poH2.x, poH2.y); bH2 = distSqY(qm, pM) <= tolSq && distSqY(qo, pM) >= gapSq; eH2 = bH2 || meshWall46(qm, qo, pM, oA, oB, tolSq, gapSq); }
  bool spanH = (eH1 && eH2) || (bH1 && wH2) || (bH2 && wH1);
  if (!spanH) return false;
  if (hV1) { vec3 qm = PY(pmV1.x, pmV1.y), qo = PY(poV1.x, poV1.y); bV1 = distSqY(qm, pM) <= tolSq && distSqY(qo, pM) >= gapSq; eV1 = bV1 || meshWall46(qm, qo, pM, oA, oB, tolSq, gapSq); }
  if (hV2) { vec3 qm = PY(pmV2.x, pmV2.y), qo = PY(poV2.x, poV2.y); bV2 = distSqY(qm, pM) <= tolSq && distSqY(qo, pM) >= gapSq; eV2 = bV2 || meshWall46(qm, qo, pM, oA, oB, tolSq, gapSq); }
  bool spanV = (eV1 && eV2) || (bV1 && wV2) || (bV2 && wV1);
  if (!spanV) return false;
  bool wide = (bH1 && bH2) || (bV1 && bV2);
  if (!wide)
  {
    if (!((bH1 || bH2) && (bV1 || bV2))) return false;
    float qx = bH1 ? (pmH1.x < 0.0 ? -2.0 : 2.0) : (pmH2.x < 0.0 ? -2.0 : 2.0);
    float qy = bV1 ? -2.0 : 2.0;
    if (!meshQuad46(coord, qx, qy, pM, tolSq, gapSq, pmH1.x > 0.0)) return false;
  }
  vec2 pm11 = vec2(pmH1.x > 0.0 ? 2.0 : -1.0, -1.0);
  vec2 pm22 = vec2(pmH2.x > 0.0 ? 2.0 : -1.0,  2.0);
  vec3 qTmp = vec3(0.0), qA = vec3(0.0), qB = vec3(0.0);
  bool haveTmp = false, haveA = false, haveB = false;
  if (!meshCornerOk46(coord, pm11, hH1, hV1, wH1, wV1, mH1, mV1, pM, tolSq, gapSq, true,  !wide, qTmp, haveTmp)
   || !meshCornerOk46(coord, pm22, hH2, hV2, wH2, wV2, mH2, mV2, pM, tolSq, gapSq, true,  !wide, qTmp, haveTmp)
   || !meshCornerOk46(coord, pcA,  hH2, hV1, wH2, wV1, mH2, mV1, pM, tolSq, gapSq, false, !wide, qA,   haveA)
   || !meshCornerOk46(coord, pcB,  hH1, hV2, wH1, wV2, mH1, mV2, pM, tolSq, gapSq, false, !wide, qB,   haveB))
    return false;
  if (distSqY(oA, oB) <= tolSq)
  {
    vec3 pO = 0.5 * (oA + oB);
    if (min(min(distSqY(oH1, pO), distSqY(oH2, pO)), min(distSqY(oV1, pO), distSqY(oV2, pO))) >= SQ255(54.0))
    {
      if (!haveA) { qA = PY(pcA.x, pcA.y); haveA = true; }
      if (distSqY(qA, pO) <= tolSq) return false;
      if (!haveB) { qB = PY(pcB.x, pcB.y); haveB = true; }
      if (distSqY(qB, pO) <= tolSq) return false;
    }
  }
  if (meshFlankStroke46(coord, oA, oB, oH2, oV1, oH1, oV2, pcA, qA, haveA, tolSq)
   || meshFlankStroke46(coord, oB, oA, oH1, oV2, oH2, oV1, pcB, qB, haveB, tolSq))
    return false;
  return true;
}
// d) Shaded / gradient 2D checkerboards and high-contrast 1-parity 50% mesh-transparency overlays.
bool checkerShaded46(vec2 coord, vec3 kf, vec3 kg, vec3 kj, vec3 kk, float d0, float d1, float dFG, float dFJ,
                     vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko)
{
  float minEdgeSq = min(min(dFG, dFJ), min(distSqY(kk, kg), distSqY(kk, kj)));
  if (minEdgeSq < SQ255(30.0) || min(d0, d1) >= 0.18 * minEdgeSq) return false;
  if (max(d0, d1) < 0.18 * minEdgeSq)
  {
    vec3 p0 = 0.5 * (kf + kk), p1 = 0.5 * (kg + kj);
    float tolSq = 0.18 * distSqY(p0, p1);
    bool hL = chkSoftEq(ke, p1, p0, tolSq) && chkSoftEq(ki, p0, p1, tolSq);
    bool hR = chkSoftEq(kh, p0, p1, tolSq) && chkSoftEq(kl, p1, p0, tolSq);
    bool hU = chkSoftEq(kb, p1, p0, tolSq) && chkSoftEq(kc, p0, p1, tolSq);
    bool hD = chkSoftEq(kn, p0, p1, tolSq) && chkSoftEq(ko, p1, p0, tolSq);
    int rem = int(hL) + int(hR) + int(hU) + int(hD);
    if (rem >= 3)
    {
      int ok = 0;
      if (hL) { if (chkSoftEq(PY(-2.0, 0.0), p0, p1, tolSq) && chkSoftEq(PY(-2.0, 1.0), p1, p0, tolSq)) ok++; rem--; }
      if (ok + rem >= 3 && hR) { if (chkSoftEq(PY( 3.0, 0.0), p1, p0, tolSq) && chkSoftEq(PY( 3.0, 1.0), p0, p1, tolSq)) ok++; rem--; }
      if (ok + rem >= 3 && hU) { if (chkSoftEq(PY( 0.0,-2.0), p0, p1, tolSq) && chkSoftEq(PY( 1.0,-2.0), p1, p0, tolSq)) ok++; rem--; }
      if (ok >= 3) return true;
      if (ok + rem >= 3 && hD && chkSoftEq(PY( 0.0, 3.0), p1, p0, tolSq) && chkSoftEq(PY( 1.0, 3.0), p0, p1, tolSq)) ok++;
      if (ok >= 3) return true;
    }
  }
  float mTolSq = min(SQ255(26.0), 0.08 * minEdgeSq);
  if (minEdgeSq < SQ255(72.0) || min(d0, d1) > mTolSq) return false;
  float mGapSq = max(SQ255(72.0), 4.0 * mTolSq);
  if (d0 <= mTolSq && meshParity46(coord, kf, kk, kg, kj, mTolSq, mGapSq,
                                   ki, ke, kh, kl, kc, kb, kn, ko,
                                   vec2(-2.0, 0.0), vec2(-2.0, 1.0), vec2(3.0, 1.0), vec2(3.0, 0.0),
                                   vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(1.0, 3.0), vec2(0.0, 3.0),
                                   vec2(2.0, -1.0), vec2(-1.0, 2.0)))
    return true;
  if (d1 <= mTolSq && meshParity46(coord, kg, kj, kf, kk, mTolSq, mGapSq,
                                   kl, kh, ke, ki, kb, kc, ko, kn,
                                   vec2(3.0, 0.0), vec2(3.0, 1.0), vec2(-2.0, 1.0), vec2(-2.0, 0.0),
                                   vec2(1.0, -2.0), vec2(0.0, -2.0), vec2(0.0, 3.0), vec2(1.0, 3.0),
                                   vec2(-1.0, -1.0), vec2(2.0, 2.0)))
    return true;
  return false;
}
// Helper for 2x4 shaded or 3-row 1-parity 50% mesh checker strip beside an exact 1x4 solid wall (in-register checks first).
bool chkEdgeSoft2x4(vec2 coord, vec3 a0, vec3 b0, vec3 a1, vec3 b1, vec3 a2, vec3 b2, vec2 oA, vec2 oB, vec2 p3A, vec2 p3B, vec3 w, float dA0B0Sq, float dA01Sq, float dB01Sq)
{
  float minEdgeSq = min(min(dA0B0Sq, distSqY(a0, b1)), min(distSqY(a1, b0), distSqY(a1, b1)));
  if (minEdgeSq < SQ255(35.0) || min(dA01Sq, dB01Sq) >= 0.18 * minEdgeSq) return false;
  vec3 pA = 0.5 * (a0 + a1), pB = 0.5 * (b0 + b1);
  if (max(dA01Sq, dB01Sq) < 0.18 * minEdgeSq)
  {
    float tolSq = 0.18 * distSqY(pA, pB);
    if (chkSoftEq(a2, pA, pB, tolSq) && chkSoftEq(b2, pB, pA, tolSq)
        && chkSoftEq(PY(oA.x, oA.y), pA, pB, tolSq) && chkSoftEq(PY(oB.x, oB.y), pB, pA, tolSq))
      return true;
  }
  float mTolSq = min(SQ255(26.0), 0.08 * minEdgeSq);
  if (minEdgeSq < SQ255(72.0) || min(dA01Sq, dB01Sq) > mTolSq) return false;
  float mGapSq = max(SQ255(72.0), 4.0 * mTolSq);
  float dwA = distSqY(w, pA), dwB = distSqY(w, pB);
  bool baseA = dA01Sq <= mTolSq && (dwA <= mTolSq || (dwA >= mGapSq && neq(w, b0) && neq(w, b1)));
  bool baseB = dB01Sq <= mTolSq && (dwB <= mTolSq || (dwB >= mGapSq && neq(w, a0) && neq(w, a1)));
  if (!baseA && !baseB) return false;
  bool mA_P = distSqY(a2, pA) <= mTolSq, mA_M = distSqY(b2, pA) >= mGapSq;
  bool mB_M = distSqY(b2, pB) <= mTolSq, mB_P = distSqY(a2, pB) >= mGapSq;
  bool wM = eq(b2, w), wP = eq(a2, w);
  bool candA = baseA && ((mA_P && mA_M) || (wM && mA_P) || (wP && mA_M));
  bool candB = baseB && ((mB_M && mB_P) || (wM && mB_P) || (wP && mB_M));
  if (!candA && !candB) return false;
  vec3 qOA = PY(oA.x, oA.y), qOB = PY(oB.x, oB.y);
  bool perpM = wM && eq(qOA, w), perpP = wP && eq(qOB, w);
  bool sideA_M = mA_M && distSqY(qOA, pA) <= mTolSq;
  bool sideA_P = mA_P && distSqY(qOB, pA) >= mGapSq && !(dwA >= mGapSq && eq(w, b2) && eq(w, qOB));
  bool sideB_M = mB_M && distSqY(qOA, pB) >= mGapSq && !(dwB >= mGapSq && eq(w, a2) && eq(w, qOA));
  bool sideB_P = mB_P && distSqY(qOB, pB) <= mTolSq;
  bool okA = baseA && sideA_M && sideA_P;
  bool okB = baseB && sideB_M && sideB_P;
  bool cA_M = !okA && baseA && perpM && sideA_P;
  bool cA_P = !okA && baseA && perpP && sideA_M;
  bool cB_M = !okB && baseB && perpM && sideB_P;
  bool cB_P = !okB && baseB && perpP && sideB_M;
  if (!(okA || okB || cA_M || cA_P || cB_M || cB_P)) return false;
  vec3 q3A = PY(p3A.x, p3A.y), q3B = PY(p3B.x, p3B.y);
  bool r3A = distSqY(q3A, pA) <= mTolSq && distSqY(q3B, pA) >= mGapSq;
  bool r3B = distSqY(q3B, pB) <= mTolSq && distSqY(q3A, pB) >= mGapSq;
  if ((okA && r3A) || (okB && r3B)) return true;
  vec2 t = p3B - p3A, n = p3A - (oA + t);
  if ((cA_M && r3A) || (cB_M && r3B))
  {
    vec2 e1 = oB - n + t, e2 = oB + t, e3 = p3B + t, e4 = p3B + 2.0 * t;
    vec3 q1 = PY(e1.x, e1.y), q2 = PY(e2.x, e2.y), q3 = PY(e3.x, e3.y), q4 = PY(e4.x, e4.y);
    if (cA_M && r3A && distSqY(q1, pA) >= mGapSq && distSqY(q2, pA) <= mTolSq && distSqY(q3, pA) <= mTolSq && distSqY(q4, pA) >= mGapSq) return true;
    if (cB_M && r3B && distSqY(q1, pB) <= mTolSq && distSqY(q2, pB) >= mGapSq && distSqY(q3, pB) >= mGapSq && distSqY(q4, pB) <= mTolSq) return true;
  }
  if ((cA_P && r3A) || (cB_P && r3B))
  {
    vec2 e1 = oA - n - t, e2 = oA - t, e3 = p3A - t, e4 = p3A - 2.0 * t;
    vec3 q1 = PY(e1.x, e1.y), q2 = PY(e2.x, e2.y), q3 = PY(e3.x, e3.y), q4 = PY(e4.x, e4.y);
    if (cA_P && r3A && distSqY(q1, pA) <= mTolSq && distSqY(q2, pA) >= mGapSq && distSqY(q3, pA) >= mGapSq && distSqY(q4, pA) <= mTolSq) return true;
    if (cB_P && r3B && distSqY(q1, pB) >= mGapSq && distSqY(q2, pB) <= mTolSq && distSqY(q3, pB) <= mTolSq && distSqY(q4, pB) >= mGapSq) return true;
  }
  return false;
}
// 3-wall inner corner of a framed 50% mesh (3 pixels equal wall W, 1 odd corner O opens into a 3x3 alternating mesh).
bool chkCornerMesh46(vec2 coord, vec3 W, float dOWSq, vec3 m1, vec3 m2, vec3 w1, vec3 w2, float sx, float sy, float dx, float dy)
{
  if (dOWSq < SQ255(72.0) || !eq(w1, W) || !eq(w2, W)) return false;
  float mTolSq = min(SQ255(26.0), 0.08 * dOWSq);
  if (distSqY(m1, W) > mTolSq || distSqY(m2, W) > mTolSq) return false;
  float mGapSq = max(SQ255(72.0), 4.0 * mTolSq);
  return distSqY(PY(sx + dx, sy + dy), W) >= mGapSq
      && distSqY(PY(sx + 2.0 * dx, sy), W) >= mGapSq && distSqY(PY(sx + 2.0 * dx, sy + dy), W) <= mTolSq
      && distSqY(PY(sx, sy + 2.0 * dy), W) >= mGapSq && distSqY(PY(sx + dx, sy + 2.0 * dy), W) <= mTolSq
      && distSqY(PY(sx + 2.0 * dx, sy + 2.0 * dy), W) >= mGapSq;
}
// c) A 4-pixel solid wall column/row immediately adjacent to a confirmed 2x4 checker strip (exact, shaded, or 3-row 50% mesh).
bool chkCapPerp46(vec2 coord, vec3 c1, vec3 c2, vec3 sA0, vec3 sB0, vec2 pA1, vec2 pB1, vec2 pf0, vec2 pf1)
{
  bool cA0 = eq(sA0, c2), cB0 = eq(sB0, c1);
  bool wA0 = eq(sA0, c1), wB0 = eq(sB0, c2);
  if (!((cA0 && (cB0 || wB0)) || (cB0 && wA0))) return false;
  if (!eq(PY(pf0.x, pf0.y), c1) || !eq(PY(pf1.x, pf1.y), c2)) return false;
  vec3 sA1 = PY(pA1.x, pA1.y), sB1 = PY(pB1.x, pB1.y);
  bool cA = cA0 && eq(sA1, c1), cB = cB0 && eq(sB1, c2);
  bool wA = (cA0 || wA0) && eq(sA0, sA1);
  bool wB = (cB0 || wB0) && eq(sB0, sB1);
  return (cA && (cB || wB)) || (cB && wA);
}
bool chkEdgeDir46(vec2 coord, vec3 c1, vec3 c2, vec3 w, bool sameWall, vec3 wA, vec3 wB, bool eqWA, bool eqWB,
                  vec3 a1, vec3 b1, vec3 a2, vec3 b2, vec2 oA, vec2 oB, vec2 p3A, vec2 p3B, float dC12Sq, float dA01Sq, float dB01Sq)
{
  bool cIn = eq(b1, c2) && eq(a1, c1);
  if (eqWA && eqWB)
  {
    if (cIn)
    {
      if (sameWall)
      {
        if (eq(b2, c2) && eq(a2, c1) && eq(PY(oA.x, oA.y), c1) && eq(PY(oB.x, oB.y), c2))
          return true;
      }
      else if (chkCapPerp46(coord, c1, c2, b2, a2, oA, oB, p3A, p3B))
        return true;
    }
    return chkEdgeSoft2x4(coord, c1, c2, a1, b1, a2, b2, oA, oB, p3A, p3B, w, dC12Sq, dA01Sq, dB01Sq);
  }
  if (!sameWall || !cIn) return false;
  vec3 wOth = eqWA ? wB : wA;
  if (!(eq(eqWA ? a2 : b2, wOth) && neq(wOth, c1) && neq(wOth, c2) && eq(eqWA ? b2 : a2, eqWA ? c2 : c1)))
    return false;
  vec2 t = p3B - p3A, n = (oA - p3A) + t;
  vec2 oS = eqWA ? oA : oB;
  vec2 s1 = oS + n + (eqWA ? -t : t);
  vec2 s2 = s1 + n;
  vec3 cExp = eqWA ? c1 : c2;
  return eq(PY(oS.x, oS.y), cExp) && eq(PY(s1.x, s1.y), cExp) && eq(PY(s2.x, s2.y), w);
}
bool checkerEdge46(vec2 coord, vec3 kb, vec3 kc, vec3 ke, vec3 kf, vec3 kg, vec3 kh, vec3 ki, vec3 kj, vec3 kk, vec3 kl, vec3 kn, vec3 ko,
                   bool eqFG, bool eqFJ, bool eqJK, bool eqGK, vec4 jgSq, vec4 fkSq, float dFkSq, float dJgSq)
{
  if (eqGK != eqFJ)
  {
    vec3 w = eqGK ? kg : kf, wA = eqGK ? kc : kb, wB = eqGK ? ko : kn;
    bool eqWA = eq(wA, w), eqWB = eq(wB, w);
    if (eqWA || eqWB)
    {
      float dA = eqGK ? jgSq.x : fkSq.w, dB = eqGK ? fkSq.x : jgSq.w;
      vec3 c1 = eqGK ? kf : kg, c2 = eqGK ? kj : kk;
      float dC12Sq = distSqY(c1, c2);
      if (min(dA, dB) <= 0.18 * dC12Sq
          && chkEdgeDir46(coord, c1, c2, w, eqFG || eqJK, wA, wB, eqWA, eqWB,
                          eqGK ? ki : kl, eqGK ? ke : kh, eqGK ? kn : ko, eqGK ? kb : kc,
                          eqGK ? vec2(-1.0, -1.0) : vec2(2.0, -1.0), eqGK ? vec2(-1.0, 2.0) : vec2(2.0, 2.0),
                          eqGK ? vec2(-2.0,  0.0) : vec2(3.0,  0.0), eqGK ? vec2(-2.0, 1.0) : vec2(3.0, 1.0),
                          dC12Sq, dA, dB))
        return true;
    }
  }
  if (eqJK != eqFG)
  {
    vec3 w = eqJK ? kj : kf, wA = eqJK ? ki : ke, wB = eqJK ? kl : kh;
    bool eqWA = eq(wA, w), eqWB = eq(wB, w);
    if (eqWA || eqWB)
    {
      float dA = eqJK ? jgSq.y : fkSq.y, dB = eqJK ? fkSq.z : jgSq.z;
      vec3 c1 = eqJK ? kf : kj, c2 = eqJK ? kg : kk;
      float dC12Sq = distSqY(c1, c2);
      if (min(dA, dB) <= 0.18 * dC12Sq
          && chkEdgeDir46(coord, c1, c2, w, eqFJ || eqGK, wA, wB, eqWA, eqWB,
                          eqJK ? kc : ko, eqJK ? kb : kn, eqJK ? kh : kl, eqJK ? ke : ki,
                          eqJK ? vec2(-1.0, -1.0) : vec2(-1.0, 2.0), eqJK ? vec2(2.0, -1.0) : vec2(2.0, 2.0),
                          eqJK ? vec2( 0.0, -2.0) : vec2( 0.0, 3.0), eqJK ? vec2(1.0, -2.0) : vec2(1.0, 3.0),
                          dC12Sq, dA, dB))
        return true;
    }
  }
  if (eqGK != eqFJ && eqJK != eqFG)
  {
    if (eqFG && eqFJ && chkCornerMesh46(coord, kf, dFkSq, kl, ko, kh, kn, 1.0, 1.0,  1.0,  1.0)) return true;
    if (eqFG && eqGK && chkCornerMesh46(coord, kg, dJgSq, ki, kn, ke, ko, 0.0, 1.0, -1.0,  1.0)) return true;
    if (eqFJ && eqJK && chkCornerMesh46(coord, kj, dJgSq, kh, kc, kl, kb, 1.0, 0.0,  1.0, -1.0)) return true;
    if (eqGK && eqJK && chkCornerMesh46(coord, kk, dFkSq, ke, kb, ki, kc, 0.0, 0.0, -1.0, -1.0)) return true;
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
  vec4 jgSq = vec4(distSqY(kf, ki), distSqY(kc, kf), distSqY(kk, kn), distSqY(kh, kk));
  vec4 fkSq = vec4(distSqY(ke, kj), distSqY(kj, ko), distSqY(kb, kg), distSqY(kg, kl));
  float dJgSq = distSqY(kg, kj), dFkSq = distSqY(kf, kk);
  vec4 sJG = sqrt(jgSq);
  vec4 sFK = sqrt(fkSq);
  vec2 sDiag = sqrt(vec2(dJgSq, dFkSq));
  float jg = sJG.x + sJG.y + sJG.z + sJG.w + (4.0 * sDiag.x);
  float fk = sFK.x + sFK.y + sFK.z + sFK.w + (4.0 * sDiag.y);
  bool eqFG = eq(kf, kg), eqFJ = eq(kf, kj), eqJK = eq(kj, kk), eqGK = eq(kg, kk);
  if (jg + TIE_EPS < fk)
  {
    int t = (DOM_E * jg < fk) ? BLEND_DOMINANT : BLEND_NORMAL;
    if (!eqFG && !eqFJ) r.x = t;
    if (!eqJK && !eqGK) r.w = t;
  }
  else if (fk + TIE_EPS < jg)
  {
    int t = (DOM_E * fk < jg) ? BLEND_DOMINANT : BLEND_NORMAL;
    if (!eqFG && !eqGK) r.y = t;
    if (!eqFJ && !eqJK) r.z = t;
  }
//#crisp{
  if (CRISP_RULES)
  {
    bool eqFK = eq(kf, kk), eqGJ = eq(kg, kj);
    bool isChecker = eqFK && eqGJ && !eqFG;
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
    // 36. Crossing strokes: join j-g (if kf==kk) or f-k (if kg==kj); skip when r already chose that diagonal (no-op)
    if (eqFK != eqGJ)
    {
      float dStSq = eqFK ? dJgSq : dFkSq;
      if ((eqFK ? r.x : r.y) == BLEND_NONE && crossWinCore(eqFK ? kf : kg, eqFK ? kg : kf, eqFK ? kj : kk, dStSq))
      {
        float limSq = max(SQ255(30.0), 0.64 * dStSq);
        vec3 st1 = eqFK ? kg : kf, st2 = eqFK ? kj : kk, bg = eqFK ? kf : kg;
        if (thinOuter(coord, eqFK ? kc : kb, eqFK ? kh : ke, eqFK ? kb : kc, eqFK ? kl : ki, eqFK ? vec2(2.0, -1.0) : vec2(-1.0, -1.0), st1, st2, limSq)
            && thinOuter(coord, eqFK ? ki : kl, eqFK ? kn : ko, eqFK ? ke : kh, eqFK ? ko : kn, eqFK ? vec2(-1.0, 2.0) : vec2(2.0, 2.0), st1, st2, limSq)
            && (massOuter(coord, eqFK ? kb : kc, eqFK ? ke : kh, eqFK ? kc : kb, eqFK ? ki : kl, eqFK ? vec2(-1.0, -1.0) : vec2(2.0, -1.0), bg)
                || massOuter(coord, eqFK ? kl : ki, eqFK ? ko : kn, eqFK ? kh : ke, eqFK ? kn : ko, eqFK ? vec2(2.0, 2.0) : vec2(-1.0, 2.0), bg)))
          r = eqFK ? ivec4(BLEND_NORMAL, BLEND_NONE, BLEND_NONE, BLEND_NORMAL) : ivec4(BLEND_NONE, BLEND_NORMAL, BLEND_NORMAL, BLEND_NONE);
      }
    }
    // 46. a 2x2 checker (exact, shaded, or 50% mesh) inside a checker texture (or its edge against a solid wall) keeps its corners square
    if (r.x + r.y + r.z + r.w > 0)
    {
      if (eqFG || eqJK || eqFJ || eqGK)
      {
        if (checkerEdge46(coord, kb, kc, ke, kf, kg, kh, ki, kj, kk, kl, kn, ko, eqFG, eqFJ, eqJK, eqGK, jgSq, fkSq, dFkSq, dJgSq))
          r = ivec4(BLEND_NONE);
      }
      else
      {
        if (isChecker && checker46(coord, kf, kg, kb, kc, ke, kh, ki, kl, kn, ko))
          r = ivec4(BLEND_NONE);
        else
        {
          float dFG = distSqY(kf, kg), dFJ = distSqY(kf, kj);
          if (min(dFkSq, dJgSq) < 0.18 * min(dFG, dFJ)
              && checkerShaded46(coord, kf, kg, kj, kk, dFkSq, dJgSq, dFG, dFJ, kb, kc, ke, kh, ki, kl, kn, ko))
            r = ivec4(BLEND_NONE);
        }
      }
    }
  }
//#crisp}
  return r;
}

void main()
{
  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;
  vec3 rgbF = P(0., 0.), rgbG = P(1., 0.), rgbJ = P(0., 1.), rgbK = P(1., 1.);
  ivec4 r = ivec4(BLEND_NONE);
  // where the 2x2 is two rows or two columns of one color nothing blends (and rules 31 and 36 need a
  // diagonal of one color), so the 4x4 is read only at the other points
  if (!((eq(rgbF, rgbG) && eq(rgbJ, rgbK)) || (eq(rgbF, rgbJ) && eq(rgbG, rgbK))))
    r = pointBlend(coord, PY(0., -1.), PY(1., -1.), PY(-1., 0.), toYCbCr(rgbF), toYCbCr(rgbG), PY(2., 0.),
                   PY(-1., 1.), toYCbCr(rgbJ), toYCbCr(rgbK), PY(2., 1.), PY(0., 2.), PY(1., 2.));
  FRAG_OUT = vec4(rgbF, float(r.x + 4 * r.y + 16 * r.z + 64 * r.w) / 255.0);
}

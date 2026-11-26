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
// Matching pass of xbrz-crisp (Vulkan / slang): once per input pixel, between the resolve pass and pass 1 (rule 26)

layout(push_constant) uniform Push
{
	vec4 SourceSize;
	vec4 xbrz_crisp_refpassSize;
	vec4 OutputSize;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
	float XBRZ_MINC;
} global;
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
#define XBRZ_MINC global.XBRZ_MINC

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
// the resolve pass's decisions
layout(set = 0, binding = 2) uniform sampler2D Source;
// the input of the first pass (the preset's reference pass), which is the original image unless
// other shaders run before xBRZ
layout(set = 0, binding = 3) uniform sampler2D xbrz_crisp_refpass;
// pass 0's decisions, before the resolve pass changed them
layout(set = 0, binding = 4) uniform sampler2D xbrz_crisp_pass0;
ivec2 gIpx = ivec2(0), gMaxI = ivec2(0);
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define OUT_SIZE params.OutputSize
#define P(x,y) texelFetch(xbrz_crisp_refpass, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gMaxI), 0).rgb
#define INFO_CENTER texelFetch(Source, gIpx, 0)
#define INFO_AT(x, y) floor(texelFetch(Source, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gMaxI), 0) * 255.0 + 0.5)
#define W0_RAW texelFetch(xbrz_crisp_pass0, gIpx, 0)
#define W0_AT(x, y) floor(texelFetch(xbrz_crisp_pass0, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gMaxI), 0) * 255.0 + 0.5)

// the decision word of a corner (see pass 0 and the resolve pass): BLEND is the blend type, FLAG(r, f) one of its flags
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
vec4 cut4(vec4 w) { return vec4(greaterThan(BLEND(w), vec4(0.0))); }
// a pass-0 cut that is neither weak (blend 3) nor blocked (bit 128)
vec4 activeW0(vec4 w) { return cut4(w) * vec4(lessThan(BLEND(w), vec4(3.0))) * vec4(lessThan(w, vec4(128.0))); }
vec4 isLine45(vec4 r) { return FLAG(r, 4.0) * (1.0 - FLAG(r, 16.0)) * (1.0 - FLAG(r, 64.0)) * vec4(equal(FLAG(r, 32.0) + FLAG(r, 128.0), vec4(0.0))); }

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
#define TIE_EPS 1e-5     // matches pass 0: equal integer color steps can differ in the last float bits
#define XBRZ_SAME_M 15.0 // two pixels within this are one color (sameColor of the resolve pass); rule 41

// ---- Rule 26: matching corners ----
#define XBRZ_MATCH_EDGE 40.0  // E differs from one of the corner's two neighbors by more than this
#define XBRZ_MATCH_WRAP 50.0  // gap: the corner's two neighbors are within this of each other
#define XBRZ_MATCH_LINE 30.0  // gap: so are the same two pixels of both neighbors along the cut

// ---- Rule 27: a bar at a vertex ----
#define XBRZ_VERTEX_TOL 15.0  // the arms' pixels have C within this
#define XBRZ_VERTEX_EDGE 40.0 // G and T differ from C by more than this
#define XBRZ_VERTEX_BAR 15.0  // the bar's pixels have T's color within this

// E and its 4 cardinal neighbors in linear YCbCr, and E's squared YCbCr distances to them
vec3 nB, nD, nE, nF, nH;
float sBSq, sDSq, sFSq, sHSq;

float sideSq(vec2 n)
{
  return n.y < -0.5 ? sBSq : (n.y > 0.5 ? sHSq : (n.x < 0.0 ? sDSq : sFSq));
}
vec3 cardColor(vec2 n)
{
  return n.y < -0.5 ? nB : (n.y > 0.5 ? nH : (n.x < 0.0 ? nD : nF));
}

#define infoAt(o) INFO_AT((o).x, (o).y)
#define at3(o) toYCbCr(P((o).x, (o).y))
#define diagColor(c) at3(c)
#define diagInfo(c) infoAt(c)
#define cardInfo(n) infoAt(n)
bool pickSecSq(float dPri, float dSec, vec3 cPri, vec3 cSec)
{
  if (dSec + TIE_EPS < dPri) return true;
  if (dPri + TIE_EPS < dSec) return false;
  if (abs(cPri.x - cSec.x) > SAFE_EPS) return cSec.x < cPri.x;
  if (abs(cPri.y - cSec.y) > SAFE_EPS) return cSec.y < cPri.y;
  return cSec.z < cPri.z;
}

vec4 vtxCorner(vec2 c) { return vec4(c.x < 0.0 && c.y < 0.0, c.x > 0.0 && c.y < 0.0, c.x > 0.0 && c.y > 0.0, c.x < 0.0 && c.y > 0.0); }
bool vtxSec(vec2 c, vec2 n) { return (c.x * c.y > 0.0) != (abs(n.x) > 0.5); }
bool vtxSame(vec3 a, vec3 b) { return withinEqY255(a, b, XBRZ_VERTEX_TOL); }

bool vtxAt(vec2 u, vec2 v)
{
  if (sideSq(-u) <= SQ255(XBRZ_VERTEX_EDGE)) return false;
  vec3 C = cardColor(-u), T = cardColor(-v);
  if (vtxSame(C, cardColor(u))) return false;
  return vtxSame(C, at3(u - v)) && !vtxSame(C, at3(-u - v))
      && vtxSame(C, toYCbCr(P(v.x - 2.0 * u.x, v.y - 2.0 * u.y))) && vtxSame(C, toYCbCr(P(2.0 * u.x, 2.0 * u.y)))
      && withinEqY255(T, toYCbCr(P(-2.0 * v.x, -2.0 * v.y)), XBRZ_VERTEX_BAR)
      && withinEqY255(T, toYCbCr(P(-3.0 * v.x, -3.0 * v.y)), XBRZ_VERTEX_BAR);
}

bool vtxBetween(vec3 g, vec3 t, vec3 c)
{
  vec3 tc = t - c;
  float k = dot(g - c, tc) / max(dot(tc, tc), SAFE_EPS);
  float yt = t.x, yc = c.x, kY = (g.x - yc) / (abs(yt - yc) > 1e-3 ? yt - yc : 1e-3);
  return k > 0.15 && k < 0.85 && withinY255(c + k * tc, g, 24.0) && abs(yt - yc) > 1e-3 && kY > 0.15 && kY < 0.85;
}

void vtx(vec2 u, vec2 v, vec4 pairSq, inout vec4 res)
{
  vec2 c = -u - v;
  vec4 m = vtxCorner(c);
  float w = dot(res, m);
  if (BLEND(w) < 0.5 || FLAG(w, 4.0) < 0.5 || (FLAG(w, 8.0) > 0.5) != vtxSec(c, -v)
      || dot(pairSq, m) <= SQ255(XBRZ_VERTEX_EDGE) || !vtxAt(u, v)) return;
  if (vtxBetween(nE, cardColor(-v), cardColor(-u)))
    res = mix(res, vec4(vtxSec(c, -v) ? 9.0 : 1.0), m);
  else
  {
    res = mix(res, vec4(0.0), m);
    vec2 c2 = u - v;
    vec4 m2 = vtxCorner(c2);
    if ((FLAG(dot(res, m2), 8.0) > 0.5) == vtxSec(c2, -v)) res = mix(res, vec4(0.0), m2);
  }
}

// ---- Rule 38: a pixel kept whole at a junction of four colors ----
#define XBRZ_JUNC4 30.0
bool keptWhole(vec2 n)
{
  if (dot(cut4(cardInfo(n)), vec4(1.0)) > 0.5) return false;
  vec4 w0 = W0_AT(n.x, n.y);
  return dot(cut4(w0) * vec4(lessThan(BLEND(w0), vec4(3.0))) * FLAG(w0, 4.0), vec4(1.0)) > 0.5;
}
#define XBRZ_STEP38 0.5
vec4 junc4(vec4 res, vec4 pairSq)
{
  vec4 jm = cut4(res) * vec4(lessThan(FLAG(res, 16.0) + FLAG(res, 64.0), vec4(0.5)))
          * vec4(greaterThan(min(vec4(sDSq, sBSq, sFSq, sHSq), vec4(sBSq, sFSq, sHSq, sDSq)), vec4(SQ255(XBRZ_JUNC4))))
          * vec4(greaterThan(pairSq, vec4(SQ255(XBRZ_JUNC4))));
  if (dot(jm, vec4(1.0)) < 0.5) return res;
  vec3 E = nE;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    if (dot(jm, m) < 0.5) continue;
    vec3 Ch = c.x > 0.0 ? nF : nD, Cv = c.y > 0.0 ? nH : nB;
    vec3 X = at3(c);
    float lo5Sq = min(min(c.x > 0.0 ? sFSq : sDSq, c.y > 0.0 ? sHSq : sBSq),
                      min(distSqY(E, X), min(distSqY(Ch, X), distSqY(Cv, X))));
    if (lo5Sq <= SQ255(XBRZ_JUNC4) || dot(pairSq, m) < min((XBRZ_STEP38 * XBRZ_STEP38) * lo5Sq, SQ255(50.0))) continue;
    if (BLEND(dot(infoAt(c), vtxCorner(-c))) < 0.5) continue;
    if (!keptWhole(vec2(c.x, 0.0)) && !keptWhole(vec2(0.0, c.y))) continue;
    if ((withinY255(at3(vec2(c.x, -c.y)), Ch, XBRZ_SAME_M) && withinY255(toYCbCr(P(0.0, 2.0 * c.y)), Cv, XBRZ_SAME_M))
        || (withinY255(at3(vec2(-c.x, c.y)), Cv, XBRZ_SAME_M) && withinY255(toYCbCr(P(2.0 * c.x, 0.0)), Ch, XBRZ_SAME_M)))
      continue;
    res = mix(res, vec4(0.0), m);
  }
  return res;
}

// ---- Rule 39: a pixel exactly between its two corner colors ----
#define XBRZ_FAR39 100.0
#define XBRZ_MID39 0.1
vec4 tieRamp(vec4 res, vec4 m39)
{
  vec3 E = nE;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    if (dot(m39, m) < 0.5) continue;
    vec3 Nh = c.x > 0.0 ? nF : nD, Nv = c.y > 0.0 ? nH : nB;
    vec3 X = at3(c);
    float xdSq = min(distSqY(X, Nh), min(distSqY(X, Nv), distSqY(X, E)));
    if (xdSq <= SQ255(20.0)) continue;
    float wc = dot(res, m);
    bool tie = xdSq > SQ255(XBRZ_FAR39) && FLAG(wc, 16.0) + FLAG(wc, 64.0) < 0.5;
    if (!tie)
    {
      float aSq = c.x > 0.0 ? sFSq : sDSq, bSq = c.y > 0.0 ? sHSq : sBSq;
      if (min(aSq, bSq) > 0.99 * max(aSq, bSq))
        tie = abs(sqrt(aSq) - sqrt(bSq)) * 255.0 < 0.01;
    }
    if (tie) res = mix(res, vec4(0.0), m);
  }
  return res;
}

// ---- Rule 40: a dot separates what is around it ----
#define XBRZ_DOT40 40.0
#define XBRZ_DOTK40 8.0
bool dot40(vec2 n, vec3 c, vec3 K)
{
  float lk = K.x;
  if (c.x >= lk || withinY255(c, K, XBRZ_DOT40)) return false;
  float g = 0.0;
  vec2 r[8];
  r[0] = vec2(-1.0, -1.0); r[1] = vec2(0.0, -1.0); r[2] = vec2(1.0, -1.0); r[3] = vec2(1.0, 0.0);
  r[4] = vec2(1.0, 1.0); r[5] = vec2(0.0, 1.0); r[6] = vec2(-1.0, 1.0); r[7] = vec2(-1.0, 0.0);
  vec3 q = at3(n + vec2(-1.0, 0.0));
  if (withinY255(c, q, XBRZ_DOT40)) return false;
  bool qk = withinY255(q, K, XBRZ_DOTK40);
  if (!qk && q.x <= lk) return false;
  float nc = 0.0;
  vec3 u0 = q, u1 = q, u2 = q;
  bool prev = qk;
  for (int i = 0; i < 8; i++)
  {
    vec3 p = i == 7 ? q : at3(n + r[i]);
    if (i < 7 && withinY255(c, p, XBRZ_DOT40)) return false;
    bool k = i == 7 ? qk : withinY255(p, K, XBRZ_DOTK40);
    bool fresh = nc < 0.5 || (!withinY255(p, u0, XBRZ_DOTK40) && (nc < 1.5 || !withinY255(p, u1, XBRZ_DOTK40)) && (nc < 2.5 || !withinY255(p, u2, XBRZ_DOTK40)));
    if (fresh) { if (nc > 2.5) return false; if (nc < 0.5) u0 = p; else if (nc < 1.5) u1 = p; else u2 = p; nc += 1.0; }
    if (k && !prev) g += 1.0;
    if (!k && p.x <= lk) return false;
    prev = k;
  }
  return g > 1.5;
}
vec4 dots40(vec4 res, float minSideSq, vec4 pairSq)
{
  bool loneDot = false;
  if (minSideSq >= SQ255(XBRZ_DOT40) && nE.x < max(max(nB.x, nH.x), max(nD.x, nF.x)))
  {
    float d8Sq = min(min(distSqY(nE, at3(vec2(-1.0, -1.0))), distSqY(nE, at3(vec2(1.0, -1.0)))),
                     min(distSqY(nE, at3(vec2(-1.0,  1.0))), distSqY(nE, at3(vec2(1.0,  1.0)))));
    loneDot = d8Sq >= SQ255(XBRZ_DOT40);
  }
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float w = dot(res, m);
    if (BLEND(w) < 0.5) continue;
    bool horiz = (c.x * c.y > 0.0) != (FLAG(w, 8.0) > 0.5);
    vec2 kDir = horiz ? vec2(c.x, 0.0) : vec2(0.0, c.y);
    vec3 K = horiz ? (c.x > 0.0 ? nF : nD) : (c.y > 0.0 ? nH : nB);
    vec2 o = horiz ? vec2(0.0, c.y) : vec2(c.x, 0.0);
    vec3 Oc = horiz ? (c.y > 0.0 ? nH : nB) : (c.x > 0.0 ? nF : nD);
    if (sideSq(o) >= SQ255(XBRZ_DOT40) && Oc.x < K.x && dot(pairSq, m) >= SQ255(XBRZ_DOT40)
        && (nE.x > K.x || sideSq(kDir) < SQ255(XBRZ_DOTK40)) && dot40(o, Oc, K))
      res = mix(res, vec4(0.0), m);
    else if (loneDot && nE.x < K.x
             && (nB.x > K.x || withinY255(nB, K, XBRZ_DOTK40))
             && (nD.x > K.x || withinY255(nD, K, XBRZ_DOTK40))
             && (nF.x > K.x || withinY255(nF, K, XBRZ_DOTK40))
             && (nH.x > K.x || withinY255(nH, K, XBRZ_DOTK40))
             && dot40(vec2(0.0), nE, K))
      res = mix(res, vec4(3.0 + 8.0 * FLAG(w, 8.0)), m);
  }
  return res;
}

// ---- Rule 41: a 1-pixel diagonal stroke keeps an even edge ----
bool lone41(vec2 p)
{
  vec3 c = at3(p);
  return !withinY255(c, at3(p + vec2(-1.0, 0.0)), XBRZ_SAME_M) && !withinY255(c, at3(p + vec2(1.0, 0.0)), XBRZ_SAME_M)
      && !withinY255(c, at3(p + vec2(0.0, -1.0)), XBRZ_SAME_M) && !withinY255(c, at3(p + vec2(0.0, 1.0)), XBRZ_SAME_M);
}
bool lone41Card(vec2 p)
{
  // caller already verified sideSq(p) >= SQ255(XBRZ_SAME_M), so skip neighbor -p (= nE)
  vec3 c = cardColor(p);
  vec2 s = vec2(p.y, -p.x);
  return !withinY255(c, at3(2.0 * p), XBRZ_SAME_M)
      && !withinY255(c, at3(p + s), XBRZ_SAME_M)
      && !withinY255(c, at3(p - s), XBRZ_SAME_M);
}
float lineType41(float w)
{
  if (FLAG(w, 32.0) + FLAG(w, 128.0) > 0.5) return 0.0;
  return FLAG(w, 4.0) * (FLAG(w, 16.0) - FLAG(w, 64.0));
}
float edge41(vec2 c, vec4 r0, vec3 E)
{
  if (BLEND(dot(r0, vtxCorner(-c))) < 0.5) return 0.0;
  vec3 V = c.y > 0.0 ? nH : nB, H = c.x > 0.0 ? nF : nD;
  if (E.x > min(V.x, H.x) - 0.03) return 0.0;
  if (!withinY255(E, at3(vec2(c.x, -c.y)), XBRZ_SAME_M) || !withinY255(E, at3(vec2(-c.x, c.y)), XBRZ_SAME_M)) return 0.0;
  vec3 X = at3(c);
  if (withinY255(E, X, XBRZ_SAME_M)) return 0.0;
  bool kH = withinY255(X, H, XBRZ_SAME_M), kV = withinY255(X, V, XBRZ_SAME_M);
  if (kH == kV) return 0.0;
  vec2 o = kH ? vec2(0.0, c.y) : vec2(c.x, 0.0);
  vec3 O = cardColor(o);
  if (withinY255(O, toYCbCr(P(2.0 * o.x, 2.0 * o.y)), XBRZ_SAME_M)) return 0.0;
  if (withinY255(O, at3(o + vec2(c.x, -c.y)), XBRZ_SAME_M) || withinY255(O, at3(o + vec2(-c.x, c.y)), XBRZ_SAME_M)) return 0.0;
  bool sec = vtxSec(c, kH ? vec2(c.x, 0.0) : vec2(0.0, c.y));
  return sec ? 13.0 : 5.0;
}

// ---- 42. A step in a 45-degree edge ----
vec2 paintOf(vec2 c, float w) { return ((c.x * c.y > 0.0) != (FLAG(w, 8.0) > 0.5)) ? vec2(c.x, 0.0) : vec2(0.0, c.y); }
vec4 edgeStep42(vec4 res, vec4 m42)
{
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    if (dot(m42, m) < 0.5) continue;
    vec3 Kh = c.x > 0.0 ? nF : nD, Kv = c.y > 0.0 ? nH : nB;
    vec3 K = 0.5 * (Kh + Kv);
    if (withinY255(K, c.x > 0.0 ? nD : nF, XBRZ_SAME_M) || withinY255(K, c.y > 0.0 ? nB : nH, XBRZ_SAME_M)) continue;
    if (!withinY255(K, diagColor(c), XBRZ_SAME_M)) continue;
    float ok = 1.0;
    for (int j = 0; j < 2; j++)
    {
      vec2 q = j == 0 ? vec2(c.x, -c.y) : vec2(-c.x, c.y);
      float wq = dot(diagInfo(q), m);
      if (BLEND(wq) < 0.5 || FLAG(wq, 4.0) < 0.5 || FLAG(wq, 16.0) + FLAG(wq, 64.0) + FLAG(wq, 32.0) + FLAG(wq, 128.0) > 0.5
          || !withinY255(at3(q + paintOf(c, wq)), K, XBRZ_SAME_M))
      { ok = 0.0; break; }
    }
    if (ok > 0.5)
    {
      float hSq = c.x > 0.0 ? sFSq : sDSq, vSq = c.y > 0.0 ? sHSq : sBSq;
      bool hz = c.x * c.y > 0.0;
      float dPri = hz ? hSq : vSq, dSec = hz ? vSq : hSq;
      vec3 Nh = c.x > 0.0 ? nF : nD, Nv = c.y > 0.0 ? nH : nB;
      res = mix(res, vec4(pickSecSq(dPri, dSec, hz ? Nh : Nv, hz ? Nv : Nh) ? 13.0 : 5.0), m);
    }
  }
  return res;
}

vec4 diagStroke41(vec4 res, bool loneE, vec4 pairSq)
{
  vec3 E = nE;
  vec4 r0 = res;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float w = dot(r0, m);
    if (BLEND(w) < 0.5 && loneE) { float e41 = edge41(c, r0, E); if (e41 > 0.0) { res = mix(res, vec4(e41), m); w = e41; } }
    float t = lineType41(w);
    if (BLEND(w) < 0.5 || abs(t) < 0.5) continue;
    if (!loneE && (dot(pairSq, m) >= SQ255(XBRZ_SAME_M)
                   || min(c.x > 0.0 ? sFSq : sDSq, c.y > 0.0 ? sHSq : sBSq) < SQ255(XBRZ_SAME_M))) continue;
    for (int j = 0; j < 2; j++)
    {
      vec2 n = j == 0 ? vec2(c.x, 0.0) : vec2(0.0, c.y);
      float wn = dot(cardInfo(n), vtxCorner(-c));
      if (BLEND(wn) < 0.5 || lineType41(wn) != -t) continue;
      vec2 o = c - n;
      if (!loneE && lone41Card(n) && lone41Card(o))
      { res -= m * (16.0 * FLAG(w, 16.0) + 64.0 * FLAG(w, 64.0)); break; }
      vec2 q = -c + c * abs(n);
      if (loneE && withinY255(E, at3(n + q), XBRZ_SAME_M) && lone41(n + q))
      { res -= m * (4.0 + 16.0 * FLAG(w, 16.0) + 64.0 * FLAG(w, 64.0)); break; }
    }
  }
  return res;
}

// ---- Rule 43: a dome ----
float dome43(vec2 c, vec2 s, vec2 v)
{
  if (sideSq(-s) >= SQ255(XBRZ_SAME_M)) return 0.0;
  vec3 S = cardColor(s), U = cardColor(v);
  if (!withinY255(diagColor(c), U, XBRZ_SAME_M) || !withinY255(diagColor(v - s), U, XBRZ_SAME_M)
      || !withinY255(toYCbCr(P(-2.0 * s.x, -2.0 * s.y)), S, XBRZ_SAME_M)
      || !withinY255(toYCbCr(P(v.x - 2.0 * s.x, v.y - 2.0 * s.y)), U, XBRZ_SAME_M))
    return 0.0;
  return float(BLEND(dot(cardInfo(-s), vtxCorner(c - 2.0 * s))) > 0.5);
}
vec4 domes43(vec4 lost)
{
  vec4 d = vec4(0.0);
  for (int j = 0; j < 8; j++)
  {
    int i = j / 2;
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    if (dot(lost - d, m) < 0.5) continue;
    bool alongX = j - 2 * i == 0;
    vec2 s = alongX ? vec2(c.x, 0.0) : vec2(0.0, c.y), v = c - s;
    d += dome43(c, s, v) * m;
  }
  return d;
}

// ---- Rule 44: the end of a dark 1-pixel stroke ----
#define XBRZ_END44 100.0
float far44(vec3 E, float lE, vec2 o)
{
  vec3 q = diagColor(o);
  return float(distSqY(E, q) >= SQ255(XBRZ_END44) && q.x >= lE + 0.15);
}

vec4 strokeEnd44(vec4 res)
{
  vec4 sSq = vec4(sBSq, sFSq, sHSq, sDSq);
  if (dot(vec4(lessThan(sSq, vec4(SQ255(XBRZ_SAME_M)))), vec4(1.0)) != 1.0
      || dot(vec4(greaterThanEqual(sSq, vec4(SQ255(XBRZ_END44)))), vec4(1.0)) != 3.0)
    return res;
  vec2 v = sBSq < SQ255(XBRZ_SAME_M) ? vec2(0.0, -1.0) : sFSq < SQ255(XBRZ_SAME_M) ? vec2(1.0, 0.0) : sHSq < SQ255(XBRZ_SAME_M) ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
  vec2 u = vec2(v.y, v.x);
  vec3 E = nE;
  float lE = E.x;
  vec3 cTip = cardColor(-v), cU = cardColor(u), cMU = cardColor(-u);
  if (lE > 0.35 || dot(E.yz, E.yz) >= SQ255(50.0)
      || cTip.x < lE + 0.15 || cU.x < lE + 0.15 || cMU.x < lE + 0.15)
    return res;
  if (far44(E, lE, v + u) < 0.5 || far44(E, lE, v - u) < 0.5 || far44(E, lE, u - v) < 0.5 || far44(E, lE, -u - v) < 0.5)
    return res;
  if (min(distSqY(cTip, cU), min(distSqY(cTip, cMU), distSqY(cU, cMU))) >= SQ255(60.0)
      && withinY255(E, at3(2.0 * v), XBRZ_SAME_M)
      && withinY255(cTip, at3(-2.0 * v), XBRZ_SAME_M))
    return res;
  for (int k = 0; k < 2; k++)
  {
    vec2 c = k == 0 ? u - v : -u - v;
    vec4 m = vtxCorner(c);
    if (BLEND(dot(res, m)) > 0.5) continue;
    vec2 k1 = c - v, k2 = 2.0 * c + v;
    vec4 wG = diagInfo(c);
    if ((withinY255(E, at3(k1), XBRZ_SAME_M) && BLEND(dot(wG, vtxCorner(-c - 2.0 * v))) > 0.5)
        || (withinY255(E, at3(k2), XBRZ_SAME_M) && BLEND(dot(wG, vtxCorner(c + 2.0 * v))) > 0.5)) continue;
    float hSq = c.x > 0.0 ? sFSq : sDSq, vSq = c.y > 0.0 ? sHSq : sBSq;
    bool hz = c.x * c.y > 0.0;
    float dPri = hz ? hSq : vSq, dSec = hz ? vSq : hSq;
    vec3 Nh = c.x > 0.0 ? nF : nD, Nv = c.y > 0.0 ? nH : nB;
    res = mix(res, vec4(pickSecSq(dPri, dSec, hz ? Nh : Nv, hz ? Nv : Nh) ? 9.0 : 1.0), m);
  }
  return res;
}

// ---- Rule 49: a 1-pixel diagonal bar ----
#define XBRZ_BAR49 60.0
vec2 barEnd0(vec3 E, out vec3 dA, out vec3 dC, out vec3 dI, out vec3 dG)
{
  dC = vec3(0.0); dI = vec3(0.0); dG = vec3(0.0);
  float n = 0.0;
  vec2 c = vec2(0.0);
  vec3 Ccol = E;
  dA = at3(vec2(-1.0, -1.0));
  if (withinY255(E, dA, XBRZ_BAR49)) { n += 1.0; c = vec2(-1.0, -1.0); Ccol = dA; }
  dC = at3(vec2( 1.0, -1.0));
  if (withinY255(E, dC, XBRZ_BAR49)) { n += 1.0; if (n > 1.5) return vec2(0.0); c = vec2( 1.0, -1.0); Ccol = dC; }
  dI = at3(vec2( 1.0,  1.0));
  if (withinY255(E, dI, XBRZ_BAR49)) { n += 1.0; if (n > 1.5) return vec2(0.0); c = vec2( 1.0,  1.0); Ccol = dI; }
  dG = at3(vec2(-1.0,  1.0));
  if (withinY255(E, dG, XBRZ_BAR49)) { n += 1.0; if (n > 1.5) return vec2(0.0); c = vec2(-1.0,  1.0); Ccol = dG; }
  if (n < 0.5 || !withinY255(E, Ccol, XBRZ_SAME_M)) return vec2(0.0);
  float lE = E.x, l1 = (c.x > 0.0 ? nF.x : nD.x), l2 = (c.y > 0.0 ? nH.x : nB.x);
  if ((lE - l1) * (lE - l2) <= 0.0) return vec2(0.0);
  if (BLEND(dot(infoAt(vec2(c.x, 0.0)), vtxCorner(vec2(-c.x, c.y)))) < 0.5 ||
      BLEND(dot(infoAt(vec2(0.0, c.y)), vtxCorner(vec2(c.x, -c.y)))) < 0.5) return vec2(0.0);
  if (withinY255(E, at3(vec2(2.0 * c.x, 0.0)), XBRZ_BAR49)
      || withinY255(E, at3(vec2(0.0, 2.0 * c.y)), XBRZ_BAR49)
      || withinY255(E, at3(vec2(2.0 * c.x, c.y)), XBRZ_BAR49)
      || withinY255(E, at3(vec2(c.x, 2.0 * c.y)), XBRZ_BAR49))
    return vec2(0.0);
  float d2Sq = distSqY(E, at3(2.0 * c));
  if (d2Sq < SQ255(XBRZ_BAR49) && d2Sq >= SQ255(XBRZ_SAME_M)) return vec2(0.0);
  return c;
}

// Zero-color-fetch test: true iff cardinal neighbor q cuts corner k using center E (-q)
// (used when the other neighbor of q at corner k is already proven >= 15 from E).
bool cutsToCenter(vec2 q, vec2 k)
{
  float w = dot(infoAt(q), vtxCorner(k));
  if (BLEND(w) < 0.5) return false;
  bool hz = k.x * k.y > 0.0, sec = FLAG(w, 8.0) > 0.5;
  vec2 p = (hz == sec) ? vec2(0.0, k.y) : vec2(k.x, 0.0);
  return dot(p, q) < -0.5;
}

bool goesOn(vec2 k)
{
  // Caller guarantees minSideSq >= 60^2 (so cutsIn(k,-k,E) is always false) and dist(E,k) >= 60
  return cutsToCenter(vec2(k.x, 0.0), vec2(-k.x, k.y)) || cutsToCenter(vec2(0.0, k.y), vec2(k.x, -k.y));
}


// ---- Rule 41b/c: true 45-degree convex apex (strip colliding 2:1 pinch + complete multi-tone 45-deg edge) ----
// Zero-color-fetch test: caller's v45 guarantees both candidate paint pixels (E and s-u/-s-u) are within 15 of E.
bool hasLine45(vec2 q, vec2 k)
{
  float w = dot(infoAt(q), vtxCorner(k));
  return BLEND(w) >= 0.5 && FLAG(w, 4.0) >= 0.5
      && FLAG(w, 16.0) + FLAG(w, 64.0) + FLAG(w, 32.0) + FLAG(w, 128.0) < 0.5;
}
vec4 apex41(vec4 res, vec4 pairSq)
{
  vec4 c41 = cut4(res) * FLAG(res, 4.0);
  vec4 is21 = c41 * vec4(equal(FLAG(res, 32.0) + FLAG(res, 128.0), vec4(0.0)));
  vec4 f16 = FLAG(res, 16.0), f64 = FLAG(res, 64.0);
  vec4 sh41 = is21 * f16 * (1.0 - f64);
  vec4 st41 = is21 * f64 * (1.0 - f16);
  vec4 colEdge = vec4(
    max(sh41.x * c41.y, st41.y * c41.x),
    max(sh41.y * c41.z, st41.z * c41.y),
    max(sh41.z * c41.w, st41.w * c41.z),
    max(sh41.w * c41.x, st41.x * c41.w));
  vec4 minSideSq = min(vec4(sDSq, sFSq, sFSq, sDSq), vec4(sBSq, sBSq, sHSq, sHSq));
  vec4 validG4 = (1.0 - cut4(res)) * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_SAME_M))))
               * vec4(lessThan(pairSq, minSideSq))
               * vec4(greaterThanEqual(minSideSq, vec4(SQ255(XBRZ_MINC))));
  vec4 pA = is21 * (1.0 - f64);
  vec4 pB = is21 * (1.0 - f16);
  vec4 g4Edge = vec4(max(validG4.x * pB.y, validG4.y * pA.x),
                     max(validG4.y * pB.z, validG4.z * pA.y),
                     max(validG4.z * pB.w, validG4.w * pA.z),
                     max(validG4.w * pB.x, validG4.x * pA.w));
  if (dot(colEdge + g4Edge, vec4(1.0)) < 0.5) return res;
  bool sA = withinY255(nE, at3(vec2(-1.0, -1.0)), XBRZ_SAME_M);
  bool sI = withinY255(nE, at3(vec2( 1.0,  1.0)), XBRZ_SAME_M);
  if (sA == sI) return res;
  bool sC = withinY255(nE, at3(vec2( 1.0, -1.0)), XBRZ_SAME_M);
  bool sG = withinY255(nE, at3(vec2(-1.0,  1.0)), XBRZ_SAME_M);
  if (sC == sG) return res;
  vec4 l45 = is21 * (1.0 - f16) * (1.0 - f64);
  vec4 v45 = vec4(float(sG && sI && !sA && !sC), float(sA && sG && !sC && !sI),
                  float(sA && sC && !sG && !sI), float(sC && sI && !sA && !sG));
  vec4 actCol = colEdge * v45, actG4 = g4Edge * v45;
  if (dot(actCol + actG4, vec4(1.0)) < 0.5) return res;
  vec4 fixEdge = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec4 ek = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
    float doC = dot(actCol, ek), doG = dot(actG4, ek);
    if (doC + doG < 0.5) continue;
    vec2 u = k == 0 ? vec2(0.0, -1.0) : k == 1 ? vec2(1.0, 0.0) : k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
    vec2 s = vec2(u.y, -u.x);
    if (withinY255(nE, at3(s - 2.0 * u), XBRZ_SAME_M) && withinY255(nE, at3(-s - 2.0 * u), XBRZ_SAME_M)) continue;
    if (doC > 0.5) fixEdge += ek;
    if (doG > 0.5)
    {
      vec2 c1 = u + s, c2 = u - s;
      vec4 m1 = vtxCorner(c1), m2 = vtxCorner(c2);
      // loneE guarantees !cutsIn(c1,-c1,nE) & !cutsIn(c2,-c2,nE), and validG4.m1 & validG4.m2 are mutually exclusive
      if (dot(validG4, m1) > 0.5)
      {
        if (hasLine45(s, -c1) && !cutsToCenter(u, c1 - 2.0 * u) && (dot(l45, m2) > 0.5 || hasLine45(-s, -c2)))
        {
          res = mix(res, vec4(5.0), m1);
          if (dot(st41, m2) > 0.5) fixEdge += ek;
        }
      }
      else if (dot(validG4, m2) > 0.5)
      {
        if (hasLine45(-s, -c2) && !cutsToCenter(u, c2 - 2.0 * u) && (dot(l45, m1) > 0.5 || hasLine45(s, -c1)))
        {
          res = mix(res, vec4(13.0), m2);
          if (dot(sh41, m1) > 0.5) fixEdge += ek;
        }
      }
    }
  }
  fixEdge = min(fixEdge, vec4(1.0));
  res -= 16.0 * (sh41 * fixEdge) + 64.0 * (st41 * fixEdge.wxyz);
  return res;
}

// ---- Rules 47 and 48: lone shades along a stroke ----
#define XBRZ_NOTCH47 60.0
#define XBRZ_FAR47 80.0
#define XBRZ_SHADE48 60.0
float adjPairMinSq(vec2 a, vec4 pairSq)
{
  return a.y < -0.5 ? min(pairSq.x, pairSq.y)
       : a.y >  0.5 ? min(pairSq.z, pairSq.w)
       : a.x >  0.5 ? min(pairSq.y, pairSq.z)
                    : min(pairSq.w, pairSq.x);
}
bool isLone3x3Card(vec3 Q, vec2 a)
{
  // caller already verified sideSq(a) >= SQ255(XBRZ_SAME_M) and adjPairMinSq(a, pairSq) >= SQ255(XBRZ_SAME_M)
  vec2 s = vec2(a.y, -a.x);
  return !withinY255(Q, at3(a + s), XBRZ_SAME_M) && !withinY255(Q, at3(a - s), XBRZ_SAME_M)
      && !withinY255(Q, at3(2.0 * a + s), XBRZ_SAME_M) && !withinY255(Q, at3(2.0 * a), XBRZ_SAME_M)
      && !withinY255(Q, at3(2.0 * a - s), XBRZ_SAME_M);
}

// ---- Rule 28 post-resolve completion helpers (mirrors resolve.inc XBRZ_HOLD_SAME = 30.0) ----
#define XBRZ_HOLD28 30.0
float held28(vec3 a, vec3 b) { return float(distSqY(a, b) <= SQ255(XBRZ_HOLD28)); }
float holdOf28(vec3 c, vec3 tl, vec3 t, vec3 tr, vec3 l, vec3 r, vec3 bl, vec3 b, vec3 br)
{
  return held28(c, tl) + held28(c, tr) + held28(c, bl) + held28(c, br)
       + 2.0 * (held28(c, t) + held28(c, l) + held28(c, r) + held28(c, b));
}
float holdOfEdge28(vec3 c, float hE, vec3 in0, vec3 in1, vec3 in2, vec3 in3, vec3 in4, vec2 o0, vec2 o1, vec2 o2)
{
  float hIn = held28(c, in0) + held28(c, in1) + 2.0 * (held28(c, in2) + held28(c, in3) + held28(c, in4));
  if (hE > hIn + 4.5 || hIn > hE + 0.5) return hIn;
  return hIn + held28(c, at3(o0)) + 2.0 * held28(c, at3(o1)) + held28(c, at3(o2));
}
float tie28m(vec3 e, vec3 n)
{
  if (abs(e.x - n.x) > SAFE_EPS) return float(e.x < n.x);
  if (abs(e.y - n.y) > SAFE_EPS) return float(e.y < n.y);
  return float(e.z < n.z);
}

void main()
{
  gMaxI = ivec2(ORIG_SIZE.xy) - ivec2(1);
  gIpx = clamp(ivec2(floor(vTexCoord * ORIG_SIZE.xy)), ivec2(0), gMaxI);
  vec4 rawRes = INFO_CENTER;
  if (XBRZ_MINC <= 0.0)
  {
    FRAG_OUT = rawRes;
    return;
  }
  bool resZero = dot(rawRes, vec4(1.0)) < 0.5 / 255.0;
  vec3 pD = P(-1.0, 0.0), pE = P(0.0, 0.0), pF = P(1.0, 0.0);
  if (resZero && pD == pE && pF == pE)
  {
    FRAG_OUT = vec4(0.0);
    return;
  }
  vec3 pB = P(0.0, -1.0), pH = P(0.0, 1.0);
  if (resZero && pB == pE && pH == pE)
  {
    FRAG_OUT = vec4(0.0);
    return;
  }
  vec4 rawW0 = W0_RAW;
  vec4 res = floor(rawRes * 255.0 + 0.5);
  vec4 w0 = floor(rawW0 * 255.0 + 0.5);
  vec4 aW0 = activeW0(w0);
  bool noCuts = dot(cut4(res) + aW0, vec4(1.0)) == 0.0;

  // Fast path: when neither pass 0 nor resolve cuts any corner, only rules 42, 44 and 49 can cut one,
  // and all three need contrast >= min(XBRZ_MINC, XBRZ_BAR49) on both axes (D or F, and B or H)
  float fastLimSq = min(SQ255(XBRZ_MINC), SQ255(XBRZ_BAR49));
  nD = toYCbCr(pD);  nE = toYCbCr(pE);  nF = toYCbCr(pF);
  sDSq = distSqY(nE, nD); sFSq = distSqY(nE, nF);
  if (noCuts && max(sDSq, sFSq) < fastLimSq)
  {
    FRAG_OUT = res / 255.0;
    return;
  }
  nB = toYCbCr(pB);  nH = toYCbCr(pH);
  sBSq = distSqY(nE, nB); sHSq = distSqY(nE, nH);
  if (noCuts && max(sBSq, sHSq) < fastLimSq)
  {
    FRAG_OUT = res / 255.0;
    return;
  }

  float minSideSq = min(min(sBSq, sDSq), min(sFSq, sHSq));
  float maxSideSq = max(max(sBSq, sDSq), max(sFSq, sHSq));
  vec4 pairSq = vec4(distSqY(nB, nD), distSqY(nB, nF), distSqY(nF, nH), distSqY(nH, nD));

  vec4 maxCornerSq = max(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq));
  vec4 minCornerSq = min(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq));
  vec4 lost = aW0 * (1.0 - cut4(res));
  if (dot(lost, vec4(1.0)) > 0.0)
  {
    vec4 lostStrong = lost * vec4(greaterThan(maxCornerSq, vec4(SQ255(XBRZ_MATCH_EDGE))));
    vec4 fix = vec4(0.0);
    if (dot(lostStrong, vec4(1.0)) > 0.0)
    {
      vec4 iA = INFO_AT(-1.0, -1.0), iC = INFO_AT(1.0, -1.0);
      vec4 iI = INFO_AT( 1.0,  1.0), iG = INFO_AT(-1.0, 1.0);
      vec4 gap = vec4(cut4(iC).x * cut4(iG).x, cut4(iI).y * cut4(iA).y, cut4(iC).z * cut4(iG).z, cut4(iI).w * cut4(iA).w);
      vec4 wrapE = vec4(lessThan(pairSq, vec4(SQ255(XBRZ_MATCH_WRAP))));
      vec4 needGap = lostStrong * gap * wrapE;
      vec4 wrapN = vec4(0.0);
      if (needGap.x > 0.5) wrapN.x = float(withinY255(toYCbCr(P( 1.0, -2.0)), nB, XBRZ_MATCH_LINE) && withinY255(nD, toYCbCr(P(-2.0,  1.0)), XBRZ_MATCH_LINE));
      if (needGap.y > 0.5) wrapN.y = float(withinY255(toYCbCr(P(-1.0, -2.0)), nB, XBRZ_MATCH_LINE) && withinY255(nF, toYCbCr(P( 2.0,  1.0)), XBRZ_MATCH_LINE));
      if (needGap.z > 0.5) wrapN.z = float(withinY255(toYCbCr(P( 2.0, -1.0)), nF, XBRZ_MATCH_LINE) && withinY255(nH, toYCbCr(P(-1.0,  2.0)), XBRZ_MATCH_LINE));
      if (needGap.w > 0.5) wrapN.w = float(withinY255(nD, toYCbCr(P(-2.0, -1.0)), XBRZ_MATCH_LINE) && withinY255(toYCbCr(P( 1.0,  2.0)), nH, XBRZ_MATCH_LINE));

      vec4 part = vec4(cut4(iA).z, cut4(iC).w, cut4(iI).x, cut4(iG).y);
      vec4 l45 = vec4(isLine45(iA).z, isLine45(iC).w, isLine45(iI).x, isLine45(iG).y);
      vec4 pairCloser = vec4(lessThan(pairSq, maxCornerSq));
      vec4 junc26 = vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
                  * vec4(greaterThanEqual(pairSq, 0.5 * maxCornerSq));
      if (dot(lostStrong * junc26, vec4(1.0)) > 0.5)
      {
        vec4 onRamp26 = vec4(lessThan(sqrt(minCornerSq) + sqrt(pairSq), 1.12 * sqrt(maxCornerSq)));
        pairCloser *= 1.0 - junc26 * (1.0 - onRamp26);
      }
      fix = max(needGap * wrapN, lostStrong * pairCloser * part * l45 * (1.0 - FLAG(w0, 4.0)));
    }
    vec4 far43 = vec4(greaterThanEqual(min(vec4(sDSq, sFSq, sFSq, sDSq), vec4(sBSq, sBSq, sHSq, sHSq)), vec4(SQ255(XBRZ_MINC))))
               * vec4(lessThan(min(vec4(sFSq, sDSq, sDSq, sFSq), vec4(sHSq, sHSq, sBSq, sBSq)), vec4(SQ255(XBRZ_SAME_M))))
               * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MINC))));
    if (dot(lost, far43) > 0.0) fix = max(fix, domes43(lost * far43));
    if (dot(fix, vec4(1.0)) > 0.0)
    {
      vec4 noR9 = 1.0 - FLAG(w0, 32.0);
      vec4 back = 1.0 + 4.0 * FLAG(w0, 4.0) + 8.0 * FLAG(w0, 8.0) + noR9 * (16.0 * FLAG(w0, 16.0) + 64.0 * FLAG(w0, 64.0));
      res = mix(res, back, fix);
    }
    // Rescue a lost pass-0 diagonal line as a clean 45 deg line when P and Q are closer to each other than to E
    // (pair < minSide, minSide >= 40) and P's opposite corner already draws a live 45 deg line painting E
    vec4 cont45 = lost * (1.0 - cut4(res)) * FLAG(w0, 4.0) * vec4(lessThan(pairSq, minCornerSq))
                * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_MATCH_EDGE))));
    if (dot(cont45, vec4(1.0)) > 0.5)
    {
      vec4 w0Sec = FLAG(w0, 8.0);
      vec4 iB = INFO_AT( 0.0, -1.0), iD = INFO_AT(-1.0, 0.0);
      vec4 iF = INFO_AT( 1.0,  0.0), iH = INFO_AT( 0.0, 1.0);
      vec4 pOpp = mix(vec4(iD.z, iB.w, iF.x, iH.y), vec4(iB.z, iF.w, iH.x, iD.y), w0Sec);
      vec4 fix45 = cont45 * cut4(pOpp) * isLine45(pOpp) * vec4(equal(FLAG(pOpp, 8.0), w0Sec));
      if (dot(fix45, vec4(1.0)) > 0.5)
        res = mix(res, 1.0 + 4.0 + 8.0 * w0Sec, fix45);
    }
  }
  // Rule 26b: drop uncontinued junction cuts after resolve:
  // (a) plain (non-line) b1 with pairSq > 40 where the facing corner was cut in pass 0 and removed by resolve,
  // (b) plain b1 with pairSq >= 30 where the facing corner draws a diagonal line (or symmetric 4-color nb1)
  //     in the opposite side's color and neither cardinal edge neighbor continues the cut,
  // (c) plain b1 on an off-ramp obtuse 3-color triangle (pairSq > max(40^2, maxCornerSq), minCornerSq >= 20^2,
  //     sMin + sMax >= 1.12 * sPair) facing a diagonal line where the unchosen corner neighbor Q is completely uncut,
  // (d) lone plain b1 on an off-ramp 3-color triangle with oR == 0: either (d1) pair >= 30, minSide >= 30,
  //     sMin + sPair >= 1.25 * sMax with facing diagonal pixel, edgeCut, and unchosen Q all uncut, or (d2) pair >= 40,
  //     minSide >= 30, sMin + sPair >= 1.12 * sMax with painted P completely uncut and sameColor(P, diag), or
  // (e) non-2:1, non-ribbon off-ramp obtuse 3-color junction cut (pairSq > max(40^2, maxCornerSq),
  //     minCornerSq >= 0.25^2 * pairSq, sMin + sMax >= 1.12 * sPair) that survived Rule 20 only via a phantom
  //     pass-0 diagonal run whose run neighbors and facing corner were removed
  {
    vec4 nb1 = vec4(equal(BLEND(res), vec4(1.0))) * (1.0 - FLAG(res, 4.0))
             * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
    if (dot(nb1, vec4(1.0)) > 0.5)
    {
      vec4 dA = INFO_AT(-1.0, -1.0), dC = INFO_AT(1.0, -1.0);
      vec4 dI = INFO_AT( 1.0,  1.0), dG = INFO_AT(-1.0, 1.0);
      vec4 oInfo = vec4(dA.z, dC.w, dI.x, dG.y);
      vec4 oR = cut4(oInfo);
      vec4 nb1Orph = nb1 * vec4(greaterThan(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE)))) * (1.0 - oR);
      vec4 drop = vec4(0.0);
      if (dot(nb1Orph, vec4(1.0)) > 0.5)
      {
        vec4 oW0 = vec4(
          nb1Orph.x > 0.5 ? activeW0(W0_AT(-1.0, -1.0)).z : 0.0,
          nb1Orph.y > 0.5 ? activeW0(W0_AT( 1.0, -1.0)).w : 0.0,
          nb1Orph.z > 0.5 ? activeW0(W0_AT( 1.0,  1.0)).x : 0.0,
          nb1Orph.w > 0.5 ? activeW0(W0_AT(-1.0,  1.0)).y : 0.0);
        drop = nb1Orph * oW0;
      }
      vec4 diffSec = nb1 * oR * (1.0 - abs(FLAG(res, 8.0) - FLAG(oInfo, 8.0)));
      vec4 candB = diffSec * FLAG(oInfo, 4.0);
      vec4 candB2 = diffSec * vec4(equal(BLEND(oInfo), vec4(1.0))) * (1.0 - FLAG(oInfo, 4.0))
                  * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_MINC))));
      vec4 candB2ok = vec4(0.0);
      if (dot(candB2, vec4(1.0)) > 0.5)
      {
        vec4 oEdgeOk = vec4(0.0);
        if (candB2.x > 0.5) { vec3 Oc = diagColor(vec2(-1.0, -1.0)); oEdgeOk.x = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nB), distSqY(Oc, nD)) >= SQ255(XBRZ_MINC)); }
        if (candB2.y > 0.5) { vec3 Oc = diagColor(vec2( 1.0, -1.0)); oEdgeOk.y = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nB), distSqY(Oc, nF)) >= SQ255(XBRZ_MINC)); }
        if (candB2.z > 0.5) { vec3 Oc = diagColor(vec2( 1.0,  1.0)); oEdgeOk.z = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nF), distSqY(Oc, nH)) >= SQ255(XBRZ_MINC)); }
        if (candB2.w > 0.5) { vec3 Oc = diagColor(vec2(-1.0,  1.0)); oEdgeOk.w = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nH), distSqY(Oc, nD)) >= SQ255(XBRZ_MINC)); }
        candB2ok = candB2 * oEdgeOk;
      }
      vec4 obt26 = nb1 * oR * FLAG(oInfo, 4.0)
                 * vec4(greaterThan(pairSq, max(vec4(SQ255(XBRZ_MATCH_EDGE)), maxCornerSq)))
                 * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_MINC))));
      if (dot(obt26, vec4(1.0)) > 0.5)
        obt26 *= vec4(greaterThanEqual(sqrt(minCornerSq) + sqrt(maxCornerSq), 1.12 * sqrt(pairSq)));
      vec4 loneNb1 = nb1 * (1.0 - oR) * float(dot(cut4(res), vec4(1.0)) < 1.5)
                   * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_JUNC4))));
      vec4 isoOff = vec4(0.0), isoBar = vec4(0.0);
      if (dot(loneNb1, vec4(1.0)) > 0.5)
      {
        vec4 sSum = sqrt(minCornerSq) + sqrt(pairSq), sMax = sqrt(maxCornerSq);
        isoOff = loneNb1 * vec4(greaterThanEqual(sSum, 1.25 * sMax));
        isoBar = loneNb1 * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
               * vec4(greaterThanEqual(sSum, 1.12 * sMax));
      }
      if (dot(candB + candB2ok + obt26 + isoOff + isoBar, vec4(1.0)) > 0.5)
      {
        vec4 iB = INFO_AT( 0.0, -1.0), iD = INFO_AT(-1.0, 0.0);
        vec4 iF = INFO_AT( 1.0,  0.0), iH = INFO_AT( 0.0, 1.0);
        vec4 cB = cut4(iB), cD = cut4(iD), cF = cut4(iF), cH = cut4(iH);
        vec4 edgeCut = vec4(max(cB.z, cD.z), max(cB.w, cF.w), max(cF.x, cH.x), max(cH.y, cD.y));
        drop = max(drop, candB * (1.0 - edgeCut));
        if (dot(candB2ok, vec4(1.0)) > 0.5)
        {
          float sEA = float(withinY255(nE, diagColor(vec2(-1.0, -1.0)), XBRZ_SAME_M));
          float sEC = float(withinY255(nE, diagColor(vec2( 1.0, -1.0)), XBRZ_SAME_M));
          float sEI = float(withinY255(nE, diagColor(vec2( 1.0,  1.0)), XBRZ_SAME_M));
          float sEG = float(withinY255(nE, diagColor(vec2(-1.0,  1.0)), XBRZ_SAME_M));
          vec4 edgeCutE = vec4(
            max(cB.z * max(FLAG(iB.z, 8.0), sEC), cD.z * max(1.0 - FLAG(iD.z, 8.0), sEG)),
            max(cB.w * max(1.0 - FLAG(iB.w, 8.0), sEA), cF.w * max(FLAG(iF.w, 8.0), sEI)),
            max(cF.x * max(1.0 - FLAG(iF.x, 8.0), sEC), cH.x * max(FLAG(iH.x, 8.0), sEG)),
            max(cH.y * max(1.0 - FLAG(iH.y, 8.0), sEI), cD.y * max(FLAG(iD.y, 8.0), sEA)));
          drop = max(drop, candB2ok * (1.0 - edgeCutE));
        }
        if (dot(obt26 + isoOff + isoBar, vec4(1.0)) > 0.5)
        {
          vec4 uC = vec4(float(dot(cB, vec4(1.0)) < 0.5), float(dot(cD, vec4(1.0)) < 0.5),
                         float(dot(cF, vec4(1.0)) < 0.5), float(dot(cH, vec4(1.0)) < 0.5));
          vec4 secM = FLAG(res, 8.0);
          vec4 qUncut = mix(vec4(uC.x, uC.z, uC.w, uC.y), vec4(uC.y, uC.x, uC.z, uC.w), secM);
          drop = max(drop, obt26 * qUncut);
          if (dot(isoOff, vec4(1.0)) > 0.5)
          {
            vec4 dUncut = vec4(float(dot(cut4(dA), vec4(1.0)) < 0.5), float(dot(cut4(dC), vec4(1.0)) < 0.5),
                               float(dot(cut4(dI), vec4(1.0)) < 0.5), float(dot(cut4(dG), vec4(1.0)) < 0.5));
            vec4 isoBase = isoOff * (1.0 - edgeCut) * qUncut;
            drop = max(drop, isoBase * dUncut);
            vec4 isoWall = isoBase * (1.0 - dUncut) * float(minSideSq >= SQ255(XBRZ_SAME_M));
            if (dot(isoWall, vec4(1.0)) > 0.5)
            {
              for (int k = 0; k < 4; k++)
              {
                vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
                vec4 m = vtxCorner(c);
                if (dot(isoWall, m) < 0.5) continue;
                bool s1 = dot(secM, m) > 0.5;
                bool pIsV = (k == 0 || k == 2) ? s1 : !s1;
                vec2 pOff = pIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
                vec2 qOff = pIsV ? vec2(c.x, 0.0) : vec2(0.0, c.y);
                vec4 rPc = pOff.y < -0.5 ? iB : (pOff.y > 0.5 ? iH : (pOff.x < 0.0 ? iD : iF));
                if (dot(cut4(rPc) * FLAG(rPc, 4.0), vec4(1.0)) < 0.5 && withinY255(cardColor(qOff), diagColor(c), XBRZ_SAME_M))
                  drop = max(drop, m);
              }
            }
          }
          if (dot(isoBar, vec4(1.0)) > 0.5)
          {
            isoBar *= mix(vec4(uC.y, uC.x, uC.z, uC.w), vec4(uC.x, uC.z, uC.w, uC.y), secM);
            for (int k = 0; k < 4; k++)
            {
              vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
              vec4 m = vtxCorner(c);
              if (dot(isoBar, m) < 0.5) continue;
              bool s1 = dot(secM, m) > 0.5;
              bool pIsV = (k == 0 || k == 2) ? s1 : !s1;
              vec2 pOff = pIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
              if (withinY255(cardColor(pOff), diagColor(c), XBRZ_SAME_M))
                drop = max(drop, m);
            }
          }
        }
      }
      res *= 1.0 - drop;
    }
    vec4 oppLn26 = cut4(res.zwxy) * FLAG(res.zwxy, 4.0);
    vec4 ph26 = cut4(res) * (1.0 - FLAG(res, 16.0)) * (1.0 - FLAG(res, 64.0)) * (1.0 - oppLn26)
              * vec4(greaterThan(pairSq, max(vec4(SQ255(XBRZ_MATCH_EDGE)), maxCornerSq)))
              * vec4(greaterThanEqual(minCornerSq, 0.0625 * pairSq));
    if (dot(ph26, vec4(1.0)) > 0.5)
    {
      ph26 *= vec4(greaterThanEqual(sqrt(minCornerSq) + sqrt(maxCornerSq), 1.12 * sqrt(pairSq)));
      if (dot(ph26, vec4(1.0)) > 0.5)
      {
        vec4 iA = INFO_AT(-1.0, -1.0), iC = INFO_AT(1.0, -1.0);
        vec4 iI = INFO_AT( 1.0,  1.0), iG = INFO_AT(-1.0, 1.0);
        vec4 oR = vec4(cut4(iA).z, cut4(iC).w, cut4(iI).x, cut4(iG).y);
        vec4 runLive = vec4(max(cut4(iC).x, cut4(iG).x), max(cut4(iA).y, cut4(iI).y),
                            max(cut4(iC).z, cut4(iG).z), max(cut4(iA).w, cut4(iI).w));
        ph26 *= (1.0 - oR) * (1.0 - runLive);
        if (dot(ph26, vec4(1.0)) > 0.5)
        {
          vec4 wA = (ph26.y + ph26.w > 0.5) ? activeW0(W0_AT(-1.0, -1.0)) : vec4(0.0);
          vec4 wC = (ph26.x + ph26.z > 0.5) ? activeW0(W0_AT( 1.0, -1.0)) : vec4(0.0);
          vec4 wI = (ph26.y + ph26.w > 0.5) ? activeW0(W0_AT( 1.0,  1.0)) : vec4(0.0);
          vec4 wG = (ph26.x + ph26.z > 0.5) ? activeW0(W0_AT(-1.0,  1.0)) : vec4(0.0);
          vec4 hadRunP0 = vec4(max(wC.x, wG.x), max(wA.y, wI.y), max(wC.z, wG.z), max(wA.w, wI.w));
          res *= 1.0 - ph26 * hadRunP0;
        }
      }
    }
    // Rule 26d: downgrade a 2:1 shallow/steep line to 45 deg when the extended neighbor N has its adjacent corner
    // cut away at 45 deg, either:
    // (A) on a same-color diagonal (pairSq < 15^2) where diagonal X is closer to E than to N (d(N,X) >= 15 && d(N,X) > d(E,X)),
    // (B) on a 3-color edge (pairSq >= 30^2, d(N,X) >= 30, d(O,X) >= 20) painting O while the neighbor -O behind the
    //     2:1 extension shares E's color and is completely uncut, and N's 45 deg line paints X,
    // (C) on any distinct-color corner (pairSq >= 20^2, minCornerSq >= 30^2) painting O while N's 45 deg line
    //     paints E back across the edge (with E != X so N's sec is not an asymmetric tie), or
    // (D) on a 45-deg-sandwiched fake 2:1 (O != X, E != X, E's opposite corner is 45 deg, N's 45 deg line paints X,
    //     either O or diag(c) draws a 45 deg line at -c, and X is not 2:1 at -c)
    vec4 sh26 = FLAG(res, 16.0), st26 = FLAG(res, 64.0);
    vec4 ln21Base = cut4(res) * FLAG(res, 4.0) * abs(sh26 - st26)
                  * (1.0 - FLAG(res, 32.0)) * (1.0 - FLAG(res, 128.0));
    vec4 ln21A = ln21Base * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))));
    vec4 ln21B = ln21Base * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
    vec4 ln21C = ln21Base * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MINC))))
               * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_JUNC4))));
    vec4 ln21D = ln21Base * cut4(res.zwxy) * isLine45(res.zwxy);
    vec4 ln21 = max(max(ln21A, ln21B), max(ln21C, ln21D));
    if (dot(ln21, vec4(1.0)) > 0.5)
    {
      for (int k = 0; k < 4; k++)
      {
        vec4 m = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
        if (dot(ln21, m) < 0.5) continue;
        bool isSh = dot(sh26, m) > 0.5;
        vec2 nbrOff = isSh ? (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))))
                           : (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))));
        float nw = dot(INFO_AT(nbrOff.x, nbrOff.y), m.zwxy);
        if (BLEND(nw) < 0.5 || FLAG(nw, 4.0) < 0.5 || FLAG(nw, 16.0) > 0.5 || FLAG(nw, 64.0) > 0.5) continue;
        float wantSec = isSh ? 0.0 : 1.0;
        float nwSec = FLAG(nw, 8.0);
        vec2 extOff = isSh ? (k == 0 ? vec2(1.0, -1.0) : (k == 1 ? vec2(1.0, 1.0) : (k == 2 ? vec2(-1.0, 1.0) : vec2(-1.0, -1.0))))
                           : (k == 0 ? vec2(-1.0, 1.0) : (k == 1 ? vec2(-1.0, -1.0) : (k == 2 ? vec2(1.0, -1.0) : vec2(1.0, 1.0))));
        vec3 Nc = cardColor(nbrOff), Xc = diagColor(extOff);
        float dNXSq = distSqY(Nc, Xc), dEXSq = distSqY(nE, Xc);
        bool ok26d = false;
        if (dot(ln21C, m) > 0.5
            && abs(FLAG(dot(res, m), 8.0) - wantSec) < 0.5
            && abs(nwSec - (1.0 - wantSec)) < 0.5
            && dEXSq >= SQ255(XBRZ_SAME_M))
          ok26d = true;
        if (!ok26d && dot(ln21A, m) > 0.5)
        {
          if (dNXSq >= SQ255(XBRZ_SAME_M) && dNXSq > dEXSq
              && (abs(nwSec - wantSec) < 0.5 || dEXSq < SQ255(XBRZ_SAME_M)))
            ok26d = true;
        }
        else if (!ok26d && dot(ln21B, m) > 0.5
                 && abs(nwSec - wantSec) < 0.5
                 && abs(FLAG(dot(res, m), 8.0) - wantSec) < 0.5)
        {
          vec2 othOff = isSh ? (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))))
                             : (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))));
          vec3 Oc = cardColor(othOff);
          if (dNXSq >= SQ255(XBRZ_JUNC4) && distSqY(Oc, Xc) >= SQ255(XBRZ_MINC)
              && withinY255(nE, cardColor(-othOff), XBRZ_SAME_M)
              && dot(cut4(cardInfo(-othOff)), vec4(1.0)) < 0.5)
            ok26d = true;
        }
        if (!ok26d && dot(ln21D, m) > 0.5
            && FLAG(nw, 32.0) + FLAG(nw, 128.0) < 0.5
            && abs(nwSec - wantSec) < 0.5
            && dEXSq >= SQ255(XBRZ_SAME_M))
        {
          vec2 othOff = isSh ? (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))))
                             : (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))));
          if (distSqY(cardColor(othOff), Xc) >= SQ255(XBRZ_MINC))
          {
            vec4 rO = cardInfo(othOff), rD = diagInfo(nbrOff + othOff);
            if (dot(cut4(rO) * isLine45(rO) + cut4(rD) * isLine45(rD), m.zwxy) > 0.5)
            {
              float xw = dot(INFO_AT(extOff.x, extOff.y), m.zwxy);
              if (FLAG(xw, 16.0) + FLAG(xw, 64.0) < 0.5)
                ok26d = true;
            }
          }
        }
        if (ok26d)
          res -= m * (isSh ? 16.0 : 64.0);
      }
    }
  }
  // Rule 28 post-resolve completion: catch crossing 2:1 color swaps missed in resolve when one side was R2-blocked,
  // and flip off-ramp 2:1 color when the neighbor across the shared edge draws the matching opposite 2:1 line in Q's color
  {
    vec4 sec28 = FLAG(res, 8.0);
    vec4 p28 = cut4(res) * FLAG(res, 4.0) * (1.0 - FLAG(res, 32.0)) * (1.0 - FLAG(res, 128.0))
             * mix(FLAG(res, 64.0), FLAG(res, 16.0), sec28);
    if (dot(p28, vec4(1.0)) > 0.5)
    {
      vec4 iB = INFO_AT( 0.0, -1.0), iD = INFO_AT(-1.0, 0.0);
      vec4 iF = INFO_AT( 1.0,  0.0), iH = INFO_AT( 0.0, 1.0);
      vec4 nW = mix(vec4(iD.z, iB.w, iF.x, iH.y), vec4(iB.z, iF.w, iH.x, iD.y), sec28);
      vec4 pair28 = p28 * cut4(nW) * FLAG(nW, 4.0) * (1.0 - FLAG(nW, 32.0)) * (1.0 - FLAG(nW, 128.0))
                  * vec4(equal(FLAG(nW, 8.0), sec28)) * mix(FLAG(nW, 64.0), FLAG(nW, 16.0), sec28);
      if (dot(pair28, vec4(1.0)) > 0.5)
      {
        vec3 nA = diagColor(vec2(-1.0, -1.0)), nC = diagColor(vec2(1.0, -1.0));
        vec3 nG = diagColor(vec2(-1.0,  1.0)), nI = diagColor(vec2(1.0,  1.0));
        float hE = holdOf28(nE, nA, nB, nC, nD, nF, nG, nH, nI), hB = 0.0, hD = 0.0, hF = 0.0, hH = 0.0;
        if (pair28.x * sec28.x + pair28.y * (1.0 - sec28.y) > 0.5) hB = holdOfEdge28(nB, hE, nD, nF, nA, nC, nE, vec2(-1.,-2.), vec2( 0.,-2.), vec2( 1.,-2.));
        if (pair28.x * (1.0 - sec28.x) + pair28.w * sec28.w > 0.5) hD = holdOfEdge28(nD, hE, nB, nH, nA, nE, nG, vec2(-2.,-1.), vec2(-2., 0.), vec2(-2., 1.));
        if (pair28.y * sec28.y + pair28.z * (1.0 - sec28.z) > 0.5) hF = holdOfEdge28(nF, hE, nB, nH, nC, nE, nI, vec2( 2.,-1.), vec2( 2., 0.), vec2( 2., 1.));
        if (pair28.z * sec28.z + pair28.w * (1.0 - sec28.w) > 0.5) hH = holdOfEdge28(nH, hE, nD, nF, nE, nG, nI, vec2(-1., 2.), vec2( 0., 2.), vec2( 1., 2.));
        vec4 hN = mix(vec4(hD, hB, hF, hH), vec4(hB, hF, hH, hD), sec28);
        vec4 tie = vec4(tie28m(nE, sec28.x > 0.5 ? nB : nD), tie28m(nE, sec28.y > 0.5 ? nF : nB),
                        tie28m(nE, sec28.z > 0.5 ? nH : nF), tie28m(nE, sec28.w > 0.5 ? nD : nH));
        vec4 whole = max(vec4(greaterThan(vec4(hE), hN + 0.5)),
                         vec4(lessThan(abs(hE - hN), vec4(0.5))) * tie);
        res *= 1.0 - pair28 * whole;
      }
      vec4 opp28 = p28 * abs(FLAG(res, 16.0) - FLAG(res, 64.0))
                 * cut4(nW) * FLAG(nW, 4.0) * (1.0 - FLAG(nW, 32.0)) * (1.0 - FLAG(nW, 128.0))
                 * abs(FLAG(nW, 16.0) - FLAG(nW, 64.0))
                 * vec4(notEqual(FLAG(nW, 8.0), sec28)) * mix(FLAG(nW, 64.0), FLAG(nW, 16.0), sec28)
                 * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MINC))));
      if (dot(opp28, vec4(1.0)) > 0.5)
      {
        vec4 flip28 = vec4(0.0);
        for (int k = 0; k < 4; k++)
        {
          vec4 m = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
          if (dot(opp28, m) < 0.5) continue;
          bool isSh = dot(sec28, m) > 0.5;
          vec2 nbrOff = isSh ? (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))))
                             : (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))));
          vec2 othOff = isSh ? (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))))
                             : (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))));
          vec2 extOff = nbrOff - othOff;
          if (withinY255(cardColor(othOff), diagColor(extOff), XBRZ_SAME_M)
              && sqrt(sideSq(nbrOff)) + sqrt(dot(pairSq, m)) > 1.2 * sqrt(sideSq(othOff)))
            flip28 += m * (isSh ? -8.0 : 8.0);
        }
        res += flip28;
      }
    }
  }
  // Rule 28b: unflip a Rule-18 dark 2:1 line (painting O along N, d(E,N) < min(60, d(E,O)), pair >= 40)
  // back to N when N is uncut at -c and X (= extOff, matching O) cuts its corner facing E with a line
  {
    vec4 sh18 = FLAG(res, 16.0), st18 = FLAG(res, 64.0), sec18 = FLAG(res, 8.0);
    vec4 u18 = cut4(res) * FLAG(res, 4.0) * abs(sh18 - st18)
             * (1.0 - FLAG(res, 32.0)) * (1.0 - FLAG(res, 128.0))
             * mix(sh18, st18, sec18)
             * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
             * vec4(lessThan(minCornerSq, vec4(SQ255(60.0))));
    if (dot(u18, vec4(1.0)) > 0.5)
    {
      vec4 unflip = vec4(0.0);
      for (int k = 0; k < 4; k++)
      {
        vec4 m = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
        if (dot(u18, m) < 0.5) continue;
        bool isSh = dot(sh18, m) > 0.5;
        vec2 nbrOff = isSh ? (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))))
                           : (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))));
        vec2 othOff = isSh ? (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))))
                           : (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))));
        float dNSq = sideSq(nbrOff), dOSq = sideSq(othOff);
        if (dNSq >= SQ255(60.0) || dNSq >= dOSq - TIE_EPS) continue;
        if (BLEND(dot(INFO_AT(nbrOff.x, nbrOff.y), m.zwxy)) > 0.5) continue;
        vec2 extOff = nbrOff - othOff;
        if (!withinY255(cardColor(othOff), diagColor(extOff), XBRZ_SAME_M)) continue;
        float xw = dot(INFO_AT(extOff.x, extOff.y), vtxCorner(-extOff));
        if (BLEND(xw) > 0.5 && FLAG(xw, 4.0) > 0.5)
          unflip += m * (isSh ? 8.0 : -8.0);
      }
      res += unflip;
    }
  }
  // Rule 26e: 2px Eye L-corner after resolve — drop a 45 deg line cutting a straight 2px light sclera E
  // (lE - max(lP, lQ) >= 0.15, minSide >= 60, pair >= 30) tucked inside two orthogonal uncut straight dark bars
  // (Q == diag and P == P-q, e.g., eyebrow + 2px iris after resolve squared the eyebrow)
  {
    vec4 eyeC = cut4(res) * isLine45(res)
              * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))))
              * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(60.0))));
    if (dot(eyeC, vec4(1.0)) > 0.5)
    {
      vec4 secM = FLAG(res, 8.0);
      vec4 dropEye = vec4(0.0);
      for (int k = 0; k < 4; k++)
      {
        vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
        vec4 m = vtxCorner(c);
        if (dot(eyeC, m) < 0.5) continue;
        bool s1 = dot(secM, m) > 0.5;
        bool pIsV = (k == 0 || k == 2) ? s1 : !s1;
        vec2 pOff = pIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
        vec2 qOff = pIsV ? vec2(c.x, 0.0) : vec2(0.0, c.y);
        vec3 Pc = cardColor(pOff), Qc = cardColor(qOff);
        if (max(Pc.x, Qc.x) > nE.x - 0.15) continue;
        if (!withinY255(nE, cardColor(-qOff), XBRZ_SAME_M) || withinY255(nE, cardColor(-pOff), XBRZ_SAME_M)) continue;
        if (!withinY255(Qc, diagColor(c), XBRZ_SAME_M) || !withinY255(Pc, diagColor(pOff - qOff), XBRZ_SAME_M)) continue;
        if (dot(cut4(cardInfo(pOff)), vec4(1.0)) > 0.5) continue;
        if (dot(cut4(cardInfo(qOff)), vec4(1.0)) > 0.5) continue;
        if (dot(cut4(diagInfo(c)), vec4(1.0)) > 0.5) continue;
        dropEye += m;
      }
      res *= 1.0 - min(dropEye, vec4(1.0));
    }
  }
  // Rule 26f: upgrade a 45 deg line on a high-contrast (>= 100) gradient edge (pair < 45, d(N,X) < 45) to 2:1
  // shallow/steep when E forms a 2px step along the curve (E == -othOff, E == runOff) and the partner at extOff
  // already draws the matching 2:1 line (eliminating half-pixel stair steps on smooth outline curves)
  {
    vec4 ln45 = cut4(res) * isLine45(res)
              * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(100.0))))
              * vec4(lessThan(pairSq, vec4(SQ255(45.0))));
    if (dot(ln45, vec4(1.0)) > 0.5)
    {
      for (int k = 0; k < 4; k++)
      {
        vec4 m = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
        if (dot(ln45, m) < 0.5) continue;
        float addBit = 0.0;
        for (int dir = 0; dir < 2; dir++)
        {
          bool isSh = (dir == 0);
          vec2 nbrOff = isSh ? (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))))
                             : (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))));
          vec2 othOff = isSh ? (k == 0 ? vec2(-1.0, 0.0) : (k == 1 ? vec2(0.0, -1.0) : (k == 2 ? vec2(1.0, 0.0) : vec2(0.0, 1.0))))
                             : (k == 0 ? vec2(0.0, -1.0) : (k == 1 ? vec2(1.0, 0.0) : (k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0))));
          vec2 extOff = nbrOff - othOff;
          vec2 runOff = othOff - nbrOff;
          if (!withinY255(nE, cardColor(-othOff), XBRZ_SAME_M)) continue;
          if (!withinY255(nE, diagColor(runOff), XBRZ_SAME_M)) continue;
          vec3 Nc = cardColor(nbrOff), Xc = diagColor(extOff);
          if (distSqY(Nc, Xc) >= SQ255(45.0) || distSqY(nE, Xc) < SQ255(100.0)) continue;
          float xw = dot(INFO_AT(extOff.x, extOff.y), m.zwxy);
          float wantBit = isSh ? 16.0 : 64.0;
          float otherBit = isSh ? 64.0 : 16.0;
          if (BLEND(xw) > 0.5 && FLAG(xw, 4.0) > 0.5 && FLAG(xw, wantBit) > 0.5 && FLAG(xw, otherBit) < 0.5
              && FLAG(xw, 32.0) < 0.5 && FLAG(xw, 128.0) < 0.5)
            addBit = addBit > 0.5 ? -1.0 : wantBit;
        }
        if (addBit > 0.5)
          res += m * addBit;
      }
    }
  }
  // Rule 26c (unified dark-outline flat-wall guard):
  // - non-line (!line): lone near-black (<= 0.20) b1 bevel leaking a darker uncut Pc against a brighter 3px wall Qc
  // - line (line): dark low-chroma outline leaking a lighter off-ramp color across a > 100 YCbCr flat wall
  if (nE.x <= 0.30)
  {
    vec4 isL26 = FLAG(res, 4.0);
    vec4 wallNb1 = float(nE.x <= 0.20) * vec4(equal(BLEND(res), vec4(1.0))) * (1.0 - isL26)
                 * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
    vec4 wallLn  = float(dot(nE.yz, nE.yz) < SQ255(50.0)) * cut4(res) * isL26
                 * vec4(greaterThan(pairSq, vec4(SQ255(100.0))));
    vec4 wallAll = max(wallNb1, wallLn);
    if (dot(wallAll, vec4(1.0)) > 0.5)
    {
      vec4 secM = FLAG(res, 8.0);
      vec4 sqW = vec4(0.0);
      for (int k = 0; k < 4; k++)
      {
        vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
        vec4 m = vtxCorner(c);
        if (dot(wallAll, m) < 0.5) continue;
        vec4 oppM = vtxCorner(-c);
        if (BLEND(dot(diagInfo(c), oppM)) > 0.5) continue;
        bool s1 = dot(secM, m) > 0.5;
        bool pIsV = (k == 0 || k == 2) ? s1 : !s1;
        vec2 pOff = pIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
        vec2 qOff = pIsV ? vec2(c.x, 0.0) : vec2(0.0, c.y);
        vec3 Pc = cardColor(pOff), Qc = cardColor(qOff);
        if (dot(wallNb1, m) > 0.5)
        {
          float aw = dot(res, vtxCorner(pOff - qOff));
          if (BLEND(aw) < 0.5 || FLAG(aw, 4.0) < 0.5) continue;
          if (Pc.x >= Qc.x - 0.15 || Qc.x < nE.x + 0.30) continue;
          if (!withinY255(nE, cardColor(-pOff), XBRZ_SAME_M)) continue;
          if (BLEND(dot(cardInfo(qOff), oppM)) > 0.5) continue;
          if (dot(cut4(cardInfo(pOff)), vec4(1.0)) > 0.5) continue;
          if (!withinY255(Qc, diagColor(c), XBRZ_SAME_M) || !withinY255(Qc, diagColor(qOff - pOff), XBRZ_SAME_M)) continue;
          if (withinY255(Pc, diagColor(pOff - qOff), XBRZ_SAME_M)) continue;
          sqW += m;
        }
        else
        {
          if (Pc.x < nE.x + 0.10) continue;
          float qw = dot(cardInfo(qOff), oppM);
          if (BLEND(qw) < 0.5 || FLAG(qw, 4.0) < 0.5) continue;
          vec4 rPc = cardInfo(pOff);
          if (dot(cut4(rPc) * FLAG(rPc, 4.0), vec4(1.0)) > 0.5) continue;
          if (distSqY(Qc, diagColor(c)) >= SQ255(XBRZ_SAME_M)) continue;
          vec3 dQP = diagColor(qOff - pOff), dPQ = diagColor(pOff - qOff);
          if (!withinY255(nE, dQP, XBRZ_SAME_M)) continue;
          vec3 eqV = Qc - nE;
          float tP = clamp(dot(Pc - nE, eqV) / max(dot(eqV, eqV), SAFE_EPS), 0.0, 1.0);
          vec3 perpV = Pc - (nE + tP * eqV);
          if (dot(perpV, perpV) < SQ255(24.0)) continue;
          if (distSqY(Pc, dQP) < SQ255(XBRZ_JUNC4) || distSqY(Pc, dPQ) < SQ255(XBRZ_JUNC4)) continue;
          if (withinY255(Pc, at3(2.0 * pOff), XBRZ_SAME_M)) continue;
          if (!withinY255(Qc, at3(2.0 * qOff), XBRZ_SAME_M)) continue;
          sqW += m;
        }
      }
      res *= 1.0 - min(sqW, vec4(1.0));
    }
  }
  // rule 27
  if (maxSideSq > SQ255(XBRZ_VERTEX_EDGE)
      && dot(cut4(res) * FLAG(res, 4.0) * vec4(greaterThan(pairSq, vec4(SQ255(XBRZ_VERTEX_EDGE)))), vec4(1.0)) > 0.5)
  {
    for (int i = 0; i < 8; i++)
    {
      vec2 u = i == 0 || i == 2 ? vec2(1.0, 0.0) : i == 1 || i == 3 ? vec2(-1.0, 0.0) : i == 4 || i == 6 ? vec2(0.0, 1.0) : vec2(0.0, -1.0);
      vec2 v = i < 2 ? vec2(0.0, 1.0) : i < 4 ? vec2(0.0, -1.0) : i < 6 ? vec2(1.0, 0.0) : vec2(-1.0, 0.0);
      vtx(u, v, pairSq, res);
    }
  }
  // 42
  vec4 m42 = (1.0 - cut4(res))
           * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_MINC))))
           * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))));
  if (dot(m42, vec4(1.0)) > 0.5) res = edgeStep42(res, m42);
  // rules 38 to 41
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = junc4(res, pairSq);
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    vec4 hi39 = max(vec4(sDSq, sFSq, sFSq, sDSq), vec4(sBSq, sBSq, sHSq, sHSq));
    vec4 m39 = cut4(res) * vec4(greaterThan(minCornerSq, vec4(SQ255(20.0))))
             * vec4(greaterThan(minCornerSq, (1.0 - XBRZ_MID39) * (1.0 - XBRZ_MID39) * hi39))
             * vec4(greaterThan(pairSq, 3.24 * hi39));
    if (dot(m39, vec4(1.0)) > 0.5) res = tieRamp(res, m39);
  }
  if (maxSideSq >= SQ255(XBRZ_DOT40)
      && (minSideSq >= SQ255(XBRZ_DOT40)
          || dot(cut4(res) * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_DOT40)))), vec4(1.0)) > 0.5)
      && dot(cut4(res), vec4(1.0)) > 0.0)
    res = dots40(res, minSideSq, pairSq);
  bool loneE = minSideSq >= SQ255(XBRZ_SAME_M);
  if (dot(cut4(res), vec4(1.0)) > 0.0
      && (loneE || dot(cut4(res) * FLAG(res, 4.0) * abs(FLAG(res, 16.0) - FLAG(res, 64.0))
          * vec4(equal(FLAG(res, 32.0) + FLAG(res, 128.0), vec4(0.0)))
          * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))))
          * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_SAME_M)))), vec4(1.0)) > 0.0))
    res = diagStroke41(res, loneE, pairSq);
  // 44
  if (maxSideSq >= SQ255(XBRZ_END44) && minSideSq < SQ255(XBRZ_SAME_M)) res = strokeEnd44(res);
  // 47, 45, 48 (all require at least one cut corner in res)
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    // 47. a notch in the straight side of a stroke in shades
    if (maxSideSq >= SQ255(XBRZ_FAR47) && minSideSq < SQ255(XBRZ_NOTCH47))
    {
      vec4 cutM = cut4(res), secM = FLAG(res, 8.0), sqM = vec4(0.0);
      for (int k = 0; k < 4; k++)
      {
        vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
        vec4 m = vtxCorner(c);
        if (dot(cutM, m) < 0.5) continue;
        bool s1 = dot(secM, m) > 0.5;
        bool paintV = (k == 0 || k == 2) ? s1 : !s1;
        vec2 a = paintV ? vec2(0.0, c.y) : vec2(c.x, 0.0), b = paintV ? vec2(c.x, 0.0) : vec2(0.0, c.y);
        float dBSq = sideSq(b), dASq = sideSq(a);
        if (dASq < SQ255(XBRZ_SAME_M) || dASq >= SQ255(XBRZ_NOTCH47) || dBSq >= SQ255(XBRZ_NOTCH47)
            || dBSq >= 1.44 * dASq || sideSq(-a) < SQ255(XBRZ_FAR47) || adjPairMinSq(a, pairSq) < SQ255(XBRZ_SAME_M))
          continue;
        vec3 Ac = cardColor(a);
        if (!withinY255(nE, at3(a - b), XBRZ_SAME_M) || withinY255(Ac, at3(c), XBRZ_SAME_M)
            || BLEND(dot(infoAt(b), vtxCorner(c - 2.0 * b))) > 0.5 || !withinY255(nE, at3(2.0 * b), XBRZ_SAME_M)
            || !isLone3x3Card(Ac, a))
          continue;
        sqM += m;
      }
      res *= 1.0 - min(sqM, vec4(1.0));
    }
    // 45. the dark side of a mid-tone stroke's end
    if (maxSideSq >= SQ255(80.0) && minSideSq < SQ255(XBRZ_SAME_M))
    {
      vec4 cw45 = cut4(res) * vec4(notEqual(BLEND(res), vec4(2.0))) * FLAG(res, 4.0)
                * abs(FLAG(res, 16.0) - FLAG(res, 64.0))
                * vec4(equal(FLAG(res, 32.0) + FLAG(res, 128.0), vec4(0.0)))
                * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MINC))));
      if (dot(cw45, vec4(1.0)) > 0.0)
      {
        vec4 cAny = cut4(res);
        vec4 sq = vec4(0.0);
        for (int k = 0; k < 4; k++)
        {
          vec2 u = k == 0 ? vec2(0.0, -1.0) : k == 1 ? vec2(1.0, 0.0) : k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
          if (sideSq(u) >= SQ255(XBRZ_SAME_M)) continue;
          vec2 s = vec2(-u.y, u.x);
          for (int j = 0; j < 2; j++)
          {
            vec2 sd = j == 0 ? s : -s;
            vec2 c = sd - u;
            vec4 m = vtxCorner(c);
            if (dot(cw45, m) < 0.5 || dot(cAny, vtxCorner(-sd - u)) > 0.5) continue;
            float dSSq = sideSq(sd), dFSq = sideSq(-u);
            if (max(dSSq, dFSq) >= SQ255(XBRZ_MATCH_EDGE) || min(dSSq, dFSq) < SQ255(XBRZ_MINC) || sideSq(-sd) < SQ255(80.0)) continue;
            if (distSqY(nE, at3(c)) >= SQ255(XBRZ_MATCH_EDGE)) continue;
            sq += m;
          }
        }
        res *= 1.0 - min(sq, vec4(1.0));
      }
    }
    // 48 & 48b. 2:1 slope colliding along its long edge with a neighbor's 45-degree line:
    //   - sOff paints E ((sw_sec == sh)): close-shade lone pixel (48)
    //   - sOff paints Fc = sOff - tOff ((sw_sec != sh)): unpartnered 2:1 vs distinct 3rd color (48b)
    {
      vec4 shM = FLAG(res, 16.0), stM = FLAG(res, 64.0);
      vec4 cw48 = cut4(res) * FLAG(res, 4.0) * abs(shM - stM)
                * vec4(equal(FLAG(res, 32.0) + FLAG(res, 128.0), vec4(0.0)));
      if (dot(cw48, vec4(1.0)) > 0.5)
      {
        vec4 secM = FLAG(res, 8.0);
        bool can48a = maxSideSq >= SQ255(XBRZ_SAME_M) && minSideSq < SQ255(XBRZ_SHADE48);
        vec4 dropS = vec4(0.0), dropT = vec4(0.0);
        for (int k = 0; k < 4; k++)
        {
          vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
          vec4 m = vtxCorner(c);
          if (dot(cw48, m) < 0.5) continue;
          bool sh = dot(shM, m) > 0.5;
          bool sIsV = (k == 0 || k == 2) ? sh : !sh;
          vec2 sOff = sIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
          vec2 tOff = sIsV ? vec2(c.x, 0.0) : vec2(0.0, c.y);
          vec4 oppM = vtxCorner(-c);
          vec4 rS = cardInfo(sOff);
          float sw = dot(rS, oppM);
          if (BLEND(sw) < 0.5 || dot(isLine45(rS), oppM) < 0.5) continue;
          bool swPaintsE = (FLAG(sw, 8.0) > 0.5) == sh;
          if (swPaintsE)
          {
            if (!can48a || (dot(secM, m) > 0.5) != sh) continue;
            float dASq = sideSq(sOff);
            if (dASq < SQ255(XBRZ_SAME_M) || dASq >= SQ255(XBRZ_SHADE48)) continue;
            vec3 Ac = cardColor(sOff);
            bool hit = false;
            if (loneE && withinY255(Ac, cardColor(-sOff), XBRZ_SAME_M)
                && !withinY255(nE, diagColor(vec2(-1.0, -1.0)), XBRZ_SAME_M) && !withinY255(nE, diagColor(vec2(1.0, -1.0)), XBRZ_SAME_M)
                && !withinY255(nE, diagColor(vec2(-1.0,  1.0)), XBRZ_SAME_M) && !withinY255(nE, diagColor(vec2(1.0,  1.0)), XBRZ_SAME_M))
              hit = true;
            else if (adjPairMinSq(sOff, pairSq) >= SQ255(XBRZ_SAME_M) && withinY255(nE, at3(2.0 * sOff), XBRZ_SAME_M) && isLone3x3Card(Ac, sOff))
              hit = true;
            if (!hit) continue;
          }
          else
          {
            bool ePaintsT = ((dot(secM, m) > 0.5) != sh) || (dot(pairSq, m) < SQ255(XBRZ_SAME_M));
            if (ePaintsT)
            {
              float tw = dot(cardInfo(tOff), oppM);
              if (BLEND(tw) > 0.5 && FLAG(tw, 4.0) > 0.5 && (FLAG(tw, 16.0) > 0.5) == sh && (FLAG(tw, 64.0) > 0.5) != sh) continue;
            }
            float mw = dot(cardInfo(-tOff), m);
            if (BLEND(mw) > 0.5 && FLAG(mw, 4.0) > 0.5 && (FLAG(mw, 16.0) > 0.5) == sh && (FLAG(mw, 64.0) > 0.5) != sh) continue;
            vec3 Fc = diagColor(sOff - tOff);
            if (min(min(distSqY(Fc, cardColor(sOff)), distSqY(Fc, cardColor(tOff))), distSqY(Fc, nE)) < SQ255(XBRZ_JUNC4)) continue;
          }
          if (sh) dropS += m; else dropT += m;
        }
        res -= 16.0 * dropS + 64.0 * dropT;
      }
    }
    // 48c. bright phantom wedge cut into a turning dark 2:1 outline whose long side already cuts Pc's touching corner
    {
      vec4 sumSq = vec4(sDSq + sBSq, sBSq + sFSq, sFSq + sHSq, sHSq + sDSq);
      vec4 cw48c = cut4(res) * (1.0 - FLAG(res, 16.0)) * (1.0 - FLAG(res, 64.0))
                 * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))))
                 * vec4(greaterThan(pairSq, sumSq));
      if (dot(cw48c, vec4(1.0)) > 0.5)
      {
        vec4 secM = FLAG(res, 8.0);
        vec4 sq48c = vec4(0.0);
        for (int k = 0; k < 4; k++)
        {
          vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
          vec4 m = vtxCorner(c);
          if (dot(cw48c, m) < 0.5) continue;
          bool s1 = dot(secM, m) > 0.5;
          bool pIsV = (k == 0 || k == 2) ? s1 : !s1;
          vec2 pOff = pIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
          vec2 qOff = pIsV ? vec2(c.x, 0.0) : vec2(0.0, c.y);
          vec3 Pc = cardColor(pOff), Qc = cardColor(qOff);
          if (Qc.x > 0.25 || Qc.x >= nE.x - 0.05 || Pc.x <= nE.x + 0.05) continue;
          vec4 oppM = vtxCorner(-c);
          if (BLEND(dot(diagInfo(c), oppM)) > 0.5) continue;
          vec4 rP = cardInfo(pOff);
          float pw = dot(rP, m);
          if (BLEND(pw) < 0.5 || FLAG(pw, 4.0) < 0.5 || BLEND(dot(rP, oppM)) > 0.5) continue;
          bool p21 = s1 ? (FLAG(pw, 64.0) > 0.5 && FLAG(pw, 16.0) < 0.5) : (FLAG(pw, 16.0) > 0.5 && FLAG(pw, 64.0) < 0.5);
          if (!p21) continue;
          if (BLEND(dot(cardInfo(qOff), oppM)) < 0.5) continue;
          if (distSqY(Qc, diagColor(c)) >= SQ255(XBRZ_SAME_M)) continue;
          sq48c += m;
        }
        res *= 1.0 - min(sq48c, vec4(1.0));
      }
    }
  }
  // 49. a 1-pixel diagonal bar ends even
  {
    vec3 E = nE;
    if (minSideSq >= SQ255(XBRZ_BAR49))
    {
      vec3 dA, dC, dI, dG;
      vec2 c = barEnd0(E, dA, dC, dI, dG);
      if (c != vec2(0.0))
      {
        vec2 s1 = vec2(c.x, -c.y), s2 = vec2(-c.x, c.y), e = -c;
        vec4 m1 = vtxCorner(s1), m2 = vtxCorner(s2), me = vtxCorner(e);
        vec3 R1 = e.x > 0.0 ? nF : nD, R2 = e.y > 0.0 ? nH : nB;
        vec3 C1 = c.x > 0.0 ? nF : nD, C2 = c.y > 0.0 ? nH : nB;
        vec3 cS1 = s1.y < 0.0 ? (s1.x < 0.0 ? dA : dC) : (s1.x < 0.0 ? dG : dI);
        vec3 cS2 = s2.y < 0.0 ? (s2.x < 0.0 ? dA : dC) : (s2.x < 0.0 ? dG : dI);
        vec3 cE  = e.y  < 0.0 ? (e.x  < 0.0 ? dA : dC) : (e.x  < 0.0 ? dG : dI);
        bool plug = dot(pairSq, me) < SQ255(XBRZ_SAME_M) && !withinY255(R1, C1, XBRZ_SAME_M) &&
                    !withinY255(R1, C2, XBRZ_SAME_M);
        bool ok1 = dot(pairSq, m1) < SQ255(100.0) || withinY255(C1, cS1, 100.0);
        bool ok2 = dot(pairSq, m2) < SQ255(100.0) || withinY255(C2, cS2, 100.0);
        if (!plug && ok1 && BLEND(dot(res, m1)) < 0.5 && !goesOn(s1)) res = mix(res, vec4(s1.x * s1.y > 0.0 ? 5.0 : 13.0), m1);
        if (!plug && ok2 && BLEND(dot(res, m2)) < 0.5 && !goesOn(s2)) res = mix(res, vec4(s2.x * s2.y > 0.0 ? 13.0 : 5.0), m2);
        float lE = E.x, lA = cE.x, lS = 0.5 * (C1.x + C2.x);
        bool wrap49 = distSqY(C1, C2) >= SQ255(100.0) && dot(pairSq, me) >= SQ255(XBRZ_BAR49)
                   && (withinY255(R1, C2, XBRZ_SAME_M) || withinY255(R2, C1, XBRZ_SAME_M));
        if (!wrap49 && (BLEND(dot(res, me)) < 0.5 || FLAG(dot(res, me), 4.0) < 0.5) && (lA - lS) * (lE - lS) <= 0.0 && !goesOn(e))
        {
          float hSq = e.x > 0.0 ? sFSq : sDSq, vSq = e.y > 0.0 ? sHSq : sBSq;
          bool hz = e.x * e.y > 0.0;
          float dPri = hz ? hSq : vSq, dSec = hz ? vSq : hSq;
          vec3 cPri = hz ? R1 : R2, cSec = hz ? R2 : R1;
          res = mix(res, vec4(pickSecSq(dPri, dSec, cPri, cSec) ? 13.0 : 5.0), me);
        }
      }
    }
    vec4 c49 = cut4(res);
    if (maxSideSq >= SQ255(XBRZ_BAR49) && dot(c49, vec4(1.0)) > 0.0)
    {
      vec4 p15 = vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))));
      vec4 p60 = vec4(lessThan(pairSq, vec4(SQ255(XBRZ_BAR49))));
      vec4 sec49 = FLAG(res, 8.0);
      vec4 q49 = vec4(
        c49.x * (1.0 - sec49.x) * p15.y * (1.0 - p60.x) + c49.y * sec49.y * p15.x * (1.0 - p60.y),
        c49.y * (1.0 - sec49.y) * p15.z * (1.0 - p60.y) + c49.z * sec49.z * p15.y * (1.0 - p60.z),
        c49.z * (1.0 - sec49.z) * p15.w * (1.0 - p60.z) + c49.w * sec49.w * p15.z * (1.0 - p60.w),
        c49.w * (1.0 - sec49.w) * p15.x * (1.0 - p60.w) + c49.x * sec49.x * p15.w * (1.0 - p60.x))
        * vec4(greaterThanEqual(vec4(sBSq, sFSq, sHSq, sDSq), vec4(SQ255(XBRZ_BAR49))));
      if (dot(q49, vec4(1.0)) > 0.5)
      {
        for (int q = 0; q < 4; q++)
        {
          float qOn = q == 0 ? q49.x : (q == 1 ? q49.y : (q == 2 ? q49.z : q49.w));
          if (qOn < 0.5) continue;
          vec2 n  = q == 0 ? vec2(0.0, -1.0) : q == 1 ? vec2(1.0, 0.0) : q == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
          vec3 En = q == 0 ? nB : (q == 1 ? nF : (q == 2 ? nH : nD));
          vec2 cn = q == 0 ? (p15.y > 0.5 ? vec2( 1.0,  1.0) : vec2(-1.0,  1.0))
                  : q == 1 ? (p15.z > 0.5 ? vec2(-1.0,  1.0) : vec2(-1.0, -1.0))
                  : q == 2 ? (p15.w > 0.5 ? vec2(-1.0, -1.0) : vec2( 1.0, -1.0))
                           : (p15.x > 0.5 ? vec2( 1.0, -1.0) : vec2( 1.0,  1.0));
          vec2 sideDir = cn + n;
          vec2 k = n - sideDir;
          vec4 mk = vtxCorner(k);
          float wk = dot(res, mk);
          if (BLEND(wk) < 0.5) continue;
          bool hz = k.x * k.y > 0.0, sec = FLAG(wk, 8.0) > 0.5;
          vec2 pk = (hz == sec) ? vec2(0.0, k.y) : vec2(k.x, 0.0);
          vec3 pCol = cardColor(pk);
          if (withinY255(pCol, En, XBRZ_SAME_M)) continue;
          vec3 other = diagColor(n + sideDir);
          if (!withinY255(pCol, other, XBRZ_SAME_M) || withinY255(En, other, XBRZ_BAR49)) continue;
          if ((En.x - nE.x) * (En.x - other.x) <= 0.0) continue;
          vec3 cK = diagColor(k);
          if (withinY255(En, cK, XBRZ_BAR49)) continue;
          if (!(withinY255(nE, cK, 100.0) || sideSq(-sideDir) < SQ255(100.0))) continue;
          if (withinY255(En, at3(2.0 * n), XBRZ_BAR49)) continue;
          if (withinY255(En, at3(2.0 * n + sideDir), XBRZ_BAR49) || withinY255(En, at3(2.0 * n - sideDir), XBRZ_BAR49)) continue;
          if (BLEND(dot(infoAt(n + vec2(cn.x, 0.0)), vtxCorner(vec2(-cn.x, cn.y)))) < 0.5 ||
              BLEND(dot(infoAt(n + vec2(0.0, cn.y)), vtxCorner(vec2(cn.x, -cn.y)))) < 0.5) continue;
          if (withinY255(En, at3(n + vec2(2.0 * cn.x, 0.0)), XBRZ_BAR49)
              || withinY255(En, at3(n + vec2(0.0, 2.0 * cn.y)), XBRZ_BAR49)
              || withinY255(En, at3(n + vec2(2.0 * cn.x, cn.y)), XBRZ_BAR49)
              || withinY255(En, at3(n + vec2(cn.x, 2.0 * cn.y)), XBRZ_BAR49))
            continue;
          float d2Sq = distSqY(En, at3(n + 2.0 * cn));
          if (d2Sq < SQ255(XBRZ_BAR49) && d2Sq >= SQ255(XBRZ_SAME_M)) continue;
          res = mix(res, vec4(0.0), mk);
        }
      }
    }
  }
  if (loneE && dot(cut4(res), vec4(1.0)) > 0.0) res = apex41(res, pairSq);
  // 38b. 3+ color corner on a 1px bar flush against a 4-color orthogonal crosshair
  if (!loneE && min(max(sDSq, sFSq), max(sBSq, sHSq)) > SQ255(40.0))
  {
    vec4 sec38 = FLAG(res, 8.0);
    vec4 hz38 = vec4(1.0 - sec38.x, sec38.y, 1.0 - sec38.z, sec38.w);
    vec4 m38b = cut4(res) * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))))
              * vec4(lessThan(mix(vec4(sHSq, sHSq, sBSq, sBSq), vec4(sFSq, sDSq, sDSq, sFSq), hz38), vec4(SQ255(XBRZ_SAME_M))))
              * vec4(greaterThan(mix(vec4(sBSq, sBSq, sHSq, sHSq), vec4(sDSq, sFSq, sFSq, sDSq), hz38), vec4(SQ255(40.0))))
              * vec4(greaterThan(mix(vec4(sFSq, sDSq, sDSq, sFSq), vec4(sHSq, sHSq, sBSq, sBSq), hz38), vec4(SQ255(40.0))))
              * vec4(greaterThan(mix(pairSq.yxwz, pairSq.wzyx, hz38), vec4(SQ255(40.0))));
    if (dot(m38b, vec4(1.0)) > 0.5)
    {
      for (int i = 0; i < 4; i++)
      {
        vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
        vec4 m = vtxCorner(c);
        if (dot(m38b, m) < 0.5) continue;
        vec2 h = dot(hz38, m) > 0.5 ? vec2(c.x, 0.0) : vec2(0.0, c.y), v = c - h;
        vec3 Hc = cardColor(h), Bc = cardColor(-v);
        vec3 Cc = at3(h - v);
        if (distSqY(Bc, Cc) <= SQ255(40.0) || distSqY(Hc, Cc) <= SQ255(XBRZ_JUNC4) || distSqY(nE, Cc) <= SQ255(40.0)) continue;
        if (!withinY255(Hc, at3(2.0 * h), XBRZ_SAME_M)) continue;
        if (!withinY255(Bc, at3(-v - h), XBRZ_SAME_M) || !withinY255(Bc, at3(-2.0 * v), XBRZ_SAME_M)) continue;
        if (!withinY255(Cc, at3(2.0 * h - v), XBRZ_SAME_M) || !withinY255(Cc, at3(h - 2.0 * v), XBRZ_SAME_M)) continue;
        res = mix(res, vec4(0.0), m);
      }
    }
  }
  // 42b. Convex corner bevel painting a shared darker background beside an adjacent brighter wall
  if (!loneE && maxSideSq >= SQ255(XBRZ_MINC))
  {
    vec4 uSq42b = vec4(nD.x < nB.x ? sFSq : sHSq, nF.x < nB.x ? sDSq : sHSq,
                       nF.x < nH.x ? sDSq : sBSq, nD.x < nH.x ? sFSq : sBSq);
    vec4 cMinL = min(vec4(nD.x, nF.x, nF.x, nD.x), vec4(nB.x, nB.x, nH.x, nH.x));
    vec4 cMaxL = max(vec4(nD.x, nF.x, nF.x, nD.x), vec4(nB.x, nB.x, nH.x, nH.x));
    vec4 m42b = (1.0 - cut4(res))
              * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_MINC))))
              * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MINC))))
              * vec4(lessThan(uSq42b, vec4(SQ255(XBRZ_SAME_M))))
              * vec4(lessThan(cMinL, vec4(nE.x - 0.05)))
              * vec4(lessThan(vec4(nE.x), cMaxL - 0.05));
    if (dot(m42b, vec4(1.0)) > 0.5)
    {
      for (int i = 0; i < 4; i++)
      {
        vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
        vec4 m = vtxCorner(c);
        if (dot(m42b, m) < 0.5) continue;
        vec3 Nh = c.x > 0.0 ? nF : nD, Nv = c.y > 0.0 ? nH : nB;
        bool alongX = Nh.x < Nv.x;
        vec2 u = alongX ? vec2(c.x, 0.0) : vec2(0.0, c.y), s = c - u;
        vec3 U = alongX ? Nh : Nv, S = alongX ? Nv : Nh;
        if (!withinY255(nE, at3(u - s), XBRZ_SAME_M) || !withinY255(S, at3(c), XBRZ_SAME_M) || !withinY255(U, at3(s - u), XBRZ_SAME_M)) continue;
        vec4 rU = infoAt(u);
        if (dot(cut4(rU) * isLine45(rU), vtxCorner(-c)) < 0.5) continue;
        if (BLEND(dot(rU, vtxCorner(s - u))) > 0.5 || BLEND(dot(infoAt(s), vtxCorner(u - s))) > 0.5) continue;
        res = mix(res, vec4(vtxSec(c, u) ? 13.0 : 5.0), m);
      }
    }
  }
  FRAG_OUT = res / 255.0;
}

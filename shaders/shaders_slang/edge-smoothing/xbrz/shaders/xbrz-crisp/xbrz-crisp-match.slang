#version 450
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
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define P(x,y) texture(xbrz_crisp_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define OUT_SIZE params.OutputSize
#define INFO(uv) texture(Source, uv)
#define INFO_STEP ORIG_SIZE.zw
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)

// pass 0's decisions, before the resolve pass changed them
layout(set = 0, binding = 4) uniform sampler2D xbrz_crisp_pass0;
#define W0_RAW texture(xbrz_crisp_pass0, coord)
#define W0_AT(x, y) floor(texture(xbrz_crisp_pass0, coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)

// the center of the pixel in the original, set in main (the functions read P)
vec2 coord = vec2(0.0);

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

vec4 vtxCorner(vec2 c) { return vec4(c.x < 0.0 && c.y < 0.0, c.x > 0.0 && c.y < 0.0, c.x > 0.0 && c.y > 0.0, c.x < 0.0 && c.y > 0.0); }
bool vtxSec(vec2 c, vec2 n) { return (c.x * c.y > 0.0) != (abs(n.x) > 0.5); }
bool vtxSame(vec3 a, vec3 b) { return withinEqY255(a, b, XBRZ_VERTEX_TOL); }

bool vtxAt(vec2 u, vec2 v)
{
  if (sideSq(-u) <= SQ255(XBRZ_VERTEX_EDGE)) return false;
  vec3 C = cardColor(-u), T = cardColor(-v);
  if (withinEqY255(C, T, XBRZ_VERTEX_EDGE) || vtxSame(C, cardColor(u))) return false;
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

void vtx(vec2 u, vec2 v, inout vec4 res)
{
  vec2 c = -u - v;
  vec4 m = vtxCorner(c);
  float w = dot(res, m);
  if (BLEND(w) < 0.5 || FLAG(w, 4.0) < 0.5 || (FLAG(w, 8.0) > 0.5) != vtxSec(c, -v) || !vtxAt(u, v)) return;
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
float keptWhole(vec2 n)
{
  vec4 r = infoAt(n);
  vec4 w0 = W0_AT(n.x, n.y);
  return float(dot(cut4(r), vec4(1.0)) < 0.5 && dot(cut4(w0) * vec4(lessThan(BLEND(w0), vec4(3.0))) * FLAG(w0, 4.0), vec4(1.0)) > 0.5);
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
    float w = dot(res, m);
    bool horiz = (c.x * c.y > 0.0) != (FLAG(w, 8.0) > 0.5);
    vec2 p = horiz ? vec2(c.x, 0.0) : vec2(0.0, c.y), q = horiz ? vec2(0.0, c.y) : vec2(c.x, 0.0);
    vec3 Pc = cardColor(p), Qc = cardColor(q);
    float dPQSq = dot(pairSq, m);
    vec3 X = at3(c);
    float lo5Sq = min(min(min(sideSq(p), sideSq(q)), min(distSqY(E, X), distSqY(Pc, X))), distSqY(Qc, X));
    if (lo5Sq <= SQ255(XBRZ_JUNC4) || dPQSq < (XBRZ_STEP38 * XBRZ_STEP38) * lo5Sq) continue;
    if (BLEND(dot(infoAt(c), vtxCorner(-c))) < 0.5) continue;
    if (keptWhole(p) < 0.5 && keptWhole(q) < 0.5) continue;
    vec3 Ch = c.x > 0.0 ? nF : nD, Cv = c.y > 0.0 ? nH : nB;
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
vec4 tieRamp(vec4 res)
{
  vec3 E = nE;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float wc = dot(res, m);
    if (BLEND(wc) < 0.5) continue;
    float aSq = c.x > 0.0 ? sFSq : sDSq, bSq = c.y > 0.0 ? sHSq : sBSq;
    float loSq = min(aSq, bSq), hiSq = max(aSq, bSq);
    if (loSq <= SQ255(20.0) || loSq <= (1.0 - XBRZ_MID39) * (1.0 - XBRZ_MID39) * hiSq) continue;
    vec3 Nh = c.x > 0.0 ? nF : nD, Nv = c.y > 0.0 ? nH : nB;
    if (distSqY(Nh, Nv) <= 3.24 * hiSq) continue;
    vec3 X = at3(c);
    float xdSq = min(distSqY(X, Nh), min(distSqY(X, Nv), distSqY(X, E)));
    if (xdSq <= SQ255(20.0)) continue;
    bool tie = xdSq > SQ255(XBRZ_FAR39) && FLAG(wc, 16.0) + FLAG(wc, 64.0) < 0.5;
    if (!tie && loSq > 0.99 * hiSq)
      tie = abs(sqrt(aSq) - sqrt(bSq)) * 255.0 < 0.01;
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
vec4 edgeStep42(vec4 res)
{
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    if (BLEND(dot(res, m)) > 0.5) continue;
    float hSq = c.x > 0.0 ? sFSq : sDSq, vSq = c.y > 0.0 ? sHSq : sBSq;
    if (min(hSq, vSq) < SQ255(XBRZ_MINC)) continue;
    vec3 Kh = c.x > 0.0 ? nF : nD, Kv = c.y > 0.0 ? nH : nB;
    if (!withinY255(Kh, Kv, XBRZ_SAME_M)) continue;
    vec3 K = 0.5 * (Kh + Kv);
    if (withinY255(K, c.x > 0.0 ? nD : nF, XBRZ_SAME_M) || withinY255(K, c.y > 0.0 ? nB : nH, XBRZ_SAME_M)) continue;
    if (!withinY255(K, at3(c), XBRZ_SAME_M)) continue;
    float ok = 1.0;
    for (int j = 0; j < 2; j++)
    {
      vec2 q = j == 0 ? vec2(c.x, -c.y) : vec2(-c.x, c.y);
      float wq = dot(infoAt(q), m);
      if (BLEND(wq) < 0.5 || FLAG(wq, 4.0) < 0.5 || FLAG(wq, 16.0) + FLAG(wq, 64.0) + FLAG(wq, 32.0) + FLAG(wq, 128.0) > 0.5
          || !withinY255(at3(q + paintOf(c, wq)), K, XBRZ_SAME_M))
      { ok = 0.0; break; }
    }
    if (ok > 0.5)
    {
      bool hz = c.x * c.y > 0.0;
      float dPri = hz ? hSq : vSq, dSec = hz ? vSq : hSq;
      res = mix(res, vec4(dPri <= dSec + TIE_EPS ? 5.0 : 13.0), m);
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
    if (!loneE && dot(pairSq, m) >= SQ255(XBRZ_SAME_M)) continue;
    for (int j = 0; j < 2; j++)
    {
      vec2 n = j == 0 ? vec2(c.x, 0.0) : vec2(0.0, c.y);
      float wn = dot(infoAt(n), vtxCorner(-c));
      if (BLEND(wn) < 0.5 || lineType41(wn) != -t) continue;
      vec2 o = c - n;
      if (!loneE && lone41(n) && lone41(o))
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
  if (withinY255(S, U, XBRZ_MINC)
      || !withinY255(at3(c), U, XBRZ_SAME_M) || !withinY255(at3(v - s), U, XBRZ_SAME_M)
      || !withinY255(toYCbCr(P(-2.0 * s.x, -2.0 * s.y)), S, XBRZ_SAME_M)
      || !withinY255(toYCbCr(P(v.x - 2.0 * s.x, v.y - 2.0 * s.y)), U, XBRZ_SAME_M))
    return 0.0;
  return float(BLEND(dot(infoAt(-s), vtxCorner(c - 2.0 * s))) > 0.5);
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
  vec3 q = at3(o);
  return float(distSqY(E, q) >= SQ255(XBRZ_END44) && q.x >= lE);
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
  if (cardColor(-v).x < lE || cardColor(u).x < lE || cardColor(-u).x < lE)
    return res;
  if (far44(E, lE, v + u) < 0.5 || far44(E, lE, v - u) < 0.5 || far44(E, lE, u - v) < 0.5 || far44(E, lE, -u - v) < 0.5)
    return res;
  for (int k = 0; k < 2; k++)
  {
    vec2 c = k == 0 ? u - v : -u - v;
    vec4 m = vtxCorner(c);
    if (BLEND(dot(res, m)) > 0.5) continue;
    vec2 k1 = c - v, k2 = 2.0 * c + v;
    vec4 wG = infoAt(c);
    if ((withinY255(E, at3(k1), XBRZ_SAME_M) && BLEND(dot(wG, vtxCorner(-c - 2.0 * v))) > 0.5)
        || (withinY255(E, at3(k2), XBRZ_SAME_M) && BLEND(dot(wG, vtxCorner(c + 2.0 * v))) > 0.5)) continue;
    float hSq = c.x > 0.0 ? sFSq : sDSq, vSq = c.y > 0.0 ? sHSq : sBSq;
    bool hz = c.x * c.y > 0.0;
    float dPri = hz ? hSq : vSq, dSec = hz ? vSq : hSq;
    res = mix(res, vec4(dPri <= dSec + TIE_EPS ? 1.0 : 9.0), m);
  }
  return res;
}

// ---- Rule 49: a 1-pixel diagonal bar ----
#define XBRZ_BAR49 60.0
vec2 barEndBody(vec2 o, vec3 E, vec3 cT, vec3 cL, vec3 cR, vec3 cB)
{
  float n = 0.0;
  vec2 c = vec2(0.0);
  vec3 Ccol = E;
  for (int k = 0; k < 4; k++)
  {
    vec2 d = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec3 q = at3(o + d);
    if (withinY255(E, q, XBRZ_BAR49))
    {
      n += 1.0;
      if (n > 1.5) return vec2(0.0);
      c = d;
      Ccol = q;
    }
  }
  if (n < 0.5 || !withinY255(E, Ccol, XBRZ_SAME_M)) return vec2(0.0);
  float lE = E.x, l1 = (c.x > 0.0 ? cR.x : cL.x), l2 = (c.y > 0.0 ? cB.x : cT.x);
  if ((lE - l1) * (lE - l2) <= 0.0) return vec2(0.0);
  if (BLEND(dot(infoAt(o + vec2(c.x, 0.0)), vtxCorner(vec2(-c.x, c.y)))) < 0.5 ||
      BLEND(dot(infoAt(o + vec2(0.0, c.y)), vtxCorner(vec2(c.x, -c.y)))) < 0.5) return vec2(0.0);
  if (withinY255(E, at3(o + vec2(2.0 * c.x, 0.0)), XBRZ_BAR49)
      || withinY255(E, at3(o + vec2(0.0, 2.0 * c.y)), XBRZ_BAR49)
      || withinY255(E, at3(o + vec2(2.0 * c.x, c.y)), XBRZ_BAR49)
      || withinY255(E, at3(o + vec2(c.x, 2.0 * c.y)), XBRZ_BAR49))
    return vec2(0.0);
  float d2Sq = distSqY(E, at3(o + 2.0 * c));
  if (d2Sq < SQ255(XBRZ_BAR49) && d2Sq >= SQ255(XBRZ_SAME_M)) return vec2(0.0);
  return c;
}
vec2 barEndN(vec2 o, vec3 E)
{
  vec3 cT = o.y > 0.5 ? nE : at3(o + vec2(0.0, -1.0));
  if (o.y <= 0.5 && withinY255(E, cT, XBRZ_BAR49)) return vec2(0.0);
  vec3 cL = o.x > 0.5 ? nE : at3(o + vec2(-1.0, 0.0));
  if (o.x <= 0.5 && withinY255(E, cL, XBRZ_BAR49)) return vec2(0.0);
  vec3 cR = o.x < -0.5 ? nE : at3(o + vec2(1.0, 0.0));
  if (o.x >= -0.5 && withinY255(E, cR, XBRZ_BAR49)) return vec2(0.0);
  vec3 cB = o.y < -0.5 ? nE : at3(o + vec2(0.0, 1.0));
  if (o.y >= -0.5 && withinY255(E, cB, XBRZ_BAR49)) return vec2(0.0);
  return barEndBody(o, E, cT, cL, cR, cB);
}

bool cutsIn(vec2 q, vec2 k, vec3 C)
{
  float w = dot(infoAt(q), vtxCorner(k));
  if (BLEND(w) < 0.5) return false;
  bool hz = k.x * k.y > 0.0, sec = FLAG(w, 8.0) > 0.5;
  vec2 p = (hz == sec) ? vec2(0.0, k.y) : vec2(k.x, 0.0);
  return withinY255(at3(q + p), C, XBRZ_SAME_M);
}

bool goesOn(vec2 k, vec3 E)
{
  return cutsIn(vec2(k.x, 0.0), vec2(-k.x, k.y), E) || cutsIn(vec2(0.0, k.y), vec2(k.x, -k.y), E) ||
         cutsIn(k, -k, E);
}

// ---- Rules 47 and 48: lone shades along a stroke ----
#define XBRZ_NOTCH47 60.0
#define XBRZ_FAR47 80.0
#define XBRZ_SHADE48 60.0
bool isLone3x3(vec3 Q, vec2 q)
{
  for (int i = -1; i <= 1; i++)
    for (int j = -1; j <= 1; j++)
      if ((i != 0 || j != 0) && withinY255(Q, at3(q + vec2(float(i), float(j))), XBRZ_SAME_M))
        return false;
  return true;
}

void main()
{
  vec2 pos = fract(vTexCoord * ORIG_SIZE.xy) - vec2(0.5, 0.5);
  coord = vTexCoord - pos * ORIG_SIZE.zw;
  vec4 rawRes = INFO(coord);
  if (XBRZ_MINC <= 0.0)
  {
    FRAG_OUT = rawRes;
    return;
  }
  vec4 rawW0 = W0_RAW;
  vec3 pD = P(-1.0, 0.0), pE = P(0.0, 0.0), pF = P(1.0, 0.0);
  bool rawZero = dot(rawRes + rawW0, vec4(1.0)) < 0.5 / 255.0;
  if (rawZero && pD == pE && pF == pE)
  {
    FRAG_OUT = vec4(0.0);
    return;
  }
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
  vec3 pB = P(0.0, -1.0), pH = P(0.0, 1.0);
  if (noCuts && pB == pE && pH == pE)
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

  vec4 lost = aW0 * (1.0 - cut4(res));
  if (dot(lost, vec4(1.0)) > 0.0)
  {
    vec4 lostStrong = lost * vec4(greaterThan(max(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq)), vec4(SQ255(XBRZ_MATCH_EDGE))));
    vec4 fix = vec4(0.0);
    if (dot(lostStrong, vec4(1.0)) > 0.0)
    {
      vec4 rA = INFO_AT(-1.0, -1.0), rC = INFO_AT(1.0, -1.0), rI = INFO_AT(1.0, 1.0), rG = INFO_AT(-1.0, 1.0);
      vec4 gap = vec4(cut4(rC).x * cut4(rG).x, cut4(rI).y * cut4(rA).y, cut4(rC).z * cut4(rG).z, cut4(rI).w * cut4(rA).w);
      vec4 wrapE = vec4(lessThan(pairSq, vec4(SQ255(XBRZ_MATCH_WRAP))));
      vec4 needGap = lostStrong * gap * wrapE;
      vec4 wrapN = vec4(0.0);
      if (needGap.x > 0.5) wrapN.x = float(max(distSqY(toYCbCr(P( 1.0, -2.0)), nB), distSqY(nD, toYCbCr(P(-2.0,  1.0)))) < SQ255(XBRZ_MATCH_LINE));
      if (needGap.y > 0.5) wrapN.y = float(max(distSqY(toYCbCr(P(-1.0, -2.0)), nB), distSqY(nF, toYCbCr(P( 2.0,  1.0)))) < SQ255(XBRZ_MATCH_LINE));
      if (needGap.z > 0.5) wrapN.z = float(max(distSqY(toYCbCr(P( 2.0, -1.0)), nF), distSqY(nH, toYCbCr(P(-1.0,  2.0)))) < SQ255(XBRZ_MATCH_LINE));
      if (needGap.w > 0.5) wrapN.w = float(max(distSqY(nD, toYCbCr(P(-2.0, -1.0))), distSqY(toYCbCr(P( 1.0,  2.0)), nH)) < SQ255(XBRZ_MATCH_LINE));

      vec4 part = vec4(cut4(rA).z, cut4(rC).w, cut4(rI).x, cut4(rG).y);
      vec4 l45 = vec4(isLine45(rA).z, isLine45(rC).w, isLine45(rI).x, isLine45(rG).y);
      fix = max(needGap * wrapN, lostStrong * part * l45 * (1.0 - FLAG(w0, 4.0)));
    }
    vec4 far43 = vec4(greaterThanEqual(min(vec4(sDSq, sFSq, sFSq, sDSq), vec4(sBSq, sBSq, sHSq, sHSq)), vec4(SQ255(XBRZ_MINC))));
    far43 *= vec4(lessThan(min(vec4(sFSq, sDSq, sDSq, sFSq), vec4(sHSq, sHSq, sBSq, sBSq)), vec4(SQ255(XBRZ_SAME_M))));
    if (dot(lost, far43) > 0.0) fix = max(fix, domes43(lost * far43));
    if (dot(fix, vec4(1.0)) > 0.0)
    {
      vec4 noR9 = 1.0 - FLAG(w0, 32.0);
      vec4 back = 1.0 + 4.0 * FLAG(w0, 4.0) + 8.0 * FLAG(w0, 8.0) + noR9 * (16.0 * FLAG(w0, 16.0) + 64.0 * FLAG(w0, 64.0));
      res = mix(res, back, fix);
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
      vtx(u, v, res);
    }
  }
  // 42
  vec4 m42 = (1.0 - cut4(res))
           * vec4(greaterThanEqual(min(vec4(sDSq, sFSq, sFSq, sDSq), vec4(sBSq, sBSq, sHSq, sHSq)), vec4(SQ255(XBRZ_MINC))))
           * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))));
  if (dot(m42, vec4(1.0)) > 0.5) res = edgeStep42(res);
  // rules 38 to 41
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = junc4(res, pairSq);
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    vec4 lo39 = min(vec4(sDSq, sFSq, sFSq, sDSq), vec4(sBSq, sBSq, sHSq, sHSq));
    vec4 hi39 = max(vec4(sDSq, sFSq, sFSq, sDSq), vec4(sBSq, sBSq, sHSq, sHSq));
    vec4 m39 = cut4(res) * vec4(greaterThan(lo39, vec4(SQ255(20.0))))
             * vec4(greaterThan(lo39, (1.0 - XBRZ_MID39) * (1.0 - XBRZ_MID39) * hi39))
             * vec4(greaterThan(pairSq, 3.24 * hi39));
    if (dot(m39, vec4(1.0)) > 0.5) res = tieRamp(res);
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
          * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M)))), vec4(1.0)) > 0.0))
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
        if (dASq >= SQ255(XBRZ_NOTCH47) || dBSq >= SQ255(XBRZ_NOTCH47) || dBSq >= 1.44 * dASq || sideSq(-a) < SQ255(XBRZ_FAR47))
          continue;
        vec3 Ac = cardColor(a);
        if (!withinY255(nE, at3(a - b), XBRZ_SAME_M) || withinY255(Ac, at3(c), XBRZ_SAME_M)
            || BLEND(dot(infoAt(b), vtxCorner(c - 2.0 * b))) > 0.5 || !withinY255(nE, at3(2.0 * b), XBRZ_SAME_M)
            || !isLone3x3(Ac, a))
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
    // 48. one slope beside a lone shade
    if (maxSideSq >= SQ255(XBRZ_SAME_M) && minSideSq < SQ255(XBRZ_SHADE48))
    {
      vec4 shM = FLAG(res, 16.0), stM = FLAG(res, 64.0);
      vec4 cw48 = cut4(res) * FLAG(res, 4.0) * abs(shM - stM)
                * vec4(equal(FLAG(res, 32.0) + FLAG(res, 128.0), vec4(0.0)));
      if (dot(cw48, vec4(1.0)) > 0.5)
      {
        vec4 secM = FLAG(res, 8.0);
        vec4 dropS = vec4(0.0), dropT = vec4(0.0);
        for (int k = 0; k < 4; k++)
        {
          vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
          vec4 m = vtxCorner(c);
          if (dot(cw48, m) < 0.5) continue;
          float sh = dot(shM, m);
          bool xz = k == 0 || k == 2;
          bool paintV = xz ? dot(secM, m) > 0.5 : dot(secM, m) < 0.5;
          bool hLong = xz ? sh > 0.5 : (1.0 - sh) > 0.5;
          if (hLong != paintV) continue;
          vec2 a = paintV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
          float dASq = sideSq(a);
          if (dASq < SQ255(XBRZ_SAME_M) || dASq >= SQ255(XBRZ_SHADE48)) continue;
          vec4 rA = infoAt(a), mA = vtxCorner(-c);
          if (BLEND(dot(rA, mA)) < 0.5 || dot(isLine45(rA), mA) < 0.5) continue;
          bool pVA = xz ? dot(FLAG(rA, 8.0), mA) > 0.5 : dot(FLAG(rA, 8.0), mA) < 0.5;
          if (pVA != paintV) continue;
          vec3 Ac = cardColor(a);
          bool hit = false;
          if (loneE && withinY255(Ac, cardColor(-a), XBRZ_SAME_M)
              && !withinY255(nE, at3(vec2(-1.0, -1.0)), XBRZ_SAME_M) && !withinY255(nE, at3(vec2(1.0, -1.0)), XBRZ_SAME_M)
              && !withinY255(nE, at3(vec2(-1.0,  1.0)), XBRZ_SAME_M) && !withinY255(nE, at3(vec2(1.0,  1.0)), XBRZ_SAME_M))
            hit = true;
          else if (withinY255(nE, at3(2.0 * a), XBRZ_SAME_M) && isLone3x3(Ac, a))
            hit = true;
          if (!hit) continue;
          if (sh > 0.5) dropS += m; else dropT += m;
        }
        res -= 16.0 * dropS + 64.0 * dropT;
      }
    }
  }
  // 49. a 1-pixel diagonal bar ends even
  {
    vec3 E = nE;
    if (minSideSq >= SQ255(XBRZ_BAR49))
    {
      vec2 c = barEndBody(vec2(0.0), E, nB, nD, nF, nH);
      if (c != vec2(0.0))
      {
        vec2 s1 = vec2(c.x, -c.y), s2 = vec2(-c.x, c.y), e = -c;
        vec4 m1 = vtxCorner(s1), m2 = vtxCorner(s2), me = vtxCorner(e);
        vec3 R1 = e.x > 0.0 ? nF : nD, R2 = e.y > 0.0 ? nH : nB;
        vec3 C1 = c.x > 0.0 ? nF : nD, C2 = c.y > 0.0 ? nH : nB;
        bool plug = withinY255(R1, R2, XBRZ_SAME_M) && !withinY255(R1, C1, XBRZ_SAME_M) &&
                    !withinY255(R1, C2, XBRZ_SAME_M);
        if (!plug && BLEND(dot(res, m1)) < 0.5 && !goesOn(s1, E)) res = mix(res, vec4(s1.x * s1.y > 0.0 ? 5.0 : 13.0), m1);
        if (!plug && BLEND(dot(res, m2)) < 0.5 && !goesOn(s2, E)) res = mix(res, vec4(s2.x * s2.y > 0.0 ? 13.0 : 5.0), m2);
        float lE = E.x, lA = at3(e).x, lS = 0.5 * (C1.x + C2.x);
        if ((BLEND(dot(res, me)) < 0.5 || FLAG(dot(res, me), 4.0) < 0.5) && (lA - lS) * (lE - lS) <= 0.0 && !goesOn(e, E))
        {
          float hSq = e.x > 0.0 ? sFSq : sDSq, vSq = e.y > 0.0 ? sHSq : sBSq;
          bool hz = e.x * e.y > 0.0;
          float dPri = hz ? hSq : vSq, dSec = hz ? vSq : hSq;
          res = mix(res, vec4(dPri <= dSec + TIE_EPS ? 5.0 : 13.0), me);
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
          vec2 n = q == 0 ? vec2(0.0, -1.0) : q == 1 ? vec2(1.0, 0.0) : q == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
          vec3 En = q == 0 ? nB : (q == 1 ? nF : (q == 2 ? nH : nD));
          vec2 cn = barEndN(n, En);
          if (cn == vec2(0.0)) continue;
          vec2 sE = -n == vec2(cn.x, 0.0) ? vec2(cn.x, -cn.y) : -n == vec2(0.0, cn.y) ? vec2(-cn.x, cn.y) : vec2(0.0);
          if (sE == vec2(0.0)) continue;
          vec2 k = sE + 2.0 * n;
          vec4 mk = vtxCorner(k);
          float wk = dot(res, mk);
          if (BLEND(wk) < 0.5) continue;
          bool hz = k.x * k.y > 0.0, sec = FLAG(wk, 8.0) > 0.5;
          vec2 pk = (hz == sec) ? vec2(0.0, k.y) : vec2(k.x, 0.0);
          vec3 other = -n == vec2(cn.x, 0.0) ? at3(n + vec2(0.0, cn.y)) : at3(n + vec2(cn.x, 0.0));
          vec3 pCol = cardColor(pk);
          if (!withinY255(pCol, En, XBRZ_SAME_M) && withinY255(pCol, other, XBRZ_SAME_M)) { res = mix(res, vec4(0.0), mk); }
        }
      }
    }
  }
  FRAG_OUT = res / 255.0;
}

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
// Matching pass of xbrz-crisp (OpenGL / GLES): once per input pixel, between the resolve pass and pass 1 (rule 26)
//#crisp}

//#crisp{
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
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

uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;
#define vTexCoord TEX0.xy
#define FRAG_OUT FragColor
//#crisp{
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float XBRZ_MINC;
#else
#define XBRZ_MINC 20.0
#endif
//#crisp}

// the point pass (three passes back), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev3Texture;
uniform COMPAT_PRECISION vec2 PassPrev3TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev3InputSize;
#define OUT_SIZE OutputSize
#define ORIG_SIZE vec4(PassPrev3TextureSize, 1.0 / PassPrev3TextureSize)
#define ORIG_INPUT_SIZE PassPrev3InputSize
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
#define P(x,y) COMPAT_TEXTURE(PassPrev3Texture, ocoord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, uv)
#define INFO_STEP SRC_SIZE.zw
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)

// pass 0's decisions (two passes back), before the resolve pass changed them
uniform sampler2D PassPrev2Texture;
uniform COMPAT_PRECISION vec2 PassPrev2TextureSize;
#define P0_SIZE vec4(PassPrev2TextureSize, 1.0 / PassPrev2TextureSize)
#define W0_AT(x, y) floor(COMPAT_TEXTURE(PassPrev2Texture, c0 + vec2(x, y) * P0_SIZE.zw) * 255.0 + 0.5)
vec2 coord = vec2(0.0), ocoord = vec2(0.0), c0 = vec2(0.0);

// the decision word of a corner (see pass 0 and the resolve pass): BLEND is the blend type, FLAG(r, f) one of its flags
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
vec4 cut4(vec4 w) { return vec4(greaterThan(BLEND(w), vec4(0.0))); }
vec4 isLine45(vec4 r) { return FLAG(r, 4.0) * (1.0 - FLAG(r, 16.0)) * (1.0 - FLAG(r, 64.0)) * vec4(equal(FLAG(r, 32.0) + FLAG(r, 128.0), vec4(0.0))); }

// Rec. 2020 luma weights and chroma difference scales, shared across passes
const vec3 LUMA_W = vec3(0.2627, 0.6780, 0.0593);
const float SCALE_B = 0.5 / (1.0 - 0.0593);
const float SCALE_R = 0.5 / (1.0 - 0.2627);

float luma(vec3 c) { return dot(c, LUMA_W); }

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

bool within255(vec3 pixA, vec3 pixB, float lim)
{
  return distSqYCbCr(pixA, pixB) < SQ255(lim);
}

bool withinEq255(vec3 pixA, vec3 pixB, float lim)
{
  return distSqYCbCr(pixA, pixB) <= SQ255(lim);
}
#define XBRZ_SAME_M 15.0 // two pixels within this are one color (sameColor of the resolve pass); rule 41

// ---- Rule 26: matching corners ----
#define XBRZ_MATCH_EDGE 40.0  // E differs from one of the corner's two neighbors by more than this
#define XBRZ_MATCH_WRAP 50.0  // gap: the corner's two neighbors are within this of each other
#define XBRZ_MATCH_LINE 30.0  // gap: so are the same two pixels of both neighbors along the cut

// ---- Rule 27: a bar at a vertex ----
#define XBRZ_VERTEX_TOL 15.0  // the arms' pixels have C within this
#define XBRZ_VERTEX_EDGE 40.0 // G and T differ from C by more than this
#define XBRZ_VERTEX_BAR 15.0  // the bar's pixels have T's color within this

// E and its 8 neighbors in the original (nA to nI, named as in pass 0), read in main for the rules below,
// E's squared YCbCr distances to its 4 side neighbors (sBSq, sDSq, sFSq, sHSq), and cached 3x3 INFO_AT reads
vec3 nB, nD, nE, nF, nH;
float sBSq, sDSq, sFSq, sHSq;

float sideSq(vec2 n)
{
  return n.y < -0.5 ? sBSq : (n.y > 0.5 ? sHSq : (n.x < 0.0 ? sDSq : sFSq));
}

#define infoAt(o) INFO_AT((o).x, (o).y)

// the pixel at offset o: served from the 3x3 registers when within (-1..1, -1..1), texture P otherwise
#define at3(o) P((o).x, (o).y)

vec4 vtxCorner(vec2 c) { return vec4(c.x < 0.0 && c.y < 0.0, c.x > 0.0 && c.y < 0.0, c.x > 0.0 && c.y > 0.0, c.x < 0.0 && c.y > 0.0); }
bool vtxSec(vec2 c, vec2 n) { return (c.x * c.y > 0.0) != (abs(n.x) > 0.5); }
bool vtxSame(vec3 a, vec3 b) { return withinEq255(a, b, XBRZ_VERTEX_TOL); }

bool vtxAt(vec2 u, vec2 v)
{
  vec3 C = at3(-u), G = nE, T = at3(-v);
  return vtxSame(C, at3(u - v)) && vtxSame(C, P(v.x - 2.0 * u.x, v.y - 2.0 * u.y)) && vtxSame(C, P(2.0 * u.x, 2.0 * u.y))
      && !withinEq255(C, G, XBRZ_VERTEX_EDGE) && !withinEq255(C, T, XBRZ_VERTEX_EDGE)
      && !vtxSame(C, at3(u)) && !vtxSame(C, at3(-u - v))
      && withinEq255(T, P(-2.0 * v.x, -2.0 * v.y), XBRZ_VERTEX_BAR) && withinEq255(T, P(-3.0 * v.x, -3.0 * v.y), XBRZ_VERTEX_BAR);
}

bool vtxBetween(vec3 g, vec3 t, vec3 c)
{
  vec3 tc = t - c;
  float k = dot(g - c, tc) / max(dot(tc, tc), 1e-6);
  float yt = luma(t), yc = luma(c), kY = (luma(g) - yc) / (abs(yt - yc) > 1e-3 ? yt - yc : 1e-3);
  return k > 0.15 && k < 0.85 && within255(c + k * tc, g, 24.0) && abs(yt - yc) > 1e-3 && kY > 0.15 && kY < 0.85;
}

void vtx(vec2 u, vec2 v, inout vec4 res)
{
  vec2 c = -u - v;
  vec4 m = vtxCorner(c);
  float w = dot(res, m);
  if (BLEND(w) < 0.5 || FLAG(w, 4.0) < 0.5 || (FLAG(w, 8.0) > 0.5) != vtxSec(c, -v) || !vtxAt(u, v)) return;
  if (vtxBetween(nE, at3(-v), at3(-u)))
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
  return float(dot(cut4(r), vec4(1.0)) < 0.5 && dot(cut4(w0) * FLAG(w0, 4.0), vec4(1.0)) > 0.5);
}
#define XBRZ_STEP38 0.5
vec4 junc4(vec4 res)
{
  vec3 E = nE;
  float wB = keptWhole(vec2(0.0, -1.0)), wD = keptWhole(vec2(-1.0, 0.0));
  float wF = keptWhole(vec2(1.0, 0.0)), wH = keptWhole(vec2(0.0, 1.0));
  if (wB + wD + wF + wH < 0.5) return res;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float w = dot(res, m);
    if (BLEND(w) < 0.5 || FLAG(w, 16.0) + FLAG(w, 64.0) > 0.5) continue;
    bool horiz = (c.x * c.y > 0.0) != (FLAG(w, 8.0) > 0.5);
    vec2 p = horiz ? vec2(c.x, 0.0) : vec2(0.0, c.y), q = horiz ? vec2(0.0, c.y) : vec2(c.x, 0.0);
    float wp = p.x < -0.5 ? wD : p.x > 0.5 ? wF : p.y < -0.5 ? wB : wH;
    float wq = q.x < -0.5 ? wD : q.x > 0.5 ? wF : q.y < -0.5 ? wB : wH;
    if (wp + wq < 0.5) continue;
    if (BLEND(dot(infoAt(c), vtxCorner(-c))) < 0.5) continue;
    vec3 Pc = at3(p), Qc = at3(q), X = at3(c);
    float dPQSq = distSqYCbCr(Pc, Qc);
    float lo5Sq = min(min(min(sideSq(p), sideSq(q)), min(distSqYCbCr(E, X), distSqYCbCr(Pc, X))), distSqYCbCr(Qc, X));
    if (min(lo5Sq, dPQSq) <= SQ255(XBRZ_JUNC4)) continue;
    if (dPQSq < (XBRZ_STEP38 * XBRZ_STEP38) * lo5Sq) continue;
    if ((within255(at3(vec2(c.x, -c.y)), at3(vec2(c.x, 0.0)), XBRZ_SAME_M) && within255(P(0.0, 2.0 * c.y), at3(vec2(0.0, c.y)), XBRZ_SAME_M))
        || (within255(at3(vec2(-c.x, c.y)), at3(vec2(0.0, c.y)), XBRZ_SAME_M) && within255(P(2.0 * c.x, 0.0), at3(vec2(c.x, 0.0)), XBRZ_SAME_M)))
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
    if (min(aSq, bSq) <= SQ255(20.0)) continue;
    vec3 Nh = at3(vec2(c.x, 0.0)), Nv = at3(vec2(0.0, c.y)), X = at3(c);
    float xdSq = min(distSqYCbCr(X, Nh), min(distSqYCbCr(X, Nv), distSqYCbCr(X, E)));
    if (xdSq <= SQ255(20.0)) continue;
    float a = sqrt(aSq) * 255.0, b = sqrt(bSq) * 255.0;
    bool tie = abs(a - b) < 0.01 ? true : abs(a - b) < XBRZ_MID39 * max(a, b) && xdSq > SQ255(XBRZ_FAR39) && FLAG(wc, 16.0) + FLAG(wc, 64.0) < 0.5;
    if (tie && dist255(Nh, Nv) > 1.8 * max(a, b)) res = mix(res, vec4(0.0), m);
  }
  return res;
}

// ---- Rule 40: a dot separates what is around it ----
#define XBRZ_DOT40 40.0
#define XBRZ_DOTK40 8.0
bool dot40(vec2 n, vec3 K)
{
  vec3 c = at3(n);
  if (within255(c, K, XBRZ_DOT40)) return false;
  float g = 0.0;
  float lk = luma(K);
  if (luma(c) >= lk) return false;
  vec2 r[8];
  r[0] = vec2(-1.0, -1.0); r[1] = vec2(0.0, -1.0); r[2] = vec2(1.0, -1.0); r[3] = vec2(1.0, 0.0);
  r[4] = vec2(1.0, 1.0); r[5] = vec2(0.0, 1.0); r[6] = vec2(-1.0, 1.0); r[7] = vec2(-1.0, 0.0);
  vec3 q = at3(n + vec2(-1.0, 0.0));
  float nc = 0.0;
  vec3 u0 = q, u1 = q, u2 = q;
  bool prev = within255(q, K, XBRZ_DOTK40);
  for (int i = 0; i < 8; i++)
  {
    vec3 p = at3(n + r[i]);
    if (within255(c, p, XBRZ_DOT40)) return false;
    bool k = within255(p, K, XBRZ_DOTK40);
    bool fresh = nc < 0.5 || (!within255(p, u0, XBRZ_DOTK40) && (nc < 1.5 || !within255(p, u1, XBRZ_DOTK40)) && (nc < 2.5 || !within255(p, u2, XBRZ_DOTK40)));
    if (fresh) { if (nc > 2.5) return false; if (nc < 0.5) u0 = p; else if (nc < 1.5) u1 = p; else u2 = p; nc += 1.0; }
    if (k && !prev) g += 1.0;
    if (!k && luma(p) <= lk) return false;
    prev = k;
  }
  return g > 1.5;
}
vec4 dots40(vec4 res)
{
  vec3 nA = P(-1.0, -1.0), nC = P(1.0, -1.0), nG = P(-1.0, 1.0), nI = P(1.0, 1.0);
  float r8Sq = min(min(min(sBSq, sDSq), min(sFSq, sHSq)),
                   min(min(distSqYCbCr(nE, nA), distSqYCbCr(nE, nC)), min(distSqYCbCr(nE, nG), distSqYCbCr(nE, nI))));
  bool loneDot = r8Sq >= SQ255(XBRZ_DOT40);
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float w = dot(res, m);
    if (BLEND(w) < 0.5) continue;
    bool horiz = (c.x * c.y > 0.0) != (FLAG(w, 8.0) > 0.5);
    vec3 K = horiz ? at3(vec2(c.x, 0.0)) : at3(vec2(0.0, c.y));
    vec2 o = horiz ? vec2(0.0, c.y) : vec2(c.x, 0.0);
    if (dot40(o, K)) res = mix(res, vec4(0.0), m);
    else if (loneDot && dot40(vec2(0.0), K)) res = mix(res, vec4(3.0 + 8.0 * FLAG(w, 8.0)), m);
  }
  return res;
}

// ---- Rule 41: a 1-pixel diagonal stroke keeps an even edge ----
bool lone41(vec2 p)
{
  vec3 c = at3(p);
  return !within255(c, at3(p + vec2(-1.0, 0.0)), XBRZ_SAME_M) && !within255(c, at3(p + vec2(1.0, 0.0)), XBRZ_SAME_M)
      && !within255(c, at3(p + vec2(0.0, -1.0)), XBRZ_SAME_M) && !within255(c, at3(p + vec2(0.0, 1.0)), XBRZ_SAME_M);
}
float lineType41(float w)
{
  if (FLAG(w, 32.0) + FLAG(w, 128.0) > 0.5) return 0.0;
  return FLAG(w, 4.0) * (FLAG(w, 16.0) - FLAG(w, 64.0));
}
float edge41(vec2 c, vec4 r0, vec3 E)
{
  if (BLEND(dot(r0, vtxCorner(-c))) < 0.5) return 0.0;
  if (!within255(E, at3(vec2(c.x, -c.y)), XBRZ_SAME_M) || !within255(E, at3(vec2(-c.x, c.y)), XBRZ_SAME_M)) return 0.0;
  vec3 V = at3(vec2(0.0, c.y)), H = at3(vec2(c.x, 0.0)), X = at3(c);
  if (within255(E, X, XBRZ_SAME_M)) return 0.0;
  if (luma(E) > min(luma(V), luma(H)) - 0.03) return 0.0;
  bool kH = within255(X, H, XBRZ_SAME_M), kV = within255(X, V, XBRZ_SAME_M);
  if (kH == kV) return 0.0;
  vec2 o = kH ? vec2(0.0, c.y) : vec2(c.x, 0.0);
  vec3 O = at3(o);
  if (within255(O, P(2.0 * o.x, 2.0 * o.y), XBRZ_SAME_M)) return 0.0;
  if (within255(O, at3(o + vec2(c.x, -c.y)), XBRZ_SAME_M) || within255(O, at3(o + vec2(-c.x, c.y)), XBRZ_SAME_M)) return 0.0;
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
    if (min(c.x > 0.0 ? sFSq : sDSq, c.y > 0.0 ? sHSq : sBSq) < SQ255(XBRZ_MINC)) continue;
    vec3 Kh = at3(vec2(c.x, 0.0)), Kv = at3(vec2(0.0, c.y));
    if (!within255(Kh, Kv, XBRZ_SAME_M)) continue;
    vec3 K = 0.5 * (Kh + Kv);
    if (!within255(K, at3(c), XBRZ_SAME_M)) continue;
    if (within255(K, at3(vec2(-c.x, 0.0)), XBRZ_SAME_M) || within255(K, at3(vec2(0.0, -c.y)), XBRZ_SAME_M)) continue;
    float ok = 1.0;
    for (int j = 0; j < 2; j++)
    {
      vec2 q = j == 0 ? vec2(c.x, -c.y) : vec2(-c.x, c.y);
      float wq = dot(infoAt(q), m);
      vec2 p = q + paintOf(c, wq);
      if (BLEND(wq) < 0.5 || FLAG(wq, 4.0) < 0.5 || FLAG(wq, 16.0) != FLAG(wq, 64.0) || !within255(at3(p), K, XBRZ_SAME_M)) ok = 0.0;
    }
    if (ok > 0.5) res = mix(res, vec4(5.0 + 8.0 * FLAG(dot(res, m), 8.0)), m);
  }
  return res;
}

vec4 diagStroke41(vec4 res, bool loneE)
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
    for (int j = 0; j < 2; j++)
    {
      vec2 n = j == 0 ? vec2(c.x, 0.0) : vec2(0.0, c.y);
      float wn = dot(infoAt(n), vtxCorner(-c));
      if (BLEND(wn) < 0.5 || lineType41(wn) != -t) continue;
      vec2 o = c - n;
      vec3 N = at3(n);
      if (!loneE && within255(N, at3(o), XBRZ_SAME_M) && lone41(n) && lone41(o))
      { res -= m * (16.0 * FLAG(w, 16.0) + 64.0 * FLAG(w, 64.0)); break; }
      vec2 q = -c + c * abs(n);
      if (loneE && within255(E, at3(n + q), XBRZ_SAME_M) && lone41(n + q))
      { res -= m * (4.0 + 16.0 * FLAG(w, 16.0) + 64.0 * FLAG(w, 64.0)); break; }
    }
  }
  return res;
}

// ---- Rule 43: a dome ----
float dome43(vec2 c, vec2 s, vec2 v)
{
  if (!within255(at3(-s), nE, XBRZ_SAME_M)) return 0.0;
  vec3 S = at3(s), U = at3(v);
  if (within255(S, U, XBRZ_MINC)
      || !within255(at3(c), U, XBRZ_SAME_M) || !within255(at3(v - s), U, XBRZ_SAME_M)
      || !within255(P(-2.0 * s.x, -2.0 * s.y), S, XBRZ_SAME_M) || !within255(P(v.x - 2.0 * s.x, v.y - 2.0 * s.y), U, XBRZ_SAME_M))
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
  return float(distSqYCbCr(E, q) >= SQ255(XBRZ_END44) && luma(q) >= lE);
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
  float lE = luma(E);
  if (far44(E, lE, -v) * far44(E, lE, u) * far44(E, lE, -u) * far44(E, lE, v + u) * far44(E, lE, v - u) *
      far44(E, lE, u - v) * far44(E, lE, -u - v) < 0.5)
    return res;
  for (int k = 0; k < 2; k++)
  {
    vec2 c = k == 0 ? u - v : -u - v;
    vec4 m = vtxCorner(c);
    if (BLEND(dot(res, m)) > 0.5) continue;
    vec2 k1 = c - v, k2 = 2.0 * c + v;
    vec4 wG = infoAt(c);
    if ((within255(E, at3(k1), XBRZ_SAME_M) && BLEND(dot(wG, vtxCorner(-c - 2.0 * v))) > 0.5)
        || (within255(E, at3(k2), XBRZ_SAME_M) && BLEND(dot(wG, vtxCorner(c + 2.0 * v))) > 0.5)) continue;
    vec3 Nh = at3(vec2(c.x, 0.0)), Nv = at3(vec2(0.0, c.y));
    bool hz = c.x * c.y > 0.0;
    float dPri = distSqYCbCr(E, hz ? Nh : Nv), dSec = distSqYCbCr(E, hz ? Nv : Nh);
    res = mix(res, vec4(dPri <= dSec ? 1.0 : 9.0), m);
  }
  return res;
}

// ---- Rule 49: a 1-pixel diagonal bar ----
#define XBRZ_BAR49 60.0
vec2 barEnd(vec2 o)
{
  vec3 E = at3(o);
  float n = 0.0;
  vec2 c = vec2(0.0);
  for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++)
  {
    vec2 d = vec2(float(i), float(j));
    if ((i != 0 || j != 0) && within255(E, at3(o + d), XBRZ_BAR49)) { n += 1.0; c = d; }
  }
  if (n != 1.0 || c.x == 0.0 || c.y == 0.0 || !within255(E, at3(o + c), XBRZ_SAME_M)) return vec2(0.0);
  for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++)
  {
    vec2 d = vec2(float(i), float(j));
    if ((i != 0 || j != 0) && d != -c && d != c && within255(E, at3(o + c + d), XBRZ_BAR49)) return vec2(0.0);
  }
  float d2Sq = distSqYCbCr(E, at3(o + 2.0 * c));
  if (d2Sq < SQ255(XBRZ_BAR49) && d2Sq >= SQ255(XBRZ_SAME_M)) return vec2(0.0);
  float lE = luma(E), l1 = luma(at3(o + vec2(c.x, 0.0))), l2 = luma(at3(o + vec2(0.0, c.y)));
  if ((lE - l1) * (lE - l2) <= 0.0) return vec2(0.0);
  if (BLEND(dot(INFO_AT(o.x + c.x, o.y), vtxCorner(vec2(-c.x, c.y)))) < 0.5 ||
      BLEND(dot(INFO_AT(o.x, o.y + c.y), vtxCorner(vec2(c.x, -c.y)))) < 0.5) return vec2(0.0);
  return c;
}

bool cutsIn(vec2 q, vec2 k, vec3 C)
{
  float w = dot(infoAt(q), vtxCorner(k));
  if (BLEND(w) < 0.5) return false;
  bool hz = k.x * k.y > 0.0, sec = FLAG(w, 8.0) > 0.5;
  vec2 p = (hz == sec) ? vec2(0.0, k.y) : vec2(k.x, 0.0);
  return within255(at3(q + p), C, XBRZ_SAME_M);
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
      if ((i != 0 || j != 0) && within255(Q, at3(q + vec2(float(i), float(j))), XBRZ_SAME_M))
        return false;
  return true;
}

void main()
{
  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  coord = vTexCoord - pos * SRC_SIZE.zw;
  ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;
  c0 = coord * SRC_SIZE.xy * P0_SIZE.zw;
  vec4 res = INFO_AT(0.0, 0.0);
  if (XBRZ_MINC <= 0.0)
  {
    FRAG_OUT = res / 255.0;
    return;
  }
  vec4 w0 = W0_AT(0.0, 0.0);
  bool noCuts = dot(cut4(res) + cut4(w0), vec4(1.0)) == 0.0;

  // Fast path: when neither pass 0 nor resolve cuts any corner, only rules 42, 44 and 49 can cut one,
  // and all three need contrast >= min(XBRZ_MINC, XBRZ_BAR49) on both axes (D or F, and B or H)
  float fastLimSq = min(SQ255(XBRZ_MINC), SQ255(XBRZ_BAR49));
  nD = P(-1.0, 0.0);  nE = P(0.0, 0.0);  nF = P(1.0, 0.0);
  sDSq = distSqYCbCr(nE, nD); sFSq = distSqYCbCr(nE, nF);
  if (noCuts && max(sDSq, sFSq) < fastLimSq)
  {
    FRAG_OUT = res / 255.0;
    return;
  }
  nB = P(0.0, -1.0);  nH = P(0.0, 1.0);
  sBSq = distSqYCbCr(nE, nB); sHSq = distSqYCbCr(nE, nH);
  if (noCuts && max(sBSq, sHSq) < fastLimSq)
  {
    FRAG_OUT = res / 255.0;
    return;
  }

  float minSideSq = min(min(sBSq, sDSq), min(sFSq, sHSq));
  float maxSideSq = max(max(sBSq, sDSq), max(sFSq, sHSq));

  vec4 lost = cut4(w0) * (1.0 - cut4(res));
  if (dot(lost, vec4(1.0)) > 0.0)
  {
    vec4 rA = INFO_AT(-1.0, -1.0), rC = INFO_AT(1.0, -1.0), rI = INFO_AT(1.0, 1.0), rG = INFO_AT(-1.0, 1.0);
    vec3 B = nB, D = nD, F = nF, H = nH;
    vec4 strong = vec4(greaterThan(max(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq)), vec4(SQ255(XBRZ_MATCH_EDGE))));

    vec4 gap = vec4(cut4(rC).x * cut4(rG).x, cut4(rI).y * cut4(rA).y, cut4(rC).z * cut4(rG).z, cut4(rI).w * cut4(rA).w);
    vec4 wrapE = vec4(lessThan(vec4(distSqYCbCr(B, D), distSqYCbCr(B, F), distSqYCbCr(F, H), distSqYCbCr(H, D)), vec4(SQ255(XBRZ_MATCH_WRAP))));
    float wCx = distSqYCbCr(P(1.0, -2.0), B), wGx = distSqYCbCr(D, P(-2.0, 1.0));
    float wAy = distSqYCbCr(P(-1.0, -2.0), B), wIy = distSqYCbCr(F, P(2.0, 1.0));
    float wCz = distSqYCbCr(P(2.0, -1.0), F), wGz = distSqYCbCr(H, P(-1.0, 2.0));
    float wAw = distSqYCbCr(D, P(-2.0, -1.0)), wIw = distSqYCbCr(P(1.0, 2.0), H);
    vec4 wrapN = vec4(lessThan(vec4(max(wCx, wGx), max(wAy, wIy), max(wCz, wGz), max(wAw, wIw)), vec4(SQ255(XBRZ_MATCH_LINE))));

    vec4 part = vec4(cut4(rA).z, cut4(rC).w, cut4(rI).x, cut4(rG).y);
    vec4 l45 = vec4(isLine45(rA).z, isLine45(rC).w, isLine45(rI).x, isLine45(rG).y);

    vec4 fix = lost * strong * max(gap * wrapE * wrapN, part * l45 * (1.0 - FLAG(w0, 4.0)));
    vec4 far43 = vec4(greaterThanEqual(min(vec4(sDSq, sFSq, sFSq, sDSq), vec4(sBSq, sBSq, sHSq, sHSq)), vec4(SQ255(XBRZ_MINC))));
    far43 *= vec4(lessThan(min(vec4(sFSq, sDSq, sDSq, sFSq), vec4(sHSq, sHSq, sBSq, sBSq)), vec4(SQ255(XBRZ_SAME_M))));
    if (dot(lost, far43) > 0.0) fix = max(fix, domes43(lost * far43));
    vec4 back = 1.0 + 4.0 * FLAG(w0, 4.0) + 8.0 * FLAG(w0, 8.0) + 16.0 * FLAG(w0, 16.0) + 64.0 * FLAG(w0, 64.0);
    res = mix(res, back, fix);
  }
  // rule 27
  if (dot(cut4(res) * FLAG(res, 4.0), vec4(1.0)) > 0.0)
  {
    vtx(vec2( 1.0, 0.0), vec2(0.0,  1.0), res); vtx(vec2(-1.0, 0.0), vec2(0.0,  1.0), res);
    vtx(vec2( 1.0, 0.0), vec2(0.0, -1.0), res); vtx(vec2(-1.0, 0.0), vec2(0.0, -1.0), res);
    vtx(vec2(0.0,  1.0), vec2( 1.0, 0.0), res); vtx(vec2(0.0, -1.0), vec2( 1.0, 0.0), res);
    vtx(vec2(0.0,  1.0), vec2(-1.0, 0.0), res); vtx(vec2(0.0, -1.0), vec2(-1.0, 0.0), res);
  }
  // 42
  if (min(max(sDSq, sFSq), max(sBSq, sHSq)) >= SQ255(XBRZ_MINC)) res = edgeStep42(res);
  // rules 38 to 41
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = junc4(res);
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = tieRamp(res);
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = dots40(res);
  bool loneE = minSideSq >= SQ255(XBRZ_SAME_M);
  if (dot(cut4(res), vec4(1.0)) > 0.0
      && (loneE || dot(cut4(res) * FLAG(res, 4.0) * abs(FLAG(res, 16.0) - FLAG(res, 64.0)) * vec4(equal(FLAG(res, 32.0) + FLAG(res, 128.0), vec4(0.0))), vec4(1.0)) > 0.0))
    res = diagStroke41(res, loneE);
  // 44
  if (maxSideSq >= SQ255(XBRZ_END44)) res = strokeEnd44(res);
  // 47, 45, 48 (all require at least one cut corner in res)
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    // 47. a notch in the straight side of a stroke in shades
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
        vec3 Ac = at3(a);
        float dBSq = sideSq(b), dASq = sideSq(a);
        if (dASq >= SQ255(XBRZ_NOTCH47) || dBSq >= SQ255(XBRZ_NOTCH47) || dBSq >= 1.44 * dASq || sideSq(-a) < SQ255(XBRZ_FAR47)
            || !within255(nE, at3(a - b), XBRZ_SAME_M) || within255(Ac, at3(c), XBRZ_SAME_M)
            || BLEND(dot(infoAt(b), vtxCorner(c - 2.0 * b))) > 0.5 || !within255(nE, at3(2.0 * b), XBRZ_SAME_M)
            || !isLone3x3(Ac, a))
          continue;
        sqM += m;
      }
      res *= 1.0 - min(sqM, vec4(1.0));
    }
    // 45. the dark side of a mid-tone stroke's end
    if (dot(cut4(res) * FLAG(res, 4.0) * abs(FLAG(res, 16.0) - FLAG(res, 64.0)), vec4(1.0)) > 0.0)
    {
      vec4 cw = cut4(res) * FLAG(res, 4.0) * abs(FLAG(res, 16.0) - FLAG(res, 64.0));
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
          if (dot(cw, m) < 0.5 || dot(cAny, vtxCorner(-sd - u)) > 0.5) continue;
          float dSSq = sideSq(sd), dFSq = sideSq(-u), dGSq = distSqYCbCr(nE, at3(c));
          if (max(max(dSSq, dFSq), dGSq) >= SQ255(XBRZ_MATCH_EDGE) || min(dSSq, dFSq) < SQ255(XBRZ_MINC) || sideSq(-sd) < SQ255(80.0)
              || within255(at3(sd), at3(-u), XBRZ_MINC)) continue;
          sq += m;
        }
      }
      res *= 1.0 - min(sq, vec4(1.0));
    }
    // 48. one slope beside a lone shade
    if (dot(cut4(res) * FLAG(res, 4.0), vec4(1.0)) > 0.0)
    {
      vec4 cutM = cut4(res) * FLAG(res, 4.0), secM = FLAG(res, 8.0), shM = FLAG(res, 16.0), stM = FLAG(res, 64.0);
      vec4 lngM = FLAG(res, 32.0) + FLAG(res, 128.0);
      vec4 dropS = vec4(0.0), dropT = vec4(0.0);
      for (int k = 0; k < 4; k++)
      {
        vec2 c = k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
        vec4 m = vtxCorner(c);
        float sh = dot(shM, m), st = dot(stM, m);
        if (dot(cutM, m) < 0.5 || sh + st != 1.0 || dot(lngM, m) > 0.5) continue;
        bool xz = k == 0 || k == 2;
        bool paintV = xz ? dot(secM, m) > 0.5 : dot(secM, m) < 0.5;
        bool hLong = xz ? sh > 0.5 : st > 0.5;
        if (hLong != paintV) continue;
        vec2 a = paintV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
        vec3 Ac = at3(a);
        float dASq = sideSq(a);
        if (dASq < SQ255(XBRZ_SAME_M) || dASq >= SQ255(XBRZ_SHADE48)) continue;
        vec4 rA = infoAt(a), mA = vtxCorner(-c);
        if (BLEND(dot(rA, mA)) < 0.5 || dot(FLAG(rA, 16.0) + FLAG(rA, 64.0), mA) > 0.5) continue;
        bool pVA = xz ? dot(FLAG(rA, 8.0), mA) > 0.5 : dot(FLAG(rA, 8.0), mA) < 0.5;
        if (pVA != paintV) continue;
        bool hit = false;
        for (int h = 0; h < 2; h++)
        {
          vec2 q = h == 0 ? vec2(0.0) : a;
          vec3 Q = h == 0 ? nE : Ac, Sc = h == 0 ? Ac : nE;
          if (within255(Sc, at3(h == 0 ? -a : 2.0 * a), XBRZ_SAME_M) && isLone3x3(Q, q)) { hit = true; break; }
        }
        if (!hit) continue;
        if (sh > 0.5) dropS += m; else dropT += m;
      }
      res -= 16.0 * dropS + 64.0 * dropT;
    }
  }
  // 49. a 1-pixel diagonal bar ends even
  {
    vec3 E = nE;
    if (minSideSq >= SQ255(XBRZ_BAR49))
    {
      vec2 c = barEnd(vec2(0.0));
      if (c != vec2(0.0))
      {
        vec2 s1 = vec2(c.x, -c.y), s2 = vec2(-c.x, c.y), e = -c;
        vec4 m1 = vtxCorner(s1), m2 = vtxCorner(s2), me = vtxCorner(e);
        vec3 R1 = at3(vec2(e.x, 0.0)), R2 = at3(vec2(0.0, e.y));
        bool plug = within255(R1, R2, XBRZ_SAME_M) && !within255(R1, at3(vec2(c.x, 0.0)), XBRZ_SAME_M) &&
                    !within255(R1, at3(vec2(0.0, c.y)), XBRZ_SAME_M);
        if (!plug && BLEND(dot(res, m1)) < 0.5 && !goesOn(s1, E)) res = mix(res, vec4(s1.x * s1.y > 0.0 ? 5.0 : 13.0), m1);
        if (!plug && BLEND(dot(res, m2)) < 0.5 && !goesOn(s2, E)) res = mix(res, vec4(s2.x * s2.y > 0.0 ? 13.0 : 5.0), m2);
        float lE = luma(E), lA = luma(at3(e)), lS = 0.5 * (luma(at3(vec2(c.x, 0.0))) + luma(at3(vec2(0.0, c.y))));
        if ((BLEND(dot(res, me)) < 0.5 || FLAG(dot(res, me), 4.0) < 0.5) && (lA - lS) * (lE - lS) <= 0.0 && !goesOn(e, E))
        {
          vec3 Nh = at3(vec2(e.x, 0.0)), Nv = at3(vec2(0.0, e.y));
          bool hz = e.x * e.y > 0.0;
          float dPri = distSqYCbCr(E, hz ? Nh : Nv), dSec = distSqYCbCr(E, hz ? Nv : Nh);
          res = mix(res, vec4(dPri <= dSec ? 5.0 : 13.0), me);
        }
      }
    }
    if (dot(cut4(res), vec4(1.0)) > 0.0)
    {
      for (int q = 0; q < 4; q++)
      {
        float sqDistSq = q == 0 ? sBSq : (q == 1 ? sFSq : (q == 2 ? sHSq : sDSq));
        if (sqDistSq < SQ255(XBRZ_BAR49)) continue;
        vec2 n = q == 0 ? vec2(0.0, -1.0) : q == 1 ? vec2(1.0, 0.0) : q == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
        vec2 cn = barEnd(n);
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
        if (!within255(at3(pk), at3(n), XBRZ_SAME_M) && within255(at3(pk), other, XBRZ_SAME_M)) res = mix(res, vec4(0.0), mk);
      }
    }
  }
  FRAG_OUT = res / 255.0;
}

#endif

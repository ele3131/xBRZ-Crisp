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
// Matching pass of xbrz-crisp (OpenGL / GLES): once per input pixel, between resolve and pass 1 (rules 26, 28, 38-45, 48, 49)

#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
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
uniform COMPAT_PRECISION float XBRZ_MINC;
#else
#define XBRZ_MINC 20.0
#endif

// the point pass (three passes back), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev3Texture;
uniform COMPAT_PRECISION vec2 PassPrev3TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev3InputSize;
// pass 0's decisions (two passes back), before the resolve pass changed them
uniform sampler2D PassPrev2Texture;
uniform COMPAT_PRECISION vec2 PassPrev2TextureSize;
#define OUT_SIZE OutputSize
#define ORIG_INPUT_SIZE PassPrev3InputSize
#if __VERSION__ >= 300
ivec2 gIpx = ivec2(0), gSrcMaxI = ivec2(0), gOrigMaxI = ivec2(0);
#define P(x,y) texelFetch(PassPrev3Texture, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gOrigMaxI), 0).rgb
#define INFO_CENTER texelFetch(Texture, gIpx, 0)
#define INFO_AT(x, y) floor(texelFetch(Texture, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gSrcMaxI), 0) * 255.0 + 0.5)
#define W0_RAW texelFetch(PassPrev2Texture, gIpx, 0)
#define W0_AT(x, y) floor(texelFetch(PassPrev2Texture, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gSrcMaxI), 0) * 255.0 + 0.5)
#else
vec2 gSrcInv = vec2(0.0), gSrcMax = vec2(0.0);
vec2 gOrigInv = vec2(0.0), gOrigMax = vec2(0.0);
vec2 gP0Inv = vec2(0.0), gP0Max = vec2(0.0);
#define ORIG_SIZE vec4(PassPrev3TextureSize, gOrigInv)
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define SRC_SIZE vec4(TextureSize, gSrcInv)
#define CLAMP_ORIG(uv) min((uv), gOrigMax)
#define CLAMP_SRC(uv) min((uv), gSrcMax)
#define P(x,y) COMPAT_TEXTURE(PassPrev3Texture, CLAMP_ORIG(ocoord + gOrigInv * vec2(x, y))).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, CLAMP_SRC(uv))
#define INFO_CENTER INFO(coord)
#define INFO_STEP gSrcInv
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)
#define P0_SIZE vec4(PassPrev2TextureSize, gP0Inv)
#define CLAMP_P0(uv) min((uv), gP0Max)
#define W0_RAW COMPAT_TEXTURE(PassPrev2Texture, CLAMP_P0(c0))
#define W0_AT(x, y) floor(COMPAT_TEXTURE(PassPrev2Texture, CLAMP_P0(c0 + vec2(x, y) * gP0Inv)) * 255.0 + 0.5)
vec2 coord = vec2(0.0), ocoord = vec2(0.0), c0 = vec2(0.0);
#endif

// Decision-word bit layout (0..255 per corner: x = TL, y = TR, z = BR, w = BL):
//   bits 0..1 (BLEND): 0 = none, 1 = normal, 2 = dominant (pass0) / thin sliver R14 (resolve+), 3 = weak (pass0) / small tip R23/R40 (resolve+)
//   bit  2 (  4.0): BIT_LINE    - line blend (45-deg unless BIT_SHALLOW or BIT_STEEP is also set)
//   bit  3 (  8.0): BIT_SEC     - blend with second candidate neighbor (B, F, H, D instead of D, B, F, H)
//   bit  4 ( 16.0): BIT_SHALLOW - shallow 2:1 (or 3:1 / 4:1 when paired with BIT_LONG3 / BIT_LONG4)
//   bit  5 ( 32.0): BIT_TONE    - pass0: hue-weighted-only line (rule 9); resolve/match/pass1: BIT_LONG3 (3:1 slope)
//   bit  6 ( 64.0): BIT_STEEP   - steep 2:1 (or 3:1 / 4:1 when paired with BIT_LONG3 / BIT_LONG4)
//   bit  7 (128.0): BIT_BLOCKED - pass0: diagonal-limit blocked (rule 2); resolve/match/pass1: BIT_LONG4 (4:1 slope)
#define BIT_LINE    4.0
#define BIT_SEC     8.0
#define BIT_SHALLOW 16.0
#define BIT_TONE    32.0
#define BIT_LONG3   32.0
#define BIT_STEEP   64.0
#define BIT_BLOCKED 128.0
#define BIT_LONG4   128.0

#define BLEND(r)   mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)

// Corner decision-word masks (values in 0..255)
vec4 cut4(vec4 w)        { return vec4(greaterThan(BLEND(w), vec4(0.0))); }
// A cut that is neither weak (blend 3) nor blocked (bit 128)
vec4 activeCutOf(vec4 w) { vec4 bl = BLEND(w); return vec4(greaterThan(bl, vec4(0.0))) * vec4(lessThan(bl, vec4(3.0))) * vec4(lessThan(w, vec4(BIT_BLOCKED))); }
// A cut that is not weak (blend 3); keeps blocked (bit 128) when resolve may still rescue it
vec4 cutNoWeak(vec4 w)   { vec4 bl = BLEND(w); return vec4(greaterThan(bl, vec4(0.0))) * vec4(lessThan(bl, vec4(3.0))); }
vec4 drawsLine4(vec4 r)  { return activeCutOf(r) * FLAG(r, BIT_LINE); }
vec4 isLine45(vec4 r)    { return FLAG(r, BIT_LINE) * (1.0 - FLAG(r, BIT_SHALLOW)) * (1.0 - FLAG(r, BIT_STEEP)) * vec4(equal(FLAG(r, BIT_LONG3) + FLAG(r, BIT_LONG4), vec4(0.0))); }
float wordPlain(bool sec)  { return sec ? (1.0 + BIT_SEC) : 1.0; }
float wordLine45(bool sec) { return sec ? (1.0 + BIT_LINE + BIT_SEC) : (1.0 + BIT_LINE); }
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

// Squared threshold in [0..255] YCbCr units, kept in [0..1.5] so GLSL ES mediump never overflows.
// Implemented as a function (not a macro) so older glslang preprocessors (RetroArch Vulkan/Slang)
// never double-expand self-referential `#define XBRZ_* global.XBRZ_*` arguments into `global.global.*`.
float SQ255(float x)
{
  float t = x / 255.0;
  return t * t;
}
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

// Unified geometric AA-ramp test from squared pairwise color distances (a2, b2, c2):
// returns 1.0 when the middle color projects strictly onto the segment of length sqrt(c2)
// and its exact perpendicular distance sits within min(relLim * sqrt(c2), absLim255/255).
// Exact D4-symmetric in (a2, b2) and sqrt-free (reuses squared distances already in registers).
vec4 geomRamp4(vec4 a2, vec4 b2, vec4 c2, float relLim, float absLim255)
{
  vec4 diff2 = a2 - b2;
  vec4 safeC2 = max(c2, vec4(SAFE_EPS));
  vec4 mono = vec4(lessThan(abs(diff2), c2));
  vec4 perpSq = max(vec4(0.0), 0.5 * (a2 + b2) - 0.25 * c2 - (diff2 * diff2) / (4.0 * safeC2));
  vec4 limSq = min(vec4(SQ255(absLim255)), (relLim * relLim) * c2);
  return mono * vec4(lessThanEqual(perpSq, limSq));
}
// ---- Shared corner/axis geometry helpers for the match pass ----
// Corner index order matches decision-word channels: 0 = TL (-1,-1), 1 = TR (1,-1), 2 = BR (1,1), 3 = BL (-1,1)
vec2 cornerOff(int k)
{
  return k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
}
// Cardinal index order: 0 = B (0,-1), 1 = F (1,0), 2 = H (0,1), 3 = D (-1,0)
vec2 cardOff(int k)
{
  return k == 0 ? vec2(0.0, -1.0) : k == 1 ? vec2(1.0, 0.0) : k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
}
vec4 cornerMask(int k)
{
  return vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
}
vec4 vtxCorner(vec2 c)
{
  return vec4(c.x < 0.0 && c.y < 0.0, c.x > 0.0 && c.y < 0.0, c.x > 0.0 && c.y > 0.0, c.x < 0.0 && c.y > 0.0);
}
// True when cardinal neighbor n is the second candidate (BIT_SEC) of corner c
bool vtxSec(vec2 c, vec2 n)
{
  return (c.x * c.y > 0.0) != (abs(n.x) > 0.5);
}
// For corner k with a 2:1 slope (isSh = shallow, !isSh = steep):
//   nbrOff = cardinal neighbor along the 2:1 long edge, othOff = the other cardinal neighbor of corner k
void slope21Offsets(int k, bool isSh, out vec2 nbrOff, out vec2 othOff)
{
  vec2 c = cornerOff(k);
  bool nIsV = (k == 0 || k == 2) ? isSh : !isSh;
  nbrOff = nIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
  othOff = c - nbrOff;
}
// For corner k at offset c with BIT_SEC flag s1:
//   pOff = painted cardinal neighbor, qOff = unchosen cardinal neighbor
void paintPairOffsets(int k, vec2 c, bool s1, out vec2 pOff, out vec2 qOff)
{
  bool pIsV = (k == 0 || k == 2) ? s1 : !s1;
  pOff = pIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
  qOff = c - pOff;
}
// ---- Rule 28: shared hold-score & tie-breaker helpers (used by resolve and match passes) ----
#define XBRZ_HOLD_SAME 30.0 // a neighbor this close in color holds a pixel

float held28(vec3 a, vec3 b) { return float(withinEqY255(a, b, XBRZ_HOLD_SAME)); }
// How firmly pixel c is held by its 8 neighbors (cardinal neighbors count twice)
float holdOf28(vec3 c, vec3 tl, vec3 t, vec3 tr, vec3 l, vec3 r, vec3 bl, vec3 b, vec3 br)
{
  return held28(c, tl) + held28(c, tr) + held28(c, bl) + held28(c, br)
       + 2.0 * (held28(c, t) + held28(c, l) + held28(c, r) + held28(c, b));
}
// Lazy-ring hold score for an edge neighbor: fetches outer 3 texels only when the 5 inner texels can tie/flip hE
float holdOfEdge28(vec3 c, float hE, vec3 in0, vec3 in1, vec3 in2, vec3 in3, vec3 in4, vec2 o0, vec2 o1, vec2 o2)
{
  float hIn = held28(c, in0) + held28(c, in1) + 2.0 * (held28(c, in2) + held28(c, in3) + held28(c, in4));
  if (hE > hIn + 4.5 || hIn > hE + 0.5) return hIn;
  return hIn + held28(c, toYCbCr(P(o0.x, o0.y))) + 2.0 * held28(c, toYCbCr(P(o1.x, o1.y))) + held28(c, toYCbCr(P(o2.x, o2.y)));
}
float tie28(vec3 e, vec3 n)
{
  if (abs(e.x - n.x) > SAFE_EPS) return float(e.x < n.x);
  if (abs(e.y - n.y) > SAFE_EPS) return float(e.y < n.y);
  return float(e.z < n.z);
}
// Returns per-corner mask of pixels that stay whole (higher hold score, or darker on tie)
vec4 whole28Mask(float hE, vec4 hN, vec4 sec, vec3 E, vec3 B, vec3 D, vec3 F, vec3 H)
{
  vec4 tie = vec4(tie28(E, sec.x > 0.5 ? B : D), tie28(E, sec.y > 0.5 ? F : B),
                  tie28(E, sec.z > 0.5 ? H : F), tie28(E, sec.w > 0.5 ? D : H));
  return max(vec4(greaterThan(vec4(hE), hN + 0.5)),
             vec4(lessThan(abs(hE - hN), vec4(0.5))) * tie);
}
#define TIE_EPS 1e-5     // matches pass 0: equal integer color steps can differ in the last float bits
#define XBRZ_SAME_M 15.0 // two pixels within this are one color (sameColor of the resolve pass); rule 41

// ---- Rule 26: matching corners ----
#define XBRZ_MATCH_EDGE 40.0  // E differs from one of the corner's two neighbors by more than this
#define XBRZ_MATCH_WRAP 50.0  // gap: the corner's two neighbors are within this of each other
#define XBRZ_MATCH_LINE 30.0  // gap: so are the same two pixels of both neighbors along the cut

// ---- Rule 38: 4-color junction threshold ----
#define XBRZ_JUNC4 30.0

// E and its 4 cardinal neighbors in linear YCbCr, and E's squared YCbCr distances to them
vec3 nB, nD, nE, nF, nH;
float sBSq, sDSq, sFSq, sHSq;
float mincSq;

// Lazy-cached 3x3 neighbor decision words and diagonal YCbCr colors (shared across all match rules)
vec4 gIB, gID, gIF, gIH, gIA, gIC, gIG, gII;
vec3 gCA, gCC, gCG, gCI;
bool gHaveCardI, gHaveDiagI, gHaveDiagC;

void ensureCardInfo()
{
  if (!gHaveCardI)
  {
    gIB = INFO_AT(0.0, -1.0); gID = INFO_AT(-1.0, 0.0);
    gIF = INFO_AT(1.0,  0.0); gIH = INFO_AT( 0.0, 1.0);
    gHaveCardI = true;
  }
}
void ensureDiagInfo()
{
  if (!gHaveDiagI)
  {
    gIA = INFO_AT(-1.0, -1.0); gIC = INFO_AT(1.0, -1.0);
    gIG = INFO_AT(-1.0,  1.0); gII = INFO_AT(1.0,  1.0);
    gHaveDiagI = true;
  }
}
void ensureDiagColor()
{
  if (!gHaveDiagC)
  {
    gCA = toYCbCr(P(-1.0, -1.0)); gCC = toYCbCr(P(1.0, -1.0));
    gCG = toYCbCr(P(-1.0,  1.0)); gCI = toYCbCr(P(1.0,  1.0));
    gHaveDiagC = true;
  }
}

float sideSq(vec2 n)
{
  return n.y < -0.5 ? sBSq : (n.y > 0.5 ? sHSq : (n.x < 0.0 ? sDSq : sFSq));
}
vec3 cardColor(vec2 n)
{
  return n.y < -0.5 ? nB : (n.y > 0.5 ? nH : (n.x < 0.0 ? nD : nF));
}
vec4 cardInfo(vec2 n)
{
  ensureCardInfo();
  return n.y < -0.5 ? gIB : (n.y > 0.5 ? gIH : (n.x < 0.0 ? gID : gIF));
}
vec4 diagInfo(vec2 c)
{
  ensureDiagInfo();
  return c.y < 0.0 ? (c.x < 0.0 ? gIA : gIC) : (c.x < 0.0 ? gIG : gII);
}
vec3 diagColor(vec2 c)
{
  ensureDiagColor();
  return c.y < 0.0 ? (c.x < 0.0 ? gCA : gCC) : (c.x < 0.0 ? gCG : gCI);
}

#define infoAt(o) INFO_AT((o).x, (o).y)
#define at3(o) toYCbCr(P((o).x, (o).y))

vec3 at3x3(vec2 o)
{
  float d1 = abs(o.x) + abs(o.y);
  if (d1 < 0.5) return nE;
  if (d1 < 1.5) return cardColor(o);
  if (abs(o.x) < 1.5 && abs(o.y) < 1.5) return diagColor(o);
  return at3(o);
}

// Exact 0-sqrt triangle tests on squared distances:
// sqrt(a) + sqrt(b) < k * sqrt(c)  <=>  t = k^2*c - a - b > 0 && 4*a*b < t^2
vec4 triLt4(vec4 a, vec4 b, float k2, vec4 c)
{
  vec4 t = k2 * c - a - b;
  return vec4(greaterThan(t, vec4(0.0))) * vec4(lessThan(4.0 * a * b, t * t));
}
vec4 triGe4(vec4 a, vec4 b, float k2, vec4 c)
{
  return 1.0 - triLt4(a, b, k2, c);
}
bool triGt(float a, float b, float k2, float c)
{
  float t = k2 * c - a - b;
  return t < 0.0 || 4.0 * a * b > t * t;
}

bool pickSecSq(float dPri, float dSec, vec3 cPri, vec3 cSec)
{
  if (dSec + TIE_EPS < dPri) return true;
  if (dPri + TIE_EPS < dSec) return false;
  if (abs(cPri.x - cSec.x) > SAFE_EPS) return cSec.x < cPri.x;
  if (abs(cPri.y - cSec.y) > SAFE_EPS) return cSec.y < cPri.y;
  return cSec.z < cPri.z;
}
// Pick nearer candidate (BIT_SEC) for corner offset c using symmetric tie-breaker
bool pickCornerSec(vec2 c)
{
  float hSq = c.x > 0.0 ? sFSq : sDSq, vSq = c.y > 0.0 ? sHSq : sBSq;
  bool hz = c.x * c.y > 0.0;
  vec3 Nh = c.x > 0.0 ? nF : nD, Nv = c.y > 0.0 ? nH : nB;
  return pickSecSq(hz ? hSq : vSq, hz ? vSq : hSq, hz ? Nh : Nv, hz ? Nv : Nh);
}

// ============================================================================================
// Match pass — 1-pixel strokes, domes, slopes, and diagonal bars (Rules 41, 43-45, 48, 49)
// ============================================================================================

// ---- Rule 41: a 1-pixel diagonal stroke keeps an even edge ----
bool lone41(vec2 p)
{
  vec3 c = at3x3(p);
  return !withinY255(c, at3x3(p + vec2(-1.0, 0.0)), XBRZ_SAME_M) && !withinY255(c, at3x3(p + vec2(1.0, 0.0)), XBRZ_SAME_M)
      && !withinY255(c, at3x3(p + vec2(0.0, -1.0)), XBRZ_SAME_M) && !withinY255(c, at3x3(p + vec2(0.0, 1.0)), XBRZ_SAME_M);
}
bool lone41Card(vec2 p)
{
  // caller already verified sideSq(p) >= SQ255(XBRZ_SAME_M), so skip neighbor -p (= nE)
  vec3 c = cardColor(p);
  vec2 s = vec2(p.y, -p.x);
  return !withinY255(c, at3(2.0 * p), XBRZ_SAME_M)
      && !withinY255(c, diagColor(p + s), XBRZ_SAME_M)
      && !withinY255(c, diagColor(p - s), XBRZ_SAME_M);
}
float lineType41(float w)
{
  if (FLAG(w, BIT_LONG3) + FLAG(w, BIT_LONG4) > 0.5) return 0.0;
  return FLAG(w, BIT_LINE) * (FLAG(w, BIT_SHALLOW) - FLAG(w, BIT_STEEP));
}
float edge41(vec2 c, vec4 r0, vec3 E)
{
  if (BLEND(dot(r0, vtxCorner(-c))) < 0.5) return 0.0;
  vec3 V = c.y > 0.0 ? nH : nB, H = c.x > 0.0 ? nF : nD;
  if (E.x > min(V.x, H.x) - 0.03) return 0.0;
  if (!withinY255(E, diagColor(vec2(c.x, -c.y)), XBRZ_SAME_M) || !withinY255(E, diagColor(vec2(-c.x, c.y)), XBRZ_SAME_M)) return 0.0;
  vec3 X = diagColor(c);
  if (withinY255(E, X, XBRZ_SAME_M)) return 0.0;
  bool kH = withinY255(X, H, XBRZ_SAME_M), kV = withinY255(X, V, XBRZ_SAME_M);
  if (kH == kV) return 0.0;
  vec2 o = kH ? vec2(0.0, c.y) : vec2(c.x, 0.0);
  vec3 O = cardColor(o);
  if (withinY255(O, toYCbCr(P(2.0 * o.x, 2.0 * o.y)), XBRZ_SAME_M)) return 0.0;
  if (withinY255(O, at3x3(o + vec2(c.x, -c.y)), XBRZ_SAME_M) || withinY255(O, at3x3(o + vec2(-c.x, c.y)), XBRZ_SAME_M)) return 0.0;
  return wordLine45(vtxSec(c, kH ? vec2(c.x, 0.0) : vec2(0.0, c.y)));
}
vec4 diagStroke41(vec4 res, bool loneE, vec4 pairSq)
{
  vec3 E = nE;
  vec4 r0 = res;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = cornerOff(i);
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
      { res -= m * (BIT_SHALLOW * FLAG(w, BIT_SHALLOW) + BIT_STEEP * FLAG(w, BIT_STEEP)); break; }
      vec2 q = -c + c * abs(n);
      if (loneE && withinY255(E, at3x3(n + q), XBRZ_SAME_M) && lone41(n + q))
      { res -= m * (BIT_LINE + BIT_SHALLOW * FLAG(w, BIT_SHALLOW) + BIT_STEEP * FLAG(w, BIT_STEEP)); break; }
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
    vec2 c = cornerOff(i);
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
  if (BLEND(dot(res, vtxCorner(u - v))) > 0.5 && BLEND(dot(res, vtxCorner(-u - v))) > 0.5)
    return res;
  vec3 E = nE;
  float lE = E.x;
  vec3 cTip = cardColor(-v), cU = cardColor(u), cMU = cardColor(-u);
  if (dot(E.yz, E.yz) >= SQ255(50.0)
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
    res = mix(res, vec4(wordPlain(pickCornerSec(c))), m);
  }
  return res;
}

// ---- Rule 49: a 1-pixel diagonal bar ----
#define XBRZ_BAR49 60.0
vec2 barEnd0(vec3 E, out vec3 dA, out vec3 dC, out vec3 dI, out vec3 dG)
{
  dA = diagColor(vec2(-1.0, -1.0)); dC = diagColor(vec2(1.0, -1.0));
  dI = diagColor(vec2( 1.0,  1.0)); dG = diagColor(vec2(-1.0, 1.0));
  float n = 0.0;
  vec2 c = vec2(0.0);
  vec3 Ccol = E;
  if (withinY255(E, dA, XBRZ_BAR49)) { n += 1.0; c = vec2(-1.0, -1.0); Ccol = dA; }
  if (withinY255(E, dC, XBRZ_BAR49)) { n += 1.0; if (n > 1.5) return vec2(0.0); c = vec2( 1.0, -1.0); Ccol = dC; }
  if (withinY255(E, dI, XBRZ_BAR49)) { n += 1.0; if (n > 1.5) return vec2(0.0); c = vec2( 1.0,  1.0); Ccol = dI; }
  if (withinY255(E, dG, XBRZ_BAR49)) { n += 1.0; if (n > 1.5) return vec2(0.0); c = vec2(-1.0,  1.0); Ccol = dG; }
  if (n < 0.5 || !withinY255(E, Ccol, XBRZ_SAME_M)) return vec2(0.0);
  float lE = E.x, l1 = (c.x > 0.0 ? nF.x : nD.x), l2 = (c.y > 0.0 ? nH.x : nB.x);
  if ((lE - l1) * (lE - l2) <= 0.0) return vec2(0.0);
  if (BLEND(dot(cardInfo(vec2(c.x, 0.0)), vtxCorner(vec2(-c.x, c.y)))) < 0.5 ||
      BLEND(dot(cardInfo(vec2(0.0, c.y)), vtxCorner(vec2(c.x, -c.y)))) < 0.5) return vec2(0.0);
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
  float w = dot(cardInfo(q), vtxCorner(k));
  if (BLEND(w) < 0.5) return false;
  bool hz = k.x * k.y > 0.0, sec = FLAG(w, BIT_SEC) > 0.5;
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
  float w = dot(cardInfo(q), vtxCorner(k));
  return BLEND(w) >= 0.5 && FLAG(w, BIT_LINE) >= 0.5
      && FLAG(w, BIT_SHALLOW) + FLAG(w, BIT_STEEP) + FLAG(w, BIT_LONG3) + FLAG(w, BIT_LONG4) < 0.5;
}
vec4 apex41(vec4 res, vec4 pairSq, vec4 minCornerSq)
{
  vec4 c41 = cut4(res) * FLAG(res, BIT_LINE);
  vec4 is21 = c41 * vec4(equal(FLAG(res, BIT_LONG3) + FLAG(res, BIT_LONG4), vec4(0.0)));
  vec4 f16 = FLAG(res, BIT_SHALLOW), f64 = FLAG(res, BIT_STEEP);
  vec4 sh41 = is21 * f16 * (1.0 - f64);
  vec4 st41 = is21 * f64 * (1.0 - f16);
  vec4 colEdge = vec4(
    max(sh41.x * c41.y, st41.y * c41.x),
    max(sh41.y * c41.z, st41.z * c41.y),
    max(sh41.z * c41.w, st41.w * c41.z),
    max(sh41.w * c41.x, st41.x * c41.w));
  vec4 validG4 = (1.0 - cut4(res)) * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_SAME_M))))
               * vec4(lessThan(pairSq, minCornerSq))
               * vec4(greaterThanEqual(minCornerSq, vec4(mincSq)));
  vec4 pA = is21 * (1.0 - f64);
  vec4 pB = is21 * (1.0 - f16);
  vec4 g4Edge = vec4(max(validG4.x * pB.y, validG4.y * pA.x),
                     max(validG4.y * pB.z, validG4.z * pA.y),
                     max(validG4.z * pB.w, validG4.w * pA.z),
                     max(validG4.w * pB.x, validG4.x * pA.w));
  if (dot(colEdge + g4Edge, vec4(1.0)) < 0.5) return res;
  bool sA = withinY255(nE, diagColor(vec2(-1.0, -1.0)), XBRZ_SAME_M);
  bool sI = withinY255(nE, diagColor(vec2( 1.0,  1.0)), XBRZ_SAME_M);
  if (sA == sI) return res;
  bool sC = withinY255(nE, diagColor(vec2( 1.0, -1.0)), XBRZ_SAME_M);
  bool sG = withinY255(nE, diagColor(vec2(-1.0,  1.0)), XBRZ_SAME_M);
  if (sC == sG) return res;
  vec4 l45 = is21 * (1.0 - f16) * (1.0 - f64);
  vec4 v45 = vec4(float(sG && sI && !sA && !sC), float(sA && sG && !sC && !sI),
                  float(sA && sC && !sG && !sI), float(sC && sI && !sA && !sG));
  vec4 actCol = colEdge * v45, actG4 = g4Edge * v45;
  if (dot(actCol + actG4, vec4(1.0)) < 0.5) return res;
  vec4 fixEdge = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec4 ek = cornerMask(k);
    float doC = dot(actCol, ek), doG = dot(actG4, ek);
    if (doC + doG < 0.5) continue;
    vec2 u = cardOff(k);
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
          res = mix(res, vec4(wordLine45(false)), m1);
          if (dot(st41, m2) > 0.5) fixEdge += ek;
        }
      }
      else if (dot(validG4, m2) > 0.5)
      {
        if (hasLine45(-s, -c2) && !cutsToCenter(u, c2 - 2.0 * u) && (dot(l45, m1) > 0.5 || hasLine45(s, -c1)))
        {
          res = mix(res, vec4(wordLine45(true)), m2);
          if (dot(sh41, m1) > 0.5) fixEdge += ek;
        }
      }
    }
  }
  fixEdge = min(fixEdge, vec4(1.0));
  res -= BIT_SHALLOW * (sh41 * fixEdge) + BIT_STEEP * (st41 * fixEdge.wxyz);
  return res;
}

// ---- Rule 48: lone shades along a stroke ----
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
  return !withinY255(Q, diagColor(a + s), XBRZ_SAME_M) && !withinY255(Q, diagColor(a - s), XBRZ_SAME_M)
      && !withinY255(Q, at3(2.0 * a + s), XBRZ_SAME_M) && !withinY255(Q, at3(2.0 * a), XBRZ_SAME_M)
      && !withinY255(Q, at3(2.0 * a - s), XBRZ_SAME_M);
}

// 45. the dark side of a mid-tone stroke's end
vec4 applyRule45(vec4 res, vec4 pairSq, vec4 minCornerSq, vec4 maxCornerSq)
{
  vec4 cw45 = cut4(res) * vec4(notEqual(BLEND(res), vec4(2.0))) * FLAG(res, BIT_LINE)
            * abs(FLAG(res, BIT_SHALLOW) - FLAG(res, BIT_STEEP))
            * vec4(equal(FLAG(res, BIT_LONG3) + FLAG(res, BIT_LONG4), vec4(0.0)))
            * vec4(greaterThanEqual(pairSq, vec4(mincSq)))
            * vec4(lessThan(maxCornerSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
            * vec4(greaterThanEqual(minCornerSq, vec4(mincSq)));
  if (dot(cw45, vec4(1.0)) <= 0.0) return res;
  vec4 cAny = cut4(res);
  vec4 sq = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec2 u = cardOff(k);
    if (sideSq(u) >= SQ255(XBRZ_SAME_M)) continue;
    vec2 s = vec2(-u.y, u.x);
    for (int j = 0; j < 2; j++)
    {
      vec2 sd = j == 0 ? s : -s;
      vec2 c = sd - u;
      vec4 m = vtxCorner(c);
      if (dot(cw45, m) < 0.5 || dot(cAny, vtxCorner(-sd - u)) > 0.5) continue;
      if (sideSq(-sd) < SQ255(80.0)) continue;
      if (distSqY(nE, diagColor(c)) >= SQ255(XBRZ_MATCH_EDGE)) continue;
      sq += m;
    }
  }
  return res * (1.0 - min(sq, vec4(1.0)));
}

// 48, 48b & 48c: 2:1 slope colliding along its long edge with a neighbor's 45-degree line,
// plus bright phantom wedge cut into a turning dark 2:1 outline
vec4 applyRule48(vec4 res, vec4 pairSq, float minSideSq, float maxSideSq, bool loneE)
{
  vec4 shM = FLAG(res, BIT_SHALLOW), stM = FLAG(res, BIT_STEEP);
  vec4 cw48 = cut4(res) * FLAG(res, BIT_LINE) * abs(shM - stM)
            * vec4(equal(FLAG(res, BIT_LONG3) + FLAG(res, BIT_LONG4), vec4(0.0)));
  if (dot(cw48, vec4(1.0)) > 0.5)
  {
    vec4 secM = FLAG(res, BIT_SEC);
    bool can48a = maxSideSq >= SQ255(XBRZ_SAME_M) && minSideSq < SQ255(XBRZ_SHADE48);
    vec4 dropS = vec4(0.0), dropT = vec4(0.0);
    for (int k = 0; k < 4; k++)
    {
      vec2 c = cornerOff(k);
      vec4 m = vtxCorner(c);
      if (dot(cw48, m) < 0.5) continue;
      bool sh = dot(shM, m) > 0.5;
      vec2 sOff, tOff;
      slope21Offsets(k, sh, sOff, tOff);
      vec4 oppM = vtxCorner(-c);
      vec4 rS = cardInfo(sOff);
      float sw = dot(rS, oppM);
      if (BLEND(sw) < 0.5 || dot(isLine45(rS), oppM) < 0.5) continue;
      bool swPaintsE = (FLAG(sw, BIT_SEC) > 0.5) == sh;
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
          if (BLEND(tw) > 0.5 && FLAG(tw, BIT_LINE) > 0.5 && (FLAG(tw, BIT_SHALLOW) > 0.5) == sh && (FLAG(tw, BIT_STEEP) > 0.5) != sh) continue;
        }
        float mw = dot(cardInfo(-tOff), m);
        if (BLEND(mw) > 0.5 && FLAG(mw, BIT_LINE) > 0.5 && (FLAG(mw, BIT_SHALLOW) > 0.5) == sh && (FLAG(mw, BIT_STEEP) > 0.5) != sh) continue;
        vec3 Fc = diagColor(sOff - tOff);
        if (min(min(distSqY(Fc, cardColor(sOff)), distSqY(Fc, cardColor(tOff))), distSqY(Fc, nE)) < SQ255(XBRZ_JUNC4)) continue;
      }
      if (sh) dropS += m; else dropT += m;
    }
    res -= BIT_SHALLOW * dropS + BIT_STEEP * dropT;
  }
  // 48c. bright phantom wedge cut into a turning dark 2:1 outline whose long side already cuts Pc's touching corner
  vec4 sumSq = vec4(sDSq + sBSq, sBSq + sFSq, sFSq + sHSq, sHSq + sDSq);
  vec4 cw48c = cut4(res) * (1.0 - FLAG(res, BIT_SHALLOW)) * (1.0 - FLAG(res, BIT_STEEP))
             * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))))
             * vec4(greaterThan(pairSq, sumSq));
  if (dot(cw48c, vec4(1.0)) > 0.5)
  {
    vec4 secM = FLAG(res, BIT_SEC);
    vec4 sq48c = vec4(0.0);
    for (int k = 0; k < 4; k++)
    {
      vec2 c = cornerOff(k);
      vec4 m = vtxCorner(c);
      if (dot(cw48c, m) < 0.5) continue;
      bool s1 = dot(secM, m) > 0.5;
      vec2 pOff, qOff;
      paintPairOffsets(k, c, s1, pOff, qOff);
      vec3 Pc = cardColor(pOff), Qc = cardColor(qOff);
      if (Qc.x > 0.25 || Qc.x >= nE.x - 0.05 || Pc.x <= nE.x + 0.05) continue;
      vec4 oppM = vtxCorner(-c);
      if (BLEND(dot(diagInfo(c), oppM)) > 0.5) continue;
      vec4 rP = cardInfo(pOff);
      float pw = dot(rP, m);
      if (BLEND(pw) < 0.5 || FLAG(pw, BIT_LINE) < 0.5 || BLEND(dot(rP, oppM)) > 0.5) continue;
      bool p21 = s1 ? (FLAG(pw, BIT_STEEP) > 0.5 && FLAG(pw, BIT_SHALLOW) < 0.5) : (FLAG(pw, BIT_SHALLOW) > 0.5 && FLAG(pw, BIT_STEEP) < 0.5);
      if (!p21) continue;
      if (BLEND(dot(cardInfo(qOff), oppM)) < 0.5) continue;
      if (distSqY(Qc, diagColor(c)) >= SQ255(XBRZ_SAME_M)) continue;
      sq48c += m;
    }
    res *= 1.0 - min(sq48c, vec4(1.0));
  }
  return res;
}

// 49. a 1-pixel diagonal bar ends even
vec4 applyRule49(vec4 res, vec4 res0, vec4 pairSq, float minSideSq, float maxSideSq)
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
      bool plug = dot(pairSq, me) < SQ255(XBRZ_SAME_M)
               && !withinY255(R1, C1, XBRZ_SAME_M) && !withinY255(R1, C2, XBRZ_SAME_M)
               && !withinY255(R2, C1, XBRZ_SAME_M) && !withinY255(R2, C2, XBRZ_SAME_M);
      bool ok1 = dot(pairSq, m1) < SQ255(100.0) || withinY255(C1, cS1, 100.0);
      bool ok2 = dot(pairSq, m2) < SQ255(100.0) || withinY255(C2, cS2, 100.0);
      if (!plug && ok1 && BLEND(dot(res, m1)) < 0.5 && !goesOn(s1)) res = mix(res, vec4(wordLine45(s1.x * s1.y <= 0.0)), m1);
      if (!plug && ok2 && BLEND(dot(res, m2)) < 0.5 && !goesOn(s2)) res = mix(res, vec4(wordLine45(s2.x * s2.y > 0.0)), m2);
      float lE = E.x, lA = cE.x, lS = 0.5 * (C1.x + C2.x);
      bool wrap49 = distSqY(C1, C2) >= SQ255(100.0) && dot(pairSq, me) >= SQ255(XBRZ_BAR49)
                 && (withinY255(R1, C2, XBRZ_SAME_M) || withinY255(R2, C1, XBRZ_SAME_M));
      if (!wrap49 && (BLEND(dot(res, me)) < 0.5 || FLAG(dot(res, me), BIT_LINE) < 0.5) && (lA - lS) * (lE - lS) <= 0.0 && !goesOn(e))
        res = mix(res, vec4(wordLine45(pickCornerSec(e))), me);
    }
  }
  vec4 c49 = cut4(res);
  if (maxSideSq >= SQ255(XBRZ_BAR49) && dot(c49, vec4(1.0)) > 0.0)
  {
    vec4 p15 = vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))));
    vec4 p60 = vec4(lessThan(pairSq, vec4(SQ255(XBRZ_BAR49))));
    vec4 sec49 = FLAG(res, BIT_SEC);
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
        vec2 n  = cardOff(q);
        vec3 En = q == 0 ? nB : (q == 1 ? nF : (q == 2 ? nH : nD));
        vec2 cn = q == 0 ? (p15.y > 0.5 ? vec2( 1.0,  1.0) : vec2(-1.0,  1.0))
                : q == 1 ? (p15.z > 0.5 ? vec2(-1.0,  1.0) : vec2(-1.0, -1.0))
                : q == 2 ? (p15.w > 0.5 ? vec2(-1.0, -1.0) : vec2( 1.0, -1.0))
                         : (p15.x > 0.5 ? vec2( 1.0, -1.0) : vec2( 1.0,  1.0));
        vec2 sideDir = cn + n;
        vec2 k = n - sideDir;
        vec4 mk = vtxCorner(k);
        float wk = dot(res, mk);
        bool hz = k.x * k.y > 0.0, sec = FLAG(wk, BIT_SEC) > 0.5;
        vec2 pk = (hz == sec) ? vec2(0.0, k.y) : vec2(k.x, 0.0);
        vec3 pCol = cardColor(pk);
        vec3 other = diagColor(n + sideDir);
        if (!withinY255(pCol, other, XBRZ_SAME_M) || withinY255(En, other, XBRZ_BAR49)) continue;
        if ((En.x - nE.x) * (En.x - other.x) <= 0.0) continue;
        vec3 cK = diagColor(k);
        if (withinY255(En, cK, XBRZ_BAR49)) continue;
        if (!(withinY255(nE, cK, 100.0) || sideSq(-sideDir) < SQ255(100.0))) continue;
        if (withinY255(En, at3(2.0 * n), XBRZ_BAR49)) continue;
        if (withinY255(En, at3(2.0 * n + sideDir), XBRZ_BAR49) || withinY255(En, at3(2.0 * n - sideDir), XBRZ_BAR49)) continue;
        vec2 iOff1 = n + vec2(cn.x, 0.0), iOff2 = n + vec2(0.0, cn.y);
        vec4 iW1 = (abs(iOff1.x) + abs(iOff1.y) < 0.5) ? res0 : diagInfo(iOff1);
        vec4 iW2 = (abs(iOff2.x) + abs(iOff2.y) < 0.5) ? res0 : diagInfo(iOff2);
        if (BLEND(dot(iW1, vtxCorner(vec2(-cn.x, cn.y)))) < 0.5 ||
            BLEND(dot(iW2, vtxCorner(vec2(cn.x, -cn.y)))) < 0.5) continue;
        if (withinY255(En, at3x3(n + vec2(2.0 * cn.x, 0.0)), XBRZ_BAR49)
            || withinY255(En, at3x3(n + vec2(0.0, 2.0 * cn.y)), XBRZ_BAR49)
            || withinY255(En, at3x3(n + vec2(2.0 * cn.x, cn.y)), XBRZ_BAR49)
            || withinY255(En, at3x3(n + vec2(cn.x, 2.0 * cn.y)), XBRZ_BAR49))
          continue;
        float d2Sq = distSqY(En, at3(n + 2.0 * cn));
        if (d2Sq < SQ255(XBRZ_BAR49) && d2Sq >= SQ255(XBRZ_SAME_M)) continue;
        res = mix(res, vec4(0.0), mk);
      }
    }
  }
  return res;
}
// ============================================================================================
// Match pass — 4-color junction, ramp, dot, and convex bevel rules (Rules 38-40, 42b)
// ============================================================================================

// ---- Rule 38: a pixel kept whole at a junction of four colors ----
bool keptWhole(vec2 n)
{
  if (dot(cut4(cardInfo(n)), vec4(1.0)) > 0.5) return false;
  vec4 w0 = W0_AT(n.x, n.y);
  return dot(cut4(w0) * vec4(lessThan(BLEND(w0), vec4(3.0))) * FLAG(w0, BIT_LINE), vec4(1.0)) > 0.5;
}
#define XBRZ_STEP38 0.5
vec4 junc4(vec4 res, vec4 pairSq, vec4 minCornerSq)
{
  vec4 jm = cut4(res) * vec4(lessThan(FLAG(res, BIT_SHALLOW) + FLAG(res, BIT_STEEP), vec4(0.5)))
          * vec4(greaterThan(minCornerSq, vec4(SQ255(XBRZ_JUNC4))))
          * vec4(greaterThan(pairSq, vec4(SQ255(XBRZ_JUNC4))));
  if (dot(jm, vec4(1.0)) < 0.5) return res;
  vec3 E = nE;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = cornerOff(i);
    vec4 m = vtxCorner(c);
    if (dot(jm, m) < 0.5) continue;
    vec3 Ch = c.x > 0.0 ? nF : nD, Cv = c.y > 0.0 ? nH : nB;
    vec3 X = diagColor(c);
    float lo5Sq = min(min(c.x > 0.0 ? sFSq : sDSq, c.y > 0.0 ? sHSq : sBSq),
                      min(distSqY(E, X), min(distSqY(Ch, X), distSqY(Cv, X))));
    if (lo5Sq <= SQ255(XBRZ_JUNC4) || dot(pairSq, m) < min((XBRZ_STEP38 * XBRZ_STEP38) * lo5Sq, SQ255(50.0))) continue;
    if (BLEND(dot(diagInfo(c), vtxCorner(-c))) < 0.5) continue;
    if (!keptWhole(vec2(c.x, 0.0)) && !keptWhole(vec2(0.0, c.y))) continue;
    if ((withinY255(diagColor(vec2(c.x, -c.y)), Ch, XBRZ_SAME_M) && withinY255(toYCbCr(P(0.0, 2.0 * c.y)), Cv, XBRZ_SAME_M))
        || (withinY255(diagColor(vec2(-c.x, c.y)), Cv, XBRZ_SAME_M) && withinY255(toYCbCr(P(2.0 * c.x, 0.0)), Ch, XBRZ_SAME_M)))
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
    vec2 c = cornerOff(i);
    vec4 m = vtxCorner(c);
    if (dot(m39, m) < 0.5) continue;
    vec3 Nh = c.x > 0.0 ? nF : nD, Nv = c.y > 0.0 ? nH : nB;
    vec3 X = diagColor(c);
    float xdSq = min(distSqY(X, Nh), min(distSqY(X, Nv), distSqY(X, E)));
    if (xdSq <= SQ255(20.0)) continue;
    float wc = dot(res, m);
    bool tie = xdSq > SQ255(XBRZ_FAR39) && FLAG(wc, BIT_SHALLOW) + FLAG(wc, BIT_STEEP) < 0.5;
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
  vec3 q = at3x3(n + vec2(-1.0, 0.0));
  if (withinY255(c, q, XBRZ_DOT40)) return false;
  bool qk = withinY255(q, K, XBRZ_DOTK40);
  if (!qk && q.x <= lk) return false;
  float nc = 0.0;
  vec3 u0 = q, u1 = q, u2 = q;
  bool prev = qk;
  for (int i = 0; i < 8; i++)
  {
    vec3 p = i == 7 ? q : at3x3(n + r[i]);
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
    float d8Sq = min(min(distSqY(nE, diagColor(vec2(-1.0, -1.0))), distSqY(nE, diagColor(vec2(1.0, -1.0)))),
                     min(distSqY(nE, diagColor(vec2(-1.0,  1.0))), distSqY(nE, diagColor(vec2(1.0,  1.0)))));
    loneDot = d8Sq >= SQ255(XBRZ_DOT40);
  }
  for (int i = 0; i < 4; i++)
  {
    vec2 c = cornerOff(i);
    vec4 m = vtxCorner(c);
    float w = dot(res, m);
    if (BLEND(w) < 0.5) continue;
    bool horiz = (c.x * c.y > 0.0) != (FLAG(w, BIT_SEC) > 0.5);
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
      res = mix(res, vec4(3.0 + BIT_SEC * FLAG(w, BIT_SEC)), m);
  }
  return res;
}

// ---- Rule 42b: convex corner bevel painting a shared darker background beside an adjacent brighter wall ----
vec4 applyRule42b(vec4 res, vec4 pairSq, vec4 minCornerSq)
{
  vec4 uSq42b = vec4(nD.x < nB.x ? sFSq : sHSq, nF.x < nB.x ? sDSq : sHSq,
                     nF.x < nH.x ? sDSq : sBSq, nD.x < nH.x ? sFSq : sBSq);
  vec4 cMinL = min(vec4(nD.x, nF.x, nF.x, nD.x), vec4(nB.x, nB.x, nH.x, nH.x));
  vec4 cMaxL = max(vec4(nD.x, nF.x, nF.x, nD.x), vec4(nB.x, nB.x, nH.x, nH.x));
  vec4 m42b = (1.0 - cut4(res))
            * vec4(greaterThanEqual(minCornerSq, vec4(mincSq)))
            * vec4(greaterThanEqual(pairSq, vec4(mincSq)))
            * vec4(lessThan(uSq42b, vec4(SQ255(XBRZ_SAME_M))))
            * vec4(lessThan(cMinL, vec4(nE.x - 0.05)))
            * vec4(lessThan(vec4(nE.x), cMaxL - 0.05));
  if (dot(m42b, vec4(1.0)) <= 0.5) return res;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = cornerOff(i);
    vec4 m = vtxCorner(c);
    if (dot(m42b, m) < 0.5) continue;
    vec3 Nh = c.x > 0.0 ? nF : nD, Nv = c.y > 0.0 ? nH : nB;
    bool alongX = Nh.x < Nv.x;
    vec2 u = alongX ? vec2(c.x, 0.0) : vec2(0.0, c.y), s = c - u;
    vec3 U = alongX ? Nh : Nv, S = alongX ? Nv : Nh;
    if (!withinY255(nE, diagColor(u - s), XBRZ_SAME_M) || !withinY255(S, diagColor(c), XBRZ_SAME_M) || !withinY255(U, diagColor(s - u), XBRZ_SAME_M)) continue;
    vec4 rU = cardInfo(u);
    if (dot(cut4(rU) * isLine45(rU), vtxCorner(-c)) < 0.5) continue;
    if (BLEND(dot(rU, vtxCorner(s - u))) > 0.5 || BLEND(dot(cardInfo(s), vtxCorner(u - s))) > 0.5) continue;
    res = mix(res, vec4(wordLine45(vtxSec(c, u))), m);
  }
  return res;
}
// ============================================================================================
// Match pass — Rule 26 family (matching corners, junction pruning, 2:1 downgrade/upgrade, dark walls)
// ============================================================================================

// Rule 26 (lost cut rescue + gap fill + Rule 43 dome + clean 45-deg continuation)
vec4 applyRule26Lost(vec4 res, vec4 w0, vec4 aW0, vec4 pairSq, vec4 minCornerSq, vec4 maxCornerSq)
{
  vec4 lost = aW0 * (1.0 - cut4(res));
  if (dot(lost, vec4(1.0)) <= 0.0) return res;
  vec4 lostStrong = lost * vec4(greaterThan(maxCornerSq, vec4(SQ255(XBRZ_MATCH_EDGE))));
  vec4 fix = vec4(0.0);
  if (dot(lostStrong, vec4(1.0)) > 0.0)
  {
    ensureDiagInfo();
    vec4 iA = gIA, iC = gIC, iI = gII, iG = gIG;
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
      vec4 onRamp26 = triLt4(minCornerSq, pairSq, 1.12 * 1.12, maxCornerSq);
      pairCloser *= 1.0 - junc26 * (1.0 - onRamp26);
    }
    fix = max(needGap * wrapN, lostStrong * pairCloser * part * l45 * (1.0 - FLAG(w0, BIT_LINE)));
  }
  vec4 far43 = vec4(greaterThanEqual(minCornerSq, vec4(mincSq)))
             * vec4(lessThan(minCornerSq.zwxy, vec4(SQ255(XBRZ_SAME_M))))
             * vec4(greaterThanEqual(pairSq, vec4(mincSq)));
  if (dot(lost, far43) > 0.0) fix = max(fix, domes43(lost * far43));
  if (dot(fix, vec4(1.0)) > 0.0)
  {
    vec4 noR9 = 1.0 - FLAG(w0, BIT_TONE);
    vec4 back = 1.0 + BIT_LINE * FLAG(w0, BIT_LINE) + BIT_SEC * FLAG(w0, BIT_SEC)
              + noR9 * (BIT_SHALLOW * FLAG(w0, BIT_SHALLOW) + BIT_STEEP * FLAG(w0, BIT_STEEP));
    res = mix(res, back, fix);
  }
  // Rescue a lost pass-0 diagonal line as a clean 45 deg line when P and Q are closer to each other than to E
  // (pair < minSide, minSide >= 40) and P's opposite corner already draws a live 45 deg line painting E
  vec4 cont45 = lost * (1.0 - cut4(res)) * FLAG(w0, BIT_LINE) * vec4(lessThan(pairSq, minCornerSq))
              * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_MATCH_EDGE))));
  if (dot(cont45, vec4(1.0)) > 0.5)
  {
    vec4 w0Sec = FLAG(w0, BIT_SEC);
    ensureCardInfo();
    vec4 iB = gIB, iD = gID, iF = gIF, iH = gIH;
    vec4 pOpp = mix(vec4(iD.z, iB.w, iF.x, iH.y), vec4(iB.z, iF.w, iH.x, iD.y), w0Sec);
    vec4 base45 = cont45 * cut4(pOpp) * isLine45(pOpp);
    vec4 secOk = vec4(equal(FLAG(pOpp, BIT_SEC), w0Sec));
    vec4 needTie = base45 * (1.0 - secOk);
    if (dot(needTie, vec4(1.0)) > 0.5)
    {
      if (needTie.x > 0.5 && distSqY(nE, diagColor(w0Sec.x > 0.5 ? vec2( 1.0, -1.0) : vec2(-1.0,  1.0))) < SQ255(XBRZ_SAME_M)) secOk.x = 1.0;
      if (needTie.y > 0.5 && distSqY(nE, diagColor(w0Sec.y > 0.5 ? vec2( 1.0,  1.0) : vec2(-1.0, -1.0))) < SQ255(XBRZ_SAME_M)) secOk.y = 1.0;
      if (needTie.z > 0.5 && distSqY(nE, diagColor(w0Sec.z > 0.5 ? vec2(-1.0,  1.0) : vec2( 1.0, -1.0))) < SQ255(XBRZ_SAME_M)) secOk.z = 1.0;
      if (needTie.w > 0.5 && distSqY(nE, diagColor(w0Sec.w > 0.5 ? vec2(-1.0, -1.0) : vec2( 1.0,  1.0))) < SQ255(XBRZ_SAME_M)) secOk.w = 1.0;
    }
    vec4 fix45 = base45 * secOk;
    if (dot(fix45, vec4(1.0)) > 0.5)
      res = mix(res, 1.0 + BIT_LINE + BIT_SEC * w0Sec, fix45);
  }
  return res;
}

// Rule 26b: drop uncontinued junction cuts after resolve (orphan bevels, 4-color nb1, obtuse off-ramp,
// lone off-ramp 3-color triangles, and phantom pass-0 diagonal run survivors)
vec4 applyRule26b(vec4 res, vec4 pairSq, vec4 minCornerSq, vec4 maxCornerSq, float minSideSq)
{
  vec4 nb1 = vec4(equal(BLEND(res), vec4(1.0))) * (1.0 - FLAG(res, BIT_LINE))
           * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
  if (dot(nb1, vec4(1.0)) > 0.5)
  {
    ensureDiagInfo();
    vec4 dA = gIA, dC = gIC, dI = gII, dG = gIG;
    vec4 oInfo = vec4(dA.z, dC.w, dI.x, dG.y);
    vec4 oR = cut4(oInfo);
    vec4 nb1Orph = nb1 * vec4(greaterThan(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE)))) * (1.0 - oR);
    vec4 drop = vec4(0.0);
    if (dot(nb1Orph, vec4(1.0)) > 0.5)
    {
      vec4 oW0 = vec4(
        nb1Orph.x > 0.5 ? activeCutOf(W0_AT(-1.0, -1.0)).z : 0.0,
        nb1Orph.y > 0.5 ? activeCutOf(W0_AT( 1.0, -1.0)).w : 0.0,
        nb1Orph.z > 0.5 ? activeCutOf(W0_AT( 1.0,  1.0)).x : 0.0,
        nb1Orph.w > 0.5 ? activeCutOf(W0_AT(-1.0,  1.0)).y : 0.0);
      drop = nb1Orph * oW0;
    }
    vec4 diffSec = nb1 * oR * (1.0 - abs(FLAG(res, BIT_SEC) - FLAG(oInfo, BIT_SEC)));
    vec4 candB = diffSec * FLAG(oInfo, BIT_LINE);
    vec4 candB2 = diffSec * vec4(equal(BLEND(oInfo), vec4(1.0))) * (1.0 - FLAG(oInfo, BIT_LINE))
                * vec4(greaterThanEqual(minCornerSq, vec4(mincSq)));
    vec4 candB2ok = vec4(0.0);
    if (dot(candB2, vec4(1.0)) > 0.5)
    {
      vec4 oEdgeOk = vec4(0.0);
      if (candB2.x > 0.5) { vec3 Oc = diagColor(vec2(-1.0, -1.0)); oEdgeOk.x = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nB), distSqY(Oc, nD)) >= mincSq); }
      if (candB2.y > 0.5) { vec3 Oc = diagColor(vec2( 1.0, -1.0)); oEdgeOk.y = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nB), distSqY(Oc, nF)) >= mincSq); }
      if (candB2.z > 0.5) { vec3 Oc = diagColor(vec2( 1.0,  1.0)); oEdgeOk.z = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nF), distSqY(Oc, nH)) >= mincSq); }
      if (candB2.w > 0.5) { vec3 Oc = diagColor(vec2(-1.0,  1.0)); oEdgeOk.w = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nH), distSqY(Oc, nD)) >= mincSq); }
      candB2ok = candB2 * oEdgeOk;
    }
    vec4 obt26 = nb1 * oR * FLAG(oInfo, BIT_LINE)
               * vec4(greaterThan(pairSq, max(vec4(SQ255(XBRZ_MATCH_EDGE)), maxCornerSq)))
               * vec4(greaterThanEqual(minCornerSq, vec4(mincSq)));
    if (dot(obt26, vec4(1.0)) > 0.5)
      obt26 *= triGe4(minCornerSq, maxCornerSq, 1.12 * 1.12, pairSq);
    vec4 loneNb1 = nb1 * (1.0 - oR) * float(dot(cut4(res), vec4(1.0)) < 1.5)
                 * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_JUNC4))));
    vec4 isoOff = vec4(0.0), isoBar = vec4(0.0);
    if (dot(loneNb1, vec4(1.0)) > 0.5)
    {
      isoOff = loneNb1 * triGe4(minCornerSq, pairSq, 1.25 * 1.25, maxCornerSq);
      isoBar = loneNb1 * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
             * triGe4(minCornerSq, pairSq, 1.12 * 1.12, maxCornerSq);
    }
    if (dot(candB + candB2ok + obt26 + isoOff + isoBar, vec4(1.0)) > 0.5)
    {
      ensureCardInfo();
      vec4 iB = gIB, iD = gID, iF = gIF, iH = gIH;
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
          max(cB.z * max(FLAG(iB.z, BIT_SEC), sEC), cD.z * max(1.0 - FLAG(iD.z, BIT_SEC), sEG)),
          max(cB.w * max(1.0 - FLAG(iB.w, BIT_SEC), sEA), cF.w * max(FLAG(iF.w, BIT_SEC), sEI)),
          max(cF.x * max(1.0 - FLAG(iF.x, BIT_SEC), sEC), cH.x * max(FLAG(iH.x, BIT_SEC), sEG)),
          max(cH.y * max(1.0 - FLAG(iH.y, BIT_SEC), sEI), cD.y * max(FLAG(iD.y, BIT_SEC), sEA)));
        drop = max(drop, candB2ok * (1.0 - edgeCutE));
      }
      if (dot(obt26 + isoOff + isoBar, vec4(1.0)) > 0.5)
      {
        vec4 uC = vec4(float(dot(cB, vec4(1.0)) < 0.5), float(dot(cD, vec4(1.0)) < 0.5),
                       float(dot(cF, vec4(1.0)) < 0.5), float(dot(cH, vec4(1.0)) < 0.5));
        vec4 secM = FLAG(res, BIT_SEC);
        vec4 qUncut = mix(vec4(uC.x, uC.z, uC.w, uC.y), vec4(uC.y, uC.x, uC.z, uC.w), secM);
        drop = max(drop, obt26 * qUncut);
        vec4 isoWall = vec4(0.0);
        if (dot(isoOff, vec4(1.0)) > 0.5)
        {
          vec4 dUncut = vec4(float(dot(cut4(dA), vec4(1.0)) < 0.5), float(dot(cut4(dC), vec4(1.0)) < 0.5),
                             float(dot(cut4(dI), vec4(1.0)) < 0.5), float(dot(cut4(dG), vec4(1.0)) < 0.5));
          vec4 isoBase = isoOff * (1.0 - edgeCut) * qUncut;
          drop = max(drop, isoBase * dUncut);
          isoWall = isoBase * (1.0 - dUncut) * float(minSideSq >= SQ255(XBRZ_SAME_M));
        }
        isoBar *= mix(vec4(uC.y, uC.x, uC.z, uC.w), vec4(uC.x, uC.z, uC.w, uC.y), secM);
        if (dot(isoWall + isoBar, vec4(1.0)) > 0.5)
        {
          for (int k = 0; k < 4; k++)
          {
            vec2 c = cornerOff(k);
            vec4 m = vtxCorner(c);
            float doW = dot(isoWall, m), doB = dot(isoBar, m);
            if (doW + doB < 0.5) continue;
            vec2 pOff, qOff;
            paintPairOffsets(k, c, dot(secM, m) > 0.5, pOff, qOff);
            vec3 dc = diagColor(c);
            if (doW > 0.5)
            {
              vec4 rPc = pOff.y < -0.5 ? iB : (pOff.y > 0.5 ? iH : (pOff.x < 0.0 ? iD : iF));
              if (dot(cut4(rPc) * FLAG(rPc, BIT_LINE), vec4(1.0)) < 0.5 && withinY255(cardColor(qOff), dc, XBRZ_SAME_M))
                drop = max(drop, m);
            }
            if (doB > 0.5 && withinY255(cardColor(pOff), dc, XBRZ_SAME_M))
              drop = max(drop, m);
          }
        }
      }
    }
    res *= 1.0 - drop;
  }
  vec4 oppLn26 = cut4(res.zwxy) * FLAG(res.zwxy, BIT_LINE);
  vec4 ph26 = cut4(res) * (1.0 - FLAG(res, BIT_SHALLOW)) * (1.0 - FLAG(res, BIT_STEEP)) * (1.0 - oppLn26)
            * vec4(greaterThan(pairSq, max(vec4(SQ255(XBRZ_MATCH_EDGE)), maxCornerSq)))
            * vec4(greaterThanEqual(minCornerSq, 0.0625 * pairSq));
  if (dot(ph26, vec4(1.0)) > 0.5)
  {
    ph26 *= triGe4(minCornerSq, maxCornerSq, 1.12 * 1.12, pairSq);
    if (dot(ph26, vec4(1.0)) > 0.5)
    {
      ensureDiagInfo();
      vec4 iA = gIA, iC = gIC, iI = gII, iG = gIG;
      vec4 oR = vec4(cut4(iA).z, cut4(iC).w, cut4(iI).x, cut4(iG).y);
      vec4 runLive = vec4(max(cut4(iC).x, cut4(iG).x), max(cut4(iA).y, cut4(iI).y),
                          max(cut4(iC).z, cut4(iG).z), max(cut4(iA).w, cut4(iI).w));
      ph26 *= (1.0 - oR) * (1.0 - runLive);
      if (dot(ph26, vec4(1.0)) > 0.5)
      {
        vec4 wA = (ph26.y + ph26.w > 0.5) ? activeCutOf(W0_AT(-1.0, -1.0)) : vec4(0.0);
        vec4 wC = (ph26.x + ph26.z > 0.5) ? activeCutOf(W0_AT( 1.0, -1.0)) : vec4(0.0);
        vec4 wI = (ph26.y + ph26.w > 0.5) ? activeCutOf(W0_AT( 1.0,  1.0)) : vec4(0.0);
        vec4 wG = (ph26.x + ph26.z > 0.5) ? activeCutOf(W0_AT(-1.0,  1.0)) : vec4(0.0);
        vec4 hadRunP0 = vec4(max(wC.x, wG.x), max(wA.y, wI.y), max(wC.z, wG.z), max(wA.w, wI.w));
        res *= 1.0 - ph26 * hadRunP0;
      }
    }
  }
  return res;
}

// Rule 26d: downgrade a 2:1 shallow/steep line to 45 deg when extended neighbor N has its adjacent corner
// cut away at 45 deg (cases A, B, C, D)
vec4 applyRule26d(vec4 res, vec4 pairSq, vec4 minCornerSq)
{
  vec4 sh26 = FLAG(res, BIT_SHALLOW), st26 = FLAG(res, BIT_STEEP), sec26 = FLAG(res, BIT_SEC);
  vec4 ln21Base = cut4(res) * FLAG(res, BIT_LINE) * abs(sh26 - st26)
                * (1.0 - FLAG(res, BIT_LONG3)) * (1.0 - FLAG(res, BIT_LONG4));
  vec4 ln21A = ln21Base * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))));
  vec4 ln21Want = ln21Base * vec4(equal(sec26, st26));
  vec4 ln21B = ln21Want * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
  vec4 ln21C = ln21Want * vec4(greaterThanEqual(pairSq, vec4(mincSq)))
             * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_JUNC4))));
  vec4 ln21D = ln21Base * cut4(res.zwxy) * isLine45(res.zwxy);
  vec4 ln21 = max(max(ln21A, ln21B), max(ln21C, ln21D));
  if (dot(ln21, vec4(1.0)) <= 0.5) return res;
  for (int k = 0; k < 4; k++)
  {
    vec4 m = cornerMask(k);
    if (dot(ln21, m) < 0.5) continue;
    bool isSh = dot(sh26, m) > 0.5;
    vec2 nbrOff, othOff;
    slope21Offsets(k, isSh, nbrOff, othOff);
    float nw = dot(cardInfo(nbrOff), m.zwxy);
    if (BLEND(nw) < 0.5 || FLAG(nw, BIT_LINE) < 0.5 || FLAG(nw, BIT_SHALLOW) > 0.5 || FLAG(nw, BIT_STEEP) > 0.5) continue;
    float wantSec = isSh ? 0.0 : 1.0;
    float nwSec = FLAG(nw, BIT_SEC);
    vec2 extOff = nbrOff - othOff;
    vec3 Nc = cardColor(nbrOff), Xc = diagColor(extOff);
    float dNXSq = distSqY(Nc, Xc), dEXSq = distSqY(nE, Xc);
    bool ok26d = false;
    if (dot(ln21C, m) > 0.5
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
             && abs(nwSec - wantSec) < 0.5)
    {
      vec3 Oc = cardColor(othOff);
      if (dNXSq >= SQ255(XBRZ_JUNC4) && distSqY(Oc, Xc) >= mincSq
          && withinY255(nE, cardColor(-othOff), XBRZ_SAME_M)
          && dot(cut4(cardInfo(-othOff)), vec4(1.0)) < 0.5)
        ok26d = true;
    }
    if (!ok26d && dot(ln21D, m) > 0.5
        && FLAG(nw, BIT_LONG3) + FLAG(nw, BIT_LONG4) < 0.5
        && abs(nwSec - wantSec) < 0.5
        && dEXSq >= SQ255(XBRZ_SAME_M))
    {
      if (distSqY(cardColor(othOff), Xc) >= mincSq)
      {
        vec4 rO = cardInfo(othOff), rD = diagInfo(nbrOff + othOff);
        if (dot(cut4(rO) * isLine45(rO) + cut4(rD) * isLine45(rD), m.zwxy) > 0.5)
        {
          float xw = dot(diagInfo(extOff), m.zwxy);
          if (FLAG(xw, BIT_SHALLOW) + FLAG(xw, BIT_STEEP) < 0.5)
            ok26d = true;
        }
      }
    }
    if (ok26d)
      res -= m * (isSh ? BIT_SHALLOW : BIT_STEEP);
  }
  return res;
}

// Rules 26e & 26f (shared 45-degree line gate):
// - 26e: drop a 45 deg line cutting a straight 2px light sclera E tucked inside two orthogonal uncut dark bars
// - 26f: upgrade a 45 deg line on a high-contrast (>= 100) gradient edge to 2:1 when partner at extOff matches
vec4 applyRule26ef(vec4 res, vec4 pairSq, vec4 minCornerSq)
{
  vec4 l45_26 = cut4(res) * isLine45(res);
  vec4 eyeC = l45_26 * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))))
            * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(60.0))));
  vec4 ln45 = l45_26 * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(100.0))))
            * vec4(lessThan(pairSq, vec4(SQ255(45.0))));
  if (dot(eyeC + ln45, vec4(1.0)) <= 0.5) return res;
  vec4 secM = FLAG(res, BIT_SEC);
  vec4 dropEye = vec4(0.0);
  vec4 add26f = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec2 c = cornerOff(k);
    vec4 m = vtxCorner(c);
    bool dropped = false;
    if (dot(eyeC, m) > 0.5)
    {
      vec2 pOff, qOff;
      paintPairOffsets(k, c, dot(secM, m) > 0.5, pOff, qOff);
      vec3 Pc = cardColor(pOff), Qc = cardColor(qOff);
      if (max(Pc.x, Qc.x) <= nE.x - 0.15
          && withinY255(nE, cardColor(-qOff), XBRZ_SAME_M) && !withinY255(nE, cardColor(-pOff), XBRZ_SAME_M)
          && withinY255(Qc, diagColor(c), XBRZ_SAME_M) && withinY255(Pc, diagColor(pOff - qOff), XBRZ_SAME_M)
          && dot(cut4(cardInfo(pOff)), vec4(1.0)) < 0.5
          && dot(cut4(cardInfo(qOff)), vec4(1.0)) < 0.5
          && dot(cut4(diagInfo(c)), vec4(1.0)) < 0.5)
      {
        dropEye += m;
        dropped = true;
      }
    }
    if (!dropped && dot(ln45, m) > 0.5)
    {
      float addBit = 0.0;
      for (int dir = 0; dir < 2; dir++)
      {
        bool isSh = (dir == 0);
        vec2 nbrOff, othOff;
        slope21Offsets(k, isSh, nbrOff, othOff);
        vec2 extOff = nbrOff - othOff;
        vec2 runOff = othOff - nbrOff;
        if (!withinY255(nE, cardColor(-othOff), XBRZ_SAME_M)) continue;
        if (!withinY255(nE, diagColor(runOff), XBRZ_SAME_M)) continue;
        vec3 Nc = cardColor(nbrOff), Xc = diagColor(extOff);
        if (distSqY(Nc, Xc) >= SQ255(45.0) || distSqY(nE, Xc) < SQ255(100.0)) continue;
        float xw = dot(diagInfo(extOff), m.zwxy);
        float wantBit = isSh ? BIT_SHALLOW : BIT_STEEP;
        float otherBit = isSh ? BIT_STEEP : BIT_SHALLOW;
        if (BLEND(xw) > 0.5 && FLAG(xw, BIT_LINE) > 0.5 && FLAG(xw, wantBit) > 0.5 && FLAG(xw, otherBit) < 0.5
            && FLAG(xw, BIT_LONG3) < 0.5 && FLAG(xw, BIT_LONG4) < 0.5)
          addBit = addBit > 0.5 ? -1.0 : wantBit;
      }
      if (addBit > 0.5) add26f += m * addBit;
    }
  }
  return res * (1.0 - min(dropEye, vec4(1.0))) + add26f;
}

// Rule 26c (unified dark-outline flat-wall guard):
// - non-line: lone near-black (<= 0.20) b1 bevel leaking a darker uncut Pc against a brighter 3px wall Qc
// - line: dark low-chroma outline leaking a lighter off-ramp color across a > 100 YCbCr flat wall
vec4 applyRule26c(vec4 res, vec4 pairSq)
{
  vec4 isL26 = FLAG(res, BIT_LINE);
  vec4 wallNb1 = float(nE.x <= 0.20) * vec4(equal(BLEND(res), vec4(1.0))) * (1.0 - isL26)
               * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
  vec4 wallLn  = float(dot(nE.yz, nE.yz) < SQ255(50.0)) * cut4(res) * isL26
               * vec4(greaterThan(pairSq, vec4(SQ255(100.0))));
  vec4 wallAll = max(wallNb1, wallLn);
  if (dot(wallAll, vec4(1.0)) <= 0.5) return res;
  vec4 secM = FLAG(res, BIT_SEC);
  vec4 sqW = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec2 c = cornerOff(k);
    vec4 m = vtxCorner(c);
    if (dot(wallAll, m) < 0.5) continue;
    vec4 oppM = vtxCorner(-c);
    if (BLEND(dot(diagInfo(c), oppM)) > 0.5) continue;
    vec2 pOff, qOff;
    paintPairOffsets(k, c, dot(secM, m) > 0.5, pOff, qOff);
    vec3 Pc = cardColor(pOff), Qc = cardColor(qOff);
    if (dot(wallNb1, m) > 0.5)
    {
      float aw = dot(res, vtxCorner(pOff - qOff));
      if (BLEND(aw) < 0.5 || FLAG(aw, BIT_LINE) < 0.5) continue;
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
      if (BLEND(qw) < 0.5 || FLAG(qw, BIT_LINE) < 0.5) continue;
      vec4 rPc = cardInfo(pOff);
      if (dot(cut4(rPc) * FLAG(rPc, BIT_LINE), vec4(1.0)) > 0.5) continue;
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
  return res * (1.0 - min(sqW, vec4(1.0)));
}
// ============================================================================================
// Match pass — Rule 28 post-resolve completion & Rule 28b
// ============================================================================================
// - catch crossing 2:1 color swaps missed in resolve when one side was R2-blocked,
// - flip off-ramp 2:1 color when the neighbor across the shared edge draws the matching opposite 2:1 line in Q's color,
// - 28b: unflip a Rule-18 dark 2:1 line (painting O along N, d(E,N) < min(60, d(E,O)), pair >= 40) back to N
vec4 applyRule28Match(vec4 res, vec4 pairSq)
{
  vec4 sh28 = FLAG(res, BIT_SHALLOW), st28 = FLAG(res, BIT_STEEP), sec28 = FLAG(res, BIT_SEC);
  vec4 base28 = cut4(res) * FLAG(res, BIT_LINE) * (1.0 - FLAG(res, BIT_LONG3)) * (1.0 - FLAG(res, BIT_LONG4));
  vec4 p28 = base28 * mix(st28, sh28, sec28);
  if (dot(p28, vec4(1.0)) > 0.5)
  {
    ensureCardInfo();
    vec4 iB = gIB, iD = gID, iF = gIF, iH = gIH;
    vec4 nW = mix(vec4(iD.z, iB.w, iF.x, iH.y), vec4(iB.z, iF.w, iH.x, iD.y), sec28);
    vec4 pair28 = p28 * cut4(nW) * FLAG(nW, BIT_LINE) * (1.0 - FLAG(nW, BIT_LONG3)) * (1.0 - FLAG(nW, BIT_LONG4))
                * vec4(equal(FLAG(nW, BIT_SEC), sec28)) * mix(FLAG(nW, BIT_STEEP), FLAG(nW, BIT_SHALLOW), sec28);
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
      res *= 1.0 - pair28 * whole28Mask(hE, hN, sec28, nE, nB, nD, nF, nH);
    }
    vec4 opp28 = p28 * abs(sh28 - st28)
               * cut4(nW) * FLAG(nW, BIT_LINE) * (1.0 - FLAG(nW, BIT_LONG3)) * (1.0 - FLAG(nW, BIT_LONG4))
               * abs(FLAG(nW, BIT_SHALLOW) - FLAG(nW, BIT_STEEP))
               * vec4(notEqual(FLAG(nW, BIT_SEC), sec28)) * mix(FLAG(nW, BIT_STEEP), FLAG(nW, BIT_SHALLOW), sec28)
               * vec4(greaterThanEqual(pairSq, vec4(mincSq)));
    if (dot(opp28, vec4(1.0)) > 0.5)
    {
      vec4 flip28 = vec4(0.0);
      for (int k = 0; k < 4; k++)
      {
        vec4 m = cornerMask(k);
        if (dot(opp28, m) < 0.5) continue;
        bool isSh = dot(sec28, m) > 0.5;
        vec2 nbrOff, othOff;
        slope21Offsets(k, isSh, nbrOff, othOff);
        vec2 extOff = nbrOff - othOff;
        if (withinY255(cardColor(othOff), diagColor(extOff), XBRZ_SAME_M)
            && triGt(sideSq(nbrOff), dot(pairSq, m), 1.2 * 1.2, sideSq(othOff)))
          flip28 += m * (isSh ? -BIT_SEC : BIT_SEC);
      }
      res += flip28;
    }
  }
  vec4 sh18 = FLAG(res, BIT_SHALLOW), st18 = FLAG(res, BIT_STEEP), sec18 = FLAG(res, BIT_SEC);
  vec4 dN18Sq = mix(vec4(sDSq, sBSq, sFSq, sHSq), vec4(sBSq, sFSq, sHSq, sDSq), sh18);
  vec4 dO18Sq = mix(vec4(sBSq, sFSq, sHSq, sDSq), vec4(sDSq, sBSq, sFSq, sHSq), sh18);
  vec4 u18 = cut4(res) * FLAG(res, BIT_LINE) * abs(sh18 - st18)
           * (1.0 - FLAG(res, BIT_LONG3)) * (1.0 - FLAG(res, BIT_LONG4))
           * mix(sh18, st18, sec18)
           * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
           * vec4(lessThan(dN18Sq, vec4(SQ255(60.0))))
           * vec4(lessThan(dN18Sq, dO18Sq - TIE_EPS));
  if (dot(u18, vec4(1.0)) > 0.5)
  {
    vec4 unflip = vec4(0.0);
    for (int k = 0; k < 4; k++)
    {
      vec4 m = cornerMask(k);
      if (dot(u18, m) < 0.5) continue;
      bool isSh = dot(sh18, m) > 0.5;
      vec2 nbrOff, othOff;
      slope21Offsets(k, isSh, nbrOff, othOff);
      if (BLEND(dot(cardInfo(nbrOff), m.zwxy)) > 0.5) continue;
      vec2 extOff = nbrOff - othOff;
      if (!withinY255(cardColor(othOff), diagColor(extOff), XBRZ_SAME_M)) continue;
      float xw = dot(diagInfo(extOff), vtxCorner(-extOff));
      if (BLEND(xw) > 0.5 && FLAG(xw, BIT_LINE) > 0.5)
        unflip += m * (isSh ? BIT_SEC : -BIT_SEC);
    }
    res += unflip;
  }
  return res;
}
void main()
{
#if __VERSION__ >= 300
  gSrcMaxI = ivec2(InputSize) - ivec2(1);
  gOrigMaxI = ivec2(ORIG_INPUT_SIZE) - ivec2(1);
  gIpx = clamp(ivec2(floor(vTexCoord * TextureSize)), ivec2(0), gSrcMaxI);
#else
  gSrcInv = 1.0 / TextureSize;
  gSrcMax = (InputSize - 0.5) * gSrcInv;
  gOrigInv = 1.0 / PassPrev3TextureSize;
  gOrigMax = (ORIG_INPUT_SIZE - 0.5) * gOrigInv;
  gP0Inv = 1.0 / PassPrev2TextureSize;
  gP0Max = (InputSize - 0.5) * gP0Inv;
  vec2 pos = fract(vTexCoord * TextureSize) - vec2(0.5, 0.5);
  coord = vTexCoord - pos * gSrcInv;
  ocoord = coord * TextureSize * gOrigInv;
  c0 = coord * TextureSize * gP0Inv;
#endif
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
  vec4 res0 = res;
  vec4 w0 = floor(rawW0 * 255.0 + 0.5);
  vec4 aW0 = activeCutOf(w0);
  bool noCuts = dot(cut4(res) + aW0, vec4(1.0)) == 0.0;

  // Fast path: when neither pass 0 nor resolve cuts any corner, only rules 42, 44 and 49 can cut one,
  // and all three need contrast >= min(XBRZ_MINC, XBRZ_BAR49) on both axes (D or F, and B or H)
  mincSq = SQ255(XBRZ_MINC);
  float fastLimSq = min(mincSq, SQ255(XBRZ_BAR49));
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


  gHaveCardI = false; gHaveDiagI = false; gHaveDiagC = false;
  float minSideSq = min(min(sBSq, sDSq), min(sFSq, sHSq));
  float maxSideSq = max(max(sBSq, sDSq), max(sFSq, sHSq));
  vec4 pairSq = vec4(distSqY(nB, nD), distSqY(nB, nF), distSqY(nF, nH), distSqY(nH, nD));
  vec4 maxCornerSq = max(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq));
  vec4 minCornerSq = min(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq));

  // ---- Rules 26, 28: matching corners and post-resolve 2:1 fixes ----
  res = applyRule26Lost(res, w0, aW0, pairSq, minCornerSq, maxCornerSq);
  res = applyRule26b(res, pairSq, minCornerSq, maxCornerSq, minSideSq);
  res = applyRule26d(res, pairSq, minCornerSq);
  res = applyRule28Match(res, pairSq);
  res = applyRule26ef(res, pairSq, minCornerSq);
  if (nE.x <= 0.30) res = applyRule26c(res, pairSq);

  // ---- Rules 38-41: 4-color junctions, ramp ties, dots, diagonal strokes ----
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = junc4(res, pairSq, minCornerSq);
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    vec4 m39 = cut4(res) * vec4(greaterThan(minCornerSq, vec4(SQ255(20.0))))
             * vec4(greaterThan(minCornerSq, (1.0 - XBRZ_MID39) * (1.0 - XBRZ_MID39) * maxCornerSq))
             * vec4(greaterThan(pairSq, 3.24 * maxCornerSq));
    if (dot(m39, vec4(1.0)) > 0.5) res = tieRamp(res, m39);
  }
  if (maxSideSq >= SQ255(XBRZ_DOT40)
      && (minSideSq >= SQ255(XBRZ_DOT40)
          || dot(cut4(res) * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_DOT40)))), vec4(1.0)) > 0.5)
      && dot(cut4(res), vec4(1.0)) > 0.0)
    res = dots40(res, minSideSq, pairSq);
  bool loneE = minSideSq >= SQ255(XBRZ_SAME_M);
  if (dot(cut4(res), vec4(1.0)) > 0.0
      && (loneE || dot(cut4(res) * FLAG(res, BIT_LINE) * abs(FLAG(res, BIT_SHALLOW) - FLAG(res, BIT_STEEP))
          * vec4(equal(FLAG(res, BIT_LONG3) + FLAG(res, BIT_LONG4), vec4(0.0)))
          * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))))
          * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_SAME_M)))), vec4(1.0)) > 0.0))
    res = diagStroke41(res, loneE, pairSq);

  // ---- Rules 44, 45, 48, 49, 41b/c, 42b: stroke ends, slopes, bars, convex bevels ----
  if (nE.x <= 0.35 && maxSideSq >= SQ255(XBRZ_END44) && minSideSq < SQ255(XBRZ_SAME_M)) res = strokeEnd44(res);
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    if (maxSideSq >= SQ255(80.0) && minSideSq < SQ255(XBRZ_SAME_M)) res = applyRule45(res, pairSq, minCornerSq, maxCornerSq);
    res = applyRule48(res, pairSq, minSideSq, maxSideSq, loneE);
  }
  res = applyRule49(res, res0, pairSq, minSideSq, maxSideSq);
  if (loneE && dot(cut4(res), vec4(1.0)) > 0.0) res = apex41(res, pairSq, minCornerSq);
  if (!loneE && maxSideSq >= mincSq)
    res = applyRule42b(res, pairSq, minCornerSq);

  FRAG_OUT = res / 255.0;
}

#endif

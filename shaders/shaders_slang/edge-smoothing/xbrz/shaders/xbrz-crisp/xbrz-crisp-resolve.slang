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
// Resolve pass of xbrz-crisp (Vulkan / slang): once per input pixel, between pass 0 and pass 1
//#crisp}
//#plain // Resolve pass of xbrz-freescale-multipass (Vulkan / slang)

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
//#crisp{
	float XBRZ_MINC;
//#crisp}
} global;
//#crisp{
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
#define XBRZ_MINC global.XBRZ_MINC
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
// the input of the first pass (the preset's reference pass), which is the original image unless
// other shaders run before xBRZ
ivec2 gIpx = ivec2(0), gMaxI = ivec2(0);
//#crisp{
layout(set = 0, binding = 3) uniform sampler2D xbrz_crisp_refpass;
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define P(x,y) texelFetch(xbrz_crisp_refpass, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gMaxI), 0).rgb
//#crisp}
//#plain layout(set = 0, binding = 3) uniform sampler2D xbrz_fs_refpass;
//#plain #define ORIG_SIZE params.xbrz_fs_refpassSize
//#plain #define P(x,y) texelFetch(xbrz_fs_refpass, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gMaxI), 0).rgb
#define OUT_SIZE params.OutputSize
#define ORIG_INPUT_SIZE ORIG_SIZE
#define INFO_RAW(x, y) texelFetch(Source, clamp(gIpx + ivec2(int(x), int(y)), ivec2(0), gMaxI), 0)

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
// Decision-word bit layout (0..255 per corner: x = TL, y = TR, z = BR, w = BL):
//   bits 0..1 (BLEND): 0 = none, 1 = normal, 2 = dominant (or thin sliver / small tip), 3 = weak (pass0 -> resolve)
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
float drawsLine(float r) { float bl = BLEND(r); return float(r < BIT_BLOCKED && bl > 0.0 && bl < 3.0 && FLAG(r, BIT_LINE) > 0.0); }
vec4 drawsLine4(vec4 r)  { return activeCutOf(r) * FLAG(r, BIT_LINE); }
vec4 isLine45(vec4 r)    { return FLAG(r, BIT_LINE) * (1.0 - FLAG(r, BIT_SHALLOW)) * (1.0 - FLAG(r, BIT_STEEP)) * vec4(equal(FLAG(r, BIT_LONG3) + FLAG(r, BIT_LONG4), vec4(0.0))); }
float wordPlain(bool sec)  { return sec ? (1.0 + BIT_SEC) : 1.0; }
float wordLine45(bool sec) { return sec ? (1.0 + BIT_LINE + BIT_SEC) : (1.0 + BIT_LINE); }
// the first pass's decisions for the four corners of the pixel at (x, y) from E
#ifndef INFO_RAW
#define INFO_RAW(x, y) INFO(coord + vec2(x, y) * INFO_STEP)
#endif
#define INFO_AT(x, y) floor(INFO_RAW(x, y) * 255.0 + 0.5)

//#crisp{
// ---- Tunables of rules 14 and 17 to 25 (distances in x/255, like XBRZ_MINC), in rule order ----
#define XBRZ_SAME 15.0         // the tolerance of sameColor (the default tolerance, fixed here)
#define XBRZ_TONE 20.0         // 14. the tolerance of sameTone, the colors of one stroke
#define XBRZ_STRAIGHT 64.0     // 14. minimum contrast of a straightened edge
#define XBRZ_THIN_TONE 40.0    // 14. a pixel this close to the step pixel may take the thin end of its line
#define XBRZ_DARK 0.3          // 14. a stroke this dark (luma) or darker may have two lighter side colors
#define XBRZ_LONE_RAMP 1.4     // 17. not a ramp: d(L,E) + d(E,O) above this times d(L,O)
#define XBRZ_ISO 40.0          // 19. a pixel this far from all 8 of its neighbors keeps out of their corners
#define XBRZ_ISO_FAR 60.0      // 19. a lone pixel keeps out of a plain cut whose other neighbor is this far from it
#define XBRZ_JUNCTION 40.0     // 20. two neighbors this far apart do not make one edge across a corner
#define XBRZ_JUNC_NEAR 20.0    // 20. a color this close to the next pixel goes on along the cut
#define XBRZ_JUNC_RAMP 1.06    // 20. not a junction but a ramp
#define XBRZ_JUNC_RAMP2 1.12   // 20. a looser ramp, where a cut goes on or E is a strip
#define XBRZ_JUNC_RAMP3 1.15   // 20. looser still where E is the end of a strong ramp
#define XBRZ_JUNC_AA_MIN 40.0  // 20. dark outline with an antialiasing pixel: min distance
#define XBRZ_JUNC_AA_MAX 70.0  // 20. and max distance
#define XBRZ_JUNC_AA_DARK 0.35 // 20. and the darkest of the three is darker than this (luma)
#define XBRZ_JUNC_MID 0.4      // 20. the middle step of a strong ramp is more than this times the whole
#define XBRZ_JUNC_FAR 100.0    // 20. a ramp is strong when its far end differs from E by more than this
#define XBRZ_JUNC_GRAY 12.0    // 20. a color this close to gray (Cb and Cr, x/255) is nearly gray
#define XBRZ_JUNC_HUE 8.0      // 20. two colors this close in hue (Cb and Cr only) are shades of one hue
#define XBRZ_JUNC_SHADE 0.65   // 20. two shades are one outline when this much closer to each other than to E
#define XBRZ_JUNC_TONE 0.25    // 20. E is a shade of a neighbor this much closer to it than the two neighbors are apart
#define XBRZ_LINE_SIDE 25.0    // 21. the other neighbor of a corner differs from a straight line by this
#define XBRZ_LINE_TONE 0.4     // 21. p and q are close shades when they differ by less than this times E's difference
#define XBRZ_LINE_STRONG 64.0  // 21. a line this far from E is strong
#define XBRZ_LINE_ALONG 20.0   // 21. E's color goes on along the cut when a pixel beside the corner is closer than this
#define XBRZ_LINE_PAST 40.0    // 21. tip in an area: q differs from the pixel past E by this
#define XBRZ_LINE_BACK 0.5     // 21. tip in an area: p and q are one background
#define XBRZ_CROSS_MAX 64.0    // 22. E and the neighbor are close shades
#define XBRZ_CROSS_RAMP 45.0   // 22. a faint step on a ramp toward a darker pixel stays
#define XBRZ_LONE23 100.0      // 23b. a dot this far from all 8 neighbors is far from everything
#define XBRZ_LOOSE 60.0        // 23. a pixel this far from each of its 4 side neighbors is loose
#define XBRZ_HOOK 90.0         // 24. a line between two colors this far apart needs a corner to go on to
#define XBRZ_POINT 60.0        // 25. the two pixels beside a pointed pixel differ by this

// ---- Helpers of the Crisp rules ----


const vec2 vX = vec2(0., -1.), hX = vec2(-1., 0.), vY = vec2(1., 0.), hY = vec2(0., -1.);
const vec2 vZ = vec2(0., 1.), hZ = vec2(1., 0.), vW = vec2(-1., 0.), hW = vec2(0., 1.);

bool sameColor(vec3 a, vec3 b) { return withinY255(a, b, XBRZ_SAME); }
float chromaSqY(vec3 a, vec3 b)
{
  vec2 dc = a.yz - b.yz;
  return dot(dc, dc);
}
bool sameTone(vec3 a, vec3 b) { return withinEqY255(a, b, XBRZ_TONE); }
// The original pixel at an offset from E (in linear YCbCr)
#define at(o) toYCbCr(P((o).x, (o).y))
float sameF(vec3 a, vec3 b) { return float(sameColor(a, b)); }
vec4 isCut(vec4 blend) { return vec4(greaterThan(blend, vec4(0.0))); }
bool anyCut(vec4 blend) { return any(greaterThan(blend, vec4(0.0))); }
float junctionNear(vec3 a, vec3 b) { return withinY255(a, b, XBRZ_JUNC_NEAR) ? 1.0 : 0.0; }
float apartFrom4(vec3 c, vec3 a, vec3 b, vec3 d, vec3 e)
{
  return (!sameColor(c, a) && !sameColor(c, b) && !sameColor(c, d) && !sameColor(c, e)) ? 1.0 : 0.0;
}
float sameAsOne(vec3 c, vec3 a, vec3 b) { return (sameColor(c, a) || sameColor(c, b)) ? 1.0 : 0.0; }

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
// ============================================================================================
// Resolve pass — Straight steps (Rule 14) & Point on a shared edge (Rule 25)
// ============================================================================================

float point25(vec3 E, vec3 N, vec3 s1, vec3 s2, vec3 a1, vec3 a2, vec3 notch, vec2 o1, vec2 o2, vec3 b1, vec3 b2)
{
  if (!(sameColor(E, a1) && sameColor(E, a2) && !sameColor(E, notch))) return 0.0;
  if (withinY255(E, N, XBRZ_JUNCTION) || withinY255(s1, N, XBRZ_JUNC_NEAR) || withinY255(s2, N, XBRZ_JUNC_NEAR) || withinY255(s1, s2, XBRZ_POINT)) return 0.0;
  if (!(sameColor(N, b1) || sameColor(N, b2))) return 0.0;
  return (!sameColor(E, at(o1)) && !sameColor(E, at(o2))) ? 1.0 : 0.0;
}

bool lighterSide(vec3 side, vec3 stroke) { return side.x > stroke.x && !withinY255(side, stroke, XBRZ_STRAIGHT); }
float sideTones(inout vec3 t1, inout vec3 t2, float n, vec3 c)
{
  if (n < 0.5) { t1 = c; return 1.0; }
  if (sameTone(c, t1)) return n;
  if (n < 1.5) { t2 = c; return 2.0; }
  return sameTone(c, t2) ? n : 3.0;
}

// State for walking one straight step along an edge in Rule 14:
//   n    : pixel count along the current step (valid range 2..6)
//   thin : stroke stays 1px wide (far side != stroke color X)
//   nu   : near side stays uniform in tone Y
//   fu   : far side stays uniform in its initial tone farC
//   dk   : dark stroke (X.x <= XBRZ_DARK) with both sides strictly lighter and >= XBRZ_STRAIGHT apart
//   farC : initial far-side tone; t1/t2 + nt track up to 2 distinct lighter side tones when dk holds
struct Walk { float n; bool thin, nu, fu, dk; vec3 farC, t1, t2; float nt; };

bool walkCell(inout Walk w, vec3 X, vec3 Y, vec2 o, vec2 n, bool first, bool knownX)
{
  if (!knownX && !sameTone(at(o), X)) return false;
  vec3 nr = at(o + n);
  if (sameTone(nr, X)) return false;
  w.n += 1.0;
  w.nu = w.nu && sameTone(nr, Y);
  if (w.thin)
  {
    vec3 fr = at(o - n);
    if (first) w.farC = fr;
    w.thin = !sameTone(fr, X);
    w.fu = w.fu && sameTone(fr, w.farC);
    w.dk = w.dk && lighterSide(nr, X) && lighterSide(fr, X);
    if (w.dk) { w.nt = sideTones(w.t1, w.t2, w.nt, nr); w.nt = sideTones(w.t1, w.t2, w.nt, fr); }
  }
  return w.nu || (w.thin && (w.fu || (w.dk && w.nt < 2.5)));
}
vec2 stepSide(vec3 X, vec3 Y, vec2 row1, vec2 row2, vec2 a, vec2 n, bool skipFirst)
{
  Walk w = Walk(0.0, true, true, true, X.x <= XBRZ_DARK, X, X, X, 0.0);
  for (int k = 0; k < 7; k++) { if (!walkCell(w, X, Y, row1 - float(k) * a, n, k == 0, k == 0 && skipFirst)) break; }
  float n1 = w.n;
  if (n1 < 2.0 || n1 > 6.0 || !(w.nu || (w.thin && (w.fu || (w.dk && w.nt < 2.5))))) return vec2(0.0);
  w.n = 0.0;
  for (int k = 1; k < 8; k++) { if (w.n > n1 + 1.5 || !walkCell(w, X, Y, row2 + float(k) * a, n, false, false)) break; }
  float run = (w.n <= 6.0 && abs(n1 - w.n) <= 1.0) ? min(4.0, min(n1, w.n)) : 0.0;
  bool dark = w.dk && w.nt < 2.5;
  return vec2((w.thin && (w.nu || w.fu || dark)) ? run : 0.0, w.nu ? run : 0.0);
}
vec2 stepRun(vec3 X, vec3 Y, vec2 s, vec2 a, vec2 b)
{
  vec2 rx = stepSide(X, Y, s, s - b, a, b, true), ry = stepSide(Y, X, s + b, s, a, -b, false);
  return vec2(max(rx.x, ry.x), max(rx.y, ry.y));
}
vec2 stepSlope(vec2 st, vec2 sh, float xs, float xh)
{
  if (st.x >= 2.0 && sh.x < 2.0) return vec2(st.x, 1.0);
  if (sh.x >= 2.0 && st.x < 2.0) return vec2(sh.x, 2.0);
  bool ys = xs > 0.0 && st.y >= 3.0 && sh.x < 2.0;
  bool yh = xh > 0.0 && sh.y >= 3.0 && st.x < 2.0;
  if (ys && !yh) return vec2(st.y, 1.0);
  if (yh && !ys) return vec2(sh.y, 2.0);
  return vec2(0.0);
}
float thinEnd(vec2 r, vec2 other, bool steep, float xLine)
{
  if (max(r.x, r.y * xLine) < 3.0) return 0.0;
  r = steep ? stepSlope(r, other, xLine, 0.0) : stepSlope(other, r, 0.0, xLine);
  return (r.x >= 3.0 && r.y == (steep ? 1.0 : 2.0)) ? r.x : 0.0;
}
bool blockedByQ3(vec2 stepOff, vec2 h, vec2 v, bool steep, vec3 pStep, vec3 pH, vec3 pV)
{
  vec2 q3 = stepOff + (steep ? h - v : v - h);
  vec3 X3 = at(q3);
  if (withinY255(X3, pStep, XBRZ_STRAIGHT) || withinY255(X3, pH, XBRZ_STRAIGHT) || withinY255(X3, pV, XBRZ_STRAIGHT))
    return false;
  float solid3 = sameF(X3, at(q3 + vec2(1.0, 0.0))) + sameF(X3, at(q3 - vec2(1.0, 0.0)))
               + sameF(X3, at(q3 + vec2(0.0, 1.0))) + sameF(X3, at(q3 - vec2(0.0, 1.0)));
  return solid3 > 0.5;
}

void evalSteps14(vec4 blendResult, vec4 line, vec4 haveSteepLine, vec4 haveShallowLine,
                 vec4 iB, vec4 iD, vec4 iF, vec4 iH, vec4 dE1Sq, vec4 dLOSq,
                 bool haveE, vec3 cachedE, bool haveCardPix, vec3 cBpix, vec3 cDpix, vec3 cFpix, vec3 cHpix,
                 bool haveDiagPix, vec3 cachedA, vec3 cachedC, vec3 cachedG, vec3 cachedI,
                 out vec4 nn, out vec4 ty, out vec4 thinN, out vec4 thinSteep)
{
  nn = vec4(0.0); ty = vec4(0.0); thinN = vec4(0.0); thinSteep = vec4(0.0);
  vec4 dEv14Sq = dE1Sq.xzwy, dEh14Sq = dE1Sq.yxzw;
  vec4 lineOn = line * isCut(blendResult) * vec4(greaterThanEqual(max(dEv14Sq, dEh14Sq), vec4(SQ255(XBRZ_STRAIGHT))));
  vec4 free = vec4(equal(blendResult, vec4(0.0)));
  if (anyCut(blendResult))
  {
    vec4 dNSq = vec4(min(dE1Sq.x, dE1Sq.y), min(dE1Sq.x, dE1Sq.z), min(dE1Sq.z, dE1Sq.w), min(dE1Sq.y, dE1Sq.w));
    free = max(free, isCut(blendResult) * vec4(lessThan(dNSq, (XBRZ_JUNC_TONE * XBRZ_JUNC_TONE) * dLOSq))
                   * vec4(greaterThan(dLOSq, vec4(SQ255(XBRZ_STRAIGHT)))));
  }
  vec4 cSt = free * drawsLine4(vec4(iB.x, iF.y, iH.z, iD.w));
  vec4 cSh = free * drawsLine4(vec4(iD.x, iB.y, iF.z, iH.w));
  if (!any(greaterThan(lineOn + cSt + cSh, vec4(0.0)))) return;
  vec4 xSt = vec4(FLAG(iB.x, BIT_STEEP), FLAG(iF.y, BIT_STEEP), FLAG(iH.z, BIT_STEEP), FLAG(iD.w, BIT_STEEP));
  vec4 xSh = vec4(FLAG(iD.x, BIT_SHALLOW), FLAG(iB.y, BIT_SHALLOW), FLAG(iF.z, BIT_SHALLOW), FLAG(iH.w, BIT_SHALLOW));
  vec3 E0 = haveE ? cachedE : toYCbCr(P(0., 0.));
  for (int k = 0; k < 4; k++)
  {
    vec4 m = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
    if (dot(m, lineOn + cSt + cSh) <= 0.0) continue;
    vec2 v = k == 0 ? vX : (k == 1 ? vY : (k == 2 ? vZ : vW));
    vec2 h = k == 0 ? hX : (k == 1 ? hY : (k == 2 ? hZ : hW));
    float lo = dot(m, lineOn), xs = dot(m, xSt), xh = dot(m, xSh);
    vec3 vPix = haveCardPix ? (k == 0 ? cBpix : (k == 1 ? cFpix : (k == 2 ? cHpix : cDpix))) : vec3(0.0);
    vec3 hPix = haveCardPix ? (k == 0 ? cDpix : (k == 1 ? cBpix : (k == 2 ? cFpix : cHpix))) : vec3(0.0);
    bool haveVPix = haveCardPix, haveHPix = haveCardPix;
    bool steepOk = false, shallowOk = false;
    if (dot(m, cSt) > 0.0)
    {
      if (!haveVPix) { vPix = at(v); haveVPix = true; }
      steepOk = withinY255(vPix, E0, XBRZ_THIN_TONE);
    }
    float thinS = 0.0;
    vec2 r0 = vec2(0.0), r1 = vec2(0.0), r2 = vec2(0.0), r3 = vec2(0.0), r4 = vec2(0.0), r5 = vec2(0.0);
    for (int j = 0; j < 6; j++)
    {
      if (j == 4)
      {
        if (steepOk)
        {
          thinS = thinEnd(r2, r3, true, xs);
          if (thinS > 0.0)
          {
            vec3 vhPix = haveDiagPix ? (k == 0 ? cachedA : (k == 1 ? cachedC : (k == 2 ? cachedI : cachedG))) : at(v + h);
            if (blockedByQ3(v, h, v, true, vPix, vhPix, at(2.0 * v))) thinS = 0.0;
          }
        }
        if (thinS == 0.0 && dot(m, cSh) > 0.0)
        {
          if (!haveHPix) { hPix = at(h); haveHPix = true; }
          shallowOk = withinY255(hPix, E0, XBRZ_THIN_TONE);
        }
      }
      vec2 s = vec2(0.), a = v, b = h;
      bool need = lo > 0.0 && dot(m, dEv14Sq) >= SQ255(XBRZ_STRAIGHT);
      if (j == 1) { a = h; b = v; need = lo > 0.0 && dot(m, dEh14Sq) >= SQ255(XBRZ_STRAIGHT); }
      else if (j == 2) { s = v; need = steepOk; }
      else if (j == 3) { s = v; a = h; b = v; need = steepOk && max(r2.x, r2.y * xs) >= 3.0; }
      else if (j == 4) { s = h; a = h; b = v; need = shallowOk; }
      else if (j == 5) { s = h; need = shallowOk && max(r4.x, r4.y * xh) >= 3.0; }
      vec2 rr = vec2(0.0);
      if (need)
      {
        vec3 X = (j < 2) ? E0 : ((j < 4) ? vPix : hPix);
        vec3 Y = (j == 0 && haveVPix) ? vPix
               : ((j == 1 && haveHPix) ? hPix
               : (((j == 3 || j == 5) && haveDiagPix) ? (k == 0 ? cachedA : (k == 1 ? cachedC : (k == 2 ? cachedI : cachedG)))
               : at(s + a)));
        if (!withinY255(X, Y, XBRZ_STRAIGHT)) rr = stepRun(X, Y, s, a, b);
      }
      if (j == 0) r0 = rr; else if (j == 1) r1 = rr; else if (j == 2) r2 = rr;
      else if (j == 3) r3 = rr; else if (j == 4) r4 = rr; else r5 = rr;
    }
    float thinSh = shallowOk ? thinEnd(r4, r5, false, xh) : 0.0;
    if (thinSh > 0.0)
    {
      vec3 vhPix = haveDiagPix ? (k == 0 ? cachedA : (k == 1 ? cachedC : (k == 2 ? cachedI : cachedG))) : at(h + v);
      if (blockedByQ3(h, h, v, false, hPix, at(2.0 * h), vhPix)) thinSh = 0.0;
    }
    vec2 sl = stepSlope(r0, r1, dot(m, haveSteepLine), dot(m, haveShallowLine));
    if (sl.x > 0.0)
    {
      if (!haveVPix) vPix = at(v);
      if (!haveHPix) hPix = at(h);
      if (blockedByQ3(vec2(0.0), h, v, sl.y == 1.0, E0, hPix, vPix)) sl = vec2(0.0);
    }
    nn += m * sl.x;
    ty += m * sl.y;
    thinN += m * (thinS + thinSh);
    thinSteep += m * (thinS > 0.0 ? 1.0 : 0.0);
  }
}
// ============================================================================================
// Resolve pass — Isolated pixels, junctions, straight lines, crossed cuts, knight's move
// (Rules 19, 20, 21, 22, 37)
// ============================================================================================

// ---- 19. A pixel apart keeps to itself ----
float isoSqOf5(vec3 c, float baseSq, vec3 n0, vec3 n1, vec3 n2, vec3 n3, vec3 n4)
{
  if (baseSq < SQ255(XBRZ_SAME)) return baseSq;
  return min(baseSq, min(min(distSqY(c, n0), distSqY(c, n1)),
                         min(min(distSqY(c, n2), distSqY(c, n3)), distSqY(c, n4))));
}
float squareOf(vec4 word) { return dot(BLEND(word), vec4(1.0)) == 0.0 ? 1.0 : 0.0; }

// ---- 20. Strong-ramp midpoint helper ----
float aa20(vec3 Pc, vec3 O, vec3 P2, vec3 O2, float d1, float d2)
{
  if (!sameColor(P2, Pc) || !sameColor(O2, O)) return 0.0;
  float acSq = distSqY(Pc, O);
  if (acSq <= SQ255(XBRZ_JUNC_FAR)) return 0.0;
  float s = d1 + d2;
  return float(s * s < (XBRZ_JUNC_RAMP * XBRZ_JUNC_RAMP) * acSq);
}

// ---- 37. Knight's-move contour kin & single-corner test ----
#define XBRZ_KIN37 0.6
bool kin37(vec3 O, vec3 K, vec3 Pc)
{
  float okSq = distSqY(O, K);
  return okSq < SQ255(XBRZ_SAME) || okSq < (XBRZ_KIN37 * XBRZ_KIN37) * min(distSqY(O, Pc), distSqY(K, Pc));
}
float knightFlip37(bool s1, vec3 cPri, vec3 cSec, vec3 kPri, vec3 kSec, float dPri, float dSec, float cand,
                   float cutPri, float secPri, float cutSec, float secSec)
{
  bool face = s1 ? (cutSec > 0.5 && secSec < 0.5) : (cutPri > 0.5 && secPri > 0.5);
  if (!face) return 0.0;
  vec3 Pc = s1 ? cSec : cPri, O = s1 ? cPri : cSec, K = s1 ? kSec : kPri;
  float dPcE = s1 ? dSec : dPri, dOE = s1 ? dPri : dSec;
  return float(dPcE >= XBRZ_JUNCTION && dOE >= XBRZ_JUNCTION && cand + dPcE >= 1.15 * dOE && kin37(O, K, Pc));
}

// ---- 21 and 22: corner-local neighborhood frame ----
// Oriented around a corner's chosen paint direction p (color u) and unchosen side q (color w):
//   p, q     : unit cardinal offsets to painted neighbor u and unchosen neighbor w; s = BIT_SEC flag
//   u, w     : colors at +p and +q; mu, mw = colors at -p and -q; opp = diagonal pixel at -p-q
//   uw       : corner diagonal pixel at +p+q; umw = +p-q; wmu = +q-p
//   u2, w2   : two steps along +p and +q; u2mw = +2p-q; w2mu = +2q-p; uw2 = +p+2q
//   ru, rumw : decision word of +p's opposite corner and +p-q's matching corner
struct Roles
{
  vec2 p, q;
  float s;
  vec3 u, w, mu, mw, opp, uw, umw, wmu, u2, w2, u2mw, w2mu, uw2;
  float ru, rumw;
};
Roles makeRoles(vec2 v, vec2 h, vec3 cv, vec3 ch, vec3 cvh, vec3 cvmh, vec3 chmv,
                vec3 cv2, vec3 ch2, vec3 cv2mh, vec3 ch2mv, vec3 cvp2h, vec3 chp2v,
                vec3 cmv, vec3 cmh, vec3 copp, float rv, float rh, float rvmh, float rhmv, float s)
{
  bool sv = s > 0.5;
  Roles r;
  r.s = s;
  r.p = sv ? v : h;            r.q = sv ? h : v;
  r.u = sv ? cv : ch;          r.w = sv ? ch : cv;
  r.mu = sv ? cmv : cmh;       r.mw = sv ? cmh : cmv;
  r.opp = copp;                r.uw = cvh;
  r.umw = sv ? cvmh : chmv;    r.wmu = sv ? chmv : cvmh;
  r.u2 = sv ? cv2 : ch2;       r.w2 = sv ? ch2 : cv2;
  r.u2mw = sv ? cv2mh : ch2mv; r.w2mu = sv ? ch2mv : cv2mh;
  r.uw2 = sv ? cvp2h : chp2v;
  r.ru = sv ? rv : rh;         r.rumw = sv ? rvmh : rhmv;
  return r;
}

// ---- 21. A straight line does not bend ----
vec2 straight21(Roles r, vec3 E, float ln, float uwSq, float euSq, float ewSq)
{
  bool shadedLine = withinY255(r.u, r.uw, XBRZ_MINC) && withinY255(r.u, r.umw, XBRZ_MINC) && sameColor(r.uw, r.umw);
  if (uwSq <= SQ255(XBRZ_LINE_SIDE) || (!sameColor(r.u, r.uw) && !shadedLine)) return vec2(0.0);
  float minESq = min(euSq, ewSq);
  float dEwmuSq = distSqY(E, r.wmu);
  bool sEwmu = dEwmuSq < SQ255(XBRZ_SAME);
  float dEmuSq = distSqY(E, r.mu);
  bool sEmu = dEmuSq < SQ255(XBRZ_SAME);
  bool sEmw = sameColor(E, r.mw);
  if (minESq >= SQ255(XBRZ_LINE_STRONG) && sEwmu && sEmw && !sEmu && !sameColor(E, r.opp))
    return vec2(0.0);
  if (uwSq < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * minESq
      && (ln > 0.5 || sameColor(r.w, r.mw))
      && (sEmu || sEwmu
          || dEmuSq < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * distSqY(r.mu, r.u)
          || dEwmuSq < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * distSqY(r.wmu, r.u))) return vec2(0.0);
  if (minESq >= SQ255(XBRZ_LINE_STRONG) && sameColor(r.u, r.u2) && sEwmu && !withinY255(r.w, r.mw, XBRZ_LINE_PAST))
  {
    bool tipE = !sEmu && !sEmw;
    if (uwSq < (XBRZ_LINE_BACK * XBRZ_LINE_BACK) * minESq) { if (tipE) return vec2(0.0); }
    else if ((tipE || sameColor(r.w, r.w2mu)) && !(sameColor(r.u, r.mu) && sameColor(r.u, r.mw))) return vec2(1.0, 1.0);
  }
  bool middle = sameColor(r.u, r.umw) || shadedLine;
  bool four = !middle && euSq >= SQ255(XBRZ_LINE_STRONG) && !sameColor(r.w, r.umw)
           && distSqY(r.u2, r.u) > distSqY(r.u2, E)
           && sameColor(r.u, r.uw2)
           && distSqY(r.u2mw, E) < min(distSqY(r.u2mw, r.u), distSqY(r.u2mw, r.w))
           && dEwmuSq >= SQ255(XBRZ_LINE_ALONG) && !withinY255(E, r.umw, XBRZ_LINE_ALONG)
           && sameColor(r.u, at(r.p + 3.0 * r.q));
  if (!middle && !four) return vec2(0.0);
  bool takes = sameColor(r.w, r.w2) && euSq >= SQ255(XBRZ_LINE_STRONG) && sameColor(r.w, r.w2mu)
            && dEwmuSq < distSqY(r.wmu, r.w) && r.w.x < E.x;
  return vec2(1.0, takes ? 1.0 : 0.0);
}

// ---- 22. Crossed cuts ----
float back22(Roles r, vec3 E, float eWord, float blocked, float loneE)
{
  float along = r.s > 0.5 ? BIT_SHALLOW : BIT_STEEP;
  if (BLEND(r.ru) == 0.0 || abs(FLAG(r.ru, BIT_SEC) - r.s) > 0.5 || max(FLAG(r.ru, BIT_BLOCKED), blocked) < 0.5
      || max(FLAG(r.ru, along), FLAG(eWord, along)) < 0.5) return 0.0;
  float dnSq = distSqY(E, r.u);
  if (dnSq >= SQ255(XBRZ_CROSS_MAX)) return 0.0;
  if (r.u.x > E.x)
  {
    if (dnSq < SQ255(XBRZ_CROSS_RAMP) && r.mu.x < E.x) return 0.0;
    return sameAsOne(r.u, r.w, r.u2mw) * loneE;
  }
  if (dnSq < SQ255(XBRZ_CROSS_RAMP) && r.u2.x < r.u.x) return 0.0;
  return sameAsOne(E, r.umw, r.wmu) * apartFrom4(r.u, E, r.u2, r.uw, r.umw);
}
float tip22(Roles r, vec3 E)
{
  if (BLEND(r.ru) == 0.0 || BLEND(r.rumw) == 0.0 || max(FLAG(r.ru, BIT_BLOCKED), FLAG(r.rumw, BIT_BLOCKED)) < 0.5) return 0.0;
  float dlSq = distSqY(r.umw, r.u);
  if (dlSq < SQ255(XBRZ_SAME) || dlSq >= SQ255(XBRZ_CROSS_MAX) || r.umw.x <= r.u.x) return 0.0;
  if (sameColor(r.u, r.w) || sameColor(r.u, r.uw) || sameColor(r.w, r.uw) || sameColor(E, r.uw) || sameColor(E, r.u) || sameColor(r.u, r.u2)) return 0.0;
  return sameColor(r.umw, at(2.0 * (r.p - r.q))) ? 1.0 : 0.0;
}
#define ROLES_0(s) makeRoles(vX, hX, B, D, A, C, G, uu, ll, ruu, lld, llu, luu, H, F, I, iB.z, iD.z, iC.x, iG.x, s)
#define ROLES_1(s) makeRoles(vY, hY, F, B, C, I, A, rr, uu, rrd, luu, ruu, rru, D, H, G, iF.w, iB.w, iI.y, iA.y, s)
#define ROLES_2(s) makeRoles(vZ, hZ, H, F, I, G, C, dd, rr, ldd, rru, rrd, rdd, B, D, A, iH.x, iF.x, iG.z, iC.z, s)
#define ROLES_3(s) makeRoles(vW, hW, D, H, G, A, I, ll, dd, llu, rdd, ldd, lld, F, B, C, iD.y, iH.y, iA.w, iI.w, s)
//#crisp}

void main()
{
  gMaxI = ivec2(ORIG_SIZE.xy) - ivec2(1);
  gIpx = clamp(ivec2(floor(vTexCoord * ORIG_SIZE.xy)), ivec2(0), gMaxI);
  vec4 info = INFO_AT(0.0, 0.0);
  bool infoZero = dot(info, vec4(1.0)) < 0.5;
  vec4 iB = vec4(0.0), iD = vec4(0.0), iF = vec4(0.0), iH = vec4(0.0);
//#plain   if (infoZero) { FRAG_OUT = vec4(0.0); return; }
//#crisp{
  if (infoZero && XBRZ_MINC <= 0.0) { FRAG_OUT = vec4(0.0); return; }
  iB = INFO_AT( 0.0, -1.0); iD = INFO_AT(-1.0,  0.0);
  iF = INFO_AT( 1.0,  0.0); iH = INFO_AT( 0.0,  1.0);
  if (infoZero && dot(drawsLine4(vec4(iB.x, iF.y, iH.z, iD.w)) + drawsLine4(vec4(iD.x, iB.y, iF.z, iH.w)), vec4(1.0)) < 0.5)
  { FRAG_OUT = vec4(0.0); return; }
//#crisp}
//#plain   bool haveCardInfo = false;
//#crisp{
  vec4 blockedBit = step(BIT_BLOCKED, info);
//#crisp}
  vec4 blendResult = BLEND(info);
  vec4 iA = vec4(0.0), iC = vec4(0.0), iG = vec4(0.0), iI = vec4(0.0);
  bool haveDiagInfo = false;
  vec3 cachedE = vec3(0.0);
  bool haveE = false;
//#crisp{
  vec3 cachedA = vec3(0.0), cachedC = vec3(0.0), cachedG = vec3(0.0), cachedI = vec3(0.0);
  bool haveDiagPix = false;
//#crisp}

  vec4 weak = vec4(equal(blendResult, vec4(3.0)));
  if (max(max(info.x, info.y), max(info.z, info.w)) >= 128.0 || dot(weak, vec4(1.0)) > 0.0)
  {
    vec4 blocked = floor(info / 128.0);
    info = mod(info, 128.0);
    iC = INFO_AT( 1.0,-1.0);
    iG = INFO_AT(-1.0, 1.0);
    iI = INFO_AT( 1.0, 1.0);
    iA = INFO_AT(-1.0,-1.0);
    haveDiagInfo = true;
    vec4 aA = activeCutOf(iC);
    vec4 aB = activeCutOf(iG);
    vec4 aC = activeCutOf(iI);
    vec4 aD = activeCutOf(iA);

    // ---- 2. Diagonal limit: a blocked corner is cut only where it continues a cut ----
    vec4 chain = vec4(max(aA.x, aB.x), max(aC.y, aD.y), max(aA.z, aB.z), max(aC.w, aD.w));
    vec4 lineB = blocked * FLAG(info, 4.0) * vec4(greaterThan(blendResult, vec4(0.0))) * (1.0 - chain);
    vec4 meet = vec4(0.0);
    if (dot(lineB, vec4(1.0)) > 0.0)
    {
      cachedE = toYCbCr(P(0., 0.));
      haveE = true;
//#plain       iD = INFO_AT(-1.0, 0.0);
//#plain       iF = INFO_AT( 1.0, 0.0);
//#plain       iB = INFO_AT( 0.0,-1.0);
//#plain       iH = INFO_AT( 0.0, 1.0);
//#plain       haveCardInfo = true;
      vec4 sec2 = FLAG(info, 8.0);
      vec4 nO = vec4(mix(iD.z, iB.z, sec2.x), mix(iB.w, iF.w, sec2.y), mix(iF.x, iH.x, sec2.z), mix(iH.y, iD.y, sec2.w));
      vec3 mA = toYCbCr(P(-1., -1.)), mC = toYCbCr(P( 1., -1.));
      vec3 mG = toYCbCr(P(-1.,  1.)), mI = toYCbCr(P( 1.,  1.));
//#crisp{
      cachedA = mA; cachedC = mC; cachedG = mG; cachedI = mI;
      haveDiagPix = true;
//#crisp}
      vec3 dX = sec2.x > 0.5 ? mC : mG, dY = sec2.y > 0.5 ? mI : mA;
      vec3 dZ = sec2.z > 0.5 ? mG : mC, dW = sec2.w > 0.5 ? mA : mI;
      vec4 sameE = vec4(float(withinEqY255(cachedE, dX, 20.0)), float(withinEqY255(cachedE, dY, 20.0)),
                        float(withinEqY255(cachedE, dZ, 20.0)), float(withinEqY255(cachedE, dW, 20.0)));
      meet = activeCutOf(nO) * FLAG(nO, 4.0)
           * max(1.0 - abs(FLAG(nO, 8.0) - sec2), abs(FLAG(nO, 8.0) - sec2) * sameE)
           * FLAG(info, 4.0);
    }
    blendResult *= max(1.0 - blocked, max(chain, meet));

    // ---- 1. Minimum contrast: a weak corner is cut only inside a cut diagonal ----
    blendResult *= mix(vec4(1.0), vec4(min(aA.x, aB.x), min(aC.y, aD.y), min(aA.z, aB.z), min(aC.w, aD.w)), weak);
  }

  vec4 haveShallowLine = FLAG(info, 16.0);
  vec4 haveSteepLine = FLAG(info, 64.0);

  // ---- 9. Line shapes, second part ----
  vec4 tone = FLAG(info, 32.0) * vec4(greaterThan(blendResult, vec4(0.0)));
  if (tone.x + tone.y + tone.z + tone.w > 0.0)
  {
//#plain     if (!haveCardInfo)
//#plain     {
//#plain       iD = INFO_AT(-1.0, 0.0);
//#plain       iF = INFO_AT( 1.0, 0.0);
//#plain       iB = INFO_AT( 0.0,-1.0);
//#plain       iH = INFO_AT( 0.0, 1.0);
//#plain       haveCardInfo = true;
//#plain     }
    vec4 drawL = activeCutOf(iD) * FLAG(iD, 4.0), drawR = activeCutOf(iF) * FLAG(iF, 4.0);
    vec4 drawU = activeCutOf(iB) * FLAG(iB, 4.0), drawD = activeCutOf(iH) * FLAG(iH, 4.0);
    vec4 steepN = vec4(drawL.z * FLAG(iD.z, 64.0), drawU.w * FLAG(iB.w, 64.0),
                       drawR.x * FLAG(iF.x, 64.0), drawD.y * FLAG(iH.y, 64.0));
    vec4 shallowN = vec4(drawU.z * FLAG(iB.z, 16.0), drawR.w * FLAG(iF.w, 16.0),
                         drawD.x * FLAG(iH.x, 16.0), drawL.y * FLAG(iD.y, 16.0));
    haveSteepLine *= 1.0 - tone * steepN;
    haveShallowLine *= 1.0 - tone * shallowN;
  }

//#crisp{
  vec4 line = FLAG(info, 4.0);
  vec4 sec = FLAG(info, 8.0);
  vec4 x22 = vec4(0.0);
  vec4 small23 = vec4(0.0);
  vec4 hook24 = vec4(0.0);
  vec4 nn = vec4(0.0), ty = vec4(0.0), thinN = vec4(0.0), thinSteep = vec4(0.0);
  vec4 dE1Sq = vec4(0.0), dLOSq = vec4(0.0);
  vec4 dE4 = vec4(0.0), cand20 = vec4(0.0);
  vec3 cBpix = vec3(0.0), cDpix = vec3(0.0), cFpix = vec3(0.0), cHpix = vec3(0.0);
  bool haveCardPix = false;
  if (XBRZ_MINC > 0.0)
  {
    if (anyCut(blendResult))
    {
      vec3 B = toYCbCr(P( 0., -1.));
      vec3 D = toYCbCr(P(-1.,  0.));
      vec3 E = haveE ? cachedE : toYCbCr(P(0., 0.));
      vec3 F = toYCbCr(P( 1.,  0.));
      vec3 H = toYCbCr(P( 0.,  1.));
      cBpix = B; cDpix = D; cFpix = F; cHpix = H;
      haveCardPix = true;
      cachedE = E;
      haveE = true;

      vec3 A = cachedA, C = cachedC, G = cachedG, I = cachedI;
      vec4 cA = vec4(0.0), cC = vec4(0.0), cG = vec4(0.0), cI = vec4(0.0);
      bool haveDiagCut = false, haveSqrt = false;
      vec4 dE1_raw = vec4(0.0), dLO_raw = vec4(0.0);

      dE1Sq = vec4(distSqY(E, B), distSqY(E, D), distSqY(E, F), distSqY(E, H));
      dLOSq = vec4(distSqY(D, B), distSqY(B, F), distSqY(F, H), distSqY(H, D));
      vec4 sECard = vec4(lessThan(dE1Sq, vec4(SQ255(XBRZ_SAME))));
      vec4 cB = cutNoWeak(iB), cD = cutNoWeak(iD), cF = cutNoWeak(iF), cH = cutNoWeak(iH);

      // Exact 0-fetch gate: skip the 12 outer-ring fetches (luu..rdd) and rules 17/19/20/21/37/22/29
      // whenever none of those rules can fire (clean smooth edges with dLO < 24 and no special flags).
      // Diagonal INFO_AT/colors and sqrt() also defer off clean non-ring 2:1 edges.
      vec4 cutInit = isCut(blendResult);
      vec4 sh = haveShallowLine, st = haveSteepLine;
      vec4 on17 = cutInit * line * abs(sh - st) * vec4(equal(sec, st));
      vec4 oSh17 = vec4(iB.z, iF.w, iH.x, iD.y), oSt17 = vec4(iD.z, iB.w, iF.x, iH.y);
      vec4 hit17 = vec4(0.0);
      if (any(greaterThan(on17, vec4(0.0))))
      {
        vec4 o17 = mix(oSt17, oSh17, sh);
        hit17 = on17 * activeCutOf(o17) * FLAG(o17, 4.0)
              * mix(FLAG(o17, 64.0), FLAG(o17, 16.0), sh) * vec4(equal(FLAG(o17, 8.0), sh));
      }
      float sqB = squareOf(iB), sqD = squareOf(iD), sqF = squareOf(iF), sqH = squareOf(iH);
      vec4 sq19 = vec4(sec.x > 0.5 ? sqB : sqD, sec.y > 0.5 ? sqF : sqB, sec.z > 0.5 ? sqH : sqF, sec.w > 0.5 ? sqD : sqH);
      vec4 bk22 = max(blockedBit, max(FLAG(oSh17, 128.0), FLAG(oSt17, 128.0)));
      bool needRing = any(greaterThan(
        cutInit * (vec4(greaterThanEqual(dLOSq, vec4(SQ255(24.0)))) + sq19 + bk22) + hit17, vec4(0.0)));
      if (!needRing && any(greaterThan(cutInit * (1.0 - line), vec4(0.0))))
      {
        if (!haveDiagInfo)
        {
          iA = INFO_AT(-1.0, -1.0); iC = INFO_AT(1.0, -1.0); iG = INFO_AT(-1.0, 1.0); iI = INFO_AT(1.0, 1.0);
          haveDiagInfo = true;
        }
        vec4 bk22D = max(FLAG(vec4(iC.x, iI.y, iG.z, iA.w), 128.0), FLAG(vec4(iG.x, iA.y, iC.z, iI.w), 128.0));
        bk22 = max(bk22, bk22D);
        needRing = any(greaterThan(cutInit * (1.0 - line) * bk22D, vec4(0.0)));
      }

      if (needRing)
      {
        if (!haveDiagInfo)
        {
          iA = INFO_AT(-1.0, -1.0); iC = INFO_AT(1.0, -1.0); iG = INFO_AT(-1.0, 1.0); iI = INFO_AT(1.0, 1.0);
          haveDiagInfo = true;
        }
        bk22 = max(bk22, max(FLAG(vec4(iC.x, iI.y, iG.z, iA.w), 128.0), FLAG(vec4(iG.x, iA.y, iC.z, iI.w), 128.0)));
        cA = cutNoWeak(iA); cC = cutNoWeak(iC); cG = cutNoWeak(iG); cI = cutNoWeak(iI);
        haveDiagCut = true;
        if (!haveDiagPix)
        {
          cachedA = toYCbCr(P(-1., -1.)); cachedC = toYCbCr(P(1., -1.));
          cachedG = toYCbCr(P(-1.,  1.)); cachedI = toYCbCr(P(1.,  1.));
          haveDiagPix = true;
        }
        A = cachedA; C = cachedC; G = cachedG; I = cachedI;
        dE1_raw = sqrt(dE1Sq);
        dLO_raw = sqrt(dLOSq);
        dE4 = dE1_raw * 255.0;
        cand20 = dLO_raw * 255.0;
        haveSqrt = true;
        vec3 luu = toYCbCr(P(-1., -2.)), uu = toYCbCr(P(0., -2.)), ruu = toYCbCr(P(1., -2.));
        vec3 llu = toYCbCr(P(-2., -1.)), ll = toYCbCr(P(-2., 0.)), lld = toYCbCr(P(-2., 1.));
        vec3 rru = toYCbCr(P( 2., -1.)), rr = toYCbCr(P( 2., 0.)), rrd = toYCbCr(P( 2., 1.));
        vec3 ldd = toYCbCr(P(-1.,  2.)), dd = toYCbCr(P( 0., 2.)), rdd = toYCbCr(P( 1., 2.));

        // ---- 17. A line drawn on one side only ----
        if (any(greaterThan(hit17, vec4(0.0))))
        {
          vec4 oDraw = hit17;
          vec4 cSh = vec4(max(sameF(D, ll), sameF(C, rru)), max(sameF(B, uu), sameF(I, rdd)),
                          max(sameF(F, rr), sameF(G, lld)), max(sameF(H, dd), sameF(A, luu)));
          vec4 cSt = vec4(max(sameF(B, uu), sameF(G, ldd)), max(sameF(F, rr), sameF(A, llu)),
                          max(sameF(H, dd), sameF(C, ruu)), max(sameF(D, ll), sameF(I, rrd)));
          oDraw *= 1.0 - mix(cSt, cSh, sh);
          vec4 rSh = vec4(sameAsOne(E, rru, lld), sameAsOne(E, rdd, luu), sameAsOne(E, rru, lld), sameAsOne(E, rdd, luu));
          vec4 rSt = vec4(sameAsOne(E, ruu, ldd), sameAsOne(E, rrd, llu), sameAsOne(E, ruu, ldd), sameAsOne(E, rrd, llu));
          oDraw *= 1.0 - mix(rSt, rSh, sh);
          vec4 dLE = dE1_raw.yxzw;
          vec4 dOE = dE1_raw.xzwy;
          oDraw *= vec4(greaterThan(dLE + dOE, XBRZ_LONE_RAMP * dLO_raw));
          blendResult *= 1.0 - oDraw;
        }

        // ---- 19. A pixel apart keeps to itself ----
        if (anyCut(blendResult))
        {
          vec4 c19 = isCut(blendResult);
          vec4 sqOther19 = vec4(sec.x > 0.5 ? sqD : sqB, sec.y > 0.5 ? sqB : sqF, sec.z > 0.5 ? sqF : sqH, sec.w > 0.5 ? sqH : sqD);
          vec4 need19 = c19 * max(sq19, max(sqOther19 * vec4(greaterThanEqual(cand20, vec4(XBRZ_ISO_FAR))),
                                            (1.0 - line) * vec4(greaterThanEqual(cand20, vec4(XBRZ_ISO_FAR)))));
          if (any(greaterThan(need19, vec4(0.0))))
          {
            float isoB = 0.0, isoD = 0.0, isoF = 0.0, isoH = 0.0;
            if (need19.x + need19.y > 0.0) isoB = isoSqOf5(B, min(dE1Sq.x, min(dLOSq.x, dLOSq.y)), luu, uu, ruu, A, C);
            if (need19.x + need19.w > 0.0) isoD = isoSqOf5(D, min(dE1Sq.y, min(dLOSq.x, dLOSq.w)), llu, A, ll, lld, G);
            if (need19.y + need19.z > 0.0) isoF = isoSqOf5(F, min(dE1Sq.z, min(dLOSq.y, dLOSq.z)), C, rru, rr, I, rrd);
            if (need19.z + need19.w > 0.0) isoH = isoSqOf5(H, min(dE1Sq.w, min(dLOSq.z, dLOSq.w)), G, I, ldd, dd, rdd);
            vec4 near19 = vec4(sec.x > 0.5 ? isoB : isoD, sec.y > 0.5 ? isoF : isoB, sec.z > 0.5 ? isoH : isoF, sec.w > 0.5 ? isoD : isoH);
            vec4 otherNear19 = vec4(sec.x > 0.5 ? isoD : isoB, sec.y > 0.5 ? isoB : isoF, sec.z > 0.5 ? isoF : isoH, sec.w > 0.5 ? isoH : isoD);
            vec4 dEP19 = mix(dE4.yxzw, dE4.xzwy, sec), dEQ19 = mix(dE4.xzwy, dE4.yxzw, sec);
            vec4 notRamp19 = vec4(greaterThan(dEP19 + cand20, XBRZ_JUNC_RAMP3 * dEQ19));
            vec4 iso = vec4(greaterThanEqual(near19, vec4(SQ255(XBRZ_ISO))))
                     * max(sq19, (1.0 - line) * vec4(greaterThanEqual(cand20, vec4(XBRZ_ISO_FAR))) * notRamp19);
            vec4 otherIso = vec4(greaterThanEqual(otherNear19, vec4(SQ255(XBRZ_ISO)))) * sqOther19
                          * vec4(greaterThanEqual(cand20, vec4(XBRZ_ISO_FAR)));
            vec4 blockP = vec4(
              sec.x > 0.5 ? (sameF(B, uu) * sameF(B, A)) : (sameF(D, ll) * sameF(D, A)),
              sec.y > 0.5 ? (sameF(F, rr) * sameF(F, C)) : (sameF(B, uu) * sameF(B, C)),
              sec.z > 0.5 ? (sameF(H, dd) * sameF(H, I)) : (sameF(F, rr) * sameF(F, I)),
              sec.w > 0.5 ? (sameF(D, ll) * sameF(D, G)) : (sameF(H, dd) * sameF(H, G)));
            otherIso *= max(blockP, vec4(
              sec.x > 0.5 ? (sameF(B, C) * (1.0 - sameF(B, A))) : (sameF(D, G) * (1.0 - sameF(D, A))),
              sec.y > 0.5 ? (sameF(F, I) * (1.0 - sameF(F, C))) : (sameF(B, A) * (1.0 - sameF(B, C))),
              sec.z > 0.5 ? (sameF(H, G) * (1.0 - sameF(H, I))) : (sameF(F, C) * (1.0 - sameF(F, I))),
              sec.w > 0.5 ? (sameF(D, A) * (1.0 - sameF(D, G))) : (sameF(H, I) * (1.0 - sameF(H, G)))));
            vec4 lone = vec4(greaterThanEqual(near19, vec4(SQ255(XBRZ_SAME)))) * (1.0 - line)
                      * vec4(greaterThanEqual(cand20, vec4(XBRZ_ISO_FAR)))
                      * vec4(greaterThanEqual(vec4(min(distSqY(A, B), distSqY(A, D)), min(distSqY(C, F), distSqY(C, B)),
                                                   min(distSqY(I, H), distSqY(I, F)), min(distSqY(G, D), distSqY(G, H))), vec4(SQ255(XBRZ_SAME))));
            blendResult *= 1.0 - max(max(iso, otherIso), lone);
          }
        }

        // ---- 20. A corner where no edge runs ----
        {
          vec4 dE1 = dE4.yxzw, dE2 = dE1.yzwx;
          vec4 gate20 = isCut(blendResult) * vec4(greaterThan(cand20, vec4(XBRZ_JUNCTION))) * vec4(greaterThanEqual(min(dE1, dE2), XBRZ_JUNC_TONE * cand20));
          if (any(greaterThan(gate20, vec4(0.0))))
          {
            vec4 ramp20 = vec4(lessThan(dE1 + dE2 + cand20, (1.0 + XBRZ_JUNC_RAMP) * max(cand20, max(dE1, dE2))));
            vec4 cr20 = max(vec4(junctionNear(B, lld), junctionNear(F, luu), junctionNear(H, rru), junctionNear(D, rdd)),
                            vec4(junctionNear(D, ruu), junctionNear(B, rrd), junctionNear(F, ldd), junctionNear(H, llu)));
            vec4 lu20 = vec4(D.x, B.x, F.x, H.x);
            vec4 lmin20 = min(min(lu20, lu20.yzwx), vec4(E.x));
            vec4 ext1 = vec4(junctionNear(D, lld), junctionNear(B, luu), junctionNear(F, rru), junctionNear(H, rdd));
            vec4 ext2 = vec4(junctionNear(B, ruu), junctionNear(F, rrd), junctionNear(H, ldd), junctionNear(D, llu));
            vec4 nbASq = vec4(distSqY(D, A), distSqY(B, C), distSqY(F, I), distSqY(H, G));
            vec4 nbBSq = vec4(distSqY(B, A), distSqY(F, C), distSqY(H, I), distSqY(D, G));
            vec4 dgESq = vec4(distSqY(E, A), distSqY(E, C), distSqY(E, I), distSqY(E, G));
            vec4 sNbA = vec4(lessThan(nbASq, vec4(SQ255(XBRZ_SAME))));
            vec4 sNbB = vec4(lessThan(nbBSq, vec4(SQ255(XBRZ_SAME))));
            vec4 sDgE = vec4(lessThan(dgESq, vec4(SQ255(XBRZ_SAME))));
            vec4 d4_20 = gate20 * vec4(greaterThan(min(min(nbASq, nbBSq), dgESq), vec4(SQ255(XBRZ_JUNCTION))));
            vec4 orthoBlock = vec4(0.0);
            if (any(greaterThan(d4_20, vec4(0.0))))
            {
              float sDll = sameF(D, ll), sBuu = sameF(B, uu), sFrr = sameF(F, rr), sHdd = sameF(H, dd);
              vec4 cross20 = vec4(0.0);
              if (E.x <= XBRZ_DARK)
              {
                cross20 = d4_20 * vec4(greaterThan(min(dE1, dE2), vec4(XBRZ_JUNCTION)))
                        * vec4(lessThan(vec4(E.x), min(lu20, lu20.yzwx))) * line;
                float loD = 1.0 - max(sNbA.x, max(sNbB.w, sDll)), loB = 1.0 - max(sNbB.x, max(sNbA.y, sBuu));
                float loF = 1.0 - max(sNbB.y, max(sNbA.z, sFrr)), loH = 1.0 - max(sNbA.w, max(sNbB.z, sHdd));
                cross20 *= vec4(mix(loD, loB, sec.x), mix(loB, loF, sec.y), mix(loF, loH, sec.z), mix(loH, loD, sec.w));
              }
              vec4 blkC20 = vec4(sameF(A, llu) * sameF(A, luu), sameF(C, ruu) * sameF(C, rru), sameF(I, rrd) * sameF(I, rdd), sameF(G, ldd) * sameF(G, lld));
              vec4 blk1_20 = sNbB.wxyz * vec4(sDll, sBuu, sFrr, sHdd);
              vec4 blk2_20 = sNbA.yzwx * vec4(sBuu, sFrr, sHdd, sDll);
              vec4 vOrtho = vec4(sBuu * sECard.w, sFrr * sECard.y, sHdd * sECard.x, sDll * sECard.z);
              vec4 ortho1 = d4_20 * blkC20 * vOrtho;
              vec4 ortho2 = d4_20 * blkC20 * vOrtho.wxyz;
              ext1 *= 1.0 - max(cross20, ortho1) * blk1_20;
              ext2 *= 1.0 - max(cross20, ortho2) * blk2_20;
              orthoBlock = max(ortho1 * blk1_20, ortho2 * blk2_20);
            }
            vec4 jnDgE = vec4(lessThan(dgESq, vec4(SQ255(XBRZ_JUNC_NEAR))));
            float eAcross = max(jnDgE.w, jnDgE.y), eAlong = max(jnDgE.x, jnDgE.z);
            bool grayE = dot(E.yz, E.yz) < SQ255(XBRZ_JUNC_GRAY);
            float sC = grayE && chromaSqY(E, C) < SQ255(XBRZ_JUNC_HUE) ? dgESq.y : 4.0, sG = grayE && chromaSqY(E, G) < SQ255(XBRZ_JUNC_HUE) ? dgESq.w : 4.0;
            float sA = grayE && chromaSqY(E, A) < SQ255(XBRZ_JUNC_HUE) ? dgESq.x : 4.0, sI = grayE && chromaSqY(E, I) < SQ255(XBRZ_JUNC_HUE) ? dgESq.z : 4.0;
            vec4 shadeLimSq = (XBRZ_JUNC_SHADE / 255.0) * min(dE1, dE2);
            shadeLimSq *= shadeLimSq;
            vec4 extE = max(vec4(eAcross, eAlong, eAcross, eAlong), vec4(lessThan(vec4(min(sC, sG), min(sA, sI), min(sC, sG), min(sA, sI)), shadeLimSq)));
            vec4 chr20Sq = vec4(chromaSqY(B, D), chromaSqY(B, F), chromaSqY(F, H), chromaSqY(D, H));
            float gB20 = dot(B.yz, B.yz), gD20 = dot(D.yz, D.yz), gF20 = dot(F.yz, F.yz), gH20 = dot(H.yz, H.yz);
            vec4 gray20 = vec4(lessThan(vec4(max(gB20, gD20), max(gB20, gF20), max(gF20, gH20), max(gD20, gH20)), vec4(SQ255(XBRZ_JUNC_GRAY))));
            vec4 on20 = gate20
                      * (1.0 - vec4(lessThan(cand20, XBRZ_JUNC_SHADE * min(dE1, dE2))) * vec4(lessThan(chr20Sq, vec4(SQ255(XBRZ_JUNC_HUE)))) * gray20)
                      * (1.0 - ramp20 * cr20 * vec4(greaterThan(min(dE1, dE2), vec4(XBRZ_JUNC_AA_MIN))) * vec4(lessThan(min(dE1, dE2), vec4(XBRZ_JUNC_AA_MAX))) * vec4(lessThan(lmin20, vec4(XBRZ_JUNC_AA_DARK))))
                      * (1.0 - ext1) * (1.0 - ext2) * (1.0 - extE);
            if (any(greaterThan(on20, vec4(0.0))))
            {
              vec4 tipH = vec4(sNbB.x * cB.z * cA.w, sNbA.y * cB.w * cC.z, sNbB.z * cH.x * cI.y, sNbA.w * cH.y * cG.x);
              vec4 tipV = vec4(sNbA.x * cD.z * cA.y, sNbB.y * cF.w * cC.x, sNbA.z * cF.x * cI.w, sNbB.w * cD.y * cG.z);
              on20 *= 1.0 - mix(tipV, tipH, vec4(1.0 - sec.x, sec.y, 1.0 - sec.z, sec.w));
              vec4 half20 = mix(vec4(cD.z, cB.w, cF.x, cH.y), vec4(cB.z, cF.w, cH.x, cD.y), sec);
              vec4 w20 = mix(vec4(iG.z, iA.w, iC.x, iI.y), vec4(iC.z, iI.w, iG.x, iA.y), haveShallowLine);
              vec4 far20 = line * abs(haveShallowLine - haveSteepLine) * mix(sECard.wyxz, sECard.zwyx, haveShallowLine)
                         * drawsLine4(w20)
                         * vec4(equal(FLAG(w20, BIT_SEC), haveShallowLine))
                         * vec4(equal(FLAG(w20, BIT_SHALLOW), haveShallowLine))
                         * vec4(equal(FLAG(w20, BIT_STEEP), haveSteepLine))
                         * (1.0 - orthoBlock);
              on20 *= 1.0 - max(half20, far20) * vec4(lessThan(cand20, 0.5 * min(dE1, dE2)));
              vec4 fetch20 = on20 * (1.0 - orthoBlock);
              vec4 m2 = (fetch20.y * cA.y + fetch20.w * cA.w > 0.0) ? cutNoWeak(INFO_AT(-2.0, -2.0)) : vec4(0.0);
              vec4 p2 = (fetch20.y * cI.y + fetch20.w * cI.w > 0.0) ? cutNoWeak(INFO_AT( 2.0,  2.0)) : vec4(0.0);
              vec4 u2 = (fetch20.x * cC.x + fetch20.z * cC.z > 0.0) ? cutNoWeak(INFO_AT( 2.0, -2.0)) : vec4(0.0);
              vec4 d2 = (fetch20.x * cG.x + fetch20.z * cG.z > 0.0) ? cutNoWeak(INFO_AT(-2.0,  2.0)) : vec4(0.0);
              vec4 runA = vec4(cC.x + cC.x * u2.x, cA.y + cA.y * m2.y, cC.z + cC.z * u2.z, cA.w + cA.w * m2.w);
              vec4 runB = vec4(cG.x + cG.x * d2.x, cI.y + cI.y * p2.y, cG.z + cG.z * d2.z, cI.w + cI.w * p2.w);
              on20 *= max(vec4(lessThan(1.0 + runA + runB, vec4(3.0))), orthoBlock);
              vec4 maxE20 = max(dE1, dE2);
              vec4 wide20 = max(vec4(lessThan(dE1 + dE2 + cand20, (1.0 + XBRZ_JUNC_RAMP2) * max(cand20, maxE20))),
                                vec4(lessThan(dE1 + dE2 + cand20, (1.0 + XBRZ_JUNC_RAMP3) * maxE20)) * vec4(lessThan(cand20, maxE20))
                                * vec4(greaterThan(min(cand20, min(dE1, dE2)), XBRZ_JUNC_MID * maxE20)) * vec4(greaterThan(maxE20, vec4(XBRZ_JUNC_FAR))));
              vec4 keep20 = max(vec4(greaterThan(runA + runB, vec4(0.5))), (isCut(blendResult) * (1.0 - on20)).zwxy);
              on20 *= 1.0 - keep20 * wide20 * (1.0 - orthoBlock);
              if (any(greaterThan(on20, vec4(0.0))))
              {
                vec4 frame20 = vec4(sNbA.y * sameF(B, rru) * sNbB.w * sameF(D, ldd) * cA.z * max(sameF(A, uu), sameF(A, ll)),
                                    sNbB.x * sameF(B, llu) * sNbA.z * sameF(F, rdd) * cC.w * max(sameF(C, uu), sameF(C, rr)),
                                    sNbB.y * sameF(F, ruu) * sNbA.w * sameF(H, lld) * cI.x * max(sameF(I, rr), sameF(I, dd)),
                                    sNbA.x * sameF(D, luu) * sNbB.z * sameF(H, rrd) * cG.y * max(sameF(G, ll), sameF(G, dd)))
                             * (1.0 - sDgE);
                on20 *= 1.0 - frame20;
                if (any(greaterThan(on20, vec4(0.0))))
                {
                  float aaV = aa20(B, H, uu, dd, dE1_raw.x, dE1_raw.w);
                  float aaH = aa20(D, F, ll, rr, dE1_raw.y, dE1_raw.z);
                  vec4 aa = vec4(mix(aaH, aaV, sec.x), mix(aaV, aaH, sec.y), mix(aaH, aaV, sec.z), mix(aaV, aaH, sec.w));
                  vec4 c20 = isCut(blendResult);
                  vec4 tip1 = sDgE.zwxy * (1.0 - sDgE) * vec4(c20.y * c20.w, c20.x * c20.z, c20.y * c20.w, c20.x * c20.z);
                  on20 *= (1.0 - aa) * (1.0 - tip1);
                  blendResult *= 1.0 - on20;
                }
              }
            }
          }
        }

        // ---- 21. A straight line does not bend ----
        if (any(greaterThan(isCut(blendResult) * vec4(greaterThan(cand20, vec4(XBRZ_LINE_SIDE))), vec4(0.0))))
        {
          vec4 line21 = vec4(0.0), on21 = vec4(0.0);
          vec4 partSh = vec4(max(cD.z, cC.z), max(cF.w, cA.w), max(cF.x, cG.x), max(cD.y, cI.y));
          vec4 partSt = vec4(max(cB.z, cG.z), max(cB.w, cI.w), max(cH.x, cC.x), max(cH.y, cA.y));
          vec4 shOn = line * vec4(haveShallowLine.x, haveSteepLine.y, haveShallowLine.z, haveSteepLine.w);
          vec4 stOn = line * vec4(haveSteepLine.x, haveShallowLine.y, haveSteepLine.z, haveShallowLine.w);
          vec4 part21 = max(partSh * (1.0 - stOn * (1.0 - shOn)), partSt * (1.0 - shOn * (1.0 - stOn)));
          vec4 run21 = max(part21, vec4(max(cC.x, cG.x), max(cA.y, cI.y), max(cC.z, cG.z), max(cA.w, cI.w)));
          if (blendResult.x > 0.0 && cand20.x > XBRZ_LINE_SIDE) { vec2 t = straight21(ROLES_0(sec.x), E, run21.x, dLOSq.x, sec.x > 0.5 ? dE1Sq.x : dE1Sq.y, sec.x > 0.5 ? dE1Sq.y : dE1Sq.x); line21.x = t.x; on21.x = t.y; }
          if (blendResult.y > 0.0 && cand20.y > XBRZ_LINE_SIDE) { vec2 t = straight21(ROLES_1(sec.y), E, run21.y, dLOSq.y, sec.y > 0.5 ? dE1Sq.z : dE1Sq.x, sec.y > 0.5 ? dE1Sq.x : dE1Sq.z); line21.y = t.x; on21.y = t.y; }
          if (blendResult.z > 0.0 && cand20.z > XBRZ_LINE_SIDE) { vec2 t = straight21(ROLES_2(sec.z), E, run21.z, dLOSq.z, sec.z > 0.5 ? dE1Sq.w : dE1Sq.z, sec.z > 0.5 ? dE1Sq.z : dE1Sq.w); line21.z = t.x; on21.z = t.y; }
          if (blendResult.w > 0.0 && cand20.w > XBRZ_LINE_SIDE) { vec2 t = straight21(ROLES_3(sec.w), E, run21.w, dLOSq.w, sec.w > 0.5 ? dE1Sq.y : dE1Sq.w, sec.w > 0.5 ? dE1Sq.w : dE1Sq.y); line21.w = t.x; on21.w = t.y; }
          sec = abs(sec - on21);
          haveShallowLine *= 1.0 - on21;
          haveSteepLine *= 1.0 - on21;
          blendResult *= 1.0 - line21 * (1.0 - on21);
        }

        // ---- 37. A contour by a knight's move ----
        if (any(greaterThan(isCut(blendResult) * vec4(greaterThanEqual(cand20, vec4(24.0))), vec4(0.0))))
        {
          vec4 cutK = isCut(blendResult);
          vec4 sB = FLAG(iB, BIT_SEC), sD = FLAG(iD, BIT_SEC), sF = FLAG(iF, BIT_SEC), sH = FLAG(iH, BIT_SEC);
          vec4 flipK = vec4(0.0);
          if (cutK.x > 0.5 && cand20.x >= 24.0) flipK.x = knightFlip37(sec.x > 0.5, D, B, G, C, dE4.y, dE4.x, cand20.x, cD.z, sD.z, cB.z, sB.z);
          if (cutK.y > 0.5 && cand20.y >= 24.0) flipK.y = knightFlip37(sec.y > 0.5, B, F, A, I, dE4.x, dE4.z, cand20.y, cB.w, sB.w, cF.w, sF.w);
          if (cutK.z > 0.5 && cand20.z >= 24.0) flipK.z = knightFlip37(sec.z > 0.5, F, H, C, G, dE4.z, dE4.w, cand20.z, cF.x, sF.x, cH.x, sH.x);
          if (cutK.w > 0.5 && cand20.w >= 24.0) flipK.w = knightFlip37(sec.w > 0.5, H, D, I, A, dE4.w, dE4.y, cand20.w, cH.y, sH.y, cD.y, sD.y);
          if (any(greaterThan(flipK, vec4(0.0))))
          {
            vec4 straightO = vec4(sameF(A, sec.x > 0.5 ? D : B), sameF(C, sec.y > 0.5 ? B : F), sameF(I, sec.z > 0.5 ? F : H), sameF(G, sec.w > 0.5 ? H : D));
            vec4 lineO = vec4(sec.x > 0.5 ? sameF(G, D) : sameF(C, B), sec.y > 0.5 ? sameF(A, B) : sameF(I, F),
                              sec.z > 0.5 ? sameF(C, F) : sameF(G, H), sec.w > 0.5 ? sameF(I, H) : sameF(A, D));
            vec4 block37 = vec4(sECard.z * sECard.w * sameF(E, I), sECard.y * sECard.w * sameF(E, G),
                                sECard.x * sECard.y * sameF(E, A), sECard.x * sECard.z * sameF(E, C));
            blendResult *= 1.0 - flipK * straightO * lineO * block37;
            flipK *= 1.0 - straightO;
            sec = abs(sec - flipK);
            haveShallowLine *= 1.0 - flipK * sec;
            haveSteepLine   *= 1.0 - flipK * (1.0 - sec);
          }
        }

        // ---- 22. Crossed cuts ----
        if (any(greaterThan(bk22 * isCut(blendResult), vec4(0.0))))
        {
          float loneE = float(min(min(dE4.x, dE4.y), min(dE4.z, dE4.w)) >= XBRZ_SAME);
          if (blendResult.x > 0.0 && bk22.x > 0.0) { Roles r = ROLES_0(sec.x); float b = back22(r, E, info.x, blockedBit.x, loneE); if (b < 0.5 && line.x < 0.5) b = tip22(r, E); x22.x = b; }
          if (blendResult.y > 0.0 && bk22.y > 0.0) { Roles r = ROLES_1(sec.y); float b = back22(r, E, info.y, blockedBit.y, loneE); if (b < 0.5 && line.y < 0.5) b = tip22(r, E); x22.y = b; }
          if (blendResult.z > 0.0 && bk22.z > 0.0) { Roles r = ROLES_2(sec.z); float b = back22(r, E, info.z, blockedBit.z, loneE); if (b < 0.5 && line.z < 0.5) b = tip22(r, E); x22.z = b; }
          if (blendResult.w > 0.0 && bk22.w > 0.0) { Roles r = ROLES_3(sec.w); float b = back22(r, E, info.w, blockedBit.w, loneE); if (b < 0.5 && line.w < 0.5) b = tip22(r, E); x22.w = b; }
          blendResult *= 1.0 - x22;
        }

        // ---- 28. Two 2:1 cuts that cross ----
        vec4 p28pre = isCut(blendResult) * line * mix(haveSteepLine, haveShallowLine, sec);
        if (any(greaterThan(p28pre, vec4(0.5))))
        {
          vec4 nW = mix(oSt17, oSh17, sec);
          vec4 pair = p28pre * drawsLine4(nW) * vec4(equal(FLAG(nW, BIT_SEC), sec))
                    * mix(FLAG(nW, BIT_STEEP), FLAG(nW, BIT_SHALLOW), sec)
                    * (1.0 - FLAG(nW, BIT_TONE) * (1.0 - blockedBit) * (1.0 - weak));
          if (any(greaterThan(pair, vec4(0.5))))
          {
            float hE = holdOf28(E, A, B, C, D, F, G, H, I), hB = 0.0, hD = 0.0, hF = 0.0, hH = 0.0;
            if (pair.x * sec.x + pair.y * (1.0 - sec.y) > 0.0) hB = holdOf28(B, luu, uu, ruu, A, C, D, E, F);
            if (pair.x * (1.0 - sec.x) + pair.w * sec.w > 0.0) hD = holdOf28(D, llu, A, B, ll, E, lld, G, H);
            if (pair.y * sec.y + pair.z * (1.0 - sec.z) > 0.0) hF = holdOf28(F, B, C, rru, E, rr, H, I, rrd);
            if (pair.z * sec.z + pair.w * (1.0 - sec.w) > 0.0) hH = holdOf28(H, D, E, F, G, I, ldd, dd, rdd);
            vec4 hN = mix(vec4(hD, hB, hF, hH), vec4(hB, hF, hH, hD), sec);
            blendResult *= 1.0 - pair * whole28Mask(hE, hN, sec, E, B, D, F, H);
          }
        }

        // ---- 29. The burr of a square stroke ----
        if (E.x <= XBRZ_DARK && dot(sECard, vec4(1.0)) == 1.0
            && any(greaterThan(isCut(blendResult) * line * vec4(greaterThan(cand20, vec4(XBRZ_JUNCTION))), vec4(0.0))))
        {
          vec4 nC = mix(vec4(cD.y, cB.z, cF.w, cH.x), vec4(cB.w, cF.x, cH.y, cD.z), sec);
          vec4 dEN = mix(dE4.yxzw, dE4.xzwy, sec);
          vec4 cP = vec4(cA.z, cC.w, cI.x, cG.y);
          vec4 oA = mix(vec4(sameF(A, B), sameF(C, F), sameF(I, H), sameF(G, D)), vec4(sameF(A, D), sameF(C, B), sameF(I, F), sameF(G, H)), sec);
          vec4 ok = vec4(lessThan(vec4(iC.x, iA.y, iC.z, iA.w), vec4(BIT_BLOCKED))) * vec4(cC.x, cA.y, cC.z, cA.w) + vec4(lessThan(vec4(iG.x, iI.y, iG.z, iI.w), vec4(BIT_BLOCKED))) * vec4(cG.x, cI.y, cG.z, cI.w);
          vec4 tip = vec4(sECard.z + sECard.w, sECard.y + sECard.w, sECard.x + sECard.y, sECard.x + sECard.z);
          vec4 lN = mix(vec4(D.x, B.x, F.x, H.x), vec4(B.x, F.x, H.x, D.x), sec);
          float sA = sameF(E, A), sC = sameF(E, C), sG = sameF(E, G), sI = sameF(E, I);
          tip *= 1.0 - min(vec4(sA + sC + sG, sC + sA + sI, sI + sC + sG, sG + sA + sI), vec4(1.0));
          tip *= vec4(greaterThan(lN, vec4(E.x)));
          vec4 burr = tip * vec4(lessThan(ok, vec4(0.5))) * isCut(blendResult) * line * oA * (1.0 - nC) * (1.0 - cP)
                    * vec4(greaterThan(cand20, vec4(XBRZ_JUNCTION))) * vec4(greaterThanEqual(dEN, vec4(XBRZ_STRAIGHT)));
          blendResult *= 1.0 - burr;
        }
      }
      else
      {
        // ---- 28 (lean non-ring path: fetch only 0 or 3 outer texels per active neighbor instead of all 12) ----
        vec4 p28pre = cutInit * line * mix(st, sh, sec);
        if (any(greaterThan(p28pre, vec4(0.5))))
        {
          vec4 nW = mix(oSt17, oSh17, sec);
          vec4 pair = p28pre * drawsLine4(nW) * vec4(equal(FLAG(nW, BIT_SEC), sec))
                    * mix(FLAG(nW, BIT_STEEP), FLAG(nW, BIT_SHALLOW), sec)
                    * (1.0 - FLAG(nW, BIT_TONE) * (1.0 - blockedBit) * (1.0 - weak));
          if (any(greaterThan(pair, vec4(0.5))))
          {
            if (!haveDiagPix)
            {
              cachedA = toYCbCr(P(-1., -1.)); cachedC = toYCbCr(P(1., -1.));
              cachedG = toYCbCr(P(-1.,  1.)); cachedI = toYCbCr(P(1.,  1.));
              haveDiagPix = true;
            }
            A = cachedA; C = cachedC; G = cachedG; I = cachedI;
            float hE = holdOf28(E, A, B, C, D, F, G, H, I), hB = 0.0, hD = 0.0, hF = 0.0, hH = 0.0;
            if (pair.x * sec.x + pair.y * (1.0 - sec.y) > 0.0) hB = holdOfEdge28(B, hE, D, F, A, C, E, vec2(-1.,-2.), vec2( 0.,-2.), vec2( 1.,-2.));
            if (pair.x * (1.0 - sec.x) + pair.w * sec.w > 0.0) hD = holdOfEdge28(D, hE, B, H, A, E, G, vec2(-2.,-1.), vec2(-2., 0.), vec2(-2., 1.));
            if (pair.y * sec.y + pair.z * (1.0 - sec.z) > 0.0) hF = holdOfEdge28(F, hE, B, H, C, E, I, vec2( 2.,-1.), vec2( 2., 0.), vec2( 2., 1.));
            if (pair.z * sec.z + pair.w * (1.0 - sec.w) > 0.0) hH = holdOfEdge28(H, hE, D, F, E, G, I, vec2(-1., 2.), vec2( 0., 2.), vec2( 1., 2.));
            vec4 hN = mix(vec4(hD, hB, hF, hH), vec4(hB, hF, hH, hD), sec);
            blendResult *= 1.0 - pair * whole28Mask(hE, hN, sec, E, B, D, F, H);
          }
        }
      }

      // ---- 24. A line with nothing to go on to ----
      if (anyCut(blendResult))
      {
        vec4 pDistSq = mix(dE1Sq.yxzw, dE1Sq.xzwy, sec);
        vec4 lone24 = line * isCut(blendResult) * abs(haveShallowLine - haveSteepLine)
                    * vec4(greaterThanEqual(pDistSq, vec4(SQ255(XBRZ_HOOK))));
        if (any(greaterThan(lone24, vec4(0.0))))
        {
          if (!haveDiagInfo)
          {
            iA = INFO_AT(-1.0, -1.0); iC = INFO_AT(1.0, -1.0); iG = INFO_AT(-1.0, 1.0); iI = INFO_AT(1.0, 1.0);
            haveDiagInfo = true;
          }
          if (!haveDiagCut) { cA = cutNoWeak(iA); cC = cutNoWeak(iC); cG = cutNoWeak(iG); cI = cutNoWeak(iI); haveDiagCut = true; }
          vec4 partSh = vec4(max(cD.z, cC.z), max(cF.w, cA.w), max(cF.x, cG.x), max(cD.y, cI.y));
          vec4 partSt = vec4(max(cB.z, cG.z), max(cB.w, cI.w), max(cH.x, cC.x), max(cH.y, cA.y));
          vec4 steepOnScreen = vec4(haveSteepLine.x, haveShallowLine.y, haveSteepLine.z, haveShallowLine.w);
          vec4 part = mix(partSh, partSt, steepOnScreen);
          vec4 dW24 = vec4(iA.z, iC.w, iI.x, iG.y);
          vec4 diag24 = drawsLine4(dW24)
                      * vec4(equal(FLAG(dW24, BIT_SHALLOW), haveShallowLine))
                      * vec4(equal(FLAG(dW24, BIT_STEEP), haveSteepLine))
                      * vec4(lessThan(dLOSq, vec4(SQ255(XBRZ_SAME))));
          hook24 = lone24 * (1.0 - max(part, diag24));
        }
      }

      // ---- 25. A point on a shared edge ----
      {
        vec4 pl = isCut(blendResult) * line * (1.0 - haveShallowLine) * (1.0 - haveSteepLine);
        if (pl.x + pl.y + pl.z + pl.w > 1.5)
        {
          float pB = pl.x * pl.y * sec.x * (1.0 - sec.y), pF = pl.y * pl.z * sec.y * (1.0 - sec.z);
          float pH = pl.z * pl.w * sec.z * (1.0 - sec.w), pD = pl.w * pl.x * sec.w * (1.0 - sec.x);
          if (pB + pF + pH + pD > 0.0)
          {
            if (!haveDiagPix)
            {
              cachedA = toYCbCr(P(-1., -1.)); cachedC = toYCbCr(P(1., -1.));
              cachedG = toYCbCr(P(-1.,  1.)); cachedI = toYCbCr(P(1.,  1.));
              haveDiagPix = true;
            }
            A = cachedA; C = cachedC; G = cachedG; I = cachedI;
            if (pB > 0.0) pB = point25(E, B, D, F, G, I, H, vec2(-2., 2.), vec2( 2., 2.), A, C);
            if (pF > 0.0) pF = point25(E, F, B, H, A, G, D, vec2(-2.,-2.), vec2(-2., 2.), C, I);
            if (pH > 0.0) pH = point25(E, H, F, D, A, C, B, vec2(-2.,-2.), vec2( 2.,-2.), G, I);
            if (pD > 0.0) pD = point25(E, D, H, B, C, I, F, vec2( 2.,-2.), vec2( 2., 2.), A, G);
            blendResult *= 1.0 - min(vec4(pB + pD, pB + pF, pF + pH, pH + pD), vec4(1.0));
          }
        }
      }

      // ---- 23. A loose pixel is a square with rounded corners ----
      float minDE1Sq = min(min(dE1Sq.x, dE1Sq.y), min(dE1Sq.z, dE1Sq.w));
      float nCut23 = dot(isCut(blendResult), vec4(1.0));
      if (nCut23 > 3.5 && minDE1Sq >= SQ255(XBRZ_LOOSE))
      {
        if (!haveDiagPix)
        {
          cachedA = toYCbCr(P(-1., -1.)); cachedC = toYCbCr(P(1., -1.));
          cachedG = toYCbCr(P(-1.,  1.)); cachedI = toYCbCr(P(1.,  1.));
          haveDiagPix = true;
        }
        A = cachedA; C = cachedC; G = cachedG; I = cachedI;
        if (sameF(E, A) + sameF(E, C) + sameF(E, G) + sameF(E, I) < 0.5)
        {
          line = vec4(0.0); haveShallowLine = vec4(0.0); haveSteepLine = vec4(0.0);
          small23 = vec4(1.0);
        }
      }
      // ---- 23b. A loose pixel cut by different colors ----
      if (dot(small23, vec4(1.0)) < 0.5 && nCut23 > 2.5 && minDE1Sq >= SQ255(XBRZ_LONE23))
      {
        if (!haveDiagPix)
        {
          cachedA = toYCbCr(P(-1., -1.)); cachedC = toYCbCr(P(1., -1.));
          cachedG = toYCbCr(P(-1.,  1.)); cachedI = toYCbCr(P(1.,  1.));
          haveDiagPix = true;
        }
        A = cachedA; C = cachedC; G = cachedG; I = cachedI;
        if (!withinY255(E, A, XBRZ_LONE23) && !withinY255(E, C, XBRZ_LONE23) && !withinY255(E, G, XBRZ_LONE23) && !withinY255(E, I, XBRZ_LONE23))
        {
          vec4 cutB = isCut(blendResult);
          vec3 kx = sec.x > 0.5 ? B : D, ky = sec.y > 0.5 ? F : B, kz = sec.z > 0.5 ? H : F, kw = sec.w > 0.5 ? D : H;
          float farSq = 0.0;
          if (cutB.x * cutB.y > 0.5) farSq = max(farSq, distSqY(kx, ky));
          if (cutB.y * cutB.z > 0.5) farSq = max(farSq, distSqY(ky, kz));
          if (cutB.z * cutB.w > 0.5) farSq = max(farSq, distSqY(kz, kw));
          if (cutB.w * cutB.x > 0.5) farSq = max(farSq, distSqY(kw, kx));
          if (cutB.x * cutB.z > 0.5) farSq = max(farSq, distSqY(kx, kz));
          if (cutB.y * cutB.w > 0.5) farSq = max(farSq, distSqY(ky, kw));
          if (farSq >= SQ255(XBRZ_LOOSE))
          {
            vec4 pair = vec4(lessThan(dLOSq, vec4(SQ255(XBRZ_SAME))));
            blendResult *= pair;
            line = vec4(0.0); haveShallowLine = vec4(0.0); haveSteepLine = vec4(0.0);
            small23 = isCut(blendResult);
          }
        }
      }

      // ---- 15b & 14b. Lone-pixel stub recovery (45-deg bridge & dark 2:1 coupling) + 2-1-2 arc smoothing ----
      {
        vec4 cutB = isCut(blendResult);
        vec4 stub = cutB * (1.0 - line) * (1.0 - small23);
        vec4 dMinCSq = min(dE1Sq.yxzw, dE1Sq.xzwy);
        vec4 baseB = stub * vec4(lessThan(dLOSq, vec4(SQ255(XBRZ_SAME)))) * vec4(greaterThanEqual(dMinCSq, vec4(SQ255(XBRZ_STRAIGHT))));
        if (any(greaterThan(baseB, vec4(0.5))))
        {
          if (!haveDiagPix)
          {
            cachedA = toYCbCr(P(-1., -1.)); cachedC = toYCbCr(P(1., -1.));
            cachedG = toYCbCr(P(-1.,  1.)); cachedI = toYCbCr(P(1.,  1.));
            haveDiagPix = true;
          }
          A = cachedA; C = cachedC; G = cachedG; I = cachedI;
          if (!haveDiagInfo)
          {
            iA = INFO_AT(-1.0, -1.0); iC = INFO_AT(1.0, -1.0); iG = INFO_AT(-1.0, 1.0); iI = INFO_AT(1.0, 1.0);
            haveDiagInfo = true;
          }
          vec4 dOppMaxSq = max(dE1Sq.yxzw, dE1Sq.xzwy).zwxy;
          vec4 oppLine = (line * (1.0 - hook24)).zwxy;
          vec4 diagE = vec4(sameF(E, A), sameF(E, C), sameF(E, I), sameF(E, G));
          float notDotE = float(minDE1Sq < SQ255(XBRZ_LOOSE)
                                || dot(diagE, vec4(1.0)) > 0.5);
          float isTwoCut = float(dot(cutB, vec4(1.0)) < 2.5);
          vec4 twoCutBridge = vec4(isTwoCut) * (1.0 - oppLine)
                            * vec4(greaterThanEqual(dLOSq.zwxy, vec4(SQ255(XBRZ_SAME))))
                            * vec4(lessThan(4.0 * dMinCSq.zwxy, dMinCSq));
          vec4 adjLine = cutB * line * vec4(lessThan(dLOSq, vec4(SQ255(XBRZ_SAME)))) * diagE;
          vec4 adjBridge = vec4(isTwoCut) * diagE * max(adjLine.yzwx, adjLine.wxyz);
          vec4 adjWeak = cutB * (1.0 - line) * vec4(greaterThanEqual(dLOSq, vec4(SQ255(XBRZ_SAME))));
          vec4 oW15 = vec4(iA.z, iC.w, iI.x, iG.y);
          vec4 oLine15 = drawsLine4(oW15);
          vec4 lDiag15 = 0.5 * (vec4(D.x, B.x, F.x, H.x) + vec4(B.x, F.x, H.x, D.x));
          vec4 lOpp15 = vec4(A.x, C.x, I.x, G.x);
          vec4 darkDiag15 = vec4(lessThanEqual(lDiag15, vec4(XBRZ_DARK)))
                          * vec4(greaterThanEqual(min(vec4(E.x), lOpp15), lDiag15 + 0.2));
          vec4 darkAdjBridge = vec4(isTwoCut * notDotE) * max(adjWeak.yzwx, adjWeak.wxyz) * oLine15 * darkDiag15;
          vec4 promB = baseB
                     * max(cutB.zwxy * max(vec4(notDotE) * max(1.0 - oppLine, vec4(lessThan(2.25 * dOppMaxSq, dMinCSq))), twoCutBridge),
                           max(adjBridge, darkAdjBridge));
          line = max(line, promB);
          stub *= 1.0 - promB;
        }
        if (E.x <= XBRZ_DARK && any(greaterThan(stub, vec4(0.5))))
        {
          if (!haveDiagPix)
          {
            cachedA = toYCbCr(P(-1., -1.)); cachedC = toYCbCr(P(1., -1.));
            cachedG = toYCbCr(P(-1.,  1.)); cachedI = toYCbCr(P(1.,  1.));
            haveDiagPix = true;
          }
          A = cachedA; C = cachedC; G = cachedG; I = cachedI;
          if (!haveSqrt)
          {
            dE1_raw = sqrt(dE1Sq); dLO_raw = sqrt(dLOSq);
            dE4 = dE1_raw * 255.0; cand20 = dLO_raw * 255.0;
            haveSqrt = true;
          }
          // Exact D4 neighbor words along each corner's local h (shallow) and v (steep) axes:
          // x: h=D, v=B | y: h=B, v=F | z: h=F, v=H | w: h=H, v=D
          vec4 wSh = vec4(iD.x, iB.y, iF.z, iH.w);
          vec4 wSt = vec4(iB.x, iF.y, iH.z, iD.w);
          vec4 nSh = drawsLine4(wSh) * FLAG(wSh, BIT_SHALLOW) * (1.0 - FLAG(wSh, BIT_STEEP));
          vec4 nSt = drawsLine4(wSt) * FLAG(wSt, BIT_STEEP) * (1.0 - FLAG(wSt, BIT_SHALLOW));
          vec4 contE_sh = sECard.zwyx;
          vec4 contE_st = sECard.wyxz;
          vec4 wall_sh  = vec4(sameF(B, A) * sameF(B, C), sameF(F, C) * sameF(F, I),
                               sameF(H, I) * sameF(H, G), sameF(D, G) * sameF(D, A));
          vec4 wall_st  = wall_sh.wxyz;
          vec4 dEh5 = dE4.yxzw, dEv5 = dE4.xzwy;
          vec4 rampSh = vec4(lessThan(dEh5 + cand20, 1.30 * dEv5));
          vec4 rampSt = vec4(lessThan(dEv5 + cand20, 1.30 * dEh5));
          vec4 pSh = stub * nSh * (1.0 - nSt) * contE_sh * wall_sh * rampSh * (1.0 - sec);
          vec4 pSt = stub * nSt * (1.0 - nSh) * contE_st * wall_st * rampSt * sec;
          vec4 prom = max(pSh, pSt);
          line            = max(line, prom);
          haveShallowLine = max(haveShallowLine, pSh);
          haveSteepLine   = max(haveSteepLine,   pSt);
        }
        vec4 plain45 = cutB * line * (1.0 - haveShallowLine) * (1.0 - haveSteepLine)
                     * vec4(lessThan(dLOSq, vec4(SQ255(XBRZ_SAME))));
        if (any(greaterThan(plain45, vec4(0.5))))
        {
          if (!haveDiagPix)
          {
            cachedA = toYCbCr(P(-1., -1.)); cachedC = toYCbCr(P(1., -1.));
            cachedG = toYCbCr(P(-1.,  1.)); cachedI = toYCbCr(P(1.,  1.));
            haveDiagPix = true;
          }
          A = cachedA; C = cachedC; G = cachedG; I = cachedI;
          if (!haveDiagInfo)
          {
            iA = INFO_AT(-1.0, -1.0); iC = INFO_AT(1.0, -1.0); iG = INFO_AT(-1.0, 1.0); iI = INFO_AT(1.0, 1.0);
            haveDiagInfo = true;
          }
          vec4 sameDiag = vec4(sameF(E, C) * sameF(E, G), sameF(E, A) * sameF(E, I),
                               sameF(E, C) * sameF(E, G), sameF(E, A) * sameF(E, I));
          vec4 d1 = vec4(iC.x, iA.y, iC.z, iA.w);
          vec4 d2 = vec4(iG.x, iI.y, iG.z, iI.w);
          vec4 dAct = drawsLine4(d1) * drawsLine4(d2);
          vec4 dSh = plain45 * sameDiag * dAct * FLAG(d1, BIT_SHALLOW) * FLAG(d2, BIT_SHALLOW) * (1.0 - FLAG(d1, BIT_STEEP)) * (1.0 - FLAG(d2, BIT_STEEP));
          vec4 dSt = plain45 * sameDiag * dAct * FLAG(d1, BIT_STEEP) * FLAG(d2, BIT_STEEP) * (1.0 - FLAG(d1, BIT_SHALLOW)) * (1.0 - FLAG(d2, BIT_SHALLOW));
          haveShallowLine = max(haveShallowLine, dSh);
          haveSteepLine   = max(haveSteepLine,   dSt);
        }
      }
    }

    // ---- 14. Straight steps ----
    evalSteps14(blendResult, line, haveSteepLine, haveShallowLine,
                iB, iD, iF, iH, dE1Sq, dLOSq,
                haveE, cachedE, haveCardPix, cBpix, cDpix, cFpix, cHpix,
                haveDiagPix, cachedA, cachedC, cachedG, cachedI,
                nn, ty, thinN, thinSteep);
  }
  vec4 over = vec4(greaterThan(nn, vec4(0.0)));
  haveSteepLine = mix(haveSteepLine, vec4(equal(ty, vec4(1.0))), over);
  haveShallowLine = mix(haveShallowLine, vec4(equal(ty, vec4(2.0))), over);
  hook24 *= 1.0 - over;
  line *= 1.0 - hook24; haveShallowLine *= 1.0 - hook24; haveSteepLine *= 1.0 - hook24;
  thinN *= 1.0 - x22;
  vec4 isThin = vec4(greaterThan(thinN, vec4(0.0)));
  vec4 slope = mix(nn, thinN, isThin);
  vec4 cutFinal = isCut(blendResult);
  vec4 res = min(blendResult, vec4(1.0)) + (2.0 * small23 + 4.0 * line + 8.0 * sec + 16.0 * haveShallowLine + 64.0 * haveSteepLine) * cutFinal;
  res = mix(res, 2.0 + 4.0 + 24.0 * (1.0 - thinSteep) + 64.0 * thinSteep, isThin);
  res += 32.0 * vec4(equal(slope, vec4(3.0))) + 128.0 * vec4(equal(slope, vec4(4.0)));
//#crisp}
//#plain   vec4 cutPlain = vec4(greaterThan(blendResult, vec4(0.0)));
//#plain   vec4 res = min(blendResult, vec4(1.0)) + (4.0 * FLAG(info, 4.0) + 8.0 * FLAG(info, 8.0) + 16.0 * haveShallowLine + 64.0 * haveSteepLine) * cutPlain;
  FRAG_OUT = res / 255.0;
}

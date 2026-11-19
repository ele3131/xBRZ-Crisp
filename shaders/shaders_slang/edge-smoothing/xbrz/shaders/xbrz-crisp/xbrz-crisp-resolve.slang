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
//#crisp{
layout(set = 0, binding = 3) uniform sampler2D xbrz_crisp_refpass;
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define P(x,y) texture(xbrz_crisp_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
//#crisp}
//#plain layout(set = 0, binding = 3) uniform sampler2D xbrz_fs_refpass;
//#plain #define ORIG_SIZE params.xbrz_fs_refpassSize
//#plain #define P(x,y) texture(xbrz_fs_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define OUT_SIZE params.OutputSize
#define ORIG_INPUT_SIZE ORIG_SIZE
#define INFO(uv) texture(Source, uv)
#define INFO_STEP ORIG_SIZE.zw

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
// the first pass's decisions for the four corners of the pixel at (x, y) from E; see the decision
// word in pass 0 (BLEND is the blend type, FLAG(r, f) one of its flags)
#define INFO_RAW(x, y) INFO(coord + vec2(x, y) * INFO_STEP)
#define INFO_AT(x, y) floor(INFO_RAW(x, y) * 255.0 + 0.5)
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)

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
#define XBRZ_HOLD_SAME 30.0    // 28. a neighbor this close in color holds a pixel

// ---- Helpers of the Crisp rules ----
vec2 coord = vec2(0.0);

const vec2 vX = vec2(0., -1.), hX = vec2(-1., 0.), vY = vec2(1., 0.), hY = vec2(0., -1.);
const vec2 vZ = vec2(0., 1.), hZ = vec2(1., 0.), vW = vec2(-1., 0.), hW = vec2(0., 1.);

bool sameColor(vec3 a, vec3 b) { return withinY255(a, b, XBRZ_SAME); }
float chromaSqY(vec3 a, vec3 b)
{
  vec2 dc = a.yz - b.yz;
  return dot(dc, dc);
}
#define XBRZ_KIN37 0.6
bool kin37(vec3 O, vec3 K, vec3 Pc)
{
  float okSq = distSqY(O, K);
  return okSq < SQ255(XBRZ_SAME) || okSq < (XBRZ_KIN37 * XBRZ_KIN37) * min(distSqY(O, Pc), distSqY(K, Pc));
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

// 28. How firmly the pixel c is held by its 8 neighbors (in row order), and symmetric tie-breaker
float held(vec3 a, vec3 b) { return float(withinEqY255(a, b, XBRZ_HOLD_SAME)); }
float holdOf(vec3 c, vec3 tl, vec3 t, vec3 tr, vec3 l, vec3 r, vec3 bl, vec3 b, vec3 br)
{
  return held(c, tl) + held(c, tr) + held(c, bl) + held(c, br) + 2.0 * (held(c, t) + held(c, l) + held(c, r) + held(c, b));
}
float tie28(vec3 e, vec3 n)
{
  if (abs(e.x - n.x) > SAFE_EPS) return float(e.x < n.x);
  if (abs(e.y - n.y) > SAFE_EPS) return float(e.y < n.y);
  return float(e.z < n.z);
}

// ---- 14. Straight steps & 25. A point on a shared edge ----
float point25(vec3 E, vec3 N, vec3 s1, vec3 s2, vec3 a1, vec3 a2, vec3 notch, vec3 f1, vec3 f2, vec3 b1, vec3 b2)
{
  if (!(sameColor(E, a1) && sameColor(E, a2) && !sameColor(E, notch) && !sameColor(E, f1) && !sameColor(E, f2))) return 0.0;
  if (withinY255(E, N, XBRZ_JUNCTION) || withinY255(s1, N, XBRZ_JUNC_NEAR) || withinY255(s2, N, XBRZ_JUNC_NEAR) || withinY255(s1, s2, XBRZ_POINT)) return 0.0;
  return (sameColor(N, b1) || sameColor(N, b2)) ? 1.0 : 0.0;
}

bool lighterSide(vec3 side, vec3 stroke) { return side.x > stroke.x && !withinY255(side, stroke, XBRZ_STRAIGHT); }
float sideTones(inout vec3 t1, inout vec3 t2, float n, vec3 c)
{
  if (n < 0.5) { t1 = c; return 1.0; }
  if (sameTone(c, t1)) return n;
  if (n < 1.5) { t2 = c; return 2.0; }
  return sameTone(c, t2) ? n : 3.0;
}
struct Walk { float n; bool thin, nu, fu, dk; vec3 farC, t1, t2; float nt; };
bool walkCell(inout Walk w, vec3 X, vec3 Y, vec2 o, vec2 n, bool first)
{
  if (!sameTone(at(o), X)) return false;
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
vec2 stepSide(vec3 X, vec3 Y, vec2 row1, vec2 row2, vec2 a, vec2 n)
{
  Walk w = Walk(0.0, true, true, true, X.x <= XBRZ_DARK, X, X, X, 0.0);
  for (int k = 0; k < 7; k++) { if (!walkCell(w, X, Y, row1 - float(k) * a, n, k == 0)) break; }
  float n1 = w.n;
  if (n1 < 2.0 || n1 > 6.0 || !(w.nu || (w.thin && (w.fu || (w.dk && w.nt < 2.5))))) return vec2(0.0);
  w.n = 0.0;
  for (int k = 1; k < 8; k++) { if (w.n > n1 + 1.5 || !walkCell(w, X, Y, row2 + float(k) * a, n, false)) break; }
  float run = (w.n <= 6.0 && abs(n1 - w.n) <= 1.0) ? min(4.0, min(n1, w.n)) : 0.0;
  bool dark = w.dk && w.nt < 2.5;
  return vec2((w.thin && (w.nu || w.fu || dark)) ? run : 0.0, w.nu ? run : 0.0);
}
vec2 stepRun(vec3 X, vec3 Y, vec2 s, vec2 a, vec2 b)
{
  vec2 rx = stepSide(X, Y, s, s - b, a, b), ry = stepSide(Y, X, s + b, s, a, -b);
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
float aa20(vec3 Pc, vec3 O, vec3 P2, vec3 O2, float d1, float d2)
{
  if (!sameColor(P2, Pc) || !sameColor(O2, O)) return 0.0;
  float acSq = distSqY(Pc, O);
  if (acSq <= SQ255(XBRZ_JUNC_FAR)) return 0.0;
  float s = d1 + d2;
  return float(s * s < (XBRZ_JUNC_RAMP * XBRZ_JUNC_RAMP) * acSq);
}
float drawsLine(float r) { return float(r < 128.0 && BLEND(r) > 0.0 && BLEND(r) < 3.0 && FLAG(r, 4.0) > 0.0); }

// ---- 19. A pixel apart keeps to itself ----
float isoSqOf(vec3 c, vec3 n0, vec3 n1, vec3 n2, vec3 n3, vec3 n4, vec3 n5, vec3 n6, vec3 n7)
{
  return min(min(min(distSqY(c, n0), distSqY(c, n1)), min(distSqY(c, n2), distSqY(c, n3))),
             min(min(distSqY(c, n4), distSqY(c, n5)), min(distSqY(c, n6), distSqY(c, n7))));
}
float squareOf(vec4 word) { return dot(BLEND(word), vec4(1.0)) == 0.0 ? 1.0 : 0.0; }

// ---- 21 and 22: what a corner sees around it ----
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
  r.p = sv ? v : h;           r.q = sv ? h : v;
  r.u = sv ? cv : ch;         r.w = sv ? ch : cv;
  r.mu = sv ? cmv : cmh;      r.mw = sv ? cmh : cmv;
  r.opp = copp;               r.uw = cvh;
  r.umw = sv ? cvmh : chmv;   r.wmu = sv ? chmv : cvmh;
  r.u2 = sv ? cv2 : ch2;      r.w2 = sv ? ch2 : cv2;
  r.u2mw = sv ? cv2mh : ch2mv; r.w2mu = sv ? ch2mv : cv2mh;
  r.uw2 = sv ? cvp2h : chp2v;
  r.ru = sv ? rv : rh;        r.rumw = sv ? rvmh : rhmv;
  return r;
}

// ---- 21. A straight line does not bend ----
vec2 straight21(Roles r, vec3 E, float ln)
{
  float uwSq = distSqY(r.u, r.w);
  if (uwSq <= SQ255(XBRZ_LINE_SIDE)) return vec2(0.0);
  float euSq = distSqY(E, r.u), ewSq = distSqY(E, r.w);
  float minESq = min(euSq, ewSq);
  if (minESq >= SQ255(XBRZ_LINE_STRONG) && sameColor(E, r.wmu) && sameColor(E, r.mw) && !sameColor(E, r.mu) && !sameColor(E, r.opp))
    return vec2(0.0);
  if (uwSq < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * minESq
      && (ln > 0.5 || sameColor(r.w, r.mw))
      && (sameColor(r.mu, E) || sameColor(r.wmu, E)
          || distSqY(r.mu, E) < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * distSqY(r.mu, r.u)
          || distSqY(r.wmu, E) < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * distSqY(r.wmu, r.u))) return vec2(0.0);
  if (minESq >= SQ255(XBRZ_LINE_STRONG) && sameColor(r.u, r.u2) && sameColor(r.u, r.uw) && sameColor(E, r.wmu) && !withinY255(r.w, r.mw, XBRZ_LINE_PAST))
  {
    bool tipE = !sameColor(E, r.mu) && !sameColor(E, r.mw);
    if (uwSq < (XBRZ_LINE_BACK * XBRZ_LINE_BACK) * minESq) { if (tipE) return vec2(0.0); }
    else if (tipE || sameColor(r.w, r.w2mu)) return vec2(1.0, 1.0);
  }
  bool middle = sameColor(r.u, r.uw) && sameColor(r.u, r.umw);
  bool four = !middle && euSq >= SQ255(XBRZ_LINE_STRONG) && !sameColor(r.w, r.umw)
           && distSqY(r.u2, r.u) > distSqY(r.u2, E)
           && sameColor(r.u, r.uw) && sameColor(r.u, r.uw2) && sameColor(r.u, at(r.p + 3.0 * r.q))
           && distSqY(r.u2mw, E) < min(distSqY(r.u2mw, r.u), distSqY(r.u2mw, r.w))
           && !withinY255(E, r.wmu, XBRZ_LINE_ALONG) && !withinY255(E, r.umw, XBRZ_LINE_ALONG);
  if (!middle && !four) return vec2(0.0);
  bool takes = sameColor(r.w, r.w2) && euSq >= SQ255(XBRZ_LINE_STRONG) && sameColor(r.w, r.w2mu)
            && distSqY(r.wmu, E) < distSqY(r.wmu, r.w) && r.w.x < E.x;
  return vec2(1.0, takes ? 1.0 : 0.0);
}

// ---- 22. Crossed cuts ----
float back22(Roles r, vec3 E, float eWord, float blocked, float loneE)
{
  float along = r.s > 0.5 ? 16.0 : 64.0;
  if (BLEND(r.ru) == 0.0 || abs(FLAG(r.ru, 8.0) - r.s) > 0.5 || max(FLAG(r.ru, 128.0), blocked) < 0.5
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
  float dlSq = distSqY(r.umw, r.u);
  if (dlSq < SQ255(XBRZ_SAME) || dlSq >= SQ255(XBRZ_CROSS_MAX) || r.umw.x <= r.u.x) return 0.0;
  if (sameColor(r.u, r.w) || sameColor(r.u, r.uw) || sameColor(r.w, r.uw) || sameColor(E, r.uw) || sameColor(E, r.u)) return 0.0;
  if (!sameColor(r.umw, at(2.0 * (r.p - r.q))) || sameColor(r.u, r.u2)) return 0.0;
  if (BLEND(r.ru) == 0.0 || BLEND(r.rumw) == 0.0 || max(FLAG(r.ru, 128.0), FLAG(r.rumw, 128.0)) < 0.5) return 0.0;
  return 1.0;
}
#define ROLES_0(s) makeRoles(vX, hX, B, D, A, C, G, uu, ll, ruu, lld, llu, luu, H, F, I, iB.z, iD.z, iC.x, iG.x, s)
#define ROLES_1(s) makeRoles(vY, hY, F, B, C, I, A, rr, uu, rrd, luu, ruu, rru, D, H, G, iF.w, iB.w, iI.y, iA.y, s)
#define ROLES_2(s) makeRoles(vZ, hZ, H, F, I, G, C, dd, rr, ldd, rru, rrd, rdd, B, D, A, iH.x, iF.x, iG.z, iC.z, s)
#define ROLES_3(s) makeRoles(vW, hW, D, H, G, A, I, ll, dd, llu, rdd, ldd, lld, F, B, C, iD.y, iH.y, iA.w, iI.w, s)
//#crisp}
// a cut that is neither weak (blend 3) nor blocked (bit 128)
vec4 activeCutOf(vec4 word) { vec4 bl = BLEND(word); return vec4(greaterThan(bl, vec4(0.0))) * vec4(lessThan(bl, vec4(3.0))) * vec4(lessThan(word, vec4(128.0))); }
// a cut that is not weak (blend 3); keeps R2-blocked (bit 128) since chain/meet may rescue it
vec4 cutNoWeak(vec4 word) { vec4 bl = BLEND(word); return vec4(greaterThan(bl, vec4(0.0))) * vec4(lessThan(bl, vec4(3.0))); }

void main()
{
  vec2 pos = fract(vTexCoord * ORIG_SIZE.xy) - vec2(0.5, 0.5);
//#crisp{
  coord = vTexCoord - pos * ORIG_SIZE.zw;
//#crisp}
//#plain   vec2 coord = vTexCoord - pos * ORIG_SIZE.zw;
  vec4 info = INFO_AT(0.0, 0.0);
  vec4 iB = vec4(0.0), iD = vec4(0.0), iF = vec4(0.0), iH = vec4(0.0);
//#crisp{
  iB = INFO_AT( 0.0, -1.0); iD = INFO_AT(-1.0,  0.0);
  iF = INFO_AT( 1.0,  0.0); iH = INFO_AT( 0.0,  1.0);
//#crisp}
//#plain   bool haveCardInfo = false;
//#crisp{
  vec4 blockedBit = FLAG(info, 128.0);
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
    vec4 aA = vec4(greaterThan(BLEND(iC), vec4(0.0))) * vec4(lessThan(BLEND(iC), vec4(3.0))) * vec4(lessThan(iC, vec4(128.0)));
    vec4 aB = vec4(greaterThan(BLEND(iG), vec4(0.0))) * vec4(lessThan(BLEND(iG), vec4(3.0))) * vec4(lessThan(iG, vec4(128.0)));
    vec4 aC = vec4(greaterThan(BLEND(iI), vec4(0.0))) * vec4(lessThan(BLEND(iI), vec4(3.0))) * vec4(lessThan(iI, vec4(128.0)));
    vec4 aD = vec4(greaterThan(BLEND(iA), vec4(0.0))) * vec4(lessThan(BLEND(iA), vec4(3.0))) * vec4(lessThan(iA, vec4(128.0)));

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
  vec4 dE4 = vec4(0.0), cand20 = vec4(0.0);
  if (XBRZ_MINC > 0.0)
  {
    if (anyCut(blendResult))
    {
      if (!haveDiagInfo)
      {
        iA = INFO_AT(-1.0, -1.0); iC = INFO_AT(1.0, -1.0); iG = INFO_AT(-1.0, 1.0); iI = INFO_AT(1.0, 1.0);
        haveDiagInfo = true;
      }
      vec3 A = haveDiagPix ? cachedA : toYCbCr(P(-1., -1.));
      vec3 B = toYCbCr(P( 0., -1.));
      vec3 C = haveDiagPix ? cachedC : toYCbCr(P( 1., -1.));
      vec3 D = toYCbCr(P(-1.,  0.));
      vec3 E = haveE ? cachedE : toYCbCr(P(0., 0.));
      vec3 F = toYCbCr(P( 1.,  0.));
      vec3 G = haveDiagPix ? cachedG : toYCbCr(P(-1.,  1.));
      vec3 H = toYCbCr(P( 0.,  1.));
      vec3 I = haveDiagPix ? cachedI : toYCbCr(P( 1.,  1.));
      cachedE = E;
      haveE = true;

      vec4 dE1_raw = sqrt(vec4(distSqY(E, B), distSqY(E, D), distSqY(E, F), distSqY(E, H)));
      vec4 dLO_raw = sqrt(vec4(distSqY(D, B), distSqY(B, F), distSqY(F, H), distSqY(H, D)));
      dE4 = dE1_raw * 255.0;
      cand20 = dLO_raw * 255.0;
      vec4 cB = cutNoWeak(iB), cD = cutNoWeak(iD), cF = cutNoWeak(iF), cH = cutNoWeak(iH), cA = cutNoWeak(iA), cC = cutNoWeak(iC), cG = cutNoWeak(iG), cI = cutNoWeak(iI);

      // Exact 0-fetch gate: skip the 12 outer-ring fetches (luu..rdd) and rules 17/19/20/21/37/22/28/29
      // whenever none of those rules can fire (clean smooth edges with cand20 < 24 and no special flags)
      vec4 cutInit = isCut(blendResult);
      vec4 sh = haveShallowLine, st = haveSteepLine;
      vec4 on17 = cutInit * line * abs(sh - st) * vec4(equal(sec, st));
      vec4 oSh17 = vec4(iB.z, iF.w, iH.x, iD.y), oSt17 = vec4(iD.z, iB.w, iF.x, iH.y);
      vec4 o17 = mix(oSt17, oSh17, sh);
      vec4 oDraw17 = activeCutOf(o17) * FLAG(o17, 4.0)
                   * mix(FLAG(o17, 64.0), FLAG(o17, 16.0), sh) * vec4(equal(FLAG(o17, 8.0), sh));
      float sqB = squareOf(iB), sqD = squareOf(iD), sqF = squareOf(iF), sqH = squareOf(iH);
      vec4 sq19 = vec4(sec.x > 0.5 ? sqB : sqD, sec.y > 0.5 ? sqF : sqB, sec.z > 0.5 ? sqH : sqF, sec.w > 0.5 ? sqD : sqH);
      vec4 bk22 = max(blockedBit,
                      max(max(FLAG(oSh17, 128.0), FLAG(oSt17, 128.0)),
                          max(FLAG(vec4(iC.x, iI.y, iG.z, iA.w), 128.0), FLAG(vec4(iG.x, iA.y, iC.z, iI.w), 128.0))));
      vec4 nW28 = mix(oSt17, oSh17, sec);
      vec4 pair28_0 = cutInit * activeCutOf(nW28) * vec4(equal(FLAG(nW28, 8.0), sec)) * line * FLAG(nW28, 4.0)
                    * mix(st, sh, sec) * mix(FLAG(nW28, 64.0), FLAG(nW28, 16.0), sec)
                    * vec4(greaterThan(mix(dE4.yxzw, dE4.xzwy, sec), vec4(XBRZ_JUNCTION)))
                    * (1.0 - FLAG(nW28, 32.0) * (1.0 - blockedBit) * (1.0 - weak));
      bool needRing = any(greaterThan(
        cutInit * vec4(greaterThanEqual(cand20, vec4(24.0)))
        + on17 * oDraw17 + cutInit * sq19 + cutInit * bk22 + pair28_0, vec4(0.0)));

      vec3 luu = vec3(0.0), uu = vec3(0.0), ruu = vec3(0.0);
      vec3 llu = vec3(0.0), ll = vec3(0.0), lld = vec3(0.0);
      vec3 rru = vec3(0.0), rr = vec3(0.0), rrd = vec3(0.0);
      vec3 ldd = vec3(0.0), dd = vec3(0.0), rdd = vec3(0.0);
      if (needRing)
      {
        luu = toYCbCr(P(-1., -2.)); uu = toYCbCr(P(0., -2.)); ruu = toYCbCr(P(1., -2.));
        llu = toYCbCr(P(-2., -1.)); ll = toYCbCr(P(-2., 0.)); lld = toYCbCr(P(-2., 1.));
        rru = toYCbCr(P( 2., -1.)); rr = toYCbCr(P( 2., 0.)); rrd = toYCbCr(P( 2., 1.));
        ldd = toYCbCr(P(-1.,  2.)); dd = toYCbCr(P( 0., 2.)); rdd = toYCbCr(P( 1., 2.));

        // ---- 17. A line drawn on one side only ----
        if (any(greaterThan(on17 * oDraw17, vec4(0.0))))
        {
          vec4 oDraw = oDraw17;
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
          blendResult *= 1.0 - on17 * oDraw;
        }

        // ---- 19. A pixel apart keeps to itself ----
        if (anyCut(blendResult))
        {
          vec4 c19 = isCut(blendResult);
          vec4 need19 = c19 * max(sq19, (1.0 - line) * vec4(greaterThanEqual(cand20, vec4(XBRZ_ISO_FAR))));
          if (any(greaterThan(need19, vec4(0.0))))
          {
            float isoB = 0.0, isoD = 0.0, isoF = 0.0, isoH = 0.0;
            if (need19.x * sec.x + need19.y * (1.0 - sec.y) > 0.0) isoB = isoSqOf(B, luu, uu, ruu, A, C, D, E, F);
            if (need19.x * (1.0 - sec.x) + need19.w * sec.w > 0.0) isoD = isoSqOf(D, llu, A, B, ll, E, lld, G, H);
            if (need19.y * sec.y + need19.z * (1.0 - sec.z) > 0.0) isoF = isoSqOf(F, B, C, rru, E, rr, H, I, rrd);
            if (need19.z * sec.z + need19.w * (1.0 - sec.w) > 0.0) isoH = isoSqOf(H, D, E, F, G, I, ldd, dd, rdd);
            vec4 near19 = vec4(sec.x > 0.5 ? isoB : isoD, sec.y > 0.5 ? isoF : isoB, sec.z > 0.5 ? isoH : isoF, sec.w > 0.5 ? isoD : isoH);
            vec4 iso = vec4(greaterThanEqual(near19, vec4(SQ255(XBRZ_ISO)))) * sq19;
            vec4 lone = vec4(greaterThanEqual(near19, vec4(SQ255(XBRZ_SAME)))) * (1.0 - line)
                      * vec4(greaterThanEqual(cand20, vec4(XBRZ_ISO_FAR)))
                      * vec4(greaterThanEqual(vec4(min(distSqY(A, B), distSqY(A, D)), min(distSqY(C, F), distSqY(C, B)),
                                                   min(distSqY(I, H), distSqY(I, F)), min(distSqY(G, D), distSqY(G, H))), vec4(SQ255(XBRZ_SAME))));
            blendResult *= 1.0 - max(iso, lone);
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
          vec4 cross20 = vec4(greaterThan(min(min(nbASq, nbBSq), dgESq), vec4(SQ255(XBRZ_JUNCTION))))
                       * vec4(greaterThan(min(dE1, dE2), vec4(XBRZ_JUNCTION)));
          cross20 *= vec4(lessThan(vec4(E.x), min(lu20, lu20.yzwx))) * float(E.x <= XBRZ_DARK) * line;
          float loD = 1.0 - max(sameF(D, A), max(sameF(D, G), sameF(D, ll))), loB = 1.0 - max(sameF(B, A), max(sameF(B, C), sameF(B, uu)));
          float loF = 1.0 - max(sameF(F, C), max(sameF(F, I), sameF(F, rr))), loH = 1.0 - max(sameF(H, G), max(sameF(H, I), sameF(H, dd)));
          cross20 *= vec4(mix(loD, loB, sec.x), mix(loB, loF, sec.y), mix(loF, loH, sec.z), mix(loH, loD, sec.w));
          ext1 *= 1.0 - cross20 * vec4(sameF(D, G) * sameF(D, ll), sameF(B, A) * sameF(B, uu), sameF(F, C) * sameF(F, rr), sameF(H, I) * sameF(H, dd));
          ext2 *= 1.0 - cross20 * vec4(sameF(B, C) * sameF(B, uu), sameF(F, I) * sameF(F, rr), sameF(H, G) * sameF(H, dd), sameF(D, A) * sameF(D, ll));
          float eAcross = max(junctionNear(E, G), junctionNear(E, C)), eAlong = max(junctionNear(E, A), junctionNear(E, I));
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
            vec4 m2 = (on20.y * cA.y + on20.w * cA.w > 0.0) ? cutNoWeak(INFO_AT(-2.0, -2.0)) : vec4(0.0);
            vec4 p2 = (on20.y * cI.y + on20.w * cI.w > 0.0) ? cutNoWeak(INFO_AT( 2.0,  2.0)) : vec4(0.0);
            vec4 u2 = (on20.x * cC.x + on20.z * cC.z > 0.0) ? cutNoWeak(INFO_AT( 2.0, -2.0)) : vec4(0.0);
            vec4 d2 = (on20.x * cG.x + on20.z * cG.z > 0.0) ? cutNoWeak(INFO_AT(-2.0,  2.0)) : vec4(0.0);
            vec4 runA = vec4(cC.x + cC.x * u2.x, cA.y + cA.y * m2.y, cC.z + cC.z * u2.z, cA.w + cA.w * m2.w);
            vec4 runB = vec4(cG.x + cG.x * d2.x, cI.y + cI.y * p2.y, cG.z + cG.z * d2.z, cI.w + cI.w * p2.w);
            on20 *= vec4(lessThan(1.0 + runA + runB, vec4(3.0)));
            vec4 tipH = vec4(sameF(A, B) * cB.z * cA.w, sameF(C, B) * cB.w * cC.z, sameF(I, H) * cH.x * cI.y, sameF(G, H) * cH.y * cG.x);
            vec4 tipV = vec4(sameF(A, D) * cD.z * cA.y, sameF(C, F) * cF.w * cC.x, sameF(I, F) * cF.x * cI.w, sameF(G, D) * cD.y * cG.z);
            on20 *= 1.0 - mix(tipV, tipH, vec4(1.0 - sec.x, sec.y, 1.0 - sec.z, sec.w));
            vec4 half20 = mix(vec4(cD.z, cB.w, cF.x, cH.y), vec4(cB.z, cF.w, cH.x, cD.y), sec);
            on20 *= 1.0 - half20 * vec4(lessThan(cand20, 0.5 * min(dE1, dE2)));
            vec4 maxE20 = max(dE1, dE2);
            vec4 wide20 = max(vec4(lessThan(dE1 + dE2 + cand20, (1.0 + XBRZ_JUNC_RAMP2) * max(cand20, maxE20))),
                              vec4(lessThan(dE1 + dE2 + cand20, (1.0 + XBRZ_JUNC_RAMP3) * maxE20)) * vec4(lessThan(cand20, maxE20))
                              * vec4(greaterThan(min(cand20, min(dE1, dE2)), XBRZ_JUNC_MID * maxE20)) * vec4(greaterThan(maxE20, vec4(XBRZ_JUNC_FAR))));
            vec4 keep20 = max(vec4(greaterThan(runA + runB, vec4(0.5))), (isCut(blendResult) * (1.0 - on20)).zwxy);
            on20 *= 1.0 - keep20 * wide20;
            vec4 frame20 = vec4(sameF(B, C) * sameF(B, rru) * sameF(D, G) * sameF(D, ldd) * cA.z * max(sameF(A, uu), sameF(A, ll)) * (1.0 - sameF(E, A)),
                                sameF(B, A) * sameF(B, llu) * sameF(F, I) * sameF(F, rdd) * cC.w * max(sameF(C, uu), sameF(C, rr)) * (1.0 - sameF(E, C)),
                                sameF(F, C) * sameF(F, ruu) * sameF(H, G) * sameF(H, lld) * cI.x * max(sameF(I, rr), sameF(I, dd)) * (1.0 - sameF(E, I)),
                                sameF(D, A) * sameF(D, luu) * sameF(H, I) * sameF(H, rrd) * cG.y * max(sameF(G, ll), sameF(G, dd)) * (1.0 - sameF(E, G)));
            on20 *= 1.0 - frame20;
            if (any(greaterThan(on20, vec4(0.0))))
            {
              float aaV = aa20(B, H, uu, dd, dE1_raw.x, dE1_raw.w);
              float aaH = aa20(D, F, ll, rr, dE1_raw.y, dE1_raw.z);
              vec4 aa = vec4(mix(aaH, aaV, sec.x), mix(aaV, aaH, sec.y), mix(aaH, aaV, sec.z), mix(aaV, aaH, sec.w));
              vec4 c20 = isCut(blendResult);
              vec4 tip1 = vec4(sameF(E, I) * (1.0 - sameF(E, A)) * c20.y * c20.w, sameF(E, G) * (1.0 - sameF(E, C)) * c20.x * c20.z,
                               sameF(E, A) * (1.0 - sameF(E, I)) * c20.y * c20.w, sameF(E, C) * (1.0 - sameF(E, G)) * c20.x * c20.z);
              on20 *= (1.0 - aa) * (1.0 - tip1);
              blendResult *= 1.0 - on20;
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
          if (blendResult.x > 0.0 && cand20.x > XBRZ_LINE_SIDE) { vec2 t = straight21(ROLES_0(sec.x), E, run21.x); line21.x = t.x; on21.x = t.y; }
          if (blendResult.y > 0.0 && cand20.y > XBRZ_LINE_SIDE) { vec2 t = straight21(ROLES_1(sec.y), E, run21.y); line21.y = t.x; on21.y = t.y; }
          if (blendResult.z > 0.0 && cand20.z > XBRZ_LINE_SIDE) { vec2 t = straight21(ROLES_2(sec.z), E, run21.z); line21.z = t.x; on21.z = t.y; }
          if (blendResult.w > 0.0 && cand20.w > XBRZ_LINE_SIDE) { vec2 t = straight21(ROLES_3(sec.w), E, run21.w); line21.w = t.x; on21.w = t.y; }
          sec = abs(sec - on21);
          haveShallowLine *= 1.0 - on21;
          haveSteepLine *= 1.0 - on21;
          blendResult *= 1.0 - line21 * (1.0 - on21);
        }

        // ---- 37. A contour by a knight's move ----
        if (any(greaterThan(isCut(blendResult) * vec4(greaterThanEqual(cand20, vec4(24.0))), vec4(0.0))))
        {
          vec4 cutK = isCut(blendResult);
          vec4 sB = FLAG(iB, 8.0), sD = FLAG(iD, 8.0), sF = FLAG(iF, 8.0), sH = FLAG(iH, 8.0);
          vec4 flipK = vec4(0.0);
          if (cutK.x > 0.5)
          {
            bool s1 = sec.x > 0.5; vec3 Pc = s1 ? B : D, O = s1 ? D : B, K = s1 ? C : G;
            float dPcE = s1 ? dE4.x : dE4.y, dOE = s1 ? dE4.y : dE4.x;
            bool face = s1 ? (cB.z > 0.5 && sB.z < 0.5) : (cD.z > 0.5 && sD.z > 0.5);
            flipK.x = float(face && cand20.x >= 24.0 && dPcE >= XBRZ_JUNCTION && dOE >= XBRZ_JUNCTION && cand20.x + dPcE >= 1.15 * dOE && kin37(O, K, Pc));
          }
          if (cutK.y > 0.5)
          {
            bool s1 = sec.y > 0.5; vec3 Pc = s1 ? F : B, O = s1 ? B : F, K = s1 ? I : A;
            float dPcE = s1 ? dE4.z : dE4.x, dOE = s1 ? dE4.x : dE4.z;
            bool face = s1 ? (cF.w > 0.5 && sF.w < 0.5) : (cB.w > 0.5 && sB.w > 0.5);
            flipK.y = float(face && cand20.y >= 24.0 && dPcE >= XBRZ_JUNCTION && dOE >= XBRZ_JUNCTION && cand20.y + dPcE >= 1.15 * dOE && kin37(O, K, Pc));
          }
          if (cutK.z > 0.5)
          {
            bool s1 = sec.z > 0.5; vec3 Pc = s1 ? H : F, O = s1 ? F : H, K = s1 ? G : C;
            float dPcE = s1 ? dE4.w : dE4.z, dOE = s1 ? dE4.z : dE4.w;
            bool face = s1 ? (cH.x > 0.5 && sH.x < 0.5) : (cF.x > 0.5 && sF.x > 0.5);
            flipK.z = float(face && cand20.z >= 24.0 && dPcE >= XBRZ_JUNCTION && dOE >= XBRZ_JUNCTION && cand20.z + dPcE >= 1.15 * dOE && kin37(O, K, Pc));
          }
          if (cutK.w > 0.5)
          {
            bool s1 = sec.w > 0.5; vec3 Pc = s1 ? D : H, O = s1 ? H : D, K = s1 ? A : I;
            float dPcE = s1 ? dE4.y : dE4.w, dOE = s1 ? dE4.w : dE4.y;
            bool face = s1 ? (cD.y > 0.5 && sD.y < 0.5) : (cH.y > 0.5 && sH.y > 0.5);
            flipK.w = float(face && cand20.w >= 24.0 && dPcE >= XBRZ_JUNCTION && dOE >= XBRZ_JUNCTION && cand20.w + dPcE >= 1.15 * dOE && kin37(O, K, Pc));
          }
          if (any(greaterThan(flipK, vec4(0.0))))
          {
            vec4 straightO = vec4(sameF(A, sec.x > 0.5 ? D : B), sameF(C, sec.y > 0.5 ? B : F), sameF(I, sec.z > 0.5 ? F : H), sameF(G, sec.w > 0.5 ? H : D));
            vec4 lineO = vec4(sec.x > 0.5 ? sameF(G, D) : sameF(C, B), sec.y > 0.5 ? sameF(A, B) : sameF(I, F),
                              sec.z > 0.5 ? sameF(C, F) : sameF(G, H), sec.w > 0.5 ? sameF(I, H) : sameF(A, D));
            vec4 sECard = vec4(lessThan(dE4, vec4(XBRZ_SAME)));
            vec4 block37 = vec4(sECard.z * sECard.w * sameF(E, I), sECard.y * sECard.w * sameF(E, G),
                                sECard.x * sECard.y * sameF(E, A), sECard.x * sECard.z * sameF(E, C));
            blendResult *= 1.0 - flipK * straightO * lineO * block37;
            flipK *= 1.0 - straightO;
            sec = abs(sec - flipK);
            haveShallowLine *= 1.0 - flipK * sec;
            haveSteepLine   *= 1.0 - flipK * (1.0 - sec);
          }
        }
      }

      // ---- 24. A line with nothing to go on to ----
      if (anyCut(blendResult))
      {
        vec4 lone24 = line * isCut(blendResult) * abs(haveShallowLine - haveSteepLine);
        if (any(greaterThan(lone24, vec4(0.0))))
        {
          vec4 partSh = vec4(max(cD.z, cC.z), max(cF.w, cA.w), max(cF.x, cG.x), max(cD.y, cI.y));
          vec4 partSt = vec4(max(cB.z, cG.z), max(cB.w, cI.w), max(cH.x, cC.x), max(cH.y, cA.y));
          vec4 steepOnScreen = vec4(haveSteepLine.x, haveShallowLine.y, haveSteepLine.z, haveShallowLine.w);
          vec4 part = mix(partSh, partSt, steepOnScreen);
          vec4 pDist = vec4(sec.x > 0.5 ? dE4.x : dE4.y, sec.y > 0.5 ? dE4.z : dE4.x, sec.z > 0.5 ? dE4.w : dE4.z, sec.w > 0.5 ? dE4.y : dE4.w);
          hook24 = lone24 * (1.0 - part) * vec4(greaterThanEqual(pDist, vec4(XBRZ_HOOK)));
        }
      }

      if (needRing)
      {
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
        if (any(greaterThan(isCut(blendResult) * line, vec4(0.0))))
        {
          vec4 nW = mix(oSt17, oSh17, sec);
          vec4 nCut = activeCutOf(nW);
          vec4 pair = isCut(blendResult) * nCut * vec4(equal(FLAG(nW, 8.0), sec)) * line * FLAG(nW, 4.0)
                    * mix(haveSteepLine, haveShallowLine, sec) * mix(FLAG(nW, 64.0), FLAG(nW, 16.0), sec)
                    * vec4(greaterThan(mix(dE4.yxzw, dE4.xzwy, sec), vec4(XBRZ_JUNCTION)))
                    * (1.0 - FLAG(nW, 32.0) * (1.0 - blockedBit) * (1.0 - weak));
          if (any(greaterThan(pair, vec4(0.5))))
          {
            float hE = holdOf(E, A, B, C, D, F, G, H, I), hB = 0.0, hD = 0.0, hF = 0.0, hH = 0.0;
            if (pair.x * sec.x + pair.y * (1.0 - sec.y) > 0.0) hB = holdOf(B, luu, uu, ruu, A, C, D, E, F);
            if (pair.x * (1.0 - sec.x) + pair.w * sec.w > 0.0) hD = holdOf(D, llu, A, B, ll, E, lld, G, H);
            if (pair.y * sec.y + pair.z * (1.0 - sec.z) > 0.0) hF = holdOf(F, B, C, rru, E, rr, H, I, rrd);
            if (pair.z * sec.z + pair.w * (1.0 - sec.w) > 0.0) hH = holdOf(H, D, E, F, G, I, ldd, dd, rdd);
            vec4 hN = mix(vec4(hD, hB, hF, hH), vec4(hB, hF, hH, hD), sec);
            vec4 tie = vec4(tie28(E, sec.x > 0.5 ? B : D), tie28(E, sec.y > 0.5 ? F : B),
                            tie28(E, sec.z > 0.5 ? H : F), tie28(E, sec.w > 0.5 ? D : H));
            vec4 whole = max(vec4(lessThan(vec4(hE), hN - 0.5)),
                             vec4(lessThan(abs(hE - hN), vec4(0.5))) * tie);
            blendResult *= 1.0 - pair * whole;
          }
        }

        // ---- 29. The burr of a square stroke ----
        if (E.x <= XBRZ_DARK && any(greaterThan(isCut(blendResult) * line * vec4(greaterThan(cand20, vec4(XBRZ_JUNCTION))), vec4(0.0))))
        {
          vec4 nC = mix(vec4(cD.y, cB.z, cF.w, cH.x), vec4(cB.w, cF.x, cH.y, cD.z), sec);
          vec4 dEN = mix(dE4.yxzw, dE4.xzwy, sec);
          vec4 cP = vec4(cA.z, cC.w, cI.x, cG.y);
          vec4 oA = mix(vec4(sameF(A, B), sameF(C, F), sameF(I, H), sameF(G, D)), vec4(sameF(A, D), sameF(C, B), sameF(I, F), sameF(G, H)), sec);
          vec4 ok = vec4(lessThan(vec4(iC.x, iA.y, iC.z, iA.w), vec4(128.0))) * vec4(cC.x, cA.y, cC.z, cA.w) + vec4(lessThan(vec4(iG.x, iI.y, iG.z, iI.w), vec4(128.0))) * vec4(cG.x, cI.y, cG.z, cI.w);
          float sB = sameF(E, B), sD = sameF(E, D), sF = sameF(E, F), sH = sameF(E, H);
          float nS = sB + sD + sF + sH;
          vec4 tip = vec4(float(nS == 1.0)) * vec4(sF + sH, sD + sH, sB + sD, sB + sF);
          vec4 lN = mix(vec4(D.x, B.x, F.x, H.x), vec4(B.x, F.x, H.x, D.x), sec);
          float sA = sameF(E, A), sC = sameF(E, C), sG = sameF(E, G), sI = sameF(E, I);
          tip *= 1.0 - min(vec4(sA + sC + sG, sC + sA + sI, sI + sC + sG, sG + sA + sI), vec4(1.0));
          tip *= vec4(greaterThan(lN, vec4(E.x)));
          vec4 burr = tip * vec4(lessThan(ok, vec4(0.5))) * isCut(blendResult) * line * oA * (1.0 - nC) * (1.0 - cP)
                    * vec4(greaterThan(cand20, vec4(XBRZ_JUNCTION))) * vec4(greaterThanEqual(dEN, vec4(XBRZ_STRAIGHT)));
          blendResult *= 1.0 - burr;
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
            vec3 a2 = (pF + pH > 0.0) ? toYCbCr(P(-2., -2.)) : vec3(0.0);
            vec3 c2 = (pH + pD > 0.0) ? toYCbCr(P( 2., -2.)) : vec3(0.0);
            vec3 g2 = (pB + pF > 0.0) ? toYCbCr(P(-2.,  2.)) : vec3(0.0);
            vec3 i2 = (pB + pD > 0.0) ? toYCbCr(P( 2.,  2.)) : vec3(0.0);
            if (pB > 0.0) pB = point25(E, B, D, F, G, I, H, g2, i2, A, C);
            if (pF > 0.0) pF = point25(E, F, B, H, A, G, D, a2, g2, C, I);
            if (pH > 0.0) pH = point25(E, H, F, D, A, C, B, a2, c2, G, I);
            if (pD > 0.0) pD = point25(E, D, H, B, C, I, F, c2, i2, A, G);
            blendResult *= 1.0 - min(vec4(pB + pD, pB + pF, pF + pH, pH + pD), vec4(1.0));
          }
        }
      }

      // ---- 23. A loose pixel is a square with rounded corners ----
      if (dot(isCut(blendResult), vec4(1.0)) > 3.5 && min(min(dE4.x, dE4.y), min(dE4.z, dE4.w)) >= XBRZ_LOOSE
          && sameF(E, A) + sameF(E, C) + sameF(E, G) + sameF(E, I) < 0.5)
      {
        line = vec4(0.0); haveShallowLine = vec4(0.0); haveSteepLine = vec4(0.0);
        small23 = vec4(1.0);
      }
      // ---- 23b. A loose pixel cut by different colors ----
      else if (dot(isCut(blendResult), vec4(1.0)) > 2.5 && min(min(dE4.x, dE4.y), min(dE4.z, dE4.w)) >= XBRZ_LONE23
          && !withinY255(E, A, XBRZ_LONE23) && !withinY255(E, C, XBRZ_LONE23) && !withinY255(E, G, XBRZ_LONE23) && !withinY255(E, I, XBRZ_LONE23))
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
          vec4 pair = vec4(sameF(D, B), sameF(B, F), sameF(F, H), sameF(H, D));
          blendResult *= pair;
          line = vec4(0.0); haveShallowLine = vec4(0.0); haveSteepLine = vec4(0.0);
          small23 = isCut(blendResult);
        }
      }
    }

    // ---- 14. Straight steps ----
    vec4 dEv14 = dE4.xzwy, dEh14 = dE4.yxzw;
    vec4 lineOn = line * isCut(blendResult) * vec4(greaterThanEqual(max(dEv14, dEh14), vec4(XBRZ_STRAIGHT)));
    vec4 free = vec4(equal(blendResult, vec4(0.0)));
    if (anyCut(blendResult))
    {
      vec4 dN = vec4(min(dE4.x, dE4.y), min(dE4.x, dE4.z), min(dE4.z, dE4.w), min(dE4.y, dE4.w));
      free = max(free, isCut(blendResult) * vec4(lessThan(dN, XBRZ_JUNC_TONE * cand20)) * vec4(greaterThan(cand20, vec4(XBRZ_STRAIGHT))));
    }
    vec4 cSt = free * vec4(drawsLine(iB.x), drawsLine(iF.y), drawsLine(iH.z), drawsLine(iD.w));
    vec4 cSh = free * vec4(drawsLine(iD.x), drawsLine(iB.y), drawsLine(iF.z), drawsLine(iH.w));
    if (any(greaterThan(lineOn + cSt + cSh, vec4(0.0))))
    {
      vec4 xSt = vec4(FLAG(iB.x, 64.0), FLAG(iF.y, 64.0), FLAG(iH.z, 64.0), FLAG(iD.w, 64.0));
      vec4 xSh = vec4(FLAG(iD.x, 16.0), FLAG(iB.y, 16.0), FLAG(iF.z, 16.0), FLAG(iH.w, 16.0));
      vec3 E0 = haveE ? cachedE : toYCbCr(P(0., 0.));
      for (int k = 0; k < 4; k++)
      {
        vec4 m = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
        if (dot(m, lineOn + cSt + cSh) > 0.0)
        {
          vec2 v = k == 0 ? vX : (k == 1 ? vY : (k == 2 ? vZ : vW));
          vec2 h = k == 0 ? hX : (k == 1 ? hY : (k == 2 ? hZ : hW));
          float lo = dot(m, lineOn), xs = dot(m, xSt), xh = dot(m, xSh);
          vec3 vPix = vec3(0.0), hPix = vec3(0.0);
          bool haveVPix = false, haveHPix = false;
          bool steepOk = false, shallowOk = false;
          if (dot(m, cSt) > 0.0)
          {
            vPix = at(v);
            haveVPix = true;
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
                if (thinS > 0.0 && blockedByQ3(v, h, v, true, vPix, at(v + h), at(2.0 * v))) thinS = 0.0;
              }
              if (thinS == 0.0 && dot(m, cSh) > 0.0)
              {
                hPix = at(h);
                haveHPix = true;
                shallowOk = withinY255(hPix, E0, XBRZ_THIN_TONE);
              }
            }
            vec2 s = vec2(0.), a = v, b = h;
            bool need = lo > 0.0 && dot(m, dEv14) >= XBRZ_STRAIGHT;
            if (j == 1) { a = h; b = v; need = lo > 0.0 && dot(m, dEh14) >= XBRZ_STRAIGHT; }
            else if (j == 2) { s = v; need = steepOk; }
            else if (j == 3) { s = v; a = h; b = v; need = steepOk && max(r2.x, r2.y * xs) >= 3.0; }
            else if (j == 4) { s = h; a = h; b = v; need = shallowOk; }
            else if (j == 5) { s = h; need = shallowOk && max(r4.x, r4.y * xh) >= 3.0; }
            vec2 rr = vec2(0.0);
            if (need)
            {
              vec3 X = (j < 2) ? E0 : ((j < 4) ? vPix : hPix);
              vec3 Y = at(s + a);
              if (!withinY255(X, Y, XBRZ_STRAIGHT)) rr = stepRun(X, Y, s, a, b);
            }
            if (j == 0) r0 = rr; else if (j == 1) r1 = rr; else if (j == 2) r2 = rr;
            else if (j == 3) r3 = rr; else if (j == 4) r4 = rr; else r5 = rr;
          }
          float thinSh = shallowOk ? thinEnd(r4, r5, false, xh) : 0.0;
          if (thinSh > 0.0 && blockedByQ3(h, h, v, false, hPix, at(2.0 * h), at(h + v))) thinSh = 0.0;
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
    }
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

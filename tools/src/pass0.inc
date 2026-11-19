@include "header.inc"
@include "license.inc"

//#crisp{
// Pass 0 of xbrz-crisp (@BACKEND_LABEL@)
//#crisp}
//#plain // Pass 0 of xbrz-freescale-multipass (@BACKEND_LABEL@)
@STAGE_PASS0@

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

// The decision of each corner of E (x top-left, y top-right, z bottom-right, w bottom-left), written
// to the info texture as a number from 0 to 255:
//   BLEND(r)       blend type: 0 none, 1 normal, 2 dominant, 3 weak (rule 1: the resolve pass decides)
//   FLAG(r, 4.0)   xBRZ's line blend (without it only the tip of the corner is cut)
//   FLAG(r, 8.0)   the corner blends with the second of its two candidate colors
//   FLAG(r, 16.0)  shallow line
//   FLAG(r, 32.0)  the line was found only because hue weighs more (rule 9)
//   FLAG(r, 64.0)  steep line
//   FLAG(r, 128.0) blocked by the diagonal limit (rule 2: the resolve pass decides)
// The candidate colors of the corners x, y, z and w are D or B, B or F, F or H and H or D. Below, the
// one a corner blends with is P and the other one Q.
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)

// ---- rule tunables (XBRZ_MINC and XBRZ_DIAG are in the menu) ----
// rules 3, 9 and 13 belong to the crisp look rather than fixing clear xBRZ errors, so they
// run only when XBRZ_MINC is on too (plain xBRZ, with XBRZ_MINC 0, keeps rules 2, 4 to 7 and 10)
#define CRISP_RULES (XBRZ_MINC > 0.0 && XBRZ_DIAG > 0.0)
#define XBRZ_ALIKE 20.0        // colors this close (x/255) count as alike
#define XBRZ_HYST 4.0          // 1. a corner this close below XBRZ_MINC is weak
#define XBRZ_DIAG_AA 92.0      // 2. diagonal limit on antialiasing ramps
#define XBRZ_RAMP 1.15         // 2, 6. a ramp: (d(E,P) + d(P,Q)) / d(E,Q) up to this
#define XBRZ_STRIPE 64.0       // 2, 3. a diagonal stripe keeps a close color (within this) along its length
#define XBRZ_OUTLINE 0.15      // 2, 3. an outline is darker (in luma) than both inner tones by this much
#define XBRZ_NOT_LIGHTER 4.0   // 2. P is not lighter than E up to this much more luma (x/255)
#define XBRZ_THIN_LIGHT 0.15   // 5. a thin stroke is lighter (in luma) than both of its colors by this much
#define XBRZ_THIN_DARK 0.45    // 5. on colors darker than this (luma) the stroke counts without the test of its sides
#define XBRZ_TONE 0.6          // 5, 6. a pixel has E's tone when it is closer to E than this times its distance to the other colors
#define XBRZ_NOTCH 45.0        // 6. the notch's diagonal limit is XBRZ_DIAG plus this
#define XBRZ_TIP 36.0          // 7. stripe ends stay square above this diagonal distance
#define XBRZ_AA_LINE 1.01      // 8. E lies between the colors: d(P1,E) + d(E,P2) up to this times d(P1,P2)
#define XBRZ_AA_OFF 1.2        // 8. three colors are on no ramp when the two short steps add up to more than this times the long one
#define XBRZ_AA_EDGE 40.0      // 8. the two colors differ by at least this
#define XBRZ_FAR_TONE 36.0     // 9. two colors that clearly differ: more than this apart
#define XBRZ_BLACK 0.15        // 10. a near-black outline is darker than this (luma)
#define XBRZ_BLACK_GAP 0.1     // 10. the outline is darker (luma) than E and the pixel closed by it by this much
#define XBRZ_STRONG 40.0       // 11. the contour past a 1-pixel stripe differs from it by at least this
#define XBRZ_GUARD 30.0        // 15. lone pixel test tolerance on strong edges (reference xBRZ)
#define XBRZ_GUARD_EDGE 64.0   // 15. a strong edge: the pixel differs from both corner colors by this much
#define XBRZ_GUARD_EDGE_L 54.0 // 15. the same for the L-shape test
#define XBRZ_TINT 20.0         // 16. the two colors beside the line differ by more than this
#define XBRZ_TINT_RAMP 1.2     // 16. not a ramp: d(E,P) + d(P,L) above this times d(E,L)
#define XBRZ_TINT_DARK 0.25    // 18. a near-black outline is darker than this (luma)
#define XBRZ_BAND_FAR 20.0     // 30. the color past a band of three pixels or more differs from the pixel by this
#define XBRZ_BAND_FAR2 30.0    // 30. and past a band of two pixels by this
#define eq(a,b)  (a == b)
#define neq(a,b) (a != b)

// the ring of pixels two steps from E (the 5x5 window without its corners), read once and pre-converted to linear YCbCr in main
vec3 N_m1_m2, N_p0_m2, N_p1_m2, N_m2_m1, N_p2_m1, N_m2_p0, N_p2_p0, N_m2_p1, N_p2_p1, N_m1_p2, N_p0_p2, N_p1_p2;

@include "color.inc"

#define PY(x, y) toYCbCr(P(x, y))
#define at5x5(coord, o) PY((o).x, (o).y)

bool alike(vec3 a, vec3 b) { return withinEqY255(a, b, XBRZ_ALIKE); }

// The distance is symmetric, and below the two pixels of each distance (and of alike and IsPixEqual) are
// written in one fixed order (A to I, then the ring of pixels two steps away), so the compiler computes
// each distance only once. The pixels two steps away are read once, at the start of main.
bool IsPixEqual(vec3 pixA, vec3 pixB)
{
  return withinY255(pixA, pixB, TOL_E);
}

// 15. Lone pixel and L-shape tests on strong edges: the tolerance of xBRZ's lone pixel test and L-shape
// test in the blend decisions; edge is how much E differs from the closer corner color, and edgeLimit
// how much that must be (XBRZ_GUARD_EDGE or XBRZ_GUARD_EDGE_L) for the reference tolerance to apply
bool equalOnEdge(vec3 pixA, vec3 pixB, float edge, float edgeLimit)
{
  return withinY255(pixA, pixB, XBRZ_MINC > 0.0 && edge * 255.0 >= edgeLimit ? XBRZ_GUARD : TOL_E);
}

// xBRZ's test of whether a corner (blend type own) is cut, in the corner's own frame: c2 is the diagonal
// pixel of the corner and c0 to c4 run around it (for the bottom-right corner G H I F C), and nbr0 and
// nbr4 are the blend types of the two corners beside it, nbr0 the one on the c4 side and nbr4 the one on
// the c0 side (for the bottom-right corner, the top-right and bottom-left corners). A dominant corner is always
// cut. A normal one is not cut when the lone pixel test fails (the corner beside it on the c4 side is cut
// and E differs from c0, or the corner on the c0 side is cut and E differs from c4) or when the L-shape
// test holds (c0 to c4 are one color around the corner pixel c2, which E does not share)
bool cornerCut(int own, int nbr0, int nbr4, float edge, vec3 E, vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4)
{
  if (own == BLEND_DOMINANT)
    return true;
  if (own != BLEND_NORMAL)
    return false;
  bool lone0 = nbr0 != BLEND_NONE && !equalOnEdge(E, c0, edge, XBRZ_GUARD_EDGE);
  if (lone0)
    return false;
  bool lone4 = nbr4 != BLEND_NONE && !equalOnEdge(c4, E, edge, XBRZ_GUARD_EDGE);
  if (lone4)
    return false;
  bool lShape = equalOnEdge(c0, c1, edge, XBRZ_GUARD_EDGE_L) && equalOnEdge(c1, c2, edge, XBRZ_GUARD_EDGE_L) &&
                equalOnEdge(c3, c2, edge, XBRZ_GUARD_EDGE_L) && equalOnEdge(c4, c3, edge, XBRZ_GUARD_EDGE_L) &&
                !equalOnEdge(E, c2, edge, XBRZ_GUARD_EDGE_L);
  return !lShape;
}

// ============================================================================================
// 9. Line shapes
// ============================================================================================
// the extra distance for the shallow and steep line tests with the crisp rules on (a line passes with
// it or with xBRZ's): hue weighs 1.2x more than lightness, scaled so that as many neighbour pairs pass
// the thresholds (inputs are linear YCbCr)
float DistShapeSq(vec3 a, vec3 b)
{
  vec3 d = vec3(0.937, 1.125, 1.125) * (a - b);
  return dot(d, d);
}

// a line xBRZ finds that the hue-weighted test does not is kept too, except where it would bring
// back a corner blocked by the diagonal limit (rule 2), or where the line's color runs on along a
// 45-degree diagonal in the same color while the line test pairs it with a different one (alt45)
bool plainLineSq(float abSq, float cdSq, float st2, float pairD, bool alt45)
{
  return st2 * abSq <= cdSq && pairD * 255.0 <= XBRZ_DIAG && !alt45;
}

// a shallow or steep line found only because hue weighs more (DistShape) between two different
// colors is flagged +32, so the resolve pass can drop it where it runs into the neighbour's line
float toneLineSq(float abSq, float cdSq, float st2)
{
  return float(abSq >= SQ255(TOL_E) && st2 * abSq > cdSq);
}

// a line found only because hue weighs more (+32) is dropped where the pixel at its far end is closer
// to E than to the line's color: that pixel belongs to E's side, so the line would cut into E's run.
// It is also dropped where its two colors clearly differ (more than XBRZ_FAR_TONE) and the line's color runs on
// along a 45-degree diagonal in the same color (alt45, as for plainLine): the line would bend that
// diagonal toward another stroke (the tip of Goku's nose in Buu's Fury)
bool farToneSq(vec3 b, float abSq, float tone, vec3 E, bool alt45)
{
  return !(tone > 0.5 && (distSqY(E, b) < abSq || (alt45 && abSq > SQ255(XBRZ_FAR_TONE))));
}

// the shallow (x) and steep (y) line tests of a corner, a line along a-b against one along c-d, as
// the flags they add (+16 and +64, and +32 for a line found only because hue weighs more): xBRZ's own
// test (STEEP_E * d(a, b) <= d(c, d)) without the crisp rules, the hue-weighted one with them
vec2 lineTests(vec3 a, vec3 b, vec3 c, vec3 d, vec3 E, float pairD, bool alt45s, bool alt45t)
{
  float abSq = distSqY(a, b), cdSq = distSqY(c, d), st2 = STEEP_E * STEEP_E;
  if (!CRISP_RULES)
    return vec2(st2 * abSq <= cdSq ? 16.0 : 0.0, st2 * cdSq <= abSq ? 64.0 : 0.0);
  float sabSq = DistShapeSq(a, b), scdSq = DistShapeSq(c, d);
  float toneSh = toneLineSq(abSq, cdSq, st2), toneSt = toneLineSq(cdSq, abSq, st2);
  float shallow = (((st2 * sabSq <= scdSq) && farToneSq(b, abSq, toneSh, E, alt45s)) || plainLineSq(abSq, cdSq, st2, pairD, alt45s)) ? 16.0 + 32.0 * toneSh : 0.0;
  float steep = (((st2 * scdSq <= sabSq) && farToneSq(d, cdSq, toneSt, E, alt45t)) || plainLineSq(cdSq, abSq, st2, pairD, alt45t)) ? 64.0 + 32.0 * toneSt : 0.0;
  return vec2(shallow, steep);
}

// ============================================================================================
// 30. Diagonal bands
// ============================================================================================
float bandSide(vec2 coord, vec2 o, vec2 p, vec2 q, vec3 e, vec3 cp, vec3 cpq)
{
  vec2 t = p - q;
  if (eq(cp, cpq))
  {
    bool a = eq(e, at5x5(coord, o + t)), b = eq(e, at5x5(coord, o - t));
    if (!a && !b) return 0.0;
    vec3 opp = at5x5(coord, o - p - q);
    float dSq = distSqY(opp, cp);
    if (dSq <= distSqY(opp, e) || dSq < SQ255(XBRZ_BAND_FAR)) return 0.0;
    if (dSq >= SQ255(XBRZ_BAND_FAR2) || (a && b)) return 1.0;
    return (a ? eq(e, at5x5(coord, o + 2.0 * t)) : eq(e, at5x5(coord, o - 2.0 * t))) ? 1.0 : 0.0;
  }
  float dAESq = distSqY(cpq, e);
  if (dAESq <= distSqY(cpq, cp) || dAESq < SQ255(XBRZ_BAND_FAR)) return 0.0;
  if (!eq(cpq, at5x5(coord, o + 2.0 * p)) && !eq(cpq, at5x5(coord, o + 2.0 * q))) return 0.0;
  if (!eq(e, at5x5(coord, o + t)) && !eq(e, at5x5(coord, o - t))) return 0.0;
  if (dAESq >= SQ255(XBRZ_BAND_FAR2)) return 1.0;
  return (eq(cp, at5x5(coord, o + p + t)) || eq(cp, at5x5(coord, o + q - t))) ? 1.0 : 0.0;
}

// 32 to 34: two close shades (under 30 apart)
bool near(vec3 a, vec3 b) { return withinY255(a, b, 30.0); }

vec4 diagonalBands(vec4 xbrz, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  vec4 band = vec4(0.0);
  if (XBRZ_MINC <= 0.0)
    return band;
  vec4 cut = vec4(greaterThan(BLEND(xbrz), vec4(0.0)));
  for (int k = 0; k < 4; k++)
  {
    vec4 m = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
    if (dot(cut, m) < 0.5) continue;
    vec2 v = vec2(0.0, k < 2 ? -1.0 : 1.0), h = vec2(k == 1 || k == 2 ? 1.0 : -1.0, 0.0);
    vec3 cV = k < 2 ? B : H, cH = k == 1 || k == 2 ? F : D;
    vec3 cVH = k == 0 ? A : (k == 1 ? C : (k == 2 ? I : G));
    bool vh = eq(cV, cH);
    if (!vh && !eq(E, cVH)) continue;
    float f = 0.0;
    for (int j = 0; j < 2; j++)
    {
      if (f > 0.5) continue;
      bool first = j == 0;
      vec2 o = vh ? (first ? vec2(0.0) : v + h) : (first ? v : h);
      vec2 p = vh ? (first ? v : -v) : (first ? -v : v);
      vec2 q = first ? h : -h;
      vec3 e   = vh ? (first ? E : cVH) : (first ? cV : cH);
      vec3 cp  = vh ? (first ? cV : cH) : (first ? E : cVH);
      vec3 cpq = vh ? (first ? cVH : E) : (first ? cH : cV);
      f = bandSide(coord, o, p, q, e, cp, cpq);
    }
    band += m * f;
  }
  return band;
}

// 30b. Outline around a strong shape
#define XBRZ_RING 64.0
float ringBand(vec3 Pc, vec3 Q, vec3 X, vec3 E)
{
  if (!alike(Pc, Q)) return 0.0;
  return float(!withinY255(Pc, X, XBRZ_RING) && !withinY255(Q, X, XBRZ_RING) && !withinY255(E, X, XBRZ_RING)
               && max(Pc.x, Q.x) < min(E.x, X.x));
}
float ringOutBand(vec3 E, vec3 K1, vec3 K2, vec3 X, vec3 N1, vec3 N2)
{
  if (!alike(E, K1) || !alike(E, K2)) return 0.0;
  float lE = E.x;
  return float(!withinY255(E, X, XBRZ_RING) && !withinY255(N1, X, XBRZ_RING) && !withinY255(N2, X, XBRZ_RING) && lE < X.x && lE < N1.x && lE < N2.x);
}

// ============================================================================================
// 1. Minimum contrast
// ============================================================================================
// a corner whose two colors (E and its closer candidate) differ by less than XBRZ_MINC stays square;
// one up to XBRZ_HYST below the limit is kept but marked weak afterwards (weakCorners)
vec4 minimumContrast(vec4 res, float dEB, float dED, float dEF, float dEH, out vec4 contrast, out vec4 weak)
{
  weak = vec4(0.0);
  contrast = vec4(0.0);
  if (XBRZ_MINC > 0.0)
  {
    contrast = vec4(min(dED, dEB), min(dEB, dEF), min(dEF, dEH), min(dEH, dED)) * 255.0;
    vec4 keep = vec4(greaterThanEqual(contrast, vec4(XBRZ_MINC - XBRZ_HYST)));
    weak = keep * vec4(lessThan(contrast, vec4(XBRZ_MINC)));
    res *= keep;
  }
  return res;
}

// a weak corner that is still cut after rules 2 to 7 gets blend type 3: the resolve pass rounds it
// only where the same corner of both neighbours along the cut is rounded
vec4 weakCorners(vec4 res, vec4 weak)
{
  weak *= vec4(greaterThan(BLEND(res), vec4(0.0)));
  return res + weak * (3.0 - BLEND(res));
}

// ============================================================================================
// helpers for rules 3 and 4
// ============================================================================================
float strokeEnds(vec3 p, vec3 q, vec2 coord, vec2 o, vec2 side)
{
  vec3 T = at5x5(coord, o);
  return float(!alike(p, T) && !alike(q, T) && !alike(p, at5x5(coord, o + side)) && !alike(p, at5x5(coord, o - side)));
}

float wallAt(vec2 coord, vec2 t, vec3 T)
{
  bool l = alike(T, at5x5(coord, vec2(t.x - 1.0, t.y))), r = alike(T, at5x5(coord, vec2(t.x + 1.0, t.y))),
       u = alike(T, at5x5(coord, vec2(t.x, t.y - 1.0))), d = alike(T, at5x5(coord, vec2(t.x, t.y + 1.0)));
  return float((l && (r || alike(T, at5x5(coord, vec2(t.x - 2.0, t.y))))) || (r && alike(T, at5x5(coord, vec2(t.x + 2.0, t.y)))) ||
               (u && (d || alike(T, at5x5(coord, vec2(t.x, t.y - 2.0))))) || (d && alike(T, at5x5(coord, vec2(t.x, t.y + 2.0)))));
}

float runWall(vec3 E, vec2 coord, vec2 d)
{
  vec3 c1 = at5x5(coord, d);
  if (!alike(E, c1)) return wallAt(coord, d, c1);
  vec3 c2 = PY(2.0 * d.x, 2.0 * d.y);
  if (!alike(E, c2)) return wallAt(coord, 2.0 * d, c2);
  vec3 c3 = PY(3.0 * d.x, 3.0 * d.y);
  if (!alike(E, c3)) return wallAt(coord, 3.0 * d, c3);
  return 1.0;
}

// ============================================================================================
// helper for rule 7
// ============================================================================================
bool stripeEnd(vec2 coord, vec2 o1, vec2 o2, vec2 o3, bool thin, vec3 E, vec3 A, vec3 B, vec3 C, vec3 D, vec3 F, vec3 G, vec3 H, vec3 I,
               vec3 l2, vec3 r2, vec3 rt, vec3 rb)
{
  // check all cheap register conditions before fetching distant o1, o2, o3
  if (!(thin && alike(E, F) && !eq(E, D) && !eq(B, A) && !eq(H, G) && alike(B, C) && alike(H, I)
        && alike(E, r2) && alike(C, rt) && alike(I, rb)))
    return false;
  bool aAE = alike(A, E), aEG = alike(E, G);
  if ((aAE && alike(B, D)) || (aEG && alike(D, H)))
    return false;
  bool nDE = !alike(D, E);
  if (aAE && nDE && !alike(B, E) && alike(E, PY(o1.x, o1.y)))
    return false;
  if (aEG && nDE && !alike(E, H) && alike(E, PY(o2.x, o2.y)))
    return false;
  return !eq(D, l2) || alike(E, PY(o3.x, o3.y));
}

// ============================================================================================
// Rules 2 to 7 (XBRZ_DIAG)
// ============================================================================================
vec4 diagonalRules(vec4 res, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                   vec4 pair, float dEB, float dED, float dEF, float dEH)
{
  vec4 cut = vec4(greaterThan(BLEND(res), vec4(0.0)));
  if (XBRZ_DIAG <= 0.0 || dot(cut, vec4(1.0)) <= 0.0)
    return res;
  vec4 before = res;

  // ---- what the rules look at ----
  vec4 dEP = vec4(dED, dEB, dEF, dEH);
  vec4 dEQ = vec4(dEB, dEF, dEH, dED);
  vec4 sec = FLAG(res, 8.0);
  vec3 Px = sec.x > 0.5 ? B : D, Py = sec.y > 0.5 ? F : B, Pz = sec.z > 0.5 ? H : F, Pw = sec.w > 0.5 ? D : H;
  vec3 Qx = sec.x > 0.5 ? D : B, Qy = sec.y > 0.5 ? B : F, Qz = sec.z > 0.5 ? F : H, Qw = sec.w > 0.5 ? H : D;
  float lE = E.x;
  vec4 lP = vec4(Px.x, Py.x, Pz.x, Pw.x);
  vec4 lQ = vec4(Qx.x, Qy.x, Qz.x, Qw.x);
  vec4 notLighter = vec4(lessThanEqual(lP, vec4(lE + XBRZ_NOT_LIGHTER / 255.0)));
  vec4 straight = vec4(float(sec.x > 0.5 ? alike(B, C) : alike(D, G)), float(sec.y > 0.5 ? alike(F, I) : alike(A, B)),
                       float(sec.z > 0.5 ? alike(G, H) : alike(C, F)), float(sec.w > 0.5 ? alike(A, D) : alike(H, I)));
  vec3 Rx = sec.x > 0.5 ? N_p0_m2 : N_m2_p0, Ry = sec.y > 0.5 ? N_p2_p0 : N_p0_m2;
  vec3 Rz = sec.z > 0.5 ? N_p0_p2 : N_p2_p0, Rw = sec.w > 0.5 ? N_m2_p0 : N_p0_p2;
  vec3 Sx = sec.x > 0.5 ? C : G, Sy = sec.y > 0.5 ? I : A, Sz = sec.z > 0.5 ? G : C, Sw = sec.w > 0.5 ? A : I;
  vec3 Ux = sec.x > 0.5 ? N_p1_m2 : N_m2_p1, Uy = sec.y > 0.5 ? N_p2_p1 : N_m1_m2;
  vec3 Uz = sec.z > 0.5 ? N_m1_p2 : N_p2_m1, Uw = sec.w > 0.5 ? N_m2_m1 : N_p1_p2;

  // ---- 2. Diagonal limit ----
  vec4 ramp = min((dEP + pair) / max(dEQ, vec4(SAFE_EPS)), (dEQ + pair) / max(dEP, vec4(SAFE_EPS)));
  vec4 limit = mix(vec4(XBRZ_DIAG), vec4(XBRZ_DIAG_AA), vec4(lessThanEqual(ramp, vec4(XBRZ_RAMP))));
  vec4 keep = max(vec4(lessThanEqual(pair * 255.0, limit)), vec4(greaterThanEqual(res, vec4(16.0))) * notLighter);
  vec4 tipLine;
  tipLine.x = sec.x > 0.5 ? float(alike(C, E) && min(distSqY(B, N_p0_m2), distSqY(B, N_p1_m2)) <= SQ255(XBRZ_STRIPE))
                          : float(alike(E, G) && min(distSqY(D, N_m2_p0), distSqY(D, N_m2_p1)) <= SQ255(XBRZ_STRIPE));
  tipLine.y = sec.y > 0.5 ? float(alike(E, I) && min(distSqY(F, N_p2_p0), distSqY(F, N_p2_p1)) <= SQ255(XBRZ_STRIPE))
                          : float(alike(A, E) && min(distSqY(B, N_p0_m2), distSqY(B, N_m1_m2)) <= SQ255(XBRZ_STRIPE));
  tipLine.z = sec.z > 0.5 ? float(alike(E, G) && min(distSqY(H, N_p0_p2), distSqY(H, N_m1_p2)) <= SQ255(XBRZ_STRIPE))
                          : float(alike(C, E) && min(distSqY(F, N_p2_p0), distSqY(F, N_p2_m1)) <= SQ255(XBRZ_STRIPE));
  tipLine.w = sec.w > 0.5 ? float(alike(A, E) && min(distSqY(D, N_m2_p0), distSqY(D, N_m2_m1)) <= SQ255(XBRZ_STRIPE))
                          : float(alike(E, I) && min(distSqY(H, N_p0_p2), distSqY(H, N_p1_p2)) <= SQ255(XBRZ_STRIPE));
  keep = max(keep, tipLine);
  vec4 wide = vec4(float(alike(E, sec.x > 0.5 ? F : H)), float(alike(E, sec.y > 0.5 ? H : D)),
                   float(alike(E, sec.z > 0.5 ? D : B)), float(alike(E, sec.w > 0.5 ? B : F)));
  vec4 block = wide * vec4(float(alike(E, sec.x > 0.5 ? H : F) && alike(E, I)), float(alike(E, sec.y > 0.5 ? D : H) && alike(E, G)),
                           float(alike(E, sec.z > 0.5 ? B : D) && alike(A, E)), float(alike(E, sec.w > 0.5 ? F : B) && alike(C, E)));
  vec4 lR = vec4(Rx.x, Ry.x, Rz.x, Rw.x);
  vec4 lU = vec4(Ux.x, Uy.x, Uz.x, Uw.x);
  vec4 dEPc = mix(dEP, dEQ, sec);
  vec4 inner = vec4(lessThanEqual(dEPc * 255.0, vec4(XBRZ_DIAG))) * vec4(lessThan(lQ, min(lP, vec4(lE)) - XBRZ_OUTLINE))
             * notLighter * (1.0 - straight) * wide * (1.0 - block);
  vec4 bevel = vec4(float(alike(E, Sx)), float(alike(E, Sy)), float(alike(E, Sz)), float(alike(E, Sw)))
             * vec4(lessThan(max(lR, lU), min(lP, vec4(lE)) - XBRZ_OUTLINE));
  inner *= 1.0 - bevel;
  keep = max(keep, inner);

  // ---- 6. Antialiasing notch (folded into rule 2's diagonal limit) ----
  vec4 loneP = vec4(0.0), loneQ = vec4(0.0);
  bool haveLone = false;
  vec4 blocked2 = (1.0 - keep) * cut;
  vec4 kept = vec4(0.0);
  float eASq = 0.0, eCSq = 0.0, eGSq = 0.0, eISq = 0.0;
  bool haveDiagDist = false;
  if (dot(blocked2, vec4(1.0)) > 0.0)
  {
    vec4 lone = vec4(float(!alike(A, B) && !alike(B, C) && !alike(B, N_p0_m2)), float(!alike(A, D) && !alike(D, G) && !alike(D, N_m2_p0)),
                     float(!alike(C, F) && !alike(F, I) && !alike(F, N_p2_p0)), float(!alike(G, H) && !alike(H, I) && !alike(H, N_p0_p2)));
    loneP = mix(lone.yxzw, lone.xzwy, sec);
    loneQ = mix(lone.xzwy, lone.yxzw, sec);
    haveLone = true;
    vec4 dQc = mix(dEQ, dEP, sec);
    vec4 notch = vec4(lessThanEqual((dEPc + pair) / max(dQc, vec4(SAFE_EPS)), vec4(XBRZ_RAMP)))
               * vec4(lessThanEqual(pair * 255.0, vec4(XBRZ_DIAG + XBRZ_NOTCH))) * loneP * blocked2;
    if (dot(notch, vec4(1.0)) > 0.0)
    {
      float t2 = XBRZ_TONE * XBRZ_TONE;
      vec4 wrap = vec4(lessThan(vec4(distSqY(A, Qx), distSqY(C, Qy), distSqY(I, Qz), distSqY(G, Qw)), t2 * (pair * pair)));
      eCSq = distSqY(C, E); eGSq = distSqY(E, G); eASq = distSqY(A, E); eISq = distSqY(E, I);
      haveDiagDist = true;
      vec4 along = vec4(
        float(eCSq < t2 * min(distSqY(B, C), distSqY(C, D)) || eGSq < t2 * min(distSqY(B, G), distSqY(D, G))),
        float(eASq < t2 * min(distSqY(A, B), distSqY(A, F)) || eISq < t2 * min(distSqY(B, I), distSqY(F, I))),
        float(eCSq < t2 * min(distSqY(C, F), distSqY(C, H)) || eGSq < t2 * min(distSqY(F, G), distSqY(G, H))),
        float(eASq < t2 * min(distSqY(A, D), distSqY(A, H)) || eISq < t2 * min(distSqY(D, I), distSqY(H, I))));
      notch *= wrap * along;
      keep = max(keep, notch);
      kept = notch;
    }
  }
  res += 128.0 * (1.0 - keep) * cut;
  res *= 1.0 - (1.0 - keep) * straight * cut;

  // ---- 3. Eye ----
  if (CRISP_RULES)
  {
    vec4 gate = straight * cut * vec4(lessThan(max(lP, lQ), vec4(lE - XBRZ_OUTLINE)));
    if (dot(gate, vec4(1.0)) > 0.0)
    {
      vec4 eye = vec4(float(!alike(Px, Qx) && alike(Qx, A) && !alike(Px, A) && !alike(Px, Rx) && !alike(E, sec.x > 0.5 ? H : F)),
                      float(!alike(Py, Qy) && alike(Qy, C) && !alike(Py, C) && !alike(Py, Ry) && !alike(E, sec.y > 0.5 ? D : H)),
                      float(!alike(Pz, Qz) && alike(Qz, I) && !alike(Pz, I) && !alike(Pz, Rz) && !alike(E, sec.z > 0.5 ? B : D)),
                      float(!alike(Pw, Qw) && alike(Qw, G) && !alike(Pw, G) && !alike(Pw, Rw) && !alike(E, sec.w > 0.5 ? F : B)))
                * gate;
      float stripeCG = float(min(distSqY(C, E), distSqY(E, G)) <= SQ255(XBRZ_STRIPE));
      float stripeAI = float(min(distSqY(A, E), distSqY(E, I)) <= SQ255(XBRZ_STRIPE));
      eye *= 1.0 - vec4(stripeCG, stripeAI, stripeCG, stripeAI);
      if (dot(eye, vec4(1.0)) > 0.0)
      {
        eye *= vec4(sec.x > 0.5 ? strokeEnds(Px, Qx, coord, vec2(2.0,-1.0), vec2(0.0,1.0)) : strokeEnds(Px, Qx, coord, vec2(-1.0,2.0), vec2(1.0,0.0)),
                    sec.y > 0.5 ? strokeEnds(Py, Qy, coord, vec2(1.0,2.0), vec2(1.0,0.0)) : strokeEnds(Py, Qy, coord, vec2(-2.0,-1.0), vec2(0.0,1.0)),
                    sec.z > 0.5 ? strokeEnds(Pz, Qz, coord, vec2(-2.0,1.0), vec2(0.0,1.0)) : strokeEnds(Pz, Qz, coord, vec2(1.0,-2.0), vec2(1.0,0.0)),
                    sec.w > 0.5 ? strokeEnds(Pw, Qw, coord, vec2(-1.0,-2.0), vec2(1.0,0.0)) : strokeEnds(Pw, Qw, coord, vec2(2.0,1.0), vec2(0.0,1.0)));
        res *= 1.0 - eye;
      }
    }
  }

  // ---- 4. Diagonal up to the wall ----
  vec4 changed = vec4(notEqual(res, before));
  if (dot(changed, vec4(1.0)) > 0.0)
  {
    if (!haveLone)
    {
      vec4 lone = vec4(float(!alike(A, B) && !alike(B, C) && !alike(B, N_p0_m2)), float(!alike(A, D) && !alike(D, G) && !alike(D, N_m2_p0)),
                       float(!alike(C, F) && !alike(F, I) && !alike(F, N_p2_p0)), float(!alike(G, H) && !alike(H, I) && !alike(H, N_p0_p2)));
      loneP = mix(lone.yxzw, lone.xzwy, sec);
      loneQ = mix(lone.xzwy, lone.yxzw, sec);
      haveLone = true;
    }
    // mask per corner by changed so unchanged corners do not waste runWall fetches or falsely set kept (suppressing rule 7)
    vec4 diagE = vec4(float(alike(C, E) || alike(E, G)), float(alike(A, E) || alike(E, I)),
                      float(alike(C, E) || alike(E, G)), float(alike(A, E) || alike(E, I))) * cut * changed;
    if (dot(diagE, vec4(1.0)) > 0.0)
    {
      vec4 partner = vec4(
        float((alike(C, E) && !alike(B, C) && !alike(C, N_p1_m2)) || (alike(E, G) && !alike(G, N_m2_p1) && !alike(D, G))),
        float((alike(A, E) && !alike(A, N_m1_m2) && !alike(A, B)) || (alike(E, I) && !alike(F, I) && !alike(I, N_p2_p1))),
        float((alike(C, E) && !alike(C, N_p2_m1) && !alike(C, F)) || (alike(E, G) && !alike(G, H) && !alike(G, N_m1_p2))),
        float((alike(A, E) && !alike(A, D) && !alike(A, N_m2_m1)) || (alike(E, I) && !alike(I, N_p1_p2) && !alike(H, I))));
      float l3CG = float((alike(C, E) && alike(E, PY(2., -2.))) || (alike(E, G) && alike(E, PY(-2., 2.))));
      float l3AI = float((alike(A, E) && alike(E, PY(-2., -2.))) || (alike(E, I) && alike(E, PY(2., 2.))));
      partner = max(partner, vec4(l3CG, l3AI, l3CG, l3AI));
      float lineR = float(alike(E, F) && alike(E, N_p2_p0)), lineL = float(alike(D, E) && alike(E, N_m2_p0));
      float lineD = float(alike(E, H) && alike(E, N_p0_p2)), lineU = float(alike(B, E) && alike(E, N_p0_m2));
      vec4 endLine = vec4(max(lineR, lineD), max(lineL, lineD), max(lineL, lineU), max(lineR, lineU));
      vec4 straightQ = vec4(float(sec.x > 0.5 ? alike(D, G) : alike(B, C)), float(sec.y > 0.5 ? alike(A, B) : alike(F, I)),
                            float(sec.z > 0.5 ? alike(C, F) : alike(G, H)), float(sec.w > 0.5 ? alike(H, I) : alike(A, D)));
      vec4 straightQ0 = max(straightQ, vec4(float(alike(Qx, A)), float(alike(Qy, C)), float(alike(Qz, I)), float(alike(Qw, G))));
      straightQ = max(straightQ, vec4(float(alike(Qx, A) && alike(Qx, sec.x > 0.5 ? N_m1_m2 : N_m2_m1)),
                                      float(alike(Qy, C) && alike(Qy, sec.y > 0.5 ? N_p2_m1 : N_p1_m2)),
                                      float(alike(Qz, I) && alike(Qz, sec.z > 0.5 ? N_p1_p2 : N_p2_p1)),
                                      float(alike(Qw, G) && alike(Qw, sec.w > 0.5 ? N_m2_p1 : N_m1_p2))));
      float sH = float(!alike(B, E) && !alike(E, H) && !alike(B, H)), sV = float(!alike(D, E) && !alike(E, F) && !alike(D, F));
      vec4 stripeE = vec4(sec.x > 0.5 ? sH : sV, sec.y > 0.5 ? sV : sH, sec.z > 0.5 ? sH : sV, sec.w > 0.5 ? sV : sH);
      vec4 bendQ = straightQ0 * (1.0 - straightQ) * stripeE;
      vec4 sQ = mix(straightQ0, straightQ, stripeE);
      vec3 Qnx = sec.x > 0.5 ? N_m2_p1 : N_p1_m2, Qny = sec.y > 0.5 ? N_m1_m2 : N_p2_p1;
      vec3 Qnz = sec.z > 0.5 ? N_p2_m1 : N_m1_p2, Qnw = sec.w > 0.5 ? N_p1_p2 : N_m2_m1;
      vec4 qRun = vec4(float(alike(Qx, Qnx)), float(alike(Qy, Qny)), float(alike(Qz, Qnz)), float(alike(Qw, Qnw)));
      vec4 run = partner * (1.0 - straight * sQ) * (1.0 - straight * vec4(lessThan(lP, vec4(lE))) * (1.0 - bendQ))
               * (1.0 - endLine * straight * (1.0 - bendQ)) * (1.0 - straight * (1.0 - straightQ0) * (1.0 - qRun)) * cut * changed;
      run *= 1.0 - loneP * loneQ;
      if (dot(run, vec4(1.0)) > 0.0)
      {
        float wCG = run.x + run.z > 0.0 ? max(alike(C, E) ? runWall(E, coord, vec2(1.0, -1.0)) : 0.0, alike(E, G) ? runWall(E, coord, vec2(-1.0, 1.0)) : 0.0) : 0.0;
        float wAI = run.y + run.w > 0.0 ? max(alike(E, I) ? runWall(E, coord, vec2(1.0, 1.0)) : 0.0, alike(A, E) ? runWall(E, coord, vec2(-1.0, -1.0)) : 0.0) : 0.0;
        run *= vec4(wCG, wAI, wCG, wAI);
      }
      res = mix(res, before, run);
      kept = max(kept, run);
    }
  }

  // ---- 5. Thin light stroke ----
  vec4 back = vec4(greaterThan(vec4(lE) - max(lP, lQ), vec4(XBRZ_THIN_LIGHT))) * cut * vec4(notEqual(res, before)) * (1.0 - loneP * loneQ);
  if (dot(back, vec4(1.0)) > 0.0)
  {
    vec4 dPQmin = min(dEP, dEQ);
    if (!haveDiagDist)
    {
      eCSq = distSqY(C, E); eGSq = distSqY(E, G); eASq = distSqY(A, E); eISq = distSqY(E, I);
    }
    vec4 tE = XBRZ_TONE * dPQmin;
    vec4 tESq = tE * tE;
    bvec4 aD = bvec4(alike(C, E), alike(E, G), alike(A, E), alike(E, I));
    bvec4 nD = bvec4(aD.x || eCSq < tESq.x, aD.y || eGSq < tESq.x, aD.z || eASq < tESq.y, aD.w || eISq < tESq.y);
    bvec4 nD2 = bvec4(aD.x || eCSq < tESq.z, aD.y || eGSq < tESq.z, aD.z || eASq < tESq.w, aD.w || eISq < tESq.w);
    vec4 sideA = vec4(float(aD.x && !(dEF < tE.x)) + float(aD.y && !(dEH < tE.x)), float(aD.z && !(dED < tE.y)) + float(aD.w && !(dEH < tE.y)),
                      float(aD.x && !(dEB < tE.z)) + float(aD.y && !(dED < tE.z)), float(aD.z && !(dEB < tE.w)) + float(aD.w && !(dEF < tE.w)));
    vec4 sideN = vec4(float(nD.x && !(dEF < tE.x)) + float(nD.y && !(dEH < tE.x)), float(nD.z && !(dED < tE.y)) + float(nD.w && !(dEH < tE.y)),
                      float(nD2.x && !(dEB < tE.z)) + float(nD2.y && !(dED < tE.z)), float(nD2.z && !(dEB < tE.w)) + float(nD2.w && !(dEF < tE.w)));
    sideA = min(sideA, vec4(1.0)); sideN = min(sideN, vec4(1.0));
    vec4 farOff = vec4(float(!alike(E, I)), float(!alike(E, G)), float(!alike(A, E)), float(!alike(C, E)));
    vec4 along = max(sideA * vec4(lessThan(max(lP, lQ), vec4(XBRZ_THIN_DARK))), sideN * farOff);
    back *= along;
    res = mix(res, before, back);
    kept = max(kept, back);
  }

  // ---- 7. Stripe ends ----
  bool eB = eq(E, B), eD = eq(E, D), eF = eq(E, F), eH = eq(E, H);
  vec3 fB = eB ? N_p0_m2 : N_p0_p2, fD = eD ? N_m2_p0 : N_p2_p0;
  bool thinH = !eq(B, H) && ((!eB && !eH) || (eB != eH && !eq(fB, E)));
  bool thinV = !eq(D, F) && ((!eD && !eF) || (eD != eF && !eq(fD, E)));
  vec4 open4 = vec4(greaterThan(BLEND(res), vec4(0.0))) * vec4(greaterThan(pair * 255.0, vec4(XBRZ_TIP))) * (1.0 - kept);
  if ((thinH || thinV) && dot(open4, vec4(1.0)) > 0.0)
  {
    float endL = float(stripeEnd(coord, vec2(-2., -2.), vec2(-2., 2.), vec2(3., 0.), thinH, E, A, B, C, D, F, G, H, I, N_m2_p0, N_p2_p0, N_p2_m1, N_p2_p1));
    float endR = float(stripeEnd(coord, vec2(2., -2.), vec2(2., 2.), vec2(-3., 0.), thinH, E, C, B, A, F, D, I, H, G, N_p2_p0, N_m2_p0, N_m2_m1, N_m2_p1));
    float endT = float(stripeEnd(coord, vec2(-2., -2.), vec2(2., -2.), vec2(0., 3.), thinV, E, A, D, G, B, H, C, F, I, N_p0_m2, N_p0_p2, N_m1_p2, N_p1_p2));
    float endB = float(stripeEnd(coord, vec2(-2., 2.), vec2(2., 2.), vec2(0., -3.), thinV, E, G, D, A, H, B, I, F, C, N_p0_p2, N_p0_m2, N_m1_m2, N_p1_m2));
    if (endL + endR + endT + endB > 0.0)
    {
      bool nB = alike(B, E), nD = alike(D, E), nF = alike(E, F), nH = alike(E, H);
      vec4 tip = vec4(max(endL, endT), max(endR, endT), max(endR, endB), max(endL, endB));
      tip *= vec4(greaterThan(pair * 255.0, vec4(XBRZ_TIP)));
      float aH = float((nB && !eB) || (nH && !eH)), aV = float((nD && !eD) || (nF && !eF));
      vec4 soft = vec4(max(endL * aH, endT * aV), max(endR * aH, endT * aV), max(endR * aH, endB * aV), max(endL * aH, endB * aV));
      soft *= vec4(lessThan(max(lP, lQ), vec4(lE - XBRZ_OUTLINE)));
      tip *= 1.0 - soft * min(FLAG(res, 16.0) + FLAG(res, 64.0), vec4(1.0));
      res *= 1.0 - tip * (1.0 - kept);
    }
  }
  return res;
}

// ============================================================================================
// 8. Line through an antialiasing pixel
// ============================================================================================
vec4 lineThroughAA(vec4 res, vec4 xbrz, vec4 contrast, vec3 B, vec3 D, vec3 F, vec3 H,
                   vec4 pairDist, float dEB, float dED, float dEF, float dEH)
{
  if (XBRZ_MINC <= 0.0)
    return res;
  vec4 cut = vec4(greaterThan(BLEND(res), vec4(0.0))) * vec4(lessThan(BLEND(res), vec4(3.0))) * FLAG(res, 4.0) * vec4(lessThan(res, vec4(128.0)));
  vec4 sq = vec4(lessThan(contrast, vec4(XBRZ_MINC))) * vec4(greaterThan(BLEND(xbrz), vec4(0.0))) * FLAG(xbrz, 4.0)
          * vec4(notEqual(BLEND(res), vec4(1.0))) * vec4(notEqual(BLEND(res), vec4(2.0)));
  vec4 pair = sq * cut.zwxy;
  if (dot(pair, vec4(1.0)) <= 0.0)
    return res;
  vec4 sc = FLAG(xbrz, 8.0);
  // Reuse precomputed cardinal distances (dEB..dEH) and diagonal pair distances (pairDist):
  // when st8 checks the first neighbor against C (or sh8 checks the second against C), it is non-trivial only when
  // that neighbor is Q != C, whose distances to C and E are already pairDist and dQE (0 sqrt calls).
  vec4 dE1 = vec4(dED, dEB, dEF, dEH);
  vec4 dE2 = vec4(dEB, dEF, dEH, dED);
  vec4 dPE = mix(dE1, dE2, sc);
  vec4 dQE = mix(dE2, dE1, sc);
  vec4 st8 = FLAG(xbrz, 64.0), sh8 = FLAG(xbrz, 16.0);
  vec4 thirdCond = vec4(greaterThanEqual(min(pairDist, dQE) * 255.0, vec4(XBRZ_MINC)))
                 * vec4(greaterThan(dPE + pairDist, XBRZ_AA_OFF * dQE))
                 * vec4(greaterThan(dPE + dQE, XBRZ_AA_OFF * pairDist));
  pair *= 1.0 - (st8 * sc + sh8 * (1.0 - sc)) * thirdCond;
  float bxz = 0.0;
  if (pair.x + pair.z > 0.0)
  {
    vec3 Cx = sc.x > 0.5 ? B : D, Cz = sc.z > 0.5 ? H : F;
    float dXZ = distY(Cx, Cz);
    bxz = float(dPE.x + dPE.z <= XBRZ_AA_LINE * dXZ && dXZ * 255.0 >= XBRZ_AA_EDGE);
  }
  float byw = 0.0;
  if (pair.y + pair.w > 0.0)
  {
    vec3 Cy = sc.y > 0.5 ? F : B, Cw = sc.w > 0.5 ? D : H;
    float dYW = distY(Cy, Cw);
    byw = float(dPE.y + dPE.w <= XBRZ_AA_LINE * dYW && dYW * 255.0 >= XBRZ_AA_EDGE);
  }
  return mix(res, xbrz, pair * vec4(bxz, byw, bxz, byw));
}

// ============================================================================================
// 10. Pixel closed between outlines
// ============================================================================================
vec4 closedPixel(vec4 res, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  vec4 line = min(FLAG(res, 16.0) + FLAG(res, 64.0), 1.0) * vec4(greaterThan(BLEND(res), vec4(0.0)));
  if (XBRZ_DIAG <= 0.0 || dot(line, vec4(1.0)) <= 0.0)
    return res;
  vec4 sc = FLAG(res, 8.0);
  vec3 Px = sc.x > 0.5 ? B : D, Py = sc.y > 0.5 ? F : B, Pz = sc.z > 0.5 ? H : F, Pw = sc.w > 0.5 ? D : H;
  vec4 lQ = vec4(A.x, C.x, I.x, G.x);
  vec4 lP = vec4(Px.x, Py.x, Pz.x, Pw.x);
  vec4 dark = vec4(lessThan(lQ + XBRZ_BLACK_GAP, lP)) * vec4(lessThan(lQ + XBRZ_BLACK_GAP, vec4(E.x))) * vec4(lessThan(lQ, vec4(XBRZ_BLACK)));
  vec4 closed = dark * line;
  if (dot(closed, vec4(1.0)) <= 0.0)
    return res;
  // dark already guarantees luma gap > 0.1 (25.5/255 > XBRZ_ALIKE = 20/255), so !alike(Q, P) and !alike(Q, E) always hold
  bool sx = sc.x > 0.5 ? (alike(A, C) && alike(A, D)) : (alike(A, G) && alike(A, B));
  bool sy = sc.y > 0.5 ? (alike(C, I) && alike(B, C)) : (alike(A, C) && alike(C, F));
  bool sz = sc.z > 0.5 ? (alike(G, I) && alike(F, I)) : (alike(C, I) && alike(H, I));
  bool sw = sc.w > 0.5 ? (alike(A, G) && alike(G, H)) : (alike(G, I) && alike(D, G));
  closed *= vec4(sx, sy, sz, sw);
  return res * (1.0 - closed);
}

// ============================================================================================
// 11. Lines in a larger window
// ============================================================================================
float onTone(vec3 X, vec3 a, vec3 b)
{
  float daSq = distSqY(X, a);
  return float(daSq < distSqY(X, b) && daSq <= SQ255(XBRZ_ALIKE));
}
#define RP(o) at5x5(coord, rot * (o))

// the pixel at offset o (components -1, 0 or 1) of the 3x3
vec3 at3x3(vec2 o, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  if (o.y < -0.5)
    return o.x < -0.5 ? A : (o.x > 0.5 ? C : B);
  if (o.y > 0.5)
    return o.x < -0.5 ? G : (o.x > 0.5 ? I : H);
  return o.x < -0.5 ? D : (o.x > 0.5 ? F : E);
}

// one corner, in its own frame: Fa, Fb, O1, eStrong and pStrong are already evaluated from 3x3 registers
float stripeLine(vec2 coord, mat2 rot, vec3 E, vec3 Pc, float shape, vec3 Fa, vec3 Fb, vec3 O1, float eStrong, float pStrong)
{
  vec2 e3, e4, p1, p2, p3, p4, p5, o2, o3;
  if (shape < 0.5)
  {
    e3 = vec2(2., -2.); e4 = vec2(-2., 2.);
    p1 = vec2(2., -1.); p2 = vec2(-1., 2.); p3 = p1; p4 = vec2(3., -2.); p5 = vec2(-2., 3.);
    o2 = vec2(2., 0.); o3 = vec2(0., 2.);
  }
  else if (shape < 1.5)
  {
    e3 = vec2(2., -1.); e4 = vec2(-2., 1.);
    p1 = vec2(-1., 1.); p2 = vec2(2., 0.); p3 = vec2(-2., 2.); p4 = vec2(3., -1.); p5 = vec2(-3., 2.);
    o2 = vec2(0., 2.); o3 = vec2(2., 1.);
  }
  else
  {
    e3 = vec2(-1., 2.); e4 = vec2(1., -2.);
    p1 = vec2(1., -1.); p2 = vec2(0., 2.); p3 = vec2(2., -2.); p4 = vec2(-1., 3.); p5 = vec2(2., -3.);
    o2 = vec2(2., 0.); o3 = vec2(1., 2.);
  }
  float p1Tone = onTone(RP(p1), Pc, E);
  float runs = onTone(RP(e3), E, Pc) * onTone(RP(e4), E, Pc)
             * p1Tone * onTone(RP(p2), Pc, E)
             * (shape < 0.5 ? p1Tone : onTone(RP(p3), Pc, E))
             * onTone(RP(p4), Pc, E) * onTone(RP(p5), Pc, E)
             * (1.0 - onTone(Fa, Pc, E)) * (1.0 - onTone(Fb, Pc, E));
  if (runs <= 0.0)
    return 0.0;
  // eStrong already enforces dist(Fa/Fb, E) >= 40 > XBRZ_ALIKE (so !onTone(Fa/Fb, E, Pc)) and runs > 0 enforces !onTone(Fa/Fb, Pc, E)
  if (eStrong > 0.5)
    return 1.0;
  // pStrong already enforces dist(O1, Pc) >= 40 > XBRZ_ALIKE (so !onTone(O1, Pc, E))
  return pStrong * (1.0 - onTone(O1, E, Pc)) * (1.0 - onTone(RP(o2), Pc, E)) * (1.0 - onTone(RP(o3), Pc, E));
}

vec4 diagonalStripes(vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                     float dEB, float dED, float dEF, float dEH, vec4 xb, vec4 sq)
{
  vec4 shape = FLAG(xb, 4.0) * (FLAG(xb, 16.0) + 2.0 * FLAG(xb, 64.0));
  vec3 Px = dED <= dEB + TIE_EPS ? D : B, Qx = dED <= dEB + TIE_EPS ? B : D;
  vec3 Py = dEB <= dEF + TIE_EPS ? B : F, Qy = dEB <= dEF + TIE_EPS ? F : B;
  vec3 Pz = dEF <= dEH + TIE_EPS ? F : H, Qz = dEF <= dEH + TIE_EPS ? H : F;
  vec3 Pw = dEH <= dED + TIE_EPS ? H : D, Qw = dEH <= dED + TIE_EPS ? D : H;
  sq *= vec4(lessThan(shape, vec4(2.5))) * vec4(onTone(Qx, Px, E), onTone(Qy, Py, E), onTone(Qz, Pz, E), onTone(Qw, Pw, E));
  vec4 r = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
    if (dot(sq, m) <= 0.0) continue;
    mat2 rot = k == 0 ? mat2(-1., 0., 0., -1.) : (k == 1 ? mat2(0., -1., 1., 0.) : (k == 2 ? mat2(1., 0., 0., 1.) : mat2(0., 1., -1., 0.)));
    vec3 Pc = k == 0 ? Px : (k == 1 ? Py : (k == 2 ? Pz : Pw));
    float sh = dot(shape, m);
    vec3 Fa = at3x3(rot * (sh > 1.5 ? vec2(-1., 0.) : vec2(0., -1.)), A, B, C, D, E, F, G, H, I);
    vec3 Fb = at3x3(rot * (sh < 0.5 ? vec2(-1., 0.) : vec2(-1., -1.)), A, B, C, D, E, F, G, H, I);
    vec3 O1 = at3x3(rot * vec2(1., 1.), A, B, C, D, E, F, G, H, I);
    float eStrong = float(!withinY255(Fa, E, XBRZ_STRONG) && !withinY255(Fb, E, XBRZ_STRONG));
    float pStrong = float(!withinY255(O1, Pc, XBRZ_STRONG));
    if (eStrong + pStrong <= 0.0) continue;
    vec2 e1 = sh < 0.5 ? vec2(1., -1.) : (sh < 1.5 ? vec2(-1., 0.) : vec2(0., -1.));
    vec2 e2 = sh < 0.5 ? vec2(-1., 1.) : (sh < 1.5 ? vec2(1., -1.) : vec2(-1., 1.));
    if (onTone(at3x3(rot * e1, A, B, C, D, E, F, G, H, I), E, Pc) * onTone(at3x3(rot * e2, A, B, C, D, E, F, G, H, I), E, Pc) <= 0.0)
      continue;
    r += m * stripeLine(coord, rot, E, Pc, sh, Fa, Fb, O1, eStrong, pStrong);
  }
  return r;
}

vec4 largerWindowLines(vec4 res, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I, float dEB, float dED, float dEF, float dEH,
                       vec4 xbrz, vec4 contrast, inout vec4 weak)
{
  vec4 sq = vec4(lessThan(contrast, vec4(XBRZ_MINC))) * vec4(greaterThan(BLEND(xbrz), vec4(0.0)));
  if (XBRZ_MINC > 0.0 && dot(sq, vec4(1.0)) > 0.0)
  {
    sq *= diagonalStripes(coord, A, B, C, D, E, F, G, H, I, dEB, dED, dEF, dEH, xbrz, sq);
    res = mix(res, xbrz, sq);
    weak *= 1.0 - sq;
  }
  return res;
}

// ============================================================================================
// 13. Tiles between walls
// ============================================================================================
float tileStripe(vec2 coord, vec3 E, vec2 a, vec2 w)
{
  vec3 P1 = at5x5(coord, a), Q = at5x5(coord, w), Q2 = at5x5(coord, w + a), O = at5x5(coord, -w), O2 = at5x5(coord, a - w);
  vec3 T0 = at5x5(coord, -a);
  float lE = E.x, lP = P1.x, lQ = Q.x, lO = O.x;
  bool light = min(lE, lP) > max(lQ, lO) + XBRZ_OUTLINE, dark = max(lE, lP) + XBRZ_OUTLINE < min(lQ, lO);
  if (!((light || dark) && alike(Q, Q2) && alike(O, O2) && !alike(E, T0) && !alike(T0, Q) && !alike(T0, O)))
    return 0.0;
  vec3 T3 = at5x5(coord, 2.0 * a);
  bool wallQ = alike(Q, at5x5(coord, w - a)) || alike(Q, at5x5(coord, w + 2.0 * a));
  bool wallO = alike(O, at5x5(coord, -w - a)) || alike(O, at5x5(coord, 2.0 * a - w));
  bool tiles = !alike(P1, T3) && !alike(T3, Q) && !alike(T3, O) && (alike(T0, P1) || alike(E, T3));
  return float(wallQ && wallO && tiles);
}

vec4 tilesBetweenWalls(vec4 res, vec2 coord, vec3 E)
{
  if (!(CRISP_RULES && max(max(res.x, res.y), max(res.z, res.w)) >= 128.0))
    return res;
  vec4 blk = vec4(greaterThanEqual(res, vec4(128.0))) * vec4(greaterThan(BLEND(res), vec4(0.0)));
  vec4 sc = FLAG(mod(res, 128.0), 8.0);
  vec4 tile = vec4(0.0);
  vec2 d = vec2(-1., 0.);
  for (int k = 0; k < 4; k++)
  {
    vec2 n = vec2(-d.y, d.x);
    vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
    if (dot(blk, m) > 0.0)
    {
      bool second = dot(sc, m) > 0.5;
      tile += m * tileStripe(coord, E, second ? n : d, second ? d : n);
    }
    d = n;
  }
  res *= 1.0 - tile;
  return res;
}

// ============================================================================================
// 16 and 18. Line in another color
// ============================================================================================
vec4 lineInOtherColor(vec4 res, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                      vec4 pair, float dEB, float dED, float dEF, float dEH)
{
  if (XBRZ_MINC <= 0.0)
    return res;
  vec4 r = res;
  vec4 sh = FLAG(r, 16.0), st = FLAG(r, 64.0), sec = FLAG(r, 8.0);
  vec4 tint = vec4(greaterThan(BLEND(r), vec4(0.0))) * FLAG(r, 4.0) *
              abs(sh - st) * (sh * sec + st * (1.0 - sec)) * vec4(greaterThan(pair * 255.0, vec4(XBRZ_TINT)));
  if (dot(tint, vec4(1.0)) <= 0.0)
    return res;
  vec4 pShSq = vec4(distSqY(C, D), distSqY(B, I), distSqY(F, G), distSqY(A, H));
  vec4 pStSq = vec4(distSqY(B, G), distSqY(A, F), distSqY(C, H), distSqY(D, I));
  tint *= vec4(lessThan(sh * pShSq + st * pStSq, vec4(SQ255(TOL_E))));
  vec4 dE1 = vec4(dED, dEB, dEF, dEH);
  vec4 dE2 = vec4(dEB, dEF, dEH, dED);
  vec4 dP = mix(dE1, dE2, sec), dL = mix(dE2, dE1, sec);
  tint *= vec4(greaterThan(dP + pair, XBRZ_TINT_RAMP * dL));
  if (dot(tint, vec4(1.0)) <= 0.0)
    return res;
  bool lone = !(IsPixEqual(A, E) || IsPixEqual(B, E) || IsPixEqual(C, E) || IsPixEqual(D, E) ||
                IsPixEqual(E, F) || IsPixEqual(E, G) || IsPixEqual(E, H) || IsPixEqual(E, I));
  bool straight = IsPixEqual(D, F) || IsPixEqual(B, H);
  vec3 pX = st.x > 0.5 ? D : B, pY = st.y > 0.5 ? B : F, pZ = st.z > 0.5 ? F : H, pW = st.w > 0.5 ? H : D;
  vec4 eOnSq = vec4(min(distSqY(E, st.x > 0.5 ? N_m1_p2 : N_p2_m1), distSqY(E, st.x > 0.5 ? N_p1_m2 : N_m2_p1)),
                    min(distSqY(E, st.y > 0.5 ? N_m2_m1 : N_p1_p2), distSqY(E, st.y > 0.5 ? N_p2_p1 : N_m1_m2)),
                    min(distSqY(E, st.z > 0.5 ? N_p1_m2 : N_m2_p1), distSqY(E, st.z > 0.5 ? N_m1_p2 : N_p2_m1)),
                    min(distSqY(E, st.w > 0.5 ? N_p2_p1 : N_m1_m2), distSqY(E, st.w > 0.5 ? N_m2_m1 : N_p1_p2)));
  vec4 pOnSq = vec4(distSqY(pX, st.x > 0.5 ? N_p0_m2 : N_m2_p0), distSqY(pY, st.y > 0.5 ? N_p2_p0 : N_p0_m2),
                    distSqY(pZ, st.z > 0.5 ? N_p0_p2 : N_p2_p0), distSqY(pW, st.w > 0.5 ? N_m2_p0 : N_p0_p2));
  vec4 stripes = vec4(lessThan(eOnSq, vec4(SQ255(TOL_E)))) * vec4(lessThan(pOnSq, vec4(SQ255(TOL_E)))) * (straight ? 0.0 : 1.0);
  tint *= max(vec4(lessThan(r, vec4(128.0))), stripes);
  vec4 tint0 = tint;
  vec4 lumC1 = vec4(D.x, B.x, F.x, H.x);
  vec4 lumC2 = lumC1.yzwx;
  vec4 lumLine = mix(lumC1, lumC2, st);
  vec4 dark = vec4(lessThan(lumLine, vec4(E.x))) * (straight ? 0.0 : 1.0);
  if (!lone)
  {
    dark *= vec4(lessThan(lumLine, vec4(XBRZ_TINT_DARK)));
    dark *= vec4(greaterThanEqual(mix(lumC2, lumC1, st), vec4(XBRZ_TINT_DARK)));
    tint *= dark;
  }
  dark = max(dark, stripes);
  tint = max(tint, tint0 * stripes);
  vec4 flip = st - sec;
  vec4 shape = lone ? (16.0 * sh + 64.0 * st + 32.0 * FLAG(r, 32.0)) * (1.0 - stripes) : vec4(0.0);
  res -= tint * dark * (shape - 8.0 * flip);
  res *= 1.0 - tint * (1.0 - dark);
  res -= 128.0 * vec4(greaterThanEqual(r, vec4(128.0))) * tint * dark;
  return res;
}

// ============================================================================================
// The corners of E, written once in one frame
// ============================================================================================
// Computes line blend flags for a cut corner; lineTests runs only when cornerCut passes
float xbrzCorner(int own, int nbr0, int nbr4, float edge, float pairD,
                 vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I, vec3 altS, vec3 altT)
{
  if (!cornerCut(own, nbr0, nbr4, edge, E, G, H, I, F, C))
    return 0.0;
  vec2 line = lineTests(F, G, H, C, E, pairD, eq(altS, H) && !eq(G, H), eq(altT, F) && !eq(C, F));
  float r = 4.0;
  if (neq(E, G) && neq(D, G)) r += line.x;
  if (neq(E, C) && neq(B, C)) r += line.y;
  return r;
}

struct Win
{
  vec3 A, B, C, D, E, F, G, H, I;
  vec3 m1_m2, p0_m2, p1_m2, m2_m1, p2_m1, m2_p0, p2_p0, m2_p1, p2_p1, m1_p2, p0_p2, p1_p2;
  vec4 dE, pair;
};

Win turn(Win o)
{
  return Win(o.C, o.F, o.I, o.B, o.E, o.H, o.A, o.D, o.G,
             o.p2_m1, o.p2_p0, o.p2_p1, o.p1_m2, o.p1_p2, o.p0_m2, o.p0_p2, o.m1_m2, o.m1_p2, o.m2_m1, o.m2_p0, o.m2_p1,
             o.dE.yzwx, o.pair.yzwx);
}

vec2 cornerLines(Win n)
{
  return lineTests(n.F, n.G, n.H, n.C, n.E, n.pair.z, eq(n.m1_p2, n.H) && !eq(n.G, n.H), eq(n.p2_m1, n.F) && !eq(n.C, n.F));
}

float cutFlags(Win n, vec2 line)
{
  float r = 4.0;
  if (neq(n.E, n.G) && neq(n.D, n.G)) r += line.x;
  if (neq(n.E, n.C) && neq(n.B, n.C)) r += line.y;
  return r;
}

float noLine(float r) { return mod(r, 4.0) + 8.0 * mod(floor(r / 8.0), 2.0); }

// 33. Hole in a thick stroke
float holeInStroke(Win n, float r)
{
  float ln = FLAG(r, 4.0) * FLAG(r, 16.0) * FLAG(r, 64.0);
  float dEB = n.dE.x, dEF = n.dE.y, dED = n.dE.w;
  float dEFSq = dEF * dEF;
  if (ln > 0.5 && dEF * 255.0 >= 64.0 && eq(n.F,n.H) && eq(n.F,n.C) && eq(n.H,n.G) && neq(n.I,n.E) && neq(n.I,n.F)
      && (dEB * 255.0 < 30.0) && (dED * 255.0 < 30.0) && distSqY(n.I, n.F) < dEFSq && distSqY(n.I, n.E) < dEFSq
      && neq(n.I, n.p2_p1) && neq(n.I, n.p1_p2) && neq(n.F, n.p2_p1) && neq(n.F, n.p1_p2) && (eq(n.F, n.p2_p0) || eq(n.H, n.p0_p2)))
    return noLine(r);
  return r;
}

// 32 & 35. Lone pixel test redone and edge of a thin band
float lonePixelRedone(Win n, vec4 r, ivec4 b)
{
  vec4 bl = mod(r, 4.0);
  float ln = mod(floor(r.z / 4.0), 2.0);
  float c4 = min(n.dE.y, n.dE.z) * 255.0;
  float dEB = n.dE.x, dED = n.dE.w;
  if ((bl.z > 0.0 && ln < 0.5 && !((eq(n.E,n.D) && !eq(n.E,n.m2_p0)) || (eq(n.E,n.B) && !eq(n.E,n.p0_m2))) && bl.y == 0.0 && bl.w == 0.0
       && c4 >= 64.0 && b.z == BLEND_NORMAL && eq(n.F,n.H) && eq(n.F,n.C) && eq(n.H,n.G) && neq(n.F, n.p2_p0) && neq(n.H, n.p0_p2)
       && cornerCut(b.z, BLEND_NONE, BLEND_NONE, min(n.dE.y, n.dE.z), n.E, n.G, n.H, n.I, n.F, n.C))
      || (bl.z == 1.0 && ln < 0.5 && c4 >= 40.0 && c4 < XBRZ_GUARD_EDGE && eq(n.F,n.H) && !withinY255(n.I, n.F, 40.0)
       && ((eq(n.G,n.H) && eq(n.F,n.p2_p0) && (dED * 255.0 < 30.0) && near(n.E,n.C) && !withinY255(n.p0_p2, n.H, 40.0))
        || (eq(n.C,n.F) && eq(n.H,n.p0_p2) && (dEB * 255.0 < 30.0) && near(n.E,n.G) && !withinY255(n.p2_p0, n.F, 40.0)))
       && cornerCut(b.z, b.y, b.w, 1.0, n.E, n.G, n.H, n.I, n.F, n.C)))
    return cutFlags(n, cornerLines(n));
  return 0.0;
}

// 34. Small square of close shades
float smallSquare(Win n, float r)
{
  if (min(n.dE.y, n.dE.z) * 255.0 >= 48.0 && (n.dE.w * 255.0 < 30.0) && (n.dE.x * 255.0 < 30.0) && near(n.E,n.A) && (n.E != n.D || n.E != n.B || n.E != n.A)
      && eq(n.F,n.C) && eq(n.F,n.H) && eq(n.F,n.G) && eq(n.F,n.m2_p0) && eq(n.F,n.m2_m1) && eq(n.F,n.p0_m2) && eq(n.F,n.m1_m2))
    return noLine(r);
  return r;
}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping:  -|x|x|x|-
  //                       x|A|B|C|x
  //                       x|D|E|F|x
  //                       x|G|H|I|x
  //                       -|x|x|x|-

@PASS0_COORDS@

  // Read B, D and E as vec4 so their alpha (the point pass's decisions) is reused below without re-fetching
  vec4 tB = P4( 0.,-1.);
  vec4 tD = P4(-1., 0.);
  vec4 tE = P4( 0., 0.);
  vec3 B = tB.rgb, D = tD.rgb, E = tE.rgb;
  vec3 F = P( 1., 0.);
  vec3 H = P( 0., 1.);

  // fast path: xBRZ blends a corner only where E differs from both pixels beside it, so where E equals
  // opposite side neighbours (D and F, or B and H) nothing is cut
  if ((eq(E, D) && eq(E, F)) || (eq(E, B) && eq(E, H)))
  {
    FRAG_OUT = vec4(0.0);
    return;
  }

  vec4 tA = P4(-1.,-1.);
  float ptA = floor(tA.a * 255.0 + 0.5), ptB = floor(tB.a * 255.0 + 0.5);
  float ptE = floor(tE.a * 255.0 + 0.5), ptD = floor(tD.a * 255.0 + 0.5);
  vec4 pts = vec4(floor(ptA / 64.0), mod(floor(ptB / 16.0), 4.0), mod(ptE, 4.0), mod(floor(ptD / 4.0), 4.0));
  vec2 ip = floor(coord * SRC_SIZE.xy);
  pts *= vec4(min(ip.x, ip.y) > 0.5, ip.y > 0.5, 1.0, ip.x > 0.5);
  if (dot(pts, vec4(1.0)) == 0.0)
  {
    FRAG_OUT = vec4(0.0);
    return;
  }

  // pre-convert all 21 neighborhood pixels once to linear YCbCr
  vec3 A = toYCbCr(tA.rgb);
  B = toYCbCr(B);
  vec3 C = PY( 1.,-1.);
  D = toYCbCr(D);
  E = toYCbCr(E);
  F = toYCbCr(F);
  vec3 G = PY(-1., 1.);
  H = toYCbCr(H);
  vec3 I = PY( 1., 1.);
  N_m1_m2 = PY(-1., -2.);
  N_p0_m2 = PY( 0., -2.);
  N_p1_m2 = PY( 1., -2.);
  N_m2_m1 = PY(-2., -1.);
  N_p2_m1 = PY( 2., -1.);
  N_m2_p0 = PY(-2.,  0.);
  N_p2_p0 = PY( 2.,  0.);
  N_m2_p1 = PY(-2.,  1.);
  N_p2_p1 = PY( 2.,  1.);
  N_m1_p2 = PY(-1.,  2.);
  N_p0_p2 = PY( 0.,  2.);
  N_p1_p2 = PY( 1.,  2.);

  // ============================================================================================
  // xBRZ: the reference decisions (only the line tests use DistShape and toneLine, rule 9)
  // ============================================================================================
  ivec4 blendResult = ivec4(pts);

  vec4 res = vec4(blendResult);

  float dEB = distY(B, E);
  float dED = distY(D, E);
  float dEF = distY(E, F);
  float dEH = distY(E, H);
  vec4 pair = vec4(distY(B, D), distY(B, F), distY(F, H), distY(D, H));

  if (blendResult.z >= BLEND_NORMAL) res.z += xbrzCorner(blendResult.z, blendResult.y, blendResult.w, min(dEF, dEH), pair.z, B, C, D, E, F, G, H, I, N_m1_p2, N_p2_m1);
  if (blendResult.w >= BLEND_NORMAL) res.w += xbrzCorner(blendResult.w, blendResult.z, blendResult.x, min(dEH, dED), pair.w, F, I, B, E, H, A, D, G, N_m2_m1, N_p1_p2);
  if (blendResult.x >= BLEND_NORMAL) res.x += xbrzCorner(blendResult.x, blendResult.w, blendResult.y, min(dED, dEB), pair.x, H, G, F, E, D, C, B, A, N_p1_m2, N_m2_p1);
  if (blendResult.y >= BLEND_NORMAL) res.y += xbrzCorner(blendResult.y, blendResult.x, blendResult.z, min(dEB, dEF), pair.y, D, A, H, E, B, I, F, C, N_p2_p1, N_m1_m2);

  vec4 second = vec4(dED <= dEB + TIE_EPS ? 0.0 : 1.0, dEB <= dEF + TIE_EPS ? 0.0 : 1.0, dEF <= dEH + TIE_EPS ? 0.0 : 1.0, dEH <= dED + TIE_EPS ? 0.0 : 1.0);
  res += 8.0 * second;

  // ============================================================================================
  // the rules, in order
  // ============================================================================================
  vec4 xbrz = res;
  vec4 contrast, weak;
  res = minimumContrast(res, dEB, dED, dEF, dEH, contrast, weak);              // 1
  vec4 band30 = diagonalBands(xbrz, coord, A, B, C, D, E, F, G, H, I);          // 30
  vec4 ring30 = vec4(0.0);
  vec4 low30 = vec4(greaterThan(BLEND(xbrz), vec4(0.0))) * vec4(lessThan(contrast, vec4(XBRZ_MINC)));
  if (XBRZ_MINC > 0.0 && dot(low30, vec4(1.0)) > 0.0)
    ring30 = low30 * max(vec4(ringBand(B, D, A, E), ringBand(B, F, C, E), ringBand(F, H, I, E), ringBand(H, D, G, E)),
                         vec4(ringOutBand(E, C, G, I, B, D), ringOutBand(E, A, I, G, B, F), ringOutBand(E, C, G, A, F, H), ringOutBand(E, A, I, C, H, D)));
  vec4 rescue30 = max(band30, ring30);
  res = mix(res, xbrz, rescue30);
  weak *= 1.0 - rescue30;
  res = largerWindowLines(res, coord, A, B, C, D, E, F, G, H, I, dEB, dED, dEF, dEH, xbrz, contrast, weak);  // 11
  res = diagonalRules(res, coord, A, B, C, D, E, F, G, H, I, pair, dEB, dED, dEF, dEH);  // 2 to 7
  res = weakCorners(res, weak);                                                 // 1, weak corners
  res = lineThroughAA(res, xbrz, contrast, B, D, F, H, pair, dEB, dED, dEF, dEH);  // 8
  res = closedPixel(res, A, B, C, D, E, F, G, H, I);                            // 10
  res = tilesBetweenWalls(res, coord, E);                                       // 13
  res = lineInOtherColor(res, A, B, C, D, E, F, G, H, I, pair, dEB, dED, dEF, dEH);  // 16, 18
  if (CRISP_RULES && dot(vec4(greaterThan(BLEND(res), vec4(0.0))), vec4(1.0)) > 0.0)  // 32 to 35
  {
    Win w = Win(A, B, C, D, E, F, G, H, I, N_m1_m2, N_p0_m2, N_p1_m2, N_m2_m1, N_p2_m1, N_m2_p0, N_p2_p0, N_m2_p1, N_p2_p1, N_m1_p2, N_p0_p2, N_p1_p2,
                vec4(dEB, dEF, dEH, dED), pair);
    vec4 r33 = res;
    if (BLEND(res.z) > 0.0) { r33.z = holeInStroke(w, res.z); res.z = smallSquare(w, r33.z + lonePixelRedone(w, r33, blendResult)); }
    w = turn(w);
    if (BLEND(res.w) > 0.0) { r33.w = holeInStroke(w, res.w); res.w = smallSquare(w, r33.w + lonePixelRedone(w, r33.yzwx, blendResult.yzwx)); }
    w = turn(w);
    if (BLEND(res.x) > 0.0) { r33.x = holeInStroke(w, res.x); res.x = smallSquare(w, r33.x + lonePixelRedone(w, r33.zwxy, blendResult.zwxy)); }
    w = turn(w);
    if (BLEND(res.y) > 0.0) { r33.y = holeInStroke(w, res.y); res.y = smallSquare(w, r33.y + lonePixelRedone(w, r33.wxyz, blendResult.wxyz)); }
  }
  res = mix(res, xbrz, band30);                                                 // 30, the band wins over the rules above
  FRAG_OUT = res / 255.0;
}

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
// rules 3, 9, 12 and 13 belong to the crisp look rather than fixing clear xBRZ errors, so they
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
#define XBRZ_SHADOW 0.10       // 12. a shadow is darker than this (luma)
#define XBRZ_SHADOW_NEAR 0.08  // 12. close to a shadow color: darker than XBRZ_SHADOW plus this
#define XBRZ_SHADOW_BG 0.07    // 12. close to the background: lighter than XBRZ_SHADOW plus this
#define XBRZ_SHADOW_FLOOR 0.15 // 12. the floor and the object are lighter than the shadow by more than this (luma)
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

// the ring of pixels two steps from E (the 5x5 window without its corners), read once in main
vec3 N_m1_m2, N_p0_m2, N_p1_m2, N_m2_m1, N_p2_m1, N_m2_p0, N_p2_p0, N_m2_p1, N_p2_p1, N_m1_p2, N_p0_p2, N_p1_p2;

@include "color.inc"

bool alike(vec3 a, vec3 b) { return dist255(a, b) <= XBRZ_ALIKE; }

// The distance is symmetric, and below the two pixels of each distance (and of alike and IsPixEqual) are
// written in one fixed order (A to I, then the ring of pixels two steps away), so the compiler computes
// each distance only once. The pixels two steps away are read once, at the start of main.
bool IsPixEqual(vec3 pixA, vec3 pixB)
{
  return (distYCbCr(pixA, pixB) < EQUAL_COLOR_TOLERANCE);
}

// 15. Lone pixel and L-shape tests on strong edges: the tolerance of xBRZ's lone pixel test and L-shape
// test in the blend decisions; edge is how much E differs from the closer corner color, and edgeLimit
// how much that must be (XBRZ_GUARD_EDGE or XBRZ_GUARD_EDGE_L) for the reference tolerance to apply
bool equalOnEdge(vec3 pixA, vec3 pixB, float edge, float edgeLimit)
{
  return distYCbCr(pixA, pixB) < (XBRZ_MINC > 0.0 && edge * 255.0 >= edgeLimit ? XBRZ_GUARD / 255.0 : EQUAL_COLOR_TOLERANCE);
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
// the thresholds
float DistShape(vec3 pixA, vec3 pixB)
{
  const vec2 k = vec2(0.937, 1.125);
  vec3 diff = pixA - pixB;
  float y = dot(diff, LUMA_W);
  float Y = k.x * y;
  float Cb = k.y * SCALE_B * (diff.b - y);
  float Cr = k.y * SCALE_R * (diff.r - y);
  return sqrt((Y * Y) + (Cb * Cb) + (Cr * Cr));
}

// a line xBRZ finds that the hue-weighted test does not is kept too, except where it would bring
// back a corner blocked by the diagonal limit (rule 2), or where the line's color runs on along a
// 45-degree diagonal in the same color while the line test pairs it with a different one (alt45)
bool plainLine(vec3 a, vec3 b, vec3 c, vec3 d, float pairD, bool alt45)
{
  return STEEP_E * distYCbCr(a, b) <= distYCbCr(c, d) && pairD * 255.0 <= XBRZ_DIAG && !alt45;
}

// a shallow or steep line found only because hue weighs more (DistShape) between two different
// colors is flagged +32, so the resolve pass can drop it where it runs into the neighbour's line
float toneLine(vec3 a, vec3 b, vec3 c, vec3 d)
{
  return float(!IsPixEqual(a, b) && STEEP_E * distYCbCr(a, b) > distYCbCr(c, d));
}

// a line found only because hue weighs more (+32) is dropped where the pixel at its far end is closer
// to E than to the line's color: that pixel belongs to E's side, so the line would cut into E's run.
// It is also dropped where its two colors clearly differ (more than XBRZ_FAR_TONE) and the line's color runs on
// along a 45-degree diagonal in the same color (alt45, as for plainLine): the line would bend that
// diagonal toward another stroke (the tip of Goku's nose in Buu's Fury)
bool farTone(vec3 a, vec3 b, vec3 c, vec3 d, vec3 E, bool alt45)
{
  return !(toneLine(a, b, c, d) > 0.5 && (distYCbCr(E, b) < distYCbCr(a, b) || (alt45 && dist255(a, b) > XBRZ_FAR_TONE)));
}

// the shallow (x) and steep (y) line tests of a corner, a line along a-b against one along c-d, as
// the flags they add (+16 and +64, and +32 for a line found only because hue weighs more): xBRZ's own
// test (STEEP_E * d(a, b) <= d(c, d)) without the crisp rules, the hue-weighted one with them
vec2 lineTests(vec3 a, vec3 b, vec3 c, vec3 d, vec3 E, float pairD, bool alt45s, bool alt45t)
{
  if (!CRISP_RULES)
  {
    float ab = distYCbCr(a, b), cd = distYCbCr(c, d);
    return vec2(STEEP_E * ab <= cd ? 16.0 : 0.0, STEEP_E * cd <= ab ? 64.0 : 0.0);
  }
  float sab = DistShape(a, b), scd = DistShape(c, d);
  float shallow = (((STEEP_E * sab <= scd) && farTone(a, b, c, d, E, alt45s)) || plainLine(a, b, c, d, pairD, alt45s)) ? 16.0 + 32.0 * toneLine(a, b, c, d) : 0.0;
  float steep = (((STEEP_E * scd <= sab) && farTone(c, d, a, b, E, alt45t)) || plainLine(c, d, a, b, pairD, alt45t)) ? 64.0 + 32.0 * toneLine(c, d, a, b) : 0.0;
  return vec2(shallow, steep);
}

// ============================================================================================
// 30. Diagonal bands
// ============================================================================================
float bandSide(vec2 coord, vec2 o, vec2 p, vec2 q, vec3 e, vec3 cp, vec3 cq, vec3 cpq)
{
  if (!eq(cp, cq)) return 0.0;
  vec2 t = p - q;
  if (eq(cp, cpq))
  {
    bool a = eq(e, P(o.x + t.x, o.y + t.y)), b = eq(e, P(o.x - t.x, o.y - t.y));
    if (!a && !b) return 0.0;
    vec3 opp = P(o.x - p.x - q.x, o.y - p.y - q.y);
    float d = distYCbCr(opp, cp);
    if (d <= distYCbCr(opp, e) || d * 255.0 < XBRZ_BAND_FAR) return 0.0;
    if (d * 255.0 >= XBRZ_BAND_FAR2 || (a && b)) return 1.0;
    return (a ? eq(e, P(o.x + 2.0 * t.x, o.y + 2.0 * t.y)) : eq(e, P(o.x - 2.0 * t.x, o.y - 2.0 * t.y))) ? 1.0 : 0.0;
  }
  float dAE = distYCbCr(cpq, e);
  if (dAE <= distYCbCr(cpq, cp) || dAE * 255.0 < XBRZ_BAND_FAR) return 0.0;
  if (!eq(cpq, P(o.x + 2.0 * p.x, o.y + 2.0 * p.y)) && !eq(cpq, P(o.x + 2.0 * q.x, o.y + 2.0 * q.y))) return 0.0;
  if (!eq(e, P(o.x + t.x, o.y + t.y)) && !eq(e, P(o.x - t.x, o.y - t.y))) return 0.0;
  if (dAE * 255.0 >= XBRZ_BAND_FAR2) return 1.0;
  return (eq(cp, P(o.x + p.x + t.x, o.y + p.y + t.y)) || eq(cp, P(o.x + q.x - t.x, o.y + q.y - t.y))) ? 1.0 : 0.0;
}

// 32 to 34: two close shades (under 30 apart)
bool near(vec3 a, vec3 b) { return dist255(a, b) < 30.0; }

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
      vec3 cq  = vh ? (first ? cH : cV) : (first ? cVH : E);
      vec3 cpq = vh ? (first ? cVH : E) : (first ? cH : cV);
      f = bandSide(coord, o, p, q, e, cp, cq, cpq);
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
  float lP = luma(Pc);
  return float(dist255(Pc, X) >= XBRZ_RING && dist255(E, X) >= XBRZ_RING && lP < luma(E) && lP < luma(X) && !alike(E, X));
}
float ringOutBand(vec3 E, vec3 K1, vec3 K2, vec3 X, vec3 N1, vec3 N2)
{
  if (!alike(E, K1) || !alike(E, K2)) return 0.0;
  float lE = luma(E);
  return float(dist255(E, X) >= XBRZ_RING && min(dist255(N1, X), dist255(N2, X)) >= XBRZ_RING && lE < luma(X) && lE < luma(N1) && lE < luma(N2));
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
    weak = vec4(greaterThanEqual(contrast, vec4(XBRZ_MINC - XBRZ_HYST))) * vec4(lessThan(contrast, vec4(XBRZ_MINC)));
    res *= max(vec4(greaterThanEqual(contrast, vec4(XBRZ_MINC))), weak);
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
  vec3 T = P(o.x, o.y);
  return float(!alike(p, T) && !alike(q, T) && !alike(p, P(o.x + side.x, o.y + side.y)) && !alike(p, P(o.x - side.x, o.y - side.y)));
}

float wallAt(vec2 coord, vec2 t)
{
  vec3 T = P(t.x, t.y);
  bool l = alike(T, P(t.x - 1., t.y)), r = alike(T, P(t.x + 1., t.y)), u = alike(T, P(t.x, t.y - 1.)), d = alike(T, P(t.x, t.y + 1.));
  return float((l && (r || alike(T, P(t.x - 2., t.y)))) || (r && alike(T, P(t.x + 2., t.y))) ||
               (u && (d || alike(T, P(t.x, t.y - 2.)))) || (d && alike(T, P(t.x, t.y + 2.))));
}

float runWall(vec3 E, vec2 coord, vec2 d)
{
  float k = !alike(E, P(d.x, d.y)) ? 1.0 : !alike(E, P(2. * d.x, 2. * d.y)) ? 2.0 : !alike(E, P(3. * d.x, 3. * d.y)) ? 3.0 : 0.0;
  return k > 0.0 ? wallAt(coord, k * d) : 1.0;
}

// ============================================================================================
// helper for rule 7
// ============================================================================================
bool stripeEnd(vec2 coord, vec2 o1, vec2 o2, vec2 o3, bool thin, vec3 E, vec3 A, vec3 B, vec3 C, vec3 D, vec3 F, vec3 G, vec3 H, vec3 I,
               vec3 l2, vec3 r2, vec3 rt, vec3 rb)
{
  if (!(thin && alike(E, F) && !eq(E, D) && !eq(B, A) && !eq(H, G) && alike(B, C) && alike(H, I)))
    return false;
  if (alike(A, E) && alike(E, P(o1.x, o1.y)) && !alike(D, E) && !alike(B, E))
    return false;
  if (alike(E, G) && alike(E, P(o2.x, o2.y)) && !alike(D, E) && !alike(E, H))
    return false;
  if ((alike(A, E) && alike(B, D)) || (alike(E, G) && alike(D, H)))
    return false;
  return alike(E, r2) && (alike(E, P(o3.x, o3.y)) || !eq(D, l2)) && alike(C, rt) && alike(I, rb);
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
  float lE = luma(E);
  vec4 lP = vec4(luma(Px), luma(Py), luma(Pz), luma(Pw));
  vec4 lQ = vec4(luma(Qx), luma(Qy), luma(Qz), luma(Qw));
  vec4 notLighter = vec4(lessThanEqual(lP, vec4(lE + XBRZ_NOT_LIGHTER / 255.0)));
  vec4 straight = vec4(float(sec.x > 0.5 ? alike(B, C) : alike(D, G)), float(sec.y > 0.5 ? alike(F, I) : alike(A, B)),
                       float(sec.z > 0.5 ? alike(G, H) : alike(C, F)), float(sec.w > 0.5 ? alike(A, D) : alike(H, I)));
  vec3 Rx = sec.x > 0.5 ? N_p0_m2 : N_m2_p0, Ry = sec.y > 0.5 ? N_p2_p0 : N_p0_m2;
  vec3 Rz = sec.z > 0.5 ? N_p0_p2 : N_p2_p0, Rw = sec.w > 0.5 ? N_m2_p0 : N_p0_p2;
  vec3 Sx = sec.x > 0.5 ? C : G, Sy = sec.y > 0.5 ? I : A, Sz = sec.z > 0.5 ? G : C, Sw = sec.w > 0.5 ? A : I;
  vec3 Ux = sec.x > 0.5 ? N_p1_m2 : N_m2_p1, Uy = sec.y > 0.5 ? N_p2_p1 : N_m1_m2;
  vec3 Uz = sec.z > 0.5 ? N_m1_p2 : N_p2_m1, Uw = sec.w > 0.5 ? N_m2_m1 : N_p1_p2;

  // ---- 2. Diagonal limit ----
  vec4 ramp = min((dEP + pair) / max(dEQ, vec4(1e-5)), (dEQ + pair) / max(dEP, vec4(1e-5)));
  vec4 limit = mix(vec4(XBRZ_DIAG), vec4(XBRZ_DIAG_AA), vec4(lessThanEqual(ramp, vec4(XBRZ_RAMP))));
  vec4 keep = max(vec4(lessThanEqual(pair * 255.0, limit)), vec4(greaterThanEqual(res, vec4(16.0))) * notLighter);
  vec4 tipLine;
  tipLine.x = sec.x > 0.5 ? float(alike(C, E) && min(distYCbCr(B, N_p0_m2), distYCbCr(B, N_p1_m2)) * 255.0 <= XBRZ_STRIPE)
                          : float(alike(E, G) && min(distYCbCr(D, N_m2_p0), distYCbCr(D, N_m2_p1)) * 255.0 <= XBRZ_STRIPE);
  tipLine.y = sec.y > 0.5 ? float(alike(E, I) && min(distYCbCr(F, N_p2_p0), distYCbCr(F, N_p2_p1)) * 255.0 <= XBRZ_STRIPE)
                          : float(alike(A, E) && min(distYCbCr(B, N_p0_m2), distYCbCr(B, N_m1_m2)) * 255.0 <= XBRZ_STRIPE);
  tipLine.z = sec.z > 0.5 ? float(alike(E, G) && min(distYCbCr(H, N_p0_p2), distYCbCr(H, N_m1_p2)) * 255.0 <= XBRZ_STRIPE)
                          : float(alike(C, E) && min(distYCbCr(F, N_p2_p0), distYCbCr(F, N_p2_m1)) * 255.0 <= XBRZ_STRIPE);
  tipLine.w = sec.w > 0.5 ? float(alike(A, E) && min(distYCbCr(D, N_m2_p0), distYCbCr(D, N_m2_m1)) * 255.0 <= XBRZ_STRIPE)
                          : float(alike(E, I) && min(distYCbCr(H, N_p0_p2), distYCbCr(H, N_p1_p2)) * 255.0 <= XBRZ_STRIPE);
  keep = max(keep, tipLine);
  vec4 wide = vec4(float(alike(E, sec.x > 0.5 ? F : H)), float(alike(E, sec.y > 0.5 ? H : D)),
                   float(alike(E, sec.z > 0.5 ? D : B)), float(alike(E, sec.w > 0.5 ? B : F)));
  vec4 block = wide * vec4(float(alike(E, sec.x > 0.5 ? H : F) && alike(E, I)), float(alike(E, sec.y > 0.5 ? D : H) && alike(E, G)),
                           float(alike(E, sec.z > 0.5 ? B : D) && alike(A, E)), float(alike(E, sec.w > 0.5 ? F : B) && alike(C, E)));
  vec4 lR = vec4(luma(Rx), luma(Ry), luma(Rz), luma(Rw));
  vec4 lU = vec4(luma(Ux), luma(Uy), luma(Uz), luma(Uw));
  vec4 dEPc = mix(dEP, dEQ, sec);
  vec4 inner = vec4(lessThanEqual(dEPc * 255.0, vec4(XBRZ_DIAG))) * vec4(lessThan(lQ, min(lP, vec4(lE)) - XBRZ_OUTLINE))
             * notLighter * (1.0 - straight) * wide * (1.0 - block);
  vec4 bevel = vec4(float(alike(E, Sx)), float(alike(E, Sy)), float(alike(E, Sz)), float(alike(E, Sw)))
             * vec4(lessThan(max(lR, lU), min(lP, vec4(lE)) - XBRZ_OUTLINE));
  inner *= 1.0 - bevel;
  keep = max(keep, inner);
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
      float stripeCG = float(min(distYCbCr(C, E), distYCbCr(E, G)) * 255.0 <= XBRZ_STRIPE);
      float stripeAI = float(min(distYCbCr(A, E), distYCbCr(E, I)) * 255.0 <= XBRZ_STRIPE);
      eye *= 1.0 - vec4(stripeCG, stripeAI, stripeCG, stripeAI);
      if (dot(eye, vec4(1.0)) > 0.0)
      {
        eye *= vec4(sec.x > 0.5 ? strokeEnds(Px, Qx, coord, vec2(2.,-1.), vec2(0.,1.)) : strokeEnds(Px, Qx, coord, vec2(-1.,2.), vec2(1.,0.)),
                    sec.y > 0.5 ? strokeEnds(Py, Qy, coord, vec2(1.,2.), vec2(1.,0.)) : strokeEnds(Py, Qy, coord, vec2(-2.,-1.), vec2(0.,1.)),
                    sec.z > 0.5 ? strokeEnds(Pz, Qz, coord, vec2(-2.,1.), vec2(0.,1.)) : strokeEnds(Pz, Qz, coord, vec2(1.,-2.), vec2(1.,0.)),
                    sec.w > 0.5 ? strokeEnds(Pw, Qw, coord, vec2(-1.,-2.), vec2(1.,0.)) : strokeEnds(Pw, Qw, coord, vec2(2.,1.), vec2(0.,1.)));
        res *= 1.0 - eye;
      }
    }
  }

  // ---- 4. Diagonal up to the wall ----
  vec4 kept = vec4(0.0), loneP = vec4(0.0), loneQ = vec4(0.0);
  if (any(notEqual(res, before)))
  {
    vec4 lone = vec4(float(!alike(A, B) && !alike(B, C) && !alike(B, N_p0_m2)), float(!alike(A, D) && !alike(D, G) && !alike(D, N_m2_p0)),
                     float(!alike(C, F) && !alike(F, I) && !alike(F, N_p2_p0)), float(!alike(G, H) && !alike(H, I) && !alike(H, N_p0_p2)));
    loneP = mix(lone.yxzw, lone.xzwy, sec);
    loneQ = mix(lone.xzwy, lone.yxzw, sec);
    vec4 diagE = vec4(float(alike(C, E) || alike(E, G)), float(alike(A, E) || alike(E, I)),
                      float(alike(C, E) || alike(E, G)), float(alike(A, E) || alike(E, I))) * cut;
    if (dot(diagE, vec4(1.0)) > 0.0)
    {
      vec4 partner = vec4(
        float((alike(C, E) && !alike(B, C) && !alike(C, N_p1_m2)) || (alike(E, G) && !alike(G, N_m2_p1) && !alike(D, G))),
        float((alike(A, E) && !alike(A, N_m1_m2) && !alike(A, B)) || (alike(E, I) && !alike(F, I) && !alike(I, N_p2_p1))),
        float((alike(C, E) && !alike(C, N_p2_m1) && !alike(C, F)) || (alike(E, G) && !alike(G, H) && !alike(G, N_m1_p2))),
        float((alike(A, E) && !alike(A, D) && !alike(A, N_m2_m1)) || (alike(E, I) && !alike(I, N_p1_p2) && !alike(H, I))));
      float l3CG = float((alike(C, E) && alike(E, P(2., -2.))) || (alike(E, G) && alike(E, P(-2., 2.))));
      float l3AI = float((alike(A, E) && alike(E, P(-2., -2.))) || (alike(E, I) && alike(E, P(2., 2.))));
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
               * (1.0 - endLine * straight * (1.0 - bendQ)) * (1.0 - straight * (1.0 - straightQ0) * (1.0 - qRun)) * cut;
      run *= 1.0 - loneP * loneQ;
      if (dot(run, vec4(1.0)) > 0.0)
      {
        float wCG = run.x + run.z > 0.0 ? max(runWall(E, coord, vec2(1., -1.)), runWall(E, coord, vec2(-1., 1.))) : 0.0;
        float wAI = run.y + run.w > 0.0 ? max(runWall(E, coord, vec2(1., 1.)), runWall(E, coord, vec2(-1., -1.))) : 0.0;
        run *= vec4(wCG, wAI, wCG, wAI);
      }
      res = mix(res, before, run);
      kept = run;
    }
  }

  // ---- 5. Thin light stroke ----
  float eA = 0.0, eC = 0.0, eG = 0.0, eI = 0.0;
  bool haveDiagDist = false;
  vec4 back = vec4(greaterThan(vec4(lE) - max(lP, lQ), vec4(XBRZ_THIN_LIGHT))) * cut * vec4(notEqual(res, before)) * (1.0 - loneP * loneQ);
  if (dot(back, vec4(1.0)) > 0.0)
  {
    vec4 dPQmin = min(mix(dEP, dEQ, sec), mix(dEQ, dEP, sec));
    eC = distYCbCr(C, E); eG = distYCbCr(E, G); eA = distYCbCr(A, E); eI = distYCbCr(E, I);
    haveDiagDist = true;
    vec4 tE = XBRZ_TONE * dPQmin;
    bvec4 aD = bvec4(alike(C, E), alike(E, G), alike(A, E), alike(E, I));
    bvec4 nD = bvec4(aD.x || eC < tE.x, aD.y || eG < tE.x, aD.z || eA < tE.y, aD.w || eI < tE.y);
    bvec4 nD2 = bvec4(aD.x || eC < tE.z, aD.y || eG < tE.z, aD.z || eA < tE.w, aD.w || eI < tE.w);
    vec4 sideA = vec4(float(aD.x && !(dEF < tE.x)) + float(aD.y && !(dEH < tE.x)), float(aD.z && !(dED < tE.y)) + float(aD.w && !(dEH < tE.y)),
                      float(aD.x && !(dEB < tE.z)) + float(aD.y && !(dED < tE.z)), float(aD.z && !(dEB < tE.w)) + float(aD.w && !(dEF < tE.w)));
    vec4 sideN = vec4(float(nD.x && !(dEF < tE.x)) + float(nD.y && !(dEH < tE.x)), float(nD.z && !(dED < tE.y)) + float(nD.w && !(dEH < tE.y)),
                      float(nD2.x && !(dEB < tE.z)) + float(nD2.y && !(dED < tE.z)), float(nD2.z && !(dEB < tE.w)) + float(nD2.w && !(dEF < tE.w)));
    sideA = min(sideA, vec4(1.0)); sideN = min(sideN, vec4(1.0));
    vec4 farOff = vec4(float(!alike(E, I)), float(!alike(E, G)), float(!alike(A, E)), float(!alike(C, E)));
    vec4 along = sideA * farOff;
    along = max(along, sideA * vec4(lessThan(max(lP, lQ), vec4(XBRZ_THIN_DARK))));
    along = max(along, sideN * farOff);
    back *= along;
    res = mix(res, before, back);
    kept = max(kept, back);
  }

  // ---- 6. Antialiasing notch ----
  if (any(notEqual(res, before)))
  {
    vec4 dPc = mix(dEP, dEQ, sec), dQc = mix(dEQ, dEP, sec);
    vec4 notch = vec4(lessThanEqual((dPc + pair) / max(dQc, vec4(1e-5)), vec4(XBRZ_RAMP))) * vec4(lessThanEqual(pair * 255.0, vec4(XBRZ_DIAG + XBRZ_NOTCH)))
               * loneP * cut * vec4(notEqual(res, before));
    if (dot(notch, vec4(1.0)) > 0.0)
    {
      vec4 wrap = vec4(lessThan(vec4(distYCbCr(A, Qx), distYCbCr(C, Qy), distYCbCr(I, Qz), distYCbCr(G, Qw)), XBRZ_TONE * pair));
      if (!haveDiagDist)
      {
        eC = distYCbCr(C, E); eG = distYCbCr(E, G); eA = distYCbCr(A, E); eI = distYCbCr(E, I);
      }
      vec4 onC = vec4(lessThan(vec4(eC), XBRZ_TONE * min(vec4(distYCbCr(Px, C), distYCbCr(Py, C), distYCbCr(Pz, C), distYCbCr(Pw, C)),
                                                   vec4(distYCbCr(Qx, C), distYCbCr(Qy, C), distYCbCr(Qz, C), distYCbCr(Qw, C)))));
      vec4 onG = vec4(lessThan(vec4(eG), XBRZ_TONE * min(vec4(distYCbCr(Px, G), distYCbCr(Py, G), distYCbCr(Pz, G), distYCbCr(Pw, G)),
                                                   vec4(distYCbCr(Qx, G), distYCbCr(Qy, G), distYCbCr(Qz, G), distYCbCr(Qw, G)))));
      vec4 onA = vec4(lessThan(vec4(eA), XBRZ_TONE * min(vec4(distYCbCr(Px, A), distYCbCr(Py, A), distYCbCr(Pz, A), distYCbCr(Pw, A)),
                                                   vec4(distYCbCr(Qx, A), distYCbCr(Qy, A), distYCbCr(Qz, A), distYCbCr(Qw, A)))));
      vec4 onI = vec4(lessThan(vec4(eI), XBRZ_TONE * min(vec4(distYCbCr(Px, I), distYCbCr(Py, I), distYCbCr(Pz, I), distYCbCr(Pw, I)),
                                                   vec4(distYCbCr(Qx, I), distYCbCr(Qy, I), distYCbCr(Qz, I), distYCbCr(Qw, I)))));
      vec4 along = vec4(max(onC.x, onG.x), max(onA.y, onI.y), max(onC.z, onG.z), max(onA.w, onI.w));
      notch *= wrap * along;
      res = mix(res, before, notch);
      kept = max(kept, notch);
    }
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
float thirdColor(vec3 s, vec3 p, vec3 E)
{
  float dsp = distYCbCr(s, p), dsE = distYCbCr(s, E), dpE = distYCbCr(p, E);
  return float(min(dsp, dsE) * 255.0 >= XBRZ_MINC && dpE + dsp > XBRZ_AA_OFF * dsE && dpE + dsE > XBRZ_AA_OFF * dsp);
}
vec4 lineThroughAA(vec4 res, vec4 xbrz, vec4 contrast, vec3 B, vec3 D, vec3 E, vec3 F, vec3 H)
{
  if (XBRZ_MINC <= 0.0)
    return res;
  vec4 cut = vec4(greaterThan(BLEND(res), vec4(0.0))) * vec4(lessThan(BLEND(res), vec4(3.0))) * FLAG(res, 4.0);
  vec4 sq = vec4(lessThan(contrast, vec4(XBRZ_MINC))) * vec4(greaterThan(BLEND(xbrz), vec4(0.0))) * FLAG(xbrz, 4.0)
          * vec4(notEqual(BLEND(res), vec4(1.0))) * vec4(notEqual(BLEND(res), vec4(2.0)));
  vec4 pair = sq * cut.zwxy;
  if (dot(pair, vec4(1.0)) <= 0.0)
    return res;
  vec4 sc = FLAG(xbrz, 8.0);
  vec3 Cx = sc.x > 0.5 ? B : D, Cy = sc.y > 0.5 ? F : B, Cz = sc.z > 0.5 ? H : F, Cw = sc.w > 0.5 ? D : H;
  float dXZ = distYCbCr(Cx, Cz), dYW = distYCbCr(Cy, Cw);
  vec4 st8 = FLAG(xbrz, 64.0), sh8 = FLAG(xbrz, 16.0);
  vec4 third8 = st8 * vec4(thirdColor(D, Cx, E), thirdColor(B, Cy, E), thirdColor(F, Cz, E), thirdColor(H, Cw, E))
              + sh8 * vec4(thirdColor(B, Cx, E), thirdColor(F, Cy, E), thirdColor(H, Cz, E), thirdColor(D, Cw, E));
  pair *= 1.0 - min(third8, vec4(1.0));
  float bxz = float(distYCbCr(Cx, E) + distYCbCr(E, Cz) <= XBRZ_AA_LINE * dXZ && dXZ * 255.0 >= XBRZ_AA_EDGE);
  float byw = float(distYCbCr(Cy, E) + distYCbCr(E, Cw) <= XBRZ_AA_LINE * dYW && dYW * 255.0 >= XBRZ_AA_EDGE);
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
  vec4 lQ = vec4(luma(A), luma(C), luma(I), luma(G));
  vec4 lP = vec4(luma(Px), luma(Py), luma(Pz), luma(Pw));
  vec4 dark = vec4(lessThan(lQ + XBRZ_BLACK_GAP, lP)) * vec4(lessThan(lQ + XBRZ_BLACK_GAP, vec4(luma(E)))) * vec4(lessThan(lQ, vec4(XBRZ_BLACK)));
  vec4 closed = dark * line;
  if (dot(closed, vec4(1.0)) <= 0.0)
    return res;
  bool sx = sc.x > 0.5 ? (alike(A, C) && alike(A, D) && !alike(A, B) && !alike(A, E)) : (alike(A, G) && alike(A, B) && !alike(A, D) && !alike(A, E));
  bool sy = sc.y > 0.5 ? (alike(C, I) && alike(B, C) && !alike(C, F) && !alike(C, E)) : (alike(A, C) && alike(C, F) && !alike(B, C) && !alike(C, E));
  bool sz = sc.z > 0.5 ? (alike(G, I) && alike(F, I) && !alike(H, I) && !alike(E, I)) : (alike(C, I) && alike(H, I) && !alike(F, I) && !alike(E, I));
  bool sw = sc.w > 0.5 ? (alike(A, G) && alike(G, H) && !alike(D, G) && !alike(E, G)) : (alike(G, I) && alike(D, G) && !alike(G, H) && !alike(E, G));
  closed *= vec4(sx, sy, sz, sw);
  return res * (1.0 - closed);
}

// ============================================================================================
// 11. Lines in a larger window
// ============================================================================================
float onTone(vec3 X, vec3 a, vec3 b)
{
  float da = distYCbCr(X, a);
  return float(da < distYCbCr(X, b) && da * 255.0 <= XBRZ_ALIKE);
}
float strongPx(vec3 X, vec3 a, vec3 b)
{
  return (1.0 - onTone(X, a, b)) * (1.0 - onTone(X, b, a)) * float(dist255(X, a) >= XBRZ_STRONG);
}
#define RP(o) P((rot * (o)).x, (rot * (o)).y)

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
  float eNarrow = eStrong * strongPx(Fa, E, Pc) * strongPx(Fb, E, Pc);
  float pNarrow = pStrong * strongPx(O1, Pc, E) * (1.0 - onTone(RP(o2), Pc, E)) * (1.0 - onTone(RP(o3), Pc, E));
  return max(eNarrow, pNarrow);
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
    float eStrong = float(min(distYCbCr(Fa, E), distYCbCr(Fb, E)) * 255.0 >= XBRZ_STRONG);
    float pStrong = float(dist255(O1, Pc) >= XBRZ_STRONG);
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
// 12. Closed shadow
// ============================================================================================
bool floorPx(vec3 X, vec3 S, vec3 O, float lS)
{
  return luma(X) > lS + XBRZ_SHADOW_FLOOR && !alike(X, S) && !alike(X, O);
}

float shadowClose(vec2 coord, vec3 E, vec2 s, vec2 o)
{
  vec3 S = P(s.x, s.y);
  vec3 O = P(o.x, o.y);
  vec2 k = o - s;
  vec3 K = P(k.x, k.y);
  float lS = luma(S);
  if (!(lS < XBRZ_SHADOW && luma(K) < XBRZ_SHADOW && luma(E) > XBRZ_SHADOW + XBRZ_SHADOW_FLOOR && alike(S, K) && !alike(O, S) && !alike(O, E) && !alike(E, S)
        && lS + XBRZ_SHADOW_FLOOR < luma(E) && lS + XBRZ_SHADOW_FLOOR < luma(O)))
    return 0.0;
  bool bg = floorPx(P(-s.x, -s.y), S, O, lS) && floorPx(P(-o.x, -o.y), S, O, lS);
  bool arm = alike(S, P(2. * s.x, 2. * s.y)) && alike(S, P(3. * s.x, 3. * s.y))
          && floorPx(P(s.x - o.x, s.y - o.y), S, O, lS) && floorPx(P(2. * s.x - o.x, 2. * s.y - o.y), S, O, lS)
          && !alike(S, P(s.x + o.x, s.y + o.y));
  bool lobe = alike(S, P(k.x + o.x, k.y + o.y)) && alike(S, P(k.x + o.x - s.x, k.y + o.y - s.y))
           && alike(S, P(k.x + 2. * o.x, k.y + 2. * o.y)) && alike(S, P(k.x + 2. * o.x - s.x, k.y + 2. * o.y - s.y));
  vec3 O2 = P(2. * o.x, 2. * o.y);
  bool obj = !alike(E, O2) && !alike(S, O2);
  return float(bg && arm && lobe && obj);
}

vec4 closedShadow(vec4 res, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  if (!CRISP_RULES)
    return res;
  float lE = luma(E);
  vec4 lX = vec4(luma(B), luma(D), luma(F), luma(H));
  vec4 lY = vec4(luma(A), luma(C), luma(G), luma(I));
  bvec4 dS = lessThan(lX, vec4(XBRZ_SHADOW)), dSd = lessThan(lY, vec4(XBRZ_SHADOW));
  bvec4 dA = lessThan(lX, vec4(XBRZ_SHADOW + XBRZ_SHADOW_NEAR)), dAd = lessThan(lY, vec4(XBRZ_SHADOW + XBRZ_SHADOW_NEAR));
  bvec4 nd = not(dS), ndd = not(dSd);
  bvec4 bg = greaterThan(lX, vec4(XBRZ_SHADOW + XBRZ_SHADOW_BG)), bgd = greaterThan(lY, vec4(XBRZ_SHADOW + XBRZ_SHADOW_BG));
  bvec4 lt = greaterThan(lX, vec4(XBRZ_SHADOW + XBRZ_SHADOW_FLOOR)), ltd = greaterThan(lY, vec4(XBRZ_SHADOW + XBRZ_SHADOW_FLOOR));
  if (lE > XBRZ_SHADOW + XBRZ_SHADOW_FLOOR && any(dS))
  {
    vec4 g1 = vec4(dS.y && dSd.y && nd.x && bg.z && bg.w && bgd.z, dS.x && dSd.w && nd.z && bg.w && bg.y && bgd.x,
                   dS.z && dSd.z && nd.w && bg.y && bg.x && bgd.y, dS.w && dSd.x && nd.y && bg.x && bg.z && bgd.w);
    vec4 g2 = vec4(dS.x && dSd.z && nd.y && bg.w && bg.z && bgd.y, dS.z && dSd.x && nd.x && bg.y && bg.w && bgd.w,
                   dS.w && dSd.y && nd.z && bg.x && bg.y && bgd.z, dS.y && dSd.w && nd.w && bg.z && bg.x && bgd.x);
    vec4 c1 = vec4(0.0), c2 = vec4(0.0);
    vec2 d = vec2(-1., 0.);
    for (int i = 0; i < 8; i++)
    {
      int k = i / 2;
      bool second = i - 2 * k == 1;
      vec2 n = vec2(-d.y, d.x);
      vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
      if (dot(second ? g2 : g1, m) > 0.0)
      {
        float r = shadowClose(coord, E, second ? n : d, second ? d : n);
        if (second) c2 += m * r; else c1 += m * r;
      }
      if (second) d = n;
    }
    c2 *= 1.0 - c1;
    res = mix(res, vec4(1. + 4. + 16.), c1);
    res = mix(res, vec4(1. + 4. + 8. + 64.), c2);
  }
  else if (lE < XBRZ_SHADOW && (any(lt) || any(ltd)))
  {
    vec4 gT1 = vec4(lt.y && bg.w && bgd.w && dA.z && ndd.x, lt.x && bg.y && bgd.z && dA.w && ndd.y,
                    lt.z && bg.x && bgd.x && dA.y && ndd.w, lt.w && bg.z && bgd.y && dA.x && ndd.z);
    vec4 gT2 = vec4(lt.x && bg.z && bgd.w && dA.w && ndd.x, lt.z && bg.w && bgd.z && dA.y && ndd.y,
                    lt.w && bg.y && bgd.x && dA.x && ndd.w, lt.y && bg.x && bgd.y && dA.z && ndd.z);
    vec4 gK1 = vec4(ltd.x && nd.y && bg.x && dA.w && dAd.w, ltd.y && nd.x && bg.z && dA.y && dAd.z,
                    ltd.w && nd.z && bg.w && dA.x && dAd.x, ltd.z && nd.w && bg.y && dA.z && dAd.y);
    vec4 gK2 = vec4(ltd.x && nd.x && bg.y && dA.z && dAd.w, ltd.y && nd.z && bg.x && dA.w && dAd.z,
                    ltd.w && nd.w && bg.z && dA.y && dAd.x, ltd.z && nd.y && bg.w && dA.x && dAd.y);
    vec4 keepSq = vec4(0.0);
    vec2 d = vec2(-1., 0.);
    for (int i = 0; i < 16; i++)
    {
      int k = i / 4;
      int t = i - 4 * k;
      vec2 n = vec2(-d.y, d.x);
      vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
      vec4 g = t == 0 ? gT1 : (t == 1 ? gT2 : (t == 2 ? gK1 : gK2));
      if (dot(g, m) > 0.0)
      {
        vec2 y = t == 0 ? d : (t == 1 ? n : d + n);
        vec2 s = t == 0 ? -d : (t == 1 ? -n : (t == 2 ? d : n));
        vec2 o = t == 0 ? n : (t == 1 ? d : (t == 2 ? -n : -d));
        keepSq = max(keepSq, m * shadowClose(coord + SRC_SIZE.zw * y, P(y.x, y.y), s, o));
      }
      if (t == 3) d = n;
    }
    res *= 1.0 - min(keepSq, vec4(1.0));
  }
  return res;
}

// ============================================================================================
// 13. Tiles between walls
// ============================================================================================
float tileStripe(vec2 coord, vec3 E, vec2 a, vec2 w)
{
  vec3 P1 = P(a.x, a.y), Q = P(w.x, w.y), Q2 = P(w.x + a.x, w.y + a.y), O = P(-w.x, -w.y), O2 = P(a.x - w.x, a.y - w.y);
  vec3 T0 = P(-a.x, -a.y);
  float lE = luma(E), lP = luma(P1), lQ = luma(Q), lO = luma(O);
  bool light = min(lE, lP) > max(lQ, lO) + XBRZ_OUTLINE, dark = max(lE, lP) + XBRZ_OUTLINE < min(lQ, lO);
  if (!((light || dark) && alike(Q, Q2) && alike(O, O2) && !alike(E, T0) && !alike(T0, Q) && !alike(T0, O)))
    return 0.0;
  vec3 T3 = P(2. * a.x, 2. * a.y);
  bool wallQ = alike(Q, P(w.x - a.x, w.y - a.y)) || alike(Q, P(w.x + 2. * a.x, w.y + 2. * a.y));
  bool wallO = alike(O, P(-w.x - a.x, -w.y - a.y)) || alike(O, P(2. * a.x - w.x, 2. * a.y - w.y));
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
  bool lone = !(eq(A, E) || eq(B, E) || eq(C, E) || eq(D, E) || eq(E, F) || eq(E, G) || eq(E, H) || eq(E, I));
  vec4 r = res;
  vec4 sh = FLAG(r, 16.0), st = FLAG(r, 64.0), sec = FLAG(r, 8.0);
  vec4 tint = vec4(greaterThan(BLEND(r), vec4(0.0))) * FLAG(r, 4.0) *
              abs(sh - st) * (sh * sec + st * (1.0 - sec)) * vec4(greaterThan(pair * 255.0, vec4(XBRZ_TINT)));
  if (dot(tint, vec4(1.0)) <= 0.0)
    return res;
  vec4 pSh = vec4(distYCbCr(C, D), distYCbCr(B, I), distYCbCr(F, G), distYCbCr(A, H));
  vec4 pSt = vec4(distYCbCr(B, G), distYCbCr(A, F), distYCbCr(C, H), distYCbCr(D, I));
  tint *= vec4(lessThan(sh * pSh + st * pSt, vec4(EQUAL_COLOR_TOLERANCE)));
  vec4 dE1 = vec4(dED, dEB, dEF, dEH);
  vec4 dE2 = vec4(dEB, dEF, dEH, dED);
  vec4 dP = mix(dE1, dE2, sec), dL = mix(dE2, dE1, sec);
  tint *= vec4(greaterThan(dP + pair, XBRZ_TINT_RAMP * dL));
  bool straight = IsPixEqual(D, F) || IsPixEqual(B, H);
  vec3 pX = st.x > 0.5 ? D : B, pY = st.y > 0.5 ? B : F, pZ = st.z > 0.5 ? F : H, pW = st.w > 0.5 ? H : D;
  vec4 eOn = vec4(min(distYCbCr(E, st.x > 0.5 ? N_m1_p2 : N_p2_m1), distYCbCr(E, st.x > 0.5 ? N_p1_m2 : N_m2_p1)),
                  min(distYCbCr(E, st.y > 0.5 ? N_m2_m1 : N_p1_p2), distYCbCr(E, st.y > 0.5 ? N_p2_p1 : N_m1_m2)),
                  min(distYCbCr(E, st.z > 0.5 ? N_p1_m2 : N_m2_p1), distYCbCr(E, st.z > 0.5 ? N_m1_p2 : N_p2_m1)),
                  min(distYCbCr(E, st.w > 0.5 ? N_p2_p1 : N_m1_m2), distYCbCr(E, st.w > 0.5 ? N_m2_m1 : N_p1_p2)));
  vec4 pOn = vec4(distYCbCr(pX, st.x > 0.5 ? N_p0_m2 : N_m2_p0), distYCbCr(pY, st.y > 0.5 ? N_p2_p0 : N_p0_m2),
                  distYCbCr(pZ, st.z > 0.5 ? N_p0_p2 : N_p2_p0), distYCbCr(pW, st.w > 0.5 ? N_m2_p0 : N_p0_p2));
  vec4 stripes = vec4(lessThan(eOn, vec4(EQUAL_COLOR_TOLERANCE))) * vec4(lessThan(pOn, vec4(EQUAL_COLOR_TOLERANCE))) * (straight ? 0.0 : 1.0);
  tint *= max(vec4(lessThan(r, vec4(128.0))), stripes);
  vec4 tint0 = tint;
  vec4 lumC1 = vec4(luma(D), luma(B), luma(F), luma(H));
  vec4 lumC2 = lumC1.yzwx;
  vec4 lumLine = mix(lumC1, lumC2, st);
  vec4 dark = vec4(lessThan(lumLine, vec4(luma(E)))) * (straight ? 0.0 : 1.0);
  if (!lone)
  {
    dark *= vec4(lessThan(lumLine, vec4(XBRZ_TINT_DARK)));
    dark *= vec4(greaterThanEqual(mix(lumC2, lumC1, st), vec4(XBRZ_TINT_DARK)));
    tint *= dark;
  }
  dark = max(dark, stripes);
  tint = max(tint, tint0 * stripes);
  vec4 flip = st - sec;
  vec4 shape = lone ? 16.0 * sh + 64.0 * st + 32.0 * FLAG(r, 32.0) : vec4(0.0);
  res -= tint * dark * (shape - 8.0 * flip);
  res *= 1.0 - tint * (1.0 - dark);
  res -= 128.0 * vec4(greaterThanEqual(r, vec4(128.0))) * tint * dark;
  return res;
}

// ============================================================================================
// The corners of E, written once in one frame
// ============================================================================================
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

vec2 cornerLines(Win n, int own)
{
  if (own < BLEND_NORMAL)
    return vec2(0.0);
  return lineTests(n.F, n.G, n.H, n.C, n.E, n.pair.z, eq(n.m1_p2, n.H) && !eq(n.G, n.H), eq(n.p2_m1, n.F) && !eq(n.C, n.F));
}

float cutFlags(Win n, vec2 line)
{
  float r = 4.0;
  if (neq(n.E, n.G) && neq(n.D, n.G)) r += line.x;
  if (neq(n.E, n.C) && neq(n.B, n.C)) r += line.y;
  return r;
}

float xbrzCorner(Win n, ivec4 b, vec2 line)
{
  return cornerCut(b.z, b.y, b.w, min(n.dE.y, n.dE.z), n.E, n.G, n.H, n.I, n.F, n.C) ? cutFlags(n, line) : 0.0;
}

float noLine(float r) { return mod(r, 4.0) + 8.0 * mod(floor(r / 8.0), 2.0); }

// 33. Hole in a thick stroke
float holeInStroke(Win n, float r)
{
  float ln = mod(floor(r / 4.0), 2.0) * mod(floor(r / 16.0), 2.0) * step(64.0, r);
  float dEB = n.dE.x, dEF = n.dE.y, dED = n.dE.w;
  if (ln > 0.5 && min(dEF, n.dE.z) * 255.0 >= 64.0 && eq(n.F,n.H) && eq(n.F,n.C) && eq(n.H,n.G) && neq(n.I,n.E) && neq(n.I,n.F)
      && (dEB * 255.0 < 30.0) && (dED * 255.0 < 30.0) && distYCbCr(n.I,n.F) < dEF && distYCbCr(n.I,n.E) < dEF
      && neq(n.I, n.p2_p1) && neq(n.I, n.p1_p2) && neq(n.F, n.p2_p1) && neq(n.F, n.p1_p2) && (eq(n.F, n.p2_p0) || eq(n.H, n.p0_p2)))
    return noLine(r);
  return r;
}

// 32 & 35. Lone pixel test redone and edge of a thin band
float lonePixelRedone(Win n, vec4 r, ivec4 b, vec2 line)
{
  vec4 bl = mod(r, 4.0);
  float ln = mod(floor(r.z / 4.0), 2.0);
  float c4 = min(n.dE.y, n.dE.z) * 255.0;
  float dEB = n.dE.x, dED = n.dE.w;
  if ((bl.z > 0.0 && ln < 0.5 && !((eq(n.E,n.D) && !eq(n.E,n.m2_p0)) || (eq(n.E,n.B) && !eq(n.E,n.p0_m2))) && bl.y == 0.0 && bl.w == 0.0
       && c4 >= 64.0 && b.z == BLEND_NORMAL && eq(n.F,n.H) && eq(n.F,n.C) && eq(n.H,n.G) && neq(n.F, n.p2_p0) && neq(n.H, n.p0_p2)
       && cornerCut(b.z, BLEND_NONE, BLEND_NONE, min(n.dE.y, n.dE.z), n.E, n.G, n.H, n.I, n.F, n.C))
      || (bl.z == 1.0 && ln < 0.5 && c4 >= 40.0 && c4 < XBRZ_GUARD_EDGE && eq(n.F,n.H) && dist255(n.I,n.F) >= 40.0
       && ((eq(n.G,n.H) && eq(n.F,n.p2_p0) && (dED * 255.0 < 30.0) && near(n.E,n.C) && dist255(n.p0_p2,n.H) >= 40.0)
        || (eq(n.C,n.F) && eq(n.H,n.p0_p2) && (dEB * 255.0 < 30.0) && near(n.E,n.G) && dist255(n.p2_p0,n.F) >= 40.0))
       && cornerCut(b.z, b.y, b.w, 1.0, n.E, n.G, n.H, n.I, n.F, n.C)))
    return cutFlags(n, line);
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

  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;

  // Read B, D and E as vec4 so their alpha (the point pass's decisions) is reused below without re-fetching
  vec4 tB = P4( 0.,-1.);
  vec4 tD = P4(-1., 0.);
  vec4 tE = P4( 0., 0.);
  vec3 B = tB.rgb, D = tD.rgb, E = tE.rgb;
  vec3 F = P( 1., 0.);
  vec3 H = P( 0., 1.);

  // fast path: xBRZ blends a corner only where E differs from both pixels beside it, so where E equals
  // opposite side neighbours (D and F, or B and H) nothing is cut and contrast is 0 at all four corners
  bool eqDF = eq(E, D) && eq(E, F);
  bool eqBH = eq(E, B) && eq(E, H);
  if (eqDF || eqBH)
  {
    if (XBRZ_MINC > XBRZ_HYST)
    {
      FRAG_OUT = vec4(0.0);
      return;
    }
    float fEB = eqBH ? 0.0 : distYCbCr(B, E);
    float fED = eqDF ? 0.0 : distYCbCr(D, E);
    float fEF = eqDF ? 0.0 : distYCbCr(E, F);
    float fEH = eqBH ? 0.0 : distYCbCr(E, H);
    vec4 fres = 8.0 * vec4(fED <= fEB + TIE_EPS ? 0.0 : 1.0, fEB <= fEF + TIE_EPS ? 0.0 : 1.0, fEF <= fEH + TIE_EPS ? 0.0 : 1.0, fEH <= fED + TIE_EPS ? 0.0 : 1.0);
    vec4 fcontrast, fweak;
    fres = minimumContrast(fres, fEB, fED, fEF, fEH, fcontrast, fweak);
    FRAG_OUT = fres / 255.0;
    return;
  }

  vec4 tA = P4(-1.,-1.);
  vec3 A = tA.rgb;
  vec3 C = P( 1.,-1.);
  vec3 G = P(-1., 1.);
  vec3 I = P( 1., 1.);
  N_m1_m2 = P(-1., -2.);
  N_p0_m2 = P(0., -2.);
  N_p1_m2 = P(1., -2.);
  N_m2_m1 = P(-2., -1.);
  N_p2_m1 = P(2., -1.);
  N_m2_p0 = P(-2., 0.);
  N_p2_p0 = P(2., 0.);
  N_m2_p1 = P(-2., 1.);
  N_p2_p1 = P(2., 1.);
  N_m1_p2 = P(-1., 2.);
  N_p0_p2 = P(0., 2.);
  N_p1_p2 = P(1., 2.);

  // ============================================================================================
  // xBRZ: the reference decisions (only the line tests use DistShape and toneLine, rule 9)
  // ============================================================================================
  float ptA = floor(tA.a * 255.0 + 0.5), ptB = floor(tB.a * 255.0 + 0.5);
  float ptE = floor(tE.a * 255.0 + 0.5), ptD = floor(tD.a * 255.0 + 0.5);
  vec4 pts = vec4(floor(ptA / 64.0), mod(floor(ptB / 16.0), 4.0), mod(ptE, 4.0), mod(floor(ptD / 4.0), 4.0));
  vec2 ip = floor(coord * SRC_SIZE.xy);
  pts *= vec4(min(ip.x, ip.y) > 0.5, ip.y > 0.5, 1.0, ip.x > 0.5);
  ivec4 blendResult = ivec4(pts);

  vec4 res = vec4(blendResult);

  float dEB = distYCbCr(B, E);
  float dED = distYCbCr(D, E);
  float dEF = distYCbCr(E, F);
  float dEH = distYCbCr(E, H);
  vec4 pair = vec4(distYCbCr(B, D), distYCbCr(B, F), distYCbCr(F, H), distYCbCr(D, H));

  Win wz = Win(A, B, C, D, E, F, G, H, I, N_m1_m2, N_p0_m2, N_p1_m2, N_m2_m1, N_p2_m1, N_m2_p0, N_p2_p0, N_m2_p1, N_p2_p1, N_m1_p2, N_p0_p2, N_p1_p2,
               vec4(dEB, dEF, dEH, dED), pair);
  Win ww = turn(wz);
  Win wx = turn(ww);
  Win wy = turn(wx);

  vec2 lineZ = cornerLines(wz, blendResult.z);
  vec2 lineW = cornerLines(ww, blendResult.w);
  vec2 lineX = cornerLines(wx, blendResult.x);
  vec2 lineY = cornerLines(wy, blendResult.y);
  res.z += xbrzCorner(wz, blendResult, lineZ);
  res.w += xbrzCorner(ww, blendResult.yzwx, lineW);
  res.x += xbrzCorner(wx, blendResult.zwxy, lineX);
  res.y += xbrzCorner(wy, blendResult.wxyz, lineY);

  vec4 second = vec4(dED <= dEB + TIE_EPS ? 0.0 : 1.0, dEB <= dEF + TIE_EPS ? 0.0 : 1.0, dEF <= dEH + TIE_EPS ? 0.0 : 1.0, dEH <= dED + TIE_EPS ? 0.0 : 1.0);
  res += 8.0 * second;

  // ============================================================================================
  // the rules, in order
  // ============================================================================================
  vec4 xbrz = res;
  vec4 contrast, weak;
  res = minimumContrast(res, dEB, dED, dEF, dEH, contrast, weak);              // 1
  vec4 band = diagonalBands(xbrz, coord, A, B, C, D, E, F, G, H, I);            // 30
  vec4 low30 = vec4(greaterThan(BLEND(xbrz), vec4(0.0))) * vec4(lessThan(contrast, vec4(XBRZ_MINC)));
  if (XBRZ_MINC > 0.0 && dot(low30, vec4(1.0)) > 0.0)
    band = max(band, low30 * max(vec4(ringBand(B, D, A, E), ringBand(B, F, C, E), ringBand(F, H, I, E), ringBand(H, D, G, E)),
                                 vec4(ringOutBand(E, C, G, I, B, D), ringOutBand(E, A, I, G, B, F), ringOutBand(E, C, G, A, F, H), ringOutBand(E, A, I, C, H, D))));
  res = mix(res, xbrz, band);
  weak *= 1.0 - band;
  res = largerWindowLines(res, coord, A, B, C, D, E, F, G, H, I, dEB, dED, dEF, dEH, xbrz, contrast, weak);  // 11
  res = diagonalRules(res, coord, A, B, C, D, E, F, G, H, I, pair, dEB, dED, dEF, dEH);  // 2 to 7
  res = weakCorners(res, weak);                                                 // 1, weak corners
  res = lineThroughAA(res, xbrz, contrast, B, D, E, F, H);                      // 8
  res = closedPixel(res, A, B, C, D, E, F, G, H, I);                            // 10
  res = closedShadow(res, coord, A, B, C, D, E, F, G, H, I);                    // 12
  res = tilesBetweenWalls(res, coord, E);                                       // 13
  res = lineInOtherColor(res, A, B, C, D, E, F, G, H, I, pair, dEB, dED, dEF, dEH);  // 16, 18
  if (CRISP_RULES)                                                              // 32 to 35
  {
    res.z = holeInStroke(wz, res.z);                                            // 33
    res.w = holeInStroke(ww, res.w);
    res.x = holeInStroke(wx, res.x);
    res.y = holeInStroke(wy, res.y);
    vec4 r33 = res;                                                             // 32, 35
    res.z += lonePixelRedone(wz, r33, blendResult, lineZ);
    res.w += lonePixelRedone(ww, r33.yzwx, blendResult.yzwx, lineW);
    res.x += lonePixelRedone(wx, r33.zwxy, blendResult.zwxy, lineX);
    res.y += lonePixelRedone(wy, r33.wxyz, blendResult.wxyz, lineY);
    res.z = smallSquare(wz, res.z);                                             // 34
    res.w = smallSquare(ww, res.w);
    res.x = smallSquare(wx, res.x);
    res.y = smallSquare(wy, res.y);
  }
  res = mix(res, xbrz, band);                                                   // 30, the band wins over the rules above
  FRAG_OUT = res / 255.0;
}

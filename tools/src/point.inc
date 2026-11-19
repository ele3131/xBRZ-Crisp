//#crisp{
// xBRZ crisp, point pass (@BACKEND_LABEL@): xBRZ's decision at each point where 4 pixels meet, made once.
//#crisp}
//#plain // xBRZ freescale multipass, point pass (@BACKEND_LABEL@): xBRZ's decision at each point where 4 pixels meet, made once.
//
// xBRZ decides each point where 4 pixels meet once (its preprocessing) and the 4 pixels around the point
// use that decision. This pass does the same: each pixel decides the point at its bottom-right corner and
// writes the blend type of the 4 pixels there in the alpha channel, next to its own color, so pass 0 reads
// the decisions of the 4 points around a pixel with the colors it reads anyway.
//#crisp{
// The crisp rules that decide a point (31, 36 and 46) run here too.
//#crisp}
// Every later pass reads the image from this pass's color.
@include "license.inc"

@STAGE_POINT@

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

@include "color.inc"

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
// how many pixels of each diagonal's color there are in the 8x8 around the 2x2 (the rarer color wins);
// the inner 4x4 is already in registers so only the 48 outer pixels are fetched
vec2 tieSparse(vec2 coord, vec3 tl, vec3 tr, vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko,
               vec3 cTL, vec3 cTR, vec3 cBL, vec3 cBR)
{
  // inner 2x2 is a checker (kf == kk == tl, kg == kj == tr, tl != tr), contributing 2 of each
  vec2 n = vec2(2.0)
         + tieCnt(cTL, tl, tr) + tieCnt(kb, tl, tr) + tieCnt(kc, tl, tr) + tieCnt(cTR, tl, tr)
         + tieCnt(ke,  tl, tr) + tieCnt(kh, tl, tr) + tieCnt(ki, tl, tr) + tieCnt(kl,  tl, tr)
         + tieCnt(cBL, tl, tr) + tieCnt(kn, tl, tr) + tieCnt(ko, tl, tr) + tieCnt(cBR, tl, tr);
  for (int j = -3; j <= 4; j++)
  {
    if (j >= -1 && j <= 2)
    {
      n += tieCnt(PY(-3.0, float(j)), tl, tr) + tieCnt(PY(-2.0, float(j)), tl, tr)
         + tieCnt(PY( 3.0, float(j)), tl, tr) + tieCnt(PY( 4.0, float(j)), tl, tr);
    }
    else
    {
      for (int i = -3; i <= 4; i++)
        n += tieCnt(PY(float(i), float(j)), tl, tr);
    }
  }
  return n;
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
bool chkPair(vec3 a, vec3 b, vec3 c1, vec3 c2)
{
  return (eq(a, c1) && eq(b, c2)) || (eq(a, c2) && eq(b, c1));
}
// three or more of the four 2x2 blocks beside the 2x2 at (0, 0) are checkers of c1 and c2; each block already has
// two of its four pixels in registers kb..ko, and stops as soon as two blocks fail
bool checker46(vec2 coord, vec3 c1, vec3 c2, vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko)
{
  int miss = 0;
  if (!(chkPair(ke, ki, c1, c2) && eq(PY(-2.0, 0.0), ki) && eq(PY(-2.0, 1.0), ke))) miss++;
  if (!(chkPair(kh, kl, c1, c2) && eq(PY( 3.0, 0.0), kl) && eq(PY( 3.0, 1.0), kh))) { if (++miss > 1) return false; }
  if (!(chkPair(kb, kc, c1, c2) && eq(PY( 0.0,-2.0), kc) && eq(PY( 1.0,-2.0), kb))) { if (++miss > 1) return false; }
  if (!(chkPair(kn, ko, c1, c2) && eq(PY( 0.0, 3.0), ko) && eq(PY( 1.0, 3.0), kn))) { if (++miss > 1) return false; }
  return true;
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
          vec2 s = tieSparse(coord, kf, kg, kb, kc, ke, kh, ki, kl, kn, ko, cTL, cTR, cBL, cBR).yx + 0.25 * c0;
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
    // 46. a 2x2 checker of two colors inside a checker texture keeps its corners square
    if (isChecker && (r.x + r.y + r.z + r.w > 0) && checker46(coord, kf, kg, kb, kc, ke, kh, ki, kl, kn, ko))
      r = ivec4(BLEND_NONE);
  }
//#crisp}
  return r;
}

void main()
{
@POINT_COORDS@
  vec3 rgbF = P(0., 0.), rgbG = P(1., 0.), rgbJ = P(0., 1.), rgbK = P(1., 1.);
  ivec4 r = ivec4(BLEND_NONE);
  // where the 2x2 is two rows or two columns of one color nothing blends (and rules 31 and 36 need a
  // diagonal of one color), so the 4x4 is read only at the other points
  if (!((eq(rgbF, rgbG) && eq(rgbJ, rgbK)) || (eq(rgbF, rgbJ) && eq(rgbG, rgbK))))
    r = pointBlend(coord, PY(0., -1.), PY(1., -1.), PY(-1., 0.), toYCbCr(rgbF), toYCbCr(rgbG), PY(2., 0.),
                   PY(-1., 1.), toYCbCr(rgbJ), toYCbCr(rgbK), PY(2., 1.), PY(0., 2.), PY(1., 2.));
  FRAG_OUT = vec4(rgbF, float(r.x + 4 * r.y + 16 * r.z + 64 * r.w) / 255.0);
}

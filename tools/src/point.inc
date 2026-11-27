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
#define eq(a,b)  ((a) == (b))
#define neq(a,b) ((a) != (b))
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

@include "point_checker46.inc"
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
    // On a 3-color T-junction (one straight 2-pixel wall, so only one corner of the 2x2 is cut),
    // reject an upside-down vote where outer 4x4 weights let a worse diagonal (> XBRZ_DIAG and farther
    // than the rejected diagonal) win across a distinct off-ramp third color (all 3 pairs >= 64 apart).
    // Two-tone shaded slopes (e.g. light/dark green on a hill) and soft shadows stay untouched.
    bool oneJG = (r.x > 0) != (r.w > 0);
    bool oneFK = (r.y > 0) != (r.z > 0);
    if (oneJG && dJgSq > dFkSq && dJgSq > SQ255(XBRZ_DIAG) && dFkSq >= SQ255(64.0))
    {
      float dOSq = r.x > 0 ? (eqGK ? distSqY(kf, kj) : distSqY(kf, kg))
                           : (eqFG ? distSqY(kk, kj) : distSqY(kk, kg));
      if (dOSq >= SQ255(64.0) && sDiag.y + sqrt(dOSq) > 1.15 * sDiag.x) r = ivec4(BLEND_NONE);
    }
    else if (oneFK && dFkSq > dJgSq && dFkSq > SQ255(XBRZ_DIAG) && dJgSq >= SQ255(64.0))
    {
      float dOSq = r.y > 0 ? (eqFJ ? distSqY(kg, kk) : distSqY(kg, kf))
                           : (eqFG ? distSqY(kj, kk) : distSqY(kj, kf));
      if (dOSq >= SQ255(64.0) && sDiag.x + sqrt(dOSq) > 1.15 * sDiag.y) r = ivec4(BLEND_NONE);
    }
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
    // Protect a continuous dark outline diagonal (eqFK or eqGJ, Y < 0.15, darker than both light colors,
    // massOuter on both sides) from being cut by a non-dominant heterochromatic diagonal (>= 50 apart)
    // where at least one light color continues cardinally (not a shaded 1px diagonal stroke through bg).
    if (eqFK != eqGJ)
    {
      bool bgFK = eqFK;
      vec3 bg = bgFK ? kf : kg;
      float dWinSq = bgFK ? dJgSq : dFkSq;
      int winT = bgFK ? r.x : r.y;
      if (winT == BLEND_NORMAL && bg.x < XBRZ_X36_DARK && dWinSq >= SQ255(50.0))
      {
        vec3 st1 = bgFK ? kg : kf, st2 = bgFK ? kj : kk;
        float farSq = min(distSqY(bg, st1), distSqY(bg, st2));
        bool cardCont = bgFK
          ? (min(distSqY(kc, st1), distSqY(kh, st1)) < SQ255(30.0) || min(distSqY(ki, st2), distSqY(kn, st2)) < SQ255(30.0))
          : (min(distSqY(kb, st1), distSqY(ke, st1)) < SQ255(30.0) || min(distSqY(kl, st2), distSqY(ko, st2)) < SQ255(30.0));
        if (cardCont && farSq >= SQ255(64.0) && bg.x + 0.15 < min(st1.x, st2.x)
            && massOuter(coord, bgFK ? kb : kc, bgFK ? ke : kh, bgFK ? kc : kb, bgFK ? ki : kl, bgFK ? vec2(-1.0, -1.0) : vec2(2.0, -1.0), bg)
            && massOuter(coord, bgFK ? kl : ki, bgFK ? ko : kn, bgFK ? kh : ke, bgFK ? kn : ko, bgFK ? vec2(2.0, 2.0) : vec2(-1.0, 2.0), bg))
        {
          vec3 c1 = PY(bgFK ? 2.0 : -1.0, -1.0);
          vec3 c2 = PY(bgFK ? -1.0 : 2.0,  2.0);
          if ((distSqY(c1, bg) < SQ255(30.0) || distSqY(c2, bg) < SQ255(30.0))
              && distSqY(c1, st1) >= SQ255(30.0) && distSqY(c2, st2) >= SQ255(30.0))
            r = bgFK ? ivec4(BLEND_NONE, BLEND_NORMAL, BLEND_NORMAL, BLEND_NONE)
                     : ivec4(BLEND_NORMAL, BLEND_NONE, BLEND_NONE, BLEND_NORMAL);
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

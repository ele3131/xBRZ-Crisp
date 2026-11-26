@include "header_short.inc"
@include "license.inc"

// Matching pass of xbrz-crisp (@BACKEND_LABEL@): once per input pixel, between resolve and pass 1 (rules 26-28, 38-45, 47-49)
@STAGE_MATCH@

@include "bits.inc"
@include "color.inc"
@include "match_geom.inc"
@include "hold28.inc"

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

// ---- Rule 38: 4-color junction threshold ----
#define XBRZ_JUNC4 30.0

// E and its 4 cardinal neighbors in linear YCbCr, and E's squared YCbCr distances to them
vec3 nB, nD, nE, nF, nH;
float sBSq, sDSq, sFSq, sHSq;
float mincSq;

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
#define cardInfo(n) INFO_AT((n).x, (n).y)
#define diagInfo(c) INFO_AT((c).x, (c).y)
#define diagColor(c) toYCbCr(P((c).x, (c).y))

vec3 at3x3(vec2 o)
{
  float d1 = abs(o.x) + abs(o.y);
  if (d1 < 0.5) return nE;
  if (d1 < 1.5) return cardColor(o);
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

@include "match_strokes.inc"
@include "match_junctions.inc"
@include "match_r26.inc"
@include "match_r28.inc"

void main()
{
@MATCH_COORDS@
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


  float minSideSq = min(min(sBSq, sDSq), min(sFSq, sHSq));
  float maxSideSq = max(max(sBSq, sDSq), max(sFSq, sHSq));
  vec4 pairSq = vec4(distSqY(nB, nD), distSqY(nB, nF), distSqY(nF, nH), distSqY(nH, nD));
  vec4 maxCornerSq = max(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq));
  vec4 minCornerSq = min(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq));

  // ---- Rules 26, 28, 27: matching corners, post-resolve 2:1 fixes, and vertex bars ----
  res = applyRule26Lost(res, w0, aW0, pairSq, minCornerSq, maxCornerSq);
  res = applyRule26b(res, pairSq, minCornerSq, maxCornerSq, minSideSq);
  res = applyRule26d(res, pairSq, minCornerSq);
  res = applyRule28Match(res, pairSq);
  res = applyRule26ef(res, pairSq, minCornerSq);
  if (nE.x <= 0.30) res = applyRule26c(res, pairSq);
  res = applyRule27(res, pairSq, maxSideSq);

  // ---- Rules 42, 38-41: 45-deg edge steps, 4-color junctions, ramp ties, dots, diagonal strokes ----
  vec4 m42 = (1.0 - cut4(res))
           * vec4(greaterThanEqual(minCornerSq, vec4(mincSq)))
           * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))));
  if (dot(m42, vec4(1.0)) > 0.5) res = edgeStep42(res, m42);
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

  // ---- Rules 44, 47, 45, 48, 49, 41b/c, 38b, 42b: stroke ends, notches, slopes, bars, crosshairs ----
  if (nE.x <= 0.35 && maxSideSq >= SQ255(XBRZ_END44) && minSideSq < SQ255(XBRZ_SAME_M)) res = strokeEnd44(res);
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    if (maxSideSq >= SQ255(XBRZ_FAR47) && minSideSq < SQ255(XBRZ_NOTCH47)) res = applyRule47(res, pairSq, maxCornerSq);
    if (maxSideSq >= SQ255(80.0) && minSideSq < SQ255(XBRZ_SAME_M)) res = applyRule45(res, pairSq, minCornerSq, maxCornerSq);
    res = applyRule48(res, pairSq, minSideSq, maxSideSq, loneE);
  }
  res = applyRule49(res, res0, pairSq, minSideSq, maxSideSq);
  if (loneE && dot(cut4(res), vec4(1.0)) > 0.0) res = apex41(res, pairSq, minCornerSq);
  if (!loneE && min(max(sDSq, sFSq), max(sBSq, sHSq)) > SQ255(40.0) && dot(cut4(res), vec4(1.0)) > 0.0)
    res = applyRule38b(res, pairSq);
  if (!loneE && maxSideSq >= mincSq)
    res = applyRule42b(res, pairSq, minCornerSq);

  FRAG_OUT = res / 255.0;
}

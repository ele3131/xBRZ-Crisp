@include "header_short.inc"
@include "license.inc"

// Matching pass of xbrz-crisp (@BACKEND_LABEL@): once per input pixel, between resolve and pass 1 (rules 26, 28, 38-45, 48, 49)
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


  gHaveCardI = false; gHaveDiagI = false; gHaveDiagC = false;
  float minSideSq = min(min(sBSq, sDSq), min(sFSq, sHSq));
  float maxSideSq = max(max(sBSq, sDSq), max(sFSq, sHSq));
  vec4 pairSq = vec4(distSqY(nB, nD), distSqY(nB, nF), distSqY(nF, nH), distSqY(nH, nD));
  vec4 maxCornerSq = max(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq));
  vec4 minCornerSq = min(vec4(sBSq, sBSq, sFSq, sHSq), vec4(sDSq, sFSq, sHSq, sDSq));

  bool loneE = minSideSq >= SQ255(XBRZ_SAME_M);

  // ---- Phase 1: Rescues & Upgrades (26Lost+43+cont45 -> 26f) ----
  res = applyRule26Lost(res, w0, aW0, pairSq, minCornerSq, maxCornerSq);
  res = applyRule26f(res, pairSq, minCornerSq);

  // ---- Phase 2: Prunes & Color Flips (26b, 28Match, 26e, 26c, 38, 39, 40, 45, 48c) ----
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    res = applyRule26b(res, pairSq, minCornerSq, maxCornerSq, minSideSq);
    res = applyRule28Match(res, pairSq);
    res = applyRule26e(res, pairSq, minCornerSq);
    if (nE.x <= 0.30) res = applyRule26c(res, pairSq);
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
    if (dot(cut4(res), vec4(1.0)) > 0.0)
    {
      if (maxSideSq >= SQ255(80.0) && !loneE) res = applyRule45(res, pairSq, minCornerSq, maxCornerSq);
      res = applyRule48c(res, pairSq);
    }
  }

  // ---- Phase 3: Unified 2:1 Downgrades & Lone-Pixel Apex (41, 26d+48a+48b, 41b/c) ----
  if (dot(cut4(res), vec4(1.0)) > 0.0)
  {
    if (loneE || dot(cut4(res) * FLAG(res, BIT_LINE) * abs(FLAG(res, BIT_SHALLOW) - FLAG(res, BIT_STEEP))
        * vec4(equal(FLAG(res, BIT_LONG3) + FLAG(res, BIT_LONG4), vec4(0.0)))
        * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))))
        * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_SAME_M)))), vec4(1.0)) > 0.0)
      res = diagStroke41(res, loneE, pairSq);
    res = downgrade21Collision(res, pairSq, minCornerSq, minSideSq, maxSideSq, loneE);
    if (loneE) res = apex41(res, pairSq, minCornerSq);
  }

  // ---- Phase 4: Late Geometric Completions (44, 49, 42b) ----
  if (nE.x <= 0.35 && maxSideSq >= SQ255(XBRZ_END44) && !loneE) res = strokeEnd44(res);
  res = applyRule49(res, res0, pairSq, minSideSq, maxSideSq);
  if (!loneE && maxSideSq >= mincSq) res = applyRule42b(res, pairSq, minCornerSq);

  // ---- Phase 5: Precompute C1 curve tags (BIT_ARC45 & BIT_ARC21) once at 1x for zero-fetch pass1 ----
  vec4 c45 = cut4(res) * isLine45(res);
  if (dot(c45, vec4(1.0)) > 0.5)
  {
    ensureCardInfo();
    vec4 wX  = vec4(gID.z, gIB.w, gIF.x, gIH.y);
    vec4 wY  = vec4(gIB.z, gIF.w, gIH.x, gID.y);
    vec4 wXr = vec4(gID.y, gIB.z, gIF.w, gIH.x);
    vec4 wYr = vec4(gIB.w, gIF.x, gIH.y, gID.z);
    vec4 shX  = cut4(wX)  * FLAG(wX,  BIT_LINE) * FLAG(wX,  BIT_SHALLOW) * (1.0 - FLAG(wX,  BIT_STEEP));
    vec4 stY  = cut4(wY)  * FLAG(wY,  BIT_LINE) * FLAG(wY,  BIT_STEEP)   * (1.0 - FLAG(wY,  BIT_SHALLOW));
    vec4 stXr = cut4(wXr) * FLAG(wXr, BIT_LINE) * FLAG(wXr, BIT_STEEP)   * (1.0 - FLAG(wXr, BIT_SHALLOW));
    vec4 shYr = cut4(wYr) * FLAG(wYr, BIT_LINE) * FLAG(wYr, BIT_SHALLOW) * (1.0 - FLAG(wYr, BIT_STEEP));
    vec4 cont = cut4(wY) * isLine45(wY) + stY + cut4(wYr) * isLine45(wYr) + shYr
              + cut4(wX) * isLine45(wX) + shX + cut4(wXr) * isLine45(wXr) + stXr;
    res += BIT_ARC45 * c45 * vec4(lessThan(cont, vec4(0.5)));
  }
  vec4 is21Base = cut4(res) * FLAG(res, BIT_LINE) * (1.0 - FLAG(res, BIT_LONG3)) * (1.0 - FLAG(res, BIT_LONG4));
  vec4 c21Sh = is21Base * FLAG(res, BIT_SHALLOW) * (1.0 - FLAG(res, BIT_STEEP));
  vec4 c21St = is21Base * FLAG(res, BIT_STEEP)   * (1.0 - FLAG(res, BIT_SHALLOW));
  if (dot(c21Sh + c21St, vec4(1.0)) > 0.5)
  {
    ensureCardInfo();
    ensureDiagInfo();
    vec4 wX  = vec4(gID.z, gIB.w, gIF.x, gIH.y);
    vec4 wY  = vec4(gIB.z, gIF.w, gIH.x, gID.y);
    vec4 wXr = vec4(gID.y, gIB.z, gIF.w, gIH.x);
    vec4 wYr = vec4(gIB.w, gIF.x, gIH.y, gID.z);
    // Shallow 2:1: right end P1 meets 45-deg (wX) with no reversing cut (wXr);
    // left end P0 meets flat horizontal wall (no continuing shallow slope in wDiagSh, no cut on adj corner).
    vec4 wDiagSh = vec4(gIC.z, gII.w, gIG.x, gIA.y);
    vec4 shDiagCont = cut4(wDiagSh) * FLAG(wDiagSh, BIT_LINE) * FLAG(wDiagSh, BIT_SHALLOW) * (1.0 - FLAG(wDiagSh, BIT_STEEP));
    vec4 shRev = cut4(wXr) * FLAG(wXr, BIT_LINE);
    vec4 shOk = c21Sh * cut4(wX) * isLine45(wX) * (1.0 - shRev)
              * (1.0 - shDiagCont) * (1.0 - cut4(res.yzwx));
    // Steep 2:1: exact transpose
    vec4 wDiagSt = vec4(gIG.z, gIA.w, gIC.x, gII.y);
    vec4 stDiagCont = cut4(wDiagSt) * FLAG(wDiagSt, BIT_LINE) * FLAG(wDiagSt, BIT_STEEP) * (1.0 - FLAG(wDiagSt, BIT_SHALLOW));
    vec4 stRev = cut4(wYr) * FLAG(wYr, BIT_LINE);
    vec4 stOk = c21St * cut4(wY) * isLine45(wY) * (1.0 - stRev)
              * (1.0 - stDiagCont) * (1.0 - cut4(res.wxyz));
    res += BIT_ARC21 * (shOk + stOk);
  }

  FRAG_OUT = res / 255.0;
}

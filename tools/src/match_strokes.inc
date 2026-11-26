// ============================================================================================
// Match pass — 1-pixel strokes, domes, notches, slopes, and diagonal bars (Rules 41, 43-45, 47-49)
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

// ---- Rules 47 and 48: lone shades along a stroke ----
#define XBRZ_NOTCH47 60.0
#define XBRZ_FAR47 80.0
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

// 47. a notch in the straight side of a stroke in shades
vec4 applyRule47(vec4 res, vec4 pairSq, vec4 maxCornerSq)
{
  vec4 cutM = cut4(res) * vec4(lessThan(maxCornerSq, vec4(SQ255(XBRZ_NOTCH47))))
            * vec4(greaterThanEqual(maxCornerSq, vec4(SQ255(XBRZ_SAME_M))));
  if (dot(cutM, vec4(1.0)) <= 0.5) return res;
  vec4 secM = FLAG(res, BIT_SEC), sqM = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec2 c = cornerOff(k);
    vec4 m = vtxCorner(c);
    if (dot(cutM, m) < 0.5) continue;
    vec2 a, b;
    paintPairOffsets(k, c, dot(secM, m) > 0.5, a, b);
    float dBSq = sideSq(b), dASq = sideSq(a);
    if (dASq < SQ255(XBRZ_SAME_M) || dBSq >= 1.44 * dASq
        || sideSq(-a) < SQ255(XBRZ_FAR47) || adjPairMinSq(a, pairSq) < SQ255(XBRZ_SAME_M))
      continue;
    vec3 Ac = cardColor(a);
    if (!withinY255(nE, diagColor(a - b), XBRZ_SAME_M) || withinY255(Ac, diagColor(c), XBRZ_SAME_M)
        || BLEND(dot(cardInfo(b), vtxCorner(c - 2.0 * b))) > 0.5 || !withinY255(nE, at3(2.0 * b), XBRZ_SAME_M)
        || !isLone3x3Card(Ac, a))
      continue;
    sqM += m;
  }
  return res * (1.0 - min(sqM, vec4(1.0)));
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
      bool plug = dot(pairSq, me) < SQ255(XBRZ_SAME_M) && !withinY255(R1, C1, XBRZ_SAME_M) &&
                  !withinY255(R1, C2, XBRZ_SAME_M);
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

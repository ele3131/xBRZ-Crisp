// ============================================================================================
// Match pass — Vertex, 4-color junction, ramp, dot, and 45-degree edge rules (Rules 27, 38-40, 42)
// ============================================================================================

// ---- Rule 27: a bar at a vertex ----
bool vtxSame(vec3 a, vec3 b) { return withinEqY255(a, b, XBRZ_VERTEX_TOL); }
bool vtxAt(vec2 u, vec2 v)
{
  if (sideSq(-u) <= SQ255(XBRZ_VERTEX_EDGE)) return false;
  vec3 C = cardColor(-u), T = cardColor(-v);
  if (vtxSame(C, cardColor(u))) return false;
  return vtxSame(C, at3(u - v)) && !vtxSame(C, at3(-u - v))
      && vtxSame(C, toYCbCr(P(v.x - 2.0 * u.x, v.y - 2.0 * u.y))) && vtxSame(C, toYCbCr(P(2.0 * u.x, 2.0 * u.y)))
      && withinEqY255(T, toYCbCr(P(-2.0 * v.x, -2.0 * v.y)), XBRZ_VERTEX_BAR)
      && withinEqY255(T, toYCbCr(P(-3.0 * v.x, -3.0 * v.y)), XBRZ_VERTEX_BAR);
}
bool vtxBetween(vec3 g, vec3 t, vec3 c)
{
  vec3 tc = t - c;
  float k = dot(g - c, tc) / max(dot(tc, tc), SAFE_EPS);
  float yt = t.x, yc = c.x, kY = (g.x - yc) / (abs(yt - yc) > 1e-3 ? yt - yc : 1e-3);
  return k > 0.15 && k < 0.85 && withinY255(c + k * tc, g, 24.0) && abs(yt - yc) > 1e-3 && kY > 0.15 && kY < 0.85;
}
void vtx(vec2 u, vec2 v, vec4 pairSq, inout vec4 res)
{
  vec2 c = -u - v;
  vec4 m = vtxCorner(c);
  float w = dot(res, m);
  if (BLEND(w) < 0.5 || FLAG(w, BIT_LINE) < 0.5 || (FLAG(w, BIT_SEC) > 0.5) != vtxSec(c, -v)
      || dot(pairSq, m) <= SQ255(XBRZ_VERTEX_EDGE) || !vtxAt(u, v)) return;
  if (vtxBetween(nE, cardColor(-v), cardColor(-u)))
    res = mix(res, vec4(wordPlain(vtxSec(c, -v))), m);
  else
  {
    res = mix(res, vec4(0.0), m);
    vec2 c2 = u - v;
    vec4 m2 = vtxCorner(c2);
    if ((FLAG(dot(res, m2), BIT_SEC) > 0.5) == vtxSec(c2, -v)) res = mix(res, vec4(0.0), m2);
  }
}
vec4 applyRule27(vec4 res, vec4 pairSq, float maxSideSq)
{
  if (maxSideSq <= SQ255(XBRZ_VERTEX_EDGE)
      || dot(cut4(res) * FLAG(res, BIT_LINE) * vec4(greaterThan(pairSq, vec4(SQ255(XBRZ_VERTEX_EDGE)))), vec4(1.0)) <= 0.5)
    return res;
  for (int i = 0; i < 8; i++)
  {
    vec2 u = i == 0 || i == 2 ? vec2(1.0, 0.0) : i == 1 || i == 3 ? vec2(-1.0, 0.0) : i == 4 || i == 6 ? vec2(0.0, 1.0) : vec2(0.0, -1.0);
    vec2 v = i < 2 ? vec2(0.0, 1.0) : i < 4 ? vec2(0.0, -1.0) : i < 6 ? vec2(1.0, 0.0) : vec2(-1.0, 0.0);
    vtx(u, v, pairSq, res);
  }
  return res;
}

// ---- Rule 38 & 38b: a pixel kept whole at a junction of four colors ----
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
// 38b. 3+ color corner on a 1px bar flush against a 4-color orthogonal crosshair
vec4 applyRule38b(vec4 res, vec4 pairSq)
{
  vec4 sec38 = FLAG(res, BIT_SEC);
  vec4 hz38 = vec4(1.0 - sec38.x, sec38.y, 1.0 - sec38.z, sec38.w);
  vec4 m38b = cut4(res) * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))))
            * vec4(lessThan(mix(vec4(sHSq, sHSq, sBSq, sBSq), vec4(sFSq, sDSq, sDSq, sFSq), hz38), vec4(SQ255(XBRZ_SAME_M))))
            * vec4(greaterThan(mix(vec4(sBSq, sBSq, sHSq, sHSq), vec4(sDSq, sFSq, sFSq, sDSq), hz38), vec4(SQ255(40.0))))
            * vec4(greaterThan(mix(vec4(sFSq, sDSq, sDSq, sFSq), vec4(sHSq, sHSq, sBSq, sBSq), hz38), vec4(SQ255(40.0))))
            * vec4(greaterThan(mix(pairSq.yxwz, pairSq.wzyx, hz38), vec4(SQ255(40.0))));
  if (dot(m38b, vec4(1.0)) <= 0.5) return res;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = cornerOff(i);
    vec4 m = vtxCorner(c);
    if (dot(m38b, m) < 0.5) continue;
    vec2 h = dot(hz38, m) > 0.5 ? vec2(c.x, 0.0) : vec2(0.0, c.y), v = c - h;
    vec3 Hc = cardColor(h), Bc = cardColor(-v);
    vec3 Cc = diagColor(h - v);
    if (distSqY(Bc, Cc) <= SQ255(40.0) || distSqY(Hc, Cc) <= SQ255(XBRZ_JUNC4) || distSqY(nE, Cc) <= SQ255(40.0)) continue;
    if (!withinY255(Hc, at3(2.0 * h), XBRZ_SAME_M)) continue;
    if (!withinY255(Bc, diagColor(-v - h), XBRZ_SAME_M) || !withinY255(Bc, at3(-2.0 * v), XBRZ_SAME_M)) continue;
    if (!withinY255(Cc, at3(2.0 * h - v), XBRZ_SAME_M) || !withinY255(Cc, at3(h - 2.0 * v), XBRZ_SAME_M)) continue;
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

// ---- Rule 42 & 42b: a step in a 45-degree edge & convex corner bevel ----
vec2 paintOf(vec2 c, float w) { return ((c.x * c.y > 0.0) != (FLAG(w, BIT_SEC) > 0.5)) ? vec2(c.x, 0.0) : vec2(0.0, c.y); }
vec4 edgeStep42(vec4 res, vec4 m42)
{
  for (int i = 0; i < 4; i++)
  {
    vec2 c = cornerOff(i);
    vec4 m = vtxCorner(c);
    if (dot(m42, m) < 0.5) continue;
    vec3 Kh = c.x > 0.0 ? nF : nD, Kv = c.y > 0.0 ? nH : nB;
    vec3 K = 0.5 * (Kh + Kv);
    if (withinY255(K, c.x > 0.0 ? nD : nF, XBRZ_SAME_M) || withinY255(K, c.y > 0.0 ? nB : nH, XBRZ_SAME_M)) continue;
    if (!withinY255(K, diagColor(c), XBRZ_SAME_M)) continue;
    float ok = 1.0;
    for (int j = 0; j < 2; j++)
    {
      vec2 q = j == 0 ? vec2(c.x, -c.y) : vec2(-c.x, c.y);
      float wq = dot(diagInfo(q), m);
      if (BLEND(wq) < 0.5 || FLAG(wq, BIT_LINE) < 0.5 || FLAG(wq, BIT_SHALLOW) + FLAG(wq, BIT_STEEP) + FLAG(wq, BIT_LONG3) + FLAG(wq, BIT_LONG4) > 0.5)
      { ok = 0.0; break; }
      vec2 pOff = paintOf(c, wq);
      // When dot(q, pOff) < -0.5, q + pOff is Kh or Kv, whose distance to K = 0.5*(Kh+Kv) is 0.5*pair < 7.5 < XBRZ_SAME_M
      if (dot(q, pOff) > -0.5 && !withinY255(at3(q + pOff), K, XBRZ_SAME_M))
      { ok = 0.0; break; }
    }
    if (ok > 0.5)
      res = mix(res, vec4(wordLine45(pickCornerSec(c))), m);
  }
  return res;
}
// 42b. Convex corner bevel painting a shared darker background beside an adjacent brighter wall
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

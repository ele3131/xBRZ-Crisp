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

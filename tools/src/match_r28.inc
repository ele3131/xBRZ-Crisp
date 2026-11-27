// ============================================================================================
// Match pass — Rule 28 post-resolve completion & Rule 28b
// ============================================================================================
// - catch crossing 2:1 color swaps missed in resolve when one side was R2-blocked,
// - flip off-ramp 2:1 color when the neighbor across the shared edge draws the matching opposite 2:1 line in Q's color,
// - 28b: unflip a Rule-18 dark 2:1 line (painting O along N, d(E,N) < min(60, d(E,O)), pair >= 40) back to N
vec4 applyRule28Match(vec4 res, vec4 pairSq)
{
  vec4 sh28 = FLAG(res, BIT_SHALLOW), st28 = FLAG(res, BIT_STEEP), sec28 = FLAG(res, BIT_SEC);
  vec4 base28 = cut4(res) * FLAG(res, BIT_LINE) * (1.0 - FLAG(res, BIT_LONG3)) * (1.0 - FLAG(res, BIT_LONG4));
  vec4 p28 = base28 * mix(st28, sh28, sec28);
  if (dot(p28, vec4(1.0)) > 0.5)
  {
    ensureCardInfo();
    vec4 iB = gIB, iD = gID, iF = gIF, iH = gIH;
    vec4 nW = mix(vec4(iD.z, iB.w, iF.x, iH.y), vec4(iB.z, iF.w, iH.x, iD.y), sec28);
    vec4 pair28 = p28 * cut4(nW) * FLAG(nW, BIT_LINE) * (1.0 - FLAG(nW, BIT_LONG3)) * (1.0 - FLAG(nW, BIT_LONG4))
                * vec4(equal(FLAG(nW, BIT_SEC), sec28)) * mix(FLAG(nW, BIT_STEEP), FLAG(nW, BIT_SHALLOW), sec28);
    if (dot(pair28, vec4(1.0)) > 0.5)
    {
      vec3 nA = diagColor(vec2(-1.0, -1.0)), nC = diagColor(vec2(1.0, -1.0));
      vec3 nG = diagColor(vec2(-1.0,  1.0)), nI = diagColor(vec2(1.0,  1.0));
      res *= 1.0 - dropCross28(pair28, sec28, nE, nA, nB, nC, nD, nF, nG, nH, nI);
    }
    vec4 opp28 = p28 * abs(sh28 - st28)
               * cut4(nW) * FLAG(nW, BIT_LINE) * (1.0 - FLAG(nW, BIT_LONG3)) * (1.0 - FLAG(nW, BIT_LONG4))
               * abs(FLAG(nW, BIT_SHALLOW) - FLAG(nW, BIT_STEEP))
               * vec4(notEqual(FLAG(nW, BIT_SEC), sec28)) * mix(FLAG(nW, BIT_STEEP), FLAG(nW, BIT_SHALLOW), sec28)
               * vec4(greaterThanEqual(pairSq, vec4(mincSq)));
    if (dot(opp28, vec4(1.0)) > 0.5)
    {
      vec4 flip28 = vec4(0.0);
      for (int k = 0; k < 4; k++)
      {
        vec4 m = cornerMask(k);
        if (dot(opp28, m) < 0.5) continue;
        bool isSh = dot(sec28, m) > 0.5;
        vec2 nbrOff, othOff;
        slope21Offsets(k, isSh, nbrOff, othOff);
        vec2 extOff = nbrOff - othOff;
        if (withinY255(cardColor(othOff), diagColor(extOff), XBRZ_SAME_M)
            && triGt(sideSq(nbrOff), dot(pairSq, m), 1.2 * 1.2, sideSq(othOff)))
          flip28 += m * (isSh ? -BIT_SEC : BIT_SEC);
      }
      res += flip28;
    }
  }
  vec4 sh18 = FLAG(res, BIT_SHALLOW), st18 = FLAG(res, BIT_STEEP), sec18 = FLAG(res, BIT_SEC);
  vec4 dN18Sq = mix(vec4(sDSq, sBSq, sFSq, sHSq), vec4(sBSq, sFSq, sHSq, sDSq), sh18);
  vec4 dO18Sq = mix(vec4(sBSq, sFSq, sHSq, sDSq), vec4(sDSq, sBSq, sFSq, sHSq), sh18);
  vec4 u18 = cut4(res) * FLAG(res, BIT_LINE) * abs(sh18 - st18)
           * (1.0 - FLAG(res, BIT_LONG3)) * (1.0 - FLAG(res, BIT_LONG4))
           * mix(sh18, st18, sec18)
           * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
           * vec4(lessThan(dN18Sq, vec4(SQ255(60.0))))
           * vec4(lessThan(dN18Sq, dO18Sq - TIE_EPS));
  if (dot(u18, vec4(1.0)) > 0.5)
  {
    vec4 unflip = vec4(0.0);
    for (int k = 0; k < 4; k++)
    {
      vec4 m = cornerMask(k);
      if (dot(u18, m) < 0.5) continue;
      bool isSh = dot(sh18, m) > 0.5;
      vec2 nbrOff, othOff;
      slope21Offsets(k, isSh, nbrOff, othOff);
      if (BLEND(dot(cardInfo(nbrOff), m.zwxy)) > 0.5) continue;
      vec2 extOff = nbrOff - othOff;
      if (!withinY255(cardColor(othOff), diagColor(extOff), XBRZ_SAME_M)) continue;
      float xw = dot(diagInfo(extOff), vtxCorner(-extOff));
      if (BLEND(xw) > 0.5 && FLAG(xw, BIT_LINE) > 0.5)
        unflip += m * (isSh ? BIT_SEC : -BIT_SEC);
    }
    res += unflip;
  }
  return res;
}

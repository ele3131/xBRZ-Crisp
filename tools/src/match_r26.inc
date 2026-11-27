// ============================================================================================
// Match pass — Rule 26 family (matching corners, junction pruning, 2:1 downgrade/upgrade, dark walls)
// ============================================================================================

// Rule 26 (lost cut rescue + gap fill + Rule 43 dome + clean 45-deg continuation)
vec4 applyRule26Lost(vec4 res, vec4 w0, vec4 aW0, vec4 pairSq, vec4 minCornerSq, vec4 maxCornerSq)
{
  vec4 lost = aW0 * (1.0 - cut4(res));
  if (dot(lost, vec4(1.0)) <= 0.0) return res;
  vec4 lostStrong = lost * vec4(greaterThan(maxCornerSq, vec4(SQ255(XBRZ_MATCH_EDGE))));
  vec4 fix = vec4(0.0);
  if (dot(lostStrong, vec4(1.0)) > 0.0)
  {
    ensureDiagInfo();
    vec4 iA = gIA, iC = gIC, iI = gII, iG = gIG;
    vec4 gap = vec4(cut4(iC).x * cut4(iG).x, cut4(iI).y * cut4(iA).y, cut4(iC).z * cut4(iG).z, cut4(iI).w * cut4(iA).w);
    vec4 wrapE = vec4(lessThan(pairSq, vec4(SQ255(XBRZ_MATCH_WRAP))));
    vec4 needGap = lostStrong * gap * wrapE;
    vec4 wrapN = vec4(0.0);
    if (needGap.x > 0.5) wrapN.x = float(withinY255(toYCbCr(P( 1.0, -2.0)), nB, XBRZ_MATCH_LINE) && withinY255(nD, toYCbCr(P(-2.0,  1.0)), XBRZ_MATCH_LINE));
    if (needGap.y > 0.5) wrapN.y = float(withinY255(toYCbCr(P(-1.0, -2.0)), nB, XBRZ_MATCH_LINE) && withinY255(nF, toYCbCr(P( 2.0,  1.0)), XBRZ_MATCH_LINE));
    if (needGap.z > 0.5) wrapN.z = float(withinY255(toYCbCr(P( 2.0, -1.0)), nF, XBRZ_MATCH_LINE) && withinY255(nH, toYCbCr(P(-1.0,  2.0)), XBRZ_MATCH_LINE));
    if (needGap.w > 0.5) wrapN.w = float(withinY255(nD, toYCbCr(P(-2.0, -1.0)), XBRZ_MATCH_LINE) && withinY255(toYCbCr(P( 1.0,  2.0)), nH, XBRZ_MATCH_LINE));

    vec4 part = vec4(cut4(iA).z, cut4(iC).w, cut4(iI).x, cut4(iG).y);
    vec4 l45 = vec4(isLine45(iA).z, isLine45(iC).w, isLine45(iI).x, isLine45(iG).y);
    vec4 pairCloser = vec4(lessThan(pairSq, maxCornerSq));
    vec4 junc26 = vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
                * vec4(greaterThanEqual(pairSq, 0.5 * maxCornerSq));
    if (dot(lostStrong * junc26, vec4(1.0)) > 0.5)
    {
      vec4 onRamp26 = triLt4(minCornerSq, pairSq, 1.12 * 1.12, maxCornerSq);
      pairCloser *= 1.0 - junc26 * (1.0 - onRamp26);
    }
    fix = max(needGap * wrapN, lostStrong * pairCloser * part * l45 * (1.0 - FLAG(w0, BIT_LINE)));
  }
  vec4 far43 = vec4(greaterThanEqual(minCornerSq, vec4(mincSq)))
             * vec4(lessThan(minCornerSq.zwxy, vec4(SQ255(XBRZ_SAME_M))))
             * vec4(greaterThanEqual(pairSq, vec4(mincSq)));
  if (dot(lost, far43) > 0.0) fix = max(fix, domes43(lost * far43));
  if (dot(fix, vec4(1.0)) > 0.0)
  {
    vec4 noR9 = 1.0 - FLAG(w0, BIT_TONE);
    vec4 back = 1.0 + BIT_LINE * FLAG(w0, BIT_LINE) + BIT_SEC * FLAG(w0, BIT_SEC)
              + noR9 * (BIT_SHALLOW * FLAG(w0, BIT_SHALLOW) + BIT_STEEP * FLAG(w0, BIT_STEEP));
    res = mix(res, back, fix);
  }
  // Rescue a lost pass-0 diagonal line as a clean 45 deg line when P and Q are closer to each other than to E
  // (pair < minSide, minSide >= 40) and P's opposite corner already draws a live 45 deg line painting E
  vec4 cont45 = lost * (1.0 - cut4(res)) * FLAG(w0, BIT_LINE) * vec4(lessThan(pairSq, minCornerSq))
              * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_MATCH_EDGE))));
  if (dot(cont45, vec4(1.0)) > 0.5)
  {
    vec4 w0Sec = FLAG(w0, BIT_SEC);
    ensureCardInfo();
    vec4 iB = gIB, iD = gID, iF = gIF, iH = gIH;
    vec4 pOpp = mix(vec4(iD.z, iB.w, iF.x, iH.y), vec4(iB.z, iF.w, iH.x, iD.y), w0Sec);
    vec4 base45 = cont45 * cut4(pOpp) * isLine45(pOpp);
    vec4 secOk = vec4(equal(FLAG(pOpp, BIT_SEC), w0Sec));
    vec4 needTie = base45 * (1.0 - secOk);
    if (dot(needTie, vec4(1.0)) > 0.5)
    {
      if (needTie.x > 0.5 && distSqY(nE, diagColor(w0Sec.x > 0.5 ? vec2( 1.0, -1.0) : vec2(-1.0,  1.0))) < SQ255(XBRZ_SAME_M)) secOk.x = 1.0;
      if (needTie.y > 0.5 && distSqY(nE, diagColor(w0Sec.y > 0.5 ? vec2( 1.0,  1.0) : vec2(-1.0, -1.0))) < SQ255(XBRZ_SAME_M)) secOk.y = 1.0;
      if (needTie.z > 0.5 && distSqY(nE, diagColor(w0Sec.z > 0.5 ? vec2(-1.0,  1.0) : vec2( 1.0, -1.0))) < SQ255(XBRZ_SAME_M)) secOk.z = 1.0;
      if (needTie.w > 0.5 && distSqY(nE, diagColor(w0Sec.w > 0.5 ? vec2(-1.0, -1.0) : vec2( 1.0,  1.0))) < SQ255(XBRZ_SAME_M)) secOk.w = 1.0;
    }
    vec4 fix45 = base45 * secOk;
    if (dot(fix45, vec4(1.0)) > 0.5)
      res = mix(res, 1.0 + BIT_LINE + BIT_SEC * w0Sec, fix45);
  }
  return res;
}

// Rule 26b: drop uncontinued junction cuts after resolve (orphan bevels, 4-color nb1, obtuse off-ramp,
// lone off-ramp 3-color triangles, and phantom pass-0 diagonal run survivors)
vec4 applyRule26b(vec4 res, vec4 pairSq, vec4 minCornerSq, vec4 maxCornerSq, float minSideSq)
{
  vec4 nb1 = vec4(equal(BLEND(res), vec4(1.0))) * (1.0 - FLAG(res, BIT_LINE))
           * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
  if (dot(nb1, vec4(1.0)) > 0.5)
  {
    ensureDiagInfo();
    vec4 dA = gIA, dC = gIC, dI = gII, dG = gIG;
    vec4 oInfo = vec4(dA.z, dC.w, dI.x, dG.y);
    vec4 oR = cut4(oInfo);
    vec4 nb1Orph = nb1 * vec4(greaterThan(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE)))) * (1.0 - oR);
    vec4 drop = vec4(0.0);
    if (dot(nb1Orph, vec4(1.0)) > 0.5)
    {
      vec4 oW0 = vec4(
        nb1Orph.x > 0.5 ? activeCutOf(W0_AT(-1.0, -1.0)).z : 0.0,
        nb1Orph.y > 0.5 ? activeCutOf(W0_AT( 1.0, -1.0)).w : 0.0,
        nb1Orph.z > 0.5 ? activeCutOf(W0_AT( 1.0,  1.0)).x : 0.0,
        nb1Orph.w > 0.5 ? activeCutOf(W0_AT(-1.0,  1.0)).y : 0.0);
      drop = nb1Orph * oW0;
    }
    vec4 diffSec = nb1 * oR * (1.0 - abs(FLAG(res, BIT_SEC) - FLAG(oInfo, BIT_SEC)));
    vec4 candB = diffSec * FLAG(oInfo, BIT_LINE);
    vec4 candB2 = diffSec * vec4(equal(BLEND(oInfo), vec4(1.0))) * (1.0 - FLAG(oInfo, BIT_LINE))
                * vec4(greaterThanEqual(minCornerSq, vec4(mincSq)));
    vec4 candB2ok = vec4(0.0);
    if (dot(candB2, vec4(1.0)) > 0.5)
    {
      vec4 oEdgeOk = vec4(0.0);
      if (candB2.x > 0.5) { vec3 Oc = diagColor(vec2(-1.0, -1.0)); oEdgeOk.x = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nB), distSqY(Oc, nD)) >= mincSq); }
      if (candB2.y > 0.5) { vec3 Oc = diagColor(vec2( 1.0, -1.0)); oEdgeOk.y = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nB), distSqY(Oc, nF)) >= mincSq); }
      if (candB2.z > 0.5) { vec3 Oc = diagColor(vec2( 1.0,  1.0)); oEdgeOk.z = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nF), distSqY(Oc, nH)) >= mincSq); }
      if (candB2.w > 0.5) { vec3 Oc = diagColor(vec2(-1.0,  1.0)); oEdgeOk.w = float(distSqY(nE, Oc) >= SQ255(XBRZ_JUNC4) && min(distSqY(Oc, nH), distSqY(Oc, nD)) >= mincSq); }
      candB2ok = candB2 * oEdgeOk;
    }
    vec4 obt26 = nb1 * oR * FLAG(oInfo, BIT_LINE)
               * vec4(greaterThan(pairSq, max(vec4(SQ255(XBRZ_MATCH_EDGE)), maxCornerSq)))
               * vec4(greaterThanEqual(minCornerSq, vec4(mincSq)));
    if (dot(obt26, vec4(1.0)) > 0.5)
      obt26 *= triGe4(minCornerSq, maxCornerSq, 1.12 * 1.12, pairSq);
    vec4 loneNb1 = nb1 * (1.0 - oR) * float(dot(cut4(res), vec4(1.0)) < 1.5)
                 * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_JUNC4))));
    vec4 isoOff = vec4(0.0), isoBar = vec4(0.0);
    if (dot(loneNb1, vec4(1.0)) > 0.5)
    {
      isoOff = loneNb1 * triGe4(minCornerSq, pairSq, 1.25 * 1.25, maxCornerSq);
      isoBar = loneNb1 * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_MATCH_EDGE))))
             * triGe4(minCornerSq, pairSq, 1.12 * 1.12, maxCornerSq);
    }
    if (dot(candB + candB2ok + obt26 + isoOff + isoBar, vec4(1.0)) > 0.5)
    {
      ensureCardInfo();
      vec4 iB = gIB, iD = gID, iF = gIF, iH = gIH;
      vec4 cB = cut4(iB), cD = cut4(iD), cF = cut4(iF), cH = cut4(iH);
      vec4 edgeCut = vec4(max(cB.z, cD.z), max(cB.w, cF.w), max(cF.x, cH.x), max(cH.y, cD.y));
      drop = max(drop, candB * (1.0 - edgeCut));
      if (dot(candB2ok, vec4(1.0)) > 0.5)
      {
        float sEA = float(withinY255(nE, diagColor(vec2(-1.0, -1.0)), XBRZ_SAME_M));
        float sEC = float(withinY255(nE, diagColor(vec2( 1.0, -1.0)), XBRZ_SAME_M));
        float sEI = float(withinY255(nE, diagColor(vec2( 1.0,  1.0)), XBRZ_SAME_M));
        float sEG = float(withinY255(nE, diagColor(vec2(-1.0,  1.0)), XBRZ_SAME_M));
        vec4 edgeCutE = vec4(
          max(cB.z * max(FLAG(iB.z, BIT_SEC), sEC), cD.z * max(1.0 - FLAG(iD.z, BIT_SEC), sEG)),
          max(cB.w * max(1.0 - FLAG(iB.w, BIT_SEC), sEA), cF.w * max(FLAG(iF.w, BIT_SEC), sEI)),
          max(cF.x * max(1.0 - FLAG(iF.x, BIT_SEC), sEC), cH.x * max(FLAG(iH.x, BIT_SEC), sEG)),
          max(cH.y * max(1.0 - FLAG(iH.y, BIT_SEC), sEI), cD.y * max(FLAG(iD.y, BIT_SEC), sEA)));
        drop = max(drop, candB2ok * (1.0 - edgeCutE));
      }
      if (dot(obt26 + isoOff + isoBar, vec4(1.0)) > 0.5)
      {
        vec4 uC = vec4(float(dot(cB, vec4(1.0)) < 0.5), float(dot(cD, vec4(1.0)) < 0.5),
                       float(dot(cF, vec4(1.0)) < 0.5), float(dot(cH, vec4(1.0)) < 0.5));
        vec4 secM = FLAG(res, BIT_SEC);
        vec4 qUncut = mix(vec4(uC.x, uC.z, uC.w, uC.y), vec4(uC.y, uC.x, uC.z, uC.w), secM);
        drop = max(drop, obt26 * qUncut);
        vec4 isoWall = vec4(0.0);
        if (dot(isoOff, vec4(1.0)) > 0.5)
        {
          vec4 dUncut = vec4(float(dot(cut4(dA), vec4(1.0)) < 0.5), float(dot(cut4(dC), vec4(1.0)) < 0.5),
                             float(dot(cut4(dI), vec4(1.0)) < 0.5), float(dot(cut4(dG), vec4(1.0)) < 0.5));
          vec4 isoBase = isoOff * (1.0 - edgeCut) * qUncut;
          drop = max(drop, isoBase * dUncut);
          isoWall = isoBase * (1.0 - dUncut) * float(minSideSq >= SQ255(XBRZ_SAME_M));
        }
        isoBar *= mix(vec4(uC.y, uC.x, uC.z, uC.w), vec4(uC.x, uC.z, uC.w, uC.y), secM);
        if (dot(isoWall + isoBar, vec4(1.0)) > 0.5)
        {
          for (int k = 0; k < 4; k++)
          {
            vec2 c = cornerOff(k);
            vec4 m = vtxCorner(c);
            float doW = dot(isoWall, m), doB = dot(isoBar, m);
            if (doW + doB < 0.5) continue;
            vec2 pOff, qOff;
            paintPairOffsets(k, c, dot(secM, m) > 0.5, pOff, qOff);
            vec3 dc = diagColor(c);
            if (doW > 0.5)
            {
              vec4 rPc = pOff.y < -0.5 ? iB : (pOff.y > 0.5 ? iH : (pOff.x < 0.0 ? iD : iF));
              if (dot(cut4(rPc) * FLAG(rPc, BIT_LINE), vec4(1.0)) < 0.5 && withinY255(cardColor(qOff), dc, XBRZ_SAME_M))
                drop = max(drop, m);
            }
            if (doB > 0.5 && withinY255(cardColor(pOff), dc, XBRZ_SAME_M))
              drop = max(drop, m);
          }
        }
      }
    }
    res *= 1.0 - drop;
  }
  vec4 oppLn26 = cut4(res.zwxy) * FLAG(res.zwxy, BIT_LINE);
  vec4 ph26 = cut4(res) * (1.0 - FLAG(res, BIT_SHALLOW)) * (1.0 - FLAG(res, BIT_STEEP)) * (1.0 - oppLn26)
            * vec4(greaterThan(pairSq, max(vec4(SQ255(XBRZ_MATCH_EDGE)), maxCornerSq)))
            * vec4(greaterThanEqual(minCornerSq, 0.0625 * pairSq));
  if (dot(ph26, vec4(1.0)) > 0.5)
  {
    ph26 *= triGe4(minCornerSq, maxCornerSq, 1.12 * 1.12, pairSq);
    if (dot(ph26, vec4(1.0)) > 0.5)
    {
      ensureDiagInfo();
      vec4 iA = gIA, iC = gIC, iI = gII, iG = gIG;
      vec4 oR = vec4(cut4(iA).z, cut4(iC).w, cut4(iI).x, cut4(iG).y);
      vec4 runLive = vec4(max(cut4(iC).x, cut4(iG).x), max(cut4(iA).y, cut4(iI).y),
                          max(cut4(iC).z, cut4(iG).z), max(cut4(iA).w, cut4(iI).w));
      ph26 *= (1.0 - oR) * (1.0 - runLive);
      if (dot(ph26, vec4(1.0)) > 0.5)
      {
        vec4 wA = (ph26.y + ph26.w > 0.5) ? activeCutOf(W0_AT(-1.0, -1.0)) : vec4(0.0);
        vec4 wC = (ph26.x + ph26.z > 0.5) ? activeCutOf(W0_AT( 1.0, -1.0)) : vec4(0.0);
        vec4 wI = (ph26.y + ph26.w > 0.5) ? activeCutOf(W0_AT( 1.0,  1.0)) : vec4(0.0);
        vec4 wG = (ph26.x + ph26.z > 0.5) ? activeCutOf(W0_AT(-1.0,  1.0)) : vec4(0.0);
        vec4 hadRunP0 = vec4(max(wC.x, wG.x), max(wA.y, wI.y), max(wC.z, wG.z), max(wA.w, wI.w));
        res *= 1.0 - ph26 * hadRunP0;
      }
    }
  }
  return res;
}

// Rule 26d: downgrade a 2:1 shallow/steep line to 45 deg when extended neighbor N has its adjacent corner
// cut away at 45 deg (cases A, B, C, D)
vec4 applyRule26d(vec4 res, vec4 pairSq, vec4 minCornerSq)
{
  vec4 sh26 = FLAG(res, BIT_SHALLOW), st26 = FLAG(res, BIT_STEEP), sec26 = FLAG(res, BIT_SEC);
  vec4 ln21Base = cut4(res) * FLAG(res, BIT_LINE) * abs(sh26 - st26)
                * (1.0 - FLAG(res, BIT_LONG3)) * (1.0 - FLAG(res, BIT_LONG4));
  vec4 ln21A = ln21Base * vec4(lessThan(pairSq, vec4(SQ255(XBRZ_SAME_M))));
  vec4 ln21Want = ln21Base * vec4(equal(sec26, st26));
  vec4 ln21B = ln21Want * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
  vec4 ln21C = ln21Want * vec4(greaterThanEqual(pairSq, vec4(mincSq)))
             * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(XBRZ_JUNC4))));
  vec4 ln21D = ln21Base * cut4(res.zwxy) * isLine45(res.zwxy);
  vec4 ln21 = max(max(ln21A, ln21B), max(ln21C, ln21D));
  if (dot(ln21, vec4(1.0)) <= 0.5) return res;
  for (int k = 0; k < 4; k++)
  {
    vec4 m = cornerMask(k);
    if (dot(ln21, m) < 0.5) continue;
    bool isSh = dot(sh26, m) > 0.5;
    vec2 nbrOff, othOff;
    slope21Offsets(k, isSh, nbrOff, othOff);
    float nw = dot(cardInfo(nbrOff), m.zwxy);
    if (BLEND(nw) < 0.5 || FLAG(nw, BIT_LINE) < 0.5 || FLAG(nw, BIT_SHALLOW) > 0.5 || FLAG(nw, BIT_STEEP) > 0.5) continue;
    float wantSec = isSh ? 0.0 : 1.0;
    float nwSec = FLAG(nw, BIT_SEC);
    vec2 extOff = nbrOff - othOff;
    vec3 Nc = cardColor(nbrOff), Xc = diagColor(extOff);
    float dNXSq = distSqY(Nc, Xc), dEXSq = distSqY(nE, Xc);
    bool ok26d = false;
    if (dot(ln21C, m) > 0.5
        && abs(nwSec - (1.0 - wantSec)) < 0.5
        && dEXSq >= SQ255(XBRZ_SAME_M))
      ok26d = true;
    if (!ok26d && dot(ln21A, m) > 0.5)
    {
      if (dNXSq >= SQ255(XBRZ_SAME_M) && dNXSq > dEXSq
          && (abs(nwSec - wantSec) < 0.5 || dEXSq < SQ255(XBRZ_SAME_M)))
        ok26d = true;
    }
    else if (!ok26d && dot(ln21B, m) > 0.5
             && abs(nwSec - wantSec) < 0.5)
    {
      vec3 Oc = cardColor(othOff);
      if (dNXSq >= SQ255(XBRZ_JUNC4) && distSqY(Oc, Xc) >= mincSq
          && withinY255(nE, cardColor(-othOff), XBRZ_SAME_M)
          && dot(cut4(cardInfo(-othOff)), vec4(1.0)) < 0.5)
        ok26d = true;
    }
    if (!ok26d && dot(ln21D, m) > 0.5
        && FLAG(nw, BIT_LONG3) + FLAG(nw, BIT_LONG4) < 0.5
        && abs(nwSec - wantSec) < 0.5
        && dEXSq >= SQ255(XBRZ_SAME_M))
    {
      if (distSqY(cardColor(othOff), Xc) >= mincSq)
      {
        vec4 rO = cardInfo(othOff), rD = diagInfo(nbrOff + othOff);
        if (dot(cut4(rO) * isLine45(rO) + cut4(rD) * isLine45(rD), m.zwxy) > 0.5)
        {
          float xw = dot(diagInfo(extOff), m.zwxy);
          if (FLAG(xw, BIT_SHALLOW) + FLAG(xw, BIT_STEEP) < 0.5)
            ok26d = true;
        }
      }
    }
    if (ok26d)
      res -= m * (isSh ? BIT_SHALLOW : BIT_STEEP);
  }
  return res;
}

// Rules 26e & 26f (shared 45-degree line gate):
// - 26e: drop a 45 deg line cutting a straight 2px light sclera E tucked inside two orthogonal uncut dark bars
// - 26f: upgrade a 45 deg line on a high-contrast (>= 100) gradient edge to 2:1 when partner at extOff matches
vec4 applyRule26ef(vec4 res, vec4 pairSq, vec4 minCornerSq)
{
  vec4 l45_26 = cut4(res) * isLine45(res);
  vec4 eyeC = l45_26 * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))))
            * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(60.0))));
  vec4 ln45 = l45_26 * vec4(greaterThanEqual(minCornerSq, vec4(SQ255(100.0))))
            * vec4(lessThan(pairSq, vec4(SQ255(45.0))));
  if (dot(eyeC + ln45, vec4(1.0)) <= 0.5) return res;
  vec4 secM = FLAG(res, BIT_SEC);
  vec4 dropEye = vec4(0.0);
  vec4 add26f = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec2 c = cornerOff(k);
    vec4 m = vtxCorner(c);
    bool dropped = false;
    if (dot(eyeC, m) > 0.5)
    {
      vec2 pOff, qOff;
      paintPairOffsets(k, c, dot(secM, m) > 0.5, pOff, qOff);
      vec3 Pc = cardColor(pOff), Qc = cardColor(qOff);
      if (max(Pc.x, Qc.x) <= nE.x - 0.15
          && withinY255(nE, cardColor(-qOff), XBRZ_SAME_M) && !withinY255(nE, cardColor(-pOff), XBRZ_SAME_M)
          && withinY255(Qc, diagColor(c), XBRZ_SAME_M) && withinY255(Pc, diagColor(pOff - qOff), XBRZ_SAME_M)
          && dot(cut4(cardInfo(pOff)), vec4(1.0)) < 0.5
          && dot(cut4(cardInfo(qOff)), vec4(1.0)) < 0.5
          && dot(cut4(diagInfo(c)), vec4(1.0)) < 0.5)
      {
        dropEye += m;
        dropped = true;
      }
    }
    if (!dropped && dot(ln45, m) > 0.5)
    {
      float addBit = 0.0;
      for (int dir = 0; dir < 2; dir++)
      {
        bool isSh = (dir == 0);
        vec2 nbrOff, othOff;
        slope21Offsets(k, isSh, nbrOff, othOff);
        vec2 extOff = nbrOff - othOff;
        vec2 runOff = othOff - nbrOff;
        if (!withinY255(nE, cardColor(-othOff), XBRZ_SAME_M)) continue;
        if (!withinY255(nE, diagColor(runOff), XBRZ_SAME_M)) continue;
        vec3 Nc = cardColor(nbrOff), Xc = diagColor(extOff);
        if (distSqY(Nc, Xc) >= SQ255(45.0) || distSqY(nE, Xc) < SQ255(100.0)) continue;
        float xw = dot(diagInfo(extOff), m.zwxy);
        float wantBit = isSh ? BIT_SHALLOW : BIT_STEEP;
        float otherBit = isSh ? BIT_STEEP : BIT_SHALLOW;
        if (BLEND(xw) > 0.5 && FLAG(xw, BIT_LINE) > 0.5 && FLAG(xw, wantBit) > 0.5 && FLAG(xw, otherBit) < 0.5
            && FLAG(xw, BIT_LONG3) < 0.5 && FLAG(xw, BIT_LONG4) < 0.5)
          addBit = addBit > 0.5 ? -1.0 : wantBit;
      }
      if (addBit > 0.5) add26f += m * addBit;
    }
  }
  return res * (1.0 - min(dropEye, vec4(1.0))) + add26f;
}

// Rule 26c (unified dark-outline flat-wall guard):
// - non-line: lone near-black (<= 0.20) b1 bevel leaking a darker uncut Pc against a brighter 3px wall Qc
// - line: dark low-chroma outline leaking a lighter off-ramp color across a > 100 YCbCr flat wall
vec4 applyRule26c(vec4 res, vec4 pairSq)
{
  vec4 isL26 = FLAG(res, BIT_LINE);
  vec4 wallNb1 = float(nE.x <= 0.20) * vec4(equal(BLEND(res), vec4(1.0))) * (1.0 - isL26)
               * vec4(greaterThanEqual(pairSq, vec4(SQ255(XBRZ_JUNC4))));
  vec4 wallLn  = float(dot(nE.yz, nE.yz) < SQ255(50.0)) * cut4(res) * isL26
               * vec4(greaterThan(pairSq, vec4(SQ255(100.0))));
  vec4 wallAll = max(wallNb1, wallLn);
  if (dot(wallAll, vec4(1.0)) <= 0.5) return res;
  vec4 secM = FLAG(res, BIT_SEC);
  vec4 sqW = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec2 c = cornerOff(k);
    vec4 m = vtxCorner(c);
    if (dot(wallAll, m) < 0.5) continue;
    vec4 oppM = vtxCorner(-c);
    if (BLEND(dot(diagInfo(c), oppM)) > 0.5) continue;
    vec2 pOff, qOff;
    paintPairOffsets(k, c, dot(secM, m) > 0.5, pOff, qOff);
    vec3 Pc = cardColor(pOff), Qc = cardColor(qOff);
    if (dot(wallNb1, m) > 0.5)
    {
      float aw = dot(res, vtxCorner(pOff - qOff));
      if (BLEND(aw) < 0.5 || FLAG(aw, BIT_LINE) < 0.5) continue;
      if (Pc.x >= Qc.x - 0.15 || Qc.x < nE.x + 0.30) continue;
      if (!withinY255(nE, cardColor(-pOff), XBRZ_SAME_M)) continue;
      if (BLEND(dot(cardInfo(qOff), oppM)) > 0.5) continue;
      if (dot(cut4(cardInfo(pOff)), vec4(1.0)) > 0.5) continue;
      if (!withinY255(Qc, diagColor(c), XBRZ_SAME_M) || !withinY255(Qc, diagColor(qOff - pOff), XBRZ_SAME_M)) continue;
      if (withinY255(Pc, diagColor(pOff - qOff), XBRZ_SAME_M)) continue;
      sqW += m;
    }
    else
    {
      if (Pc.x < nE.x + 0.10) continue;
      float qw = dot(cardInfo(qOff), oppM);
      if (BLEND(qw) < 0.5 || FLAG(qw, BIT_LINE) < 0.5) continue;
      vec4 rPc = cardInfo(pOff);
      if (dot(cut4(rPc) * FLAG(rPc, BIT_LINE), vec4(1.0)) > 0.5) continue;
      if (distSqY(Qc, diagColor(c)) >= SQ255(XBRZ_SAME_M)) continue;
      vec3 dQP = diagColor(qOff - pOff), dPQ = diagColor(pOff - qOff);
      if (!withinY255(nE, dQP, XBRZ_SAME_M)) continue;
      vec3 eqV = Qc - nE;
      float tP = clamp(dot(Pc - nE, eqV) / max(dot(eqV, eqV), SAFE_EPS), 0.0, 1.0);
      vec3 perpV = Pc - (nE + tP * eqV);
      if (dot(perpV, perpV) < SQ255(24.0)) continue;
      if (distSqY(Pc, dQP) < SQ255(XBRZ_JUNC4) || distSqY(Pc, dPQ) < SQ255(XBRZ_JUNC4)) continue;
      if (withinY255(Pc, at3(2.0 * pOff), XBRZ_SAME_M)) continue;
      if (!withinY255(Qc, at3(2.0 * qOff), XBRZ_SAME_M)) continue;
      sqW += m;
    }
  }
  return res * (1.0 - min(sqW, vec4(1.0)));
}

// ============================================================================================
// 46. A checkerboard keeps its squares
// ============================================================================================
// Soft parity match: q is within tolSq of same and strictly at least 2x closer to same than to opp.
bool chkSoftEq(vec3 q, vec3 same, vec3 opp, float tolSq)
{
  float ds = distSqY(q, same);
  return ds <= tolSq && ds < 0.25 * distSqY(q, opp);
}
// a) 2D interior checkerboards: 3+ of the four 2x2 blocks beside (0, 0) are in-phase checkers of c1 and c2,
//    or 2 orthogonal 2x2 blocks plus the diagonal 2x2 corner between them form a solid 4x4 exact checkerboard.
// b) 1D 2-pixel-wide checker strips: full 6-pixel axial run (bU && bD or bL && bR) bounded laterally by
//    axis-aligned walls (rejecting shifted 45-degree diagonal stripes).
bool chkQuad46(vec2 coord, float ox, float oy, vec3 c1, vec3 c2)
{
  return eq(PY(ox, oy), c1) && eq(PY(ox + 1.0, oy), c2)
      && eq(PY(ox, oy + 1.0), c2) && eq(PY(ox + 1.0, oy + 1.0), c1);
}
bool chkWallBreak46(vec2 coord, vec3 c1, vec3 c2, vec3 w, vec3 o1, vec3 o2,
                    vec2 wE1, vec2 wE2, vec2 oE1, vec2 oE2)
{
  if (!(eq(w, c1) || eq(w, c2))) return false;
  vec3 opp = eq(w, c1) ? c2 : c1;
  bool s1 = eq(o1, opp) && neq(o2, c1) && neq(o2, c2);
  bool s2 = eq(o2, opp) && neq(o1, c1) && neq(o1, c2);
  if (!s1 && !s2) return false;
  if (!eq(PY(wE1.x, wE1.y), w) || !eq(PY(wE2.x, wE2.y), w)) return false;
  vec2 oe = s1 ? oE1 : oE2;
  return eq(PY(oe.x, oe.y), opp);
}
bool chkStrip46(vec2 coord, vec3 c1, vec3 c2, bool hA, bool hB, bool hS1, bool hS2,
                bool wA, bool wB, bool wS1, bool wS2, vec3 cA, vec3 cB, vec3 s1a, vec3 s1b, vec3 s2a, vec3 s2b,
                vec2 pA0, vec2 pA1, vec2 pB0, vec2 pB1, vec2 cTL, vec2 cBL, vec2 cTR, vec2 cBR,
                out bool gotA, out bool outA, out bool gotB, out bool outB)
{
  gotA = false; outA = false; gotB = false; outB = false;
  bool sWall = (wS1 && wS2) || (wS2 && (eq(s2a, c1) || eq(s2a, c2)) && hS1) || (wS1 && (eq(s1a, c1) || eq(s1a, c2)) && hS2);
  if (hA && hB)
  {
    if (sWall
        || (wS1 && chkWallBreak46(coord, c1, c2, s1a, s2a, s2b, cTL, cBL, cTR, cBR))
        || (wS2 && chkWallBreak46(coord, c1, c2, s2a, s1a, s1b, cTR, cBR, cTL, cBL)))
    {
      vec3 a0 = PY(pA0.x, pA0.y), a1 = PY(pA1.x, pA1.y);
      bool bA2 = eq(a0, c1) && eq(a1, c2);
      gotA = true; outA = bA2;
      if (!sWall && !bA2) return false;
      vec3 b0 = PY(pB0.x, pB0.y), b1 = PY(pB1.x, pB1.y);
      bool bB2 = eq(b0, c2) && eq(b1, c1);
      gotB = true; outB = bB2;
      if (bA2 && bB2) return true;
      if (sWall && ((bA2 && eq(b0, b1) && neq(b0, c1) && neq(b0, c2))
                 || (bB2 && eq(a0, a1) && neq(a0, c1) && neq(a0, c2))))
        return true;
    }
    return false;
  }
  if (!sWall) return false;
  bool useA = hA && wB && neq(cB, c1) && neq(cB, c2);
  bool useB = !useA && hB && wA && neq(cA, c1) && neq(cA, c2);
  if (!useA && !useB) return false;
  vec3 cEnd = useA ? cB : cA;
  vec2 e0 = useA ? cBL : cTL, e1 = useA ? cBR : cTR;
  vec2 q0 = useA ? pA0 : pB0, q1 = useA ? pA1 : pB1;
  return eq(PY(e0.x, e0.y), cEnd) && eq(PY(e1.x, e1.y), cEnd)
      && eq(PY(q0.x, q0.y), useA ? c1 : c2) && eq(PY(q1.x, q1.y), useA ? c2 : c1);
}
bool checker46(vec2 coord, vec3 c1, vec3 c2, vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko)
{
  bool hL = eq(ke, c2) && eq(ki, c1);
  bool hR = eq(kh, c1) && eq(kl, c2);
  bool hU = eq(kb, c2) && eq(kc, c1);
  bool hD = eq(kn, c1) && eq(ko, c2);
  if (!(hL || hR || hU || hD)) return false;
  bool wL = eq(ke, ki), wR = eq(kh, kl), wU = eq(kb, kc), wD = eq(kn, ko);
  bool gotU = false, cU = false, gotD = false, cD = false;
  if ((hU || hD) && chkStrip46(coord, c1, c2, hU, hD, hL, hR, wU, wD, wL, wR, kb, kn, ke, ki, kh, kl,
                               vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(0.0, 3.0), vec2(1.0, 3.0),
                               vec2(-1.0, -1.0), vec2(-1.0, 2.0), vec2(2.0, -1.0), vec2(2.0, 2.0),
                               gotU, cU, gotD, cD))
    return true;
  bool gotL = false, cL = false, gotR = false, cR = false;
  if ((hL || hR) && chkStrip46(coord, c1, c2, hL, hR, hU, hD, wL, wR, wU, wD, ke, kh, kb, kc, kn, ko,
                               vec2(-2.0, 0.0), vec2(-2.0, 1.0), vec2(3.0, 0.0), vec2(3.0, 1.0),
                               vec2(-1.0, -1.0), vec2(2.0, -1.0), vec2(-1.0, 2.0), vec2(2.0, 2.0),
                               gotL, cL, gotR, cR))
    return true;
  if (!((hU || hD) && (hL || hR))) return false;
  bool bL = gotL ? cL : (hL && eq(PY(-2.0, 0.0), c1) && eq(PY(-2.0, 1.0), c2));
  bool bR = gotR ? cR : (hR && eq(PY( 3.0, 0.0), c2) && eq(PY( 3.0, 1.0), c1));
  if (!bL && !bR) return false;
  bool bU = gotU ? cU : (hU && eq(PY( 0.0,-2.0), c1) && eq(PY( 1.0,-2.0), c2));
  bool bD = gotD ? cD : (hD && eq(PY( 0.0, 3.0), c2) && eq(PY( 1.0, 3.0), c1));
  if (!bU && !bD) return false;
  if (int(bL) + int(bR) + int(bU) + int(bD) >= 3) return true;
  // Exactly 2 orthogonal 2x2 blocks match: accept if the diagonal 2x2 between them completes an exact 4x4 checker
  return chkQuad46(coord, bL ? -2.0 : 2.0, bU ? -2.0 : 2.0, c1, c2);
}
vec2 meshTolGap(float edgeSq) { float t = min(SQ255(26.0), 0.08 * edgeSq); return vec2(t, max(SQ255(72.0), 4.0 * t)); }
bool meshPair46(vec3 m, vec3 o, vec3 pM, float tolSq, float gapSq) { return distSqY(m, pM) <= tolSq && distSqY(o, pM) >= gapSq; }
bool meshWall46(vec3 w0, vec3 w1, vec3 pM, vec3 oA, vec3 oB, float tolSq, float gapSq)
{
  if (!eq(w0, w1)) return false;
  float dw = distSqY(w0, pM);
  return dw <= tolSq || (dw >= gapSq && neq(w0, oA) && neq(w0, oB));
}
void meshStep46(vec2 coord, bool h, vec2 pm, vec2 po, vec3 pM, vec3 oA, vec3 oB, float tolSq, float gapSq, out bool b, out bool e)
{
  b = false; e = false;
  if (!h) return;
  vec3 qm = PY(pm.x, pm.y), qo = PY(po.x, po.y);
  b = meshPair46(qm, qo, pM, tolSq, gapSq);
  e = b || meshWall46(qm, qo, pM, oA, oB, tolSq, gapSq);
}
bool meshFlankStroke46(vec2 coord, vec3 oS, vec3 oOpp, vec3 oD1, vec3 oD2, vec3 oN1, vec3 oN2, vec2 pcFar, inout vec3 qFar, inout bool haveFar, float tolSq)
{
  if (distSqY(oD1, oS) > tolSq || distSqY(oD2, oS) > tolSq) return false;
  if (min(min(distSqY(oOpp, oS), distSqY(oN1, oS)), distSqY(oN2, oS)) < SQ255(54.0)) return false;
  if (!haveFar) { qFar = PY(pcFar.x, pcFar.y); haveFar = true; }
  if (distSqY(qFar, oS) < SQ255(54.0)) return false;
  vec2 pS = step(vec2(0.5), pcFar);
  vec2 dS = 2.0 * (pcFar - pS);
  vec2 pe1 = pS + vec2(-dS.y, dS.x), pe2 = pS - vec2(-dS.y, dS.x);
  return distSqY(PY(pe1.x, pe1.y), oS) <= tolSq || distSqY(PY(pe2.x, pe2.y), oS) <= tolSq;
}
bool meshQuad46(vec2 coord, float ox, float oy, vec3 pM, float tolSq, float gapSq, bool flip)
{
  vec3 q00 = PY(ox, oy), q10 = PY(ox + 1.0, oy), q01 = PY(ox, oy + 1.0), q11 = PY(ox + 1.0, oy + 1.0);
  if (!flip) return meshPair46(q00, q10, pM, tolSq, gapSq) && meshPair46(q11, q01, pM, tolSq, gapSq);
  return meshPair46(q10, q00, pM, tolSq, gapSq) && meshPair46(q01, q11, pM, tolSq, gapSq);
}
bool meshCornerOk46(vec2 coord, vec2 p, bool hA, bool hB, bool wA, bool wB, vec3 mA, vec3 mB, vec3 pM, float tolSq, float gapSq, bool isMeshSlot, bool strictNonMesh, inout vec3 qOut, inout bool haveOut)
{
  if (hA && hB)
  {
    if (!isMeshSlot && !strictNonMesh) return true;
    qOut = PY(p.x, p.y); haveOut = true;
    return isMeshSlot ? (distSqY(qOut, pM) <= tolSq) : (distSqY(qOut, pM) >= gapSq);
  }
  if (wA && hB) { qOut = PY(p.x, p.y); haveOut = true; return eq(qOut, mA); }
  if (wB && hA) { qOut = PY(p.x, p.y); haveOut = true; return eq(qOut, mB); }
  if (wA && wB && eq(mA, mB)) { qOut = PY(p.x, p.y); haveOut = true; return eq(qOut, mA); }
  return true;
}
bool meshParity46(vec2 coord, vec3 cA, vec3 cB, vec3 oA, vec3 oB, float tolSq, float gapSq,
                  vec3 mH1, vec3 oH1, vec3 mH2, vec3 oH2, vec3 mV1, vec3 oV1, vec3 mV2, vec3 oV2,
                  vec2 pmH1, vec2 poH1, vec2 pmH2, vec2 poH2, vec2 pmV1, vec2 poV1, vec2 pmV2, vec2 poV2,
                  vec2 pcA, vec2 pcB)
{
  vec3 pM = 0.5 * (cA + cB);
  bool hH1 = meshPair46(mH1, oH1, pM, tolSq, gapSq), hH2 = meshPair46(mH2, oH2, pM, tolSq, gapSq);
  if (!hH1 && !hH2) return false;
  bool hV1 = meshPair46(mV1, oV1, pM, tolSq, gapSq), hV2 = meshPair46(mV2, oV2, pM, tolSq, gapSq);
  if (!hV1 && !hV2) return false;
  // Zero-fetch early-out: every side must be either mesh (h*) or a solid wall (w*).
  bool wH1 = !hH1 && meshWall46(mH1, oH1, pM, oA, oB, tolSq, gapSq);
  bool wH2 = !hH2 && meshWall46(mH2, oH2, pM, oA, oB, tolSq, gapSq);
  if (!(hH1 || wH1) || !(hH2 || wH2)) return false;
  bool wV1 = !hV1 && meshWall46(mV1, oV1, pM, oA, oB, tolSq, gapSq);
  bool wV2 = !hV2 && meshWall46(mV2, oV2, pM, oA, oB, tolSq, gapSq);
  if (!(hV1 || wV1) || !(hV2 || wV2)) return false;
  bool bH1, bH2, bV1, bV2, eH1, eH2, eV1, eV2;
  meshStep46(coord, hH1, pmH1, poH1, pM, oA, oB, tolSq, gapSq, bH1, eH1);
  meshStep46(coord, hH2, pmH2, poH2, pM, oA, oB, tolSq, gapSq, bH2, eH2);
  if (!((eH1 && eH2) || (bH1 && wH2) || (bH2 && wH1))) return false;
  meshStep46(coord, hV1, pmV1, poV1, pM, oA, oB, tolSq, gapSq, bV1, eV1);
  meshStep46(coord, hV2, pmV2, poV2, pM, oA, oB, tolSq, gapSq, bV2, eV2);
  if (!((eV1 && eV2) || (bV1 && wV2) || (bV2 && wV1))) return false;
  bool wide = (bH1 && bH2) || (bV1 && bV2);
  if (!wide)
  {
    if (!((bH1 || bH2) && (bV1 || bV2))) return false;
    float qx = bH1 ? (pmH1.x < 0.0 ? -2.0 : 2.0) : (pmH2.x < 0.0 ? -2.0 : 2.0);
    if (!meshQuad46(coord, qx, bV1 ? -2.0 : 2.0, pM, tolSq, gapSq, pmH1.x > 0.0)) return false;
  }
  vec2 pm11 = vec2(pmH1.x > 0.0 ? 2.0 : -1.0, -1.0), pm22 = vec2(pmH2.x > 0.0 ? 2.0 : -1.0, 2.0);
  vec3 qTmp = vec3(0.0), qA = vec3(0.0), qB = vec3(0.0);
  bool haveTmp = false, haveA = false, haveB = false;
  if (!meshCornerOk46(coord, pm11, hH1, hV1, wH1, wV1, mH1, mV1, pM, tolSq, gapSq, true,  !wide, qTmp, haveTmp)
   || !meshCornerOk46(coord, pm22, hH2, hV2, wH2, wV2, mH2, mV2, pM, tolSq, gapSq, true,  !wide, qTmp, haveTmp)
   || !meshCornerOk46(coord, pcA,  hH2, hV1, wH2, wV1, mH2, mV1, pM, tolSq, gapSq, false, !wide, qA,   haveA)
   || !meshCornerOk46(coord, pcB,  hH1, hV2, wH1, wV2, mH1, mV2, pM, tolSq, gapSq, false, !wide, qB,   haveB))
    return false;
  if (distSqY(oA, oB) <= tolSq)
  {
    vec3 pO = 0.5 * (oA + oB);
    if (min(min(distSqY(oH1, pO), distSqY(oH2, pO)), min(distSqY(oV1, pO), distSqY(oV2, pO))) >= SQ255(54.0))
    {
      if (!haveA) { qA = PY(pcA.x, pcA.y); haveA = true; }
      if (distSqY(qA, pO) <= tolSq) return false;
      if (!haveB) { qB = PY(pcB.x, pcB.y); haveB = true; }
      if (distSqY(qB, pO) <= tolSq) return false;
    }
  }
  return !(meshFlankStroke46(coord, oA, oB, oH2, oV1, oH1, oV2, pcA, qA, haveA, tolSq)
        || meshFlankStroke46(coord, oB, oA, oH1, oV2, oH2, oV1, pcB, qB, haveB, tolSq));
}
// d) Shaded / gradient 2D checkerboards and high-contrast 1-parity 50% mesh-transparency overlays.
bool checkerShaded46(vec2 coord, vec3 kf, vec3 kg, vec3 kj, vec3 kk, float d0, float d1, float dFG, float dFJ,
                     vec3 kb, vec3 kc, vec3 ke, vec3 kh, vec3 ki, vec3 kl, vec3 kn, vec3 ko)
{
  float minEdgeSq = min(min(dFG, dFJ), min(distSqY(kk, kg), distSqY(kk, kj)));
  if (minEdgeSq < SQ255(30.0) || min(d0, d1) >= 0.18 * minEdgeSq) return false;
  if (max(d0, d1) < 0.18 * minEdgeSq)
  {
    vec3 p0 = 0.5 * (kf + kk), p1 = 0.5 * (kg + kj);
    float tolSq = 0.18 * distSqY(p0, p1);
    bool hL = chkSoftEq(ke, p1, p0, tolSq) && chkSoftEq(ki, p0, p1, tolSq);
    bool hR = chkSoftEq(kh, p0, p1, tolSq) && chkSoftEq(kl, p1, p0, tolSq);
    bool hU = chkSoftEq(kb, p1, p0, tolSq) && chkSoftEq(kc, p0, p1, tolSq);
    bool hD = chkSoftEq(kn, p0, p1, tolSq) && chkSoftEq(ko, p1, p0, tolSq);
    int rem = int(hL) + int(hR) + int(hU) + int(hD);
    if (rem >= 3)
    {
      int ok = 0;
      if (hL) { if (chkSoftEq(PY(-2.0, 0.0), p0, p1, tolSq) && chkSoftEq(PY(-2.0, 1.0), p1, p0, tolSq)) ok++; rem--; }
      if (ok + rem >= 3 && hR) { if (chkSoftEq(PY( 3.0, 0.0), p1, p0, tolSq) && chkSoftEq(PY( 3.0, 1.0), p0, p1, tolSq)) ok++; rem--; }
      if (ok + rem >= 3 && hU) { if (chkSoftEq(PY( 0.0,-2.0), p0, p1, tolSq) && chkSoftEq(PY( 1.0,-2.0), p1, p0, tolSq)) ok++; rem--; }
      if (ok >= 3) return true;
      if (ok + rem >= 3 && hD && chkSoftEq(PY( 0.0, 3.0), p1, p0, tolSq) && chkSoftEq(PY( 1.0, 3.0), p0, p1, tolSq)) ok++;
      if (ok >= 3) return true;
    }
  }
  if (minEdgeSq < SQ255(72.0)) return false;
  vec2 tg = meshTolGap(minEdgeSq);
  if (min(d0, d1) > tg.x) return false;
  if (d0 <= tg.x && meshParity46(coord, kf, kk, kg, kj, tg.x, tg.y,
                                 ki, ke, kh, kl, kc, kb, kn, ko,
                                 vec2(-2.0, 0.0), vec2(-2.0, 1.0), vec2(3.0, 1.0), vec2(3.0, 0.0),
                                 vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(1.0, 3.0), vec2(0.0, 3.0),
                                 vec2(2.0, -1.0), vec2(-1.0, 2.0)))
    return true;
  if (d1 <= tg.x && meshParity46(coord, kg, kj, kf, kk, tg.x, tg.y,
                                 kl, kh, ke, ki, kb, kc, ko, kn,
                                 vec2(3.0, 0.0), vec2(3.0, 1.0), vec2(-2.0, 1.0), vec2(-2.0, 0.0),
                                 vec2(1.0, -2.0), vec2(0.0, -2.0), vec2(0.0, 3.0), vec2(1.0, 3.0),
                                 vec2(-1.0, -1.0), vec2(2.0, 2.0)))
    return true;
  return false;
}
// Helper for 2x4 shaded or 3-row 1-parity 50% mesh checker strip beside an exact 1x4 solid wall (in-register checks first).
bool chkEdgeSoft2x4(vec2 coord, vec3 a0, vec3 b0, vec3 a1, vec3 b1, vec3 a2, vec3 b2, vec2 oA, vec2 oB, vec2 p3A, vec2 p3B, vec3 w,
                    float dA0B0Sq, float dA01Sq, float dB01Sq, bool haveO, vec3 qOA, vec3 qOB, bool have3, vec3 q3A, vec3 q3B)
{
  float minEdgeSq = min(min(dA0B0Sq, distSqY(a0, b1)), min(distSqY(a1, b0), distSqY(a1, b1)));
  if (minEdgeSq < SQ255(35.0) || min(dA01Sq, dB01Sq) >= 0.18 * minEdgeSq) return false;
  vec3 pA = 0.5 * (a0 + a1), pB = 0.5 * (b0 + b1);
  if (max(dA01Sq, dB01Sq) < 0.18 * minEdgeSq)
  {
    float tolSq = 0.18 * distSqY(pA, pB);
    if (chkSoftEq(a2, pA, pB, tolSq) && chkSoftEq(b2, pB, pA, tolSq))
    {
      if (!haveO) { qOA = PY(oA.x, oA.y); qOB = PY(oB.x, oB.y); haveO = true; }
      if (chkSoftEq(qOA, pA, pB, tolSq) && chkSoftEq(qOB, pB, pA, tolSq))
        return true;
    }
  }
  if (minEdgeSq < SQ255(72.0)) return false;
  vec2 tg = meshTolGap(minEdgeSq);
  float mTolSq = tg.x, mGapSq = tg.y;
  if (min(dA01Sq, dB01Sq) > mTolSq) return false;
  float dwA = distSqY(w, pA), dwB = distSqY(w, pB);
  bool baseA = dA01Sq <= mTolSq && (dwA <= mTolSq || (dwA >= mGapSq && neq(w, b0) && neq(w, b1)));
  bool baseB = dB01Sq <= mTolSq && (dwB <= mTolSq || (dwB >= mGapSq && neq(w, a0) && neq(w, a1)));
  if (!baseA && !baseB) return false;
  bool mA_P = distSqY(a2, pA) <= mTolSq, mA_M = distSqY(b2, pA) >= mGapSq;
  bool mB_M = distSqY(b2, pB) <= mTolSq, mB_P = distSqY(a2, pB) >= mGapSq;
  bool wM = eq(b2, w), wP = eq(a2, w);
  bool candA = baseA && ((mA_P && mA_M) || (wM && mA_P) || (wP && mA_M));
  bool candB = baseB && ((mB_M && mB_P) || (wM && mB_P) || (wP && mB_M));
  if (!candA && !candB) return false;
  if (!haveO) { qOA = PY(oA.x, oA.y); qOB = PY(oB.x, oB.y); }
  bool perpM = wM && eq(qOA, w), perpP = wP && eq(qOB, w);
  bool sideA_M = mA_M && distSqY(qOA, pA) <= mTolSq;
  bool sideA_P = mA_P && distSqY(qOB, pA) >= mGapSq && !(dwA >= mGapSq && eq(w, b2) && eq(w, qOB));
  bool sideB_M = mB_M && distSqY(qOA, pB) >= mGapSq && !(dwB >= mGapSq && eq(w, a2) && eq(w, qOA));
  bool sideB_P = mB_P && distSqY(qOB, pB) <= mTolSq;
  bool okA = baseA && sideA_M && sideA_P, okB = baseB && sideB_M && sideB_P;
  bool cA_M = !okA && baseA && perpM && sideA_P, cA_P = !okA && baseA && perpP && sideA_M;
  bool cB_M = !okB && baseB && perpM && sideB_P, cB_P = !okB && baseB && perpP && sideB_M;
  if (!(okA || okB || cA_M || cA_P || cB_M || cB_P)) return false;
  if (!have3) { q3A = PY(p3A.x, p3A.y); q3B = PY(p3B.x, p3B.y); }
  bool r3A = meshPair46(q3A, q3B, pA, mTolSq, mGapSq);
  bool r3B = meshPair46(q3B, q3A, pB, mTolSq, mGapSq);
  if ((okA && r3A) || (okB && r3B)) return true;
  vec2 t = p3B - p3A, n = p3A - (oA + t);
  if ((cA_M && r3A) || (cB_M && r3B))
  {
    vec2 e1 = oB - n + t, e2 = oB + t, e3 = p3B + t, e4 = p3B + 2.0 * t;
    vec3 q1 = PY(e1.x, e1.y), q2 = PY(e2.x, e2.y), q3 = PY(e3.x, e3.y), q4 = PY(e4.x, e4.y);
    if (cA_M && r3A && meshPair46(q2, q1, pA, mTolSq, mGapSq) && meshPair46(q3, q4, pA, mTolSq, mGapSq)) return true;
    if (cB_M && r3B && meshPair46(q1, q2, pB, mTolSq, mGapSq) && meshPair46(q4, q3, pB, mTolSq, mGapSq)) return true;
  }
  if ((cA_P && r3A) || (cB_P && r3B))
  {
    vec2 e1 = oA - n - t, e2 = oA - t, e3 = p3A - t, e4 = p3A - 2.0 * t;
    vec3 q1 = PY(e1.x, e1.y), q2 = PY(e2.x, e2.y), q3 = PY(e3.x, e3.y), q4 = PY(e4.x, e4.y);
    if (cA_P && r3A && meshPair46(q1, q2, pA, mTolSq, mGapSq) && meshPair46(q4, q3, pA, mTolSq, mGapSq)) return true;
    if (cB_P && r3B && meshPair46(q2, q1, pB, mTolSq, mGapSq) && meshPair46(q3, q4, pB, mTolSq, mGapSq)) return true;
  }
  return false;
}
// 3-wall inner corner of a framed 50% mesh (3 pixels equal wall W, 1 odd corner O opens into a 3x3 alternating mesh).
bool chkCornerMesh46(vec2 coord, vec3 W, float dOWSq, vec3 m1, vec3 m2, vec3 w1, vec3 w2, float sx, float sy, float dx, float dy)
{
  if (dOWSq < SQ255(72.0) || !eq(w1, W) || !eq(w2, W)) return false;
  vec2 tg = meshTolGap(dOWSq);
  if (distSqY(m1, W) > tg.x || distSqY(m2, W) > tg.x) return false;
  return distSqY(PY(sx + dx, sy + dy), W) >= tg.y
      && meshPair46(PY(sx + 2.0 * dx, sy + dy), PY(sx + 2.0 * dx, sy), W, tg.x, tg.y)
      && meshPair46(PY(sx + dx, sy + 2.0 * dy), PY(sx, sy + 2.0 * dy), W, tg.x, tg.y)
      && distSqY(PY(sx + 2.0 * dx, sy + 2.0 * dy), W) >= tg.y;
}
// c) A 4-pixel solid wall column/row immediately adjacent to a confirmed 2x4 checker strip (exact, shaded, or 3-row 50% mesh).
bool chkCapPerp46(vec2 coord, vec3 c1, vec3 c2, vec3 sA0, vec3 sB0, vec2 pA1, vec2 pB1, vec2 pf0, vec2 pf1,
                  inout bool haveO, inout vec3 qOA, inout vec3 qOB, inout bool have3, inout vec3 q3A, inout vec3 q3B)
{
  bool cA0 = eq(sA0, c2), cB0 = eq(sB0, c1);
  bool wA0 = eq(sA0, c1), wB0 = eq(sB0, c2);
  if (!((cA0 && (cB0 || wB0)) || (cB0 && wA0))) return false;
  q3A = PY(pf0.x, pf0.y); q3B = PY(pf1.x, pf1.y); have3 = true;
  if (!eq(q3A, c1) || !eq(q3B, c2)) return false;
  qOA = PY(pA1.x, pA1.y); qOB = PY(pB1.x, pB1.y); haveO = true;
  bool cA = cA0 && eq(qOA, c1), cB = cB0 && eq(qOB, c2);
  bool wA = (cA0 || wA0) && eq(sA0, qOA);
  bool wB = (cB0 || wB0) && eq(sB0, qOB);
  return (cA && (cB || wB)) || (cB && wA);
}
bool chkEdgeDir46(vec2 coord, vec3 c1, vec3 c2, vec3 w, bool sameWall, vec3 wA, vec3 wB, bool eqWA, bool eqWB,
                  vec3 a1, vec3 b1, vec3 a2, vec3 b2, vec2 oA, vec2 oB, vec2 p3A, vec2 p3B, float dC12Sq, float dA01Sq, float dB01Sq)
{
  bool cIn = eq(b1, c2) && eq(a1, c1);
  if (eqWA && eqWB)
  {
    bool haveO = false, have3 = false;
    vec3 qOA = vec3(0.0), qOB = vec3(0.0), q3A = vec3(0.0), q3B = vec3(0.0);
    if (cIn)
    {
      if (sameWall)
      {
        if (eq(b2, c2) && eq(a2, c1))
        {
          qOA = PY(oA.x, oA.y); qOB = PY(oB.x, oB.y); haveO = true;
          if (eq(qOA, c1) && eq(qOB, c2)) return true;
        }
      }
      else if (chkCapPerp46(coord, c1, c2, b2, a2, oA, oB, p3A, p3B, haveO, qOA, qOB, have3, q3A, q3B))
        return true;
    }
    return chkEdgeSoft2x4(coord, c1, c2, a1, b1, a2, b2, oA, oB, p3A, p3B, w, dC12Sq, dA01Sq, dB01Sq, haveO, qOA, qOB, have3, q3A, q3B);
  }
  if (!sameWall || !cIn) return false;
  vec3 wOth = eqWA ? wB : wA;
  if (!(eq(eqWA ? a2 : b2, wOth) && neq(wOth, c1) && neq(wOth, c2) && eq(eqWA ? b2 : a2, eqWA ? c2 : c1)))
    return false;
  vec2 t = p3B - p3A, n = (oA - p3A) + t;
  vec2 oS = eqWA ? oA : oB;
  vec2 s1 = oS + n + (eqWA ? -t : t);
  vec2 s2 = s1 + n;
  vec3 cExp = eqWA ? c1 : c2;
  return eq(PY(oS.x, oS.y), cExp) && eq(PY(s1.x, s1.y), cExp) && eq(PY(s2.x, s2.y), w);
}
bool checkerEdge46(vec2 coord, vec3 kb, vec3 kc, vec3 ke, vec3 kf, vec3 kg, vec3 kh, vec3 ki, vec3 kj, vec3 kk, vec3 kl, vec3 kn, vec3 ko,
                   bool eqFG, bool eqFJ, bool eqJK, bool eqGK, vec4 jgSq, vec4 fkSq, float dFkSq, float dJgSq)
{
  if (eqGK != eqFJ)
  {
    vec3 w = eqGK ? kg : kf, wA = eqGK ? kc : kb, wB = eqGK ? ko : kn;
    bool eqWA = eq(wA, w), eqWB = eq(wB, w);
    if (eqWA || eqWB)
    {
      float dA = eqGK ? jgSq.x : fkSq.w, dB = eqGK ? fkSq.x : jgSq.w;
      vec3 c1 = eqGK ? kf : kg, c2 = eqGK ? kj : kk;
      float dC12Sq = distSqY(c1, c2);
      if (min(dA, dB) <= 0.18 * dC12Sq
          && chkEdgeDir46(coord, c1, c2, w, eqFG || eqJK, wA, wB, eqWA, eqWB,
                          eqGK ? ki : kl, eqGK ? ke : kh, eqGK ? kn : ko, eqGK ? kb : kc,
                          eqGK ? vec2(-1.0, -1.0) : vec2(2.0, -1.0), eqGK ? vec2(-1.0, 2.0) : vec2(2.0, 2.0),
                          eqGK ? vec2(-2.0,  0.0) : vec2(3.0,  0.0), eqGK ? vec2(-2.0, 1.0) : vec2(3.0, 1.0),
                          dC12Sq, dA, dB))
        return true;
    }
  }
  if (eqJK != eqFG)
  {
    vec3 w = eqJK ? kj : kf, wA = eqJK ? ki : ke, wB = eqJK ? kl : kh;
    bool eqWA = eq(wA, w), eqWB = eq(wB, w);
    if (eqWA || eqWB)
    {
      float dA = eqJK ? jgSq.y : fkSq.y, dB = eqJK ? fkSq.z : jgSq.z;
      vec3 c1 = eqJK ? kf : kj, c2 = eqJK ? kg : kk;
      float dC12Sq = distSqY(c1, c2);
      if (min(dA, dB) <= 0.18 * dC12Sq
          && chkEdgeDir46(coord, c1, c2, w, eqFJ || eqGK, wA, wB, eqWA, eqWB,
                          eqJK ? kc : ko, eqJK ? kb : kn, eqJK ? kh : kl, eqJK ? ke : ki,
                          eqJK ? vec2(-1.0, -1.0) : vec2(-1.0, 2.0), eqJK ? vec2(2.0, -1.0) : vec2(2.0, 2.0),
                          eqJK ? vec2( 0.0, -2.0) : vec2( 0.0, 3.0), eqJK ? vec2(1.0, -2.0) : vec2(1.0, 3.0),
                          dC12Sq, dA, dB))
        return true;
    }
  }
  if (eqGK != eqFJ && eqJK != eqFG)
  {
    if (eqFG && eqFJ && chkCornerMesh46(coord, kf, dFkSq, kl, ko, kh, kn, 1.0, 1.0,  1.0,  1.0)) return true;
    if (eqFG && eqGK && chkCornerMesh46(coord, kg, dJgSq, ki, kn, ke, ko, 0.0, 1.0, -1.0,  1.0)) return true;
    if (eqFJ && eqJK && chkCornerMesh46(coord, kj, dJgSq, kh, kc, kl, kb, 1.0, 0.0,  1.0, -1.0)) return true;
    if (eqGK && eqJK && chkCornerMesh46(coord, kk, dFkSq, ke, kb, ki, kc, 0.0, 0.0, -1.0, -1.0)) return true;
  }
  return false;
}

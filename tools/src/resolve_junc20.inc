// ============================================================================================
// Resolve pass — Isolated pixels, junctions, straight lines, crossed cuts, knight's move
// (Rules 19, 20, 21, 22, 37)
// ============================================================================================

// ---- 19. A pixel apart keeps to itself ----
float isoSqOf5(vec3 c, float baseSq, vec3 n0, vec3 n1, vec3 n2, vec3 n3, vec3 n4)
{
  if (baseSq < SQ255(XBRZ_SAME)) return baseSq;
  return min(baseSq, min(min(distSqY(c, n0), distSqY(c, n1)),
                         min(min(distSqY(c, n2), distSqY(c, n3)), distSqY(c, n4))));
}
float squareOf(vec4 word) { return dot(BLEND(word), vec4(1.0)) == 0.0 ? 1.0 : 0.0; }

// ---- 20. Strong-ramp midpoint helper ----
float aa20(vec3 Pc, vec3 O, vec3 P2, vec3 O2, float d1, float d2)
{
  if (!sameColor(P2, Pc) || !sameColor(O2, O)) return 0.0;
  float acSq = distSqY(Pc, O);
  if (acSq <= SQ255(XBRZ_JUNC_FAR)) return 0.0;
  float s = d1 + d2;
  return float(s * s < (XBRZ_JUNC_RAMP * XBRZ_JUNC_RAMP) * acSq);
}

// ---- 37. Knight's-move contour kin & single-corner test ----
#define XBRZ_KIN37 0.6
bool kin37(vec3 O, vec3 K, vec3 Pc)
{
  float okSq = distSqY(O, K);
  return okSq < SQ255(XBRZ_SAME) || okSq < (XBRZ_KIN37 * XBRZ_KIN37) * min(distSqY(O, Pc), distSqY(K, Pc));
}
float knightFlip37(bool s1, vec3 cPri, vec3 cSec, vec3 kPri, vec3 kSec, float dPri, float dSec, float cand,
                   float cutPri, float secPri, float cutSec, float secSec)
{
  bool face = s1 ? (cutSec > 0.5 && secSec < 0.5) : (cutPri > 0.5 && secPri > 0.5);
  if (!face) return 0.0;
  vec3 Pc = s1 ? cSec : cPri, O = s1 ? cPri : cSec, K = s1 ? kSec : kPri;
  float dPcE = s1 ? dSec : dPri, dOE = s1 ? dPri : dSec;
  return float(dPcE >= XBRZ_JUNCTION && dOE >= XBRZ_JUNCTION && cand + dPcE >= 1.15 * dOE && kin37(O, K, Pc));
}

// ---- 21 and 22: corner-local neighborhood frame ----
// Oriented around a corner's chosen paint direction p (color u) and unchosen side q (color w):
//   p, q     : unit cardinal offsets to painted neighbor u and unchosen neighbor w; s = BIT_SEC flag
//   u, w     : colors at +p and +q; mu, mw = colors at -p and -q; opp = diagonal pixel at -p-q
//   uw       : corner diagonal pixel at +p+q; umw = +p-q; wmu = +q-p
//   u2, w2   : two steps along +p and +q; u2mw = +2p-q; w2mu = +2q-p; uw2 = +p+2q
//   ru, rumw : decision word of +p's opposite corner and +p-q's matching corner
struct Roles
{
  vec2 p, q;
  float s;
  vec3 u, w, mu, mw, opp, uw, umw, wmu, u2, w2, u2mw, w2mu, uw2;
  float ru, rumw;
};
Roles makeRoles(vec2 v, vec2 h, vec3 cv, vec3 ch, vec3 cvh, vec3 cvmh, vec3 chmv,
                vec3 cv2, vec3 ch2, vec3 cv2mh, vec3 ch2mv, vec3 cvp2h, vec3 chp2v,
                vec3 cmv, vec3 cmh, vec3 copp, float rv, float rh, float rvmh, float rhmv, float s)
{
  bool sv = s > 0.5;
  Roles r;
  r.s = s;
  r.p = sv ? v : h;            r.q = sv ? h : v;
  r.u = sv ? cv : ch;          r.w = sv ? ch : cv;
  r.mu = sv ? cmv : cmh;       r.mw = sv ? cmh : cmv;
  r.opp = copp;                r.uw = cvh;
  r.umw = sv ? cvmh : chmv;    r.wmu = sv ? chmv : cvmh;
  r.u2 = sv ? cv2 : ch2;       r.w2 = sv ? ch2 : cv2;
  r.u2mw = sv ? cv2mh : ch2mv; r.w2mu = sv ? ch2mv : cv2mh;
  r.uw2 = sv ? cvp2h : chp2v;
  r.ru = sv ? rv : rh;         r.rumw = sv ? rvmh : rhmv;
  return r;
}

// ---- 21. A straight line does not bend ----
vec2 straight21(Roles r, vec3 E, float ln, float uwSq, float euSq, float ewSq)
{
  bool shadedLine = withinY255(r.u, r.uw, XBRZ_MINC) && withinY255(r.u, r.umw, XBRZ_MINC) && sameColor(r.uw, r.umw);
  if (uwSq <= SQ255(XBRZ_LINE_SIDE) || (!sameColor(r.u, r.uw) && !shadedLine)) return vec2(0.0);
  float minESq = min(euSq, ewSq);
  float dEwmuSq = distSqY(E, r.wmu);
  bool sEwmu = dEwmuSq < SQ255(XBRZ_SAME);
  float dEmuSq = distSqY(E, r.mu);
  bool sEmu = dEmuSq < SQ255(XBRZ_SAME);
  bool sEmw = sameColor(E, r.mw);
  if (minESq >= SQ255(XBRZ_LINE_STRONG) && sEwmu && sEmw && !sEmu && !sameColor(E, r.opp))
    return vec2(0.0);
  if (uwSq < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * minESq
      && (ln > 0.5 || sameColor(r.w, r.mw))
      && (sEmu || sEwmu
          || dEmuSq < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * distSqY(r.mu, r.u)
          || dEwmuSq < (XBRZ_LINE_TONE * XBRZ_LINE_TONE) * distSqY(r.wmu, r.u))) return vec2(0.0);
  if (minESq >= SQ255(XBRZ_LINE_STRONG) && sameColor(r.u, r.u2) && sEwmu && !withinY255(r.w, r.mw, XBRZ_LINE_PAST))
  {
    bool tipE = !sEmu && !sEmw;
    if (uwSq < (XBRZ_LINE_BACK * XBRZ_LINE_BACK) * minESq) { if (tipE) return vec2(0.0); }
    else if ((tipE || sameColor(r.w, r.w2mu)) && !(sameColor(r.u, r.mu) && sameColor(r.u, r.mw))) return vec2(1.0, 1.0);
  }
  bool middle = sameColor(r.u, r.umw) || shadedLine;
  bool four = !middle && euSq >= SQ255(XBRZ_LINE_STRONG) && !sameColor(r.w, r.umw)
           && distSqY(r.u2, r.u) > distSqY(r.u2, E)
           && sameColor(r.u, r.uw2)
           && distSqY(r.u2mw, E) < min(distSqY(r.u2mw, r.u), distSqY(r.u2mw, r.w))
           && dEwmuSq >= SQ255(XBRZ_LINE_ALONG) && !withinY255(E, r.umw, XBRZ_LINE_ALONG)
           && sameColor(r.u, at(r.p + 3.0 * r.q));
  if (!middle && !four) return vec2(0.0);
  bool takes = sameColor(r.w, r.w2) && euSq >= SQ255(XBRZ_LINE_STRONG) && sameColor(r.w, r.w2mu)
            && dEwmuSq < distSqY(r.wmu, r.w) && r.w.x < E.x;
  return vec2(1.0, takes ? 1.0 : 0.0);
}

// ---- 22. Crossed cuts ----
float back22(Roles r, vec3 E, float eWord, float blocked, float loneE)
{
  float along = r.s > 0.5 ? BIT_SHALLOW : BIT_STEEP;
  if (BLEND(r.ru) == 0.0 || abs(FLAG(r.ru, BIT_SEC) - r.s) > 0.5 || max(FLAG(r.ru, BIT_BLOCKED), blocked) < 0.5
      || max(FLAG(r.ru, along), FLAG(eWord, along)) < 0.5) return 0.0;
  float dnSq = distSqY(E, r.u);
  if (dnSq >= SQ255(XBRZ_CROSS_MAX)) return 0.0;
  if (r.u.x > E.x)
  {
    if (dnSq < SQ255(XBRZ_CROSS_RAMP) && r.mu.x < E.x) return 0.0;
    return sameAsOne(r.u, r.w, r.u2mw) * loneE;
  }
  if (dnSq < SQ255(XBRZ_CROSS_RAMP) && r.u2.x < r.u.x) return 0.0;
  return sameAsOne(E, r.umw, r.wmu) * apartFrom4(r.u, E, r.u2, r.uw, r.umw);
}
float tip22(Roles r, vec3 E)
{
  if (BLEND(r.ru) == 0.0 || BLEND(r.rumw) == 0.0 || max(FLAG(r.ru, BIT_BLOCKED), FLAG(r.rumw, BIT_BLOCKED)) < 0.5) return 0.0;
  float dlSq = distSqY(r.umw, r.u);
  if (dlSq < SQ255(XBRZ_SAME) || dlSq >= SQ255(XBRZ_CROSS_MAX) || r.umw.x <= r.u.x) return 0.0;
  if (sameColor(r.u, r.w) || sameColor(r.u, r.uw) || sameColor(r.w, r.uw) || sameColor(E, r.uw) || sameColor(E, r.u) || sameColor(r.u, r.u2)) return 0.0;
  return sameColor(r.umw, at(2.0 * (r.p - r.q))) ? 1.0 : 0.0;
}
#define ROLES_0(s) makeRoles(vX, hX, B, D, A, C, G, uu, ll, ruu, lld, llu, luu, H, F, I, iB.z, iD.z, iC.x, iG.x, s)
#define ROLES_1(s) makeRoles(vY, hY, F, B, C, I, A, rr, uu, rrd, luu, ruu, rru, D, H, G, iF.w, iB.w, iI.y, iA.y, s)
#define ROLES_2(s) makeRoles(vZ, hZ, H, F, I, G, C, dd, rr, ldd, rru, rrd, rdd, B, D, A, iH.x, iF.x, iG.z, iC.z, s)
#define ROLES_3(s) makeRoles(vW, hW, D, H, G, A, I, ll, dd, llu, rdd, ldd, lld, F, B, C, iD.y, iH.y, iA.w, iI.w, s)

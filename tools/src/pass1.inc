@include "header_short.inc"
@include "license.inc"

//#crisp{
// Pass 1 of xbrz-crisp (@BACKEND_LABEL@)
//#crisp}
//#plain // Pass 1 of xbrz-freescale-multipass (@BACKEND_LABEL@)
@STAGE_PASS1@

const float INV_SQRT2 = 0.7071067811865475;

#if __VERSION__ < 300
// the first pass's decisions for the four corners of the pixel at (x, y) from E; see the decision
// word in pass 0 (BLEND is the blend type, FLAG(r, f) one of its flags)
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
#endif
//#crisp{
#define XBRZ_TIPK 0.1  // 23. a loose pixel's tip: the cut line moves out by this

// Exact C1 signed distance to the corner chip outside a quarter-circle of radius r
// centered at (c, c) where c = 0.5 - r, tangent to y = 0.5 at (c, 0.5) and x = 0.5 at (0.5, c).
// Exact D4-symmetric in (cpx, cpy) with zero AA bleed along flat walls.
float sdCornerArc(float cpx, float cpy, float r)
{
  float c = 0.5 - r;
  float dx = cpx - c, dy = cpy - c;
  if (dx >= 0.0 && dy >= 0.0) return length(vec2(dx, dy)) - r;
  if (dx <  0.0 && dy >= 0.0) return -length(vec2(dx, cpy - 0.5));
  if (dy <  0.0 && dx >= 0.0) return -length(vec2(cpx - 0.5, dy));
  return -min(length(vec2(dx, cpy - 0.5)), length(vec2(cpx - 0.5, dy)));
}

#if __VERSION__ >= 300
bool cIs45U(uint w)  { return (w & 3u) != 0u && ((w >> 2u) & 1u) != 0u && (w & 240u) == 0u; }
bool cIsShLU(uint w) { return (w & 3u) != 0u && ((w >> 2u) & 1u) != 0u && ((w >> 4u) & 1u) != 0u && ((w >> 6u) & 1u) == 0u; }
bool cIsStLU(uint w) { return (w & 3u) != 0u && ((w >> 2u) & 1u) != 0u && ((w >> 6u) & 1u) != 0u && ((w >> 4u) & 1u) == 0u; }
bool flat45ArcU(uint wx, uint wy, uint wxr, uint wyr)
{
  bool p0Cont = cIs45U(wy) || cIsStLU(wy) || cIs45U(wyr) || cIsShLU(wyr);
  bool p1Cont = cIs45U(wx) || cIsShLU(wx) || cIs45U(wxr) || cIsStLU(wxr);
  return !p0Cont && !p1Cont;
}
#else
bool cIs45F(float w)  { return BLEND(w) > 0.0 && FLAG(w, 4.0) > 0.5 && (FLAG(w, 16.0) + FLAG(w, 32.0) + FLAG(w, 64.0) + FLAG(w, 128.0)) < 0.5; }
bool cIsShLF(float w) { return BLEND(w) > 0.0 && FLAG(w, 4.0) > 0.5 && FLAG(w, 16.0) > 0.5 && FLAG(w, 64.0) < 0.5; }
bool cIsStLF(float w) { return BLEND(w) > 0.0 && FLAG(w, 4.0) > 0.5 && FLAG(w, 64.0) > 0.5 && FLAG(w, 16.0) < 0.5; }
bool flat45ArcF(float wx, float wy, float wxr, float wyr)
{
  bool p0Cont = cIs45F(wy) || cIsStLF(wy) || cIs45F(wyr) || cIsShLF(wyr);
  bool p1Cont = cIs45F(wx) || cIsShLF(wx) || cIs45F(wxr) || cIsStLF(wxr);
  return !p0Cont && !p1Cont;
}
#endif
//#crisp}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping: -|B|-
  //                      D|E|F
  //                      -|H|-

@PASS1_COORDS@

  vec4 rawInfo = INFO_CENTER;

  // most output pixels have no corner to blend, and only need these two reads
  if (dot(rawInfo, vec4(1.0)) < 0.5 / 255.0)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }

  // info Mapping: x|y|
  //               w|z|
#if __VERSION__ >= 300
  uvec4 iw = uvec4(rawInfo * 255.0 + 0.5);
  uvec4 blU = iw & 3u;
  MP vec4 blendResult = vec4(blU);
  MP vec4 isCut = vec4(notEqual(blU, uvec4(0u)));
  MP vec4 doLineBlend = vec4((iw >> 2u) & 1u);
  MP vec4 secondPix = vec4((iw >> 3u) & 1u);
  MP vec4 haveShallowLine = vec4((iw >> 4u) & 1u);
  MP vec4 haveSteepLine = vec4((iw >> 6u) & 1u);
//#crisp{
  MP vec4 tip = 1.0 + XBRZ_TIPK * vec4(equal(blU, uvec4(3u)));
//#crisp}
#else
  vec4 info = floor(rawInfo * 255.0 + 0.5);
  vec4 blendResult = BLEND(info);
  vec4 isCut = vec4(greaterThan(blendResult, vec4(0.0)));
  vec4 doLineBlend = FLAG(info, 4.0);
  vec4 secondPix = FLAG(info, 8.0);
  vec4 haveShallowLine = FLAG(info, 16.0);
  vec4 haveSteepLine = FLAG(info, 64.0);
//#crisp{
  vec4 tip = 1.0 + XBRZ_TIPK * vec4(equal(blendResult, vec4(3.0)));
  vec4 longL = FLAG(info, 32.0) + 2.0 * FLAG(info, 128.0);
//#crisp}
#endif

  // Vectorized exact signed distance (pre-scaled by INV_SQRT2) for all 4 corners in canonical BR frame
  vec4 px = vec4(-pos.x, -pos.y,  pos.x,  pos.y);
  vec4 py = vec4(-pos.y,  pos.x,  pos.y, -pos.x);

  vec4 pSum = px + py;
//#crisp{
  vec4 d = (pSum - mix(INV_SQRT2 * tip, vec4(0.5), doLineBlend)) * scK.x;
//#crisp}
//#plain   vec4 d = (pSum - mix(vec4(INV_SQRT2), vec4(0.5), doLineBlend)) * scK.x;
#if __VERSION__ >= 300
  if (any(notEqual(iw & uvec4(80u), uvec4(0u))))
#else
  if (dot(doLineBlend * (haveShallowLine + haveSteepLine), vec4(1.0)) > 0.0)
#endif
  {
    vec4 dSh = (px + 2.0 * py - 0.5) * scK.yzyz;
    vec4 dSt = (2.0 * px + py - 0.5) * scK.zyzy;
    vec4 dLine = mix(mix(d, dSh, haveShallowLine),
                     mix(dSt, max(dSh, dSt), haveShallowLine),
                     haveSteepLine);
    d = mix(d, dLine, doLineBlend);
  }

//#crisp{
#if __VERSION__ >= 300
  if (any(notEqual(iw & uvec4(160u), uvec4(0u))))
  {
    MP vec4 longL = vec4(((iw >> 5u) & 1u) | (((iw >> 7u) & 1u) << 1u));
#endif
    MP vec4 isLong = isCut * doLineBlend * vec4(greaterThan(longL, vec4(0.0)));
    if (dot(isLong, vec4(1.0)) > 0.0)
    {
      float sx2 = scale.x * scale.x, sy2 = scale.y * scale.y;
      vec4 shiftA = vec4(equal(blendResult, vec4(2.0)));
      vec4 ox = (0.5 + shiftA) * haveShallowLine;
      vec4 oy = (0.5 + shiftA) * (1.0 - haveShallowLine);
      vec4 dx = 1.0 + haveShallowLine * (1.0 + longL);
      vec4 dy = 1.0 + haveSteepLine * (1.0 + longL);
      vec4 scX2 = vec4(sx2, sy2, sx2, sy2);
      vec4 scY2 = vec4(sy2, sx2, sy2, sx2);
      vec4 dLong = scArea * ((px - ox) * dy + (py - oy) * dx) * inversesqrt(dx * dx * scX2 + dy * dy * scY2);
      d = mix(d, dLong, isLong);
    }
#if __VERSION__ >= 300
  }
#endif
//#crisp}

  // Exact smoothstep(-INV_SQRT2, INV_SQRT2, d_raw): d is already multiplied by INV_SQRT2.
  // Because sdCornerArc(px, py, r) * scArc <= d_lin wherever d_lin <= -0.5 (Cauchy-Schwarz),
  // any corner already at t == 0 can skip B1-arc and its neighbor fetches bit-exactly.
  MP vec4 t = isCut * clamp(d + 0.5, 0.0, 1.0);
  if (dot(t, vec4(1.0)) <= 1e-4)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }

//#crisp{
  // C1 circular fillets on surviving corners only: plain bevels (0 neighbor fetches)
  // and isolated 45-deg corners meeting flat H & V walls (only the 2 neighbors of the active corner).
  MP float scArc = scK.x * 1.4142135623730951;
  MP vec4 actBev = vec4(greaterThan(t, vec4(0.0))) * (1.0 - doLineBlend);
  if (dot(actBev, vec4(1.0)) > 0.0)
  {
    MP vec4 rBev = max(vec4(0.05), 1.0 - INV_SQRT2 * tip);
    if (actBev.x > 0.5) d.x = sdCornerArc(px.x, py.x, rBev.x) * scArc;
    if (actBev.y > 0.5) d.y = sdCornerArc(px.y, py.y, rBev.y) * scArc;
    if (actBev.z > 0.5) d.z = sdCornerArc(px.z, py.z, rBev.z) * scArc;
    if (actBev.w > 0.5) d.w = sdCornerArc(px.w, py.w, rBev.w) * scArc;
    t = isCut * clamp(d + 0.5, 0.0, 1.0);
  }
#if __VERSION__ >= 300
  uvec4 act45U = uvec4(greaterThan(t, vec4(0.0))) * ((iw >> 2u) & 1u) * uvec4(equal(iw & uvec4(240u), uvec4(0u)));
  if (any(notEqual(act45U, uvec4(0u))))
  {
    if (act45U.x != 0u)
    {
      uvec4 iD = uvec4(INFO_AT(-1.0,  0.0) * 255.0 + 0.5);
      uvec4 iB = uvec4(INFO_AT( 0.0, -1.0) * 255.0 + 0.5);
      if (flat45ArcU(iD.z, iB.z, iD.y, iB.w)) d.x = sdCornerArc(px.x, py.x, 0.5) * scArc;
    }
    if (act45U.y != 0u)
    {
      uvec4 iB = uvec4(INFO_AT( 0.0, -1.0) * 255.0 + 0.5);
      uvec4 iF = uvec4(INFO_AT( 1.0,  0.0) * 255.0 + 0.5);
      if (flat45ArcU(iB.w, iF.w, iB.z, iF.x)) d.y = sdCornerArc(px.y, py.y, 0.5) * scArc;
    }
    if (act45U.z != 0u)
    {
      uvec4 iF = uvec4(INFO_AT( 1.0,  0.0) * 255.0 + 0.5);
      uvec4 iH = uvec4(INFO_AT( 0.0,  1.0) * 255.0 + 0.5);
      if (flat45ArcU(iF.x, iH.x, iF.w, iH.y)) d.z = sdCornerArc(px.z, py.z, 0.5) * scArc;
    }
    if (act45U.w != 0u)
    {
      uvec4 iH = uvec4(INFO_AT( 0.0,  1.0) * 255.0 + 0.5);
      uvec4 iD = uvec4(INFO_AT(-1.0,  0.0) * 255.0 + 0.5);
      if (flat45ArcU(iH.y, iD.y, iH.x, iD.z)) d.w = sdCornerArc(px.w, py.w, 0.5) * scArc;
    }
    t = isCut * clamp(d + 0.5, 0.0, 1.0);
  }
#else
  vec4 act45 = vec4(greaterThan(t, vec4(0.0))) * doLineBlend * (1.0 - haveShallowLine) * (1.0 - haveSteepLine) * vec4(equal(longL, vec4(0.0)));
  if (dot(act45, vec4(1.0)) > 0.0)
  {
    if (act45.x > 0.5)
    {
      vec4 iD = floor(INFO_AT(-1.0,  0.0) * 255.0 + 0.5);
      vec4 iB = floor(INFO_AT( 0.0, -1.0) * 255.0 + 0.5);
      if (flat45ArcF(iD.z, iB.z, iD.y, iB.w)) d.x = sdCornerArc(px.x, py.x, 0.5) * scArc;
    }
    if (act45.y > 0.5)
    {
      vec4 iB = floor(INFO_AT( 0.0, -1.0) * 255.0 + 0.5);
      vec4 iF = floor(INFO_AT( 1.0,  0.0) * 255.0 + 0.5);
      if (flat45ArcF(iB.w, iF.w, iB.z, iF.x)) d.y = sdCornerArc(px.y, py.y, 0.5) * scArc;
    }
    if (act45.z > 0.5)
    {
      vec4 iF = floor(INFO_AT( 1.0,  0.0) * 255.0 + 0.5);
      vec4 iH = floor(INFO_AT( 0.0,  1.0) * 255.0 + 0.5);
      if (flat45ArcF(iF.x, iH.x, iF.w, iH.y)) d.z = sdCornerArc(px.z, py.z, 0.5) * scArc;
    }
    if (act45.w > 0.5)
    {
      vec4 iH = floor(INFO_AT( 0.0,  1.0) * 255.0 + 0.5);
      vec4 iD = floor(INFO_AT(-1.0,  0.0) * 255.0 + 0.5);
      if (flat45ArcF(iH.y, iD.y, iH.x, iD.z)) d.w = sdCornerArc(px.w, py.w, 0.5) * scArc;
    }
    t = isCut * clamp(d + 0.5, 0.0, 1.0);
  }
#endif
  if (dot(t, vec4(1.0)) <= 1e-4)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }
//#crisp}
  MP vec4 ratios = t * t * (3.0 - 2.0 * t);

  // ============================================================================================
  // xBRZ: drawing the corners (0, 90, 180, 270 degrees); neighbor color is fetched only when ratio > 0
  // ============================================================================================
//#crisp{
  MP float sumR = dot(ratios, vec4(1.0));
  if (sumR <= 1e-4)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }
  MP vec4 om = 1.0 - ratios;
  MP float keepE = (om.x * om.y) * (om.z * om.w);
  MP float maxR = max(max(ratios.x, ratios.y), max(ratios.z, ratios.w));
  MP vec4 w = ratios;
  MP float sumW = sumR;
  if (sumR > maxR + 1e-4)
  {
    // Depth-sensitive weighting when 2+ corners overlap at the same output subpixel:
    // prefer the deeper half-plane (larger signed distance d) to prevent AA fringe bleed.
    vec4 dAct = mix(vec4(-1e4), d, isCut);
    float dMax = max(max(dAct.x, dAct.y), max(dAct.z, dAct.w));
    MP vec4 dw = clamp(1.0 - (dMax - d), 0.0, 1.0);
    w = ratios * (dw * dw);
    sumW = dot(w, vec4(1.0));
  }
  MP float wF = w.z * (1.0 - secondPix.z) + w.y * secondPix.y;
  MP float wH = w.z * secondPix.z         + w.w * (1.0 - secondPix.w);
  MP float wB = w.y * (1.0 - secondPix.y) + w.x * secondPix.x;
  MP float wD = w.x * (1.0 - secondPix.x) + w.w * secondPix.w;
  MP vec3 accCol = vec3(0.0);
  if (wF > 0.0) accCol += wF * P( 1., 0.);
  if (wH > 0.0) accCol += wH * P( 0., 1.);
  if (wB > 0.0) accCol += wB * P( 0.,-1.);
  if (wD > 0.0) accCol += wD * P(-1., 0.);
  MP vec3 res = accCol / sumW;
  if (keepE > 1e-4) res = mix(P_CENTER, res, 1.0 - keepE);
  FRAG_OUT = vec4(res, 1.0);
//#crisp}
//#plain   MP vec3 res = P_CENTER;
//#plain   if (ratios.z > 0.0) { vec2 bo = secondPix.z > 0.0 ? vec2( 0., 1.) : vec2( 1., 0.); res = mix(res, P(bo.x, bo.y), ratios.z); }
//#plain   if (ratios.y > 0.0) { vec2 bo = secondPix.y > 0.0 ? vec2( 1., 0.) : vec2( 0.,-1.); res = mix(res, P(bo.x, bo.y), ratios.y); }
//#plain   if (ratios.x > 0.0) { vec2 bo = secondPix.x > 0.0 ? vec2( 0.,-1.) : vec2(-1., 0.); res = mix(res, P(bo.x, bo.y), ratios.x); }
//#plain   if (ratios.w > 0.0) { vec2 bo = secondPix.w > 0.0 ? vec2(-1., 0.) : vec2( 0., 1.); res = mix(res, P(bo.x, bo.y), ratios.w); }
//#plain   FRAG_OUT = vec4(res, 1.0);
}

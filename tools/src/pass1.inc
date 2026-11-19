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
  MP vec4 longL = vec4(((iw >> 5u) & 1u) | (((iw >> 7u) & 1u) << 1u));
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
  vec4 kSh = scK.yzyz;
  vec4 kSt = scK.zyzy;

  vec4 pSum = px + py;
//#crisp{
  vec4 dPlain = (pSum - INV_SQRT2 * tip) * scK.x;
//#crisp}
//#plain   vec4 dPlain = (pSum - INV_SQRT2) * scK.x;
  vec4 dLine45 = (pSum - 0.5) * scK.x;
  vec4 dSh = (px + 2.0 * py - 0.5) * kSh;
  vec4 dSt = (2.0 * px + py - 0.5) * kSt;
  vec4 d = mix(dPlain,
               mix(mix(dLine45, dSh, haveShallowLine),
                   mix(dSt, max(dSh, dSt), haveShallowLine),
                   haveSteepLine),
               doLineBlend);

//#crisp{
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
//#crisp}

  // Exact smoothstep(-INV_SQRT2, INV_SQRT2, d_raw): d is already multiplied by INV_SQRT2
  MP vec4 t = isCut * clamp(d + 0.5, 0.0, 1.0);
  if (dot(t, vec4(1.0)) <= 1e-4)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }
  MP vec4 ratios = t * t * (3.0 - 2.0 * t);

  // ============================================================================================
  // xBRZ: drawing the corners (0, 90, 180, 270 degrees); neighbor color is fetched only when ratio > 0
  // ============================================================================================
//#crisp{
  MP float sumR = ratios.x + ratios.y + ratios.z + ratios.w;
  MP vec3 accCol = vec3(0.0);
  MP float keepE = 1.0;
  if (ratios.z > 0.0) { vec2 bo = secondPix.z > 0.0 ? vec2( 0., 1.) : vec2( 1., 0.); accCol += ratios.z * P(bo.x, bo.y); keepE *= 1.0 - ratios.z; }
  if (ratios.y > 0.0) { vec2 bo = secondPix.y > 0.0 ? vec2( 1., 0.) : vec2( 0.,-1.); accCol += ratios.y * P(bo.x, bo.y); keepE *= 1.0 - ratios.y; }
  if (ratios.x > 0.0) { vec2 bo = secondPix.x > 0.0 ? vec2( 0.,-1.) : vec2(-1., 0.); accCol += ratios.x * P(bo.x, bo.y); keepE *= 1.0 - ratios.x; }
  if (ratios.w > 0.0) { vec2 bo = secondPix.w > 0.0 ? vec2(-1., 0.) : vec2( 0., 1.); accCol += ratios.w * P(bo.x, bo.y); keepE *= 1.0 - ratios.w; }
  MP vec3 res = accCol / sumR;
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

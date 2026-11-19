@include "header_short.inc"
@include "license.inc"

//#crisp{
// Pass 1 of xbrz-crisp (@BACKEND_LABEL@)
//#crisp}
//#plain // Pass 1 of xbrz-freescale-multipass (@BACKEND_LABEL@)
@STAGE_PASS1@

const float INV_SQRT2 = 0.7071067811865475;

float get_left_ratio(vec2 center, vec2 origin, vec2 direction, vec2 scale, float scArea)
{
  vec2 P0 = center - origin;
  vec2 orth = vec2(-direction.y, direction.x);
  vec2 sd = direction * scale;
  float d = scArea * dot(P0, orth) * inversesqrt(dot(sd, sd));
  return smoothstep(-INV_SQRT2, INV_SQRT2, d);
}

// the first pass's decisions for the four corners of the pixel at (x, y) from E; see the decision
// word in pass 0 (BLEND is the blend type, FLAG(r, f) one of its flags)
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
//#crisp{
#define XBRZ_TIPK 0.1  // 23. a loose pixel's tip: the cut line moves out by this
//#crisp}

// Evaluates the coverage ratio of a cut corner in the canonical bottom-right (z) frame; the other
// corners pass pos and scale rotated by multiples of 90 degrees.
float cornerRatio(vec2 p, vec2 sc, float scArea, float doLine, float sh, float st, float bothL
//#crisp{
                  , float tipK, float lg, float shA
//#crisp}
                  )
{
  if (bothL > 0.0)
    return max(get_left_ratio(p, vec2(0.0, 0.25), vec2(2.0, -1.0), sc, scArea),
               get_left_ratio(p, vec2(0.0, 0.5), vec2(1.0, -2.0), sc, scArea));
  vec2 origin = vec2(0.0, INV_SQRT2);
//#crisp{
  origin.y *= tipK;
//#crisp}
  vec2 direction = vec2(1.0, -1.0);
  if (doLine > 0.0)
  {
    origin = sh > 0.0 ? vec2(0.0, 0.25) : vec2(0.0, 0.5);
    direction.x += sh;
    direction.y -= st;
//#crisp{
    if (lg > 0.0)
    {
      if (sh > 0.0) origin = vec2(0.5, 0.0);
      origin += shA * (sh > 0.0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
      direction.x += sh * lg;
      direction.y -= st * lg;
    }
//#crisp}
  }
  return get_left_ratio(p, origin, direction, sc, scArea);
}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping: -|B|-
  //                      D|E|F
  //                      -|H|-

@PASS1_COORDS@

  vec4 rawInfo = INFO(coord);

  // most output pixels have no corner to blend, and only need these two reads
  if (dot(rawInfo, vec4(1.0)) < 0.5 / 255.0)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }

  vec4 info = floor(rawInfo * 255.0 + 0.5);
  // info Mapping: x|y|
  //               w|z|
  vec4 blendResult = BLEND(info);

  // SIMD opposite-quadrant culling: skip corners that cannot mathematically reach subpixel pos
//#crisp{
  float cullLim = 0.5 - 2.916 / min(scale.x, scale.y);
//#crisp}
//#plain   float cullLim = 0.5 - 1.582 / min(scale.x, scale.y);
  vec4 oppX = vec4(-pos.x, -pos.y,  pos.x,  pos.y);
  vec4 oppY = vec4(-pos.y,  pos.x,  pos.y, -pos.x);
  vec4 reach = 1.0 - vec4(lessThanEqual(oppX, vec4(0.0))) * vec4(lessThanEqual(oppY, vec4(0.0)))
                   * vec4(lessThanEqual(oppX + oppY, vec4(cullLim)));
  vec4 activeC = vec4(greaterThan(blendResult, vec4(0.0))) * reach;
  if (dot(activeC, vec4(1.0)) <= 0.0)
  {
    FRAG_OUT = vec4(P_CENTER, 1.0);
    return;
  }

  float scArea = scale.x * scale.y;
//#crisp{
  vec4 tip = 1.0 + XBRZ_TIPK * vec4(equal(blendResult, vec4(3.0)));
//#crisp}
  vec4 doLineBlend = FLAG(info, 4.0);
  vec4 secondPix = FLAG(info, 8.0);
  vec4 haveShallowLine = FLAG(info, 16.0);
  vec4 haveSteepLine = FLAG(info, 64.0);
  vec4 bothLines = doLineBlend * haveShallowLine * haveSteepLine;
//#crisp{
  vec4 longL = FLAG(info, 32.0) + 2.0 * FLAG(info, 128.0);
  vec4 shiftA = vec4(equal(blendResult, vec4(2.0))) * vec4(greaterThan(longL, vec4(0.0)));
  bothLines *= vec4(equal(longL, vec4(0.0)));
  vec3 accCol = vec3(0.0);
  float sumR = 0.0;
  float keepE = 1.0;
  float hits = 0.0;
//#crisp}
//#plain   vec3 res = P_CENTER;

  // ============================================================================================
  // xBRZ: drawing the corners (0, 90, 180, 270 degrees); neighbor color is fetched only when ratio > 0
  // ============================================================================================
  if (activeC.z > 0.5)
  {
    float ratio = cornerRatio(pos, scale, scArea, doLineBlend.z, haveShallowLine.z, haveSteepLine.z, bothLines.z
//#crisp{
                              , tip.z, longL.z, shiftA.z
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.z > 0.0) ? vec2( 0., 1.) : vec2( 1., 0.);
//#crisp{
      accCol += ratio * P(bo.x, bo.y);
      sumR += ratio;
      keepE *= 1.0 - ratio;
      hits += 1.0;
//#crisp}
//#plain       res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (activeC.y > 0.5)
  {
    float ratio = cornerRatio(vec2(-pos.y, pos.x), scale.yx, scArea, doLineBlend.y, haveShallowLine.y, haveSteepLine.y, bothLines.y
//#crisp{
                              , tip.y, longL.y, shiftA.y
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.y > 0.0) ? vec2( 1., 0.) : vec2( 0.,-1.);
//#crisp{
      accCol += ratio * P(bo.x, bo.y);
      sumR += ratio;
      keepE *= 1.0 - ratio;
      hits += 1.0;
//#crisp}
//#plain       res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (activeC.x > 0.5)
  {
    float ratio = cornerRatio(-pos, scale, scArea, doLineBlend.x, haveShallowLine.x, haveSteepLine.x, bothLines.x
//#crisp{
                              , tip.x, longL.x, shiftA.x
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.x > 0.0) ? vec2( 0.,-1.) : vec2(-1., 0.);
//#crisp{
      accCol += ratio * P(bo.x, bo.y);
      sumR += ratio;
      keepE *= 1.0 - ratio;
      hits += 1.0;
//#crisp}
//#plain       res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (activeC.w > 0.5)
  {
    float ratio = cornerRatio(vec2(pos.y, -pos.x), scale.yx, scArea, doLineBlend.w, haveShallowLine.w, haveSteepLine.w, bothLines.w
//#crisp{
                              , tip.w, longL.w, shiftA.w
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.w > 0.0) ? vec2(-1., 0.) : vec2( 0., 1.);
//#crisp{
      accCol += ratio * P(bo.x, bo.y);
      sumR += ratio;
      keepE *= 1.0 - ratio;
      hits += 1.0;
//#crisp}
//#plain       res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

//#crisp{
  vec3 res;
  if (hits < 0.5)
    res = P_CENTER;
  else if (keepE <= 1e-5)
    res = accCol / sumR;
  else
    res = mix(P_CENTER, accCol / sumR, 1.0 - keepE);
  FRAG_OUT = vec4(res, 1.0);
//#crisp}
//#plain   FRAG_OUT = vec4(res, 1.0);
}

@include "header.inc"
@include "license.inc"

//#crisp{
// Pass 1 of xbrz-crisp (@BACKEND_LABEL@)
//#crisp}
//#plain // Pass 1 of xbrz-freescale-multipass (@BACKEND_LABEL@)
@STAGE_PASS1@

float get_left_ratio(vec2 center, vec2 origin, vec2 direction, vec2 scale)
{
  vec2 P0 = center - origin;
  vec2 proj = direction * (dot(P0, direction) / dot(direction, direction));
  vec2 distv = P0 - proj;
  vec2 orth = vec2(-direction.y, direction.x);
  float side = sign(dot(P0, orth));
  float v = side * length(distv * scale);
  return smoothstep(-sqrt(2.0)/2.0, sqrt(2.0)/2.0, v);
}

// the first pass's decisions for the four corners of the pixel at (x, y) from E; see the decision
// word in pass 0 (BLEND is the blend type, FLAG(r, f) one of its flags)
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
//#crisp{
#define XBRZ_TIPK 0.1  // 23. a loose pixel's tip: the cut line moves out by this
//#crisp}

// Evaluates the coverage ratio of a cut corner in the canonical bottom-right (z) frame; the other
// corners pass pos and scale rotated by multiples of 90 degrees.
float cornerRatio(vec2 p, vec2 sc, float doLine, float sh, float st, float bothL
//#crisp{
                  , float tipK, float lg, float shA
//#crisp}
                  )
{
  vec2 origin = vec2(0.0, 1.0 / sqrt(2.0));
//#crisp{
  origin *= tipK;
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
  float ratio = get_left_ratio(p, origin, direction, sc);
  if (bothL > 0.0)
    ratio = max(get_left_ratio(p, vec2(0.0, 0.25), vec2(1.0, -1.0) + vec2(1.0, 0.0), sc),
                get_left_ratio(p, vec2(0.0, 0.5), vec2(1.0, -1.0) + vec2(0.0, -1.0), sc));
  return ratio;
}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping: -|B|-
  //                      D|E|F
  //                      -|H|-

@PASS1_COORDS@

  vec4 info = INFO_AT(0.0, 0.0);
  vec3 E = P( 0., 0.);
  vec3 res = E;

  // info Mapping: x|y|
  //               w|z|
  vec4 blendResult = BLEND(info);

  // most output pixels have no corner to blend, and only need these two reads
  if (blendResult.x + blendResult.y + blendResult.z + blendResult.w <= 0.0)
  {
    FRAG_OUT = vec4(res, 1.0);
    return;
  }

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
//#crisp}

  // ============================================================================================
  // xBRZ: drawing the corners (0, 90, 180, 270 degrees); neighbor color is fetched only when ratio > 0
  // ============================================================================================
  if (blendResult.z > 0.0)
  {
    float ratio = cornerRatio(pos, scale, doLineBlend.z, haveShallowLine.z, haveSteepLine.z, bothLines.z
//#crisp{
                              , tip.z, longL.z, shiftA.z
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.z > 0.0) ? vec2( 0., 1.) : vec2( 1., 0.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.y > 0.0)
  {
    float ratio = cornerRatio(vec2(-pos.y, pos.x), scale.yx, doLineBlend.y, haveShallowLine.y, haveSteepLine.y, bothLines.y
//#crisp{
                              , tip.y, longL.y, shiftA.y
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.y > 0.0) ? vec2( 1., 0.) : vec2( 0.,-1.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.x > 0.0)
  {
    float ratio = cornerRatio(-pos, scale, doLineBlend.x, haveShallowLine.x, haveSteepLine.x, bothLines.x
//#crisp{
                              , tip.x, longL.x, shiftA.x
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.x > 0.0) ? vec2( 0.,-1.) : vec2(-1., 0.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.w > 0.0)
  {
    float ratio = cornerRatio(vec2(pos.y, -pos.x), scale.yx, doLineBlend.w, haveShallowLine.w, haveSteepLine.w, bothLines.w
//#crisp{
                              , tip.w, longL.w, shiftA.w
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (secondPix.w > 0.0) ? vec2(-1., 0.) : vec2( 0., 1.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  FRAG_OUT = vec4(res, 1.0);
}

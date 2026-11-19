@include "header_short.inc"
@include "license.inc"

//#crisp{
// Pass 1 of xbrz-crisp (@BACKEND_LABEL@)
//#crisp}
//#plain // Pass 1 of xbrz-freescale-multipass (@BACKEND_LABEL@)
@STAGE_PASS1@

float get_left_ratio(vec2 center, vec2 origin, vec2 direction, vec2 scale)
{
  vec2 P0 = center - origin;
  vec2 orth = vec2(-direction.y, direction.x);
  vec2 sd = direction * scale;
  float d = (scale.x * scale.y) * dot(P0, orth) * inversesqrt(dot(sd, sd));
  return smoothstep(-sqrt(2.0) / 2.0, sqrt(2.0) / 2.0, d);
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
float cornerRatio(vec2 p, vec2 sc, float w
//#crisp{
                  , float b
//#crisp}
                  )
{
  if (FLAG(w, 4.0) <= 0.0)
  {
    float tipY = 1.0 / sqrt(2.0);
//#crisp{
    if (b > 2.5) tipY *= 1.0 + XBRZ_TIPK;
//#crisp}
    return get_left_ratio(p, vec2(0.0, tipY), vec2(1.0, -1.0), sc);
  }
  float sh = FLAG(w, 16.0);
  float st = FLAG(w, 64.0);
//#crisp{
  float lg = FLAG(w, 32.0) + 2.0 * FLAG(w, 128.0);
  if (sh > 0.0 && st > 0.0 && lg <= 0.0)
//#crisp}
//#plain   if (sh > 0.0 && st > 0.0)
    return max(get_left_ratio(p, vec2(0.0, 0.25), vec2(2.0, -1.0), sc),
               get_left_ratio(p, vec2(0.0, 0.5), vec2(1.0, -2.0), sc));
  vec2 origin = sh > 0.0 ? vec2(0.0, 0.25) : vec2(0.0, 0.5);
  vec2 direction = vec2(1.0 + sh, -1.0 - st);
//#crisp{
  if (lg > 0.0)
  {
    if (sh > 0.0) origin = vec2(0.5, 0.0);
    if (abs(b - 2.0) < 0.5)
      origin += sh > 0.0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    direction.x += sh * lg;
    direction.y -= st * lg;
  }
//#crisp}
  return get_left_ratio(p, origin, direction, sc);
}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping: -|B|-
  //                      D|E|F
  //                      -|H|-

@PASS1_COORDS@

  vec4 rawInfo = INFO(coord);
  vec3 E = P( 0., 0.);

  // most output pixels have no corner to blend, and only need these two reads
  if (dot(rawInfo, vec4(1.0)) < 0.5 / 255.0)
  {
    FRAG_OUT = vec4(E, 1.0);
    return;
  }

  vec4 info = floor(rawInfo * 255.0 + 0.5);
  // info Mapping: x|y|
  //               w|z|
  vec4 blendResult = BLEND(info);
  if (dot(blendResult, vec4(1.0)) < 0.5)
  {
    FRAG_OUT = vec4(E, 1.0);
    return;
  }

  vec3 res = E;
  // Conservative opposite-quadrant culling threshold: provably ratio == 0 for all cut slopes and scales.
//#crisp{
  vec2 cut = vec2(0.075) - (sqrt(2.0) / 2.0) / scale;
//#crisp}
//#plain   vec2 cut = vec2(0.15) - (sqrt(2.0) / 2.0) / scale;

  // ============================================================================================
  // xBRZ: drawing the corners (0, 90, 180, 270 degrees); flags are unpacked lazily and neighbor
  // color is fetched only when ratio > 0
  // ============================================================================================
  if (blendResult.z > 0.0 && (pos.x >= cut.x || pos.y >= cut.y))
  {
    float ratio = cornerRatio(pos, scale, info.z
//#crisp{
                              , blendResult.z
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (FLAG(info.z, 8.0) > 0.0) ? vec2( 0., 1.) : vec2( 1., 0.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.y > 0.0 && (pos.x >= cut.x || pos.y <= -cut.y))
  {
    float ratio = cornerRatio(vec2(-pos.y, pos.x), scale.yx, info.y
//#crisp{
                              , blendResult.y
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (FLAG(info.y, 8.0) > 0.0) ? vec2( 1., 0.) : vec2( 0.,-1.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.x > 0.0 && (pos.x <= -cut.x || pos.y <= -cut.y))
  {
    float ratio = cornerRatio(-pos, scale, info.x
//#crisp{
                              , blendResult.x
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (FLAG(info.x, 8.0) > 0.0) ? vec2( 0.,-1.) : vec2(-1., 0.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  if (blendResult.w > 0.0 && (pos.x <= -cut.x || pos.y >= cut.y))
  {
    float ratio = cornerRatio(vec2(pos.y, -pos.x), scale.yx, info.w
//#crisp{
                              , blendResult.w
//#crisp}
                              );
    if (ratio > 0.0)
    {
      vec2 bo = (FLAG(info.w, 8.0) > 0.0) ? vec2(-1., 0.) : vec2( 0., 1.);
      res = mix(res, P(bo.x, bo.y), ratio);
    }
  }

  FRAG_OUT = vec4(res, 1.0);
}

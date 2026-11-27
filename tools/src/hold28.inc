// ---- Rule 28: shared hold-score & tie-breaker helpers (used by resolve and match passes) ----
#define XBRZ_HOLD_SAME 30.0 // a neighbor this close in color holds a pixel

float held28(vec3 a, vec3 b) { return float(withinEqY255(a, b, XBRZ_HOLD_SAME)); }
// How firmly pixel c is held by its 8 neighbors (cardinal neighbors count twice)
float holdOf28(vec3 c, vec3 tl, vec3 t, vec3 tr, vec3 l, vec3 r, vec3 bl, vec3 b, vec3 br)
{
  return held28(c, tl) + held28(c, tr) + held28(c, bl) + held28(c, br)
       + 2.0 * (held28(c, t) + held28(c, l) + held28(c, r) + held28(c, b));
}
// Lazy-ring hold score for an edge neighbor: fetches outer 3 texels only when the 5 inner texels can tie/flip hE
float holdOfEdge28(vec3 c, float hE, vec3 in0, vec3 in1, vec3 in2, vec3 in3, vec3 in4, vec2 o0, vec2 o1, vec2 o2)
{
  float hIn = held28(c, in0) + held28(c, in1) + 2.0 * (held28(c, in2) + held28(c, in3) + held28(c, in4));
  if (hE > hIn + 4.5 || hIn > hE + 0.5) return hIn;
  return hIn + held28(c, toYCbCr(P(o0.x, o0.y))) + 2.0 * held28(c, toYCbCr(P(o1.x, o1.y))) + held28(c, toYCbCr(P(o2.x, o2.y)));
}
float tie28(vec3 e, vec3 n)
{
  if (abs(e.x - n.x) > SAFE_EPS) return float(e.x < n.x);
  if (abs(e.y - n.y) > SAFE_EPS) return float(e.y < n.y);
  return float(e.z < n.z);
}
// Returns per-corner mask of crossing 2:1 cuts that stay whole (higher hold score, or darker on tie)
vec4 dropCross28(vec4 pair, vec4 sec, vec3 E, vec3 A, vec3 B, vec3 C, vec3 D, vec3 F, vec3 G, vec3 H, vec3 I)
{
  float hE = holdOf28(E, A, B, C, D, F, G, H, I), hB = 0.0, hD = 0.0, hF = 0.0, hH = 0.0;
  if (pair.x * sec.x + pair.y * (1.0 - sec.y) > 0.5) hB = holdOfEdge28(B, hE, D, F, A, C, E, vec2(-1.,-2.), vec2( 0.,-2.), vec2( 1.,-2.));
  if (pair.x * (1.0 - sec.x) + pair.w * sec.w > 0.5) hD = holdOfEdge28(D, hE, B, H, A, E, G, vec2(-2.,-1.), vec2(-2., 0.), vec2(-2., 1.));
  if (pair.y * sec.y + pair.z * (1.0 - sec.z) > 0.5) hF = holdOfEdge28(F, hE, B, H, C, E, I, vec2( 2.,-1.), vec2( 2., 0.), vec2( 2., 1.));
  if (pair.z * sec.z + pair.w * (1.0 - sec.w) > 0.5) hH = holdOfEdge28(H, hE, D, F, E, G, I, vec2(-1., 2.), vec2( 0., 2.), vec2( 1., 2.));
  vec4 hN = mix(vec4(hD, hB, hF, hH), vec4(hB, hF, hH, hD), sec);
  vec4 tie = vec4(tie28(E, sec.x > 0.5 ? B : D), tie28(E, sec.y > 0.5 ? F : B),
                  tie28(E, sec.z > 0.5 ? H : F), tie28(E, sec.w > 0.5 ? D : H));
  vec4 whole = max(vec4(greaterThan(vec4(hE), hN + 0.5)),
                   vec4(lessThan(abs(hE - hN), vec4(0.5))) * tie);
  return pair * whole;
}

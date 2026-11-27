// Rec. 2020 luma weights and chroma difference scales, shared across passes
const vec3 LUMA_W = vec3(0.2627, 0.6780, 0.0593);
const float SCALE_B = 0.5 / (1.0 - 0.0593);
const float SCALE_R = 0.5 / (1.0 - 0.2627);

// Linear RGB -> YCbCr conversion so cached neighborhood texels convert once and
// subsequent squared distances reduce to dot(d, d) (6 ops vs 13 ops), luma to c.x.
vec3 toYCbCr(vec3 c)
{
  float Y = dot(c, LUMA_W);
  return vec3(Y, SCALE_B * (c.b - Y), SCALE_R * (c.r - Y));
}

float distSqY(vec3 a, vec3 b)
{
  vec3 d = a - b;
  return dot(d, d);
}

// Squared threshold in [0..255] YCbCr units, kept in [0..1.5] so GLSL ES mediump never overflows.
// Implemented as a function (not a macro) so older glslang preprocessors (RetroArch Vulkan/Slang)
// never double-expand self-referential `#define XBRZ_* global.XBRZ_*` arguments into `global.global.*`.
float SQ255(float x)
{
  float t = x / 255.0;
  return t * t;
}
// FP16-safe division guard (> 6.1e-5 smallest FP16 normal) so FTZ GPUs never produce NaN
const float SAFE_EPS = 1e-4;

bool withinY255(vec3 a, vec3 b, float lim)
{
  return distSqY(a, b) < SQ255(lim);
}

bool withinEqY255(vec3 a, vec3 b, float lim)
{
  return distSqY(a, b) <= SQ255(lim);
}

// Unified geometric AA-ramp test from squared pairwise color distances (a2, b2, c2):
// returns 1.0 when the middle color projects strictly onto the segment of length sqrt(c2)
// and its exact perpendicular distance sits within min(relLim * sqrt(c2), absLim255/255).
// Exact D4-symmetric in (a2, b2) and sqrt-free (reuses squared distances already in registers).
vec4 geomRamp4(vec4 a2, vec4 b2, vec4 c2, float relLim, float absLim255)
{
  vec4 diff2 = a2 - b2;
  vec4 safeC2 = max(c2, vec4(SAFE_EPS));
  vec4 mono = vec4(lessThan(abs(diff2), c2));
  vec4 perpSq = max(vec4(0.0), 0.5 * (a2 + b2) - 0.25 * c2 - (diff2 * diff2) / (4.0 * safeC2));
  vec4 limSq = min(vec4(SQ255(absLim255)), (relLim * relLim) * c2);
  return mono * vec4(lessThanEqual(perpSq, limSq));
}


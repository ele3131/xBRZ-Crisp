// Rec. 2020 luma weights and chroma difference scales, shared across passes
const vec3 LUMA_W = vec3(0.2627, 0.6780, 0.0593);
const float SCALE_B = 0.5 / (1.0 - 0.0593);
const float SCALE_R = 0.5 / (1.0 - 0.2627);

float luma(vec3 c) { return dot(c, LUMA_W); }

float distSqYCbCr(vec3 pixA, vec3 pixB)
{
  vec3 diff = pixA - pixB;
  float Y = dot(diff, LUMA_W);
  float Cb = SCALE_B * (diff.b - Y);
  float Cr = SCALE_R * (diff.r - Y);
  return (Y * Y) + (Cb * Cb) + (Cr * Cr);
}

float distYCbCr(vec3 pixA, vec3 pixB)
{
  return sqrt(distSqYCbCr(pixA, pixB));
}

float dist255(vec3 pixA, vec3 pixB)
{
  return distYCbCr(pixA, pixB) * 255.0;
}

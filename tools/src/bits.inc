// Decision-word bit layout (0..255 per corner: x = TL, y = TR, z = BR, w = BL):
//   bits 0..1 (BLEND): 0 = none, 1 = normal, 2 = dominant (pass0) / thin sliver R14 (resolve+), 3 = weak (pass0) / small tip R23/R40 (resolve+)
//   bit  2 (  4.0): BIT_LINE    - line blend (45-deg unless BIT_SHALLOW or BIT_STEEP is also set)
//   bit  3 (  8.0): BIT_SEC     - blend with second candidate neighbor (B, F, H, D instead of D, B, F, H)
//   bit  4 ( 16.0): BIT_SHALLOW - shallow 2:1 (or 3:1 / 4:1 when paired with BIT_LONG3 / BIT_LONG4)
//   bit  5 ( 32.0): BIT_TONE    - pass0: hue-weighted-only line (rule 9); resolve+: BIT_LONG3 (3:1 slope) or BIT_ARC45 (isolated flat-wall 45-deg arc, match->pass1)
//   bit  6 ( 64.0): BIT_STEEP   - steep 2:1 (or 3:1 / 4:1 when paired with BIT_LONG3 / BIT_LONG4)
//   bit  7 (128.0): BIT_BLOCKED - pass0: diagonal-limit blocked (rule 2); resolve+: BIT_LONG4 (4:1 slope); BIT_LONG3+BIT_LONG4 (160) on 2:1 = BIT_ARC21 (C1 flat->2:1->45-deg curve)
#define BIT_LINE    4.0
#define BIT_SEC     8.0
#define BIT_SHALLOW 16.0
#define BIT_TONE    32.0
#define BIT_LONG3   32.0
#define BIT_ARC45   32.0
#define BIT_ARC21   160.0
#define BIT_STEEP   64.0
#define BIT_BLOCKED 128.0
#define BIT_LONG4   128.0

#define BLEND(r)   mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)

// Corner decision-word masks (values in 0..255)
vec4 cut4(vec4 w)        { return vec4(greaterThan(BLEND(w), vec4(0.0))); }
// A cut that is neither weak (blend 3) nor blocked (bit 128)
vec4 activeCutOf(vec4 w) { vec4 bl = BLEND(w); return vec4(greaterThan(bl, vec4(0.0))) * vec4(lessThan(bl, vec4(3.0))) * vec4(lessThan(w, vec4(BIT_BLOCKED))); }
// A cut that is not weak (blend 3); keeps blocked (bit 128) when resolve may still rescue it
vec4 cutNoWeak(vec4 w)   { vec4 bl = BLEND(w); return vec4(greaterThan(bl, vec4(0.0))) * vec4(lessThan(bl, vec4(3.0))); }
vec4 drawsLine4(vec4 r)  { return activeCutOf(r) * FLAG(r, BIT_LINE); }
vec4 isLine45(vec4 r)    { return FLAG(r, BIT_LINE) * (1.0 - FLAG(r, BIT_SHALLOW)) * (1.0 - FLAG(r, BIT_STEEP)) * vec4(equal(FLAG(r, BIT_LONG3) + FLAG(r, BIT_LONG4), vec4(0.0))); }
float wordPlain(bool sec)  { return sec ? (1.0 + BIT_SEC) : 1.0; }
float wordLine45(bool sec) { return sec ? (1.0 + BIT_LINE + BIT_SEC) : (1.0 + BIT_LINE); }

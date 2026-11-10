//#crisp{
// xBRZ crisp: xBRZ freescale that only rounds corners between clearly different colors.
//
// This is xbrz-freescale-multipass with a minimum contrast (rule 1) of 20: tools/make-multipass.py
// writes that shader, dropping the lines between //#crisp{ and //#crisp} and turning the //#plain
// lines on.
//#crisp}
//#plain // xBRZ freescale, multipass: xBRZ at any scale factor, in three passes.
//#plain //
//#plain // Rules 2, 4 to 7 and 10 below keep xBRZ from cutting corners into shapes the artist did not
//#plain // draw (fake diagonals at junctions of three colors, bent frames, rounded ends of stripes, a pixel
//#plain // closed between outlines). They are on by default; XBRZ_DIAG = 0 turns them off, for the
//#plain // reference xBRZ shapes. Rules 1, 3, 8, 9 and 11 to 13 are the crisp look and run with XBRZ_MINC
//#plain // above 0; the xbrz-crisp preset sets it to 20, so low-contrast shading and textures keep their pixels.
//
// xBRZ decides, for each corner of each pixel, whether to cut it and how (a corner piece, a 45-degree
// line, or a shallow or steep line). The rules below then change some of those decisions. Each rule
// has a section of the same number and name in the code. The first pass (pass 0) makes the decisions,
// the resolve pass, also once per game pixel, finishes rules 1, 2 and 9, which need the neighbours'
// decisions, and the output pass (pass 1) only draws the corners.
//
// 1. Minimum contrast (XBRZ_MINC): a corner whose two colors differ by less than XBRZ_MINC (x/255,
//    YCbCr distance) is left square, so low-contrast shading, dithering and textures (grass,
//    foliage, stone) keep their pixel detail, while outlines, text and sprites are smoothed as in
//    xBRZ. A corner up to 4 below the limit is weak: it is still rounded when the same corner of both
//    neighbours along its cut is rounded, so a diagonal edge has no tooth where its contrast dips.
// 2. Diagonal limit (XBRZ_DIAG): a corner is blocked when the two colors on its diagonal (the colors
//    the cut would join) differ by more than XBRZ_DIAG, so a junction of three different colors is
//    not pulled into a fake diagonal (an idea from torcado's cleanEdge, MIT license).
//    Antialiasing ramps, where one of those colors sits between the pixel and the other one, use 92.
//    A corner is not blocked:
//    - on a shallow or steep line, unless it would cut a pixel with a lighter color, so dark
//      outlines, eyes and eyebrows keep their pixels;
//    - at the tip of a 1-pixel diagonal stripe, so the stripe runs on to the edge;
//    - between two close inner tones next to an outline darker than both, so the cut runs up to the
//      outline, which stays whole (not at the corner of a solid block, along a 1-pixel stripe or next
//      to a corner the artist already rounded with an antialiasing pixel).
//    A blocked corner whose blend color runs straight on, like a frame or a horizontal line, stays
//    square, so lines do not bend where they meet. Any other blocked corner is cut by the resolve pass
//    only where it continues a cut: when a neighbour on the same diagonal is cut, so lines are drawn
//    to the end, or when the neighbour across its edge cuts the other end of that edge with a line in
//    the pixel's color, so the two cuts make one diagonal that ends on a straight edge, like the tip
//    of a lock of hair (that line may also run toward the pixel diagonal to E when it has E's color,
//    so a thin arm closes up to the next color).
// 3. Eye: where two dark strokes of different colors meet in an L around a 1-pixel light gap, like
//    a pupil under an eyebrow, the corner stays square. Not where one stroke ends in the other's
//    color, like a shaded outline: that is one outline, cut as in xBRZ.
// 4. Diagonal up to the wall: a corner changed by rules 2 and 3 comes back as in xBRZ where the
//    pixel's color runs on as a 45-degree diagonal along the cut up to a straight line, like hair or
//    a fence post, unless that would bend a straight line or stretch a lone 1-pixel dot.
// 5. Thin light stroke: it also comes back where a 1-pixel stroke lighter than both colors runs on
//    along the cut, like the white strokes of letters.
// 6. Antialiasing notch: and where a single antialiasing pixel steps along a diagonal edge between
//    two colors, like the shaded edge of a cape.
// 7. Stripe ends: where a stack of 1- or 2-pixel stripes of different colors ends flush, like the
//    bars of a gauge or a striped wall, the end corners stay square when their diagonal colors differ
//    by more than 36, so every stripe ends the same way. A line that turns diagonal at its end is
//    not a stripe end. A stripe only 3 pixels long is left alone when the color past its end
//    runs straight on, like a line meeting it. Nor is a pixel whose side neighbour is a close tone of
//    it, where the end corner is a line between two outline colors darker than it, like a dark outline
//    turning diagonal over a forehead.
// 8. Line through an antialiasing pixel: when a line cuts one corner of a pixel whose color lies
//    between the line's two colors on a strong edge, and rule 1 left the opposite corner square, that
//    corner is cut too, as in xBRZ, so the pixel becomes a thin strip of the diagonal instead of a
//    notch in it.
// 9. Line shapes: the shallow and steep line tests weigh hue a little more than lightness (1.2x), so
//    lines in hue-shifted shading follow the artist's pixels. A line xBRZ finds is kept too, unless it
//    would bring back a corner blocked by rule 2 or the line's color runs on along a 45-degree
//    diagonal in the same color. Where a line found only by the hue weighting, between two
//    different colors, would run into the line of the neighbour across the same edge, it is drawn
//    as in xBRZ. A line found only by the hue weighting is not drawn where the pixel at its far end is
//    closer to the pixel's own color than to the line's, so a diagonal of that color is not cut short
//    (Goku's brow in Buu's Fury), nor where its two colors clearly differ and the line's color runs on
//    along a 45-degree diagonal in the same color (the tip of Goku's nose).
// 10. Pixel closed between outlines: a pixel closed in a straight row between two pixels of a
//     near-black outline that also wraps the corner, like the brown brow between the black lines of
//     Link's eye, is not pulled toward E by a line through the outline; that corner stays square.
// 11. Lines in a larger window: a corner that rule 1 left square is still cut as in xBRZ where it lies
//     on a straight line (45 degrees or 2:1, with regular steps) between two stripes that run on for
//     5 pixels or more, one of them 1 pixel wide against a strong contour, like the inner side of an
//     outline's antialiasing band or the stripes of a bar, so those lines have no teeth.
// 12. Closed shadow: where a near-black shadow runs under an object, like the round shadow under a
//     character's feet, the background pixel in the notch between them gets a wedge of the shadow's
//     color and the shadow's corners next to the notch stay square, so the shadow's outline closes.
//     The shape is read in a 7x7 window (an arm 3 pixels long with background outside it, a solid
//     2x2 lobe, an object bigger than 1 pixel), so serifs, letters and textures are left alone.
//     The floor around the notch may have any color or texture (grass, tiles): it only has to be
//     lighter than the shadow and differ from both the shadow and the object.
// 13. Tiles between walls: in a row of 1-pixel tiles (4 or more, in a repeating pattern) that runs
//     between two straight walls, like the squares of a gauge, a blocked corner between two tiles
//     stays square, so no diagonal is chained through the row.
//#crisp{
// 14. Straight steps: where an edge between two clearly different colors (XBRZ_STRAIGHT) climbs in
//     regular steps of 2 to 6 pixels, along a 1-pixel stroke with one side in a single color (or a
//     dark stroke whose sides take only two lighter colors, like the shadow of a letter between the
//     letter and its background) or between two single colors, like the italic stems of a font, a
//     rail or an outline,
//     the corner at each step is cut with one line of the steps' slope (2:1, 3:1, or 4:1 for steps of
//     4 to 6; xBRZ only draws 45 degrees and 2:1), and with steps of 3 or more the corner next to the
//     step at the thin end gets a sliver of that line. Both sides of a stroke then run parallel and a
//     long step does not bend. Runs of 7 or more, irregular steps and low-contrast edges (water,
//     wood, shading) keep xBRZ's lines.
// 15. Lone pixel and L-shape tests on strong edges: xBRZ draws no line through a pixel that already
//     has another corner cut and differs from the pixel across it, so a lone pixel keeps its shape, and
//     only rounds a corner, without a line, where one color wraps around it in an L. Where the pixel
//     differs from both colors of the corner by 64 or more (54 for the L), these tests use the reference
//     xBRZ tolerance (30) instead of XBRZ_TOL, so a light pixel close to its background is cut, and a
//     light tip is rounded, as in the reference xBRZ, like Isaac's leg in Golden Sun; textures and
//     shading keep XBRZ_TOL.
// 16. Line in another color: where xBRZ draws a line through a lone pixel along a pair of one color
//     but paints the corner with the other neighbor's color, which differs from the line's by more
//     than XBRZ_TINT and does not lie on an antialiasing ramp with it, the corner stays square when
//     the line is lighter than the pixel or the pixel sits in a straight line of one color (its two
//     opposite neighbors match, like the stripes of a background), and otherwise the line is drawn at
//     45 degrees in its own color. A single pixel keeps its shape instead of being pierced by a spike
//     of a third color, like the wine pixel at a junction of four colors in Golden Sun's village.
// 17. A line drawn on one side only: where xBRZ cuts a corner with a line between two lone pixels
//     (neither goes on along the line and the pixel's own color does not repeat along it) but the
//     pixel across the line draws the same line in the first pixel's color, and the three colors are
//     not an antialiasing ramp, the corner stays square, so the line does not stick a spike into the
//     pixel, like the light gray pixel under the pot in Golden Sun's village.
// 18. Outlines closed: the line of rule 16 is also drawn in its own color through a pixel that is not
//     lone, where that line is a near-black outline (XBRZ_TINT_DARK) darker than the pixel, so an
//     outline that steps by a knight's move stays closed instead of letting the colors on both sides
//     touch, like a black outline between yellow and pink on a fighter's sprite.
// 19. A pixel apart keeps to itself: a corner is not painted with the color of a pixel that differs from
//     all 8 of its neighbors by XBRZ_ISO or more and keeps its own corners square, so a lone dot of
//     color, like the bead of a bracelet in Golden Sun's village, does not leak into the pixels around it.
// 20. A corner where no edge runs: a corner between two neighbors of clearly different colors
//     (XBRZ_JUNCTION) stays square where no line goes on through it (neither color continues past the
//     corner, the pixel's own color does not continue along the cut, and fewer than three pixels in a
//     row cut that corner), so a pixel at a junction of several colors keeps its square shape, while
//     antialiased curves, whose cuts run on, stay round. A corner on a dark outline with an
//     antialiasing pixel is still cut: the pixel and its two neighbors form a ramp (XBRZ_JUNC_RAMP),
//     the darkest of them is dark, and one neighbor's color goes on just past the other along the cut,
//     like the outline of a neck that runs on behind its transition pixel.
// 21. A straight line does not bend: a corner is not painted with the color of a pixel that lies in a
//     straight line of three of its color along the pixel's side, where the corner's other neighbor
//     differs from that line by more than XBRZ_LINE_SIDE, so the line goes on straight instead of
//     bending into the pixel, and checkered patterns keep their squares. A strong thin line of four that
//     starts beside the pixel and runs toward the corner counts too, and where the other neighbor is darker
//     and goes on along the cut, the corner takes that neighbor's color instead of staying square.
// 22. Crossed cuts: where two neighboring pixels of close but distinct shades cut into each other from the two ends
//     of their shared side, the lighter one ends a 45-degree stripe of its color and the darker one
//     stands apart from its other neighbors, both corners stay square, so the darker shade does not
//     bulge into the stripe and the side between them is straight; the darker pixel then leaks no
//     round tip into the pixel past the stripe's end either.
// XBRZ_DIAG = 0 turns rules 2 to 7, 9, 10, 12 and 13 off, and XBRZ_MINC = 0 turns rules 1, 3, 8, 9 and
// 11 to 22 off, so with XBRZ_MINC at 0 only rules 2, 4 to 7 and 10 run.
//#crisp}
//#plain // XBRZ_DIAG = 0 turns rules 2 to 7, 9, 10, 12 and 13 off, and XBRZ_MINC = 0 turns rules 1, 3, 8, 9 and
//#plain // 11 to 13 off, so with XBRZ_MINC at 0 only rules 2, 4 to 7 and 10 run.
//
// The first pass makes every blend decision once per input pixel (blend type, line type, blend
// color and the minimum contrast) and the resolve pass, also once per input pixel, settles the
// ones that depend on the neighbours' decisions, so the output pass, which runs once per output
// pixel, only reads two textures where no corner is cut. Blend color ties and the order of the
// four corners follow the reference C++ xBRZ, and the output pass reads the image from the pass
// before xBRZ, so it also works after other shaders in a preset.
// Defaults: equal color tolerance 15, dominant direction 3.8, steep/shallow line 3.2
// (reference xBRZ: 30, 3.6 and 2.2).
/*
   Hyllian's xBR-vertex code and texel mapping
   Copyright (C) 2011/2016 Hyllian - sergiogdb@gmail.com
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:
   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.
*/
// This shader also uses code and/or concepts from xBRZ as it appears
// in the Desmume source code. The license for which is as follows:
// ****************************************************************************
// * This file is part of the HqMAME project. It is distributed under         *
// * GNU General Public License: http://www.gnu.org/licenses/gpl-3.0          *
// * Copyright (C) Zenju (zenju AT gmx DOT de) - All Rights Reserved          *
// *                                                                          *
// * Additionally and as a special exception, the author gives permission     *
// * to link the code of this program with the MAME library (or with modified *
// * versions of MAME that use the same license as MAME), and distribute      *
// * linked combinations including the two. You must obey the GNU General     *
// * Public License in all respects for all of the code used other than MAME. *
// * If you modify this file, you may extend this exception to your version   *
// * of the file, but you are not obligated to do so. If you do not wish to   *
// * do so, delete this exception statement from your version.                *
// ****************************************************************************

//#crisp{
// Resolve pass of xbrz-crisp (OpenGL / GLES): once per input pixel, between pass 0 and pass 1
//#crisp}
//#plain // Resolve pass of xbrz-freescale-multipass (OpenGL / GLES)

//#crisp{
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
//#crisp}
#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 COL0;
COMPAT_VARYING vec4 TEX0;

uniform mat4 MVPMatrix;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    TEX0.xy = TexCoord.xy * 1.0001;
}

#elif defined(FRAGMENT)

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out COMPAT_PRECISION vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;
#define vTexCoord TEX0.xy
#define FRAG_OUT FragColor
//#crisp{
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float XBRZ_MINC;
#else
#define XBRZ_MINC 20.0
#endif
//#crisp}

// the input of the first pass, which is the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev2Texture;
uniform COMPAT_PRECISION vec2 PassPrev2TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev2InputSize;
#define OUT_SIZE OutputSize
#define ORIG_SIZE vec4(PassPrev2TextureSize, 1.0 / PassPrev2TextureSize)
#define ORIG_INPUT_SIZE PassPrev2InputSize
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
#define P(x,y) COMPAT_TEXTURE(PassPrev2Texture, ocoord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, uv)
#define INFO_STEP SRC_SIZE.zw

float distYCbCr(vec3 pixA, vec3 pixB)
{
  const vec3 w = vec3(0.2627, 0.6780, 0.0593);
  vec3 diff = pixA - pixB;
  float Y = dot(diff, w);
  float Cb = 0.5 / (1.0 - 0.0593) * (diff.b - Y);
  float Cr = 0.5 / (1.0 - 0.2627) * (diff.r - Y);
  return sqrt(Y * Y + Cb * Cb + Cr * Cr);
}

// the first pass's decisions for the four corners of the pixel at (x, y) from E; see the decision
// word in pass 0 (BLEND is the blend type, FLAG(r, f) one of its flags)
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)

//#crisp{
// ---- 14. Straight steps ----
#define XBRZ_STRAIGHT 64.0   // 14. minimum contrast (x/255) of a straightened edge
vec2 stepBase = vec2(0.0);
vec3 PS(vec2 v) { return COMPAT_TEXTURE(PassPrev2Texture, stepBase + ORIG_SIZE.zw * v).rgb; }
bool sameTone(vec3 a, vec3 b) { return distYCbCr(a, b) * 255.0 <= 20.0; }
#define XBRZ_DARK 0.3       // 14. a stroke this dark (luma) or darker may have two lighter side colors
#define XBRZ_LONE_RAMP 1.4 // 17. not a ramp: d(L,E) + d(E,O) above this times d(L,O)
#define XBRZ_ISO 40.0      // 19. a pixel this far (x/255) from all 8 of its neighbors keeps out of their corners
#define XBRZ_JUNCTION 40.0 // 20. two neighbors this far apart (x/255) do not make one edge across a corner
#define XBRZ_JUNC_NEAR 20.0 // 20. a color this close (x/255) to the next pixel goes on along the cut
#define XBRZ_JUNC_RAMP 1.06 // 20. not a junction but a ramp: the two shorter distances of E and its two neighbors add up to less than this times the longest
#define XBRZ_LINE_SIDE 25.0 // 21. the other neighbor of a corner differs from a straight line by this (x/255)
// 19. 1.0 when the pixel c differs from all 8 of its neighbors by XBRZ_ISO or more
float isoOf(vec3 c, vec3 n0, vec3 n1, vec3 n2, vec3 n3, vec3 n4, vec3 n5, vec3 n6, vec3 n7)
{
  float m = min(min(min(distYCbCr(c, n0), distYCbCr(c, n1)), min(distYCbCr(c, n2), distYCbCr(c, n3))),
                min(min(distYCbCr(c, n4), distYCbCr(c, n5)), min(distYCbCr(c, n6), distYCbCr(c, n7))));
  return m * 255.0 >= XBRZ_ISO ? 1.0 : 0.0;
}
// a side pixel clearly lighter than a dark stroke
bool lighterSide(vec3 side, vec3 stroke) { return distYCbCr(side, stroke) * 255.0 >= XBRZ_STRAIGHT && dot(side - stroke, vec3(0.2627, 0.6780, 0.0593)) > 0.0; }
// counts the colors on the sides of a dark stroke (up to 3): a letter's shadow has two, the letter and
// its background, while an outline around shading has more and keeps its pixels
float sideTones(inout vec3 t1, inout vec3 t2, float n, vec3 c)
{
  if (n < 0.5) { t1 = c; return 1.0; }
  if (sameTone(c, t1)) return n;
  if (n < 1.5) { t2 = c; return 2.0; }
  return sameTone(c, t2) ? n : 3.0;
}
// A step at the pixel s: the line runs along a (past the step) and the cut crosses b. Returns
// x: the steps' run length (2 to 4; runs of 5 and 6 count as 4) where a 1-pixel stroke, of s's color or
//    of the color past the step, runs on along both runs with one of its sides in a single color, or
//    with both sides in two lighter colors when the stroke is dark, 0 otherwise;
// y: the run length where both sides of the edge keep one color each (a plain edge), 0 otherwise.
vec2 stepRun(vec2 s, vec2 a, vec2 b)
{
  vec3 X = PS(s);
  vec3 Y = PS(s + a);
  if (distYCbCr(X, Y) * 255.0 < XBRZ_STRAIGHT) return vec2(0.0);
  vec3 farX = X, farY = Y;
  float strokeX = 0.0, plainX = 0.0, strokeY = 0.0, plainY = 0.0;
  // the run of X: X at s - k a (k = 0, 1, ...) and at s + k a - b (k = 1, 2, ...)
  float n1 = 0.0, n2 = 0.0;
  bool thin = true, nu = true, fu = true, dk = true;
  vec3 t1 = X, t2 = X;
  float nt = 0.0;
  for (int k = 0; k < 7; k++)
  {
    vec2 o = s - float(k) * a;
    vec3 nr = PS(o + b);
    if (!sameTone(PS(o), X) || sameTone(nr, X)) break;
    vec3 fr = PS(o - b);
    if (k == 0) farX = fr;
    n1 += 1.0; thin = thin && !sameTone(fr, X); nu = nu && sameTone(nr, Y); fu = fu && sameTone(fr, farX);
    dk = dk && lighterSide(nr, X) && lighterSide(fr, X);
    if (dk) { nt = sideTones(t1, t2, nt, nr); nt = sideTones(t1, t2, nt, fr); }
  }
  if (n1 >= 2.0 && n1 <= 6.0)
  {
    for (int k = 1; k < 8; k++)
    {
      vec2 o = s + float(k) * a;
      vec3 nr = PS(o);
      if (sameTone(nr, X) || !sameTone(PS(o - b), X)) break;
      vec3 fr = PS(o - 2.0 * b);
      n2 += 1.0; thin = thin && !sameTone(fr, X); nu = nu && sameTone(nr, Y); fu = fu && sameTone(fr, farX);
      dk = dk && lighterSide(nr, X) && lighterSide(fr, X);
      if (dk) { nt = sideTones(t1, t2, nt, nr); nt = sideTones(t1, t2, nt, fr); }
    }
    float nX = (n2 <= 6.0 && abs(n1 - n2) <= 1.0) ? min(4.0, min(n1, n2)) : 0.0;
    bool darkX = dk && nt < 2.5 && dot(X, vec3(0.2627, 0.6780, 0.0593)) <= XBRZ_DARK;
    strokeX = (thin && (nu || fu || darkX)) ? nX : 0.0;
    plainX = nu ? nX : 0.0;
  }
  // the run of Y: Y at s - k a + b (k = 0, 1, ...) and at s + k a (k = 1, 2, ...)
  n1 = 0.0; n2 = 0.0; thin = true; nu = true; fu = true; dk = true; nt = 0.0;
  for (int k = 0; k < 7; k++)
  {
    vec2 o = s - float(k) * a;
    vec3 nr = PS(o);
    if (sameTone(nr, Y) || !sameTone(PS(o + b), Y)) break;
    vec3 fr = PS(o + 2.0 * b);
    if (k == 0) farY = fr;
    n1 += 1.0; thin = thin && !sameTone(fr, Y); nu = nu && sameTone(nr, X); fu = fu && sameTone(fr, farY);
    dk = dk && lighterSide(nr, Y) && lighterSide(fr, Y);
    if (dk) { nt = sideTones(t1, t2, nt, nr); nt = sideTones(t1, t2, nt, fr); }
  }
  if (n1 >= 2.0 && n1 <= 6.0)
  {
    for (int k = 1; k < 8; k++)
    {
      vec2 o = s + float(k) * a;
      vec3 nr = PS(o - b);
      if (!sameTone(PS(o), Y) || sameTone(nr, Y)) break;
      vec3 fr = PS(o + b);
      n2 += 1.0; thin = thin && !sameTone(fr, Y); nu = nu && sameTone(nr, X); fu = fu && sameTone(fr, farY);
      dk = dk && lighterSide(nr, Y) && lighterSide(fr, Y);
      if (dk) { nt = sideTones(t1, t2, nt, nr); nt = sideTones(t1, t2, nt, fr); }
    }
    float nY = (n2 <= 6.0 && abs(n1 - n2) <= 1.0) ? min(4.0, min(n1, n2)) : 0.0;
    bool darkY = dk && nt < 2.5 && dot(Y, vec3(0.2627, 0.6780, 0.0593)) <= XBRZ_DARK;
    strokeY = (thin && (nu || fu || darkY)) ? nY : 0.0;
    plainY = nu ? nY : 0.0;
  }
  return vec2(max(strokeX, strokeY), max(plainX, plainY));
}
// slope (0: keep xBRZ's line, else 2, 3 or 4) and line type (1 steep, 2 shallow) of a corner, from its
// steep and shallow step runs and xBRZ's own line type (xs steep, xh shallow)
vec2 stepSlope(vec2 st, vec2 sh, float xs, float xh)
{
  if (st.x >= 2.0 && sh.x < 2.0) return vec2(st.x, 1.0);
  if (sh.x >= 2.0 && st.x < 2.0) return vec2(sh.x, 2.0);
  if (xs > 0.0 && st.y >= 3.0 && sh.x < 2.0) return vec2(st.y, 1.0);
  if (xh > 0.0 && sh.y >= 3.0 && st.x < 2.0) return vec2(sh.y, 2.0);
  return vec2(0.0);
}
// the thin end of a step of 3 or more at the step pixel s (= v or h from E, in the corner's frame v, h):
// its slope when the step there is a steep (steep = true) or shallow line of that length, else 0
float thinEnd(vec2 v, vec2 h, bool steep, float xLine)
{
  vec2 s = steep ? v : h;
  vec2 r = steep ? stepRun(s, v, h) : stepRun(s, h, v);
  if (max(r.x, r.y * xLine) < 3.0) return 0.0;
  r = steep ? stepSlope(r, stepRun(s, h, v), xLine, 0.0) : stepSlope(stepRun(s, v, h), r, 0.0, xLine);
  return (r.x >= 3.0 && r.y == (steep ? 1.0 : 2.0)) ? r.x : 0.0;
}
float drawsLine(float r) { return float(r < 128.0 && BLEND(r) > 0.0 && BLEND(r) < 3.0 && FLAG(r, 4.0) > 0.0); }
// 22. the pixel at o (from stepBase): its color goes on along the diagonal d (a 45-degree stripe), it
// differs from all 4 of its neighbors, and its brightness
float stripe22(vec2 o, vec2 d) { vec3 c = PS(o); return (distYCbCr(c, PS(o + d)) * 255.0 < 15.0 || distYCbCr(c, PS(o - d)) * 255.0 < 15.0) ? 1.0 : 0.0; }
float lone22(vec2 o) { vec3 c = PS(o); return (distYCbCr(c, PS(o + vec2(-1., 0.))) * 255.0 >= 15.0 && distYCbCr(c, PS(o + vec2(1., 0.))) * 255.0 >= 15.0 && distYCbCr(c, PS(o + vec2(0., -1.))) * 255.0 >= 15.0 && distYCbCr(c, PS(o + vec2(0., 1.))) * 255.0 >= 15.0) ? 1.0 : 0.0; }
float luma22(vec2 o) { return dot(PS(o), vec3(0.2627, 0.6780, 0.0593)); }
// 22. n's corner (its info word r) paints E (E is its candidate s: 0 first, 1 second), one of the two cuts
// was blocked by the diagonal limit (mbl: E's corner), one of them draws a line along the shared side (the
// flag "along" on n's corner, "mine" on E's), E and n are distinct but close shades (under 64 apart, and
// at least 45 when the darker one sits on a ramp down to a still darker pixel past it), and
// the lighter of the two pixels lies on a 45-degree stripe of its color along d while the darker one differs
// from all 4 of its neighbors
// 22. a plain round corner of E that takes its color from p, where p is a darker pixel apart from its 4
// neighbors at the end of a lighter 45-degree stripe (the stripe ends at p - q, beside p), E, p, q and the
// corner pixel p + q are four colors, and p and the stripe's end cross their cuts (see back22): the stripe
// stops at p, so p's color leaks no tip into E
float corner22(vec4 w, vec2 c) { return c.y < 0.0 ? (c.x < 0.0 ? w.x : w.y) : (c.x > 0.0 ? w.z : w.w); }
float tip22(vec2 p, vec2 q, vec3 e, vec2 c0)
{
  vec3 cp = PS(p), cl = PS(p - q);
  float dl = distYCbCr(cl, cp) * 255.0;
  if (dl < 15.0 || dl >= 64.0 || dot(cl - cp, vec3(0.2627, 0.6780, 0.0593)) <= 0.0) return 0.0;
  vec3 cq = PS(q), ck = PS(p + q);
  if (distYCbCr(cp, cq) * 255.0 < 15.0 || distYCbCr(cp, ck) * 255.0 < 15.0 || distYCbCr(cq, ck) * 255.0 < 15.0 || distYCbCr(e, ck) * 255.0 < 15.0 || distYCbCr(e, cp) * 255.0 < 15.0) return 0.0;
  if (distYCbCr(cl, PS(p - q + p - q)) * 255.0 >= 15.0 || distYCbCr(cp, PS(p + p)) * 255.0 < 15.0) return 0.0;
  vec4 iP = floor(INFO(c0 + p * INFO_STEP) * 255.0 + 0.5), iL = floor(INFO(c0 + (p - q) * INFO_STEP) * 255.0 + 0.5);
  float rP = corner22(iP, -p - q), rL = corner22(iL, p + q);
  if (BLEND(rP) == 0.0 || BLEND(rL) == 0.0 || max(FLAG(rP, 128.0), FLAG(rL, 128.0)) < 0.5) return 0.0;
  return 1.0;
}
float back22(float r, float s, vec2 n, vec2 d, float along, float mine, float mbl)
{
  if (BLEND(r) == 0.0 || abs(FLAG(r, 8.0) - s) > 0.5 || max(FLAG(r, 128.0), mbl) < 0.5 || max(FLAG(r, along), mine) < 0.5) return 0.0;
  float dn = distYCbCr(PS(vec2(0.)), PS(n)) * 255.0;
  if (dn >= 64.0) return 0.0;
  vec2 lit = luma22(n) > luma22(vec2(0.)) ? n : vec2(0.), dark = luma22(n) > luma22(vec2(0.)) ? vec2(0.) : n;
  if (dn < 45.0 && luma22(dark + dark - lit) < luma22(dark)) return 0.0; // a faint step on a ramp toward a darker pixel stays
  return stripe22(lit, d) * lone22(dark);
}

//#crisp}
// The parts of rules 1, 2 and 9 that need the neighbours' decisions, once per game pixel (they were in
// the output pass, once per output pixel). The word written for the output pass keeps BLEND (the
// final blend type: 0 none, anything else cut), +4 line, +8 second color, +16 shallow, +64 steep.
//#crisp{
// Rule 14 (straight steps) is also made here, and adds BLEND 2 (a thin end), +32 (3:1) and +128 (4:1).
//#crisp}
void main()
{
  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;
  vec2 ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;

  vec4 info = INFO_AT(0.0, 0.0);
  vec4 blendResult = BLEND(info);

  vec4 weak = vec4(equal(BLEND(info), vec4(3.0)));
  if (max(max(info.x, info.y), max(info.z, info.w)) >= 128.0 || dot(weak, vec4(1.0)) > 0.0)
  {
    vec3 E = P( 0., 0.);
    vec4 blocked = floor(info / 128.0);
    info = mod(info, 128.0);
    blendResult = BLEND(info);
    vec4 nA = INFO_AT( 1.0,-1.0);
    vec4 nB = INFO_AT(-1.0, 1.0);
    vec4 nC = INFO_AT( 1.0, 1.0);
    vec4 nD = INFO_AT(-1.0,-1.0);
    vec4 aA = vec4(greaterThan(BLEND(nA), vec4(0.0))) * vec4(lessThan(BLEND(nA), vec4(3.0))) * vec4(lessThan(nA, vec4(128.0)));
    vec4 aB = vec4(greaterThan(BLEND(nB), vec4(0.0))) * vec4(lessThan(BLEND(nB), vec4(3.0))) * vec4(lessThan(nB, vec4(128.0)));
    vec4 aC = vec4(greaterThan(BLEND(nC), vec4(0.0))) * vec4(lessThan(BLEND(nC), vec4(3.0))) * vec4(lessThan(nC, vec4(128.0)));
    vec4 aD = vec4(greaterThan(BLEND(nD), vec4(0.0))) * vec4(lessThan(BLEND(nD), vec4(3.0))) * vec4(lessThan(nD, vec4(128.0)));

    // ---- 2. Diagonal limit: a blocked corner is cut only where it continues a cut ----
    vec4 chain = vec4(max(aA.x, aB.x), max(aC.y, aD.y), max(aA.z, aB.z), max(aC.w, aD.w));
    vec4 lineB = blocked * FLAG(info, 4.0) * vec4(greaterThan(blendResult, vec4(0.0))) * (1.0 - chain);
    vec4 meet = vec4(0.0);
    if (dot(lineB, vec4(1.0)) > 0.0)
    {
      vec4 oL = INFO_AT(-1.0, 0.0);
      vec4 oR = INFO_AT( 1.0, 0.0);
      vec4 oU = INFO_AT( 0.0,-1.0);
      vec4 oD = INFO_AT( 0.0, 1.0);
      vec4 sec = FLAG(info, 8.0);
      vec4 nO = vec4(mix(oL.z, oU.z, sec.x), mix(oU.w, oR.w, sec.y), mix(oR.x, oD.x, sec.z), mix(oD.y, oL.y, sec.w));
      vec3 dX = sec.x > 0.5 ? P( 1.,-1.) : P(-1., 1.), dY = sec.y > 0.5 ? P( 1., 1.) : P(-1.,-1.);
      vec3 dZ = sec.z > 0.5 ? P(-1., 1.) : P( 1.,-1.), dW = sec.w > 0.5 ? P(-1.,-1.) : P( 1., 1.);
      vec4 sameE = vec4(float(distYCbCr(E, dX) * 255.0 <= 20.0), float(distYCbCr(E, dY) * 255.0 <= 20.0),
                        float(distYCbCr(E, dZ) * 255.0 <= 20.0), float(distYCbCr(E, dW) * 255.0 <= 20.0));
      meet = vec4(greaterThan(BLEND(nO), vec4(0.0))) * vec4(lessThan(nO, vec4(128.0))) * FLAG(nO, 4.0)
           * max(1.0 - abs(FLAG(nO, 8.0) - sec), abs(FLAG(nO, 8.0) - sec) * sameE)
           * FLAG(info, 4.0);
    }
    blendResult *= max(1.0 - blocked, max(chain, meet));

    // ---- 1. Minimum contrast: a weak corner is cut only inside a cut diagonal ----
    blendResult *= mix(vec4(1.0), vec4(min(aA.x, aB.x), min(aC.y, aD.y), min(aA.z, aB.z), min(aC.w, aD.w)), weak);
  }

  vec4 haveShallowLine = FLAG(info, 16.0);
  vec4 haveSteepLine = FLAG(info, 64.0);

  // ---- 9. Line shapes, second part ----
  vec4 tone = FLAG(info, 32.0) * vec4(greaterThan(blendResult, vec4(0.0)));
  if (tone.x + tone.y + tone.z + tone.w > 0.0)
  {
    vec4 nL = INFO_AT(-1.0, 0.0);
    vec4 nR = INFO_AT( 1.0, 0.0);
    vec4 nU = INFO_AT( 0.0,-1.0);
    vec4 nD = INFO_AT( 0.0, 1.0);
    vec4 drawL = vec4(lessThan(nL, vec4(128.0))) * FLAG(nL, 4.0), drawR = vec4(lessThan(nR, vec4(128.0))) * FLAG(nR, 4.0);
    vec4 drawU = vec4(lessThan(nU, vec4(128.0))) * FLAG(nU, 4.0), drawD = vec4(lessThan(nD, vec4(128.0))) * FLAG(nD, 4.0);
    vec4 steepN = vec4(drawL.z * FLAG(nL.z, 64.0), drawU.w * FLAG(nU.w, 64.0),
                       drawR.x * FLAG(nR.x, 64.0), drawD.y * FLAG(nD.y, 64.0));
    vec4 shallowN = vec4(drawU.z * FLAG(nU.z, 16.0), drawR.w * FLAG(nR.w, 16.0),
                         drawD.x * FLAG(nD.x, 16.0), drawL.y * FLAG(nL.y, 16.0));
    haveSteepLine *= 1.0 - tone * steepN;
    haveShallowLine *= 1.0 - tone * shallowN;
  }

//#crisp{
  // ---- 17. A line drawn on one side only ----
  // a corner that draws xBRZ's line in the line's own color, where the pixel across the line (O) draws
  // the same line in E's color, stays square: the line is E's color there, not a spike into E
  if (XBRZ_MINC > 0.0)
  {
    vec4 sh = haveShallowLine, st = haveSteepLine;
    vec4 on = vec4(greaterThan(blendResult, vec4(0.0))) * FLAG(info, 4.0) * abs(sh - st)
            * vec4(equal(FLAG(info, 8.0), st));
    if (dot(on, vec4(1.0)) > 0.0)
    {
      vec4 oU = INFO_AT(0.0, -1.0), oL = INFO_AT(-1.0, 0.0), oR = INFO_AT(1.0, 0.0), oD = INFO_AT(0.0, 1.0);
      // O's matching corner: x: shallow B.z, steep D.z; y: shallow F.w, steep B.w;
      // z: shallow H.x, steep F.x; w: shallow D.y, steep H.y
      vec4 oSh = vec4(oU.z, oR.w, oD.x, oL.y), oSt = vec4(oL.z, oU.w, oR.x, oD.y);
      vec4 o = mix(oSt, oSh, sh);
      vec4 oDraw = vec4(lessThan(o, vec4(128.0))) * vec4(greaterThan(BLEND(o), vec4(0.0))) * FLAG(o, 4.0)
                 * mix(FLAG(o, 64.0), FLAG(o, 16.0), sh) * vec4(equal(FLAG(o, 8.0), sh));
      // the line is only two lone pixels: neither goes on along the line
      #define CONT(ax, ay, bx, by) float(distYCbCr(P(ax, ay), P(bx, by)) * 255.0 < 15.0)
      vec4 cSh = vec4(max(CONT(-1., 0., -2., 0.), CONT(1., -1., 2., -1.)), max(CONT(0., -1., 0., -2.), CONT(1., 1., 1., 2.)),
                      max(CONT(1., 0., 2., 0.), CONT(-1., 1., -2., 1.)), max(CONT(0., 1., 0., 2.), CONT(-1., -1., -1., -2.)));
      vec4 cSt = vec4(max(CONT(0., -1., 0., -2.), CONT(-1., 1., -1., 2.)), max(CONT(1., 0., 2., 0.), CONT(-1., -1., -2., -1.)),
                      max(CONT(0., 1., 0., 2.), CONT(1., -1., 1., -2.)), max(CONT(-1., 0., -2., 0.), CONT(1., 1., 2., 1.)));
      oDraw *= 1.0 - mix(cSt, cSh, sh);
      // and E's color does not repeat along the line (a dotted line with E as one of its dots)
      vec3 E1 = P(0., 0.);
      #define REP(vx, vy) max(float(distYCbCr(E1, P(vx, vy)) * 255.0 < 15.0), float(distYCbCr(E1, P(-(vx), -(vy))) * 255.0 < 15.0))
      vec4 rSh = vec4(REP(2., -1.), REP(1., 2.), REP(2., -1.), REP(1., 2.));
      vec4 rSt = vec4(REP(1., -2.), REP(2., 1.), REP(1., -2.), REP(2., 1.));
      oDraw *= 1.0 - mix(rSt, rSh, sh);
      // and the line's color L, E and O are not an antialiasing ramp (for a steep line L and O swap,
      // which leaves the test the same)
      vec3 pB = P(0., -1.), pD = P(-1., 0.), pF = P(1., 0.), pH = P(0., 1.);
      vec4 dLE = vec4(distYCbCr(pD, E1), distYCbCr(pB, E1), distYCbCr(pF, E1), distYCbCr(pH, E1));
      vec4 dOE = vec4(distYCbCr(pB, E1), distYCbCr(pF, E1), distYCbCr(pH, E1), distYCbCr(pD, E1));
      vec4 dLO = vec4(distYCbCr(pD, pB), distYCbCr(pB, pF), distYCbCr(pF, pH), distYCbCr(pH, pD));
      oDraw *= vec4(greaterThan(dLE + dOE, XBRZ_LONE_RAMP * dLO));
      blendResult *= 1.0 - on * oDraw;
    }
  }

  // ---- 19. A pixel apart keeps to itself ----
  // a cut corner whose color comes from a pixel that differs from all 8 of its neighbors by XBRZ_ISO or
  // more, and keeps its own four corners square, stays square: the pixel does not leak into its neighbors
  if (XBRZ_MINC > 0.0 && dot(vec4(greaterThan(blendResult, vec4(0.0))), vec4(1.0)) > 0.0)
  {
    vec4 sec19 = FLAG(info, 8.0);
    // the pixel each corner paints from: x: D or B, y: B or F, z: F or H, w: H or D
    vec2 pX = sec19.x > 0.5 ? vec2(0., -1.) : vec2(-1., 0.);
    vec2 pY = sec19.y > 0.5 ? vec2(1., 0.) : vec2(0., -1.);
    vec2 pZ = sec19.z > 0.5 ? vec2(0., 1.) : vec2(1., 0.);
    vec2 pW = sec19.w > 0.5 ? vec2(-1., 0.) : vec2(0., 1.);
    #define ISO19(p) isoOf(P(p.x, p.y), P(p.x - 1., p.y - 1.), P(p.x, p.y - 1.), P(p.x + 1., p.y - 1.), P(p.x - 1., p.y), P(p.x + 1., p.y), P(p.x - 1., p.y + 1.), P(p.x, p.y + 1.), P(p.x + 1., p.y + 1.))
    vec4 iso = vec4(blendResult.x > 0.0 ? ISO19(pX) : 0.0, blendResult.y > 0.0 ? ISO19(pY) : 0.0,
                    blendResult.z > 0.0 ? ISO19(pZ) : 0.0, blendResult.w > 0.0 ? ISO19(pW) : 0.0);
    #define SQ19(p) (dot(BLEND(INFO_AT(p.x, p.y)), vec4(1.0)) == 0.0 ? 1.0 : 0.0)
    vec4 sq = vec4(SQ19(pX), SQ19(pY), SQ19(pZ), SQ19(pW));
    blendResult *= 1.0 - iso * sq;
  }

  // ---- 20. A corner where no edge runs ----
  // a cut corner between two neighbors of clearly different colors (XBRZ_JUNCTION) stays square where
  // nothing goes on along the cut: neither neighbor's color continues past the corner, E's color does
  // not continue along the cut, and fewer than three pixels in a row cut that corner along the line
  // (a corner on a dark outline with an antialiasing pixel is left to xBRZ: see ramp20 and cr20)
  if (XBRZ_MINC > 0.0 && dot(vec4(greaterThan(blendResult, vec4(0.0))), vec4(1.0)) > 0.0)
  {
    vec3 qA = P(-1., -1.), qB = P(0., -1.), qC = P(1., -1.), qD = P(-1., 0.), qE = P(0., 0.);
    vec3 qF = P(1., 0.), qG = P(-1., 1.), qH = P(0., 1.), qI = P(1., 1.);
    #define DD20(a, b) (distYCbCr(a, b) * 255.0)
    #define NEAR20(a, b) (DD20(a, b) < XBRZ_JUNC_NEAR ? 1.0 : 0.0)
    vec4 cand20 = vec4(DD20(qB, qD), DD20(qB, qF), DD20(qF, qH), DD20(qD, qH));
    // the three colors E and the two neighbors of a corner form a ramp (their distances sum to under
    // RAMP + 1 times the longest), and one neighbor's color goes on just past the other along the cut
    vec4 dE1 = vec4(DD20(qE, qD), DD20(qE, qB), DD20(qE, qF), DD20(qE, qH));
    vec4 dE2 = vec4(DD20(qE, qB), DD20(qE, qF), DD20(qE, qH), DD20(qE, qD));
    vec4 ramp20 = vec4(lessThan(dE1 + dE2 + cand20, (1.0 + XBRZ_JUNC_RAMP) * max(cand20, max(dE1, dE2))));
    vec4 cr20 = max(vec4(NEAR20(qB, P(-2., 1.)), NEAR20(qF, P(-1., -2.)), NEAR20(qH, P(2., -1.)), NEAR20(qD, P(1., 2.))),
                    vec4(NEAR20(qD, P(1., -2.)), NEAR20(qB, P(2., 1.)), NEAR20(qF, P(-1., 2.)), NEAR20(qH, P(-2., -1.))));
    #define LU20(c) dot(c, vec3(0.2627, 0.6780, 0.0593))
    vec4 lu20 = vec4(LU20(qD), LU20(qB), LU20(qF), LU20(qH));
    vec4 lmin20 = min(min(lu20, lu20.yzwx), vec4(LU20(qE)));
    // each neighbor's color past the corner, along the cut (x: D and B, y: B and F, z: F and H, w: H and D)
    vec4 ext1 = vec4(NEAR20(qD, P(-2., 1.)), NEAR20(qB, P(-1., -2.)), NEAR20(qF, P(2., -1.)), NEAR20(qH, P(1., 2.)));
    vec4 ext2 = vec4(NEAR20(qB, P(1., -2.)), NEAR20(qF, P(2., 1.)), NEAR20(qH, P(-1., 2.)), NEAR20(qD, P(-2., -1.)));
    // E's color on the pixels beside it along the cut
    vec4 extE = vec4(max(NEAR20(qE, qG), NEAR20(qE, qC)), max(NEAR20(qE, qA), NEAR20(qE, qI)),
                     max(NEAR20(qE, qC), NEAR20(qE, qG)), max(NEAR20(qE, qA), NEAR20(qE, qI)));
    // the run of pixels that cut the same corner along the cut's line (E included, up to 2 on each side)
    #define CUT20(x, y) vec4(greaterThan(BLEND(INFO_AT(x, y)), vec4(0.0)))
    vec4 m1 = CUT20(-1., -1.), m2 = CUT20(-2., -2.), p1 = CUT20(1., 1.), p2 = CUT20(2., 2.);
    vec4 u1 = CUT20(1., -1.), u2 = CUT20(2., -2.), d1 = CUT20(-1., 1.), d2 = CUT20(-2., 2.);
    vec4 runA = vec4(u1.x + u1.x * u2.x, m1.y + m1.y * m2.y, u1.z + u1.z * u2.z, m1.w + m1.w * m2.w);
    vec4 runB = vec4(d1.x + d1.x * d2.x, p1.y + p1.y * p2.y, d1.z + d1.z * d2.z, p1.w + p1.w * p2.w);
    vec4 on20 = vec4(greaterThan(blendResult, vec4(0.0))) * vec4(greaterThan(cand20, vec4(XBRZ_JUNCTION))) * (1.0 - ramp20 * cr20 * vec4(greaterThan(min(dE1, dE2), vec4(40.0))) * vec4(lessThan(min(dE1, dE2), vec4(70.0))) * vec4(lessThan(lmin20, vec4(0.35)))) *
                (1.0 - ext1) * (1.0 - ext2) * (1.0 - extE) * vec4(lessThan(1.0 + runA + runB, vec4(3.0)));
    blendResult *= 1.0 - on20;
  }

  // ---- 21. A straight line does not bend ----
  // a cut corner whose color comes from a pixel p in a straight line of its color along E's side (three
  // pixels centered on p, or a strong line of four that starts at p and runs toward the corner), where the
  // corner's other neighbor q differs from it by more than XBRZ_LINE_SIDE, does not take the line's color:
  // it takes q's color where q is darker than E and goes on along the cut, and otherwise stays square
  if (XBRZ_MINC > 0.0 && dot(vec4(greaterThan(blendResult, vec4(0.0))), vec4(1.0)) > 0.0)
  {
    vec4 s21 = FLAG(info, 8.0);
    // the pixel each corner paints from (p) and the corner's other neighbor (q)
    vec2 pX = s21.x > 0.5 ? vec2(0., -1.) : vec2(-1., 0.), qX = s21.x > 0.5 ? vec2(-1., 0.) : vec2(0., -1.);
    vec2 pY = s21.y > 0.5 ? vec2(1., 0.) : vec2(0., -1.), qY = s21.y > 0.5 ? vec2(0., -1.) : vec2(1., 0.);
    vec2 pZ = s21.z > 0.5 ? vec2(0., 1.) : vec2(1., 0.), qZ = s21.z > 0.5 ? vec2(1., 0.) : vec2(0., 1.);
    vec2 pW = s21.w > 0.5 ? vec2(-1., 0.) : vec2(0., 1.), qW = s21.w > 0.5 ? vec2(0., 1.) : vec2(-1., 0.);
    #define DIST21(a, b) (distYCbCr(P(a.x, a.y), P(b.x, b.y)) * 255.0)
    #define SAME21(a, b) (DIST21(a, b) < 15.0)
    // the direction of E's side next to p (horizontal for B and H, vertical for D and F), and the same
    // direction pointing toward the corner
    #define ALONG21(p) (abs(p.y) > 0.5 ? vec2(1., 0.) : vec2(0., 1.))
    #define TOWARD21(p, q) (abs(p.y) > 0.5 ? vec2(q.x, 0.) : vec2(0., q.y))
    // p in the middle of three of its color along E's side
    #define MID21(p) (SAME21(p, (p + ALONG21(p))) && SAME21(p, (p - ALONG21(p))))
    // a line of four from p toward the corner: it differs from E by 64 or more and is thin (the pixel
    // across it from E is closer to E than to p), q's color does not cross it (at p - q), the cut ends at p
    // (the pixel past p along the cut is closer to E than to p and q), and E's color does not go on along
    // the cut on either side
    #define FROM21(p, q) (DIST21(p, vec2(0.)) >= 64.0 && !SAME21(q, (p - q)) && DIST21((2.0 * p), p) > DIST21((2.0 * p), vec2(0.)) && SAME21(p, (p + TOWARD21(p, q))) && SAME21(p, (p + 2.0 * TOWARD21(p, q))) && SAME21(p, (p + 3.0 * TOWARD21(p, q))) && DIST21((2.0 * p - q), vec2(0.)) < min(DIST21((2.0 * p - q), p), DIST21((2.0 * p - q), q)) && DIST21(vec2(0.), (q - p)) >= 20.0 && DIST21(vec2(0.), (p - q)) >= 20.0)
    #define LINE21(p, q) (((MID21(p) || FROM21(p, q)) && DIST21(p, q) > XBRZ_LINE_SIDE) ? 1.0 : 0.0)
    // q takes the corner: q's color goes on away from E (2q) and along the cut one step past q (2q - p),
    // the line differs from E by 64 or more, the pixel beside q toward E is closer to E than to q, and q is
    // darker than E
    #define ON21(p, q) ((SAME21(q, (2.0 * q)) && DIST21(p, vec2(0.)) >= 64.0 && SAME21(q, (2.0 * q - p)) && DIST21((q - p), vec2(0.)) < DIST21((q - p), q) && dot(P(q.x, q.y), vec3(0.2627, 0.6780, 0.0593)) < dot(P(0., 0.), vec3(0.2627, 0.6780, 0.0593))) ? 1.0 : 0.0)
    vec4 line21 = vec4(blendResult.x > 0.0 ? LINE21(pX, qX) : 0.0, blendResult.y > 0.0 ? LINE21(pY, qY) : 0.0,
                       blendResult.z > 0.0 ? LINE21(pZ, qZ) : 0.0, blendResult.w > 0.0 ? LINE21(pW, qW) : 0.0);
    vec4 on21 = line21 * vec4(ON21(pX, qX), ON21(pY, qY), ON21(pZ, qZ), ON21(pW, qW));
    // a corner that takes q's color becomes a plain corner (no line) in that color
    info += 8.0 * on21 * (1.0 - 2.0 * s21);
    haveShallowLine *= 1.0 - on21;
    haveSteepLine *= 1.0 - on21;
    blendResult *= 1.0 - line21 * (1.0 - on21);
  }

  // ---- 22. Crossed cuts ----
  // a cut corner whose color comes from the neighbor n stays square when n's corner at the other end of
  // their shared side cuts back into E (the two cuts cross along that side), E and n are close shades
  // (under 64 apart), and the lighter of the two ends a 45-degree stripe of its color next to a darker pixel that
  // differs from its 4 neighbors (see back22); n's corner stays square the same way, so the side between
  // them is straight and the darker shade does not bulge into the stripe
  vec4 x22 = vec4(0.0);
  if (XBRZ_MINC > 0.0 && dot(vec4(greaterThan(blendResult, vec4(0.0))), vec4(1.0)) > 0.0)
  {
    stepBase = ocoord;
    vec4 s22 = FLAG(info, 8.0), sh22 = FLAG(info, 16.0), st22 = FLAG(info, 64.0), bl22 = FLAG(INFO_AT(0.0, 0.0), 128.0);
    vec4 iD = INFO_AT(-1.0, 0.0), iB = INFO_AT(0.0, -1.0), iF = INFO_AT(1.0, 0.0), iH = INFO_AT(0.0, 1.0);
    vec2 dXZ = vec2(1., -1.), dYW = vec2(1., 1.);
    if (blendResult.x > 0.0) x22.x = s22.x > 0.5 ? back22(iB.z, 1.0, vec2(0., -1.), dXZ, 16.0, sh22.x, bl22.x) : back22(iD.z, 0.0, vec2(-1., 0.), dXZ, 64.0, st22.x, bl22.x);
    if (blendResult.y > 0.0) x22.y = s22.y > 0.5 ? back22(iF.w, 1.0, vec2(1., 0.), dYW, 64.0, st22.y, bl22.y) : back22(iB.w, 0.0, vec2(0., -1.), dYW, 16.0, sh22.y, bl22.y);
    if (blendResult.z > 0.0) x22.z = s22.z > 0.5 ? back22(iH.x, 1.0, vec2(0., 1.), dXZ, 16.0, sh22.z, bl22.z) : back22(iF.x, 0.0, vec2(1., 0.), dXZ, 64.0, st22.z, bl22.z);
    if (blendResult.w > 0.0) x22.w = s22.w > 0.5 ? back22(iD.y, 1.0, vec2(-1., 0.), dYW, 64.0, st22.w, bl22.w) : back22(iH.y, 0.0, vec2(0., 1.), dYW, 16.0, sh22.w, bl22.w);
    blendResult *= 1.0 - x22;
    // and a round corner at the far end of such a lone darker pixel takes no tip of it (see tip22)
    vec4 L22 = FLAG(info, 4.0), t22 = vec4(0.0);
    vec3 e22 = PS(vec2(0.0));
    vec2 vD = vec2(-1., 0.), vB = vec2(0., -1.), vF = vec2(1., 0.), vH = vec2(0., 1.);
    if (blendResult.x > 0.0 && L22.x < 0.5) t22.x = s22.x > 0.5 ? tip22(vB, vD, e22, coord) : tip22(vD, vB, e22, coord);
    if (blendResult.y > 0.0 && L22.y < 0.5) t22.y = s22.y > 0.5 ? tip22(vF, vB, e22, coord) : tip22(vB, vF, e22, coord);
    if (blendResult.z > 0.0 && L22.z < 0.5) t22.z = s22.z > 0.5 ? tip22(vH, vF, e22, coord) : tip22(vF, vH, e22, coord);
    if (blendResult.w > 0.0 && L22.w < 0.5) t22.w = s22.w > 0.5 ? tip22(vD, vH, e22, coord) : tip22(vH, vD, e22, coord);
    blendResult *= 1.0 - t22;
    x22 = max(x22, t22);
  }

  // ---- 14. Straight steps ----
  // nn: the slope of a cut corner's line (0: xBRZ's), ty: its type (1 steep, 2 shallow); a free corner
  // next to the step pixel along the line (steep: E + v, shallow: E + h) takes that line's thin end
  vec4 nn = vec4(0.0), ty = vec4(0.0), thinN = vec4(0.0), thinSteep = vec4(0.0);
  if (XBRZ_MINC > 0.0)
  {
    stepBase = ocoord;
    // each corner's frame: v runs from E across the corner's vertical side, h across its horizontal side
    vec2 vX = vec2(0.,-1.), hX = vec2(-1.,0.), vY = vec2(1.,0.), hY = vec2(0.,-1.);
    vec2 vZ = vec2(0., 1.), hZ = vec2( 1.,0.), vW = vec2(-1.,0.), hW = vec2(0., 1.);
    vec4 lineOn = FLAG(info, 4.0) * vec4(greaterThan(blendResult, vec4(0.0)));
    vec2 r;
    if (lineOn.x > 0.0) { r = stepSlope(stepRun(vec2(0.), vX, hX), stepRun(vec2(0.), hX, vX), haveSteepLine.x, haveShallowLine.x); nn.x = r.x; ty.x = r.y; }
    if (lineOn.y > 0.0) { r = stepSlope(stepRun(vec2(0.), vY, hY), stepRun(vec2(0.), hY, vY), haveSteepLine.y, haveShallowLine.y); nn.y = r.x; ty.y = r.y; }
    if (lineOn.z > 0.0) { r = stepSlope(stepRun(vec2(0.), vZ, hZ), stepRun(vec2(0.), hZ, vZ), haveSteepLine.z, haveShallowLine.z); nn.z = r.x; ty.z = r.y; }
    if (lineOn.w > 0.0) { r = stepSlope(stepRun(vec2(0.), vW, hW), stepRun(vec2(0.), hW, vW), haveSteepLine.w, haveShallowLine.w); nn.w = r.x; ty.w = r.y; }
    vec4 free = vec4(equal(blendResult, vec4(0.0)));
    if (dot(free, vec4(1.0)) > 0.0)
    {
      vec4 nL = INFO_AT(-1.0, 0.0), nR = INFO_AT(1.0, 0.0), nU = INFO_AT(0.0, -1.0), nDn = INFO_AT(0.0, 1.0);
      vec4 cSt = free * vec4(drawsLine(nU.x), drawsLine(nR.y), drawsLine(nDn.z), drawsLine(nL.w));
      vec4 cSh = free * vec4(drawsLine(nL.x), drawsLine(nU.y), drawsLine(nR.z), drawsLine(nDn.w));
      if (dot(cSt + cSh, vec4(1.0)) > 0.0)
      {
        vec3 E0 = P(0., 0.);
        if (cSt.x > 0.0 && sameTone(PS(vX), E0)) { thinN.x = thinEnd(vX, hX, true, FLAG(nU.x, 64.0)); thinSteep.x = 1.0; }
        if (thinN.x == 0.0 && cSh.x > 0.0 && sameTone(PS(hX), E0)) { thinN.x = thinEnd(vX, hX, false, FLAG(nL.x, 16.0)); thinSteep.x = 0.0; }
        if (cSt.y > 0.0 && sameTone(PS(vY), E0)) { thinN.y = thinEnd(vY, hY, true, FLAG(nR.y, 64.0)); thinSteep.y = 1.0; }
        if (thinN.y == 0.0 && cSh.y > 0.0 && sameTone(PS(hY), E0)) { thinN.y = thinEnd(vY, hY, false, FLAG(nU.y, 16.0)); thinSteep.y = 0.0; }
        if (cSt.z > 0.0 && sameTone(PS(vZ), E0)) { thinN.z = thinEnd(vZ, hZ, true, FLAG(nDn.z, 64.0)); thinSteep.z = 1.0; }
        if (thinN.z == 0.0 && cSh.z > 0.0 && sameTone(PS(hZ), E0)) { thinN.z = thinEnd(vZ, hZ, false, FLAG(nR.z, 16.0)); thinSteep.z = 0.0; }
        if (cSt.w > 0.0 && sameTone(PS(vW), E0)) { thinN.w = thinEnd(vW, hW, true, FLAG(nL.w, 64.0)); thinSteep.w = 1.0; }
        if (thinN.w == 0.0 && cSh.w > 0.0 && sameTone(PS(hW), E0)) { thinN.w = thinEnd(vW, hW, false, FLAG(nDn.w, 16.0)); thinSteep.w = 0.0; }
      }
    }
  }
  vec4 over = vec4(greaterThan(nn, vec4(0.0)));
  haveSteepLine = mix(haveSteepLine, vec4(equal(ty, vec4(1.0))), over);
  haveShallowLine = mix(haveShallowLine, vec4(equal(ty, vec4(2.0))), over);
  thinN *= 1.0 - x22; // 22. a crossed cut takes no thin end either
  vec4 isThin = vec4(greaterThan(thinN, vec4(0.0)));
  vec4 slope = mix(nn, thinN, isThin);
  // the output word: BLEND 1 cut, 2 the thin end of a straight step (its line starts 1 pixel further
  // along); +32 a 3:1 line, +128 a 4:1 line
  vec4 res = min(blendResult, vec4(1.0)) + 4.0 * FLAG(info, 4.0) + 8.0 * FLAG(info, 8.0) + 16.0 * haveShallowLine + 64.0 * haveSteepLine;
  res = mix(res, 2.0 + 4.0 + 24.0 * (1.0 - thinSteep) + 64.0 * thinSteep, isThin);
  res += 32.0 * vec4(equal(slope, vec4(3.0))) + 128.0 * vec4(equal(slope, vec4(4.0)));
//#crisp}
//#plain   vec4 res = blendResult + 4.0 * FLAG(info, 4.0) + 8.0 * FLAG(info, 8.0) + 16.0 * haveShallowLine + 64.0 * haveSteepLine;
  FRAG_OUT = res / 255.0;
}

#endif

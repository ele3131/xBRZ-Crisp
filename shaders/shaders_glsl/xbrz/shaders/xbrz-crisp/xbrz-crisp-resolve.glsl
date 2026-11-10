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
// ---- Tunables of rules 14 and 17 to 22 (distances in x/255, like XBRZ_MINC), in rule order ----
#define XBRZ_STRAIGHT 64.0   // 14. minimum contrast of a straightened edge
#define XBRZ_DARK 0.3        // 14. a stroke this dark (luma) or darker may have two lighter side colors
#define XBRZ_LONE_RAMP 1.4   // 17. not a ramp: d(L,E) + d(E,O) above this times d(L,O)
#define XBRZ_ISO 40.0        // 19. a pixel this far from all 8 of its neighbors keeps out of their corners
#define XBRZ_JUNCTION 40.0   // 20. two neighbors this far apart do not make one edge across a corner
#define XBRZ_JUNC_NEAR 20.0  // 20. a color this close to the next pixel goes on along the cut
#define XBRZ_JUNC_RAMP 1.06  // 20. not a junction but a ramp: the two shorter distances of E and its two neighbors add up to less than this times the longest
#define XBRZ_LINE_SIDE 25.0  // 21. the other neighbor of a corner differs from a straight line by this

// ---- Helpers of the Crisp rules ----
// The center of E in the original image, set once in main. It is the one place the original is read from
// (through P), by every rule below.
vec2 ocoord = vec2(0.0);
const vec3 LUMA = vec3(0.2627, 0.6780, 0.0593);
// The corners of E: v is the neighbor across the corner's vertical side, h the one across its horizontal side.
const vec2 vX = vec2(0., -1.), hX = vec2(-1., 0.), vY = vec2(1., 0.), hY = vec2(0., -1.);
const vec2 vZ = vec2(0., 1.), hZ = vec2(1., 0.), vW = vec2(-1., 0.), hW = vec2(0., 1.);

float luma(vec3 c) { return dot(c, LUMA); }
// The distance of two colors in x/255 units.
float dist255(vec3 a, vec3 b) { return distYCbCr(a, b) * 255.0; }
// Two colors closer than the default tolerance (15, fixed here: it is not the XBRZ_TOL parameter).
bool sameColor(vec3 a, vec3 b) { return dist255(a, b) < 15.0; }
// The tolerance of the straight steps (rule 14).
bool sameTone(vec3 a, vec3 b) { return dist255(a, b) <= 20.0; }
// The original pixel at an offset from E.
vec3 at(vec2 o) { return P(o.x, o.y); }
float sameF(vec3 a, vec3 b) { return float(sameColor(a, b)); }
// 1.0 in the corners that are cut, in a blend result and in a decision word.
vec4 isCut(vec4 blend) { return vec4(greaterThan(blend, vec4(0.0))); }
vec4 cutOf(vec4 word) { return isCut(BLEND(word)); }
bool anyCut(vec4 blend) { return dot(isCut(blend), vec4(1.0)) > 0.0; }
// 1.0 when the colors a and b are closer than XBRZ_JUNC_NEAR (rule 20).
float junctionNear(vec3 a, vec3 b) { return dist255(a, b) < XBRZ_JUNC_NEAR ? 1.0 : 0.0; }
// 1.0 when the color c differs from all of the colors a to e.
float apartFrom4(vec3 c, vec3 a, vec3 b, vec3 d, vec3 e)
{
  return (!sameColor(c, a) && !sameColor(c, b) && !sameColor(c, d) && !sameColor(c, e)) ? 1.0 : 0.0;
}
// 1.0 when one of the two colors a and b is the color c.
float sameAsOne(vec3 c, vec3 a, vec3 b) { return (sameColor(c, a) || sameColor(c, b)) ? 1.0 : 0.0; }

// ---- 14. Straight steps ----
// A side pixel clearly lighter than a dark stroke.
bool lighterSide(vec3 side, vec3 stroke) { return dist255(side, stroke) >= XBRZ_STRAIGHT && luma(side - stroke) > 0.0; }
// Counts the colors on the sides of a dark stroke (up to 3): a letter's shadow has two, the letter and
// its background, while an outline around shading has more and keeps its pixels.
float sideTones(inout vec3 t1, inout vec3 t2, float n, vec3 c)
{
  if (n < 0.5) { t1 = c; return 1.0; }
  if (sameTone(c, t1)) return n;
  if (n < 1.5) { t2 = c; return 2.0; }
  return sameTone(c, t2) ? n : 3.0;
}
// What the cells of one side of a step have seen so far: how many there are, whether the pixels beside
// them (thin: not the stroke's color, nu: the color past the step, fu: the same color as the first far
// pixel) keep to one color, and the colors on the sides of a dark stroke.
struct Walk { float n; bool thin, nu, fu, dk; vec3 farC, t1, t2; float nt; };
// Looks at the cell o of the stroke X: false when the stroke ends there. n points to the pixel beside
// the cell on the side of Y (the color past the step), and the pixel on the other side is the far one.
bool walkCell(inout Walk w, vec3 X, vec3 Y, vec2 o, vec2 n, bool first)
{
  vec3 nr = at(o + n);
  if (sameTone(nr, X) || !sameTone(at(o), X)) return false;
  vec3 fr = at(o - n);
  if (first) w.farC = fr;
  w.n += 1.0;
  w.thin = w.thin && !sameTone(fr, X);
  w.nu = w.nu && sameTone(nr, Y);
  w.fu = w.fu && sameTone(fr, w.farC);
  w.dk = w.dk && lighterSide(nr, X) && lighterSide(fr, X);
  if (w.dk) { w.nt = sideTones(w.t1, w.t2, w.nt, nr); w.nt = sideTones(w.t1, w.t2, w.nt, fr); }
  return true;
}
// The run of the stroke color X along one side of a step: X at the cells row1 - k a (k = 0, 1, ...) and
// at row2 + k a (k = 1, 2, ...). Returns x: the steps' run length (2 to 4; runs of 5 and 6 count as 4) where
// the stroke is 1 pixel thin and runs on along both runs with one of its sides in a single color, or with both
// sides in two lighter colors when the stroke is dark, 0 otherwise; y: the run length where the side keeps
// the color Y past the step (a plain edge), 0 otherwise.
vec2 stepSide(vec3 X, vec3 Y, vec2 row1, vec2 row2, vec2 a, vec2 n)
{
  Walk w = Walk(0.0, true, true, true, true, X, X, X, 0.0);
  for (int k = 0; k < 7; k++) { if (!walkCell(w, X, Y, row1 - float(k) * a, n, k == 0)) break; }
  float n1 = w.n;
  if (n1 < 2.0 || n1 > 6.0) return vec2(0.0);
  w.n = 0.0;
  for (int k = 1; k < 8; k++) { if (!walkCell(w, X, Y, row2 + float(k) * a, n, false)) break; }
  float run = (w.n <= 6.0 && abs(n1 - w.n) <= 1.0) ? min(4.0, min(n1, w.n)) : 0.0;
  bool dark = w.dk && w.nt < 2.5 && luma(X) <= XBRZ_DARK;
  return vec2((w.thin && (w.nu || w.fu || dark)) ? run : 0.0, w.nu ? run : 0.0);
}
// A step at the pixel s: the line runs along a (past the step) and the cut crosses b. Returns x: the
// run of the stroke (see stepSide) for either of the two colors, y: the run of a plain edge.
vec2 stepRun(vec2 s, vec2 a, vec2 b)
{
  vec3 X = at(s);
  vec3 Y = at(s + a);
  if (dist255(X, Y) < XBRZ_STRAIGHT) return vec2(0.0);
  vec2 rx = stepSide(X, Y, s, s - b, a, b);      // X at s - k a and at s + k a - b
  vec2 ry = stepSide(Y, X, s + b, s, a, -b);     // Y at s - k a + b and at s + k a
  return vec2(max(rx.x, ry.x), max(rx.y, ry.y));
}
// Slope (0: keep xBRZ's line, else 2, 3 or 4) and line type (1 steep, 2 shallow) of a corner, from its
// steep and shallow step runs and xBRZ's own line type (xs steep, xh shallow).
vec2 stepSlope(vec2 st, vec2 sh, float xs, float xh)
{
  if (st.x >= 2.0 && sh.x < 2.0) return vec2(st.x, 1.0);
  if (sh.x >= 2.0 && st.x < 2.0) return vec2(sh.x, 2.0);
  if (xs > 0.0 && st.y >= 3.0 && sh.x < 2.0) return vec2(st.y, 1.0);
  if (xh > 0.0 && sh.y >= 3.0 && st.x < 2.0) return vec2(sh.y, 2.0);
  return vec2(0.0);
}
// The slope and line type of a corner with a line, from the step runs at E in its frame (v, h).
vec2 cornerStep(vec2 v, vec2 h, float xs, float xh)
{
  return stepSlope(stepRun(vec2(0.), v, h), stepRun(vec2(0.), h, v), xs, xh);
}
// The thin end of a step of 3 or more at the step pixel s (= v or h from E, in the corner's frame v, h):
// its slope when the step there is a steep (steep = true) or shallow line of that length, else 0.
float thinEnd(vec2 v, vec2 h, bool steep, float xLine)
{
  vec2 s = steep ? v : h;
  vec2 r = steep ? stepRun(s, v, h) : stepRun(s, h, v);
  if (max(r.x, r.y * xLine) < 3.0) return 0.0;
  r = steep ? stepSlope(r, stepRun(s, h, v), xLine, 0.0) : stepSlope(stepRun(s, v, h), r, 0.0, xLine);
  return (r.x >= 3.0 && r.y == (steep ? 1.0 : 2.0)) ? r.x : 0.0;
}
// The thin end that a free corner takes: x: its slope (0: none), y: 1.0 when it is a steep line. cSt and cSh
// say that the neighbor along v (steep) or along h (shallow) draws a line; xSt and xSh are that line's flags.
vec2 thinCorner(vec2 v, vec2 h, vec3 E, float cSt, float cSh, float xSt, float xSh)
{
  vec2 t = vec2(0.0);
  if (cSt > 0.0 && sameTone(at(v), E)) t = vec2(thinEnd(v, h, true, xSt), 1.0);
  if (t.x == 0.0 && cSh > 0.0 && sameTone(at(h), E)) t = vec2(thinEnd(v, h, false, xSh), 0.0);
  return t;
}
float drawsLine(float r) { return float(r < 128.0 && BLEND(r) > 0.0 && BLEND(r) < 3.0 && FLAG(r, 4.0) > 0.0); }

// ---- 19. A pixel apart keeps to itself ----
// 1.0 when the pixel c differs from all 8 of its neighbors by XBRZ_ISO or more.
float isoOf(vec3 c, vec3 n0, vec3 n1, vec3 n2, vec3 n3, vec3 n4, vec3 n5, vec3 n6, vec3 n7)
{
  float m = min(min(min(distYCbCr(c, n0), distYCbCr(c, n1)), min(distYCbCr(c, n2), distYCbCr(c, n3))),
                min(min(distYCbCr(c, n4), distYCbCr(c, n5)), min(distYCbCr(c, n6), distYCbCr(c, n7))));
  return m * 255.0 >= XBRZ_ISO ? 1.0 : 0.0;
}
// 1.0 when none of the four corners of a pixel (its decision word) is cut.
float squareOf(vec4 word) { return dot(BLEND(word), vec4(1.0)) == 0.0 ? 1.0 : 0.0; }

// ---- 21 and 22: what a corner sees around it ----
// The colors and decision words around a corner of E (v and h as above). cv, ch: the pixels at v and h;
// cvh: at v + h (the corner pixel); cvmh, chmv: at v - h and h - v; cv2, ch2: at 2v and 2h; cv2mh,
// ch2mv: at 2v - h and 2h - v; cvp2h, chp2v: at v + 2h and h + 2v; cmv, cmh: at -v and -h. rv and rh
// are the decision words of the neighbors at v and h, and rvmh and rhmv those of the pixels at v - h and
// h - v, each at the corner that faces the cut: the corner of the neighbors at v and h on the far side of E,
// and the corner of the diagonal pixels on the near side.
struct Frame
{
  vec2 v, h;
  vec3 cv, ch, cvh, cvmh, chmv, cv2, ch2, cv2mh, ch2mv, cvp2h, chp2v, cmv, cmh;
  float rv, rh, rvmh, rhmv;
};
// The same, by role: p (offset) and u (color) are the pixel that paints the corner, q and w the corner's
// other neighbor. s is the corner's second color flag: 1.0 when p is v, 0.0 when p is h. The names
// follow Frame: uw is the corner pixel, umw and wmu the pixels at p - q and q - p, u2 and w2 at 2p and 2q,
// u2mw and w2mu at 2p - q and 2q - p, uw2 at p + 2q, mu at -p; ru and rumw are the decision words of
// the pixels at p and at p - q.
struct Roles
{
  vec2 p, q;
  float s;
  vec3 u, w, mu, uw, umw, wmu, u2, w2, u2mw, w2mu, uw2;
  float ru, rumw;
};
Roles roles(Frame f, float s)
{
  bool sv = s > 0.5;
  Roles r;
  r.s = s;
  r.p = sv ? f.v : f.h;      r.q = sv ? f.h : f.v;
  r.u = sv ? f.cv : f.ch;    r.w = sv ? f.ch : f.cv;    r.mu = sv ? f.cmv : f.cmh;
  r.uw = f.cvh;
  r.umw = sv ? f.cvmh : f.chmv;    r.wmu = sv ? f.chmv : f.cvmh;
  r.u2 = sv ? f.cv2 : f.ch2;       r.w2 = sv ? f.ch2 : f.cv2;
  r.u2mw = sv ? f.cv2mh : f.ch2mv; r.w2mu = sv ? f.ch2mv : f.cv2mh;
  r.uw2 = sv ? f.cvp2h : f.chp2v;
  r.ru = sv ? f.rv : f.rh;         r.rumw = sv ? f.rvmh : f.rhmv;
  return r;
}

// ---- 21. A straight line does not bend ----
// For a cut corner painted from the pixel p (color u), with q the corner's other neighbor (color w).
// x: 1.0 when p lies in a straight line of its color along E's side (three pixels centered on p, or a strong
// line of four that starts at p and runs toward the corner) and q differs from p by more than XBRZ_LINE_SIDE,
// so the corner does not take p's color; y: 1.0 when, besides, q takes the corner instead (q's color goes on
// away from E and along the cut, the line differs from E by 64 or more, the pixel beside q toward E is closer
// to E than to q, and q is darker than E).
vec2 straight21(Roles r, vec3 E)
{
  if (dist255(r.u, r.w) <= XBRZ_LINE_SIDE) return vec2(0.0);
  // p in the middle of three of its color along E's side
  bool middle = sameColor(r.u, r.uw) && sameColor(r.u, r.umw);
  // or a line of four from p toward the corner: it differs from E by 64 or more and is thin (the pixel
  // across it from E is closer to E than to p), q's color does not cross it (at p - q), the cut ends at p
  // (the pixel past p along the cut is closer to E than to p and q), and E's color does not go on along
  // the cut on either side
  bool four = !middle && dist255(r.u, E) >= 64.0 && !sameColor(r.w, r.umw)
           && dist255(r.u2, r.u) > dist255(r.u2, E)
           && sameColor(r.u, r.uw) && sameColor(r.u, r.uw2) && sameColor(r.u, at(r.p + 3.0 * r.q))
           && dist255(r.u2mw, E) < min(dist255(r.u2mw, r.u), dist255(r.u2mw, r.w))
           && dist255(E, r.wmu) >= 20.0 && dist255(E, r.umw) >= 20.0;
  if (!middle && !four) return vec2(0.0);
  bool takes = sameColor(r.w, r.w2) && dist255(r.u, E) >= 64.0 && sameColor(r.w, r.w2mu)
            && dist255(r.wmu, E) < dist255(r.wmu, r.w) && luma(r.w) < luma(E);
  return vec2(1.0, takes ? 1.0 : 0.0);
}

// ---- 22. Crossed cuts ----
// Whether the cut of a corner of E, painted from the neighbor n (the pixel p, color u), crosses n's cut.
// It does when n's corner at the other end of their shared side is cut with the same second color flag,
// one of the two corners was blocked by the diagonal limit, and one of them draws a line along the shared
// side (the flag "along"). E and n must be close but distinct shades (under 64 apart, and at least 45 when
// the darker one sits on a ramp down to a still darker pixel past it), the lighter of the two must end a
// 45-degree stripe of its color along the corner's diagonal, and the darker one must differ from all 4 of
// its neighbors. eWord is E's decision word at the corner, blocked is E's blocked bit and loneE is 1.0
// when E differs from its 4 neighbors.
float back22(Roles r, vec3 E, float eWord, float blocked, float loneE)
{
  float along = abs(r.p.y) > 0.5 ? 16.0 : 64.0;
  if (BLEND(r.ru) == 0.0 || abs(FLAG(r.ru, 8.0) - r.s) > 0.5 || max(FLAG(r.ru, 128.0), blocked) < 0.5
      || max(FLAG(r.ru, along), FLAG(eWord, along)) < 0.5) return 0.0;
  float dn = dist255(E, r.u);
  if (dn >= 64.0) return 0.0;
  if (luma(r.u) > luma(E))
  {
    // n is the lighter one: it ends the stripe, and E is the darker one
    if (dn < 45.0 && luma(r.mu) < luma(E)) return 0.0; // a faint step on a ramp toward a darker pixel stays
    return sameAsOne(r.u, r.w, r.u2mw) * loneE;
  }
  if (dn < 45.0 && luma(r.u2) < luma(r.u)) return 0.0;
  return sameAsOne(E, r.umw, r.wmu) * apartFrom4(r.u, E, r.u2, r.uw, r.umw);
}
// A plain round corner of E that takes its color from p, where p is a darker pixel apart from its 4
// neighbors at the end of a lighter 45-degree stripe (the stripe ends at p - q, beside p), E, p, q and the
// corner pixel p + q are four colors, and p and the stripe's end cross their cuts (see back22): the stripe
// stops at p, so p's color leaks no tip into E.
float tip22(Roles r, vec3 E)
{
  float dl = dist255(r.umw, r.u);
  if (dl < 15.0 || dl >= 64.0 || luma(r.umw - r.u) <= 0.0) return 0.0;
  if (sameColor(r.u, r.w) || sameColor(r.u, r.uw) || sameColor(r.w, r.uw) || sameColor(E, r.uw) || sameColor(E, r.u)) return 0.0;
  if (!sameColor(r.umw, at(2.0 * (r.p - r.q))) || sameColor(r.u, r.u2)) return 0.0;
  if (BLEND(r.ru) == 0.0 || BLEND(r.rumw) == 0.0 || max(FLAG(r.ru, 128.0), FLAG(r.rumw, 128.0)) < 0.5) return 0.0;
  return 1.0;
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
//#crisp{
  ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;
//#crisp}
//#plain   vec2 ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;

  vec4 info = INFO_AT(0.0, 0.0);
//#crisp{
  vec4 blockedBit = FLAG(info, 128.0); // rule 2's bit, which info loses below
//#crisp}
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
  // The rules below that belong to the Crisp look read the neighborhood once: the decisions of the four
  // neighbors beside E, and, where a corner is still cut, the 3x3 colors around E, the 12 pixels at two
  // steps beside them and the decisions of the diagonal neighbors.
  vec4 line = FLAG(info, 4.0);
  vec4 sec = FLAG(info, 8.0);
  vec4 x22 = vec4(0.0);
  vec4 nn = vec4(0.0), ty = vec4(0.0), thinN = vec4(0.0), thinSteep = vec4(0.0);
  if (XBRZ_MINC > 0.0)
  {
    vec4 iB = INFO_AT(0.0, -1.0), iD = INFO_AT(-1.0, 0.0), iF = INFO_AT(1.0, 0.0), iH = INFO_AT(0.0, 1.0);
    if (anyCut(blendResult))
    {
      vec4 iA = INFO_AT(-1.0, -1.0), iC = INFO_AT(1.0, -1.0), iG = INFO_AT(-1.0, 1.0), iI = INFO_AT(1.0, 1.0);
      vec3 A = P(-1., -1.), B = P(0., -1.), C = P(1., -1.), D = P(-1., 0.), E = P(0., 0.);
      vec3 F = P(1., 0.), G = P(-1., 1.), H = P(0., 1.), I = P(1., 1.);
      // the pixels at two steps, named by their moves: l left, r right, u up, d down
      vec3 luu = P(-1., -2.), uu = P(0., -2.), ruu = P(1., -2.), llu = P(-2., -1.), ll = P(-2., 0.), lld = P(-2., 1.);
      vec3 rru = P(2., -1.), rr = P(2., 0.), rrd = P(2., 1.), ldd = P(-1., 2.), dd = P(0., 2.), rdd = P(1., 2.);

      // ---- 17. A line drawn on one side only ----
      // a corner that draws xBRZ's line in the line's own color, where the pixel across the line (O) draws
      // the same line in E's color, stays square: the line is E's color there, not a spike into E
      vec4 sh = haveShallowLine, st = haveSteepLine;
      vec4 on = isCut(blendResult) * line * abs(sh - st) * vec4(equal(sec, st));
      if (dot(on, vec4(1.0)) > 0.0)
      {
        // O's matching corner: x: shallow B.z, steep D.z; y: shallow F.w, steep B.w;
        // z: shallow H.x, steep F.x; w: shallow D.y, steep H.y
        vec4 oSh = vec4(iB.z, iF.w, iH.x, iD.y), oSt = vec4(iD.z, iB.w, iF.x, iH.y);
        vec4 o = mix(oSt, oSh, sh);
        vec4 oDraw = vec4(lessThan(o, vec4(128.0))) * cutOf(o) * FLAG(o, 4.0)
                   * mix(FLAG(o, 64.0), FLAG(o, 16.0), sh) * vec4(equal(FLAG(o, 8.0), sh));
        // the line is only two lone pixels: neither goes on along the line
        vec4 cSh = vec4(max(sameF(D, ll), sameF(C, rru)), max(sameF(B, uu), sameF(I, rdd)),
                        max(sameF(F, rr), sameF(G, lld)), max(sameF(H, dd), sameF(A, luu)));
        vec4 cSt = vec4(max(sameF(B, uu), sameF(G, ldd)), max(sameF(F, rr), sameF(A, llu)),
                        max(sameF(H, dd), sameF(C, ruu)), max(sameF(D, ll), sameF(I, rrd)));
        oDraw *= 1.0 - mix(cSt, cSh, sh);
        // and E's color does not repeat along the line (a dotted line with E as one of its dots)
        vec4 rSh = vec4(sameAsOne(E, rru, lld), sameAsOne(E, rdd, luu), sameAsOne(E, rru, lld), sameAsOne(E, rdd, luu));
        vec4 rSt = vec4(sameAsOne(E, ruu, ldd), sameAsOne(E, rrd, llu), sameAsOne(E, ruu, ldd), sameAsOne(E, rrd, llu));
        oDraw *= 1.0 - mix(rSt, rSh, sh);
        // and the line's color L, E and O are not an antialiasing ramp (for a steep line L and O swap,
        // which leaves the test the same)
        vec4 dLE = vec4(distYCbCr(D, E), distYCbCr(B, E), distYCbCr(F, E), distYCbCr(H, E));
        vec4 dOE = vec4(distYCbCr(B, E), distYCbCr(F, E), distYCbCr(H, E), distYCbCr(D, E));
        vec4 dLO = vec4(distYCbCr(D, B), distYCbCr(B, F), distYCbCr(F, H), distYCbCr(H, D));
        oDraw *= vec4(greaterThan(dLE + dOE, XBRZ_LONE_RAMP * dLO));
        blendResult *= 1.0 - on * oDraw;
      }

      // ---- 19. A pixel apart keeps to itself ----
      // a cut corner whose color comes from a pixel that differs from all 8 of its neighbors by XBRZ_ISO or
      // more, and keeps its own four corners square, stays square: the pixel does not leak into its neighbors
      if (anyCut(blendResult))
      {
        // the pixel each corner paints from: x: B or D, y: F or B, z: H or F, w: D or H (see sec)
        vec4 c19 = isCut(blendResult);
        float isoB = 0.0, isoD = 0.0, isoF = 0.0, isoH = 0.0;
        if (c19.x * sec.x + c19.y * (1.0 - sec.y) > 0.0) isoB = isoOf(B, luu, uu, ruu, A, C, D, E, F);
        if (c19.x * (1.0 - sec.x) + c19.w * sec.w > 0.0) isoD = isoOf(D, llu, A, B, ll, E, lld, G, H);
        if (c19.y * sec.y + c19.z * (1.0 - sec.z) > 0.0) isoF = isoOf(F, B, C, rru, E, rr, H, I, rrd);
        if (c19.z * sec.z + c19.w * (1.0 - sec.w) > 0.0) isoH = isoOf(H, D, E, F, G, I, ldd, dd, rdd);
        float sqB = squareOf(iB), sqD = squareOf(iD), sqF = squareOf(iF), sqH = squareOf(iH);
        vec4 iso = vec4(sec.x > 0.5 ? isoB : isoD, sec.y > 0.5 ? isoF : isoB, sec.z > 0.5 ? isoH : isoF, sec.w > 0.5 ? isoD : isoH);
        vec4 sq = vec4(sec.x > 0.5 ? sqB : sqD, sec.y > 0.5 ? sqF : sqB, sec.z > 0.5 ? sqH : sqF, sec.w > 0.5 ? sqD : sqH);
        blendResult *= 1.0 - iso * sq;
      }

      // ---- 20. A corner where no edge runs ----
      // a cut corner between two neighbors of clearly different colors (XBRZ_JUNCTION) stays square where
      // nothing goes on along the cut: neither neighbor's color continues past the corner, E's color does
      // not continue along the cut, and fewer than three pixels in a row cut that corner along the line
      // (a corner on a dark outline with an antialiasing pixel is left to xBRZ: see ramp20 and cr20)
      if (anyCut(blendResult))
      {
        vec4 cand20 = vec4(dist255(B, D), dist255(B, F), dist255(F, H), dist255(D, H));
        // the three colors E and the two neighbors of a corner form a ramp (their distances sum to under
        // RAMP + 1 times the longest), and one neighbor's color goes on just past the other along the cut
        vec4 dE1 = vec4(dist255(E, D), dist255(E, B), dist255(E, F), dist255(E, H));
        vec4 dE2 = dE1.yzwx;
        vec4 ramp20 = vec4(lessThan(dE1 + dE2 + cand20, (1.0 + XBRZ_JUNC_RAMP) * max(cand20, max(dE1, dE2))));
        vec4 cr20 = max(vec4(junctionNear(B, lld), junctionNear(F, luu), junctionNear(H, rru), junctionNear(D, rdd)),
                        vec4(junctionNear(D, ruu), junctionNear(B, rrd), junctionNear(F, ldd), junctionNear(H, llu)));
        vec4 lu20 = vec4(luma(D), luma(B), luma(F), luma(H));
        vec4 lmin20 = min(min(lu20, lu20.yzwx), vec4(luma(E)));
        // each neighbor's color past the corner, along the cut (x: D and B, y: B and F, z: F and H, w: H and D)
        vec4 ext1 = vec4(junctionNear(D, lld), junctionNear(B, luu), junctionNear(F, rru), junctionNear(H, rdd));
        vec4 ext2 = vec4(junctionNear(B, ruu), junctionNear(F, rrd), junctionNear(H, ldd), junctionNear(D, llu));
        // E's color on the pixels beside it along the cut
        float eAcross = max(junctionNear(E, G), junctionNear(E, C)), eAlong = max(junctionNear(E, A), junctionNear(E, I));
        vec4 extE = vec4(eAcross, eAlong, eAcross, eAlong);
        // the run of pixels that cut the same corner along the cut's line (E included, up to 2 on each side)
        vec4 m1 = cutOf(iA), m2 = cutOf(INFO_AT(-2.0, -2.0)), p1 = cutOf(iI), p2 = cutOf(INFO_AT(2.0, 2.0));
        vec4 u1 = cutOf(iC), u2 = cutOf(INFO_AT(2.0, -2.0)), d1 = cutOf(iG), d2 = cutOf(INFO_AT(-2.0, 2.0));
        vec4 runA = vec4(u1.x + u1.x * u2.x, m1.y + m1.y * m2.y, u1.z + u1.z * u2.z, m1.w + m1.w * m2.w);
        vec4 runB = vec4(d1.x + d1.x * d2.x, p1.y + p1.y * p2.y, d1.z + d1.z * d2.z, p1.w + p1.w * p2.w);
        vec4 on20 = isCut(blendResult) * vec4(greaterThan(cand20, vec4(XBRZ_JUNCTION)))
                  * (1.0 - ramp20 * cr20 * vec4(greaterThan(min(dE1, dE2), vec4(40.0))) * vec4(lessThan(min(dE1, dE2), vec4(70.0))) * vec4(lessThan(lmin20, vec4(0.35))))
                  * (1.0 - ext1) * (1.0 - ext2) * (1.0 - extE) * vec4(lessThan(1.0 + runA + runB, vec4(3.0)));
        blendResult *= 1.0 - on20;
      }

      // The four corners as seen from E, for rules 21 and 22.
      Frame fX = Frame(vX, hX, B, D, A, C, G, uu, ll, ruu, lld, llu, luu, H, F, iB.z, iD.z, iC.x, iG.x);
      Frame fY = Frame(vY, hY, F, B, C, I, A, rr, uu, rrd, luu, ruu, rru, D, H, iF.w, iB.w, iI.y, iA.y);
      Frame fZ = Frame(vZ, hZ, H, F, I, G, C, dd, rr, ldd, rru, rrd, rdd, B, D, iH.x, iF.x, iG.z, iC.z);
      Frame fW = Frame(vW, hW, D, H, G, A, I, ll, dd, llu, rdd, ldd, lld, F, B, iD.y, iH.y, iA.w, iI.w);

      // ---- 21. A straight line does not bend ----
      // a cut corner whose color comes from a pixel p in a straight line of its color along E's side (three
      // pixels centered on p, or a strong line of four that starts at p and runs toward the corner), where the
      // corner's other neighbor q differs from it by more than XBRZ_LINE_SIDE, does not take the line's color:
      // it takes q's color where q is darker than E and goes on along the cut, and otherwise stays square
      if (anyCut(blendResult))
      {
        Roles rX = roles(fX, sec.x), rY = roles(fY, sec.y), rZ = roles(fZ, sec.z), rW = roles(fW, sec.w);
        vec4 line21 = vec4(0.0), on21 = vec4(0.0);
        vec2 t;
        if (blendResult.x > 0.0) { t = straight21(rX, E); line21.x = t.x; on21.x = t.y; }
        if (blendResult.y > 0.0) { t = straight21(rY, E); line21.y = t.x; on21.y = t.y; }
        if (blendResult.z > 0.0) { t = straight21(rZ, E); line21.z = t.x; on21.z = t.y; }
        if (blendResult.w > 0.0) { t = straight21(rW, E); line21.w = t.x; on21.w = t.y; }
        // a corner that takes q's color becomes a plain corner (no line) in that color
        sec = abs(sec - on21);
        haveShallowLine *= 1.0 - on21;
        haveSteepLine *= 1.0 - on21;
        blendResult *= 1.0 - line21 * (1.0 - on21);
      }

      // ---- 22. Crossed cuts ----
      // a cut corner whose color comes from the neighbor n stays square when n's corner at the other end of
      // their shared side cuts back into E (the two cuts cross along that side), E and n are close shades
      // (under 64 apart), and the lighter of the two ends a 45-degree stripe of its color next to a darker pixel
      // that differs from its 4 neighbors (see back22); n's corner stays square the same way, so the side
      // between them is straight and the darker shade does not bulge into the stripe
      if (anyCut(blendResult))
      {
        Roles rX = roles(fX, sec.x), rY = roles(fY, sec.y), rZ = roles(fZ, sec.z), rW = roles(fW, sec.w);
                float loneE = apartFrom4(E, B, D, F, H);
        if (blendResult.x > 0.0) x22.x = back22(rX, E, info.x, blockedBit.x, loneE);
        if (blendResult.y > 0.0) x22.y = back22(rY, E, info.y, blockedBit.y, loneE);
        if (blendResult.z > 0.0) x22.z = back22(rZ, E, info.z, blockedBit.z, loneE);
        if (blendResult.w > 0.0) x22.w = back22(rW, E, info.w, blockedBit.w, loneE);
        blendResult *= 1.0 - x22;
        // and a round corner at the far end of such a lone darker pixel takes no tip of it (see tip22)
        vec4 t22 = vec4(0.0);
        if (blendResult.x > 0.0 && line.x < 0.5) t22.x = tip22(rX, E);
        if (blendResult.y > 0.0 && line.y < 0.5) t22.y = tip22(rY, E);
        if (blendResult.z > 0.0 && line.z < 0.5) t22.z = tip22(rZ, E);
        if (blendResult.w > 0.0 && line.w < 0.5) t22.w = tip22(rW, E);
        blendResult *= 1.0 - t22;
        x22 = max(x22, t22);
      }
    }

    // ---- 14. Straight steps ----
    // nn: the slope of a cut corner's line (0: xBRZ's), ty: its type (1 steep, 2 shallow); a free corner
    // next to the step pixel along the line (steep: E + v, shallow: E + h) takes that line's thin end
    vec4 lineOn = line * isCut(blendResult);
    vec2 r;
    if (lineOn.x > 0.0) { r = cornerStep(vX, hX, haveSteepLine.x, haveShallowLine.x); nn.x = r.x; ty.x = r.y; }
    if (lineOn.y > 0.0) { r = cornerStep(vY, hY, haveSteepLine.y, haveShallowLine.y); nn.y = r.x; ty.y = r.y; }
    if (lineOn.z > 0.0) { r = cornerStep(vZ, hZ, haveSteepLine.z, haveShallowLine.z); nn.z = r.x; ty.z = r.y; }
    if (lineOn.w > 0.0) { r = cornerStep(vW, hW, haveSteepLine.w, haveShallowLine.w); nn.w = r.x; ty.w = r.y; }
    vec4 free = vec4(equal(blendResult, vec4(0.0)));
    if (dot(free, vec4(1.0)) > 0.0)
    {
      vec4 cSt = free * vec4(drawsLine(iB.x), drawsLine(iF.y), drawsLine(iH.z), drawsLine(iD.w));
      vec4 cSh = free * vec4(drawsLine(iD.x), drawsLine(iB.y), drawsLine(iF.z), drawsLine(iH.w));
      if (dot(cSt + cSh, vec4(1.0)) > 0.0)
      {
        vec3 E0 = P(0., 0.);
        vec2 t;
        t = thinCorner(vX, hX, E0, cSt.x, cSh.x, FLAG(iB.x, 64.0), FLAG(iD.x, 16.0)); thinN.x = t.x; thinSteep.x = t.y;
        t = thinCorner(vY, hY, E0, cSt.y, cSh.y, FLAG(iF.y, 64.0), FLAG(iB.y, 16.0)); thinN.y = t.x; thinSteep.y = t.y;
        t = thinCorner(vZ, hZ, E0, cSt.z, cSh.z, FLAG(iH.z, 64.0), FLAG(iF.z, 16.0)); thinN.z = t.x; thinSteep.z = t.y;
        t = thinCorner(vW, hW, E0, cSt.w, cSh.w, FLAG(iD.w, 64.0), FLAG(iH.w, 16.0)); thinN.w = t.x; thinSteep.w = t.y;
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
  vec4 res = min(blendResult, vec4(1.0)) + 4.0 * line + 8.0 * sec + 16.0 * haveShallowLine + 64.0 * haveSteepLine;
  res = mix(res, 2.0 + 4.0 + 24.0 * (1.0 - thinSteep) + 64.0 * thinSteep, isThin);
  res += 32.0 * vec4(equal(slope, vec4(3.0))) + 128.0 * vec4(equal(slope, vec4(4.0)));
//#crisp}
//#plain   vec4 res = blendResult + 4.0 * FLAG(info, 4.0) + 8.0 * FLAG(info, 8.0) + 16.0 * haveShallowLine + 64.0 * haveSteepLine;
  FRAG_OUT = res / 255.0;
}

#endif

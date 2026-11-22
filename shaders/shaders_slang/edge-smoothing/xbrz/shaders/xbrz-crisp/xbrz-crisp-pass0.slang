#version 310 es
precision highp float;
precision highp int;
//#crisp{
// xBRZ crisp: xBRZ freescale that only rounds corners between clearly different colors.
//
// This is xbrz-freescale-multipass with a minimum contrast (rule 1) of 20: tools/make-multipass.py
// writes that shader, dropping the lines between //#crisp{ and //#crisp} and turning the //#plain
// lines on.
//#crisp}
//#plain // xBRZ freescale, multipass: xBRZ at any scale factor, in four passes.
//#plain //
//#plain // Rules 2, 4 to 7 and 10 below keep xBRZ from cutting corners into shapes the artist did not
//#plain // draw (fake diagonals at junctions of three colors, bent frames, rounded ends of stripes, a pixel
//#plain // closed between outlines). They are on by default; XBRZ_DIAG = 0 turns them off, for the
//#plain // reference xBRZ shapes. Rules 1, 3, 8, 9, 11 and 13 are the crisp look and run with XBRZ_MINC
//#plain // above 0; the xbrz-crisp preset sets it to 20, so low-contrast shading and textures keep their pixels.
//
// xBRZ decides, for each corner of each pixel, whether to cut it and how (a corner piece, a 45-degree
// line, or a shallow or steep line). The rules below then change some of those decisions. Each rule
// has a section of the same number and name in the code. The point pass decides once, at each point where
// 4 pixels meet, which way xBRZ blends there (as xBRZ's own preprocessing does), pass 0 makes each pixel's
// decisions from those of its 4 points, the resolve pass, also once per game pixel, finishes the rules
// that need the neighbours' decisions, and the output pass (pass 1) only draws the corners.
//#crisp{
// The match pass, between the resolve pass and pass 1, runs rules 26, 27 and 38 to 49.
//#crisp}
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
//    A 2:1 wedge is not brought back where it would lie against a third color (the neighbor along whose
//    side it runs is XBRZ_MINC or more from both the wedge's color and the pixel, and on no ramp with
//    them), like a dark wedge beside the blue line of a sword in Golden Sun.
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
//     wood, shading) keep xBRZ's lines. The thin end also goes to a pixel that is a close shade of the step
//     pixel (under XBRZ_THIN_TONE), in place of a cut of its own where it is a close shade of one neighbor of the
//     corner, so an antialiased side of a stroke runs as straight as a side in one color (a highlight on
//     red armor). Where the pixel past the line's far end is an area of a third color (clearly different from
//     the pixel and both neighbors at the corner, with a side neighbor in its own color; a checker is no area),
//     the corner keeps xBRZ's line, so a hood's light edge is not drawn up against the blue beside it (the boy
//     in Final Fantasy Tactics Advance). Before the step walk, a surviving non-line stub on a dark outline
//     (E.x <= XBRZ_DARK) that continues straight along the step beside a straight wall and an active 2:1 ramp
//     pixel couples to that 2:1 slope, and a clean 2-color 45-degree step (cand20 < XBRZ_SAME) flanked on both
//     diagonals by pixels of E's color drawing the same 2:1 slope follows that 2:1 curve.
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
//     Where three stripes run side by side at 2:1 (E's color goes on along the line on one side and the
//     paint color on the other), the line is drawn in its own color whether it is lighter or not, and even
//     where rule 2 blocked the corner, so a 1-pixel stripe between two others runs on unbroken (a black
//     stroke between magenta and blue, a dashed dark line on a slope).
// 17. A line drawn on one side only: where xBRZ cuts a corner with a line between two lone pixels
//     (neither goes on along the line and the pixel's own color does not repeat along it) but the
//     pixel across the line draws the same line in the first pixel's color, and the three colors are
//     not an antialiasing ramp, the corner stays square, so the line does not stick a spike into the
//     pixel, like the light gray pixel under the pot in Golden Sun's village.
// 18. Outlines closed: the line of rule 16 is also drawn in its own color through a pixel that is not
//     lone, where that line is a near-black outline (XBRZ_TINT_DARK) darker than the pixel, so an
//     outline that steps by a knight's move stays closed instead of letting the colors on both sides
//     touch, like a black outline between yellow and pink on a fighter's sprite. Unlike rule 16, the
//     line keeps its shallow or steep shape, so a band that runs along the outline stays straight (the
//     grey band of a hood). Not where the color the corner would take is near-black too: two dark shades
//     meet there and there is no outline to close (Isaac's shoulder).
// 19. A pixel apart keeps to itself: a corner is not painted with the color of a pixel that differs from
//     all 8 of its neighbors by XBRZ_ISO or more and keeps its own corners square, so a lone dot of
//     color, like the bead of a bracelet in Golden Sun's village, does not leak into the pixels around it.
//     Likewise, a square isolated dot sitting at the other cardinal neighbor of a right-angle block corner
//     (cand20 >= XBRZ_ISO_FAR) cannot push a diagonal spur into E.
//     Nor is a corner cut without a line painted with the color of a pixel none of whose 8 neighbors shares
//     its color, where the corner's other neighbor differs from it by XBRZ_ISO_FAR or more and the pixel
//     across the corner is neither color, like a dark green pixel on the Golden Sun slime (except when the
//     dot sits inline inside a matching circular ring, keeping a plain bevel).
// 20. A corner where no edge runs: a corner between two neighbors of clearly different colors
//     (XBRZ_JUNCTION) stays square where no line goes on through it (neither color continues past the
//     corner, the pixel's own color does not continue along the cut, and fewer than three pixels in a
//     row cut that corner), so a pixel at a junction of several colors keeps its square shape, while
//     antialiased curves, whose cuts run on, stay round. A corner on a dark outline with an
//     antialiasing pixel is still cut: the pixel and its two neighbors form a ramp (XBRZ_JUNC_RAMP),
//     the darkest of them is dark, and one neighbor's color goes on just past the other along the cut,
//     like the outline of a neck that runs on behind its transition pixel. On a looser ramp
//     (XBRZ_JUNC_RAMP2) a corner also stays round where another pixel cuts the same corner along the
//     line, or where the opposite corner of the pixel stays cut, so a pixel on an antialiased curve
//     is not cut at one end and square at the other, like the corner of a trunk in Minish Cap. Where the
//     pixel is one end of a strong ramp (XBRZ_JUNC_RAMP3), like foam on water, the ramp may be looser still.
//     At a
//     crossing of four clearly different colors, where the pixel is dark and darker than both neighbors and
//     the cut's color comes from a pixel that stands alone, a color that goes on only inside a flat area
//     is no line, so a dark outline pixel is not nibbled by a small detail beside it. At the end of a bar two
//     pixels wide whose two corners at the end are cut, the corner just under the end is cut too, so the tip
//     stays round, like the tip of a foot in Tales of Phantasia. A corner whose cut goes on as one straight
//     line through the facing corner of the neighbor that gives its color stays cut where its two neighbors
//     are much closer to each other than to the pixel, so a thin stroke between two background colors keeps
//     both its edges, like the halo of King Kai in Buu's Fury. Two shades are no junction: where E is a
//     close shade of one neighbor (under XBRZ_JUNC_TONE of the neighbors' distance) the corner is the edge of
//     E's area, like a highlight beside antialiased red; where the two neighbors are shades of one gray (both
//     nearly gray, under XBRZ_JUNC_GRAY, and their hue under XBRZ_JUNC_HUE apart) much closer to each other than
//     to E (XBRZ_JUNC_SHADE), they are one outline; and, for a nearly gray E, a shade of E's own gray along the
//     cut counts as E's color going on, so an outline in two grays that steps by a darker joint bends as in xBRZ
//     (the hood in a SNES portrait). Two shades of a color are not taken for one outline, so a belt and the
//     cloth above it meet a buckle with square corners on both sides (Isaac in Golden Sun). Where the pixel is
//     the middle step of a strong ramp between the area whose color the corner takes and the area on its other
//     side, both going on past it in line, it is no junction, so a light cheek meets orange and brown round (the
//     boy in Final Fantasy Tactics Advance); and the end of a 1-pixel diagonal stroke keeps its cut. On a
//     4-color orthogonal tile crosshair (where two adjacent quadrants are solid 2x2 blocks and both opposite
//     colors extend straight orthogonally), flat-block continuations, diagonal runs, and wide ramps do not
//     rescue the corner.
// 21. A straight line does not bend: a corner is not painted with the color of a pixel that lies in a
//     straight line of three of its color along the pixel's side, where the corner's other neighbor
//     differs from that line by more than XBRZ_LINE_SIDE, so the line goes on straight instead of
//     bending into the pixel, and checkered patterns keep their squares. A strong thin line of four that
//     starts beside the pixel and runs toward the corner counts too, and where the other neighbor is darker
//     and goes on along the cut, the corner takes that neighbor's color instead of staying square. On a
//     ramp (the two neighbors are close shades far from the pixel, and the cut goes on) the corner is cut.
//     At the tip of an outline that runs diagonally into an area of one color, the area is no line: the
//     corner is cut as in xBRZ where the area and the other neighbor are close shades of one background,
//     and otherwise takes the other neighbor's color (except where the line's color also surrounds the
//     opposite sides of E, preventing unrelated object bleed across a shared background), so the background
//     does not bite into the object, like the hand in Golden Sun's village.
//     The ramp also counts where the pixel's color goes on diagonally on the far side of the cut, or where
//     the pixel past it there is a close shade of the pixel (within XBRZ_LINE_TONE of its distance to the
//     line), so the tip of a V and a diagonal outline that steps along a straight line are cut as in xBRZ,
//     like the tip of a heart and the edge of a shield in The Minish Cap. Where the pixel is the bend of an
//     outline 1 pixel wide (its color goes on past both ends of the corner, diagonally beside the line and
//     on the side away from it) with contrast 64 or more, the line does not count either, so the outline
//     bends diagonally to its end, like the corner of the "0" in Golden Sun's battle menu.
// 22. Crossed cuts: where two neighboring pixels of close but distinct shades cut into each other from the two ends
//     of their shared side, the lighter one ends a 45-degree stripe of its color and the darker one
//     stands apart from its other neighbors, both corners stay square, so the darker shade does not
//     bulge into the stripe and the side between them is straight; the darker pixel then leaks no
//     round tip into the pixel past the stripe's end either.
// 24. A line with nothing to go on to: a 2:1 or 1:2 line between two colors XBRZ_HOOK or more apart is drawn only
//     where a corner at one of the two ends of its step is cut too (the pixel beside E along the line has the
//     other half of the line), and the corner is not a step of a straight edge (rule 14). Where none is, the corner
//     is a plain tip like a corner without a line, so the end of a 1-pixel bar, like the end of a letter's stroke,
//     does not grow a hook.
// 23. A loose pixel is a square with rounded corners: where a pixel differs from each of its 4 side neighbors by
//     XBRZ_LOOSE or more and from all 4 diagonal neighbors, and xBRZ cuts all 4 of its corners (a dot, an eye, a
//     highlight), the corners take a plain tip with no line and the output pass draws that tip smaller than a
//     normal one, so the pixel stays a square with softened corners instead of a circle.
//     A loose pixel with only 3 corners cut that differs from all 8 neighbors by XBRZ_LONE23 or more,
//     where those corners would take colors that differ from each other (a red eye between white, lilac
//     and purple), keeps the small tip only at a corner between two neighbors of the same color; a corner
//     between two different colors stays square, so no color around the dot reaches into it.
// 25. A point on a shared edge: where both corners of a pixel at one edge are cut with a 45-degree line in
//     the color across that edge (the two lines meet in a point), the pixel is the vertex of a V of its color
//     with no further arms, and the edge is straight and shared by three colors (XBRZ_POINT), both corners
//     stay square, so a small detail keeps its whole edge instead of an arrow tip, like the lower khaki pixel
//     of Isaac's sword hilt in Golden Sun's village.
// 26. Matching corners: a pass after the resolve pass compares each corner the resolve pass left square
//     with pass 0's decision. Where the square corner leaves a burr in a diagonal, it is cut again as pass 0
//     decided: in a clean line between two colors (the corner's two neighbors within XBRZ_MATCH_WRAP, the same
//     two pixels of both neighbors along the cut within XBRZ_MATCH_LINE) whose neighbors on both sides along
//     the cut are cut, so the line has no gap, or where the pixel diagonal to E across the corner's point cuts
//     the facing corner with a 45-degree line and pass 0 drew E's corner with no line, so the two cuts meet.
//     Only where E differs from one of the corner's two neighbors by more than XBRZ_MATCH_EDGE.
// 27. A bar at a vertex: where two arms of an outline end a knight's move apart and a bar of another color
//     (three pixels or more) comes down to the gap pixel between them, pass 0 cuts the gap pixel's corner
//     along a line in the bar's color, so the bar runs on past the vertex as a spike. The corner becomes a
//     plain 45-degree cut in the bar's color where the gap pixel is an in-between tone of the bar and the
//     outline, like the yellow bar between the red outlines of the Scooby-Doo 2 title, and otherwise the gap
//     pixel's corners under the bar stay square, so the bar ends flat (XBRZ_VERTEX_TOL, _EDGE, _BAR).
// 28. Two 2:1 cuts that cross: two pixels of one color a knight's move apart make xBRZ see a 2:1 line, and
//     the two pixels between them then cut into each other along their shared side, each with a 2:1 line in
//     the other's color, so the two colors seem to swap places. The pixel that is held less by its
//     surroundings keeps its cut, and the other stays whole: each of the 8 neighbors within XBRZ_HOLD_SAME
//     of a pixel's color counts for it, a side neighbor twice, and on a tie the darker pixel stays whole,
//     like the tree crowns of Golden Sun's Mt. Aleph.
// 29. The burr of a square stroke: the corner of a pixel at the tip of a dark outline (its color goes on only
//     on the side away from the corner) that xBRZ cuts with a line in the color of a lighter neighbor stays
//     square where that neighbor's own corner at the same point is square, the corner pixel has the other
//     neighbor's color, no pixel along the cut cuts the same corner and the three colors are clearly apart,
//     so the outline ends flat under a square stroke instead of taking a lone wedge of it, like the black
//     outline under Link's brown eyebrow in The Minish Cap.
// 30. Diagonal bands: where a diagonal band 1 pixel wide passes through a corner (two of the four pixels
//     that meet there share a color on one diagonal, the colors on its two sides go on along it, and the
//     far side differs from the pixel by XBRZ_BAND_FAR or more for a band of three pixels, XBRZ_BAND_FAR2
//     for a band of two), all four pixels keep xBRZ's cut at that corner, even below the minimum contrast
//     and whatever the rules above decide, so a shadow under a line or the steps of an antialiasing ramp
//     are drawn as straight bands instead of squares, like the shadow under a sword in Golden Sun.
//     A corner that rule 1 left square also keeps xBRZ's cut where a dark outline 1 pixel wide runs
//     diagonally around a pixel XBRZ_RING or more from it, on the background side and at the outline's own
//     outer corners, so the outline of a bright shape stays a closed diagonal ring over a low-contrast
//     background, like an orange diamond on a scaffold.
// 31. Exact ties: where xBRZ's two diagonal sums of a 2x2 checkerboard of two colors (64 or more apart)
//     are exactly equal, xBRZ cuts neither corner and the two diagonals touch. Where only one diagonal
//     goes on as a stroke 1 pixel wide, the rarer of the two colors in the 8x8 around it wins and keeps
//     its diagonal joined, and the other is cut where each of its two pixels has a neighbor of its own
//     color, so a dark outline closes on a light background and a light stroke on a dark one (the "O" of
//     YOSHI in Zenju's test image, a kanji in Harry Potter).
// 32. Lone pixel test redone: xBRZ draws no line through a pixel that has another corner cut, but where
//     the rules above left that other corner square, a corner with contrast 64 or more inside a stroke 1
//     pixel wide that bends gets xBRZ's line back, like the same corner on the other side of the stroke
//     (the inside of the "0" in Golden Sun's battle menu), unless E's own color stops within 2 pixels.
// 33. Hole in a thick stroke: the inner corner of a thick dark stroke that bends, with an antialiasing
//     pixel of a third color at the outer corner, keeps only the small cut, without a line, so a hole
//     in a digit has the same four corners.
// 34. Small square of close shades: in a 2x2 of close shades that are not all exactly equal, closed on
//     its 8 side neighbors by one color (48 or more apart), the outer corner is only rounded, without a
//     line, so the four corners match (the studs in Street Boxing's fence).
// 35. Edge of a thin band: along a band 1 pixel wide that runs on in a 2:1 line, with a strong color
//     past it and close shades on E's side, the lone pixel test uses the reference tolerance (30) also
//     at medium contrast (40 to 64), as rule 15 does at 64, so the band's edge has no tooth.
// 36. Crossing strokes: in a 2x2 where one diagonal has one exact color and the other two close shades of
//     one stroke, far from the first, the stroke is joined where each of its two pixels goes on outward by
//     one pixel of its shades at a side (a stroke 1 pixel wide) and the exact color has two or more pixels
//     outward (a mass), so a thin halo crossed by a skirt in Buu's Fury stays whole. A dark outline beside a
//     dull stroke (XBRZ_X36_DARK, XBRZ_X36_DULL) separates two areas and stays joined.
// 37. A contour by a knight's move: where a corner takes the color of a neighbor P while the other neighbor
//     has the color of the pixel just past P (the two a knight's move apart) and P's facing corner on the same
//     cut already takes that color, the corner takes the other neighbor's color, so an outline that skips a
//     pixel follows the edge instead of leaving a sliver of the inner color outside it (Golden Sun's village).
//     P must not be a shade between the outline and the pixel.
//     The other neighbor and the pixel past P may also be two shades of one outline, much closer to each
//     other than to P, like a shoulder in Golden Sun's battles.
//     Not where the other neighbor's color goes on at the pixel diagonal to E: it runs straight on there and
//     does not turn, and the corner would be a loose tip of it (a blue dot on a black block). Where it runs
//     straight on both ways and E is the corner of a solid block of its color, the corner stays square.
// 38. A junction of four colors: where a side neighbor that the resolve pass keeps whole meets E and two
//     more pixels at a point where all four colors differ by more than XBRZ_JUNC4, and the pixel diagonal to
//     E cuts its corner there, E's corner there stays square too (unless it is a 2:1 line), so it does not
//     paint the whole pixel's color or end as a lone ramp against its square side (Golden Sun's menu frame).
//     Not where the two colors the cut joins are two shades of one stroke (under XBRZ_STEP38 as far apart as
//     the other colors), like the dark brown and brown outline of a hood, which bends there as in xBRZ.
//     A 3+ color corner (pairSq >= XBRZ_JUNC4^2) on a 1-pixel bar flush against a 4-color orthogonal crosshair
//     likewise stays square so straight tile-border bars do not notch across the seam.
// 39. A tie on a ramp: where E's two neighbors at a corner are equally far from E and E lies on the straight
//     ramp between them, neither color has a better claim to the corner when the pixel across it is a
//     fourth color, so the corner stays square and E touches both, like the light pink under the white of
//     Harry's eye. A near tie (within XBRZ_MID39) counts too where the pixel across the corner is
//     XBRZ_FAR39 or more from all three and no 2:1 line runs there, like a grey leaf.
// 40. A dot that separates: a lone dot (40 or more from all 8 neighbors, like a nostril between skin
//     tones) whose ring of neighbors holds a color K in two or more separate groups (the shadow under an eye
//     and a mouth, on two sides of Harry's nose) keeps them apart when it is darker than K and K is darker
//     than the rest of the ring: a corner next to the dot that would paint K stays square, and the dot's
//     own corners take rule 23's small tip, so K is not drawn as one stroke through the dot.
// 41. A 1-pixel diagonal stroke keeps an even edge: on a stroke 1 pixel wide whose color goes on only
//     diagonally, an outer corner that xBRZ leaves square between two side neighbors of different colors is
//     cut along the stroke where the stroke is darker than both, like the black outline at Harry's knees,
//     and two 2:1 lines that lean opposite ways at one edge, squeezing the stripe into a thin tip, are
//     drawn as a 45-degree cut and a plain cut, like the olive stripe on the Golden Sun slime. On a true
//     45-degree convex apex (two diagonals of E's color behind one edge, excluding parallel stem walls),
//     colliding 2:1 cuts are stripped to 45 degrees and a missing multi-tone 45-degree corner whose two
//     outer neighbors are closer to each other than to E (pairSq < minSideSq) is completed when confirmed
//     by an adjacent 45-degree line in E's color.
// 42. A step in a 45-degree edge: a corner that xBRZ leaves square, where its two neighbors at the corner and
//     the pixel across it are one color K (XBRZ_MINC or more from E) and E's other two neighbors are not K,
//     is cut along the edge when the same corner of both pixels along the edge is cut with a 45-degree line
//     painting K. xBRZ leaves such a corner square where its two diagonals nearly tie and a pixel farther
//     away tips them the other way, which leaves a square step in a straight diagonal edge.
// 43. A dome: where the resolve pass took back a corner of a 2-pixel run, and a cap color runs over the run
//     and past both ends while the run ends on both sides in one other color, the corner is cut again (if the
//     mirror corner of the run's other pixel is cut), so the cap ends round on both sides, like the top of
//     a wizard's hair under his hood.
// 44. The end of a dark 1-pixel stroke: where E ends a stroke 1 pixel wide and the 7 pixels around that end
//     are XBRZ_END44 or more from it and lighter, E's two corners at the end are cut, so a dark mark ends
//     round at both ends, like a pupil under a white eyelid (Isaac's eye) or the end of a font's shadow.
//     Not a corner past which E's color goes on by a knight's move, where the pixel diagonal to E cuts its
//     corner toward it: the stroke turns there as an outline (rule 37), so it leaves no tip of the other color
//     (the flame of a fire horse).
// 45. The end of a mid-tone stroke: where E ends a stroke 1 pixel wide, only one corner at the end is cut,
//     with a 2:1 line, the three pixels around that corner are close tones of E (XBRZ_MINC to
//     XBRZ_MATCH_EDGE from it, the two side ones two different tones) and the pixel on E's other side is 80
//     or more away, the corner stays square, so the stroke ends square (a gray seam on Isaac's shoulder).
// 46. A checkerboard keeps its squares: a 2x2 checker of two colors (or a shaded/gradient checker and a
//     high-contrast 1-parity 50% mesh transparency overlay) with three or more of the 2x2 blocks beside it
//     (2 pixels left, right, above and below) matching its parity, or forming a 2x6 axial checker strip
//     bounded laterally by axis-aligned walls, is not cut; likewise a 1x4 solid wall immediately adjacent to
//     a confirmed 2x4 exact or shaded checker strip keeps its squares, so checker dithering and 50% HUD mesh
//     overlays stay square right up to their borders without affecting 1-pixel dotted lines or diagonal strokes.
// 47. A notch in a straight stroke: where E's corner would be cut in the color of a lone pixel beside it
//     that is a close shade of E, while E's color goes on straight past its other neighbor and diagonally
//     past the lone pixel, and the color on E's far side is XBRZ_FAR47 or more away, the corner stays square,
//     so a shade at the bend of a stroke does not cut a notch into its straight side (a wizard's staff).
// 48. One slope beside a lone shade: where E's corner is cut by a shallow or steep line whose long side runs
//     along the edge E shares with the neighbor A whose color it takes, and A's corner at the other end of
//     that edge is cut at 45 degrees in E's color, while A and E are close shades (under XBRZ_SHADE48) and one
//     of them is a lone pixel in a stroke of the other's color, E's corner is cut at 45 degrees too: the two
//     cuts lie on one straight diagonal, so a light pixel in a staff keeps its slant with no step in its middle.
// 49. A 1-pixel diagonal bar ends even: where E ends a stroke 1 pixel wide that goes on only diagonally (its
//     color goes on at one diagonal, and E and the next pixel are XBRZ_BAR49 or more from all their other
//     neighbors), lighter or darker than both pixels beside it and drawn joined, E's two side corners are cut at
//     45 degrees in the color beside the stroke (when that side color matches either the far side or the corner
//     pixel within 100 YCbCr, preventing foreign-color leaks) and its end corner at 45 degrees in the nearer
//     neighbor, so the stroke is an even bar with a straight end (a light stroke on the boy's shoulder in Final
//     Fantasy Tactics Advance). The end stays as it is where the stroke runs on into a region on its own side of
//     the sides' shades (a dark stroke into an outline) or into one region that holds both pixels at the end corner
//     (a dark line that meets a white branch), and no corner is cut where a neighbor already draws the stroke's
//     color across it. A neighbor's corner at the point where a side cut actually paints that neighbor is not cut
//     in the color from the stroke's other side, so that color does not wrap around the bar's end.
// 50. Drop shadow in a 1-pixel cavity: where a mid-tone background pixel (0.12 < E.x < 0.72) is cut on
//     separate corners by both a bright foreground stroke (like a 1-pixel HUD letter) and a dark drop shadow,
//     the dark shadow bevel is suppressed so small glyph bowls stay open; likewise a near-black drop-shadow
//     pixel (E.x <= 0.08) tucked against a bright 1-pixel stroke does not bevel its mid-tone background corner.
// XBRZ_DIAG = 0 turns rules 2 to 7, 9, 10 and 13 off, and XBRZ_MINC = 0 turns rules 1, 3, 8, 9, 11 and
// 13 to 50 off, so with XBRZ_MINC at 0 only rules 2, 4 to 7 and 10 run.
//#crisp}
//#plain // XBRZ_DIAG = 0 turns rules 2 to 7, 9, 10 and 13 off, and XBRZ_MINC = 0 turns rules 1, 3, 8, 9, 11
//#plain // and 13 off, so with XBRZ_MINC at 0 only rules 2, 4 to 7 and 10 run.
//
// The point pass decides each point once and keeps the image's color next to that decision, pass 0
// makes every blend decision once per input pixel (blend type, line type, blend color and the minimum
// contrast) and the resolve pass, also once per input pixel, settles the ones that depend on the
// neighbours' decisions, so the output pass, which runs once per output pixel, only reads two textures
// where no corner is cut. Blend color ties (to within 1e-5, as the integer colors of the C++ code tie),
// the order of the four corners and the cut of a corner with both a shallow and a steep line follow the
// reference C++ xBRZ, and every pass reads the image from the point pass, which keeps the colors of the
// pass before xBRZ, so it also works after other shaders in a preset.
// Defaults: equal color tolerance 15, dominant direction 3.8, steep/shallow line 3.2
// (reference xBRZ 1.9: 30, 3.6 and 2.4).
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
// Pass 0 of xbrz-crisp (Vulkan / slang)
//#crisp}
//#plain // Pass 0 of xbrz-freescale-multipass (Vulkan / slang)

layout(push_constant) uniform Push
{
	vec4 SourceSize;
	vec4 OutputSize;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
	float XBRZ_TOL;
	float XBRZ_DOM;
	float XBRZ_STEEP;
	float XBRZ_MINC;
	float XBRZ_DIAG;
} global;

#pragma parameter XBRZ_TOL "xBRZ: equal color tolerance (x/255)" 15 1 80 1
#pragma parameter XBRZ_DOM "xBRZ: dominant direction threshold" 3.8 1 8 0.05
#pragma parameter XBRZ_STEEP "xBRZ: steep/shallow line threshold" 3.2 1 6 0.1
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
//#plain-default XBRZ_MINC 0
#pragma parameter XBRZ_DIAG "xBRZ: max color distance on the diagonal (0 = off)" 100 0 160 4
#define XBRZ_TOL global.XBRZ_TOL
#define XBRZ_DOM global.XBRZ_DOM
#define XBRZ_STEEP global.XBRZ_STEEP
#define XBRZ_MINC global.XBRZ_MINC
#define XBRZ_DIAG global.XBRZ_DIAG

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
layout(set = 0, binding = 2) uniform sampler2D Source;
#define SRC_SIZE params.SourceSize
#define P4(x,y) texture(Source, coord + SRC_SIZE.zw * vec2(x, y))
#define P(x,y) P4(x, y).rgb

#define BLEND_NONE 0
#define BLEND_NORMAL 1
#define BLEND_DOMINANT 2
#ifndef TOL_E
#define TOL_E XBRZ_TOL
#endif
#ifndef DOM_E
#define DOM_E XBRZ_DOM
#endif
#ifndef STEEP_E
#define STEEP_E XBRZ_STEEP
#endif
#define EQUAL_COLOR_TOLERANCE (TOL_E / 255.0)
// two distances closer than this are a tie (the float colors of equal integer steps differ in the last bits)
#define TIE_EPS 1e-5

// The decision of each corner of E (x top-left, y top-right, z bottom-right, w bottom-left), written
// to the info texture as a number from 0 to 255:
//   BLEND(r)       blend type: 0 none, 1 normal, 2 dominant, 3 weak (rule 1: the resolve pass decides)
//   FLAG(r, 4.0)   xBRZ's line blend (without it only the tip of the corner is cut)
//   FLAG(r, 8.0)   the corner blends with the second of its two candidate colors
//   FLAG(r, 16.0)  shallow line
//   FLAG(r, 32.0)  the line was found only because hue weighs more (rule 9)
//   FLAG(r, 64.0)  steep line
//   FLAG(r, 128.0) blocked by the diagonal limit (rule 2: the resolve pass decides)
// The candidate colors of the corners x, y, z and w are D or B, B or F, F or H and H or D. Below, the
// one a corner blends with is P and the other one Q.
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)

// ---- rule tunables (XBRZ_MINC and XBRZ_DIAG are in the menu) ----
// rules 3, 9 and 13 belong to the crisp look rather than fixing clear xBRZ errors, so they
// run only when XBRZ_MINC is on too (plain xBRZ, with XBRZ_MINC 0, keeps rules 2, 4 to 7 and 10)
#define CRISP_RULES (XBRZ_MINC > 0.0 && XBRZ_DIAG > 0.0)
#define XBRZ_ALIKE 20.0        // colors this close (x/255) count as alike
#define XBRZ_HYST 4.0          // 1. a corner this close below XBRZ_MINC is weak
#define XBRZ_RAMP 1.15         // 2, 6. a ramp: (d(E,P) + d(P,Q)) / d(E,Q) up to this
#define XBRZ_STRIPE 64.0       // 2, 3. a diagonal stripe keeps a close color (within this) along its length
#define XBRZ_OUTLINE 0.15      // 2, 3. an outline is darker (in luma) than both inner tones by this much
#define XBRZ_NOT_LIGHTER 4.0   // 2. P is not lighter than E up to this much more luma (x/255)
#define XBRZ_THIN_LIGHT 0.15   // 5. a thin stroke is lighter (in luma) than both of its colors by this much
#define XBRZ_THIN_DARK 0.45    // 5. on colors darker than this (luma) the stroke counts without the test of its sides
#define XBRZ_TONE 0.6          // 5, 6. a pixel has E's tone when it is closer to E than this times its distance to the other colors
#define XBRZ_NOTCH 45.0        // 6. the notch's diagonal limit is XBRZ_DIAG plus this
#define XBRZ_TIP 36.0          // 7. stripe ends stay square above this diagonal distance
#define XBRZ_AA_LINE 1.01      // 8. E lies between the colors: d(P1,E) + d(E,P2) up to this times d(P1,P2)
#define XBRZ_AA_OFF 1.2        // 8. three colors are on no ramp when the two short steps add up to more than this times the long one
#define XBRZ_AA_EDGE 40.0      // 8. the two colors differ by at least this
#define XBRZ_FAR_TONE 36.0     // 9. two colors that clearly differ: more than this apart
#define XBRZ_BLACK 0.15        // 10. a near-black outline is darker than this (luma)
#define XBRZ_BLACK_GAP 0.1     // 10. the outline is darker (luma) than E and the pixel closed by it by this much
#define XBRZ_STRONG 40.0       // 11. the contour past a 1-pixel stripe differs from it by at least this
#define XBRZ_GUARD 30.0        // 15. lone pixel test tolerance on strong edges (reference xBRZ)
#define XBRZ_GUARD_EDGE 64.0   // 15. a strong edge: the pixel differs from both corner colors by this much
#define XBRZ_GUARD_EDGE_L 54.0 // 15. the same for the L-shape test
#define XBRZ_TINT 20.0         // 16. the two colors beside the line differ by more than this
#define XBRZ_TINT_RAMP 1.2     // 16. not a ramp: d(E,P) + d(P,L) above this times d(E,L)
#define XBRZ_TINT_DARK 0.25    // 18. a near-black outline is darker than this (luma)
#define XBRZ_BAND_FAR 20.0     // 30. the color past a band of three pixels or more differs from the pixel by this
#define XBRZ_BAND_FAR2 30.0    // 30. and past a band of two pixels by this
#define eq(a,b)  (a == b)
#define neq(a,b) (a != b)

// the ring of pixels two steps from E (the 5x5 window without its corners), read once and pre-converted to linear YCbCr in main
vec3 N_m1_m2, N_p0_m2, N_p1_m2, N_m2_m1, N_p2_m1, N_m2_p0, N_p2_p0, N_m2_p1, N_p2_p1, N_m1_p2, N_p0_p2, N_p1_p2;

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

float luma(vec3 c) { return dot(c, LUMA_W); }

float distSqY(vec3 a, vec3 b)
{
  vec3 d = a - b;
  return dot(d, d);
}

float distY(vec3 a, vec3 b) { return sqrt(distSqY(a, b)); }
float distY255(vec3 a, vec3 b) { return distY(a, b) * 255.0; }

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

// Squared threshold in [0..255] YCbCr units, kept in [0..1.5] so GLSL ES mediump never overflows
#define SQ255(x) (((x) / 255.0) * ((x) / 255.0))
// FP16-safe division guard (> 6.1e-5 smallest FP16 normal) so FTZ GPUs never produce NaN
const float SAFE_EPS = 1e-4;

bool within255(vec3 pixA, vec3 pixB, float lim)
{
  return distSqYCbCr(pixA, pixB) < SQ255(lim);
}

bool withinEq255(vec3 pixA, vec3 pixB, float lim)
{
  return distSqYCbCr(pixA, pixB) <= SQ255(lim);
}

bool withinY255(vec3 a, vec3 b, float lim)
{
  return distSqY(a, b) < SQ255(lim);
}

bool withinEqY255(vec3 a, vec3 b, float lim)
{
  return distSqY(a, b) <= SQ255(lim);
}

// Unified hue-shifting-tolerant AA / sel-out ramp check in YCbCr space (0 sqrt).
// True when m lies strictly between endpoints a and b along their chord with
// bounded orthogonal deviation (allowing pixel-art hue-shifting) and monotonic luma.
bool isAaRampY(vec3 a, vec3 m, vec3 b, float orthoTolSq, float minSpanSq)
{
  vec3 ab = b - a;
  float abSq = dot(ab, ab);
  if (abSq < minSpanSq) return false;
  vec3 am = m - a;
  float proj = dot(am, ab);
  if (proj <= 0.05 * abSq || proj >= 0.95 * abSq) return false;
  float t = proj / abSq;
  vec3 err = am - t * ab;
  if (dot(err, err) > orthoTolSq * abSq) return false;
  float loY = min(a.x, b.x), hiY = max(a.x, b.x);
  if (hiY - loY > 0.08 && (m.x < loY - 0.02 || m.x > hiY + 0.02)) return false;
  return true;
}
#define PY(x, y) toYCbCr(P(x, y))

#define at5x5(coord, o) PY((o).x, (o).y)

bool alike(vec3 a, vec3 b) { return withinEqY255(a, b, XBRZ_ALIKE); }

// D4-invariant tie-breaker when two candidate neighbor distances are equal within TIE_EPS:
// breaks exact ties by color order (Y, Cb, Cr) so rotations and reflections pick the same color.
float pickSecond(float d1, float d2, vec3 c1, vec3 c2)
{
  if (d1 + TIE_EPS < d2) return 0.0;
  if (d2 + TIE_EPS < d1) return 1.0;
  if (abs(c1.x - c2.x) > SAFE_EPS) return float(c2.x < c1.x);
  if (abs(c1.y - c2.y) > SAFE_EPS) return float(c2.y < c1.y);
  return float(c2.z < c1.z);
}

// The distance is symmetric, and below the two pixels of each distance (and of alike and IsPixEqual) are
// written in one fixed order (A to I, then the ring of pixels two steps away), so the compiler computes
// each distance only once. The pixels two steps away are read once, at the start of main.
bool IsPixEqual(vec3 pixA, vec3 pixB)
{
  return withinY255(pixA, pixB, TOL_E);
}

// 15. Lone pixel and L-shape tests on strong edges: the tolerance of xBRZ's lone pixel test and L-shape
// test in the blend decisions; edge is how much E differs from the closer corner color, and edgeLimit
// how much that must be (XBRZ_GUARD_EDGE or XBRZ_GUARD_EDGE_L) for the reference tolerance to apply
bool equalOnEdge(vec3 pixA, vec3 pixB, float edge, float edgeLimit)
{
  return withinY255(pixA, pixB, XBRZ_MINC > 0.0 && edge * 255.0 >= edgeLimit ? XBRZ_GUARD : TOL_E);
}

// xBRZ's test of whether a corner (blend type own) is cut, in the corner's own frame: c2 is the diagonal
// pixel of the corner and c0 to c4 run around it (for the bottom-right corner G H I F C), and nbr0 and
// nbr4 are the blend types of the two corners beside it, nbr0 the one on the c4 side and nbr4 the one on
// the c0 side (for the bottom-right corner, the top-right and bottom-left corners). A dominant corner is always
// cut. A normal one is not cut when the lone pixel test fails (the corner beside it on the c4 side is cut
// and E differs from c0, or the corner on the c0 side is cut and E differs from c4) or when the L-shape
// test holds (c0 to c4 are one color around the corner pixel c2, which E does not share)
bool cornerCut(int own, int nbr0, int nbr4, float edge, vec3 E, vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4)
{
  if (own == BLEND_DOMINANT)
    return true;
  if (own != BLEND_NORMAL)
    return false;
  bool lone0 = nbr0 != BLEND_NONE && !equalOnEdge(E, c0, edge, XBRZ_GUARD_EDGE);
  if (lone0)
    return false;
  bool lone4 = nbr4 != BLEND_NONE && !equalOnEdge(c4, E, edge, XBRZ_GUARD_EDGE);
  if (lone4)
    return false;
  bool lShape = equalOnEdge(c0, c1, edge, XBRZ_GUARD_EDGE_L) && equalOnEdge(c1, c2, edge, XBRZ_GUARD_EDGE_L) &&
                equalOnEdge(c3, c2, edge, XBRZ_GUARD_EDGE_L) && equalOnEdge(c4, c3, edge, XBRZ_GUARD_EDGE_L) &&
                !equalOnEdge(E, c2, edge, XBRZ_GUARD_EDGE_L);
  return !lShape;
}

// ============================================================================================
// 9. Line shapes
// ============================================================================================
// the extra distance for the shallow and steep line tests with the crisp rules on (a line passes with
// it or with xBRZ's): hue weighs 1.2x more than lightness, scaled so that as many neighbour pairs pass
// the thresholds (inputs are linear YCbCr)
float DistShapeSq(vec3 a, vec3 b)
{
  vec3 d = vec3(0.937, 1.125, 1.125) * (a - b);
  return dot(d, d);
}

// a line xBRZ finds that the hue-weighted test does not is kept too, except where it would bring
// back a corner blocked by the diagonal limit (rule 2), or where the line's color runs on along a
// 45-degree diagonal in the same color while the line test pairs it with a different one (alt45)
bool plainLineSq(float abSq, float cdSq, float st2, float pairDSq, bool alt45)
{
  return st2 * abSq <= cdSq && pairDSq <= SQ255(XBRZ_DIAG) && !alt45;
}

// a shallow or steep line found only because hue weighs more (DistShape) between two different
// colors is flagged +32, so the resolve pass can drop it where it runs into the neighbour's line
float toneLineSq(float abSq, float cdSq, float st2)
{
  return float(abSq >= SQ255(TOL_E) && st2 * abSq > cdSq);
}

// a line found only because hue weighs more (+32) is dropped where the pixel at its far end is closer
// to E than to the line's color: that pixel belongs to E's side, so the line would cut into E's run.
// It is also dropped where its two colors clearly differ (more than XBRZ_FAR_TONE) and the line's color runs on
// along a 45-degree diagonal in the same color (alt45, as for plainLine): the line would bend that
// diagonal toward another stroke (the tip of Goku's nose in Buu's Fury)
bool farToneSq(vec3 b, float abSq, float tone, vec3 E, bool alt45)
{
  return !(tone > 0.5 && (distSqY(E, b) < abSq || (alt45 && abSq > SQ255(XBRZ_FAR_TONE))));
}

// the shallow (x) and steep (y) line tests of a corner, a line along a-b against one along c-d, as
// the flags they add (+16 and +64, and +32 for a line found only because hue weighs more): xBRZ's own
// test (STEEP_E * d(a, b) <= d(c, d)) without the crisp rules, the hue-weighted one with them
vec2 lineTests(vec3 a, vec3 b, vec3 c, vec3 d, vec3 E, float pairDSq, bool alt45s, bool alt45t)
{
  float abSq = distSqY(a, b), cdSq = distSqY(c, d), st2 = STEEP_E * STEEP_E;
  if (!CRISP_RULES)
    return vec2(st2 * abSq <= cdSq ? 16.0 : 0.0, st2 * cdSq <= abSq ? 64.0 : 0.0);
  float sabSq = DistShapeSq(a, b), scdSq = DistShapeSq(c, d);
  float toneSh = toneLineSq(abSq, cdSq, st2), toneSt = toneLineSq(cdSq, abSq, st2);
  float shallow = (((st2 * sabSq <= scdSq) && farToneSq(b, abSq, toneSh, E, alt45s)) || plainLineSq(abSq, cdSq, st2, pairDSq, alt45s)) ? 16.0 + 32.0 * toneSh : 0.0;
  float steep = (((st2 * scdSq <= sabSq) && farToneSq(d, cdSq, toneSt, E, alt45t)) || plainLineSq(cdSq, abSq, st2, pairDSq, alt45t)) ? 64.0 + 32.0 * toneSt : 0.0;
  return vec2(shallow, steep);
}

// ============================================================================================
// 30. Diagonal bands
// ============================================================================================
float bandSide(vec2 coord, vec2 o, vec2 p, vec2 q, vec3 e, vec3 cp, vec3 cpq)
{
  vec2 t = p - q;
  if (eq(cp, cpq))
  {
    bool a = eq(e, at5x5(coord, o + t)), b = eq(e, at5x5(coord, o - t));
    if (!a && !b) return 0.0;
    vec3 opp = at5x5(coord, o - p - q);
    float dSq = distSqY(opp, cp);
    if (dSq <= distSqY(opp, e) || dSq < SQ255(XBRZ_BAND_FAR)) return 0.0;
    if (dSq >= SQ255(XBRZ_BAND_FAR2) || (a && b)) return 1.0;
    return (a ? eq(e, at5x5(coord, o + 2.0 * t)) : eq(e, at5x5(coord, o - 2.0 * t))) ? 1.0 : 0.0;
  }
  float dAESq = distSqY(cpq, e);
  if (dAESq <= distSqY(cpq, cp) || dAESq < SQ255(XBRZ_BAND_FAR)) return 0.0;
  if (!eq(cpq, at5x5(coord, o + 2.0 * p)) && !eq(cpq, at5x5(coord, o + 2.0 * q))) return 0.0;
  if (!eq(e, at5x5(coord, o + t)) && !eq(e, at5x5(coord, o - t))) return 0.0;
  if (dAESq >= SQ255(XBRZ_BAND_FAR2)) return 1.0;
  return (eq(cp, at5x5(coord, o + p + t)) || eq(cp, at5x5(coord, o + q - t))) ? 1.0 : 0.0;
}

// 32 to 34: two close shades (under 30 apart)
bool near(vec3 a, vec3 b) { return withinY255(a, b, 30.0); }

vec4 diagonalBands(vec4 xbrz, vec4 mask, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  vec4 band = vec4(0.0);
  vec4 cut = vec4(greaterThan(BLEND(xbrz), vec4(0.0))) * mask;
  if (XBRZ_MINC <= 0.0 || dot(cut, vec4(1.0)) <= 0.0)
    return band;
  for (int k = 0; k < 4; k++)
  {
    vec4 m = vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
    if (dot(cut, m) < 0.5) continue;
    vec2 v = vec2(0.0, k < 2 ? -1.0 : 1.0), h = vec2(k == 1 || k == 2 ? 1.0 : -1.0, 0.0);
    vec3 cV = k < 2 ? B : H, cH = k == 1 || k == 2 ? F : D;
    vec3 cVH = k == 0 ? A : (k == 1 ? C : (k == 2 ? I : G));
    bool vh = eq(cV, cH);
    if (!vh && !eq(E, cVH)) continue;
    float f = 0.0;
    for (int j = 0; j < 2; j++)
    {
      if (f > 0.5) continue;
      bool first = j == 0;
      vec2 o = vh ? (first ? vec2(0.0) : v + h) : (first ? v : h);
      vec2 p = vh ? (first ? v : -v) : (first ? -v : v);
      vec2 q = first ? h : -h;
      vec3 e   = vh ? (first ? E : cVH) : (first ? cV : cH);
      vec3 cp  = vh ? (first ? cV : cH) : (first ? E : cVH);
      vec3 cpq = vh ? (first ? cVH : E) : (first ? cH : cV);
      f = bandSide(coord, o, p, q, e, cp, cpq);
    }
    band += m * f;
  }
  return band;
}

// 30b. Outline around a strong shape
#define XBRZ_RING 64.0
float ringBand(vec3 Pc, vec3 Q, vec3 X, vec3 E)
{
  if (!alike(Pc, Q)) return 0.0;
  return float(!withinY255(Pc, X, XBRZ_RING) && !withinY255(Q, X, XBRZ_RING) && !withinY255(E, X, XBRZ_RING)
               && max(Pc.x, Q.x) < min(E.x, X.x));
}
float ringOutBand(vec3 E, vec3 K1, vec3 K2, vec3 X, vec3 N1, vec3 N2)
{
  if (!alike(E, K1) || !alike(E, K2)) return 0.0;
  float lE = E.x;
  return float(!withinY255(E, X, XBRZ_RING) && !withinY255(N1, X, XBRZ_RING) && !withinY255(N2, X, XBRZ_RING) && lE < X.x && lE < N1.x && lE < N2.x);
}

// ============================================================================================
// 1. Minimum contrast
// ============================================================================================
// a corner whose two colors (E and its closer candidate) differ by less than XBRZ_MINC stays square;
// one up to XBRZ_HYST below the limit is kept but marked weak afterwards (weakCorners)
vec4 minimumContrast(vec4 res, float dEB, float dED, float dEF, float dEH, out vec4 contrast, out vec4 weak)
{
  weak = vec4(0.0);
  contrast = vec4(0.0);
  if (XBRZ_MINC > 0.0)
  {
    contrast = vec4(min(dED, dEB), min(dEB, dEF), min(dEF, dEH), min(dEH, dED)) * 255.0;
    vec4 keep = vec4(greaterThanEqual(contrast, vec4(XBRZ_MINC - XBRZ_HYST)));
    weak = keep * vec4(lessThan(contrast, vec4(XBRZ_MINC)));
    res *= keep;
  }
  return res;
}

// a weak corner that is still cut after rules 2 to 7 gets blend type 3: the resolve pass rounds it
// only where the same corner of both neighbours along the cut is rounded
vec4 weakCorners(vec4 res, vec4 weak)
{
  weak *= vec4(greaterThan(BLEND(res), vec4(0.0)));
  return res + weak * (3.0 - BLEND(res));
}

// ============================================================================================
// helpers for rules 3 and 4
// ============================================================================================
float strokeEnds(vec3 p, vec3 q, vec2 coord, vec2 o, vec2 side)
{
  vec3 T = at5x5(coord, o);
  return float(!alike(p, T) && !alike(q, T) && !alike(p, at5x5(coord, o + side)) && !alike(p, at5x5(coord, o - side)));
}

float wallAt(vec2 coord, vec2 t, vec3 T)
{
  bool l = alike(T, at5x5(coord, vec2(t.x - 1.0, t.y))), r = alike(T, at5x5(coord, vec2(t.x + 1.0, t.y))),
       u = alike(T, at5x5(coord, vec2(t.x, t.y - 1.0))), d = alike(T, at5x5(coord, vec2(t.x, t.y + 1.0)));
  return float((l && (r || alike(T, at5x5(coord, vec2(t.x - 2.0, t.y))))) || (r && alike(T, at5x5(coord, vec2(t.x + 2.0, t.y)))) ||
               (u && (d || alike(T, at5x5(coord, vec2(t.x, t.y - 2.0))))) || (d && alike(T, at5x5(coord, vec2(t.x, t.y + 2.0)))));
}

float runWall(vec3 E, vec2 coord, vec2 d)
{
  vec3 c1 = at5x5(coord, d);
  if (!alike(E, c1)) return wallAt(coord, d, c1);
  vec3 c2 = PY(2.0 * d.x, 2.0 * d.y);
  if (!alike(E, c2)) return wallAt(coord, 2.0 * d, c2);
  vec3 c3 = PY(3.0 * d.x, 3.0 * d.y);
  if (!alike(E, c3)) return wallAt(coord, 3.0 * d, c3);
  return 1.0;
}

// ============================================================================================
// helper for rule 7
// ============================================================================================
bool stripeEnd(vec2 coord, vec2 o1, vec2 o2, vec2 o3, bool thin, vec3 E, vec3 A, vec3 B, vec3 C, vec3 D, vec3 F, vec3 G, vec3 H, vec3 I,
               vec3 l2, vec3 r2, vec3 rt, vec3 rb)
{
  // check all cheap register conditions before fetching distant o1, o2, o3
  if (!(thin && alike(E, F) && !eq(E, D) && !eq(B, A) && !eq(H, G) && alike(B, C) && alike(H, I)
        && alike(E, r2) && alike(C, rt) && alike(I, rb)))
    return false;
  bool aAE = alike(A, E), aEG = alike(E, G);
  if ((aAE && alike(B, D)) || (aEG && alike(D, H)))
    return false;
  bool nDE = !alike(D, E);
  if (aAE && nDE && !alike(B, E) && alike(E, PY(o1.x, o1.y)))
    return false;
  if (aEG && nDE && !alike(E, H) && alike(E, PY(o2.x, o2.y)))
    return false;
  return !eq(D, l2) || alike(E, PY(o3.x, o3.y));
}

// ============================================================================================
// Rules 2 to 7 (XBRZ_DIAG)
// ============================================================================================
vec4 diagonalRules(vec4 res, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                   vec4 pair, float dEB, float dED, float dEF, float dEH)
{
  vec4 cut = vec4(greaterThan(BLEND(res), vec4(0.0)));
  if (XBRZ_DIAG <= 0.0 || dot(cut, vec4(1.0)) <= 0.0)
    return res;
  vec4 before = res;

  // ---- what the rules look at ----
  vec4 dEP = vec4(dED, dEB, dEF, dEH);
  vec4 dEQ = vec4(dEB, dEF, dEH, dED);
  vec4 sec = FLAG(res, 8.0);
  vec3 Px = sec.x > 0.5 ? B : D, Py = sec.y > 0.5 ? F : B, Pz = sec.z > 0.5 ? H : F, Pw = sec.w > 0.5 ? D : H;
  vec3 Qx = sec.x > 0.5 ? D : B, Qy = sec.y > 0.5 ? B : F, Qz = sec.z > 0.5 ? F : H, Qw = sec.w > 0.5 ? H : D;
  float lE = E.x;
  vec4 lP = vec4(Px.x, Py.x, Pz.x, Pw.x);
  vec4 lQ = vec4(Qx.x, Qy.x, Qz.x, Qw.x);
  vec4 notLighter = vec4(lessThanEqual(lP, vec4(lE + XBRZ_NOT_LIGHTER / 255.0)));
  vec4 straight = vec4(float(sec.x > 0.5 ? alike(B, C) : alike(D, G)), float(sec.y > 0.5 ? alike(F, I) : alike(A, B)),
                       float(sec.z > 0.5 ? alike(G, H) : alike(C, F)), float(sec.w > 0.5 ? alike(A, D) : alike(H, I)));
  vec3 Rx = sec.x > 0.5 ? N_p0_m2 : N_m2_p0, Ry = sec.y > 0.5 ? N_p2_p0 : N_p0_m2;
  vec3 Rz = sec.z > 0.5 ? N_p0_p2 : N_p2_p0, Rw = sec.w > 0.5 ? N_m2_p0 : N_p0_p2;

  // ---- 2. Diagonal limit ----
  vec4 ramp = min((dEP + pair) / max(dEQ, vec4(SAFE_EPS)), (dEQ + pair) / max(dEP, vec4(SAFE_EPS)));
  vec4 limit = mix(vec4(XBRZ_DIAG), vec4(XBRZ_DIAG * 0.92), vec4(lessThanEqual(ramp, vec4(XBRZ_RAMP))));
  vec4 keep = max(vec4(lessThanEqual(pair * 255.0, limit)), vec4(greaterThanEqual(res, vec4(16.0))) * notLighter);
  vec4 loneP = vec4(0.0), loneQ = vec4(0.0);
  bool haveLone = false;
  vec4 kept = vec4(0.0);
  float eASq = 0.0, eCSq = 0.0, eGSq = 0.0, eISq = 0.0;
  bool haveDiagDist = false;
  if (dot((1.0 - keep) * cut, vec4(1.0)) > 0.0)
  {
    vec4 tipLine;
    tipLine.x = sec.x > 0.5 ? float(alike(C, E) && min(distSqY(B, N_p0_m2), distSqY(B, N_p1_m2)) <= SQ255(XBRZ_STRIPE))
                            : float(alike(E, G) && min(distSqY(D, N_m2_p0), distSqY(D, N_m2_p1)) <= SQ255(XBRZ_STRIPE));
    tipLine.y = sec.y > 0.5 ? float(alike(E, I) && min(distSqY(F, N_p2_p0), distSqY(F, N_p2_p1)) <= SQ255(XBRZ_STRIPE))
                            : float(alike(A, E) && min(distSqY(B, N_p0_m2), distSqY(B, N_m1_m2)) <= SQ255(XBRZ_STRIPE));
    tipLine.z = sec.z > 0.5 ? float(alike(E, G) && min(distSqY(H, N_p0_p2), distSqY(H, N_m1_p2)) <= SQ255(XBRZ_STRIPE))
                            : float(alike(C, E) && min(distSqY(F, N_p2_p0), distSqY(F, N_p2_m1)) <= SQ255(XBRZ_STRIPE));
    tipLine.w = sec.w > 0.5 ? float(alike(A, E) && min(distSqY(D, N_m2_p0), distSqY(D, N_m2_m1)) <= SQ255(XBRZ_STRIPE))
                            : float(alike(E, I) && min(distSqY(H, N_p0_p2), distSqY(H, N_p1_p2)) <= SQ255(XBRZ_STRIPE));
    keep = max(keep, tipLine);
    vec4 wide = vec4(float(alike(E, sec.x > 0.5 ? F : H)), float(alike(E, sec.y > 0.5 ? H : D)),
                     float(alike(E, sec.z > 0.5 ? D : B)), float(alike(E, sec.w > 0.5 ? B : F)));
    vec4 block = wide * vec4(float(alike(E, sec.x > 0.5 ? H : F) && alike(E, I)), float(alike(E, sec.y > 0.5 ? D : H) && alike(E, G)),
                             float(alike(E, sec.z > 0.5 ? B : D) && alike(A, E)), float(alike(E, sec.w > 0.5 ? F : B) && alike(C, E)));
    vec3 Sx = sec.x > 0.5 ? C : G, Sy = sec.y > 0.5 ? I : A, Sz = sec.z > 0.5 ? G : C, Sw = sec.w > 0.5 ? A : I;
    vec3 Ux = sec.x > 0.5 ? N_p1_m2 : N_m2_p1, Uy = sec.y > 0.5 ? N_p2_p1 : N_m1_m2;
    vec3 Uz = sec.z > 0.5 ? N_m1_p2 : N_p2_m1, Uw = sec.w > 0.5 ? N_m2_m1 : N_p1_p2;
    vec4 lR = vec4(Rx.x, Ry.x, Rz.x, Rw.x);
    vec4 lU = vec4(Ux.x, Uy.x, Uz.x, Uw.x);
    vec4 dEPc = mix(dEP, dEQ, sec);
    vec4 inner = vec4(lessThanEqual(dEPc * 255.0, vec4(XBRZ_DIAG))) * vec4(lessThan(lQ, min(lP, vec4(lE)) - XBRZ_OUTLINE))
               * notLighter * (1.0 - straight) * wide * (1.0 - block);
    vec4 bevel = vec4(float(alike(E, Sx)), float(alike(E, Sy)), float(alike(E, Sz)), float(alike(E, Sw)))
               * vec4(lessThan(max(lR, lU), min(lP, vec4(lE)) - XBRZ_OUTLINE));
    inner *= 1.0 - bevel;
    keep = max(keep, inner);

    // ---- 6. Antialiasing notch (folded into rule 2's diagonal limit) ----
    vec4 blocked2 = (1.0 - keep) * cut;
    if (dot(blocked2, vec4(1.0)) > 0.0)
    {
      vec4 lone = vec4(float(!alike(A, B) && !alike(B, C) && !alike(B, N_p0_m2)), float(!alike(A, D) && !alike(D, G) && !alike(D, N_m2_p0)),
                       float(!alike(C, F) && !alike(F, I) && !alike(F, N_p2_p0)), float(!alike(G, H) && !alike(H, I) && !alike(H, N_p0_p2)));
      loneP = mix(lone.yxzw, lone.xzwy, sec);
      loneQ = mix(lone.xzwy, lone.yxzw, sec);
      haveLone = true;
      vec4 dQc = mix(dEQ, dEP, sec);
      vec4 notch = vec4(lessThanEqual((dEPc + pair) / max(dQc, vec4(SAFE_EPS)), vec4(XBRZ_RAMP)))
                 * vec4(lessThanEqual(pair * 255.0, vec4(XBRZ_DIAG + XBRZ_NOTCH))) * loneP * blocked2;
      if (dot(notch, vec4(1.0)) > 0.0)
      {
        float t2 = XBRZ_TONE * XBRZ_TONE;
        vec4 wrap = vec4(lessThan(vec4(distSqY(A, Qx), distSqY(C, Qy), distSqY(I, Qz), distSqY(G, Qw)), t2 * (pair * pair)));
        eCSq = distSqY(C, E); eGSq = distSqY(E, G); eASq = distSqY(A, E); eISq = distSqY(E, I);
        haveDiagDist = true;
        vec4 along = vec4(
          float(eCSq < t2 * min(distSqY(B, C), distSqY(C, D)) || eGSq < t2 * min(distSqY(B, G), distSqY(D, G))),
          float(eASq < t2 * min(distSqY(A, B), distSqY(A, F)) || eISq < t2 * min(distSqY(B, I), distSqY(F, I))),
          float(eCSq < t2 * min(distSqY(C, F), distSqY(C, H)) || eGSq < t2 * min(distSqY(F, G), distSqY(G, H))),
          float(eASq < t2 * min(distSqY(A, D), distSqY(A, H)) || eISq < t2 * min(distSqY(D, I), distSqY(H, I))));
        notch *= wrap * along;
        keep = max(keep, notch);
        kept = notch;
      }
    }
    res += 128.0 * (1.0 - keep) * cut;
    res *= 1.0 - (1.0 - keep) * straight * cut;
  }

  // ---- 3. Eye ----
  if (CRISP_RULES)
  {
    vec4 gate = straight * cut * vec4(lessThan(max(lP, lQ), vec4(lE - XBRZ_OUTLINE)));
    if (dot(gate, vec4(1.0)) > 0.0)
    {
      vec4 eye = vec4(float(!alike(Px, Qx) && alike(Qx, A) && !alike(Px, A) && !alike(Px, Rx) && !alike(E, sec.x > 0.5 ? H : F)),
                      float(!alike(Py, Qy) && alike(Qy, C) && !alike(Py, C) && !alike(Py, Ry) && !alike(E, sec.y > 0.5 ? D : H)),
                      float(!alike(Pz, Qz) && alike(Qz, I) && !alike(Pz, I) && !alike(Pz, Rz) && !alike(E, sec.z > 0.5 ? B : D)),
                      float(!alike(Pw, Qw) && alike(Qw, G) && !alike(Pw, G) && !alike(Pw, Rw) && !alike(E, sec.w > 0.5 ? F : B)))
                * gate;
      float stripeCG = float(min(distSqY(C, E), distSqY(E, G)) <= SQ255(XBRZ_STRIPE));
      float stripeAI = float(min(distSqY(A, E), distSqY(E, I)) <= SQ255(XBRZ_STRIPE));
      eye *= 1.0 - vec4(stripeCG, stripeAI, stripeCG, stripeAI);
      if (dot(eye, vec4(1.0)) > 0.0)
      {
        eye *= vec4(eye.x > 0.5 ? (sec.x > 0.5 ? strokeEnds(Px, Qx, coord, vec2(2.0,-1.0), vec2(0.0,1.0)) : strokeEnds(Px, Qx, coord, vec2(-1.0,2.0), vec2(1.0,0.0))) : 0.0,
                    eye.y > 0.5 ? (sec.y > 0.5 ? strokeEnds(Py, Qy, coord, vec2(1.0,2.0), vec2(-1.0,0.0)) : strokeEnds(Py, Qy, coord, vec2(-2.0,-1.0), vec2(0.0,1.0))) : 0.0,
                    eye.z > 0.5 ? (sec.z > 0.5 ? strokeEnds(Pz, Qz, coord, vec2(-2.0,1.0), vec2(0.0,-1.0)) : strokeEnds(Pz, Qz, coord, vec2(1.0,-2.0), vec2(-1.0,0.0))) : 0.0,
                    eye.w > 0.5 ? (sec.w > 0.5 ? strokeEnds(Pw, Qw, coord, vec2(-1.0,-2.0), vec2(1.0,0.0)) : strokeEnds(Pw, Qw, coord, vec2(2.0,1.0), vec2(0.0,-1.0))) : 0.0);
        res *= 1.0 - eye;
      }
    }
  }

  // ---- 4. Diagonal up to the wall ----
  vec4 changed = vec4(notEqual(res, before));
  if (dot(changed, vec4(1.0)) > 0.0)
  {
    if (!haveLone)
    {
      vec4 lone = vec4(float(!alike(A, B) && !alike(B, C) && !alike(B, N_p0_m2)), float(!alike(A, D) && !alike(D, G) && !alike(D, N_m2_p0)),
                       float(!alike(C, F) && !alike(F, I) && !alike(F, N_p2_p0)), float(!alike(G, H) && !alike(H, I) && !alike(H, N_p0_p2)));
      loneP = mix(lone.yxzw, lone.xzwy, sec);
      loneQ = mix(lone.xzwy, lone.yxzw, sec);
      haveLone = true;
    }
    // mask per corner by changed so unchanged corners do not waste runWall fetches or falsely set kept (suppressing rule 7)
    vec4 diagE = vec4(float(alike(C, E) || alike(E, G)), float(alike(A, E) || alike(E, I)),
                      float(alike(C, E) || alike(E, G)), float(alike(A, E) || alike(E, I))) * cut * changed;
    if (dot(diagE, vec4(1.0)) > 0.0)
    {
      vec4 partner = vec4(
        float((alike(C, E) && !alike(B, C) && !alike(C, N_p1_m2)) || (alike(E, G) && !alike(G, N_m2_p1) && !alike(D, G))),
        float((alike(A, E) && !alike(A, N_m1_m2) && !alike(A, B)) || (alike(E, I) && !alike(F, I) && !alike(I, N_p2_p1))),
        float((alike(C, E) && !alike(C, N_p2_m1) && !alike(C, F)) || (alike(E, G) && !alike(G, H) && !alike(G, N_m1_p2))),
        float((alike(A, E) && !alike(A, D) && !alike(A, N_m2_m1)) || (alike(E, I) && !alike(I, N_p1_p2) && !alike(H, I))));
      float l3CG = float((alike(C, E) && alike(E, PY(2., -2.))) || (alike(E, G) && alike(E, PY(-2., 2.))));
      float l3AI = float((alike(A, E) && alike(E, PY(-2., -2.))) || (alike(E, I) && alike(E, PY(2., 2.))));
      partner = max(partner, vec4(l3CG, l3AI, l3CG, l3AI));
      float lineR = float(alike(E, F) && alike(E, N_p2_p0)), lineL = float(alike(D, E) && alike(E, N_m2_p0));
      float lineD = float(alike(E, H) && alike(E, N_p0_p2)), lineU = float(alike(B, E) && alike(E, N_p0_m2));
      vec4 endLine = vec4(max(lineR, lineD), max(lineL, lineD), max(lineL, lineU), max(lineR, lineU));
      vec4 straightQ = vec4(float(sec.x > 0.5 ? alike(D, G) : alike(B, C)), float(sec.y > 0.5 ? alike(A, B) : alike(F, I)),
                            float(sec.z > 0.5 ? alike(C, F) : alike(G, H)), float(sec.w > 0.5 ? alike(H, I) : alike(A, D)));
      vec4 straightQ0 = max(straightQ, vec4(float(alike(Qx, A)), float(alike(Qy, C)), float(alike(Qz, I)), float(alike(Qw, G))));
      straightQ = max(straightQ, vec4(float(alike(Qx, A) && alike(Qx, sec.x > 0.5 ? N_m1_m2 : N_m2_m1)),
                                      float(alike(Qy, C) && alike(Qy, sec.y > 0.5 ? N_p2_m1 : N_p1_m2)),
                                      float(alike(Qz, I) && alike(Qz, sec.z > 0.5 ? N_p1_p2 : N_p2_p1)),
                                      float(alike(Qw, G) && alike(Qw, sec.w > 0.5 ? N_m2_p1 : N_m1_p2))));
      float sH = float(!alike(B, E) && !alike(E, H) && !alike(B, H)), sV = float(!alike(D, E) && !alike(E, F) && !alike(D, F));
      vec4 stripeE = vec4(sec.x > 0.5 ? sH : sV, sec.y > 0.5 ? sV : sH, sec.z > 0.5 ? sH : sV, sec.w > 0.5 ? sV : sH);
      vec4 bendQ = straightQ0 * (1.0 - straightQ) * stripeE;
      vec4 sQ = mix(straightQ0, straightQ, stripeE);
      vec3 Qnx = sec.x > 0.5 ? N_m2_p1 : N_p1_m2, Qny = sec.y > 0.5 ? N_m1_m2 : N_p2_p1;
      vec3 Qnz = sec.z > 0.5 ? N_p2_m1 : N_m1_p2, Qnw = sec.w > 0.5 ? N_p1_p2 : N_m2_m1;
      vec4 qRun = vec4(float(alike(Qx, Qnx)), float(alike(Qy, Qny)), float(alike(Qz, Qnz)), float(alike(Qw, Qnw)));
      vec4 run = partner * (1.0 - straight * sQ) * (1.0 - straight * vec4(lessThan(lP, vec4(lE))) * (1.0 - bendQ))
               * (1.0 - endLine * straight * (1.0 - bendQ)) * (1.0 - straight * (1.0 - straightQ0) * (1.0 - qRun)) * cut * changed;
      run *= 1.0 - loneP * loneQ;
      if (dot(run, vec4(1.0)) > 0.0)
      {
        float wCG = run.x + run.z > 0.0 ? max(alike(C, E) ? runWall(E, coord, vec2(1.0, -1.0)) : 0.0, alike(E, G) ? runWall(E, coord, vec2(-1.0, 1.0)) : 0.0) : 0.0;
        float wAI = run.y + run.w > 0.0 ? max(alike(E, I) ? runWall(E, coord, vec2(1.0, 1.0)) : 0.0, alike(A, E) ? runWall(E, coord, vec2(-1.0, -1.0)) : 0.0) : 0.0;
        run *= vec4(wCG, wAI, wCG, wAI);
      }
      res = mix(res, before, run);
      kept = max(kept, run);
    }
  }

  // ---- 5. Thin light stroke ----
  vec4 back = vec4(greaterThan(vec4(lE) - max(lP, lQ), vec4(XBRZ_THIN_LIGHT))) * cut * vec4(notEqual(res, before)) * (1.0 - loneP * loneQ);
  if (dot(back, vec4(1.0)) > 0.0)
  {
    vec4 dPQmin = min(dEP, dEQ);
    if (!haveDiagDist)
    {
      eCSq = distSqY(C, E); eGSq = distSqY(E, G); eASq = distSqY(A, E); eISq = distSqY(E, I);
    }
    vec4 tE = XBRZ_TONE * dPQmin;
    vec4 tESq = tE * tE;
    bvec4 aD = bvec4(alike(C, E), alike(E, G), alike(A, E), alike(E, I));
    bvec4 nD = bvec4(aD.x || eCSq < tESq.x, aD.y || eGSq < tESq.x, aD.z || eASq < tESq.y, aD.w || eISq < tESq.y);
    bvec4 nD2 = bvec4(aD.x || eCSq < tESq.z, aD.y || eGSq < tESq.z, aD.z || eASq < tESq.w, aD.w || eISq < tESq.w);
    vec4 sideA = vec4(float(aD.x && !(dEF < tE.x)) + float(aD.y && !(dEH < tE.x)), float(aD.z && !(dED < tE.y)) + float(aD.w && !(dEH < tE.y)),
                      float(aD.x && !(dEB < tE.z)) + float(aD.y && !(dED < tE.z)), float(aD.z && !(dEB < tE.w)) + float(aD.w && !(dEF < tE.w)));
    vec4 sideN = vec4(float(nD.x && !(dEF < tE.x)) + float(nD.y && !(dEH < tE.x)), float(nD.z && !(dED < tE.y)) + float(nD.w && !(dEH < tE.y)),
                      float(nD2.x && !(dEB < tE.z)) + float(nD2.y && !(dED < tE.z)), float(nD2.z && !(dEB < tE.w)) + float(nD2.w && !(dEF < tE.w)));
    sideA = min(sideA, vec4(1.0)); sideN = min(sideN, vec4(1.0));
    vec4 farOff = vec4(float(!alike(E, I)), float(!alike(E, G)), float(!alike(A, E)), float(!alike(C, E)));
    vec4 along = max(sideA * vec4(lessThan(max(lP, lQ), vec4(XBRZ_THIN_DARK))), sideN * farOff);
    back *= along;
    res = mix(res, before, back);
    kept = max(kept, back);
  }

  // ---- 7. Stripe ends ----
  bool eB = eq(E, B), eD = eq(E, D), eF = eq(E, F), eH = eq(E, H);
  vec3 fB = eB ? N_p0_m2 : N_p0_p2, fD = eD ? N_m2_p0 : N_p2_p0;
  bool thinH = !eq(B, H) && ((!eB && !eH) || (eB != eH && !eq(fB, E)));
  bool thinV = !eq(D, F) && ((!eD && !eF) || (eD != eF && !eq(fD, E)));
  vec4 open4 = vec4(greaterThan(BLEND(res), vec4(0.0))) * vec4(greaterThan(pair * 255.0, vec4(XBRZ_TIP))) * (1.0 - kept);
  if ((thinH || thinV) && dot(open4, vec4(1.0)) > 0.0)
  {
    float endL = float(stripeEnd(coord, vec2(-2., -2.), vec2(-2., 2.), vec2(3., 0.), thinH, E, A, B, C, D, F, G, H, I, N_m2_p0, N_p2_p0, N_p2_m1, N_p2_p1));
    float endR = float(stripeEnd(coord, vec2(2., -2.), vec2(2., 2.), vec2(-3., 0.), thinH, E, C, B, A, F, D, I, H, G, N_p2_p0, N_m2_p0, N_m2_m1, N_m2_p1));
    float endT = float(stripeEnd(coord, vec2(-2., -2.), vec2(2., -2.), vec2(0., 3.), thinV, E, A, D, G, B, H, C, F, I, N_p0_m2, N_p0_p2, N_m1_p2, N_p1_p2));
    float endB = float(stripeEnd(coord, vec2(-2., 2.), vec2(2., 2.), vec2(0., -3.), thinV, E, G, D, A, H, B, I, F, C, N_p0_p2, N_p0_m2, N_m1_m2, N_p1_m2));
    if (endL + endR + endT + endB > 0.0)
    {
      bool nB = alike(B, E), nD = alike(D, E), nF = alike(E, F), nH = alike(E, H);
      vec4 tip = vec4(max(endL, endT), max(endR, endT), max(endR, endB), max(endL, endB));
      tip *= vec4(greaterThan(pair * 255.0, vec4(XBRZ_TIP)));
      float aH = float((nB && !eB) || (nH && !eH)), aV = float((nD && !eD) || (nF && !eF));
      vec4 soft = vec4(max(endL * aH, endT * aV), max(endR * aH, endT * aV), max(endR * aH, endB * aV), max(endL * aH, endB * aV));
      soft *= vec4(lessThan(max(lP, lQ), vec4(lE - XBRZ_OUTLINE)));
      tip *= 1.0 - soft * min(FLAG(res, 16.0) + FLAG(res, 64.0), vec4(1.0));
      res *= 1.0 - tip * (1.0 - kept);
    }
  }
  return res;
}

// ============================================================================================
// 8. Line through an antialiasing pixel
// ============================================================================================
vec4 lineThroughAA(vec4 res, vec4 xbrz, vec4 contrast, vec3 B, vec3 D, vec3 F, vec3 H,
                   vec4 pairDist, float dEB, float dED, float dEF, float dEH)
{
  if (XBRZ_MINC <= 0.0)
    return res;
  vec4 cut = vec4(greaterThan(BLEND(res), vec4(0.0))) * vec4(lessThan(BLEND(res), vec4(3.0))) * FLAG(res, 4.0) * vec4(lessThan(res, vec4(128.0)));
  vec4 sq = vec4(lessThan(contrast, vec4(XBRZ_MINC))) * vec4(greaterThan(BLEND(xbrz), vec4(0.0))) * FLAG(xbrz, 4.0)
          * vec4(notEqual(BLEND(res), vec4(1.0))) * vec4(notEqual(BLEND(res), vec4(2.0))) * vec4(lessThan(res, vec4(128.0)));
  vec4 pair = sq * cut.zwxy;
  if (dot(pair, vec4(1.0)) <= 0.0)
    return res;
  vec4 sc = FLAG(xbrz, 8.0);
  // Reuse precomputed cardinal distances (dEB..dEH) and diagonal pair distances (pairDist):
  // when st8 checks the first neighbor against C (or sh8 checks the second against C), it is non-trivial only when
  // that neighbor is Q != C, whose distances to C and E are already pairDist and dQE (0 sqrt calls).
  vec4 dE1 = vec4(dED, dEB, dEF, dEH);
  vec4 dE2 = vec4(dEB, dEF, dEH, dED);
  vec4 dPE = mix(dE1, dE2, sc);
  vec4 dQE = mix(dE2, dE1, sc);
  vec4 st8 = FLAG(xbrz, 64.0), sh8 = FLAG(xbrz, 16.0);
  vec4 thirdCond = vec4(greaterThanEqual(min(pairDist, dQE) * 255.0, vec4(XBRZ_MINC)))
                 * vec4(greaterThan(dPE + pairDist, XBRZ_AA_OFF * dQE))
                 * vec4(greaterThan(dPE + dQE, XBRZ_AA_OFF * pairDist));
  pair *= 1.0 - (st8 * sc + sh8 * (1.0 - sc)) * thirdCond;
  float bxz = 0.0;
  if (pair.x + pair.z > 0.0)
  {
    vec3 Cx = sc.x > 0.5 ? B : D, Cz = sc.z > 0.5 ? H : F;
    float dXZSq = distSqY(Cx, Cz);
    float s = dPE.x + dPE.z;
    bxz = float(s * s <= (XBRZ_AA_LINE * XBRZ_AA_LINE) * dXZSq && dXZSq >= SQ255(XBRZ_AA_EDGE));
  }
  float byw = 0.0;
  if (pair.y + pair.w > 0.0)
  {
    vec3 Cy = sc.y > 0.5 ? F : B, Cw = sc.w > 0.5 ? D : H;
    float dYWSq = distSqY(Cy, Cw);
    float s = dPE.y + dPE.w;
    byw = float(s * s <= (XBRZ_AA_LINE * XBRZ_AA_LINE) * dYWSq && dYWSq >= SQ255(XBRZ_AA_EDGE));
  }
  return mix(res, xbrz, pair * vec4(bxz, byw, bxz, byw));
}

// ============================================================================================
// 10. Pixel closed between outlines
// ============================================================================================
vec4 closedPixel(vec4 res, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  vec4 line = min(FLAG(res, 16.0) + FLAG(res, 64.0), 1.0) * vec4(greaterThan(BLEND(res), vec4(0.0)));
  if (XBRZ_DIAG <= 0.0 || dot(line, vec4(1.0)) <= 0.0)
    return res;
  vec4 sc = FLAG(res, 8.0);
  vec3 Px = sc.x > 0.5 ? B : D, Py = sc.y > 0.5 ? F : B, Pz = sc.z > 0.5 ? H : F, Pw = sc.w > 0.5 ? D : H;
  vec4 lQ = vec4(A.x, C.x, I.x, G.x);
  vec4 lP = vec4(Px.x, Py.x, Pz.x, Pw.x);
  vec4 dark = vec4(lessThan(lQ + XBRZ_BLACK_GAP, lP)) * vec4(lessThan(lQ + XBRZ_BLACK_GAP, vec4(E.x))) * vec4(lessThan(lQ, vec4(XBRZ_BLACK)));
  vec4 closed = dark * line;
  if (dot(closed, vec4(1.0)) <= 0.0)
    return res;
  // dark already guarantees luma gap > 0.1 (25.5/255 > XBRZ_ALIKE = 20/255), so !alike(Q, P) and !alike(Q, E) always hold
  bool sx = sc.x > 0.5 ? (alike(A, C) && alike(A, D)) : (alike(A, G) && alike(A, B));
  bool sy = sc.y > 0.5 ? (alike(C, I) && alike(B, C)) : (alike(A, C) && alike(C, F));
  bool sz = sc.z > 0.5 ? (alike(G, I) && alike(F, I)) : (alike(C, I) && alike(H, I));
  bool sw = sc.w > 0.5 ? (alike(A, G) && alike(G, H)) : (alike(G, I) && alike(D, G));
  closed *= vec4(sx, sy, sz, sw);
  return res * (1.0 - closed);
}

// ============================================================================================
// 11. Lines in a larger window
// ============================================================================================
float onTone(vec3 X, vec3 a, vec3 b)
{
  float daSq = distSqY(X, a);
  return float(daSq < distSqY(X, b) && daSq <= SQ255(XBRZ_ALIKE));
}
#define RP(o) at5x5(coord, rot * (o))

// the pixel at offset o (components -1, 0 or 1) of the 3x3
vec3 at3x3(vec2 o, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  if (o.y < -0.5)
    return o.x < -0.5 ? A : (o.x > 0.5 ? C : B);
  if (o.y > 0.5)
    return o.x < -0.5 ? G : (o.x > 0.5 ? I : H);
  return o.x < -0.5 ? D : (o.x > 0.5 ? F : E);
}

// one corner, in its own frame: Fa, Fb, O1, eStrong and pStrong are already evaluated from 3x3 registers
float stripeLine(vec2 coord, mat2 rot, vec3 E, vec3 Pc, float shape, vec3 Fa, vec3 Fb, vec3 O1, float eStrong, float pStrong)
{
  vec2 e3, e4, p1, p2, p3, p4, p5, o2, o3;
  if (shape < 0.5)
  {
    e3 = vec2(2., -2.); e4 = vec2(-2., 2.);
    p1 = vec2(2., -1.); p2 = vec2(-1., 2.); p3 = p1; p4 = vec2(3., -2.); p5 = vec2(-2., 3.);
    o2 = vec2(2., 0.); o3 = vec2(0., 2.);
  }
  else if (shape < 1.5)
  {
    e3 = vec2(2., -1.); e4 = vec2(-2., 1.);
    p1 = vec2(-1., 1.); p2 = vec2(2., 0.); p3 = vec2(-2., 2.); p4 = vec2(3., -1.); p5 = vec2(-3., 2.);
    o2 = vec2(0., 2.); o3 = vec2(2., 1.);
  }
  else
  {
    e3 = vec2(-1., 2.); e4 = vec2(1., -2.);
    p1 = vec2(1., -1.); p2 = vec2(0., 2.); p3 = vec2(2., -2.); p4 = vec2(-1., 3.); p5 = vec2(2., -3.);
    o2 = vec2(2., 0.); o3 = vec2(1., 2.);
  }
  if (onTone(Fa, Pc, E) + onTone(Fb, Pc, E) > 0.5
      || onTone(RP(p1), Pc, E) * onTone(RP(p2), Pc, E) <= 0.0
      || onTone(RP(e3), E, Pc) * onTone(RP(e4), E, Pc) <= 0.0
      || (shape >= 0.5 && onTone(RP(p3), Pc, E) <= 0.0)
      || onTone(RP(p4), Pc, E) * onTone(RP(p5), Pc, E) <= 0.0)
    return 0.0;
  // eStrong already enforces dist(Fa/Fb, E) >= 40 > XBRZ_ALIKE (so !onTone(Fa/Fb, E, Pc)) and runs > 0 enforces !onTone(Fa/Fb, Pc, E)
  if (eStrong > 0.5)
    return 1.0;
  // pStrong already enforces dist(O1, Pc) >= 40 > XBRZ_ALIKE (so !onTone(O1, Pc, E))
  return pStrong * (1.0 - onTone(O1, E, Pc)) * (1.0 - onTone(RP(o2), Pc, E)) * (1.0 - onTone(RP(o3), Pc, E));
}

vec4 diagonalStripes(vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                     float dEB, float dED, float dEF, float dEH, vec4 xb, vec4 sq)
{
  vec4 shape = FLAG(xb, 4.0) * (FLAG(xb, 16.0) + 2.0 * FLAG(xb, 64.0));
  vec4 sec11 = FLAG(xb, 8.0);
  vec3 Px = sec11.x > 0.5 ? B : D, Qx = sec11.x > 0.5 ? D : B;
  vec3 Py = sec11.y > 0.5 ? F : B, Qy = sec11.y > 0.5 ? B : F;
  vec3 Pz = sec11.z > 0.5 ? H : F, Qz = sec11.z > 0.5 ? F : H;
  vec3 Pw = sec11.w > 0.5 ? D : H, Qw = sec11.w > 0.5 ? H : D;
  sq *= vec4(lessThan(shape, vec4(2.5))) * vec4(onTone(Qx, Px, E), onTone(Qy, Py, E), onTone(Qz, Pz, E), onTone(Qw, Pw, E));
  vec4 r = vec4(0.0);
  for (int k = 0; k < 4; k++)
  {
    vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
    if (dot(sq, m) <= 0.0) continue;
    mat2 rot = k == 0 ? mat2(-1., 0., 0., -1.) : (k == 1 ? mat2(0., -1., 1., 0.) : (k == 2 ? mat2(1., 0., 0., 1.) : mat2(0., 1., -1., 0.)));
    vec3 Pc = k == 0 ? Px : (k == 1 ? Py : (k == 2 ? Pz : Pw));
    float sh = dot(shape, m);
    vec3 Fa = at3x3(rot * (sh > 1.5 ? vec2(-1., 0.) : vec2(0., -1.)), A, B, C, D, E, F, G, H, I);
    vec3 Fb = at3x3(rot * (sh < 0.5 ? vec2(-1., 0.) : vec2(-1., -1.)), A, B, C, D, E, F, G, H, I);
    vec3 O1 = at3x3(rot * vec2(1., 1.), A, B, C, D, E, F, G, H, I);
    float eStrong = float(!withinY255(Fa, E, XBRZ_STRONG) && !withinY255(Fb, E, XBRZ_STRONG));
    float pStrong = float(!withinY255(O1, Pc, XBRZ_STRONG));
    if (eStrong + pStrong <= 0.0) continue;
    vec2 e1 = sh < 0.5 ? vec2(1., -1.) : (sh < 1.5 ? vec2(-1., 0.) : vec2(0., -1.));
    vec2 e2 = sh < 0.5 ? vec2(-1., 1.) : (sh < 1.5 ? vec2(1., -1.) : vec2(-1., 1.));
    if (onTone(at3x3(rot * e1, A, B, C, D, E, F, G, H, I), E, Pc) * onTone(at3x3(rot * e2, A, B, C, D, E, F, G, H, I), E, Pc) <= 0.0)
      continue;
    r += m * stripeLine(coord, rot, E, Pc, sh, Fa, Fb, O1, eStrong, pStrong);
  }
  return r;
}

vec4 largerWindowLines(vec4 res, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I, float dEB, float dED, float dEF, float dEH,
                       vec4 xbrz, vec4 contrast, inout vec4 weak)
{
  vec4 sq = vec4(lessThan(contrast, vec4(XBRZ_MINC))) * vec4(greaterThan(BLEND(xbrz), vec4(0.0)));
  if (XBRZ_MINC > 0.0 && dot(sq, vec4(1.0)) > 0.0)
  {
    sq *= diagonalStripes(coord, A, B, C, D, E, F, G, H, I, dEB, dED, dEF, dEH, xbrz, sq);
    res = mix(res, xbrz, sq);
    weak *= 1.0 - sq;
  }
  return res;
}

// ============================================================================================
// 13. Tiles between walls
// ============================================================================================
float tileStripeReg(vec3 E, vec3 P1, vec3 Q, vec3 Q2, vec3 O, vec3 O2, vec3 T0, vec3 T3,
                    vec3 qPrev, vec3 qNext, vec3 oPrev, vec3 oNext)
{
  float lE = E.x, lP = P1.x, lQ = Q.x, lO = O.x;
  bool light = min(lE, lP) > max(lQ, lO) + XBRZ_OUTLINE, dark = max(lE, lP) + XBRZ_OUTLINE < min(lQ, lO);
  if (!((light || dark) && alike(Q, Q2) && alike(O, O2) && !alike(E, T0) && !alike(T0, Q) && !alike(T0, O)))
    return 0.0;
  bool wallQ = alike(Q, qPrev) || alike(Q, qNext);
  bool wallO = alike(O, oPrev) || alike(O, oNext);
  bool tiles = !alike(P1, T3) && !alike(T3, Q) && !alike(T3, O) && (alike(T0, P1) || alike(E, T3));
  return float(wallQ && wallO && tiles);
}

vec4 tilesBetweenWalls(vec4 res, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  if (!(CRISP_RULES && max(max(res.x, res.y), max(res.z, res.w)) >= 128.0))
    return res;
  vec4 blk = vec4(greaterThanEqual(res, vec4(128.0))) * vec4(greaterThan(BLEND(res), vec4(0.0)));
  if (dot(blk, vec4(1.0)) <= 0.0)
    return res;
  vec4 sc = FLAG(mod(res, 128.0), 8.0);
  vec4 needDir = vec4(
    blk.x * (1.0 - sc.x) + blk.w * sc.w,
    blk.x * sc.x + blk.y * (1.0 - sc.y),
    blk.y * sc.y + blk.z * (1.0 - sc.z),
    blk.z * sc.z + blk.w * (1.0 - sc.w));
  float tL = needDir.x > 0.5 ? tileStripeReg(E, D, B, A, H, G, F, N_m2_p0, C, N_m2_m1, I, N_m2_p1) : 0.0;
  float tU = needDir.y > 0.5 ? tileStripeReg(E, B, D, A, F, C, H, N_p0_m2, G, N_m1_m2, I, N_p1_m2) : 0.0;
  float tR = needDir.z > 0.5 ? tileStripeReg(E, F, B, C, H, I, D, N_p2_p0, A, N_p2_m1, G, N_p2_p1) : 0.0;
  float tD = needDir.w > 0.5 ? tileStripeReg(E, H, D, G, F, I, B, N_p0_p2, A, N_m1_p2, C, N_p1_p2) : 0.0;
  vec4 tile = blk * vec4(sc.x > 0.5 ? tU : tL, sc.y > 0.5 ? tR : tU, sc.z > 0.5 ? tD : tR, sc.w > 0.5 ? tL : tD);
  res *= 1.0 - tile;
  return res;
}

// ============================================================================================
// 16 and 18. Line in another color
// ============================================================================================
vec4 lineInOtherColor(vec4 res, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                      vec4 pair, float dEB, float dED, float dEF, float dEH)
{
  if (XBRZ_MINC <= 0.0)
    return res;
  vec4 r = res;
  vec4 sh = FLAG(r, 16.0), st = FLAG(r, 64.0), sec = FLAG(r, 8.0);
  vec4 tint = vec4(greaterThan(BLEND(r), vec4(0.0))) * FLAG(r, 4.0) *
              abs(sh - st) * (sh * sec + st * (1.0 - sec)) * vec4(greaterThan(pair * 255.0, vec4(XBRZ_TINT)));
  if (dot(tint, vec4(1.0)) <= 0.0)
    return res;
  vec4 pShSq = vec4(distSqY(C, D), distSqY(B, I), distSqY(F, G), distSqY(A, H));
  vec4 pStSq = vec4(distSqY(B, G), distSqY(A, F), distSqY(C, H), distSqY(D, I));
  tint *= vec4(lessThan(sh * pShSq + st * pStSq, vec4(SQ255(TOL_E))));
  vec4 dE1 = vec4(dED, dEB, dEF, dEH);
  vec4 dE2 = vec4(dEB, dEF, dEH, dED);
  vec4 dP = mix(dE1, dE2, sec), dL = mix(dE2, dE1, sec);
  tint *= vec4(greaterThan(dP + pair, XBRZ_TINT_RAMP * dL));
  if (dot(tint, vec4(1.0)) <= 0.0)
    return res;
  bool lone = !(IsPixEqual(A, E) || IsPixEqual(B, E) || IsPixEqual(C, E) || IsPixEqual(D, E) ||
                IsPixEqual(E, F) || IsPixEqual(E, G) || IsPixEqual(E, H) || IsPixEqual(E, I));
  bool straight = IsPixEqual(D, F) || IsPixEqual(B, H);
  vec3 pX = st.x > 0.5 ? D : B, pY = st.y > 0.5 ? B : F, pZ = st.z > 0.5 ? F : H, pW = st.w > 0.5 ? H : D;
  vec4 eOnSq = vec4(min(distSqY(E, st.x > 0.5 ? N_m1_p2 : N_p2_m1), distSqY(E, st.x > 0.5 ? N_p1_m2 : N_m2_p1)),
                    min(distSqY(E, st.y > 0.5 ? N_m2_m1 : N_p1_p2), distSqY(E, st.y > 0.5 ? N_p2_p1 : N_m1_m2)),
                    min(distSqY(E, st.z > 0.5 ? N_p1_m2 : N_m2_p1), distSqY(E, st.z > 0.5 ? N_m1_p2 : N_p2_m1)),
                    min(distSqY(E, st.w > 0.5 ? N_p2_p1 : N_m1_m2), distSqY(E, st.w > 0.5 ? N_m2_m1 : N_p1_p2)));
  vec4 pOnSq = vec4(distSqY(pX, st.x > 0.5 ? N_p0_m2 : N_m2_p0), distSqY(pY, st.y > 0.5 ? N_p2_p0 : N_p0_m2),
                    distSqY(pZ, st.z > 0.5 ? N_p0_p2 : N_p2_p0), distSqY(pW, st.w > 0.5 ? N_m2_p0 : N_p0_p2));
  vec4 stripes = vec4(lessThan(eOnSq, vec4(SQ255(TOL_E)))) * vec4(lessThan(pOnSq, vec4(SQ255(TOL_E)))) * (straight ? 0.0 : 1.0);
  tint *= max(vec4(lessThan(r, vec4(128.0))), stripes);
  vec4 tint0 = tint;
  vec4 lumC1 = vec4(D.x, B.x, F.x, H.x);
  vec4 lumC2 = lumC1.yzwx;
  vec4 lumLine = mix(lumC1, lumC2, st);
  vec4 dark = vec4(lessThan(lumLine, vec4(E.x))) * (straight ? 0.0 : 1.0);
  if (!lone)
  {
    dark *= vec4(lessThan(lumLine, vec4(XBRZ_TINT_DARK)));
    dark *= vec4(greaterThanEqual(mix(lumC2, lumC1, st), vec4(XBRZ_TINT_DARK)));
    tint *= dark;
  }
  dark = max(dark, stripes);
  tint = max(tint, tint0 * stripes);
  vec4 flip = st - sec;
  vec4 shape = lone ? (16.0 * sh + 64.0 * st + 32.0 * FLAG(r, 32.0)) * (1.0 - stripes) : vec4(0.0);
  res -= tint * dark * (shape - 8.0 * flip);
  res *= 1.0 - tint * (1.0 - dark);
  res -= 128.0 * vec4(greaterThanEqual(r, vec4(128.0))) * tint * dark;
  return res;
}

// ============================================================================================
// The corners of E, written once in one frame
// ============================================================================================
// Computes line blend flags for a cut corner; lineTests runs only when cornerCut passes
float xbrzCorner(int own, int nbr0, int nbr4, float edge, float pairDSq,
                 vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I, vec3 altS, vec3 altT)
{
  if (!cornerCut(own, nbr0, nbr4, edge, E, G, H, I, F, C))
    return 0.0;
  bool needSh = neq(E, G) && neq(D, G);
  bool needSt = neq(E, C) && neq(B, C);
  float r = 4.0;
  if (!needSh && !needSt)
    return r;
  vec2 line = lineTests(F, G, H, C, E, pairDSq, eq(altS, H) && !eq(G, H), eq(altT, F) && !eq(C, F));
  if (needSh) r += line.x;
  if (needSt) r += line.y;
  return r;
}

struct Win
{
  vec3 A, B, C, D, E, F, G, H, I;
  vec3 m1_m2, p0_m2, p1_m2, m2_m1, p2_m1, m2_p0, p2_p0, m2_p1, p2_p1, m1_p2, p0_p2, p1_p2;
  vec4 dE, pairSq;
};

Win turn(Win o)
{
  return Win(o.C, o.F, o.I, o.B, o.E, o.H, o.A, o.D, o.G,
             o.p2_m1, o.p2_p0, o.p2_p1, o.p1_m2, o.p1_p2, o.p0_m2, o.p0_p2, o.m1_m2, o.m1_p2, o.m2_m1, o.m2_p0, o.m2_p1,
             o.dE.yzwx, o.pairSq.yzwx);
}

vec2 cornerLines(Win n)
{
  return lineTests(n.F, n.G, n.H, n.C, n.E, n.pairSq.z, eq(n.m1_p2, n.H) && !eq(n.G, n.H), eq(n.p2_m1, n.F) && !eq(n.C, n.F));
}

float cutFlags(Win n, vec2 line)
{
  float r = 4.0;
  if (neq(n.E, n.G) && neq(n.D, n.G)) r += line.x;
  if (neq(n.E, n.C) && neq(n.B, n.C)) r += line.y;
  return r;
}

float noLine(float r) { return mod(r, 4.0) + 8.0 * mod(floor(r / 8.0), 2.0); }

// 33. Hole in a thick stroke
float holeInStroke(Win n, float r)
{
  float ln = FLAG(r, 4.0) * FLAG(r, 16.0) * FLAG(r, 64.0);
  float dEB = n.dE.x, dEF = n.dE.y, dED = n.dE.w;
  float dEFSq = dEF * dEF;
  if (ln > 0.5 && dEF * 255.0 >= 64.0 && eq(n.F,n.H) && eq(n.F,n.C) && eq(n.H,n.G) && neq(n.I,n.E) && neq(n.I,n.F)
      && (dEB * 255.0 < 30.0) && (dED * 255.0 < 30.0) && distSqY(n.I, n.F) < dEFSq && distSqY(n.I, n.E) < dEFSq
      && neq(n.I, n.p2_p1) && neq(n.I, n.p1_p2) && neq(n.F, n.p2_p1) && neq(n.F, n.p1_p2) && (eq(n.F, n.p2_p0) || eq(n.H, n.p0_p2)))
    return noLine(r);
  return r;
}

// 32 & 35. Lone pixel test redone and edge of a thin band
float lonePixelRedone(Win n, vec4 r, ivec4 b)
{
  vec4 bl = mod(r, 4.0);
  float ln = mod(floor(r.z / 4.0), 2.0);
  float c4 = min(n.dE.y, n.dE.z) * 255.0;
  float dEB = n.dE.x, dED = n.dE.w;
  if ((bl.z > 0.0 && ln < 0.5 && !((eq(n.E,n.D) && !eq(n.E,n.m2_p0)) || (eq(n.E,n.B) && !eq(n.E,n.p0_m2))) && bl.y == 0.0 && bl.w == 0.0
       && c4 >= 64.0 && b.z == BLEND_NORMAL && eq(n.F,n.H) && eq(n.F,n.C) && eq(n.H,n.G) && neq(n.F, n.p2_p0) && neq(n.H, n.p0_p2)
       && cornerCut(b.z, BLEND_NONE, BLEND_NONE, min(n.dE.y, n.dE.z), n.E, n.G, n.H, n.I, n.F, n.C))
      || (bl.z == 1.0 && ln < 0.5 && c4 >= 40.0 && c4 < XBRZ_GUARD_EDGE && eq(n.F,n.H) && !withinY255(n.I, n.F, 40.0)
       && ((eq(n.G,n.H) && eq(n.F,n.p2_p0) && (dED * 255.0 < 30.0) && near(n.E,n.C) && !withinY255(n.p0_p2, n.H, 40.0))
        || (eq(n.C,n.F) && eq(n.H,n.p0_p2) && (dEB * 255.0 < 30.0) && near(n.E,n.G) && !withinY255(n.p2_p0, n.F, 40.0)))
       && cornerCut(b.z, b.y, b.w, 1.0, n.E, n.G, n.H, n.I, n.F, n.C)))
    return cutFlags(n, cornerLines(n));
  return 0.0;
}

// 34. Small square of close shades
float smallSquare(Win n, float r)
{
  if (min(n.dE.y, n.dE.z) * 255.0 >= 48.0 && (n.dE.w * 255.0 < 30.0) && (n.dE.x * 255.0 < 30.0) && near(n.E,n.A) && (n.E != n.D || n.E != n.B || n.E != n.A)
      && eq(n.F,n.C) && eq(n.F,n.H) && eq(n.F,n.G) && eq(n.F,n.m2_p0) && eq(n.F,n.m2_m1) && eq(n.F,n.p0_m2) && eq(n.F,n.m1_m2))
    return noLine(r);
  return r;
}

void main()
{
  //---------------------------------------
  // Input Pixel Mapping:  -|x|x|x|-
  //                       x|A|B|C|x
  //                       x|D|E|F|x
  //                       x|G|H|I|x
  //                       -|x|x|x|-

  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;

  // Read B, D and E as vec4 so their alpha (the point pass's decisions) is reused below without re-fetching
  vec4 tB = P4( 0.,-1.);
  vec4 tD = P4(-1., 0.);
  vec4 tE = P4( 0., 0.);
  vec3 B = tB.rgb, D = tD.rgb, E = tE.rgb;
  vec3 F = P( 1., 0.);
  vec3 H = P( 0., 1.);

  // fast path: xBRZ blends a corner only where E differs from both pixels beside it, so where E equals
  // opposite side neighbours (D and F, or B and H) nothing is cut
  if ((eq(E, D) && eq(E, F)) || (eq(E, B) && eq(E, H)))
  {
    FRAG_OUT = vec4(0.0);
    return;
  }

  vec4 tA = P4(-1.,-1.);
  float ptA = floor(tA.a * 255.0 + 0.5), ptB = floor(tB.a * 255.0 + 0.5);
  float ptE = floor(tE.a * 255.0 + 0.5), ptD = floor(tD.a * 255.0 + 0.5);
  vec4 pts = vec4(floor(ptA / 64.0), mod(floor(ptB / 16.0), 4.0), mod(ptE, 4.0), mod(floor(ptD / 4.0), 4.0));
  vec2 ip = floor(coord * SRC_SIZE.xy);
  pts *= vec4(min(ip.x, ip.y) > 0.5, ip.y > 0.5, 1.0, ip.x > 0.5);
  if (dot(pts, vec4(1.0)) == 0.0)
  {
    FRAG_OUT = vec4(0.0);
    return;
  }

  // pre-convert all 21 neighborhood pixels once to linear YCbCr
  vec3 A = toYCbCr(tA.rgb);
  B = toYCbCr(B);
  vec3 C = PY( 1.,-1.);
  D = toYCbCr(D);
  E = toYCbCr(E);
  F = toYCbCr(F);
  vec3 G = PY(-1., 1.);
  H = toYCbCr(H);
  vec3 I = PY( 1., 1.);
  N_m1_m2 = PY(-1., -2.);
  N_p0_m2 = PY( 0., -2.);
  N_p1_m2 = PY( 1., -2.);
  N_m2_m1 = PY(-2., -1.);
  N_p2_m1 = PY( 2., -1.);
  N_m2_p0 = PY(-2.,  0.);
  N_p2_p0 = PY( 2.,  0.);
  N_m2_p1 = PY(-2.,  1.);
  N_p2_p1 = PY( 2.,  1.);
  N_m1_p2 = PY(-1.,  2.);
  N_p0_p2 = PY( 0.,  2.);
  N_p1_p2 = PY( 1.,  2.);

  // ============================================================================================
  // xBRZ: the reference decisions (only the line tests use DistShape and toneLine, rule 9)
  // ============================================================================================
  ivec4 blendResult = ivec4(pts);

  vec4 res = vec4(blendResult);

  vec4 dE4 = sqrt(vec4(distSqY(B, E), distSqY(D, E), distSqY(E, F), distSqY(E, H)));
  float dEB = dE4.x, dED = dE4.y, dEF = dE4.z, dEH = dE4.w;
  vec4 pairSq = vec4(distSqY(B, D), distSqY(B, F), distSqY(F, H), distSqY(D, H));

  if (blendResult.z >= BLEND_NORMAL) res.z += xbrzCorner(blendResult.z, blendResult.y, blendResult.w, min(dEF, dEH), pairSq.z, B, C, D, E, F, G, H, I, N_m1_p2, N_p2_m1);
  if (blendResult.w >= BLEND_NORMAL) res.w += xbrzCorner(blendResult.w, blendResult.z, blendResult.x, min(dEH, dED), pairSq.w, F, I, B, E, H, A, D, G, N_m2_m1, N_p1_p2);
  if (blendResult.x >= BLEND_NORMAL) res.x += xbrzCorner(blendResult.x, blendResult.w, blendResult.y, min(dED, dEB), pairSq.x, H, G, F, E, D, C, B, A, N_p1_m2, N_m2_p1);
  if (blendResult.y >= BLEND_NORMAL) res.y += xbrzCorner(blendResult.y, blendResult.x, blendResult.z, min(dEB, dEF), pairSq.y, D, A, H, E, B, I, F, C, N_p2_p1, N_m1_m2);

  vec4 second = vec4(pickSecond(dED, dEB, D, B), pickSecond(dEB, dEF, B, F), pickSecond(dEF, dEH, F, H), pickSecond(dEH, dED, H, D));
  res += 8.0 * second;

  // ============================================================================================
  // the rules, in order
  // ============================================================================================
  vec4 xbrz = res;
  vec4 contrast, weak;
  res = minimumContrast(res, dEB, dED, dEF, dEH, contrast, weak);              // 1
  vec4 cutXbrz = vec4(greaterThan(BLEND(xbrz), vec4(0.0)));
  vec4 low30 = cutXbrz * vec4(lessThan(contrast, vec4(XBRZ_MINC)));
  vec4 band30Lo = vec4(0.0);
  vec4 ring30 = vec4(0.0);
  if (XBRZ_MINC > 0.0 && dot(low30, vec4(1.0)) > 0.0)
  {
    band30Lo = diagonalBands(xbrz, low30, coord, A, B, C, D, E, F, G, H, I);   // 30 (low contrast)
    ring30 = low30 * max(vec4(ringBand(B, D, A, E), ringBand(B, F, C, E), ringBand(F, H, I, E), ringBand(H, D, G, E)),
                         vec4(ringOutBand(E, C, G, I, B, D), ringOutBand(E, A, I, G, B, F), ringOutBand(E, C, G, A, F, H), ringOutBand(E, A, I, C, H, D)));
  }
  vec4 rescue30 = max(band30Lo, ring30);
  res = mix(res, xbrz, rescue30);
  weak *= 1.0 - rescue30;
  res = largerWindowLines(res, coord, A, B, C, D, E, F, G, H, I, dEB, dED, dEF, dEH, xbrz, contrast, weak);  // 11
  vec4 pair = sqrt(pairSq);
  res = diagonalRules(res, coord, A, B, C, D, E, F, G, H, I, pair, dEB, dED, dEF, dEH);  // 2 to 7
  res = weakCorners(res, weak);                                                 // 1, weak corners
  res = lineThroughAA(res, xbrz, contrast, B, D, F, H, pair, dEB, dED, dEF, dEH);  // 8
  res = closedPixel(res, A, B, C, D, E, F, G, H, I);                            // 10
  res = tilesBetweenWalls(res, A, B, C, D, E, F, G, H, I);                      // 13
  res = lineInOtherColor(res, A, B, C, D, E, F, G, H, I, pair, dEB, dED, dEF, dEH);  // 16, 18
  if (CRISP_RULES)                                                              // 32 to 35
  {
    vec4 eqPair = vec4(float(eq(B, D)), float(eq(B, F)), float(eq(F, H)), float(eq(H, D)));
    vec4 flankAny = vec4(float(eq(D, G) || eq(B, C)), float(eq(B, A) || eq(F, I)),
                         float(eq(F, C) || eq(H, G)), float(eq(H, I) || eq(D, A)));
    vec4 oppMax = max(vec4(dEH, dED, dEB, dEF), vec4(dEF, dEH, dED, dEB));
    vec4 ok3235 = max(1.0 - FLAG(res, 4.0), vec4(lessThan(oppMax * 255.0, vec4(30.0))));
    vec4 r32gate = vec4(greaterThan(BLEND(res), vec4(0.0))) * eqPair * flankAny * ok3235
                 * vec4(greaterThanEqual(contrast, vec4(40.0)));
    if (dot(r32gate, vec4(1.0)) > 0.0)
    {
      Win w = Win(A, B, C, D, E, F, G, H, I, N_m1_m2, N_p0_m2, N_p1_m2, N_m2_m1, N_p2_m1, N_m2_p0, N_p2_p0, N_m2_p1, N_p2_p1, N_m1_p2, N_p0_p2, N_p1_p2,
                  vec4(dEB, dEF, dEH, dED), pairSq);
      vec4 r33 = res;
      if (r32gate.z > 0.5) { r33.z = holeInStroke(w, res.z); res.z = smallSquare(w, r33.z + lonePixelRedone(w, r33, blendResult)); }
      if (r32gate.w + r32gate.x + r32gate.y > 0.5)
      {
        w = turn(w);
        if (r32gate.w > 0.5) { r33.w = holeInStroke(w, res.w); res.w = smallSquare(w, r33.w + lonePixelRedone(w, r33.yzwx, blendResult.yzwx)); }
        if (r32gate.x + r32gate.y > 0.5)
        {
          w = turn(w);
          if (r32gate.x > 0.5) { r33.x = holeInStroke(w, res.x); res.x = smallSquare(w, r33.x + lonePixelRedone(w, r33.zwxy, blendResult.zwxy)); }
          if (r32gate.y > 0.5)
          {
            w = turn(w);
            r33.y = holeInStroke(w, res.y); res.y = smallSquare(w, r33.y + lonePixelRedone(w, r33.wxyz, blendResult.wxyz));
          }
        }
      }
    }
  }
  vec4 band30 = band30Lo;
  vec4 needBandHi = vec4(notEqual(res, xbrz)) * cutXbrz * (1.0 - low30);
  if (XBRZ_MINC > 0.0 && dot(needBandHi, vec4(1.0)) > 0.0)
    band30 = max(band30, diagonalBands(xbrz, needBandHi, coord, A, B, C, D, E, F, G, H, I));
  res = mix(res, xbrz, band30);                                                 // 30, the band wins over the rules above
  FRAG_OUT = res / 255.0;
}

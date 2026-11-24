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
//     shading keep XBRZ_TOL. A strong exact-color 45-degree corner (dMinC >= XBRZ_STRAIGHT, cand20 < XBRZ_SAME)
//     whose line was suppressed by the lone-pixel test gets its 45-degree line back when the opposite cut
//     is non-line or much weaker, or on a 2-cut pixel where an adjacent corner draws an exact-color line
//     and E's color continues diagonally across both corners.
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
//     line through the facing corner of the neighbor that gives its color (or through its matching far-end 2:1
//     line partner painting E's color, outside a 4-color orthogonal crosshair) stays cut where its two neighbors
//     are much closer to each other than to the pixel, so a thin stroke or 2:1 contour between two light colors
//     keeps both its edges (the halo of King Kai in Buu's Fury, Sonic's muzzle outline). Two shades are no junction: where E is a
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
//     other half of the line), or where the facing corner diagonally across a uniform band (cand20 < XBRZ_SAME)
//     draws the same parallel 2:1 slope, and the corner is not a step of a straight edge (rule 14). Where none is,
//     the corner is a plain tip like a corner without a line, so the end of a 1-pixel bar, like the end of a
//     letter's stroke, does not grow a hook.
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
//     away tips them the other way, which leaves a square step in a straight diagonal edge. Likewise, where a
//     2-pixel run of a mid-tone pixel E sits beside a 2-pixel brighter wall S and shares a darker background U
//     whose facing corner already cuts into E with a 45-degree line (with the outer corners of U and S uncut),
//     E's uncut corner is beveled at 45 degrees in U's color to complete the convex corner.
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
//     (2 pixels left, right, above and below) matching its parity, or two orthogonal 2x2 blocks plus the
//     diagonal 2x2 corner between them forming a solid 4x4 exact checkerboard or framed 50% mesh quadrant
//     (with consistent 4x4 mesh/wall corners so curved outlines and compact X glyphs stay smooth), or forming
//     a 2x6 axial checker strip bounded laterally by axis-aligned walls (including where one wall transitions
//     to a foreign third color, or >= 4px wide along a full 6-pixel pure mesh axis), is not cut—except where a
//     distinct 1-pixel 45-degree diagonal stroke crosses through the 50% mesh, so diagonal dividers stay smooth.
//     Likewise a 1x4 solid wall immediately adjacent to a confirmed 2x4 exact/shaded or 3-row 50% mesh strip
//     (including against a perpendicular corner wall or at a 3-wall inner corner opening into a 3x3 alternating
//     mesh, with any non-mesh wall distinct from the adjacent non-mesh pixels) keeps its squares, so checker
//     dithering and 50% HUD mesh overlays stay square right up to their borders and corners without affecting
//     1-pixel dotted lines, compact glyphs, sawtooth edges, or diagonal strokes.
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
// XBRZ_DIAG = 0 turns rules 2 to 7, 9, 10 and 13 off, and XBRZ_MINC = 0 turns rules 1, 3, 8, 9, 11 and
// 13 to 49 off, so with XBRZ_MINC at 0 only rules 2, 4 to 7 and 10 run.
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

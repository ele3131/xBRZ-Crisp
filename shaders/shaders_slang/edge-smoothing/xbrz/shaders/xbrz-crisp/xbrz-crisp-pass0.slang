#version 450
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
//#plain // reference xBRZ shapes. Rules 1, 3, 8, 9 and 11 to 13 are the crisp look and run with XBRZ_MINC
//#plain // above 0; the xbrz-crisp preset sets it to 20, so low-contrast shading and textures keep their pixels.
//
// xBRZ decides, for each corner of each pixel, whether to cut it and how (a corner piece, a 45-degree
// line, or a shallow or steep line). The rules below then change some of those decisions. Each rule
// has a section of the same number and name in the code. The point pass decides once, at each point where
// 4 pixels meet, which way xBRZ blends there (as xBRZ's own preprocessing does), pass 0 makes each pixel's
// decisions from those of its 4 points, the resolve pass, also once per game pixel, finishes the rules
// that need the neighbours' decisions, and the output pass (pass 1) only draws the corners.
//#crisp{
// The match pass, between the resolve pass and pass 1, runs rules 26, 27 and 38 to 44.
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
//     wood, shading) keep xBRZ's lines. The thin end also goes to a pixel that is a close shade of the step
//     pixel (under XBRZ_THIN_TONE), in place of a cut of its own where it is a close shade of one neighbor of the
//     corner, so an antialiased side of a stroke runs as straight as a side in one color (a highlight on
//     red armor).
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
//     Nor is a corner cut without a line painted with the color of a pixel none of whose 8 neighbors shares
//     its color, where the corner's other neighbor differs from it by XBRZ_ISO_FAR or more and the pixel
//     across the corner is neither color, like a dark green pixel on the Golden Sun slime.
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
//     cloth above it meet a buckle with square corners on both sides (Isaac in Golden Sun).
// 21. A straight line does not bend: a corner is not painted with the color of a pixel that lies in a
//     straight line of three of its color along the pixel's side, where the corner's other neighbor
//     differs from that line by more than XBRZ_LINE_SIDE, so the line goes on straight instead of
//     bending into the pixel, and checkered patterns keep their squares. A strong thin line of four that
//     starts beside the pixel and runs toward the corner counts too, and where the other neighbor is darker
//     and goes on along the cut, the corner takes that neighbor's color instead of staying square. On a
//     ramp (the two neighbors are close shades far from the pixel, and the cut goes on) the corner is cut.
//     At the tip of an outline that runs diagonally into an area of one color, the area is no line: the
//     corner is cut as in xBRZ where the area and the other neighbor are close shades of one background,
//     and otherwise takes the other neighbor's color, so the background does not bite into the object,
//     like the hand in Golden Sun's village.
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
//     of a pixel's color counts for it, a side neighbor twice, and on a tie the darker pixel stays whole
//     (the two differ by more than XBRZ_JUNCTION), like the tree crowns of Golden Sun's Mt. Aleph.
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
//     drawn as a 45-degree cut and a plain cut, like the olive stripe on the Golden Sun slime.
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
// 46. A checkerboard keeps its squares: a 2x2 checker of two colors with three or more of the 2x2 blocks
//     beside it (2 pixels left, right, above and below) checkers of the same two colors is not cut, so a
//     checker texture stays square up to an outline that crosses it (xBRZ's 4x4 window turns the checker
//     next to an outline into zigzags).
// 47. A notch in a straight stroke: where E's corner would be cut in the color of a lone pixel beside it
//     that is a close shade of E, while E's color goes on straight past its other neighbor and diagonally
//     past the lone pixel, and the color on E's far side is XBRZ_FAR47 or more away, the corner stays square,
//     so a shade at the bend of a stroke does not cut a notch into its straight side (a wizard's staff).
// XBRZ_DIAG = 0 turns rules 2 to 7, 9, 10, 12 and 13 off, and XBRZ_MINC = 0 turns rules 1, 3, 8, 9 and
// 11 to 47 off, so with XBRZ_MINC at 0 only rules 2, 4 to 7 and 10 run.
//#crisp}
//#plain // XBRZ_DIAG = 0 turns rules 2 to 7, 9, 10, 12 and 13 off, and XBRZ_MINC = 0 turns rules 1, 3, 8, 9 and
//#plain // 11 to 13 off, so with XBRZ_MINC at 0 only rules 2, 4 to 7 and 10 run.
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
   vTexCoord = TexCoord * 1.0001;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
layout(set = 0, binding = 2) uniform sampler2D Source;
#define SRC_SIZE params.SourceSize
#define P(x,y) texture(Source, coord + SRC_SIZE.zw * vec2(x, y)).rgb
// the point pass's decision of the point at a pixel's bottom-right corner (see the point pass)
#define PT(x,y) floor(texture(Source, coord + SRC_SIZE.zw * vec2(x, y)).a * 255.0 + 0.5)

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
// rules 3, 9, 12 and 13 belong to the crisp look rather than fixing clear xBRZ errors, so they
// run only when XBRZ_MINC is on too (plain xBRZ, with XBRZ_MINC 0, keeps rules 2, 4 to 7 and 10)
#define CRISP_RULES (XBRZ_MINC > 0.0 && XBRZ_DIAG > 0.0)
#define XBRZ_ALIKE 20.0     // colors this close (x/255) count as alike
#define XBRZ_HYST 4.0       // 1. a corner this close below XBRZ_MINC is weak
#define XBRZ_BAND_FAR 20.0  // 30. the color past a band of three pixels or more differs from the pixel by this
#define XBRZ_BAND_FAR2 30.0 // 30. and past a band of two pixels by this
#define XBRZ_DIAG_AA 92.0   // 2. diagonal limit on antialiasing ramps
#define XBRZ_RAMP 1.15      // 2, 6. a ramp: (d(E,P) + d(P,Q)) / d(E,Q) up to this
#define XBRZ_STRIPE 64.0    // 2, 3. a diagonal stripe keeps a close color (within this) along its length
#define XBRZ_OUTLINE 0.15   // 2, 3. an outline is darker (in luma) than both inner tones by this much
#define XBRZ_NOT_LIGHTER 4.0 // 2. P is not lighter than E up to this much more luma (x/255)
#define XBRZ_THIN_LIGHT 0.15 // 5. a thin stroke is lighter (in luma) than both of its colors by this much
#define XBRZ_THIN_DARK 0.45 // 5. on colors darker than this (luma) the stroke counts without the test of its sides
#define XBRZ_TONE 0.6       // 5, 6. a pixel has E's tone when it is closer to E than this times its distance to the other colors
#define XBRZ_NOTCH 45.0     // 6. the notch's diagonal limit is XBRZ_DIAG plus this
#define XBRZ_TIP 36.0       // 7. stripe ends stay square above this diagonal distance
#define XBRZ_AA_LINE 1.01   // 8. E lies between the colors: d(P1,E) + d(E,P2) up to this times d(P1,P2)
#define XBRZ_AA_OFF 1.2     // 8. three colors are on no ramp when the two short steps add up to more than this times the long one
#define XBRZ_AA_EDGE 40.0   // 8. the two colors differ by at least this
#define XBRZ_FAR_TONE 36.0  // 9. two colors that clearly differ: more than this apart
#define XBRZ_BLACK 0.15     // 10. a near-black outline is darker than this (luma)
#define XBRZ_BLACK_GAP 0.1  // 10. the outline is darker (luma) than E and the pixel closed by it by this much
#define XBRZ_STRONG 40.0    // 11. the contour past a 1-pixel stripe differs from it by at least this
#define XBRZ_SHADOW 0.10    // 12. a shadow is darker than this (luma)
#define XBRZ_SHADOW_NEAR 0.08 // 12. close to a shadow color: darker than XBRZ_SHADOW plus this
#define XBRZ_SHADOW_BG 0.07 // 12. close to the background: lighter than XBRZ_SHADOW plus this
#define XBRZ_SHADOW_FLOOR 0.15 // 12. the floor and the object are lighter than the shadow by more than this (luma)
#define XBRZ_GUARD 30.0     // 15. lone pixel test tolerance on strong edges (reference xBRZ)
#define XBRZ_GUARD_EDGE 64.0 // 15. a strong edge: the pixel differs from both corner colors by this much
#define XBRZ_GUARD_EDGE_L 54.0 // 15. the same for the L-shape test
#define XBRZ_TINT 20.0      // 16. the two colors beside the line differ by more than this
#define XBRZ_TINT_RAMP 1.2  // 16. not a ramp: d(E,P) + d(P,L) above this times d(E,L)
#define XBRZ_TINT_DARK 0.25 // 18. a near-black outline is darker than this (luma)
#define alike(a,b) (DistYCbCr(a, b) * 255.0 <= XBRZ_ALIKE)
#define eq(a,b)  (a == b)
#define neq(a,b) (a != b)

// the ring of pixels two steps from E (the 5x5 window without its corners), read once in main
vec3 N_m1_m2, N_p0_m2, N_p1_m2, N_m2_m1, N_p2_m1, N_m2_p0, N_p2_p0, N_m2_p1, N_p2_p1, N_m1_p2, N_p0_p2, N_p1_p2;

// the luma weights (Rec. 2020) and the scales of the two chroma differences, for DistYCbCr and DistShape
const vec3 lumaW = vec3(0.2627, 0.6780, 0.0593);
const float scaleB = 0.5 / (1.0 - 0.0593);
const float scaleR = 0.5 / (1.0 - 0.2627);

float DistYCbCr(vec3 pixA, vec3 pixB)
{
  vec3 diff = pixA - pixB;
  float Y = dot(diff.rgb, lumaW);
  float Cb = scaleB * (diff.b - Y);
  float Cr = scaleR * (diff.r - Y);
  return sqrt((Y * Y) + (Cb * Cb) + (Cr * Cr));
}

// The distance is symmetric, and below the two pixels of each distance (and of alike and IsPixEqual) are
// written in one fixed order (A to I, then the ring of pixels two steps away), so the compiler computes
// each distance only once. The pixels two steps away are read once, at the start of main.
bool IsPixEqual(vec3 pixA, vec3 pixB)
{
  return (DistYCbCr(pixA, pixB) < EQUAL_COLOR_TOLERANCE);
}

// 15. Lone pixel and L-shape tests on strong edges: the tolerance of xBRZ's lone pixel test and L-shape
// test in the blend decisions; edge is how much E differs from the closer corner color, and edgeLimit
// how much that must be (XBRZ_GUARD_EDGE or XBRZ_GUARD_EDGE_L) for the reference tolerance to apply
bool equalOnEdge(vec3 pixA, vec3 pixB, float edge, float edgeLimit)
{
  return DistYCbCr(pixA, pixB) < (XBRZ_MINC > 0.0 && edge * 255.0 >= edgeLimit ? XBRZ_GUARD / 255.0 : EQUAL_COLOR_TOLERANCE);
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
// the thresholds
float DistShape(vec3 pixA, vec3 pixB)
{
  const vec2 k = vec2(0.937, 1.125);
  vec3 diff = pixA - pixB;
  float y = dot(diff.rgb, lumaW);
  float Y = k.x * y;
  float Cb = k.y * scaleB * (diff.b - y);
  float Cr = k.y * scaleR * (diff.r - y);
  return sqrt((Y * Y) + (Cb * Cb) + (Cr * Cr));
}

// a line xBRZ finds that the hue-weighted test does not is kept too, except where it would bring
// back a corner blocked by the diagonal limit (rule 2), or where the line's color runs on along a
// 45-degree diagonal in the same color while the line test pairs it with a different one (alt45)
bool plainLine(vec3 a, vec3 b, vec3 c, vec3 d, float pairD, bool alt45)
{
  return STEEP_E * DistYCbCr(a, b) <= DistYCbCr(c, d) && pairD * 255.0 <= XBRZ_DIAG && !alt45;
}

// a shallow or steep line found only because hue weighs more (DistShape) between two different
// colors is flagged +32, so the resolve pass can drop it where it runs into the neighbour's line
float toneLine(vec3 a, vec3 b, vec3 c, vec3 d)
{
  return float(!IsPixEqual(a, b) && STEEP_E * DistYCbCr(a, b) > DistYCbCr(c, d));
}

// a line found only because hue weighs more (+32) is dropped where the pixel at its far end is closer
// to E than to the line's color: that pixel belongs to E's side, so the line would cut into E's run.
// It is also dropped where its two colors clearly differ (more than XBRZ_FAR_TONE) and the line's color runs on
// along a 45-degree diagonal in the same color (alt45, as for plainLine): the line would bend that
// diagonal toward another stroke (the tip of Goku's nose in Buu's Fury)
bool farTone(vec3 a, vec3 b, vec3 c, vec3 d, vec3 E, bool alt45)
{
  return !(toneLine(a, b, c, d) > 0.5 && (DistYCbCr(E, b) < DistYCbCr(a, b) || (alt45 && DistYCbCr(a, b) * 255.0 > XBRZ_FAR_TONE)));
}

// the shallow (x) and steep (y) line tests of a corner, a line along a-b against one along c-d, as
// the flags they add (+16 and +64, and +32 for a line found only because hue weighs more): xBRZ's own
// test (STEEP_E * d(a, b) <= d(c, d)) without the crisp rules, the hue-weighted one with them
vec2 lineTests(vec3 a, vec3 b, vec3 c, vec3 d, vec3 E, float pairD, bool alt45s, bool alt45t)
{
  if (!CRISP_RULES)
  {
    float ab = DistYCbCr(a, b), cd = DistYCbCr(c, d);
    return vec2(STEEP_E * ab <= cd ? 16.0 : 0.0, STEEP_E * cd <= ab ? 64.0 : 0.0);
  }
  float sab = DistShape(a, b), scd = DistShape(c, d);
  float shallow = (((STEEP_E * sab <= scd) && farTone(a, b, c, d, E, alt45s)) || plainLine(a, b, c, d, pairD, alt45s)) ? 16.0 + 32.0 * toneLine(a, b, c, d) : 0.0;
  float steep = (((STEEP_E * scd <= sab) && farTone(c, d, a, b, E, alt45t)) || plainLine(c, d, a, b, pairD, alt45t)) ? 64.0 + 32.0 * toneLine(c, d, a, b) : 0.0;
  return vec2(shallow, steep);
}

// ============================================================================================
// 30. Diagonal bands
// ============================================================================================
// The band test at one corner, seen from the pixel at offset o (color e): p and q are the offsets of its
// two neighbors at the corner (colors cp and cq) and cpq is the color of the corner pixel. Two cases, both
// with cp and cq of one color. That color is the band (cpq differs): the corner pixel's color goes on along
// the band, e's color goes on on the other side, and the corner pixel is farther from e than from the band.
// Or e is the band (cpq is the same color as cp and cq): e's color goes on diagonally, and the pixel across e
// from the corner is farther from that color than from e. A band of three pixels or more needs the far color
// XBRZ_BAND_FAR away, a band of two XBRZ_BAND_FAR2. The four colors come from the caller, so nothing is
// read before the cheap test of cp and cq.
float bandSide(vec2 coord, vec2 o, vec2 p, vec2 q, vec3 e, vec3 cp, vec3 cq, vec3 cpq)
{
  if (!eq(cp, cq)) return 0.0;
  vec2 t = p - q;
  if (eq(cp, cpq))
  {
    bool a = eq(e, P(o.x + t.x, o.y + t.y)), b = eq(e, P(o.x - t.x, o.y - t.y));
    if (!a && !b) return 0.0;
    vec3 opp = P(o.x - p.x - q.x, o.y - p.y - q.y);
    float d = DistYCbCr(opp, cp);
    if (d <= DistYCbCr(opp, e) || d * 255.0 < XBRZ_BAND_FAR) return 0.0;
    if (d * 255.0 >= XBRZ_BAND_FAR2 || (a && b)) return 1.0;
    return (a ? eq(e, P(o.x + 2.0 * t.x, o.y + 2.0 * t.y)) : eq(e, P(o.x - 2.0 * t.x, o.y - 2.0 * t.y))) ? 1.0 : 0.0;
  }
  float dAE = DistYCbCr(cpq, e);
  if (dAE <= DistYCbCr(cpq, cp) || dAE * 255.0 < XBRZ_BAND_FAR) return 0.0;
  if (!eq(cpq, P(o.x + 2.0 * p.x, o.y + 2.0 * p.y)) && !eq(cpq, P(o.x + 2.0 * q.x, o.y + 2.0 * q.y))) return 0.0;
  if (!eq(e, P(o.x + t.x, o.y + t.y)) && !eq(e, P(o.x - t.x, o.y - t.y))) return 0.0;
  if (dAE * 255.0 >= XBRZ_BAND_FAR2) return 1.0;
  return (eq(cp, P(o.x + p.x + t.x, o.y + p.y + t.y)) || eq(cp, P(o.x + q.x - t.x, o.y + q.y - t.y))) ? 1.0 : 0.0;
}
// The corners of E that xBRZ cuts and a band passes through, seen from any of the four pixels that meet at
// the corner: E, V and H (its neighbors at the offsets v and h) and VH (the corner pixel). A band needs one
// of the two diagonals of those four pixels in one color, so most corners leave before anything is read.
// One corner and one side at a time, so the test is compiled once.
// 32 to 34: two close shades (under 30 apart)
bool near(vec3 a, vec3 b) { return DistYCbCr(a, b) * 255.0 < 30.0; }

vec4 diagonalBands(vec4 xbrz, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  vec4 band = vec4(0.0);
  if (XBRZ_MINC <= 0.0)
    return band;
  vec4 cut = vec4(greaterThan(BLEND(xbrz), vec4(0.0)));
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
      // the pixel that looks at the corner: E and the corner pixel when V and H share a color, V and H otherwise
      bool first = j == 0;
      vec2 o = vh ? (first ? vec2(0.0) : v + h) : (first ? v : h);
      vec2 p = vh ? (first ? v : -v) : (first ? -v : v);
      vec2 q = first ? h : -h;
      vec3 e   = vh ? (first ? E : cVH) : (first ? cV : cH);
      vec3 cp  = vh ? (first ? cV : cH) : (first ? E : cVH);
      vec3 cq  = vh ? (first ? cH : cV) : (first ? cVH : E);
      vec3 cpq = vh ? (first ? cVH : E) : (first ? cH : cV);
      f = bandSide(coord, o, p, q, e, cp, cq, cpq);
    }
    band += m * f;
  }
  return band;
}
// 30b. Outline around a strong shape: a corner that rule 1 left square because its colors are close
// shades still takes xBRZ's cut where a dark outline 1 pixel wide runs diagonally around a pixel that
// differs from the outline by XBRZ_RING or more: on the background side (the corner's two neighbors are
// the outline, the strong pixel lies past the cut) and on the outline's own outer corners (E is the
// outline, which goes on diagonally on both sides, with the strong pixel at the opposite corner), so the
// outline of a bright shape stays a closed diagonal ring over a low-contrast background (the orange
// diamond in Plataforma).
#define XBRZ_RING 64.0
float ringBand(vec3 P, vec3 Q, vec3 X, vec3 E)
{
  if (!alike(P, Q)) return 0.0;
  float lP = dot(P, lumaW);
  return float(DistYCbCr(P, X) * 255.0 >= XBRZ_RING && DistYCbCr(E, X) * 255.0 >= XBRZ_RING && lP < dot(E, lumaW) && lP < dot(X, lumaW) && !alike(E, X));
}
float ringOutBand(vec3 E, vec3 K1, vec3 K2, vec3 X, vec3 N1, vec3 N2)
{
  if (!alike(E, K1) || !alike(E, K2)) return 0.0;
  float lE = dot(E, lumaW);
  return float(DistYCbCr(E, X) * 255.0 >= XBRZ_RING && min(DistYCbCr(N1, X), DistYCbCr(N2, X)) * 255.0 >= XBRZ_RING && lE < dot(X, lumaW) && lE < dot(N1, lumaW) && lE < dot(N2, lumaW));
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
    weak = vec4(greaterThanEqual(contrast, vec4(XBRZ_MINC - XBRZ_HYST))) * vec4(lessThan(contrast, vec4(XBRZ_MINC)));
    res *= max(vec4(greaterThanEqual(contrast, vec4(XBRZ_MINC))), weak);
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
// P's stroke ends at its pixel o - side: no pixel of P's color right after it, straight on (o) or diagonally (o +- side),
// and the pixel straight on is not Q's color either (a shaded outline whose tones step from P to Q is one outline)
float strokeEnds(vec3 p, vec3 q, vec2 coord, vec2 o, vec2 side)
{
  vec3 T = P(o.x, o.y);
  return float(!alike(p, T) && !alike(q, T) && !alike(p, P(o.x + side.x, o.y + side.y)) && !alike(p, P(o.x - side.x, o.y - side.y)));
}

// the pixel at t is part of a straight horizontal or vertical line of its color, 3 pixels or more (a wall)
float wallAt(vec2 coord, vec2 t)
{
  vec3 T = P(t.x, t.y);
  bool l = alike(T, P(t.x - 1., t.y)), r = alike(T, P(t.x + 1., t.y)), u = alike(T, P(t.x, t.y - 1.)), d = alike(T, P(t.x, t.y + 1.));
  return float((l && (r || alike(T, P(t.x - 2., t.y)))) || (r && alike(T, P(t.x + 2., t.y))) ||
               (u && (d || alike(T, P(t.x, t.y - 2.)))) || (d && alike(T, P(t.x, t.y + 2.))));
}

// E's color runs on along the diagonal d and the first pixel past the run (up to 3 pixels) is a wall;
// the run's length k is found first, so the wall test is compiled once
float runWall(vec3 E, vec2 coord, vec2 d)
{
  float k = !alike(E, P(d.x, d.y)) ? 1.0 : !alike(E, P(2. * d.x, 2. * d.y)) ? 2.0 : !alike(E, P(3. * d.x, 3. * d.y)) ? 3.0 : 0.0;
  return k > 0.0 ? wallAt(coord, k * d) : 1.0;
}

// ============================================================================================
// helper for rule 7
// ============================================================================================
// E ends a stripe at one of its four ends, read in the end's own frame: the canonical end is the left
// one (the stripe runs on to the right, D lies past the end, B and H are the stripes on both sides).
// The other ends pass the pixels turned to that frame: the right end passes C B A F D I H G for
// A B C D F G H I, the top end A D G B H C F I, and the bottom end G D A H B I F C. l2 and r2 are the
// pixels two steps from E past the end and along the stripe, rt and rb the ones beside r2 on the
// sides of B and H. o1 and o2 are the offsets (in the whole window) of the pixels two steps past the
// end and two to the side, o3 of the pixel three steps along the stripe.
bool stripeEnd(vec2 coord, vec2 o1, vec2 o2, vec2 o3, bool thin, vec3 E, vec3 A, vec3 B, vec3 C, vec3 D, vec3 F, vec3 G, vec3 H, vec3 I,
               vec3 l2, vec3 r2, vec3 rt, vec3 rb)
{
  // the cheap terms first: E's stripe runs on along F and ends at D, and the stripes on both sides
  // differ from the pixels past their ends (A, G) and run on (C, I)
  if (!(thin && alike(E, F) && !eq(E, D) && !eq(B, A) && !eq(H, G) && alike(B, C) && alike(H, I)))
    return false;
  // E is not an end when its color runs on along a diagonal past the end (a line turning diagonal,
  // like the bottom of a 3), or when a side stripe bends into it there
  if (alike(A, E) && alike(E, P(o1.x, o1.y)) && !alike(D, E) && !alike(B, E))
    return false;
  if (alike(E, G) && alike(E, P(o2.x, o2.y)) && !alike(D, E) && !alike(E, H))
    return false;
  if ((alike(A, E) && alike(B, D)) || (alike(E, G) && alike(D, H)))
    return false;
  // all three stripes run at least 3 pixels back from the end, and E's 4 when the color past the end
  // runs straight on (a line meeting a short stripe, not a gauge)
  return alike(E, r2) && (alike(E, P(o3.x, o3.y)) || !eq(D, l2)) && alike(C, rt) && alike(I, rb);
}

// ============================================================================================
// Rules 2 to 7 (XBRZ_DIAG)
// ============================================================================================
vec4 diagonalRules(vec4 res, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                   vec4 pair, float dEB, float dED, float dEF, float dEH)
{
  // only pixels that still have a corner to cut
  vec4 cut = vec4(greaterThan(BLEND(res), vec4(0.0)));
  if (XBRZ_DIAG <= 0.0 || dot(cut, vec4(1.0)) <= 0.0)
    return res;
  // the decisions before rules 2 to 7: rules 4 to 6 bring corners back to them
  vec4 before = res;

  // ---- what the rules look at ----
  // E's distance to the first and second candidate of each corner
  vec4 dEP = vec4(dED, dEB, dEF, dEH);
  vec4 dEQ = vec4(dEB, dEF, dEH, dED);
  // P and Q of each corner (FLAG 8: P is the second candidate)
  vec4 sec = FLAG(res, 8.0);
  vec3 Px = sec.x > 0.5 ? B : D, Py = sec.y > 0.5 ? F : B, Pz = sec.z > 0.5 ? H : F, Pw = sec.w > 0.5 ? D : H;
  vec3 Qx = sec.x > 0.5 ? D : B, Qy = sec.y > 0.5 ? B : F, Qz = sec.z > 0.5 ? F : H, Qw = sec.w > 0.5 ? H : D;
  float lE = dot(E, lumaW);
  vec4 lP = vec4(dot(Px, lumaW), dot(Py, lumaW), dot(Pz, lumaW), dot(Pw, lumaW));
  vec4 lQ = vec4(dot(Qx, lumaW), dot(Qy, lumaW), dot(Qz, lumaW), dot(Qw, lumaW));
  // dark keeps its pixel: P is not lighter than E
  vec4 notLighter = vec4(lessThanEqual(lP, vec4(lE + XBRZ_NOT_LIGHTER / 255.0)));
  // P runs straight on away from the corner (a horizontal or vertical line or frame)
  vec4 straight = vec4(float(sec.x > 0.5 ? alike(B, C) : alike(D, G)), float(sec.y > 0.5 ? alike(F, I) : alike(A, B)),
                       float(sec.z > 0.5 ? alike(G, H) : alike(C, F)), float(sec.w > 0.5 ? alike(A, D) : alike(H, I)));
  // the pixel two steps from E through P (R), the pixel on the far side of P from Q (S), and the pixel
  // next to R on E's side (U)
  vec3 Rx = sec.x > 0.5 ? N_p0_m2 : N_m2_p0, Ry = sec.y > 0.5 ? N_p2_p0 : N_p0_m2;
  vec3 Rz = sec.z > 0.5 ? N_p0_p2 : N_p2_p0, Rw = sec.w > 0.5 ? N_m2_p0 : N_p0_p2;
  vec3 Sx = sec.x > 0.5 ? C : G, Sy = sec.y > 0.5 ? I : A, Sz = sec.z > 0.5 ? G : C, Sw = sec.w > 0.5 ? A : I;
  vec3 Ux = sec.x > 0.5 ? N_p1_m2 : N_m2_p1, Uy = sec.y > 0.5 ? N_p2_p1 : N_m1_m2;
  vec3 Uz = sec.z > 0.5 ? N_m1_p2 : N_p2_m1, Uw = sec.w > 0.5 ? N_m2_m1 : N_p1_p2;

  // ---- 2. Diagonal limit ----
  // a ramp: one diagonal color lies (almost) on the way from E to the other one
  vec4 ramp = min((dEP + pair) / max(dEQ, vec4(1e-5)), (dEQ + pair) / max(dEP, vec4(1e-5)));
  vec4 limit = mix(vec4(XBRZ_DIAG), vec4(XBRZ_DIAG_AA), vec4(lessThanEqual(ramp, vec4(XBRZ_RAMP))));
  // within the limit, or a shallow or steep line (+16, +64) that does not cut a pixel lighter than P
  vec4 keep = max(vec4(lessThanEqual(pair * 255.0, limit)), vec4(greaterThanEqual(res, vec4(16.0))) * notLighter);
  // diagonal stripe tips: P is a 1-pixel stripe that runs on along the cut (a close color two pixels
  // away from E) and E's color runs on along its other side, so the tip is drawn to the edge
  vec4 tipLine;
  tipLine.x = sec.x > 0.5 ? float(alike(C, E) && min(DistYCbCr(B, N_p0_m2), DistYCbCr(B, N_p1_m2)) * 255.0 <= XBRZ_STRIPE)
                          : float(alike(E, G) && min(DistYCbCr(D, N_m2_p0), DistYCbCr(D, N_m2_p1)) * 255.0 <= XBRZ_STRIPE);
  tipLine.y = sec.y > 0.5 ? float(alike(E, I) && min(DistYCbCr(F, N_p2_p0), DistYCbCr(F, N_p2_p1)) * 255.0 <= XBRZ_STRIPE)
                          : float(alike(A, E) && min(DistYCbCr(B, N_p0_m2), DistYCbCr(B, N_m1_m2)) * 255.0 <= XBRZ_STRIPE);
  tipLine.z = sec.z > 0.5 ? float(alike(E, G) && min(DistYCbCr(H, N_p0_p2), DistYCbCr(H, N_m1_p2)) * 255.0 <= XBRZ_STRIPE)
                          : float(alike(C, E) && min(DistYCbCr(F, N_p2_p0), DistYCbCr(F, N_p2_m1)) * 255.0 <= XBRZ_STRIPE);
  tipLine.w = sec.w > 0.5 ? float(alike(A, E) && min(DistYCbCr(D, N_m2_p0), DistYCbCr(D, N_m2_m1)) * 255.0 <= XBRZ_STRIPE)
                          : float(alike(E, I) && min(DistYCbCr(H, N_p0_p2), DistYCbCr(H, N_p1_p2)) * 255.0 <= XBRZ_STRIPE);
  keep = max(keep, tipLine);
  // inner line up to the outline: E and P are close tones (within XBRZ_DIAG) and Q is an outline darker
  // than both, so the cut runs between the inner tones and the outline stays whole. A straight P is
  // left straight, and the steps of a 1-pixel stripe along the outline (a gauge) stay square
  // E's color goes on past E away from Q, so E is wider than a 1-pixel stripe along Q
  vec4 wide = vec4(float(alike(E, sec.x > 0.5 ? F : H)), float(alike(E, sec.y > 0.5 ? H : D)),
                   float(alike(E, sec.z > 0.5 ? D : B)), float(alike(E, sec.w > 0.5 ? B : F)));
  // E is the corner of a solid block of its color (E's color goes on past E on both far sides and
  // between them), so a dot of another color next to it does not round the block's corner
  vec4 block = wide * vec4(float(alike(E, sec.x > 0.5 ? H : F) && alike(E, I)), float(alike(E, sec.y > 0.5 ? D : H) && alike(E, G)),
                           float(alike(E, sec.z > 0.5 ? B : D) && alike(A, E)), float(alike(E, sec.w > 0.5 ? F : B) && alike(C, E)));
  vec4 lR = vec4(dot(Rx, lumaW), dot(Ry, lumaW), dot(Rz, lumaW), dot(Rw, lumaW));
  vec4 lU = vec4(dot(Ux, lumaW), dot(Uy, lumaW), dot(Uz, lumaW), dot(Uw, lumaW));
  vec4 dEPc = mix(dEP, dEQ, sec);
  vec4 inner = vec4(lessThanEqual(dEPc * 255.0, vec4(XBRZ_DIAG))) * vec4(lessThan(lQ, min(lP, vec4(lE)) - XBRZ_OUTLINE))
             * notLighter * (1.0 - straight) * wide * (1.0 - block);
  // the artist's corner bevel: P is a single antialiasing pixel in a corner of the outline (E's color on
  // its far side, the outline beyond it and turning back along E's side), so the corner is already
  // rounded and the line does not round the pixel next to it again
  vec4 bevel = vec4(float(alike(E, Sx)), float(alike(E, Sy)), float(alike(E, Sz)), float(alike(E, Sw)))
             * vec4(lessThan(max(lR, lU), min(lP, vec4(lE)) - XBRZ_OUTLINE));
  inner *= 1.0 - bevel;
  keep = max(keep, inner);
  // a blocked corner is flagged (+128); the resolve pass cuts it only where it continues a cut line.
  // When P runs straight on, the corner is dropped instead, so a diagonal stops at a frame
  res += 128.0 * (1.0 - keep) * cut;
  res *= 1.0 - (1.0 - keep) * straight * cut;

  // ---- 3. Eye ----
  // two dark strokes of different colors meet in an L around a 1-pixel light gap E, like a pupil under
  // an eyebrow: Q passes the corner, P is a short 1-pixel line that ends against it. The corner is
  // dropped, so the two strokes are not joined into a diagonal
  if (CRISP_RULES)
  {
    // the cheap factors first: the many alike() tests run only where one of them is nonzero
    vec4 gate = straight * cut * vec4(lessThan(max(lP, lQ), vec4(lE - XBRZ_OUTLINE)));
    if (dot(gate, vec4(1.0)) > 0.0)
    {
      vec4 eye = vec4(float(!alike(Px, Qx) && alike(Qx, A) && !alike(Px, A) && !alike(Px, Rx) && !alike(E, sec.x > 0.5 ? H : F)),
                      float(!alike(Py, Qy) && alike(Qy, C) && !alike(Py, C) && !alike(Py, Ry) && !alike(E, sec.y > 0.5 ? D : H)),
                      float(!alike(Pz, Qz) && alike(Qz, I) && !alike(Pz, I) && !alike(Pz, Rz) && !alike(E, sec.z > 0.5 ? B : D)),
                      float(!alike(Pw, Qw) && alike(Qw, G) && !alike(Pw, G) && !alike(Pw, Rw) && !alike(E, sec.w > 0.5 ? F : B)))
                * gate;
      // E is not part of a diagonal stripe along the cut
      float stripeCG = float(min(DistYCbCr(C, E), DistYCbCr(E, G)) * 255.0 <= XBRZ_STRIPE);
      float stripeAI = float(min(DistYCbCr(A, E), DistYCbCr(E, I)) * 255.0 <= XBRZ_STRIPE);
      eye *= 1.0 - vec4(stripeCG, stripeAI, stripeCG, stripeAI);
      if (dot(eye, vec4(1.0)) > 0.0)
      {
        eye *= vec4(sec.x > 0.5 ? strokeEnds(Px, Qx, coord, vec2(2.,-1.), vec2(0.,1.)) : strokeEnds(Px, Qx, coord, vec2(-1.,2.), vec2(1.,0.)),
                    sec.y > 0.5 ? strokeEnds(Py, Qy, coord, vec2(1.,2.), vec2(1.,0.)) : strokeEnds(Py, Qy, coord, vec2(-2.,-1.), vec2(0.,1.)),
                    sec.z > 0.5 ? strokeEnds(Pz, Qz, coord, vec2(-2.,1.), vec2(0.,1.)) : strokeEnds(Pz, Qz, coord, vec2(1.,-2.), vec2(1.,0.)),
                    sec.w > 0.5 ? strokeEnds(Pw, Qw, coord, vec2(-1.,-2.), vec2(1.,0.)) : strokeEnds(Pw, Qw, coord, vec2(2.,1.), vec2(0.,1.)));
        res *= 1.0 - eye;
      }
    }
  }

  // ---- 4. Diagonal up to the wall ----
  // a corner changed by rules 2 and 3 goes back to its decision before them when E's color runs on as a
  // 45-degree diagonal parallel to the cut (C or G for the / corners, A or I for the \ ones) up to a wall
  // at one end, and the neighbour on that diagonal sits on the same 45-degree step (or E's color runs 3
  // pixels along it), like hair or the corner of a fence post
  vec4 kept = vec4(0.0), loneP = vec4(0.0), loneQ = vec4(0.0);
  if (any(notEqual(res, before)))
  {
    // not where P and Q are both lone pixels (no neighbour of their own color in a cross), like an eye.
    // B, D, F and H are each lone when none of their other three cross neighbours has their color; the
    // first and second blend candidates of the corners x y z w are D B F H and B F H D
    vec4 lone = vec4(float(!alike(A, B) && !alike(B, C) && !alike(B, N_p0_m2)), float(!alike(A, D) && !alike(D, G) && !alike(D, N_m2_p0)),
                     float(!alike(C, F) && !alike(F, I) && !alike(F, N_p2_p0)), float(!alike(G, H) && !alike(H, I) && !alike(H, N_p0_p2)));
    loneP = mix(lone.yxzw, lone.xzwy, sec);
    loneQ = mix(lone.xzwy, lone.yxzw, sec);
    // E's color runs on along a diagonal of a cut corner (the partner test below needs it): the rest only there
    vec4 diagE = vec4(float(alike(C, E) || alike(E, G)), float(alike(A, E) || alike(E, I)),
                      float(alike(C, E) || alike(E, G)), float(alike(A, E) || alike(E, I))) * cut;
    if (dot(diagE, vec4(1.0)) > 0.0)
    {
    // the neighbour of E's color on the diagonal differs from both pixels beside its own corner
    vec4 partner = vec4(
      float((alike(C, E) && !alike(B, C) && !alike(C, N_p1_m2)) || (alike(E, G) && !alike(G, N_m2_p1) && !alike(D, G))),
      float((alike(A, E) && !alike(A, N_m1_m2) && !alike(A, B)) || (alike(E, I) && !alike(F, I) && !alike(I, N_p2_p1))),
      float((alike(C, E) && !alike(C, N_p2_m1) && !alike(C, F)) || (alike(E, G) && !alike(G, H) && !alike(G, N_m1_p2))),
      float((alike(A, E) && !alike(A, D) && !alike(A, N_m2_m1)) || (alike(E, I) && !alike(I, N_p1_p2) && !alike(H, I))));
    float l3CG = float((alike(C, E) && alike(E, P(2., -2.))) || (alike(E, G) && alike(E, P(-2., 2.))));
    float l3AI = float((alike(A, E) && alike(E, P(-2., -2.))) || (alike(E, I) && alike(E, P(2., 2.))));
    partner = max(partner, vec4(l3CG, l3AI, l3CG, l3AI));
    // E ends a straight line of its color, 3 pixels or more, that runs away from the corner
    float lineR = float(alike(E, F) && alike(E, N_p2_p0)), lineL = float(alike(D, E) && alike(E, N_m2_p0));
    float lineD = float(alike(E, H) && alike(E, N_p0_p2)), lineU = float(alike(B, E) && alike(E, N_p0_m2));
    vec4 endLine = vec4(max(lineR, lineD), max(lineL, lineD), max(lineL, lineU), max(lineR, lineU));
    // Q runs straight on away from the corner, or passes through it for 2 pixels (straightQ0) or 3 (straightQ)
    vec4 straightQ = vec4(float(sec.x > 0.5 ? alike(D, G) : alike(B, C)), float(sec.y > 0.5 ? alike(A, B) : alike(F, I)),
                          float(sec.z > 0.5 ? alike(C, F) : alike(G, H)), float(sec.w > 0.5 ? alike(H, I) : alike(A, D)));
    vec4 straightQ0 = max(straightQ, vec4(float(alike(Qx, A)), float(alike(Qy, C)), float(alike(Qz, I)), float(alike(Qw, G))));
    straightQ = max(straightQ, vec4(float(alike(Qx, A) && alike(Qx, sec.x > 0.5 ? N_m1_m2 : N_m2_m1)),
                                    float(alike(Qy, C) && alike(Qy, sec.y > 0.5 ? N_p2_m1 : N_p1_m2)),
                                    float(alike(Qz, I) && alike(Qz, sec.z > 0.5 ? N_p1_p2 : N_p2_p1)),
                                    float(alike(Qw, G) && alike(Qw, sec.w > 0.5 ? N_m2_p1 : N_m1_p2))));
    // E is a 1-pixel stripe along P; there Q bends when it passes the corner for only 2 pixels
    float sH = float(!alike(B, E) && !alike(E, H) && !alike(B, H)), sV = float(!alike(D, E) && !alike(E, F) && !alike(D, F));
    vec4 stripeE = vec4(sec.x > 0.5 ? sH : sV, sec.y > 0.5 ? sV : sH, sec.z > 0.5 ? sH : sV, sec.w > 0.5 ? sV : sH);
    vec4 bendQ = straightQ0 * (1.0 - straightQ) * stripeE;
    vec4 sQ = mix(straightQ0, straightQ, stripeE);
    // Q runs on along the cut: the pixel after Q in the cut's direction has Q's color
    vec3 Qnx = sec.x > 0.5 ? N_m2_p1 : N_p1_m2, Qny = sec.y > 0.5 ? N_m1_m2 : N_p2_p1;
    vec3 Qnz = sec.z > 0.5 ? N_p2_m1 : N_m1_p2, Qnw = sec.w > 0.5 ? N_p1_p2 : N_m2_m1;
    vec4 qRun = vec4(float(alike(Qx, Qnx)), float(alike(Qy, Qny)), float(alike(Qz, Qnz)), float(alike(Qw, Qnw)));
    // not where P and Q both run straight (a right-angle junction), where a straight P is a darker line
    // or E ends a straight line beside it (unless Q bends), or where a straight P meets a Q that neither
    // runs straight nor along the cut
    vec4 run = partner * (1.0 - straight * sQ) * (1.0 - straight * vec4(lessThan(lP, vec4(lE))) * (1.0 - bendQ))
             * (1.0 - endLine * straight * (1.0 - bendQ)) * (1.0 - straight * (1.0 - straightQ0) * (1.0 - qRun)) * cut;
    run *= 1.0 - loneP * loneQ;
    // E's diagonal runs up to a wall (only where the rest passes: up to 24 reads)
    if (dot(run, vec4(1.0)) > 0.0)
    {
      float wCG = run.x + run.z > 0.0 ? max(runWall(E, coord, vec2(1., -1.)), runWall(E, coord, vec2(-1., 1.))) : 0.0;
      float wAI = run.y + run.w > 0.0 ? max(runWall(E, coord, vec2(1., 1.)), runWall(E, coord, vec2(-1., -1.))) : 0.0;
      run *= vec4(wCG, wAI, wCG, wAI);
    }
    res = mix(res, before, run);
    kept = run;
    }
  }

  // ---- 5. Thin light stroke ----
  // a blocked corner comes back where E is a 1-pixel stroke lighter than both diagonal colors that runs
  // on along the diagonal of the cut (E's color in C or G for the / corners, A or I for the \ ones, not
  // on E's far side), like the white strokes of letters or a ring with gray antialiasing
  // only a changed corner where E is lighter than both colors, and not between two lone pixels (like an eye)
  // E's distance to the diagonal neighbors, read by rules 5 and 6 (set by the first of them that needs it)
  float eA = 0.0, eC = 0.0, eG = 0.0, eI = 0.0;
  bool haveDiagDist = false;
  vec4 back = vec4(greaterThan(vec4(lE) - max(lP, lQ), vec4(XBRZ_THIN_LIGHT))) * cut * vec4(notEqual(res, before)) * (1.0 - loneP * loneQ);
  if (dot(back, vec4(1.0)) > 0.0)
  {
    // E's color, or a tone closer to E than the corner's two colors (an antialiasing step), goes on along the diagonal
    vec4 dPQmin = min(mix(dEP, dEQ, sec), mix(dEQ, dEP, sec));
    eC = DistYCbCr(C, E), eG = DistYCbCr(E, G), eA = DistYCbCr(A, E), eI = DistYCbCr(E, I);
    haveDiagDist = true;
    // a diagonal neighbour counts only when the stroke really bends there: the cross neighbour beside it on E's far side
    // is not E's tone too (a peak on top of a straight line is not a diagonal stroke)
    vec4 tE = XBRZ_TONE * dPQmin;
    bvec4 aD = bvec4(alike(C, E), alike(E, G), alike(A, E), alike(E, I));
    bvec4 nD = bvec4(aD.x || eC < tE.x, aD.y || eG < tE.x, aD.z || eA < tE.y, aD.w || eI < tE.y);
    bvec4 nD2 = bvec4(aD.x || eC < tE.z, aD.y || eG < tE.z, aD.z || eA < tE.w, aD.w || eI < tE.w);
    // x: C beside F, G beside H; y: A beside D, I beside H; z: C beside B, G beside D; w: A beside B, I beside F
    vec4 sideA = vec4(float(aD.x && !(dEF < tE.x)) + float(aD.y && !(dEH < tE.x)), float(aD.z && !(dED < tE.y)) + float(aD.w && !(dEH < tE.y)),
                      float(aD.x && !(dEB < tE.z)) + float(aD.y && !(dED < tE.z)), float(aD.z && !(dEB < tE.w)) + float(aD.w && !(dEF < tE.w)));
    vec4 sideN = vec4(float(nD.x && !(dEF < tE.x)) + float(nD.y && !(dEH < tE.x)), float(nD.z && !(dED < tE.y)) + float(nD.w && !(dEH < tE.y)),
                      float(nD2.x && !(dEB < tE.z)) + float(nD2.y && !(dED < tE.z)), float(nD2.z && !(dEB < tE.w)) + float(nD2.w && !(dEF < tE.w)));
    sideA = min(sideA, vec4(1.0)); sideN = min(sideN, vec4(1.0));
    vec4 farOff = vec4(float(!alike(E, I)), float(!alike(E, G)), float(!alike(A, E)), float(!alike(C, E)));
    vec4 along = sideA * farOff;
    along = max(along, sideA * vec4(lessThan(max(lP, lQ), vec4(XBRZ_THIN_DARK))));
    along = max(along, sideN * farOff);
    back *= along;
    res = mix(res, before, back);
    kept = max(kept, back);
  }

  // ---- 6. Antialiasing notch ----
  // a corner blocked on an antialiasing ramp comes back where P is a single antialiasing pixel between E
  // and Q (the ramp runs E, P, Q and the diagonal is within XBRZ_DIAG + XBRZ_NOTCH), Q's tone wraps around P in
  // the outer corner (A, C, I, G) and E's tone runs on along the cut (C or G for the / corners, A or I
  // for the \ ones), like the shaded edges of a cape
  if (any(notEqual(res, before)))
  {
    vec4 dPc = mix(dEP, dEQ, sec), dQc = mix(dEQ, dEP, sec);
    vec4 notch = vec4(lessThanEqual((dPc + pair) / max(dQc, vec4(1e-5)), vec4(XBRZ_RAMP))) * vec4(lessThanEqual(pair * 255.0, vec4(XBRZ_DIAG + XBRZ_NOTCH)))
               * loneP * cut * vec4(notEqual(res, before));
    // the color tests only where a notch can come back
    if (dot(notch, vec4(1.0)) > 0.0)
    {
      vec4 wrap = vec4(lessThan(vec4(DistYCbCr(A, Qx), DistYCbCr(C, Qy), DistYCbCr(I, Qz), DistYCbCr(G, Qw)), XBRZ_TONE * pair));
      // E's tone in a diagonal neighbour X: closer to E than to P and Q by XBRZ_TONE
      if (!haveDiagDist)
      {
        eC = DistYCbCr(C, E), eG = DistYCbCr(E, G), eA = DistYCbCr(A, E), eI = DistYCbCr(E, I);
      }
      vec4 onC = vec4(lessThan(vec4(eC), XBRZ_TONE * min(vec4(DistYCbCr(Px, C), DistYCbCr(Py, C), DistYCbCr(Pz, C), DistYCbCr(Pw, C)),
                                                   vec4(DistYCbCr(Qx, C), DistYCbCr(Qy, C), DistYCbCr(Qz, C), DistYCbCr(Qw, C)))));
      vec4 onG = vec4(lessThan(vec4(eG), XBRZ_TONE * min(vec4(DistYCbCr(Px, G), DistYCbCr(Py, G), DistYCbCr(Pz, G), DistYCbCr(Pw, G)),
                                                   vec4(DistYCbCr(Qx, G), DistYCbCr(Qy, G), DistYCbCr(Qz, G), DistYCbCr(Qw, G)))));
      vec4 onA = vec4(lessThan(vec4(eA), XBRZ_TONE * min(vec4(DistYCbCr(Px, A), DistYCbCr(Py, A), DistYCbCr(Pz, A), DistYCbCr(Pw, A)),
                                                   vec4(DistYCbCr(Qx, A), DistYCbCr(Qy, A), DistYCbCr(Qz, A), DistYCbCr(Qw, A)))));
      vec4 onI = vec4(lessThan(vec4(eI), XBRZ_TONE * min(vec4(DistYCbCr(Px, I), DistYCbCr(Py, I), DistYCbCr(Pz, I), DistYCbCr(Pw, I)),
                                                   vec4(DistYCbCr(Qx, I), DistYCbCr(Qy, I), DistYCbCr(Qz, I), DistYCbCr(Qw, I)))));
      vec4 along = vec4(max(onC.x, onG.x), max(onA.y, onI.y), max(onC.z, onG.z), max(onA.w, onI.w));
      notch *= wrap * along;
      res = mix(res, before, notch);
      kept = max(kept, notch);
    }
  }

  // ---- 7. Stripe ends ----
  // E ends a 1-pixel horizontal line (left or right end) or vertical line (top or bottom end); a corner
  // brought back by rules 4 to 6 is left as it is
  bool eB = eq(E, B), eD = eq(E, D), eF = eq(E, F), eH = eq(E, H);
  // the stripes on both sides differ from each other too, so outlines (same color on both sides) are left alone;
  // E's stripe may also be 2 pixels wide (E's color on one side and not 2 pixels away)
  vec3 fB = eB ? N_p0_m2 : N_p0_p2, fD = eD ? N_m2_p0 : N_p2_p0;
  bool thinH = !eq(B, H) && ((!eB && !eH) || (eB != eH && !eq(fB, E)));
  bool thinV = !eq(D, F) && ((!eD && !eF) || (eD != eF && !eq(fD, E)));
  // only where a corner that is still cut, and not brought back by rules 4 to 6, could be squared
  vec4 open4 = vec4(greaterThan(BLEND(res), vec4(0.0))) * vec4(greaterThan(pair * 255.0, vec4(XBRZ_TIP))) * (1.0 - kept);
  if ((thinH || thinV) && dot(open4, vec4(1.0)) > 0.0)
  {
    // the stripes only need to keep a similar color (within 20/255) along their length, so a background
    // with a slight gradient still counts as one stripe
    bool nB = alike(B, E), nD = alike(D, E), nF = alike(E, F), nH = alike(E, H);
    // only inside a stack of parallel stripes: the rows (or columns) on both sides run along the line too
    // and they all end flush at the same column (or row), like the stripes of a gauge
    float endL = float(stripeEnd(coord, vec2(-2., -2.), vec2(-2., 2.), vec2(3., 0.), thinH, E, A, B, C, D, F, G, H, I, N_m2_p0, N_p2_p0, N_p2_m1, N_p2_p1));
    float endR = float(stripeEnd(coord, vec2(2., -2.), vec2(2., 2.), vec2(-3., 0.), thinH, E, C, B, A, F, D, I, H, G, N_p2_p0, N_m2_p0, N_m2_m1, N_m2_p1));
    float endT = float(stripeEnd(coord, vec2(-2., -2.), vec2(2., -2.), vec2(0., 3.), thinV, E, A, D, G, B, H, C, F, I, N_p0_m2, N_p0_p2, N_m1_p2, N_p1_p2));
    float endB = float(stripeEnd(coord, vec2(-2., 2.), vec2(2., 2.), vec2(0., -3.), thinV, E, G, D, A, H, B, I, F, C, N_p0_p2, N_p0_m2, N_m1_m2, N_p1_m2));
    if (endL + endR + endT + endB > 0.0)
    {
      vec4 tip = vec4(max(endL, endT), max(endR, endT), max(endR, endB), max(endL, endB));
      tip *= vec4(greaterThan(pair * 255.0, vec4(XBRZ_TIP)));
      // E's stripe is not a stripe of its own where a side stripe is a close tone of it (an inner tone of a shaded
      // area): there a corner that xBRZ cuts with a line between two outline colors darker than E is not a stripe
      // end, so the outline goes on as a diagonal (the forehead under Gohan's hair in Buu's Fury)
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
// when one corner is a cut line and the opposite corner is a line that rule 1 squared or left weak,
// and E lies between their two blend colors on a strong edge, the opposite corner goes back to its
// xBRZ decision, so a line through an antialiasing pixel cuts both halves of it, as in xBRZ
// 1.0 when s is a third color next to the wedge's color p and E: XBRZ_MINC or more from both and on no
// ramp with them (neither p nor E lies between the other two, within XBRZ_AA_OFF)
float thirdColor(vec3 s, vec3 p, vec3 E)
{
  float dsp = DistYCbCr(s, p), dsE = DistYCbCr(s, E), dpE = DistYCbCr(p, E);
  return float(min(dsp, dsE) * 255.0 >= XBRZ_MINC && dpE + dsp > XBRZ_AA_OFF * dsE && dpE + dsE > XBRZ_AA_OFF * dsp);
}
vec4 lineThroughAA(vec4 res, vec4 xbrz, vec4 contrast, vec3 B, vec3 D, vec3 E, vec3 F, vec3 H)
{
  if (XBRZ_MINC <= 0.0)
    return res;
  vec4 cut = vec4(greaterThan(BLEND(res), vec4(0.0))) * vec4(lessThan(BLEND(res), vec4(3.0))) * FLAG(res, 4.0);
  vec4 sq = vec4(lessThan(contrast, vec4(XBRZ_MINC))) * vec4(greaterThan(BLEND(xbrz), vec4(0.0))) * FLAG(xbrz, 4.0)
          * vec4(notEqual(BLEND(res), vec4(1.0))) * vec4(notEqual(BLEND(res), vec4(2.0)));
  vec4 pair = sq * cut.zwxy;
  if (dot(pair, vec4(1.0)) <= 0.0)
    return res;
  // the blend colors of the four corners
  vec4 sc = FLAG(xbrz, 8.0);
  vec3 Cx = sc.x > 0.5 ? B : D, Cy = sc.y > 0.5 ? F : B, Cz = sc.z > 0.5 ? H : F, Cw = sc.w > 0.5 ? D : H;
  float dXZ = DistYCbCr(Cx, Cz), dYW = DistYCbCr(Cy, Cw);
  // a 2:1 wedge is not brought back where it would lie against a third color: the neighbor along
  // whose side the wedge runs (the corner's first neighbor for a steep line, the second for a shallow
  // one) must be within XBRZ_MINC of the wedge's color or of E
  vec4 st8 = FLAG(xbrz, 64.0), sh8 = FLAG(xbrz, 16.0);
  vec4 third8 = st8 * vec4(thirdColor(D, Cx, E), thirdColor(B, Cy, E), thirdColor(F, Cz, E), thirdColor(H, Cw, E))
              + sh8 * vec4(thirdColor(B, Cx, E), thirdColor(F, Cy, E), thirdColor(H, Cz, E), thirdColor(D, Cw, E));
  pair *= 1.0 - min(third8, vec4(1.0));
  float bxz = float(DistYCbCr(Cx, E) + DistYCbCr(E, Cz) <= XBRZ_AA_LINE * dXZ && dXZ * 255.0 >= XBRZ_AA_EDGE);
  float byw = float(DistYCbCr(Cy, E) + DistYCbCr(E, Cw) <= XBRZ_AA_LINE * dYW && dYW * 255.0 >= XBRZ_AA_EDGE);
  return mix(res, xbrz, pair * vec4(bxz, byw, bxz, byw));
}

// ============================================================================================
// 10. Pixel closed between outlines
// ============================================================================================
// the blend color P is a pixel closed in a straight row (or column) between two pixels of a dark
// outline color Q, and Q also takes the corner's other neighbour, in an L around P: a line test that
// reads Q on both sides of P as one line would pull P toward E, so the corner stays square
vec4 closedPixel(vec4 res, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  // only where xBRZ found a shallow or steep line
  vec4 line = min(FLAG(res, 16.0) + FLAG(res, 64.0), 1.0) * vec4(greaterThan(BLEND(res), vec4(0.0)));
  if (XBRZ_DIAG <= 0.0 || dot(line, vec4(1.0)) <= 0.0)
    return res;
  vec4 sc = FLAG(res, 8.0);
  // Q (A, C, I, G for the corners x, y, z, w) is an outline close to black, darker than both E and P
  vec3 Px = sc.x > 0.5 ? B : D, Py = sc.y > 0.5 ? F : B, Pz = sc.z > 0.5 ? H : F, Pw = sc.w > 0.5 ? D : H;
  vec4 lQ = vec4(dot(A, lumaW), dot(C, lumaW), dot(I, lumaW), dot(G, lumaW));
  vec4 lP = vec4(dot(Px, lumaW), dot(Py, lumaW), dot(Pz, lumaW), dot(Pw, lumaW));
  vec4 dark = vec4(lessThan(lQ + XBRZ_BLACK_GAP, lP)) * vec4(lessThan(lQ + XBRZ_BLACK_GAP, vec4(dot(E, lumaW)))) * vec4(lessThan(lQ, vec4(XBRZ_BLACK)));
  vec4 closed = dark * line;
  if (dot(closed, vec4(1.0)) <= 0.0)
    return res;
  // P is closed in a row between two pixels of Q's color, which also takes the corner's other neighbour
  bool sx = sc.x > 0.5 ? (alike(A, C) && alike(A, D) && !alike(A, B) && !alike(A, E)) : (alike(A, G) && alike(A, B) && !alike(A, D) && !alike(A, E));
  bool sy = sc.y > 0.5 ? (alike(C, I) && alike(B, C) && !alike(C, F) && !alike(C, E)) : (alike(A, C) && alike(C, F) && !alike(B, C) && !alike(C, E));
  bool sz = sc.z > 0.5 ? (alike(G, I) && alike(F, I) && !alike(H, I) && !alike(E, I)) : (alike(C, I) && alike(H, I) && !alike(F, I) && !alike(E, I));
  bool sw = sc.w > 0.5 ? (alike(A, G) && alike(G, H) && !alike(D, G) && !alike(E, G)) : (alike(G, I) && alike(D, G) && !alike(G, H) && !alike(E, G));
  closed *= vec4(sx, sy, sz, sw);
  return res * (1.0 - closed);
}

// ============================================================================================
// 11. Lines in a larger window
// ============================================================================================
// a corner that rule 1 squared is cut as in xBRZ where it lies on a straight boundary between two
// stripes, along the slope xBRZ found for it (45 degrees, or a 2:1 shallow or steep line), read in a
// 7x7 window: E's tone runs on along the boundary on E's side and the corner's two colors run on along
// it on the other side, with every step of a 2:1 line exactly 2 pixels long; E's far side does not
// have the other tone (not a checkerboard); and one of the two stripes is 1 pixel wide with a strong
// contour past it (at least XBRZ_STRONG), so it is a line or the antialiasing band of one, not a band
// of shading or a texture
// X has a's tone against b: closer to a than to b, and alike a
float onTone(vec3 X, vec3 a, vec3 b)
{
  float da = DistYCbCr(X, a);
  return float(da < DistYCbCr(X, b) && da * 255.0 <= XBRZ_ALIKE);
}
// X is past a stripe of tone a (next to tone b) on a strong contour: neither tone, and XBRZ_STRONG from a
float strongPx(vec3 X, vec3 a, vec3 b)
{
  return (1.0 - onTone(X, a, b)) * (1.0 - onTone(X, b, a)) * float(DistYCbCr(X, a) * 255.0 >= XBRZ_STRONG);
}
// the pixel at offset o in the corner's own frame (canonical corner: bottom-right, colors F and H)
#define RP(o) P((rot * (o)).x, (rot * (o)).y)

// one corner, in its own frame: shape 0 is a 45-degree boundary, 1 shallow (2:1), 2 steep (1:2)
float stripeLine(vec2 coord, mat2 rot, vec3 E, vec3 Pc, float shape)
{
  // offsets: e1..e4 run on E's side, p1..p5 on the other side (with F and H; p4 and p5 close the steps at
  // both ends, so each step of a 2:1 line is exactly 2 pixels long), f1 f2 are E's far side,
  // o1 o2 o3 the pixels past the other stripe
  vec2 e1, e2, e3, e4, p1, p2, p3, p4, p5, f1, f2, o1, o2, o3;
  if (shape < 0.5)
  {
    e1 = vec2(1., -1.); e2 = vec2(-1., 1.); e3 = vec2(2., -2.); e4 = vec2(-2., 2.);
    p1 = vec2(2., -1.); p2 = vec2(-1., 2.); p3 = p1; p4 = vec2(3., -2.); p5 = vec2(-2., 3.);
    f1 = vec2(0., -1.); f2 = vec2(-1., 0.);
    o1 = vec2(1., 1.); o2 = vec2(2., 0.); o3 = vec2(0., 2.);
  }
  else if (shape < 1.5)
  {
    // E's run is the 2-pixel step D E, then C and the pixel right of it, and the one below-left of D
    e1 = vec2(-1., 0.); e2 = vec2(1., -1.); e3 = vec2(2., -1.); e4 = vec2(-2., 1.);
    p1 = vec2(-1., 1.); p2 = vec2(2., 0.); p3 = vec2(-2., 2.); p4 = vec2(3., -1.); p5 = vec2(-3., 2.);
    f1 = vec2(0., -1.); f2 = vec2(-1., -1.);
    o1 = vec2(1., 1.); o2 = vec2(0., 2.); o3 = vec2(2., 1.);
  }
  else
  {
    e1 = vec2(0., -1.); e2 = vec2(-1., 1.); e3 = vec2(-1., 2.); e4 = vec2(1., -2.);
    p1 = vec2(1., -1.); p2 = vec2(0., 2.); p3 = vec2(2., -2.); p4 = vec2(-1., 3.); p5 = vec2(2., -3.);
    f1 = vec2(-1., 0.); f2 = vec2(-1., -1.);
    o1 = vec2(1., 1.); o2 = vec2(2., 0.); o3 = vec2(1., 2.);
  }
  // a strong contour on one side first (cheap: three reads), since textures seldom have one
  vec3 Fa = RP(f1), Fb = RP(f2), O1 = RP(o1);
  float eStrong = float(min(DistYCbCr(Fa, E), DistYCbCr(Fb, E)) * 255.0 >= XBRZ_STRONG);
  float pStrong = float(DistYCbCr(O1, Pc) * 255.0 >= XBRZ_STRONG);
  if (eStrong + pStrong <= 0.0)
    return 0.0;
  // then the two runs, nearest pixels first
  if (onTone(RP(e1), E, Pc) * onTone(RP(e2), E, Pc) <= 0.0)
    return 0.0;
  float runs = onTone(RP(e3), E, Pc) * onTone(RP(e4), E, Pc)
             * onTone(RP(p1), Pc, E) * onTone(RP(p2), Pc, E) * onTone(RP(p3), Pc, E)
             * onTone(RP(p4), Pc, E) * onTone(RP(p5), Pc, E)
             * (1.0 - onTone(Fa, Pc, E)) * (1.0 - onTone(Fb, Pc, E));
  if (runs <= 0.0)
    return 0.0;
  float eNarrow = eStrong * strongPx(Fa, E, Pc) * strongPx(Fb, E, Pc);
  float pNarrow = pStrong * strongPx(O1, Pc, E) * (1.0 - onTone(RP(o2), Pc, E)) * (1.0 - onTone(RP(o3), Pc, E));
  return max(eNarrow, pNarrow);
}

// the pixel at offset o (components -1, 0 or 1) of the 3x3
vec3 at3x3(vec2 o, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  if (o.y < -0.5)
    return o.x < -0.5 ? A : (o.x > 0.5 ? C : B);
  if (o.y > 0.5)
    return o.x < -0.5 ? G : (o.x > 0.5 ? I : H);
  return o.x < -0.5 ? D : (o.x > 0.5 ? F : E);
}

vec4 diagonalStripes(vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                     float dEB, float dED, float dEF, float dEH, vec4 xb, vec4 sq)
{
  // the slope xBRZ found for each corner (+16 shallow, +64 steep, in the corner's own frame)
  vec4 shape = FLAG(xb, 4.0) * (FLAG(xb, 16.0) + 2.0 * FLAG(xb, 64.0));
  // P the closer candidate of each corner, Q the other one; Q must have P's tone (one stripe)
  vec3 Px = dED <= dEB + TIE_EPS ? D : B, Qx = dED <= dEB + TIE_EPS ? B : D;
  vec3 Py = dEB <= dEF + TIE_EPS ? B : F, Qy = dEB <= dEF + TIE_EPS ? F : B;
  vec3 Pz = dEF <= dEH + TIE_EPS ? F : H, Qz = dEF <= dEH + TIE_EPS ? H : F;
  vec3 Pw = dEH <= dED + TIE_EPS ? H : D, Qw = dEH <= dED + TIE_EPS ? D : H;
  sq *= vec4(lessThan(shape, vec4(2.5))) * vec4(onTone(Qx, Px, E), onTone(Qy, Py, E), onTone(Qz, Pz, E), onTone(Qw, Pw, E));
  // one corner at a time, so the test is compiled once (corner z is the canonical frame, the others turned)
  vec4 r = vec4(0.0);
  // first the cheap strong-contour test of stripeLine, read from the 3x3, so the loop below only runs the
  // long test on the corners that pass it
  for (int k = 0; k < 4; k++)
  {
    vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
    if (dot(sq, m) > 0.0)
    {
      mat2 rot = k == 0 ? mat2(-1., 0., 0., -1.) : (k == 1 ? mat2(0., -1., 1., 0.) : (k == 2 ? mat2(1., 0., 0., 1.) : mat2(0., 1., -1., 0.)));
      vec3 Pc = k == 0 ? Px : (k == 1 ? Py : (k == 2 ? Pz : Pw));
      float sh = dot(shape, m);
      // the same f1, f2 and o1 as in stripeLine
      vec3 Fa = at3x3(rot * (sh > 1.5 ? vec2(-1., 0.) : vec2(0., -1.)), A, B, C, D, E, F, G, H, I);
      vec3 Fb = at3x3(rot * (sh < 0.5 ? vec2(-1., 0.) : vec2(-1., -1.)), A, B, C, D, E, F, G, H, I);
      vec3 O1 = at3x3(rot * vec2(1., 1.), A, B, C, D, E, F, G, H, I);
      float strong = float(min(DistYCbCr(Fa, E), DistYCbCr(Fb, E)) * 255.0 >= XBRZ_STRONG)
                   + float(DistYCbCr(O1, Pc) * 255.0 >= XBRZ_STRONG);
      sq *= 1.0 - m * float(strong <= 0.0);
    }
  }
  for (int k = 0; k < 4; k++)
  {
    vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
    if (dot(sq, m) > 0.0)
    {
      mat2 rot = k == 0 ? mat2(-1., 0., 0., -1.) : (k == 1 ? mat2(0., -1., 1., 0.) : (k == 2 ? mat2(1., 0., 0., 1.) : mat2(0., 1., -1., 0.)));
      vec3 Pc = k == 0 ? Px : (k == 1 ? Py : (k == 2 ? Pz : Pw));
      r += m * stripeLine(coord, rot, E, Pc, dot(shape, m));
    }
  }
  return r;
}

// rule 11: a corner that rule 1 squared comes back where it lies on a straight line (diagonalStripes);
// a corner that comes back is no longer weak
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
// 12. Closed shadow
// ============================================================================================
// E (background) sits in the notch where a near-black shadow blob runs under another object O (like
// feet over a round shadow): S = P(s) is the shadow's arm beside E, O = P(o) the object, K = P(o - s)
// the shadow on O's other side. The shape is read from a bigger window: the arm runs straight 3
// pixels with background outside it and the object over it, and beyond K the shadow is a solid 2x2
// lobe (a blob, not a 1-pixel stroke like a serif)
bool floorPx(vec3 X, vec3 S, vec3 O, float lS)
{
  return dot(X, lumaW) > lS + XBRZ_SHADOW_FLOOR && !alike(X, S) && !alike(X, O);
}

float shadowClose(vec2 coord, vec3 E, vec2 s, vec2 o)
{
  vec3 S = P(s.x, s.y);
  vec3 O = P(o.x, o.y);
  vec2 k = o - s;
  vec3 K = P(k.x, k.y);
  float lS = dot(S, lumaW);
  if (!(lS < XBRZ_SHADOW && dot(K, lumaW) < XBRZ_SHADOW && dot(E, lumaW) > XBRZ_SHADOW + XBRZ_SHADOW_FLOOR && alike(S, K) && !alike(O, S) && !alike(O, E) && !alike(E, S)
        && lS + XBRZ_SHADOW_FLOOR < dot(E, lumaW) && lS + XBRZ_SHADOW_FLOOR < dot(O, lumaW)))
    return 0.0;
  // the floor around the notch is any pixel lighter than the shadow that is neither the shadow nor the
  // object, so a textured floor (grass, tiles) counts the same as a flat one
  bool bg = floorPx(P(-s.x, -s.y), S, O, lS) && floorPx(P(-o.x, -o.y), S, O, lS);
  bool arm = alike(S, P(2. * s.x, 2. * s.y)) && alike(S, P(3. * s.x, 3. * s.y))
          && floorPx(P(s.x - o.x, s.y - o.y), S, O, lS) && floorPx(P(2. * s.x - o.x, 2. * s.y - o.y), S, O, lS)
          && !alike(S, P(s.x + o.x, s.y + o.y));
  bool lobe = alike(S, P(k.x + o.x, k.y + o.y)) && alike(S, P(k.x + o.x - s.x, k.y + o.y - s.y))
           && alike(S, P(k.x + 2. * o.x, k.y + 2. * o.y)) && alike(S, P(k.x + 2. * o.x - s.x, k.y + 2. * o.y - s.y));
  vec3 O2 = P(2. * o.x, 2. * o.y);
  bool obj = !alike(E, O2) && !alike(S, O2);
  return float(bg && arm && lobe && obj);
}

// the notch's corner and, on the shadow's side, the corners next to the notch
vec4 closedShadow(vec4 res, vec2 coord, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I)
{
  if (!CRISP_RULES)
    return res;
  float lE = dot(E, lumaW);
  // cheap gates on the 3x3 before the 7x7 tests (cross order B D F H, diagonal order A C G I):
  // dS shadow, dA close to a shadow color, nd not a shadow, bg close to a background lighter than the shadow
  vec4 lX = vec4(dot(B, lumaW), dot(D, lumaW), dot(F, lumaW), dot(H, lumaW));
  vec4 lY = vec4(dot(A, lumaW), dot(C, lumaW), dot(G, lumaW), dot(I, lumaW));
  bvec4 dS = lessThan(lX, vec4(XBRZ_SHADOW)), dSd = lessThan(lY, vec4(XBRZ_SHADOW));
  bvec4 dA = lessThan(lX, vec4(XBRZ_SHADOW + XBRZ_SHADOW_NEAR)), dAd = lessThan(lY, vec4(XBRZ_SHADOW + XBRZ_SHADOW_NEAR));
  bvec4 nd = not(dS), ndd = not(dSd);
  bvec4 bg = greaterThan(lX, vec4(XBRZ_SHADOW + XBRZ_SHADOW_BG)), bgd = greaterThan(lY, vec4(XBRZ_SHADOW + XBRZ_SHADOW_BG));
  bvec4 lt = greaterThan(lX, vec4(XBRZ_SHADOW + XBRZ_SHADOW_FLOOR)), ltd = greaterThan(lY, vec4(XBRZ_SHADOW + XBRZ_SHADOW_FLOOR));
  // corner k (x, y, z, w) lies between the directions d = L, U, R, Dn and n = d turned 90 degrees (U, R, Dn, L);
  // the loops run one 7x7 test at a time, so the test is compiled once
  if (lE > XBRZ_SHADOW + XBRZ_SHADOW_FLOOR && any(dS))
  {
    // E is the notch: S = P(s) and K = P(o - s) shadow, O = P(o) not, background at -s, -o and s - o;
    // first candidate (s, o) = (d, n), second (n, d)
    vec4 g1 = vec4(dS.y && dSd.y && nd.x && bg.z && bg.w && bgd.z, dS.x && dSd.w && nd.z && bg.w && bg.y && bgd.x,
                   dS.z && dSd.z && nd.w && bg.y && bg.x && bgd.y, dS.w && dSd.x && nd.y && bg.x && bg.z && bgd.w);
    vec4 g2 = vec4(dS.x && dSd.z && nd.y && bg.w && bg.z && bgd.y, dS.z && dSd.x && nd.x && bg.y && bg.w && bgd.w,
                   dS.w && dSd.y && nd.z && bg.x && bg.y && bgd.z, dS.y && dSd.w && nd.w && bg.z && bg.x && bgd.x);
    vec4 c1 = vec4(0.0), c2 = vec4(0.0);
    vec2 d = vec2(-1., 0.);
    for (int i = 0; i < 8; i++)
    {
      int k = i / 2;
      bool second = i - 2 * k == 1;
      vec2 n = vec2(-d.y, d.x);
      vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
      if (dot(second ? g2 : g1, m) > 0.0)
      {
        float r = shadowClose(coord, E, second ? n : d, second ? d : n);
        if (second) c2 += m * r; else c1 += m * r;
      }
      if (second) d = n;
    }
    // first candidate as S: x/z with a horizontal arm and y/w with a vertical one take +16; second (+8): +64
    c2 *= 1.0 - c1;
    res = mix(res, vec4(1. + 4. + 16.), c1);
    res = mix(res, vec4(1. + 4. + 8. + 64.), c2);
  }
  else if (lE < XBRZ_SHADOW && (any(lt) || any(ltd)))
  {
    // E is the shadow next to a notch Y: the arm's tip (Y = E + d, O = Y + o diagonal to E) or the lobe's
    // corner (Y = E + s - o diagonal to E, O = E + s); E's corner toward the notch stays square.
    // Candidates for corner k, as (Y, s, o): (d, -d, n), (n, -n, d), (d + n, d, -n), (d + n, n, -d)
    vec4 gT1 = vec4(lt.y && bg.w && bgd.w && dA.z && ndd.x, lt.x && bg.y && bgd.z && dA.w && ndd.y,
                    lt.z && bg.x && bgd.x && dA.y && ndd.w, lt.w && bg.z && bgd.y && dA.x && ndd.z);
    vec4 gT2 = vec4(lt.x && bg.z && bgd.w && dA.w && ndd.x, lt.z && bg.w && bgd.z && dA.y && ndd.y,
                    lt.w && bg.y && bgd.x && dA.x && ndd.w, lt.y && bg.x && bgd.y && dA.z && ndd.z);
    vec4 gK1 = vec4(ltd.x && nd.y && bg.x && dA.w && dAd.w, ltd.y && nd.x && bg.z && dA.y && dAd.z,
                    ltd.w && nd.z && bg.w && dA.x && dAd.x, ltd.z && nd.w && bg.y && dA.z && dAd.y);
    vec4 gK2 = vec4(ltd.x && nd.x && bg.y && dA.z && dAd.w, ltd.y && nd.z && bg.x && dA.w && dAd.z,
                    ltd.w && nd.w && bg.z && dA.y && dAd.x, ltd.z && nd.y && bg.w && dA.x && dAd.y);
    vec4 keepSq = vec4(0.0);
    vec2 d = vec2(-1., 0.);
    for (int i = 0; i < 16; i++)
    {
      int k = i / 4;
      int t = i - 4 * k;
      vec2 n = vec2(-d.y, d.x);
      vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
      vec4 g = t == 0 ? gT1 : (t == 1 ? gT2 : (t == 2 ? gK1 : gK2));
      if (dot(g, m) > 0.0)
      {
        vec2 y = t == 0 ? d : (t == 1 ? n : d + n);
        vec2 s = t == 0 ? -d : (t == 1 ? -n : (t == 2 ? d : n));
        vec2 o = t == 0 ? n : (t == 1 ? d : (t == 2 ? -n : -d));
        keepSq = max(keepSq, m * shadowClose(coord + SRC_SIZE.zw * y, P(y.x, y.y), s, o));
      }
      if (t == 3) d = n;
    }
    res *= 1.0 - min(keepSq, vec4(1.0));
  }
  return res;
}

// ============================================================================================
// 13. Tiles between walls
// ============================================================================================
// E and its neighbour P = E + a are two square tiles of a row of tiles 1 pixel wide (4 tiles or more,
// in a repeating pattern, all lighter or all darker than the walls) that runs between two straight
// walls (Q's side w and the opposite side, 3 pixels or more each): a blocked corner between two tiles
// stays square, so the second pass does not chain a diagonal through the row (Castlevania's gauge)
float tileStripe(vec2 coord, vec3 E, vec2 a, vec2 w)
{
  vec3 P1 = P(a.x, a.y), Q = P(w.x, w.y), Q2 = P(w.x + a.x, w.y + a.y), O = P(-w.x, -w.y), O2 = P(a.x - w.x, a.y - w.y);
  vec3 T0 = P(-a.x, -a.y);
  // first what the 3x3 shows: both walls along E and P, E and P tiles, the pixel before E another tile
  float lE = dot(E, lumaW), lP = dot(P1, lumaW), lQ = dot(Q, lumaW), lO = dot(O, lumaW);
  bool light = min(lE, lP) > max(lQ, lO) + XBRZ_OUTLINE, dark = max(lE, lP) + XBRZ_OUTLINE < min(lQ, lO);
  if (!((light || dark) && alike(Q, Q2) && alike(O, O2) && !alike(E, T0) && !alike(T0, Q) && !alike(T0, O)))
    return 0.0;
  // then the row past P: the walls run on (3 pixels) and the next tile follows the pattern
  vec3 T3 = P(2. * a.x, 2. * a.y);
  bool wallQ = alike(Q, P(w.x - a.x, w.y - a.y)) || alike(Q, P(w.x + 2. * a.x, w.y + 2. * a.y));
  bool wallO = alike(O, P(-w.x - a.x, -w.y - a.y)) || alike(O, P(2. * a.x - w.x, 2. * a.y - w.y));
  bool tiles = !alike(P1, T3) && !alike(T3, Q) && !alike(T3, O) && (alike(T0, P1) || alike(E, T3));
  return float(wallQ && wallO && tiles);
}

// a blocked corner between two tiles is dropped
vec4 tilesBetweenWalls(vec4 res, vec2 coord, vec3 E)
{
  if (!(CRISP_RULES && max(max(res.x, res.y), max(res.z, res.w)) >= 128.0))
    return res;
  vec4 blk = vec4(greaterThanEqual(res, vec4(128.0))) * vec4(greaterThan(BLEND(res), vec4(0.0)));
  vec4 sc = FLAG(mod(res, 128.0), 8.0);
  // corner k (x, y, z, w) lies between the directions d = L, U, R, Dn and n = d turned 90 degrees (U, R, Dn, L):
  // P = E + a is d's pixel, or n's with the second blend color, and Q's side w is the other one. The loop
  // runs one test at a time, so the test is compiled once
  vec4 tile = vec4(0.0);
  vec2 d = vec2(-1., 0.);
  for (int k = 0; k < 4; k++)
  {
    vec2 n = vec2(-d.y, d.x);
    vec4 m = vec4(equal(vec4(float(k)), vec4(0., 1., 2., 3.)));
    if (dot(blk, m) > 0.0)
    {
      bool second = dot(sc, m) > 0.5;
      tile += m * tileStripe(coord, E, second ? n : d, second ? d : n);
    }
    d = n;
  }
  res *= 1.0 - tile;
  return res;
}

// ============================================================================================
// 16 and 18. Line in another color
// ============================================================================================
// a corner that draws a line along a pair of one color but is painted with the other candidate (18: also
// where E is not lone, for a near-black outline); pair is the distance between the two candidates of each corner
vec4 lineInOtherColor(vec4 res, vec3 A, vec3 B, vec3 C, vec3 D, vec3 E, vec3 F, vec3 G, vec3 H, vec3 I,
                      vec4 pair, float dEB, float dED, float dEF, float dEH)
{
  if (XBRZ_MINC <= 0.0)
    return res;
  bool lone = !(eq(A, E) || eq(B, E) || eq(C, E) || eq(D, E) || eq(E, F) || eq(E, G) || eq(E, H) || eq(E, I));
  vec4 r = res;
  vec4 sh = FLAG(r, 16.0), st = FLAG(r, 64.0), sec = FLAG(r, 8.0);
  // a shallow line is drawn along the first candidate's color and a steep one along the second's; the
  // corner is painted with the other candidate, which differs from it by more than XBRZ_TINT
  vec4 tint = vec4(greaterThan(BLEND(r), vec4(0.0))) * FLAG(r, 4.0) *
              abs(sh - st) * (sh * sec + st * (1.0 - sec)) * vec4(greaterThan(pair * 255.0, vec4(XBRZ_TINT)));
  // no corner can change: skip the rest (tint is only multiplied from here)
  if (dot(tint, vec4(1.0)) <= 0.0)
    return res;
  // the two pixels that make the line have one color
  vec4 pSh = vec4(DistYCbCr(C, D), DistYCbCr(B, I), DistYCbCr(F, G), DistYCbCr(A, H));
  vec4 pSt = vec4(DistYCbCr(B, G), DistYCbCr(A, F), DistYCbCr(C, H), DistYCbCr(D, I));
  tint *= vec4(lessThan(sh * pSh + st * pSt, vec4(EQUAL_COLOR_TOLERANCE)));
  // E, the paint color P and the line's color L are not an antialiasing ramp
  vec4 dE1 = vec4(dED, dEB, dEF, dEH);
  vec4 dE2 = vec4(dEB, dEF, dEH, dED);
  vec4 dP = mix(dE1, dE2, sec), dL = mix(dE2, dE1, sec);
  tint *= vec4(greaterThan(dP + pair, XBRZ_TINT_RAMP * dL));
  // 16b. three stripes in a row: E's color goes on along the line on one side, the paint color on the other
  // (a band of 2:1 stripes): the line is drawn in its own color, lighter or not
  vec3 pX = st.x > 0.5 ? D : B, pY = st.y > 0.5 ? B : F, pZ = st.z > 0.5 ? F : H, pW = st.w > 0.5 ? H : D;
  vec4 eOn = vec4(min(DistYCbCr(E, st.x > 0.5 ? N_m1_p2 : N_p2_m1), DistYCbCr(E, st.x > 0.5 ? N_p1_m2 : N_m2_p1)),
                  min(DistYCbCr(E, st.y > 0.5 ? N_m2_m1 : N_p1_p2), DistYCbCr(E, st.y > 0.5 ? N_p2_p1 : N_m1_m2)),
                  min(DistYCbCr(E, st.z > 0.5 ? N_p1_m2 : N_m2_p1), DistYCbCr(E, st.z > 0.5 ? N_m1_p2 : N_p2_m1)),
                  min(DistYCbCr(E, st.w > 0.5 ? N_p2_p1 : N_m1_m2), DistYCbCr(E, st.w > 0.5 ? N_m2_m1 : N_p1_p2)));
  vec4 pOn = vec4(DistYCbCr(pX, st.x > 0.5 ? N_p0_m2 : N_m2_p0), DistYCbCr(pY, st.y > 0.5 ? N_p2_p0 : N_p0_m2),
                  DistYCbCr(pZ, st.z > 0.5 ? N_p0_p2 : N_p2_p0), DistYCbCr(pW, st.w > 0.5 ? N_m2_p0 : N_p0_p2));
  vec4 stripes = vec4(lessThan(eOn, vec4(EQUAL_COLOR_TOLERANCE))) * vec4(lessThan(pOn, vec4(EQUAL_COLOR_TOLERANCE)));
  stripes *= (DistYCbCr(D, F) < EQUAL_COLOR_TOLERANCE || DistYCbCr(B, H) < EQUAL_COLOR_TOLERANCE) ? 0.0 : 1.0;
  // a corner blocked by rule 2 takes part only in a band of stripes
  tint *= max(vec4(lessThan(r, vec4(128.0))), stripes);
  vec4 tint0 = tint;
  // a line darker than E is drawn in its own color; a lighter one, or any line through an E that sits in a
  // straight line of one color (its two opposite neighbors match), leaves the corner square
  vec4 lumC1 = vec4(dot(D, lumaW), dot(B, lumaW), dot(F, lumaW), dot(H, lumaW));
  vec4 lumC2 = vec4(dot(B, lumaW), dot(F, lumaW), dot(H, lumaW), dot(D, lumaW));
  vec4 lumLine = mix(lumC1, lumC2, st);
  bool straight = DistYCbCr(D, F) < EQUAL_COLOR_TOLERANCE || DistYCbCr(B, H) < EQUAL_COLOR_TOLERANCE;
  vec4 dark = vec4(lessThan(lumLine, vec4(dot(E, lumaW)))) * (straight ? 0.0 : 1.0);
  // 18. where E is not lone, only a near-black line (an outline) is drawn in its own color, keeping its
  // shallow or steep shape, and no corner is left square
  if (!lone)
  {
    dark *= vec4(lessThan(lumLine, vec4(XBRZ_TINT_DARK)));
    // (not where the paint color is near-black too: two dark shades meet, there is nothing to close)
    dark *= vec4(greaterThanEqual(mix(lumC2, lumC1, st), vec4(XBRZ_TINT_DARK)));
    tint *= dark;
  }
  dark = max(dark, stripes);
  tint = max(tint, tint0 * stripes);
  vec4 flip = st - sec;  // +1: paint the second candidate, -1: the first
  // a lone E's line is drawn at 45 degrees (16); an outline keeps its shape and only takes its own color (18)
  vec4 shape = lone ? 16.0 * sh + 64.0 * st + 32.0 * FLAG(r, 32.0) : vec4(0.0);
  res -= tint * dark * (shape - 8.0 * flip);
  res *= 1.0 - tint * (1.0 - dark);
  res -= 128.0 * vec4(greaterThanEqual(r, vec4(128.0))) * tint * dark;
  return res;
}


// ============================================================================================
// The corners of E, written once in one frame
// ============================================================================================
// The 5x5 window around E without its corners (A to I and the ring two steps away), with E's distances
// to B, F, H and D (dE) and the distances across the diagonals of the corners x, y, z and w (pair). Like
// xBRZ's rotations, each corner's code below is written once, for the bottom-right corner z (between E, F,
// H and I), and runs on the window turned so that the corner being decided is the bottom-right one. The
// four decisions of E (x, y, z, w) are turned with the window: in the turned frame, .z is the corner being
// decided and .y and .w the corners beside it, across the edges E-F and E-H.
struct Win
{
  vec3 A, B, C, D, E, F, G, H, I;
  vec3 m1_m2, p0_m2, p1_m2, m2_m1, p2_m1, m2_p0, p2_p0, m2_p1, p2_p1, m1_p2, p0_p2, p1_p2;
  vec4 dE, pair;
};
// a quarter turn: the bottom-right corner goes to the bottom-left one, which goes to the top-left one,
// and so on (the vec4s of the corners turn with .yzwx)
Win turn(Win o)
{
  return Win(o.C, o.F, o.I, o.B, o.E, o.H, o.A, o.D, o.G,
             o.p2_m1, o.p2_p0, o.p2_p1, o.p1_m2, o.p1_p2, o.p0_m2, o.p0_p2, o.m1_m2, o.m1_p2, o.m2_m1, o.m2_p0, o.m2_p1,
             o.dE.yzwx, o.pair.yzwx);
}

// xBRZ's shallow (x) and steep (y) line tests at the corner, for a corner xBRZ blends
vec2 cornerLines(Win n, int own)
{
  if (own < BLEND_NORMAL)
    return vec2(0.0);
  return lineTests(n.F, n.G, n.H, n.C, n.E, n.pair.z, eq(n.m1_p2, n.H) && !eq(n.G, n.H), eq(n.p2_m1, n.F) && !eq(n.C, n.F));
}
// the flags of a cut corner: +4 and its lines, unless the pixel at the far end of the line has E's color
// or the color of E's neighbor on that side
float cutFlags(Win n, vec2 line)
{
  float r = 4.0;
  if (neq(n.E, n.G) && neq(n.D, n.G)) r += line.x;
  if (neq(n.E, n.C) && neq(n.B, n.C)) r += line.y;
  return r;
}
// xBRZ's cut (cornerCut, with the blend types of the corner and of the two corners beside it)
float xbrzCorner(Win n, ivec4 b, vec2 line)
{
  return cornerCut(b.z, b.y, b.w, min(n.dE.y, n.dE.z), n.E, n.G, n.H, n.I, n.F, n.C) ? cutFlags(n, line) : 0.0;
}
// a corner without its line: only the small cut (and the second-color bit) are left
float noLine(float r) { return mod(r, 4.0) + 8.0 * mod(floor(r / 8.0), 2.0); }

// 33. Hole in a thick stroke: the inner corner of a thick stroke that bends, with an antialiasing pixel
// (a third color) at the outer corner, keeps only the small cut, without a line
float holeInStroke(Win n, float r)
{
  float ln = mod(floor(r / 4.0), 2.0) * mod(floor(r / 16.0), 2.0) * step(64.0, r);
  float dEB = n.dE.x, dEF = n.dE.y, dED = n.dE.w;
  if (ln > 0.5 && min(dEF, n.dE.z) * 255.0 >= 64.0 && eq(n.F,n.H) && eq(n.F,n.C) && eq(n.H,n.G) && neq(n.I,n.E) && neq(n.I,n.F)
      && (dEB * 255.0 < 30.0) && (dED * 255.0 < 30.0) && DistYCbCr(n.I,n.F) < dEF && DistYCbCr(n.I,n.E) < dEF
      && neq(n.I, n.p2_p1) && neq(n.I, n.p1_p2) && neq(n.F, n.p2_p1) && neq(n.F, n.p1_p2) && (eq(n.F, n.p2_p0) || eq(n.H, n.p0_p2)))
    return noLine(r);
  return r;
}

// 32. Lone pixel test redone: a corner cut without a line, blocked by a neighboring corner that the rules
// above left square, gets xBRZ's line (contrast 64 or more) where a stroke 1 pixel wide bends around it,
// and E's color, where it goes on, runs for 3 pixels or more
// 35. Edge of a thin band: along a band 1 pixel wide that runs on in a 2:1 line, with a strong color past
// it and close shades on E's side, the lone pixel test uses the reference tolerance (30) also at medium
// contrast (40 to 64), so the band's edge has no tooth
// (r: the four decisions after rule 33, b: xBRZ's blend types; returns what the corner gains)
float lonePixelRedone(Win n, vec4 r, ivec4 b, vec2 line)
{
  vec4 bl = mod(r, 4.0);
  float ln = mod(floor(r.z / 4.0), 2.0);
  float c4 = min(n.dE.y, n.dE.z) * 255.0;
  float dEB = n.dE.x, dED = n.dE.w;
  if ((bl.z > 0.0 && ln < 0.5 && !((eq(n.E,n.D) && !eq(n.E,n.m2_p0)) || (eq(n.E,n.B) && !eq(n.E,n.p0_m2))) && bl.y == 0.0 && bl.w == 0.0
       && c4 >= 64.0 && b.z == BLEND_NORMAL && eq(n.F,n.H) && eq(n.F,n.C) && eq(n.H,n.G) && neq(n.F, n.p2_p0) && neq(n.H, n.p0_p2)
       && cornerCut(b.z, BLEND_NONE, BLEND_NONE, min(n.dE.y, n.dE.z), n.E, n.G, n.H, n.I, n.F, n.C))
      || (bl.z == 1.0 && ln < 0.5 && c4 >= 40.0 && c4 < XBRZ_GUARD_EDGE && eq(n.F,n.H) && DistYCbCr(n.I,n.F) * 255.0 >= 40.0
       && ((eq(n.G,n.H) && eq(n.F,n.p2_p0) && (dED * 255.0 < 30.0) && near(n.E,n.C) && DistYCbCr(n.p0_p2,n.H) * 255.0 >= 40.0)
        || (eq(n.C,n.F) && eq(n.H,n.p0_p2) && (dEB * 255.0 < 30.0) && near(n.E,n.G) && DistYCbCr(n.p2_p0,n.F) * 255.0 >= 40.0))
       && cornerCut(b.z, b.y, b.w, 1.0, n.E, n.G, n.H, n.I, n.F, n.C)))
    return cutFlags(n, line);
  return 0.0;
}

// 34. Small square of close shades: in a 2x2 of close shades (not all exactly equal) closed on its 8 side
// neighbors by one color, the outer corner is only rounded, without a line, like the other three (here the
// 2x2 is A, B, D and E, and the outer corner is E's bottom-right one)
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

  vec3 B = P( 0.,-1.);
  vec3 D = P(-1., 0.);
  vec3 E = P( 0., 0.);
  vec3 F = P( 1., 0.);
  vec3 H = P( 0., 1.);
  // fast path: xBRZ blends a corner only where E differs from both pixels beside it, so where E equals a side
  // neighbour at every corner nothing is cut and only the second-color bits (+8) and rule 1 are left
  if ((eq(E,F) || eq(E,H)) && (eq(E,H) || eq(E,D)) && (eq(E,D) || eq(E,B)) && (eq(E,B) || eq(E,F)))
  {
    float fEB = DistYCbCr(B, E);
    float fED = DistYCbCr(D, E);
    float fEF = DistYCbCr(E, F);
    float fEH = DistYCbCr(E, H);
    vec4 fres = 8.0 * vec4(fED <= fEB + TIE_EPS ? 0.0 : 1.0, fEB <= fEF + TIE_EPS ? 0.0 : 1.0, fEF <= fEH + TIE_EPS ? 0.0 : 1.0, fEH <= fED + TIE_EPS ? 0.0 : 1.0);
    vec4 fcontrast, fweak;
    fres = minimumContrast(fres, fEB, fED, fEF, fEH, fcontrast, fweak);
    FRAG_OUT = fres / 255.0;
    return;
  }
  vec3 A = P(-1.,-1.);
  vec3 C = P( 1.,-1.);
  vec3 G = P(-1., 1.);
  vec3 I = P( 1., 1.);
  N_m1_m2 = P(-1., -2.);
  N_p0_m2 = P(0., -2.);
  N_p1_m2 = P(1., -2.);
  N_m2_m1 = P(-2., -1.);
  N_p2_m1 = P(2., -1.);
  N_m2_p0 = P(-2., 0.);
  N_p2_p0 = P(2., 0.);
  N_m2_p1 = P(-2., 1.);
  N_p2_p1 = P(2., 1.);
  N_m1_p2 = P(-1., 2.);
  N_p0_p2 = P(0., 2.);
  N_p1_p2 = P(1., 2.);

  // ============================================================================================
  // xBRZ: the reference decisions (only the line tests use DistShape and toneLine, rule 9)
  // ============================================================================================

  // blendResult Mapping: x|y|
  //                      w|z|
  // each corner as the point pass decided its point (the point at a pixel's bottom-right corner is in that
  // pixel's alpha, as f + 4 g + 16 j + 64 k): z is f of the point at E, w g of the point at D, y j of the
  // point at B and x k of the point at A
  vec4 pts = vec4(floor(PT(-1., -1.) / 64.0), mod(floor(PT(0., -1.) / 16.0), 4.0), mod(PT(0., 0.), 4.0), mod(floor(PT(-1., 0.) / 4.0), 4.0));
  // on the top row and the left column the points outside the image are not decided (beyond the edge the
  // image goes on as its edge pixels, so xBRZ blends nothing there)
  vec2 ip = floor(coord * SRC_SIZE.xy);
  pts *= vec4(min(ip.x, ip.y) > 0.5, ip.y > 0.5, 1.0, ip.x > 0.5);
  ivec4 blendResult = ivec4(pts);

  vec4 res = vec4(blendResult);

  // E's distance to each side neighbor (a corner's edge is the smaller of its two)
  float dEB = DistYCbCr(B, E);
  float dED = DistYCbCr(D, E);
  float dEF = DistYCbCr(E, F);
  float dEH = DistYCbCr(E, H);
  // the two colors on each corner's diagonal: top-left D-B, top-right B-F, bottom-right F-H, bottom-left H-D
  vec4 pair = vec4(DistYCbCr(B, D), DistYCbCr(B, F), DistYCbCr(F, H), DistYCbCr(D, H));

  // the window in the frame of each corner: as it is for z, then turned a quarter at a time
  Win wz = Win(A, B, C, D, E, F, G, H, I, N_m1_m2, N_p0_m2, N_p1_m2, N_m2_m1, N_p2_m1, N_m2_p0, N_p2_p0, N_m2_p1, N_p2_p1, N_m1_p2, N_p0_p2, N_p1_p2,
               vec4(dEB, dEF, dEH, dED), pair);
  Win ww = turn(wz);
  Win wx = turn(ww);
  Win wy = turn(wx);

  // xBRZ's cut and lines at each corner
  vec2 lineZ = cornerLines(wz, blendResult.z);
  vec2 lineW = cornerLines(ww, blendResult.w);
  vec2 lineX = cornerLines(wx, blendResult.x);
  vec2 lineY = cornerLines(wy, blendResult.y);
  res.z += xbrzCorner(wz, blendResult, lineZ);
  res.w += xbrzCorner(ww, blendResult.yzwx, lineW);
  res.x += xbrzCorner(wx, blendResult.zwxy, lineX);
  res.y += xbrzCorner(wy, blendResult.wxyz, lineY);

  // Decisions for the output pass, made once per input pixel instead of once per output pixel:
  // +8 when a corner blends with its second candidate colour (ties go to the first, as in xBRZ).
  vec4 second = vec4(dED <= dEB + TIE_EPS ? 0.0 : 1.0, dEB <= dEF + TIE_EPS ? 0.0 : 1.0, dEF <= dEH + TIE_EPS ? 0.0 : 1.0, dEH <= dED + TIE_EPS ? 0.0 : 1.0);
  res += 8.0 * second;

  // ============================================================================================
  // the rules, in order
  // ============================================================================================
  vec4 xbrz = res;
  vec4 contrast, weak;
  res = minimumContrast(res, dEB, dED, dEF, dEH, contrast, weak);              // 1
  vec4 band = diagonalBands(xbrz, coord, A, B, C, D, E, F, G, H, I);         // 30
  // 30b. only where xBRZ cuts a corner that rule 1 left square
  vec4 low30 = vec4(greaterThan(BLEND(xbrz), vec4(0.0))) * vec4(lessThan(contrast, vec4(XBRZ_MINC)));
  if (XBRZ_MINC > 0.0 && dot(low30, vec4(1.0)) > 0.0)
    band = max(band, low30 * max(vec4(ringBand(B, D, A, E), ringBand(B, F, C, E), ringBand(F, H, I, E), ringBand(H, D, G, E)),
                                 vec4(ringOutBand(E, C, G, I, B, D), ringOutBand(E, A, I, G, B, F), ringOutBand(E, C, G, A, F, H), ringOutBand(E, A, I, C, H, D))));
  res = mix(res, xbrz, band);
  weak *= 1.0 - band;
  res = largerWindowLines(res, coord, A, B, C, D, E, F, G, H, I, dEB, dED, dEF, dEH, xbrz, contrast, weak);  // 11
  res = diagonalRules(res, coord, A, B, C, D, E, F, G, H, I, pair, dEB, dED, dEF, dEH);  // 2 to 7
  res = weakCorners(res, weak);                                                 // 1, weak corners
  res = lineThroughAA(res, xbrz, contrast, B, D, E, F, H);                      // 8
  res = closedPixel(res, A, B, C, D, E, F, G, H, I);                            // 10
  res = closedShadow(res, coord, A, B, C, D, E, F, G, H, I);                    // 12
  res = tilesBetweenWalls(res, coord, E);                                       // 13
  res = lineInOtherColor(res, A, B, C, D, E, F, G, H, I, pair, dEB, dED, dEF, dEH);  // 16, 18
  if (CRISP_RULES)                                                              // 32 to 35
  {
    res.z = holeInStroke(wz, res.z);                                            // 33
    res.w = holeInStroke(ww, res.w);
    res.x = holeInStroke(wx, res.x);
    res.y = holeInStroke(wy, res.y);
    vec4 r33 = res;                                                             // 32, 35
    res.z += lonePixelRedone(wz, r33, blendResult, lineZ);
    res.w += lonePixelRedone(ww, r33.yzwx, blendResult.yzwx, lineW);
    res.x += lonePixelRedone(wx, r33.zwxy, blendResult.zwxy, lineX);
    res.y += lonePixelRedone(wy, r33.wxyz, blendResult.wxyz, lineY);
    res.z = smallSquare(wz, res.z);                                             // 34
    res.w = smallSquare(ww, res.w);
    res.x = smallSquare(wx, res.x);
    res.y = smallSquare(wy, res.y);
  }
  res = mix(res, xbrz, band);                                                   // 30, the band wins over the rules above
  FRAG_OUT = res / 255.0;
}

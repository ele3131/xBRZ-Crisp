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
//     grey band of a hood).
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
//     E's area, like a highlight beside antialiased red; where the two neighbors are shades of one gray or hue
//     (their hue under XBRZ_JUNC_HUE apart) much closer to each other than to E (XBRZ_JUNC_SHADE), they are one
//     outline; and a shade of E's own gray or hue along the cut counts as E's color going on, so an outline in
//     two grays that steps by a darker joint bends as in xBRZ (the hood in a SNES portrait).
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
// XBRZ_DIAG = 0 turns rules 2 to 7, 9, 10, 12 and 13 off, and XBRZ_MINC = 0 turns rules 1, 3, 8, 9 and
// 11 to 44 off, so with XBRZ_MINC at 0 only rules 2, 4 to 7 and 10 run.
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
// Matching pass of xbrz-crisp (OpenGL / GLES): once per input pixel, between the resolve pass and pass 1 (rule 26)
//#crisp}

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

// the point pass (three passes back), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev3Texture;
uniform COMPAT_PRECISION vec2 PassPrev3TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev3InputSize;
#define OUT_SIZE OutputSize
#define ORIG_SIZE vec4(PassPrev3TextureSize, 1.0 / PassPrev3TextureSize)
#define ORIG_INPUT_SIZE PassPrev3InputSize
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
#define P(x,y) COMPAT_TEXTURE(PassPrev3Texture, ocoord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, uv)
#define INFO_STEP SRC_SIZE.zw
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)

// pass 0's decisions (two passes back), before the resolve pass changed them
uniform sampler2D PassPrev2Texture;
uniform COMPAT_PRECISION vec2 PassPrev2TextureSize;
#define P0_SIZE vec4(PassPrev2TextureSize, 1.0 / PassPrev2TextureSize)
#define W0_AT(x, y) floor(COMPAT_TEXTURE(PassPrev2Texture, c0 + vec2(x, y) * P0_SIZE.zw) * 255.0 + 0.5)
vec2 ocoord, c0;

// the decision word of a corner (see pass 0 and the resolve pass): BLEND is the blend type, FLAG(r, f) one of its flags
#define BLEND(r) mod(r, 4.0)
#define FLAG(r, f) mod(floor((r) / (f)), 2.0)
vec4 cut4(vec4 w) { return vec4(greaterThan(BLEND(w), vec4(0.0))); }

float distYCbCr(vec3 pixA, vec3 pixB)
{
  const vec3 w = vec3(0.2627, 0.6780, 0.0593);
  vec3 diff = pixA - pixB;
  float Y = dot(diff, w);
  float Cb = 0.5 / (1.0 - 0.0593) * (diff.b - Y);
  float Cr = 0.5 / (1.0 - 0.2627) * (diff.r - Y);
  return sqrt(Y * Y + Cb * Cb + Cr * Cr);
}
float dist255(vec3 a, vec3 b) { return distYCbCr(a, b) * 255.0; }
#define XBRZ_SAME_M 15.0 // two pixels within this are one color (sameColor of the resolve pass); rule 41

// ---- Rule 26: matching corners ----
// A corner that pass 0 cuts and the resolve pass leaves square is cut again where the square corner
// would leave a burr in a diagonal: in a clean line between two colors whose neighbors on both sides
// along the cut are cut (a gap), or where the pixel diagonal to E across the corner's point cuts the
// facing corner with a 45-degree line and E's corner had no line (a crossed cut).
#define XBRZ_MATCH_EDGE 40.0  // E differs from one of the corner's two neighbors by more than this
#define XBRZ_MATCH_WRAP 50.0  // gap: the corner's two neighbors are within this of each other
#define XBRZ_MATCH_LINE 30.0  // gap: so are the same two pixels of both neighbors along the cut


// ---- Rule 27: a bar at a vertex ----
// Two arms of an outline of color C end a knight's move apart (L = G - u and UR = G + u - v) with the gap
// pixel G between them, and T = G - v is the tip of a bar of another color that comes down to the vertex.
// Where pass 0 cuts G's corner toward T and L along a line in T's color, T's color runs on past the
// vertex as a spike: the corner becomes a plain 45-degree cut in T's color where G's color lies between
// T's and C's (an in-between tone), and otherwise G's corners under T stay square, so the bar ends flat.
#define XBRZ_VERTEX_TOL 15.0   // the arms' pixels have C within this
#define XBRZ_VERTEX_EDGE 40.0  // G and T differ from C by more than this
#define XBRZ_VERTEX_BAR 15.0   // the bar's pixels have T's color within this

// one-hot corner of direction c (x TL, y TR, z BR, w BL)
// E and its 8 neighbors in the original (nA to nI, named as in pass 0), read once in main for all the rules
// below, and E's distances to its 4 side neighbors (sB, sD, sF, sH, in x/255)
vec3 nA, nB, nC, nD, nE, nF, nG, nH, nI;
float sB, sD, sF, sH;
// the pixel at offset o (each coordinate -1, 0 or 1) from the 3x3 read in main
#define at3(o) P((o).x, (o).y)
vec4 vtxCorner(vec2 c) { return vec4(c.x < 0.0 && c.y < 0.0, c.x > 0.0 && c.y < 0.0, c.x > 0.0 && c.y > 0.0, c.x < 0.0 && c.y > 0.0); }
// pass 1 takes the horizontal neighbor for corners x and z and the vertical one for y and w, or the other with flag 8
bool vtxSec(vec2 c, vec2 n) { return (c.x * c.y > 0.0) != (abs(n.x) > 0.5); }
bool vtxSame(vec3 a, vec3 b) { return dist255(a, b) <= XBRZ_VERTEX_TOL; }
// the vertex around G = E: L and UR have color C and go on to G - 2u + v and G + 2u; G, T, G + u and
// G - u - v are not C; T's color goes on for two more pixels away from G (a bar, not the 2-pixel round
// end of a shape, which keeps xBRZ's curve)
bool vtxAt(vec2 u, vec2 v)
{
  vec3 C = at3(-u), G = nE, T = at3(-v);
  return vtxSame(C, P(u.x - v.x, u.y - v.y)) && vtxSame(C, P(v.x - 2.0 * u.x, v.y - 2.0 * u.y)) && vtxSame(C, P(2.0 * u.x, 2.0 * u.y))
      && dist255(C, G) > XBRZ_VERTEX_EDGE && dist255(C, T) > XBRZ_VERTEX_EDGE
      && !vtxSame(C, at3(u)) && !vtxSame(C, at3(-u - v))
      && dist255(T, P(-2.0 * v.x, -2.0 * v.y)) <= XBRZ_VERTEX_BAR && dist255(T, P(-3.0 * v.x, -3.0 * v.y)) <= XBRZ_VERTEX_BAR;
}
// G's color lies between T's and C's, in color and in brightness
bool vtxBetween(vec3 g, vec3 t, vec3 c)
{
  vec3 tc = t - c;
  float k = dot(g - c, tc) / max(dot(tc, tc), 1e-6);
  const vec3 wY = vec3(0.2627, 0.6780, 0.0593);
  float yt = dot(t, wY), yc = dot(c, wY), kY = (dot(g, wY) - yc) / (abs(yt - yc) > 1e-3 ? yt - yc : 1e-3);
  return k > 0.15 && k < 0.85 && dist255(c + k * tc, g) < 24.0 && abs(yt - yc) > 1e-3 && kY > 0.15 && kY < 0.85;
}
void vtx(vec2 u, vec2 v, inout vec4 res)
{
  vec2 c = -u - v;
  vec4 m = vtxCorner(c);
  float w = dot(res, m);
  // G's corner toward T and L is cut along a line in T's color
  if (BLEND(w) < 0.5 || FLAG(w, 4.0) < 0.5 || (FLAG(w, 8.0) > 0.5) != vtxSec(c, -v) || !vtxAt(u, v)) return;
  if (vtxBetween(nE, at3(-v), at3(-u)))
    res = mix(res, vec4(vtxSec(c, -v) ? 9.0 : 1.0), m);
  else
  {
    res = mix(res, vec4(0.0), m);
    // G's other corner under T loses a cut in T's color too
    vec2 c2 = u - v;
    vec4 m2 = vtxCorner(c2);
    if ((FLAG(dot(res, m2), 8.0) > 0.5) == vtxSec(c2, -v)) res = mix(res, vec4(0.0), m2);
  }
}
// ---- Rule 38: a pixel kept whole at a junction of four colors ----
// Where the resolve pass keeps a pixel whole (all four corners square, at least one of them cut by pass 0), and
// that pixel and E meet with two more pixels at a point where all four colors clearly differ (all six pairs by
// more than XBRZ_JUNC4) and the pixel diagonal to E cuts its corner at that point, E's corner there stays square
// too (unless it is a shallow or steep line): it would paint the whole pixel's color, or end as a lone ramp of a
// third color against the whole pixel's square side.
#define XBRZ_JUNC4 30.0
float keptWhole(vec2 coord, vec2 n)
{
  vec4 r = INFO_AT(n.x, n.y);
  vec4 w0 = W0_AT(n.x, n.y);
  return float(dot(cut4(r), vec4(1.0)) < 0.5 && dot(cut4(w0) * FLAG(w0, 4.0), vec4(1.0)) > 0.5);
}
#define XBRZ_STEP38 0.5 // 38. two shades of one stroke: under this fraction as far apart as the other colors
vec4 junc4(vec2 coord, vec4 res)
{
  vec3 E = nE;
  float wB = keptWhole(coord, vec2(0.0, -1.0)), wD = keptWhole(coord, vec2(-1.0, 0.0));
  float wF = keptWhole(coord, vec2(1.0, 0.0)), wH = keptWhole(coord, vec2(0.0, 1.0));
  if (wB + wD + wF + wH < 0.5) return res;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float w = dot(res, m);
    if (BLEND(w) < 0.5 || FLAG(w, 16.0) + FLAG(w, 64.0) > 0.5) continue;
    // the blend color is the horizontal neighbor for x and z and the vertical one for y and w, or the other with flag 8
    bool horiz = (c.x * c.y > 0.0) != (FLAG(w, 8.0) > 0.5);
    vec2 p = horiz ? vec2(c.x, 0.0) : vec2(0.0, c.y), q = horiz ? vec2(0.0, c.y) : vec2(c.x, 0.0);
    float wp = p.x < -0.5 ? wD : p.x > 0.5 ? wF : p.y < -0.5 ? wB : wH;
    float wq = q.x < -0.5 ? wD : q.x > 0.5 ? wF : q.y < -0.5 ? wB : wH;
    // E paints the whole pixel's color (wp), or E's cut ends against the whole pixel's square side (wq)
    if (wp + wq < 0.5) continue;
    // the pixel diagonal to E cuts its corner at the same point too (the two cuts join P and Q across the point)
    if (BLEND(dot(INFO_AT(c.x, c.y), vtxCorner(-c))) < 0.5) continue;
    // a junction of four different colors
    vec3 Pc = at3(p), Qc = at3(q), X = at3(c);
    float dPQ = dist255(Pc, Qc);
    float lo5 = min(min(min(dist255(E, Pc), dist255(E, Qc)), min(dist255(E, X), dist255(Pc, X))), dist255(Qc, X));
    if (min(lo5, dPQ) <= XBRZ_JUNC4) continue;
    // unless the two colors the cut joins are two shades of one stroke (under XBRZ_STEP38 as far apart as the
    // other colors), like the dark brown and brown outline of a hood: the cut is the stroke's bend, as in xBRZ
    if (dPQ < XBRZ_STEP38 * lo5) continue;
    // or the two side neighbors' colors go on away from the point, one along each side
    if (dist255(P(0.0, 2.0 * c.y), at3(vec2(0.0, c.y))) < XBRZ_SAME_M && dist255(at3(vec2(c.x, -c.y)), at3(vec2(c.x, 0.0))) < XBRZ_SAME_M) continue;
    res = mix(res, vec4(0.0), m);
  }
  return res;
}
// ---- Rule 39: a pixel exactly between its two corner colors ----
// Where E's two neighbors at a corner are equally far from E (an exact tie) and E lies on the straight
// ramp between them (it is the middle step of an antialiasing ramp), neither color has a better claim to
// the corner when the pixel across the corner is a fourth color, so it stays square and E touches both, like the light pink under the white of an eye.
#define XBRZ_FAR39 100.0 // 39. a near tie needs the pixel across the corner this far from the three
#define XBRZ_MID39 0.1   // 39. E's distances to the two neighbors differ by less than this fraction
vec4 tieRamp(vec4 res)
{
  vec3 E = nE;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float wc = dot(res, m);
    if (BLEND(wc) < 0.5) continue;
    vec3 Nh = at3(vec2(c.x, 0.0)), Nv = at3(vec2(0.0, c.y));
    float a = c.x > 0.0 ? sF : sD, b = c.y > 0.0 ? sH : sB;   // dist255(E, Nh) and dist255(E, Nv)
    vec3 X = at3(c);
    float xd = min(dist255(X, Nh), min(dist255(X, Nv), dist255(X, E)));
    // an exact tie with a fourth color across the corner, or a near tie (within XBRZ_MID39) with a far one (a highlight)
    // (a near tie only on a plain cut or a 45-degree line: a 2:1 line goes on through the neighbors)
    bool tie = abs(a - b) < 0.01 ? xd > 20.0 : abs(a - b) < XBRZ_MID39 * max(a, b) && xd > XBRZ_FAR39 && FLAG(wc, 16.0) + FLAG(wc, 64.0) < 0.5;
    if (tie && min(a, b) > 20.0 && dist255(Nh, Nv) > 1.8 * max(a, b)) res = mix(res, vec4(0.0), m);
  }
  return res;
}

// ---- Rule 40: a dot separates what is around it ----
// A lone dot (a pixel that differs from all 8 of its neighbors by XBRZ_DOT40 or more, like a nostril between
// skin tones) whose ring of neighbors holds a color K in two or more separate groups (the shadow under an eye
// and a mouth, on two sides of the nose) keeps them apart: a corner next to the dot (or of the dot) that would
// paint K stays square, so K is not drawn as one stroke through the dot.
#define XBRZ_DOT40 40.0
#define XBRZ_DOTK40 8.0
bool dot40(vec2 n, vec3 K)
{
  vec3 c = at3(n);
  if (dist255(c, K) < XBRZ_DOT40) return false;
  float g = 0.0;
  const vec3 lw = vec3(0.2627, 0.6780, 0.0593);
  float lk = dot(K, lw);
  if (dot(c, lw) >= lk) return false; // the dot is darker than K, and K darker than the rest of the ring
  // ring in circular order: TL T TR R BR B BL L
  vec2 r[8];
  r[0] = vec2(-1.0, -1.0); r[1] = vec2(0.0, -1.0); r[2] = vec2(1.0, -1.0); r[3] = vec2(1.0, 0.0);
  r[4] = vec2(1.0, 1.0); r[5] = vec2(0.0, 1.0); r[6] = vec2(-1.0, 1.0); r[7] = vec2(-1.0, 0.0);
  vec3 q = P(n.x - 1.0, n.y);
  float nc = 0.0; // distinct colors in the ring
  vec3 u0 = q, u1 = q, u2 = q;
  bool prev = dist255(q, K) < XBRZ_DOTK40;
  for (int i = 0; i < 8; i++)
  {
    vec3 p = P(n.x + r[i].x, n.y + r[i].y);
    if (dist255(c, p) < XBRZ_DOT40) return false; // not a lone dot
    bool k = dist255(p, K) < XBRZ_DOTK40;
    bool fresh = nc < 0.5 || (dist255(p, u0) >= XBRZ_DOTK40 && (nc < 1.5 || dist255(p, u1) >= XBRZ_DOTK40) && (nc < 2.5 || dist255(p, u2) >= XBRZ_DOTK40));
    if (fresh) { if (nc > 2.5) return false; if (nc < 0.5) u0 = p; else if (nc < 1.5) u1 = p; else u2 = p; nc += 1.0; }
    if (k && !prev) g += 1.0;
    if (!k && dot(p, lw) <= lk) return false; // K is not darker than the rest of the ring
    prev = k;
  }
  return g > 1.5;
}
vec4 dots40(vec4 res)
{
  // E itself can only be the dot when it differs from all 8 neighbors by XBRZ_DOT40 or more (dot40 tests the
  // same distances), so that is tested once here instead of in each corner's call
  float r8 = min(min(min(dist255(nE, nA), dist255(nE, nB)), min(dist255(nE, nC), dist255(nE, nF))),
                 min(min(dist255(nE, nI), dist255(nE, nH)), min(dist255(nE, nG), dist255(nE, nD))));
  bool loneDot = r8 >= XBRZ_DOT40;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float w = dot(res, m);
    if (BLEND(w) < 0.5) continue;
    bool horiz = (c.x * c.y > 0.0) != (FLAG(w, 8.0) > 0.5);
    vec3 K = horiz ? at3(vec2(c.x, 0.0)) : at3(vec2(0.0, c.y));
    vec2 o = horiz ? vec2(0.0, c.y) : vec2(c.x, 0.0);
    if (dot40(o, K)) res = mix(res, vec4(0.0), m);
    else if (loneDot && dot40(vec2(0.0), K)) res = mix(res, vec4(3.0 + 8.0 * FLAG(w, 8.0)), m); // the dot itself: rule 23's small tip
  }
  return res;
}
// ---- Rule 41: a 1-pixel diagonal stroke keeps an even edge ----
// A 1-pixel diagonal stroke or stripe (its color goes on at diagonal neighbors and at none of the 4 side
// neighbors) should keep straight edges. Two corners break them:
// a) the stroke's outer corner, left square when the two side neighbors at it have different colors, so a dark
//    stroke (darker than both) gets a square bump. That corner is cut along the stroke's edge and takes the side
//    neighbor whose color is across the corner, like the black outline under the red at Harry's knees.
// b) the two corners at the ends of the edge between E and a side neighbor N, drawn as 2:1 lines that lean
//    opposite ways (one shallow, one steep), where one of them joins two pixels of a stripe of N's or E's color:
//    they squeeze the stripe into a thin tip that runs down the edge (the olive stripe on the Golden Sun
//    slime). The joining corner is drawn at 45 degrees and the stripe pixel's own corner as a plain cut.
bool lone41(vec2 p)
{
  vec3 c = at3(p);
  return dist255(c, P(p.x - 1.0, p.y)) >= XBRZ_SAME_M && dist255(c, P(p.x + 1.0, p.y)) >= XBRZ_SAME_M
      && dist255(c, P(p.x, p.y - 1.0)) >= XBRZ_SAME_M && dist255(c, P(p.x, p.y + 1.0)) >= XBRZ_SAME_M;
}
float lineType41(float w) { return FLAG(w, 4.0) * (FLAG(w, 16.0) - FLAG(w, 64.0)); } // +1 shallow only, -1 steep only
// a) what to add to E's square corner c (0 to leave it): E is the stroke pixel, its other corner on the stroke's
// side is already cut along it, and exactly one side neighbor at c has the color across the corner
float edge41(vec2 c, vec4 r0, vec3 E, float w)
{
  if (BLEND(dot(r0, vtxCorner(-c))) < 0.5) return 0.0;
  if (dist255(E, at3(vec2(c.x, -c.y))) >= XBRZ_SAME_M || dist255(E, at3(vec2(-c.x, c.y))) >= XBRZ_SAME_M) return 0.0;
  vec3 V = at3(vec2(0.0, c.y)), H = at3(vec2(c.x, 0.0)), X = at3(c);
  if (dist255(E, X) < XBRZ_SAME_M) return 0.0;
  vec3 lw = vec3(0.299, 0.587, 0.114);
  if (dot(E, lw) > min(dot(V, lw), dot(H, lw)) - 0.03) return 0.0;
  bool kH = dist255(X, H) < XBRZ_SAME_M, kV = dist255(X, V) < XBRZ_SAME_M;
  if (kH == kV) return 0.0;
  // the other side neighbor O is not a parallel stroke (its color does not go on along the stroke) nor the end
  // of a straight run of its color pointing at E (the cut would clip the run's end)
  vec2 o = kH ? vec2(0.0, c.y) : vec2(c.x, 0.0);
  vec3 O = at3(o);
  if (dist255(O, P(2.0 * o.x, 2.0 * o.y)) < XBRZ_SAME_M) return 0.0;
  if (dist255(O, P(o.x + c.x, o.y - c.y)) < XBRZ_SAME_M || dist255(O, P(o.x - c.x, o.y + c.y)) < XBRZ_SAME_M) return 0.0;
  bool sec = vtxSec(c, kH ? vec2(c.x, 0.0) : vec2(0.0, c.y));
  return 1.0 + 4.0 + (sec ? 8.0 : 0.0) - mod(floor(w / 8.0), 2.0) * 8.0;
}
// ---- 42. A step in a 45-degree edge ----
// E's corner c is square while the same corner of both pixels along the edge, (c.x, -c.y) and (-c.x, c.y),
// is cut along a 45-degree line (a line with neither or both of the 2:1 flags) in the color K of the far
// side. E's two neighbors at c and the pixel across c are that one color K, which differs from E by
// XBRZ_MINC or more, and E's other two neighbors are not K (E is the convex tip of its side): the edge is
// a straight 45-degree line and E's square corner is a step in it (xBRZ leaves it square where a far pixel
// of its ring tips a near tie the other way). E's corner is cut along the same 45-degree line.
// the neighbor whose color fills corner c of a pixel with word w (as pass 1 takes it)
vec2 paintOf(vec2 c, float w) { return ((c.x * c.y > 0.0) != (FLAG(w, 8.0) > 0.5)) ? vec2(c.x, 0.0) : vec2(0.0, c.y); }
vec4 edgeStep42(vec2 coord, vec4 res)
{
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    if (BLEND(dot(res, m)) > 0.5) continue;
    vec3 K = at3(vec2(c.x, 0.0));
    if (dist255(K, at3(vec2(0.0, c.y))) >= XBRZ_SAME_M || dist255(K, at3(c)) >= XBRZ_SAME_M || (c.x > 0.0 ? sF : sD) < XBRZ_MINC) continue;
    if (dist255(K, at3(vec2(-c.x, 0.0))) < XBRZ_SAME_M || dist255(K, at3(vec2(0.0, -c.y))) < XBRZ_SAME_M) continue;
    float ok = 1.0;
    for (int j = 0; j < 2; j++)
    {
      vec2 q = j == 0 ? vec2(c.x, -c.y) : vec2(-c.x, c.y);
      float wq = dot(INFO_AT(q.x, q.y), m);
      vec2 p = q + paintOf(c, wq);
      if (BLEND(wq) < 0.5 || FLAG(wq, 4.0) < 0.5 || FLAG(wq, 16.0) != FLAG(wq, 64.0) || dist255(P(p.x, p.y), K) >= XBRZ_SAME_M) ok = 0.0;
    }
    res += m * 5.0 * ok;
  }
  return res;
}
vec4 diagStroke41(vec2 coord, vec4 res, bool loneE)
{
  vec3 E = nE;
  vec4 r0 = res;
  for (int i = 0; i < 4; i++)
  {
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    float w = dot(r0, m);
    if (BLEND(w) < 0.5 && loneE) { res += m * edge41(c, r0, E, w); w = dot(res, m); }
    // b) a pinch: c and the facing corner of a side neighbor N are 2:1 lines leaning opposite ways
    float t = lineType41(w);
    if (BLEND(w) < 0.5 || abs(t) < 0.5) continue;
    for (int j = 0; j < 2; j++)
    {
      vec2 n = j == 0 ? vec2(c.x, 0.0) : vec2(0.0, c.y);
      float wn = dot(INFO_AT(n.x, n.y), vtxCorner(-c));
      if (BLEND(wn) < 0.5 || lineType41(wn) != -t) continue;
      vec2 o = c - n;                       // E's other neighbor at corner c
      vec3 N = at3(n);
      // E's corner joins N to O, two pixels of a 1-pixel diagonal stripe of N's color
      if (!loneE && dist255(N, at3(o)) < XBRZ_SAME_M && lone41(n) && lone41(o))
      { res -= m * (16.0 * FLAG(w, 16.0) + 64.0 * FLAG(w, 64.0)); break; }
      // E is the stripe pixel and N's corner joins E to the next stripe pixel (diagonal to E across N's corner)
      vec2 q = -c + c * abs(n); // from N, its other neighbor at its corner -c
      if (loneE && dist255(E, at3(n + q)) < XBRZ_SAME_M && lone41(n + q))
      { res -= m * (4.0 + 16.0 * FLAG(w, 16.0) + 64.0 * FLAG(w, 64.0)); break; }
    }
  }
  return res;
}
// ---- Rule 43: a dome ----
// Corner c of E, whose pass 0 cut the resolve pass took back (lost), is cut again when E and its
// neighbor along the run (-s) are one color, a cap color U runs over both and past each end (v, c, v - s, v - 2s),
// the run ends on both sides in one color S (s and -2s), E, S and U are XBRZ_MINC or more apart, and the mirror
// corner of the run's other pixel is cut: the cap of a 2-pixel run ends round on both sides.
float dome43(vec2 coord, vec2 c, vec2 s, vec2 v)
{
  if (dist255(at3(-s), nE) >= XBRZ_SAME_M) return 0.0;
  vec3 S = at3(s), U = at3(v);
  if (dist255(S, U) < XBRZ_MINC
      || dist255(at3(c), U) >= XBRZ_SAME_M || dist255(at3(v - s), U) >= XBRZ_SAME_M
      || dist255(P(-2.0 * s.x, -2.0 * s.y), S) >= XBRZ_SAME_M || dist255(P(v.x - 2.0 * s.x, v.y - 2.0 * s.y), U) >= XBRZ_SAME_M)
    return 0.0;
  return float(BLEND(dot(INFO_AT(-s.x, -s.y), vtxCorner(c - 2.0 * s))) > 0.5);
}
vec4 domes43(vec2 coord, vec4 lost)
{
  vec4 d = vec4(0.0);
  // j: the corner (j / 2) and the run's direction (even: along x, odd: along y)
  for (int j = 0; j < 8; j++)
  {
    int i = j / 2;
    vec2 c = i == 0 ? vec2(-1.0, -1.0) : i == 1 ? vec2(1.0, -1.0) : i == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
    vec4 m = vtxCorner(c);
    if (dot(lost - d, m) < 0.5) continue;
    bool alongX = j - 2 * i == 0;
    vec2 s = alongX ? vec2(c.x, 0.0) : vec2(0.0, c.y), v = c - s;
    d += dome43(coord, c, s, v) * m;
  }
  return d;
}
// ---- Rule 44: the end of a dark 1-pixel stroke ----
// Where E ends a stroke 1 pixel wide (one side neighbor, the next pixel of the stroke, within XBRZ_SAME_M of E) and
// the 7 pixels around that end (the one in front, the two beside E, the two diagonal in front and the two beside
// the next pixel) are all XBRZ_END44 or more from E and lighter than it, E's two corners at the end that pass 0
// left square are cut as plain corners, so the end of a dark mark is round like its other end (a pupil under a
// white eyelid, the end of a font's shadow).
#define XBRZ_END44 100.0
#define LUMA_W44 vec3(0.2627, 0.6780, 0.0593)
float far44(vec3 E, float lE, vec2 o)
{
  vec3 q = P(o.x, o.y);
  return float(dist255(E, q) >= XBRZ_END44 && dot(q, LUMA_W44) >= lE);
}
vec4 strokeEnd44(vec4 res)
{
  vec4 s = vec4(sB, sF, sH, sD);
  // one side neighbor goes on with E and the other three are far: E is the end of a 1-pixel stroke
  if (dot(vec4(lessThan(s, vec4(XBRZ_SAME_M))), vec4(1.0)) != 1.0 || dot(vec4(greaterThanEqual(s, vec4(XBRZ_END44))), vec4(1.0)) != 3.0)
    return res;
  vec2 v = sB < XBRZ_SAME_M ? vec2(0.0, -1.0) : sF < XBRZ_SAME_M ? vec2(1.0, 0.0) : sH < XBRZ_SAME_M ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
  vec2 u = vec2(v.y, v.x);
  vec3 E = nE;
  float lE = dot(E, LUMA_W44);
  if (far44(E, lE, -v) * far44(E, lE, u) * far44(E, lE, -u) * far44(E, lE, v + u) * far44(E, lE, v - u) *
      far44(E, lE, u - v) * far44(E, lE, -u - v) < 0.5)
    return res;
  for (int k = 0; k < 2; k++)
  {
    vec2 c = k == 0 ? u - v : -u - v;
    vec4 m = vtxCorner(c);
    if (BLEND(dot(res, m)) > 0.5) continue;
    // a plain cut in the nearer of the corner's two neighbors (pass 1 takes the horizontal one for x and z)
    vec3 Nh = at3(vec2(c.x, 0.0)), Nv = at3(vec2(0.0, c.y));
    bool hz = c.x * c.y > 0.0;
    float dPri = dist255(E, hz ? Nh : Nv), dSec = dist255(E, hz ? Nv : Nh);
    res = mix(res, vec4(dPri <= dSec ? 1.0 : 9.0), m);
  }
  return res;
}
void main()
{
  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;
  ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;
  c0 = coord * SRC_SIZE.xy * P0_SIZE.zw;
  vec4 res = INFO_AT(0.0, 0.0);
  // every rule of this pass is off with XBRZ_MINC 0
  if (XBRZ_MINC <= 0.0)
  {
    FRAG_OUT = res / 255.0;
    return;
  }
  vec4 w0 = W0_AT(0.0, 0.0);
  nA = P(-1.0, -1.0); nB = P(0.0, -1.0); nC = P(1.0, -1.0);
  nD = P(-1.0, 0.0);  nE = P(0.0, 0.0);  nF = P(1.0, 0.0);
  nG = P(-1.0, 1.0);  nH = P(0.0, 1.0);  nI = P(1.0, 1.0);
  sB = dist255(nE, nB); sD = dist255(nE, nD); sF = dist255(nE, nF); sH = dist255(nE, nH);
  vec4 lost = cut4(w0) * (1.0 - cut4(res));
  if (dot(lost, vec4(1.0)) > 0.0)
  {
    vec4 rA = INFO_AT(-1.0, -1.0), rC = INFO_AT(1.0, -1.0), rI = INFO_AT(1.0, 1.0), rG = INFO_AT(-1.0, 1.0);
    vec3 E = nE, B = nB, D = nD, F = nF, H = nH;
    float dB = sB, dD = sD, dF = sF, dH = sH;
    vec4 strong = vec4(greaterThan(max(vec4(dB, dB, dF, dH), vec4(dD, dF, dH, dD)), vec4(XBRZ_MATCH_EDGE)));

    // gap: the same corner of both neighbors along the cut is cut, E's corner nearly wraps (its two
    // neighbors are close) and so do the neighbors' corners, so the cut is one boundary between two colors
    vec4 gap = vec4(cut4(rC).x * cut4(rG).x, cut4(rI).y * cut4(rA).y, cut4(rC).z * cut4(rG).z, cut4(rI).w * cut4(rA).w);
    vec4 wrapE = vec4(lessThan(vec4(dist255(B, D), dist255(B, F), dist255(F, H), dist255(H, D)), vec4(XBRZ_MATCH_WRAP)));
    float wCx = dist255(P(1.0, -2.0), B), wGx = dist255(D, P(-2.0, 1.0));
    float wAy = dist255(P(-1.0, -2.0), B), wIy = dist255(F, P(2.0, 1.0));
    float wCz = dist255(P(2.0, -1.0), F), wGz = dist255(H, P(-1.0, 2.0));
    float wAw = dist255(D, P(-2.0, -1.0)), wIw = dist255(P(1.0, 2.0), H);
    vec4 wrapN = vec4(lessThan(vec4(max(wCx, wGx), max(wAy, wIy), max(wCz, wGz), max(wAw, wIw)), vec4(XBRZ_MATCH_LINE)));

    // crossed cut: the pixel diagonal to E across the corner's point cuts the facing corner with a
    // 45-degree line (shallow and steep), and pass 0 drew E's corner with no line
    vec4 part = vec4(cut4(rA).z, cut4(rC).w, cut4(rI).x, cut4(rG).y);
    vec4 l45 = vec4(FLAG(rA, 16.0).z * FLAG(rA, 64.0).z, FLAG(rC, 16.0).w * FLAG(rC, 64.0).w,
                    FLAG(rI, 16.0).x * FLAG(rI, 64.0).x, FLAG(rG, 16.0).y * FLAG(rG, 64.0).y);

    vec4 fix = lost * strong * max(gap * wrapE * wrapN, part * l45 * (1.0 - FLAG(w0, 4.0)));
    // 43 (a corner of a 2-pixel run under a cap)
    // (only where both side neighbors at the corner are XBRZ_MINC or more from E,
    vec4 far43 = vec4(greaterThanEqual(min(vec4(dD, dF, dF, dD), vec4(dB, dB, dH, dH)), vec4(XBRZ_MINC)));
    // and the run goes on to the other side neighbor along x or along y (x: F or H, y: D or H, z: D or B, w: F or B)
    far43 *= vec4(lessThan(min(vec4(dF, dD, dD, dF), vec4(dH, dH, dB, dB)), vec4(XBRZ_SAME_M)));
    if (dot(lost, far43) > 0.0) fix = max(fix, domes43(coord, lost * far43));
    // pass 0's corner back, in the resolve's word (cut, line, second color, shallow, steep)
    vec4 back = 1.0 + 4.0 * FLAG(w0, 4.0) + 8.0 * FLAG(w0, 8.0) + 16.0 * FLAG(w0, 16.0) + 64.0 * FLAG(w0, 64.0);
    res = mix(res, back, fix);
  }
  // rule 27: a bar at a vertex ends flat (or in a plain cut where the gap pixel is an in-between tone)
  // (only a corner cut along a line can be the spike)
  if (dot(cut4(res) * FLAG(res, 4.0), vec4(1.0)) > 0.0)
  {
    vtx(vec2( 1.0, 0.0), vec2(0.0,  1.0), res); vtx(vec2(-1.0, 0.0), vec2(0.0,  1.0), res);
    vtx(vec2( 1.0, 0.0), vec2(0.0, -1.0), res); vtx(vec2(-1.0, 0.0), vec2(0.0, -1.0), res);
    vtx(vec2(0.0,  1.0), vec2( 1.0, 0.0), res); vtx(vec2(0.0, -1.0), vec2( 1.0, 0.0), res);
    vtx(vec2(0.0,  1.0), vec2(-1.0, 0.0), res); vtx(vec2(0.0, -1.0), vec2(-1.0, 0.0), res);
  }
  // 42 (only where E differs from a horizontal neighbor by XBRZ_MINC or more, which the rule needs)
  if (max(sD, sF) >= XBRZ_MINC) res = edgeStep42(coord, res);
  // rules 38 to 41 (38 a junction of four colors, 39 a tie on a ramp, 40 a dot that separates, 41 a 1-pixel
  // diagonal stroke's edge)
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = junc4(coord, res);
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = tieRamp(res);
  if (dot(cut4(res), vec4(1.0)) > 0.0) res = dots40(res);
  // 41 (a: E is a 1-pixel stroke, apart from its 4 side neighbors; b: a corner drawn as a 2:1 line)
  bool loneE = min(min(sB, sD), min(sF, sH)) >= XBRZ_SAME_M;
  if (loneE || dot(cut4(res) * FLAG(res, 4.0) * abs(FLAG(res, 16.0) - FLAG(res, 64.0)), vec4(1.0)) > 0.0)
    res = diagStroke41(coord, res, loneE);
  // 44 (only where E has a side neighbor XBRZ_END44 or more away)
  if (max(max(sB, sD), max(sF, sH)) >= XBRZ_END44) res = strokeEnd44(res);
  FRAG_OUT = res / 255.0;
}
#endif

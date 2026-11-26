// ---- Shared corner/axis geometry helpers for the match pass ----
// Corner index order matches decision-word channels: 0 = TL (-1,-1), 1 = TR (1,-1), 2 = BR (1,1), 3 = BL (-1,1)
vec2 cornerOff(int k)
{
  return k == 0 ? vec2(-1.0, -1.0) : k == 1 ? vec2(1.0, -1.0) : k == 2 ? vec2(1.0, 1.0) : vec2(-1.0, 1.0);
}
// Cardinal index order: 0 = B (0,-1), 1 = F (1,0), 2 = H (0,1), 3 = D (-1,0)
vec2 cardOff(int k)
{
  return k == 0 ? vec2(0.0, -1.0) : k == 1 ? vec2(1.0, 0.0) : k == 2 ? vec2(0.0, 1.0) : vec2(-1.0, 0.0);
}
vec4 cornerMask(int k)
{
  return vec4(float(k == 0), float(k == 1), float(k == 2), float(k == 3));
}
vec4 vtxCorner(vec2 c)
{
  return vec4(c.x < 0.0 && c.y < 0.0, c.x > 0.0 && c.y < 0.0, c.x > 0.0 && c.y > 0.0, c.x < 0.0 && c.y > 0.0);
}
// True when cardinal neighbor n is the second candidate (BIT_SEC) of corner c
bool vtxSec(vec2 c, vec2 n)
{
  return (c.x * c.y > 0.0) != (abs(n.x) > 0.5);
}
// For corner k with a 2:1 slope (isSh = shallow, !isSh = steep):
//   nbrOff = cardinal neighbor along the 2:1 long edge, othOff = the other cardinal neighbor of corner k
void slope21Offsets(int k, bool isSh, out vec2 nbrOff, out vec2 othOff)
{
  vec2 c = cornerOff(k);
  bool nIsV = (k == 0 || k == 2) ? isSh : !isSh;
  nbrOff = nIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
  othOff = c - nbrOff;
}
// For corner k at offset c with BIT_SEC flag s1:
//   pOff = painted cardinal neighbor, qOff = unchosen cardinal neighbor
void paintPairOffsets(int k, vec2 c, bool s1, out vec2 pOff, out vec2 qOff)
{
  bool pIsV = (k == 0 || k == 2) ? s1 : !s1;
  pOff = pIsV ? vec2(0.0, c.y) : vec2(c.x, 0.0);
  qOff = c - pOff;
}

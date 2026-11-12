"""Build siege4_td.map: a self-made four-lane siege map for the cs_td tower-defence rules
(X Hero Siege style: base in the middle, monsters walk in from the four ends).

    python maps/siege4_td/build_siege4.py OUT.map

Layout (top view, units; the whole map is symmetric in x and y):

                 [N spawn room]
                      | |   lane 384 wide, 1920 long
    [W room] ===== [ plaza ] ===== [E room]
                      | |
                 [S spawn room]

- plaza 1280 x 1280 in the middle: player spawns, the Arms Dealer, gold mines A (north-east
  corner) and B (south-west corner)
- four lanes 384 wide; spawn rooms 1024 x 480 at the far ends (monster spawns, info_target
  pve_mspawn)
- everything outside the plus shape is a 256-high rock block under an open sky
- info_node grid every 128 units over the walkable floor (monster path-finding)

Textures come from halflife.wad, which every Sven Co-op install ships (not embedded).
Needs goldsrc-agent-kit (tools/bspdecomp.py) next to this repo for write_map().
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(HERE, '..', '..', '..', 'goldsrc-agent-kit', 'tools')
sys.path.insert(0, KIT)
from bspdecomp import write_map   # noqa: E402

WAD = r'C:\Program Files (x86)\Steam\steamapps\common\Sven Co-op\svencoop\halflife.wad'

EXT = 3072          # outer wall inner face
T = 32              # shell thickness
PLAZA = 640         # plaza half size
LANE = 192          # lane half width
ROOM_IN = 2560      # spawn room starts here
ROOM_HALF = 512     # spawn room half width
BLOCK_H = 256       # rock blocks
SKY_Z = 640         # sky ceiling bottom

FLOOR_PLAZA = 'OUT_PAVE1'
FLOOR_LANE = 'OUT_GRVL2'
FLOOR_ROOM = 'OUT_DIRT1'
ROCK_SIDE = 'OUT_RK3'
ROCK_TOP = 'OUT_GRND1'
SHELL = 'OUT_RK3'
CRATE = 'CRATE02'


def box(mn, mx, side, top=None, bottom=None):
    """axis-aligned brush; side/top/bottom texture names"""
    top = top or side
    bottom = bottom or side
    faces = []
    for axis in range(3):
        for sign in (-1, 1):
            n = [0, 0, 0]
            n[axis] = sign
            p = mn if sign < 0 else mx
            tex = side if axis < 2 else (top if sign > 0 else bottom)
            faces.append((tuple(n), tuple(p), (tex, None, None)))
    return faces


brushes = []

# ---- shell: floor pieces, outer walls, sky lid ----
# floor, textured per area (one slab per area so each gets its own texture)
def floor(x0, y0, x1, y1, tex):
    brushes.append(box((x0, y0, -32), (x1, y1, 0), tex))

floor(-PLAZA, -PLAZA, PLAZA, PLAZA, FLOOR_PLAZA)
for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    if sx:
        a, b = sorted((sx * PLAZA, sx * ROOM_IN))
        floor(a, -LANE, b, LANE, FLOOR_LANE)
        a, b = sorted((sx * ROOM_IN, sx * EXT))
        floor(a, -ROOM_HALF, b, ROOM_HALF, FLOOR_ROOM)
    else:
        a, b = sorted((sy * PLAZA, sy * ROOM_IN))
        floor(-LANE, a, LANE, b, FLOOR_LANE)
        a, b = sorted((sy * ROOM_IN, sy * EXT))
        floor(-ROOM_HALF, a, ROOM_HALF, b, FLOOR_ROOM)

# rock blocks fill each quadrant outside the plus shape (quadrant +x +y, mirrored)
QUAD = [
    ((LANE, PLAZA), (ROOM_HALF, ROOM_IN)),        # beside the N lane, up to the N room
    ((ROOM_HALF, PLAZA), (PLAZA, EXT)),           # beside the N room
    ((PLAZA, PLAZA), (EXT, EXT)),                 # the corner
    ((PLAZA, ROOM_HALF), (EXT, PLAZA)),           # beside the E room
    ((PLAZA, LANE), (ROOM_IN, ROOM_HALF)),        # beside the E lane, up to the E room
]
for sx in (1, -1):
    for sy in (1, -1):
        for (x0, y0), (x1, y1) in QUAD:
            xa, xb = sorted((x0 * sx, x1 * sx))
            ya, yb = sorted((y0 * sy, y1 * sy))
            brushes.append(box((xa, ya, -32), (xb, yb, BLOCK_H), ROCK_SIDE, ROCK_TOP))

# outer walls up to the sky, sky lid
brushes.append(box((-EXT - T, -EXT - T, -32), (-EXT, EXT + T, SKY_Z), SHELL))
brushes.append(box((EXT, -EXT - T, -32), (EXT + T, EXT + T, SKY_Z), SHELL))
brushes.append(box((-EXT, -EXT - T, -32), (EXT, -EXT, SKY_Z), SHELL))
brushes.append(box((-EXT, EXT, -32), (EXT, EXT + T, SKY_Z), SHELL))
brushes.append(box((-EXT - T, -EXT - T, SKY_Z), (EXT + T, EXT + T, SKY_Z + T), 'SKY'))
brushes.append(box((-EXT - T, -EXT - T, -32 - T), (EXT + T, EXT + T, -32), SHELL))

# a little cover: crate stacks at the lane mouths (players can build towers behind them)
CRATES = [(-320, 320), (320, -320)]   # the two plaza corners without a gold mine
for cx, cy in CRATES:
    for dx, dy in ((0, 0), (64, 0)):
        x = cx + (dx if cx > 0 else -dx)
        brushes.append(box((x - 32, cy - 32, 0), (x + 32, cy + 32, 64), CRATE))
    brushes.append(box((cx - 32, cy - 32, 64), (cx + 32, cy + 32, 128), CRATE))

# ---- entities ----
ents = []


def ent(cls, origin, **kv):
    e = {'classname': cls, 'origin': '%d %d %d' % origin}
    e.update({k: str(v) for k, v in kv.items()})
    ents.append(e)


ents.append({'classname': 'light_environment', 'origin': '0 0 520', 'pitch': '-55', 'angles': '0 35 0',
             '_light': '255 236 200 260', '_diffuse_light': '170 190 220 70'})
# a few fill lights so the lane walls in shadow are not pitch black
for p in ((0, 0, 400), (0, 1600, 300), (0, -1600, 300), (1600, 0, 300), (-1600, 0, 300)):
    ent('light', p, _light='255 230 190 160')

# players: a ring of 8 spawns in the plaza (also the buy zone; core.as puts the Arms Dealer there)
for i, (x, y) in enumerate(((0, 160), (160, 0), (0, -160), (-160, 0), (112, 112), (-112, 112), (112, -112), (-112, -112))):
    ent('info_player_start', (x, y, 40), angles='0 %d 0' % (90 * (i % 4)))

# monster spawns: a 3 x 3 grid in each spawn room
for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    for a in (-256, 0, 256):          # across the room
        for b in (2700, 2820, 2940):  # depth into the room
            x, y = (sx * b, a) if sx else (a, sy * b)
            ent('info_target', (x, y, 40), targetname='pve_mspawn')

# info_node grid over the walkable floor (plaza, lanes, rooms), skipping the crates
def walkable(x, y):
    if abs(x) <= PLAZA - 48 and abs(y) <= PLAZA - 48:
        for cx, cy in CRATES:
            if abs(x - cx) < 140 and abs(y - cy) < 80:
                return False
        return True
    for u, v in ((x, y), (y, x)):
        if abs(v) <= LANE - 48 and PLAZA - 48 <= abs(u) <= ROOM_IN:
            return True
        if abs(v) <= ROOM_HALF - 48 and ROOM_IN <= abs(u) <= EXT - 48:
            return True
    return False

nodes = 0
for x in range(-EXT + 64, EXT, 128):
    for y in range(-EXT + 64, EXT, 128):
        if walkable(x, y):
            ent('info_node', (x, y, 16))
            nodes += 1

ws = {'classname': 'worldspawn', 'mapversion': '220', 'wad': WAD, 'skyname': 'desert',
      'message': 'siege4 TD - four lanes, one base', 'MaxRange': '8192'}
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'siege4_td.map')
write_map(out, ws, brushes, ents)
print('brushes', len(brushes), 'entities', len(ents), 'info_nodes', nodes, '->', out)

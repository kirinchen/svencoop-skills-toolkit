"""cs2sven.py - port a compiled Counter-Strike 1.6 map into Sven Co-op as a PVE (monster) map.

No decompile, no recompile. Only the entity lump is rewritten:
  * worldspawn         : wad list reduced to basenames (Sven searches its own dirs)
  * info_player_start  : kept -> player spawns (CT side)
  * info_player_deathmatch (T side)           -> info_target "pve_mspawn"  (monster spawns)
  * func_bomb_target / func_hostage_rescue /
    func_vip_safetyzone / func_escapezone     -> a few info_target "pve_flank" inside the zone
  * func_buyzone, hostage_entity, armoury_entity, info_hostage_rescue : dropped (CS-only)
  * info_node grid generated from the walkable area (reachlib BFS from the first player
    spawn) so Sven's monsters can path-find; the engine builds the .nod graph on first load.

Then copies the wads the map references (from the Half-Life install) and the per-map
assets (NAME.cfg, NAME.res, NAME_motd.txt, NAME.as) from --assets into svencoop_addon.

usage:
  python tools/cs2sven.py SRC.bsp NAME [--assets DIR] [--spacing 128] [--dry-run]
         [--hl "C:/.../Half-Life"] [--sven "C:/.../Sven Co-op"] [--tools PATH/to/cs16-bsp-mini/tools]

example:
  python tools/cs2sven.py "C:/.../Half-Life/cstrike/maps/de_dust2.bsp" dust2_pve --assets maps/dust2_pve
"""
import argparse
import os
import shutil
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
STEAM = r'C:\Program Files (x86)\Steam\steamapps\common'

ap = argparse.ArgumentParser()
ap.add_argument('src')
ap.add_argument('name')
ap.add_argument('--assets', default=None, help='dir holding NAME.cfg / NAME.res / NAME_motd.txt / NAME.as')
ap.add_argument('--spacing', type=int, default=128, help='info_node spacing in units')
ap.add_argument('--min-clear', type=int, default=12, help='skip node spots closer than this to a wall')
ap.add_argument('--max-nodes', type=int, default=900)
ap.add_argument('--hl', default=os.path.join(STEAM, 'Half-Life'))
ap.add_argument('--sven', default=os.path.join(STEAM, 'Sven Co-op'))
ap.add_argument('--tools', default=None, help='cs16-bsp-mini/tools dir (bspents.py, reachlib.py)')
ap.add_argument('--res-extra', action='append', default=[],
                help='extra .res file(s) whose lines are appended to NAME.res (e.g. svencoop_addon/cs16_resources.res)')
ap.add_argument('--dry-run', action='store_true')
a = ap.parse_args()

tools = a.tools or os.environ.get('CS16_BSP_MINI_TOOLS') or os.path.normpath(
    os.path.join(HERE, '..', '..', 'cs16-bsp-mini', 'tools'))
if not os.path.exists(os.path.join(tools, 'reachlib.py')):
    sys.exit('cs16-bsp-mini tools not found at %s (use --tools or CS16_BSP_MINI_TOOLS)' % tools)
sys.path.insert(0, tools)
import bspents                      # noqa: E402
from reachlib import Map, origin    # noqa: E402

NAME = a.name
ADDON = os.path.join(a.sven, 'svencoop_addon')
SVEN_SEARCH = [os.path.join(a.sven, d) for d in ('svencoop_addon', 'svencoop_downloads', 'svencoop')]
HL_SEARCH = [os.path.join(a.hl, d) for d in ('cstrike', 'cstrike_downloads', 'valve')]

DROP = {'func_buyzone', 'hostage_entity', 'armoury_entity', 'info_hostage_rescue', 'info_vip_start'}
FLANK_ZONES = {'func_bomb_target', 'func_hostage_rescue', 'func_vip_safetyzone', 'func_escapezone'}


def fmt(e):
    return '{\n' + ''.join('"%s" "%s"\n' % (k, v) for k, v in e.items()) + '}\n'


def vec(p):
    return '%g %g %g' % tuple(p)


# ---------------------------------------------------------------- entities
d, L, ents = bspents.read(a.src)
M = Map(a.src, grid=16, hulls=((1, 36),))

out = []
flank_boxes = []
wads = []
for b in bspents.blocks(ents):
    e = bspents.kv(b)
    cls = e.get('classname')
    if cls == 'worldspawn':
        wads = [os.path.basename(w.replace('\\', '/')) for w in e.get('wad', '').split(';') if w.strip()]
        e['wad'] = ';'.join(wads) + (';' if wads else '')
        e.pop('map_script', None)
    elif cls in DROP:
        continue
    elif cls in FLANK_ZONES:
        if e.get('model', '').startswith('*'):
            flank_boxes.append(M.models[int(e['model'][1:])][:6])
        continue
    elif cls == 'info_player_deathmatch':
        e = {'classname': 'info_target', 'targetname': 'pve_mspawn',
             'origin': e['origin'], 'angles': e.get('angles', '0 0 0')}
    out.append(e)

for (x0, y0, z0, x1, y1, z1) in flank_boxes:
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for dx, dy in ((0, 0), (-96, 0), (96, 0), (0, -96), (0, 96)):
        sp = M.near_spot((cx + dx, cy + dy, z0 + 36))
        if sp:
            out.append({'classname': 'info_target', 'targetname': 'pve_flank',
                        'origin': vec((sp[0] * M.G, sp[1] * M.G, sp[2] + 8))})

# ---------------------------------------------------------------- info_nodes
starts = [origin(e) for e in M.ents if e.get('classname') == 'info_player_start']
if not starts:
    sys.exit('no info_player_start in map')
seen = M.bfs(M.near_spot(starts[0]))
print('walkable spots', len(seen))

buckets = {}
for (cx, cy, fz, h) in seen:
    x, y = cx * M.G, cy * M.G
    key = (int(x // a.spacing), int(y // a.spacing), int(round(fz / 96)))
    buckets.setdefault(key, []).append((x, y, fz))

nodes = []
for key, pts in buckets.items():
    bx = (key[0] + 0.5) * a.spacing
    by = (key[1] + 0.5) * a.spacing
    pts.sort(key=lambda p: (p[0] - bx) ** 2 + (p[1] - by) ** 2)
    best = None
    for p in pts[:8]:
        c = M.clearance((p[0], p[1], p[2] + 36), cap=24)
        if best is None or c > best[0]:
            best = (c, p)
        if c >= 24:
            break
    if best and best[0] >= a.min_clear:
        nodes.append(best[1])
print('info_nodes', len(nodes))
if len(nodes) > a.max_nodes:
    sys.exit('too many nodes (%d) - raise --spacing' % len(nodes))
for p in nodes:
    out.append({'classname': 'info_node', 'origin': vec((p[0], p[1], p[2] + 8))})

print(Counter(e['classname'] for e in out).most_common())
print('wads', wads)
if a.dry_run:
    sys.exit(0)

# ---------------------------------------------------------------- write
maps_dir = os.path.join(ADDON, 'maps')
scripts_dir = os.path.join(ADDON, 'scripts', 'maps')
os.makedirs(maps_dir, exist_ok=True)
os.makedirs(scripts_dir, exist_ok=True)

bsp_out = os.path.join(maps_dir, NAME + '.bsp')
tmp_out = bsp_out + '.tmp'
bspents.write(tmp_out, d, L, ''.join(fmt(e) for e in out))
if os.path.exists(bsp_out) and open(bsp_out, 'rb').read() == open(tmp_out, 'rb').read():
    os.remove(tmp_out)
    print('bsp unchanged - kept (node graph cache stays valid)')
else:
    os.replace(tmp_out, bsp_out)
    for gdir in [os.path.join(s, 'maps', 'graphs') for s in SVEN_SEARCH]:
        for ext in ('.nod', '.nrp'):
            p = os.path.join(gdir, NAME + ext)
            if os.path.exists(p):
                os.remove(p)
    print('bsp written (stale node graphs removed)')

# wads: copy the ones Sven does not already have
for w in wads:
    if any(os.path.exists(os.path.join(s, w)) for s in SVEN_SEARCH):
        continue
    src = next((os.path.join(s, w) for s in HL_SEARCH if os.path.exists(os.path.join(s, w))), None)
    if src is None:
        print('WARNING: wad not found anywhere:', w)
        continue
    shutil.copy(src, os.path.join(ADDON, w))
    print('copied wad', w)

# shared scripts (repo/scripts/maps/** -> svencoop_addon/scripts/maps/**)
shared = os.path.normpath(os.path.join(HERE, '..', 'scripts', 'maps'))
if os.path.isdir(shared):
    shutil.copytree(shared, scripts_dir, dirs_exist_ok=True)
    print('copied shared scripts from', shared)

# per-map assets
if a.assets:
    for fn, dst in ((NAME + '.cfg', maps_dir), (NAME + '.res', maps_dir),
                    (NAME + '_motd.txt', maps_dir), (NAME + '_skl.cfg', maps_dir),
                    (NAME + '.as', scripts_dir)):
        p = os.path.join(a.assets, fn)
        if os.path.exists(p):
            shutil.copy(p, os.path.join(dst, fn))
            print('copied', fn)
    if a.res_extra:
        res_path = os.path.join(maps_dir, NAME + '.res')
        lines = open(res_path, encoding='utf-8').read().splitlines() if os.path.exists(res_path) else []
        for extra in a.res_extra:
            for ln in open(extra, encoding='utf-8').read().splitlines():
                if ln.strip() and not ln.startswith('//') and ln not in lines:
                    lines.append(ln)
        open(res_path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
        print('res merged:', len(lines), 'entries')
print('written to', ADDON)

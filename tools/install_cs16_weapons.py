"""install_cs16_weapons.py - install KernCore's Counter-Strike 1.6 Weapons Project into Sven Co-op.

The pack (https://github.com/KernCore91/-SC-Counter-Strike-1.6-Weapons-Project) is NOT vendored
here: its license forbids repacking. This script clones it next to this repo and copies the
runtime files into svencoop_addon:

  models/cs16/  sound/cs16/  sprites/cs16/  events/  scripts/maps/cs16/  cs16_resources.res

Map scripts then `#include "cs16/weapons"` + `#include "cs16/BuyMenu"` and call RegisterAll()
(see maps/dust2_pve/dust2_pve.as). Credit the authors listed in the pack's cs16_credits.txt.

usage: python tools/install_cs16_weapons.py [--sven "C:/.../Sven Co-op"] [--src DIR]
"""
import argparse
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_URL = 'https://github.com/KernCore91/-SC-Counter-Strike-1.6-Weapons-Project'
STEAM = r'C:\Program Files (x86)\Steam\steamapps\common'

ap = argparse.ArgumentParser()
ap.add_argument('--sven', default=os.path.join(STEAM, 'Sven Co-op'))
ap.add_argument('--src', default=os.path.normpath(os.path.join(HERE, '..', '..', 'sc-cs16-weapons')),
                help='where to clone / find the weapons pack')
a = ap.parse_args()

if not os.path.exists(os.path.join(a.src, 'cs16_resources.res')):
    print('cloning', REPO_URL, '->', a.src)
    subprocess.check_call(['git', 'clone', '--depth', '1', REPO_URL, a.src])

addon = os.path.join(a.sven, 'svencoop_addon')
copied = 0
for sub in ('models/cs16', 'sound/cs16', 'sprites/cs16', 'events', 'scripts/maps/cs16'):
    src = os.path.join(a.src, sub)
    if not os.path.isdir(src):
        sys.exit('missing in pack: ' + sub)
    dst = os.path.join(addon, sub)
    shutil.copytree(src, dst, dirs_exist_ok=True)
    copied += sum(len(f) for _, _, f in os.walk(src))
shutil.copy(os.path.join(a.src, 'cs16_resources.res'), os.path.join(addon, 'cs16_resources.res'))
shutil.copy(os.path.join(a.src, 'cs16_credits.txt'), os.path.join(addon, 'cs16_credits.txt'))
print('installed %d files into %s' % (copied, addon))

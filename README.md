# svencoop-skills-toolkit

Skills and tools for making **Sven Co-op** content, starting with a way to turn any compiled
Counter-Strike 1.6 map into a co-op monster-survival (PVE) map **without decompiling**.

First result: `dust2_pve` — de_dust2 with 10 waves of Half-Life monsters, playable in
Sven Co-op with friends.

## What is in here

| path | what |
|---|---|
| `tools/install_cs16_weapons.py` | installs KernCore's [CS 1.6 Weapons Project](https://github.com/KernCore91/-SC-Counter-Strike-1.6-Weapons-Project) (AK-47, M4A1, AWP, AUG, 30 guns + buy menu) into `svencoop_addon`; not vendored, its license forbids repacking |
| `tools/cs2sven.py` | CS 1.6 `.bsp` → Sven Co-op PVE map: rewrites the entity lump, generates `info_node`s for monster path-finding, copies wads and per-map assets into `svencoop_addon` |
| `scripts/maps/cs_pve/core.as` | the shared game logic: waves, monster AI nudging, CS economy and buy menu; every map script includes it |
| `maps/dust2_pve/` | de_dust2 PVE: wave table (`.as`), `.cfg`, `.res`, motd |
| `maps/bloodstrike_pve/` | cs_bloodstrike PVE: small arena, lighter waves |
| `.claude/skills/cs-map-to-sven-pve/` | Claude Code skill: the whole port workflow, including the headless validation run |
| `docs/notes.md` | Sven Co-op facts and pitfalls learned the hard way (map_script location, node graph, `svends.exe` + SDL3.dll, AngelScript API) |

Depends on [cs16-bsp-mini](https://github.com/kirinchen/cs16-bsp-mini) (`tools/bspents.py`,
`tools/reachlib.py`) for BSP entity editing and the walkability model. Pure Python 3.

## Quick start

```
git clone https://github.com/kirinchen/cs16-bsp-mini ../cs16-bsp-mini
python tools/install_cs16_weapons.py
python tools/cs2sven.py "C:/Program Files (x86)/Steam/steamapps/common/Half-Life/cstrike/maps/de_dust2.bsp" dust2_pve --assets maps/dust2_pve --res-extra "C:/Program Files (x86)/Steam/steamapps/common/Sven Co-op/svencoop_addon/cs16_resources.res"
```

Then in Sven Co-op: `map dust2_pve` (or `map bloodstrike_pve`). The first load builds the node graph (a few minutes for
~700 nodes); it is cached in `svencoop/maps/graphs/`.

## Why Sven Co-op and not CS 1.6

CS 1.6's `mp.dll` has no monster AI at all; PVE there means Metamod + AMX Mod X plugins faking
monsters. Sven Co-op ships 70+ Half-Life monsters, co-op respawn rules, `squadmaker`,
survival mode and AngelScript, and loads GoldSrc BSP v30 directly. A CS map only needs its
wad copied over and its CS-only entities swapped out.

## How `dust2_pve` plays

- players spawn on the CT side; monsters come from the T spawns, later waves also from the bomb sites
- 10 themed waves (headcrabs → zombies → vortigaunts → soldiers → baby gargantua boss → … → gargantua)
- monster count scales with player count; clearing a wave heals everyone and gives a 20 s break
- monsters that never find a player are pushed onto the nearest one; a wave that drags on is force-cleared
- Counter-Strike economy: knife + USP + $800 at start, $300 per kill, a bonus per cleared wave
- buy from the Arms Dealer NPCs in spawn: walk up and press E (no binds needed); one pistol + one primary (buying into a taken slot drops the old gun)
- `bind b ".buy"`, `bind , ".buyammo1"` (primary ammo), `bind . ".buyammo2"` (pistol ammo); or say `buy` in chat
- guns and prices are CS 1.6's (AK-47 $2500, M4A1 $3100, AWP $4750, AUG $3500, ...) via KernCore's weapon pack

Tune constants at the top of `maps/dust2_pve/dust2_pve.as` or the wave table in `BuildWaves()`,
rerun `cs2sven.py` (the BSP is only rewritten when it actually changes, so the node graph cache survives).

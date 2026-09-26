# svencoop-skills-toolkit

Skills and tools for making **Sven Co-op** content, starting with a way to turn any compiled
Counter-Strike 1.6 map into a co-op monster-survival (PVE) map **without decompiling**.

First result: `dust2_pve` — de_dust2 with 10 waves of Half-Life monsters, playable in
Sven Co-op with friends.

## What is in here

| path | what |
|---|---|
| `tools/cs2sven.py` | CS 1.6 `.bsp` → Sven Co-op PVE map: rewrites the entity lump, generates `info_node`s for monster path-finding, copies wads and per-map assets into `svencoop_addon` |
| `maps/dust2_pve/` | the de_dust2 PVE map: wave script (`.as`), `.cfg`, `.res`, motd |
| `.claude/skills/cs-map-to-sven-pve/` | Claude Code skill: the whole port workflow, including the headless validation run |
| `docs/notes.md` | Sven Co-op facts and pitfalls learned the hard way (map_script location, node graph, `svends.exe` + SDL3.dll, AngelScript API) |

Depends on [cs16-bsp-mini](https://github.com/kirinchen/cs16-bsp-mini) (`tools/bspents.py`,
`tools/reachlib.py`) for BSP entity editing and the walkability model. Pure Python 3.

## Quick start

```
git clone https://github.com/kirinchen/cs16-bsp-mini ../cs16-bsp-mini
python tools/cs2sven.py "C:/Program Files (x86)/Steam/steamapps/common/Half-Life/cstrike/maps/de_dust2.bsp" dust2_pve --assets maps/dust2_pve
```

Then in Sven Co-op: `map dust2_pve`. The first load builds the node graph (a few minutes for
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
- loadout: crowbar, Desert Eagle, M16, shotgun, medkit

Tune constants at the top of `maps/dust2_pve/dust2_pve.as` or the wave table in `BuildWaves()`,
rerun `cs2sven.py` (the BSP is only rewritten when it actually changes, so the node graph cache survives).

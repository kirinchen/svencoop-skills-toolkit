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
| `maps/csgodust2_pve/` | gg_csgodust2_mini PVE: CS:GO-style dust2, compact; custom sky copied by the build |
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

Then in Sven Co-op: `map dust2_pve` (or `map bloodstrike_pve`, `map csgodust2_pve`). The first load builds the node graph (a few minutes for
~700 nodes); it is cached in `svencoop/maps/graphs/`.

## Why Sven Co-op and not CS 1.6

CS 1.6's `mp.dll` has no monster AI at all; PVE there means Metamod + AMX Mod X plugins faking
monsters. Sven Co-op ships 70+ Half-Life monsters, co-op respawn rules, `squadmaker`,
survival mode and AngelScript, and loads GoldSrc BSP v30 directly. A CS map only needs its
wad copied over and its CS-only entities swapped out.

## How `dust2_pve` plays

- players spawn on the CT side; monsters come from the T spawns, later waves also from the bomb sites
- 15 themed waves (headcrabs → zombies → vortigaunts → soldiers → baby gargantua → … → gargantua → Race X → twin gargantua finale), counts x3 of the table, bosses single
- spawn points are spread: a point is reused only after 3 s and only when no monster is still standing on it
- every wave lasts 3 min. Clear it early, then press E on the Next Wave console: the sooner, the bigger the speed bonus (up to $1500 each)
- not cleared in 3 min: the leftovers are removed and the next wave gets up to +25% HP and damage (by the uncleared fraction)
- team lives: 20 deaths in total = defeat; dying also loses your guns
- monster count scales with player count; clearing a wave heals everyone and pays a bonus
- monsters that never find a player are pushed onto the nearest one
- Counter-Strike economy: knife + USP + $800 at start, $300 per kill, a bonus per cleared wave
- buy from the Arms Dealer NPCs in spawn: walk up and press E (no binds needed); one pistol + one primary (buying into a taken slot drops the old gun)
- `bind b ".buy"`, `bind , ".buyammo1"` (primary ammo), `bind . ".buyammo2"` (pistol ammo); or say `buy` in chat
- guns and prices are CS 1.6's (AK-47 $2500, M4A1 $3100, AWP $4750, AUG $3500, ...) via KernCore's weapon pack; ammo and Kevlar cost 4x CS
- Equipment menu upgrades for the gun you are holding, 3 levels each, priced separately: magazine +20% per level ($1000 x level), +2 spare magazines of reserve per level ($800 x level)

Tune constants at the top of `maps/dust2_pve/dust2_pve.as` or the wave table in `BuildWaves()`,
rerun `cs2sven.py` (the BSP is only rewritten when it actually changes, so the node graph cache survives).

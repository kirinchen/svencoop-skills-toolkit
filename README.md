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
| `maps/assault_pve/` | cs_assault PVE: players hold the warehouse (T side, `--player-side t`), monsters come from outside |
| `maps/italy_pve/` | cs_italy PVE: players start at the T house (`--player-side t`) |
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

`--player-side t` puts the players on the T spawns instead of CT (used for the hostage maps).

Then in Sven Co-op: `map dust2_pve` (or `bloodstrike_pve`, `csgodust2_pve`, `assault_pve`, `italy_pve`). The first load builds the node graph (a few minutes for
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
- hostage maps (cs_): the hostages stay as NPCs (400 HP, they flee and can follow you); a third of the monsters hunt them, all hostages dead = defeat
- monster count scales with player count; clearing a wave heals everyone and pays a bonus
- monsters that never find a player are pushed onto the nearest one
- Counter-Strike economy: knife + USP + $800 at start, $300 per kill, a bonus per cleared wave
- buy from the Arms Dealer NPC in spawn: walk up and press E (no binds needed)
- one gun per category: [2] pistol or shotgun, [3] SMG, [4] rifle/sniper, [5] machine gun (buying into a taken category drops the old gun; picking up a second one drops it too)
- buying a gun you already own upgrades it (same price): +2 spare mags of reserve, then magazine +20%, alternating, 5 levels each
- `bind b ".buy"`, `bind , ".buyammo1"` (primary ammo), `bind . ".buyammo2"` (pistol ammo); or say `buy` in chat
- guns and prices are CS 1.6's (AK-47 $2500, M4A1 $3100, AWP $4750, AUG $3500, ...) via KernCore's weapon pack; ammo and Kevlar cost 4x CS
- ammo is bought per magazine from the Ammo menu (pick the category): price = rounds in the magazine x per-round price of that ammo type (CS magazine price x4 / rounds); an upgraded, bigger magazine costs proportionally more

Tune constants at the top of `maps/dust2_pve/dust2_pve.as` or the wave table in `BuildWaves()`,
rerun `cs2sven.py` (the BSP is only rewritten when it actually changes, so the node graph cache survives).

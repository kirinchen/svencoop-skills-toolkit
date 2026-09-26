---
name: cs-map-to-sven-pve
description: Port a compiled Counter-Strike 1.6 / GoldSrc map (.bsp) into Sven Co-op as a co-op monster-survival (PVE) map, with monster path-finding nodes and an AngelScript wave script. Use when the user wants to fight monsters / zombies / NPCs on a CS map, asks to play a CS map in Sven Co-op, or wants a wave / horde / survival mode on an existing GoldSrc map.
---

# cs-map-to-sven-pve

Everything is Python 3 + the Sven Co-op install. Needs `cs16-bsp-mini/tools` next to this
repo (or `--tools PATH`). Read `docs/notes.md` first if anything Sven-specific is unclear.

## Workflow

1. **Decide the target**: PVE with real monster AI means Sven Co-op, not CS 1.6
   (CS has no monster AI; it would need Metamod/AMXX plugins with fake monsters). Say so.

2. **Check for prior art** (scmapdb.wikidot.com, gamebanana Sven Co-op maps). Most CS ports
   there are PVP/objective conversions, not monster waves.

3. **Inspect the source map**
   ```
   python ../cs16-bsp-mini/tools/bspents.py MAP.bsp dump
   ```
   Note: spawn classes (`info_player_start` = CT, `info_player_deathmatch` = T), objective
   zones (`func_bomb_target`, `func_hostage_rescue`), wads referenced by worldspawn.

4. **Create the per-map assets** in `maps/NAME/` (copy `maps/dust2_pve/` and rename):
   - `NAME.cfg` — must contain `map_script NAME`, the loadout and cvars
   - `NAME.as` — wave script; edit `BuildWaves()` and the constants at the top
   - `NAME.res` — wads the clients must download
   - `NAME_motd.txt`

5. **Build**
   ```
   python tools/cs2sven.py MAP.bsp NAME --assets maps/NAME --dry-run   # check counts first
   python tools/cs2sven.py MAP.bsp NAME --assets maps/NAME
   ```
   Keep `info_nodes` under ~1000; raise `--spacing` if needed. Output lands in
   `Sven Co-op/svencoop_addon/`.

6. **Validate headless** (no need to open the game). Steam must be running.
   ```
   $env:PATH = "C:\Program Files (x86)\Steam;" + $env:PATH
   # start svends.exe -console -game svencoop +sv_lan 1 +maxplayers 4 +map NAME
   # with redirected stdin/stdout, wait ~60 s (or ~5 min on first load for the node graph),
   # write "quit" to stdin, then read stdout
   ```
   Must see: `Map script 'NAME' loaded`, `Map script compilation succeeded`,
   `[NAME] spawns: main=N flank=M`, and `*Graph Loaded!` (or the node-graph build message).
   Compile errors are also in `svencoop/logs/Angelscript/AS_server_*.log`.
   Never `taskkill` a run while another wrapper is still armed — it kills the wrong server.

7. **Deliver**: tell the user `map NAME` in Sven Co-op, what the first load does (node graph
   build), and what has NOT been play-tested (monster movement, balance, flank spawn distance).

## Script conventions (`NAME.as`)
- Spawn markers: `info_target` with targetname `pve_mspawn` (main) and `pve_flank` (later waves).
- Spawn with `g_EntityFuncs.Create(cls, pos, ang, false, null)` + `DispatchSpawn`, then
  `SetClassification(CLASS_ALIEN_MILITARY)`, set `m_hEnemy` to a player and
  `SetConditions(bits_COND_NEW_ENEMY)`.
- Track monsters with `array<EHandle>`; a wave ends when none `IsAlive()`.
- Always add a wave timeout and a straggler relocation so the mode cannot soft-lock.
- No `ServerCommand` in the API: restart via `trigger_changelevel` / `game_end` + `Use()`.

# Sven Co-op notes (things that cost time)

## Map loading
- Sven loads GoldSrc BSP v30 directly. CS maps work; unknown classes (`func_buyzone`,
  `func_bomb_target`) are just logged and dropped, but cleaner to remove them.
- `worldspawn` `wad` paths like `\sierra\half-life\valve\cs_dust.wad` are fine: the engine only
  uses the basename and searches `svencoop_addon`, `svencoop_downloads`, `svencoop` (in that order).
  Sven does NOT ship `cs_dust.wad`; copy it from `Half-Life/cstrike/`.
- Custom content goes in `svencoop_addon/` (maps/, scripts/maps/, wads at the root).

## Map script
- The map script is declared in the map's **`.cfg`**: `map_script NAME` → `scripts/maps/NAME.as`.
  A `map_script` key on worldspawn does nothing (the FGD has no such key).
- Compile results go to the console and to `svencoop/logs/Angelscript/AS_server_YYYY-MM-DD.log`.
- Player spawn points in co-op: both `info_player_start` and `info_player_deathmatch` are used.
  To keep players on one side, convert the other side's spawns to something else.

## Monster path-finding
- Sven still uses the Half-Life node graph. A map without `info_node`s = monsters that only walk
  straight at what they can see.
- Node graph is built on first load (`Queue full! Building the node graph`) and saved as
  `svencoop/maps/graphs/NAME.nod` (+ `.nrp` report). ~700 nodes ≈ 4 minutes on a dedicated
  server. It is rebuilt when the BSP is newer than the `.nod`.
- Nodes dropped 8 units above the floor are fine; the engine drops them to the floor.
- 128-unit spacing on de_dust2 → 712 nodes. 96 → 1110 (too many; keep under ~1000).

## AngelScript API (5.0.1.8, AS 2.36.1)
- Docs: https://baso88.github.io/SC_AngelScript/docs/  (class pages are `docs/<Class>.htm`).
- `g_EntityFuncs.Create(cls, origin, angles, fCreateAndDontSpawn, owner)`; then
  `g_EntityFuncs.DispatchSpawn(e.edict())`.
- `g_EntityFuncs.CreateEntity(cls, dictionary@ keys, bool spawn)` for keyvalue-driven creation.
- `CBaseMonster`: `m_hEnemy` (EHandle, writable), `SetConditions(bits_COND_NEW_ENEMY)`,
  `SetState(MONSTERSTATE_COMBAT)`, `MyMonsterPointer()` from CBaseEntity.
- `e.SetClassification(CLASS_ALIEN_MILITARY)` stops monsters fighting each other.
- There is **no** `g_EngineFuncs.ServerCommand`. To restart / end the map create a
  `trigger_changelevel` (key `map`) or `game_end` and `.Use(null, null, USE_ON, 0)`.
- Precache spawned classes in `MapInit()` with `g_Game.PrecacheOther(cls)`.
- `g_Scheduler.SetInterval("Func", secs, g_Scheduler.REPEAT_INFINITE_TIMES)`.
- `HUDTextParams` fields: channel, x, y, effect, r1 g1 b1 a1, r2 g2 b2 a2, fadeinTime,
  fadeoutTime, holdTime, fxTime. `g_PlayerFuncs.HudMessageAll(params, text)`.

## Headless validation with svends.exe
- `svends.exe` needs the Steam client running **and** `SDL3.dll` from the Steam root on PATH,
  otherwise: `Assertion Failed: Failed to load "SDL3.dll"` / `Unable to initialize Steam`.
- `-condebug` did not produce `qconsole.log`; capture stdout instead (`-console`) and send
  `quit` on stdin for a clean exit so buffers flush. See the skill for the PowerShell runner.
- Watch for: `Map script 'NAME' loaded`, `Map script compilation succeeded`, `*Graph Loaded!`.

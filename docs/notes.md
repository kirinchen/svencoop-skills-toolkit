# Sven Co-op notes (things that cost time)

## Map loading
- Sven loads GoldSrc BSP v30 directly. CS maps work; unknown classes (`func_buyzone`,
  `func_bomb_target`) are just logged and dropped, but cleaner to remove them.
- `worldspawn` `wad` paths like `\sierra\half-life\valve\cs_dust.wad` are fine: the engine only
  uses the basename and searches `svencoop_addon`, `svencoop_downloads`, `svencoop` (in that order).
  Sven does NOT ship `cs_dust.wad`; copy it from `Half-Life/cstrike/`.
- Custom content goes in `svencoop_addon/` (maps/, scripts/maps/, wads at the root).

- Custom skies: `worldspawn` `skyname` needs `gfx/env/<sky>{bk,dn,ft,lf,rt,up}.tga`; cs2sven.py copies
  them from the Half-Life dirs into `svencoop_addon` and they must be listed in the map `.res`.

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

## CS 1.6 weapons in Sven
- KernCore's CS 1.6 Weapons Project is a plugin-or-map_script pack; its `cs16_register.as`
  defines `MapInit()` itself, so it cannot be a second `map_script`. From your own map script:
  `#include "cs16/weapons"`, `#include "cs16/BuyMenu"`, set the `CS16_*::POSITION` slots,
  `RegisterAll()`, add `BuyMenu::BuyableItem`s to `g_CS16Menu`, then `BuyMenu::MoneyInit()`.
- Money lives in `BuyMenu::BuyPoints[steamid]`; `BuyMenu::BuyMenuCVARS().PlayerID(p)` gives the
  key and `ShowPointsSprite(p)` refreshes the HUD. Default: $10 per score, max $16000.
- Loadout lines in the map cfg accept the custom classnames (`weapon_m4a1`, `ammo_m4a1 3`).
- Append `cs16_resources.res` to the map `.res` so clients download models/sounds.
- We do NOT use the pack's BuyMenu (no buy zone / slot rules); dust2_pve.as has its own CS-rules
  buy system: `CTextMenu` + `CClientCommand` (`.buy`, `.buyammo1`, `.buyammo2`), buy zone = box
  around `info_player_start`, `HasNamedPlayerItem` / `DropItem` for the one-pistol-one-primary rule,
  kill credit from `pev.dmg_inflictor` (bullets: the player; grenades: inflictor's owner).
- Buy stations without touching the BSP: `core.as` spawns `monster_generic` NPCs (disableai 1, takedamage 0, idle1 via LookupSequence)
  (`models/hgrunt_opfor.mdl`) + an `env_sprite` glow at 3 spread-out `info_player_start`s in
  `MapActivate`, and a `Hooks::Player::PlayerUse` hook (`m_afButtonPressed & IN_USE`, set
  `uiFlags |= PlrHook_SkipUse`) opens the menu when the player is within 128 units of a crate.
- `Hooks::Player::PlayerTakeDamage(DamageInfo@)` works for scaling monster damage
  (`info.pAttacker.IsMonster()`, `info.flDamage *= mult`). `Hooks::Player::PlayerKilled(CBasePlayer@,
  CBaseEntity@, int)` + `RemoveAllItems(false, false)` + removing nearby `weaponbox` = no guns on death.
- `pev.netname` is `string_t`: wrap in `string(...)` before concatenating.
- Servers cannot push key binds (`cl_filterstuffcmd 1` is the client default): binds go in the
  client's autoexec.cfg / MOTD.

## Headless validation with svends.exe
- `svends.exe` needs the Steam client running **and** `SDL3.dll` from the Steam root on PATH,
  otherwise: `Assertion Failed: Failed to load "SDL3.dll"` / `Unable to initialize Steam`.
- `-condebug` did not produce `qconsole.log`; capture stdout instead (`-console`) and send
  `quit` on stdin for a clean exit so buffers flush. See the skill for the PowerShell runner.
- Starting a new svends right after a previous one quit can fail with `Couldn't allocate
  dedicated server IP port 27015` or the SDL3/Steam error even with PATH set: the old process
  is still shutting down. Wait ~20 s and retry.
- Watch for: `Map script 'NAME' loaded`, `Map script compilation succeeded`, `*Graph Loaded!`.

/*
 * bloodstrike_pve.as - cs_bloodstrike monster survival (small arena)
 * Generic logic lives in scripts/maps/cs_pve/core.as; this file only defines the waves.
 */
#include "cs_pve/core"

void MapInit()     { PveMapInit(); }
void MapActivate() { PveMapActivate(); }

void BuildWaves()
{
    WaveDef@ w;

    @w = WaveDef( "Wave 1 - Infestation", 1.0f, false );
    w.spawns.insertLast( SpawnDef( "monster_headcrab", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_zombie", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 2 - The Dead Walk", 1.0f, false );
    w.spawns.insertLast( SpawnDef( "monster_zombie", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_houndeye", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 3 - Vortigaunt Raid", 1.1f, false );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_houndeye", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_zombie", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 4 - Black Ops Sweep", 1.0f, true );
    w.spawns.insertLast( SpawnDef( "monster_human_grunt", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 5 - BOSS: Baby Gargantua", 1.2f, false );
    w.spawns.insertLast( SpawnDef( "monster_babygarg", 1 ) );
    w.spawns.insertLast( SpawnDef( "monster_zombie", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_headcrab", 6 ) );
    AddWave( w );

    @w = WaveDef( "Wave 6 - Xen Fauna", 1.2f, true );
    w.spawns.insertLast( SpawnDef( "monster_bullchicken", 5 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_grunt", 3 ) );
    w.spawns.insertLast( SpawnDef( "monster_houndeye", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 7 - Rotting Squad", 1.3f, true );
    w.spawns.insertLast( SpawnDef( "monster_zombie_soldier", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_gonome", 3 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 8 - Assassins", 1.2f, true );
    w.spawns.insertLast( SpawnDef( "monster_human_assassin", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_human_grunt", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_hwgrunt", 1 ) );
    AddWave( w );

    @w = WaveDef( "Wave 9 - Race X", 1.3f, true );
    w.spawns.insertLast( SpawnDef( "monster_pitdrone", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_shocktrooper", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_voltigore", 2 ) );
    AddWave( w );

    @w = WaveDef( "Wave 10 - FINAL BOSS: Gargantua", 1.4f, true );
    w.spawns.insertLast( SpawnDef( "monster_gargantua", 1 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_grunt", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 4 ) );
    AddWave( w );
}

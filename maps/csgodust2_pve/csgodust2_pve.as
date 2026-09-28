/*
 * csgodust2_pve.as - gg_csgodust2_mini monster survival (CS:GO dust2, mini)
 * Generic logic lives in scripts/maps/cs_pve/core.as; this file only defines the waves.
 */
#include "cs_pve/core"

void MapInit()     { PveMapInit(); }
void MapActivate() { PveMapActivate(); }

void BuildWaves()
{
    WaveDef@ w;

    @w = WaveDef( "Wave 1 - Infestation", 1.0f, false );
    w.spawns.insertLast( SpawnDef( "monster_headcrab", 8 ) );
    w.spawns.insertLast( SpawnDef( "monster_zombie", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 2 - The Dead Walk", 1.0f, false );
    w.spawns.insertLast( SpawnDef( "monster_zombie", 8 ) );
    w.spawns.insertLast( SpawnDef( "monster_houndeye", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 3 - Vortigaunt Raid", 1.1f, false );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_houndeye", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_zombie", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 4 - Black Ops Sweep", 1.0f, true );
    w.spawns.insertLast( SpawnDef( "monster_human_grunt", 8 ) );
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
    w.spawns.insertLast( SpawnDef( "monster_zombie_soldier", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_gonome", 3 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 8 - Assassins", 1.2f, true );
    w.spawns.insertLast( SpawnDef( "monster_human_assassin", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_human_grunt", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_hwgrunt", 1 ) );
    AddWave( w );

    @w = WaveDef( "Wave 9 - Race X", 1.3f, true );
    w.spawns.insertLast( SpawnDef( "monster_pitdrone", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_shocktrooper", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_voltigore", 2 ) );
    AddWave( w );

    @w = WaveDef( "Wave 10 - BOSS: Gargantua", 1.4f, true );
    w.spawns.insertLast( SpawnDef( "monster_gargantua", 1 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_grunt", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 6 ) );
    AddWave( w );

    @w = WaveDef( "Wave 11 - Grunt Battalion", 1.3f, true );
    w.spawns.insertLast( SpawnDef( "monster_human_grunt", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_hwgrunt", 1 ) );
    w.spawns.insertLast( SpawnDef( "monster_robogrunt", 2 ) );
    AddWave( w );

    @w = WaveDef( "Wave 12 - Xen Swarm", 1.35f, true );
    w.spawns.insertLast( SpawnDef( "monster_alien_grunt", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 5 ) );
    w.spawns.insertLast( SpawnDef( "monster_bullchicken", 3 ) );
    w.spawns.insertLast( SpawnDef( "monster_houndeye", 4 ) );
    AddWave( w );

    @w = WaveDef( "Wave 13 - Race X Assault", 1.4f, true );
    w.spawns.insertLast( SpawnDef( "monster_shocktrooper", 5 ) );
    w.spawns.insertLast( SpawnDef( "monster_pitdrone", 5 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_voltigore", 2 ) );
    AddWave( w );

    @w = WaveDef( "Wave 14 - Undead Horde", 1.4f, true );
    w.spawns.insertLast( SpawnDef( "monster_zombie_soldier", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_gonome", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_zombie", 6 ) );
    w.spawns.insertLast( SpawnDef( "monster_babygarg", 1 ) );
    AddWave( w );

    @w = WaveDef( "Wave 15 - FINAL: Twin Gargantua", 1.5f, true );
    w.spawns.insertLast( SpawnDef( "monster_gargantua", 1 ) );
    w.spawns.insertLast( SpawnDef( "monster_babygarg", 1 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_grunt", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_shocktrooper", 3 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 5 ) );
    AddWave( w );
}

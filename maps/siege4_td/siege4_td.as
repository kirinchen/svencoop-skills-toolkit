/*
 * siege4_td.as - siege4 tower defence: a self-made four-lane map (X Hero Siege style), base and
 * both gold mines in the middle, monsters walk in from the four ends.
 * Rules: scripts/maps/cs_td/core.as + scripts/maps/cs_td/td.as. Same 15 waves as dust2_td, but
 * monster HP grows by the same factor every wave (towers are strong, so monsters get tougher
 * steadily): wave n HP = HP_BASE * HP_GROWTH^(n-1)  (1.5x on wave 1 ... 7.3x on wave 15).
 */
#include "cs_td/core"
#include "cs_td/td"

const float HP_BASE   = 1.5f;
const float HP_GROWTH = 1.12f;

// gold mines: the map has no pve_flank points, so these are used (plaza NE and SW corners)
Vector TdMineA() { return Vector( 448, 448, 0 ); }
Vector TdMineB() { return Vector( -448, -448, 0 ); }

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

    // the table's per-wave multipliers are replaced by one steady curve
    float m = HP_BASE;
    for( uint i = 0; i < g_Waves.length(); ++i )
    {
        g_Waves[i].healthMult = m;
        m *= HP_GROWTH;
    }
}

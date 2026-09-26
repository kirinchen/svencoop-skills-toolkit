/*
 * dust2_pve.as - wave-based monster survival on de_dust2 (Sven Co-op 5.x)
 *
 * Built by C:\Users\DDT\Desktop\projects\dust2-pve\build.py
 *
 * - players spawn on the CT side (info_player_start)
 * - monsters come from the T spawns (info_target "pve_mspawn") and, on later waves,
 *   from the bomb sites (info_target "pve_flank")
 * - a wave is cleared when every monster of it is dead; players get healed and a break
 * - monsters that never find a player are pushed onto the nearest player, and a wave
 *   that drags on too long is force-cleared so the game can never soft-lock
 */

const float THINK_INTERVAL   = 1.0f;
const float START_COUNTDOWN  = 30.0f;   // seconds after the first player spawns
const float WAVE_BREAK       = 20.0f;   // seconds between waves
const float WAVE_TIMEOUT     = 420.0f;  // force-clear a wave after this long
const int   MAX_ALIVE        = 22;      // concurrent monsters cap
const int   SPAWN_PER_TICK   = 3;
const float SPAWN_MIN_DIST   = 450.0f;  // never spawn this close to a player
const int   STRAGGLER_SECS   = 40;      // no enemy for this long -> relocate near players
const float VICTORY_RESTART  = 25.0f;

enum PveState
{
    PVE_WAITING,
    PVE_COUNTDOWN,
    PVE_WAVE,
    PVE_BREAK,
    PVE_VICTORY
}

class SpawnDef
{
    string cls;
    int count;
    SpawnDef( const string& in c, int n ) { cls = c; count = n; }
}

class WaveDef
{
    string title;
    float healthMult;
    bool flank;
    array<SpawnDef@> spawns;
    WaveDef( const string& in t, float hm, bool f ) { title = t; healthMult = hm; flank = f; }
}

array<WaveDef@> g_Waves;
array<Vector>   g_MainSpawns;
array<Vector>   g_FlankSpawns;

PveState g_State = PVE_WAITING;
float    g_Timer = 0.0f;
int      g_WaveIdx = -1;          // index into g_Waves
float    g_WaveStart = 0.0f;
array<string>  g_Queue;           // monsters still to spawn this wave
array<EHandle> g_Alive;           // monsters spawned this wave
array<int>     g_IdleSecs;        // parallel to g_Alive
int      g_WaveTotal = 0;

HUDTextParams g_HudBig;
HUDTextParams g_HudStatus;

// ------------------------------------------------------------------ waves

void AddWave( WaveDef@ w ) { g_Waves.insertLast( w ); }

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

    @w = WaveDef( "Wave 10 - FINAL BOSS: Gargantua", 1.4f, true );
    w.spawns.insertLast( SpawnDef( "monster_gargantua", 1 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_grunt", 4 ) );
    w.spawns.insertLast( SpawnDef( "monster_alien_slave", 6 ) );
    AddWave( w );
}

// ------------------------------------------------------------------ lifecycle

void MapInit()
{
    BuildWaves();
    for( uint i = 0; i < g_Waves.length(); ++i )
        for( uint j = 0; j < g_Waves[i].spawns.length(); ++j )
            g_Game.PrecacheOther( g_Waves[i].spawns[j].cls );

    g_HudBig.channel = 4;
    g_HudBig.x = -1; g_HudBig.y = 0.25;
    g_HudBig.effect = 2;
    g_HudBig.r1 = 255; g_HudBig.g1 = 180; g_HudBig.b1 = 40; g_HudBig.a1 = 255;
    g_HudBig.r2 = 255; g_HudBig.g2 = 255; g_HudBig.b2 = 255; g_HudBig.a2 = 255;
    g_HudBig.fadeinTime = 0.05; g_HudBig.fadeoutTime = 1.0; g_HudBig.holdTime = 4.0; g_HudBig.fxTime = 0.5;

    g_HudStatus.channel = 5;
    g_HudStatus.x = 0.02; g_HudStatus.y = 0.85;
    g_HudStatus.effect = 0;
    g_HudStatus.r1 = 200; g_HudStatus.g1 = 220; g_HudStatus.b1 = 255; g_HudStatus.a1 = 255;
    g_HudStatus.fadeinTime = 0.0; g_HudStatus.fadeoutTime = 0.2; g_HudStatus.holdTime = 1.2; g_HudStatus.fxTime = 0.0;

    g_Hooks.RegisterHook( Hooks::Player::PlayerSpawn, @OnPlayerSpawn );
    g_Scheduler.SetInterval( "PveThink", THINK_INTERVAL, g_Scheduler.REPEAT_INFINITE_TIMES );
}

void MapActivate()
{
    CBaseEntity@ e = null;
    while( ( @e = g_EntityFuncs.FindEntityByTargetname( e, "pve_mspawn" ) ) !is null )
        g_MainSpawns.insertLast( e.pev.origin );
    @e = null;
    while( ( @e = g_EntityFuncs.FindEntityByTargetname( e, "pve_flank" ) ) !is null )
        g_FlankSpawns.insertLast( e.pev.origin );
    g_Game.AlertMessage( at_console, "[dust2_pve] spawns: main=%1 flank=%2 waves=%3\n",
        g_MainSpawns.length(), g_FlankSpawns.length(), g_Waves.length() );
}

HookReturnCode OnPlayerSpawn( CBasePlayer@ pPlayer )
{
    if( g_State == PVE_WAITING )
    {
        g_State = PVE_COUNTDOWN;
        g_Timer = START_COUNTDOWN;
        g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] First wave in " + int( START_COUNTDOWN ) + " seconds. Hold the CT side!\n" );
    }
    return HOOK_CONTINUE;
}

// ------------------------------------------------------------------ helpers

int CountPlayers( bool aliveOnly )
{
    int n = 0;
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p is null || !p.IsConnected() ) continue;
        if( aliveOnly && !p.IsAlive() ) continue;
        ++n;
    }
    return n;
}

CBasePlayer@ NearestPlayer( const Vector& in pos, float& out dist )
{
    CBasePlayer@ best = null;
    dist = 999999.0f;
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p is null || !p.IsConnected() || !p.IsAlive() ) continue;
        float d = ( p.pev.origin - pos ).Length();
        if( d < dist ) { dist = d; @best = p; }
    }
    return best;
}

CBasePlayer@ RandomAlivePlayer()
{
    array<CBasePlayer@> ps;
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p !is null && p.IsConnected() && p.IsAlive() ) ps.insertLast( p );
    }
    if( ps.length() == 0 ) return null;
    return ps[ Math.RandomLong( 0, ps.length() - 1 ) ];
}

// pick a spawn point that is not right next to a player
bool PickSpawn( bool allowFlank, Vector& out pos )
{
    array<Vector> pool;
    if( allowFlank && g_FlankSpawns.length() > 0 && Math.RandomLong( 0, 99 ) < 35 )
        pool = g_FlankSpawns;
    else
        pool = g_MainSpawns;
    if( pool.length() == 0 ) return false;

    for( int attempt = 0; attempt < 12; ++attempt )
    {
        Vector cand = pool[ Math.RandomLong( 0, pool.length() - 1 ) ];
        float d;
        NearestPlayer( cand, d );
        if( d >= SPAWN_MIN_DIST ) { pos = cand; return true; }
    }
    pos = pool[ Math.RandomLong( 0, pool.length() - 1 ) ];
    return true;
}

// a spot in the pools closest to a given player (used to relocate stragglers)
Vector SpawnNearPlayer( CBasePlayer@ p )
{
    Vector best = g_MainSpawns.length() > 0 ? g_MainSpawns[0] : p.pev.origin;
    float bd = 999999.0f;
    array<Vector> all = g_MainSpawns;
    for( uint i = 0; i < g_FlankSpawns.length(); ++i ) all.insertLast( g_FlankSpawns[i] );
    for( uint i = 0; i < all.length(); ++i )
    {
        float d = ( all[i] - p.pev.origin ).Length();
        if( d < SPAWN_MIN_DIST ) continue;
        if( d < bd ) { bd = d; best = all[i]; }
    }
    return best;
}

void HealAll()
{
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p is null || !p.IsConnected() || !p.IsAlive() ) continue;
        p.pev.health = p.pev.max_health;
        if( p.pev.armorvalue < 50 ) p.pev.armorvalue = 50;
    }
}

void Big( const string& in msg )
{
    g_PlayerFuncs.HudMessageAll( g_HudBig, msg );
    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] " + msg + "\n" );
}

// ------------------------------------------------------------------ waves

void StartWave( int idx )
{
    g_WaveIdx = idx;
    WaveDef@ w = g_Waves[idx];
    int players = CountPlayers( false );
    if( players < 1 ) players = 1;
    float scale = 1.0f + 0.35f * float( players - 1 );   // 1 player = x1, 4 players = x2.05

    g_Queue.resize( 0 );
    g_Alive.resize( 0 );
    g_IdleSecs.resize( 0 );
    for( uint i = 0; i < w.spawns.length(); ++i )
    {
        int n = int( float( w.spawns[i].count ) * scale + 0.5f );
        if( w.spawns[i].count == 1 ) n = 1;                 // bosses stay single
        for( int k = 0; k < n; ++k ) g_Queue.insertLast( w.spawns[i].cls );
    }
    // shuffle so types are mixed
    for( uint i = g_Queue.length(); i > 1; --i )
    {
        uint j = Math.RandomLong( 0, i - 1 );
        string tmp = g_Queue[i - 1]; g_Queue[i - 1] = g_Queue[j]; g_Queue[j] = tmp;
    }
    g_WaveTotal = int( g_Queue.length() );
    g_WaveStart = g_Engine.time;
    g_State = PVE_WAVE;
    Big( w.title + "  (" + g_WaveTotal + " monsters)" );
}

void SpawnOne( const string& in cls, float healthMult, bool allowFlank )
{
    Vector pos;
    if( !PickSpawn( allowFlank, pos ) ) return;
    pos.z += 8.0f;
    Vector ang( 0, Math.RandomFloat( 0, 360 ), 0 );

    CBaseEntity@ e = g_EntityFuncs.Create( cls, pos, ang, false, null );
    if( e is null ) return;
    g_EntityFuncs.DispatchSpawn( e.edict() );

    e.SetClassification( CLASS_ALIEN_MILITARY );     // no in-fighting; everyone hates players
    e.pev.health = e.pev.health * healthMult;
    e.pev.max_health = e.pev.health;

    // point it at a player straight away
    CBaseMonster@ m = e.MyMonsterPointer();
    if( m !is null )
    {
        CBasePlayer@ p = RandomAlivePlayer();
        if( p !is null )
        {
            m.m_hEnemy = EHandle( p );
            m.SetConditions( bits_COND_NEW_ENEMY );
        }
    }
    g_Alive.insertLast( EHandle( e ) );
    g_IdleSecs.insertLast( 0 );
}

int PruneAndCountAlive()
{
    int alive = 0;
    for( uint i = 0; i < g_Alive.length(); )
    {
        CBaseEntity@ e = g_Alive[i].GetEntity();
        if( e is null || !e.IsAlive() )
        {
            g_Alive.removeAt( i );
            g_IdleSecs.removeAt( i );
            continue;
        }
        ++alive;
        ++i;
    }
    return alive;
}

void NudgeMonsters()
{
    for( uint i = 0; i < g_Alive.length(); ++i )
    {
        CBaseEntity@ e = g_Alive[i].GetEntity();
        if( e is null ) continue;
        CBaseMonster@ m = e.MyMonsterPointer();
        if( m is null ) continue;

        bool hasEnemy = m.m_hEnemy.IsValid();
        if( hasEnemy )
        {
            CBaseEntity@ en = m.m_hEnemy.GetEntity();
            if( en is null || !en.IsAlive() ) hasEnemy = false;
        }
        if( hasEnemy ) { g_IdleSecs[i] = 0; continue; }

        g_IdleSecs[i] = g_IdleSecs[i] + 1;
        float d;
        CBasePlayer@ p = NearestPlayer( e.pev.origin, d );
        if( p is null ) continue;

        if( g_IdleSecs[i] >= STRAGGLER_SECS && d > 1200.0f )
        {
            // lost somewhere far away: bring it back into the fight
            Vector np = SpawnNearPlayer( p );
            np.z += 8.0f;
            g_EntityFuncs.SetOrigin( e, np );
            g_IdleSecs[i] = 0;
        }
        m.m_hEnemy = EHandle( p );
        m.SetConditions( bits_COND_NEW_ENEMY );
    }
}

void ClearRemaining()
{
    for( uint i = 0; i < g_Alive.length(); ++i )
    {
        CBaseEntity@ e = g_Alive[i].GetEntity();
        if( e !is null ) g_EntityFuncs.Remove( e );
    }
    g_Alive.resize( 0 );
    g_IdleSecs.resize( 0 );
    g_Queue.resize( 0 );
}

void WaveCleared()
{
    HealAll();
    bool last = ( g_WaveIdx + 1 >= int( g_Waves.length() ) );
    if( last )
    {
        g_State = PVE_VICTORY;
        g_Timer = VICTORY_RESTART;
        Big( "VICTORY! de_dust2 is clear. Restarting in " + int( VICTORY_RESTART ) + "s" );
    }
    else
    {
        g_State = PVE_BREAK;
        g_Timer = WAVE_BREAK;
        Big( "Wave cleared! Everyone healed. Next wave in " + int( WAVE_BREAK ) + "s" );
    }
}

void RestartMap()
{
    // reload this same map; fall back to a normal map end (next map in cycle)
    dictionary keys;
    keys["map"] = string( g_Engine.mapname );
    keys["targetname"] = "pve_restart";
    CBaseEntity@ pChange = g_EntityFuncs.CreateEntity( "trigger_changelevel", keys, true );
    if( pChange !is null )
    {
        pChange.Use( null, null, USE_ON, 0 );
        return;
    }
    CBaseEntity@ pEnd = g_EntityFuncs.CreateEntity( "game_end", null, true );
    if( pEnd !is null )
        pEnd.Use( null, null, USE_ON, 0 );
}

// ------------------------------------------------------------------ main loop

void PveThink()
{
    if( g_State == PVE_WAITING )
        return;

    if( g_State == PVE_COUNTDOWN || g_State == PVE_BREAK )
    {
        g_Timer -= THINK_INTERVAL;
        string lead = ( g_State == PVE_COUNTDOWN ) ? "Get ready - first wave in " : "Next wave in ";
        g_PlayerFuncs.HudMessageAll( g_HudStatus, lead + int( g_Timer + 0.5f ) + "s" );
        if( g_Timer <= 0.0f )
            StartWave( g_WaveIdx + 1 );
        return;
    }

    if( g_State == PVE_VICTORY )
    {
        g_Timer -= THINK_INTERVAL;
        if( g_Timer <= 0.0f )
        {
            g_State = PVE_WAITING;
            RestartMap();
        }
        return;
    }

    // PVE_WAVE
    WaveDef@ w = g_Waves[g_WaveIdx];
    int alive = PruneAndCountAlive();

    int spawned = 0;
    while( g_Queue.length() > 0 && alive < MAX_ALIVE && spawned < SPAWN_PER_TICK )
    {
        string cls = g_Queue[ g_Queue.length() - 1 ];
        g_Queue.removeLast();
        SpawnOne( cls, w.healthMult, w.flank );
        ++alive; ++spawned;
    }

    NudgeMonsters();

    int remaining = alive + int( g_Queue.length() );
    g_PlayerFuncs.HudMessageAll( g_HudStatus,
        w.title + "\nMonsters left: " + remaining + " / " + g_WaveTotal );

    if( remaining <= 0 )
    {
        WaveCleared();
        return;
    }
    if( g_Engine.time - g_WaveStart > WAVE_TIMEOUT )
    {
        ClearRemaining();
        g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] Wave timed out - remaining monsters removed.\n" );
        WaveCleared();
    }
}

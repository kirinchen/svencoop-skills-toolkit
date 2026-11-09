/*
 * turret.as - friendly sentry guns for the cs_pve maps (PJ-047 test)
 * Include after cs_pve/core, call TurretMapInit() in MapInit and TurretMapActivate() in MapActivate.
 *
 * A. map-placed: TURRET_PREPLACED sentries in front of the player spawns, on the player side
 * B. player-built: chat "!turret" / console ".turret" puts a sentry on the floor where you aim
 * C. rules: TURRET_PRICE each, TURRET_MAX_PER_PLAYER alive at once, destroyed = slot freed,
 *    turret kills pay the owner (core's KillerOf follows the inflictor's pev.owner) and are counted
 */

const string TURRET_CLASS          = "monster_sentry";
const int    TURRET_PREPLACED      = 2;
const int    TURRET_PRICE          = 1000;
const int    TURRET_MAX_PER_PLAYER = 2;
const float  TURRET_HP             = 300.0f;
const float  TURRET_BUILD_RANGE    = 160.0f;
const bool   TURRET_PRECACHE       = true;     // false = reproduce the "precache in spawn functions" pitfall

class Turret
{
    EHandle h;
    string ownerKey;     // "" = map turret
    string ownerName;
    int kills = 0;
}

array<Turret@> g_Turrets;
array<EHandle> g_TurretCounted;   // monsters already credited to a turret
dictionary     g_TurretKillsBy;   // owner key -> total turret kills

void TurretMapInit()
{
    if( TURRET_PRECACHE )
    {
        g_Game.PrecacheOther( TURRET_CLASS );
        g_Game.PrecacheModel( "models/sentry.mdl" );
    }
    g_Hooks.RegisterHook( Hooks::Player::ClientSay, @TurretOnSay );
    g_Scheduler.SetInterval( "TurretThink", 0.25f, g_Scheduler.REPEAT_INFINITE_TIMES );
}

void TurretMapActivate()
{
    int placed = 0;
    CBaseEntity@ e = null;
    while( placed < TURRET_PREPLACED && ( @e = g_EntityFuncs.FindEntityByClassname( e, "info_player_start" ) ) !is null )
    {
        float yaw = e.pev.angles.y * 0.0174533f;
        Vector fwd( cos( yaw ), sin( yaw ), 0 );
        Vector pos;
        if( !TurretSpot( e.pev.origin + fwd * 128.0f, pos ) && !FindPropSpot( e.pev.origin, e.pev.angles.y, pos ) ) continue;
        if( SpawnTurret( pos, YawToNearestMonsterSpawn( pos, e.pev.angles.y ), null ) !is null ) ++placed;
    }
    g_Game.AlertMessage( at_console, "[turret] preplaced %1 %2\n", placed, TURRET_CLASS );
}

// face the way the monsters come from (nearest main monster spawn), else keep the fallback yaw
float YawToNearestMonsterSpawn( const Vector& in from, float fallback )
{
    float best = 1e9f;
    float yaw = fallback;
    for( uint i = 0; i < g_MainSpawns.length(); ++i )
    {
        Vector d = g_MainSpawns[i] - from;
        if( d.Length() >= best ) continue;
        best = d.Length();
        yaw = atan2( d.y, d.x ) * 57.29578f;
    }
    return yaw;
}

// floor below a point, with room for a sentry
bool TurretSpot( const Vector& in p, Vector& out feet )
{
    TraceResult tr;
    g_Utility.TraceLine( p + Vector( 0, 0, 32 ), p - Vector( 0, 0, 256 ), ignore_monsters, null, tr );
    if( tr.flFraction >= 1.0f || tr.fStartSolid == 1 ) return false;
    feet = tr.vecEndPos;
    TraceResult th;
    Vector o = feet + Vector( 0, 0, 37 );
    g_Utility.TraceHull( o, o, dont_ignore_monsters, human_hull, null, th );
    return th.fStartSolid == 0 && th.fAllSolid == 0;
}

CBaseEntity@ SpawnTurret( const Vector& in feet, float yaw, CBasePlayer@ owner )
{
    dictionary kv;
    kv["origin"] = string( feet.x ) + " " + string( feet.y ) + " " + string( feet.z + 4.0f );
    kv["angles"] = "0 " + string( yaw ) + " 0";
    kv["spawnflags"] = "32";              // SF_MONSTER_TURRET_AUTOACTIVATE
    kv["is_player_ally"] = "1";
    kv["displayname"] = owner is null ? "Base Sentry" : string( owner.pev.netname ) + "'s Sentry";
    CBaseEntity@ t = g_EntityFuncs.CreateEntity( TURRET_CLASS, kv, true );
    if( t is null )
    {
        g_Game.AlertMessage( at_console, "[turret] CreateEntity(%1) returned null\n", TURRET_CLASS );
        return null;
    }
    t.SetClassification( CLASS_PLAYER_ALLY );
    t.pev.health = TURRET_HP;
    t.pev.max_health = TURRET_HP;
    if( owner !is null ) @t.pev.owner = owner.edict();

    Turret r;
    r.h = EHandle( t );
    r.ownerKey = owner is null ? "" : PlayerKey( owner );
    r.ownerName = owner is null ? "base" : string( owner.pev.netname );
    g_Turrets.insertLast( r );
    g_Game.AlertMessage( at_console, "[turret] spawned #%1 for %2 at %3 %4 %5\n", t.entindex(), r.ownerName, feet.x, feet.y, feet.z );
    return t;
}

int TurretsOf( const string& in key )
{
    int n = 0;
    for( uint i = 0; i < g_Turrets.length(); ++i )
        if( g_Turrets[i].ownerKey == key ) ++n;
    return n;
}

void BuildTurret( CBasePlayer@ p )
{
    if( p is null || !p.IsAlive() ) return;
    string key = PlayerKey( p );
    int have = TurretsOf( key );
    if( have >= TURRET_MAX_PER_PLAYER )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Turret limit: " + TURRET_MAX_PER_PLAYER + " per player" );
        return;
    }
    if( GetMoney( p ) < TURRET_PRICE )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "A turret costs $" + TURRET_PRICE );
        return;
    }
    // where the crosshair hits, at most TURRET_BUILD_RANGE away, pulled back a bit from walls
    g_EngineFuncs.MakeVectors( p.pev.v_angle );
    Vector eye = p.pev.origin + p.pev.view_ofs;
    TraceResult tr;
    g_Utility.TraceLine( eye, eye + g_Engine.v_forward * TURRET_BUILD_RANGE, dont_ignore_monsters, p.edict(), tr );
    Vector aim = tr.vecEndPos - g_Engine.v_forward * 24.0f;
    Vector feet;
    if( !TurretSpot( aim, feet ) )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "No room for a turret there" );
        return;
    }
    if( SpawnTurret( feet, p.pev.angles.y, p ) is null )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Turret failed to spawn" );
        return;
    }
    AddMoney( p, -TURRET_PRICE );
    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] " + string( p.pev.netname ) + " built a sentry (" + ( have + 1 ) + "/" + TURRET_MAX_PER_PLAYER + ", -$" + TURRET_PRICE + ")\n" );
}

bool AlreadyCounted( CBaseEntity@ e )
{
    for( uint i = 0; i < g_TurretCounted.length(); ++i )
        if( g_TurretCounted[i].GetEntity() is e ) return true;
    return false;
}

void TurretThink()
{
    // credit monster kills whose last hit came from one of our turrets
    for( uint i = 0; i < g_Alive.length(); ++i )
    {
        CBaseEntity@ m = g_Alive[i].GetEntity();
        if( m is null || m.IsAlive() || m.pev.dmg_inflictor is null ) continue;
        CBaseEntity@ inf = g_EntityFuncs.Instance( m.pev.dmg_inflictor );
        if( inf is null || AlreadyCounted( m ) ) continue;
        for( uint k = 0; k < g_Turrets.length(); ++k )
        {
            if( g_Turrets[k].h.GetEntity() !is inf ) continue;
            Turret@ r = g_Turrets[k];
            ++r.kills;
            g_TurretCounted.insertLast( EHandle( m ) );
            int total = 1;
            if( r.ownerKey != "" )
            {
                total = g_TurretKillsBy.exists( r.ownerKey ) ? int( g_TurretKillsBy[r.ownerKey] ) + 1 : 1;
                g_TurretKillsBy[r.ownerKey] = total;
            }
            g_PlayerFuncs.ClientPrintAll( HUD_PRINTNOTIFY, "[PVE] " + r.ownerName + "'s sentry killed " + string( m.pev.classname ) + " (turret kills: " + r.kills + ")\n" );
            g_Game.AlertMessage( at_console, "[turret] kill %1 by turret #%2 (%3) total %4\n", string( m.pev.classname ), inf.entindex(), r.ownerName, r.kills );
            break;
        }
    }
    for( uint i = 0; i < g_TurretCounted.length(); )
    {
        if( g_TurretCounted[i].GetEntity() is null ) g_TurretCounted.removeAt( i );
        else ++i;
    }

    // destroyed turrets free their slot
    for( uint i = 0; i < g_Turrets.length(); )
    {
        CBaseEntity@ t = g_Turrets[i].h.GetEntity();
        if( t is null || !t.IsAlive() || t.pev.deadflag != DEAD_NO )
        {
            g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] " + g_Turrets[i].ownerName + "'s sentry was destroyed after " + g_Turrets[i].kills + " kills\n" );
            g_Game.AlertMessage( at_console, "[turret] destroyed (%1, %2 kills)\n", g_Turrets[i].ownerName, g_Turrets[i].kills );
            g_Turrets.removeAt( i );
            continue;
        }
        ++i;
    }
}

void CmdTurret( const CCommand@ args ) { BuildTurret( g_ConCommandSystem.GetCurrentPlayer() ); }
CClientCommand g_CmdTurret( "turret", "Build a friendly sentry where you aim ($" + TURRET_PRICE + ")", @CmdTurret );

HookReturnCode TurretOnSay( SayParameters@ pParams )
{
    CBasePlayer@ p = pParams.GetPlayer();
    const CCommand@ args = pParams.GetArguments();
    if( p is null || args.ArgC() < 1 ) return HOOK_CONTINUE;
    string a = args.Arg( 0 ).ToLowercase();
    if( a == "!turret" || a == "/turret" ) { pParams.ShouldHide = true; BuildTurret( p ); }
    else if( a == "!tpturret" && g_Turrets.length() > 0 && g_EngineFuncs.CVarGetFloat( "sv_cheats" ) > 0.0f )
    {
        // test helper: stand behind turret N (default 1), looking the way it faces
        pParams.ShouldHide = true;
        uint n = args.ArgC() > 1 ? uint( atoi( args.Arg( 1 ) ) ) : 1;
        if( n < 1 || n > g_Turrets.length() ) n = 1;
        CBaseEntity@ t = g_Turrets[n - 1].h.GetEntity();
        if( t !is null )
        {
            float yaw = t.pev.angles.y * 0.0174533f;
            Vector back( cos( yaw ), sin( yaw ), 0 );
            p.SetOrigin( t.pev.origin - back * 96.0f + Vector( 0, 0, 36 ) );
            p.pev.angles = Vector( 0, t.pev.angles.y, 0 );
            p.pev.v_angle = p.pev.angles;
            p.pev.fixangle = FAM_FORCEVIEWANGLES;
        }
    }
    else if( a == "!horde" && g_EngineFuncs.CVarGetFloat( "sv_cheats" ) > 0.0f )
    {
        // test helper: N monsters 400-700 units in front of the player (camera shot of turrets at work)
        pParams.ShouldHide = true;
        int n = args.ArgC() > 1 ? atoi( args.Arg( 1 ) ) : 6;
        string cls = args.ArgC() > 2 ? args.Arg( 2 ) : "monster_zombie";
        float yaw = p.pev.angles.y * 0.0174533f;
        Vector fwd( cos( yaw ), sin( yaw ), 0 );
        Vector right( sin( yaw ), -cos( yaw ), 0 );
        int made = 0;
        for( int i = 0; i < n * 4 && made < n; ++i )
        {
            Vector cand = p.pev.origin + fwd * Math.RandomFloat( 400.0f, 700.0f ) + right * Math.RandomFloat( -200.0f, 200.0f );
            Vector feet;
            if( !TurretSpot( cand, feet ) ) continue;
            TraceResult los;
            g_Utility.TraceLine( p.pev.origin, feet + Vector( 0, 0, 36 ), ignore_monsters, p.edict(), los );
            if( los.flFraction < 1.0f ) continue;
            CBaseEntity@ m = g_EntityFuncs.Create( cls, feet + Vector( 0, 0, 8 ), Vector( 0, p.pev.angles.y + 180.0f, 0 ), false, null );
            if( m is null ) break;
            m.SetClassification( CLASS_ALIEN_MILITARY );
            CBaseMonster@ mm = m.MyMonsterPointer();
            if( mm !is null ) { mm.m_hEnemy = EHandle( p ); mm.SetConditions( bits_COND_NEW_ENEMY ); }
            g_Alive.insertLast( EHandle( m ) );
            g_IdleSecs.insertLast( 0 );
            ++made;
        }
        g_Game.AlertMessage( at_console, "[turret] horde: %1 x %2\n", made, cls );
    }
    else if( a == "!turrets" )
    {
        pParams.ShouldHide = true;
        string key = PlayerKey( p );
        int kills = g_TurretKillsBy.exists( key ) ? int( g_TurretKillsBy[key] ) : 0;
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTTALK, "[PVE] Your sentries: " + TurretsOf( key ) + "/" + TURRET_MAX_PER_PLAYER + ", turret kills: " + kills + "\n" );
    }
    return HOOK_CONTINUE;
}

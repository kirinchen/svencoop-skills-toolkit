/*
 * cs_td/td.as - tower-defence rules on top of cs_td/core.as (PJ-047 game spec v1, maps/dust2_td)
 *
 * - two gold mines (A / B bomb site), MINE_HP each; every mine pays everyone MINE_INCOME $/s
 * - monster target priority: player > tower > NPC (guard / miner / ammo carrier) > gold mine
 *   (the best one it can see within RETARGET_DIST; nothing in sight -> the nearest mine)
 * - drop a CS gun (G) -> it becomes a tower that fires THAT gun (its damage, fire rate, pellets,
 *   magazine, sound); the gun is gone, a destroyed tower is gone. No price, no limit.
 *   Tower HP = the gun's full ammo capacity (magazine + reserve with upgrades) -> upgrade, then drop.
 *   A tower out of ammo stops firing until an ammo carrier brings more.
 *   Looks: the gun's p_ (held) model lying flat on a small sandbag nest, turning to its target.
 *   Server variable td_towers 0 turns towers off.
 * - lose = both mines destroyed (no team lives); win = the last wave cleared
 * - guards: GUARDS_PER_MINE armed soldiers per mine (GUARD_HP, shotgun), never hired, never replaced;
 *   with nothing left to shoot a guard walks back to his post (GUARD_LEASH)
 * - gold miners: unarmed scientists standing at the mine (MINER_HP), MINERS_AT_START per mine, hire
 *   more at the Arms Dealer (MINER_PRICE, max MINER_MAX per mine); each pays +MINER_INCOME $/s.
 *   A guard or miner who sees a monster raises the alarm (centre text only, no sound).
 *   Dead miners stay dead (hire again).
 * - ammo carrier: hire at the Arms Dealer (CARRIER_PRICE). Unarmed, CARRIER_HP, can be killed.
 *   Small (CARRIER_SCALE, point-sized hull) so he gets through doors. A tower with no rounds left
 *   shows a red "!" (NOAMMO_SPRITE) until he brings more.
 *   Loop: at the dealer he buys up to CARRIER_LOAD rounds at shop price with the hirer's money, walks
 *   them to the towers that need ammo, then walks back -> towers far from the dealer refill slower
 *
 * Test cheats (sv_cheats 1 only; not for real play): !tdhorde N [class], !tdmoney, !tdskip,
 * !tdgo A|B|spawn, !tdhurt A|B dmg, !tdempty, !tdbuild [weapon_x], !tdcam [dist] [angle] [height]
 */

const int    MINE_HP          = 2000;
const int    MINE_INCOME      = 10;      // $ per second per standing mine, to every player
const string MINE_MODEL       = "models/crystal.mdl";
const float  RETARGET_DIST    = 900.0f;  // a monster chasing something else farther than this goes back to a mine

// v2 (2026-11-11): guards and miners are two NPCs. Guards: 2 per mine, strong, armed, never hired
// or replaced. Miners: unarmed workers, fragile, 1 per mine at the start, hire more.
const string GUARD_CLASS      = "monster_human_grunt_ally";
const int    GUARDS_PER_MINE  = 2;
const int    GUARD_HP         = 500;
const int    MINER_PRICE      = 2000;
const int    MINER_MAX        = 5;       // per mine
const int    MINER_INCOME     = 10;      // $ per second per living miner, to every player
const int    MINER_HP         = 50;
const string MINER_MODEL      = "models/scientist.mdl";   // standing scientists (the kneeling construction worker sank into the floor)
const float  ALERT_DIST       = 1100.0f; // a guard / miner "sees" a monster this close (and in line of sight)
const float  ALERT_COOLDOWN   = 10.0f;
const float  GUARD_LEASH      = 160.0f;  // a guard with nothing to shoot farther than this from his post walks back
const int    MINERS_AT_START  = 2;       // per mine
const float  CARRIER_SCALE    = 0.6f;    // small model + point-sized hull: fits through doors, slips past NPCs
const string NOAMMO_SPRITE    = "sprites/cs_td/noammo.spr";
const int    CARRIER_PRICE    = 1000;
const int    CARRIER_HP       = 150;
const int    CARRIER_LOAD     = 1500;    // rounds per trip, bought at the Arms Dealer (shop price, paid by whoever hired him)
const float  CARRIER_REACH    = 110.0f;
const float  DEALER_REACH     = 150.0f;

const string TOWER_BASE_MODEL = "models/sandbags.mdl";   // a small sandbag nest under the gun
const float  TOWER_BASE_SCALE = 0.5f;                   // sandbags.mdl is 132x58x50 -> 66x29x25
// tower HP = the gun's full ammo capacity (magazine + reserve, with the owner's upgrades), fixed when it is built
const float  TOWER_RANGE      = 1400.0f;
const float  TOWER_RELOAD     = 2.5f;
const float  TOWER_GUN_HEIGHT = 30.0f;   // gun (and muzzle) above the floor: resting on the sandbags
const float  TOWER_GUN_SCALE  = 1.6f;
// CS p_ models are posed upright (barrel along +z) and off-centre around the player's hand.
// Centre of that pose, measured from the .mdl (p_ak47 / m3 / usp / awp / m249 all within ~1.5 units).
const Vector P_MODEL_CENTER = Vector( 7.5f, -9.5f, 29.0f );

CCVar g_TdTowers( "td_towers", 1, "1 = a dropped gun grows into a tower, 0 = towers off", ConCommandFlag::AdminOnly );

// ------------------------------------------------------------------ gun table (stats read from the KernCore weapon scripts)

class TowerGun
{
    string cls;
    int dmg;
    float rate;     // seconds between shots
    int pellets;
    string snd;
    string gunmodel;
    TowerGun( const string& in c, int d, float r, int p, const string& in s, const string& in w )
    { cls = c; dmg = d; rate = r; pellets = p; snd = s; gunmodel = w; }
}

array<TowerGun@> g_TowerGuns;

void BuildTowerGuns()
{
    g_TowerGuns.insertLast( TowerGun( "weapon_csglock18",  CS16_GLOCK18::DAMAGE, CS16_GLOCK18::RPM_SINGLE, 1, CS16_GLOCK18::SHOOT_S, CS16_GLOCK18::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_usp",        CS16_USP::DAMAGE,     CS16_USP::RPM,     1, CS16_USP::SHOOT_S,     CS16_USP::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_p228",       CS16_P228::DAMAGE,    CS16_P228::RPM,    1, CS16_P228::SHOOT_S,    CS16_P228::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_csdeagle",   CS16_DEAGLE::DAMAGE,  CS16_DEAGLE::RPM,  1, CS16_DEAGLE::SHOOT_S,  CS16_DEAGLE::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_fiveseven",  CS16_57::DAMAGE,      CS16_57::RPM,      1, CS16_57::SHOOT_S,      CS16_57::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_dualelites", CS16_ELITES::DAMAGE,  CS16_ELITES::RPM,  1, CS16_ELITES::SHOOT_S,  CS16_ELITES::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_m3",         CS16_M3::DAMAGE,      CS16_M3::RPM_PUMP, CS16_M3::PELLETS, CS16_M3::SHOOT_S, CS16_M3::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_xm1014",     CS16_XM1014::DAMAGE,  CS16_XM1014::RPM,  CS16_XM1014::PELLETS, CS16_XM1014::SHOOT_S, CS16_XM1014::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_tmp",        CS16_TMP::DAMAGE,     CS16_TMP::RPM,     1, CS16_TMP::SHOOT_S,     CS16_TMP::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_mac10",      CS16_MAC10::DAMAGE,   CS16_MAC10::RPM,   1, CS16_MAC10::SHOOT_S,   CS16_MAC10::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_mp5navy",    CS16_MP5::DAMAGE,     CS16_MP5::RPM,     1, CS16_MP5::SHOOT_S,     CS16_MP5::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_ump45",      CS16_UMP45::DAMAGE,   CS16_UMP45::RPM,   1, CS16_UMP45::SHOOT_S,   CS16_UMP45::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_p90",        CS16_P90::DAMAGE,     CS16_P90::RPM,     1, CS16_P90::SHOOT_S,     CS16_P90::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_galil",      CS16_GALIL::DAMAGE,   CS16_GALIL::RPM,   1, CS16_GALIL::SHOOT_S,   CS16_GALIL::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_famas",      CS16_FAMAS::DAMAGE,   CS16_FAMAS::RPM_SINGLE, 1, CS16_FAMAS::SHOOT_S, CS16_FAMAS::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_ak47",       CS16_AK47::DAMAGE,    CS16_AK47::RPM,    1, CS16_AK47::SHOOT_S,    CS16_AK47::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_m4a1",       CS16_M4A1::DAMAGE,    CS16_M4A1::RPM,    1, CS16_M4A1::SHOOT_S,    CS16_M4A1::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_aug",        CS16_AUG::DAMAGE,     CS16_AUG::RPM,     1, CS16_AUG::SHOOT_S,     CS16_AUG::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_sg552",      CS16_SG552::DAMAGE,   CS16_SG552::RPM,   1, CS16_SG552::SHOOT_S,   CS16_SG552::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_scout",      CS16_SCOUT::DAMAGE,   CS16_SCOUT::RPM,   1, CS16_SCOUT::SHOOT_S,   CS16_SCOUT::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_awp",        CS16_AWP::DAMAGE,     CS16_AWP::RPM,     1, CS16_AWP::SHOOT_S,     CS16_AWP::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_sg550",      CS16_SG550::DAMAGE,   CS16_SG550::RPM,   1, CS16_SG550::SHOOT_S,   CS16_SG550::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_g3sg1",      CS16_G3SG1::DAMAGE,   CS16_G3SG1::RPM,   1, CS16_G3SG1::SHOOT_S,   CS16_G3SG1::P_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_csm249",     CS16_M249::DAMAGE,    CS16_M249::RPM,    1, CS16_M249::SHOOT_S,    CS16_M249::P_MODEL ) );
}

TowerGun@ TowerGunByClass( const string& in cls )
{
    for( uint i = 0; i < g_TowerGuns.length(); ++i )
        if( g_TowerGuns[i].cls == cls ) return g_TowerGuns[i];
    return null;
}

// ------------------------------------------------------------------ gold mine

array<EHandle> g_Mines;
array<string>  g_MineNames;

class CTdMine : ScriptBaseMonsterEntity
{
    void Spawn()
    {
        Precache();
        pev.movetype   = MOVETYPE_NONE;
        pev.solid      = SOLID_BBOX;
        pev.takedamage = DAMAGE_YES;
        pev.flags     |= FL_MONSTER;
        pev.deadflag   = DEAD_NO;
        pev.health     = MINE_HP;
        pev.max_health = MINE_HP;
        pev.view_ofs   = Vector( 0, 0, 48 );   // monsters "see" it at this height
        g_EntityFuncs.SetModel( self, MINE_MODEL );
        g_EntityFuncs.SetSize( self.pev, Vector( -28, -28, 0 ), Vector( 28, 28, 80 ) );
        self.m_bloodColor = DONT_BLEED;
        pev.renderfx    = kRenderFxGlowShell;
        pev.rendercolor = Vector( 255, 190, 0 );
        pev.renderamt   = 8;
        self.SetClassification( CLASS_PLAYER_ALLY );
        SetThink( ThinkFunction( this.MineThink ) );
        pev.nextthink = g_Engine.time + 0.1f;
    }

    void Precache() { g_Game.PrecacheModel( MINE_MODEL ); }

    int Classify() { return CLASS_PLAYER_ALLY; }

    int TakeDamage( entvars_t@ pevInflictor, entvars_t@ pevAttacker, float flDamage, int bitsDamageType )
    {
        if( pev.deadflag != DEAD_NO ) return 0;
        CBaseEntity@ att = pevAttacker !is null ? g_EntityFuncs.Instance( pevAttacker ) : null;
        if( att !is null && ( att.IsPlayer() || att.Classify() == CLASS_PLAYER_ALLY ) ) return 0;   // no friendly fire
        pev.health -= flDamage;
        if( pev.health <= 0 ) { MineDestroyed( self ); return 0; }
        return 1;
    }

    void MineThink()
    {
        self.StudioFrameAdvance();
        pev.nextthink = g_Engine.time + 0.1f;
    }
}

void MineDestroyed( CBaseEntity@ mine )
{
    mine.pev.deadflag = DEAD_DEAD;
    mine.pev.takedamage = DAMAGE_NO;
    mine.pev.health = 0;
    g_EntityFuncs.CreateExplosion( mine.pev.origin + Vector( 0, 0, 40 ), Vector( 0, 0, 0 ), null, 120, false );
    Big( MineName( mine ) + " gold mine DESTROYED!" );
    mine.pev.renderfx = kRenderFxNone;
    mine.pev.rendermode = kRenderTransTexture;
    mine.pev.renderamt = 60;
    mine.pev.solid = SOLID_NOT;
    mine.pev.flags &= ~FL_MONSTER;
}

string MineName( CBaseEntity@ mine )
{
    for( uint i = 0; i < g_Mines.length(); ++i )
        if( g_Mines[i].GetEntity() is mine ) return g_MineNames[i];
    return "?";
}

bool MineAlive( CBaseEntity@ m ) { return m !is null && m.pev.deadflag == DEAD_NO && m.pev.health > 0; }

int AliveMines()
{
    int n = 0;
    for( uint i = 0; i < g_Mines.length(); ++i )
        if( MineAlive( g_Mines[i].GetEntity() ) ) ++n;
    return n;
}

CBaseEntity@ NearestMine( const Vector& in pos )
{
    CBaseEntity@ best = null;
    float bd = 1.0e9f;
    for( uint i = 0; i < g_Mines.length(); ++i )
    {
        CBaseEntity@ m = g_Mines[i].GetEntity();
        if( !MineAlive( m ) ) continue;
        float d = ( m.pev.origin - pos ).Length();
        if( d < bd ) { bd = d; @best = m; }
    }
    return best;
}

// open floor near a point, with room for a mine (the bomb-site centre is often a crate stack)
Vector OpenSpotNear( const Vector& in at )
{
    for( int r = 0; r <= 320; r += 40 )
    {
        int steps = r == 0 ? 1 : 12;
        for( int k = 0; k < steps; ++k )
        {
            float a = float( k ) * 6.2831853f / float( steps );
            Vector c = at + Vector( cos( a ) * float( r ), sin( a ) * float( r ), 48.0f );
            TraceResult tr;
            g_Utility.TraceLine( c, c - Vector( 0, 0, 320 ), ignore_monsters, null, tr );
            if( tr.fStartSolid != 0 || tr.flFraction >= 1.0f ) continue;
            Vector feet = tr.vecEndPos;
            if( feet.z > at.z + 24.0f ) continue;          // on top of a crate
            bool ok = true;
            for( int q = 0; q < 5 && ok; ++q )   // the spot and four points 56 units around it must be free
            {
                Vector off( 0, 0, 0 );
                if( q == 1 ) off.x = 56; else if( q == 2 ) off.x = -56; else if( q == 3 ) off.y = 56; else if( q == 4 ) off.y = -56;
                TraceResult th;
                Vector o = feet + off + Vector( 0, 0, 40 );
                g_Utility.TraceHull( o, o, ignore_monsters, large_hull, null, th );
                if( th.fStartSolid != 0 || th.fAllSolid != 0 ) ok = false;
            }
            if( !ok ) continue;
            return feet;
        }
    }
    return FloorAt( at );
}

void SpawnMine( const Vector& in at, const string& in name )
{
    Vector feet = OpenSpotNear( at );
    dictionary kv;
    kv["origin"] = string( feet.x ) + " " + string( feet.y ) + " " + string( feet.z + 1.0f );
    kv["displayname"] = name + " Gold Mine";
    kv["targetname"] = "td_mine";
    CBaseEntity@ e = g_EntityFuncs.CreateEntity( "td_goldmine", kv, true );
    if( e is null ) { g_Game.AlertMessage( at_console, "[cs_td] could not create gold mine %1\n", name ); return; }
    g_Mines.insertLast( EHandle( e ) );
    g_MineNames.insertLast( name );
    g_Miners.insertLast( array<EHandle>() );
    g_Guards.insertLast( array<EHandle>() );
    g_GuardPosts.insertLast( array<EHandle>() );
    g_NextAlert.insertLast( 0.0f );
    uint mi = g_Mines.length() - 1;
    for( int k = 0; k < GUARDS_PER_MINE; ++k ) SpawnGuard( mi );
    for( int k = 0; k < MINERS_AT_START; ++k ) SpawnMiner( mi );
    g_Game.AlertMessage( at_console, "[cs_td] gold mine %1 at %2 %3 %4\n", name, feet.x, feet.y, feet.z );
}

// ------------------------------------------------------------------ monsters go for the mines

void AimAt( CBaseMonster@ m, CBaseEntity@ target )
{
    m.m_hEnemy = EHandle( target );
    m.m_vecEnemyLKP = target.pev.origin;
    m.SetConditions( bits_COND_NEW_ENEMY );
}

CBaseEntity@ RandomMine()
{
    array<CBaseEntity@> ms;
    for( uint i = 0; i < g_Mines.length(); ++i )
    {
        CBaseEntity@ m = g_Mines[i].GetEntity();
        if( MineAlive( m ) ) ms.insertLast( m );
    }
    if( ms.length() == 0 ) return null;
    return ms[ Math.RandomLong( 0, ms.length() - 1 ) ];
}

// a new monster picks one of the standing mines at random (both sites get pressure)
void TdAimAtMine( CBaseMonster@ m )
{
    CBaseEntity@ mine = RandomMine();
    if( mine !is null ) AimAt( m, mine );
}

// target priority (v2): player > tower > NPC (guard / miner / ammo carrier) > gold mine
int TargetPrio( CBaseEntity@ t )
{
    if( t is null ) return 0;
    if( t.IsPlayer() ) return 4;
    string c = t.GetClassname();
    if( c == "td_tower" ) return 3;
    if( c == "td_goldmine" ) return 1;
    return 2;
}

// everything on our side a monster may go for instead of a mine
void AddTargets( array<CBaseEntity@>@ dst, const array<EHandle>& in hs )
{
    for( uint k = 0; k < hs.length(); ++k )
    {
        CBaseEntity@ t = hs[k].GetEntity();
        if( t !is null && t.IsAlive() && t.pev.takedamage != DAMAGE_NO ) dst.insertLast( t );
    }
}

array<CBaseEntity@> SideTargets()
{
    array<CBaseEntity@> ts;
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p !is null && p.IsConnected() && p.IsAlive() && ( p.pev.flags & FL_NOTARGET ) == 0 ) ts.insertLast( p );
    }
    AddTargets( @ts, g_Towers );
    for( uint mi = 0; mi < g_Guards.length(); ++mi ) AddTargets( @ts, g_Guards[mi] );
    for( uint mi = 0; mi < g_Miners.length(); ++mi ) AddTargets( @ts, g_Miners[mi] );
    AddTargets( @ts, g_Carriers );
    return ts;
}

// the highest-priority target this monster can see within RETARGET_DIST (nearest on a tie), or null
CBaseEntity@ BestTarget( CBaseMonster@ m, const array<CBaseEntity@>& in ts )
{
    CBaseEntity@ best = null;
    int bp = 0;
    float bd = 1.0e9f;
    for( uint k = 0; k < ts.length(); ++k )
    {
        CBaseEntity@ t = ts[k];
        float d = ( t.pev.origin - m.pev.origin ).Length();
        if( d > RETARGET_DIST ) continue;
        int pr = TargetPrio( t );
        if( pr < bp || ( pr == bp && d >= bd ) ) continue;
        if( !m.FVisible( t, true ) ) continue;
        @best = t; bp = pr; bd = d;
    }
    return best;
}

// once a second (from core's PveThink): every monster goes for the best target it can see
// (priority above); with nothing in sight it goes back to the nearest mine
dictionary g_LastPos;   // entindex -> Vector, position a second ago

void TdNudgeMonsters()
{
    array<CBaseEntity@> ts = SideTargets();
    for( uint i = 0; i < g_Alive.length(); ++i )
    {
        CBaseEntity@ e = g_Alive[i].GetEntity();
        if( e is null ) continue;
        CBaseMonster@ m = e.MyMonsterPointer();
        if( m is null ) continue;
        CBaseEntity@ mine = NearestMine( e.pev.origin );
        if( mine is null ) return;

        string key = string( e.entindex() );
        Vector last = g_LastPos.exists( key ) ? Vector( g_LastPos[key] ) : Vector( 0, 0, -99999 );
        g_LastPos[key] = e.pev.origin;
        bool moved = ( e.pev.origin - last ).Length() > 16.0f;

        CBaseEntity@ en = m.m_hEnemy.IsValid() ? m.m_hEnemy.GetEntity() : null;
        if( en !is null && !en.IsAlive() ) @en = null;
        CBaseEntity@ best = BestTarget( m, ts );
        if( best !is null && best !is en && ( en is null || TargetPrio( best ) > TargetPrio( en )
            || ( en.pev.origin - e.pev.origin ).Length() > RETARGET_DIST ) )
        {
            AimAt( m, best );
            @en = best;
            g_IdleSecs[i] = 0;
        }
        bool keep = false;
        if( en !is null )
        {
            if( en.GetClassname() == "td_goldmine" ) keep = MineAlive( en );
            else keep = ( en.pev.origin - e.pev.origin ).Length() < RETARGET_DIST;
        }
        if( !keep )
        {
            AimAt( m, mine );
            @en = mine;
            g_IdleSecs[i] = 0;
        }
        // standing still far from its target (lost the route, finished a fight): chase again
        float dist = ( en.pev.origin - e.pev.origin ).Length();
        if( moved || dist < 160.0f ) { g_IdleSecs[i] = 0; continue; }
        g_IdleSecs[i] = g_IdleSecs[i] + 1;
        if( g_IdleSecs[i] >= 3 )
        {
            g_IdleSecs[i] = 0;
            m.m_vecEnemyLKP = en.pev.origin;
            m.SetConditions( bits_COND_NEW_ENEMY );
            Schedule@ sch = m.GetScheduleOfType( SCHED_CHASE_ENEMY );
            if( sch !is null ) m.ChangeSchedule( sch );
        }
    }
}

// ------------------------------------------------------------------ towers (a dropped gun)

class CTdTower : ScriptBaseMonsterEntity
{
    string m_gunCls;
    int m_dmg = 10;
    float m_rate = 0.1f;
    int m_pellets = 1;
    string m_snd;
    int m_clipMax = 30;
    int m_clip = 30;
    int m_reserve = 0;
    int m_kills = 0;
    int m_reserveCap = 0;
    string m_label;
    float m_nextFire = 0.0f;
    float m_reloadEnd = 0.0f;
    EHandle m_hGun;      // the gun model on top
    EHandle m_hBang;     // red "!" floating above while the tower is out of ammo
    EHandle m_hTarget;
    float m_nextScan = 0.0f;
    float m_nextEmptyMsg = 0.0f;

    void Spawn()
    {
        Precache();
        pev.movetype   = MOVETYPE_NONE;
        pev.solid      = SOLID_BBOX;
        pev.takedamage = DAMAGE_YES;
        pev.flags     |= FL_MONSTER;
        pev.deadflag   = DEAD_NO;
        pev.health     = 100;   // replaced in Setup() by the gun's ammo capacity
        pev.max_health = 100;
        pev.view_ofs   = Vector( 0, 0, TOWER_GUN_HEIGHT );
        g_EntityFuncs.SetModel( self, TOWER_BASE_MODEL );
        pev.scale = TOWER_BASE_SCALE;
        g_EntityFuncs.SetSize( self.pev, Vector( -14, -14, 0 ), Vector( 14, 14, 30 ) );
        self.m_bloodColor = DONT_BLEED;
        self.SetClassification( CLASS_PLAYER_ALLY );
        SetThink( ThinkFunction( this.TowerThink ) );
        pev.nextthink = g_Engine.time + 0.2f;
    }

    void Precache() { g_Game.PrecacheModel( TOWER_BASE_MODEL ); }

    int Classify() { return CLASS_PLAYER_ALLY; }

    int TakeDamage( entvars_t@ pevInflictor, entvars_t@ pevAttacker, float flDamage, int bitsDamageType )
    {
        if( pev.deadflag != DEAD_NO ) return 0;
        CBaseEntity@ att = pevAttacker !is null ? g_EntityFuncs.Instance( pevAttacker ) : null;
        if( att !is null && ( att.IsPlayer() || att.Classify() == CLASS_PLAYER_ALLY ) ) return 0;
        pev.health -= flDamage;
        if( pev.health <= 0 ) { Destroyed(); return 0; }
        return 1;
    }

    void Setup( TowerGun@ g, int clipMax, int clip, int reserve, CBasePlayer@ owner )
    {
        m_gunCls = g.cls; m_dmg = g.dmg; m_rate = g.rate; m_pellets = g.pellets; m_snd = g.snd;
        m_clipMax = clipMax; m_clip = clip; m_reserve = reserve;
        Gun@ cg = GunByClass( g.cls );
        m_label = cg !is null ? cg.label : g.cls;
        int cap = ( cg !is null && owner !is null ) ? CarryCap( owner, cg ) : reserve;
        m_reserveCap = cap > reserve ? cap : reserve;
        pev.max_health = float( m_clipMax + m_reserveCap );   // HP = full ammo capacity (upgrade before you drop)
        pev.health = pev.max_health;
        if( owner !is null ) @pev.owner = owner.edict();
        Vector gp = pev.origin + Vector( 0, 0, TOWER_GUN_HEIGHT );
        dictionary kv;
        kv["origin"] = string( gp.x ) + " " + string( gp.y ) + " " + string( gp.z );
        kv["model"] = g.gunmodel;
        kv["targetname"] = "td_tower_gun";
        CBaseEntity@ gun = g_EntityFuncs.CreateEntity( "info_target", kv, true );
        if( gun !is null )
        {
            g_EntityFuncs.SetModel( gun, g.gunmodel );
            gun.pev.movetype = MOVETYPE_NOCLIP;
            gun.pev.solid = SOLID_NOT;
            gun.pev.scale = TOWER_GUN_SCALE;
            gun.pev.effects &= ~EF_NODRAW;
            m_hGun = EHandle( gun );
            AimGun( pev.angles.y );
        }
        Vector bp = pev.origin + Vector( 0, 0, TOWER_GUN_HEIGHT + 40.0f );
        dictionary sk;
        sk["origin"] = string( bp.x ) + " " + string( bp.y ) + " " + string( bp.z );
        sk["model"] = NOAMMO_SPRITE;
        sk["rendermode"] = "4";    // alpha test: palette index 255 is see-through
        sk["renderamt"] = "255";
        sk["scale"] = "0.6";
        sk["spawnflags"] = "1";    // start on
        CBaseEntity@ bang = g_EntityFuncs.CreateEntity( "env_sprite", sk, true );
        if( bang !is null ) { bang.pev.effects |= EF_NODRAW; m_hBang = EHandle( bang ); }
        UpdateBang();
    }

    // the "!" shows while the tower has no rounds at all (magazine and reserve empty)
    void UpdateBang()
    {
        CBaseEntity@ bang = m_hBang.GetEntity();
        if( bang is null ) return;
        bool empty = pev.deadflag == DEAD_NO && m_clip + m_reserve <= 0;
        if( empty ) bang.pev.effects &= ~EF_NODRAW; else bang.pev.effects |= EF_NODRAW;
    }

    int Deficit() { int d = m_clipMax + m_reserveCap - m_clip - m_reserve; return d > 0 ? d : 0; }
    // worth a carrier trip: at least a full magazine short (or nothing left at all)
    bool NeedsAmmo() { int d = Deficit(); return d > 0 && ( d >= m_clipMax || m_clip + m_reserve == 0 ); }

    // an ammo carrier hands over up to n rounds; returns how many were taken
    int AddAmmo( int n )
    {
        int take = Deficit();
        if( take > n ) take = n;
        if( take <= 0 ) return 0;
        m_reserve += take;
        if( m_clip <= 0 && m_reloadEnd <= 0.0f ) m_reloadEnd = g_Engine.time + TOWER_RELOAD;
        m_nextEmptyMsg = 0.0f;
        UpdateBang();
        return take;
    }

    int UnitPrice()   // $ per round of this gun's ammo (shop price)
    {
        Gun@ g = GunByClass( m_gunCls );
        return g !is null ? AmmoUnitPrice( g ) : 10;
    }

    string OwnerName()
    {
        if( pev.owner is null ) return "a";
        CBaseEntity@ o = g_EntityFuncs.Instance( pev.owner );
        return o is null ? "a" : string( o.pev.netname ) + "'s";
    }

    // Lay the upright p_ model flat and turn it to yaw: pitch +90 puts the barrel forward and the
    // magazine down (pitch -90 lays it flat too, but backwards and upside down - checked in game).
    // The model is off-centre, so shift it to keep the middle of the gun right above the base.
    void AimGun( float yaw )
    {
        CBaseEntity@ gun = m_hGun.GetEntity();
        if( gun is null ) return;
        float r = yaw * Math.PI / 180.0f;
        Vector fwd = Vector( cos( r ), sin( r ), 0 ), left = Vector( -sin( r ), cos( r ), 0 );
        Vector c = P_MODEL_CENTER * TOWER_GUN_SCALE;
        Vector off = Vector( 0, 0, c.x ) + left * c.y - fwd * c.z;   // where the model centre lands
        gun.pev.angles = Vector( 90, yaw, 0 );
        g_EntityFuncs.SetOrigin( gun, pev.origin + Vector( 0, 0, TOWER_GUN_HEIGHT ) - off );
    }

    Vector Muzzle() { return pev.origin + Vector( 0, 0, TOWER_GUN_HEIGHT + 2.0f ); }

    bool CanShoot( CBaseEntity@ t )
    {
        if( t is null || !t.IsAlive() || t.pev.takedamage == DAMAGE_NO ) return false;
        Vector aim = t.BodyTarget( Muzzle() );
        if( ( aim - Muzzle() ).Length() > TOWER_RANGE ) return false;
        TraceResult tr;
        g_Utility.TraceLine( Muzzle(), aim, ignore_monsters, self.edict(), tr );
        return tr.flFraction >= 0.99f;
    }

    CBaseEntity@ FindTarget()
    {
        CBaseEntity@ best = null;
        float bd = 1.0e9f;
        for( uint i = 0; i < g_Alive.length(); ++i )
        {
            CBaseEntity@ e = g_Alive[i].GetEntity();
            if( e is null || !e.IsAlive() ) continue;
            float d = ( e.pev.origin - pev.origin ).Length();
            if( d >= bd || d > TOWER_RANGE ) continue;
            if( !CanShoot( e ) ) continue;
            bd = d; @best = e;
        }
        return best;
    }

    void TowerThink()
    {
        float now = g_Engine.time;
        pev.nextthink = now + ( m_rate < 0.1f ? m_rate : 0.05f );
        if( pev.deadflag != DEAD_NO ) return;

        if( m_reloadEnd > 0.0f )
        {
            if( now < m_reloadEnd ) return;
            int take = m_clipMax - m_clip;
            if( take > m_reserve ) take = m_reserve;
            m_clip += take; m_reserve -= take;
            m_reloadEnd = 0.0f;
        }
        if( m_clip <= 0 )
        {
            if( m_reserve > 0 ) { m_reloadEnd = now + TOWER_RELOAD; return; }
            UpdateBang();
            if( now >= m_nextEmptyMsg )
            {
                m_nextEmptyMsg = now + 15.0f;
                g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] " + OwnerName() + " " + m_label + " tower is OUT OF AMMO\n" );
            }
            return;
        }

        CBaseEntity@ t = m_hTarget.GetEntity();
        if( now >= m_nextScan || !CanShoot( t ) )
        {
            @t = FindTarget();
            m_hTarget = EHandle( t );
            m_nextScan = now + 0.5f;
        }
        if( t is null ) return;

        Vector src = Muzzle();
        Vector dir = ( t.BodyTarget( src ) - src );
        dir = dir.Normalize();
        CBaseEntity@ gun = m_hGun.GetEntity();
        if( gun !is null )
        {
            AimGun( Math.VecToAngles( dir ).y );
        }
        if( now < m_nextFire ) return;
        m_nextFire = now + m_rate;

        Vector spread = m_pellets > 1 ? VECTOR_CONE_6DEGREES : VECTOR_CONE_2DEGREES;
        self.FireBullets( uint( m_pellets ), src, dir, spread, TOWER_RANGE + 200.0f, BULLET_PLAYER_CUSTOMDAMAGE, 2, m_dmg, self.pev );
        g_SoundSystem.EmitSoundDyn( self.edict(), CHAN_WEAPON, m_snd, 0.9f, 0.6f, 0, 94 + Math.RandomLong( 0, 15 ) );
        if( gun !is null ) gun.pev.effects |= EF_MUZZLEFLASH;
        --m_clip;
        if( !t.IsAlive() ) ++m_kills;
    }

    void Destroyed()
    {
        pev.deadflag = DEAD_DEAD;
        pev.takedamage = DAMAGE_NO;
        g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] " + OwnerName() + " " + m_label + " tower was destroyed (gun gone)\n" );
        g_EntityFuncs.CreateExplosion( pev.origin + Vector( 0, 0, 20 ), Vector( 0, 0, 0 ), null, 40, false );
        CBaseEntity@ gun = m_hGun.GetEntity();
        if( gun !is null ) g_EntityFuncs.Remove( gun );
        CBaseEntity@ bang = m_hBang.GetEntity();
        if( bang !is null ) g_EntityFuncs.Remove( bang );
        g_EntityFuncs.Remove( self );
    }
}

array<EHandle> g_Towers;

CTdTower@ TowerOf( CBaseEntity@ e )
{
    if( e is null ) return null;
    return cast<CTdTower@>( g_EntityFuncs.CastToScriptClass( e ) );
}

// remembered every tick: what each player carries (gun -> clip, reserve, clip size) so a drop
// knows how much ammo went with the gun
dictionary g_Carry;   // "playerindex|cls" -> array<int> { clip, reserve, clipMax }

void RememberCarry()
{
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p is null || !p.IsConnected() || !p.IsAlive() ) continue;
        for( uint k = 0; k < g_TowerGuns.length(); ++k )
        {
            CBasePlayerItem@ it = p.HasNamedPlayerItem( g_TowerGuns[k].cls );
            if( it is null ) continue;
            CBasePlayerWeapon@ w = cast<CBasePlayerWeapon@>( it );
            if( w is null ) continue;
            Gun@ g = GunByClass( g_TowerGuns[k].cls );
            int clipMax = g !is null ? g.clip + ClipBonus( p, g ) : w.iMaxClip();
            int reserve = w.m_iPrimaryAmmoType >= 0 ? p.m_rgAmmo( w.m_iPrimaryAmmoType ) : 0;
            array<int> v = { w.m_iClip, reserve, clipMax, w.m_iPrimaryAmmoType };
            g_Carry[string( i ) + "|" + g_TowerGuns[k].cls] = v;
        }
    }
}

// a CS gun lying in the world (nobody holds it) = it was just dropped -> grow a tower there
void CheckDroppedGuns()
{
    for( uint k = 0; k < g_TowerGuns.length(); ++k )
    {
        TowerGun@ tg = g_TowerGuns[k];
        CBaseEntity@ e = null;
        while( ( @e = g_EntityFuncs.FindEntityByClassname( e, tg.cls ) ) !is null )
        {
            CBasePlayerItem@ it = cast<CBasePlayerItem@>( e );
            if( it is null || it.m_hPlayer.IsValid() ) continue;          // carried
            CBaseEntity@ box = e.pev.owner !is null ? g_EntityFuncs.Instance( e.pev.owner ) : null;
            Vector at = ( box !is null && box.GetClassname() == "weaponbox" ) ? box.pev.origin : e.pev.origin;
            if( box is null && ( e.pev.effects & EF_NODRAW ) != 0 ) continue;

            if( g_TdTowers.GetInt() == 0 )
                continue;   // towers off: a dropped gun is just a gun on the floor

            // who dropped it: nearest player who no longer carries this gun but did a moment ago
            CBasePlayer@ owner = null;
            float bd = 260.0f;
            array<int> carry = { 0, 0, 30, -1 };
            for( int i = 1; i <= g_Engine.maxClients; ++i )
            {
                CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
                if( p is null || !p.IsConnected() ) continue;
                if( p.HasNamedPlayerItem( tg.cls ) !is null ) continue;
                float d = ( p.pev.origin - at ).Length();
                string key = string( i ) + "|" + tg.cls;
                if( d < bd && g_Carry.exists( key ) ) { bd = d; @owner = p; carry = cast<array<int>>( g_Carry[key] ); }
            }
            if( owner is null ) continue;   // a gun nobody just dropped (should not happen)
            g_Carry.delete( string( owner.entindex() ) + "|" + tg.cls );

            int reserve = carry[1];
            if( carry[3] >= 0 )
            {
                int left = owner.m_rgAmmo( carry[3] );
                if( left > 0 ) owner.m_rgAmmo( carry[3], 0 );   // the spare mags go into the tower too
            }
            if( box !is null && box.GetClassname() == "weaponbox" ) g_EntityFuncs.Remove( box );
            g_EntityFuncs.Remove( e );
            BuildTower( owner, tg, at, carry[2], carry[0], reserve );
            @e = null;   // restart the search, entities were removed
        }
    }
}

void BuildTower( CBasePlayer@ owner, TowerGun@ tg, const Vector& in at, int clipMax, int clip, int reserve )
{
    Vector feet = FloorAt( at + Vector( 0, 0, 8 ) );
    dictionary kv;
    kv["origin"] = string( feet.x ) + " " + string( feet.y ) + " " + string( feet.z + 1.0f );
    kv["angles"] = "0 " + string( owner.pev.angles.y ) + " 0";
    Gun@ g = GunByClass( tg.cls );
    string label = g !is null ? g.label : tg.cls;
    kv["displayname"] = label + " Tower";
    CBaseEntity@ e = g_EntityFuncs.CreateEntity( "td_tower", kv, true );
    CTdTower@ t = TowerOf( e );
    if( t is null ) { g_Game.AlertMessage( at_console, "[cs_td] tower create failed\n" ); return; }
    t.Setup( tg, clipMax, clip, reserve, owner );
    g_Towers.insertLast( EHandle( e ) );
    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] " + string( owner.pev.netname ) + " built a tower: " + label + " ("
        + tg.dmg + " dmg x" + tg.pellets + ", " + int( 60.0f / tg.rate + 0.5f ) + " rpm, ammo " + clip + "/" + reserve
        + ", HP " + int( e.pev.max_health ) + ")\n" );
}

// ------------------------------------------------------------------ guards and gold miners

array<array<EHandle>> g_Miners;   // per mine: unarmed workers (income)
array<array<EHandle>> g_Guards;   // per mine: armed soldiers (never replaced)
array<array<EHandle>> g_GuardPosts;   // per mine, per guard: where he stands (info_target)
dictionary g_GuardDue;                // guard entindex -> next time he may be sent home again
array<float> g_NextAlert;

int AliveIn( const array<EHandle>& in hs )
{
    int n = 0;
    for( uint k = 0; k < hs.length(); ++k )
    {
        CBaseEntity@ e = hs[k].GetEntity();
        if( e !is null && e.IsAlive() ) ++n;
    }
    return n;
}

int AliveMiners( uint mi ) { return AliveIn( g_Miners[mi] ); }
int AliveGuards( uint mi ) { return AliveIn( g_Guards[mi] ); }

int AllAliveMiners()
{
    int n = 0;
    for( uint i = 0; i < g_Miners.length(); ++i )
        if( MineAlive( g_Mines[i].GetEntity() ) ) n += AliveMiners( i );
    return n;
}

// a free floor spot 80-170 units around mine mi
bool SpotNearMine( uint mi, Vector& out feet )
{
    CBaseEntity@ mine = g_Mines[mi].GetEntity();
    if( !MineAlive( mine ) ) return false;
    Vector at = mine.pev.origin;
    for( int tries = 0; tries < 24; ++tries )
    {
        float a = Math.RandomFloat( 0.0f, 6.2831853f );
        float r = Math.RandomFloat( 80.0f, 170.0f );
        Vector c = at + Vector( cos( a ) * r, sin( a ) * r, 40.0f );
        TraceResult tr;
        g_Utility.TraceLine( c, c - Vector( 0, 0, 200 ), ignore_monsters, null, tr );
        if( tr.fStartSolid != 0 || tr.flFraction >= 1.0f ) continue;
        if( !SpotFree( tr.vecEndPos ) ) continue;
        feet = tr.vecEndPos;
        return true;
    }
    return false;
}

bool SpawnGuard( uint mi )
{
    Vector feet;
    if( !SpotNearMine( mi, feet ) ) return false;
    dictionary kv;
    kv["origin"] = string( feet.x ) + " " + string( feet.y ) + " " + string( feet.z + 4.0f );
    kv["angles"] = "0 " + string( Math.RandomFloat( 0, 360 ) ) + " 0";
    kv["displayname"] = g_MineNames[mi] + " Mine Guard";
    kv["is_player_ally"] = "1";
    kv["weapons"] = "8";   // shotgun: the stock MP5 (6 dmg a round) barely scratches a zombie
    kv["targetname"] = "td_guard";
    CBaseEntity@ e = g_EntityFuncs.CreateEntity( GUARD_CLASS, kv, true );
    if( e is null ) return false;
    e.SetClassification( CLASS_PLAYER_ALLY );
    e.pev.health = GUARD_HP;
    e.pev.max_health = GUARD_HP;
    g_Guards[mi].insertLast( EHandle( e ) );
    // his post: an invisible marker he walks back to when there is nothing to shoot
    dictionary pk;
    pk["origin"] = string( feet.x ) + " " + string( feet.y ) + " " + string( feet.z + 4.0f );
    pk["targetname"] = "td_guard_post";
    CBaseEntity@ post = g_EntityFuncs.CreateEntity( "info_target", pk, true );
    g_GuardPosts[mi].insertLast( EHandle( post ) );
    return true;
}

// a guard who chased a monster away from his mine (and then stood in a doorway, blocking the ammo
// carrier) walks back to his post once nothing is left to shoot
void GuardsGoHome()
{
    for( uint mi = 0; mi < g_Guards.length(); ++mi )
    {
        for( uint k = 0; k < g_Guards[mi].length() && k < g_GuardPosts[mi].length(); ++k )
        {
            CBaseEntity@ e = g_Guards[mi][k].GetEntity();
            CBaseEntity@ post = g_GuardPosts[mi][k].GetEntity();
            if( e is null || post is null || !e.IsAlive() ) continue;
            CBaseMonster@ m = e.MyMonsterPointer();
            if( m is null ) continue;
            CBaseEntity@ en = m.m_hEnemy.IsValid() ? m.m_hEnemy.GetEntity() : null;
            if( en !is null && en.IsAlive() && m.FVisible( en, true ) ) continue;   // still fighting
            if( ( post.pev.origin - e.pev.origin ).Length2D() <= GUARD_LEASH ) continue;
            string key = "g" + e.entindex();
            float due = g_GuardDue.exists( key ) ? float( g_GuardDue[key] ) : 0.0f;
            if( g_Engine.time < due ) continue;   // already on his way: re-issue every few seconds only
            g_GuardDue[key] = g_Engine.time + 4.0f;
            m.m_hTargetEnt = EHandle( post );
            Schedule@ sch = m.GetScheduleOfType( SCHED_TARGET_CHASE );
            if( sch !is null ) m.ChangeSchedule( sch );
        }
    }
}

bool SpawnMiner( uint mi )
{
    Vector feet;
    if( !SpotNearMine( mi, feet ) ) return false;
    CBaseEntity@ mine = g_Mines[mi].GetEntity();
    dictionary kv;
    kv["origin"] = string( feet.x ) + " " + string( feet.y ) + " " + string( feet.z + 4.0f );
    kv["angles"] = "0 " + string( Math.VecToYaw( mine.pev.origin - feet ) ) + " 0";   // facing the mine
    kv["displayname"] = g_MineNames[mi] + " Gold Miner";
    kv["targetname"] = "td_miner";
    CBaseEntity@ e = g_EntityFuncs.CreateEntity( "td_worker", kv, true );
    if( e is null ) return false;
    g_Miners[mi].insertLast( EHandle( e ) );
    return true;
}

// an unarmed scientist standing at the mine, idling (looks around, ponders, checks his tie); fragile, never fights
class CTdWorker : ScriptBaseMonsterEntity
{
    int m_workSeq = -1;
    array<int> m_idles;
    float m_removeAt = 0.0f;

    void Spawn()
    {
        Precache();
        pev.movetype   = MOVETYPE_STEP;
        pev.solid      = SOLID_SLIDEBOX;
        pev.takedamage = DAMAGE_YES;
        pev.flags     |= FL_MONSTER;
        pev.deadflag   = DEAD_NO;
        pev.health     = MINER_HP;
        pev.max_health = MINER_HP;
        g_EntityFuncs.SetModel( self, MINER_MODEL );
        g_EntityFuncs.SetSize( self.pev, VEC_HUMAN_HULL_MIN, VEC_HUMAN_HULL_MAX );
        pev.view_ofs = Vector( 0, 0, 50 );
        self.m_bloodColor = BLOOD_COLOR_RED;
        self.SetClassification( CLASS_PLAYER_ALLY );
        array<string> names = { "idle1", "idle3", "pondering", "pondering2", "checktie", "eye_wipe" };
        for( uint k = 0; k < names.length(); ++k ) { int s = self.LookupSequence( names[k] ); if( s >= 0 ) m_idles.insertLast( s ); }
        m_workSeq = self.LookupActivity( ACT_IDLE );
        Play( NextIdle() );
        g_EngineFuncs.DropToFloor( self.edict() );
        SetThink( ThinkFunction( this.WorkThink ) );
        pev.nextthink = g_Engine.time + 0.1f;
    }

    void Precache() { g_Game.PrecacheModel( MINER_MODEL ); }

    int Classify() { return CLASS_PLAYER_ALLY; }

    void Play( int seq )
    {
        if( seq < 0 ) return;
        pev.sequence = seq;
        pev.frame = 0;
        self.ResetSequenceInfo();
    }

    int TakeDamage( entvars_t@ pevInflictor, entvars_t@ pevAttacker, float flDamage, int bitsDamageType )
    {
        if( pev.deadflag != DEAD_NO ) return 0;
        CBaseEntity@ att = pevAttacker !is null ? g_EntityFuncs.Instance( pevAttacker ) : null;
        if( att !is null && ( att.IsPlayer() || att.Classify() == CLASS_PLAYER_ALLY ) ) return 0;
        pev.health -= flDamage;
        if( pev.health <= 0 )
        {
            pev.deadflag = DEAD_DYING;
            pev.takedamage = DAMAGE_NO;
            pev.solid = SOLID_NOT;
            pev.flags &= ~FL_MONSTER;
            g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] A gold miner was killed\n" );
            Play( self.LookupActivity( ACT_DIESIMPLE ) );
            m_removeAt = g_Engine.time + 4.0f;
            return 0;
        }
        return 1;
    }

    void WorkThink()
    {
        pev.nextthink = g_Engine.time + 0.1f;
        self.StudioFrameAdvance();
        if( pev.deadflag != DEAD_NO )
        {
            if( g_Engine.time >= m_removeAt ) g_EntityFuncs.Remove( self );
            return;
        }
        if( self.m_fSequenceFinished ) Play( NextIdle() );
    }

    int NextIdle() { return m_idles.length() > 0 ? m_idles[Math.RandomLong( 0, m_idles.length() - 1 )] : m_workSeq; }
}

void Alarm( uint mi )
{
    if( g_Engine.time < g_NextAlert[mi] ) return;
    g_NextAlert[mi] = g_Engine.time + ALERT_COOLDOWN;
    HUDTextParams tp;
    tp.channel = 3; tp.x = -1; tp.y = 0.38; tp.effect = 1;
    tp.r1 = 255; tp.g1 = 60; tp.b1 = 40; tp.a1 = 255;
    tp.r2 = 255; tp.g2 = 255; tp.b2 = 255; tp.a2 = 255;
    tp.fadeinTime = 0.05; tp.fadeoutTime = 0.5; tp.holdTime = 3.0; tp.fxTime = 0.3;
    g_PlayerFuncs.HudMessageAll( tp, "GOLD MINE " + g_MineNames[mi] + ": ENEMY SPOTTED!" );   // text only, no siren (too loud)
}

bool SeesMonster( const array<EHandle>& in hs )
{
    for( uint k = 0; k < hs.length(); ++k )
    {
        CBaseEntity@ me = hs[k].GetEntity();
        if( me is null || !me.IsAlive() ) continue;
        for( uint j = 0; j < g_Alive.length(); ++j )
        {
            CBaseEntity@ e = g_Alive[j].GetEntity();
            if( e is null || !e.IsAlive() ) continue;
            if( ( e.pev.origin - me.pev.origin ).Length() > ALERT_DIST ) continue;
            TraceResult tr;
            g_Utility.TraceLine( me.pev.origin + me.pev.view_ofs, e.pev.origin + e.pev.view_ofs, ignore_monsters, me.edict(), tr );
            if( tr.flFraction >= 1.0f ) return true;
        }
    }
    return false;
}

// a living guard or miner with a monster in sight -> alarm for that mine
void MinerWatch()
{
    for( uint mi = 0; mi < g_Mines.length(); ++mi )
    {
        if( !MineAlive( g_Mines[mi].GetEntity() ) ) continue;
        if( SeesMonster( g_Guards[mi] ) || SeesMonster( g_Miners[mi] ) ) Alarm( mi );
    }
}

void HireMiner( CBasePlayer@ p, uint mi )
{
    if( mi >= g_Mines.length() ) return;
    if( !MineAlive( g_Mines[mi].GetEntity() ) )
    { g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Gold mine " + g_MineNames[mi] + " is destroyed" ); return; }
    if( AliveMiners( mi ) >= MINER_MAX )
    { g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Gold mine " + g_MineNames[mi] + " already has " + MINER_MAX + " miners" ); return; }
    if( GetMoney( p ) < MINER_PRICE )
    { g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "A miner costs $" + MINER_PRICE ); return; }
    if( !SpawnMiner( mi ) )
    { g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "No room for a miner at " + g_MineNames[mi] ); return; }
    AddMoney( p, -MINER_PRICE );
    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] " + string( p.pev.netname ) + " hired a miner for gold mine " + g_MineNames[mi]
        + " (" + AliveMiners( mi ) + "/" + MINER_MAX + ", -$" + MINER_PRICE + ")\n" );
}

// ------------------------------------------------------------------ ammo carriers

array<EHandle> g_Carriers;

void HireCarrier( CBasePlayer@ p )
{
    if( GetMoney( p ) < CARRIER_PRICE )
    { g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "An ammo carrier costs $" + CARRIER_PRICE ); return; }
    Vector spot;
    if( !FindPropSpot( p.pev.origin - Vector( 0, 0, 36 ), p.pev.angles.y, spot ) ) spot = p.pev.origin - Vector( 0, 0, 36 );
    dictionary kv;
    kv["origin"] = string( spot.x ) + " " + string( spot.y ) + " " + string( spot.z + 4.0f );
    kv["angles"] = "0 " + string( p.pev.angles.y ) + " 0";
    kv["displayname"] = "Ammo Carrier";
    kv["targetname"] = "td_carrier";
    CBaseEntity@ e = g_EntityFuncs.CreateEntity( "td_carrier", kv, true );
    if( e is null ) return;
    @e.pev.owner = p.edict();   // the hirer pays for the ammo he buys
    g_Carriers.insertLast( EHandle( e ) );
    AddMoney( p, -CARRIER_PRICE );
    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] " + string( p.pev.netname ) + " hired an ammo carrier (-$" + CARRIER_PRICE
        + "; he buys up to " + CARRIER_LOAD + " rounds a trip at the Arms Dealer, on your money)\n" );
}

void CarrierThink()
{
    for( uint i = 0; i < g_Carriers.length(); )
    {
        CBaseEntity@ c = g_Carriers[i].GetEntity();
        if( c is null || c.pev.deadflag != DEAD_NO ) { g_Carriers.removeAt( i ); continue; }
        ++i;
    }
}

// the nearest tower that is short of ammo
CBaseEntity@ TowerNeedingAmmo( const Vector& in from )
{
    CBaseEntity@ best = null;
    float bd = 1.0e9f;
    for( uint k = 0; k < g_Towers.length(); ++k )
    {
        CBaseEntity@ te = g_Towers[k].GetEntity();
        CTdTower@ t = TowerOf( te );
        if( t is null || te.pev.deadflag != DEAD_NO || !t.NeedsAmmo() ) continue;
        float d = ( te.pev.origin - from ).Length();
        if( d < bd ) { bd = d; @best = te; }
    }
    return best;
}

Vector DealerPos() { return g_Stations.length() > 0 ? g_Stations[0] : Vector( 0, 0, 0 ); }

// a scripted walker (the stock scientist AI runs away from gunfire): it asks the node graph for a
// route (FGetNodeRoute) and steps along it with the engine's MoveToOrigin; no weapon, can be killed.
// v2 loop: empty -> walk to the Arms Dealer and buy up to CARRIER_LOAD rounds (hirer's money) ->
// walk to the towers that need ammo, nearest first, until the load is gone -> back to the dealer.
class CTdCarrier : ScriptBaseMonsterEntity
{
    array<Vector> m_path;
    uint m_next = 0;
    Vector m_goalPos;
    bool m_hasGoal = false;
    float m_nextRoute = 0.0f;
    float m_stuckSince = 0.0f;
    int m_stuckCount = 0;
    float m_bestDist = 1.0e9f;
    int m_walkSeq = -1;
    int m_idleSeq = -1;
    int m_load = 0;              // rounds carried
    float m_nextBroke = 0.0f;

    void Spawn()
    {
        Precache();
        pev.movetype   = MOVETYPE_STEP;
        pev.solid      = SOLID_SLIDEBOX;
        pev.takedamage = DAMAGE_YES;
        pev.flags     |= FL_MONSTER;
        pev.deadflag   = DEAD_NO;
        pev.health     = CARRIER_HP;
        pev.max_health = CARRIER_HP;
        g_EntityFuncs.SetModel( self, "models/scientist.mdl" );
        pev.scale = CARRIER_SCALE;
        // 8 units wide -> the engine moves him with the point hull: no more snagging on door frames
        // and corners (the human hull is 32 wide); still 44 tall so bullets and claws can hit him
        g_EntityFuncs.SetSize( self.pev, Vector( -4, -4, 0 ), Vector( 4, 4, 44 ) );
        pev.view_ofs = Vector( 0, 0, 38 );
        self.m_bloodColor = BLOOD_COLOR_RED;
        self.SetClassification( CLASS_PLAYER_ALLY );
        m_walkSeq = self.LookupActivity( ACT_WALK );
        m_idleSeq = self.LookupActivity( ACT_IDLE );
        g_EngineFuncs.DropToFloor( self.edict() );
        SetThink( ThinkFunction( this.CarrierWalk ) );
        pev.nextthink = g_Engine.time + 0.1f;
    }

    void Precache() { g_Game.PrecacheModel( "models/scientist.mdl" ); }

    int Classify() { return CLASS_PLAYER_ALLY; }

    int TakeDamage( entvars_t@ pevInflictor, entvars_t@ pevAttacker, float flDamage, int bitsDamageType )
    {
        if( pev.deadflag != DEAD_NO ) return 0;
        CBaseEntity@ att = pevAttacker !is null ? g_EntityFuncs.Instance( pevAttacker ) : null;
        if( att !is null && ( att.IsPlayer() || att.Classify() == CLASS_PLAYER_ALLY ) ) return 0;
        pev.health -= flDamage;
        if( pev.health <= 0 )
        {
            pev.deadflag = DEAD_DEAD;
            pev.takedamage = DAMAGE_NO;
            g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] The ammo carrier was killed" + ( m_load > 0 ? " (" + m_load + " rounds lost)" : "" ) + "\n" );
            g_EntityFuncs.SpawnRandomGibs( self.pev, 1, 1 );
            g_EntityFuncs.Remove( self );
            return 0;
        }
        return 1;
    }

    void SetSeq( int seq )
    {
        if( seq < 0 || pev.sequence == seq ) return;
        pev.sequence = seq;
        pev.frame = 0;
        self.ResetSequenceInfo();
    }

    CBasePlayer@ Payer()
    {
        if( pev.owner is null ) return null;
        CBaseEntity@ o = g_EntityFuncs.Instance( pev.owner );
        CBasePlayer@ p = cast<CBasePlayer@>( o );
        return ( p !is null && p.IsConnected() ) ? p : null;
    }

    // at the dealer: buy rounds for the towers that need them (nearest to the dealer first), up to
    // CARRIER_LOAD and as far as the hirer's money goes, each round at its gun's shop price
    void Buy()
    {
        CBasePlayer@ p = Payer();
        int money = p !is null ? GetMoney( p ) : 0;
        int rounds = 0, cost = 0;
        array<CTdTower@> ts;
        array<float> ds;
        for( uint k = 0; k < g_Towers.length(); ++k )
        {
            CTdTower@ t = TowerOf( g_Towers[k].GetEntity() );
            if( t is null || t.pev.deadflag != DEAD_NO || !t.NeedsAmmo() ) continue;
            float d = ( t.pev.origin - pev.origin ).Length();
            uint at = 0;
            while( at < ds.length() && ds[at] < d ) ++at;
            ts.insertAt( at, t ); ds.insertAt( at, d );
        }
        for( uint k = 0; k < ts.length() && rounds < CARRIER_LOAD; ++k )
        {
            int need = ts[k].Deficit();
            if( need > CARRIER_LOAD - rounds ) need = CARRIER_LOAD - rounds;
            int unit = ts[k].UnitPrice();
            int afford = unit > 0 ? ( money - cost ) / unit : need;
            if( need > afford ) need = afford;
            if( need <= 0 ) break;
            rounds += need; cost += need * unit;
        }
        if( rounds <= 0 )
        {
            if( g_Engine.time >= m_nextBroke )
            {
                m_nextBroke = g_Engine.time + 15.0f;
                g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] Ammo carrier is waiting at the Arms Dealer: "
                    + ( p !is null ? string( p.pev.netname ) + " can't pay for ammo" : "nobody to pay for ammo" ) + "\n" );
            }
            return;
        }
        AddMoney( p, -cost );
        m_load = rounds;
        g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] Ammo carrier bought " + rounds + " rounds (-$" + cost + ", " + string( p.pev.netname ) + ")\n" );
    }

    void Route( const Vector& in goal )
    {
        m_path.resize( 0 );
        m_next = 0;
        if( self.FGetNodeRoute( goal ) )
        {
            for( uint i = 0; i < ROUTE_SIZE; ++i )
            {
                Waypoint@ wp = self.m_Route( i );
                if( wp.iType == 0 ) break;                   // past the end of the route
                // stale entries from an older route: a point we already have, or a jump across the map
                bool stale = false;
                for( uint j = 0; j < m_path.length(); ++j )
                    if( ( m_path[j] - wp.vecLocation ).Length() < 1.0f ) stale = true;
                Vector prev = m_path.length() > 0 ? m_path[m_path.length() - 1] : pev.origin;
                if( stale || ( wp.vecLocation - prev ).Length() > 700.0f ) break;
                m_path.insertLast( wp.vecLocation );
                if( ( wp.iType & bits_MF_IS_GOAL ) != 0 ) break;
            }
        }
        if( m_path.length() == 0 || ( m_path[m_path.length() - 1] - goal ).Length() > 64.0f )
            m_path.insertLast( goal );           // finish (or, with no route, go) straight to the goal
        // the first node is often behind us: skip it when the second one is closer to us than to it
        if( m_path.length() > 1 && ( m_path[1] - pev.origin ).Length() < ( m_path[1] - m_path[0] ).Length() ) m_next = 1;
        m_stuckCount = 0;
    }

    void CarrierWalk()
    {
        pev.nextthink = g_Engine.time + 0.1f;
        if( pev.deadflag != DEAD_NO ) return;
        self.StudioFrameAdvance();

        Vector goal;
        float reach;
        CBaseEntity@ tower = null;
        if( m_load > 0 )
        {
            @tower = TowerNeedingAmmo( pev.origin );
            if( tower is null ) { SetSeq( m_idleSeq ); m_path.resize( 0 ); m_hasGoal = false; return; }   // keep the load, wait
            goal = tower.pev.origin; reach = CARRIER_REACH;
        }
        else
        {
            if( TowerNeedingAmmo( pev.origin ) is null || g_Stations.length() == 0 ) { SetSeq( m_idleSeq ); m_path.resize( 0 ); m_hasGoal = false; return; }
            goal = DealerPos(); reach = DEALER_REACH;
        }

        if( ( goal - pev.origin ).Length2D() <= reach )
        {
            if( tower !is null )
            {
                CTdTower@ t = TowerOf( tower );
                if( t !is null )
                {
                    int given = t.AddAmmo( m_load );
                    m_load -= given;
                    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] Ammo carrier gave " + given + " rounds to " + t.OwnerName() + " " + t.m_label
                        + " tower (" + t.m_clip + "/" + t.m_reserve + "), " + m_load + " left\n" );
                }
            }
            else Buy();
            SetSeq( m_idleSeq );
            m_path.resize( 0 );
            m_hasGoal = false;
            return;
        }

        if( !m_hasGoal || ( m_goalPos - goal ).Length() > 32.0f || m_path.length() == 0 || g_Engine.time >= m_nextRoute )
        {
            m_goalPos = goal; m_hasGoal = true;
            Route( goal );
            m_nextRoute = g_Engine.time + 10.0f;
        }
        if( m_next >= m_path.length() ) { m_nextRoute = 0.0f; return; }

        Vector to = m_path[m_next];
        Vector delta = to - pev.origin;
        if( delta.Length2D() < 24.0f ) { ++m_next; m_bestDist = 1.0e9f; m_stuckSince = g_Engine.time; return; }
        float yaw = Math.VecToYaw( delta );
        pev.angles = Vector( 0, yaw, 0 );
        pev.ideal_yaw = yaw;
        g_EngineFuncs.MoveToOrigin( self.edict(), to, 16.0f, 0 );   // ~160 units/s
        SetSeq( m_walkSeq );

        // stuck = no progress toward the current point for 2 s (it can also jitter on the spot)
        float dnow = ( to - pev.origin ).Length2D();
        if( dnow < m_bestDist - 12.0f ) { m_bestDist = dnow; m_stuckSince = g_Engine.time; return; }
        if( g_Engine.time - m_stuckSince < 2.0f ) return;
        m_bestDist = 1.0e9f;
        m_stuckSince = g_Engine.time;
        ++m_stuckCount;
        if( m_stuckCount % 2 == 1 && m_next + 1 < m_path.length() ) { ++m_next; return; }
        // monsters never step off a ledge higher than 18 units: hop over it (only into free space)
        Vector flat( delta.x, delta.y, 0 );
        flat = flat.Normalize();
        bool hopped = false;
        for( int hgt = 8; hgt <= 48 && !hopped; hgt += 20 )
        {
            for( int k = 0; k < 3 && !hopped; ++k )
            {
                float dist = 56.0f - 16.0f * float( k );
                Vector cand = pev.origin + flat * dist;
                cand.z = ( to.z > pev.origin.z ? to.z : pev.origin.z ) + float( hgt );
                TraceResult th;
                g_Utility.TraceHull( cand, cand, ignore_monsters, head_hull, self.edict(), th );
                if( th.fStartSolid != 0 || th.fAllSolid != 0 ) continue;
                TraceResult tl;   // and a clear line to it (no hopping through walls)
                g_Utility.TraceLine( pev.origin + Vector( 0, 0, float( hgt ) + 20.0f ), cand + Vector( 0, 0, 20 ), ignore_monsters, self.edict(), tl );
                if( tl.flFraction < 1.0f ) continue;
                g_EntityFuncs.SetOrigin( self, cand );
                g_EngineFuncs.DropToFloor( self.edict() );
                hopped = true;
            }
        }
        if( m_stuckCount > 6 ) m_nextRoute = 0.0f;
    }
}

// ------------------------------------------------------------------ hire menu (Arms Dealer -> Hire)

CTextMenu@ g_MenuHire = null;

void BuildHireMenu()
{
    @g_MenuHire = CTextMenu( TextMenuPlayerSlotCallback( @HireMenuCallback ) );
    g_MenuHire.SetTitle( "Hire\n" );
    g_MenuHire.AddItem( "Miner for gold mine A  $" + MINER_PRICE );
    g_MenuHire.AddItem( "Miner for gold mine B  $" + MINER_PRICE );
    g_MenuHire.AddItem( "Ammo carrier  $" + CARRIER_PRICE );
    g_MenuHire.Register();
}

void TdOpenHireMenu( CBasePlayer@ p )
{
    if( g_MenuHire is null ) return;
    string t = "Hire   ($" + GetMoney( p ) + ")\n";
    for( uint i = 0; i < g_Mines.length(); ++i )
        t += "mine " + g_MineNames[i] + ": " + ( MineAlive( g_Mines[i].GetEntity() ) ? string( AliveMiners( i ) ) + "/" + MINER_MAX + " miners, "
            + AliveGuards( i ) + " guards" : "destroyed" ) + "\n";
    g_MenuHire.SetTitle( t );
    g_MenuHire.Open( 0, 0, p );
}

void HireMenuCallback( CTextMenu@ menu, CBasePlayer@ pPlayer, int iSlot, const CTextMenuItem@ pItem )
{
    if( pItem is null || pPlayer is null ) return;
    string c = pItem.m_szName;
    if( c.Find( "gold mine A" ) != String::INVALID_INDEX ) HireMiner( pPlayer, 0 );
    else if( c.Find( "gold mine B" ) != String::INVALID_INDEX ) HireMiner( pPlayer, 1 );
    else if( c.Find( "Ammo carrier" ) != String::INVALID_INDEX ) HireCarrier( pPlayer );
}

// ------------------------------------------------------------------ income, defeat, HUD

float g_NextIncome = 0.0f;

void TdThink()
{
    if( g_TowerGuns.length() == 0 ) return;
    RememberCarry();
    CheckDroppedGuns();

    if( g_Engine.time >= g_NextIncome )
    {
        g_NextIncome = g_Engine.time + 1.0f;
        if( g_State == PVE_WAVE || g_State == PVE_CLEARED || g_State == PVE_COUNTDOWN )
        {
            MinerWatch();
            GuardsGoHome();
            CarrierThink();
            int pay = MINE_INCOME * AliveMines() + MINER_INCOME * AllAliveMiners();
            if( pay > 0 ) AddMoneyAll( pay );
            if( AliveMines() == 0 && g_Mines.length() > 0 )
            {
                Big( "Both gold mines are destroyed!" );
                Defeat();
            }
        }
    }
}

string TdHudLine( CBasePlayer@ p )
{
    string s = "";
    for( uint i = 0; i < g_Mines.length(); ++i )
    {
        CBaseEntity@ m = g_Mines[i].GetEntity();
        s += "   " + g_MineNames[i] + " mine " + ( MineAlive( m ) ? string( int( m.pev.health ) ) + " (" + AliveMiners( i ) + " miners " + AliveGuards( i ) + " guards)" : "X" );
    }
    s += "   +$" + ( MINE_INCOME * AliveMines() + MINER_INCOME * AllAliveMiners() ) + "/s";
    return s;
}

// ------------------------------------------------------------------ test cheats (sv_cheats 1)

bool TdCheat( CBasePlayer@ p )
{
    if( g_EngineFuncs.CVarGetFloat( "sv_cheats" ) > 0.0f ) return true;
    g_PlayerFuncs.ClientPrint( p, HUD_PRINTTALK, "[TD] test cheats need sv_cheats 1\n" );
    return false;
}

bool TdClientSay( SayParameters@ pParams )
{
    CBasePlayer@ p = pParams.GetPlayer();
    const CCommand@ args = pParams.GetArguments();
    if( p is null || args.ArgC() < 1 ) return false;
    string a = args.Arg( 0 ).ToLowercase();
    if( a == "!tdmoney" )
    {
        pParams.ShouldHide = true;
        if( TdCheat( p ) ) SetMoney( p, 100000 );
        return true;
    }
    if( a == "!tdskip" )
    {
        pParams.ShouldHide = true;
        if( !TdCheat( p ) ) return true;
        ClearRemaining();
        int next = ( g_State == PVE_COUNTDOWN ) ? 0 : g_WaveIdx + 1;
        if( next < int( g_Waves.length() ) ) StartWave( next );
        return true;
    }
    if( a == "!tdbuild" )   // !tdbuild [weapon_x] = a full tower 150 units ahead (no gun needed)
    {
        pParams.ShouldHide = true;
        if( !TdCheat( p ) ) return true;
        string cls = args.ArgC() > 1 ? args.Arg( 1 ) : "weapon_ak47";
        for( uint i = 0; i < g_TowerGuns.length(); ++i )
        {
            if( g_TowerGuns[i].cls != cls ) continue;
            float y = p.pev.v_angle.y * Math.PI / 180.0f;
            Vector at = p.pev.origin + Vector( cos( y ), sin( y ), 0 ) * 150.0f - Vector( 0, 0, 36 );
            BuildTower( p, g_TowerGuns[i], at, 30, 30, 60 );
        }
        return true;
    }
    if( a == "!tdcam" )   // !tdcam [dist] [angleAround] [height] = stand by the newest tower, looking at it (filming)
    {
        pParams.ShouldHide = true;
        if( !TdCheat( p ) ) return true;
        CBaseEntity@ t = g_Towers.length() > 0 ? g_Towers[g_Towers.length() - 1].GetEntity() : null;
        if( t is null ) return true;
        float d = args.ArgC() > 1 ? atof( args.Arg( 1 ) ) : 110.0f;
        float y = args.ArgC() > 2 ? atof( args.Arg( 2 ) ) : 0.0f;
        float h = args.ArgC() > 3 ? atof( args.Arg( 3 ) ) : 10.0f;
        Vector dir = Vector( cos( y * Math.PI / 180.0f ), sin( y * Math.PI / 180.0f ), 0 );
        Vector at = t.pev.origin + dir * d + Vector( 0, 0, h + 36.0f );
        g_EntityFuncs.SetOrigin( p, at );
        p.pev.velocity = g_vecZero;
        Vector look = ( t.pev.origin + Vector( 0, 0, 34 ) ) - ( at + p.pev.view_ofs );
        Vector ang = Math.VecToAngles( look );
        p.pev.angles = Vector( -ang.x, ang.y, 0 );
        p.pev.v_angle = p.pev.angles;
        p.pev.fixangle = FAM_FORCEVIEWANGLES;
        return true;
    }
    if( a == "!tdempty" )   // every tower out of ammo
    {
        pParams.ShouldHide = true;
        if( !TdCheat( p ) ) return true;
        for( uint k = 0; k < g_Towers.length(); ++k )
        {
            CTdTower@ t = TowerOf( g_Towers[k].GetEntity() );
            if( t !is null ) { t.m_clip = 0; t.m_reserve = 0; }
        }
        return true;
    }
    if( a == "!tdhurt" )   // !tdhurt A 500
    {
        pParams.ShouldHide = true;
        if( !TdCheat( p ) ) return true;
        string w = args.ArgC() > 1 ? args.Arg( 1 ) : "A";
        w = w.ToUppercase();
        float dmg = args.ArgC() > 2 ? atof( args.Arg( 2 ) ) : 500.0f;
        for( uint i = 0; i < g_Mines.length(); ++i )
        {
            CBaseEntity@ m = g_Mines[i].GetEntity();
            if( m is null || g_MineNames[i] != w || !MineAlive( m ) ) continue;
            m.pev.health -= dmg;
            if( m.pev.health <= 0 ) MineDestroyed( m );
        }
        return true;
    }
    if( a == "!tdgo" )   // !tdgo a | b | spawn
    {
        pParams.ShouldHide = true;
        if( !TdCheat( p ) ) return true;
        string w = args.ArgC() > 1 ? args.Arg( 1 ) : "a";
        w = w.ToUppercase();
        Vector to = p.pev.origin;
        if( w == "DEALER" && g_Stations.length() > 0 )
        {
            Vector spot;
            to = FindPropSpot( g_Stations[0], 0.0f, spot ) ? spot + Vector( 0, 0, 37 ) : g_Stations[0] + Vector( 0, 0, 80 );
            Vector look = g_Stations[0] - to;
            p.pev.angles = Vector( 5, Math.VecToYaw( look ), 0 );
            p.pev.v_angle = p.pev.angles;
            p.pev.fixangle = FAM_FORCEVIEWANGLES;
        }
        else if( w == "SPAWN" )
        {
            CBaseEntity@ s = g_EntityFuncs.FindEntityByClassname( null, "info_player_start" );
            if( s !is null ) to = s.pev.origin;
        }
        else
        {
            for( uint i = 0; i < g_Mines.length(); ++i )
            {
                CBaseEntity@ m = g_Mines[i].GetEntity();
                if( m !is null && g_MineNames[i] == w ) to = m.pev.origin + Vector( -160, 0, 40 );
            }
        }
        g_EntityFuncs.SetOrigin( p, to );
        if( w == "A" || w == "B" )   // face the mine
        {
            p.pev.angles = Vector( 10, 0, 0 );
            p.pev.v_angle = p.pev.angles;
            p.pev.fixangle = FAM_FORCEVIEWANGLES;
        }
        return true;
    }
    if( a == "!tdhorde" )
    {
        pParams.ShouldHide = true;
        if( !TdCheat( p ) ) return true;
        int n = args.ArgC() > 1 ? atoi( args.Arg( 1 ) ) : 5;
        string cls = args.ArgC() > 2 ? args.Arg( 2 ) : "monster_zombie";
        if( n < 1 ) n = 1; if( n > 30 ) n = 30;
        g_EngineFuncs.MakeVectors( p.pev.v_angle );
        Vector fwd = g_Engine.v_forward; fwd.z = 0; fwd = fwd.Normalize();
        for( int k = 0; k < n; ++k )
        {
            Vector pos = p.pev.origin + fwd * ( 500.0f + 60.0f * float( k / 3 ) ) + g_Engine.v_right * ( 70.0f * float( k % 3 - 1 ) );
            CBaseEntity@ e = g_EntityFuncs.Create( cls, pos, Vector( 0, 0, 0 ), false, null );
            if( e is null ) continue;
            e.SetClassification( CLASS_ALIEN_MILITARY );
            CBaseMonster@ m = e.MyMonsterPointer();
            if( m !is null ) TdAimAtMine( m );
            g_Alive.insertLast( EHandle( e ) );
            g_IdleSecs.insertLast( 0 );
        }
        return true;
    }
    return false;
}

// ------------------------------------------------------------------ navigation aids for automated play (no gameplay effect)
// .tdpos prints your position; .tdface X Y turns you toward a point (yaw only)

void CmdTdPos( const CCommand@ args )
{
    CBasePlayer@ p = g_ConCommandSystem.GetCurrentPlayer();
    if( p is null ) return;
    string mines = "";
    for( uint i = 0; i < g_Mines.length(); ++i )
    {
        CBaseEntity@ m = g_Mines[i].GetEntity();
        mines += " " + ( MineAlive( m ) ? int( m.pev.health ) : 0 ) + "/" + ( MineAlive( m ) ? AliveMiners( i ) : 0 );
    }
    bool hasPrimary = false;
    for( uint k = 0; k < g_TowerGuns.length(); ++k )
    {
        Gun@ g = GunByClass( g_TowerGuns[k].cls );
        if( g !is null && g.slot != CAT_SIDE && p.HasNamedPlayerItem( g.cls ) !is null ) hasPrimary = true;
    }
    g_PlayerFuncs.ClientPrint( p, HUD_PRINTCONSOLE, "[tdpos] " + int( p.pev.origin.x ) + " " + int( p.pev.origin.y ) + " " + int( p.pev.origin.z )
        + " alive " + ( p.IsAlive() ? 1 : 0 ) + " money " + GetMoney( p ) + " wave " + ( g_WaveIdx + 1 ) + " state " + int( g_State )
        + " primary " + ( hasPrimary ? 1 : 0 ) + " mines" + mines + "\n" );
}

void CmdTdFace( const CCommand@ args )
{
    CBasePlayer@ p = g_ConCommandSystem.GetCurrentPlayer();
    if( p is null || args.ArgC() < 3 ) return;
    Vector to( atof( args.Arg( 1 ) ), atof( args.Arg( 2 ) ), p.pev.origin.z );
    float pitch = args.ArgC() > 3 ? atof( args.Arg( 3 ) ) : 0.0f;
    p.pev.angles = Vector( pitch, Math.VecToYaw( to - p.pev.origin ), 0 );
    p.pev.v_angle = p.pev.angles;
    p.pev.fixangle = FAM_FORCEVIEWANGLES;
}

CClientCommand g_CmdTdPos( "tdpos", "print your position", @CmdTdPos );
CClientCommand g_CmdTdFace( "tdface", "turn toward X Y [pitch]", @CmdTdFace );

// ------------------------------------------------------------------ lifecycle (called from core)

void TdMapInit()
{
    g_CustomEntityFuncs.RegisterCustomEntity( "CTdMine", "td_goldmine" );
    g_CustomEntityFuncs.RegisterCustomEntity( "CTdTower", "td_tower" );
    g_Game.PrecacheOther( "td_goldmine" );
    g_Game.PrecacheOther( "td_tower" );
    g_Game.PrecacheModel( MINE_MODEL );
    g_Game.PrecacheModel( TOWER_BASE_MODEL );
    g_Game.PrecacheOther( GUARD_CLASS );
    g_CustomEntityFuncs.RegisterCustomEntity( "CTdWorker", "td_worker" );
    g_Game.PrecacheOther( "td_worker" );
    g_Game.PrecacheModel( MINER_MODEL );
    g_Game.PrecacheModel( NOAMMO_SPRITE );
    g_CustomEntityFuncs.RegisterCustomEntity( "CTdCarrier", "td_carrier" );
    g_Game.PrecacheOther( "td_carrier" );
    BuildHireMenu();
    BuildTowerGuns();
    for( uint i = 0; i < g_TowerGuns.length(); ++i )
    {
        g_Game.PrecacheModel( g_TowerGuns[i].gunmodel );
        g_SoundSystem.PrecacheSound( g_TowerGuns[i].snd );
    }
    g_Scheduler.SetInterval( "TdThink", 0.1f, g_Scheduler.REPEAT_INFINITE_TIMES );
}

// mine spots = the map's two bomb sites (cs2sven put the objective zones into info_target pve_flank).
// The points are split into two groups (2-means); A = the group with the larger x (dust2: x>0).
// Falls back to TdMineA/B() from the map script.
void TdMapActivate()
{
    array<Vector> pts, a, b;
    CBaseEntity@ e = null;
    while( ( @e = g_EntityFuncs.FindEntityByTargetname( e, "pve_flank" ) ) !is null ) pts.insertLast( e.pev.origin );
    if( pts.length() >= 2 )
    {
        Vector ca = pts[0], cb = pts[0];
        float far = -1.0f;
        for( uint i = 0; i < pts.length(); ++i )
        {
            float d = ( pts[i] - ca ).Length();
            if( d > far ) { far = d; cb = pts[i]; }
        }
        for( int it = 0; it < 8; ++it )
        {
            a.resize( 0 ); b.resize( 0 );
            for( uint i = 0; i < pts.length(); ++i )
            {
                if( ( pts[i] - ca ).Length() <= ( pts[i] - cb ).Length() ) a.insertLast( pts[i] ); else b.insertLast( pts[i] );
            }
            if( a.length() == 0 || b.length() == 0 ) break;
            ca = Centre( a ); cb = Centre( b );
        }
        if( a.length() > 0 && b.length() > 0 && Centre( a ).x < Centre( b ).x ) { array<Vector> t = a; a = b; b = t; }
    }
    SpawnMine( a.length() > 0 ? Centre( a ) : TdMineA(), "A" );
    SpawnMine( b.length() > 0 ? Centre( b ) : TdMineB(), "B" );
    // monsters never spawn on the bomb sites (core falls back to the flank pool when the T spawns are busy)
    g_FlankSpawns.resize( 0 );
    g_FlankLast.resize( 0 );
}

Vector Centre( const array<Vector>& in pts )
{
    Vector s( 0, 0, 0 );
    for( uint i = 0; i < pts.length(); ++i ) s = s + pts[i];
    return s / float( pts.length() );
}

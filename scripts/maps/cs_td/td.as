/*
 * cs_td/td.as - tower-defence rules on top of cs_td/core.as (PJ-047 game spec v1, maps/dust2_td)
 *
 * - two gold mines (A / B bomb site), MINE_HP each; every mine pays everyone MINE_INCOME $/s
 * - every monster's goal is a gold mine; players / towers / NPCs it meets on the way get attacked too
 * - drop a CS gun (G) -> it becomes a tower that fires THAT gun (its damage, fire rate, pellets,
 *   magazine, sound); the gun is gone, a destroyed tower is gone. No price, no limit.
 *   Server variable td_towers 0 turns towers off.
 * - lose = both mines destroyed (no team lives); win = the last wave cleared
 * - gold miners: 1 per mine at the start, hire more at the Arms Dealer (MINER_PRICE, max MINER_MAX
 *   per mine); each pays +MINER_INCOME $/s, all of them shoot; a miner who sees a monster sounds the
 *   alarm (centre text + siren). Dead miners stay dead (hire again).
 * - ammo carrier: hire at the Arms Dealer (CARRIER_PRICE); walks to towers that are low on ammo
 *   and refills them; monsters can kill him
 *
 * Test cheats (sv_cheats 1 only; not for real play): !tdhorde N [class], !tdmoney, !tdskip,
 * !tdgo A|B|spawn, !tdhurt A|B dmg
 */

const int    MINE_HP          = 2000;
const int    MINE_INCOME      = 10;      // $ per second per standing mine, to every player
const string MINE_MODEL       = "models/crystal.mdl";
const float  RETARGET_DIST    = 900.0f;  // a monster chasing something else farther than this goes back to a mine

const int    MINER_PRICE      = 2000;
const int    MINER_MAX        = 5;       // per mine
const int    MINER_INCOME     = 10;      // $ per second per living miner, to every player
const string MINER_CLASS      = "monster_human_grunt_ally";
const float  ALERT_DIST       = 1100.0f; // a miner "sees" a monster this close (and in line of sight)
const float  ALERT_COOLDOWN   = 10.0f;
const string ALERT_SOUND      = "ambience/warn2.wav";
const int    CARRIER_PRICE    = 1000;
const string CARRIER_CLASS    = "monster_scientist";
const float  CARRIER_REACH    = 110.0f;

const string TOWER_BASE_MODEL = "models/mil_crate.mdl";
const int    TOWER_HP        = 400;
const float  TOWER_RANGE      = 1400.0f;
const float  TOWER_RELOAD     = 2.5f;
const float  TOWER_GUN_HEIGHT = 44.0f;   // gun above the floor

CCVar g_TdTowers( "td_towers", 1, "1 = a dropped gun grows into a tower, 0 = towers off", ConCommandFlag::AdminOnly );

// ------------------------------------------------------------------ gun table (stats read from the KernCore weapon scripts)

class TowerGun
{
    string cls;
    int dmg;
    float rate;     // seconds between shots
    int pellets;
    string snd;
    string wmodel;
    TowerGun( const string& in c, int d, float r, int p, const string& in s, const string& in w )
    { cls = c; dmg = d; rate = r; pellets = p; snd = s; wmodel = w; }
}

array<TowerGun@> g_TowerGuns;

void BuildTowerGuns()
{
    g_TowerGuns.insertLast( TowerGun( "weapon_csglock18",  CS16_GLOCK18::DAMAGE, CS16_GLOCK18::RPM_SINGLE, 1, CS16_GLOCK18::SHOOT_S, CS16_GLOCK18::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_usp",        CS16_USP::DAMAGE,     CS16_USP::RPM,     1, CS16_USP::SHOOT_S,     CS16_USP::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_p228",       CS16_P228::DAMAGE,    CS16_P228::RPM,    1, CS16_P228::SHOOT_S,    CS16_P228::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_csdeagle",   CS16_DEAGLE::DAMAGE,  CS16_DEAGLE::RPM,  1, CS16_DEAGLE::SHOOT_S,  CS16_DEAGLE::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_fiveseven",  CS16_57::DAMAGE,      CS16_57::RPM,      1, CS16_57::SHOOT_S,      CS16_57::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_dualelites", CS16_ELITES::DAMAGE,  CS16_ELITES::RPM,  1, CS16_ELITES::SHOOT_S,  CS16_ELITES::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_m3",         CS16_M3::DAMAGE,      CS16_M3::RPM_PUMP, CS16_M3::PELLETS, CS16_M3::SHOOT_S, CS16_M3::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_xm1014",     CS16_XM1014::DAMAGE,  CS16_XM1014::RPM,  CS16_XM1014::PELLETS, CS16_XM1014::SHOOT_S, CS16_XM1014::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_tmp",        CS16_TMP::DAMAGE,     CS16_TMP::RPM,     1, CS16_TMP::SHOOT_S,     CS16_TMP::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_mac10",      CS16_MAC10::DAMAGE,   CS16_MAC10::RPM,   1, CS16_MAC10::SHOOT_S,   CS16_MAC10::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_mp5navy",    CS16_MP5::DAMAGE,     CS16_MP5::RPM,     1, CS16_MP5::SHOOT_S,     CS16_MP5::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_ump45",      CS16_UMP45::DAMAGE,   CS16_UMP45::RPM,   1, CS16_UMP45::SHOOT_S,   CS16_UMP45::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_p90",        CS16_P90::DAMAGE,     CS16_P90::RPM,     1, CS16_P90::SHOOT_S,     CS16_P90::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_galil",      CS16_GALIL::DAMAGE,   CS16_GALIL::RPM,   1, CS16_GALIL::SHOOT_S,   CS16_GALIL::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_famas",      CS16_FAMAS::DAMAGE,   CS16_FAMAS::RPM_SINGLE, 1, CS16_FAMAS::SHOOT_S, CS16_FAMAS::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_ak47",       CS16_AK47::DAMAGE,    CS16_AK47::RPM,    1, CS16_AK47::SHOOT_S,    CS16_AK47::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_m4a1",       CS16_M4A1::DAMAGE,    CS16_M4A1::RPM,    1, CS16_M4A1::SHOOT_S,    CS16_M4A1::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_aug",        CS16_AUG::DAMAGE,     CS16_AUG::RPM,     1, CS16_AUG::SHOOT_S,     CS16_AUG::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_sg552",      CS16_SG552::DAMAGE,   CS16_SG552::RPM,   1, CS16_SG552::SHOOT_S,   CS16_SG552::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_scout",      CS16_SCOUT::DAMAGE,   CS16_SCOUT::RPM,   1, CS16_SCOUT::SHOOT_S,   CS16_SCOUT::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_awp",        CS16_AWP::DAMAGE,     CS16_AWP::RPM,     1, CS16_AWP::SHOOT_S,     CS16_AWP::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_sg550",      CS16_SG550::DAMAGE,   CS16_SG550::RPM,   1, CS16_SG550::SHOOT_S,   CS16_SG550::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_g3sg1",      CS16_G3SG1::DAMAGE,   CS16_G3SG1::RPM,   1, CS16_G3SG1::SHOOT_S,   CS16_G3SG1::W_MODEL ) );
    g_TowerGuns.insertLast( TowerGun( "weapon_csm249",     CS16_M249::DAMAGE,    CS16_M249::RPM,    1, CS16_M249::SHOOT_S,    CS16_M249::W_MODEL ) );
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
    g_NextAlert.insertLast( 0.0f );
    SpawnMiner( g_Mines.length() - 1 );   // every mine starts with one miner
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

// once a second (from core's PveThink): a monster with no enemy, a dead enemy, or one it has
// been led far away by, goes back to the nearest mine
dictionary g_LastPos;   // entindex -> Vector, position a second ago

void TdNudgeMonsters()
{
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
        bool keep = false;
        if( en !is null && en.IsAlive() )
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
        pev.health     = TOWER_HP;
        pev.max_health = TOWER_HP;
        pev.view_ofs   = Vector( 0, 0, TOWER_GUN_HEIGHT );
        g_EntityFuncs.SetModel( self, TOWER_BASE_MODEL );
        pev.scale = 0.6f;
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
        if( owner !is null ) @pev.owner = owner.edict();
        Vector gp = pev.origin + Vector( 0, 0, TOWER_GUN_HEIGHT );
        dictionary kv;
        kv["origin"] = string( gp.x ) + " " + string( gp.y ) + " " + string( gp.z );
        kv["model"] = g.wmodel;
        kv["targetname"] = "td_tower_gun";
        CBaseEntity@ gun = g_EntityFuncs.CreateEntity( "info_target", kv, true );
        if( gun !is null )
        {
            g_EntityFuncs.SetModel( gun, g.wmodel );
            gun.pev.movetype = MOVETYPE_NOCLIP;
            gun.pev.solid = SOLID_NOT;
            gun.pev.scale = 1.6f;
            gun.pev.effects &= ~EF_NODRAW;
            g_EntityFuncs.SetOrigin( gun, gp );
            m_hGun = EHandle( gun );
        }
    }

    bool NeedsAmmo() { return m_clip + m_reserve < m_clipMax + m_reserveCap; }

    void Refill()
    {
        m_reserve = m_reserveCap + ( m_clipMax - m_clip );   // full spare mags + what the next reload takes
        if( m_clip <= 0 && m_reloadEnd <= 0.0f ) m_reloadEnd = g_Engine.time + TOWER_RELOAD;
        m_nextEmptyMsg = 0.0f;
    }

    string OwnerName()
    {
        if( pev.owner is null ) return "a";
        CBaseEntity@ o = g_EntityFuncs.Instance( pev.owner );
        return o is null ? "a" : string( o.pev.netname ) + "'s";
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
            Vector ang = Math.VecToAngles( dir );
            gun.pev.angles = Vector( 0, ang.y + 180.0f, 0 );   // world models point their barrel along -x? (checked in game)
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
        + tg.dmg + " dmg x" + tg.pellets + ", " + int( 60.0f / tg.rate + 0.5f ) + " rpm, ammo " + clip + "/" + reserve + ")\n" );
}

// ------------------------------------------------------------------ gold miners

array<array<EHandle>> g_Miners;   // per mine
array<float> g_NextAlert;

int AliveMiners( uint mi )
{
    int n = 0;
    for( uint k = 0; k < g_Miners[mi].length(); ++k )
    {
        CBaseEntity@ e = g_Miners[mi][k].GetEntity();
        if( e !is null && e.IsAlive() ) ++n;
    }
    return n;
}

int AllAliveMiners()
{
    int n = 0;
    for( uint i = 0; i < g_Miners.length(); ++i )
        if( MineAlive( g_Mines[i].GetEntity() ) ) n += AliveMiners( i );
    return n;
}

bool SpawnMiner( uint mi )
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
        Vector feet = tr.vecEndPos;
        dictionary kv;
        kv["origin"] = string( feet.x ) + " " + string( feet.y ) + " " + string( feet.z + 4.0f );
        kv["angles"] = "0 " + string( Math.RandomFloat( 0, 360 ) ) + " 0";
        kv["displayname"] = g_MineNames[mi] + " Gold Miner";
        kv["is_player_ally"] = "1";
        kv["targetname"] = "td_miner";
        CBaseEntity@ e = g_EntityFuncs.CreateEntity( MINER_CLASS, kv, true );
        if( e is null ) return false;
        e.SetClassification( CLASS_PLAYER_ALLY );
        g_Miners[mi].insertLast( EHandle( e ) );
        return true;
    }
    return false;
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
    g_PlayerFuncs.HudMessageAll( tp, "GOLD MINE " + g_MineNames[mi] + ": ENEMY SPOTTED!" );
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p is null || !p.IsConnected() ) continue;
        g_SoundSystem.EmitSoundDyn( p.edict(), CHAN_STATIC, ALERT_SOUND, 1.0f, ATTN_NONE, 0, PITCH_NORM );
    }
}

// a living miner with a monster in sight -> alarm for that mine
void MinerWatch()
{
    for( uint mi = 0; mi < g_Miners.length(); ++mi )
    {
        if( !MineAlive( g_Mines[mi].GetEntity() ) ) continue;
        bool seen = false;
        for( uint k = 0; k < g_Miners[mi].length() && !seen; ++k )
        {
            CBaseEntity@ me = g_Miners[mi][k].GetEntity();
            if( me is null || !me.IsAlive() ) continue;
            CBaseMonster@ mm = me.MyMonsterPointer();
            if( mm is null ) continue;
            for( uint j = 0; j < g_Alive.length(); ++j )
            {
                CBaseEntity@ e = g_Alive[j].GetEntity();
                if( e is null || !e.IsAlive() ) continue;
                if( ( e.pev.origin - me.pev.origin ).Length() > ALERT_DIST ) continue;
                if( mm.FVisible( e, true ) ) { seen = true; break; }
            }
        }
        if( seen ) Alarm( mi );
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
    g_Carriers.insertLast( EHandle( e ) );
    AddMoney( p, -CARRIER_PRICE );
    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] " + string( p.pev.netname ) + " hired an ammo carrier (-$" + CARRIER_PRICE + ")\n" );
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

// a scripted walker (the stock scientist AI runs away from gunfire): it asks the node graph for a
// route (FGetNodeRoute) and steps along it with the engine's MoveToOrigin; no weapon, can be killed
class CTdCarrier : ScriptBaseMonsterEntity
{
    array<Vector> m_path;
    uint m_next = 0;
    EHandle m_hGoal;
    float m_nextRoute = 0.0f;
    float m_stuckSince = 0.0f;
    int m_stuckCount = 0;
    float m_bestDist = 1.0e9f;
    Vector m_lastPos;
    int m_walkSeq = -1;
    int m_idleSeq = -1;

    void Spawn()
    {
        Precache();
        pev.movetype   = MOVETYPE_STEP;
        pev.solid      = SOLID_SLIDEBOX;
        pev.takedamage = DAMAGE_YES;
        pev.flags     |= FL_MONSTER;
        pev.deadflag   = DEAD_NO;
        pev.health     = 150;
        pev.max_health = 150;
        g_EntityFuncs.SetModel( self, "models/scientist.mdl" );
        g_EntityFuncs.SetSize( self.pev, VEC_HUMAN_HULL_MIN, VEC_HUMAN_HULL_MAX );
        pev.view_ofs = Vector( 0, 0, 64 );
        self.m_bloodColor = BLOOD_COLOR_RED;
        self.SetClassification( CLASS_PLAYER_ALLY );
        m_walkSeq = self.LookupActivity( ACT_WALK );
        m_idleSeq = self.LookupActivity( ACT_IDLE );
        g_EngineFuncs.DropToFloor( self.edict() );
        m_lastPos = pev.origin;
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
            g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] The ammo carrier was killed\n" );
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

    void Route( CBaseEntity@ goal )
    {
        m_path.resize( 0 );
        m_next = 0;
        if( self.FGetNodeRoute( goal.pev.origin ) )
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
        if( m_path.length() == 0 || ( m_path[m_path.length() - 1] - goal.pev.origin ).Length() > 64.0f )
            m_path.insertLast( goal.pev.origin );           // finish (or, with no route, go) straight to the tower
        // the first node is often behind us: skip it when the second one is closer to us than to it
        if( m_path.length() > 1 && ( m_path[1] - pev.origin ).Length() < ( m_path[1] - m_path[0] ).Length() ) m_next = 1;
        m_stuckCount = 0;
        string pts = "";
        for( uint i = 0; i < m_path.length(); ++i ) pts += " (" + int( m_path[i].x ) + "," + int( m_path[i].y ) + "," + int( m_path[i].z ) + ")";
        g_Game.AlertMessage( at_aiconsole, "[cs_td] carrier at %1 %2 %3 goal %4 %5 %6 route%7\n", int( pev.origin.x ), int( pev.origin.y ), int( pev.origin.z ),
            int( goal.pev.origin.x ), int( goal.pev.origin.y ), int( goal.pev.origin.z ), pts );
    }

    void CarrierWalk()
    {
        pev.nextthink = g_Engine.time + 0.1f;
        if( pev.deadflag != DEAD_NO ) return;
        self.StudioFrameAdvance();

        CBaseEntity@ goal = TowerNeedingAmmo( pev.origin );
        if( goal is null ) { SetSeq( m_idleSeq ); m_path.resize( 0 ); return; }

        float d = ( goal.pev.origin - pev.origin ).Length2D();
        if( d <= CARRIER_REACH )
        {
            CTdTower@ t = TowerOf( goal );
            if( t !is null )
            {
                t.Refill();
                g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[TD] Ammo carrier refilled " + t.OwnerName() + " " + t.m_label + " tower ("
                    + t.m_clip + "/" + t.m_reserve + ")\n" );
            }
            SetSeq( m_idleSeq );
            m_path.resize( 0 );
            return;
        }

        if( m_hGoal.GetEntity() !is goal || m_path.length() == 0 || g_Engine.time >= m_nextRoute )
        {
            m_hGoal = EHandle( goal );
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
                g_Utility.TraceHull( cand, cand, ignore_monsters, human_hull, self.edict(), th );
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
        t += "mine " + g_MineNames[i] + ": " + ( MineAlive( g_Mines[i].GetEntity() ) ? string( AliveMiners( i ) ) + "/" + MINER_MAX + " miners" : "destroyed" ) + "\n";
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
        s += "   " + g_MineNames[i] + " mine " + ( MineAlive( m ) ? string( int( m.pev.health ) ) + " (" + AliveMiners( i ) + " miners)" : "X" );
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

// ------------------------------------------------------------------ lifecycle (called from core)

void TdMapInit()
{
    g_CustomEntityFuncs.RegisterCustomEntity( "CTdMine", "td_goldmine" );
    g_CustomEntityFuncs.RegisterCustomEntity( "CTdTower", "td_tower" );
    g_Game.PrecacheOther( "td_goldmine" );
    g_Game.PrecacheOther( "td_tower" );
    g_Game.PrecacheModel( MINE_MODEL );
    g_Game.PrecacheModel( TOWER_BASE_MODEL );
    g_Game.PrecacheOther( MINER_CLASS );
    g_CustomEntityFuncs.RegisterCustomEntity( "CTdCarrier", "td_carrier" );
    g_Game.PrecacheOther( "td_carrier" );
    g_SoundSystem.PrecacheSound( ALERT_SOUND );
    BuildHireMenu();
    BuildTowerGuns();
    for( uint i = 0; i < g_TowerGuns.length(); ++i )
    {
        g_Game.PrecacheModel( g_TowerGuns[i].wmodel );
        g_SoundSystem.PrecacheSound( g_TowerGuns[i].snd );
    }
    g_Scheduler.SetInterval( "TdThink", 0.1f, g_Scheduler.REPEAT_INFINITE_TIMES );
}

// mine spots = the map's two bomb sites (cs2sven put the objective zones into info_target pve_flank;
// dust2: A = the cluster around x>0, B = x<0). Falls back to TD_MINE_A/B from the map script.
void TdMapActivate()
{
    array<Vector> a, b;
    CBaseEntity@ e = null;
    while( ( @e = g_EntityFuncs.FindEntityByTargetname( e, "pve_flank" ) ) !is null )
    {
        if( e.pev.origin.x > 0 ) a.insertLast( e.pev.origin ); else b.insertLast( e.pev.origin );
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

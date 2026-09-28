/*
 * cs_pve/core.as - wave-based monster survival core for Counter-Strike maps ported to Sven Co-op
 * (svencoop-skills-toolkit). A map script includes this, defines BuildWaves() and forwards
 * MapInit()/MapActivate() to PveMapInit()/PveMapActivate(). See maps/dust2_pve/dust2_pve.as.
 *
 * - players spawn on the CT side (info_player_start)
 * - monsters come from the T spawns (info_target "pve_mspawn") and, on later waves,
 *   from objective zones (info_target "pve_flank") if the map has any
 * - a wave is cleared when every monster of it is dead; players get healed and a break
 * - monsters that never find a player are pushed onto the nearest player, and a wave
 *   that drags on too long is force-cleared so the game can never soft-lock
 *
 * Counter-Strike style economy (weapons from KernCore's CS 1.6 Weapons Project, installed by
 * tools/install_cs16_weapons.py; the buy rules are our own):
 * - .buy (bind b ".buy") / chat "buy" opens the CS buy menu, only inside the spawn buy zone
 * - one knife, one pistol, one primary; buying into a taken slot drops the old gun
 * - .buyammo1 (bind , ) = primary ammo, .buyammo2 (bind . ) = pistol ammo
 * - money only from monster kills and wave-clear bonuses
 */

#include "../cs16/weapons"

const int   START_MONEY      = 800;
const int   KILL_REWARD      = 300;     // per monster killed by a player
const int   WAVE_BONUS_BASE  = 1000;    // wave-clear bonus = BASE + PER * wave number
const int   WAVE_BONUS_PER   = 250;
const int   MAX_MONEY        = 16000;
const int   KEVLAR_PRICE     = 2600;    // CS $650 x4
const int   AMMO_PRICE_MULT  = 4;       // CS ammo prices x4
const int   UPG_MAX_LEVEL    = 5;       // upgrades per kind (spare mags / magazine size); buying an owned gun again upgrades it
const float UPG_CLIP_STEP    = 0.20f;
const int   UPG_MAG_STEP     = 2;
const int   WAVE_COUNT_MULT  = 3;       // every wave's monster counts x3 (bosses stay single)
const float BUYZONE_PAD      = 320.0f;  // fallback buy zone (no stations): box around the CT spawns + padding

// two NPC "stations" at the CT spawn (spawned by the script, no BSP change):
//   Arms Dealer  - press E to open the buy menu
//   Next Wave console - after a wave is cleared, press E to start the next wave early (speed bonus)
const string STATION_MODEL   = "models/hgrunt_opfor.mdl";
const string STATION_NAME    = "Arms Dealer";
const string DEVICE_MODEL    = "models/nuke_button.mdl";
const string DEVICE_NAME     = "Next Wave Console";
const string STATION_SPRITE  = "sprites/flare1.spr";
const float  STATION_USE_DIST = 128.0f; // E works within this distance of the NPC / console
const float  STATION_BUY_DIST = 256.0f; // the buy zone around the dealer (for B / chat buy)

const float THINK_INTERVAL   = 1.0f;
const float START_COUNTDOWN  = 30.0f;   // seconds after the first player spawns
const float WAVE_TIME        = 180.0f;  // every wave lasts this long (3 min); the next one starts when it runs out
const int   SPEED_BONUS_MAX  = 1500;    // pressing the console right after a clear pays this much, shrinking to 0 at the end of the wave timer
const float PENALTY_MAX      = 0.25f;   // uncleared wave -> next wave gets up to +25% HP and damage (by uncleared fraction)
const int   MAX_TEAM_DEATHS  = 20;      // total deaths of the whole team; one more = defeat

// hostages (cs_ maps): spawned on the map's hostage spots; monsters hunt them; all dead = defeat
const string HOSTAGE_CLASS   = "monster_scientist";
const string HOSTAGE_NAME    = "Hostage";
const int    HOSTAGE_HP      = 400;
const int    HOSTAGE_TARGET_PCT = 35;   // % of spawned monsters that go for a hostage instead of a player
const int   MAX_ALIVE        = 40;      // concurrent monsters cap
const int   SPAWN_PER_TICK   = 4;
const float SPAWN_POINT_COOLDOWN = 3.0f; // a spawn point is reused only after this many seconds
const float SPAWN_POINT_CLEAR = 80.0f;   // ... and only if no monster is still standing within this distance
const float SPAWN_MIN_DIST   = 450.0f;  // never spawn this close to a player
const int   STRAGGLER_SECS   = 40;      // no enemy for this long -> relocate near players
const float VICTORY_RESTART  = 25.0f;

enum PveState
{
    PVE_WAITING,
    PVE_COUNTDOWN,
    PVE_WAVE,       // monsters alive, timer running
    PVE_CLEARED,    // wave cleared, timer still running; E on the console starts the next wave now
    PVE_VICTORY,
    PVE_DEFEAT
}

// weapon categories: one gun per category (knife is always there)
const int CAT_NONE  = 0;   // grenades, armour
const int CAT_SIDE  = 2;   // pistol OR shotgun
const int CAT_SMG   = 3;
const int CAT_RIFLE = 4;   // rifles and sniper rifles
const int CAT_MG    = 5;
const int CAT_MIN   = 2;
const int CAT_MAX   = 5;

int CategoryOf( const string& in cat )
{
    if( cat == "pistol" || cat == "shotgun" ) return CAT_SIDE;
    if( cat == "smg" )   return CAT_SMG;
    if( cat == "rifle" ) return CAT_RIFLE;
    if( cat == "mg" )    return CAT_MG;
    return CAT_NONE;
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

class Gun
{
    string cls;        // entity classname (KernCore pack)
    string label;      // menu text
    int price;         // CS 1.6 price
    int slot;          // category (CAT_*), derived from cat
    string ammo;       // ammo entity classname
    int ammoPrice;     // per magazine (CS price, multiplied by AMMO_PRICE_MULT)
    string cat;        // pistol / shotgun / smg / rifle / mg / equip
    int clip;          // base magazine size
    int carry;         // base reserve capacity
    Gun( const string& in c, const string& in l, int p, int s, const string& in a, int ap, const string& in k, int cl = 0, int ca = 0 )
    {
        cls = c; label = l; price = p; ammo = a; ammoPrice = ap; cat = k; clip = cl; carry = ca;
        slot = CategoryOf( k );
    }
}

array<WaveDef@> g_Waves;
array<Gun@>     g_Guns;
array<Vector>   g_MainSpawns;
array<Vector>   g_FlankSpawns;
array<float>    g_MainLast;      // last spawn time per point
array<float>    g_FlankLast;
array<Vector>   g_Stations;      // arms dealer position(s)
array<EHandle>  g_Hostages;
int             g_HostageTotal = 0;
Vector          g_DevicePos;
bool            g_HasDevice = false;
Vector          g_BuyMins, g_BuyMaxs;
dictionary      g_LastUse;   // steamid -> float, E-key debounce

PveState g_State = PVE_WAITING;
float    g_Timer = 0.0f;
int      g_WaveIdx = -1;
float    g_WaveStart = 0.0f;
float    g_Penalty = 0.0f;   // set when a wave times out; applied to the next wave, then reset
float    g_DmgMult = 1.0f;   // monster damage multiplier for the current wave
float    g_WaveHpMult = 1.0f;
int      g_Deaths = 0;       // team deaths so far
array<string>  g_Queue;
array<EHandle> g_Alive;
array<int>     g_IdleSecs;
int      g_WaveTotal = 0;

dictionary g_Money;          // steamid -> int
dictionary g_GotStartMoney;  // steamid -> true
dictionary g_MenuIndex;      // menu item text -> gun index

HUDTextParams g_HudBig;
HUDTextParams g_HudStatus;
HUDTextParams g_HudMoney;

CTextMenu@ g_MenuMain    = null;
CTextMenu@ g_MenuPistol  = null;
CTextMenu@ g_MenuShotgun = null;
CTextMenu@ g_MenuSmg     = null;
CTextMenu@ g_MenuRifle   = null;
CTextMenu@ g_MenuMg      = null;
CTextMenu@ g_MenuEquip   = null;

// ------------------------------------------------------------------ waves

void AddWave( WaveDef@ w ) { g_Waves.insertLast( w ); }
// BuildWaves() is defined by the map script.


// ------------------------------------------------------------------ CS 1.6 weapons

void BuildGuns()
{
    // pistols (CS 1.6 prices; ammo price per magazine)
    g_Guns.insertLast( Gun( "weapon_csglock18",  "Glock 18",        400, CAT_SIDE,  "ammo_csglock18",  20, "pistol", 20, 120 ) );
    g_Guns.insertLast( Gun( "weapon_usp",        "USP .45",         500, CAT_SIDE,  "ammo_usp",        25, "pistol", 12, 100 ) );
    g_Guns.insertLast( Gun( "weapon_p228",       "P228",            600, CAT_SIDE,  "ammo_p228",       50, "pistol", 13, 52 ) );
    g_Guns.insertLast( Gun( "weapon_csdeagle",   "Desert Eagle",    650, CAT_SIDE,  "ammo_csdeagle",   40, "pistol", 7, 35 ) );
    g_Guns.insertLast( Gun( "weapon_fiveseven",  "Five-Seven",      750, CAT_SIDE,  "ammo_fiveseven",  50, "pistol", 20, 100 ) );
    g_Guns.insertLast( Gun( "weapon_dualelites", "Dual Elites",     800, CAT_SIDE,  "ammo_dualelites", 20, "pistol", 30, 120 ) );
    // shotguns
    g_Guns.insertLast( Gun( "weapon_m3",         "M3 Super 90",    1700, CAT_RIFLE, "ammo_m3",         65, "shotgun", 8, 32 ) );
    g_Guns.insertLast( Gun( "weapon_xm1014",     "XM1014",         3000, CAT_RIFLE, "ammo_xm1014",     65, "shotgun", 7, 32 ) );
    // smgs
    g_Guns.insertLast( Gun( "weapon_tmp",        "TMP",            1250, CAT_RIFLE, "ammo_tmp",        20, "smg", 30, 120 ) );
    g_Guns.insertLast( Gun( "weapon_mac10",      "MAC-10",         1400, CAT_RIFLE, "ammo_mac10",      25, "smg", 30, 100 ) );
    g_Guns.insertLast( Gun( "weapon_mp5navy",    "MP5 Navy",       1500, CAT_RIFLE, "ammo_mp5navy",    20, "smg", 30, 120 ) );
    g_Guns.insertLast( Gun( "weapon_ump45",      "UMP45",          1700, CAT_RIFLE, "ammo_ump45",      25, "smg", 25, 100 ) );
    g_Guns.insertLast( Gun( "weapon_p90",        "P90",            2350, CAT_RIFLE, "ammo_p90",        50, "smg", 50, 100 ) );
    // rifles
    g_Guns.insertLast( Gun( "weapon_galil",      "Galil",          2000, CAT_RIFLE, "ammo_galil",      60, "rifle", 35, 90 ) );
    g_Guns.insertLast( Gun( "weapon_famas",      "FAMAS",          2250, CAT_RIFLE, "ammo_famas",      60, "rifle", 25, 90 ) );
    g_Guns.insertLast( Gun( "weapon_ak47",       "AK-47",          2500, CAT_RIFLE, "ammo_ak47",       80, "rifle", 30, 90 ) );
    g_Guns.insertLast( Gun( "weapon_scout",      "Scout",          2750, CAT_RIFLE, "ammo_scout",      80, "rifle", 10, 90 ) );
    g_Guns.insertLast( Gun( "weapon_m4a1",       "M4A1",           3100, CAT_RIFLE, "ammo_m4a1",       60, "rifle", 30, 90 ) );
    g_Guns.insertLast( Gun( "weapon_aug",        "AUG",            3500, CAT_RIFLE, "ammo_aug",        60, "rifle", 30, 90 ) );
    g_Guns.insertLast( Gun( "weapon_sg552",      "SG552",          3500, CAT_RIFLE, "ammo_sg552",      60, "rifle", 30, 90 ) );
    g_Guns.insertLast( Gun( "weapon_sg550",      "SG550",          4200, CAT_RIFLE, "ammo_sg550",      60, "rifle", 30, 90 ) );
    g_Guns.insertLast( Gun( "weapon_awp",        "AWP",            4750, CAT_RIFLE, "ammo_awp",       125, "rifle", 10, 30 ) );
    g_Guns.insertLast( Gun( "weapon_g3sg1",      "G3SG1",          5000, CAT_RIFLE, "ammo_g3sg1",      80, "rifle", 20, 90 ) );
    // machine gun
    g_Guns.insertLast( Gun( "weapon_csm249",     "M249",           5750, CAT_RIFLE, "ammo_csm249",     60, "mg", 100, 200 ) );
    // equipment
    g_Guns.insertLast( Gun( "weapon_hegrenade",  "HE Grenade",      300, CAT_NONE,    "",                 0, "equip" ) );
    g_Guns.insertLast( Gun( "kevlar",            "Kevlar (100 armor)", KEVLAR_PRICE, CAT_NONE, "",       0, "equip" ) );
}

// mirrors cs16/cs16_register.as (which cannot be a second map_script because it defines MapInit)
void SetupCS16Weapons()
{
    CS16_KNIFE::POSITION     = 10;
    CS16_GLOCK18::POSITION   = 10;  CS16_USP::POSITION   = 11;  CS16_P228::POSITION   = 12;
    CS16_57::POSITION        = 13;  CS16_ELITES::POSITION = 14; CS16_DEAGLE::POSITION = 15;
    CS16_M3::POSITION        = 10;  CS16_XM1014::POSITION = 11;
    CS16_MAC10::POSITION     = 10;  CS16_TMP::POSITION   = 11;  CS16_MP5::POSITION    = 12;
    CS16_UMP45::POSITION     = 13;  CS16_P90::POSITION   = 14;
    CS16_FAMAS::POSITION     = 10;  CS16_GALIL::POSITION = 11;  CS16_AK47::POSITION   = 12;
    CS16_M4A1::POSITION      = 13;  CS16_AUG::POSITION   = 14;  CS16_SG552::POSITION  = 15;
    CS16_SCOUT::POSITION     = 10;  CS16_AWP::POSITION   = 11;  CS16_SG550::POSITION  = 12;
    CS16_G3SG1::POSITION     = 13;
    CS16_M249::POSITION      = 10;
    CS16_HEGRENADE::POSITION = 10;  CS16_C4::POSITION    = 11;

    RegisterAll();
}

string ItemText( Gun@ g ) { return g.label + "  $" + g.price; }

CTextMenu@ MakeGunMenu( const string& in title, const string& in cat )
{
    CTextMenu@ m = CTextMenu( TextMenuPlayerSlotCallback( @GunMenuCallback ) );
    m.SetTitle( title + "\n" );
    for( uint i = 0; i < g_Guns.length(); ++i )
    {
        if( g_Guns[i].cat != cat ) continue;
        string txt = ItemText( g_Guns[i] );
        g_MenuIndex[txt] = int( i );
        m.AddItem( txt );
    }
    m.Register();
    return m;
}

void BuildMenus()
{
    @g_MenuMain = CTextMenu( TextMenuPlayerSlotCallback( @MainMenuCallback ) );
    g_MenuMain.SetTitle( "Buy Menu\n" );
    g_MenuMain.AddItem( "Pistols" );
    g_MenuMain.AddItem( "Shotguns" );
    g_MenuMain.AddItem( "Sub-Machine Guns" );
    g_MenuMain.AddItem( "Rifles" );
    g_MenuMain.AddItem( "Machine Gun" );
    g_MenuMain.AddItem( "Ammo (one magazine)" );
    g_MenuMain.AddItem( "Equipment" );
    g_MenuMain.Register();

    @g_MenuPistol  = MakeGunMenu( "Pistols",          "pistol" );
    @g_MenuShotgun = MakeGunMenu( "Shotguns",         "shotgun" );
    @g_MenuSmg     = MakeGunMenu( "Sub-Machine Guns", "smg" );
    @g_MenuRifle   = MakeGunMenu( "Rifles",           "rifle" );
    @g_MenuMg      = MakeGunMenu( "Machine Gun",      "mg" );
    @g_MenuEquip   = MakeGunMenu( "Equipment",        "equip" );
}

void MainMenuCallback( CTextMenu@ menu, CBasePlayer@ pPlayer, int iSlot, const CTextMenuItem@ pItem )
{
    if( pItem is null || pPlayer is null ) return;
    if( !CanBuy( pPlayer ) ) return;
    string c = pItem.m_szName;
    if( c == "Pistols" )               g_MenuPistol.Open( 0, 0, pPlayer );
    else if( c == "Shotguns" )         g_MenuShotgun.Open( 0, 0, pPlayer );
    else if( c == "Sub-Machine Guns" ) g_MenuSmg.Open( 0, 0, pPlayer );
    else if( c == "Rifles" )           g_MenuRifle.Open( 0, 0, pPlayer );
    else if( c == "Machine Gun" )      g_MenuMg.Open( 0, 0, pPlayer );
    else if( c == "Ammo (one magazine)" ) OpenAmmoMenu( pPlayer );
    else if( c == "Equipment" )        g_MenuEquip.Open( 0, 0, pPlayer );
}

void GunMenuCallback( CTextMenu@ menu, CBasePlayer@ pPlayer, int iSlot, const CTextMenuItem@ pItem )
{
    if( pItem is null || pPlayer is null ) return;
    if( !g_MenuIndex.exists( pItem.m_szName ) ) return;
    BuyGun( pPlayer, int( g_MenuIndex[pItem.m_szName] ) );
}

// ------------------------------------------------------------------ economy

string PlayerKey( CBasePlayer@ p )
{
    string id = g_EngineFuncs.GetPlayerAuthId( p.edict() );
    if( id.Length() > 8 && id.SubString( 0, 8 ) == "STEAM_0:" ) return id;
    if( id.Length() > 8 && id.SubString( 0, 8 ) == "STEAM_1:" ) return id;
    return "name:" + string( p.pev.netname );   // LAN / pending ids are shared by everyone
}

int GetMoney( CBasePlayer@ p )
{
    string id = PlayerKey( p );
    return g_Money.exists( id ) ? int( g_Money[id] ) : 0;
}

void SetMoney( CBasePlayer@ p, int v )
{
    if( v < 0 ) v = 0;
    if( v > MAX_MONEY ) v = MAX_MONEY;
    g_Money[PlayerKey( p )] = v;
}

void AddMoney( CBasePlayer@ p, int amount ) { SetMoney( p, GetMoney( p ) + amount ); }

void AddMoneyAll( int amount )
{
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p is null || !p.IsConnected() ) continue;
        AddMoney( p, amount );
    }
}

float NearestStationDist( const Vector& in o )
{
    float best = 999999.0f;
    for( uint i = 0; i < g_Stations.length(); ++i )
    {
        float d = ( g_Stations[i] - o ).Length();
        if( d < best ) best = d;
    }
    return best;
}

bool InBuyZone( CBasePlayer@ p )
{
    Vector o = p.pev.origin;
    if( g_Stations.length() > 0 )
        return NearestStationDist( o ) <= STATION_BUY_DIST;
    return o.x >= g_BuyMins.x && o.x <= g_BuyMaxs.x
        && o.y >= g_BuyMins.y && o.y <= g_BuyMaxs.y
        && o.z >= g_BuyMins.z && o.z <= g_BuyMaxs.z;
}

bool CanBuy( CBasePlayer@ p )
{
    if( !p.IsAlive() )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "You are dead" );
        return false;
    }
    if( !InBuyZone( p ) )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, g_Stations.length() > 0 ? "Buy from the Arms Dealer in spawn (press E on him)" : "You can only buy in the spawn buy zone" );
        return false;
    }
    return true;
}

// E on the Arms Dealer opens the buy menu; E on the console starts the next wave (when cleared)
HookReturnCode OnPlayerUse( CBasePlayer@ pPlayer, uint& out uiFlags )
{
    if( pPlayer is null || ( pPlayer.m_afButtonPressed & IN_USE ) == 0 ) return HOOK_CONTINUE;
    if( !pPlayer.IsAlive() ) return HOOK_CONTINUE;

    bool nearDevice = g_HasDevice && ( g_DevicePos - pPlayer.pev.origin ).Length() <= STATION_USE_DIST;
    bool nearDealer = g_Stations.length() > 0 && NearestStationDist( pPlayer.pev.origin ) <= STATION_USE_DIST;
    if( !nearDevice && !nearDealer ) return HOOK_CONTINUE;

    string id = PlayerKey( pPlayer );
    float last = g_LastUse.exists( id ) ? float( g_LastUse[id] ) : -10.0f;
    if( g_Engine.time - last < 0.5f ) return HOOK_CONTINUE;
    g_LastUse[id] = g_Engine.time;

    uiFlags |= PlrHook_SkipUse;
    if( nearDevice )
        UseDevice( pPlayer );
    else
        OpenBuyMenu( pPlayer );
    return HOOK_CONTINUE;
}

void UseDevice( CBasePlayer@ p )
{
    if( g_State == PVE_CLEARED )
    {
        int bonus = int( float( SPEED_BONUS_MAX ) * g_Timer / WAVE_TIME );
        if( bonus < 0 ) bonus = 0;
        AddMoneyAll( bonus );
        Big( string( p.pev.netname ) + " started the next wave early: +$" + bonus + " speed bonus for everyone!" );
        StartWave( g_WaveIdx + 1 );
    }
    else if( g_State == PVE_WAVE )
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Clear the wave first!" );
    else if( g_State == PVE_COUNTDOWN )
    {
        Big( string( p.pev.netname ) + " skipped the countdown. Here they come!" );
        StartWave( 0 );
    }
}

// monsters hit harder after an uncleared wave (see PENALTY_MAX)
HookReturnCode OnPlayerTakeDamage( DamageInfo@ info )
{
    if( g_DmgMult != 1.0f && info !is null && info.pAttacker !is null
        && info.pAttacker.IsMonster() && !info.pAttacker.IsPlayer() )
        info.flDamage = info.flDamage * g_DmgMult;
    return HOOK_CONTINUE;
}

// death = your guns are gone (nothing to pick back up)
HookReturnCode OnPlayerKilled( CBasePlayer@ pPlayer, CBaseEntity@ pAttacker, int iGib )
{
    if( pPlayer is null ) return HOOK_CONTINUE;
    pPlayer.RemoveAllItems( false, false );
    if( g_State == PVE_WAVE || g_State == PVE_CLEARED || g_State == PVE_COUNTDOWN )
    {
        ++g_Deaths;
        int left = MAX_TEAM_DEATHS - g_Deaths;
        if( left > 0 )
            g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] " + string( pPlayer.pev.netname ) + " died. Team lives left: " + left + "
" );
        else
        {
            Big( "The team died " + MAX_TEAM_DEATHS + " times!" );
            Defeat();
        }
    }
    CBaseEntity@ e = null;
    while( ( @e = g_EntityFuncs.FindEntityByClassname( e, "weaponbox" ) ) !is null )
    {
        if( ( e.pev.origin - pPlayer.pev.origin ).Length() <= 128.0f )
            g_EntityFuncs.Remove( e );
    }
    return HOOK_CONTINUE;
}

Vector FloorAt( const Vector& in p )
{
    TraceResult tr;
    g_Utility.TraceLine( p + Vector( 0, 0, 16 ), p - Vector( 0, 0, 256 ), ignore_monsters, null, tr );
    return tr.flFraction < 1.0f ? tr.vecEndPos : p;
}

// a non-AI display NPC (monster_generic): never moves, never fights, cannot die
CBaseEntity@ SpawnProp( const Vector& in pos, float yaw, const string& in model, const string& in name, const string& in targetname )
{
    dictionary kv;
    kv["origin"] = string( pos.x ) + " " + string( pos.y ) + " " + string( pos.z + 8.0f );
    kv["angles"] = "0 " + string( yaw ) + " 0";
    kv["model"] = model;
    kv["displayname"] = name;
    kv["targetname"] = targetname;
    kv["disableai"] = "1";
    CBaseEntity@ npc = g_EntityFuncs.CreateEntity( "monster_generic", kv, true );
    if( npc is null ) return null;
    npc.pev.takedamage = DAMAGE_NO;
    npc.pev.health = 1000000;
    CBaseAnimating@ anim = cast<CBaseAnimating@>( npc );
    if( anim !is null )
    {
        int seq = anim.LookupSequence( "idle1" );
        if( seq >= 0 )
        {
            npc.pev.sequence = seq;
            npc.pev.frame = 0;
            anim.ResetSequenceInfo();
        }
    }
    return npc;
}

void SpawnGlow( const Vector& in pos, const string& in color )
{
    dictionary sp;
    sp["origin"] = string( pos.x ) + " " + string( pos.y ) + " " + string( pos.z );
    sp["model"] = STATION_SPRITE;
    sp["rendermode"] = "5";
    sp["renderamt"] = "180";
    sp["rendercolor"] = color;
    sp["scale"] = "0.25";
    sp["spawnflags"] = "1";
    g_EntityFuncs.CreateEntity( "env_sprite", sp, true );
}

// Arms Dealer on the spawn point nearest the centre, Next Wave console on the one farthest from him
void SpawnBuyStations( const array<Vector>& in spawns, const array<float>& in yaws )
{
    if( spawns.length() == 0 ) return;
    Vector c( 0, 0, 0 );
    for( uint i = 0; i < spawns.length(); ++i ) c = c + spawns[i];
    c = c * ( 1.0f / float( spawns.length() ) );

    int dealerIdx = 0; float bd = 999999.0f;
    for( uint i = 0; i < spawns.length(); ++i )
    {
        float d = ( spawns[i] - c ).Length();
        if( d < bd ) { bd = d; dealerIdx = int( i ); }
    }
    int deviceIdx = -1; float far = -1.0f;
    for( uint i = 0; i < spawns.length(); ++i )
    {
        if( int( i ) == dealerIdx ) continue;
        float d = ( spawns[i] - spawns[dealerIdx] ).Length();
        if( d > far ) { far = d; deviceIdx = int( i ); }
    }

    // 72 units in front of the spawn point so nobody spawns inside the prop; prop faces the spawn
    float yaw = yaws[dealerIdx] * 0.0174533f;
    Vector pos = FloorAt( spawns[dealerIdx] + Vector( cos( yaw ), sin( yaw ), 0 ) * 72.0f );
    if( SpawnProp( pos, yaws[dealerIdx] + 180.0f, STATION_MODEL, STATION_NAME, "pve_buystation" ) !is null )
    {
        g_Stations.insertLast( pos );
        SpawnGlow( pos + Vector( 0, 0, 96 ), "255 200 60" );
    }

    if( deviceIdx >= 0 )
    {
        yaw = yaws[deviceIdx] * 0.0174533f;
        pos = FloorAt( spawns[deviceIdx] + Vector( cos( yaw ), sin( yaw ), 0 ) * 72.0f );
        if( SpawnProp( pos, yaws[deviceIdx] + 180.0f, DEVICE_MODEL, DEVICE_NAME, "pve_device" ) !is null )
        {
            g_DevicePos = pos;
            g_HasDevice = true;
            SpawnGlow( pos + Vector( 0, 0, 72 ), "80 200 255" );
        }
    }
    g_Game.AlertMessage( at_console, "[cs_pve] buy stations: %1, device: %2\n", g_Stations.length(), g_HasDevice ? 1 : 0 );
}

dictionary g_ClipLvl;   // "steamid|weapon_x" -> level
dictionary g_MagLvl;

string UpgKey( CBasePlayer@ p, const string& in cls ) { return PlayerKey( p ) + "|" + cls; }
int ClipLevel( CBasePlayer@ p, const string& in cls ) { string k = UpgKey( p, cls ); return g_ClipLvl.exists( k ) ? int( g_ClipLvl[k] ) : 0; }
int MagLevel( CBasePlayer@ p, const string& in cls )  { string k = UpgKey( p, cls ); return g_MagLvl.exists( k ) ? int( g_MagLvl[k] ) : 0; }
int ClipBonus( CBasePlayer@ p, Gun@ g ) { return int( float( g.clip ) * UPG_CLIP_STEP * float( ClipLevel( p, g.cls ) ) + 0.999f ); }
int CarryCap( CBasePlayer@ p, Gun@ g )  { return g.carry + UPG_MAG_STEP * MagLevel( p, g.cls ) * g.clip; }

Gun@ GunByClass( const string& in cls )
{
    for( uint i = 0; i < g_Guns.length(); ++i )
        if( g_Guns[i].cls == cls ) return g_Guns[i];
    return null;
}

// the gun the player is holding right now (pistol or primary), or null
Gun@ ActiveGun( CBasePlayer@ p )
{
    CBaseEntity@ act = p.m_hActiveItem.GetEntity();
    if( act is null ) return null;
    Gun@ g = GunByClass( act.GetClassname() );
    if( g is null || g.slot == CAT_NONE ) return null;
    return g;
}
// buying a gun you already own upgrades it: spare mags, then magazine size, alternating, UPG_MAX_LEVEL each
void BuyUpgrade( CBasePlayer@ p, Gun@ g )
{
    int magLvl = MagLevel( p, g.cls );
    int clipLvl = ClipLevel( p, g.cls );
    bool doMag;
    if( magLvl >= UPG_MAX_LEVEL && clipLvl >= UPG_MAX_LEVEL )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, g.label + " is fully upgraded" );
        return;
    }
    if( magLvl >= UPG_MAX_LEVEL ) doMag = false;
    else if( clipLvl >= UPG_MAX_LEVEL ) doMag = true;
    else doMag = ( magLvl <= clipLvl );
    int money = GetMoney( p );
    if( money < g.price )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Upgrade costs $" + g.price + " (buy the same gun again)" );
        return;
    }
    string k = UpgKey( p, g.cls );
    if( doMag ) g_MagLvl[k] = magLvl + 1; else g_ClipLvl[k] = clipLvl + 1;
    SetMoney( p, money - g.price );
    if( doMag )
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, g.label + " upgraded: reserve " + CarryCap( p, g ) + " rounds (spare mags " + ( magLvl + 1 ) + "/" + UPG_MAX_LEVEL + ")  -$" + g.price );
    else
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, g.label + " upgraded: magazine " + ( g.clip + ClipBonus( p, g ) ) + " rounds (size " + ( clipLvl + 1 ) + "/" + UPG_MAX_LEVEL + ")  -$" + g.price );
}
// bigger magazines: right after a full reload (clip == base) top the clip up from the reserve
HookReturnCode OnPlayerPostThink( CBasePlayer@ p )
{
    if( p is null || !p.IsAlive() ) return HOOK_CONTINUE;
    Gun@ g = ActiveGun( p );
    if( g is null || g.clip <= 0 ) return HOOK_CONTINUE;
    int bonus = ClipBonus( p, g );
    if( bonus <= 0 ) return HOOK_CONTINUE;
    CBasePlayerWeapon@ w = cast<CBasePlayerWeapon@>( p.m_hActiveItem.GetEntity() );
    if( w is null || w.m_iClip != g.clip ) return HOOK_CONTINUE;
    int type = w.m_iPrimaryAmmoType;
    if( type < 0 ) return HOOK_CONTINUE;
    int reserve = p.m_rgAmmo( type );
    int add = reserve < bonus ? reserve : bonus;
    if( add <= 0 ) return HOOK_CONTINUE;
    w.m_iClip = g.clip + add;
    p.m_rgAmmo( type, reserve - add );
    return HOOK_CONTINUE;
}

void OpenBuyMenu( CBasePlayer@ p )
{
    if( p is null || !CanBuy( p ) ) return;
    g_MenuMain.SetTitle( "Buy Menu   ($" + GetMoney( p ) + ")\n" );
    g_MenuMain.Open( 0, 0, p );
}

Gun@ HeldGun( CBasePlayer@ p, int cat )
{
    for( uint i = 0; i < g_Guns.length(); ++i )
    {
        if( g_Guns[i].slot != cat ) continue;
        if( p.HasNamedPlayerItem( g_Guns[i].cls ) !is null ) return g_Guns[i];
    }
    return null;
}
void BuyGun( CBasePlayer@ p, int idx )
{
    if( !CanBuy( p ) ) return;
    Gun@ g = g_Guns[idx];
    if( g.slot != CAT_NONE && p.HasNamedPlayerItem( g.cls ) !is null )
    {
        BuyUpgrade( p, g );
        return;
    }
    int money = GetMoney( p );
    if( money < g.price )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Not enough money: " + g.label + " costs $" + g.price );
        return;
    }
    if( g.cls == "kevlar" )
    {
        if( p.pev.armorvalue >= 100 )
        {
            g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Armor is already full" );
            return;
        }
        p.pev.armorvalue = 100;
    }
    else
    {
        if( g.slot != CAT_NONE )
        {
            Gun@ old = HeldGun( p, g.slot );
            if( old !is null )
                p.DropItem( old.cls );        // CS style: the old gun of that category goes on the floor
        }
        p.GiveNamedItem( g.cls );
        if( g.slot != CAT_NONE )
            p.SelectItem( g.cls );
    }
    SetMoney( p, money - g.price );
    g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Bought " + g.label + " for $" + g.price );
}
// one magazine for the gun in that category: rounds x per-round price of its ammo type
int AmmoUnitPrice( Gun@ g ) { return g.clip > 0 ? ( g.ammoPrice * AMMO_PRICE_MULT + g.clip - 1 ) / g.clip : 0; }
int MagazineRounds( CBasePlayer@ p, Gun@ g ) { return g.clip + ClipBonus( p, g ); }
int MagazinePrice( CBasePlayer@ p, Gun@ g ) { return MagazineRounds( p, g ) * AmmoUnitPrice( g ); }

void BuyAmmo( CBasePlayer@ p, int cat )
{
    if( !CanBuy( p ) ) return;
    Gun@ g = HeldGun( p, cat );
    if( g is null || g.ammo.Length() == 0 )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "No gun in category " + cat );
        return;
    }
    int rounds = MagazineRounds( p, g );
    int price = MagazinePrice( p, g );
    int money = GetMoney( p );
    if( money < price )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Not enough money: " + rounds + " x $" + AmmoUnitPrice( g ) + " = $" + price );
        return;
    }
    CBasePlayerWeapon@ w = cast<CBasePlayerWeapon@>( p.HasNamedPlayerItem( g.cls ) );
    if( w is null || w.m_iPrimaryAmmoType < 0 || g.clip <= 0 )
    {
        p.GiveNamedItem( g.ammo );      // fallback: let the weapon pack handle it
    }
    else
    {
        int type = w.m_iPrimaryAmmoType;
        int cur = p.m_rgAmmo( type );
        int cap = CarryCap( p, g );
        if( cur >= cap )
        {
            g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "Reserve full (" + cap + ")" );
            return;
        }
        int nv = cur + rounds; if( nv > cap ) nv = cap;
        p.m_rgAmmo( type, nv );
    }
    SetMoney( p, money - price );
    g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, g.label + ": " + rounds + " rounds x $" + AmmoUnitPrice( g ) + " = -$" + price );
}

dictionary g_AmmoMenuCat;   // item text -> category (rebuilt on every open)

void AmmoMenuCallback( CTextMenu@ menu, CBasePlayer@ pPlayer, int iSlot, const CTextMenuItem@ pItem )
{
    if( pItem is null || pPlayer is null ) return;
    if( !g_AmmoMenuCat.exists( pItem.m_szName ) ) return;
    BuyAmmo( pPlayer, int( g_AmmoMenuCat[pItem.m_szName] ) );
}

void OpenAmmoMenu( CBasePlayer@ p )
{
    if( !CanBuy( p ) ) return;
    CTextMenu@ m = CTextMenu( TextMenuPlayerSlotCallback( @AmmoMenuCallback ) );
    m.SetTitle( "Ammo - one magazine   ($" + GetMoney( p ) + ")\n" );
    int n = 0;
    for( int cat = CAT_MIN; cat <= CAT_MAX; ++cat )
    {
        Gun@ g = HeldGun( p, cat );
        if( g is null ) continue;
        string txt = "[" + cat + "] " + g.label + "  " + MagazineRounds( p, g ) + " rds x $" + AmmoUnitPrice( g ) + " = $" + MagazinePrice( p, g );
        g_AmmoMenuCat[txt] = cat;
        m.AddItem( txt );
        ++n;
    }
    if( n == 0 )
    {
        g_PlayerFuncs.ClientPrint( p, HUD_PRINTCENTER, "You have no guns to buy ammo for" );
        return;
    }
    m.Register();
    m.Open( 0, 0, p );
}
// one pistol + one primary: drop extras picked up from the floor (keeps the active one)
// one gun per category: drop extras picked up from the floor (keeps the active one)
void EnforceSlots( CBasePlayer@ p )
{
    for( int cat = CAT_MIN; cat <= CAT_MAX; ++cat )
    {
        array<Gun@> held;
        for( uint i = 0; i < g_Guns.length(); ++i )
            if( g_Guns[i].slot == cat && p.HasNamedPlayerItem( g_Guns[i].cls ) !is null )
                held.insertLast( g_Guns[i] );
        if( held.length() <= 1 ) continue;

        string active = "";
        CBaseEntity@ act = p.m_hActiveItem.GetEntity();
        if( act !is null ) active = act.GetClassname();
        bool keptOne = false;
        for( uint i = 0; i < held.length(); ++i )
        {
            if( !keptOne && ( held[i].cls == active || i == held.length() - 1 ) ) { keptOne = true; continue; }
            p.DropItem( held[i].cls );
        }
    }
}
// console commands: .buy  .buyammo1 (primary)  .buyammo2 (pistol)
void CmdBuy( const CCommand@ args )      { OpenBuyMenu( g_ConCommandSystem.GetCurrentPlayer() ); }
int PrimaryCategory( CBasePlayer@ p )
{
    if( HeldGun( p, CAT_RIFLE ) !is null ) return CAT_RIFLE;
    if( HeldGun( p, CAT_SMG ) !is null )   return CAT_SMG;
    if( HeldGun( p, CAT_MG ) !is null )    return CAT_MG;
    return CAT_SIDE;
}
void CmdBuyAmmo1( const CCommand@ args ) { CBasePlayer@ p = g_ConCommandSystem.GetCurrentPlayer(); if( p !is null ) BuyAmmo( p, PrimaryCategory( p ) ); }
void CmdBuyAmmo2( const CCommand@ args ) { CBasePlayer@ p = g_ConCommandSystem.GetCurrentPlayer(); if( p !is null ) BuyAmmo( p, CAT_SIDE ); }

CClientCommand g_CmdBuy( "buy", "Open the CS buy menu (spawn zone only)", @CmdBuy );
CClientCommand g_CmdBuyAmmo1( "buyammo1", "Buy primary weapon ammo", @CmdBuyAmmo1 );
CClientCommand g_CmdBuyAmmo2( "buyammo2", "Buy pistol ammo", @CmdBuyAmmo2 );

HookReturnCode OnClientSay( SayParameters@ pParams )
{
    CBasePlayer@ p = pParams.GetPlayer();
    const CCommand@ args = pParams.GetArguments();
    if( p is null || args.ArgC() < 1 ) return HOOK_CONTINUE;
    string a = args.Arg( 0 ).ToLowercase();
    if( a == "buy" || a == "!buy" || a == "/buy" || a == ".buy" )
    {
        pParams.ShouldHide = true;
        OpenBuyMenu( p );
    }
    else if( a == "!buyammo1" || a == "/buyammo1" ) { pParams.ShouldHide = true; BuyAmmo( p, PrimaryCategory( p ) ); }
    else if( a == "!buyammo2" || a == "/buyammo2" ) { pParams.ShouldHide = true; BuyAmmo( p, CAT_SIDE ); }
    else if( a == "!money" ) { pParams.ShouldHide = true; g_PlayerFuncs.ClientPrint( p, HUD_PRINTTALK, "[PVE] You have $" + GetMoney( p ) + "\n" ); }
    return HOOK_CONTINUE;
}

// who killed this monster? (bullets: inflictor = player; grenades: inflictor owned by player)
CBasePlayer@ KillerOf( CBaseEntity@ e )
{
    edict_t@ inf = e.pev.dmg_inflictor;
    if( inf is null ) return null;
    CBaseEntity@ ie = g_EntityFuncs.Instance( inf );
    if( ie is null ) return null;
    if( ie.IsPlayer() ) return cast<CBasePlayer@>( ie );
    if( ie.pev.owner !is null )
    {
        CBaseEntity@ o = g_EntityFuncs.Instance( ie.pev.owner );
        if( o !is null && o.IsPlayer() ) return cast<CBasePlayer@>( o );
    }
    return null;
}

// ------------------------------------------------------------------ lifecycle

void PveMapInit()
{
    SetupCS16Weapons();
    BuildGuns();
    BuildMenus();
    BuildWaves();
    for( uint i = 0; i < g_Waves.length(); ++i )
        for( uint j = 0; j < g_Waves[i].spawns.length(); ++j )
            g_Game.PrecacheOther( g_Waves[i].spawns[j].cls );
    for( uint i = 0; i < g_Guns.length(); ++i )
    {
        if( g_Guns[i].cls != "kevlar" ) g_Game.PrecacheOther( g_Guns[i].cls );
        if( g_Guns[i].ammo.Length() > 0 ) g_Game.PrecacheOther( g_Guns[i].ammo );
    }

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

    g_HudMoney.channel = 6;
    g_HudMoney.x = 0.02; g_HudMoney.y = 0.80;
    g_HudMoney.effect = 0;
    g_HudMoney.r1 = 120; g_HudMoney.g1 = 255; g_HudMoney.b1 = 120; g_HudMoney.a1 = 255;
    g_HudMoney.fadeinTime = 0.0; g_HudMoney.fadeoutTime = 0.2; g_HudMoney.holdTime = 1.2; g_HudMoney.fxTime = 0.0;

    g_Game.PrecacheOther( HOSTAGE_CLASS );
    g_Game.PrecacheModel( STATION_MODEL );
    g_Game.PrecacheModel( DEVICE_MODEL );
    g_Game.PrecacheModel( STATION_SPRITE );

    g_Hooks.RegisterHook( Hooks::Player::PlayerSpawn, @OnPlayerSpawn );
    g_Hooks.RegisterHook( Hooks::Player::ClientSay, @OnClientSay );
    g_Hooks.RegisterHook( Hooks::Player::PlayerUse, @OnPlayerUse );
    g_Hooks.RegisterHook( Hooks::Player::PlayerTakeDamage, @OnPlayerTakeDamage );
    g_Hooks.RegisterHook( Hooks::Player::PlayerKilled, @OnPlayerKilled );
    g_Hooks.RegisterHook( Hooks::Player::PlayerPostThink, @OnPlayerPostThink );
    g_Scheduler.SetInterval( "PveThink", THINK_INTERVAL, g_Scheduler.REPEAT_INFINITE_TIMES );
}

void PveMapActivate()
{
    CBaseEntity@ e = null;
    while( ( @e = g_EntityFuncs.FindEntityByTargetname( e, "pve_mspawn" ) ) !is null )
    {
        g_MainSpawns.insertLast( e.pev.origin );
        g_MainLast.insertLast( -100.0f );
    }
    @e = null;
    while( ( @e = g_EntityFuncs.FindEntityByTargetname( e, "pve_flank" ) ) !is null )
    {
        g_FlankSpawns.insertLast( e.pev.origin );
        g_FlankLast.insertLast( -100.0f );
    }

    // buy zone: box around the player spawns (fallback) + weapon crates at the spawns
    array<Vector> spawns;
    array<float> yaws;
    bool first = true;
    @e = null;
    while( ( @e = g_EntityFuncs.FindEntityByClassname( e, "info_player_start" ) ) !is null )
    {
        Vector o = e.pev.origin;
        spawns.insertLast( o );
        yaws.insertLast( e.pev.angles.y );
        if( first ) { g_BuyMins = o; g_BuyMaxs = o; first = false; continue; }
        if( o.x < g_BuyMins.x ) g_BuyMins.x = o.x;  if( o.x > g_BuyMaxs.x ) g_BuyMaxs.x = o.x;
        if( o.y < g_BuyMins.y ) g_BuyMins.y = o.y;  if( o.y > g_BuyMaxs.y ) g_BuyMaxs.y = o.y;
        if( o.z < g_BuyMins.z ) g_BuyMins.z = o.z;  if( o.z > g_BuyMaxs.z ) g_BuyMaxs.z = o.z;
    }
    g_BuyMins = g_BuyMins - Vector( BUYZONE_PAD, BUYZONE_PAD, 128 );
    g_BuyMaxs = g_BuyMaxs + Vector( BUYZONE_PAD, BUYZONE_PAD, 128 );
    SpawnBuyStations( spawns, yaws );

    // hostages
    @e = null;
    while( ( @e = g_EntityFuncs.FindEntityByTargetname( e, "pve_hostage" ) ) !is null )
    {
        dictionary kv;
        Vector o = e.pev.origin;
        kv["origin"] = string( o.x ) + " " + string( o.y ) + " " + string( o.z );
        kv["angles"] = "0 " + string( e.pev.angles.y ) + " 0";
        kv["displayname"] = HOSTAGE_NAME;
        kv["targetname"] = "pve_hostage_npc";
        CBaseEntity@ h = g_EntityFuncs.CreateEntity( HOSTAGE_CLASS, kv, true );
        if( h is null ) continue;
        h.pev.health = HOSTAGE_HP;
        h.pev.max_health = HOSTAGE_HP;
        g_Hostages.insertLast( EHandle( h ) );
    }
    g_HostageTotal = int( g_Hostages.length() );
    g_Game.AlertMessage( at_console, "[cs_pve] hostages: %1\n", g_HostageTotal );

    g_Game.AlertMessage( at_console, "[cs_pve] spawns: main=%1 flank=%2 waves=%3 guns=%4\n",
        g_MainSpawns.length(), g_FlankSpawns.length(), g_Waves.length(), g_Guns.length() );
}

HookReturnCode OnPlayerSpawn( CBasePlayer@ pPlayer )
{
    if( g_State == PVE_WAITING )
    {
        g_State = PVE_COUNTDOWN;
        g_Timer = START_COUNTDOWN;
        g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] First wave in " + int( START_COUNTDOWN ) + " seconds. Hold the CT side!\n" );
    }
    if( pPlayer !is null )
    {
        string id = PlayerKey( pPlayer );
        if( !g_GotStartMoney.exists( id ) )
        {
            g_GotStartMoney[id] = true;
            AddMoney( pPlayer, START_MONEY );
        }
        g_PlayerFuncs.ClientPrint( pPlayer, HUD_PRINTTALK, "[PVE] $" + GetMoney( pPlayer ) + ". E on the Arms Dealer to buy. E on the console after a clear = next wave + speed bonus.\n" );
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

bool MonsterNear( const Vector& in pos, float dist )
{
    for( uint i = 0; i < g_Alive.length(); ++i )
    {
        CBaseEntity@ e = g_Alive[i].GetEntity();
        if( e !is null && ( e.pev.origin - pos ).Length() < dist ) return true;
    }
    return false;
}

// a free spawn point: not used in the last SPAWN_POINT_COOLDOWN s, no monster still standing on it,
// not right next to a player. Returns false when every point is busy (spawning then waits a tick).
bool PickSpawn( bool allowFlank, Vector& out pos )
{
    bool useFlank = allowFlank && g_FlankSpawns.length() > 0 && Math.RandomLong( 0, 99 ) < 35;
    for( int pass = 0; pass < 2; ++pass )
    {
        array<Vector>@ pool = useFlank ? @g_FlankSpawns : @g_MainSpawns;
        array<float>@ last = useFlank ? @g_FlankLast : @g_MainLast;
        if( pool.length() > 0 )
        {
            int start = Math.RandomLong( 0, pool.length() - 1 );
            for( uint k = 0; k < pool.length(); ++k )
            {
                int i = ( start + int( k ) ) % int( pool.length() );
                if( g_Engine.time - last[i] < SPAWN_POINT_COOLDOWN ) continue;
                if( MonsterNear( pool[i], SPAWN_POINT_CLEAR ) ) continue;
                float d;
                NearestPlayer( pool[i], d );
                if( d < SPAWN_MIN_DIST ) continue;
                last[i] = g_Engine.time;
                pos = pool[i];
                return true;
            }
        }
        useFlank = !useFlank;   // try the other pool
    }
    return false;
}

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

int AliveHostages()
{
    int n = 0;
    for( uint i = 0; i < g_Hostages.length(); ++i )
    {
        CBaseEntity@ h = g_Hostages[i].GetEntity();
        if( h !is null && h.IsAlive() ) ++n;
    }
    return n;
}

CBaseEntity@ RandomAliveHostage()
{
    array<CBaseEntity@> hs;
    for( uint i = 0; i < g_Hostages.length(); ++i )
    {
        CBaseEntity@ h = g_Hostages[i].GetEntity();
        if( h !is null && h.IsAlive() ) hs.insertLast( h );
    }
    if( hs.length() == 0 ) return null;
    return hs[ Math.RandomLong( 0, hs.length() - 1 ) ];
}

void HealAll()
{
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p is null || !p.IsConnected() || !p.IsAlive() ) continue;
        p.pev.health = p.pev.max_health;
    }
}

void Big( const string& in msg )
{
    g_PlayerFuncs.HudMessageAll( g_HudBig, msg );
    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] " + msg + "\n" );
}

void PlayerHud()
{
    for( int i = 1; i <= g_Engine.maxClients; ++i )
    {
        CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex( i );
        if( p is null || !p.IsConnected() ) continue;
        string line = "$" + GetMoney( p ) + "   lives " + ( MAX_TEAM_DEATHS - g_Deaths ) + "/" + MAX_TEAM_DEATHS;
        if( g_HostageTotal > 0 ) line += "   hostages " + AliveHostages() + "/" + g_HostageTotal;
        if( p.IsAlive() && InBuyZone( p ) ) line += ( g_Stations.length() > 0 ) ? "   [BUY ZONE]  E on dealer / B" : "   [BUY ZONE]  B / buy";
        g_PlayerFuncs.HudMessage( p, g_HudMoney, line );
        if( p.IsAlive() ) EnforceSlots( p );
    }
}

// ------------------------------------------------------------------ waves

string Clock( float secs )
{
    int s = int( secs + 0.5f );
    if( s < 0 ) s = 0;
    int m = s / 60; s = s % 60;
    return ( m < 10 ? "0" : "" ) + m + ":" + ( s < 10 ? "0" : "" ) + s;
}

void StartWave( int idx )
{
    g_WaveIdx = idx;
    WaveDef@ w = g_Waves[idx];
    int players = CountPlayers( false );
    if( players < 1 ) players = 1;
    float scale = 1.0f + 0.35f * float( players - 1 );

    // penalty from the previous (uncleared) wave: more HP and damage this wave, then it is gone
    g_DmgMult = 1.0f + g_Penalty;
    float hpMult = w.healthMult * ( 1.0f + g_Penalty );
    string penaltyTxt = g_Penalty > 0.0f ? "  [+" + int( g_Penalty * 100.0f + 0.5f ) + "% HP/DMG]" : "";
    g_Penalty = 0.0f;
    g_WaveHpMult = hpMult;

    g_Queue.resize( 0 );
    g_Alive.resize( 0 );
    g_IdleSecs.resize( 0 );
    for( uint i = 0; i < w.spawns.length(); ++i )
    {
        int n = int( float( w.spawns[i].count * WAVE_COUNT_MULT ) * scale + 0.5f );
        if( w.spawns[i].count == 1 ) n = 1;     // bosses stay single
        for( int k = 0; k < n; ++k ) g_Queue.insertLast( w.spawns[i].cls );
    }
    for( uint i = g_Queue.length(); i > 1; --i )
    {
        uint j = Math.RandomLong( 0, i - 1 );
        string tmp = g_Queue[i - 1]; g_Queue[i - 1] = g_Queue[j]; g_Queue[j] = tmp;
    }
    g_WaveTotal = int( g_Queue.length() );
    g_WaveStart = g_Engine.time;
    g_Timer = WAVE_TIME;
    g_State = PVE_WAVE;
    Big( w.title + "  (" + g_WaveTotal + " monsters)" + penaltyTxt );
}


bool SpawnOne( const string& in cls, float healthMult, bool allowFlank )
{
    Vector pos;
    if( !PickSpawn( allowFlank, pos ) ) return false;
    pos.z += 8.0f;
    Vector ang( 0, Math.RandomFloat( 0, 360 ), 0 );

    CBaseEntity@ e = g_EntityFuncs.Create( cls, pos, ang, false, null );
    if( e is null ) return true;    // bad class: drop it from the queue
    g_EntityFuncs.DispatchSpawn( e.edict() );

    e.SetClassification( CLASS_ALIEN_MILITARY );
    e.pev.health = e.pev.health * healthMult;
    e.pev.max_health = e.pev.health;

    CBaseMonster@ m = e.MyMonsterPointer();
    if( m !is null )
    {
        CBaseEntity@ target = null;
        if( g_HostageTotal > 0 && Math.RandomLong( 0, 99 ) < HOSTAGE_TARGET_PCT )
            @target = RandomAliveHostage();
        if( target is null )
            @target = RandomAlivePlayer();
        if( target !is null )
        {
            m.m_hEnemy = EHandle( target );
            m.SetConditions( bits_COND_NEW_ENEMY );
        }
    }
    g_Alive.insertLast( EHandle( e ) );
    g_IdleSecs.insertLast( 0 );
    return true;
}

int PruneAndCountAlive()
{
    int alive = 0;
    for( uint i = 0; i < g_Alive.length(); )
    {
        CBaseEntity@ e = g_Alive[i].GetEntity();
        if( e is null || !e.IsAlive() )
        {
            if( e !is null )
            {
                CBasePlayer@ killer = KillerOf( e );
                if( killer !is null )
                {
                    AddMoney( killer, KILL_REWARD );
                    g_PlayerFuncs.ClientPrint( killer, HUD_PRINTCENTER, "+$" + KILL_REWARD );
                }
            }
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
    int bonus = WAVE_BONUS_BASE + WAVE_BONUS_PER * ( g_WaveIdx + 1 );
    AddMoneyAll( bonus );
    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[PVE] Wave bonus: $" + bonus + " to everyone.\n" );
    bool last = ( g_WaveIdx + 1 >= int( g_Waves.length() ) );
    if( last )
    {
        g_State = PVE_VICTORY;
        g_Timer = VICTORY_RESTART;
        Big( "VICTORY! The map is clear. Restarting in " + int( VICTORY_RESTART ) + "s" );
    }
    else
    {
        g_State = PVE_CLEARED;   // g_Timer keeps running down; the console starts the next wave early
        Big( "Wave cleared! Buy, then press E on the console: the sooner, the bigger the bonus (up to $" + SPEED_BONUS_MAX + ")" );
    }
}

void Defeat()
{
    if( g_State == PVE_DEFEAT ) return;
    ClearRemaining();
    g_State = PVE_DEFEAT;
    g_Timer = VICTORY_RESTART;
    Big( "DEFEAT. Restarting in " + int( VICTORY_RESTART ) + "s" );
}

// the 90 s ran out with monsters still alive
void WaveTimedOut( int remaining )
{
    float frac = g_WaveTotal > 0 ? float( remaining ) / float( g_WaveTotal ) : 0.0f;
    if( frac > 1.0f ) frac = 1.0f;
    g_Penalty = PENALTY_MAX * frac;
    ClearRemaining();
    Big( "Time's up! " + remaining + "/" + g_WaveTotal + " left -> next wave gets +" + int( g_Penalty * 100.0f + 0.5f ) + "% HP and damage" );
    bool last = ( g_WaveIdx + 1 >= int( g_Waves.length() ) );
    if( last )
    {
        g_State = PVE_VICTORY;
        g_Timer = VICTORY_RESTART;
        Big( "Final wave over. Restarting in " + int( VICTORY_RESTART ) + "s" );
        return;
    }
    StartWave( g_WaveIdx + 1 );
}

void RestartMap()
{
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
    PlayerHud();

    if( g_HostageTotal > 0 && AliveHostages() == 0 && ( g_State == PVE_WAVE || g_State == PVE_CLEARED ) )
    {
        Big( "All hostages are dead!" );
        Defeat();
    }

    if( g_State == PVE_WAITING )
        return;

    if( g_State == PVE_COUNTDOWN )
    {
        g_Timer -= THINK_INTERVAL;
        g_PlayerFuncs.HudMessageAll( g_HudStatus, "Get ready - first wave in " + int( g_Timer + 0.5f ) + "s  (E on the console to start now)" );
        if( g_Timer <= 0.0f )
            StartWave( 0 );
        return;
    }

    if( g_State == PVE_CLEARED )
    {
        g_Timer -= THINK_INTERVAL;
        int bonus = int( float( SPEED_BONUS_MAX ) * g_Timer / WAVE_TIME );
        if( bonus < 0 ) bonus = 0;
        g_PlayerFuncs.HudMessageAll( g_HudStatus,
            "WAVE CLEARED   next wave in " + Clock( g_Timer ) + "\nPress E on the console now: +$" + bonus + " for everyone" );
        if( g_Timer <= 0.0f )
            StartWave( g_WaveIdx + 1 );
        return;
    }

    if( g_State == PVE_VICTORY || g_State == PVE_DEFEAT )
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
    g_Timer -= THINK_INTERVAL;
    int alive = PruneAndCountAlive();

    int spawned = 0;
    while( g_Queue.length() > 0 && alive < MAX_ALIVE && spawned < SPAWN_PER_TICK )
    {
        string cls = g_Queue[ g_Queue.length() - 1 ];
        if( !SpawnOne( cls, g_WaveHpMult, w.flank ) ) break;   // every point busy: wait a second
        g_Queue.removeLast();
        ++alive; ++spawned;
    }

    NudgeMonsters();

    int remaining = alive + int( g_Queue.length() );
    g_PlayerFuncs.HudMessageAll( g_HudStatus,
        w.title + "   " + Clock( g_Timer ) + "\nMonsters left: " + remaining + " / " + g_WaveTotal );

    if( remaining <= 0 )
    {
        WaveCleared();
        return;
    }
    if( g_Timer <= 0.0f )
        WaveTimedOut( remaining );
}

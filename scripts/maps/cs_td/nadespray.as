// weapon_nadespray - the TD shop's grenade: one purchase = 35 CS 1.6 HE grenades, and one click
// throws all of them in a stream, one every NS_INTERVAL seconds (PJ-010's nadespray, Sven edition).
// Uses the cs16 pack's HE models + grenade projectile (bounce, 1.5 s fuse, fireball, credited to the thrower).
// Included by cs_td/td.as; needs the cs16 weapon pack (core.as includes it).

namespace TD_NADESPRAY
{

const string CLS       = "weapon_nadespray";
const string HUD_DIR   = "cs_td/";                 // sprites/cs_td/weapon_nadespray.txt
const int    MAX_CARRY = 35;
const int    GIVE      = 35;                        // one purchase = 35 grenades
const float  NS_INTERVAL = 0.1f;                    // seconds between grenades
const float  DAMAGE      = 150.0f;                  // same as a CS HE
const float  FUSE        = 1.5f;

enum Anim { IDLE = 0, PULLPIN, THROW, DRAW };

class weapon_nadespray : ScriptBasePlayerWeaponEntity, CS16BASE::WeaponBase
{
    private CBasePlayer@ m_pPlayer
    {
        get const { return cast<CBasePlayer@>( self.m_hPlayer.GetEntity() ); }
        set       { self.m_hPlayer = EHandle( @value ); }
    }
    private bool  m_bThrowing = false;  // one click = keep throwing until the grenades run out
    private float m_flNextToss = 0;

    void Spawn()
    {
        Precache();
        CommonSpawn( CS16_HEGRENADE::W_MODEL, GIVE );
        self.pev.scale = 1;
    }

    void Precache()
    {
        self.PrecacheCustomModels();
        g_Game.PrecacheModel( CS16_HEGRENADE::W_MODEL );
        g_Game.PrecacheModel( CS16_HEGRENADE::V_MODEL );
        g_Game.PrecacheModel( CS16_HEGRENADE::P_MODEL );
        g_Game.PrecacheOther( CS16GRENADEPROJECTILE::DEFAULT_PROJ_NAME );
        CommonSpritePrecache();
        g_Game.PrecacheGeneric( "sprites/" + HUD_DIR + CLS + ".txt" );
    }

    bool GetItemInfo( ItemInfo& out info )
    {
        info.iMaxAmmo1 = MAX_CARRY;
        info.iMaxAmmo2 = -1;
        info.iMaxClip  = WEAPON_NOCLIP;
        info.iSlot     = 4;
        info.iPosition = 12;
        info.iId       = g_ItemRegistry.GetIdForName( self.pev.classname );
        info.iFlags    = ITEM_FLAG_LIMITINWORLD;
        info.iWeight   = 5;
        return true;
    }

    bool AddToPlayer( CBasePlayer@ pPlayer ) { return CommonAddToPlayer( pPlayer ); }
    bool CanHaveDuplicates() { return true; }    // buying again tops the grenades up

    bool Deploy()
    {
        m_bThrowing = false;
        return Deploy( CS16_HEGRENADE::V_MODEL, CS16_HEGRENADE::P_MODEL, DRAW, "gren", 0, ( 20.0 / 30.0 ) );
    }

    void Holster( int skipLocal = 0 )
    {
        m_bThrowing = false;
        CommonHolster();
        BaseClass.Holster( skipLocal );
    }

    int Ammo() { return m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ); }

    void PrimaryAttack()
    {
        if( m_bThrowing ) return;
        if( Ammo() <= 0 )
        {
            g_PlayerFuncs.ClientPrint( m_pPlayer, HUD_PRINTCENTER, "No grenades - buy more" );
            self.m_flNextPrimaryAttack = WeaponTimeBase() + 0.5;
            return;
        }
        m_bThrowing = true;
        m_flNextToss = 0;
        self.SendWeaponAnim( THROW, 0, 0 );
        m_pPlayer.SetAnimation( PLAYER_ATTACK1 );
        self.m_flNextPrimaryAttack = WeaponTimeBase() + 0.5;
    }

    void TossOne()
    {
        // aim like the HE throw, plus a little random spread
        Vector ang = m_pPlayer.pev.v_angle + m_pPlayer.pev.punchangle;
        ang.x = ang.x < 0 ? -10 + ang.x * ( 80.0 / 90.0 ) : -10 + ang.x * ( 100.0 / 90.0 );
        ang.x += Math.RandomFloat( -4, 4 );
        ang.y += Math.RandomFloat( -6, 6 );
        float vel = Math.min( ( 90.0f - ang.x ) * 6, 750.0f ) * Math.RandomFloat( 0.85, 1.05 );
        Math.MakeVectors( ang );
        // spawn a bit ahead and below the eyes so the stream does not cover the screen
        Vector src = m_pPlayer.pev.origin + m_pPlayer.pev.view_ofs + g_Engine.v_forward * 40 - g_Engine.v_up * 10;
        CS16GRENADEPROJECTILE::TossGrenade( m_pPlayer.pev, src, g_Engine.v_forward * vel + m_pPlayer.pev.velocity,
                                            FUSE, DAMAGE, CS16_HEGRENADE::W_MODEL );
        m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType, Ammo() - 1 );
    }

    void ItemPostFrame()
    {
        if( m_bThrowing && g_Engine.time >= m_flNextToss )
        {
            if( Ammo() > 0 )
            {
                TossOne();
                m_flNextToss = g_Engine.time + NS_INTERVAL;
                self.m_flTimeWeaponIdle = WeaponTimeBase() + 0.6;
            }
            if( Ammo() <= 0 )
            {
                m_bThrowing = false;
                self.SendWeaponAnim( DRAW, 0, 0 );
            }
        }
        BaseClass.ItemPostFrame();
    }

    void WeaponIdle()
    {
        if( self.m_flTimeWeaponIdle > WeaponTimeBase() ) return;
        self.SendWeaponAnim( IDLE, 0, 0 );
        self.m_flTimeWeaponIdle = WeaponTimeBase() + 6;
    }
}

void Register()
{
    CS16GRENADEPROJECTILE::Register();
    CS16BASE::RegisterCWEntityEX( "TD_NADESPRAY::", CLS, CLS, CLS, HUD_DIR, CLS );
}

}

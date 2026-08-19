#include <sourcemod>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

// Never run fewer than this many bots -- one or two is not a team.
#define MIN_BOTS 3

public Plugin myinfo =
{
    name = "Empty Team Bots",
    author = "LAN of DOOM",
    description = "Fill an empty team with bots",
    version = "3.0",
    url = "https://github.com/lanofdoom/counterstrikesource-empty-team-bots"
};

ConVar g_cvBotQuota;
ConVar g_cvBotQuotaMode;
ConVar g_cvBotJoinTeam;

bool g_bBalancing;

public void OnPluginStart()
{
    g_cvBotQuota = FindConVar("bot_quota");
    g_cvBotQuotaMode = FindConVar("bot_quota_mode");
    g_cvBotJoinTeam = FindConVar("bot_join_team");

    if (g_cvBotQuota == null || g_cvBotQuotaMode == null || g_cvBotJoinTeam == null)
        SetFailState("Missing bot cvars; is this a CS:S server with bots installed?");

    AutoExecConfig(true, "empty_team_bots");

    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_team", Event_PlayerTeam);
}

public void OnConfigsExecuted()
{
    // The map's config just reset the bot cvars, so reassert them. Clients
    // are still reconnecting here, so this only re-establishes the cvar that
    // does not depend on a head count; ReEvaluateBots settles the rest as
    // players actually arrive.
    g_cvBotQuotaMode.SetString("normal");
    ReEvaluateBots(true);
}

// ---------------------------------------------------------------------------
// Bot management
// ---------------------------------------------------------------------------

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ReEvaluateBots();
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    if (g_bBalancing)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    // GetClientTeam still reports the old team during this event, so re-check
    // next frame, once the change has landed.
    if (client > 0 && !IsFakeClient(client))
        RequestFrame(Frame_ReEvaluateBots);
}

public void Frame_ReEvaluateBots(any data)
{
    ReEvaluateBots();
}

public void OnClientPutInServer(int client)
{
    // A joining client has no team yet; check once that has settled.
    if (!IsFakeClient(client))
        RequestFrame(Frame_ReEvaluateBots);
}

public void OnClientDisconnect_Post(int client)
{
    ReEvaluateBots();
}

// duringMapLoad distinguishes the transient zero-humans read every map change
// starts with (clients are still reconnecting, do nothing and let them
// resettle the quota) from every other call site, where zero humans means
// the last one just left. Treating those the same left bot_quota at
// whatever it was last set to, so bots kept playing a full match with no
// human anywhere near it -- which mp_winlimit/mp_maxrounds/mp_timelimit read
// as a normal match and cycled to the next map the moment it "finished",
// forever, since the next map's zero-humans read was itself mistaken for a
// map-load and left the stale quota in place again.
void ReEvaluateBots(bool duringMapLoad = false)
{
    int ctHumans, tHumans, humans;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || IsClientSourceTV(i))
            continue;

        // Counted even before they pick a side, so that a server where someone
        // is still in team selection is not mistaken for the empty one seen
        // mid-map-load.
        humans++;

        switch (GetClientTeam(i))
        {
            case CS_TEAM_CT: ctHumans++;
            case CS_TEAM_T:  tHumans++;
        }
    }

    if (humans == 0)
    {
        if (duringMapLoad)
            return;

        g_cvBotQuota.SetInt(0);
        ServerCommand("bot_kick");
        return;
    }

    // Bots fill a side only when it is empty and every human is on the other.
    // Humans on both sides already have a game, so that leaves no opponents
    // and no bots.
    int opponents;
    if (tHumans == 0)
        opponents = ctHumans;
    else if (ctHumans == 0)
        opponents = tHumans;

    int botTeam = (tHumans == 0) ? CS_TEAM_T : CS_TEAM_CT;

    // Slightly outnumber the humans they face, but always a real team.
    int quota = 0;
    if (opponents > 0)
        quota = (opponents + 1 < MIN_BOTS) ? MIN_BOTS : opponents + 1;

    g_cvBotJoinTeam.SetString(botTeam == CS_TEAM_T ? "T" : "CT");
    g_cvBotQuota.SetInt(quota);

    if (quota == 0)
    {
        ServerCommand("bot_kick");
        return;
    }

    // Move any bot that ended up on the humans' side.
    g_bBalancing = true;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i) || IsClientSourceTV(i))
            continue;

        int team = GetClientTeam(i);
        if ((team == CS_TEAM_T || team == CS_TEAM_CT) && team != botTeam)
            CS_SwitchTeam(i, botTeam);
    }
    g_bBalancing = false;
}

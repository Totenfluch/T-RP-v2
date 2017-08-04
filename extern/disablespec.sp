//Pragma
#pragma semicolon 1
#pragma newdecls required

//Sourcemod Includes
#include <sourcemod>
#include <sourcemod-misc>
#include <cstrike>

//Globals

public Plugin myinfo = 
{
	name = "Disable Spec", 
	author = "Keith Warren (Drixevel)", 
	description = "Disable Spectator for non-admins.", 
	version = "1.0.0", 
	url = "http://www.drixevel.com/"
};

public void OnPluginStart()
{
	AddCommandListener(OnTeamJoin, "jointeam");
	AddCommandListener(OnSpectate, "spectate");
}

public Action OnTeamJoin(int client, const char[] command, int argc)
{
	char sJoining[12];
	GetCmdArg(1, sJoining, sizeof(sJoining));
	int joining = StringToInt(sJoining);
	
	if (joining == CS_TEAM_SPECTATOR)
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action OnSpectate(int client, const char[] command, int argc)
{
	return Plugin_Handled;
}
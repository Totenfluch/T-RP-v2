//Pragma
#pragma semicolon 1
#pragma newdecls required

//Sourcemod Includes
#include <sourcemod>
#include <sourcemod-misc>
#include <csgocolors>

//Globals

public Plugin myinfo = 
{
	name = "Killfeed Admins", 
	author = "Keith Warren (Drixevel)", 
	description = "Only show killfeed to admins.", 
	version = "1.0.0", 
	url = "http://www.drixevel.com/"
};

public void OnPluginStart()
{
	HookEvent("player_death", Event_OnPlayerDeathPre, EventHookMode_Pre);
}

public Action Event_OnPlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));   
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	Event newEvent = CreateEvent("player_death");
	newEvent.SetInt("userid", event.GetInt("userid"));
	newEvent.SetInt("attacker", event.GetInt("attacker"));
	newEvent.SetInt("assister", event.GetInt("assister"));
	newEvent.SetBool("headshot", event.GetBool("headshot"));
	newEvent.SetInt("penetrated", event.GetInt("penetrated"));
	newEvent.SetInt("dominated", event.GetInt("dominated"));
	newEvent.SetInt("revenge", event.GetInt("revenge"));
	
	char buffer[250];
	
	event.GetString("weapon", buffer, sizeof(buffer));
	newEvent.SetString("weapon", buffer);
	
	event.GetString("weapon_itemid", buffer, sizeof(buffer));
	newEvent.SetString("weapon_itemid", buffer);
	
	event.GetString("weapon_fauxitemid", buffer, sizeof(buffer));
	newEvent.SetString("weapon_fauxitemid", buffer);
	
	event.GetString("weapon_originalowner_xuid", buffer, sizeof(buffer));
	newEvent.SetString("weapon_originalowner_xuid", buffer);
	
	SetEventBroadcast(event, true);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && CheckCommandAccess(i, "", ADMFLAG_GENERIC))
		{
			newEvent.FireToClient(i);
			CPrintToChat(i, "{red}[KILLFEED] %N killed %N", attacker, victim);
		}
	}
	
	newEvent.Cancel();
}
//Pragma
#pragma semicolon 1
#pragma newdecls required

//Sourcemod Includes
#include <sourcemod>
#include <sourcemod-misc>
#include <cstrike>

//Globals
bool g_bBinocularsEnabled[MAXPLAYERS + 1];
int g_iDefaultFOV[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "Binoculars", 
	author = "Keith Warren (Drixevel)", 
	description = "A plugin which does things... binoculars.",
	version = "1.0.0", 
	url = "http://www.drixevel.com/"
};

public void OnPluginStart()
{
	RegConsoleCmd("+binoculars", Command_PlusBinoculars);
	RegConsoleCmd("-binoculars", Command_MinusBinoculars);
}

public Action Command_PlusBinoculars(int client, int args)
{
	if (!CheckCommandAccess(client, "", ADMFLAG_CUSTOM5))
	{
		PrintToChat(client, "You are not allowed to use this command.");
		return Plugin_Handled;
	}
	
	EnableBinoculars(client);
	return Plugin_Handled;
}

public Action Command_MinusBinoculars(int client, int args)
{
	DisableBinoculars(client);
	return Plugin_Handled;
}

void EnableBinoculars(int client)
{
	g_iDefaultFOV[client] = GetEntProp(client, Prop_Send, "m_iFOV");
	SetEntProp(client, Prop_Send, "m_iFOV", 15);
	g_bBinocularsEnabled[client] = true;
}

void DisableBinoculars(int client)
{
	if (g_bBinocularsEnabled[client])
	{
		SetEntProp(client, Prop_Send, "m_iFOV", g_iDefaultFOV[client]);
		g_bBinocularsEnabled[client] = false;
	}
}
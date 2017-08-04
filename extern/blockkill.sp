//Pragma
#pragma semicolon 1
#pragma newdecls required

//Sourcemod Includes
#include <sourcemod>
//#include <sourcemod-misc>

//Globals
ConVar convar_Status;

public Plugin myinfo = 
{
	name = "Block Kill", 
	author = "Keith Warren (Drixevel)", 
	description = "", 
	version = "1.0.0", 
	url = "http://www.drixevel.com/"
};

public void OnPluginStart()
{
	convar_Status = CreateConVar("sm_blockkill_status", "1", "Status for the plugin.\n(1 = on, 0 = off)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	AutoExecConfig();
	
	AddCommandListener(OnListener_Kill, "kill");
}

public Action OnListener_Kill(int client, const char[] command, int argc)
{
	return GetConVarBool(convar_Status) ? Plugin_Continue : Plugin_Stop;
}
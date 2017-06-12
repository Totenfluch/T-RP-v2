/*
							T-RP
   			Copyright (C) 2017 Christian Ziegler
   				 
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    
    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#pragma semicolon 1

#define PLUGIN_AUTHOR "Totenfluch"
#define PLUGIN_VERSION "1.00"

#include <sourcemod>
#include <sdktools>
#include <rpg_npc_core>
#include <autoexecconfig>
#include <rpg_jobs_core>
#include <tConomy>

#pragma newdecls required

#define MAX_PERKS 128
#define MAX_JOBS 64

//int g_iLoadedPerks;
//char g_cLoadedPerks[MAX_PERKS][64];

char g_cOwnedPerks[MAXPLAYERS + 1][MAX_PERKS][64];
int g_iOwnedPerks[MAXPLAYERS + 1];

int g_iLoadedJobs;
char g_cLoadedJobs[MAX_JOBS][64];

char dbconfig[] = "gsxh_multiroot";
Database g_DB;

char my_npcType[128] = "Perk Shop";

int g_iLastInteractedWith[MAXPLAYERS + 1];

enum perkProperties {
	String:ppName[64], 
	ppCost, 
	String:ppJob[64], 
	ppLevel
}

int g_eLoadedPerks[MAX_PERKS][perkProperties];

int g_iLoadedPerks;

public Plugin myinfo = 
{
	name = "[T-RP] Perks Core", 
	author = PLUGIN_AUTHOR, 
	description = "Adds Perks for T-RP", 
	version = PLUGIN_VERSION, 
	url = "https://totenfluch.de"
};

public void OnPluginStart() {
	char error[255];
	g_DB = SQL_Connect(dbconfig, true, error, sizeof(error));
	SQL_SetCharset(g_DB, "utf8");
	
	char createTableQuery[4096];
	Format(createTableQuery, sizeof(createTableQuery), "CREATE TABLE IF NOT EXISTS t_rpg_perks ( `Id` BIGINT NOT NULL AUTO_INCREMENT , `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , `playerid` VARCHAR(20) NOT NULL , `perk` VARCHAR(64) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL , PRIMARY KEY (`Id`), UNIQUE (`playerid`, `perk`)) ENGINE = InnoDB;");
	SQL_TQuery(g_DB, SQLErrorCheckCallback, createTableQuery);
	
	RegConsoleCmd("sm_cperks", cmdCheckPerks);
}

public Action cmdCheckPerks(int client, int args) {
	PrintToConsole(client, ">> %i Perks <<", g_iOwnedPerks[client]);
	for (int i = 0; i < g_iOwnedPerks[client]; i++)
	PrintToConsole(client, "|-> %s", g_cOwnedPerks[client][i]);
	return Plugin_Handled;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	/*
		Checks if a Player has a Perk
		@Param1-> int owner
		@Param2-> char Perk[64]
		
		@return true if client has Perk
	
	*/
	CreateNative("perks_hasPerk", Native_hasPerk);
}

public int Native_hasPerk(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	char cPerk[64];
	GetNativeString(2, cPerk, sizeof(cPerk));
	return hasPerk(client, cPerk);
}

public void OnMapStart() {
	npc_registerNpcType(my_npcType);
	loadConfig();
}

public void clearConfig() {
	g_iLoadedJobs = 0;
	g_iLoadedPerks = 0;
	for (int x = 0; x < MAX_PERKS; x++) {
		g_eLoadedPerks[x][ppCost] = 0;
		g_eLoadedPerks[x][ppLevel] = 0;
		strcopy(g_eLoadedPerks[x][ppName], 64, "");
		strcopy(g_eLoadedPerks[x][ppJob], 64, "");
	}
	for (int i = 0; i < MAX_JOBS; i++)
	strcopy(g_cLoadedJobs[i], 64, "");
}


public bool loadConfig() {
	clearConfig();
	
	KeyValues kv = new KeyValues("rpg_perks_vendor");
	kv.ImportFromFile("addons/sourcemod/configs/rpg_perks_vendor.txt");
	
	if (!kv.GotoFirstSubKey())
		return false;
	
	char buffer[64];
	do
	{
		kv.GetSectionName(buffer, sizeof(buffer));
		strcopy(g_eLoadedPerks[g_iLoadedPerks][ppName], 64, buffer);
		
		char tempVars[64];
		kv.GetString("cost", tempVars, 64, "");
		g_eLoadedPerks[g_iLoadedPerks][ppCost] = StringToInt(tempVars);
		
		kv.GetString("job", tempVars, 64, "");
		strcopy(g_eLoadedPerks[g_iLoadedPerks][ppJob], 64, tempVars);
		tryToRegisterJob(tempVars);
		
		kv.GetString("level", tempVars, 64, "");
		g_eLoadedPerks[g_iLoadedPerks][ppLevel] = StringToInt(tempVars);
		
		g_iLoadedPerks++;
		
	} while (kv.GotoNextKey());
	
	delete kv;
	return true;
}

public void tryToRegisterJob(char name[64]) {
	for (int i = 0; i < MAX_JOBS; i++)
	if (StrEqual(name, g_cLoadedJobs[i]))
		return;
	strcopy(g_cLoadedJobs[g_iLoadedJobs++], 64, name);
}


public void OnClientPostAdminCheck(int client) {
	for (int i = 0; i < g_iOwnedPerks[client]; i++)
	strcopy(g_cOwnedPerks[client][i], 64, "");
	g_iOwnedPerks[client] = 0;
	g_iLastInteractedWith[client] = -1;
	loadPerks(client);
}

public void loadPerks(int client) {
	char playerid[20];
	GetClientAuthId(client, AuthId_Steam2, playerid, sizeof(playerid));
	
	char loadPerksQuery[1024];
	Format(loadPerksQuery, sizeof(loadPerksQuery), "SELECT perk FROM t_rpg_perks WHERE playerid = '%s';", playerid);
	SQL_TQuery(g_DB, SQLLoadPerksQuery, loadPerksQuery, client);
}

public void SQLLoadPerksQuery(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	if (!isValidClient(client))
		return;
	while (SQL_FetchRow(hndl)) {
		char cPerk[64];
		SQL_FetchString(hndl, 0, cPerk, sizeof(cPerk));
		strcopy(g_cOwnedPerks[client][g_iOwnedPerks[client]++], 64, cPerk);
	}
}

public void addPerk(int client, char perk[64]) {
	char playerid[20];
	GetClientAuthId(client, AuthId_Steam2, playerid, sizeof(playerid));
	
	char addPerkQuery[1024];
	Format(addPerkQuery, sizeof(addPerkQuery), "INSERT IGNORE INTO `t_rpg_perks` (`Id`, `timestamp`, `playerid`, `perk`) VALUES (NULL, CURRENT_TIMESTAMP, '%s', '%s');", playerid, perk);
	SQL_TQuery(g_DB, SQLErrorCheckCallback, addPerkQuery);
	
	strcopy(g_cOwnedPerks[client][g_iOwnedPerks[client]++], 64, perk);
}

public void SQLErrorCheckCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if (!StrEqual(error, ""))
		LogError(error);
}

stock bool isValidClient(int client) {
	return (1 <= client <= MaxClients && IsClientInGame(client));
}

public void OnNpcInteract(int client, char npcType[64], char UniqueId[128], int entIndex) {
	if (!StrEqual(my_npcType, npcType))
		return;
	g_iLastInteractedWith[client] = entIndex;
	
	showTopMenu(client);
}

public bool hasPerk(int client, char cPerks[64]) {
	for (int i = 0; i < g_iOwnedPerks[client]; i++)
	if (StrEqual(g_cOwnedPerks[client][i], cPerks))
		return true;
	return false;
}

public void showTopMenu(int client) {
	Menu topMenu = CreateMenu(topMenuHandler);
	SetMenuTitle(topMenu, ">Perks<");
	char ownedAmount[32];
	Format(ownedAmount, sizeof(ownedAmount), "You own: %i/%i Perks", g_iOwnedPerks[client], g_iLoadedPerks);
	AddMenuItem(topMenu, "x", ownedAmount, ITEMDRAW_DISABLED);
	for (int i = 0; i < g_iLoadedJobs; i++) {
		char displayText[64];
		Format(displayText, sizeof(displayText), "Perks for %s", g_cLoadedJobs[i]);
		AddMenuItem(topMenu, g_cLoadedJobs[i], displayText);
	}
	DisplayMenu(topMenu, client, 60);
}

public int topMenuHandler(Handle menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		char cValue[64];
		GetMenuItem(menu, item, cValue, sizeof(cValue));
		Menu nextMenu = CreateMenu(nextMenuHandler);
		char menuTitle[64];
		Format(menuTitle, sizeof(menuTitle), "Buy Perks for %s", cValue);
		SetMenuTitle(nextMenu, menuTitle);
		int money = tConomy_getCurrency(client);
		char jobReformat[128];
		strcopy(jobReformat, sizeof(jobReformat), cValue);
		bool hasJob = jobs_isActiveJob(client, jobReformat);
		int level = jobs_getLevel(client);
		if (!hasJob) {
			char noJobDisplay[64];
			Format(noJobDisplay, sizeof(noJobDisplay), "You currently not a %s", cValue);
			AddMenuItem(nextMenu, "x", noJobDisplay, ITEMDRAW_DISABLED);
		}
		for (int i = 0; i < g_iLoadedPerks; i++) {
			if (StrEqual(cValue, g_eLoadedPerks[i][ppJob])) {
				char display[92];
				char perkReformat[64];
				strcopy(perkReformat, sizeof(perkReformat), g_eLoadedPerks[i][ppName]);
				bool hasThePerk = hasPerk(client, perkReformat);
				if (!hasThePerk)
					Format(display, sizeof(display), "%s (%i)[%i]", g_eLoadedPerks[i][ppName], g_eLoadedPerks[i][ppCost], g_eLoadedPerks[i][ppLevel]);
				else
					Format(display, sizeof(display), "^~ %s | Owned ~^", g_eLoadedPerks[i][ppName]);
				AddMenuItem(nextMenu, g_eLoadedPerks[i][ppName], display, hasJob && money >= g_eLoadedPerks[i][ppCost] && level >= g_eLoadedPerks[i][ppLevel] && !hasThePerk ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
			}
		}
		DisplayMenu(nextMenu, client, 60);
	}
	if (action == MenuAction_End) {
		delete menu;
	}
}

public int nextMenuHandler(Handle menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		char cValue[64];
		GetMenuItem(menu, item, cValue, sizeof(cValue));
		
		float playerPos[3];
		float entPos[3];
		if (!isValidClient(client))
			return;
		if (!IsValidEntity(g_iLastInteractedWith[client]))
			return;
		GetClientAbsOrigin(client, playerPos);
		GetEntPropVector(g_iLastInteractedWith[client], Prop_Data, "m_vecOrigin", entPos);
		if (GetVectorDistance(playerPos, entPos) > 100.0)
			return;
		
		int perkId;
		if ((perkId = findPerkByName(cValue)) == -1)
			return;
		
		if (tConomy_getCurrency(client) >= g_eLoadedPerks[perkId][ppCost]) {
			char reason[256];
			Format(reason, sizeof(reason), "Bought %s for %i", g_eLoadedPerks[perkId][ppName], g_eLoadedPerks[perkId][ppCost]);
			tConomy_removeCurrency(client, g_eLoadedPerks[perkId][ppCost], reason);
			
			char reformatPerkName[64];
			strcopy(reformatPerkName, sizeof(reformatPerkName), g_eLoadedPerks[perkId][ppName]);
			addPerk(client, reformatPerkName);
		}
	}
	if (action == MenuAction_End) {
		delete menu;
	}
}

public int findPerkByName(char name[64]) {
	for (int i = 0; i < g_iLoadedPerks; i++)
	if (StrEqual(g_eLoadedPerks[i][ppName], name))
		return i;
	return -1;
} 
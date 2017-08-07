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
#include <rpg_jobs_core>
#include <rpg_npc_core>
#include <devzones>
#include <multicolors>
#include <tConomy>
#include <rpg_inventory_core>
#include <rpg_perks>
#include <smlib>
#include <rpg_jail>
#include <rpg_job_police>
#include <tStocks>

#pragma newdecls required

#define MAX_ZONES 128
#define MAX_PLANTS 1024
#define TIME_TO_NEXT_STAGE 240

int g_iPlayerPrevButtons[MAXPLAYERS + 1];
bool g_bPlayerInGardenerZone[MAXPLAYERS + 1];
int g_iCollectedLoot[MAXPLAYERS + 1][MAX_ZONES];
int g_iPlayerZoneId[MAXPLAYERS + 1];

char g_cGardenerZones[MAX_ZONES][PLATFORM_MAX_PATH];
int g_iGardenerZoneCooldown[MAXPLAYERS + 1][MAX_ZONES];
int g_iLoadedZones = 0;

int g_iZoneCooldown = 400;
int MAX_COLLECT = 5;

char activeZone[MAXPLAYERS + 1][128];

char npctype[128] = "Gardener Recruiter";

char dbconfig[] = "gsxh_multiroot";
Database g_DB;

int g_iHarvestIndex[MAXPLAYERS + 1];

bool loaded = false;

enum plantProperties {
	pEntRef, 
	String:pOwner[20], 
	String:pModel[128], 
	String:pCreatedTime[64], 
	pState, 
	pTime, 
	String:pFlags[64], 
	Float:pPos_x, 
	Float:pPos_y, 
	Float:pPos_z, 
	bool:pActive
}

int g_ePlayerPlants[MAX_PLANTS][plantProperties];
int g_iPlantsActive = 0;

public Plugin myinfo = 
{
	name = "[T-RP] Job: Gardener", 
	author = PLUGIN_AUTHOR, 
	description = "Adds mining to T-RP Jobs", 
	version = PLUGIN_VERSION, 
	url = "https://totenfluch.de"
};

public void OnPluginStart() {
	jobs_registerJob("Gardener", "Mow grass and do gardening stuff", 20, 300, 2.11);
	
	npc_registerNpcType(npctype);
	
	RegConsoleCmd("sm_gstats", cmdOnGStats, "shows gardening stats");
	
	HookEvent("round_start", onRoundStart);
	char error[255];
	g_DB = SQL_Connect(dbconfig, true, error, sizeof(error));
	SQL_SetCharset(g_DB, "utf8");
	
	char createTableQuery[2048];
	Format(createTableQuery, sizeof(createTableQuery), "CREATE TABLE IF NOT EXISTS `t_rpg_gardener_plants` ( `Id` BIGINT NOT NULL AUTO_INCREMENT , `playerid` VARCHAR(20) NOT NULL , `plantName` VARCHAR(128) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL , `plantLevel` INT NOT NULL , `plantTime` INT NOT NULL , `plantCreated` VARCHAR(64) NOT NULL, `posX` FLOAT NOT NULL, `posY` FLOAT NOT NULL, `posZ` FLOAT NOT NULL, PRIMARY KEY (`Id`)) ENGINE = InnoDB;");
	SQL_TQuery(g_DB, SQLErrorCheckCallback, createTableQuery);
}

public Action cmdOnGStats(int client, int args) {
	PrintToChatAll("InZone: %i Collected{0} %i Collected{1} %i ZoneID: %i Cd[1] %i Cd[1] %i", g_bPlayerInGardenerZone[client], g_iCollectedLoot[client][0], g_iCollectedLoot[client][1], g_iPlayerZoneId, g_iGardenerZoneCooldown[client][0], g_iGardenerZoneCooldown[client][1]);
	return Plugin_Handled;
}

public void OnMapStart() {
	CreateTimer(1.0, refreshTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	
	inventory_addItemHandle("Eggplant Seeds", 1);
	inventory_addItemHandle("Pumpkin Seeds", 1);
	inventory_addItemHandle("Strawberry Seeds", 1);
	
	PrecacheModel("models/custom_prop/ggc-plg-killzone/eggplant/eggplant_0.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/eggplant/eggplant_1.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/eggplant/eggplant_2.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/eggplant/eggplant_3.mdl");
	
	PrecacheModel("models/custom_prop/ggc-plg-killzone/pumpkinplant/pumpkinplant_0.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/pumpkinplant/pumpkinplant_1.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/pumpkinplant/pumpkinplant_2.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/pumpkinplant/pumpkinplant_3.mdl");
	
	PrecacheModel("models/custom_prop/ggc-plg-killzone/strawberryplant/strawberryplant_0.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/strawberryplant/strawberryplant_1.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/strawberryplant/strawberryplant_2.mdl");
	PrecacheModel("models/custom_prop/ggc-plg-killzone/strawberryplant/strawberryplant_3.mdl");
}

public void inventory_onItemUsed(int client, char itemname[128], int weight, char category[64], char category2[64], int rarity, char timestamp[64], int slot) {
	if (StrEqual(itemname, "Eggplant Seeds") || StrEqual(itemname, "Pumpkin Seeds") || StrEqual(itemname, "Strawberry Seeds")) {
		Menu m = CreateMenu(plantSeedHandler);
		char display[128];
		Format(display, sizeof(display), "What to do with '%s' ?", itemname);
		SetMenuTitle(m, display);
		AddMenuItem(m, itemname, "Plant Seeds");
		AddMenuItem(m, "throw", "Throw Away");
		int amount = inventory_getPlayerItemAmount(client, itemname);
		if (amount > 1) {
			char displ[128];
			Format(displ, sizeof(displ), "Throw all Away (%i)", amount);
			AddMenuItem(m, "throwall", displ);
		}
		DisplayMenu(m, client, 60);
	}
}

public int plantSeedHandler(Handle menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		char info[64];
		char display[64];
		int style = 0;
		GetMenuItem(menu, item, info, sizeof(info), style, display, sizeof(display));
		if (StrEqual(display, "Plant Seeds"))
			plantSeeds(client, info);
	}
	if (action == MenuAction_End) {
		delete menu;
	}
}

public void plantSeeds(int client, char[] plantName) {
	if (!jobs_isActiveJob(client, "Gardener")) {
		CPrintToChat(client, "[-T-]{red} You are not a Gardener");
		return;
	}
	
	if (getActivePlantsOfPlayerAmount(client) >= (2 + jobs_getLevel(client) / 2)) {
		CPrintToChat(client, "[-T-]{red} You can not have more than %i active plants (%i Active)", (2 + jobs_getLevel(client) / 2), getActivePlantsOfPlayerAmount(client));
		return;
	}
	
	if (jail_isInJail(client)) {
		CPrintToChat(client, "[-T-]{red} You can't plant Plants in jail..");
		return;
	}
	
	if (police_isPlayerCuffed(client)) {
		CPrintToChat(client, "[-T-]{red} You can't plant Plants while cuffed...");
		return;
	}
	
	if (!(GetEntityFlags(client) & FL_ONGROUND)) {
		CPrintToChat(client, "[-T-]{red} You have to stand on the Ground to plant...");
		return;
	}
	
	char item[128];
	strcopy(item, sizeof(item), plantName);
	char reason[256];
	Format(reason, sizeof(reason), "Planted %s", item);
	if (inventory_hasPlayerItem(client, item))
		inventory_removePlayerItems(client, item, 1, reason);
	else
		return;
	
	float pos[3];
	GetClientAbsOrigin(client, pos);
	
	char playerid[20];
	GetClientAuthId(client, AuthId_Steam2, playerid, sizeof(playerid));
	
	char plantTime[64];
	int time = GetTime();
	IntToString(time, plantTime, sizeof(plantTime));
	
	char plantModel[128];
	if (StrEqual(plantName, "Eggplant Seeds")) {
		strcopy(plantModel, sizeof(plantModel), "models/custom_prop/ggc-plg-killzone/eggplant/eggplant_0.mdl");
	} else if (StrEqual(plantName, "Pumpkin Seeds")) {
		strcopy(plantModel, sizeof(plantModel), "models/custom_prop/ggc-plg-killzone/pumpkinplant/pumpkinplant_0.mdl");
	} else if (StrEqual(plantName, "Strawberry Seeds")) {
		strcopy(plantModel, sizeof(plantModel), "models/custom_prop/ggc-plg-killzone/strawberryplant/strawberryplant_0.mdl");
	} else {
		CPrintToChat(client, "[-T-]{red} Invalid Seeds (INTERNAL) report to an Admin");
		return;
	}
	
	char createPlantQuery[512];
	Format(createPlantQuery, sizeof(createPlantQuery), "INSERT INTO `t_rpg_gardener_plants` (`Id`, `playerid`, `plantName`, `plantLevel`, `plantTime`, `plantCreated`, `posX`, `posY`, `posZ`) VALUES (NULL, '%s', '%s', '0', '0', %s, '%.2f', '%.2f', '%.2f');", playerid, plantModel, plantTime, pos[0], pos[1], pos[2]);
	SQL_TQuery(g_DB, SQLErrorCheckCallback, createPlantQuery);
	
	spawnPlant(playerid, 0, 0, pos, plantTime, plantModel);
}

public void loadPlants() {
	char loadPlantsQuery[512];
	Format(loadPlantsQuery, sizeof(loadPlantsQuery), "SELECT plantCreated,plantLevel,plantName,plantTime,playerid,posX,posY,posZ FROM t_rpg_gardener_plants;");
	SQL_TQuery(g_DB, SQLLoadPlantsQuery, loadPlantsQuery);
}

public void SQLLoadPlantsQuery(Handle owner, Handle hndl, const char[] error, any data) {
	if (loaded)
		return;
	while (SQL_FetchRow(hndl)) {
		char plantowner[20];
		SQL_FetchStringByName(hndl, "playerid", plantowner, sizeof(plantowner));
		int state = SQL_FetchIntByName(hndl, "plantLevel");
		int time = SQL_FetchIntByName(hndl, "plantTime");
		char creationTime[64];
		SQL_FetchStringByName(hndl, "plantCreated", creationTime, sizeof(creationTime));
		char plantModel[128];
		SQL_FetchStringByName(hndl, "plantName", plantModel, sizeof(plantModel));
		float pos[3];
		pos[0] = SQL_FetchFloatByName(hndl, "posX");
		pos[1] = SQL_FetchFloatByName(hndl, "posY");
		pos[2] = SQL_FetchFloatByName(hndl, "posZ");
		PrintToChatAll("%s %i %i %.2f %.2f %.2f %i %s", plantowner, state, time, pos[0], pos[1], pos[2], creationTime, plantModel);
		spawnPlant(plantowner, state, time, pos, creationTime, plantModel);
	}
	
	loaded = true;
}

public void spawnPlant(char owner[20], int state, int time, float pos[3], char creationTime[64], char model[128]) {
	int plant = CreateEntityByName("prop_dynamic_override");
	if (plant == -1)
		return;
	SetEntityModel(plant, model);
	DispatchKeyValue(plant, "Solid", "6");
	SetEntProp(plant, Prop_Send, "m_nSolidType", 6);
	SetEntProp(plant, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PUSHAWAY);
	DispatchSpawn(plant);
	TeleportEntity(plant, pos, NULL_VECTOR, NULL_VECTOR);
	Entity_SetGlobalName(plant, "Gardener Plant");
	
	int whereToStore = findLowestUnusedPlantSlot();
	g_ePlayerPlants[whereToStore][pEntRef] = EntIndexToEntRef(plant);
	strcopy(g_ePlayerPlants[whereToStore][pOwner], 20, owner);
	strcopy(g_ePlayerPlants[whereToStore][pCreatedTime], 64, creationTime);
	strcopy(g_ePlayerPlants[whereToStore][pModel], 128, model);
	g_ePlayerPlants[whereToStore][pState] = state;
	g_ePlayerPlants[whereToStore][pTime] = time;
	g_ePlayerPlants[whereToStore][pPos_x] = pos[0];
	g_ePlayerPlants[whereToStore][pPos_y] = pos[1];
	g_ePlayerPlants[whereToStore][pPos_z] = pos[2];
	g_ePlayerPlants[whereToStore][pActive] = true;
	
	if (g_iPlantsActive <= whereToStore)
		g_iPlantsActive = whereToStore + 1;
}

public int findLowestUnusedPlantSlot() {
	for (int i = 0; i < g_iPlantsActive; i++) {
		if (!g_ePlayerPlants[i][pActive])
			return i;
	}
	return g_iPlantsActive;
}

public int findPlantLoadedIdByIndex(int index) {
	for (int i = 0; i < g_iPlantsActive; i++) {
		if (!g_ePlayerPlants[i][pActive])
			continue;
		if (EntRefToEntIndex(g_ePlayerPlants[i][pEntRef]) == index)
			return i;
	}
	return -1;
}

public int getActivePlantsOfPlayerAmount(int client) {
	char playerid[20];
	GetClientAuthId(client, AuthId_Steam2, playerid, sizeof(playerid));
	int amount = 0;
	for (int i = 0; i < MAX_PLANTS; i++) {
		if (g_ePlayerPlants[i][pActive])
			if (StrEqual(g_ePlayerPlants[i][pOwner], playerid))
			amount++;
	}
	return amount;
}

public int getClientFromAuth2(char auth2[20]) {
	for (int i = 1; i < MAXPLAYERS; i++) {
		if (isValidClient(i)) {
			char playerid[20];
			GetClientAuthId(i, AuthId_Steam2, playerid, sizeof(playerid));
			if (StrEqual(auth2, playerid)) {
				return i;
			}
		}
	}
	return -1;
}

public Action refreshTimer(Handle Timer) {
	for (int plant = 0; plant < MAX_PLANTS; plant++) {
		if (g_ePlayerPlants[plant][pActive] && g_ePlayerPlants[plant][pState] < 4) {
			g_ePlayerPlants[plant][pTime] += 1;
			if (g_ePlayerPlants[plant][pTime] >= TIME_TO_NEXT_STAGE) {
				if (g_ePlayerPlants[plant][pState] < 3) {
					g_ePlayerPlants[plant][pState]++;
					g_ePlayerPlants[plant][pTime] = 0;
					evolvePlant(g_ePlayerPlants[plant][pEntRef], g_ePlayerPlants[plant][pState], plant);
				} else if (g_ePlayerPlants[plant][pState] < 4 && g_ePlayerPlants[plant][pTime] >= TIME_TO_NEXT_STAGE * 10) {
					deletePlant(EntRefToEntIndex(g_ePlayerPlants[plant][pEntRef]), plant);
				}
			}
			updatePlant(plant);
		}
	}
	
	for (int i = 1; i < MAXPLAYERS; i++) {
		if (!isValidClient(i))
			continue;
		for (int x = 0; x < MAX_ZONES; x++) {
			if (g_iGardenerZoneCooldown[i][x] > 0)
				g_iGardenerZoneCooldown[i][x]--;
			if (g_iGardenerZoneCooldown[i][x] == 0 && g_iCollectedLoot[i][x] == MAX_COLLECT)
				g_iCollectedLoot[i][x] = 0;
		}
	}
}

public void evolvePlant(int entRef, int state, int plantId) {
	if (state >= 0 && state < 4) {
		int entity = EntRefToEntIndex(entRef);
		if (!IsValidEntity(entity))
			return;
		char modelPath[128];
		strcopy(modelPath, sizeof(modelPath), g_ePlayerPlants[plantId][pModel]);
		char oldState[8];
		IntToString(state - 1, oldState, sizeof(oldState));
		char newState[8];
		IntToString(state, newState, sizeof(newState));
		ReplaceString(modelPath, sizeof(modelPath), oldState, newState);
		SetEntityModel(entity, modelPath);
		strcopy(g_ePlayerPlants[plantId][pModel], 128, modelPath);
	}
}

public void deletePlant(int ent, int plantId) {
	char deletePlantsQuery[512];
	Format(deletePlantsQuery, sizeof(deletePlantsQuery), "DELETE FROM t_rpg_gardener_plants WHERE plantCreated = '%s' AND playerid = '%s';", g_ePlayerPlants[plantId][pCreatedTime], g_ePlayerPlants[plantId][pOwner]);
	SQL_TQuery(g_DB, SQLErrorCheckCallback, deletePlantsQuery);
	
	if (IsValidEntity(ent))
		AcceptEntityInput(ent, "kill");
	
	g_ePlayerPlants[plantId][pEntRef] = -1;
	strcopy(g_ePlayerPlants[plantId][pOwner], 20, "");
	g_ePlayerPlants[plantId][pState] = -1;
	g_ePlayerPlants[plantId][pTime] = -1;
	g_ePlayerPlants[plantId][pPos_x] = 0.0;
	g_ePlayerPlants[plantId][pPos_y] = 0.0;
	g_ePlayerPlants[plantId][pPos_z] = 0.0;
	g_ePlayerPlants[plantId][pActive] = false;
}

public void updatePlant(int plantId) {
	char updatePlantQuery[1024];
	Format(updatePlantQuery, sizeof(updatePlantQuery), "UPDATE t_rpg_gardener_plants SET plantTime = %i, plantLevel = %i, plantName = '%s' WHERE plantCreated = '%s' AND playerid = '%s';", g_ePlayerPlants[plantId][pTime], g_ePlayerPlants[plantId][pState], g_ePlayerPlants[plantId][pModel], g_ePlayerPlants[plantId][pCreatedTime], g_ePlayerPlants[plantId][pOwner]);
	SQL_TQuery(g_DB, SQLErrorCheckCallback, updatePlantQuery);
}

public void onRoundStart(Handle event, const char[] name, bool dontBroadcast) {
	for (int i = 0; i < MAX_PLANTS; i++)
	g_ePlayerPlants[i][pActive] = false;
	g_iPlantsActive = 0;
	loaded = false;
	loadPlants();
}

public Action OnPlayerRunCmd(int client, int &iButtons, int &iImpulse, float fVelocity[3], float fAngles[3], int &iWeapon, int &tickcount) {
	if (IsClientInGame(client) && IsPlayerAlive(client)) {
		if (!(g_iPlayerPrevButtons[client] & IN_USE) && iButtons & IN_USE) {
			int ent = getClientViewObject(client);
			if (IsValidEntity(ent)) {
				if (HasEntProp(ent, Prop_Data, "m_iName") && HasEntProp(ent, Prop_Data, "m_iGlobalname")) {
					char entName[256];
					Entity_GetGlobalName(ent, entName, sizeof(entName));
					if (StrEqual(entName, "Gardener Plant")) {
						if (findPlantLoadedIdByIndex(ent) == -1 || police_isPlayerCuffed(client)) {
							g_iPlayerPrevButtons[client] = iButtons;
							return Plugin_Continue;
						}
						float pos[3];
						GetEntPropVector(ent, Prop_Data, "m_vecOrigin", pos);
						float ppos[3];
						GetClientAbsOrigin(client, ppos);
						if (GetVectorDistance(ppos, pos) < 100.0) {
							if (jobs_isActiveJob(client, "Gardener")) {
								jobs_startProgressBar(client, 60, "Harvest Plant");
								g_iHarvestIndex[client] = ent;
							} else {
								CPrintToChat(client, "{red}You have to be a Gardener to harvest this Plant");
								g_iPlayerPrevButtons[client] = iButtons;
								return Plugin_Continue;
							}
						} else {
							CPrintToChat(client, "{red}This Plant is too far away (%.2f/100.0)", GetVectorDistance(ppos, pos));
							g_iPlayerPrevButtons[client] = iButtons;
							return Plugin_Continue;
						}
					}
				}
			} else if (g_bPlayerInGardenerZone[client]) {
				if (g_iCollectedLoot[client][g_iPlayerZoneId[client]] >= MAX_COLLECT || g_iGardenerZoneCooldown[client][g_iPlayerZoneId[client]] > 0) {
					CPrintToChat(client, "{red}Gardening in this area is on cooldown");
					g_iPlayerPrevButtons[client] = iButtons;
					setInfo(client);
					return Plugin_Continue;
				}
				if (!jobs_isActiveJob(client, "Gardener"))
					return Plugin_Continue;
				char infoString[64];
				Format(infoString, sizeof(infoString), "Gardening (%i)", jobs_getLevel(client));
				
				if (perks_hasPerk(client, "Gardener Speed Boost4"))
					jobs_startProgressBar(client, 10, infoString);
				else if (perks_hasPerk(client, "Gardener Speed Boost3"))
					jobs_startProgressBar(client, 15, infoString);
				else if (perks_hasPerk(client, "Gardener Speed Boost2"))
					jobs_startProgressBar(client, 20, infoString);
				else if (perks_hasPerk(client, "Gardener Speed Boost1"))
					jobs_startProgressBar(client, 25, infoString);
				else
					jobs_startProgressBar(client, 30, infoString);
				setInfo(client);
			}
		}
		g_iPlayerPrevButtons[client] = iButtons;
	}
	return Plugin_Continue;
}

public void jobs_OnProgressBarFinished(int client, char info[64]) {
	if (!jobs_isActiveJob(client, "Gardener"))
		return;
	
	if (StrContains(info, "Harvest Plant") != -1) {
		int plantId;
		if ((plantId = findPlantLoadedIdByIndex(g_iHarvestIndex[client])) == -1)
			return;
		harvestPlant(client, g_iHarvestIndex[client], plantId, g_ePlayerPlants[plantId][pState]);
		
	} else if (StrContains(info, "Gardening", false) != -1) {
		if (g_iPlayerZoneId[client] == -1)
			return;
		
		if (++g_iCollectedLoot[client][g_iPlayerZoneId[client]] >= MAX_COLLECT)
			g_iGardenerZoneCooldown[client][g_iPlayerZoneId[client]] = g_iZoneCooldown + GetRandomInt(0, 50);
		char addCurrencyReason[256];
		Format(addCurrencyReason, sizeof(addCurrencyReason), "Gardening (Level %i)", jobs_getLevel(client));
		tConomy_addBankCurrency(client, 55 + jobs_getLevel(client) * 5, "Gardening");
		if (perks_hasPerk(client, "Gardener XP Boost4"))
			jobs_addExperience(client, 45, "Gardener");
		else if (perks_hasPerk(client, "Gardener XP Boost3"))
			jobs_addExperience(client, 40, "Gardener");
		else if (perks_hasPerk(client, "Gardener XP Boost2"))
			jobs_addExperience(client, 35, "Gardener");
		else if (perks_hasPerk(client, "Gardener XP Boost1"))
			jobs_addExperience(client, 30, "Gardener");
		else
			jobs_addExperience(client, 25, "Gardener");
		setInfo(client);
	}
}

public void harvestPlant(int client, int ent, int plantId, int state) {
	jobs_addExperience(client, state * 150, "Gardener");
	
	char resultItem[128];
	
	if (StrContains(g_ePlayerPlants[plantId][pModel], "eggplant") != -1) {
		strcopy(resultItem, sizeof(resultItem), "Eggplant");
	} else if (StrContains(g_ePlayerPlants[plantId][pModel], "strawberry") != -1) {
		strcopy(resultItem, sizeof(resultItem), "Strawberry");
	} else if (StrContains(g_ePlayerPlants[plantId][pModel], "pumpkin") != -1) {
		strcopy(resultItem, sizeof(resultItem), "Pumpkin");
	}
	
	if (state == 1) {
		for (int i = 0; i < 1; i++) {
			inventory_givePlayerItem(client, resultItem, 2, "", "Plant", "Gardener Item", 2, "Harvested Plant");
		}
	} else if (state == 2) {
		for (int i = 0; i < 2; i++) {
			inventory_givePlayerItem(client, resultItem, 2, "", "Plant", "Gardener Item", 2, "Harvested Plant");
		}
	} else if (state == 3) {
		for (int i = 0; i < 5; i++) {
			inventory_givePlayerItem(client, resultItem, 2, "", "Plant", "Gardener Item", 2, "Harvested Plant");
		}
	}
	
	deletePlant(ent, plantId);
}

public void OnClientAuthorized(int client) {
	g_bPlayerInGardenerZone[client] = false;
	g_iPlayerZoneId[client] = -1;
	for (int zones = 0; zones < MAX_ZONES; zones++) {
		g_iGardenerZoneCooldown[client][zones] = g_iZoneCooldown;
		g_iCollectedLoot[client][zones] = 0;
	}
}

public void OnClientDisconnect(int client) {
	g_bPlayerInGardenerZone[client] = false;
	g_iPlayerZoneId[client] = -1;
	for (int zones = 0; zones < MAX_ZONES; zones++) {
		g_iGardenerZoneCooldown[client][zones] = 0;
		g_iCollectedLoot[client][zones] = 0;
	}
}

public int Zone_OnClientEntry(int client, char[] zone) {
	strcopy(activeZone[client], sizeof(activeZone), zone);
	if (StrContains(zone, "garden") != -1) {
		addZone(zone);
		g_bPlayerInGardenerZone[client] = true;
		g_iPlayerZoneId[client] = getZoneId(zone);
	} else {
		g_bPlayerInGardenerZone[client] = false;
		g_iPlayerZoneId[client] = -1;
	}
	setInfo(client);
}

public int Zone_OnClientLeave(int client, char[] zone) {
	float pos[3];
	GetClientAbsOrigin(client, pos);
	if (Zone_isPositionInZone(activeZone[client], pos[0], pos[1], pos[2]))
		return;
	if (StrContains(zone, "garden", false) != -1) {
		g_bPlayerInGardenerZone[client] = false;
		g_iPlayerZoneId[client] = -1;
	}
	eraseInfo(client);
}

public void OnNpcInteract(int client, char npcType[64], char UniqueId[128], int entIndex) {
	if (!StrEqual(npcType, npctype))
		return;
	char activeJob[128];
	jobs_getActiveJob(client, activeJob);
	Menu menu = CreateMenu(JobPanelHandler);
	if (StrEqual(activeJob, "") || !jobs_isActiveJob(client, "Gardener")) {
		SetMenuTitle(menu, "You already have a job! Want to quit it and becoma a Gardener?");
		AddMenuItem(menu, "x", "No");
		AddMenuItem(menu, "x", "Not now.");
		AddMenuItem(menu, "givejob", "Yes");
	} else if (jobs_isActiveJob(client, "Gardener")) {
		SetMenuTitle(menu, "Welcome Gardener!");
		AddMenuItem(menu, "x", "Are you having a nice day?", ITEMDRAW_DISABLED);
		AddMenuItem(menu, "skin1", "First Gardener Skin [2](500$)", tConomy_getCurrency(client) >= 500 && jobs_getLevel(client) >= 2 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		
		if (tConomy_getCurrency(client) >= 75 && jobs_isActiveJob(client, "Gardener") && jobs_getLevel(client) >= 3)
			AddMenuItem(menu, "EggplantSeeds", "Buy a Eggplant Seed (75$)[3]");
		else
			AddMenuItem(menu, "x", "Buy a Eggplant Seed (75$)[3]", ITEMDRAW_DISABLED);
		
		if (tConomy_getCurrency(client) >= 125 && jobs_isActiveJob(client, "Gardener") && jobs_getLevel(client) >= 5)
			AddMenuItem(menu, "StawberrySeeds", "Buy a Stawberry Seed (125$)[5]");
		else
			AddMenuItem(menu, "x", "Buy a Stawberry Seed (125$)[5]", ITEMDRAW_DISABLED);
		
		if (tConomy_getCurrency(client) >= 200 && jobs_isActiveJob(client, "Gardener") && jobs_getLevel(client) >= 11)
			AddMenuItem(menu, "PumpkinSeeds", "Buy a Pumpkin Seed (200$)[11]");
		else
			AddMenuItem(menu, "x", "Buy a Pumpkin Seed (200$)[11]", ITEMDRAW_DISABLED);
		
		if (inventory_hasPlayerItem(client, "Eggplant"))
			AddMenuItem(menu, "sellEggplant", "Sell Eggplant");
		
		if (inventory_getPlayerItemAmount(client, "Eggplant") > 1) {
			char sellAll[256];
			int itemamount = inventory_getPlayerItemAmount(client, "Eggplant");
			Format(sellAll, sizeof(sellAll), "Sell %i Eggplant%s", itemamount, itemamount > 2 ? "s":"");
			AddMenuItem(menu, "SellEggplants", sellAll);
		}
		
		if (inventory_hasPlayerItem(client, "Strawberry"))
			AddMenuItem(menu, "sellStrawberry", "Sell Strawberry");
		
		if (inventory_getPlayerItemAmount(client, "Strawberry") > 1) {
			char sellAll[256];
			int itemamount = inventory_getPlayerItemAmount(client, "Strawberry");
			Format(sellAll, sizeof(sellAll), "Sell %i Strawberry%s", itemamount, itemamount > 2 ? "s":"");
			AddMenuItem(menu, "SellStrawberrys", sellAll);
		}
		
		if (inventory_hasPlayerItem(client, "Pumpkin"))
			AddMenuItem(menu, "sellPumpkin", "Sell Pumpkin");
		
		if (inventory_getPlayerItemAmount(client, "Pumpkin") > 1) {
			char sellAll[256];
			int itemamount = inventory_getPlayerItemAmount(client, "Pumpkin");
			Format(sellAll, sizeof(sellAll), "Sell %i Pumpkin%s", itemamount, itemamount > 2 ? "s":"");
			AddMenuItem(menu, "SellPumpkins", sellAll);
		}
	}
	DisplayMenu(menu, client, 60);
}

public int JobPanelHandler(Handle menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		char cValue[32];
		GetMenuItem(menu, item, cValue, sizeof(cValue));
		if (StrEqual(cValue, "givejob")) {
			jobs_giveJob(client, "Gardener");
		} else if (StrEqual(cValue, "skin1")) {
			if (tConomy_getCurrency(client) >= 500 && jobs_getLevel(client) >= 2) {
				tConomy_removeCurrency(client, 500, "Bought Gardener Skin");
				inventory_givePlayerItem(client, "Gardener", 0, "", "Skin", "Skin", 1, "Bought from Gardener Recruiter");
			}
		} else if (StrEqual(cValue, "sellEggplant")) {
			if (inventory_hasPlayerItem(client, "Eggplant")) {
				tConomy_addCurrency(client, 100, "Sold Eggplant to Vendor");
				inventory_removePlayerItems(client, "Eggplant", 1, "Sold to Vendor");
			}
		} else if (StrEqual(cValue, "SellEggplants")) {
			int itemamount = inventory_getPlayerItemAmount(client, "Eggplant");
			if (inventory_removePlayerItems(client, "Eggplant", itemamount, "Sold to Vendor (Mass Sell)"))
				tConomy_addCurrency(client, 100 * itemamount, "Sold Eggplant to Vendor");
		} else if (StrEqual(cValue, "sellStrawberry")) {
			if (inventory_hasPlayerItem(client, "Strawberry")) {
				tConomy_addCurrency(client, 125, "Sold Strawberry to Vendor");
				inventory_removePlayerItems(client, "Strawberry", 1, "Sold to Vendor");
			}
		} else if (StrEqual(cValue, "SellStrawberrys")) {
			int itemamount = inventory_getPlayerItemAmount(client, "Strawberry");
			if (inventory_removePlayerItems(client, "Strawberry", itemamount, "Sold to Vendor (Mass Sell)"))
				tConomy_addCurrency(client, 125 * itemamount, "Sold Strawberry to Vendor");
		} else if (StrEqual(cValue, "sellPumpkin")) {
			if (inventory_hasPlayerItem(client, "Pumpkin")) {
				tConomy_addCurrency(client, 150, "Sold Pumpkin to Vendor");
				inventory_removePlayerItems(client, "Pumpkin", 1, "Sold to Vendor");
			}
		} else if (StrEqual(cValue, "SellPumpkins")) {
			int itemamount = inventory_getPlayerItemAmount(client, "Pumpkin");
			if (inventory_removePlayerItems(client, "Pumpkin", itemamount, "Sold to Vendor (Mass Sell)"))
				tConomy_addCurrency(client, 150 * itemamount, "Sold Pumpkin to Vendor");
		} else if (StrEqual(cValue, "EggplantSeeds")) {
			if (tConomy_getCurrency(client) >= 75) {
				tConomy_removeCurrency(client, 75, "Bought Eggplant Seeds");
				inventory_givePlayerItem(client, "Eggplant Seeds", 1, "", "Plant seeds", "Gardener Item", 1, "Bought from Vendor");
			}
		} else if (StrEqual(cValue, "StawberrySeeds")) {
			if (tConomy_getCurrency(client) >= 125) {
				tConomy_removeCurrency(client, 125, "Bought Eggplant Seeds");
				inventory_givePlayerItem(client, "Strawberry Seeds", 1, "", "Plant seeds", "Gardener Item", 1, "Bought from Vendor");
			}
		} else if (StrEqual(cValue, "PumpkinSeeds")) {
			if (tConomy_getCurrency(client) >= 200) {
				tConomy_removeCurrency(client, 200, "Bought Pumpkin Seeds");
				inventory_givePlayerItem(client, "Pumpkin Seeds", 1, "", "Plant seeds", "Gardener Item", 1, "Bought from Vendor");
			}
		}
	}
	if (action == MenuAction_End) {
		delete menu;
	}
}

public void addZone(char[] zone) {
	if (StrContains(zone, "garden", false) != -1) {
		for (int i = 0; i < g_iLoadedZones; i++) {
			if (StrEqual(g_cGardenerZones[i], zone))
				return;
		}
		strcopy(g_cGardenerZones[g_iLoadedZones], PLATFORM_MAX_PATH, zone);
		g_iLoadedZones++;
	}
}

public int getZoneId(char[] zone) {
	for (int i = 0; i < g_iLoadedZones; i++) {
		if (StrEqual(g_cGardenerZones[i], zone))
			return i;
	}
	return -1;
}

public void setInfo(int client) {
	if (!jobs_isActiveJob(client, "Gardener"))
		return;
	if (StrContains(activeZone[client], "garden", false) == -1)
		return;
	char info[128];
	Format(info, sizeof(info), "%s: Gardened %i/%i (%is Cd)", activeZone[client], g_iCollectedLoot[client][g_iPlayerZoneId[client]], MAX_COLLECT, g_iGardenerZoneCooldown[client][g_iPlayerZoneId[client]]);
	jobs_setCurrentInfo(client, info);
}

public void eraseInfo(int client) {
	jobs_setCurrentInfo(client, "");
}

public void SQLErrorCheckCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if (!StrEqual(error, ""))
		LogError(error);
}

public void jobs_OnProgressBarInterrupted(int client, char info[64]) {
	g_iHarvestIndex[client] = -1;
} 
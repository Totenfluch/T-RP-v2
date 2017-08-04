//Pragma
#pragma semicolon 1
#pragma newdecls required

//Defines
#define NPC_NAME "Coinflip_Vendor"
#define NPC_NAME2 "Coinflip_Vendor2"
#define NPC_NAME3 "Coinflip_Vendor3"

//Sourcemod Includes
#include <sourcemod>
#include <sourcemod-misc>
#include <test>
#include <menus-stocks>
#include <csgocolors>

//ConVars
ConVar convar_Database;
ConVar convar_MaxBets;

//Globals
int g_iAnnouncedBet[MAXPLAYERS + 1][3];
bool g_bSelectedCoinSide[MAXPLAYERS + 1][3];
Handle g_hCountdownTimer[MAXPLAYERS + 1][3];

int g_iCreatingGame[MAXPLAYERS + 1][3];
int g_iAmountBet[MAXPLAYERS + 1][3];

bool g_bIsCancelling[MAXPLAYERS + 1][3];

Handle g_hDatabase;

//Stats
int g_iTotalWins[MAXPLAYERS + 1];
int g_iTotalLosses[MAXPLAYERS + 1];
int g_iTotalWon[MAXPLAYERS + 1];
int g_iTotalLost[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "Coinflip Vendor", 
	author = "Keith Warren (Drixevel)", 
	description = "A coinflip vendor.", 
	version = "1.0.0", 
	url = "http://www.drixevel.com/"
};

public void OnPluginStart()
{
	convar_Database = CreateConVar("sm_coinflip_vendor_database_config", "default", "Database config entry to use.");
	convar_MaxBets = CreateConVar("sm_coinflip_vendor_max_bets", "0", "Maximum amount of currency allowed to bet.", FCVAR_NOTIFY, true, 0.0);
}

public void OnConfigsExecuted()
{
	char sDatabase[256];
	GetConVarString(convar_Database, sDatabase, sizeof(sDatabase));
	
	if (g_hDatabase == null && strlen(sDatabase) > 0)
	{
		SQL_TConnect(OnSQLConnect, sDatabase);
	}
}

public void OnSQLConnect(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("Error connecting to database: %s", strlen(error) > 0 ? error : "N/A");
		return;
	}
	
	if (g_hDatabase != null)
	{
		return;
	}
	
	g_hDatabase = hndl;
	LogMessage("Connected to database successfully.");
	
	SQL_TQuery(g_hDatabase, TQuery_Void, "CREATE TABLE IF NOT EXISTS `coinflip_vendor_stats` ( `id` int(12) NOT NULL AUTO_INCREMENT, `steamid` int(12) NOT NULL DEFAULT 0, `name` varchar(64) NOT NULL DEFAULT '', `wins` int(12) NOT NULL DEFAULT 0, `losses` int(12) NOT NULL DEFAULT 0, `total_won` int(12) NOT NULL DEFAULT 0, `total_lost` int(12) NOT NULL DEFAULT 0, `first_created` int(32) NOT NULL, `last_updated` int(32) NOT NULL, PRIMARY KEY (`id`), UNIQUE KEY `id` (`id`), UNIQUE KEY `steamid` (`steamid`)) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci;");
}

public void OnMapStart()
{
	npc_registerNpcType(NPC_NAME);
	npc_registerNpcType(NPC_NAME2);
	npc_registerNpcType(NPC_NAME3);
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}
	
	if (g_hDatabase == null)
	{
		return;
	}
	
	char sQuery[2048];
	FormatEx(sQuery, sizeof(sQuery), "SELECT wins, losses, total_won, total_lost FROM `coinflip_vendor_stats` WHERE steamid = '%i';", GetSteamAccountID(client));
	SQL_TQuery(g_hDatabase, TQuery_OnParseStats, sQuery, GetClientUserId(client));
}

public void TQuery_OnParseStats(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("Error parsing player statistics: %s", strlen(error) > 0 ? error : "N/A");
		return;
	}
	
	int client = GetClientOfUserId(data);
	
	if (client == 0)
	{
		return;
	}
	
	if (SQL_FetchRow(hndl))
	{
		g_iTotalWins[client] = SQL_FetchInt(hndl, 0);
		g_iTotalLosses[client] = SQL_FetchInt(hndl, 1);
		g_iTotalWon[client] = SQL_FetchInt(hndl, 2);
		g_iTotalLost[client] = SQL_FetchInt(hndl, 3);
	}
	
	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	
	int size = 2 * strlen(sName) + 1;
	char[] sNameEscaped = new char[size + 1];
	SQL_EscapeString(g_hDatabase, sName, sNameEscaped, size + 1);
	
	int steamid = GetSteamAccountID(client);
	int time = GetTime();
	
	char sQuery[2048];
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `coinflip_vendor_stats` (steamid, name, wins, losses, total_won, total_lost, first_created, last_updated) VALUES ('%i', '%s', '0', '0', '0', '0', '%i', '%i') ON DUPLICATE KEY UPDATE name = '%s', last_updated = '%i';", steamid, sNameEscaped, time, time, sNameEscaped, time);
	SQL_TQuery(g_hDatabase, TQuery_Void, sQuery);
}

public void OnClientDisconnect(int client)
{
	for (int i = 0; i < 3; i++)
	{
		CancelGame(client, i);
		g_bIsCancelling[client][i] = false;
		
		g_iCreatingGame[client][i] = 0;
		g_iAmountBet[client][i] = 0;
	}
	
	if (g_hDatabase != null)
	{
		char sName[MAX_NAME_LENGTH];
		GetClientName(client, sName, sizeof(sName));
		
		int size = 2 * strlen(sName) + 1;
		char[] sNameEscaped = new char[size + 1];
		SQL_EscapeString(g_hDatabase, sName, sNameEscaped, size + 1);
		
		int steamid = GetSteamAccountID(client);
		int time = GetTime();
		
		char sQuery[2048];
		FormatEx(sQuery, sizeof(sQuery), "UPDATE `coinflip_vendor_stats` SET name = '%s', wins = 'i%', losses = '%i', total_won = '%i', total_lost = '%i', last_updated = '%i' WHERE steamid = '%i';", sNameEscaped, g_iTotalWins[client], g_iTotalLosses[client], g_iTotalWon[client], g_iTotalLost[client], time, steamid);
		SQL_TQuery(g_hDatabase, TQuery_Void, sQuery);
	}
	
	g_iTotalWins[client] = 0;
	g_iTotalLosses[client] = 0;
	g_iTotalWon[client] = 0;
	g_iTotalLost[client] = 0;
}

public void OnNpcInteract(int client, char npcType[64], char UniqueId[128], int entIndex)
{
	if (StrEqual(npcType, NPC_NAME))
	{
		OpenCointossMenu(client, 0);
	}
	else if (StrEqual(npcType, NPC_NAME2))
	{
		OpenCointossMenu(client, 1);
	}
	else if (StrEqual(npcType, NPC_NAME3))
	{
		OpenCointossMenu(client, 2);
	}
}

void OpenCointossMenu(int client, int index)
{
	Menu menu = CreateMenu(MenuHandler_CoinToss);
	
	AddMenuItem(menu, "create", g_iAnnouncedBet[client][index] > 0 ? "Cancel your game" : "Create a game");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && g_iAnnouncedBet[i][index] > 0)
		{
			char sDisplay[128];
			FormatEx(sDisplay, sizeof(sDisplay), "%N:[%i bet on %s]", i, g_iAnnouncedBet[i][index], g_bSelectedCoinSide[i][index] ? "Heads" : "Tails");
			
			char sID[12];
			IntToString(GetClientUserId(i), sID, sizeof(sID));
			
			int draw = ITEMDRAW_DEFAULT;
			
			if (tConomy_getCurrency(client) < g_iAnnouncedBet[i][index] || client == i || g_hCountdownTimer[i][index] != null)
			{
				draw = ITEMDRAW_DISABLED;
			}
			
			AddMenuItem(menu, sID, sDisplay, draw);
		}
	}
	
	if (GetMenuItemCount(menu) == 1)
	{
		AddMenuItem(menu, "", "[No Games Available]", ITEMDRAW_DISABLED);
	}
	
	PushMenuCell(menu, "index", index);
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_CoinToss(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sID[12];
			GetMenuItem(menu, param2, sID, sizeof(sID));
			
			int index = GetMenuCell(menu, "index");
			
			if (StrEqual(sID, "create"))
			{
				if (g_iAnnouncedBet[param1][index] > 0)
				{
					if (g_hCountdownTimer[param1][index] != null)
					{
						g_bIsCancelling[param1][index] = true;
						TriggerTimer(g_hCountdownTimer[param1][index]);
					}
					else
					{
						CancelGame(param1, index);
					}
				}
				else
				{
					CreateGame(param1, index);
				}
				
				return;
			}
			
			int target = GetClientOfUserId(StringToInt(sID));
			
			if (target == -1)
			{
				PrintToChat(param1, "Player who created the toin coss is no longer available.");
				OpenCointossMenu(param1, index);
				return;
			}
			
			if (g_hCountdownTimer[target][index] != null)
			{
				PrintToChat(param1, "You cannot join an already active game with two participants.");
				OpenCointossMenu(param1, index);
				return;
			}
			
			if (g_iAnnouncedBet[target][index] == 0)
			{
				PrintToChat(param1, "The coin toss has been cancelled by %N.", target);
				OpenCointossMenu(param1, index);
				return;
			}
			
			if (tConomy_getCurrency(param1) < g_iAnnouncedBet[target][index])
			{
				PrintToChat(param1, "You do not have enough money.");
				OpenCointossMenu(param1, index);
				return;
			}
			
			ProcessGame(target, param1, index);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void CancelGame(int client, int index)
{
	tConomy_addCurrency(client, g_iAnnouncedBet[client][index], "Cancelled a coin toss");
	
	g_iAnnouncedBet[client][index] = 0;
	g_bSelectedCoinSide[client][index] = true;
	KillTimerSafe(g_hCountdownTimer[client][index]);
}

void CreateGame(int client, int index)
{
	if (tConomy_getCurrency(client) <= 0)
	{
		PrintToChat(client, "You cannot create a game with no money.");
		return;
	}
	
	PrintToChat(client, "Please type into chat the amount you would like to bet:");
	g_iCreatingGame[client][index] = 1;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	for (int i = 0; i < 3; i++)
	{
		if (g_iCreatingGame[client][i] > 0 && StrEqual(sArgs, "cancel"))
		{
			g_iCreatingGame[client][i] = 0;
			g_iAmountBet[client][i] = 0;
			
			continue;
		}
		
		switch (g_iCreatingGame[client][i])
		{
			case 1:
			{
				int amount = StringToInt(sArgs);
				
				int max = GetConVarInt(convar_MaxBets);
				if (amount <= 0 || max > 0 && amount > max)
				{
					if (max > 0)
					{
						PrintToChat(client, "You can only bet an amount between 1 and %i.", max);
					}
					else
					{
						PrintToChat(client, "You can only bet an amount above 0.");
					}
					
					return;
				}
				
				if (tConomy_getCurrency(client) < amount)
				{
					PrintToChat(client, "You cannot bet more than you currently have.");
					return;
				}
				
				g_iAmountBet[client][i] = amount;
				
				PrintToChat(client, "Please type into chat either heads or tails:");
				g_iCreatingGame[client][i] = 2;
			}
			case 2:
			{
				if (StrEqual(sArgs, "heads"))
				{
					g_bSelectedCoinSide[client][i] = true;
					g_iAnnouncedBet[client][i] = g_iAmountBet[client][i];
					
					tConomy_removeCurrency(client, g_iAnnouncedBet[client][i], "Betting on a cointoss");
					
					PrintToChat(client, "Coin toss game has been created.");
					g_iCreatingGame[client][i] = 0;
				}
				else if (StrEqual(sArgs, "tails"))
				{
					g_bSelectedCoinSide[client][i] = false;
					g_iAnnouncedBet[client][i] = g_iAmountBet[client][i];
					
					tConomy_removeCurrency(client, g_iAnnouncedBet[client][i], "Betting on a cointoss");
					
					PrintToChat(client, "Coin toss game has been created.");
					g_iCreatingGame[client][i] = 0;
				}
				else
				{
					PrintToChat(client, "Please type into chat either heads or tails:");
				}
			}
		}
	}
}

void ProcessGame(int client, int opponent, int index)
{
	tConomy_removeCurrency(opponent, g_iAnnouncedBet[client][index], "Betting on a cointoss");
	
	DataPack pack;
	g_hCountdownTimer[client][index] = CreateDataTimer(1.0, Timer_ProcessGame, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, GetClientUserId(opponent));
	WritePackCell(pack, index);
	WritePackCell(pack, 3);
}

public Action Timer_ProcessGame(Handle timer, any data)
{
	ResetPack(data);
	
	int client = GetClientOfUserId(ReadPackCell(data));
	int opponent = GetClientOfUserId(ReadPackCell(data));
	int index = ReadPackCell(data);
	DataPackPos countdown_pos = GetPackPosition(data);
	int countdown = ReadPackCell(data);
	
	if (g_bIsCancelling[client][index])
	{
		CPrintToChat2(client, "%N has cancelled the match.", client);
		CPrintToChat2(opponent, "%N has cancelled the match.", client);
		
		g_bIsCancelling[client][index] = false;
		
		tConomy_addCurrency(opponent, g_iAnnouncedBet[client][index], "Cancelled a coin toss");
		CancelGame(client, index);
		
		g_hCountdownTimer[client][index] = null;
		return Plugin_Stop;
	}
	
	if (opponent == 0)
	{
		CPrintToChat2(client, "Opponent has disconnected.");
		g_hCountdownTimer[client][index] = null;
		return Plugin_Stop;
	}
	
	if (countdown > 0)
	{
		CPrintToChat2(client, "Countdown: %i", countdown);
		CPrintToChat2(opponent, "Countdown: %i", countdown);
		
		countdown--;
		SetPackPosition(data, countdown_pos);
		WritePackCell(data, countdown);
		
		return Plugin_Continue;
	}
	
	int winner; int loser;
	if (g_bSelectedCoinSide[client][index] == view_as<bool>(GetRandomInt(0, 1)))
	{
		winner = client;
		loser = opponent;
	}
	else
	{
		winner = opponent;
		loser = client;
	}
	
	g_iTotalWins[winner]++;
	g_iTotalLosses[loser]++;
	
	g_iTotalWon[winner] += g_iAnnouncedBet[client][index];
	g_iTotalLost[loser] += g_iAnnouncedBet[client][index];
	
	tConomy_addCurrency(winner, g_iAnnouncedBet[client][index] * 2, "Won a coin toss");
	
	CPrintToChat2(winner, "{green}You have won the cointoss of $%i", g_iAnnouncedBet[client][index]);
	CPrintToChat2(loser, "{red}You have lost the cointoss and lost -$%i", g_iAnnouncedBet[client][index]);
	
	g_iAnnouncedBet[client][index] = 0;
	g_bSelectedCoinSide[client][index] = true;
	
	g_hCountdownTimer[client][index] = null;
	return Plugin_Stop;
}

void CPrintToChat2(int client, const char[] format, any ...)
{
	if (client == 0)
	{
		return;
	}
	
	char sBuffer[256];
	VFormat(sBuffer, sizeof(sBuffer), format, 3);
	
	CPrintToChat(client, sBuffer);
}
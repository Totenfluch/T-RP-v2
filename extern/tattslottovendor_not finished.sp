//Pragma
#pragma semicolon 1
#pragma newdecls required

//Defines
#define NPC_NAME "TATTS_LOTTO_VENDOR"
#define MAX_TICKETS 256

//Sourcemod Includes
#include <sourcemod>
#include <sourcemod-misc>
#include <test>

//ConVars
ConVar convar_TicketPrice;
ConVar convar_DrawTime;
ConVar convar_Database;
ConVar convar_Table;

//Globals
Handle g_hDatabase;
Handle g_hDrawTimer;
int g_iGlobalPot;
int g_iTicketsWanted[MAXPLAYERS + 1];

StringMap g_hTrie_Tickets;
StringMap g_hTrie_Names;

public Plugin myinfo = 
{
	name = "Tatts Lotto Vendor", 
	author = "Keith Warren (Drixevel)", 
	description = "A lottery vendor.", 
	version = "1.0.0", 
	url = "http://www.drixevel.com/"
};

public void OnPluginStart()
{
	convar_TicketPrice = CreateConVar("sm_tatts_lotto_ticket_price", "45", "Price per ticket.");
	convar_DrawTime = CreateConVar("sm_tatts_lotto_draw_time", "1800.0", "Time in seconds to draw.");
	convar_Database = CreateConVar("sm_tatts_lotto_database_config_entry", "tattslotto", "Database config entry to use.");
	convar_Table = CreateConVar("sm_tatts_lotto_database_table", "lottowinners", "Database table to use.");
	AutoExecConfig();
	
	HookConVarChange(convar_DrawTime, OnConVarChange_DrawTime);
	
	g_hTrie_Tickets = CreateTrie();
	g_hTrie_Names = CreateTrie();
}

public void OnMapStart()
{
	npc_registerNpcType(NPC_NAME);
}

public void OnConfigsExecuted()
{
	delete g_hDrawTimer;
	g_hDrawTimer = CreateTimer(GetConVarFloat(convar_DrawTime), Timer_ExecuteJackpot, _, TIMER_REPEAT);
	
	if (g_hDatabase == null)
	{
		char sDatabase[256];
		GetConVarString(convar_Database, sDatabase, sizeof(sDatabase));
		
		SQL_TConnect(OnSQLConnect, sDatabase);
	}
}

public void OnConVarChange_DrawTime(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (StrEqual(oldValue, newValue))
	{
		return;
	}
	
	delete g_hDrawTimer;
	g_hDrawTimer = CreateTimer(StringToFloat(newValue), Timer_ExecuteJackpot, _, TIMER_REPEAT);
}

public void OnSQLConnect(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("Error connecting to database: %s", error);
		return;
	}
	
	if (g_hDatabase != null)
	{
		CloseHandle(hndl);
		return;
	}
	
	g_hDatabase = hndl;
	LogMessage("Connected to database successfully.");
	
	char sTable[256];
	GetConVarString(convar_Table, sTable, sizeof(sTable));
	
	SQL_VoidQueryF(g_hDatabase, DBPrio_Normal, "CREATE TABLE IF NOT EXISTS `%s` ( `id` INT NOT NULL AUTO_INCREMENT , `accountid` INT(32) NOT NULL DEFAULT '0' , `name` VARCHAR(64) NOT NULL DEFAULT '' , `bet_amount` INT(12) NOT NULL DEFAULT '0' , `total_won` INT(12) NOT NULL DEFAULT '0' , `reward_received` INT(12) NOT NULL DEFAULT '0' , `first_created` INT(12) NOT NULL DEFAULT '0' , `last_updated` INT(12) NOT NULL DEFAULT '0' , PRIMARY KEY (`id`)) ENGINE = InnoDB;", sTable);
}

public void OnClientPutInServer(int client)
{
	if (g_hDatabase != null)
	{
		char sTable[256];
		GetConVarString(convar_Table, sTable, sizeof(sTable));
		
		SQL_TQueryF(g_hDatabase, OnSQLQuery_CheckForRewards, GetClientUserId(client), DBPrio_Normal, "SELECT total_won FROM `%s` WHERE accountid = '%i' AND reward_received = '0';", sTable, GetSteamAccountID(client));
	}
}

public void OnSQLQuery_CheckForRewards(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("Error checking if client has pending rewards: %s", error);
		return;
	}
	
	int client = GetClientOfUserId(data);
	
	if (client == 0)
	{
		return;
	}
	
	while (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		int reward = SQL_FetchInt(hndl, 0);
		
		tConomy_addCurrency(client, reward, "Won the jackpot while offline");
		PrintToChat(client, "You have won a lottery while offline of '%i', your total currency has been updated.");
	}
	
	char sTable[256];
	GetConVarString(convar_Table, sTable, sizeof(sTable));
	
	SQL_VoidQueryF(g_hDatabase, DBPrio_Normal, "UPDATE `%s` SET reward_received = '1', last_updated = '%i' WHERE accountid = '%i';", sTable, GetTime(), GetSteamAccountID(client));
}

public void OnNpcInteract(int client, char npcType[64], char UniqueId[128], int entIndex)
{
	if (StrEqual(npcType, NPC_NAME))
	{
		OpenLottoMenu(client);
	}
}

void OpenLottoMenu(int client)
{
	Menu menu = CreateMenu(MenuHandler_LottoMenu);
	SetMenuTitle(menu, "The lotto is currently at $%i", g_iGlobalPot * GetConVarInt(convar_TicketPrice));
	
	AddMenuItem(menu, "single", "Would you like to buy a lotto ticket?");
	AddMenuItem(menu, "multiple", "Would you like to buy multiple lotto ticket?");
	AddMenuItem(menu, "stats", "Top 10 biggest pots won.");
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_LottoMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
			
			if (StrEqual(sInfo, "single"))
			{
				OpenLottoConfirmMenu(param1, 1);
			}
			else if (StrEqual(sInfo, "multiple"))
			{
				OpenLottoMultipleTickets(param1);
			}
			else if (StrEqual(sInfo, "stats"))
			{
				ShowTopLottosPanel(param1);
			}
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenLottoConfirmMenu(int client, int amount)
{
	g_iTicketsWanted[client] = amount;
	
	int chance = g_iTicketsWanted[client] / g_iGlobalPot + g_iTicketsWanted[client] * 100;
	
	Menu menu = CreateMenu(MenuHandler_ConfirmMenu);
	SetMenuTitle(menu, "The price is %i per ticket\nAre you sure you want to purchase %i ticket?\nCance of success: %i%", GetConVarInt(convar_TicketPrice), g_iTicketsWanted[client], chance);
	
	AddMenuItem(menu, "yes", "Yes");
	AddMenuItem(menu, "no", "No");
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_ConfirmMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[12];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
			
			if (StrEqual(sInfo, "no"))
			{
				return;
			}
			
			int amount = g_iTicketsWanted[param1];
			int price = GetConVarInt(convar_TicketPrice) * amount;
			
			if (price > tConomy_getCurrency(param1))
			{
				PrintToChat(param1, "You do not have enough credits to purchase %i ticket(s) for the lottery.", amount);
				return;
			}
			
			tConomy_removeCurrency(param1, price, "Purchased a lottery ticket");
			
			char sAccountID[32];
			IntToString(GetSteamAccountID(param1), sAccountID, sizeof(sAccountID));
			
			char sName[MAX_NAME_LENGTH];
			GetClientName(param1, sName, sizeof(sName));
			SetTrieString(g_hTrie_Names, sAccountID, sName);
			
			for (int i = 0; i < amount; i++)
			{
				int tickets[MAX_TICKETS];
				GetTrieArray(g_hTrie_Tickets, sAccountID, tickets, sizeof(tickets));
				
				int temp;
				while (tickets[temp] != 0)
				{
					temp++;
				}
				
				tickets[temp] = g_iGlobalPot;
				g_iGlobalPot++;
				
				SetTrieArray(g_hTrie_Tickets, sAccountID, tickets, sizeof(tickets));
				
				if (amount == 1)
				{
					PrintToChat(param1, "You have purchased the ticket '%i' for %i credits.", g_iGlobalPot - 1, price);
				}
			}
			
			if (amount > 1)
			{
				PrintToChat(param1, "You have purchased %i tickets for %i credits.", amount, price);
			}
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenLottoMultipleTickets(int client)
{
	Menu menu = CreateMenu(MenuHandler_MultiTicketsMenu);
	SetMenuTitle(menu, "The price is %i per ticket\nHow many tickets would you like to purchase?", GetConVarInt(convar_TicketPrice));
	
	AddMenuItem(menu, "2", "2 tickets");
	AddMenuItem(menu, "5", "5 tickets");
	AddMenuItem(menu, "10", "10 tickets");
	AddMenuItem(menu, "25", "25 tickets");
	AddMenuItem(menu, "50", "50 tickets");
	AddMenuItem(menu, "100", "100 tickets");
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_MultiTicketsMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[12];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
			
			OpenLottoConfirmMenu(param1, StringToInt(sInfo));
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void ShowTopLottosPanel(int client)
{
	if (g_hDatabase == null)
	{
		return;
	}
	
	char sTable[256];
	GetConVarString(convar_Table, sTable, sizeof(sTable));
	
	SQL_TQueryF(g_hDatabase, OnSQLQuery_GetTopLottos, GetClientUserId(client), DBPrio_Normal, "SELECT name, total_won FROM `%s` ORDER BY total_won DESC;", sTable);
}

public void OnSQLQuery_GetTopLottos(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		LogError("Error retrieving top lottery winners: %s", error);
		return;
	}
	
	int client = GetClientOfUserId(data);
	
	if (client == 0)
	{
		return;
	}
	
	Panel panel = CreatePanel();
	int count = 1;
	
	while (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		char sName[MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 0, sName, sizeof(sName));
		
		int reward = SQL_FetchInt(hndl, 1);
		
		char sDisplay[128];
		FormatEx(sDisplay, sizeof(sDisplay), "[%i] %s - %i", count, sName, reward);
		
		DrawPanelText(panel, sDisplay);
		count++;
	}
	
	SendPanelToClient(panel, client, PanelHandler_GetTopLottos, MENU_TIME_FOREVER);
	CloseHandle(panel);
}

public int PanelHandler_GetTopLottos(Menu menu, MenuAction action, int param1, int param2)
{
	OpenLottoMenu(param1);
}

public Action Timer_ExecuteJackpot(Handle timer)
{
	if (g_iGlobalPot <= 0)
	{
		PrintToChatAll("No pending tickets for the lottery, no winners chosen.");
		return Plugin_Continue;
	}
	
	int winner = GetRandomInt(0, g_iGlobalPot - 1);
	char sWinnerID[32];
	
	Handle snapshot = CreateTrieSnapshot(g_hTrie_Tickets);
	
	for (int i = 0; i < TrieSnapshotLength(snapshot); i++)
	{
		int size = TrieSnapshotKeyBufferSize(snapshot, i);
		
		char[] sAccountID = new char[size + 1];
		GetTrieSnapshotKey(snapshot, i, sAccountID, size + 1);
		
		int tickets[MAX_TICKETS];
		GetTrieArray(g_hTrie_Tickets, sAccountID, tickets, sizeof(tickets));
		
		int temp;
		while (tickets[temp] != 0)
		{
			if (tickets[temp] == winner)
			{
				strcopy(sWinnerID, sizeof(sWinnerID), sAccountID);
				break;
			}
			
			temp++;
		}
	}
	
	CloseHandle(snapshot);
	ClearTrie(g_hTrie_Tickets);
	
	if (strlen(sWinnerID) == 0)
	{
		PrintToChatAll("The winner for the lottery was not found.");
		return Plugin_Continue;
	}
	
	char sName[MAX_NAME_LENGTH];
	GetTrieString(g_hTrie_Names, sWinnerID, sName, sizeof(sName));
	
	int accountid = StringToInt(sWinnerID);
	int winner_index = FindClientByAccountID(accountid);
	
	int winning_pot = g_iGlobalPot * GetConVarInt(convar_TicketPrice);
	
	if (winner_index != -1)
	{
		GetClientName(winner_index, sName, sizeof(sName));
		tConomy_addCurrency(winner_index, winning_pot, "Won the jackpot");
		PrintToChatAll("%s has won the pot of %i dollars! Thanks for playing.", sName, winning_pot);
	}
	else
	{
		PrintToChatAll("%s has won the pot of %i dollars while offline! Thanks for playing.", sName, winning_pot);
	}
	
	char sTable[256];
	GetConVarString(convar_Table, sTable, sizeof(sTable));
	
	int size = 2 * MAX_NAME_LENGTH + 1;
	char[] sEscapedName = new char[size + 1];
	SQL_EscapeString(g_hDatabase, sName, sEscapedName, size + 1);
	
	int time = GetTime();
	
	SQL_VoidQueryF(g_hDatabase, DBPrio_Normal, "INSERT INTO `%s` (accountid, name, bet_amount, total_won, reward_received, first_created, last_updated) VALUES ('%i', '%s', '%i', '%i', '%i', '%i', '%i');", sTable, accountid, sEscapedName, GetConVarInt(convar_TicketPrice), winning_pot, winner_index != -1 ? 0 : 1, time, time);
	
	g_iGlobalPot = 0;
	ClearTrie(g_hTrie_Names);
	
	return Plugin_Continue;
}

int FindClientByAccountID(int accountid)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetSteamAccountID(i) == accountid)
		{
			return i;
		}
	}
	
	return -1;
}
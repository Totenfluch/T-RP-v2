#pragma semicolon 1

#define PLUGIN_AUTHOR "Totenfluch"
#define PLUGIN_VERSION "1.00"

#include <sourcemod>
#include <sdktools>
#include <chat-processor>
#include <tStocks>
#include <cstrike>
#include <sdkhooks>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "[T-RP] Chatcontroller", 
	author = PLUGIN_AUTHOR, 
	description = "Control the Chat for T-RP", 
	version = PLUGIN_VERSION, 
	url = "https://totenfluch.de"
};

public void OnPluginStart() {  }

public Action CP_OnChatMessage(int & author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool & processcolors, bool & removecolors) {
	if (StrContains(message, ".") == 0) {
		Format(name, MAX_NAME_LENGTH, "[GLOBAL] %s", name);
		return Plugin_Changed;
	}
	
	PrintToConsole(author, "------------------------------------------");
	PrintToConsole(author, "You are %N", author);
	for (int i = 0; i < GetArraySize(recipients); i++)
		PrintToConsole(author, "Recieved from: %N", GetArrayCell(recipients, i));
	PrintToConsole(author, "Name: %s", name);
	PrintToConsole(author, "Message: %s", message);
	PrintToConsole(author, "Size: %i", GetArraySize(recipients));
	PrintToConsole(author, "------------------------------------------");
	
	if (isValidClient(author)) {
		for (int i = 0; i < GetArraySize(recipients); i++) {
			int reciever = GetArrayCell(recipients, i);
			PrintToConsole(author, "it: %i | Size: %i | %N", i, GetArraySize(recipients), reciever);
			if (!isValidClient(reciever)){
				RemoveFromArray(recipients, i);
				i = -1;
			}
			if (author == reciever)
				continue;
			
			float pos[3];
			float opos[3];
			GetClientAbsOrigin(author, pos);
			GetClientAbsOrigin(reciever, opos);
			PrintToConsole(author, "%.2f %N %N", GetVectorDistance(pos, opos), author, reciever);
			if (GetVectorDistance(pos, opos) > 350.0 || !IsPlayerAlive(reciever)) {
				PrintToConsole(author, "Removed: %N", GetArrayCell(recipients, i));
				RemoveFromArray(recipients, i);
				i = -1;
			}
		}
		char recieverstring[128];
		int maxnames = 3;
		int names = 0;
		for (int i = 0; i < GetArraySize(recipients) && names < maxnames; i++) {
			int reciever = GetArrayCell(recipients, i);
			if (!IsPlayerAlive(reciever))
				continue;
			if (author == reciever)
				continue;
			if (names > 0 && i != GetArraySize(recipients))
				Format(recieverstring, sizeof(recieverstring), "%s, %N", recieverstring, reciever);
			else
				Format(recieverstring, sizeof(recieverstring), "%s %N", recieverstring, reciever);
			names++;
		}
		if (names == maxnames)
			Format(recieverstring, sizeof(recieverstring), "%s...", recieverstring);
		if (names != 0)
			Format(name, 192, "[%s to %s]", name, recieverstring);
	}
	return Plugin_Changed;
}

public void CP_OnChatMessagePost(int author, ArrayList recipients, const char[] flagstring, const char[] formatstring, const char[] name, const char[] message, bool processcolors, bool removecolors) {
	/*PrintToConsole(author, "++++++++++++++++++++++++++++++++++++++++");
	PrintToConsole(author, "You are %N", author);
	for (int i = 0; i < GetArraySize(recipients); i++)
	PrintToConsole(author, "Recieved from: %N", GetArrayCell(recipients, i));
	PrintToConsole(author, "Name: %s", name);
	PrintToConsole(author, "Message: %s", message);
	PrintToConsole(author, "++++++++++++++++++++++++++++++++++++++++");*/
	
	if (GetArraySize(recipients) == 1)
		PrintToChat(author, "[-T-] No one can hear you. Start Your Message with '.' to make a Global message!");
}

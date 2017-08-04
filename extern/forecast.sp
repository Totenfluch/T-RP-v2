#include <sdktools>
#include <sdkhooks>
#include <sourcemod>

ConVar g_Cvar_SkyName;

Handle g_Timer_Forecast;

char g_cSkyBox[128];
char g_cLight[64];
char g_cWeather[64];
char g_cWeatherModel[128];

char g_cTime[64];
char g_cTimeEx[64];
char g_cTimeX[64];
int g_iTime;
int g_iTimeEx;

float g_fM_vecOrigin[3];
float g_fMaxbounds[3];
float g_fMinbounds[3];

bool g_bDefault;

#define PLUGIN_VERSION          "1.0.0"
#define PLUGIN_NAME             "[CS:GO] Forecast"
#define PLUGIN_AUTHOR           "Maxximou5"
#define PLUGIN_DESCRIPTION      "Determines the forecast for the map."
#define PLUGIN_URL              "http://maxximou5.com/"

public Plugin myinfo =
{
    name                        = PLUGIN_NAME,
    author                      = PLUGIN_AUTHOR,
    description                 = PLUGIN_DESCRIPTION,
    version                     = PLUGIN_VERSION,
    url                         = PLUGIN_URL
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    RegConsoleCmd("sm_time", Command_Time, "What time is it?");
    RegConsoleCmd("sm_tm", Command_TPMenu, "Forecast Menu.");

    g_Cvar_SkyName = FindConVar("sv_skyname");

    HookEvent("player_death", Event_PlayerSpawn, EventHookMode_Post);

    GetDimensions();

    SetConditions();

    g_Timer_Forecast = CreateTimer(10.0, Timer_Forecast, _, TIMER_REPEAT);

    if (GetEngineVersion() != Engine_CSGO)
    {
        SetFailState("ERROR: This plugin is designed only for CS:GO.");
    }
}

public void OnClientPutInServer(int client) 
{
    if (IsValidClient(client))
        SetForecast(g_cSkyBox, g_cWeather, g_cLight);
}

/*
7.00am - Sunlight
11.00am - rain/lightning
8.00pm - Nighttime
8.30pm - Nighttime/fog/rain/lightning
9.30pm - Nightime
11.00pm - Nightime/fog
*/

public void OnMapStart()
{
    GetDimensions();
    RemoveWeather()
    SetConditions();

    if (g_Timer_Forecast == null)
    {
        g_Timer_Forecast = CreateTimer(10.0, Timer_Forecast, _, TIMER_REPEAT);
    }
}

public void OnMapEnd()
{
    if (g_Timer_Forecast != null)
    {
        KillTimer(g_Timer_Forecast);
    }
}

public Action Timer_Forecast(Handle timer)
{
    FormatTime(g_cTimeEx, sizeof(g_cTimeEx), "%H");
    StringToInt(g_cTimeEx, g_iTimeEx);
    if (g_iTime != g_iTimeEx)
        SetConditions();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    GetDimensions();
    RemoveWeather()
    SetConditions();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client))
        SetSkyBox(client, g_cSkyBox);
}

public Action Command_Time(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    FormatTime(g_cTimeX, sizeof(g_cTimeX), NULL_STRING);
    PrintHintText(client, "<font face=''>\n<font color='#75D1FF'>TIME:</font> %s\n", g_cTimeX);
    PrintToChat(client, "%s", g_cTimeX);

    return Plugin_Handled;
}

public Action Command_TPMenu(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    TPMenu(client);

    return Plugin_Handled;
}

public Action TPMenu(int client)
{
    Menu menu = new Menu(TPMenuHandler);
    menu.AddItem("option0", "7AM");
    menu.AddItem("option1", "11AM");
    menu.AddItem("option2", "8PM");
    menu.AddItem("option3", "9PM");
    menu.AddItem("option4", "10PM");
    menu.AddItem("option5", "11PM");
    menu.ExitBackButton = true;
    menu.Display(client, 30);
    return Plugin_Handled;
}

public TPMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            switch (param2)
            {
                case 0: SetForecast("sky_cs15_daylight02_hdr", "-1", "a");
                case 1: SetForecast("sky_csgo_cloudy01", "0", "c");
                case 2: SetForecast("sky_csgo_night02b", "1", "f");
                case 3: SetForecast("sky_csgo_night02b", "2", "w");
                case 4: SetForecast("sky_csgo_night02b", "3", "x");
                case 5: SetForecast("sky_csgo_night02b", "4", "z");
            }
        }
        case MenuAction_Cancel:
        {
            delete menu;
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
}

public Action Hook_SetTransmitLight(int entity, int client) 
{ 
    if (GetEntProp(entity, Prop_Data, "m_iHammerID") == client) 
    { 
        return Plugin_Continue; 
    } 
    return Plugin_Handled; 
}

public void LoadForecast()
{
    FormatTime(g_cTime, sizeof(g_cTime), "%H");
    StringToInt(g_cTime, g_iTime);

    Handle kv = CreateKeyValues("forecast");
    static char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/forecast.txt");

    if (!FileToKeyValues(kv, path))
    {
        SetFailState("[ERROR] File configs/forecast.txt was not found!");
    }

    FileToKeyValues(kv, path);

    KvJumpToKey(kv, g_cTime);

    char cDefault[24];
    KvGetString(kv, "default", cDefault, sizeof(cDefault), "no");

    if (StrContains(cDefault, "no") == -1)
    {
        g_bDefault = true;
    }
    else
    {
        g_bDefault = false;
        KvGetString(kv, "light", g_cLight, sizeof(g_cLight));
        KvGetString(kv, "skybox", g_cSkyBox, sizeof(g_cSkyBox));
        KvGetString(kv, "weather", g_cWeather, sizeof(g_cWeather));
    }

    char custom_skybox[24];
    KvGetString(kv, "custom", custom_skybox, sizeof(custom_skybox), "no");

    if (StrContains(custom_skybox, "no") == -1)
    {
        char skybox_vtf[128];
        Format(skybox_vtf, sizeof(skybox_vtf), "materials/skybox/%s.vtf", g_cSkyBox);
        AddFileToDownloadsTable(skybox_vtf);

        char skybox_vmt[128];
        Format(skybox_vmt, sizeof(skybox_vmt), "materials/skybox/%s.vmt", g_cSkyBox);
        AddFileToDownloadsTable(skybox_vmt);
    }

    SetForecast(g_cSkyBox, g_cWeather, g_cLight);

    KvGoBack(kv);
    
    CloseHandle(kv);
}

void GetDimensions()
{
    char map[64];
    GetCurrentMap(map, 64);
    Format(g_cWeatherModel, sizeof(g_cWeatherModel), "maps/%s.bsp", map);
    PrecacheModel(g_cWeatherModel, true);
    
    GetEntPropVector(0, Prop_Data, "m_WorldMins", g_fMinbounds);
    GetEntPropVector(0, Prop_Data, "m_WorldMaxs", g_fMaxbounds);
    
    while (TR_PointOutsideWorld(g_fMinbounds)) 
    {
        g_fMinbounds[0]++;
        g_fMinbounds[1]++;
        g_fMinbounds[2]++;
    }

    while (TR_PointOutsideWorld(g_fMaxbounds)) 
    {
        g_fMaxbounds[0]--;
        g_fMaxbounds[1]--;
        g_fMaxbounds[2]--;
    }

    g_fM_vecOrigin[0] = (g_fMinbounds[0] + g_fMaxbounds[0]) / 2;
    g_fM_vecOrigin[1] = (g_fMinbounds[1] + g_fMaxbounds[1]) / 2;
    g_fM_vecOrigin[2] = (g_fMinbounds[2] + g_fMaxbounds[2]) / 2;
}

void SetConditions()
{
    LoadForecast();
}

void SetForecast(char[] skybox, char[] weather, char[] light)
{
    strcopy(g_cWeather, sizeof(g_cWeather), weather);
    SetWeather(weather);

    strcopy(g_cSkyBox, sizeof(g_cSkyBox), skybox);
    for (int client = 1; client < MaxClients; client++)
    {
        if (!IsValidClient(client))
            continue;

        if (g_bDefault)
            continue;

        SetSkyBox(client, skybox);
    }

    strcopy(g_cLight, sizeof(g_cLight), light);
    ChangeLightStyle(light);
}

void SetSkyBox(int client, char[] skybox)
{
    SendConVarValue(client, g_Cvar_SkyName, skybox);
}

void SetWeather(char[] weather)
{
    RemoveWeather();
    
    int ent = CreateEntityByName("func_precipitation");
    DispatchKeyValue(ent, "model", g_cWeatherModel);
    DispatchKeyValue(ent, "preciptype", weather);
    DispatchKeyValue(ent, "renderamt", "5");
    DispatchKeyValue(ent, "density", "75");
    DispatchKeyValue(ent, "rendercolor", "255 255 255");
    DispatchSpawn(ent);
    ActivateEntity(ent);
    
    SetEntPropVector(ent, Prop_Send, "m_vecMins", g_fMinbounds);
    SetEntPropVector(ent, Prop_Send, "m_vecMaxs", g_fMaxbounds);    
    
    TeleportEntity(ent, g_fM_vecOrigin, NULL_VECTOR, NULL_VECTOR);
}

void RemoveWeather()
{
    int index = -1;
    while ((index = FindEntityByClassname2(index, "func_precipitation")) != -1)
        AcceptEntityInput(index, "Kill");
}

void ChangeLightStyle(char[] light) 
{
    SetLightStyle(0, light);
}

FindEntityByClassname2(int startEnt, char[] classname)
{
    while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;

    return FindEntityByClassname(startEnt, classname);
}

bool IsValidClient(int client)
{
    if (!(0 < client <= MaxClients)) return false;
    if (!IsClientInGame(client)) return false;
    if (IsFakeClient(client)) return false;
    return true;
}

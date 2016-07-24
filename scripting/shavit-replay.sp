/*
 * shavit's Timer - Replay Bot
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#define USES_STYLE_NAMES
#define USES_SHORT_STYLE_NAMES
#define USES_STYLE_PROPERTIES
#include <shavit>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

// game type
ServerGame gSG_Type = Game_Unknown;

// cache
int gI_ReplayTick[MAX_STYLES];
int gI_ReplayBotClient[MAX_STYLES];
ArrayList gA_Frames[MAX_STYLES] = {null, ...};
char gS_BotName[MAX_STYLES][MAX_NAME_LENGTH];
float gF_StartTick[MAX_STYLES];
ReplayStatus gRS_ReplayStatus[MAX_STYLES];
int gI_FrameCount[MAX_STYLES];

int gI_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
bool gB_Record[MAXPLAYERS+1];

// server specific
float gF_Tickrate = 0.0;
char gS_Map[256];
ConVar bot_quota = null;
int gI_ExpectedBots = 0;

// Plugin ConVars
ConVar gCV_ReplayDelay = null;

public Plugin myinfo =
{
	name = "[shavit] Replay Bot",
	author = "shavit, ofir",
	description = "A replay bot for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetReplayBotFirstFrame", Native_GetReplayBotFirstFrame);
	CreateNative("Shavit_GetReplayBotIndex", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetReplayBotCurrentFrame", Native_GetReplayBotIndex);
	CreateNative("Shavit_IsReplayDataLoaded", Native_IsReplayDataLoaded);

	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");
	MarkNativeAsOptional("Shavit_GetReplayBotCurrentFrame");
	MarkNativeAsOptional("Shavit_IsReplayDataLoaded");

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-replay");

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	gSG_Type = Shavit_GetGameType();
}

public void OnPluginStart()
{
	bot_quota = FindConVar("bot_quota");

	CreateTimer(1.0, Cron, INVALID_HANDLE, TIMER_REPEAT);

	for(int i = 1; i <= MaxClients; i++)
	{
		OnClientPutInServer(i);
	}

	gF_Tickrate = (1.0 / GetTickInterval());

	// plugin convars
	gCV_ReplayDelay = CreateConVar("shavit_replay_delay", "5.0", "Time to wait before restarting the replay after it finishes playing.", 0, true, 0.0, true, 10.0);

	AutoExecConfig();

	// hooks
	HookEvent("player_spawn", Player_Event);
	HookEvent("player_death", Player_Event);

	// commands
	RegAdminCmd("sm_deletereplay", Command_DeleteReplay, ADMFLAG_RCON, "Open replay deletion menu.");
}

public int Native_GetReplayBotFirstFrame(Handle handler, int numParams)
{
	SetNativeCellRef(2, gF_StartTick[GetNativeCell(1)]);
}

public int Native_GetReplayBotCurrentFrame(Handle handler, int numParams)
{
	return gI_ReplayTick[GetNativeCell(1)];
}

public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	return gI_ReplayBotClient[GetNativeCell(1)];
}

public int Native_IsReplayDataLoaded(Handle handler, int numParams)
{
	BhopStyle style = view_as<BhopStyle>(GetNativeCell(1));

	return view_as<int>(ReplayEnabled(style) && gI_FrameCount[style] > 0);
}

public Action Cron(Handle Timer)
{
	// make sure there are e nough bots
	if(bot_quota.IntValue != gI_ExpectedBots)
	{
		bot_quota.SetInt(gI_ExpectedBots);
	}

	// resets a bot's client index if there are two on the same one.
	for(int a = 0; a < MAX_STYLES; a++)
	{
		for(int b = 0; b < MAX_STYLES; b++)
		{
			if(gI_ReplayBotClient[a] == gI_ReplayBotClient[b])
			{
				gI_ReplayBotClient[a] = 0;
				gI_ReplayBotClient[b] = 0;
			}
		}
	}

	// make sure replay bot client indexes are fine
	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		if(!IsValidClient(gI_ReplayBotClient[i]))
		{
			for(int j = 1; j <= MaxClients; j++)
			{
				if(!IsClientConnected(j) || !IsFakeClient(j))
				{
					continue;
				}

				bool bContinue = false;

				for(int x = 0; x < MAX_STYLES; x++)
				{
					if(j == gI_ReplayBotClient[x])
					{
						bContinue = true;

						break;
					}
				}

				if(bContinue)
				{
					continue;
				}

				gI_ReplayBotClient[i] = j;
			}
		}

		if(!IsValidClient(gI_ReplayBotClient[i]))
		{
			continue;
		}

		if(gSG_Type == Game_CSGO)
		{
			CS_SetClientContributionScore(gI_ReplayBotClient[i], 2000);
		}

		CS_SetClientClanTag(gI_ReplayBotClient[i], "REPLAY");

		char[] sName = new char[MAX_NAME_LENGTH];
		GetClientName(gI_ReplayBotClient[i], sName, MAX_NAME_LENGTH);

		float fWRTime;
		Shavit_GetWRTime(view_as<BhopStyle>(i), fWRTime);

		if(gI_FrameCount[i] == 0 || fWRTime == 0.0)
		{
			if(IsPlayerAlive(gI_ReplayBotClient[i]))
			{
				ForcePlayerSuicide(gI_ReplayBotClient[i]);
			}

			char[] sCurrentName = new char[MAX_NAME_LENGTH];
			strcopy(sCurrentName, MAX_NAME_LENGTH, sName);

			FormatEx(sName, MAX_NAME_LENGTH, "[%s] unloaded", gS_ShortBhopStyles[i]);

			if(!StrEqual(sName, sCurrentName))
			{
				SetClientName(gI_ReplayBotClient[i], sName);
			}
		}

		else
		{
			if(!IsPlayerAlive(gI_ReplayBotClient[i]))
			{
				CS_RespawnPlayer(gI_ReplayBotClient[i]);
			}

			if(GetPlayerWeaponSlot(gI_ReplayBotClient[i], CS_SLOT_KNIFE) == -1)
			{
				GivePlayerItem(gI_ReplayBotClient[i], "weapon_knife");
			}

			char[] sNewName = new char[MAX_NAME_LENGTH];
			FormatEx(sNewName, MAX_NAME_LENGTH, "[%s] %s", gS_ShortBhopStyles[i], gS_BotName[i]);

			if(!StrEqual(gS_BotName[i], sNewName))
			{
				SetClientName(gI_ReplayBotClient[i], sNewName);
			}
		}
	}

	// clear player cache if time is worse than wr
	// might cause issues if WR time is removed and someone else gets a new WR
	float[] fWRTimes = new float[MAX_STYLES];

	for(int i = 0; i < MAX_STYLES; i++)
	{
		Shavit_GetWRTime(view_as<BhopStyle>(i), fWRTimes[i]);
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(gI_PlayerFrames[i] == 0 || !IsValidClient(i, true))
		{
			continue;
		}

		BhopStyle style = Shavit_GetBhopStyle(i);

		if(!ReplayEnabled(style) || Shavit_GetClientTime(i) >  fWRTimes[style])
		{
			ClearFrames(i);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// trigger_once | trigger_multiple.. etc
	// func_door | func_door_rotating
	if(StrContains(classname, "trigger_") != -1 || StrContains(classname, "_door") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, HookTriggers);
		SDKHook(entity, SDKHook_EndTouch, HookTriggers);
		SDKHook(entity, SDKHook_Touch, HookTriggers);
	}
}

public Action HookTriggers(int entity, int other)
{
	if(IsValidClient(other) && IsFakeClient(other))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 256);
	GetMapDisplayName(gS_Map, gS_Map, 256);

	char[] sTempMap = new char[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", gS_Map);

	if(!FileExists(sTempMap))
	{
		if(!FileExists("maps/base.nav"))
		{
			SetFailState("Plugin startup FAILED: \"maps/base.nav\" does not exist.");
		}

		File_Copy("maps/base.nav", sTempMap);

		ForceChangeLevel(gS_Map, ".nav file generate");

		return;
	}

	ConVar bot_stop = FindConVar("bot_stop");
	bot_stop.SetBool(true);

	ConVar bot_controllable = FindConVar("bot_controllable");

	if(bot_controllable != null)
	{
		bot_controllable.SetBool(false);
	}

	ConVar bot_quota_mode = FindConVar("bot_quota_mode");
	bot_quota_mode.SetString("normal");

	ConVar mp_autoteambalance = FindConVar("mp_autoteambalance");
	mp_autoteambalance.SetBool(false);

	ConVar mp_limitteams = FindConVar("mp_limitteams");
	mp_limitteams.SetInt(0);

	ServerCommand("bot_kick");

	gI_ExpectedBots = 0;

	ConVar bot_join_after_player = FindConVar("bot_join_after_player");
	bot_join_after_player.SetBool(false);

	ConVar bot_chatter = FindConVar("bot_chatter");
	bot_chatter.SetString("off");

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot");

	if(!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}

	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		gI_ExpectedBots++;
		gI_ReplayTick[i] = 0;
		gI_FrameCount[i] = 0;
		gA_Frames[i] = new ArrayList(5);

		BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d", i);

		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}

		if(!LoadReplay(view_as<BhopStyle>(i)))
		{
			FormatEx(gS_BotName[i], MAX_NAME_LENGTH, "[%s] unloaded", gS_ShortBhopStyles[i]);
			gI_ReplayTick[i] = -1;
		}

		else
		{
			gRS_ReplayStatus[i] = Replay_Running;
		}
	}
}

public bool LoadReplay(BhopStyle style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(FileExists(sPath))
	{
		File fFile = OpenFile(sPath, "r");

		fFile.ReadLine(gS_BotName[style], MAX_NAME_LENGTH);
		TrimString(gS_BotName[style]);

		char[] sLine = new char[320];
		char[][] sExplodedLine = new char[5][64];

		fFile.ReadLine(sLine, 320);

		int iSize = 0;

		while(!fFile.EndOfFile())
		{
			fFile.ReadLine(sLine, 320);
			ExplodeString(sLine, "|", sExplodedLine, 5, 64);

			gA_Frames[style].Resize(++iSize);

			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[0]), 0);
			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[1]), 1);
			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[2]), 2);

			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[3]), 3);
			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[4]), 4);
		}

		gI_FrameCount[style] = gA_Frames[style].Length;

		delete fFile;

		return true;
	}

	return false;
}

public bool SaveReplay(BhopStyle style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	File fFile = OpenFile(sPath, "w");
	fFile.WriteLine(gS_BotName[style]);

	int iSize = gA_Frames[style].Length;

	char[] sBuffer = new char[320];

	for(int i = 0; i < iSize; i++)
	{
		FormatEx(sBuffer, 320, "%f|%f|%f|%f|%f", gA_Frames[style].Get(i, 0), gA_Frames[style].Get(i, 1), gA_Frames[style].Get(i, 2), gA_Frames[style].Get(i, 3), gA_Frames[style].Get(i, 4));

		fFile.WriteLine(sBuffer);
	}

	delete fFile;

	gI_FrameCount[style] = iSize;

	return true;
}

public bool DeleteReplay(BhopStyle style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(!FileExists(sPath) || !DeleteFile(sPath))
	{
		return false;
	}

	gA_Frames[style].Clear();
	gI_FrameCount[style] = 0;
	gI_ReplayTick[style] = -1;

	CreateTimer(gCV_ReplayDelay.FloatValue / 2, EndReplay, style, TIMER_FLAG_NO_MAPCHANGE);

	return true;
}

public void OnClientPutInServer(int client)
{
	if(!IsClientConnected(client))
	{
		return;
	}

	gA_PlayerFrames[client] = new ArrayList(5);
}

public void OnClientDisconnect(int client)
{
	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(client == gI_ReplayBotClient[i])
		{
			gI_ReplayBotClient[i] = 0;

			break;
		}
	}
}

public void Shavit_OnStart(int client)
{
	if(!IsFakeClient(client))
	{
		ClearFrames(client);

		gB_Record[client] = true;
	}
}

public void Shavit_OnStop(int client)
{
	ClearFrames(client);
}

public void Shavit_OnFinish(int client, BhopStyle style, float time)
{
	float fWRTime = 0.0;
	Shavit_GetWRTime(style, fWRTime);

	if(time > fWRTime || !ReplayEnabled(style))
	{
		ClearFrames(client);
	}

	gB_Record[client] = false;
}

public void Shavit_OnWorldRecord(int client, BhopStyle style, float time)
{
	if(!ReplayEnabled(style) || gI_PlayerFrames[client] == 0)
	{
		return;
	}

	gA_Frames[style] = gA_PlayerFrames[client].Clone();

	char[] sWRTime = new char[16];
	FormatSeconds(time, sWRTime, 16);

	FormatEx(gS_BotName[style], MAX_NAME_LENGTH, "%s - %N", sWRTime, client);

	if(gI_ReplayBotClient[style] != 0)
	{
		char[] sNewName = new char[MAX_NAME_LENGTH];
		FormatEx(sNewName, MAX_NAME_LENGTH, "[%s] %s", gS_ShortBhopStyles[style], gS_BotName[style]);

		SetClientName(gI_ReplayBotClient[style], sNewName);
	}

	ClearFrames(client);

	gRS_ReplayStatus[style] = Replay_Running;
	gI_ReplayTick[style] = gA_PlayerFrames[client].Length;

	SaveReplay(style);
}

public void Shavit_OnPause(int client)
{
	gB_Record[client] = false;
}

public void Shavit_OnResume(int client)
{
	gB_Record[client] = true;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if(!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	float vecCurrentPosition[3];
	GetClientAbsOrigin(client, vecCurrentPosition);

	int iReplayBotStyle = -1;

	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(client == gI_ReplayBotClient[i])
		{
			iReplayBotStyle = i;

			break;
		}
	}

	if(iReplayBotStyle != -1 && ReplayEnabled(iReplayBotStyle))
	{
		if(gA_Frames[iReplayBotStyle] == null) // if no replay is loaded
		{
			return Plugin_Continue;
		}

		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);

		float fWRTime = 0.0;
		Shavit_GetWRTime(view_as<BhopStyle>(iReplayBotStyle), fWRTime);

		if(fWRTime != 0.0 && gI_ReplayTick[iReplayBotStyle] != -1)
		{
			int iSize = gI_FrameCount[iReplayBotStyle];

			float vecPosition[3];
			float vecAngles[3];

			if(gRS_ReplayStatus[iReplayBotStyle] != Replay_Running)
			{
				if(gRS_ReplayStatus[iReplayBotStyle] == Replay_Start)
				{
					vecPosition[0] = gA_Frames[iReplayBotStyle].Get(0, 0);
					vecPosition[1] = gA_Frames[iReplayBotStyle].Get(0, 1);
					vecPosition[2] = gA_Frames[iReplayBotStyle].Get(0, 2);

					vecAngles[0] = gA_Frames[iReplayBotStyle].Get(0, 3);
					vecAngles[1] = gA_Frames[iReplayBotStyle].Get(0, 4);
				}

				else
				{
					vecPosition[0] = gA_Frames[iReplayBotStyle].Get(iSize - 1, 0);
					vecPosition[1] = gA_Frames[iReplayBotStyle].Get(iSize - 1, 1);
					vecPosition[2] = gA_Frames[iReplayBotStyle].Get(iSize - 1, 2);

					vecAngles[0] = gA_Frames[iReplayBotStyle].Get(iSize - 1, 3);
					vecAngles[1] = gA_Frames[iReplayBotStyle].Get(iSize - 1, 4);
				}

				TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));

				return Plugin_Continue;
			}

			if(gI_ReplayTick[iReplayBotStyle] >= iSize)
			{
				gI_ReplayTick[iReplayBotStyle] = 0;
				gRS_ReplayStatus[iReplayBotStyle] = Replay_End;

				CreateTimer(gCV_ReplayDelay.FloatValue / 2, EndReplay, iReplayBotStyle, TIMER_FLAG_NO_MAPCHANGE);

				return Plugin_Continue;
			}

			if(gI_ReplayTick[iReplayBotStyle] == 1)
			{
				gF_StartTick[iReplayBotStyle] = GetEngineTime();
			}

			vecPosition[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 0);
			vecPosition[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 1);
			vecPosition[2] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 2);

			vecAngles[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 3);
			vecAngles[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 4);

			gI_ReplayTick[iReplayBotStyle]++;

			float vecVelocity[3];
			float fDistance = 0.0;

			if(gI_FrameCount[iReplayBotStyle] >= gI_ReplayTick[iReplayBotStyle] + 1)
			{
				float vecNextPosition[3];
				vecNextPosition[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 0);
				vecNextPosition[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 1);
				vecNextPosition[2] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 2);

				fDistance = GetVectorDistance(vecCurrentPosition, vecNextPosition);
				MakeVectorFromPoints(vecPosition, vecNextPosition, vecVelocity);
				ScaleVector(vecVelocity, gF_Tickrate);
			}

			TeleportEntity(client, fDistance >= 50.0? vecPosition:NULL_VECTOR, vecAngles, vecVelocity);
		}
	}

	else if(gB_Record[client] && !Shavit_InsideZone(client, Zone_Start) && ReplayEnabled(Shavit_GetBhopStyle(client)))
	{
		gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + 1);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[0], 0);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[1], 1);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[2], 2);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], angles[0], 3);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], angles[1], 4);

		gI_PlayerFrames[client]++;
	}

	return Plugin_Continue;
}

public Action EndReplay(Handle Timer, any data)
{
	gI_ReplayTick[data] = 0;
	gRS_ReplayStatus[data] = Replay_Start;

	CreateTimer(gCV_ReplayDelay.FloatValue / 2, StartReplay, data, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
}

public Action StartReplay(Handle Timer, any data)
{
	if(gRS_ReplayStatus[data] == Replay_Running)
	{
		return Plugin_Stop;
	}

	gRS_ReplayStatus[data] = Replay_Running;

	return Plugin_Stop;
}

public bool ReplayEnabled(any style)
{
	if(gI_StyleProperties[style] & STYLE_UNRANKED || gI_StyleProperties[style] & STYLE_NOREPLAY)
	{
		return false;
	}

	return true;
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if(IsValidClient(client))
	{
		ClearFrames(client);
	}
}

public void ClearFrames(int client)
{
	gA_PlayerFrames[client].Clear();
	gI_PlayerFrames[client] = 0;
}

public void Shavit_OnWRDeleted(BhopStyle style)
{
	DeleteReplay(style);
}

public Action Command_DeleteReplay(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu m = new Menu(DeleteReplay_Callback);
	m.SetTitle("Delete a replay:");

	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(!ReplayEnabled(i) || gI_FrameCount[i] == 0)
		{
			continue;
		}

		char[] sInfo = new char[4];
		IntToString(i, sInfo, 4);

		m.AddItem(sInfo, gS_BhopStyles[i]);
	}

	if(m.ItemCount == 0)
	{
		m.AddItem("-1", "No replays available.");
	}

	m.ExitButton = true;
	m.Display(client, 20);

	return Plugin_Handled;
}

public int DeleteReplay_Callback(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[4];
		m.GetItem(param2, sInfo, 4);
		BhopStyle style = view_as<BhopStyle>(StringToInt(sInfo));

		if(style == view_as<BhopStyle>(-1))
		{
			return 0;
		}

		Menu submenu = new Menu(DeleteConfirmation_Callback);
		submenu.SetTitle("Confirm deletion of %s replay?", gS_BhopStyles[style]);

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			submenu.AddItem("-1", "NO");
		}

		submenu.AddItem(sInfo, "Yes, I understand this action cannot be reversed!");

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			submenu.AddItem("-1", "NO");
		}

		submenu.ExitButton = true;
		submenu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public int DeleteConfirmation_Callback(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[4];
		m.GetItem(param2, sInfo, 4);
		BhopStyle style = view_as<BhopStyle>(StringToInt(sInfo));

		if(DeleteReplay(style))
		{
			LogAction(param1, param1, "Deleted replay for %s on map %s.", gS_BhopStyles[style], gS_Map);

			Shavit_PrintToChat(param1, "Deleted replay for \x05%s\x01.", gS_BhopStyles[style]);
		}

		else
		{
			Shavit_PrintToChat(param1, "Could not delete replay for \x05%s\x01.", gS_BhopStyles[style]);
		}
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

/*
 * Copies file source to destination
 * Based on code of javalia:
 * http://forums.alliedmods.net/showthread.php?t=159895
 *
 * @param source		Input file
 * @param destination	Output file
 */
stock bool File_Copy(const char[] source, const char[] destination)
{
	File file_source = OpenFile(source, "rb");

	if(file_source == null)
	{
		return false;
	}

	File file_destination = OpenFile(destination, "wb");

	if(file_destination == null)
	{
		delete file_source;

		return false;
	}

	int[] buffer = new int[32];
	int cache = 0;

	while(!IsEndOfFile(file_source))
	{
		cache = ReadFile(file_source, buffer, 32, 1);

		WriteFile(file_destination, buffer, cache, 1);
	}

	delete file_source;
	delete file_destination;

	return true;
}

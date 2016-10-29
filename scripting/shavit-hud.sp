/*
 * shavit's Timer - HUD
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
#include <clientprefs>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <bhopstats>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

#define HUD_NONE				(0)
#define HUD_MASTER				(1 << 0) // master setting
#define HUD_CENTER				(1 << 1) // show hud as hint text
#define HUD_ZONEHUD				(1 << 2) // show start/end zone hud
#define HUD_OBSERVE				(1 << 3) // show the HUD of the player you spectate
#define HUD_SPECTATORS			(1 << 4) // show list of spectators
#define HUD_KEYOVERLAY			(1 << 5) // show a key overlay
#define HUD_HIDEWEAPON			(1 << 6) // hide the player's weapon
#define HUD_TOPLEFT				(1 << 7) // show top left white HUD with WR/PB times (css only)
#define HUD_SYNC				(1 << 8) // shows sync at right side of the screen (css only)
#define HUD_TIMELEFT			(1 << 9) // shows time left at right tside of the screen (css only)
#define HUD_2DVEL				(1 << 10) // shows 2d velocity

#define HUD_DEFAULT				(HUD_MASTER|HUD_CENTER|HUD_ZONEHUD|HUD_OBSERVE|HUD_TOPLEFT|HUD_SYNC|HUD_TIMELEFT)

// game type (CS:S/CS:GO)
EngineVersion gEV_Type = Engine_Unknown;

// modules
bool gB_Replay = false;
bool gB_Zones = false;
bool gB_BhopStats = false;

// zone colors
char gS_StartColors[][] =
{
	"ff0000", "ff4000", "ff7f00", "ffbf00", "ffff00", "00ff00", "00ff80", "00ffff", "0080ff", "0000ff"
};

char gS_EndColors[][] =
{
	"ff0000", "ff4000", "ff7f00", "ffaa00", "ffd400", "ffff00", "bba24e", "77449c"
};

// cache
int gI_Cycle = 0;

Handle gH_HUDCookie = null;
int gI_HUDSettings[MAXPLAYERS+1];
int gI_NameLength = MAX_NAME_LENGTH;
int gI_LastScrollCount[MAXPLAYERS+1];
int gI_ScrollCount[MAXPLAYERS+1];

bool gB_Late = false;

// css hud
Handle gH_HUD = null;

// timer settings
int gI_Styles = 0;
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

public Plugin myinfo =
{
	name = "[shavit] HUD",
	author = "shavit",
	description = "HUD for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// natives
	CreateNative("Shavit_ForceHUDUpdate", Native_ForceHUDUpdate);

	RegPluginLibrary("shavit-hud");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// game-specific
	gEV_Type = GetEngineVersion();

	if(gEV_Type == Engine_CSS)
	{
		gH_HUD = CreateHudSynchronizer();
		gI_NameLength = MAX_NAME_LENGTH;
	}

	else
	{
		gI_NameLength = 14; // 14 because long names will make it look spammy in CS:GO due to the font
	}

	// prevent errors in case the replay bot isn't loaded
	gB_Replay = LibraryExists("shavit-replay");
	gB_Zones = LibraryExists("shavit-zones");
	gB_BhopStats = LibraryExists("bhopstats");

	// cron
	CreateTimer(0.10, UpdateHUD_Timer, INVALID_HANDLE, TIMER_REPEAT);

	// commands
	RegConsoleCmd("sm_hud", Command_HUD, "Opens the HUD settings menu");

	// cookies
	gH_HUDCookie = RegClientCookie("shavit_hud_setting", "HUD settings", CookieAccess_Protected);

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i) && AreClientCookiesCached(i))
			{
				OnClientCookiesCached(i);
			}
		}
	}
}

public void OnMapStart()
{
	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(view_as<BhopStyle>(i), gA_StyleSettings[i]);
		Shavit_GetStyleStrings(view_as<BhopStyle>(i), sStyleName, gS_StyleStrings[i][sStyleName], 128);
		Shavit_GetStyleStrings(view_as<BhopStyle>(i), sHTMLColor, gS_StyleStrings[i][sHTMLColor], 128);
	}

	gI_Styles = styles;
}

public void OnClientPutInServer(int client)
{
	gI_LastScrollCount[client] = 0;
	gI_ScrollCount[client] = 0;
}

public void OnClientCookiesCached(int client)
{
	char[] sHUDSettings = new char[8];
	GetClientCookie(client, gH_HUDCookie, sHUDSettings, 8);

	if(strlen(sHUDSettings) == 0)
	{
		IntToString(HUD_DEFAULT, sHUDSettings, 8);

		SetClientCookie(client, gH_HUDCookie, sHUDSettings);
		gI_HUDSettings[client] = HUD_DEFAULT;
	}

	else
	{
		gI_HUDSettings[client] = StringToInt(sHUDSettings);
	}
}

public Action Command_HUD(int client, int args)
{
	return ShowHUDMenu(client, 0);
}

Action ShowHUDMenu(int client, int item)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu m = new Menu(MenuHandler_HUD, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	m.SetTitle("HUD settings:");

	char[] sInfo = new char[16];
	IntToString(HUD_MASTER, sInfo, 16);
	m.AddItem(sInfo, "Master");

	IntToString(HUD_CENTER, sInfo, 16);
	m.AddItem(sInfo, "Center text");

	IntToString(HUD_ZONEHUD, sInfo, 16);
	m.AddItem(sInfo, "Zone HUD");

	IntToString(HUD_OBSERVE, sInfo, 16);
	m.AddItem(sInfo, "Show the HUD of the player you spectate");

	IntToString(HUD_SPECTATORS, sInfo, 16);
	m.AddItem(sInfo, "Spectator list");

	IntToString(HUD_KEYOVERLAY, sInfo, 16);
	m.AddItem(sInfo, "Key overlay");

	IntToString(HUD_HIDEWEAPON, sInfo, 16);
	m.AddItem(sInfo, "Hide weapons");

	if(gEV_Type == Engine_CSS)
	{
		IntToString(HUD_TOPLEFT, sInfo, 16);
		m.AddItem(sInfo, "Top left HUD (WR/PB)");

		IntToString(HUD_SYNC, sInfo, 16);
		m.AddItem(sInfo, "Sync");

		IntToString(HUD_TIMELEFT, sInfo, 16);
		m.AddItem(sInfo, "Time left");
	}

	IntToString(HUD_2DVEL, sInfo, 16);
	m.AddItem(sInfo, "Use 2D velocity");

	m.ExitButton = true;
	m.DisplayAt(client, item, 60);

	return Plugin_Handled;
}

public int MenuHandler_HUD(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sCookie = new char[16];
		m.GetItem(param2, sCookie, 16);
		int iSelection = StringToInt(sCookie);

		gI_HUDSettings[param1] ^= iSelection;
		IntToString(gI_HUDSettings[param1], sCookie, 16); // string recycling Kappa

		SetClientCookie(param1, gH_HUDCookie, sCookie);

		ShowHUDMenu(param1, GetMenuSelectionPosition());
	}

	else if(action == MenuAction_DisplayItem)
	{
		char[] sInfo = new char[16];
		char[] sDisplay = new char[64];
		int style = 0;
		m.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		Format(sDisplay, 64, "[%s] %s", ((gI_HUDSettings[param1] & StringToInt(sInfo)) > 0)? "x":" ", sDisplay);

		return RedrawMenuItem(sDisplay);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = true;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}

	else if(StrEqual(name, "bhopstats"))
	{
		gB_BhopStats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}

	else if(StrEqual(name, "bhopstats"))
	{
		gB_BhopStats = false;
	}
}

public void OnConfigsExecuted()
{
	ConVar sv_hudhint_sound = FindConVar("sv_hudhint_sound");

	if(sv_hudhint_sound != null)
	{
		sv_hudhint_sound.SetBool(false);
	}
}

public Action UpdateHUD_Timer(Handle Timer)
{
	if(++gI_Cycle >= 65535)
	{
		gI_Cycle = 0;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || (gI_HUDSettings[i] & HUD_MASTER) == 0)
		{
			continue;
		}

		TriggerHUDUpdate(i);
	}

	return Plugin_Continue;
}

void TriggerHUDUpdate(int client)
{
	UpdateHUD(client);
	SetEntProp(client, Prop_Data, "m_bDrawViewmodel", ((gI_HUDSettings[client] & HUD_HIDEWEAPON) > 0)? 0:1);

	if(gEV_Type == Engine_CSS)
	{
		UpdateTopLeftHUD(client, true);
		UpdateKeyHint(client);
		UpdateCenterKeys(client);
	}

	else if(((gI_HUDSettings[client] & HUD_KEYOVERLAY) > 0 || (gI_HUDSettings[client] & HUD_SPECTATORS) > 0) && (!gB_Zones || !Shavit_IsClientCreatingZone(client)) && (GetClientMenu(client, null) == MenuSource_None || GetClientMenu(client, null) == MenuSource_RawPanel))
	{
		bool bShouldDraw = false;
		Panel pHUD = new Panel();

		UpdateKeyOverlay(client, pHUD, bShouldDraw);
		pHUD.DrawItem("", ITEMDRAW_RAWLINE);

		UpdateSpectatorList(client, pHUD, bShouldDraw);

		if(bShouldDraw)
		{
			pHUD.Send(client, PanelHandler_Nothing, 1);
		}

		delete pHUD;
	}
}

void UpdateHUD(int client)
{
	int target = GetHUDTarget(client);

	if((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target)
	{
		return;
	}

	float fSpeed[3];
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

	int iSpeed = RoundToFloor(((gI_HUDSettings[client] & HUD_2DVEL) == 0)? GetVectorLength(fSpeed):(SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0))));

	char[] sHintText = new char[512];
	strcopy(sHintText, 512, "");

	if((gI_HUDSettings[client] & HUD_ZONEHUD) > 0)
	{
		if(Shavit_InsideZone(target, Zone_Start))
		{
			if(gEV_Type == Engine_CSGO)
			{
				FormatEx(sHintText, 64, "<font size=\"45\" color=\"#%s\">Start Zone</font>", gS_StartColors[gI_Cycle % sizeof(gS_StartColors)]);
			}

			else
			{
				FormatEx(sHintText, 32, "In Start Zone\n\n%d", iSpeed);
			}
		}

		else if(Shavit_InsideZone(target, Zone_End))
		{
			if(gEV_Type == Engine_CSGO)
			{
				FormatEx(sHintText, 64, "<font size=\"45\" color=\"#%s\">End Zone</font>", gS_EndColors[gI_Cycle % sizeof(gS_EndColors)]);
			}

			else
			{
				FormatEx(sHintText, 32, "In End Zone\n\n%d", iSpeed);
			}
		}
	}

	if(strlen(sHintText) > 0)
	{
		PrintHintText(client, sHintText);
	}

	else if((gI_HUDSettings[client] & HUD_CENTER) > 0)
	{
		if(!IsFakeClient(target))
		{
			float fTime = Shavit_GetClientTime(target);
			int iJumps = Shavit_GetClientJumps(target);
			BhopStyle bsStyle = Shavit_GetBhopStyle(target);
			TimerStatus tStatus = Shavit_GetTimerStatus(target);
			int iStrafes = Shavit_GetStrafeCount(target);
			int iPotentialRank = Shavit_GetRankForTime(bsStyle, fTime);

			float fWR = 0.0;
			Shavit_GetWRTime(bsStyle, fWR);

			float fPB = 0.0;
			Shavit_GetPlayerPB(target, bsStyle, fPB);

			char[] sPB = new char[32];
			FormatSeconds(fPB, sPB, 32);

			char[] sTime = new char[32];
			FormatSeconds(fTime, sTime, 32, false);

			if(gEV_Type == Engine_CSGO)
			{
				strcopy(sHintText, 512, "<font size=\"18\" face=\"Stratum2\">");

				if(tStatus >= Timer_Running)
				{
					char[] sColor = new char[8];

					if(fTime < fWR || fWR == 0.0)
					{
						strcopy(sColor, 8, "00FF00");
					}

					else if(fPB != 0.0 && fTime < fPB)
					{
						strcopy(sColor, 8, "FFA500");
					}

					else
					{
						strcopy(sColor, 8, "FF0000");
					}

					Format(sHintText, 512, "%sTime: <font color='#%s'>%s</font> (%d)", sHintText, (tStatus == Timer_Paused)? "FF0000":sColor, (tStatus == Timer_Paused)? "[PAUSED]\t":sTime, iPotentialRank);
				}

				if(fPB > 0.0)
				{
					Format(sHintText, 512, "%s%sBest: %s (#%d)", sHintText, (tStatus >= Timer_Running)? "\t":"", sPB, (oGetRankForTime(bsStyle, fPB) - 1));
				}

				if(tStatus >= Timer_Running)
				{
					Format(sHintText, 512, "%s\nJumps: %d%s\tStyle: <font color='#%s'>%s</font>", sHintText, iJumps, (iJumps < 1000)? "\t":"", gS_StyleStrings[bsStyle][sHTMLColor], gS_StyleStrings[bsStyle][sStyleName]);
				}

				else
				{
					Format(sHintText, 512, "%s\nStyle: <font color='#%s'>%s</font>", sHintText, gS_StyleStrings[bsStyle][sHTMLColor], gS_StyleStrings[bsStyle][sStyleName]);
				}

				Format(sHintText, 512, "%s\nSpeed: %d", sHintText, iSpeed);

				if(tStatus >= Timer_Running)
				{
					if(gA_StyleSettings[bsStyle][bSync])
					{
						Format(sHintText, 512, "%s%s\tStrafes: %d (%.02f%%)", sHintText, (iSpeed < 1000)? "\t":"", iStrafes, Shavit_GetSync(target));
					}

					else
					{
						Format(sHintText, 512, "%s%s\tStrafes: %d", sHintText, (iSpeed < 1000)? "\t":"", iStrafes);
					}
				}

				Format(sHintText, 512, "%s</font>", sHintText);
			}

			else
			{
				if(tStatus != Timer_Stopped)
				{
					if(Shavit_GetTimerStatus(target) == Timer_Running)
					{
						FormatEx(sHintText, 512, "%s\nTime: %s (%d)\nJumps: %d\nStrafes: %d\nSpeed: %d%s", gS_StyleStrings[bsStyle][sStyleName], sTime, iPotentialRank, iJumps, iStrafes, iSpeed, (gA_StyleSettings[bsStyle][fVelocityLimit] > 0.0 && Shavit_InsideZone(target, Zone_NoVelLimit))? "\nNo Speed Limit":"");
					}

					else
					{
						strcopy(sHintText, 16, "[PAUSED]");
					}
				}

				else
				{
					IntToString(iSpeed, sHintText, 8);
				}
			}

			PrintHintText(client, "%s", sHintText);
		}

		else if(gB_Replay)
		{
			BhopStyle bsStyle = view_as<BhopStyle>(0);

			for(int i = 0; i < gI_Styles; i++)
			{
				if(Shavit_GetReplayBotIndex(view_as<BhopStyle>(i)) == target)
				{
					bsStyle = view_as<BhopStyle>(i);

					break;
				}
			}

			float fStart = 0.0;
			Shavit_GetReplayBotFirstFrame(bsStyle, fStart);

			float fTime = GetEngineTime() - fStart;

			float fWR = 0.0;
			Shavit_GetWRTime(bsStyle, fWR);

			if(fTime > fWR || !Shavit_IsReplayDataLoaded(bsStyle))
			{
				PrintHintText(client, "No replay data loaded");

				return;
			}

			char[] sTime = new char[32];
			FormatSeconds(fTime, sTime, 32, false);

			char[] sWR = new char[32];
			FormatSeconds(fWR, sWR, 32, false);

			if(gEV_Type == Engine_CSGO)
			{
				FormatEx(sHintText, 512, "<font face='Stratum2'>");
				Format(sHintText, 512, "%s\t<u><font color='#%s'>%s Replay</font></u>", sHintText, gS_StyleStrings[bsStyle][sHTMLColor], gS_StyleStrings[bsStyle][sStyleName]);
				Format(sHintText, 512, "%s\n\tTime: <font color='#00FF00'>%s</font> / %s", sHintText, sTime, sWR);
				Format(sHintText, 512, "%s\n\tSpeed: %d", sHintText, iSpeed);
				Format(sHintText, 512, "%s</font>", sHintText);
			}

			else
			{
				FormatEx(sHintText, 512, "%s Replay", gS_StyleStrings[bsStyle][sStyleName], sHintText);
				Format(sHintText, 512, "%s\nTime: %s/%s", sHintText, sTime, sWR);
				Format(sHintText, 512, "%s\nSpeed: %d", sHintText, iSpeed);
			}

			PrintHintText(client, "%s", sHintText);
		}
	}
}

void UpdateKeyOverlay(int client, Panel panel, bool &draw)
{
	if((gI_HUDSettings[client] & HUD_KEYOVERLAY) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target) || IsClientObserver(target))
	{
		return;
	}

	int buttons = GetClientButtons(target);

	// that's a very ugly way, whatever :(
	char[] sPanelLine = new char[128];

	if(gA_StyleSettings[Shavit_GetBhopStyle(target)][bAutobhop]) // don't include [JUMP] for autobhop styles
	{
		FormatEx(sPanelLine, 128, "[%s]\n    %s\n%s   %s   %s", (buttons & IN_DUCK) > 0? "DUCK":"----", (buttons & IN_FORWARD) > 0? "W":"-", (buttons & IN_MOVELEFT) > 0? "A":"-", (buttons & IN_BACK) > 0? "S":"-", (buttons & IN_MOVERIGHT) > 0? "D":"-");
	}

	else
	{
		FormatEx(sPanelLine, 128, "[%s] [%s]\n    %s\n%s   %s   %s", (buttons & IN_JUMP) > 0? "JUMP":"----", (buttons & IN_DUCK) > 0? "DUCK":"----", (buttons & IN_FORWARD) > 0? "W":"-", (buttons & IN_MOVELEFT) > 0? "A":"-", (buttons & IN_BACK) > 0? "S":"-", (buttons & IN_MOVERIGHT) > 0? "D":"-");
	}

	panel.DrawItem(sPanelLine, ITEMDRAW_RAWLINE);

	draw = true;
}

public void Bunnyhop_OnTouchGround(int client)
{
	gI_LastScrollCount[client] = BunnyhopStats.GetScrollCount(client);
}

public void Bunnyhop_OnJumpPressed(int client)
{
	gI_ScrollCount[client] = BunnyhopStats.GetScrollCount(client);

	if(gA_StyleSettings[Shavit_GetBhopStyle(client)][bAutobhop] || gEV_Type != Engine_CSS)
	{
		return;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || (IsValidClient(i) && GetHUDTarget(i) == client))
		{
			UpdateCenterKeys(i);
		}
	}
}

void UpdateCenterKeys(int client)
{
	if((gI_HUDSettings[client] & HUD_KEYOVERLAY) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target) || IsClientObserver(target))
	{
		return;
	}

	int buttons = GetClientButtons(target);

	char[] sCenterText = new char[64];
	FormatEx(sCenterText, 64, "%s %s %s\n%s %s %s",
		(buttons & IN_DUCK > 0)? "C":"-", (buttons & IN_FORWARD > 0)? "W":"-", (buttons & IN_JUMP > 0)? "J":"-",
		(buttons & IN_MOVELEFT > 0)? "A":"-", (buttons & IN_BACK > 0)? "S":"-", (buttons & IN_MOVERIGHT > 0)? "D":"-");

	if(gB_BhopStats && !gA_StyleSettings[Shavit_GetBhopStyle(target)][bAutobhop])
	{
		Format(sCenterText, 64, "%s\n%d    %d", sCenterText, gI_ScrollCount[client], gI_LastScrollCount[target]);
	}

	PrintCenterText(client, "%s", sCenterText);
}

void UpdateSpectatorList(int client, Panel panel, bool &draw)
{
	if((gI_HUDSettings[client] & HUD_SPECTATORS) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target))
	{
		return;
	}

	int[] iSpectatorClients = new int[MaxClients];
	int iSpectators = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") != target)
		{
			continue;
		}

		int iObserverMode = GetEntProp(i, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			iSpectatorClients[iSpectators++] = i;
		}
	}

	if(iSpectators > 0)
	{
		char[] sSpectators = new char[32];
		FormatEx(sSpectators, 32, "%spectators (%d):", (client == target)? "S":"Other s", iSpectators);
		panel.DrawItem(sSpectators, ITEMDRAW_RAWLINE);

		for(int i = 0; i < iSpectators; i++)
		{
			if(i == 7)
			{
				panel.DrawItem("...", ITEMDRAW_RAWLINE);

				break;
			}

			char[] sName = new char[gI_NameLength];
			GetClientName(iSpectatorClients[i], sName, gI_NameLength);

			panel.DrawItem(sName, ITEMDRAW_RAWLINE);
		}

		draw = true;
	}
}

void UpdateTopLeftHUD(int client, bool wait)
{
	if((!wait || gI_Cycle % 25 == 0) && (gI_HUDSettings[client] & HUD_TOPLEFT) > 0)
	{
		int target = GetHUDTarget(client);

		BhopStyle style = Shavit_GetBhopStyle(target);

		float fWRTime = 0.0;
		Shavit_GetWRTime(style, fWRTime);

		if(fWRTime != 0.0)
		{
			char[] sWRTime = new char[16];
			FormatSeconds(fWRTime, sWRTime, 16);

			char[] sWRName = new char[MAX_NAME_LENGTH];
			Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH);

			float fPBTime = 0.0;
			Shavit_GetPlayerPB(target, style, fPBTime);

			char[] sPBTime = new char[16];
			FormatSeconds(fPBTime, sPBTime, MAX_NAME_LENGTH);

			char[] sTopLeft = new char[64];

			if(fPBTime != 0.0)
			{
				FormatEx(sTopLeft, 64, "WR: %s (%s)\nBest: %s (#%d)", sWRTime, sWRName, sPBTime, (Shavit_GetRankForTime(style, fPBTime) - 1));
			}

			else
			{
				FormatEx(sTopLeft, 64, "WR: %s (%s)", sWRTime, sWRName);
			}

			SetHudTextParams(0.01, 0.01, 2.5, 255, 255, 255, 255);
			ShowSyncHudText(client, gH_HUD, sTopLeft);
		}
	}
}

void UpdateKeyHint(int client)
{
	if((gI_Cycle % 10) == 0 && ((gI_HUDSettings[client] & HUD_SYNC) > 0 || (gI_HUDSettings[client] & HUD_TIMELEFT) > 0))
	{
		char[] sMessage = new char[256];
		int iTimeLeft = -1;

		if((gI_HUDSettings[client] & HUD_TIMELEFT) > 0 && GetMapTimeLeft(iTimeLeft) && iTimeLeft > 0)
		{
			FormatEx(sMessage, 256, (iTimeLeft > 60)? "Time left: %d minutes":"Time left: <1 minute", (iTimeLeft / 60));
		}

		int target = GetHUDTarget(client);

		if(IsValidClient(target) && (target == client || (gI_HUDSettings[client] & HUD_OBSERVE) > 0))
		{
			if((gI_HUDSettings[client] & HUD_SYNC) > 0 && Shavit_GetTimerStatus(target) == Timer_Running && gA_StyleSettings[Shavit_GetBhopStyle(target)][bSync] && !IsFakeClient(target) && (!gB_Zones || !Shavit_InsideZone(target, Zone_Start)))
			{
				Format(sMessage, 256, "%s%sSync: %.02f", sMessage, (strlen(sMessage) > 0)? "\n\n":"", Shavit_GetSync(target));
			}

			if((gI_HUDSettings[client] & HUD_SPECTATORS) > 0)
			{
				int[] iSpectatorClients = new int[MaxClients];
				int iSpectators = 0;

				for(int i = 1; i <= MaxClients; i++)
				{
					if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") != target)
					{
						continue;
					}

					int iObserverMode = GetEntProp(i, Prop_Send, "m_iObserverMode");

					if(iObserverMode >= 3 && iObserverMode <= 5)
					{
						iSpectatorClients[iSpectators++] = i;
					}
				}

				if(iSpectators > 0)
				{
					Format(sMessage, 256, "%s%s%spectators (%d):", sMessage, (strlen(sMessage) > 0)? "\n\n":"", (client == target)? "S":"Other s", iSpectators);

					for(int i = 0; i < iSpectators; i++)
					{
						if(i == 7)
						{
							Format(sMessage, 256, "%s\n...", sMessage);

							break;
						}

						char[] sName = new char[gI_NameLength];
						GetClientName(iSpectatorClients[i], sName, gI_NameLength);
						Format(sMessage, 256, "%s\n%s", sMessage, sName);
					}
				}
			}
		}

		if(strlen(sMessage) > 0)
		{
			Handle hKeyHintText = StartMessageOne("KeyHintText", client);
			BfWriteByte(hKeyHintText, 1);
			BfWriteString(hKeyHintText, sMessage);
			EndMessage();
		}
	}
}

int GetHUDTarget(int client)
{
	int target = client;

	if(IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(IsValidClient(iTarget, true))
			{
				target = iTarget;
			}
		}
	}

	return target;
}


public int PanelHandler_Nothing(Menu m, MenuAction action, int param1, int param2)
{
	// i don't need anything here
	return 0;
}

public void Shavit_OnStyleChanged(int client)
{
	UpdateTopLeftHUD(client, false);
}

public int Native_ForceHUDUpdate(Handle handler, int numParams)
{
	int[] clients = new int[MaxClients];
	int count = 0;

	int client = GetNativeCell(1);

	if(!IsValidClient(client))
	{
		ThrowNativeError(200, "Invalid client index %d", client);

		return -1;
	}

	clients[count++] = client;

	if(view_as<bool>(GetNativeCell(2)))
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(i == client || !IsValidClient(i) || GetHUDTarget(i) != client)
			{
				continue;
			}

			clients[count++] = client;
		}
	}

	for(int i = 0; i < count; i++)
	{
		TriggerHUDUpdate(clients[i]);
	}

	return count;
}

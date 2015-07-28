[AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=265456)

[Download](https://github.com/Shavitush/bhoptimer/releases)

# shavit's simple bhop timer
a bhop server should be simple

[Mapzones' setup demonstration](https://www.youtube.com/watch?v=oPKso2hoLw0)

# Requirements:
* [SourceMod 1.7 and above](http://www.sourcemod.net/downloads.php)

# Optional requirements:
* [DHooks](http://users.alliedmods.net/~drifter/builds/dhooks/2.0/) - required for static 250 prestrafe (bhoptimer 1.2b and above)

#  Installation:
1. Add a database entry in addons/sourcemod/configs/databases.cfg, call it "shavit"
```
"Databases"
{
	"driver_default"		"mysql"
	
	// When specifying "host", you may use an IP address, a hostname, or a socket file path
	
	"default"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"sourcemod"
		"user"				"root"
		"pass"				""
		//"timeout"			"0"
		//"port"			"0"
	}
	
	"shavit"
	{
		"driver"         "mysql"
		"host"           "localhost"
		"database"       "shavit"
		"user"           "root"
		"pass"           ""
	}
}
```
2. Copy the desired .smx files to your plugins (addons/sourcemod/plugins) folder
2.1. Copy shavit.games.txt to /gamedata if you have DHooks installed.
3. Restart your server.

# Required plugins:
shavit-core - no other plugin will work without it.
shavit-zones - wouldn't really call it required but it's actually needed to get your timer to start/finish.

# Todo for 1.4b release
~ shavit-zones:
- [ ] + Add a submenu that can adjust the zone's Z/X/Y axis before it's being confirmed.

~ [NEW PLUGIN] shavit-stats:
- [ ] + Show maps done (/SW)
- [ ] + Show maps left (/SW)
- [ ] + Show SteamID3

# Todo for 1.5b release
[NEW PLUGIN] shavit-ranks:  
[NEW PLUGIN] shavit-replay:  
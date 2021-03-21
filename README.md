[![Discord server](https://discordapp.com/api/guilds/389675819959844865/widget.png?style=shield)](https://discord.gg/jyA9q5k)

### Build status
[![Build status](https://travis-ci.org/shavitush/bhoptimer.svg?branch=master)](https://travis-ci.org/shavitush/bhoptimer)

[AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=265456)

[Download](https://github.com/shavitush/bhoptimer/releases)

# shavit's bhop timer

This is (nearly) an all-in-one server plugin for Counter-Strike: Source, Counter-Strike: Global Offensive and Team Fortress 2 that adds a timer system and many other utilities, so you can install it and run a proper bunnyhop server.

Includes a records system, map zones (start/end marks etc), bonuses, HUD with useful information, chat processor, miscellaneous such as weapon commands/spawn point generator, bots that replay the best records of the map, sounds, statistics, segmented running, a fair & competitive rankings system and more!

[Mapzones Setup Demonstration](https://youtu.be/OXFMGm40F6c)

# Requirements:
* Steam version of Counter-Strike: Source or Counter-Strike: Global Offensive.
* [SourceMod 1.10 or above](http://www.sourcemod.net/downloads.php?branch=dev)
* A MySQL database (preferably locally hosted) if your database is likely to grow big, or if you want to use the rankings plugin. MySQL server version of 5.5.5 or above (MariaDB equivalent works too) is highly recommended.
* [DHooks](https://github.com/peace-maker/DHooks2/releases)

# Optional requirements, for the best experience:
* [Bunnyhop Statistics](https://forums.alliedmods.net/showthread.php?t=286135)
* [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556)
* [DynamicChannels](https://github.com/Vauff/DynamicChannels)

#  Installation:
Refer to the [wiki page](https://github.com/shavitush/bhoptimer/wiki/1.-Installation-(from-source)).

# Required plugins:
`shavit-core` - completely required.  
`shavit-zones` - completely required.  
`shavit-wr` - required for `shavit-stats`, `shavit-replay`, `shavit-rankings` and `shavit-sounds`.

# Recommened plugins:
* [MomSurfFix](https://github.com/GAMMACASE/MomSurfFix)
	- Makes surf ramps less likely to stop players. (Ramp bug / surf glitch)
* [RNGFix](https://github.com/jason-e/rngfix)
  - Makes slopes, teleporters, and more less random. Replaces `slopefix`
* [eventqueuefix](https://github.com/hermansimensen/eventqueue-fix)
  - Changes how events are sent to players. Makes boosters more consistent. Replaces `boosterfix`
* TODO: `paint`, `mpbhops`, `showtriggers`, `showplayerclips`, `ssj`, `ljstats`, `shavit-mapchooser`, `NoViewPunch`, `bash2`
